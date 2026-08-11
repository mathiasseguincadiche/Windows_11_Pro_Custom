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
    throw 'V7 backup validation requires an elevated PowerShell session.'
}

foreach ($command in @('wbadmin.exe', 'reagentc.exe')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command is unavailable: $command"
    }
}

if (-not (Test-Path $V7Root)) {
    throw "V7 backup root not found: $V7Root"
}

if (-not (Test-Path $WindowsImageRoot)) {
    throw "WindowsImageBackup was not found at the root of $TargetDrive."
}

$ManifestFile = Get-ChildItem -Path $V7Root -Filter 'backup-manifest.json' -File -Recurse |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
if (-not $ManifestFile) {
    throw 'No V7 backup manifest was found.'
}

$Manifest = Get-Content -Raw $ManifestFile.FullName | ConvertFrom-Json
if ($Manifest.version -ne 'V7') {
    throw "Unexpected manifest version: $($Manifest.version)"
}

$SessionRoot = Split-Path (Split-Path $ManifestFile.FullName -Parent) -Parent
$WslFileName = Split-Path ([string]$Manifest.wsl.exportPath) -Leaf
$WslBackupPath = Join-Path (Join-Path $SessionRoot 'WSL') $WslFileName
if (-not (Test-Path $WslBackupPath)) {
    throw "WSL VHDX backup is missing: $WslBackupPath"
}

$ExpectedHash = ([string]$Manifest.wsl.sha256).ToUpperInvariant()
$ActualHash = (Get-FileHash -Path $WslBackupPath -Algorithm SHA256).Hash.ToUpperInvariant()
$HashValid = $ExpectedHash -eq $ActualHash
if (-not $HashValid) {
    throw 'WSL VHDX SHA-256 verification failed. Do not use this VHDX for restoration.'
}

$VersionsOutput = @(& wbadmin.exe get versions "-backupTarget:$TargetDrive" 2>&1)
$VersionsExitCode = $LASTEXITCODE
$VersionsValid = $VersionsExitCode -eq 0 -and $VersionsOutput.Count -gt 0
if (-not $VersionsValid) {
    throw 'wbadmin cannot enumerate a recoverable Windows backup version on the target.'
}

$WinReOutput = @(& reagentc.exe /info 2>&1)
$WinReExitCode = $LASTEXITCODE
$WinReText = $WinReOutput -join [Environment]::NewLine
$WinReEnabled = $WinReExitCode -eq 0 -and $WinReText -match '(?im)(Windows RE status\s*:\s*Enabled|État Windows RE\s*:\s*Activ)'
if (-not $WinReEnabled) {
    throw 'Windows Recovery Environment is not currently confirmed as enabled.'
}

$SafetyValid = ($Manifest.safety.destructiveRestoreAutomation -eq $false) -and
    ($Manifest.safety.unregisterExistingDistribution -eq $false) -and
    ($Manifest.safety.automaticDiskRecreation -eq $false)
if (-not $SafetyValid) {
    throw 'V7 manifest does not preserve the required non-destructive restore policy.'
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
    destructiveRestoreAutomation = $false
    verdict = 'V7 BACKUP READY'
}
$Report | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $ReportPath

Write-Host '[OK] WindowsImageBackup exists.' -ForegroundColor Green
Write-Host '[OK] wbadmin enumerates a recoverable backup version.' -ForegroundColor Green
Write-Host '[OK] Windows RE is enabled.' -ForegroundColor Green
Write-Host '[OK] WSL2 VHDX SHA-256 matches the manifest.' -ForegroundColor Green
Write-Host '[OK] Destructive restore automation remains disabled.' -ForegroundColor Green
Write-Host "[OK] Validation report: $ReportPath" -ForegroundColor Green
Write-Host 'VERDICT: V7 BACKUP READY' -ForegroundColor Green
