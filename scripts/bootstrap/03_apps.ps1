[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Verify')]
    [string]$Mode = 'Apply'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$manifestPath = Join-Path $repoRoot 'manifests\winget\apps-core.json'
$nativeProcessModule = Join-Path $repoRoot 'scripts\core\native-process.psm1'
Import-Module $nativeProcessModule

$wingetCommand = Get-WpcNativeApplication -Name 'winget.exe'
if (-not $wingetCommand) {
    throw 'WinGet est introuvable. Ouvre Microsoft Store > Bibliothèque > App Installer, mets-le à jour, puis relance exactement la même commande.'
}
if (-not (Test-Path $manifestPath)) { throw "Manifest applications introuvable: $manifestPath" }

function Get-WingetPackageFact {
    param([Parameter(Mandatory)][string]$Id)

    $result = Invoke-WpcNativeCapture -FilePath $wingetCommand.Source -ArgumentList @('list', '--id', $Id, '--exact', '--accept-source-agreements', '--disable-interactivity') -SuppressErrorOutput
    $line = @($result.Text -split "`r?`n" | Where-Object { $_ -match [regex]::Escape($Id) } | Select-Object -First 1)
    return [pscustomobject]@{
        Installed = ($result.ExitCode -eq 0 -and $line.Count -gt 0)
        Evidence = if ($line.Count -gt 0) { [string]$line[0] } else { 'Identifiant exact absent de winget list.' }
    }
}

function Test-WingetIdResolved {
    param([Parameter(Mandatory)][string]$Id)

    $result = Invoke-WpcNativeCapture -FilePath $wingetCommand.Source -ArgumentList @('show', '--id', $Id, '--exact', '--source', 'winget', '--accept-source-agreements', '--disable-interactivity')
    return ($result.ExitCode -eq 0)
}

$manifest = Get-Content -Raw $manifestPath | ConvertFrom-Json
$automaticApps = @($manifest.apps | Where-Object { [bool]$_.autoInstall })

foreach ($app in $automaticApps) {
    if ([string]::IsNullOrWhiteSpace([string]$app.wingetId)) {
        throw "Manifest incohérent: $($app.name) est autoInstall=true mais wingetId est vide."
    }
}

if ($Mode -eq 'Apply') {
    Write-Host '[ANALYSE] Préflight WinGet: validation de tous les identifiants avant la première installation.' -ForegroundColor Cyan
    $unresolved = [System.Collections.Generic.List[string]]::new()
    foreach ($app in $automaticApps) {
        $id = [string]$app.wingetId
        if (-not (Test-WingetIdResolved -Id $id)) {
            $unresolved.Add("$($app.name) ($id)")
        }
    }
    if ($unresolved.Count -gt 0) {
        throw "Préflight WinGet échoué avant toute mutation: identifiants non résolus: $($unresolved -join '; '). Corrige le manifest ou les sources WinGet puis relance."
    }
    Write-Host "[OK] Préflight WinGet: $($automaticApps.Count) identifiant(s) résolu(s)." -ForegroundColor Green
}

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

    $resolved = if ($Mode -eq 'Apply') { $true } else { Test-WingetIdResolved -Id $id }
    if (-not $resolved) {
        $missing.Add("$name ($id) - ID WinGet non résolu")
        if ($Mode -eq 'Audit') {
            Write-Warning "Identifiant WinGet non résolu: $name [$id]"
        } else {
            Write-Host "[KO] Identifiant WinGet non résolu: $name [$id]" -ForegroundColor Red
        }
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
        Write-Host "[À FAIRE] $name [$id] nʼest pas détecté par WinGet." -ForegroundColor Yellow
        continue
    }
    if ($Mode -eq 'Verify') {
        Write-Host "[KO] $name [$id] absent." -ForegroundColor Red
        continue
    }

    Write-Host "[EN COURS] Installation: $name [$id]" -ForegroundColor Cyan
    & $wingetCommand.Source install --id $id --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    $installCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($installCode -ne 0) {
        throw "WinGet a échoué pour $name [$id] avec le code $installCode. Relance le script: les applications déjà installées seront ignorées."
    }
    $after = Get-WingetPackageFact -Id $id
    if (-not $after.Installed) {
        throw "Installation de $name terminée sans preuve WinGet exploitable. Aucune réussite nʼest déclarée sans vérification."
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
