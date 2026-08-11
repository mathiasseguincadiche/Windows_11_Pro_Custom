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

if (-not (Test-Path $configSource)) { throw "Profil WSL introuvable: $configSource" }
if ((Get-Volume -DriveLetter D).FileSystem -ne 'NTFS') { throw 'D: doit rester NTFS.' }

New-Item -ItemType Directory -Force -Path (Split-Path $InstallLocation) | Out-Null
Copy-Item -Force $configSource $configTarget
Write-Host "[OK] Profil WSL installe: $Profile"

wsl.exe --update
if ($LASTEXITCODE -ne 0) { throw 'Echec de wsl --update.' }

wsl.exe --set-default-version 2
if ($LASTEXITCODE -ne 0) { throw 'Echec de wsl --set-default-version 2.' }

$installed = @(wsl.exe --list --quiet 2>$null) -replace "`0", ''
if ($installed -notcontains $Distribution) {
    Write-Host "Installation de $Distribution dans $InstallLocation"
    wsl.exe --install --distribution $Distribution --location $InstallLocation --no-launch
    if ($LASTEXITCODE -ne 0) {
        throw 'Installation WSL interrompue. Un redemarrage Windows peut etre requis avant de relancer le script.'
    }
} else {
    Write-Host "[OK] Distribution deja installee: $Distribution"
}

wsl.exe --shutdown
Write-Host '[OK] Configuration WSL appliquee. Aucun disque physique n a ete reformate.' -ForegroundColor Green
