#Requires -Version 7.6
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z]:$')]
    [string]$BackupTargetDrive,
    [string]$Distribution = 'Ubuntu',
    [switch]$AllowNonUsbTarget,
    [switch]$SkipRestorePoint
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$PowerShellRuntimeModule = Join-Path $RepoRoot 'scripts\core\powershell-runtime.psm1'
if (-not (Test-Path -LiteralPath $PowerShellRuntimeModule)) { throw "Contrat PowerShell introuvable: $PowerShellRuntimeModule" }
Import-Module $PowerShellRuntimeModule -Force
[void](Assert-WpcPowerShellRuntime -MinimumVersion ([version]'7.6.4') -RequireWindows -PassThru)
$Release = (Get-Content -Raw (Join-Path $RepoRoot 'VERSION')).Trim()
if ($Release -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION invalide: $Release" }
$PolicyPath = Join-Path $RepoRoot 'config\backup\policy.json'
$Policy = Get-Content -Raw $PolicyPath | ConvertFrom-Json
if ([int]$Policy.schemaVersion -ne 1) { throw "SchemaVersion de politique de sauvegarde non supporté: $($Policy.schemaVersion)" }
$TargetDrive = $BackupTargetDrive.ToUpperInvariant()
$TargetLetter = $TargetDrive.TrimEnd(':')
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$SessionRoot = Join-Path $TargetDrive "Windows_11_Pro_Custom_Backup\sessions\$Timestamp"
$WslBackupDirectory = Join-Path $SessionRoot 'WSL'
$MetadataDirectory = Join-Path $SessionRoot 'metadata'
$WindowsImageRoot = Join-Path $TargetDrive 'WindowsImageBackup'
$CanonicalStorageIdentityPath = Join-Path $env:ProgramData 'Windows11ProCustom\storage-identity\volume-identity.json'
$LegacyStorageIdentityPath = Join-Path $env:ProgramData 'Windows11ProCustom\storage-v25\volume-identity.json'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DiskForDriveLetter {
    param([Parameter(Mandatory)][string]$DriveLetter)
    $partition = Get-Partition -DriveLetter $DriveLetter -ErrorAction Stop
    return Get-Disk -Number $partition.DiskNumber -ErrorAction Stop
}

function Get-WbadminVersionIdentifiers {
    param([string[]]$Lines)
    $identifiers = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($Lines)) {
        $text = [string]$line
        if ($text -match '(?i)^\s*(?:Version identifier|Identificateur de version)\s*:\s*(?<id>.+?)\s*$') {
            $identifiers.Add($Matches.id.Trim())
            continue
        }
        if ($text -match '(?<id>\d{1,4}[/-]\d{1,2}[/-]\d{1,4}-\d{1,2}:\d{2})') { $identifiers.Add($Matches.id.Trim()) }
    }
    return @($identifiers | Sort-Object -Unique)
}

function Resolve-StorageIdentityBaseline {
    if (Test-Path -LiteralPath $CanonicalStorageIdentityPath) {
        return [pscustomobject]@{ Path=$CanonicalStorageIdentityPath; Legacy=$false }
    }
    if (Test-Path -LiteralPath $LegacyStorageIdentityPath) {
        Write-Host "[COMPAT] Baseline stockage historique utilisée sans modification: $LegacyStorageIdentityPath" -ForegroundColor DarkGray
        return [pscustomobject]@{ Path=$LegacyStorageIdentityPath; Legacy=$true }
    }
    throw "Baseline d'identité stockage absente. Exécute et vérifie .\scripts\bootstrap\00_storage_identity.ps1 avant de créer un Golden Backup."
}

if (-not (Test-Administrator)) { throw 'La création de sauvegarde nécessite une session PowerShell 7 élevée.' }
$StorageIdentity = Resolve-StorageIdentityBaseline
$StorageIdentityDocument = Get-Content -Raw -LiteralPath $StorageIdentity.Path | ConvertFrom-Json
$storageSchema = if ($StorageIdentityDocument.PSObject.Properties.Name -contains 'SchemaVersion') { [int]$StorageIdentityDocument.SchemaVersion } else { $null }
$legacyContract = if ($StorageIdentityDocument.PSObject.Properties.Name -contains 'ContractVersion') { [string]$StorageIdentityDocument.ContractVersion } else { '' }
if (-not (($storageSchema -eq 1) -or ($legacyContract -eq 'V25'))) {
    throw "Format de baseline stockage non supporté: SchemaVersion=$storageSchema ContractVersion=$legacyContract"
}

