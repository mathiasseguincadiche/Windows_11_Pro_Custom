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
$PolicyPath = Join-Path $RepoRoot 'config\backup\v7-policy.json'
$Policy = Get-Content -Raw $PolicyPath | ConvertFrom-Json
$TargetDrive = $BackupTargetDrive.ToUpperInvariant()
$TargetLetter = $TargetDrive.TrimEnd(':')
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$SessionRoot = Join-Path $TargetDrive "Windows_11_Pro_Custom_Backup\V7\$Timestamp"
$WslBackupDirectory = Join-Path $SessionRoot 'WSL'
$MetadataDirectory = Join-Path $SessionRoot 'metadata'
$WindowsImageRoot = Join-Path $TargetDrive 'WindowsImageBackup'
$StorageIdentityBaselinePath = Join-Path $env:ProgramData 'Windows11ProCustom\storage-v25\volume-identity.json'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DiskForDriveLetter {
    param(
        [Parameter(Mandatory)]
        [string]$DriveLetter
    )

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
        if ($text -match '(?<id>\d{1,4}[/-]\d{1,2}[/-]\d{1,4}-\d{1,2}:\d{2})') {
            $identifiers.Add($Matches.id.Trim())
        }
    }
    return @($identifiers | Sort-Object -Unique)
}

if (-not (Test-Administrator)) {
    throw 'La création de sauvegarde nécessite une session PowerShell élevée.'
}

if (-not (Test-Path -LiteralPath $StorageIdentityBaselinePath)) {
    throw "Baseline d'identité V25 absente: $StorageIdentityBaselinePath. Enrôle et vérifie C:/D: avant de créer un Golden Backup."
}
$StorageIdentityDocument = Get-Content -Raw -LiteralPath $StorageIdentityBaselinePath | ConvertFrom-Json
if ([string]$StorageIdentityDocument.ContractVersion -ne 'V25') {
    throw "Version de baseline stockage inattendue: $($StorageIdentityDocument.ContractVersion)"
}

foreach ($command in @('wbadmin.exe', 'reagentc.exe', 'wsl.exe', 'powershell.exe')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Commande requise indisponible: $command"
    }
}

$TargetVolume = Get-Volume -DriveLetter $TargetLetter -ErrorAction Stop
if ($TargetVolume.FileSystem -ne 'NTFS') {
    throw "La cible de sauvegarde $TargetDrive doit utiliser NTFS. Détecté: $($TargetVolume.FileSystem)"
}

$TargetDisk = Get-DiskForDriveLetter -DriveLetter $TargetLetter
$ProtectedDiskNumbers = @()
$ProtectedUsedBytes = [long]0
$ProtectedCapacity = @()
foreach ($volumeName in @($Policy.systemVolumes)) {
    $letter = ([string]$volumeName).TrimEnd(':')
    $volume = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue
    if ($null -eq $volume) {
        throw "Volume protégé requis absent: $volumeName"
    }

    $disk = Get-DiskForDriveLetter -DriveLetter $letter
    $ProtectedDiskNumbers += $disk.Number
    $usedBytes = [long]($volume.Size - $volume.SizeRemaining)
    $ProtectedUsedBytes += $usedBytes
    $ProtectedCapacity += [ordered]@{
        volume = $volumeName
        usedBytes = $usedBytes
        usedGB = [math]::Round($usedBytes / 1GB, 2)
    }
}

if ($ProtectedDiskNumbers -contains $TargetDisk.Number) {
    throw "La cible $TargetDrive se trouve sur un disque physique lui-même protégé. Utilise un disque physique séparé."
}

$TargetBusType = [string]$TargetDisk.BusType
if ($Policy.requireUsbTargetByDefault -and -not $AllowNonUsbTarget -and $TargetBusType -ne 'USB') {
    throw "La politique exige un disque USB de sauvegarde par défaut. BusType détecté=$TargetBusType. Utilise -AllowNonUsbTarget seulement après avoir vérifié qu'il s'agit bien d'un disque de sauvegarde séparé."
}

