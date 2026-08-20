[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z]:$')]
    [string]$BackupTargetDrive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Release = (Get-Content -Raw (Join-Path $RepoRoot 'VERSION')).Trim()
if ($Release -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION invalide: $Release" }
$TargetDrive = $BackupTargetDrive.ToUpperInvariant()
$CanonicalRoot = Join-Path $TargetDrive 'Windows_11_Pro_Custom_Backup\sessions'
$LegacyRoot = Join-Path $TargetDrive 'Windows_11_Pro_Custom_Backup\V7'
$WindowsImageRoot = Join-Path $TargetDrive 'WindowsImageBackup'
$ReportDirectory = Join-Path $RepoRoot 'reports\backup'
$ReportPath = Join-Path $ReportDirectory 'validation.json'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-WbadminVersionIdentifiers {
    param([string[]]$Lines)
    $identifiers = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($Lines)) {
        $text=[string]$line
        if ($text -match '(?i)^\s*(?:Version identifier|Identificateur de version)\s*:\s*(?<id>.+?)\s*$') { $identifiers.Add($Matches.id.Trim()); continue }
        if ($text -match '(?<id>\d{1,4}[/-]\d{1,2}[/-]\d{1,4}-\d{1,2}:\d{2})') { $identifiers.Add($Matches.id.Trim()) }
    }
    return @($identifiers | Sort-Object -Unique)
}
function Find-LatestManifest {
    $roots = @($CanonicalRoot,$LegacyRoot) | Where-Object { Test-Path -LiteralPath $_ }
    foreach ($root in $roots) {
        $manifest = Get-ChildItem -Path $root -Filter 'backup-manifest.json' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        if ($manifest) { return $manifest }
    }
    return $null
}
function Resolve-MetadataFile {
    param([Parameter(Mandatory)][string]$MetadataDirectory,[Parameter(Mandatory)][string[]]$Names)
    foreach ($name in $Names) { $candidate=Join-Path $MetadataDirectory $name; if (Test-Path -LiteralPath $candidate) { return $candidate } }
    return $null
}

