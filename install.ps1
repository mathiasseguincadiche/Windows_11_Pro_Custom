[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Verify', 'Rollback')]
    [string]$Mode = 'Audit',

    [ValidateSet('standard', 'lab-heavy', 'nat-fallback')]
    [string]$WslProfile = 'standard',

    [ValidateSet('standard', 'privacy', 'gaming', 'optional')]
    [string[]]$OptimizationProfiles = @('standard'),

    [string]$Distribution = 'Ubuntu',
    [string]$WslInstallLocation = 'E:\WSL\Ubuntu-DevOps',
    [string]$WslUser = '',

    [switch]$InstallDevOps,
    [switch]$ValidateDevOps,
    [switch]$ValidateWsl,
    [switch]$ValidateHardware,
    [switch]$SkipFoundationRestorePoint,

    [ValidateSet('None', 'Create', 'Verify', 'RestorePlan')]
    [string]$BackupAction = 'None',
    [string]$BackupTargetDrive = '',
    [switch]$AllowNonUsbBackupTarget,
    [switch]$SkipBackupRestorePoint,

    [switch]$FullInstall,
    [switch]$PlanOnly,
    [switch]$NonInteractive,
    [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = $PSScriptRoot
$runtimeModule = Join-Path $RepoRoot 'scripts\core\runtime.psm1'
if (-not (Test-Path $runtimeModule)) { throw "Moteur d'orchestration introuvable: $runtimeModule" }
Import-Module $runtimeModule -Force
$context = New-WpcRunContext -RepoRoot $RepoRoot -Mode $Mode -NonInteractive:$NonInteractive
$runSuccess = $false
$failureMessage = ''

function Get-RepoScript {
    param([Parameter(Mandatory)][string]$RelativePath)
    return (Join-Path $RepoRoot $RelativePath)
}

function Invoke-Step {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [hashtable]$Arguments = @{},
        [string]$Name = '',
        [string]$Phase = 'Run',
        [switch]$AllowFailure
    )
    $path = Get-RepoScript -RelativePath $RelativePath
    if ([string]::IsNullOrWhiteSpace($Name)) { $Name = [IO.Path]::GetFileName($path) }
    return Invoke-WpcManagedScript -Context $context -Path $path -Arguments $Arguments -DisplayName $Name -Phase $Phase -AllowFailure:$AllowFailure
}

function Add-PlanItem {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$VerifyRelativePath,
        [hashtable]$VerifyArguments = @{},
        [Parameter(Mandatory)][string]$ApplyRelativePath,
        [hashtable]$ApplyArguments = @{}
    )
    $verifyPath = Get-RepoScript -RelativePath $VerifyRelativePath
    $applyPath = Get-RepoScript -RelativePath $ApplyRelativePath
    $compliant = Test-WpcManagedScript -Context $context -Path $verifyPath -Arguments $VerifyArguments -DisplayName $Name
    $script:plan += [pscustomobject]@{
        Name = $Name
        VerifyPath = $verifyPath
        VerifyArguments = $VerifyArguments
        ApplyPath = $applyPath
        ApplyArguments = $ApplyArguments
        Compliant = [bool]$compliant
    }
}

function Show-Plan {
    Write-Host ''
    Write-Host ('=' * 78) -ForegroundColor DarkCyan
    Write-Host '  PLAN FACTUEL — calculé depuis lʼétat actuel de la machine' -ForegroundColor Cyan
    Write-Host ('=' * 78) -ForegroundColor DarkCyan
    foreach ($item in $script:plan) {
        if ($item.Compliant) {
            Write-WpcStatus -Status 'DEJA_OK' -Message $item.Name -Detail 'Aucune modification planifiée.' -Context $context
        } else {
            Write-WpcStatus -Status 'A_FAIRE' -Message $item.Name -Detail 'Écart détecté par Verify; Apply puis re-Verify seront exécutés.' -Context $context
        }
    }
    $pendingCount = @($script:plan | Where-Object { -not $_.Compliant }).Count
    Write-Host ''
    Write-Host ("Résumé du plan: {0} déjà conforme(s) | {1} à traiter" -f ($script:plan.Count - $pendingCount), $pendingCount) -ForegroundColor $(if ($pendingCount -eq 0) { 'Green' } else { 'Yellow' })
}

