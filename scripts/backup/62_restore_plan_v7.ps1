[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z]:$')]
    [string]$BackupTargetDrive,

    [ValidateSet('All', 'WSL', 'Windows')]
    [string]$Scenario = 'All',

    [string]$RestoreDistribution = 'Ubuntu-Restore-V7',
    [string]$RestoreLocation = 'D:\WSL\Ubuntu-Restore-V7'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$TargetDrive = $BackupTargetDrive.ToUpperInvariant()
$V7Root = Join-Path $TargetDrive 'Windows_11_Pro_Custom_Backup\V7'
$ReportDirectory = Join-Path $RepoRoot 'reports\backup'
$PlanPath = Join-Path $ReportDirectory 'restore-plan-v7.txt'

if (-not (Test-Path $V7Root)) {
    throw "Racine de sauvegarde introuvable: $V7Root"
}

$ManifestFile = Get-ChildItem -Path $V7Root -Filter 'backup-manifest.json' -File -Recurse |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
if (-not $ManifestFile) {
    throw "Aucun manifest de sauvegarde n’a été trouvé."
}

$Manifest = Get-Content -Raw $ManifestFile.FullName | ConvertFrom-Json
$SessionRoot = Split-Path (Split-Path $ManifestFile.FullName -Parent) -Parent
$WslFileName = Split-Path ([string]$Manifest.wsl.exportPath) -Leaf
$WslBackupPath = Join-Path (Join-Path $SessionRoot 'WSL') $WslFileName

if (-not (Test-Path $WslBackupPath)) {
    throw "Sauvegarde WSL VHDX manquante: $WslBackupPath"
}

$ExpectedHash = ([string]$Manifest.wsl.sha256).ToUpperInvariant()
$ActualHash = (Get-FileHash -Path $WslBackupPath -Algorithm SHA256).Hash.ToUpperInvariant()
if ($ExpectedHash -ne $ActualHash) {
    throw 'Hash de sauvegarde WSL incorrect. La génération du plan de restauration est bloquée.'
}

if ($RestoreDistribution -eq [string]$Manifest.wsl.distribution) {
    throw 'Le nom de la distribution de test restaurée doit différer de la distribution protégée.'
}

$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add('Windows_11_Pro_Custom - PLAN DE RESTAURATION')
$Lines.Add("Généré: $((Get-Date).ToString('o'))")
$Lines.Add("Manifest de sauvegarde: $($ManifestFile.FullName)")
$Lines.Add("Cible de sauvegarde: $TargetDrive")
$Lines.Add('')
$Lines.Add('POLITIQUE DE SÉCURITÉ')
$Lines.Add("- Ce script génère uniquement des instructions. Il n’exécute aucune restauration.")
$Lines.Add("- Ne jamais désenregistrer Ubuntu avant d’avoir validé une copie restaurée.")
$Lines.Add('- Ne jamais recréer ou formater automatiquement les disques depuis le dépôt.')
$Lines.Add('')

if ($Scenario -in @('All', 'WSL')) {
    $Lines.Add('TEST DE RESTAURATION WSL2')
    $Lines.Add("1. Confirmer SHA-256: $ActualHash")
    $Lines.Add('2. Arrêter WSL:')
    $Lines.Add('   wsl --shutdown')
    $Lines.Add('3. Importer la sauvegarde à côté de la distribution actuelle, sous un nom différent:')
    $Lines.Add("   wsl --import $RestoreDistribution `"$RestoreLocation`" `"$WslBackupPath`" --vhd")
    $Lines.Add('4. Vérifier que les deux distributions sont présentes:')
    $Lines.Add('   wsl -l -v')
    $Lines.Add('5. Ouvrir uniquement la copie restaurée:')
    $Lines.Add("   wsl -d $RestoreDistribution")
    $Lines.Add('6. Valider HOME, ~/projects, les paquets, Docker et les outils DevOps avant toute décision sur la distribution existante.')
    $Lines.Add('')
}

if ($Scenario -in @('All', 'Windows')) {
    $Lines.Add('RESTAURATION WINDOWS / BARE-METAL')
    $Lines.Add('1. Préférer System Restore pour une petite régression de configuration Windows.')
    $Lines.Add('2. Pour un incident de boot ou de disque, démarrer dans Windows Recovery Environment ou sur le Recovery Drive.')
    $Lines.Add("3. Depuis WinRE, énumérer les versions avec: wbadmin get versions -backupTarget:$TargetDrive")
    $Lines.Add("4. Sélectionner l’identifiant de version voulu et vérifier les disques cibles avant toute récupération.")
    $Lines.Add("5. Modèle de commande bare-metal, À EXÉCUTER MANUELLEMENT DEPUIS WINRE UNIQUEMENT: wbadmin start sysrecovery -version:<VERSION_IDENTIFIER> -backupTarget:$TargetDrive -restoreAllVolumes")
    $Lines.Add('6. Ne pas ajouter -recreateDisks sans vérification humaine explicite du layout et acceptation du risque de repartitionnement.')
    $Lines.Add('')
    $Lines.Add('MÉDIA DE RÉCUPÉRATION')
    $Lines.Add('Créer ou actualiser le Recovery Drive avec recoverydrive.exe. La clé USB choisie dans cette interface est effacée par Windows.')
    $Lines.Add('')
}

$Lines.Add('VERDICT: RESTORE PLAN READY - NO RESTORE EXECUTED')
New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null
$Lines | Set-Content -Encoding UTF8 $PlanPath
$Lines | ForEach-Object { Write-Host $_ }
Write-Host "[OK] Plan de restauration enregistré: $PlanPath" -ForegroundColor Green
