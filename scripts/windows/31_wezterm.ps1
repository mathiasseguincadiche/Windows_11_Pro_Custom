[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Verify', 'Rollback')]
    [string]$Mode = 'Audit'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$source = Join-Path $repoRoot 'config\wezterm\wezterm.lua'
$target = Join-Path $env:USERPROFILE '.wezterm.lua'
$stateDir = Join-Path $repoRoot 'state\wezterm'
$stateMeta = Join-Path $stateDir 'state.json'
$backup = Join-Path $stateDir 'wezterm.before.lua'

if (-not (Test-Path $source)) { throw "Configuration WezTerm absente: $source" }

function Test-WezTermConfigMatch {
    if (-not (Test-Path $target)) { return $false }
    return (Get-FileHash $source -Algorithm SHA256).Hash -eq (Get-FileHash $target -Algorithm SHA256).Hash
}

$wezterm = Get-Command wezterm.exe -ErrorAction SilentlyContinue
$match = Test-WezTermConfigMatch

if ($Mode -eq 'Audit') {
    Write-Host "WezTerm CLI: $(if ($wezterm) { $wezterm.Source } else { 'ABSENT' })"
    Write-Host "Configuration cible: $target"
    Write-Host "Configuration conforme: $match"
    if ($wezterm -and $match) {
        Write-Host '[DÉJÀ OK] WezTerm est installé et sa configuration est conforme.' -ForegroundColor Green
    } else {
        Write-Host '[À FAIRE] WezTerm nécessite une installation et/ou une mise en conformité de la configuration.' -ForegroundColor Yellow
    }
    return
}

if ($Mode -eq 'Verify') {
    if (-not $wezterm) { throw 'WezTerm est absent ou wezterm.exe est introuvable.' }
    if (-not $match) { throw '.wezterm.lua est absent ou différent de la configuration du dépôt.' }
    Write-Host '[OK] WezTerm validé: application présente et configuration conforme.' -ForegroundColor Green
    return
}

if ($Mode -eq 'Apply') {
    if (-not $wezterm) { throw 'WezTerm est absent. Le bootstrap applications doit dʼabord installer wez.wezterm.' }
    if ($match) {
        Write-Host '[DÉJÀ OK] WezTerm est déjà conforme; aucun fichier réécrit.' -ForegroundColor Green
        return
    }
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    if (-not (Test-Path $stateMeta)) {
        $existed = Test-Path $target
        if ($existed) { Copy-Item -Force $target $backup }
        @{ ConfigExisted=$existed; RecordedAt=(Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -Encoding utf8 $stateMeta
        Write-Host "[OK] État initial WezTerm sauvegardé: $stateMeta"
    }
    Copy-Item -Force $source $target
    if (-not (Test-WezTermConfigMatch)) { throw 'Échec de revalidation .wezterm.lua après copie.' }
    Write-Host '[FAIT] WezTerm configuré et hash revalidé.' -ForegroundColor Green
    return
}

if (-not (Test-Path $stateMeta)) {
    Write-Host '[DÉJÀ OK] Aucun état initial WezTerm géré par le dépôt; rollback inutile.' -ForegroundColor Green
    return
}
$state = Get-Content -Raw $stateMeta | ConvertFrom-Json
if ($state.ConfigExisted) {
    if (-not (Test-Path $backup)) { throw 'Sauvegarde WezTerm absente.' }
    Copy-Item -Force $backup $target
} else {
    Remove-Item -Force $target -ErrorAction SilentlyContinue
}
Write-Host '[FAIT] Configuration WezTerm restaurée à lʼétat initial enregistré.' -ForegroundColor Green
