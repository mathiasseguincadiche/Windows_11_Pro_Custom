[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$violations = New-Object System.Collections.Generic.List[string]

foreach ($file in Get-ChildItem -LiteralPath $RepoRoot -Recurse -File | Where-Object { $_.Extension -in @('.ps1', '.psm1') }) {
    $content = Get-Content -Raw -LiteralPath $file.FullName
    $declarationPattern = '(?m)^\s*\$(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:New-Object\s+System\.Collections\.Generic\.List|\[System\.Collections\.Generic\.List[^\r\n]+\]::new\(\))'
    foreach ($match in [regex]::Matches($content, $declarationPattern)) {
        $name = $match.Groups['name'].Value
        if ($content -match ("@\(\$" + [regex]::Escape($name) + "\)")) {
            $violations.Add("$($file.FullName): generic List '$name' must use .ToArray(), not @(`$$name).")
        }
    }
}

if ($violations.Count -gt 0) {
    throw ($violations -join [Environment]::NewLine)
}

Write-Host 'Generic List conversion contract: OK' -ForegroundColor Green
