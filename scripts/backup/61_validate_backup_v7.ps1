[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z]:$')]
    [string]$BackupTargetDrive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$TargetDrive = $BackupTargetDrive.ToUpperInvariant()
$V7Root = Join-Path $TargetDrive 'Windows_11_Pro_Custom_Backup\V7'
$WindowsImageRoot = Join-Path $TargetDrive 'WindowsImageBackup'
$ReportDirectory = Join-Path $RepoRoot 'reports\backup'
$ReportPath = Join-Path $ReportDirectory 'validation-v7.json'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    throw 'La validation de sauvegarde nécessite une session PowerShell élevée.'
}

foreach ($command in @('wbadmin.exe', 'reagentc.exe')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Commande requise indisponible: $command"
    }
}

if (-not (Test-Path $V7Root)) {
    throw "Racine de sauvegarde introuvable: $V7Root"
}

if (-not (Test-Path $WindowsImageRoot)) {
    throw "WindowsImageBackup est absent à la racine de $TargetDrive."
}

$ManifestFile = Get-ChildItem -Path $V7Root -Filter 'backup-manifest.json' -File -Recurse |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
if (-not $ManifestFile) {
    throw "Aucun manifest de sauvegarde n’a été trouvé."
}

$Manifest = Get-Content -Raw $ManifestFile.FullName | ConvertFrom-Json
if ($Manifest.version -ne 'V7') {
    throw "Version interne de manifest inattendue: $($Manifest.version)"
}

$SessionRoot = Split-Path (Split-Path $ManifestFile.FullName -Parent) -Parent
$MetadataDirectory = Split-Path $ManifestFile.FullName -Parent
$StorageIdentityManifestProperty = $Manifest.PSObject.Properties['storageIdentity']
if ($null -eq $StorageIdentityManifestProperty) {
    throw 'Le manifest ne contient aucune preuve storageIdentity V25. Cette sauvegarde antérieure ne peut pas recevoir le verdict V25.'
}
$StorageIdentityBackupPath = Join-Path $MetadataDirectory 'storage-identity-v25.json'
if (-not (Test-Path -LiteralPath $StorageIdentityBackupPath)) {
    throw "Baseline V25 absente des métadonnées: $StorageIdentityBackupPath"
}
$StorageIdentityDocument = Get-Content -Raw -LiteralPath $StorageIdentityBackupPath | ConvertFrom-Json
if ([string]$StorageIdentityDocument.ContractVersion -ne 'V25') {
    throw "Contrat baseline sauvegardé inattendu: $($StorageIdentityDocument.ContractVersion)"
}
$StorageIdentityExpectedHash = ([string]$Manifest.storageIdentity.sha256).ToUpperInvariant()
$StorageIdentityActualHash = (Get-FileHash -LiteralPath $StorageIdentityBackupPath -Algorithm SHA256).Hash.ToUpperInvariant()
$StorageIdentityHashValid = $StorageIdentityExpectedHash -eq $StorageIdentityActualHash
if (-not $StorageIdentityHashValid) {
    throw 'La vérification SHA-256 de la baseline d’identité stockage V25 a échoué.'
}

$WslFileName = Split-Path ([string]$Manifest.wsl.exportPath) -Leaf
$WslBackupPath = Join-Path (Join-Path $SessionRoot 'WSL') $WslFileName
if (-not (Test-Path $WslBackupPath)) {
    throw "Sauvegarde WSL VHDX manquante: $WslBackupPath"
}

$ExpectedHash = ([string]$Manifest.wsl.sha256).ToUpperInvariant()
$ActualHash = (Get-FileHash -Path $WslBackupPath -Algorithm SHA256).Hash.ToUpperInvariant()
$HashValid = $ExpectedHash -eq $ActualHash
if (-not $HashValid) {
    throw 'La vérification SHA-256 du VHDX WSL a échoué. Ne pas utiliser ce VHDX pour une restauration.'
}

$VersionsOutput = @(& wbadmin.exe get versions "-backupTarget:$TargetDrive" 2>&1)
$VersionsExitCode = $LASTEXITCODE
$VersionsValid = $VersionsExitCode -eq 0 -and $VersionsOutput.Count -gt 0
if (-not $VersionsValid) {
    throw 'wbadmin ne peut pas énumérer de version Windows récupérable sur la cible.'
}

$WinReOutput = @(& reagentc.exe /info 2>&1)
$WinReExitCode = $LASTEXITCODE
$WinReText = $WinReOutput -join [Environment]::NewLine
$WinReEnabled = $WinReExitCode -eq 0 -and $WinReText -match '(?im)(Windows RE status\s*:\s*Enabled|État Windows RE\s*:\s*Activ)'
if (-not $WinReEnabled) {
    throw "Windows Recovery Environment n’est pas confirmé comme actif."
}

$SafetyValid = ($Manifest.safety.destructiveRestoreAutomation -eq $false) -and
    ($Manifest.safety.unregisterExistingDistribution -eq $false) -and
    ($Manifest.safety.automaticDiskRecreation -eq $false)
if (-not $SafetyValid) {
    throw 'Le manifest ne respecte pas la politique de restauration non destructive requise.'
}

New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null
$Report = [ordered]@{
    version = 'V7'
    validatedAt = (Get-Date).ToString('o')
    backupTargetDrive = $TargetDrive
    manifestPath = $ManifestFile.FullName
    windowsImageBackupPresent = $true
    wbadminRecoverableVersionEnumerated = [bool]$VersionsValid
    winReEnabled = [bool]$WinReEnabled
    wslBackupPath = $WslBackupPath
    wslSha256Expected = $ExpectedHash
    wslSha256Actual = $ActualHash
    wslSha256Valid = [bool]$HashValid
    storageIdentityBackupPath = $StorageIdentityBackupPath
    storageIdentityContractVersion = [string]$StorageIdentityDocument.ContractVersion
    storageIdentitySha256Expected = $StorageIdentityExpectedHash
    storageIdentitySha256Actual = $StorageIdentityActualHash
    storageIdentitySha256Valid = [bool]$StorageIdentityHashValid
    destructiveRestoreAutomation = $false
    verdict = 'BACKUP READY'
}
$Report | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $ReportPath

Write-Host '[OK] WindowsImageBackup présent.' -ForegroundColor Green
Write-Host '[OK] wbadmin énumère une version de sauvegarde récupérable.' -ForegroundColor Green
Write-Host '[OK] Windows RE est actif.' -ForegroundColor Green
Write-Host '[OK] Le SHA-256 du VHDX WSL correspond au manifest.' -ForegroundColor Green
Write-Host '[OK] La baseline d’identité stockage V25 est présente et son SHA-256 correspond.' -ForegroundColor Green
Write-Host '[OK] La restauration destructive automatique reste désactivée.' -ForegroundColor Green
Write-Host "[OK] Rapport de validation: $ReportPath" -ForegroundColor Green
Write-Host 'VERDICT: BACKUP READY' -ForegroundColor Green
