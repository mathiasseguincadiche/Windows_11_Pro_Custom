[CmdletBinding()]
param(
    [string]$Description = 'Windows_11_Pro_Custom V4 before optimization'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Restore point creation requires an elevated PowerShell session.'
}

if (-not (Get-Command Checkpoint-Computer -ErrorAction SilentlyContinue)) {
    Write-Warning 'Checkpoint-Computer is unavailable. Registry backups remain the primary rollback mechanism.'
    return
}

try {
    $systemDrive = "$($env:SystemDrive)\"
    if (Get-Command Enable-ComputerRestore -ErrorAction SilentlyContinue) {
        Enable-ComputerRestore -Drive $systemDrive -ErrorAction SilentlyContinue
    }
    Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS
    Write-Host '[OK] Windows restore point created before V4 optimization.' -ForegroundColor Green
} catch {
    Write-Warning "Restore point creation failed: $($_.Exception.Message)"
    Write-Warning 'V4 will still preserve per-profile Registry and service state for rollback.'
}
