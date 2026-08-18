[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Record', 'Verify')]
    [string]$Mode = 'Audit',
    [string]$BaselinePath = '',
    [switch]$ConfirmHealthyTopology,
    [switch]$ReplaceBaseline
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
    $BaselinePath = Join-Path $env:ProgramData 'Windows11ProCustom\storage-v25\volume-identity.json'
}
$BaselineHashPath = "$BaselinePath.sha256"
$reportDir = Join-Path $repoRoot 'reports\storage-identity-v25'
$reportPath = Join-Path $reportDir 'latest-topology.json'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

function Get-WpcPropertyValue {
    param(
        [Parameter(Mandatory)]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function ConvertTo-WpcIdentityText {
    param($Value)
    if ($null -eq $Value) { return '' }
    return ([string]$Value).Trim().ToLowerInvariant()
}

function ConvertTo-WpcGuidText {
    param($Value)
    if ($null -eq $Value) { return '' }
    return (([string]$Value).Trim().Trim('{}')).ToUpperInvariant()
}

function Get-WpcBaselineIntegrity {
    param(
        [Parameter(Mandatory)][string]$BaselinePath,
        [Parameter(Mandatory)][string]$HashPath
    )

    if (-not (Test-Path -LiteralPath $BaselinePath)) {
        throw "Baseline V25 absente: $BaselinePath"
    }
    $actual = (Get-FileHash -LiteralPath $BaselinePath -Algorithm SHA256).Hash.ToUpperInvariant()
    if (-not (Test-Path -LiteralPath $HashPath)) {
        return [pscustomobject]@{ Status = 'MISSING_HASH'; Sha256 = $actual }
    }

    $text = (Get-Content -Raw -LiteralPath $HashPath).Trim()
    if ($text -notmatch '^(?<hash>[A-Fa-f0-9]{64})\s{2}(?<file>[^\r\n]+)$') {
        throw "Sidecar SHA-256 V25 invalide: $HashPath"
    }
    $expectedFileName = [IO.Path]::GetFileName($BaselinePath)
    if ($Matches.file -ne $expectedFileName) {
        throw "Le sidecar SHA-256 V25 référence un fichier inattendu: $($Matches.file)"
    }
    $expected = $Matches.hash.ToUpperInvariant()
    if ($actual -ne $expected) {
        throw "Intégrité baseline V25 invalide. attendu=$expected actuel=$actual"
    }
    return [pscustomobject]@{ Status = 'VERIFIED'; Sha256 = $actual }
}

function Write-WpcBaselineWithHash {
    param(
        [Parameter(Mandatory)][string]$Json,
        [Parameter(Mandatory)][string]$BaselinePath,
        [Parameter(Mandatory)][string]$HashPath
    )

    $parent = Split-Path -Parent $BaselinePath
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $token = [guid]::NewGuid().ToString('N')
    $temporaryBaseline = "$BaselinePath.$token.tmp"
    $temporaryHash = "$HashPath.$token.tmp"
    $baselineMoved = $false
    $hashMoved = $false
    try {
        $Json | Set-Content -LiteralPath $temporaryBaseline -Encoding UTF8
        $hash = (Get-FileHash -LiteralPath $temporaryBaseline -Algorithm SHA256).Hash.ToUpperInvariant()
        "$hash  $([IO.Path]::GetFileName($BaselinePath))" | Set-Content -LiteralPath $temporaryHash -Encoding ASCII
        Move-Item -LiteralPath $temporaryBaseline -Destination $BaselinePath -Force
        $baselineMoved = $true
        Move-Item -LiteralPath $temporaryHash -Destination $HashPath -Force
        $hashMoved = $true
        return $hash
    } catch {
        if ($baselineMoved -and -not $hashMoved) {
            Remove-Item -LiteralPath $BaselinePath -Force -ErrorAction SilentlyContinue
        }
        throw
    } finally {
        Remove-Item -LiteralPath $temporaryBaseline, $temporaryHash -Force -ErrorAction SilentlyContinue
    }
}

function Test-WpcAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Get-WpcStorageTopology {
    $disks = @(Get-Disk -ErrorAction Stop)
    $partitions = @(Get-Partition -ErrorAction Stop)
    $volumes = @(Get-Volume -ErrorAction Stop)

    $diskFacts = @(
        foreach ($disk in $disks) {
            [pscustomobject]@{
                Number = [int]$disk.Number
                FriendlyName = [string]$disk.FriendlyName
                Model = [string](Get-WpcPropertyValue -InputObject $disk -Name 'Model')
                SerialNumber = [string]$disk.SerialNumber
                UniqueId = [string]$disk.UniqueId
                Guid = [string](Get-WpcPropertyValue -InputObject $disk -Name 'Guid')
                Location = [string](Get-WpcPropertyValue -InputObject $disk -Name 'Location')
                BusType = [string]$disk.BusType
                PartitionStyle = [string]$disk.PartitionStyle
                OperationalStatus = @($disk.OperationalStatus | ForEach-Object { [string]$_ })
                HealthStatus = [string]$disk.HealthStatus
                IsOffline = [bool]$disk.IsOffline
                IsReadOnly = [bool]$disk.IsReadOnly
                Size = [uint64]$disk.Size
            }
        }
    )

    $partitionFacts = @(
        foreach ($partition in $partitions) {
            $disk = @($disks | Where-Object Number -EQ $partition.DiskNumber | Select-Object -First 1)
            $driveLetter = [string](Get-WpcPropertyValue -InputObject $partition -Name 'DriveLetter')
            $volume = @()
            if ($driveLetter -match '^[A-Za-z]$') {
                $volume = @(Get-Volume -DriveLetter $driveLetter[0] -ErrorAction SilentlyContinue | Select-Object -First 1)
            }
            $diskItem = if ($disk.Count -gt 0) { $disk[0] } else { $null }
            $volumeItem = if ($volume.Count -gt 0) { $volume[0] } else { $null }

            [pscustomobject]@{
                DiskNumber = [int]$partition.DiskNumber
                PartitionNumber = [int]$partition.PartitionNumber
                DriveLetter = $driveLetter.ToUpperInvariant()
                AccessPaths = @((Get-WpcPropertyValue -InputObject $partition -Name 'AccessPaths') | ForEach-Object { [string]$_ })
                Type = [string](Get-WpcPropertyValue -InputObject $partition -Name 'Type')
                GptType = [string](Get-WpcPropertyValue -InputObject $partition -Name 'GptType')
                MbrType = [string](Get-WpcPropertyValue -InputObject $partition -Name 'MbrType')
                PartitionGuid = [string](Get-WpcPropertyValue -InputObject $partition -Name 'Guid')
                PartitionUniqueId = [string](Get-WpcPropertyValue -InputObject $partition -Name 'UniqueId')
                IsActive = [bool](Get-WpcPropertyValue -InputObject $partition -Name 'IsActive')
                IsBoot = [bool](Get-WpcPropertyValue -InputObject $partition -Name 'IsBoot')
                IsSystem = [bool](Get-WpcPropertyValue -InputObject $partition -Name 'IsSystem')
                IsHidden = [bool](Get-WpcPropertyValue -InputObject $partition -Name 'IsHidden')
                IsReadOnly = [bool](Get-WpcPropertyValue -InputObject $partition -Name 'IsReadOnly')
                IsOffline = [bool](Get-WpcPropertyValue -InputObject $partition -Name 'IsOffline')
                Size = [uint64]$partition.Size
                Offset = [uint64]$partition.Offset
                DiskFriendlyName = if ($null -ne $diskItem) { [string]$diskItem.FriendlyName } else { '' }
                DiskModel = if ($null -ne $diskItem) { [string](Get-WpcPropertyValue -InputObject $diskItem -Name 'Model') } else { '' }
                DiskSerialNumber = if ($null -ne $diskItem) { [string]$diskItem.SerialNumber } else { '' }
                DiskUniqueId = if ($null -ne $diskItem) { [string]$diskItem.UniqueId } else { '' }
                DiskPartitionStyle = if ($null -ne $diskItem) { [string]$diskItem.PartitionStyle } else { '' }
                DiskIsOffline = if ($null -ne $diskItem) { [bool]$diskItem.IsOffline } else { $true }
                DiskIsReadOnly = if ($null -ne $diskItem) { [bool]$diskItem.IsReadOnly } else { $true }
                VolumeUniqueId = if ($null -ne $volumeItem) { [string]$volumeItem.UniqueId } else { '' }
                VolumePath = if ($null -ne $volumeItem) { [string]$volumeItem.Path } else { '' }
                FileSystem = if ($null -ne $volumeItem) { [string]$volumeItem.FileSystem } else { '' }
                FileSystemLabel = if ($null -ne $volumeItem) { [string]$volumeItem.FileSystemLabel } else { '' }
                VolumeHealthStatus = if ($null -ne $volumeItem) { [string]$volumeItem.HealthStatus } else { '' }
                VolumeOperationalStatus = if ($null -ne $volumeItem) { @($volumeItem.OperationalStatus | ForEach-Object { [string]$_ }) } else { @() }
            }
        }
    )

    $volumeFacts = @(
        foreach ($volume in $volumes) {
            [pscustomobject]@{
                DriveLetter = [string]$volume.DriveLetter
                Path = [string]$volume.Path
                UniqueId = [string]$volume.UniqueId
                FileSystem = [string]$volume.FileSystem
                FileSystemLabel = [string]$volume.FileSystemLabel
                DriveType = [string]$volume.DriveType
                HealthStatus = [string]$volume.HealthStatus
                OperationalStatus = @($volume.OperationalStatus | ForEach-Object { [string]$_ })
                Size = [uint64]$volume.Size
                SizeRemaining = [uint64]$volume.SizeRemaining
            }
        }
    )

    return [pscustomobject]@{
        CapturedAt = (Get-Date).ToString('o')
        Disks = $diskFacts
        Partitions = $partitionFacts
        Volumes = $volumeFacts
    }
}

function Get-WpcRolePartition {
    param(
        [Parameter(Mandatory)]$Topology,
        [Parameter(Mandatory)][ValidatePattern('^[CE]$')][string]$DriveLetter
    )
    $partitions = @($Topology.Partitions | Where-Object DriveLetter -EQ $DriveLetter)
    if ($partitions.Count -ne 1) { return $null }
    return $partitions[0]
}

function Get-WpcRoleFailures {
    param(
        [Parameter(Mandatory)][AllowNull()]$Partition,
        [Parameter(Mandatory)][ValidatePattern('^[CE]$')][string]$Role
    )
    $failures = @()
    if ($null -eq $Partition) { return @("${Role}: partition introuvable ou ambiguë") }
    if ($Partition.FileSystem -ne 'NTFS') { $failures += "${Role}: filesystem=$($Partition.FileSystem), attendu=NTFS" }
    if ($Partition.DiskPartitionStyle -ne 'GPT') { $failures += "${Role}: partitionStyle=$($Partition.DiskPartitionStyle), attendu=GPT" }
    if ($Partition.DiskIsOffline -or $Partition.IsOffline) { $failures += "${Role}: disque ou partition hors ligne" }
    if ($Partition.DiskIsReadOnly -or $Partition.IsReadOnly) { $failures += "${Role}: disque ou partition en lecture seule" }
    if ($Partition.VolumeHealthStatus -ne 'Healthy') { $failures += "${Role}: volumeHealth=$($Partition.VolumeHealthStatus), attendu=Healthy" }
    if ([string]::IsNullOrWhiteSpace($Partition.DiskUniqueId) -and [string]::IsNullOrWhiteSpace($Partition.DiskSerialNumber)) {
        $failures += "${Role}: aucune identité disque stable disponible"
    }
    if ([string]::IsNullOrWhiteSpace($Partition.PartitionGuid) -and [string]::IsNullOrWhiteSpace($Partition.PartitionUniqueId)) {
        $failures += "${Role}: aucune identité de partition stable disponible"
    }
    if ([string]::IsNullOrWhiteSpace($Partition.VolumeUniqueId)) { $failures += "${Role}: VolumeUniqueId indisponible" }
    if ($Role -eq 'E') {
        $basicDataGptType = 'EBD0A0A2-B9E5-4433-87C0-68B6B72699C7'
        $gptType = ConvertTo-WpcGuidText $Partition.GptType
        if ([string]::IsNullOrWhiteSpace($gptType)) {
            $failures += 'E: GptType indisponible ; partition de données GPT requise'
        } elseif ($gptType -ne $basicDataGptType) {
            $failures += "E: gptType=$($Partition.GptType), attendu=Basic data ($basicDataGptType)"
        }
        if ($Partition.IsBoot) { $failures += 'E: ne doit jamais être la partition de démarrage Windows' }
        if ($Partition.IsSystem) { $failures += 'E: ne doit jamais être une partition système/EFI' }
        if ($Partition.IsHidden) { $failures += 'E: ne doit jamais être une partition masquée' }
    }
    return @($failures)
}

function ConvertTo-WpcRoleIdentity {
    param(
        [Parameter(Mandatory)]$Partition,
        [Parameter(Mandatory)][ValidatePattern('^[CE]$')][string]$Role
    )
    return [ordered]@{
        Role = $Role
        DriveLetter = $Role
        DiskFriendlyName = [string]$Partition.DiskFriendlyName
        DiskModel = [string]$Partition.DiskModel
        DiskSerialNumber = [string]$Partition.DiskSerialNumber
        DiskUniqueId = [string]$Partition.DiskUniqueId
        PartitionGuid = [string]$Partition.PartitionGuid
        PartitionUniqueId = [string]$Partition.PartitionUniqueId
        VolumeUniqueId = [string]$Partition.VolumeUniqueId
        FileSystem = [string]$Partition.FileSystem
        Size = [uint64]$Partition.Size
        IsBoot = [bool]$Partition.IsBoot
        IsSystem = [bool]$Partition.IsSystem
    }
}

function Compare-WpcRoleIdentity {
    param(
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)]$Actual,
        [Parameter(Mandatory)][string]$Role
    )
    $differences = @()
    foreach ($property in @('DriveLetter','DiskSerialNumber','DiskUniqueId','PartitionGuid','PartitionUniqueId','VolumeUniqueId','FileSystem','Size','IsBoot','IsSystem')) {
        $expectedValue = Get-WpcPropertyValue -InputObject $Expected -Name $property
        $actualValue = Get-WpcPropertyValue -InputObject $Actual -Name $property
        if ((ConvertTo-WpcIdentityText $expectedValue) -ne (ConvertTo-WpcIdentityText $actualValue)) {
            $differences += "${Role}.${property}: attendu='$expectedValue' observé='$actualValue'"
        }
    }
    return @($differences)
}

