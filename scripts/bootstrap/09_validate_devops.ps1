[CmdletBinding()]
param(
    [string]$Distribution = 'Ubuntu'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$windowsScript = Join-Path $repoRoot 'scripts\wsl\validate-devops.sh'

if (-not (Test-Path $windowsScript)) { throw "Script absent: $windowsScript" }
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'wsl.exe introuvable.' }

$installed = @((wsl.exe --list --quiet 2>$null) -replace "`0", '')
if ($installed -notcontains $Distribution) { throw "Distribution WSL absente: $Distribution" }

$linuxScript = (& wsl.exe --distribution $Distribution --exec wslpath -a -u $windowsScript).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($linuxScript)) {
    throw 'Impossible de convertir le chemin du validateur DevOps avec wslpath.'
}

& wsl.exe --distribution $Distribution --exec bash $linuxScript
if ($LASTEXITCODE -ne 0) { throw 'Validation de la stack DevOps en échec.' }

Write-Host '[OK] Stack DevOps WSL validée.' -ForegroundColor Green
