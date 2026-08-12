[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Verify', 'Rollback')]
    [string]$Mode = 'Audit'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$manifestPath = Join-Path $repoRoot 'config\defender\exclusions.approved.json'
$stateDir = Join-Path $repoRoot 'state'
$statePath = Join-Path $stateDir 'defender-exclusions-backup.json'
if (-not (Test-Path $manifestPath)) { throw "Manifest absent: $manifestPath" }
$manifest = Get-Content -Raw $manifestPath | ConvertFrom-Json
$approved = @($manifest.paths)

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'PowerShell administrateur requis.' }
}

function Assert-SafeExclusionPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Exclusion vide refusée.' }
    if ($Path -match '[*?]') { throw "Wildcard refusé: $Path" }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path).TrimEnd('\\')
    if ($expanded -match '^[A-Za-z]:$') { throw "Racine de volume refusée: $Path" }
    if ($expanded -match '^\\\\[^\\]+\\[^\\]+$') { throw "Racine de partage refusée: $Path" }
    if ($expanded -match '\.(exe|dll|ps1|bat|cmd|msi)$') { throw "Fichier exécutable ou script refusé: $Path" }
    return $expanded
}

$safeApproved = @(foreach ($path in $approved) { Assert-SafeExclusionPath -Path ([string]$path) })
$current = @((Get-MpPreference).ExclusionPath)
$missing = @($safeApproved | Where-Object { $current -notcontains $_ })

if ($Mode -eq 'Audit') {
    Write-Host 'Exclusions Defender approuvées:' -ForegroundColor Cyan
    if ($safeApproved.Count -eq 0) { Write-Host '  aucune: Defender doit rester sans exclusion ajoutée par ce dépôt.' }
    foreach ($path in $safeApproved) {
        if ($current -contains $path) { Write-Host "[DÉJÀ OK] $path" -ForegroundColor Green }
        else { Write-Host "[À FAIRE] $path" -ForegroundColor Yellow }
    }
    if ($missing.Count -eq 0) { Write-Host '[DÉJÀ OK] Toutes les exclusions approuvées sont conformes.' -ForegroundColor Green }
    return
}

if ($Mode -eq 'Verify') {
    if ($missing.Count -gt 0) { throw "Exclusions Defender approuvées manquantes: $($missing -join ', ')" }
    Write-Host '[OK] Exclusions Defender approuvées vérifiées.' -ForegroundColor Green
    return
}

Assert-Administrator
if ($Mode -eq 'Apply') {
    if ($missing.Count -eq 0) {
        Write-Host '[DÉJÀ OK] Exclusions Defender déjà conformes; aucune préférence réécrite.' -ForegroundColor Green
        return
    }
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    if (Test-Path $statePath) {
        $existingState = Get-Content -Raw $statePath | ConvertFrom-Json
        $original = @($existingState.ExclusionPath)
        $previousManaged = if ($existingState.PSObject.Properties.Name -contains 'ManagedPaths') { @($existingState.ManagedPaths) } else { @() }
        $managed = @($previousManaged + $safeApproved | Sort-Object -Unique)
    } else {
        $original = $current
        $managed = $safeApproved
    }
    [ordered]@{ ExclusionPath=$original; ManagedPaths=$managed; RecordedAt=(Get-Date).ToString('o') } | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 $statePath
    foreach ($safePath in $missing) {
        Write-Host "[EN COURS] Ajout exclusion Defender ciblée: $safePath" -ForegroundColor Cyan
        Add-MpPreference -ExclusionPath $safePath
        $now = @((Get-MpPreference).ExclusionPath)
        if ($now -notcontains $safePath) { throw "Exclusion Defender non prouvée après ajout: $safePath" }
        Write-Host "[FAIT] Exclusion ajoutée et revalidée: $safePath" -ForegroundColor Green
    }
    & $PSCommandPath -Mode Verify
    return
}

if (-not (Test-Path $statePath)) {
    Write-Host '[DÉJÀ OK] Aucune exclusion gérée par le dépôt nʼa dʼétat de rollback.' -ForegroundColor Green
    return
}
$backup = Get-Content -Raw $statePath | ConvertFrom-Json
$original = @($backup.ExclusionPath)
$managed = if ($backup.PSObject.Properties.Name -contains 'ManagedPaths') { @($backup.ManagedPaths) } else { $safeApproved }
$current = @((Get-MpPreference).ExclusionPath)
$removed = 0
foreach ($path in $managed) {
    if ($original -notcontains $path -and $current -contains $path) {
        Remove-MpPreference -ExclusionPath $path
        $removed++
        Write-Host "[FAIT] Exclusion retirée: $path" -ForegroundColor Green
    }
}
if ($removed -eq 0) { Write-Host '[DÉJÀ OK] Aucune exclusion gérée nʼavait besoin dʼêtre retirée.' -ForegroundColor Green }
else { Write-Host '[FAIT] Rollback des exclusions gérées terminé.' -ForegroundColor Green }
