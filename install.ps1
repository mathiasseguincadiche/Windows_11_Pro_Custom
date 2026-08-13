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
    [string]$WslUser = '',

    [switch]$InstallDevOps,
    [switch]$ValidateDevOps,
    [switch]$ValidateWsl,
    [switch]$ValidateHardware,
    [switch]$SkipV4RestorePoint,

    [switch]$InstallOpenClawAI,
    [switch]$ValidateOpenClawAI,
    [string]$OpenClawRoot = 'D:\AI\OpenClaw',
    [string]$OpenClawControlPlanePath = 'D:\AI\OpenClaw\control-plane',
    [string]$OpenClawRepositoryRef = '',

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

function Invoke-HardwareQualification {
    $manualPath = Get-RepoScript -RelativePath 'scripts\windows\51_hardware_manual_checks.ps1'
    $manualReady = Test-WpcManagedScript -Context $context -Path $manualPath -Arguments @{ Mode='Verify' } -DisplayName 'Preuves matérielles manuelles'
    if (-not $manualReady) {
        Write-WpcStatus -Status 'ACTION_REQUISE' -Message 'Preuves matérielles manuelles incomplètes' -Detail 'Ces données BIOS/placement/stabilité ne peuvent pas être inventées par Windows.' -Context $context
        if ($context.NonInteractive) {
            throw 'Validation matérielle requiert des preuves manuelles. Exécute: .\scripts\windows\51_hardware_manual_checks.ps1 -Mode Record -Interactive puis relance Verify -ValidateHardware.'
        }
        $answer = (Read-Host 'Veux-tu enregistrer maintenant les contrôles matériels manuels ? [O/N]').Trim().ToLowerInvariant()
        if ($answer -in @('o','oui','y','yes')) {
            [void](Invoke-WpcManagedScript -Context $context -Path $manualPath -Arguments @{ Mode='Record'; Interactive=[switch]::Present } -DisplayName 'Saisie guidée des preuves matérielles' -Phase 'ManualEvidence')
        } else {
            throw 'Qualification matérielle laissée incomplète par choix utilisateur. Aucun verdict positif ne sera déclaré.'
        }
    }
    [void](Invoke-Step -RelativePath 'scripts\bootstrap\13_validate_hardware_v5.ps1' -Arguments @{ RequireManualChecks=[switch]::Present } -Name 'Qualification matérielle' -Phase 'FinalValidation')
}