if (-not (Test-Administrator)) { throw 'La validation de sauvegarde nécessite une session PowerShell élevée.' }
foreach ($command in @('wbadmin.exe','reagentc.exe')) { if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Commande requise indisponible: $command" } }
if (-not (Test-Path $WindowsImageRoot)) { throw "WindowsImageBackup est absent à la racine de $TargetDrive." }
$ManifestFile = Find-LatestManifest
if (-not $ManifestFile) { throw "Aucun manifest de sauvegarde trouvé sous $CanonicalRoot ni dans la racine historique." }
$Manifest = Get-Content -Raw $ManifestFile.FullName | ConvertFrom-Json
$isCanonical = ($Manifest.PSObject.Properties.Name -contains 'SchemaVersion') -and ([int]$Manifest.SchemaVersion -eq 1)
$isLegacy = ($Manifest.PSObject.Properties.Name -contains 'version') -and ([string]$Manifest.version -eq 'V7')
if (-not ($isCanonical -or $isLegacy)) { throw 'Format de manifest de sauvegarde non supporté.' }
if ($isLegacy) { Write-Host "[COMPAT] Manifest historique lu sans modification: $($ManifestFile.FullName)" -ForegroundColor DarkGray }

$MetadataDirectory = Split-Path $ManifestFile.FullName -Parent
$SessionRoot = Split-Path $MetadataDirectory -Parent
if (-not ($Manifest.PSObject.Properties.Name -contains 'storageIdentity')) { throw 'Le manifest ne contient aucune preuve storageIdentity.' }
$StorageIdentityBackupPath = Resolve-MetadataFile -MetadataDirectory $MetadataDirectory -Names @('storage-identity.json','storage-identity-v25.json')
if (-not $StorageIdentityBackupPath) { throw 'Baseline identité stockage absente des métadonnées.' }
$StorageIdentityDocument = Get-Content -Raw -LiteralPath $StorageIdentityBackupPath | ConvertFrom-Json
$storageSchema = if ($StorageIdentityDocument.PSObject.Properties.Name -contains 'SchemaVersion') { [int]$StorageIdentityDocument.SchemaVersion } else { $null }
$storageLegacyContract = if ($StorageIdentityDocument.PSObject.Properties.Name -contains 'ContractVersion') { [string]$StorageIdentityDocument.ContractVersion } else { '' }
if (-not (($storageSchema -eq 1) -or ($storageLegacyContract -eq 'V25'))) { throw 'Format de baseline stockage sauvegardée non supporté.' }
$StorageIdentityExpectedHash = ([string]$Manifest.storageIdentity.sha256).ToUpperInvariant()
$StorageIdentityActualHash = (Get-FileHash -LiteralPath $StorageIdentityBackupPath -Algorithm SHA256).Hash.ToUpperInvariant()
$StorageIdentityHashValid = $StorageIdentityExpectedHash -eq $StorageIdentityActualHash
if (-not $StorageIdentityHashValid) { throw 'La vérification SHA-256 de la baseline identité stockage a échoué.' }

$wslRelativePath = if ($Manifest.wsl.PSObject.Properties.Name -contains 'relativePath') { [string]$Manifest.wsl.relativePath } else { '' }
if (-not [string]::IsNullOrWhiteSpace($wslRelativePath)) { $WslBackupPath = Join-Path $SessionRoot $wslRelativePath }
else { $WslFileName=Split-Path ([string]$Manifest.wsl.exportPath) -Leaf; $WslBackupPath=Join-Path (Join-Path $SessionRoot 'WSL') $WslFileName }
if (-not (Test-Path $WslBackupPath)) { throw "Sauvegarde WSL VHDX manquante: $WslBackupPath" }
$ExpectedHash=([string]$Manifest.wsl.sha256).ToUpperInvariant(); $ActualHash=(Get-FileHash -Path $WslBackupPath -Algorithm SHA256).Hash.ToUpperInvariant(); $HashValid=$ExpectedHash -eq $ActualHash
if (-not $HashValid) { throw 'La vérification SHA-256 du VHDX WSL a échoué. Ne pas utiliser ce VHDX pour une restauration.' }

$VersionsOutput=@(& wbadmin.exe get versions "-backupTarget:$TargetDrive" 2>&1); $VersionsExitCode=$LASTEXITCODE; $global:LASTEXITCODE=0
$VersionsValid=$VersionsExitCode -eq 0 -and $VersionsOutput.Count -gt 0
if (-not $VersionsValid) { throw 'wbadmin ne peut pas énumérer de version Windows récupérable sur la cible.' }
$ExpectedVersionIdentifier = if ($Manifest.PSObject.Properties.Name -contains 'wbadminVersionIdentifier') { [string]$Manifest.wbadminVersionIdentifier } else { '' }
$VersionIdentifierMatched=$null
if (-not [string]::IsNullOrWhiteSpace($ExpectedVersionIdentifier)) {
    $VersionIdentifierMatched=@(Get-WbadminVersionIdentifiers -Lines $VersionsOutput) -contains $ExpectedVersionIdentifier
    if (-not $VersionIdentifierMatched) { throw "La version wbadmin du manifest n'est pas présente sur la cible: $ExpectedVersionIdentifier" }
} else { Write-Warning 'Manifest historique sans wbadminVersionIdentifier exact.' }

$WinReOutput=@(& reagentc.exe /info 2>&1); $WinReExitCode=$LASTEXITCODE; $global:LASTEXITCODE=0
$WinReText=$WinReOutput -join [Environment]::NewLine
$WinReEnabled=$WinReExitCode -eq 0 -and $WinReText -match '(?im)(Windows RE status\s*:\s*Enabled|État Windows RE\s*:\s*Activ)'
if (-not $WinReEnabled) { throw 'Windows Recovery Environment nʼest pas confirmé comme actif.' }
$SafetyValid=($Manifest.safety.destructiveRestoreAutomation -eq $false) -and ($Manifest.safety.unregisterExistingDistribution -eq $false) -and ($Manifest.safety.automaticDiskRecreation -eq $false)
if (-not $SafetyValid) { throw 'Le manifest ne respecte pas la politique de restauration non destructive requise.' }

New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null
$Report=[ordered]@{
    Release=$Release; SchemaVersion=1; validatedAt=(Get-Date).ToString('o'); backupTargetDrive=$TargetDrive
    manifestPath=$ManifestFile.FullName; legacyManifest=[bool]$isLegacy; windowsImageBackupPresent=$true
    wbadminRecoverableVersionEnumerated=[bool]$VersionsValid; wbadminVersionIdentifier=$ExpectedVersionIdentifier
    wbadminVersionIdentifierMatched=$VersionIdentifierMatched; winReEnabled=[bool]$WinReEnabled
    wslBackupPath=$WslBackupPath; wslSha256Expected=$ExpectedHash; wslSha256Actual=$ActualHash; wslSha256Valid=[bool]$HashValid
    storageIdentityBackupPath=$StorageIdentityBackupPath; storageIdentitySchemaVersion=$storageSchema; storageIdentityLegacyContractVersion=$storageLegacyContract
    storageIdentitySha256Expected=$StorageIdentityExpectedHash; storageIdentitySha256Actual=$StorageIdentityActualHash; storageIdentitySha256Valid=[bool]$StorageIdentityHashValid
    destructiveRestoreAutomation=$false; verdict='BACKUP READY'
}
$Report | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $ReportPath
Write-Host '[OK] WindowsImageBackup présent.' -ForegroundColor Green
Write-Host '[OK] wbadmin énumère une version récupérable.' -ForegroundColor Green
if ($VersionIdentifierMatched -eq $true) { Write-Host "[OK] Version wbadmin exacte retrouvée: $ExpectedVersionIdentifier" -ForegroundColor Green }
Write-Host '[OK] Windows RE est actif.' -ForegroundColor Green
Write-Host '[OK] SHA-256 du VHDX WSL valide.' -ForegroundColor Green
Write-Host '[OK] Baseline identité stockage présente et SHA-256 valide.' -ForegroundColor Green
Write-Host '[OK] Restauration destructive automatique désactivée.' -ForegroundColor Green
Write-Host "[OK] Rapport: $ReportPath" -ForegroundColor Green
Write-Host 'VERDICT: BACKUP READY' -ForegroundColor Green
