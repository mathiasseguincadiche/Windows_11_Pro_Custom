[CmdletBinding()]
param(
    [ValidateSet('standard', 'lab-heavy', 'nat-fallback')]
    [string]$WslProfile = 'standard',
    [string]$Distribution = 'Ubuntu',
    [string]$InstallLocation = 'E:\WSL\Ubuntu-DevOps'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$release = (Get-Content -Raw (Join-Path $repoRoot 'VERSION')).Trim()
if ($release -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION invalide: $release" }
$reportDir = Join-Path $repoRoot 'reports'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$checks = [ordered]@{}
$details = [ordered]@{}

$os = Get-CimInstance Win32_OperatingSystem
$editionId = [string](Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID -ErrorAction Stop)
$checks.Windows11 = ($os.Caption -match 'Windows 11')
$checks.Windows11SupportedEdition = ($checks.Windows11 -and $editionId -notmatch '^Core')
$details.Windows = $os.Caption
$details.WindowsEditionId = $editionId
$details.WindowsHomeEdition = ($editionId -match '^Core')
$cVolume = Get-Volume -DriveLetter C
$eVolume = Get-Volume -DriveLetter E
$checks.C_NTFS = ($cVolume.FileSystem -eq 'NTFS')
$checks.E_NTFS = ($eVolume.FileSystem -eq 'NTFS')
$details.C_FileSystem = $cVolume.FileSystem
$details.E_FileSystem = $eVolume.FileSystem

$defender = Get-MpComputerStatus
$checks.DefenderRealtime = [bool]$defender.RealTimeProtectionEnabled
$checks.DefenderAntivirus = [bool]$defender.AntivirusEnabled
$currentExclusions = @((Get-MpPreference).ExclusionPath)
$dangerousRoots = @($currentExclusions | Where-Object { $_ -match '^[CcDdEe]:\\?$' })
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

$terminalScript = Join-Path $repoRoot 'scripts\windows\31_windows_terminal.ps1'
$checks.WindowsTerminalDevOps = $false
try {
    & $terminalScript -Mode Verify -Distribution $Distribution | Out-Host
    $checks.WindowsTerminalDevOps = $true
    $details.WindowsTerminal = 'Contrat Windows Terminal DevOps validé par le composant propriétaire.'
} catch { $details.WindowsTerminal = $_.Exception.Message }

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
$report = [ordered]@{ Release=$release; SchemaVersion=1; Timestamp=(Get-Date).ToString('o'); Profile=$WslProfile; Distribution=$Distribution; InstallLocation=$InstallLocation; Checks=$checks; FailedChecks=$failed; Details=$details }
$reportPath = Join-Path $reportDir 'validation-windows.json'
$report | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 $reportPath
foreach ($check in $checks.GetEnumerator()) { Write-Host ("[{0}] {1}" -f $(if ($check.Value) { 'OK' } else { 'KO' }), $check.Key) }
if ($failed.Count -gt 0) { Write-Host "VERDICT: WINDOWS KO ($($failed.Count) contrôle(s))" -ForegroundColor Red; throw "Windows non conforme: $($failed -join ', '). Rapport: $reportPath" }
Write-Host "VERDICT: WINDOWS 11 NON-HOME READY ($editionId)" -ForegroundColor Green
Write-Host "Rapport: $reportPath"
