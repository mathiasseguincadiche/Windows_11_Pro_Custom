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
$failures = [System.Collections.Generic.List[string]]::new()

function Get-WpcNtfsVolumeCim {
    param([Parameter(Mandatory)][ValidatePattern('^[A-Z]$')][string]$DriveLetter)

    $volume = @(
        Get-CimInstance -Namespace 'root/Microsoft/Windows/Storage' -ClassName MSFT_Volume -ErrorAction Stop |
            Where-Object { [string]$_.DriveLetter -eq $DriveLetter } |
            Select-Object -First 1
    )
    if ($volume.Count -eq 0) {
        throw "MSFT_Volume introuvable pour $DriveLetter`:"
    }
    return $volume[0]
}

function Get-WpcNtfsCorruptionCount {
    param([Parameter(Mandatory)]$Volume)

    $result = Invoke-CimMethod -InputObject $Volume -MethodName GetCorruptionCount -ErrorAction Stop
    if ([uint32]$result.ReturnValue -ne 0) {
        throw "GetCorruptionCount a échoué avec le code $($result.ReturnValue)."
    }
    return [uint32]$result.CorruptionCount
}

function Invoke-WpcNtfsSafetyCheck {
    param([Parameter(Mandatory)][ValidatePattern('^[A-Z]$')][string]$DriveLetter)

    $drive = "$DriveLetter`:"
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
            Failure = "$drive doit être NTFS."
        }
    }

    $win32Volume = @(Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter='$drive'" -ErrorAction Stop | Select-Object -First 1)
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
    $scanReturnCode = if ($scanOutput.Count -gt 0) { [uint32]$scanOutput[-1] } else { $null }

    $msftVolume = Get-WpcNtfsVolumeCim -DriveLetter $DriveLetter
    $corruptionCount = Get-WpcNtfsCorruptionCount -Volume $msftVolume
    $msftHealthStatus = [uint16]$msftVolume.HealthStatus

    $global:LASTEXITCODE = 0
    $journal = @(& fsutil.exe repair enumerate $drive '$Corrupt' 2>&1 | ForEach-Object { [string]$_ })
    $journalExitCode = [int]$LASTEXITCODE
    $global:LASTEXITCODE = 0
    $journalPath = Join-Path $reportDir "$DriveLetter-corrupt-journal.txt"
    $journal | Set-Content -Encoding utf8 $journalPath

    $clean = (
        -not $dirtyBitSet -and
        $dirtyEvidenceExitCode -eq 0 -and
        $null -ne $scanReturnCode -and
        $scanReturnCode -eq 0 -and
        $msftHealthStatus -eq 0 -and
        $corruptionCount -eq 0 -and
        $journalExitCode -eq 0
    )

    $reasons = [System.Collections.Generic.List[string]]::new()
    if ($dirtyBitSet) { $reasons.Add('dirty-bit NTFS positionné') }
    if ($dirtyEvidenceExitCode -ne 0) { $reasons.Add("fsutil dirty query a échoué (code=$dirtyEvidenceExitCode)") }
    if ($null -eq $scanReturnCode) { $reasons.Add('Repair-Volume -Scan n’a retourné aucun code exploitable') }
    elseif ($scanReturnCode -ne 0) { $reasons.Add("Repair-Volume -Scan a échoué (code=$scanReturnCode)") }
    if ($msftHealthStatus -ne 0) { $reasons.Add("MSFT_Volume HealthStatus=$msftHealthStatus") }
    if ($corruptionCount -gt 0) { $reasons.Add("$corruptionCount corruption(s) NTFS confirmée(s)") }
    if ($journalExitCode -ne 0) { $reasons.Add("lecture du journal `$Corrupt impossible (code=$journalExitCode)") }

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
        Failure = if ($reasons.Count -gt 0) { $reasons -join '; ' } else { $null }
    }
}

function ConvertTo-WpcNullableUInt64 {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    return [uint64]$Value
}