function Invoke-PlannedItems {
    foreach ($item in $script:plan) {
        $knownState = if ($item.Compliant) { 'Compliant' } else { 'NeedsChange' }
        [void](Invoke-WpcPlannedComponent -Context $context -DisplayName $item.Name -VerifyPath $item.VerifyPath -VerifyArguments $item.VerifyArguments -ApplyPath $item.ApplyPath -ApplyArguments $item.ApplyArguments -KnownState $knownState)
    }
}

function Test-AnyPath {
    param([Parameter(Mandatory)][string[]]$Path)
    return @($Path | Where-Object { Test-Path -LiteralPath $_ }).Count -gt 0
}

function Test-BenchmarkEvidencePair {
    $canonicalBefore = Join-Path $RepoRoot 'reports\windows\benchmark-before.json'
    $canonicalAfter = Join-Path $RepoRoot 'reports\windows\benchmark-after.json'
    $legacyBefore = Join-Path $RepoRoot 'reports\windows\v4-benchmark-before.json'
    $legacyAfter = Join-Path $RepoRoot 'reports\windows\v4-benchmark-after.json'
    return ((Test-Path -LiteralPath $canonicalBefore) -and (Test-Path -LiteralPath $canonicalAfter)) -or
           ((Test-Path -LiteralPath $legacyBefore) -and (Test-Path -LiteralPath $legacyAfter))
}

function Ensure-HardwareManualEvidence {
    $manualPath = Get-RepoScript -RelativePath 'scripts\windows\51_hardware_manual_checks.ps1'
    Write-WpcStatus -Status 'ANALYSE' -Message 'Preuves matérielles manuelles' -Detail 'Lecture des confirmations qui ne peuvent pas être déduites automatiquement depuis Windows.' -Context $context
    $probe = Invoke-WpcManagedScript -Context $context -Path $manualPath -Arguments @{ Mode='Verify' } -DisplayName 'Preuves matérielles manuelles' -Phase 'Probe' -Purpose 'ManualEvidenceProbe' -AllowFailure -Quiet
    if (-not $probe.Success) {
        throw "Impossible de vérifier les preuves matérielles manuelles: $($probe.Error)"
    }
    if ([string]$probe.Outcome -eq 'ACTION_REQUISE') {
        Write-WpcStatus -Status 'AVERTISSEMENT' -Message 'Validation matérielle manuelle en attente' -Detail 'Des contrôles UEFI/placement/refroidissement T705/stabilité DDR5/BIOS restent à confirmer. Ils sont non bloquants pour Installation complete et seront rappelés dans la qualification finale.' -Context $context
        return
    }
    Write-WpcStatus -Status 'DEJA_OK' -Message 'Preuves matérielles manuelles' -Detail 'Toutes les preuves manuelles strictes ont déjà été confirmées; les informations purement consultatives restent non bloquantes.' -Context $context
}

function Invoke-HardwareQualification {
    Ensure-HardwareManualEvidence
    [void](Invoke-Step -RelativePath 'scripts\bootstrap\13_validate_hardware.ps1' -Arguments @{ RequireManualChecks=[switch]::Present } -Name 'Qualification matérielle' -Phase 'FinalValidation')
}

