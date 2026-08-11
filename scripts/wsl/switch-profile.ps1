[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('standard', 'lab-heavy', 'nat-fallback')]
    [string]$Profile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$source = Join-Path $repoRoot "config\wsl\$Profile.wslconfig"
$target = Join-Path $env:USERPROFILE '.wslconfig'
Copy-Item -Force $source $target
wsl.exe --shutdown
Write-Host "[OK] Profil WSL actif: $Profile" -ForegroundColor Green
