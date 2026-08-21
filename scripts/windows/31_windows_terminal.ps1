[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Verify', 'Rollback')]
    [string]$Mode = 'Audit',

    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Distribution = 'Ubuntu'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modernScript = Join-Path $PSScriptRoot '31_windows_terminal_modern.ps1'
if (-not (Test-Path -LiteralPath $modernScript)) {
    throw "Moteur Windows Terminal moderne introuvable: $modernScript"
}

& $modernScript @PSBoundParameters
