[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Verify')]
    [string]$Mode = 'Audit'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$reportDir = Join-Path $repoRoot 'reports\storage-safety-v24'
$reportPath = Join-Path $reportDir 'storage-integrity.json'
$storagePolicyPath = Join-Path $repoRoot 'config\hardware\symbiosis-v5.json'

New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

if (-not (Test-Path -LiteralPath $storagePolicyPath)) {
    throw "Politique stockage introuvable: $storagePolicyPath"
}

$storagePolicy = Get-Content -Raw $storagePolicyPath | ConvertFrom-Json
$targetModelRegex = [string]$storagePolicy.storage.modelRegex
$targetMinimumCount = [int]$storagePolicy.storage.minimumCount
$criticalTemperatureC = [int]$storagePolicy.storage.temperatureCriticalC
$failures = @()

function Get-WpcMsftVolume {
    param([Parameter(Mandatory)][ValidatePattern('^[A-Z]$')][string]$DriveLetter)

    $matches = @(
        Get-CimInstance -Namespace 'root/Microsoft/Windows/Storage' -ClassName MSFT_Volume -ErrorAction Stop |
            Where-Object { [string]$_.DriveLetter -eq $DriveLetter } |
            Select-Object -First 1
    )
    if ($matches.Count -eq 0) {
        throw "MSFT_Volume introuvable pour ${DriveLetter}:"
    }
    return $matches[0]
}

function Get-WpcCorruptionCount {
    param([Parameter(Mandatory)]$Volume)

    $result = Invoke-CimMethod -InputObject $Volume -MethodName GetCorruptionCount -ErrorAction Stop
    if ([uint32]$result.ReturnValue -ne 0) {
        throw "GetCorruptionCount a echoue avec le code $($result.ReturnValue)."
    }
    return [uint32]$result.CorruptionCount
}

function ConvertTo-WpcNullableUInt64 {
    param($Value)

    if ($null -eq $Value) { return $null }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return [uint64]$Value
}

function Invoke-WpcNtfsSafetyCheck {
    param([Parameter(Mandatory)][ValidatePattern('^[A-Z]$')][string]$DriveLetter)

    $drive = "${DriveLetter}:"
    $volume = Get-Volume -DriveLetter $DriveLetter -ErrorAction Stop
    if ([string]$volume.FileSystem -ne 'NTFS') {
        return [pscustomobject]@{
            Drive = $drive
            FileSystem = [string]$volume.FileSystem
            HealthStatus = [string]$volume.HealthStatus
            DirtyBitSet = $null
            ScanReturnCode = $null
            CorruptionCount = $null
            CorruptionJournalExitCode = $null
            CorruptionJournalPath = $null
            Clean = $false
            Failure = "$drive doit etre NTFS."
        }
    }

    $win32Volume = @(
        Get-CimInstance -ClassName Win32_Volume -Filter ("DriveLetter='{0}'" -f $drive) -ErrorAction Stop |
            Select-Object -First 1
    )
    if ($win32Volume.Count -eq 0) {
        throw "Win32_Volume introuvable pour $drive"
    }
    $dirtyBitSet = [bool]$win32Volume[0].DirtyBitSet

    $global:LASTEXITCODE = 0
    $dirtyEvidence = @(& fsutil.exe dirty query $drive 2>&1 | ForEach-Object { [string]$_ })
    $dirtyEvidenceExitCode = [int]$LASTEXITCODE
    $global:LASTEXITCODE = 0
    $dirtyEvidencePath = Join-Path $reportDir "$DriveLetter-dirty-bit.txt"
    $dirtyEvidence | Set-Content -Encoding utf8 $dirtyEvidencePath

    $scanOutput = @(Repair-Volume -DriveLetter ([char]$DriveLetter) -Scan -ErrorAction Stop)
    $scanReturnCode = $null
    if ($scanOutput.Count -gt 0) {
        $scanReturnCode = [uint32]$scanOutput[-1]
    }

    $msftVolume = Get-WpcMsftVolume -DriveLetter $DriveLetter
    $corruptionCount = Get-WpcCorruptionCount -Volume $msftVolume
    $msftHealthStatus = [uint16]$msftVolume.HealthStatus

    $global:LASTEXITCODE = 0
    $journal = @(& fsutil.exe repair enumerate $drive '$Corrupt' 2>&1 | ForEach-Object { [string]$_ })
    $journalExitCode = [int]$LASTEXITCODE
    $global:LASTEXITCODE = 0
    $journalPath = Join-Path $reportDir "$DriveLetter-corrupt-journal.txt"
    $journal | Set-Content -Encoding utf8 $journalPath

    $reasons = @()
    if ($dirtyBitSet) { $reasons += 'dirty-bit NTFS positionne' }
    if ($dirtyEvidenceExitCode -ne 0) { $reasons += "fsutil dirty query code=$dirtyEvidenceExitCode" }
    if ($null -eq $scanReturnCode) { $reasons += 'Repair-Volume -Scan sans code de retour' }
    elseif ($scanReturnCode -ne 0) { $reasons += "Repair-Volume -Scan code=$scanReturnCode" }
    if ($msftHealthStatus -ne 0) { $reasons += "MSFT_Volume HealthStatus=$msftHealthStatus" }
    if ($corruptionCount -gt 0) { $reasons += "CorruptionCount=$corruptionCount" }
    if ($journalExitCode -ne 0) { $reasons += "fsutil repair enumerate code=$journalExitCode" }

    $clean = ($reasons.Count -eq 0)
    $failureText = $null
    if (-not $clean) { $failureText = $reasons -join '; ' }

    return [pscustomobject]@{
        Drive = $drive
        FileSystem = [string]$volume.FileSystem
        HealthStatus = [string]$volume.HealthStatus
        MsftHealthStatus = $msftHealthStatus
        DirtyBitSet = $dirtyBitSet
        DirtyEvidenceExitCode = $dirtyEvidenceExitCode
        DirtyEvidencePath = $dirtyEvidencePath
        ScanReturnCode = $scanReturnCode
        CorruptionCount = $corruptionCount
        CorruptionJournalExitCode = $journalExitCode
        CorruptionJournalPath = $journalPath
        Clean = $clean
        Failure = $failureText
    }
}

function Invoke-WpcNvmeSafetyCheck {
    $nvmeDisks = @(Get-PhysicalDisk -ErrorAction Stop | Where-Object { [string]$_.BusType -eq 'NVMe' })
    if ($nvmeDisks.Count -eq 0) {
        return [pscustomobject]@{
            TargetCount = 0
            TargetMinimumCount = $targetMinimumCount
            Disks = @()
            Clean = $false
            Failure = 'Aucun disque NVMe detecte.'
        }
    }

    $targetDisks = @(
        $nvmeDisks | Where-Object {
            (([string]$_.FriendlyName + ' ' + [string]$_.Model) -match $targetModelRegex)
        }
    )

    $diskStates = @()
    foreach ($disk in $nvmeDisks) {
        $counter = $null
        $counterError = $null
        try {
            $counterRows = @($disk | Get-StorageReliabilityCounter -ErrorAction Stop | Select-Object -First 1)
            if ($counterRows.Count -gt 0) { $counter = $counterRows[0] }
        } catch {
            $counterError = $_.Exception.Message
        }

        $readTotal = $null
        $writeTotal = $null
        $readUncorrected = $null
        $writeUncorrected = $null
        $temperature = $null
        $temperatureMax = $null
        $wear = $null
        $powerOnHours = $null

        if ($null -ne $counter) {
            $readTotal = ConvertTo-WpcNullableUInt64 -Value $counter.ReadErrorsTotal
            $writeTotal = ConvertTo-WpcNullableUInt64 -Value $counter.WriteErrorsTotal
            $readUncorrected = ConvertTo-WpcNullableUInt64 -Value $counter.ReadErrorsUncorrected
            $writeUncorrected = ConvertTo-WpcNullableUInt64 -Value $counter.WriteErrorsUncorrected
            if ($null -ne $counter.Temperature) { $temperature = [int]$counter.Temperature }
            $temperatureMax = $counter.TemperatureMax
            $wear = $counter.Wear
            $powerOnHours = $counter.PowerOnHours
        }

        $reasons = @()
        $warnings = @()
        if ([string]$disk.HealthStatus -ne 'Healthy') { $reasons += "HealthStatus=$($disk.HealthStatus)" }
        if ($null -eq $counter) { $reasons += "Reliability unavailable: $counterError" }
        if ($null -eq $readTotal) { $reasons += 'ReadErrorsTotal unavailable' }
        elseif ($readTotal -gt 0) { $warnings += "ReadErrorsTotal historique=$readTotal" }
        if ($null -eq $writeTotal) { $reasons += 'WriteErrorsTotal unavailable' }
        elseif ($writeTotal -gt 0) { $warnings += "WriteErrorsTotal historique=$writeTotal" }
        if ($null -eq $readUncorrected) { $reasons += 'ReadErrorsUncorrected unavailable' }
        elseif ($readUncorrected -gt 0) { $reasons += "ReadErrorsUncorrected=$readUncorrected" }
        if ($null -eq $writeUncorrected) { $reasons += 'WriteErrorsUncorrected unavailable' }
        elseif ($writeUncorrected -gt 0) { $reasons += "WriteErrorsUncorrected=$writeUncorrected" }
        if ($null -ne $temperature -and $temperature -gt $criticalTemperatureC) {
            $reasons += "Temperature=${temperature}C critical=${criticalTemperatureC}C"
        }

        $diskClean = ($reasons.Count -eq 0)
        $diskFailure = $null
        if (-not $diskClean) { $diskFailure = $reasons -join '; ' }

        $diskStates += [pscustomobject]@{
            FriendlyName = [string]$disk.FriendlyName
            Model = [string]$disk.Model
            SerialNumber = [string]$disk.SerialNumber
            BusType = [string]$disk.BusType
            HealthStatus = [string]$disk.HealthStatus
            OperationalStatus = @($disk.OperationalStatus | ForEach-Object { [string]$_ })
            IsTargetT705 = (([string]$disk.FriendlyName + ' ' + [string]$disk.Model) -match $targetModelRegex)
            ReliabilityAvailable = ($null -ne $counter)
            Temperature = $temperature
            TemperatureMax = $temperatureMax
            Wear = $wear
            PowerOnHours = $powerOnHours
            ReadErrorsTotal = $readTotal
            WriteErrorsTotal = $writeTotal
            ReadErrorsUncorrected = $readUncorrected
            WriteErrorsUncorrected = $writeUncorrected
            Clean = $diskClean
            Failure = $diskFailure
            Warnings = @($warnings)
        }
    }

    $reasonsAll = @()
    if ($targetDisks.Count -lt $targetMinimumCount) {
        $reasonsAll += "T705 count=$($targetDisks.Count), required=$targetMinimumCount"
    }
    foreach ($state in $diskStates) {
        if (-not $state.Clean) {
            $reasonsAll += "$($state.FriendlyName): $($state.Failure)"
        }
    }

    $clean = ($reasonsAll.Count -eq 0)
    $failureText = $null
    if (-not $clean) { $failureText = $reasonsAll -join ' | ' }

    return [pscustomobject]@{
        TargetCount = $targetDisks.Count
        TargetMinimumCount = $targetMinimumCount
        Disks = @($diskStates)
        Clean = $clean
        Failure = $failureText
    }
}

$volumeStates = @()
foreach ($letter in @('C', 'D')) {
    try {
        $state = Invoke-WpcNtfsSafetyCheck -DriveLetter $letter
        $volumeStates += $state
        if (-not $state.Clean) { $failures += "$($state.Drive) $($state.Failure)" }
    } catch {
        $volumeStates += [pscustomobject]@{
            Drive = "${letter}:"
            Clean = $false
            Failure = $_.Exception.Message
        }
        $failures += "${letter}: $($_.Exception.Message)"
    }
}

$nvmeState = $null
try {
    $nvmeState = Invoke-WpcNvmeSafetyCheck
    if (-not $nvmeState.Clean) { $failures += "NVMe: $($nvmeState.Failure)" }
} catch {
    $nvmeState = [pscustomobject]@{
        Clean = $false
        Failure = $_.Exception.Message
        Disks = @()
    }
    $failures += "NVMe: $($_.Exception.Message)"
}

$report = [ordered]@{
    Version = 'V24'
    Timestamp = (Get-Date).ToString('o')
    Mode = $Mode
    NtfsVolumes = @($volumeStates)
    Nvme = $nvmeState
    Clean = ($failures.Count -eq 0)
    Failures = @($failures)
    Policy = [ordered]@{
        RequiredVolumes = @('C:', 'E:')
        DirtyBitMustBeClear = $true
        RepairVolumeScanRequired = $true
        CorruptionCountMustBeZero = $true
        CorruptionJournalCaptured = $true
        NvmeReliabilityRequired = $true
        LifetimeErrorTotalsAreAdvisory = $true
        UncorrectedErrorsMustBeZero = $true
        TargetModelRegex = $targetModelRegex
        TargetMinimumCount = $targetMinimumCount
        CriticalTemperatureC = $criticalTemperatureC
    }
}
$report | ConvertTo-Json -Depth 12 | Set-Content -Encoding utf8 $reportPath

foreach ($state in $volumeStates) {
    if ($state.Clean) {
        Write-Host "[OK] $($state.Drive) NTFS clean: dirty-bit=0, scan=0, corruptions=0." -ForegroundColor Green
    } else {
        Write-Host "[KO] $($state.Drive) NTFS blocked: $($state.Failure)" -ForegroundColor Red
    }
}
foreach ($disk in @($nvmeState.Disks)) {
    if ($disk.Clean) {
        Write-Host "[OK] NVMe $($disk.FriendlyName): Healthy, read/write errors=0." -ForegroundColor Green
    } else {
        Write-Host "[KO] NVMe $($disk.FriendlyName): $($disk.Failure)" -ForegroundColor Red
    }
    foreach ($warning in @($disk.Warnings)) {
        Write-Warning "NVMe $($disk.FriendlyName): $warning. Surveiller l'évolution entre deux rapports."
    }
}
Write-Host "[INFO] Storage safety report: $reportPath"

if ($Mode -eq 'Verify' -and $failures.Count -gt 0) {
    throw "V24 STORAGE SAFETY BLOCK: storage is not fully clean. No convergence is allowed. $($failures -join ' | ')"
}

if ($failures.Count -eq 0) {
    Write-Host 'VERDICT: STORAGE SAFETY READY' -ForegroundColor Green
}
