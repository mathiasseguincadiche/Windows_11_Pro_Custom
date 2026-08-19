[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $RepoRoot 'scripts\bootstrap\00_storage_integrity_v24.ps1'

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path -LiteralPath $scriptPath),
    [ref]$tokens,
    [ref]$errors
)

if (@($errors).Count -gt 0) {
    throw "V24 PowerShell parse failed: $($errors.Message -join '; ')"
}

$assignments = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
    $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
    $node.Left.VariablePath.UserPath -eq 'requiredVolumeLetters'
}, $true))

if ($assignments.Count -ne 1) {
    throw 'V24 must define requiredVolumeLetters exactly once.'
}

$normalizedContract = $assignments[0].Right.Extent.Text -replace '\s', ''
if ($normalizedContract -ne "@('C','E')") {
    throw "Unexpected V24 required volume contract: $normalizedContract"
}

$loops = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.ForEachStatementAst] -and
    $node.Variable.VariablePath.UserPath -eq 'letter'
}, $true))

if ($loops.Count -ne 1) {
    throw 'V24 must contain exactly one volume iteration loop.'
}

if ($loops[0].Condition.Extent.Text.Trim() -ne '$requiredVolumeLetters') {
    throw 'V24 runtime loop must derive from requiredVolumeLetters.'
}

$source = Get-Content -Raw -LiteralPath $scriptPath
if ($source -notmatch 'RequiredVolumes\s*=\s*@\(\s*\$requiredVolumeLetters\s*\|') {
    throw 'V24 Policy.RequiredVolumes must derive from requiredVolumeLetters.'
}

if ($source -match "foreach\s*\(\s*\`$letter\s+in\s+@\(\s*'C'\s*,\s*'D'\s*\)\s*\)") {
    throw 'Legacy C/D runtime loop detected in V24.'
}

# Regression V28: MSFT_Volume.HealthStatus may be adapted by PowerShell as the
# enum label "Healthy" instead of the underlying UInt16 value 0. Extract and
# execute only the pure helper so this contract is tested without touching disks.
$healthFunctions = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Test-WpcVolumeHealthHealthy'
}, $true))

if ($healthFunctions.Count -ne 1) {
    throw 'V24 must define Test-WpcVolumeHealthHealthy exactly once.'
}

$healthHelper = [scriptblock]::Create($healthFunctions[0].Extent.Text)
. $healthHelper

if (-not (Test-WpcVolumeHealthHealthy -HealthStatus 'Healthy')) {
    throw 'V24 must accept the CIM enum label Healthy.'
}
if (-not (Test-WpcVolumeHealthHealthy -HealthStatus 0)) {
    throw 'V24 must accept the numeric MSFT_Volume Healthy code 0.'
}
foreach ($unsafeHealth in @('Scan Needed', 'Spot Fix Needed', 'Full Repair Needed', '1', '2', '3', 'Unknown')) {
    if (Test-WpcVolumeHealthHealthy -HealthStatus $unsafeHealth) {
        throw "V24 incorrectly accepted unsafe volume health status: $unsafeHealth"
    }
}

if ($source.Contains('[uint16]$msftVolume.HealthStatus')) {
    throw 'Regression detected: V24 must not cast an enum label such as Healthy directly to UInt16.'
}

# Get-StorageReliabilityCounter exposes a provider-dependent set of properties.
# Missing fields are capability gaps, not evidence of media failure. They must
# remain visible as warnings while non-zero reported uncorrected errors still block.
$counterVariables = @('readTotal', 'writeTotal', 'readUncorrected', 'writeUncorrected')
foreach ($variable in $counterVariables) {
    $advisoryNeedle = 'if ($null -eq $' + $variable + ') { $warnings +='
    $blockingNeedle = 'if ($null -eq $' + $variable + ') { $reasons +='
    if (-not $source.Contains($advisoryNeedle)) {
        throw "V24 must classify missing $variable as advisory provider capability."
    }
    if ($source.Contains($blockingNeedle)) {
        throw "V24 must not classify missing $variable as a storage failure."
    }
}

foreach ($variable in @('readUncorrected', 'writeUncorrected')) {
    $nonZeroNeedle = 'elseif ($' + $variable + ' -gt 0) { $reasons +='
    if (-not $source.Contains($nonZeroNeedle)) {
        throw "V24 must still block when reported $variable is greater than zero."
    }
}

if (-not $source.Contains('UnavailableErrorCountersAreAdvisory = $true')) {
    throw 'V24 report policy must disclose capability-aware reliability handling.'
}
if (-not $source.Contains('UncorrectedErrorsMustBeZeroWhenReported = $true')) {
    throw 'V24 report policy must preserve the fail-closed rule for reported uncorrected errors.'
}

Write-Host 'Storage V24 C/E + capability-aware telemetry contract self-test: OK' -ForegroundColor Green
