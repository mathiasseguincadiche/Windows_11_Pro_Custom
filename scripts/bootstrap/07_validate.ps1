[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$reportDir = Join-Path $repoRoot 'reports'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

$checks = [ordered]@{}
$checks.Windows11 = ((Get-CimInstance Win32_OperatingSystem).Caption -match 'Windows 11')
$checks.C_NTFS = ((Get-Volume -DriveLetter C).FileSystem -eq 'NTFS')
$checks.D_NTFS = ((Get-Volume -DriveLetter D).FileSystem -eq 'NTFS')
$checks.WslConfigExists = Test-Path (Join-Path $env:USERPROFILE '.wslconfig')
$checks.DefenderRealtime = (Get-MpComputerStatus).RealTimeProtectionEnabled
$checks.WslCommand = [bool](Get-Command wsl.exe -ErrorAction SilentlyContinue)

$checks | ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $reportDir 'validation.json')

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value })
foreach ($check in $checks.GetEnumerator()) {
    $state = if ($check.Value) { 'OK' } else { 'KO' }
    Write-Host ("[{0}] {1}" -f $state, $check.Key)
}

if ($failed.Count -gt 0) {
    Write-Warning "$($failed.Count) controle(s) non valide(s). Voir reports\validation.json"
} else {
    Write-Host '[OK] Validation de la fondation V1.' -ForegroundColor Green
}
