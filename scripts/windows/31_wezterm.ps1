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

if ($Mode -eq 'Audit') {
    $wezterm = Get-Command wezterm.exe -ErrorAction SilentlyContinue
    Write-Host "WezTerm CLI: $(if ($wezterm) { $wezterm.Source } else { 'ABSENT' })"
    Write-Host "Configuration cible: $target"
    Write-Host "Configuration présente: $(Test-Path $target)"
    return
}

if ($Mode -eq 'Apply') {
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    if (-not (Test-Path $stateMeta)) {
        $existed = Test-Path $target
        if ($existed) { Copy-Item -Force $target $backup }
        @{ ConfigExisted = $existed } | ConvertTo-Json | Set-Content -Encoding utf8 $stateMeta
    }
    Copy-Item -Force $source $target
    Write-Host '[OK] WezTerm configuré pour ouvrir Ubuntu WSL par défaut.' -ForegroundColor Green
    return
}

if ($Mode -eq 'Verify') {
    if (-not (Test-Path $target)) { throw '.wezterm.lua absent.' }
    if ((Get-FileHash $source -Algorithm SHA256).Hash -ne (Get-FileHash $target -Algorithm SHA256).Hash) {
        throw '.wezterm.lua diffère de la configuration V3.'
    }
    Write-Host '[OK] WezTerm V3 validé.' -ForegroundColor Green
    return
}

if (-not (Test-Path $stateMeta)) { throw "État WezTerm absent: $stateMeta" }
$state = Get-Content -Raw $stateMeta | ConvertFrom-Json
if ($state.ConfigExisted) {
    if (-not (Test-Path $backup)) { throw 'Sauvegarde WezTerm absente.' }
    Copy-Item -Force $backup $target
} else {
    Remove-Item -Force $target -ErrorAction SilentlyContinue
}
Write-Host '[OK] Configuration WezTerm restaurée.' -ForegroundColor Green
