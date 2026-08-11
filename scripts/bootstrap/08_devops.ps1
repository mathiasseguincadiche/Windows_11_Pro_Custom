[CmdletBinding()]
param(
    [string]$Distribution = 'Ubuntu'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$windowsScript = Join-Path $repoRoot 'scripts\wsl\install-devops.sh'

if (-not (Test-Path $windowsScript)) { throw "Script absent: $windowsScript" }
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'wsl.exe introuvable.' }

$installed = @((wsl.exe --list --quiet 2>$null) -replace "`0", '')
if ($installed -notcontains $Distribution) {
    throw "Distribution WSL absente: $Distribution. Exécute d'abord scripts/bootstrap/06_wsl.ps1."
}

$linuxScript = (& wsl.exe --distribution $Distribution --exec wslpath -a -u $windowsScript).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($linuxScript)) {
    throw 'Impossible de convertir le chemin du bootstrap DevOps avec wslpath.'
}

Write-Host "Installation de la stack DevOps dans $Distribution" -ForegroundColor Cyan
& wsl.exe --distribution $Distribution --exec bash $linuxScript
if ($LASTEXITCODE -ne 0) { throw 'Le bootstrap DevOps WSL a échoué.' }

Write-Host '[INFO] Ferme ensuite WSL avec wsl --shutdown pour appliquer le groupe docker.' -ForegroundColor Yellow