try {
    if ($FullInstall) {
        $InstallDevOps = $true
        $ValidateDevOps = $true
        $ValidateWsl = $true
        $ValidateHardware = $true
        $InstallOpenClawAI = $true
        $ValidateOpenClawAI = $true
    }

    $openClawConfigPath = Join-Path $RepoRoot 'config\openclaw\control-plane.json'
    if ([string]::IsNullOrWhiteSpace($OpenClawRepositoryRef)) {
        if (-not (Test-Path $openClawConfigPath)) { throw "OpenClaw control-plane pin absent: $openClawConfigPath" }
        $openClawConfig = Get-Content -Raw $openClawConfigPath | ConvertFrom-Json
        $OpenClawRepositoryRef = [string]$openClawConfig.ref
        if ([string]::IsNullOrWhiteSpace($OpenClawRepositoryRef)) { throw 'OpenClaw control-plane pin vide.' }
    }

    Write-WpcBanner -Context $context -Title "Windows 11 Pro Custom — Orchestrateur — $Mode"
    Write-Host "Profil WSL2          : $WslProfile"
    Write-Host "Distribution         : $Distribution"
    Write-Host "Emplacement WSL      : $WslInstallLocation"
    Write-Host "Utilisateur WSL      : $(if ($WslUser) { $WslUser } else { '<détection/prompt si nécessaire>' })"
    Write-Host "Profils optimisation : $($OptimizationProfiles -join ', ')"
    Write-Host "DevOps demandé        : $([bool]$InstallDevOps)"
    Write-Host "OpenClaw demandé      : $([bool]$InstallOpenClawAI)"
    Write-Host "Mode non interactif   : $([bool]$NonInteractive)"

    if ($BackupAction -ne 'None') {
        $BackupTargetDrive = Read-WpcRequiredValue -Context $context -Name 'BackupTargetDrive' -CurrentValue $BackupTargetDrive -Prompt 'Indique la lettre du disque de sauvegarde, avec deux-points' -Example 'E:' -Pattern '^[A-Za-z]:$'
        $args = @{ BackupTargetDrive=$BackupTargetDrive }
        switch ($BackupAction) {
            'Create' {
                $args.Distribution = $Distribution
                if ($AllowNonUsbBackupTarget) { $args.AllowNonUsbTarget=[switch]::Present }
                if ($SkipBackupRestorePoint) { $args.SkipRestorePoint=[switch]::Present }
                [void](Invoke-Step -RelativePath 'scripts\backup\60_create_backup_v7.ps1' -Arguments $args -Name 'Création sauvegarde' -Phase 'Backup')
            }
            'Verify' { [void](Invoke-Step -RelativePath 'scripts\backup\61_validate_backup_v7.ps1' -Arguments $args -Name 'Validation sauvegarde' -Phase 'Backup') }
            'RestorePlan' { [void](Invoke-Step -RelativePath 'scripts\backup\62_restore_plan_v7.ps1' -Arguments $args -Name 'Plan de restauration' -Phase 'Backup') }
        }
        $runSuccess = $true
        return
    }

    if ($Mode -eq 'Rollback') {
        Write-WpcStatus -Status 'ANALYSE' -Message 'Rollback' -Detail 'Seuls les états initiaux réellement enregistrés par le dépôt seront restaurés.' -Context $context
        $v8StatePath = Join-Path $RepoRoot 'state\windows-v8\responsiveness.before.json'
        if (Test-Path $v8StatePath) { [void](Invoke-Step -RelativePath 'scripts\windows\53_responsiveness_v8.ps1' -Arguments @{ Mode='Rollback' } -Name 'Réactivité Windows' -Phase 'Rollback') }
        else { Write-WpcStatus -Status 'DEJA_OK' -Message 'Réactivité Windows' -Detail 'Aucun état initial enregistré; rien à restaurer.' -Context $context }

        [void](Invoke-Step -RelativePath 'scripts\bootstrap\10_workstation.ps1' -Arguments @{ Mode='Rollback' } -Name 'Poste de travail' -Phase 'Rollback')
        $profilesToRollback = @($OptimizationProfiles)
        if (-not $PSBoundParameters.ContainsKey('OptimizationProfiles')) {
            $profilesToRollback = @('optional','gaming','privacy','standard') | Where-Object { Test-Path (Join-Path $RepoRoot "state\windows-v4\${_}.before.json") }
        } else { [array]::Reverse($profilesToRollback) }
        foreach ($profile in $profilesToRollback) { [void](Invoke-Step -RelativePath 'scripts\windows\40_v4_optimize.ps1' -Arguments @{ Mode='Rollback'; Profile=$profile } -Name "Profil optimisation $profile" -Phase 'Rollback') }
        [void](Invoke-Step -RelativePath 'scripts\windows\10_tune.ps1' -Arguments @{ Mode='Rollback' } -Name 'Réglages Windows de base' -Phase 'Rollback')
        [void](Invoke-Step -RelativePath 'scripts\defender\03_apply_approved_exclusions.ps1' -Arguments @{ Mode='Rollback' } -Name 'Exclusions Defender' -Phase 'Rollback')
        Write-WpcStatus -Status 'ACTION_REQUISE' -Message 'OpenClaw non supprimé automatiquement' -Detail 'Son état et ses identifiants sur D: nécessitent une décision explicite; le rollback ne les efface jamais.' -Context $context
        $runSuccess = $true
        return
    }

    # La vérité machine est relue à chaque exécution avant toute décision.
    [void](Invoke-Step -RelativePath 'scripts\bootstrap\00_preflight.ps1' -Name 'Préflight Windows' -Phase 'Discovery')
    [void](Invoke-Step -RelativePath 'scripts\bootstrap\01_machine_state.ps1' -Arguments @{ WslProfile=$WslProfile; Distribution=$Distribution; WslInstallLocation=$WslInstallLocation; OpenClawRoot=$OpenClawRoot } -Name 'État réel de la machine' -Phase 'Discovery')
    [void](Invoke-Step -RelativePath 'scripts\windows\20_system_audit.ps1' -Name 'Audit système Windows' -Phase 'Discovery')
    [void](Invoke-Step -RelativePath 'scripts\windows\50_hardware_inventory.ps1' -Name 'Inventaire matériel' -Phase 'Discovery')
    [void](Invoke-Step -RelativePath 'scripts\windows\52_hardware_symbiosis.ps1' -Arguments @{ Mode='Audit' } -Name 'Symbiose matérielle' -Phase 'Discovery')
    [void](Invoke-Step -RelativePath 'scripts\windows\21_storage_trim.ps1' -Arguments @{ Mode='Audit' } -Name 'Stockage/TRIM' -Phase 'Discovery')
    [void](Invoke-Step -RelativePath 'scripts\windows\53_responsiveness_v8.ps1' -Arguments @{ Mode='Audit' } -Name 'Réactivité Windows' -Phase 'Discovery')

    if ($Mode -eq 'Audit') {
        [void](Invoke-Step -RelativePath 'scripts\windows\10_tune.ps1' -Arguments @{ Mode='Audit' } -Name 'Réglages Windows de base' -Phase 'Audit')
        foreach ($profile in $OptimizationProfiles) { [void](Invoke-Step -RelativePath 'scripts\windows\40_v4_optimize.ps1' -Arguments @{ Mode='Audit'; Profile=$profile } -Name "Profil optimisation $profile" -Phase 'Audit') }
        [void](Invoke-Step -RelativePath 'scripts\windows\42_benchmark.ps1' -Arguments @{ Stage='snapshot' } -Name 'Mesure Windows' -Phase 'Audit')
        [void](Invoke-Step -RelativePath 'scripts\windows\51_hardware_manual_checks.ps1' -Arguments @{ Mode='Show' } -Name 'Preuves matérielles manuelles' -Phase 'Audit')
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\03_apps.ps1' -Arguments @{ Mode='Audit' } -Name 'Applications WinGet' -Phase 'Audit')
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\06_wsl.ps1' -Arguments @{ Mode='Audit'; Profile=$WslProfile; Distribution=$Distribution; InstallLocation=$WslInstallLocation } -Name 'WSL2' -Phase 'Audit')
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\07_wsl_user.ps1' -Arguments @{ Mode='Audit'; Distribution=$Distribution; LinuxUser=$WslUser } -Name 'Utilisateur WSL' -Phase 'Audit' -AllowFailure)
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\10_workstation.ps1' -Arguments @{ Mode='Audit' } -Name 'Poste de travail' -Phase 'Audit')
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\05_defender.ps1' -Name 'Microsoft Defender' -Phase 'Audit')
        [void](Invoke-Step -RelativePath 'scripts\defender\03_apply_approved_exclusions.ps1' -Arguments @{ Mode='Audit' } -Name 'Exclusions Defender' -Phase 'Audit')
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\15_openclaw_ai.ps1' -Arguments @{ Mode='Audit'; Root=$OpenClawRoot; ControlPlanePath=$OpenClawControlPlanePath; RepositoryRef=$OpenClawRepositoryRef } -Name 'OpenClaw/OpenRouter' -Phase 'Audit')
        $runSuccess = $true
        return
    }

    if ($Mode -eq 'Verify') {
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\03_apps.ps1' -Arguments @{ Mode='Verify' } -Name 'Applications WinGet' -Phase 'Verify')
        [void](Invoke-Step -RelativePath 'scripts\windows\10_tune.ps1' -Arguments @{ Mode='Verify' } -Name 'Réglages Windows de base' -Phase 'Verify')
        foreach ($profile in $OptimizationProfiles) { [void](Invoke-Step -RelativePath 'scripts\windows\40_v4_optimize.ps1' -Arguments @{ Mode='Verify'; Profile=$profile } -Name "Profil optimisation $profile" -Phase 'Verify') }
        [void](Invoke-Step -RelativePath 'scripts\windows\53_responsiveness_v8.ps1' -Arguments @{ Mode='Verify' } -Name 'Réactivité Windows' -Phase 'Verify')
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\06_wsl.ps1' -Arguments @{ Mode='Verify'; Profile=$WslProfile; Distribution=$Distribution; InstallLocation=$WslInstallLocation } -Name 'WSL2' -Phase 'Verify')
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\07_wsl_user.ps1' -Arguments @{ Mode='Verify'; Distribution=$Distribution; LinuxUser=$WslUser } -Name 'Utilisateur WSL' -Phase 'Verify')
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\10_workstation.ps1' -Arguments @{ Mode='Verify' } -Name 'Poste de travail' -Phase 'Verify')
        [void](Invoke-Step -RelativePath 'scripts\defender\03_apply_approved_exclusions.ps1' -Arguments @{ Mode='Verify' } -Name 'Exclusions Defender' -Phase 'Verify')
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\05_defender.ps1' -Name 'Microsoft Defender' -Phase 'Verify')
        [void](Invoke-Step -RelativePath 'scripts\bootstrap\11_validate_v3.ps1' -Arguments @{ WslProfile=$WslProfile; Distribution=$Distribution; InstallLocation=$WslInstallLocation } -Name 'Qualification Windows' -Phase 'FinalValidation')

        $beforeReport = Join-Path $RepoRoot 'reports\windows\v4-benchmark-before.json'
        $afterReport = Join-Path $RepoRoot 'reports\windows\v4-benchmark-after.json'
        if ((Test-Path $beforeReport) -and (Test-Path $afterReport)) {
            [void](Invoke-Step -RelativePath 'scripts\windows\43_compare_benchmarks.ps1' -Name 'Comparaison mesures Windows' -Phase 'Verify')
            [void](Invoke-Step -RelativePath 'scripts\bootstrap\12_validate_v4.ps1' -Arguments @{ OptimizationProfiles=$OptimizationProfiles } -Name 'Qualification optimisation Windows' -Phase 'FinalValidation')
        } else {
            Write-WpcStatus -Status 'ACTION_REQUISE' -Message 'Preuves avant/après optimisation absentes' -Detail 'Exécute une fois .\install.ps1 -Mode Apply pour générer les mesures factuelles, puis relance Verify.' -Context $context
        }

        if ($ValidateHardware) { Invoke-HardwareQualification }
        else { Write-WpcStatus -Status 'IGNORE' -Message 'Qualification physique non demandée' -Detail 'Ajoute -ValidateHardware pour vérifier aussi les preuves BIOS/placement/stabilité.' -Context $context }

        if ($ValidateWsl -or $ValidateDevOps) { [void](Invoke-Step -RelativePath 'scripts\bootstrap\14_validate_wsl_v6.ps1' -Arguments @{ WslProfile=$WslProfile; Distribution=$Distribution } -Name 'Qualification runtime WSL2' -Phase 'FinalValidation') }
        else { Write-WpcStatus -Status 'IGNORE' -Message 'Qualification runtime WSL2 non demandée' -Detail 'Ajoute -ValidateWsl.' -Context $context }

        if ($ValidateDevOps) { [void](Invoke-Step -RelativePath 'scripts\bootstrap\09_validate_devops.ps1' -Arguments @{ Distribution=$Distribution; LinuxUser=$WslUser } -Name 'Qualification stack DevOps' -Phase 'FinalValidation') }
        else { Write-WpcStatus -Status 'IGNORE' -Message 'Qualification DevOps non demandée' -Detail 'Ajoute -ValidateDevOps après installation de la stack.' -Context $context }

        if ($ValidateOpenClawAI) { [void](Invoke-Step -RelativePath 'scripts\bootstrap\15_openclaw_ai.ps1' -Arguments @{ Mode='Verify'; Root=$OpenClawRoot; ControlPlanePath=$OpenClawControlPlanePath; RepositoryRef=$OpenClawRepositoryRef } -Name 'Qualification OpenClaw/OpenRouter' -Phase 'FinalValidation') }
        else { Write-WpcStatus -Status 'IGNORE' -Message 'Qualification OpenClaw non demandée' -Detail 'Ajoute -ValidateOpenClawAI.' -Context $context }
        $runSuccess = $true
        return
    }

    # APPLY: établir tout le plan depuis Verify AVANT la première mutation.
    $script:plan = @()
    Add-PlanItem -Name 'Applications WinGet' -VerifyRelativePath 'scripts\bootstrap\03_apps.ps1' -VerifyArguments @{ Mode='Verify' } -ApplyRelativePath 'scripts\bootstrap\03_apps.ps1' -ApplyArguments @{ Mode='Apply' }
    Add-PlanItem -Name 'Réglages Windows de base' -VerifyRelativePath 'scripts\windows\10_tune.ps1' -VerifyArguments @{ Mode='Verify' } -ApplyRelativePath 'scripts\windows\10_tune.ps1' -ApplyArguments @{ Mode='Apply' }
    foreach ($profile in $OptimizationProfiles) {
        Add-PlanItem -Name "Profil optimisation $profile" -VerifyRelativePath 'scripts\windows\40_v4_optimize.ps1' -VerifyArguments @{ Mode='Verify'; Profile=$profile } -ApplyRelativePath 'scripts\windows\40_v4_optimize.ps1' -ApplyArguments @{ Mode='Apply'; Profile=$profile }
    }
    Add-PlanItem -Name 'Réactivité Windows' -VerifyRelativePath 'scripts\windows\53_responsiveness_v8.ps1' -VerifyArguments @{ Mode='Verify' } -ApplyRelativePath 'scripts\windows\53_responsiveness_v8.ps1' -ApplyArguments @{ Mode='Apply' }
    Add-PlanItem -Name 'WSL2' -VerifyRelativePath 'scripts\bootstrap\06_wsl.ps1' -VerifyArguments @{ Mode='Verify'; Profile=$WslProfile; Distribution=$Distribution; InstallLocation=$WslInstallLocation } -ApplyRelativePath 'scripts\bootstrap\06_wsl.ps1' -ApplyArguments @{ Mode='Apply'; Profile=$WslProfile; Distribution=$Distribution; InstallLocation=$WslInstallLocation }
    Add-PlanItem -Name 'Utilisateur WSL' -VerifyRelativePath 'scripts\bootstrap\07_wsl_user.ps1' -VerifyArguments @{ Mode='Verify'; Distribution=$Distribution; LinuxUser=$WslUser } -ApplyRelativePath 'scripts\bootstrap\07_wsl_user.ps1' -ApplyArguments @{ Mode='Apply'; Distribution=$Distribution; LinuxUser=$WslUser }
    Add-PlanItem -Name 'Poste de travail' -VerifyRelativePath 'scripts\bootstrap\10_workstation.ps1' -VerifyArguments @{ Mode='Verify' } -ApplyRelativePath 'scripts\bootstrap\10_workstation.ps1' -ApplyArguments @{ Mode='Apply' }
    Add-PlanItem -Name 'Exclusions Defender approuvées' -VerifyRelativePath 'scripts\defender\03_apply_approved_exclusions.ps1' -VerifyArguments @{ Mode='Verify' } -ApplyRelativePath 'scripts\defender\03_apply_approved_exclusions.ps1' -ApplyArguments @{ Mode='Apply' }

    if ($InstallDevOps) {
        Add-PlanItem -Name 'Stack DevOps WSL' -VerifyRelativePath 'scripts\bootstrap\09_validate_devops.ps1' -VerifyArguments @{ Distribution=$Distribution; LinuxUser=$WslUser } -ApplyRelativePath 'scripts\bootstrap\08_devops.ps1' -ApplyArguments @{ Distribution=$Distribution; LinuxUser=$WslUser }
    } else {
        Write-WpcStatus -Status 'IGNORE' -Message 'Stack DevOps non demandée dans cet Apply' -Detail 'Ajoute -InstallDevOps ou utilise -FullInstall pour lʼinclure.' -Context $context
    }

    if ($InstallOpenClawAI) {
        Add-PlanItem -Name 'OpenClaw/OpenRouter' -VerifyRelativePath 'scripts\bootstrap\15_openclaw_ai.ps1' -VerifyArguments @{ Mode='Verify'; Root=$OpenClawRoot; ControlPlanePath=$OpenClawControlPlanePath; RepositoryRef=$OpenClawRepositoryRef } -ApplyRelativePath 'scripts\bootstrap\15_openclaw_ai.ps1' -ApplyArguments @{ Mode='Apply'; Root=$OpenClawRoot; ControlPlanePath=$OpenClawControlPlanePath; RepositoryRef=$OpenClawRepositoryRef }
    } else {
        Write-WpcStatus -Status 'IGNORE' -Message 'OpenClaw/OpenRouter non demandé dans cet Apply' -Detail 'Ajoute -InstallOpenClawAI ou utilise -FullInstall.' -Context $context
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
        if (-not $SkipV4RestorePoint) {
            [void](Invoke-Step -RelativePath 'scripts\windows\41_restore_point.ps1' -Name 'Point de restauration pré-changements' -Phase 'Safety')
        } else {
            Write-WpcStatus -Status 'AVERTISSEMENT' -Message 'Point de restauration ignoré explicitement' -Detail '-SkipV4RestorePoint a été fourni.' -Context $context
        }
        [void](Invoke-Step -RelativePath 'scripts\windows\42_benchmark.ps1' -Arguments @{ Stage='before' } -Name 'Mesure avant changements' -Phase 'Measurement')
    } else {
        Write-WpcStatus -Status 'DEJA_OK' -Message 'Installation demandée déjà conforme' -Detail 'Aucune modification système, réinstallation ou point de restauration nʼest nécessaire.' -Context $context
    }

    Invoke-PlannedItems

    # Les mesures restent factuelles; sur une relance totalement conforme on ne réécrit pas inutilement les preuves existantes.
    if ($pending.Count -gt 0) {
        [void](Invoke-Step -RelativePath 'scripts\windows\42_benchmark.ps1' -Arguments @{ Stage='after' } -Name 'Mesure après changements' -Phase 'Measurement')
        [void](Invoke-Step -RelativePath 'scripts\windows\43_compare_benchmarks.ps1' -Name 'Comparaison avant/après' -Phase 'Measurement')
    } else {
        $beforeReport = Join-Path $RepoRoot 'reports\windows\v4-benchmark-before.json'
        $afterReport = Join-Path $RepoRoot 'reports\windows\v4-benchmark-after.json'
        if (-not ((Test-Path $beforeReport) -and (Test-Path $afterReport))) {
            Write-WpcStatus -Status 'ANALYSE' -Message 'Preuves dʼoptimisation absentes malgré configuration conforme' -Detail 'Création de deux snapshots non mutatifs pour disposer dʼune base de validation.' -Context $context
            [void](Invoke-Step -RelativePath 'scripts\windows\42_benchmark.ps1' -Arguments @{ Stage='before' } -Name 'Mesure de référence' -Phase 'Measurement')
            [void](Invoke-Step -RelativePath 'scripts\windows\42_benchmark.ps1' -Arguments @{ Stage='after' } -Name 'Mesure de confirmation' -Phase 'Measurement')
            [void](Invoke-Step -RelativePath 'scripts\windows\43_compare_benchmarks.ps1' -Name 'Comparaison de confirmation' -Phase 'Measurement')
        }
    }

    [void](Invoke-Step -RelativePath 'scripts\bootstrap\05_defender.ps1' -Name 'Microsoft Defender' -Phase 'FinalValidation')
    [void](Invoke-Step -RelativePath 'scripts\bootstrap\11_validate_v3.ps1' -Arguments @{ WslProfile=$WslProfile; Distribution=$Distribution; InstallLocation=$WslInstallLocation } -Name 'Qualification Windows' -Phase 'FinalValidation')
    [void](Invoke-Step -RelativePath 'scripts\bootstrap\12_validate_v4.ps1' -Arguments @{ OptimizationProfiles=$OptimizationProfiles } -Name 'Qualification optimisation Windows' -Phase 'FinalValidation')

    if ($ValidateHardware) { Invoke-HardwareQualification }
    else { Write-WpcStatus -Status 'IGNORE' -Message 'Qualification physique non demandée' -Detail 'Le script ne suppose jamais les données BIOS/placement/stabilité.' -Context $context }

    if ($ValidateWsl -or $ValidateDevOps) { [void](Invoke-Step -RelativePath 'scripts\bootstrap\14_validate_wsl_v6.ps1' -Arguments @{ WslProfile=$WslProfile; Distribution=$Distribution } -Name 'Qualification runtime WSL2' -Phase 'FinalValidation') }
    if ($ValidateDevOps) { [void](Invoke-Step -RelativePath 'scripts\bootstrap\09_validate_devops.ps1' -Arguments @{ Distribution=$Distribution; LinuxUser=$WslUser } -Name 'Qualification stack DevOps' -Phase 'FinalValidation') }
    if ($ValidateOpenClawAI) { [void](Invoke-Step -RelativePath 'scripts\bootstrap\15_openclaw_ai.ps1' -Arguments @{ Mode='Verify'; Root=$OpenClawRoot; ControlPlanePath=$OpenClawControlPlanePath; RepositoryRef=$OpenClawRepositoryRef } -Name 'Qualification OpenClaw/OpenRouter' -Phase 'FinalValidation') }

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