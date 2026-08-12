[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Verify')]
    [string]$Mode = 'Apply'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$manifestPath = Join-Path $repoRoot 'manifests\winget\apps-core.json'

if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    throw 'WinGet est introuvable. Ouvre Microsoft Store > Bibliothèque > App Installer, mets-le à jour, puis relance exactement la même commande.'
}
if (-not (Test-Path $manifestPath)) { throw "Manifest applications introuvable: $manifestPath" }

function Get-WingetPackageFact {
    param([Parameter(Mandatory)][string]$Id)

    $text = (& winget.exe list --id $Id --exact --accept-source-agreements --disable-interactivity 2>$null | Out-String)
    $code = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    $line = @($text -split "`r?`n" | Where-Object { $_ -match [regex]::Escape($Id) } | Select-Object -First 1)
    return [pscustomobject]@{
        Installed = ($code -eq 0 -and $line.Count -gt 0)
        Evidence = if ($line.Count -gt 0) { [string]$line[0] } else { 'Identifiant exact absent de winget list.' }
    }
}

$manifest = Get-Content -Raw $manifestPath | ConvertFrom-Json
$missing = [System.Collections.Generic.List[string]]::new()
$manual = [System.Collections.Generic.List[string]]::new()
$changed = [System.Collections.Generic.List[string]]::new()
$already = [System.Collections.Generic.List[string]]::new()

foreach ($app in @($manifest.apps)) {
    $name = [string]$app.name
    $id = [string]$app.wingetId
    if (-not [bool]$app.autoInstall) {
        $manual.Add($name)
        Write-Host "[ACTION REQUISE] $name : installation volontairement manuelle (autoInstall=false)."
        continue
    }
    if ([string]::IsNullOrWhiteSpace($id)) {
        throw "Manifest incohérent: $name est autoInstall=true mais wingetId est vide."
    }

    & winget.exe show --id $id --exact --source winget --accept-source-agreements *> $null
    $showCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($showCode -ne 0) {
        if ($Mode -eq 'Verify') { $missing.Add("$name ($id) - ID WinGet non résolu") }
        else { Write-Warning "Identifiant WinGet non résolu: $name [$id]" }
        continue
    }

    $fact = Get-WingetPackageFact -Id $id
    if ($fact.Installed) {
        $already.Add($name)
        Write-Host "[DÉJÀ OK] $name [$id] | preuve WinGet: $($fact.Evidence)" -ForegroundColor Green
        continue
    }

    $missing.Add("$name ($id)")
    if ($Mode -eq 'Audit') {
        Write-Host "[À FAIRE] $name [$id] n’est pas détecté par WinGet." -ForegroundColor Yellow
        continue
    }
    if ($Mode -eq 'Verify') {
        Write-Host "[KO] $name [$id] absent." -ForegroundColor Red
        continue
    }

    Write-Host "[EN COURS] Installation: $name [$id]" -ForegroundColor Cyan
    & winget.exe install --id $id --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    $installCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($installCode -ne 0) {
        throw "WinGet a échoué pour $name [$id] avec le code $installCode. Relance le script: les applications déjà installées seront ignorées."
    }
    $after = Get-WingetPackageFact -Id $id
    if (-not $after.Installed) {
        throw "Installation de $name terminée sans preuve WinGet exploitable. Aucune réussite n’est déclarée sans vérification."
    }
    $changed.Add($name)
    Write-Host "[FAIT] $name installé et revalidé par WinGet." -ForegroundColor Green
}

if ($Mode -eq 'Verify' -and $missing.Count -gt 0) {
    throw "Applications automatiques incomplètes: $($missing -join '; ')"
}

Write-Host ''
Write-Host ("Applications automatiques: déjà OK={0} | installées maintenant={1} | manquantes={2} | manuelles={3}" -f $already.Count, $changed.Count, $(if ($Mode -eq 'Apply') { 0 } else { $missing.Count }), $manual.Count)
if ($manual.Count -gt 0) {
    Write-Host "[ACTION REQUISE] Applications manuelles à décider: $($manual -join ', ')" -ForegroundColor Magenta
}
if ($Mode -eq 'Apply' -and $changed.Count -eq 0) {
    Write-Host '[DÉJÀ OK] Toutes les applications automatiques détectables sont déjà installées; aucune installation relancée.' -ForegroundColor Green
} elseif ($Mode -eq 'Apply') {
    Write-Host '[FAIT] Bootstrap applications terminé; chaque installation a été revalidée.' -ForegroundColor Green
} elseif ($Mode -eq 'Verify') {
    Write-Host '[OK] Toutes les applications automatiques sont présentes.' -ForegroundColor Green
}
