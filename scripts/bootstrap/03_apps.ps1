[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$manifestPath = Join-Path $repoRoot 'manifests\winget\apps-core.json'

if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    throw 'WinGet est introuvable. Mettre a jour App Installer depuis Microsoft Store puis relancer.'
}

$manifest = Get-Content -Raw $manifestPath | ConvertFrom-Json
foreach ($app in $manifest.apps) {
    if (-not $app.autoInstall) {
        Write-Warning "Installation manuelle conservee pour: $($app.name)"
        continue
    }

    winget.exe show --id $app.wingetId --exact --source winget --accept-source-agreements *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Identifiant WinGet non resolu, installation ignoree: $($app.wingetId)"
        continue
    }

    Write-Host "Installation: $($app.name) [$($app.wingetId)]"
    winget.exe install --id $app.wingetId --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "WinGet a retourne un code non nul pour $($app.name)."
    }
}
