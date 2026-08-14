[CmdletBinding()]
param(
    [ValidateSet('standard', 'lab-heavy', 'nat-fallback')]
    [string]$WslProfile = 'standard',
    [string]$Distribution = 'Ubuntu',
    [string]$InstallLocation = 'D:\WSL\Ubuntu-DevOps'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$reportDir = Join-Path $repoRoot 'reports'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$checks = [ordered]@{}
$details = [ordered]@{}

$os = Get-CimInstance Win32_OperatingSystem
$editionId = [string](Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID -ErrorAction Stop)
$checks.Windows11 = ($os.Caption -match 'Windows 11')
$checks.Windows11Pro = ($checks.Windows11 -and $editionId -eq 'Professional')
$details.Windows = $os.Caption
$details.WindowsEditionId = $editionId
$cVolume = Get-Volume -DriveLetter C
$dVolume = Get-Volume -DriveLetter D
$checks.C_NTFS = ($cVolume.FileSystem -eq 'NTFS')
$checks.D_NTFS = ($dVolume.FileSystem -eq 'NTFS')
$details.C_FileSystem = $cVolume.FileSystem
$details.D_FileSystem = $dVolume.FileSystem

$defender = Get-MpComputerStatus
$checks.DefenderRealtime = [bool]$defender.RealTimeProtectionEnabled
$checks.DefenderAntivirus = [bool]$defender.AntivirusEnabled
$currentExclusions = @((Get-MpPreference).ExclusionPath)
$dangerousRoots = @($currentExclusions | Where-Object { $_ -match '^[CcDd]:\\?$' })
$checks.DefenderNoDriveRootExclusions = ($dangerousRoots.Count -eq 0)
$details.DefenderExclusionPath = $currentExclusions

$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
$checks.WslCommand = [bool]$wsl
$wslTarget = Join-Path $env:USERPROFILE '.wslconfig'
$wslSource = Join-Path $repoRoot "config\wsl\$WslProfile.wslconfig"
$checks.WslConfigExists = Test-Path $wslTarget
$checks.WslProfileMatches = $false
if ((Test-Path $wslTarget) -and (Test-Path $wslSource)) { $checks.WslProfileMatches = ((Get-FileHash $wslTarget -Algorithm SHA256).Hash -eq (Get-FileHash $wslSource -Algorithm SHA256).Hash) }

$distros = @()
if ($wsl) { $distros = @((wsl.exe --list --quiet 2>$null) -replace "`0", '' | ForEach-Object { $_.Trim() } | Where-Object { $_ }); $global:LASTEXITCODE=0 }
$checks.WslDistribution = ($distros -contains $Distribution)
$details.WslDistributions = $distros
$checks.WslInstallLocation = Test-Path $InstallLocation
$vhdx = @()
if (Test-Path $InstallLocation) { $vhdx = @(Get-ChildItem -Path $InstallLocation -Filter '*.vhdx' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName) }
$checks.WslVhdxOnDataSSD = ($vhdx.Count -gt 0)
$details.WslVhdx = $vhdx

$vscodeSource = Join-Path $repoRoot 'config\vscode\settings.json'
$vscodeTarget = Join-Path $env:APPDATA 'Code\User\settings.json'
$checks.VSCodeSettings = $false
if ((Test-Path $vscodeSource) -and (Test-Path $vscodeTarget)) { $checks.VSCodeSettings = ((Get-FileHash $vscodeSource -Algorithm SHA256).Hash -eq (Get-FileHash $vscodeTarget -Algorithm SHA256).Hash) }
$weztermSource = Join-Path $repoRoot 'config\wezterm\wezterm.lua'
$weztermTarget = Join-Path $env:USERPROFILE '.wezterm.lua'
$checks.WezTermConfig = $false
if ((Test-Path $weztermSource) -and (Test-Path $weztermTarget)) { $checks.WezTermConfig = ((Get-FileHash $weztermSource -Algorithm SHA256).Hash -eq (Get-FileHash $weztermTarget -Algorithm SHA256).Hash) }

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
$report = [ordered]@{ Timestamp=(Get-Date).ToString('o'); Profile=$WslProfile; Distribution=$Distribution; InstallLocation=$InstallLocation; Checks=$checks; FailedChecks=$failed; Details=$details }
$reportPath = Join-Path $reportDir 'validation-v3.json'
$report | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 $reportPath
foreach ($check in $checks.GetEnumerator()) { Write-Host ("[{0}] {1}" -f $(if ($check.Value) { 'OK' } else { 'KO' }), $check.Key) }
if ($failed.Count -gt 0) {
    Write-Host "VERDICT: WINDOWS KO ($($failed.Count) contrôle(s))" -ForegroundColor Red
    throw "Windows non conforme: $($failed -join ', '). Rapport: $reportPath"
}
Write-Host 'VERDICT: WINDOWS 11 PRO READY' -ForegroundColor Green
Write-Host "Rapport: $reportPath"
