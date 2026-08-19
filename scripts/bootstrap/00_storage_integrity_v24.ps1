[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Verify')]
    [string]$Mode = 'Audit'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$canonical = Join-Path $PSScriptRoot '00_storage_integrity.ps1'
Write-Warning 'Chemin historique détecté. Utilise désormais scripts\bootstrap\00_storage_integrity.ps1.'
& $canonical @PSBoundParameters