$topology = Get-WpcStorageTopology
$cPartition = Get-WpcRolePartition -Topology $topology -DriveLetter 'C'
$ePartition = Get-WpcRolePartition -Topology $topology -DriveLetter 'E'
$failures = @()
$failures += @(Get-WpcRoleFailures -Partition $cPartition -Role 'C')
$failures += @(Get-WpcRoleFailures -Partition $ePartition -Role 'E')
if ($null -ne $cPartition -and $null -ne $ePartition -and $cPartition.DiskNumber -eq $ePartition.DiskNumber) {
    $failures += 'C: et E: doivent résider sur deux disques physiques distincts.'
}

$baselinePresent = Test-Path -LiteralPath $BaselinePath
$baseline = $null
$baselineIntegrity = $null
if ($baselinePresent) {
    try { $baseline = Get-Content -Raw -LiteralPath $BaselinePath | ConvertFrom-Json }
    catch { $failures += "Baseline V25 illisible: $($_.Exception.Message)" }
    if ($Mode -in @('Audit', 'Verify')) {
        try { $baselineIntegrity = Get-WpcBaselineIntegrity -BaselinePath $BaselinePath -HashPath $BaselineHashPath }
        catch { $failures += $_.Exception.Message }
        if ($null -ne $baselineIntegrity -and [string]$baselineIntegrity.Status -ne 'VERIFIED') {
            $failures += "Intégrité baseline V25 insuffisante: statut=$($baselineIntegrity.Status). Ré-enrôle explicitement la topologie saine pour générer le SHA-256 local."
        }
    }
}

