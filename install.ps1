[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply')]
    [string]$Mode = 'Audit',

    [ValidateSet('standard', 'lab-heavy', 'nat-fallback')]
    [string]$WslProfile = 'standard'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = $PSScriptRoot

Write-Host "Windows 11 Pro Custom - mode: $Mode" -ForegroundColor Cyan

& "$RepoRoot\scripts\bootstrap\00_preflight.ps1"

if ($Mode -eq 'Apply') {
    & "$RepoRoot\scripts\bootstrap\06_wsl.ps1" -Profile $WslProfile
}

& "$RepoRoot\scripts\bootstrap\05_defender.ps1"
& "$RepoRoot\scripts\bootstrap\07_validate.ps1"

Write-Host 'Termine. Consultez les rapports dans reports/.' -ForegroundColor Green
