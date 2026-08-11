[CmdletBinding()]
param(
    [string]$Distribution = 'Ubuntu'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$source = Join-Path $repoRoot 'config\wsl\wsl.conf'

if (-not (Test-Path $source)) { throw 'config/wsl/wsl.conf introuvable.' }
Get-Content -Raw $source | wsl.exe --distribution $Distribution --user root -- sh -c 'cat > /etc/wsl.conf'
if ($LASTEXITCODE -ne 0) { throw 'Impossible d ecrire /etc/wsl.conf.' }
wsl.exe --shutdown
Write-Host '[OK] /etc/wsl.conf applique.' -ForegroundColor Green
