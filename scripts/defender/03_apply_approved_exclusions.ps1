[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Rollback')]
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
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'PowerShell administrateur requis.'
    }
}

function Assert-SafeExclusionPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Exclusion vide refusee.' }
    if ($Path -match '[*?]') { throw "Wildcard refuse: $Path" }

    $expanded = [Environment]::ExpandEnvironmentVariables($Path).TrimEnd('\\')
    if ($expanded -match '^[A-Za-z]:$') { throw "Racine de volume refusee: $Path" }
    if ($expanded -match '^\\\\[^\\]+\\[^\\]+$') { throw "Racine de partage refusee: $Path" }
    if ($expanded -match '\.(exe|dll|ps1|bat|cmd|msi)$') { throw "Fichier executable ou script refuse: $Path" }

    return $expanded
}

$safeApproved = @(
    foreach ($path in $approved) {
        Assert-SafeExclusionPath -Path ([string]$path)
    }
)

$current = @((Get-MpPreference).ExclusionPath)

if ($Mode -eq 'Audit') {
    Write-Host 'Exclusions Defender actuelles:' -ForegroundColor Cyan
    if ($current.Count -eq 0) { Write-Host '  aucune' } else { $current | ForEach-Object { Write-Host "  $_" } }
    Write-Host 'Exclusions approuvees par le depot:' -ForegroundColor Cyan
    if ($safeApproved.Count -eq 0) { Write-Host '  aucune' } else { $safeApproved | ForEach-Object { Write-Host "  $_" } }
    return
}

Assert-Administrator

if ($Mode -eq 'Apply') {
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

    if (Test-Path $statePath) {
        $existingState = Get-Content -Raw $statePath | ConvertFrom-Json
        $original = @($existingState.ExclusionPath)
        $previousManaged = @()
        if ($existingState.PSObject.Properties.Name -contains 'ManagedPaths') {
            $previousManaged = @($existingState.ManagedPaths)
        }
        $managed = @($previousManaged + $safeApproved | Sort-Object -Unique)
    } else {
        $original = $current
        $managed = $safeApproved
    }

    [ordered]@{
        ExclusionPath = $original
        ManagedPaths = $managed
    } | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 $statePath

    foreach ($safePath in $safeApproved) {
        if ($current -notcontains $safePath) {
            Add-MpPreference -ExclusionPath $safePath
            Write-Host "[OK] Exclusion ciblee ajoutee: $safePath"
        }
    }

    if ($safeApproved.Count -eq 0) {
        Write-Host '[OK] Aucune exclusion approuvee. Defender reste sans exception ajoutee par ce depot.'
    }
    return
}

if (-not (Test-Path $statePath)) { throw "Sauvegarde absente: $statePath" }
$backup = Get-Content -Raw $statePath | ConvertFrom-Json
$original = @($backup.ExclusionPath)
$managed = if ($backup.PSObject.Properties.Name -contains 'ManagedPaths') {
    @($backup.ManagedPaths)
} else {
    $safeApproved
}
$current = @((Get-MpPreference).ExclusionPath)

foreach ($path in $managed) {
    if ($original -notcontains $path -and $current -contains $path) {
        Remove-MpPreference -ExclusionPath $path
        Write-Host "[OK] Exclusion retiree: $path"
    }
}
Write-Host '[OK] Rollback des exclusions gerees par le depot termine.' -ForegroundColor Green