$DistroNames = @(& wsl.exe --list --quiet 2>$null | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
if ($DistroNames -notcontains $Distribution) {
    throw "Distribution WSL '$Distribution' introuvable. Disponibles: $($DistroNames -join ', ')"
}

$WslUsedOutput = @(& wsl.exe -d $Distribution -- bash -lc 'df -B1 --output=used / | tail -n 1' 2>$null)
if ($LASTEXITCODE -ne 0) {
    throw "Impossible d'estimer l'espace utilisé par la distribution WSL '$Distribution'."
}
$WslUsedText = (($WslUsedOutput -join '') -replace "`0", '').Trim()
$WslUsedBytes = [long]0
if (-not [long]::TryParse($WslUsedText, [ref]$WslUsedBytes)) {
    throw "Valeur d'espace WSL inattendue: '$WslUsedText'"
}

$MarginPercent = [double]$Policy.capacitySafetyMarginPercent
if ($MarginPercent -lt 0 -or $MarginPercent -gt 100) {
    throw "Marge de capacité invalide: $MarginPercent"
}
$EstimatedPayloadBytes = [long]($ProtectedUsedBytes + $WslUsedBytes)
$EstimatedRequiredBytes = [long][math]::Ceiling($EstimatedPayloadBytes * (1 + ($MarginPercent / 100)))
$EstimatedRequiredGB = [math]::Round($EstimatedRequiredBytes / 1GB, 2)
$MinimumTargetFreeGB = [double]$Policy.minimumTargetFreeGB
$RequiredTargetFreeGB = [math]::Max($MinimumTargetFreeGB, $EstimatedRequiredGB)
$FreeGB = [math]::Round($TargetVolume.SizeRemaining / 1GB, 2)

Write-Host "[INFO] Données Windows protégées utilisées: $([math]::Round($ProtectedUsedBytes / 1GB, 2)) Go" -ForegroundColor Cyan
Write-Host "[INFO] Données WSL utilisées pour l'export indépendant: $([math]::Round($WslUsedBytes / 1GB, 2)) Go" -ForegroundColor Cyan
Write-Host "[INFO] Marge de capacité: $MarginPercent%" -ForegroundColor Cyan
Write-Host "[INFO] Espace libre cible: $FreeGB Go; prérequis estimé: $RequiredTargetFreeGB Go" -ForegroundColor Cyan

if ($FreeGB -lt $RequiredTargetFreeGB) {
    throw "La cible ne dispose que de $FreeGB Go libres. Au moins $RequiredTargetFreeGB Go sont estimés nécessaires (données protégées + export WSL indépendant + marge de $MarginPercent%, avec minimum absolu de $MinimumTargetFreeGB Go)."
}

New-Item -ItemType Directory -Force -Path $WslBackupDirectory, $MetadataDirectory | Out-Null

$StorageIdentityBackupPath = Join-Path $MetadataDirectory 'storage-identity-v25.json'
Copy-Item -LiteralPath $StorageIdentityBaselinePath -Destination $StorageIdentityBackupPath -Force
$StorageIdentityHash = Get-FileHash -LiteralPath $StorageIdentityBackupPath -Algorithm SHA256
"$($StorageIdentityHash.Hash)  $([IO.Path]::GetFileName($StorageIdentityBackupPath))" |
    Set-Content -Encoding ASCII (Join-Path $MetadataDirectory 'storage-identity-v25.sha256')

$CapacityPreflight = [ordered]@{
    checkedAt = (Get-Date).ToString('o')
    targetFreeGB = $FreeGB
    minimumTargetFreeGB = $MinimumTargetFreeGB
    safetyMarginPercent = $MarginPercent
    protectedVolumes = $ProtectedCapacity
    protectedUsedBytes = $ProtectedUsedBytes
    wslUsedBytes = $WslUsedBytes
    estimatedPayloadBytes = $EstimatedPayloadBytes
    estimatedRequiredBytes = $EstimatedRequiredBytes
    estimatedRequiredGB = $EstimatedRequiredGB
    requiredTargetFreeGB = $RequiredTargetFreeGB
}
$CapacityPreflight | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $MetadataDirectory 'capacity-preflight.json')