if ($Mode -in @('Audit','Verify') -and $null -ne $baseline -and $null -ne $cPartition -and $null -ne $ePartition) {
    $contractVersion = Get-WpcPropertyValue -InputObject $baseline -Name 'ContractVersion'
    $roles = Get-WpcPropertyValue -InputObject $baseline -Name 'Roles'
    $expectedC = if ($null -ne $roles) { Get-WpcPropertyValue -InputObject $roles -Name 'C' } else { $null }
    $expectedE = if ($null -ne $roles) { Get-WpcPropertyValue -InputObject $roles -Name 'E' } else { $null }
    if ([string]$contractVersion -ne 'V25') { $failures += "Version baseline=$contractVersion, attendue=V25" }
    if ($null -eq $expectedC -or $null -eq $expectedE) {
        $failures += 'Schéma baseline V25 invalide: Roles.C et Roles.E sont obligatoires.'
    } else {
        $failures += @(Compare-WpcRoleIdentity -Expected $expectedC -Actual (ConvertTo-WpcRoleIdentity -Partition $cPartition -Role 'C') -Role 'C')
        $failures += @(Compare-WpcRoleIdentity -Expected $expectedE -Actual (ConvertTo-WpcRoleIdentity -Partition $ePartition -Role 'E') -Role 'E')
    }
}

