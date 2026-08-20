[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Release = (Get-Content -Raw (Join-Path $RepoRoot 'VERSION')).Trim()

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

$fingerprintScript = Join-Path $RepoRoot 'scripts\windows\90_workstation_fingerprint.ps1'
Import-FunctionFromScript -Path $fingerprintScript -Name @(
    'Get-PropertyValueCompat',
    'Get-ComparableFingerprint',
    'ConvertTo-FlatFingerprintMap',
    'Get-FingerprintDifferences',
    'Get-WpcBaselineIntegrity',
    'Write-WpcBaselineWithHash'
)

$integrityRoot = Join-Path ([IO.Path]::GetTempPath()) "wpc-workstation-integrity-$([guid]::NewGuid().ToString('N'))"
$integrityBaseline = Join-Path $integrityRoot 'workstation-fingerprint.json'
$integritySidecar = "$integrityBaseline.sha256"
try {
    $canonicalJson = @{ Release=$Release; SchemaVersion=1 } | ConvertTo-Json -Compress
    $writtenHash = Write-WpcBaselineWithHash -Json $canonicalJson -BaselinePath $integrityBaseline -HashPath $integritySidecar
    $integrity = Get-WpcBaselineIntegrity -BaselinePath $integrityBaseline -HashPath $integritySidecar
    if ($integrity.Status -ne 'VERIFIED' -or $integrity.Sha256 -ne $writtenHash) {
        throw 'A newly written workstation baseline must have a verified SHA-256 sidecar.'
    }

    Add-Content -LiteralPath $integrityBaseline -Value 'tamper' -Encoding UTF8
    $tamperRejected = $false
    try {
        [void](Get-WpcBaselineIntegrity -BaselinePath $integrityBaseline -HashPath $integritySidecar)
    } catch {
        $tamperRejected = $_.Exception.Message -match 'Intégrité de baseline workstation invalide'
    }
    if (-not $tamperRejected) { throw 'A modified workstation baseline must be rejected.' }

    [void](Write-WpcBaselineWithHash -Json $canonicalJson -BaselinePath $integrityBaseline -HashPath $integritySidecar)
    Remove-Item -LiteralPath $integritySidecar -Force
    $legacyIntegrity = Get-WpcBaselineIntegrity -BaselinePath $integrityBaseline -HashPath $integritySidecar
    if ($legacyIntegrity.Status -ne 'LEGACY_UNVERIFIED') {
        throw 'A pre-sidecar workstation baseline must remain readable with an explicit legacy status.'
    }
} finally {
    Remove-Item -LiteralPath $integrityRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$baseline = [pscustomobject]@{
    Release = $Release
    SchemaVersion = 1
    repositoryRevision = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    windows = [pscustomobject]@{ buildNumber = '1' }
    hardware = [pscustomobject]@{ cpu = @('fixture') }
    wsl = [pscustomobject]@{ version = '1' }
    storageIdentitySha256 = 'storage'
    contractDigestSha256 = 'contract'
    contractFiles = @()
}
$actual = $baseline.PSObject.Copy()
$actual.repositoryRevision = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
$differences = @(Get-FingerprintDifferences -Expected $baseline -Actual $actual)
if ($differences.Count -ne 1 -or $differences[0].path -ne '$.repositoryRevision') {
    throw 'The canonical field-level diff did not isolate repositoryRevision.'
}

# Compatibilité de lecture : une empreinte historique peut encore utiliser
# storageIdentityV25Sha256. Le numéro historique n'entre jamais dans le diff produit.
$legacyBaseline = [pscustomobject]@{
    contractVersion = 'V26'
    repositoryRevision = $baseline.repositoryRevision
    windows = $baseline.windows
    hardware = $baseline.hardware
    wsl = $baseline.wsl
    storageIdentityV25Sha256 = 'storage'
    contractDigestSha256 = 'contract'
    contractFiles = @()
}
$legacyComparable = Get-ComparableFingerprint -Fingerprint $legacyBaseline
if ($legacyComparable.storageIdentitySha256 -ne 'storage') {
    throw 'Legacy storage identity field was not normalized.'
}
$legacyDifferences = @(Get-FingerprintDifferences -Expected $legacyBaseline -Actual $baseline)
if ($legacyDifferences.Count -ne 0) {
    throw "Legacy schema normalization introduced artificial drift: $($legacyDifferences.path -join ', ')"
}

foreach ($relativePath in @(
    'scripts\backup\60_create_backup.ps1',
    'scripts\backup\61_validate_backup.ps1',
    'scripts\backup\63_restore_drill.ps1'
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

$restoreDrillSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'scripts\backup\63_restore_drill.ps1')
foreach ($requiredFragment in @(
    '$UnregisterExitCode=$LASTEXITCODE',
    '$RemainingNames -contains $TemporaryDistribution',
    'Copie scratch conservée'
)) {
    if (-not $restoreDrillSource.Contains($requiredFragment)) {
        throw "Restore drill cleanup contract missing: $requiredFragment"
    }
}

$backupSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'scripts\backup\60_create_backup.ps1')
if (-not ($backupSource.Contains('$RestorePointExitCode=$LASTEXITCODE') -and $backupSource.Contains('restorePointExitCode=$RestorePointExitCode'))) {
    throw 'Golden Backup must capture and persist the restore-point exit code.'
}

Write-Host 'Workstation evidence contract self-tests: OK' -ForegroundColor Green
