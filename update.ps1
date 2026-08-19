[CmdletBinding()]
param(
    [ValidateSet('Audit','Apply','Verify')]
    [string]$Mode = 'Audit',
    [switch]$IncludeDrivers,
    [switch]$IncludeOptionalUpdates,
    [switch]$IncludeUnknownPackages,
    [string]$Distribution = 'Ubuntu',
    [string]$LinuxUser = '',
    [switch]$PlanOnly,
    [switch]$NonInteractive,
    [switch]$Yes,
    [switch]$NoRestartPrompt
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$runtimeModule = Join-Path $repoRoot 'scripts\core\runtime.psm1'
$rebootStateModule = Join-Path $repoRoot 'scripts\core\reboot-state.psm1'
$policyPath = Join-Path $repoRoot 'config\updates\v11.json'
if (-not (Test-Path $runtimeModule)) { throw "Moteur d'orchestration absent: $runtimeModule" }
if (-not (Test-Path $rebootStateModule)) { throw "Détection de redémarrage Windows absente: $rebootStateModule" }
if (-not (Test-Path $policyPath)) { throw "Politique de mises à jour absente: $policyPath" }
Import-Module $runtimeModule -Force
Import-Module $rebootStateModule -Force
$policy = Get-Content -Raw $policyPath | ConvertFrom-Json
$context = New-WpcRunContext -RepoRoot $repoRoot -Mode "Update-$Mode" -NonInteractive:$NonInteractive
$context.OrchestratorLogPath = Join-Path $repoRoot 'logs\updates\system-update.log'

$windowsUpdate = Join-Path $repoRoot 'scripts\updates\10_windows_update.ps1'
$wingetUpdate = Join-Path $repoRoot 'scripts\updates\20_winget_update.ps1'
$wslUpdate = Join-Path $repoRoot 'scripts\updates\30_wsl_update.ps1'
$ubuntuUpdate = Join-Path $repoRoot 'scripts\updates\40_ubuntu_update.ps1'
$devopsUpdate = Join-Path $repoRoot 'scripts\updates\50_devops_pinned.ps1'
$vscodeUpdate = Join-Path $repoRoot 'scripts\updates\60_vscode_extensions_update.ps1'
foreach ($path in @($windowsUpdate,$wingetUpdate,$wslUpdate,$ubuntuUpdate,$devopsUpdate,$vscodeUpdate)) {
    if (-not (Test-Path $path)) { throw "Composant de mise à jour absent: $path" }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-WindowsRebootRequired {
    return [bool](Get-WpcPendingRebootState).Pending
}

function Test-UbuntuRebootRequired {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return $false }
    try {
        & wsl.exe --distribution $Distribution --user root --exec test -e /var/run/reboot-required 2>$null
        $code = $LASTEXITCODE
        $global:LASTEXITCODE = 0
        return ($code -eq 0)
    } catch { return $false }
}

function New-Args {
    param([string]$ComponentMode,[string]$Kind)
    switch ($Kind) {
        'Windows' { return @{ Mode=$ComponentMode; IncludeDrivers=$IncludeDrivers; IncludeOptionalUpdates=$IncludeOptionalUpdates } }
        'WinGet' { return @{ Mode=$ComponentMode; IncludeUnknownPackages=$IncludeUnknownPackages } }
        'WSL' { return @{ Mode=$ComponentMode } }
        'Ubuntu' { return @{ Mode=$ComponentMode; Distribution=$Distribution; LinuxUser=$LinuxUser } }
        'DevOps' { return @{ Mode=$ComponentMode; Distribution=$Distribution; LinuxUser=$LinuxUser } }
        'VSCode' { return @{ Mode=$ComponentMode; Distribution=$Distribution; LinuxUser=$LinuxUser } }
    }
}

$components = @(
    [pscustomobject]@{ Name='Windows Update'; Kind='Windows'; Path=$windowsUpdate; AlwaysConverge=$false },
    [pscustomobject]@{ Name='Applications WinGet'; Kind='WinGet'; Path=$wingetUpdate; AlwaysConverge=$false },
    [pscustomobject]@{ Name='Runtime WSL'; Kind='WSL'; Path=$wslUpdate; AlwaysConverge=$true },
    [pscustomobject]@{ Name='Ubuntu 26.04 / APT'; Kind='Ubuntu'; Path=$ubuntuUpdate; AlwaysConverge=$false },
    [pscustomobject]@{ Name='DevOps pinned'; Kind='DevOps'; Path=$devopsUpdate; AlwaysConverge=$false },
    [pscustomobject]@{ Name='VS Code extensions'; Kind='VSCode'; Path=$vscodeUpdate; AlwaysConverge=$true }
)

Write-WpcBanner -Context $context -Title 'WINDOWS 11 CUSTOM - GESTIONNAIRE DE MISES À JOUR'
Write-WpcStatus -Status 'INFO' -Message "Mode: $Mode" -Detail "Drivers=$([bool]$IncludeDrivers) Optional=$([bool]$IncludeOptionalUpdates) WinGetUnknown=$([bool]$IncludeUnknownPackages)" -Context $context
Write-WpcStatus -Status 'INFO' -Message 'Politique de sécurité' -Detail 'Pas de BIOS/firmware, pas de dist-upgrade Ubuntu, pas dʼautoremove, pins WinGet respectés, versions DevOps pilotées par le dépôt.' -Context $context

$failures = New-Object System.Collections.Generic.List[string]
$results = New-Object System.Collections.Generic.List[object]

if ($Mode -eq 'Audit') {
    foreach ($component in $components) {
        $result = Invoke-WpcManagedScript -Context $context -Path $component.Path -Arguments (New-Args -ComponentMode 'Audit' -Kind $component.Kind) -DisplayName $component.Name -Phase 'Update-Audit' -AllowFailure
        $results.Add([pscustomobject]@{ Component=$component.Name; Outcome=$result.Outcome; Success=$result.Success })
        if (-not $result.Success) { $failures.Add("$($component.Name): $($result.Error)") }
    }
} elseif ($Mode -eq 'Verify') {
    foreach ($component in $components) {
        $result = Invoke-WpcManagedScript -Context $context -Path $component.Path -Arguments (New-Args -ComponentMode 'Verify' -Kind $component.Kind) -DisplayName $component.Name -Phase 'Update-Verify' -AllowFailure
        $results.Add([pscustomobject]@{ Component=$component.Name; Outcome=$result.Outcome; Success=$result.Success })
        if (-not $result.Success) { $failures.Add("$($component.Name): $($result.Error)") }
    }
} else {
    if (-not (Test-IsAdministrator)) {
        throw 'Mode Apply: lance PowerShell 7 en administrateur puis relance exactement la même commande.'
    }

    Write-Host ''
    Write-Host 'PLAN FACTUEL DES MISES À JOUR' -ForegroundColor Cyan
    Write-Host ('-' * 78) -ForegroundColor DarkCyan
    $plan = New-Object System.Collections.Generic.List[object]
    foreach ($component in $components) {
        if ($component.AlwaysConverge) {
            [void](Invoke-WpcManagedScript -Context $context -Path $component.Path -Arguments (New-Args -ComponentMode 'Audit' -Kind $component.Kind) -DisplayName $component.Name -Phase 'Update-Plan' -Purpose 'Probe' -AllowFailure -Quiet)
            Write-WpcStatus -Status 'A_FAIRE' -Message $component.Name -Detail 'Convergence sûre exécutée à chaque Apply; la commande sous-jacente est no-op si rien nʼest obsolète.' -Context $context
            $plan.Add([pscustomobject]@{ Component=$component; NeedsApply=$true; Reason='Convergence' })
            continue
        }

        $probe = Invoke-WpcManagedScript -Context $context -Path $component.Path -Arguments (New-Args -ComponentMode 'Verify' -Kind $component.Kind) -DisplayName $component.Name -Phase 'Update-Plan' -Purpose 'Probe' -AllowFailure -Quiet
        if ($probe.Success) {
            Write-WpcStatus -Status 'DEJA_OK' -Message $component.Name -Detail 'Aucune mise à jour sélectionnée / cible déjà conforme.' -Context $context
            $plan.Add([pscustomobject]@{ Component=$component; NeedsApply=$false; Reason='Compliant' })
        } else {
            Write-WpcStatus -Status 'A_FAIRE' -Message $component.Name -Detail 'Mise à jour ou convergence nécessaire.' -Context $context
            $plan.Add([pscustomobject]@{ Component=$component; NeedsApply=$true; Reason='Pending' })
        }
    }

    if ($PlanOnly) {
        Write-WpcStatus -Status 'OK' -Message 'PlanOnly terminé' -Detail 'Aucune mise à jour installée.' -Context $context
        [void](Complete-WpcRun -Context $context -Success $true)
        return
    }

    Confirm-WpcChanges -Context $context -Yes:$Yes

    foreach ($item in $plan) {
        $component = $item.Component
        if (-not $item.NeedsApply) {
            $results.Add([pscustomobject]@{ Component=$component.Name; Outcome='DEJA_OK'; Success=$true })
            continue
        }
        $result = Invoke-WpcManagedScript -Context $context -Path $component.Path -Arguments (New-Args -ComponentMode 'Apply' -Kind $component.Kind) -DisplayName $component.Name -Phase 'Update-Apply' -AllowFailure
        $results.Add([pscustomobject]@{ Component=$component.Name; Outcome=$result.Outcome; Success=$result.Success })
        if (-not $result.Success) {
            $failures.Add("$($component.Name): $($result.Error)")
            Write-WpcStatus -Status 'AVERTISSEMENT' -Message "$($component.Name) en échec; poursuite des catégories indépendantes." -Detail $result.Error -Context $context
        }
    }

    Write-Host ''
    Write-Host 'REVALIDATION FINALE' -ForegroundColor Cyan
    Write-Host ('-' * 78) -ForegroundColor DarkCyan
    foreach ($component in $components) {
        $verify = Invoke-WpcManagedScript -Context $context -Path $component.Path -Arguments (New-Args -ComponentMode 'Verify' -Kind $component.Kind) -DisplayName $component.Name -Phase 'Update-PostVerify' -AllowFailure
        if (-not $verify.Success) {
            $message = "$($component.Name): $($verify.Error)"
            if (-not ($failures -contains $message)) { $failures.Add($message) }
        }
    }
}

$windowsRebootState = Get-WpcPendingRebootState
$windowsReboot = [bool]$windowsRebootState.Pending
$ubuntuReboot = Test-UbuntuRebootRequired
$rebootRequired = $windowsReboot -or $ubuntuReboot

if ($rebootRequired) {
    Write-WpcStatus -Status 'ACTION_REQUISE' -Message 'Redémarrage requis' -Detail "Windows=$windowsReboot UbuntuWSL=$ubuntuReboot. Aucun redémarrage automatique sans réponse explicite." -Context $context
} else {
    Write-WpcStatus -Status 'DEJA_OK' -Message 'Aucun redémarrage requis détecté.' -Context $context
    if ($windowsRebootState.Advisory) {
        Write-WpcStatus -Status 'AVERTISSEMENT' -Message 'PendingFileRenameOperations observé' -Detail "$($windowsRebootState.PendingFileRenameOperationsCount) entrée(s) détectée(s), non bloquantes sans marqueur CBS/Windows Update." -Context $context
    }
}

$reportDir = Join-Path $repoRoot 'reports\updates'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$reportPath = Join-Path $reportDir 'latest-run.json'
$report = [ordered]@{
    SchemaVersion='1.1'
    RunId=$context.RunId
    Mode=$Mode
    CompletedAt=(Get-Date).ToString('o')
    Success=($failures.Count -eq 0)
    RebootRequired=$rebootRequired
    WindowsRebootRequired=$windowsReboot
    WindowsRebootReasons=@($windowsRebootState.Reasons)
    WindowsRebootAdvisoryReasons=@($windowsRebootState.AdvisoryReasons)
    PendingFileRenameOperationsCount=$windowsRebootState.PendingFileRenameOperationsCount
    UbuntuRebootRequired=$ubuntuReboot
    IncludeDrivers=[bool]$IncludeDrivers
    IncludeOptionalUpdates=[bool]$IncludeOptionalUpdates
    IncludeUnknownPackages=[bool]$IncludeUnknownPackages
    Results=$results.ToArray()
    Failures=$failures.ToArray()
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8

$success = ($failures.Count -eq 0)
[void](Complete-WpcRun -Context $context -Success $success -FailureMessage ($failures -join '; '))

Write-Host ''
Write-Host ('=' * 78) -ForegroundColor DarkCyan
if ($success) {
    if ($rebootRequired) {
        Write-Host 'VERDICT: MISES À JOUR APPLIQUÉES - REDÉMARRAGE REQUIS' -ForegroundColor Magenta
    } else {
        Write-Host 'VERDICT: SYSTÈME À JOUR' -ForegroundColor Green
    }
} else {
    Write-Host ("VERDICT: PARTIELLEMENT À JOUR - {0} anomalie(s)" -f $failures.Count) -ForegroundColor Yellow
    foreach ($failure in $failures) { Write-Host ("  - {0}" -f $failure) -ForegroundColor Yellow }
}
Write-Host ("Rapport: {0}" -f $reportPath) -ForegroundColor DarkGray
Write-Host ('=' * 78) -ForegroundColor DarkCyan

if ($Mode -eq 'Apply' -and $success -and $rebootRequired -and -not $NonInteractive -and -not $NoRestartPrompt) {
    $answer = (Read-Host 'Redémarrer Windows maintenant ? [O/N]').Trim().ToLowerInvariant()
    if ($answer -in @('o','oui','y','yes')) {
        Write-Host '[ACTION REQUISE] Redémarrage demandé par lʼutilisateur.' -ForegroundColor Magenta
        Restart-Computer
        return
    }
    Write-Host '[INFO] Redémarrage différé par lʼutilisateur.' -ForegroundColor Cyan
}

if (-not $success) { throw ($failures -join '; ') }