$WinReOutput = @(& reagentc.exe /info 2>&1)
$WinReExitCode = $LASTEXITCODE
$WinReText = $WinReOutput -join [Environment]::NewLine
$WinReText | Set-Content -Encoding UTF8 (Join-Path $MetadataDirectory 'winre-info.txt')
if ($WinReExitCode -ne 0) {
    throw "reagentc /info a échoué avec le code $WinReExitCode."
}

$WinReEnabled = $WinReText -match '(?im)(Windows RE status\s*:\s*Enabled|État Windows RE\s*:\s*Activ)'
if (-not $WinReEnabled) {
    throw "Windows Recovery Environment nʼest pas confirmé comme actif. La sauvegarde de référence exige un WinRE utilisable."
}

$RestorePointAttempted = $false
$RestorePointExitCode = $null
if (-not $SkipRestorePoint) {
    $RestorePointAttempted = $true
    $RestorePointScript = Join-Path $RepoRoot 'scripts\windows\41_restore_point.ps1'
    $RestorePointOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RestorePointScript -Description 'Windows_11_Pro_Custom Golden Backup' 2>&1)
    $RestorePointExitCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    $RestorePointOutput | Set-Content -Encoding UTF8 (Join-Path $MetadataDirectory 'restore-point.txt')
    if ($RestorePointExitCode -ne 0) {
        throw "Le point de restauration Golden Backup a échoué avec le code $RestorePointExitCode. Utilise -SkipRestorePoint uniquement après une décision explicite et documentée."
    }
} else {
    'Restore point explicitly skipped by operator.' | Set-Content -Encoding UTF8 (Join-Path $MetadataDirectory 'restore-point.txt')
}

Write-Host "[INFO] Arrêt de WSL avant lʼimage de C: et D:." -ForegroundColor Yellow
& wsl.exe --shutdown
if ($LASTEXITCODE -ne 0) {
    throw "wsl --shutdown a échoué avec le code $LASTEXITCODE."
}

$VersionsBeforeOutput = @(& wbadmin.exe get versions "-backupTarget:$TargetDrive" 2>&1)
$VersionsBeforeIdentifiers = @(Get-WbadminVersionIdentifiers -Lines $VersionsBeforeOutput)
$global:LASTEXITCODE = 0
$VersionsBeforeOutput | Set-Content -Encoding UTF8 (Join-Path $MetadataDirectory 'wbadmin-get-versions-before.txt')

$WbadminArguments = @(
    'start',
    'backup',
    "-backupTarget:$TargetDrive",
    '-include:C:,D:',
    '-allCritical',
    '-vssCopy'
)

Write-Host "[INFO] Démarrage de la sauvegarde Windows vers $TargetDrive. wbadmin peut demander une confirmation lors de la première exécution." -ForegroundColor Cyan
$WbadminOutput = @(& wbadmin.exe @WbadminArguments 2>&1)
$WbadminExitCode = $LASTEXITCODE
$WbadminOutput | Set-Content -Encoding UTF8 (Join-Path $MetadataDirectory 'wbadmin-start-backup.txt')
if ($WbadminExitCode -ne 0) {
    throw "wbadmin start backup a échoué avec le code $WbadminExitCode. Consulter wbadmin-start-backup.txt."
}

$VersionsOutput = @(& wbadmin.exe get versions "-backupTarget:$TargetDrive" 2>&1)
$VersionsExitCode = $LASTEXITCODE
$VersionsOutput | Set-Content -Encoding UTF8 (Join-Path $MetadataDirectory 'wbadmin-get-versions.txt')
if ($VersionsExitCode -ne 0 -or $VersionsOutput.Count -eq 0) {
    throw "Lʼimage Windows est terminée mais wbadmin ne peut pas énumérer de version récupérable."
}
$VersionsAfterIdentifiers = @(Get-WbadminVersionIdentifiers -Lines $VersionsOutput)
$CreatedVersionIdentifiers = @($VersionsAfterIdentifiers | Where-Object { $VersionsBeforeIdentifiers -notcontains $_ })
if ($CreatedVersionIdentifiers.Count -ne 1) {
    throw "Impossible d'identifier de manière univoque la version wbadmin créée. Nouvelles versions détectées=$($CreatedVersionIdentifiers.Count). Consulter wbadmin-get-versions-before.txt et wbadmin-get-versions.txt."
}
$CreatedWbadminVersionIdentifier = $CreatedVersionIdentifiers[0]

