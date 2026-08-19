[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Record', 'Verify')]
    [string]$Mode = 'Audit',
    [string]$BaselinePath = '',
    [switch]$ConfirmHealthyTopology,
    [switch]$ReplaceBaseline
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$canonical = Join-Path $PSScriptRoot '00_storage_identity.ps1'
Write-Warning 'Chemin historique détecté. Utilise désormais scripts\bootstrap\00_storage_identity.ps1.'
& $canonical @PSBoundParameters