try {
    if ($FullInstall) {
        $InstallDevOps = $true
        $ValidateDevOps = $true
        $ValidateWsl = $true
        $ValidateHardware = $true
    }

    Write-WpcBanner -Context $context -Title "Windows 11 Pro Custom — Orchestrateur — $Mode"
    Write-Host "Release              : $($context.Release)"
    Write-Host "Profil WSL2          : $WslProfile"
    Write-Host "Distribution         : $Distribution"
    Write-Host "Emplacement WSL      : $WslInstallLocation"
    Write-Host "Utilisateur WSL      : $(if ($WslUser) { $WslUser } else { '<détection/prompt si nécessaire>' })"
    Write-Host "Profils optimisation : $($OptimizationProfiles -join ', ')"
    Write-Host "DevOps demandé        : $([bool]$InstallDevOps)"
    Write-Host "Mode non interactif   : $([bool]$NonInteractive)"

    if ($BackupAction -ne 'None') {
        $BackupTargetDrive = Read-WpcRequiredValue -Context $context -Name 'BackupTargetDrive' -CurrentValue $BackupTargetDrive -Prompt 'Indique la lettre du disque de sauvegarde, avec deux-points' -Example 'F:' -Pattern '^[A-Za-z]:$'
        $args = @{ BackupTargetDrive=$BackupTargetDrive }
        switch ($BackupAction) {
            'Create' {
                $args.Distribution = $Distribution
                if ($AllowNonUsbBackupTarget) { $args.AllowNonUsbTarget=[switch]::Present }
                if ($SkipBackupRestorePoint) { $args.SkipRestorePoint=[switch]::Present }
                [void](Invoke-Step -RelativePath 'scripts\backup\60_create_backup.ps1' -Arguments $args -Name 'Création sauvegarde' -Phase 'Backup')
            }
            'Verify' { [void](Invoke-Step -RelativePath 'scripts\backup\61_validate_backup.ps1' -Arguments $args -Name 'Validation sauvegarde' -Phase 'Backup') }
            'RestorePlan' { [void](Invoke-Step -RelativePath 'scripts\backup\62_restore_plan.ps1' -Arguments $args -Name 'Plan de restauration' -Phase 'Backup') }
        }
        $runSuccess = $true
        return
    }

    if ($Mode -eq 'Rollback') {
        Write-WpcStatus -Status 'ANALYSE' -Message 'Rollback' -Detail 'Seuls les états initiaux réellement enregistrés par le dépôt seront restaurés.' -Context $context
        $responsiveStatePaths = @(
            (Join-Path $RepoRoot 'state\windows-responsiveness\responsiveness.before.json'),
            (Join-Path $RepoRoot 'state\windows-v8\responsiveness.before.json')
        )
        if (Test-AnyPath -Path $responsiveStatePaths) {
            [void](Invoke-Step -RelativePath 'scripts\windows\53_responsiveness.ps1' -Arguments @{ Mode='Rollback' } -Name 'Réactivité Windows' -Phase 'Rollback')
        } else {
            Write-WpcStatus -Status 'DEJA_OK' -Message 'Réactivité Windows' -Detail 'Aucun état initial enregistré; rien à restaurer.' -Context $context
        }

        [void](Invoke-Step -RelativePath 'scripts\bootstrap\10_workstation.ps1' -Arguments @{ Mode='Rollback' } -Name 'Poste de travail' -Phase 'Rollback')
        $profilesToRollback = @($OptimizationProfiles)
        if (-not $PSBoundParameters.ContainsKey('OptimizationProfiles')) {
            $profilesToRollback = @('optional','gaming','privacy','standard') | Where-Object {
                (Test-Path (Join-Path $RepoRoot "state\windows-optimization\${_}.before.json")) -or
                (Test-Path (Join-Path $RepoRoot "state\windows-v4\${_}.before.json"))
            }
        } else {
            [array]::Reverse($profilesToRollback)
        }
        foreach ($profile in $profilesToRollback) {
            [void](Invoke-Step -RelativePath 'scripts\windows\40_optimize.ps1' -Arguments @{ Mode='Rollback'; Profile=$profile } -Name "Profil optimisation $profile" -Phase 'Rollback')
        }
        [void](Invoke-Step -RelativePath 'scripts\windows\10_tune.ps1' -Arguments @{ Mode='Rollback' } -Name 'Réglages Windows de base' -Phase 'Rollback')
        [void](Invoke-Step -RelativePath 'scripts\defender\03_apply_approved_exclusions.ps1' -Arguments @{ Mode='Rollback' } -Name 'Exclusions Defender' -Phase 'Rollback')
        $runSuccess = $true
        return
    }

    $preflightArgs = @{}
    if ($Mode -in @('Apply','Verify')) { $preflightArgs.StrictPhysicalReadiness = [switch]::Present }
    if ($Mode -eq 'Verify') { $preflightArgs.RequireFoundation = [switch]::Present }
    [void](Invoke-Step -RelativePath 'scripts\bootstrap\00_preflight.ps1' -Arguments $preflightArgs -Name 'Préflight Windows' -Phase 'Discovery')

    if ($Mode -eq 'Apply' -and $ValidateHardware -and -not $PlanOnly) {
        Ensure-HardwareManualEvidence
    }

    if ($Mode -eq 'Apply' -and -not $PlanOnly) {
        $foundationPath = Get-RepoScript -RelativePath 'scripts\bootstrap\02_foundation.ps1'
        $foundationReady = Test-WpcManagedScript -Context $context -Path $foundationPath -Arguments @{ Mode='Verify' } -DisplayName 'Fondations Windows'
        if (-not $foundationReady) {
            if (-not $SkipFoundationRestorePoint) {
                [void](Invoke-Step -RelativePath 'scripts\windows\41_restore_point.ps1' -Name 'Point de restauration pré-fondations' -Phase 'Safety')
            } else {
                Write-WpcStatus -Status 'AVERTISSEMENT' -Message 'Point de restauration pré-fondations ignoré explicitement' -Detail '-SkipFoundationRestorePoint a été fourni.' -Context $context
            }
            [void](Invoke-Step -RelativePath 'scripts\bootstrap\02_foundation.ps1' -Arguments @{ Mode='Apply' } -Name 'Bootstrap fondations Windows' -Phase 'Foundation')
        } else {
            Write-WpcStatus -Status 'DEJA_OK' -Message 'Fondations Windows' -Detail 'WSL/VMP, WinGet et runtime WSL sont déjà opérationnels.' -Context $context
        }
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\00_preflight.ps1' -Arguments @{ StrictPhysicalReadiness=[switch]::Present; RequireFoundation=[switch]::Present } -Name 'Revalidation fondations Windows' -Phase 'FoundationValidation')
    }

    [void](Invoke-Step -RelativePath 'scripts\bootstrap\01_machine_state.ps1' -Arguments @{ WslProfile=$WslProfile; Distribution=$Distribution; WslInstallLocation=$WslInstallLocation } -Name 'État réel de la machine' -Phase 'Discovery')
    [void](Invoke-Step -RelativePath 'scripts\windows\20_system_audit.ps1' -Name 'Audit système Windows' -Phase 'Discovery')
    [void](Invoke-Step -RelativePath 'scripts\windows\50_hardware_inventory.ps1' -Name 'Inventaire matériel' -Phase 'Discovery')
    [void](Invoke-Step -RelativePath 'scripts\windows\52_hardware_symbiosis.ps1' -Arguments @{ Mode='Audit' } -Name 'Symbiose matérielle' -Phase 'Discovery')
    [void](Invoke-Step -RelativePath 'scripts\windows\21_storage_trim.ps1' -Arguments @{ Mode='Audit' } -Name 'Stockage/TRIM' -Phase 'Discovery')
    [void](Invoke-Step -RelativePath 'scripts\windows\53_responsiveness.ps1' -Arguments @{ Mode='Audit' } -Name 'Réactivité Windows' -Phase 'Discovery')

    if ($Mode -eq 'Audit') {
        [void](Invoke-Step -RelativePath 'scripts\windows\10_tune.ps1' -Arguments @{ Mode='Audit' } -Name 'Réglages Windows de base' -Phase 'Audit')
        foreach ($profile in $OptimizationProfiles) {
            [void](Invoke-Step -RelativePath 'scripts\windows\40_optimize.ps1' -Arguments @{ Mode='Audit'; Profile=$profile } -Name "Profil optimisation $profile" -Phase 'Audit')
        }
        [void](Invoke-Step -RelativePath 'scripts\windows\42_benchmark.ps1' -Arguments @{ Stage='snapshot' } -Name 'Mesure Windows' -Phase 'Audit')
        [void](Invoke-Step -RelativePath 'scripts\windows\51_hardware_manual_checks.ps1' -Arguments @{ Mode='Show' } -Name 'Preuves matérielles manuelles' -Phase 'Audit')
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\03_apps.ps1' -Arguments @{ Mode='Audit' } -Name 'Applications WinGet' -Phase 'Audit')
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\06_wsl.ps1' -Arguments @{ Mode='Audit'; Profile=$WslProfile; Distribution=$Distribution; InstallLocation=$WslInstallLocation } -Name 'WSL2' -Phase 'Audit')
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\07_wsl_user.ps1' -Arguments @{ Mode='Audit'; Distribution=$Distribution; LinuxUser=$WslUser } -Name 'Utilisateur WSL' -Phase 'Audit' -AllowFailure)
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\10_workstation.ps1' -Arguments @{ Mode='Audit' } -Name 'Poste de travail' -Phase 'Audit')
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\05_defender.ps1' -Name 'Microsoft Defender' -Phase 'Audit')
        [void](Invoke-Step -RelativePath 'scripts\defender\03_apply_approved_exclusions.ps1' -Arguments @{ Mode='Audit' } -Name 'Exclusions Defender' -Phase 'Audit')
        $runSuccess = $true
        return
    }

    if ($Mode -eq 'Verify') {
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\03_apps.ps1' -Arguments @{ Mode='Verify' } -Name 'Applications WinGet' -Phase 'Verify')
        [void](Invoke-Step -RelativePath 'scripts\windows\10_tune.ps1' -Arguments @{ Mode='Verify' } -Name 'Réglages Windows de base' -Phase 'Verify')
        foreach ($profile in $OptimizationProfiles) {
            [void](Invoke-Step -RelativePath 'scripts\windows\40_optimize.ps1' -Arguments @{ Mode='Verify'; Profile=$profile } -Name "Profil optimisation $profile" -Phase 'Verify')
        }
        [void](Invoke-Step -RelativePath 'scripts\windows\53_responsiveness.ps1' -Arguments @{ Mode='Verify' } -Name 'Réactivité Windows' -Phase 'Verify')
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\06_wsl.ps1' -Arguments @{ Mode='Verify'; Profile=$WslProfile; Distribution=$Distribution; InstallLocation=$WslInstallLocation } -Name 'WSL2' -Phase 'Verify')
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\07_wsl_user.ps1' -Arguments @{ Mode='Verify'; Distribution=$Distribution; LinuxUser=$WslUser } -Name 'Utilisateur WSL' -Phase 'Verify')
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\10_workstation.ps1' -Arguments @{ Mode='Verify' } -Name 'Poste de travail' -Phase 'Verify')
        [void](Invoke-Step -RelativePath 'scripts\defender\03_apply_approved_exclusions.ps1' -Arguments @{ Mode='Verify' } -Name 'Exclusions Defender' -Phase 'Verify')
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\05_defender.ps1' -Name 'Microsoft Defender' -Phase 'Verify')
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\11_validate_windows.ps1' -Arguments @{ WslProfile=$WslProfile; Distribution=$Distribution; InstallLocation=$WslInstallLocation } -Name 'Qualification Windows' -Phase 'FinalValidation')

        if (Test-BenchmarkEvidencePair) {
            [void](Invoke-Step -RelativePath 'scripts\windows\43_compare_benchmarks.ps1' -Name 'Comparaison mesures Windows' -Phase 'Verify')
            [void](Invoke-Step -RelativePath 'scripts\bootstrap\12_validate_optimization.ps1' -Arguments @{ OptimizationProfiles=$OptimizationProfiles } -Name 'Qualification optimisation Windows' -Phase 'FinalValidation')
        } else {
            Write-WpcStatus -Status 'ACTION_REQUISE' -Message 'Preuves avant/après optimisation absentes' -Detail 'Exécute une fois .\install.ps1 -Mode Apply pour générer les mesures factuelles, puis relance Verify.' -Context $context
        }

        if ($ValidateHardware) { Invoke-HardwareQualification }
        else { Write-WpcStatus -Status 'IGNORE' -Message 'Qualification physique non demandée' -Detail 'Ajoute -ValidateHardware pour vérifier aussi les preuves BIOS/placement/stabilité.' -Context $context }

        if ($ValidateWsl -or $ValidateDevOps) {
            [void](Invoke-Step -RelativePath 'scripts\bootstrap\14_validate_wsl.ps1' -Arguments @{ WslProfile=$WslProfile; Distribution=$Distribution } -Name 'Qualification runtime WSL2' -Phase 'FinalValidation')
        } else {
            Write-WpcStatus -Status 'IGNORE' -Message 'Qualification runtime WSL2 non demandée' -Detail 'Ajoute -ValidateWsl.' -Context $context
        }

        if ($ValidateDevOps) {
            [void](Invoke-Step -RelativePath 'scripts\bootstrap\09_validate_devops.ps1' -Arguments @{ Distribution=$Distribution; LinuxUser=$WslUser } -Name 'Qualification stack DevOps' -Phase 'FinalValidation')
        } else {
            Write-WpcStatus -Status 'IGNORE' -Message 'Qualification DevOps non demandée' -Detail 'Ajoute -ValidateDevOps après installation de la stack.' -Context $context
        }
        $runSuccess = $true
        return
    }

    $script:plan = @()
    Add-PlanItem -Name 'Applications WinGet' -VerifyRelativePath 'scripts\bootstrap\03_apps.ps1' -VerifyArguments @{ Mode='Verify' } -ApplyRelativePath 'scripts\bootstrap\03_apps.ps1' -ApplyArguments @{ Mode='Apply' }
    Add-PlanItem -Name 'Réglages Windows de base' -VerifyRelativePath 'scripts\windows\10_tune.ps1' -VerifyArguments @{ Mode='Verify' } -ApplyRelativePath 'scripts\windows\10_tune.ps1' -ApplyArguments @{ Mode='Apply' }
    foreach ($profile in $OptimizationProfiles) {
        Add-PlanItem -Name "Profil optimisation $profile" -VerifyRelativePath 'scripts\windows\40_optimize.ps1' -VerifyArguments @{ Mode='Verify'; Profile=$profile } -ApplyRelativePath 'scripts\windows\40_optimize.ps1' -ApplyArguments @{ Mode='Apply'; Profile=$profile }
    }
    Add-PlanItem -Name 'Réactivité Windows' -VerifyRelativePath 'scripts\windows\53_responsiveness.ps1' -VerifyArguments @{ Mode='Verify' } -ApplyRelativePath 'scripts\windows\53_responsiveness.ps1' -ApplyArguments @{ Mode='Apply' }
    Add-PlanItem -Name 'WSL2' -VerifyRelativePath 'scripts\bootstrap\06_wsl.ps1' -VerifyArguments @{ Mode='Verify'; Profile=$WslProfile; Distribution=$Distribution; InstallLocation=$WslInstallLocation } -ApplyRelativePath 'scripts\bootstrap\06_wsl.ps1' -ApplyArguments @{ Mode='Apply'; Profile=$WslProfile; Distribution=$Distribution; InstallLocation=$WslInstallLocation }
    Add-PlanItem -Name 'Utilisateur WSL' -VerifyRelativePath 'scripts\bootstrap\07_wsl_user.ps1' -VerifyArguments @{ Mode='Verify'; Distribution=$Distribution; LinuxUser=$WslUser } -ApplyRelativePath 'scripts\bootstrap\07_wsl_user.ps1' -ApplyArguments @{ Mode='Apply'; Distribution=$Distribution; LinuxUser=$WslUser }
    Add-PlanItem -Name 'Poste de travail' -VerifyRelativePath 'scripts\bootstrap\10_workstation.ps1' -VerifyArguments @{ Mode='Verify' } -ApplyRelativePath 'scripts\bootstrap\10_workstation.ps1' -ApplyArguments @{ Mode='Apply' }
    Add-PlanItem -Name 'Exclusions Defender approuvées' -VerifyRelativePath 'scripts\defender\03_apply_approved_exclusions.ps1' -VerifyArguments @{ Mode='Verify' } -ApplyRelativePath 'scripts\defender\03_apply_approved_exclusions.ps1' -ApplyArguments @{ Mode='Apply' }

    if ($InstallDevOps) {
        Add-PlanItem -Name 'Stack DevOps WSL' -VerifyRelativePath 'scripts\bootstrap\09_validate_devops.ps1' -VerifyArguments @{ Distribution=$Distribution; LinuxUser=$WslUser } -ApplyRelativePath 'scripts\bootstrap\08_devops.ps1' -ApplyArguments @{ Distribution=$Distribution; LinuxUser=$WslUser }
    } else {
        Write-WpcStatus -Status 'IGNORE' -Message 'Stack DevOps non demandée dans cet Apply' -Detail 'Ajoute -InstallDevOps ou utilise -FullInstall pour lʼinclure.' -Context $context
    }

    Show-Plan
    if ($PlanOnly) {
        Write-WpcStatus -Status 'OK' -Message 'PlanOnly terminé' -Detail 'Aucune modification nʼa été effectuée après la phase de découverte.' -Context $context
        $runSuccess = $true
        return
    }

    $pending = @($script:plan | Where-Object { -not $_.Compliant })
    if ($pending.Count -gt 0) {
        Confirm-WpcChanges -Context $context -Yes:$Yes
        if (-not $SkipFoundationRestorePoint) {
            [void](Invoke-Step -RelativePath 'scripts\windows\41_restore_point.ps1' -Name 'Point de restauration pré-changements' -Phase 'Safety')
        } else {
            Write-WpcStatus -Status 'AVERTISSEMENT' -Message 'Point de restauration ignoré explicitement' -Detail '-SkipFoundationRestorePoint a été fourni.' -Context $context
        }
        [void](Invoke-Step -RelativePath 'scripts\windows\42_benchmark.ps1' -Arguments @{ Stage='before' } -Name 'Mesure avant changements' -Phase 'Measurement')
    } else {
        Write-WpcStatus -Status 'DEJA_OK' -Message 'Installation demandée déjà conforme' -Detail 'Aucune modification système, réinstallation ou point de restauration nʼest nécessaire.' -Context $context
    }

    Invoke-PlannedItems

    if ($pending.Count -gt 0) {
        [void](Invoke-Step -RelativePath 'scripts\windows\42_benchmark.ps1' -Arguments @{ Stage='after' } -Name 'Mesure après changements' -Phase 'Measurement')
        [void](Invoke-Step -RelativePath 'scripts\windows\43_compare_benchmarks.ps1' -Name 'Comparaison avant/après' -Phase 'Measurement')
    } elseif (-not (Test-BenchmarkEvidencePair)) {
        Write-WpcStatus -Status 'ANALYSE' -Message 'Preuves dʼoptimisation absentes malgré configuration conforme' -Detail 'Création de deux snapshots non mutatifs pour disposer dʼune base de validation.' -Context $context
        [void](Invoke-Step -RelativePath 'scripts\windows\42_benchmark.ps1' -Arguments @{ Stage='before' } -Name 'Mesure de référence' -Phase 'Measurement')
        [void](Invoke-Step -RelativePath 'scripts\windows\42_benchmark.ps1' -Arguments @{ Stage='after' } -Name 'Mesure de confirmation' -Phase 'Measurement')
        [void](Invoke-Step -RelativePath 'scripts\windows\43_compare_benchmarks.ps1' -Name 'Comparaison de confirmation' -Phase 'Measurement')
    }

    [void](Invoke-Step -RelativePath 'scripts\bootstrap\05_defender.ps1' -Name 'Microsoft Defender' -Phase 'FinalValidation')
    [void](Invoke-Step -RelativePath 'scripts\bootstrap\11_validate_windows.ps1' -Arguments @{ WslProfile=$WslProfile; Distribution=$Distribution; InstallLocation=$WslInstallLocation } -Name 'Qualification Windows' -Phase 'FinalValidation')
    [void](Invoke-Step -RelativePath 'scripts\bootstrap\12_validate_optimization.ps1' -Arguments @{ OptimizationProfiles=$OptimizationProfiles } -Name 'Qualification optimisation Windows' -Phase 'FinalValidation')

    if ($ValidateHardware) { Invoke-HardwareQualification }
    else { Write-WpcStatus -Status 'IGNORE' -Message 'Qualification physique non demandée' -Detail 'Le script ne suppose jamais les données BIOS/placement/stabilité.' -Context $context }

    if ($ValidateWsl -or $ValidateDevOps) {
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\14_validate_wsl.ps1' -Arguments @{ WslProfile=$WslProfile; Distribution=$Distribution } -Name 'Qualification runtime WSL2' -Phase 'FinalValidation')
    }
    if ($ValidateDevOps) {
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\09_validate_devops.ps1' -Arguments @{ Distribution=$Distribution; LinuxUser=$WslUser } -Name 'Qualification stack DevOps' -Phase 'FinalValidation')
    }

    $runSuccess = $true
}
catch {
    $failureMessage = $_.Exception.Message
    Write-WpcStatus -Status 'ERREUR' -Message 'Orchestration interrompue' -Detail $failureMessage -Context $context
    throw
}
finally {
    Complete-WpcRun -Context $context -Success:$runSuccess -FailureMessage $failureMessage
}