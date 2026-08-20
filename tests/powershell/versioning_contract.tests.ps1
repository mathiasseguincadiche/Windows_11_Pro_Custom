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
    'config\backup\policy.json',
    'config\hardware\target.json',
    'config\hardware\symbiosis.json',
    'config\updates\policy.json',
    'config\windows\optimization\standard.json',
    'config\windows\responsiveness.json',
    'scripts\backup\60_create_backup.ps1',
    'scripts\backup\61_validate_backup.ps1',
    'scripts\backup\62_restore_plan.ps1',
    'scripts\backup\63_restore_drill.ps1',
    'scripts\bootstrap\00_storage_identity.ps1',
    'scripts\bootstrap\00_storage_integrity.ps1',
    'scripts\bootstrap\11_validate_windows.ps1',
    'scripts\bootstrap\12_validate_optimization.ps1',
    'scripts\bootstrap\13_validate_hardware.ps1',
    'scripts\bootstrap\14_validate_wsl.ps1',
    'scripts\windows\40_optimize.ps1',
    'scripts\windows\53_responsiveness.ps1',
    'scripts\windows\90_workstation_fingerprint.ps1',
    'tests\powershell\storage_contract.tests.ps1',
    'tests\powershell\workstation_evidence_contract.tests.ps1',
    'tests\regression\menu_process_isolation.tests.ps1',
    '.github\workflows\storage-identity.yml',
    '.github\workflows\storage-safety.yml',
    '.github\workflows\menu-process-isolation.yml',
    '.github\workflows\workstation-evidence.yml',
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

$forbiddenLegacyPaths = @(
    'scripts\bootstrap\00_storage_integrity_v24.ps1',
    'scripts\bootstrap\00_storage_identity_v25.ps1',
    'tests\powershell\v26_contract.tests.ps1',
    'scripts\backup\60_create_backup_v7.ps1',
    'scripts\backup\61_validate_backup_v7.ps1',
    'scripts\backup\62_restore_plan_v7.ps1',
    'scripts\backup\63_restore_drill_v26.ps1',
    'scripts\bootstrap\11_validate_v3.ps1',
    'scripts\bootstrap\12_validate_v4.ps1',
    'scripts\bootstrap\13_validate_hardware_v5.ps1',
    'scripts\bootstrap\14_validate_wsl_v6.ps1',
    'scripts\windows\40_v4_optimize.ps1',
    'scripts\windows\53_responsiveness_v8.ps1',
    'scripts\windows\90_workstation_fingerprint_v26.ps1',
    'config\backup\v7-policy.json',
    'config\hardware\target-v5.json',
    'config\hardware\symbiosis-v5.json',
    'config\updates\v11.json',
    'config\windows\v4',
    'config\windows\v8'
)
foreach ($relative in $forbiddenLegacyPaths) {
    if (Test-Path -LiteralPath (Join-Path $repoRoot $relative)) {
        throw "Legacy milestone path must not remain in the active tree: $relative"
    }
}

$activeRoots = @(
    (Join-Path $repoRoot 'scripts'),
    (Join-Path $repoRoot 'config'),
    (Join-Path $repoRoot 'tests'),
    (Join-Path $repoRoot '.github\workflows')
)
$milestoneNamePattern = '(?i)(?:^|[_-])v\d+(?:[_\.-]|$)'
$pathViolations = @(
    foreach ($root in $activeRoots) {
        Get-ChildItem -LiteralPath $root -Recurse -Force | Where-Object {
            $_.Name -match $milestoneNamePattern
        } | ForEach-Object { $_.FullName.Substring($repoRoot.Length + 1) }
    }
)
if ($pathViolations.Count -gt 0) {
    throw "Active file/directory names contain legacy milestones: $($pathViolations -join ', ')"
}

$workflowFiles = Get-ChildItem -LiteralPath (Join-Path $repoRoot '.github\workflows') -Filter '*.yml' -File
foreach ($workflow in $workflowFiles) {
    $firstLine = (Get-Content -LiteralPath $workflow.FullName -TotalCount 1)
    if ($firstLine -match '\bV\d+\b') {
        throw "Active workflow display name contains legacy milestone: $($workflow.Name): $firstLine"
    }
}

Write-Host "[OK] Version globale: $release" -ForegroundColor Green
Write-Host '[OK] Release produit séparée des SchemaVersion de données.' -ForegroundColor Green
Write-Host '[OK] Composants actifs sans jalons Vxx dans leurs noms.' -ForegroundColor Green
Write-Host '[OK] Workflows actifs sans jalons Vxx dans leurs noms affichés.' -ForegroundColor Green
