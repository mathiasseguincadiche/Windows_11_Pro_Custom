[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Verify', 'Rollback')]
    [string]$Mode = 'Audit',

    [ValidateSet('standard', 'lab-heavy', 'nat-fallback')]
    [string]$WslProfile = 'standard',

    [ValidateSet('standard', 'privacy', 'gaming', 'optional')]
    [string[]]$OptimizationProfiles = @('standard'),

    [string]$Distribution = 'Ubuntu',
    [string]$WslInstallLocation = 'D:\WSL\Ubuntu-DevOps',

    [switch]$InstallDevOps,
    [switch]$ValidateDevOps,
    [switch]$ValidateWsl,
    [switch]$ValidateHardware,
    [switch]$SkipV4RestorePoint,

    [ValidateSet('None', 'Create', 'Verify', 'RestorePlan')]
    [string]$BackupAction = 'None',
    [string]$BackupTargetDrive,
    [switch]$AllowNonUsbBackupTarget,
    [switch]$SkipBackupRestorePoint
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = $PSScriptRoot

if ($BackupAction -ne 'None') {
    if ([string]::IsNullOrWhiteSpace($BackupTargetDrive) -or $BackupTargetDrive -notmatch '^[A-Za-z]:$') {
        throw 'V7 backup actions require -BackupTargetDrive with a drive letter such as E:.'
    }

    Write-Host "Windows 11 Pro Custom - V7 backup action: $BackupAction" -ForegroundColor Cyan
    Write-Host "Backup target: $BackupTargetDrive" -ForegroundColor Cyan

    switch ($BackupAction) {
        'Create' {
            $backupParameters = @{
                BackupTargetDrive = $BackupTargetDrive
                Distribution = $Distribution
            }
            if ($AllowNonUsbBackupTarget) {
                $backupParameters.AllowNonUsbTarget = $true
            }
            if ($SkipBackupRestorePoint) {
                $backupParameters.SkipRestorePoint = $true
            }
            & "$RepoRoot\scripts\backup\60_create_backup_v7.ps1" @backupParameters
        }
        'Verify' {
            & "$RepoRoot\scripts\backup\61_validate_backup_v7.ps1" -BackupTargetDrive $BackupTargetDrive
        }
        'RestorePlan' {
            & "$RepoRoot\scripts\backup\62_restore_plan_v7.ps1" -BackupTargetDrive $BackupTargetDrive
        }
    }

    return
}

Write-Host "Windows 11 Pro Custom - mode: $Mode" -ForegroundColor Cyan
Write-Host "WSL2 profile: $WslProfile" -ForegroundColor Cyan
Write-Host "V4 optimization profiles: $($OptimizationProfiles -join ', ')" -ForegroundColor Cyan

if ($Mode -eq 'Rollback') {
    & "$RepoRoot\scripts\bootstrap\10_workstation.ps1" -Mode Rollback

    $profilesToRollback = @($OptimizationProfiles)
    if (-not $PSBoundParameters.ContainsKey('OptimizationProfiles')) {
        $profilesToRollback = @('optional', 'gaming', 'privacy', 'standard') | Where-Object {
            Test-Path (Join-Path $RepoRoot "state\windows-v4\${_}.before.json")
        }
    } else {
        [array]::Reverse($profilesToRollback)
    }

    foreach ($profile in $profilesToRollback) {
        & "$RepoRoot\scripts\windows\40_v4_optimize.ps1" -Mode Rollback -Profile $profile
    }

    & "$RepoRoot\scripts\windows\10_tune.ps1" -Mode Rollback
    & "$RepoRoot\scripts\defender\03_apply_approved_exclusions.ps1" -Mode Rollback
    Write-Host 'Rollback of repository-managed settings completed.' -ForegroundColor Green
    return
}

& "$RepoRoot\scripts\bootstrap\00_preflight.ps1"
& "$RepoRoot\scripts\windows\20_system_audit.ps1"
& "$RepoRoot\scripts\windows\50_hardware_inventory.ps1"
& "$RepoRoot\scripts\windows\21_storage_trim.ps1" -Mode Audit

switch ($Mode) {
    'Audit' {
        & "$RepoRoot\scripts\windows\10_tune.ps1" -Mode Audit
        foreach ($profile in $OptimizationProfiles) {
            & "$RepoRoot\scripts\windows\40_v4_optimize.ps1" -Mode Audit -Profile $profile
        }
        & "$RepoRoot\scripts\windows\42_benchmark.ps1" -Stage snapshot
        & "$RepoRoot\scripts\windows\51_hardware_manual_checks.ps1" -Mode Show
        & "$RepoRoot\scripts\bootstrap\10_workstation.ps1" -Mode Audit
        & "$RepoRoot\scripts\bootstrap\05_defender.ps1"
        & "$RepoRoot\scripts\defender\03_apply_approved_exclusions.ps1" -Mode Audit
    }

    'Apply' {
        & "$RepoRoot\scripts\bootstrap\03_apps.ps1"

        if (-not $SkipV4RestorePoint) {
            & "$RepoRoot\scripts\windows\41_restore_point.ps1"
        } else {
            Write-Host '[INFO] V4 restore point explicitly skipped.' -ForegroundColor Yellow
        }

        & "$RepoRoot\scripts\windows\42_benchmark.ps1" -Stage before
        & "$RepoRoot\scripts\windows\10_tune.ps1" -Mode Apply
        foreach ($profile in $OptimizationProfiles) {
            & "$RepoRoot\scripts\windows\40_v4_optimize.ps1" -Mode Apply -Profile $profile
        }
        & "$RepoRoot\scripts\windows\42_benchmark.ps1" -Stage after
        & "$RepoRoot\scripts\windows\43_compare_benchmarks.ps1"
        & "$RepoRoot\scripts\bootstrap\12_validate_v4.ps1" -OptimizationProfiles $OptimizationProfiles

        & "$RepoRoot\scripts\bootstrap\06_wsl.ps1" -Profile $WslProfile -Distribution $Distribution -InstallLocation $WslInstallLocation
        & "$RepoRoot\scripts\bootstrap\10_workstation.ps1" -Mode Apply
        & "$RepoRoot\scripts\defender\03_apply_approved_exclusions.ps1" -Mode Apply

        if ($InstallDevOps) {
            & "$RepoRoot\scripts\bootstrap\08_devops.ps1" -Distribution $Distribution
            & "$RepoRoot\scripts\bootstrap\14_validate_wsl_v6.ps1" -WslProfile $WslProfile -Distribution $Distribution
        } else {
            Write-Host '[INFO] DevOps stack not installed in this pass. Relaunch Apply with -InstallDevOps after first Ubuntu launch.' -ForegroundColor Yellow
        }

        & "$RepoRoot\scripts\bootstrap\05_defender.ps1"
        & "$RepoRoot\scripts\bootstrap\11_validate_v3.ps1" -WslProfile $WslProfile -Distribution $Distribution -InstallLocation $WslInstallLocation
        Write-Host '[INFO] Hardware V5 is observational only. BIOS, ReBAR, memory tuning and device placement are never changed automatically.' -ForegroundColor Yellow
    }

    'Verify' {
        & "$RepoRoot\scripts\windows\10_tune.ps1" -Mode Verify
        foreach ($profile in $OptimizationProfiles) {
            & "$RepoRoot\scripts\windows\40_v4_optimize.ps1" -Mode Verify -Profile $profile
        }
        & "$RepoRoot\scripts\bootstrap\10_workstation.ps1" -Mode Verify
        & "$RepoRoot\scripts\bootstrap\05_defender.ps1"
        & "$RepoRoot\scripts\bootstrap\11_validate_v3.ps1" -WslProfile $WslProfile -Distribution $Distribution -InstallLocation $WslInstallLocation

        $beforeReport = Join-Path $RepoRoot 'reports\windows\v4-benchmark-before.json'
        $afterReport = Join-Path $RepoRoot 'reports\windows\v4-benchmark-after.json'
        if ((Test-Path $beforeReport) -and (Test-Path $afterReport)) {
            & "$RepoRoot\scripts\windows\43_compare_benchmarks.ps1"
        }

        & "$RepoRoot\scripts\bootstrap\12_validate_v4.ps1" -OptimizationProfiles $OptimizationProfiles

        if ($ValidateHardware) {
            & "$RepoRoot\scripts\bootstrap\13_validate_hardware_v5.ps1" -RequireManualChecks
        } else {
            Write-Host '[INFO] Final hardware V5 qualification not requested. Use -ValidateHardware after recording the manual BIOS/placement/stability checks.' -ForegroundColor Yellow
        }

        if ($ValidateWsl -or $ValidateDevOps) {
            & "$RepoRoot\scripts\bootstrap\14_validate_wsl_v6.ps1" -WslProfile $WslProfile -Distribution $Distribution
        } else {
            Write-Host '[INFO] WSL2 V6 runtime qualification not requested. Use -ValidateWsl.' -ForegroundColor Yellow
        }

        if ($ValidateDevOps) {
            & "$RepoRoot\scripts\bootstrap\09_validate_devops.ps1" -Distribution $Distribution
        } else {
            Write-Host '[INFO] Full Linux validation not requested. Use -ValidateDevOps after installing the stack.' -ForegroundColor Yellow
        }
    }
}

Write-Host 'Completed. Review reports under reports/.' -ForegroundColor Green
