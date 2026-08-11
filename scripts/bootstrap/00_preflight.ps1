[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$reportDir = Join-Path $repoRoot 'reports'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$os = Get-CimInstance Win32_OperatingSystem
$computer = Get-CimInstance Win32_ComputerSystem
$volumes = Get-Volume | Where-Object DriveLetter | Select-Object DriveLetter, FileSystem, HealthStatus, SizeRemaining, Size

$result = [ordered]@{
    Timestamp = (Get-Date).ToString('o')
    IsAdministrator = $isAdmin
    Caption = $os.Caption
    Version = $os.Version
    BuildNumber = $os.BuildNumber
    TotalMemoryGB = [math]::Round($computer.TotalPhysicalMemory / 1GB, 2)
    Volumes = $volumes
}

$result | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 (Join-Path $reportDir 'preflight.json')

if (-not $isAdmin) {
    throw 'PowerShell doit etre lance en administrateur.'
}

if ($os.Caption -notmatch 'Windows 11') {
    throw "OS non supporte par ce profil: $($os.Caption)"
}

$c = Get-Volume -DriveLetter C -ErrorAction Stop
$d = Get-Volume -DriveLetter D -ErrorAction Stop

if ($c.FileSystem -ne 'NTFS') { throw 'C: doit etre NTFS.' }
if ($d.FileSystem -ne 'NTFS') { throw 'D: doit etre NTFS. Aucun EXT4 physique n est attendu.' }

Write-Host '[OK] Preflight Windows 11 / C: NTFS / D: NTFS' -ForegroundColor Green
