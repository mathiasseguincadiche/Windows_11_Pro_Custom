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

    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Exclusion vide refusée.' }
    if ($Path -match '[*?]') { throw "Wildcard refusé: $Path" }

    $expanded = [Environment]::ExpandEnvironmentVariables($Path).TrimEnd('\\')
    if ($expanded -match '^[A-Za-z]:$') { throw "Racine de volume refusée: $Path" }
    if ($expanded -match '^\\\\[^\\]+\\[^\\]+$') { throw "Racine de partage refusée: $Path" }
    if ($expanded -match '\.(exe|dll|ps1|bat|cmd|msi)$') { throw "Exclusion de fichier exécutable/script refusée: $Path" }

    return $expanded
}

$current = @((Get-MpPreference).ExclusionPath)

if ($Mode -eq 'Audit') {
    Write-Host 'Exclusions Defender actuelles:' -ForegroundColor Cyan
    if ($current.Count -eq 0) { Write-Host '  aucune' } else { $current | ForEach-Object { Write-Host "  $_" } }
    Write-Host 'Exclusions approuvées par le dépôt:' -ForegroundColor Cyan
    if ($approved.Count -eq 0) { Write-Host '  aucune' } else { $approved | ForEach-Object { Write-Host "  $_" } }
    return
}

Assert-Administrator

if ($Mode -eq 'Apply') {
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    if (-not (Test-Path $statePath)) {
        @{ ExclusionPath = $current } | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 $statePath
    }

    foreach ($path in $approved) {
        $safePath = Assert-SafeExclusionPath -Path ([string]$path)
        if ($current -notcontains $safePath) {
            Add-MpPreference -ExclusionPath $safePath
            Write-Host "[OK] Exclusion ciblée ajoutée: $safePath"
        }
    }
    if ($approved.Count -eq 0) {
        Write-Host '[OK] Aucune exclusion approuvée: Defender reste sans exception ajoutée par ce dépôt.'
    }
    return
}

if (-not (Test-Path $statePath)) { throw "Sauvegarde absente: $statePath" }
$backup = Get-Content -Raw $statePath | ConvertFrom-Json
$original = @($backup.ExclusionPath)
$current = @((Get-MpPreference).ExclusionPath)

foreach ($path in $current) {
    if ($original -notcontains $path -and $approved -contains $path) {
        Remove-MpPreference -ExclusionPath $path
        Write-Host "[OK] Exclusion retirée: $path"
    }
}
Write-Host '[OK] Rollback des exclusions gérées par le dépôt terminé.' -ForegroundColor Green