foreach ($command in @('wbadmin.exe','reagentc.exe','wsl.exe','pwsh.exe')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Commande requise indisponible: $command" }
}

$TargetVolume = Get-Volume -DriveLetter $TargetLetter -ErrorAction Stop
if ($TargetVolume.FileSystem -ne 'NTFS') { throw "La cible de sauvegarde $TargetDrive doit utiliser NTFS. Détecté: $($TargetVolume.FileSystem)" }
$TargetDisk = Get-DiskForDriveLetter -DriveLetter $TargetLetter
$ProtectedDiskNumbers = @()
$ProtectedUsedBytes = [long]0
$ProtectedCapacity = @()
foreach ($volumeName in @($Policy.systemVolumes)) {
    $letter = ([string]$volumeName).TrimEnd(':')
    $volume = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue
    if ($null -eq $volume) { throw "Volume protégé requis absent: $volumeName" }
    $disk = Get-DiskForDriveLetter -DriveLetter $letter
    $ProtectedDiskNumbers += $disk.Number
    $usedBytes = [long]($volume.Size - $volume.SizeRemaining)
    $ProtectedUsedBytes += $usedBytes
    $ProtectedCapacity += [ordered]@{ volume=$volumeName; usedBytes=$usedBytes; usedGB=[math]::Round($usedBytes/1GB,2) }
}
if ($ProtectedDiskNumbers -contains $TargetDisk.Number) { throw "La cible $TargetDrive se trouve sur un disque physique protégé. Utilise un disque séparé." }
$TargetBusType = [string]$TargetDisk.BusType
if ($Policy.requireUsbTargetByDefault -and -not $AllowNonUsbTarget -and $TargetBusType -ne 'USB') {
    throw "La politique exige un disque USB de sauvegarde par défaut. BusType=$TargetBusType. Utilise -AllowNonUsbTarget uniquement après vérification humaine du disque séparé."
}

$DistroNames = @(& wsl.exe --list --quiet 2>$null | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
$global:LASTEXITCODE = 0
if ($DistroNames -notcontains $Distribution) { throw "Distribution WSL '$Distribution' introuvable. Disponibles: $($DistroNames -join ', ')" }
$WslUsedOutput = @(& wsl.exe -d $Distribution -- bash -lc 'df -B1 --output=used / | tail -n 1' 2>$null)
if ($LASTEXITCODE -ne 0) { throw "Impossible d'estimer l'espace utilisé par la distribution WSL '$Distribution'." }
$WslUsedText = (($WslUsedOutput -join '') -replace "`0", '').Trim()
$WslUsedBytes = [long]0
if (-not [long]::TryParse($WslUsedText,[ref]$WslUsedBytes)) { throw "Valeur d'espace WSL inattendue: '$WslUsedText'" }

$MarginPercent = [double]$Policy.capacitySafetyMarginPercent
if ($MarginPercent -lt 0 -or $MarginPercent -gt 100) { throw "Marge de capacité invalide: $MarginPercent" }
$EstimatedPayloadBytes = [long]($ProtectedUsedBytes + $WslUsedBytes)
$EstimatedRequiredBytes = [long][math]::Ceiling($EstimatedPayloadBytes * (1 + ($MarginPercent / 100)))
$EstimatedRequiredGB = [math]::Round($EstimatedRequiredBytes / 1GB,2)
$MinimumTargetFreeGB = [double]$Policy.minimumTargetFreeGB
$RequiredTargetFreeGB = [math]::Max($MinimumTargetFreeGB,$EstimatedRequiredGB)
$FreeGB = [math]::Round($TargetVolume.SizeRemaining / 1GB,2)
Write-Host "[INFO] Données Windows protégées utilisées: $([math]::Round($ProtectedUsedBytes/1GB,2)) Go" -ForegroundColor Cyan
Write-Host "[INFO] Données WSL utilisées: $([math]::Round($WslUsedBytes/1GB,2)) Go" -ForegroundColor Cyan
Write-Host "[INFO] Espace libre cible: $FreeGB Go; prérequis estimé: $RequiredTargetFreeGB Go" -ForegroundColor Cyan
if ($FreeGB -lt $RequiredTargetFreeGB) { throw "Espace cible insuffisant: $FreeGB Go libres, $RequiredTargetFreeGB Go requis." }

New-Item -ItemType Directory -Force -Path $WslBackupDirectory,$MetadataDirectory | Out-Null
$StorageIdentityBackupPath = Join-Path $MetadataDirectory 'storage-identity.json'
Copy-Item -LiteralPath $StorageIdentity.Path -Destination $StorageIdentityBackupPath -Force
$StorageIdentityHash = Get-FileHash -LiteralPath $StorageIdentityBackupPath -Algorithm SHA256
"$($StorageIdentityHash.Hash)  $([IO.Path]::GetFileName($StorageIdentityBackupPath))" | Set-Content -Encoding ASCII (Join-Path $MetadataDirectory 'storage-identity.sha256')

$CapacityPreflight = [ordered]@{
    SchemaVersion=1; checkedAt=(Get-Date).ToString('o'); targetFreeGB=$FreeGB; minimumTargetFreeGB=$MinimumTargetFreeGB
    safetyMarginPercent=$MarginPercent; protectedVolumes=$ProtectedCapacity; protectedUsedBytes=$ProtectedUsedBytes
    wslUsedBytes=$WslUsedBytes; estimatedPayloadBytes=$EstimatedPayloadBytes; estimatedRequiredBytes=$EstimatedRequiredBytes
    estimatedRequiredGB=$EstimatedRequiredGB; requiredTargetFreeGB=$RequiredTargetFreeGB
}
$CapacityPreflight | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $MetadataDirectory 'capacity-preflight.json')

