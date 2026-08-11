[CmdletBinding()]
param(
    [ValidateSet('standard', 'lab-heavy', 'nat-fallback')]
    [string]$Profile = 'standard',
    [string]$Distribution = 'Ubuntu',
    [string]$InstallLocation = 'D:\WSL\Ubuntu-DevOps'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$configSource = Join-Path $repoRoot "config\wsl\$Profile.wslconfig"
$configTarget = Join-Path $env:USERPROFILE '.wslconfig'

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'wsl.exe est introuvable.' }
if (-not (Test-Path $configSource)) { throw "Profil WSL introuvable: $configSource" }
if ((Get-Volume -DriveLetter D).FileSystem -ne 'NTFS') { throw 'D: doit rester NTFS.' }

New-Item -ItemType Directory -Force -Path (Split-Path $InstallLocation) | Out-Null
Copy-Item -Force $configSource $configTarget
Write-Host "[OK] Profil WSL installe: $Profile"

$installed = @((wsl.exe --list --quiet 2>$null) -replace "`0", '')
if ($installed -notcontains $Distribution) {
    Write-Host "Installation de $Distribution dans $InstallLocation"
    wsl.exe --install --distribution $Distribution --location $InstallLocation --no-launch
    if ($LASTEXITCODE -ne 0) {
        throw 'Installation WSL interrompue. Si Windows demande un redemarrage, redemarrer puis relancer ce script.'
    }
} else {
    Write-Host "[OK] Distribution deja installee: $Distribution"
}

wsl.exe --set-default-version 2
if ($LASTEXITCODE -ne 0) { throw 'Echec de wsl --set-default-version 2.' }

wsl.exe --update
if ($LASTEXITCODE -ne 0) { Write-Warning 'wsl --update a retourne un code non nul.' }

wsl.exe --shutdown
Write-Host '[OK] WSL2 configure. C: et D: restent NTFS.' -ForegroundColor Green
