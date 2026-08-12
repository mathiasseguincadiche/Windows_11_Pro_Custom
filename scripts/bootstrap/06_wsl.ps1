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
$runtimeContractPath = Join-Path $repoRoot 'config\wsl\runtime-contract.json'
$swapDir = 'D:\WSL\swap'

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'wsl.exe est introuvable.' }
if (-not (Test-Path $configSource)) { throw "Profil WSL introuvable: $configSource" }
if (-not (Test-Path $runtimeContractPath)) { throw "Contrat runtime WSL absent: $runtimeContractPath" }

$runtimeContract = Get-Content -Raw $runtimeContractPath | ConvertFrom-Json
$expectedDistribution = [string]$runtimeContract.distribution
$expectedVersionId = [string]$runtimeContract.expectedVersionId
$expectedCodename = [string]$runtimeContract.expectedCodename
$expectedInstallLocation = [string]$runtimeContract.installLocation

if ($Distribution -ne $expectedDistribution) {
    throw "Distribution non conforme au contrat WSL. Demandée=$Distribution Attendue=$expectedDistribution"
}
if ([System.IO.Path]::GetFullPath($InstallLocation).TrimEnd('\') -ne [System.IO.Path]::GetFullPath($expectedInstallLocation).TrimEnd('\')) {
    throw "Emplacement WSL non conforme. Demandé=$InstallLocation Attendu=$expectedInstallLocation"
}

$dVolume = Get-Volume -DriveLetter D -ErrorAction Stop
if ($dVolume.FileSystem -ne 'NTFS') { throw 'D: doit rester NTFS.' }
if ($dVolume.SizeRemaining -lt 50GB) { throw "D: dispose de moins de 50 Go libres. Libérer de l’espace avant l’installation WSL." }

New-Item -ItemType Directory -Force -Path (Split-Path $InstallLocation) | Out-Null
New-Item -ItemType Directory -Force -Path $swapDir | Out-Null

Write-Host '[INFO] Mise à jour de WSL vers la version Store actuelle...'
wsl.exe --update
if ($LASTEXITCODE -ne 0) { Write-Warning 'wsl --update a retourné un code non nul. Vérifier Microsoft Store / Windows Update.' }

wsl.exe --set-default-version 2
if ($LASTEXITCODE -ne 0) { throw 'Échec de wsl --set-default-version 2.' }

Copy-Item -Force $configSource $configTarget
Write-Host "[OK] Profil WSL installé: $Profile -> $configTarget"
Write-Host "[OK] Swap WSL dédié: $swapDir"

$installed = @((wsl.exe --list --quiet 2>$null) -replace "`0", '')
if ($installed -notcontains $Distribution) {
    Write-Host "Installation de $Distribution dans $InstallLocation"
    wsl.exe --install --distribution $Distribution --location $InstallLocation --no-launch
    if ($LASTEXITCODE -ne 0) {
        throw 'Installation WSL interrompue. Si Windows demande un redémarrage, redémarrer puis relancer ce script.'
    }
} else {
    Write-Host "[OK] Distribution déjà installée: $Distribution"
}

function Invoke-WslRootValue {
    param([Parameter(Mandatory)][string]$Command)
    $value = (& wsl.exe -d $Distribution -u root -- bash -lc $Command 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Impossible de qualifier la distribution $Distribution après installation.`n$value"
    }
    return $value
}

$versionId = Invoke-WslRootValue ". /etc/os-release; printf '%s' \"`$VERSION_ID\""
$codename = Invoke-WslRootValue ". /etc/os-release; printf '%s' \"`$VERSION_CODENAME\""
if ($versionId -ne $expectedVersionId -or $codename -ne $expectedCodename) {
    throw "Release Ubuntu non conforme: VERSION_ID=$versionId CODENAME=$codename ; attendu $expectedVersionId/$expectedCodename. Aucune suppression automatique n'est effectuée. Corriger/importer la distribution puis relancer."
}
Write-Host "[OK] Contrat Ubuntu validé: $Distribution $versionId ($codename)" -ForegroundColor Green

wsl.exe --shutdown
Write-Host '[OK] WSL2 configuré. C: et D: restent NTFS.' -ForegroundColor Green
Write-Host "[INFO] Après modification d’un profil, toujours utiliser: wsl --shutdown" -ForegroundColor Yellow
