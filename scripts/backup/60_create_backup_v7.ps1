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

if (-not (Test-Administrator)) {
    throw 'V7 backup creation requires an elevated PowerShell session.'
}

foreach ($command in @('wbadmin.exe', 'reagentc.exe', 'wsl.exe', 'powershell.exe')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command is unavailable: $command"
    }
}

$TargetVolume = Get-Volume -DriveLetter $TargetLetter -ErrorAction Stop
if ($TargetVolume.FileSystem -ne 'NTFS') {
    throw "Backup target $TargetDrive must use NTFS. Detected: $($TargetVolume.FileSystem)"
}

$TargetDisk = Get-DiskForDriveLetter -DriveLetter $TargetLetter
$ProtectedDiskNumbers = @()
foreach ($volumeName in @($Policy.systemVolumes)) {
    $letter = ([string]$volumeName).TrimEnd(':')
    if (-not (Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue)) {
        throw "Required protected volume is missing: $volumeName"
    }

    $disk = Get-DiskForDriveLetter -DriveLetter $letter
    $ProtectedDiskNumbers += $disk.Number
}

if ($ProtectedDiskNumbers -contains $TargetDisk.Number) {
    throw "Backup target $TargetDrive is on a physical disk that is itself protected by the V7 backup. Use a separate physical disk."
}

$TargetBusType = [string]$TargetDisk.BusType
if ($Policy.requireUsbTargetByDefault -and -not $AllowNonUsbTarget -and $TargetBusType -ne 'USB') {
    throw "V7 requires a USB backup disk by default. Detected BusType=$TargetBusType. Use -AllowNonUsbTarget only after verifying this is a separate backup disk."
}

$FreeGB = [math]::Round($TargetVolume.SizeRemaining / 1GB, 2)
if ($FreeGB -lt [double]$Policy.minimumTargetFreeGB) {
    throw "Backup target has only $FreeGB GB free. V7 requires at least $($Policy.minimumTargetFreeGB) GB before starting."
}

$DistroNames = @(& wsl.exe --list --quiet 2>$null | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
if ($DistroNames -notcontains $Distribution) {
    throw "WSL distribution '$Distribution' was not found. Available: $($DistroNames -join ', ')"
}

New-Item -ItemType Directory -Force -Path $WslBackupDirectory, $MetadataDirectory | Out-Null

$WinReOutput = @(& reagentc.exe /info 2>&1)
$WinReExitCode = $LASTEXITCODE
$WinReText = $WinReOutput -join [Environment]::NewLine
$WinReText | Set-Content -Encoding UTF8 (Join-Path $MetadataDirectory 'winre-info.txt')
if ($WinReExitCode -ne 0) {
    throw "reagentc /info failed with exit code $WinReExitCode."
}

$WinReEnabled = $WinReText -match '(?im)(Windows RE status\s*:\s*Enabled|État Windows RE\s*:\s*Activ)'
if (-not $WinReEnabled) {
    throw 'Windows Recovery Environment is not confirmed as enabled. V7 refuses to create a Golden Backup without a usable WinRE configuration.'
}

$RestorePointAttempted = $false
if (-not $SkipRestorePoint) {
    $RestorePointAttempted = $true
    $RestorePointScript = Join-Path $RepoRoot 'scripts\windows\41_restore_point.ps1'
    $RestorePointOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RestorePointScript -Description 'Windows_11_Pro_Custom V7 Golden Backup' 2>&1)
    $RestorePointOutput | Set-Content -Encoding UTF8 (Join-Path $MetadataDirectory 'restore-point.txt')
} else {
    'Restore point explicitly skipped by operator.' | Set-Content -Encoding UTF8 (Join-Path $MetadataDirectory 'restore-point.txt')
}

Write-Host '[INFO] Stopping WSL before imaging C: and D:.' -ForegroundColor Yellow
& wsl.exe --shutdown
if ($LASTEXITCODE -ne 0) {
    throw "wsl --shutdown failed with exit code $LASTEXITCODE."
}

$WbadminArguments = @(
    'start',
    'backup',
    "-backupTarget:$TargetDrive",
    '-include:C:,D:',
    '-allCritical',
    '-vssCopy'
)

Write-Host "[INFO] Starting Windows Golden Backup to $TargetDrive. wbadmin will request confirmation for this first run." -ForegroundColor Cyan
$WbadminOutput = @(& wbadmin.exe @WbadminArguments 2>&1)
$WbadminExitCode = $LASTEXITCODE
$WbadminOutput | Set-Content -Encoding UTF8 (Join-Path $MetadataDirectory 'wbadmin-start-backup.txt')
if ($WbadminExitCode -ne 0) {
    throw "wbadmin start backup failed with exit code $WbadminExitCode. Review wbadmin-start-backup.txt."
}

$VersionsOutput = @(& wbadmin.exe get versions "-backupTarget:$TargetDrive" 2>&1)
$VersionsExitCode = $LASTEXITCODE
$VersionsOutput | Set-Content -Encoding UTF8 (Join-Path $MetadataDirectory 'wbadmin-get-versions.txt')
if ($VersionsExitCode -ne 0 -or $VersionsOutput.Count -eq 0) {
    throw 'The Windows image completed but wbadmin could not enumerate a recoverable backup version.'
}

$WslBackupPath = Join-Path $WslBackupDirectory "$Distribution-GOLDEN-V7.vhdx"
Write-Host "[INFO] Exporting WSL2 distribution '$Distribution' as VHDX." -ForegroundColor Cyan
& wsl.exe --export $Distribution $WslBackupPath --vhd
if ($LASTEXITCODE -ne 0) {
    throw "WSL export failed with exit code $LASTEXITCODE."
}

if (-not (Test-Path $WslBackupPath)) {
    throw 'WSL export returned success but the VHDX backup file is missing.'
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
    protectedVolumes = @($Policy.systemVolumes)
    windowsImageBackupRoot = $WindowsImageRoot
    wbadminBackupExitCode = $WbadminExitCode
    wbadminVersionsExitCode = $VersionsExitCode
    winReEnabled = [bool]$WinReEnabled
    restorePointAttempted = [bool]$RestorePointAttempted
    wsl = [ordered]@{
        distribution = $Distribution
        exportPath = $WslBackupPath
        bytes = $WslFile.Length
        sha256 = $WslHash.Hash
        format = 'vhdx'
    }
    safety = [ordered]@{
        destructiveRestoreAutomation = $false
        unregisterExistingDistribution = $false
        automaticDiskRecreation = $false
    }
}

$ManifestPath = Join-Path $MetadataDirectory 'backup-manifest.json'
$Manifest | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $ManifestPath

Write-Host '[OK] Windows image created and enumerated by wbadmin.' -ForegroundColor Green
Write-Host '[OK] WSL2 VHDX exported and SHA-256 recorded.' -ForegroundColor Green
Write-Host "[OK] Manifest: $ManifestPath" -ForegroundColor Green
Write-Host 'VERDICT: V7 GOLDEN BACKUP CREATED' -ForegroundColor Green