$WinReOutput = @(& reagentc.exe /info 2>&1); $WinReExitCode=$LASTEXITCODE; $global:LASTEXITCODE=0
$WinReText = $WinReOutput -join [Environment]::NewLine
$WinReText | Set-Content -Encoding UTF8 (Join-Path $MetadataDirectory 'winre-info.txt')
if ($WinReExitCode -ne 0) { throw "reagentc /info a échoué avec le code $WinReExitCode." }
$WinReEnabled = $WinReText -match '(?im)(Windows RE status\s*:\s*Enabled|État Windows RE\s*:\s*Activ)'
if (-not $WinReEnabled) { throw 'Windows Recovery Environment nʼest pas confirmé comme actif.' }

$RestorePointAttempted=$false; $RestorePointExitCode=$null
if (-not $SkipRestorePoint) {
    $RestorePointAttempted=$true
    $RestorePointScript=Join-Path $RepoRoot 'scripts\windows\41_restore_point.ps1'
    try {
        $RestorePointOutput=@(& $RestorePointScript -Description 'Windows_11_Pro_Custom Golden Backup' *>&1)
        $RestorePointExitCode=0
    } catch {
        $RestorePointExitCode=1
        $RestorePointOutput=@([string]$_.Exception.Message)
        $RestorePointOutput | Set-Content -Encoding UTF8 (Join-Path $MetadataDirectory 'restore-point.txt')
        throw "Le point de restauration Golden Backup a échoué dans PowerShell 7: $($_.Exception.Message)"
    }
    $RestorePointOutput | Set-Content -Encoding UTF8 (Join-Path $MetadataDirectory 'restore-point.txt')
} else { 'Restore point explicitly skipped by operator.' | Set-Content -Encoding UTF8 (Join-Path $MetadataDirectory 'restore-point.txt') }

Write-Host '[INFO] Arrêt de WSL avant lʼimage de C: et E:.' -ForegroundColor Yellow
& wsl.exe --shutdown
if ($LASTEXITCODE -ne 0) { throw "wsl --shutdown a échoué avec le code $LASTEXITCODE." }
$VersionsBeforeOutput=@(& wbadmin.exe get versions "-backupTarget:$TargetDrive" 2>&1); $VersionsBeforeIdentifiers=@(Get-WbadminVersionIdentifiers -Lines $VersionsBeforeOutput); $global:LASTEXITCODE=0
$VersionsBeforeOutput | Set-Content -Encoding UTF8 (Join-Path $MetadataDirectory 'wbadmin-get-versions-before.txt')
$WbadminArguments=@('start','backup',"-backupTarget:$TargetDrive",'-include:C:,E:','-allCritical','-vssCopy')
Write-Host "[INFO] Démarrage de la sauvegarde Windows vers $TargetDrive." -ForegroundColor Cyan
$WbadminOutput=@(& wbadmin.exe @WbadminArguments 2>&1); $WbadminExitCode=$LASTEXITCODE; $global:LASTEXITCODE=0
$WbadminOutput | Set-Content -Encoding UTF8 (Join-Path $MetadataDirectory 'wbadmin-start-backup.txt')
if ($WbadminExitCode -ne 0) { throw "wbadmin start backup a échoué avec le code $WbadminExitCode." }
$VersionsOutput=@(& wbadmin.exe get versions "-backupTarget:$TargetDrive" 2>&1); $VersionsExitCode=$LASTEXITCODE; $global:LASTEXITCODE=0
$VersionsOutput | Set-Content -Encoding UTF8 (Join-Path $MetadataDirectory 'wbadmin-get-versions.txt')
if ($VersionsExitCode -ne 0 -or $VersionsOutput.Count -eq 0) { throw 'Lʼimage Windows est terminée mais aucune version récupérable nʼest énumérable.' }
$VersionsAfterIdentifiers=@(Get-WbadminVersionIdentifiers -Lines $VersionsOutput)
$CreatedVersionIdentifiers=@($VersionsAfterIdentifiers | Where-Object { $VersionsBeforeIdentifiers -notcontains $_ })
if ($CreatedVersionIdentifiers.Count -ne 1) { throw "Impossible d'identifier de manière univoque la version wbadmin créée. Nouvelles versions=$($CreatedVersionIdentifiers.Count)." }
$CreatedWbadminVersionIdentifier=$CreatedVersionIdentifiers[0]

