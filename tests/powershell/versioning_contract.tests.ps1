[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$versionPath = Join-Path $repoRoot 'VERSION'
if (-not (Test-Path -LiteralPath $versionPath)) { throw 'VERSION file is required.' }
$release = (Get-Content -Raw -LiteralPath $versionPath).Trim()
if ($release -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION must be SemVer x.y.z, observed=$release" }

$canonicalPaths = @(
    'scripts\bootstrap\00_storage_identity.ps1',
    'scripts\bootstrap\00_storage_integrity.ps1',
    'tests\powershell\storage_contract.tests.ps1',
    'tests\regression\menu_process_isolation.tests.ps1',
    '.github\workflows\storage-identity.yml',
    '.github\workflows\storage-safety.yml',
    '.github\workflows\menu-process-isolation.yml',
    '.github\workflows\orchestration.yml',
    'config\orchestration\policy.json'
)
foreach ($relative in $canonicalPaths) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relative))) {
        throw "Canonical versioning path missing: $relative"
    }
}

$runtime = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'scripts\core\runtime.psm1')
if ($runtime -match "Version\s*=\s*'V\d+") { throw 'Runtime must not expose a legacy Vxx product version.' }
foreach ($required in @('Get-WpcProjectRelease', 'Release=$Context.Release', 'SchemaVersion=1')) {
    if (-not $runtime.Contains($required)) { throw "Runtime release contract missing: $required" }
}

$machineState = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'scripts\bootstrap\01_machine_state.ps1')
if ($machineState -match "Version\s*=\s*'V\d+") { throw 'Machine-state report must not expose a legacy Vxx product version.' }
if (-not $machineState.Contains('Release = $context.Release')) { throw 'Machine-state report must use the global release.' }
if (-not $machineState.Contains('SchemaVersion = 1')) { throw 'Machine-state report schema must be explicit.' }

$preflight = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'scripts\bootstrap\00_preflight.ps1')
foreach ($legacyCall in @('00_storage_integrity_v24.ps1', '00_storage_identity_v25.ps1')) {
    if ($preflight.Contains($legacyCall)) { throw "Preflight must not call legacy component path: $legacyCall" }
}
if ($preflight -match '(?m)^.*\[ANALYSE\].*\bV\d+\b') { throw 'Preflight user output must not expose milestone Vxx labels.' }

$wsl = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'scripts\bootstrap\06_wsl.ps1')
if ($wsl.Contains('00_storage_identity_v25.ps1')) { throw 'WSL must use canonical storage identity path.' }
if ($wsl -match '(?m)^.*Write-Host.*\bV25\b') { throw 'WSL user output must not expose the old storage milestone.' }

$policy = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'config\orchestration\policy.json') | ConvertFrom-Json
if ([int]$policy.schemaVersion -ne 1) { throw 'Orchestration policy SchemaVersion must be 1.' }
if ([string]$policy.releaseSource -ne 'VERSION') { throw 'Orchestration policy must use VERSION as release source.' }

$legacyWrappers = @(
    'scripts\bootstrap\00_storage_integrity_v24.ps1',
    'scripts\bootstrap\00_storage_identity_v25.ps1'
)
foreach ($relative in $legacyWrappers) {
    $path = Join-Path $repoRoot $relative
    if (-not (Test-Path -LiteralPath $path)) { throw "Expected transition wrapper missing: $relative" }
    $text = Get-Content -Raw -LiteralPath $path
    if (-not $text.Contains('Chemin historique détecté')) { throw "Legacy path is not an explicit compatibility wrapper: $relative" }
}

$activeWorkflowNames = @(
    'storage-identity.yml',
    'storage-safety.yml',
    'menu-process-isolation.yml',
    'orchestration.yml'
)
foreach ($name in $activeWorkflowNames) {
    if ($name -match '-v\d+\.yml$') { throw "Active workflow name contains legacy milestone: $name" }
    $text = Get-Content -Raw -LiteralPath (Join-Path $repoRoot ".github\workflows\$name")
    $firstLine = ($text -split "`r?`n")[0]
    if ($firstLine -match '\bV\d+\b') { throw "Active workflow display name contains legacy milestone: $firstLine" }
}

Write-Host "[OK] Version globale: $release" -ForegroundColor Green
Write-Host '[OK] Release produit séparée des SchemaVersion de données.' -ForegroundColor Green
Write-Host '[OK] Composants actifs migrés sans jalons Vxx.' -ForegroundColor Green
Write-Host '[OK] Wrappers historiques explicitement isolés.' -ForegroundColor Green
