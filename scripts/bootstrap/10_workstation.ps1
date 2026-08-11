[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Verify', 'Rollback')]
    [string]$Mode = 'Audit'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path

& "$repoRoot\scripts\windows\30_vscode.ps1" -Mode $Mode
& "$repoRoot\scripts\windows\31_wezterm.ps1" -Mode $Mode

Write-Host "[OK] Poste de travail: $Mode terminé." -ForegroundColor Green