$WslBackupPath = Join-Path $WslBackupDirectory "$Distribution-GOLDEN-V7.vhdx"
Write-Host "[INFO] Export de la distribution WSL2 '$Distribution' au format VHDX." -ForegroundColor Cyan
& wsl.exe --export $Distribution $WslBackupPath --vhd
if ($LASTEXITCODE -ne 0) {
    throw "Lʼexport WSL a échoué avec le code $LASTEXITCODE."
}

if (-not (Test-Path $WslBackupPath)) {
    throw "Lʼexport WSL a retourné un succès mais le fichier VHDX est absent."
}

$WslHash = Get-FileHash -Path $WslBackupPath -Algorithm SHA256
$WslFile = Get-Item $WslBackupPath
"$($WslHash.Hash)  $($WslFile.Name)" | Set-Content -Encoding ASCII (Join-Path $WslBackupDirectory 'SHA256.txt')

$Os = Get-CimInstance Win32_OperatingSystem
$Manifest = [ordered]@{
    version = 'V7'
    createdAt = (Get-Date).ToString('o')
    computerName = $env:COMPUTERNAME
    osCaption = $Os.Caption
    osVersion = $Os.Version
    osBuild = $Os.BuildNumber
    backupTargetDrive = $TargetDrive
    backupTargetDiskNumber = $TargetDisk.Number
    backupTargetBusType = $TargetBusType
    backupTargetFreeGBBefore = $FreeGB
    capacityPreflight = $CapacityPreflight
    protectedVolumes = @($Policy.systemVolumes)
    windowsImageBackupRoot = $WindowsImageRoot
    wbadminBackupExitCode = $WbadminExitCode
    wbadminVersionsExitCode = $VersionsExitCode
    wbadminVersionIdentifier = $CreatedWbadminVersionIdentifier
    winReEnabled = [bool]$WinReEnabled
    restorePointAttempted = [bool]$RestorePointAttempted
    restorePointExitCode = $RestorePointExitCode
    wsl = [ordered]@{
        distribution = $Distribution
        exportPath = $WslBackupPath
        bytes = $WslFile.Length
        sha256 = $WslHash.Hash
        format = 'vhdx'
    }
    storageIdentity = [ordered]@{
        contractVersion = [string]$StorageIdentityDocument.ContractVersion
        sourcePath = $StorageIdentityBaselinePath
        backupPath = $StorageIdentityBackupPath
        sha256 = $StorageIdentityHash.Hash
    }
    safety = [ordered]@{
        destructiveRestoreAutomation = $false
        unregisterExistingDistribution = $false
        automaticDiskRecreation = $false
    }
}

$ManifestPath = Join-Path $MetadataDirectory 'backup-manifest.json'
$Manifest | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $ManifestPath

Write-Host '[OK] Préflight de capacité validé.' -ForegroundColor Green
Write-Host '[OK] Image Windows créée et énumérée par wbadmin.' -ForegroundColor Green
Write-Host "[OK] Version wbadmin liée au manifeste: $CreatedWbadminVersionIdentifier" -ForegroundColor Green
Write-Host '[OK] VHDX WSL2 exporté et SHA-256 enregistré.' -ForegroundColor Green
Write-Host '[OK] Baseline dʼidentité stockage V25 copiée et signée SHA-256.' -ForegroundColor Green
Write-Host "[OK] Manifest: $ManifestPath" -ForegroundColor Green
Write-Host 'VERDICT: GOLDEN BACKUP CREATED' -ForegroundColor Green