$WslBackupPath=Join-Path $WslBackupDirectory "$Distribution-GOLDEN.vhdx"
Write-Host "[INFO] Export de la distribution WSL2 '$Distribution' au format VHDX." -ForegroundColor Cyan
& wsl.exe --export $Distribution $WslBackupPath --vhd
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $WslBackupPath)) { throw 'Lʼexport WSL VHDX a échoué ou le fichier est absent.' }
$WslHash=Get-FileHash -Path $WslBackupPath -Algorithm SHA256; $WslFile=Get-Item $WslBackupPath
"$($WslHash.Hash)  $($WslFile.Name)" | Set-Content -Encoding ASCII (Join-Path $WslBackupDirectory 'SHA256.txt')
$Os=Get-CimInstance Win32_OperatingSystem
$Manifest=[ordered]@{
    Release=$Release; SchemaVersion=1; createdAt=(Get-Date).ToString('o'); computerName=$env:COMPUTERNAME
    osCaption=$Os.Caption; osVersion=$Os.Version; osBuild=$Os.BuildNumber; backupTargetDrive=$TargetDrive
    backupTargetDiskNumber=$TargetDisk.Number; backupTargetBusType=$TargetBusType; backupTargetFreeGBBefore=$FreeGB
    capacityPreflight=$CapacityPreflight; protectedVolumes=@($Policy.systemVolumes); windowsImageBackupRoot=$WindowsImageRoot
    wbadminBackupExitCode=$WbadminExitCode; wbadminVersionsExitCode=$VersionsExitCode; wbadminVersionIdentifier=$CreatedWbadminVersionIdentifier
    winReEnabled=[bool]$WinReEnabled; restorePointAttempted=[bool]$RestorePointAttempted; restorePointExitCode=$RestorePointExitCode
    powerShell=[ordered]@{ edition=[string]$PSVersionTable.PSEdition; version=[string]$PSVersionTable.PSVersion; executable='pwsh.exe'; minimumVersion='7.6.4' }
    wsl=[ordered]@{ distribution=$Distribution; exportPath=$WslBackupPath; relativePath="WSL\$($WslFile.Name)"; bytes=$WslFile.Length; sha256=$WslHash.Hash; format='vhdx' }
    storageIdentity=[ordered]@{ schemaVersion=$storageSchema; legacyContractVersion=$legacyContract; sourcePath=$StorageIdentity.Path; relativePath='metadata\storage-identity.json'; sha256=$StorageIdentityHash.Hash; legacySource=[bool]$StorageIdentity.Legacy }
    safety=[ordered]@{ destructiveRestoreAutomation=$false; unregisterExistingDistribution=$false; automaticDiskRecreation=$false }
}
$ManifestPath=Join-Path $MetadataDirectory 'backup-manifest.json'
$Manifest | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $ManifestPath
Write-Host '[OK] Préflight de capacité validé.' -ForegroundColor Green
Write-Host '[OK] Image Windows créée et énumérée par wbadmin.' -ForegroundColor Green
Write-Host "[OK] Version wbadmin liée au manifeste: $CreatedWbadminVersionIdentifier" -ForegroundColor Green
Write-Host '[OK] VHDX WSL2 exporté et SHA-256 enregistré.' -ForegroundColor Green
Write-Host '[OK] Baseline dʼidentité stockage copiée et signée SHA-256.' -ForegroundColor Green
Write-Host "[OK] Manifest: $ManifestPath" -ForegroundColor Green
Write-Host 'VERDICT: GOLDEN BACKUP CREATED' -ForegroundColor Green