function Invoke-WpcNvmeSafetyCheck {
    $nvmeDisks = @(Get-PhysicalDisk -ErrorAction Stop | Where-Object { [string]$_.BusType -eq 'NVMe' })
    if ($nvmeDisks.Count -eq 0) {
        return [pscustomobject]@{
            TargetCount = 0
            TargetMinimumCount = $targetMinimumCount
            Disks = @()
            Clean = $false
            Failure = 'Aucun disque NVMe détecté.'
        }
    }

    $targetDisks = @($nvmeDisks | Where-Object { (([string]$_.FriendlyName + ' ' + [string]$_.Model) -match $targetModelRegex) })
    $diskStates = [System.Collections.Generic.List[object]]::new()

    foreach ($disk in $nvmeDisks) {
        $counter = $null
        $counterError = $null
        try {
            $counter = @($disk | Get-StorageReliabilityCounter -ErrorAction Stop | Select-Object -First 1)
            if ($counter.Count -gt 0) { $counter = $counter[0] } else { $counter = $null }
        } catch {
            $counterError = $_.Exception.Message
        }

        $readTotal = if ($counter) { ConvertTo-WpcNullableUInt64 $counter.ReadErrorsTotal } else { $null }
        $writeTotal = if ($counter) { ConvertTo-WpcNullableUInt64 $counter.WriteErrorsTotal } else { $null }
        $readUncorrected = if ($counter) { ConvertTo-WpcNullableUInt64 $counter.ReadErrorsUncorrected } else { $null }
        $writeUncorrected = if ($counter) { ConvertTo-WpcNullableUInt64 $counter.WriteErrorsUncorrected } else { $null }
        $temperature = if ($counter -and $null -ne $counter.Temperature) { [int]$counter.Temperature } else { $null }

        $reasons = [System.Collections.Generic.List[string]]::new()
        if ([string]$disk.HealthStatus -ne 'Healthy') { $reasons.Add("HealthStatus=$($disk.HealthStatus)") }
        if ($null -eq $counter) { $reasons.Add("compteurs de fiabilité indisponibles: $counterError") }
        if ($null -eq $readTotal) { $reasons.Add('ReadErrorsTotal indisponible') }
        elseif ($readTotal -gt 0) { $reasons.Add("ReadErrorsTotal=$readTotal") }
        if ($null -eq $writeTotal) { $reasons.Add('WriteErrorsTotal indisponible') }
        elseif ($writeTotal -gt 0) { $reasons.Add("WriteErrorsTotal=$writeTotal") }
        if ($null -eq $readUncorrected) { $reasons.Add('ReadErrorsUncorrected indisponible') }
        elseif ($readUncorrected -gt 0) { $reasons.Add("ReadErrorsUncorrected=$readUncorrected") }
        if ($null -eq $writeUncorrected) { $reasons.Add('WriteErrorsUncorrected indisponible') }
        elseif ($writeUncorrected -gt 0) { $reasons.Add("WriteErrorsUncorrected=$writeUncorrected") }
        if ($null -ne $temperature -and $temperature -gt $criticalTemperatureC) { $reasons.Add("température=${temperature}C > ${criticalTemperatureC}C") }

        $diskStates.Add([pscustomobject]@{
            FriendlyName = [string]$disk.FriendlyName
            Model = [string]$disk.Model
            SerialNumber = [string]$disk.SerialNumber
            BusType = [string]$disk.BusType
            HealthStatus = [string]$disk.HealthStatus
            OperationalStatus = @($disk.OperationalStatus | ForEach-Object { [string]$_ })
            IsTargetT705 = (([string]$disk.FriendlyName + ' ' + [string]$disk.Model) -match $targetModelRegex)
            ReliabilityAvailable = ($null -ne $counter)
            Temperature = $temperature
            TemperatureMax = if ($counter) { $counter.TemperatureMax } else { $null }
            Wear = if ($counter) { $counter.Wear } else { $null }
            PowerOnHours = if ($counter) { $counter.PowerOnHours } else { $null }
            ReadErrorsTotal = $readTotal
            WriteErrorsTotal = $writeTotal
            ReadErrorsUncorrected = $readUncorrected
            WriteErrorsUncorrected = $writeUncorrected
            Clean = ($reasons.Count -eq 0)
            Failure = if ($reasons.Count -gt 0) { $reasons -join '; ' } else { $null }
        })
    }

    $reasonsAll = [System.Collections.Generic.List[string]]::new()
    if ($targetDisks.Count -lt $targetMinimumCount) {
        $reasonsAll.Add("T705 détectés=$($targetDisks.Count), minimum attendu=$targetMinimumCount")
    }
    foreach ($state in $diskStates) {
        if (-not $state.Clean) {
            $reasonsAll.Add("$($state.FriendlyName): $($state.Failure)")
        }
    }

    return [pscustomobject]@{
        TargetCount = $targetDisks.Count
        TargetMinimumCount = $targetMinimumCount
        Disks = @($diskStates)
        Clean = ($reasonsAll.Count -eq 0)
        Failure = if ($reasonsAll.Count -gt 0) { $reasonsAll -join ' | ' } else { $null }
    }
}

