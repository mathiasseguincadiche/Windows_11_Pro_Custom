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
    throw "V7 backup root not found: $V7Root"
}

$ManifestFile = Get-ChildItem -Path $V7Root -Filter 'backup-manifest.json' -File -Recurse |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
if (-not $ManifestFile) {
    throw 'No V7 backup manifest was found.'
}

$Manifest = Get-Content -Raw $ManifestFile.FullName | ConvertFrom-Json
$SessionRoot = Split-Path (Split-Path $ManifestFile.FullName -Parent) -Parent
$WslFileName = Split-Path ([string]$Manifest.wsl.exportPath) -Leaf
$WslBackupPath = Join-Path (Join-Path $SessionRoot 'WSL') $WslFileName

if (-not (Test-Path $WslBackupPath)) {
    throw "WSL VHDX backup is missing: $WslBackupPath"
}

$ExpectedHash = ([string]$Manifest.wsl.sha256).ToUpperInvariant()
$ActualHash = (Get-FileHash -Path $WslBackupPath -Algorithm SHA256).Hash.ToUpperInvariant()
if ($ExpectedHash -ne $ActualHash) {
    throw 'WSL backup hash mismatch. Restore plan generation is blocked.'
}

if ($RestoreDistribution -eq [string]$Manifest.wsl.distribution) {
    throw 'The restore-test distribution name must differ from the protected production distribution.'
}

$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add('Windows_11_Pro_Custom - V7 RESTORE PLAN')
$Lines.Add("Generated: $((Get-Date).ToString('o'))")
$Lines.Add("Backup manifest: $($ManifestFile.FullName)")
$Lines.Add("Backup target: $TargetDrive")
$Lines.Add('')
$Lines.Add('SAFETY POLICY')
$Lines.Add('- This script generates instructions only. It does not execute a restore.')
$Lines.Add('- Never unregister the existing Ubuntu distribution before a restored copy has been validated.')
$Lines.Add('- Never recreate or format disks automatically from the repository.')
$Lines.Add('')

if ($Scenario -in @('All', 'WSL')) {
    $Lines.Add('WSL2 RESTORE TEST')
    $Lines.Add("1. Confirm SHA-256: $ActualHash")
    $Lines.Add('2. Stop WSL:')
    $Lines.Add('   wsl --shutdown')
    $Lines.Add('3. Import the backup beside the current distro, under a different name:')
    $Lines.Add("   wsl --import $RestoreDistribution `"$RestoreLocation`" `"$WslBackupPath`" --vhd")
    $Lines.Add('4. Verify both distributions are present:')
    $Lines.Add('   wsl -l -v')
    $Lines.Add('5. Open only the restored copy:')
    $Lines.Add("   wsl -d $RestoreDistribution")
    $Lines.Add('6. Validate HOME, ~/projects, packages, Docker and DevOps tooling before deciding anything about the old distro.')
    $Lines.Add('')
}

if ($Scenario -in @('All', 'Windows')) {
    $Lines.Add('WINDOWS / BARE-METAL RESTORE')
    $Lines.Add('1. Prefer System Restore first for a small Windows configuration regression.')
    $Lines.Add('2. For a boot or disk disaster, boot into Windows Recovery Environment or the Recovery Drive.')
    $Lines.Add("3. From WinRE, enumerate versions with: wbadmin get versions -backupTarget:$TargetDrive")
    $Lines.Add('4. Select the intended Version identifier and review target disks before any recovery command.')
    $Lines.Add("5. Bare-metal recovery command template, TO BE RUN MANUALLY FROM WINRE ONLY: wbadmin start sysrecovery -version:<VERSION_IDENTIFIER> -backupTarget:$TargetDrive -restoreAllVolumes")
    $Lines.Add('6. Do not add -recreateDisks unless a human has explicitly verified the replacement-disk layout and accepts repartitioning risk.')
    $Lines.Add('')
    $Lines.Add('RECOVERY MEDIA')
    $Lines.Add('Create or refresh the Recovery Drive interactively with recoverydrive.exe. The USB selected in that UI is erased by Windows.')
    $Lines.Add('')
}

$Lines.Add('VERDICT: V7 RESTORE PLAN GENERATED - NO RESTORE EXECUTED')
New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null
$Lines | Set-Content -Encoding UTF8 $PlanPath
$Lines | ForEach-Object { Write-Host $_ }
Write-Host "[OK] Restore plan saved to: $PlanPath" -ForegroundColor Green
