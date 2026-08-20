[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Backslash = [char]92
$Slash = [char]47

function Get-RelativeRepoPath {
    param([Parameter(Mandatory)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetFullPath($RepoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    return $full.Substring($root.Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar).Replace($Backslash,$Slash)
}

function ConvertTo-ForwardSlashPath {
    param([Parameter(Mandatory)][string]$Path)
    return $Path.Replace($Backslash,$Slash)
}

# P0: le contrôle stockage doit consommer uniquement la politique matérielle canonique.
$storageScriptPath = Join-Path $RepoRoot 'scripts\bootstrap\00_storage_integrity.ps1'
$canonicalPolicyPath = Join-Path $RepoRoot 'config\hardware\symbiosis.json'
if (-not (Test-Path -LiteralPath $storageScriptPath)) { throw 'Storage integrity script missing.' }
if (-not (Test-Path -LiteralPath $canonicalPolicyPath)) { throw 'Canonical hardware symbiosis policy missing: config/hardware/symbiosis.json' }
$storageSource = Get-Content -Raw -LiteralPath $storageScriptPath
$quote = [char]39
$expectedStoragePolicyAssignment = '$storagePolicyPath = Join-Path $repoRoot ' + $quote + 'config\hardware\symbiosis.json' + $quote
if (-not $storageSource.Contains($expectedStoragePolicyAssignment)) {
    throw '00_storage_integrity.ps1 must assign storagePolicyPath to config\hardware\symbiosis.json.'
}
if ($storageSource.Contains('config\hardware\symbiosis-v5.json') -or $storageSource.Contains('config/hardware/symbiosis-v5.json')) {
    throw 'Legacy symbiosis-v5.json reference detected in storage integrity.'
}

# P0: aucun ancien chemin de composant ne doit rester dans le code actif.
# Les tests de versioning/documentation qui contiennent volontairement la liste noire sont exclus.
$forbiddenLegacyPaths = @(
    '00_storage_identity_v25.ps1',
    '00_storage_integrity_v24.ps1',
    '90_workstation_fingerprint_v26.ps1',
    '63_restore_drill_v26.ps1',
    '60_create_backup_v7.ps1',
    '61_validate_backup_v7.ps1',
    '62_restore_plan_v7.ps1',
    '11_validate_v3.ps1',
    '12_validate_v4.ps1',
    '13_validate_hardware_v5.ps1',
    '14_validate_wsl_v6.ps1',
    '40_v4_optimize.ps1',
    '53_responsiveness_v8.ps1',
    'config/backup/v7-policy.json',
    'config/hardware/target-v5.json',
    'config/hardware/symbiosis-v5.json',
    'config/updates/v11.json',
    'config/windows/v4/',
    'config/windows/v8/',
    'tests/powershell/v26_contract.tests.ps1',
    'SkipV4RestorePoint'
)

$activeCodeFiles = New-Object System.Collections.Generic.List[System.IO.FileInfo]
foreach ($entryPoint in @('install.ps1','menu.ps1','update.ps1')) {
    $activeCodeFiles.Add((Get-Item -LiteralPath (Join-Path $RepoRoot $entryPoint)))
}
Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'scripts') -Recurse -File |
    Where-Object { $_.Extension -in @('.ps1','.psm1','.sh') } |
    ForEach-Object { $activeCodeFiles.Add($_) }

$workflowExclusions = @('documentation.yml','versioning-contract.yml','repository-integrity.yml')
Get-ChildItem -LiteralPath (Join-Path $RepoRoot '.github\workflows') -Filter '*.yml' -File |
    Where-Object { $_.Name -notin $workflowExclusions } |
    ForEach-Object { $activeCodeFiles.Add($_) }

$legacyViolations = New-Object System.Collections.Generic.List[string]
foreach ($file in $activeCodeFiles) {
    $normalizedText = ConvertTo-ForwardSlashPath -Path (Get-Content -Raw -LiteralPath $file.FullName)
    foreach ($legacy in $forbiddenLegacyPaths) {
        $normalizedLegacy = ConvertTo-ForwardSlashPath -Path $legacy
        if ($normalizedText.Contains($normalizedLegacy)) {
            $legacyViolations.Add("$(Get-RelativeRepoPath -Path $file.FullName): référence obsolète: $legacy")
        }
    }
}
if ($legacyViolations.Count -gt 0) {
    throw ('Legacy active-path regression detected:' + [Environment]::NewLine + ($legacyViolations -join [Environment]::NewLine))
}

# P1: vérifier les dépendances statiques versionnées référencées par le code exécutable.
# Les chemins dynamiques contenant des variables restent couverts par leurs contrats spécifiques.
$runtimePowerShellFiles = @(
    (Get-Item -LiteralPath (Join-Path $RepoRoot 'install.ps1')),
    (Get-Item -LiteralPath (Join-Path $RepoRoot 'menu.ps1')),
    (Get-Item -LiteralPath (Join-Path $RepoRoot 'update.ps1'))
) + @(
    Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'scripts') -Recurse -File |
        Where-Object { $_.Extension -in @('.ps1','.psm1') }
)

$dependencyPattern = '(?i)(?<path>(?:config|scripts|manifests)[\\/][A-Za-z0-9._-]+(?:[\\/][A-Za-z0-9._-]+)*\.(?:ps1|psm1|sh|json|toml|wslconfig|txt))'
$missingDependencies = New-Object System.Collections.Generic.List[string]
foreach ($file in $runtimePowerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        throw "PowerShell parse error while checking dependencies in $(Get-RelativeRepoPath -Path $file.FullName): $($parseErrors.Message -join '; ')"
    }
    $stringNodes = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
        $node -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
    },$true))
    foreach ($node in $stringNodes) {
        $value = if ($node.PSObject.Properties.Name -contains 'Value') { [string]$node.Value } else { [string]$node.Extent.Text }
        foreach ($match in [regex]::Matches($value,$dependencyPattern)) {
            $relative = $match.Groups['path'].Value.Replace($Slash,$Backslash)
            $candidate = Join-Path $RepoRoot $relative
            if (-not (Test-Path -LiteralPath $candidate)) {
                $missingDependencies.Add("$(Get-RelativeRepoPath -Path $file.FullName) -> $(ConvertTo-ForwardSlashPath -Path $relative)")
            }
        }
    }
}
if ($missingDependencies.Count -gt 0) {
    $unique = @($missingDependencies | Sort-Object -Unique)
    throw ('Missing static repository dependencies detected:' + [Environment]::NewLine + ($unique -join [Environment]::NewLine))
}

# P1: le centre de contrôle doit remonter le contexte d'échec produit par l'orchestrateur.
$menuSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'menu.ps1')
foreach ($requiredFragment in @(
    'Get-WpcLatestFailureContext',
    'Format-WpcProcessFailure',
    'reports\orchestration\latest-run.json',
    'LatestScriptState',
    'Étape   :',
    'Script  :',
    'Cause   :',
    'Journal :'
)) {
    if (-not $menuSource.Contains($requiredFragment)) {
        throw "Control-center detailed failure contract missing: $requiredFragment"
    }
}

Write-Host '[OK] storagePolicyPath -> config/hardware/symbiosis.json' -ForegroundColor Green
Write-Host '[OK] aucun ancien chemin de composant dans le code actif' -ForegroundColor Green
Write-Host '[OK] dépendances statiques versionnées présentes' -ForegroundColor Green
Write-Host '[OK] contexte d’échec détaillé disponible dans le centre de contrôle' -ForegroundColor Green
Write-Host 'VERDICT: REPOSITORY INTEGRITY READY' -ForegroundColor Green