$volumeStates = [System.Collections.Generic.List[object]]::new()
foreach ($letter in @('C', 'D')) {
    try {
        $state = Invoke-WpcNtfsSafetyCheck -DriveLetter $letter
        $volumeStates.Add($state)
        if (-not $state.Clean) { $failures.Add("$($state.Drive) $($state.Failure)") }
    } catch {
        $volumeStates.Add([pscustomobject]@{
            Drive = "$letter`:"
            Clean = $false
            Failure = $_.Exception.Message
        })
        $failures.Add("$letter`: $($_.Exception.Message)")
    }
}

$nvmeState = $null
try {
    $nvmeState = Invoke-WpcNvmeSafetyCheck
    if (-not $nvmeState.Clean) { $failures.Add("NVMe: $($nvmeState.Failure)") }
} catch {
    $nvmeState = [pscustomobject]@{ Clean=$false; Failure=$_.Exception.Message; Disks=@() }
    $failures.Add("NVMe: $($_.Exception.Message)")
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
        RequiredVolumes = @('C:', 'D:')
        DirtyBitMustBeClear = $true
        RepairVolumeScanRequired = $true
        CorruptionCountMustBeZero = $true
        CorruptionJournalCaptured = $true
        NvmeReliabilityRequired = $true
        ReadErrorsTotalMustBeZero = $true
        WriteErrorsTotalMustBeZero = $true
        UncorrectedErrorsMustBeZero = $true
        TargetModelRegex = $targetModelRegex
        TargetMinimumCount = $targetMinimumCount
        CriticalTemperatureC = $criticalTemperatureC
    }
}
$report | ConvertTo-Json -Depth 12 | Set-Content -Encoding utf8 $reportPath

foreach ($state in $volumeStates) {
    if ($state.Clean) {
        Write-Host "[OK] $($state.Drive) NTFS propre: dirty-bit=0, scan=0, corruptions=0." -ForegroundColor Green
    } else {
        Write-Host "[KO] $($state.Drive) NTFS non qualifié: $($state.Failure)" -ForegroundColor Red
    }
}
foreach ($disk in @($nvmeState.Disks)) {
    if ($disk.Clean) {
        Write-Host "[OK] NVMe $($disk.FriendlyName): Healthy, erreurs lecture/écriture=0." -ForegroundColor Green
    } else {
        Write-Host "[KO] NVMe $($disk.FriendlyName): $($disk.Failure)" -ForegroundColor Red
    }
}
Write-Host "[INFO] Rapport V24: $reportPath"

if ($Mode -eq 'Verify' -and $failures.Count -gt 0) {
    throw "V24 STORAGE SAFETY BLOCK: stockage non totalement propre. Aucune convergence ne doit commencer. $($failures -join ' | ')"
}

if ($failures.Count -eq 0) {
    Write-Host 'VERDICT: V24 STORAGE SAFETY READY' -ForegroundColor Green
}
