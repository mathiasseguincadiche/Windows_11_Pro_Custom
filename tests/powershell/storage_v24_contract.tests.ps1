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

Write-Host 'Storage V24 C/E contract self-test: OK' -ForegroundColor Green
