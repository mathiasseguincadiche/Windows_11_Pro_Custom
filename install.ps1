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
    [switch]$SkipV4RestorePoint
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = $PSScriptRoot

Write-Host "Windows 11 Pro Custom - mode: $Mode" -ForegroundColor Cyan
Write-Host "V4 optimization profiles: $($OptimizationProfiles -join ', ')" -ForegroundColor Cyan

if ($Mode -eq 'Rollback') {
    & "$RepoRoot\scripts\bootstrap\10_workstation.ps1" -Mode Rollback

    $profilesToRollback = @($OptimizationProfiles)
    if (-not $PSBoundParameters.ContainsKey('OptimizationProfiles')) {
        $profilesToRollback = @('optional', 'gaming', 'privacy', 'standard') | Where-Object {
            Test-Path (Join-Path $RepoRoot "state\windows-v4\$_.before.json")
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
& "$RepoRoot\scripts\windows\21_storage_trim.ps1" -Mode Audit

switch ($Mode) {
    'Audit' {
        & "$RepoRoot\scripts\windows\10_tune.ps1" -Mode Audit
        foreach ($profile in $OptimizationProfiles) {
            & "$RepoRoot\scripts\windows\40_v4_optimize.ps1" -Mode Audit -Profile $profile
        }
        & "$RepoRoot\scripts\windows\42_benchmark.ps1" -Stage snapshot
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
        } else {
            Write-Host '[INFO] DevOps stack not installed in this pass. Relaunch Apply with -InstallDevOps after first Ubuntu launch.' -ForegroundColor Yellow
        }

        & "$RepoRoot\scripts\bootstrap\05_defender.ps1"
        & "$RepoRoot\scripts\bootstrap\11_validate_v3.ps1" -WslProfile $WslProfile -Distribution $Distribution -InstallLocation $WslInstallLocation
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

        if ($ValidateDevOps) {
            & "$RepoRoot\scripts\bootstrap\09_validate_devops.ps1" -Distribution $Distribution
        } else {
            Write-Host '[INFO] Full Linux validation not requested. Use -ValidateDevOps after installing the stack.' -ForegroundColor Yellow
        }
    }
}

Write-Host 'Completed. Review reports under reports/.' -ForegroundColor Green
