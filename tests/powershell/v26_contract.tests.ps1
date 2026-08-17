[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Import-FunctionFromScript {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Name
    )
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        (Resolve-Path -LiteralPath $Path),
        [ref]$tokens,
        [ref]$errors
    )
    if (@($errors).Count -gt 0) { throw "PowerShell parse failed: $Path" }
    foreach ($functionName in $Name) {
        $definition = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
        }, $true) | Select-Object -First 1
        if ($null -eq $definition) { throw "Function $functionName not found in $Path" }
        Set-Item -Path "Function:global:$functionName" -Value $definition.Body.GetScriptBlock()
    }
}

$fingerprintScript = Join-Path $RepoRoot 'scripts\windows\90_workstation_fingerprint_v26.ps1'
Import-FunctionFromScript -Path $fingerprintScript -Name @(
    'Get-ComparableFingerprint',
    'ConvertTo-FlatFingerprintMap',
    'Get-FingerprintDifferences',
    'Get-WpcBaselineIntegrity',
    'Write-WpcBaselineWithHash'
)

$integrityRoot = Join-Path ([IO.Path]::GetTempPath()) "wpc-v26-integrity-$([guid]::NewGuid().ToString('N'))"
$integrityBaseline = Join-Path $integrityRoot 'workstation-fingerprint.json'
$integritySidecar = "$integrityBaseline.sha256"
try {
    $writtenHash = Write-WpcBaselineWithHash -Json '{"contractVersion":"V26"}' -BaselinePath $integrityBaseline -HashPath $integritySidecar
    $integrity = Get-WpcBaselineIntegrity -BaselinePath $integrityBaseline -HashPath $integritySidecar
    if ($integrity.Status -ne 'VERIFIED' -or $integrity.Sha256 -ne $writtenHash) {
        throw 'A newly written V26 baseline must have a verified SHA-256 sidecar.'
    }

    Add-Content -LiteralPath $integrityBaseline -Value 'tamper' -Encoding UTF8
    $tamperRejected = $false
    try {
        [void](Get-WpcBaselineIntegrity -BaselinePath $integrityBaseline -HashPath $integritySidecar)
    } catch {
        $tamperRejected = $_.Exception.Message -match 'Intégrité de baseline V26 invalide'
    }
    if (-not $tamperRejected) { throw 'A modified V26 baseline must be rejected.' }

    [void](Write-WpcBaselineWithHash -Json '{"contractVersion":"V26"}' -BaselinePath $integrityBaseline -HashPath $integritySidecar)
    Remove-Item -LiteralPath $integritySidecar -Force
    $legacyIntegrity = Get-WpcBaselineIntegrity -BaselinePath $integrityBaseline -HashPath $integritySidecar
    if ($legacyIntegrity.Status -ne 'LEGACY_UNVERIFIED') {
        throw 'A pre-sidecar V26 baseline must remain readable with an explicit legacy status.'
    }
} finally {
    Remove-Item -LiteralPath $integrityRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$baseline = [pscustomobject]@{
    contractVersion = 'V26'
    repositoryRevision = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    windows = [pscustomobject]@{ buildNumber = '1' }
    hardware = [pscustomobject]@{ cpu = @('fixture') }
    wsl = [pscustomobject]@{ version = '1' }
    storageIdentityV25Sha256 = 'storage'
    contractDigestSha256 = 'contract'
    contractFiles = @()
}
$actual = $baseline.PSObject.Copy()
$actual.repositoryRevision = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
$differences = @(Get-FingerprintDifferences -Expected $baseline -Actual $actual)
if ($differences.Count -ne 1 -or $differences[0].path -ne '$.repositoryRevision') {
    throw 'The V26 field-level diff did not isolate repositoryRevision.'
}
$legacyBaseline = $baseline | Select-Object -Property * -ExcludeProperty repositoryRevision
$legacyDifferences = @(Get-FingerprintDifferences -Expected $legacyBaseline -Actual $actual)
if ($legacyDifferences.Count -ne 1 -or $legacyDifferences[0].path -ne '$.repositoryRevision') {
    throw 'A pre-hardening V26 baseline must produce a controlled repositoryRevision drift, not a StrictMode failure.'
}

foreach ($relativePath in @(
    'scripts\backup\60_create_backup_v7.ps1',
    'scripts\backup\61_validate_backup_v7.ps1',
    'scripts\backup\63_restore_drill_v26.ps1'
)) {
    Import-FunctionFromScript -Path (Join-Path $RepoRoot $relativePath) -Name @('Get-WbadminVersionIdentifiers')
    $identifiers = @(Get-WbadminVersionIdentifiers -Lines @(
        'Version identifier: 08/17/2026-08:30',
        'Identificateur de version : 17/08/2026-09:45'
    ))
    if ($identifiers.Count -ne 2) {
        throw "The wbadmin identifier parser failed for $relativePath"
    }
}

$restoreDrillSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'scripts\backup\63_restore_drill_v26.ps1')
foreach ($requiredFragment in @(
    '$UnregisterExitCode = $LASTEXITCODE',
    '$RemainingNames -contains $TemporaryDistribution',
    'Copie scratch conservée'
)) {
    if (-not $restoreDrillSource.Contains($requiredFragment)) {
        throw "Restore drill cleanup contract missing: $requiredFragment"
    }
}

$backupSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'scripts\backup\60_create_backup_v7.ps1')
if (-not ($backupSource.Contains('$RestorePointExitCode = $LASTEXITCODE') -and $backupSource.Contains('restorePointExitCode = $RestorePointExitCode'))) {
    throw 'Golden Backup must capture and persist the restore-point exit code.'
}

Write-Host 'V26 contract self-tests: OK' -ForegroundColor Green
