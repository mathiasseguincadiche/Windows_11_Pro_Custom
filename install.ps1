[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Verify', 'Rollback')]
    [string]$Mode = 'Audit',

    [ValidateSet('standard', 'lab-heavy', 'nat-fallback')]
    [string]$WslProfile = 'standard',

    [string]$Distribution = 'Ubuntu',
    [string]$WslInstallLocation = 'D:\WSL\Ubuntu-DevOps',

    [switch]$InstallDevOps,
    [switch]$ValidateDevOps
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = $PSScriptRoot

Write-Host "Windows 11 Pro Custom - mode: $Mode" -ForegroundColor Cyan

if ($Mode -eq 'Rollback') {
    & "$RepoRoot\scripts\bootstrap\10_workstation.ps1" -Mode Rollback
    & "$RepoRoot\scripts\windows\10_tune.ps1" -Mode Rollback
    & "$RepoRoot\scripts\defender\03_apply_approved_exclusions.ps1" -Mode Rollback
    Write-Host 'Rollback des réglages gérés par le dépôt terminé.' -ForegroundColor Green
    return
}

& "$RepoRoot\scripts\bootstrap\00_preflight.ps1"
& "$RepoRoot\scripts\windows\20_system_audit.ps1"
& "$RepoRoot\scripts\windows\21_storage_trim.ps1" -Mode Audit

switch ($Mode) {
    'Audit' {
        & "$RepoRoot\scripts\windows\10_tune.ps1" -Mode Audit
        & "$RepoRoot\scripts\bootstrap\10_workstation.ps1" -Mode Audit
        & "$RepoRoot\scripts\bootstrap\05_defender.ps1"
        & "$RepoRoot\scripts\defender\03_apply_approved_exclusions.ps1" -Mode Audit
    }
    'Apply' {
        & "$RepoRoot\scripts\bootstrap\03_apps.ps1"
        & "$RepoRoot\scripts\windows\10_tune.ps1" -Mode Apply
        & "$RepoRoot\scripts\bootstrap\06_wsl.ps1" -Profile $WslProfile -Distribution $Distribution -InstallLocation $WslInstallLocation
        & "$RepoRoot\scripts\bootstrap\10_workstation.ps1" -Mode Apply
        & "$RepoRoot\scripts\defender\03_apply_approved_exclusions.ps1" -Mode Apply

        if ($InstallDevOps) {
            & "$RepoRoot\scripts\bootstrap\08_devops.ps1" -Distribution $Distribution
        } else {
            Write-Host '[INFO] Stack DevOps non installée dans ce passage. Après le premier lancement Ubuntu, relance Apply avec -InstallDevOps.' -ForegroundColor Yellow
        }

        & "$RepoRoot\scripts\bootstrap\05_defender.ps1"
        & "$RepoRoot\scripts\bootstrap\11_validate_v3.ps1" -WslProfile $WslProfile -Distribution $Distribution -InstallLocation $WslInstallLocation
    }
    'Verify' {
        & "$RepoRoot\scripts\windows\10_tune.ps1" -Mode Verify
        & "$RepoRoot\scripts\bootstrap\10_workstation.ps1" -Mode Verify
        & "$RepoRoot\scripts\bootstrap\05_defender.ps1"
        & "$RepoRoot\scripts\bootstrap\11_validate_v3.ps1" -WslProfile $WslProfile -Distribution $Distribution -InstallLocation $WslInstallLocation
        if ($ValidateDevOps) {
            & "$RepoRoot\scripts\bootstrap\09_validate_devops.ps1" -Distribution $Distribution
        } else {
            Write-Host '[INFO] Validation Linux complète non demandée. Utilise -ValidateDevOps après installation de la stack.' -ForegroundColor Yellow
        }
    }
}

Write-Host 'Terminé. Consulte les rapports dans reports/.' -ForegroundColor Green