$report = [ordered]@{
    Version = 'V25'
    Timestamp = (Get-Date).ToString('o')
    Mode = $Mode
    BaselinePath = $BaselinePath
    BaselineHashPath = $BaselineHashPath
    BaselinePresent = $baselinePresent
    BaselineContractVersion = if ($null -ne $baseline) { [string](Get-WpcPropertyValue -InputObject $baseline -Name 'ContractVersion') } else { $null }
    BaselineIntegrityStatus = if ($null -ne $baselineIntegrity) { [string]$baselineIntegrity.Status } else { $null }
    Clean = ($failures.Count -eq 0)
    Failures = @($failures)
    Topology = $topology
}
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding utf8

if ($Mode -eq 'Record') {
    if (-not (Test-WpcAdministrator)) {
        throw 'Enrôlement refusé: PowerShell administrateur est requis pour écrire la baseline machine dans ProgramData.'
    }
    if (-not $ConfirmHealthyTopology) {
        throw 'Enrôlement refusé: utilise explicitement -ConfirmHealthyTopology après vérification humaine de la topologie C:/E:.'
    }
    if ($baselinePresent -and -not $ReplaceBaseline) {
        throw "Baseline V25 déjà présente: $BaselinePath. Aucun remplacement silencieux. Utilise -ReplaceBaseline avec -ConfirmHealthyTopology uniquement après investigation."
    }
    if ($failures.Count -gt 0) {
        throw "Enrôlement V25 refusé: stockage non qualifié. $($failures -join ' | ')"
    }
    $baselineDocument = [ordered]@{
        ContractVersion = 'V25'
        RecordedAt = (Get-Date).ToString('o')
        Policy = 'explicit-trust-enrollment; fail-closed; no-automatic-repair; distinct-physical-disks'
        Roles = [ordered]@{
            C = ConvertTo-WpcRoleIdentity -Partition $cPartition -Role 'C'
            E = ConvertTo-WpcRoleIdentity -Partition $ePartition -Role 'E'
        }
    }
    $baselineDir = Split-Path -Parent $BaselinePath
    New-Item -ItemType Directory -Force -Path $baselineDir | Out-Null
    $baselineHash = Write-WpcBaselineWithHash -Json ($baselineDocument | ConvertTo-Json -Depth 8) -BaselinePath $BaselinePath -HashPath $BaselineHashPath
    Write-Host "[FAIT] Baseline V25 enregistrée explicitement: $BaselinePath" -ForegroundColor Green
    Write-Host "[FAIT] Sidecar SHA-256 V25 enregistré: $BaselineHashPath ($baselineHash)" -ForegroundColor Green
    Write-Host 'Relance immédiatement le mode Verify avant toute installation.' -ForegroundColor Yellow
    return
}

if (-not $baselinePresent) {
    $message = "Baseline V25 absente. Après contrôle humain de C:/E:, exécute: .\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Record -ConfirmHealthyTopology"
    if ($Mode -eq 'Verify') { throw $message }
    Write-Host "[ACTION REQUISE] $message" -ForegroundColor Yellow
}

if ($failures.Count -gt 0) {
    if ($Mode -eq 'Verify') {
        throw "V25 STORAGE IDENTITY BLOCK: topologie disque/volume différente ou non sûre. Aucune convergence autorisée. $($failures -join ' | ')"
    }
    Write-Host "[ALERTE] Topologie V25 non qualifiée: $($failures -join ' | ')" -ForegroundColor Yellow
} elseif ($baselinePresent) {
    Write-Host '[OK] V25: C: et E: correspondent exactement aux identités enrôlées.' -ForegroundColor Green
    Write-Host 'VERDICT: STORAGE IDENTITY READY' -ForegroundColor Green
}
Write-Host "[INFO] Rapport topologique V25: $reportPath" -ForegroundColor DarkGray
