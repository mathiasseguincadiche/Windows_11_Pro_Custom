[CmdletBinding()]
param(
    [string]$Choice = '',
    [switch]$DryRun,
    [switch]$NoPause,
    [switch]$NoClear
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = $PSScriptRoot
$InstallScript = Join-Path $RepoRoot 'install.ps1'
$UpdateScript = Join-Path $RepoRoot 'update.ps1'
$AppsScript = Join-Path $RepoRoot 'scripts\bootstrap\03_apps.ps1'

foreach ($required in @($InstallScript, $UpdateScript, $AppsScript)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Point d'entree introuvable: $required"
    }
}

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Get-PowerShellExecutable {
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($pwsh) { return $pwsh.Source }
    $windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($windowsPowerShell) { return $windowsPowerShell.Source }
    try { return (Get-Process -Id $PID).Path } catch { throw 'Aucun executable PowerShell utilisable.' }
}

function Clear-WpcScreen {
    if (-not $NoClear -and -not $DryRun) { Clear-Host }
}

function Write-Line {
    param([string]$Text = '', [ConsoleColor]$Color = [ConsoleColor]::Gray)
    Write-Host $Text -ForegroundColor $Color
}

function Write-Header {
    Clear-WpcScreen
    $admin = Test-IsAdministrator
    $adminText = if ($admin) { 'OUI' } else { 'NON' }
    $adminColor = if ($admin) { [ConsoleColor]::Green } else { [ConsoleColor]::Yellow }

    Write-Line ('=' * 78) DarkCyan
    Write-Line ' WINDOWS 11 PRO CUSTOM - CENTRE DE CONTROLE V12' Cyan
    Write-Line ('=' * 78) DarkCyan
    Write-Host ' PowerShell : ' -NoNewline -ForegroundColor DarkGray
    Write-Host $PSVersionTable.PSVersion -ForegroundColor White
    Write-Host ' Administrateur : ' -NoNewline -ForegroundColor DarkGray
    Write-Host $adminText -ForegroundColor $adminColor
    Write-Host ' Depot : ' -NoNewline -ForegroundColor DarkGray
    Write-Host $RepoRoot -ForegroundColor White
    Write-Line ('-' * 78) DarkCyan
}

function Pause-WpcMenu {
    if ($NoPause -or $DryRun -or -not [string]::IsNullOrWhiteSpace($Choice)) { return }
    Write-Host ''
    [void](Read-Host 'Appuie sur Entree pour revenir au menu')
}

function Confirm-WpcAction {
    param(
        [Parameter(Mandatory)][string]$Message,
        [switch]$Dangerous
    )
    if ($DryRun) { return $true }
    Write-Host ''
    if ($Dangerous) {
        Write-Line '[ATTENTION] Cette action modifie ou restaure des reglages geres par le depot.' Yellow
    }
    $answer = (Read-Host "$Message [O/N]").Trim().ToLowerInvariant()
    return $answer -in @('o','oui','y','yes')
}

function Convert-ArgumentsForElevation {
    param([hashtable]$Arguments)
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($key in $Arguments.Keys) {
        $value = $Arguments[$key]
        if ($value -is [System.Management.Automation.SwitchParameter]) {
            if ($value.IsPresent) { $list.Add("-$key") }
            continue
        }
        if ($value -is [bool]) {
            if ($value) { $list.Add("-$key") }
            continue
        }
        if ($null -eq $value) { continue }
        if ($value -is [Array]) {
            if ($value.Count -gt 0) {
                $list.Add("-$key")
                foreach ($item in $value) { $list.Add([string]$item) }
            }
            continue
        }
        $list.Add("-$key")
        $list.Add([string]$value)
    }
    return @($list)
}

function Format-WpcCommand {
    param([string]$Path, [hashtable]$Arguments)
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add("& '$Path'")
    foreach ($key in $Arguments.Keys) {
        $value = $Arguments[$key]
        if ($value -is [System.Management.Automation.SwitchParameter]) {
            if ($value.IsPresent) { $parts.Add("-$key") }
        } elseif ($value -is [bool]) {
            if ($value) { $parts.Add("-$key") }
        } elseif ($value -is [Array]) {
            if ($value.Count -gt 0) {
                $quoted = @($value | ForEach-Object { "'$_'" }) -join ','
                $parts.Add("-$key $quoted")
            }
        } elseif ($null -ne $value) {
            $parts.Add("-$key '$value'")
        }
    }
    return ($parts -join ' ')
}

function Invoke-WpcRepoScript {
    param(
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$Path,
        [hashtable]$Arguments = @{},
        [switch]$RequiresAdmin
    )

    Write-Host ''
    Write-Line ("[ACTION] {0}" -f $DisplayName) Cyan
    Write-Line ("Commande: {0}" -f (Format-WpcCommand -Path $Path -Arguments $Arguments)) DarkGray

    if ($DryRun) {
        Write-Line '[DRY-RUN] Aucune commande executee.' Green
        return $true
    }

    try {
        if ($RequiresAdmin -and -not (Test-IsAdministrator)) {
            Write-Line '[ADMIN] Elevation UAC requise. Une fenetre PowerShell admin va etre ouverte.' Yellow
            $exe = Get-PowerShellExecutable
            $argList = New-Object System.Collections.Generic.List[string]
            $argList.Add('-NoProfile')
            $argList.Add('-ExecutionPolicy')
            $argList.Add('Bypass')
            $argList.Add('-File')
            $argList.Add($Path)
            foreach ($arg in (Convert-ArgumentsForElevation -Arguments $Arguments)) { $argList.Add($arg) }
            $process = Start-Process -FilePath $exe -Verb RunAs -ArgumentList @($argList) -Wait -PassThru
            if ($process.ExitCode -ne 0) { throw "Le processus eleve a retourne le code $($process.ExitCode)." }
        } else {
            & $Path @Arguments
        }
        Write-Line '[TERMINE] Action terminee.' Green
        return $true
    } catch {
        Write-Line ("[ERREUR] {0}" -f $_.Exception.Message) Red
        return $false
    }
}

function Invoke-OpenFolder {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Label)
    Write-Host ''
    Write-Line ("[ACTION] Ouvrir {0}" -f $Label) Cyan
    if ($DryRun) {
        Write-Line ("[DRY-RUN] explorer.exe '$Path'") Green
        return
    }
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    Start-Process explorer.exe -ArgumentList @($Path)
}

function Invoke-MainAction {
    param([Parameter(Mandatory)][string]$Selected)

    switch ($Selected.ToLowerInvariant()) {
        '1' {
            if (Confirm-WpcAction -Message 'Lancer l installation COMPLETE de la workstation') {
                [void](Invoke-WpcRepoScript -DisplayName 'Installation complete' -Path $InstallScript -Arguments @{ Mode='Apply'; FullInstall=[switch]::Present } -RequiresAdmin)
            }
        }
        '2' {
            if (Confirm-WpcAction -Message 'Installer ou reparer uniquement les logiciels Windows geres par WinGet') {
                [void](Invoke-WpcRepoScript -DisplayName 'Installation / reparation des logiciels' -Path $AppsScript -Arguments @{ Mode='Apply' } -RequiresAdmin)
            }
        }
        '3' {
            if (Confirm-WpcAction -Message 'Lancer les mises a jour completes du systeme') {
                [void](Invoke-WpcRepoScript -DisplayName 'System Update Manager V11' -Path $UpdateScript -Arguments @{ Mode='Apply' } -RequiresAdmin)
            }
        }
        '4.1' {
            [void](Invoke-WpcRepoScript -DisplayName 'Creer une sauvegarde V7' -Path $InstallScript -Arguments @{ BackupAction='Create' } -RequiresAdmin)
        }
        '4.2' {
            [void](Invoke-WpcRepoScript -DisplayName 'Verifier une sauvegarde V7' -Path $InstallScript -Arguments @{ BackupAction='Verify' })
        }
        '5.1' {
            Write-Line '[SECURITE] Cette option genere uniquement un plan de restauration. Elle ne restaure rien automatiquement.' Yellow
            [void](Invoke-WpcRepoScript -DisplayName 'Plan de restauration V7' -Path $InstallScript -Arguments @{ BackupAction='RestorePlan' })
        }
        '5.2' {
            if (Confirm-WpcAction -Message 'Rollback des reglages Windows geres par le depot' -Dangerous) {
                [void](Invoke-WpcRepoScript -DisplayName 'Rollback des reglages geres' -Path $InstallScript -Arguments @{ Mode='Rollback' } -RequiresAdmin)
            }
        }
        '6' {
            [void](Invoke-WpcRepoScript -DisplayName 'Audit et diagnostic global' -Path $InstallScript -Arguments @{ Mode='Audit' })
        }
        '7' {
            [void](Invoke-WpcRepoScript -DisplayName 'Verification de conformite globale' -Path $InstallScript -Arguments @{ Mode='Verify' })
        }
        '8.1' {
            if (Confirm-WpcAction -Message 'Installer ou reparer WSL2 et la stack DevOps') {
                [void](Invoke-WpcRepoScript -DisplayName 'WSL2 + stack DevOps' -Path $InstallScript -Arguments @{ Mode='Apply'; InstallDevOps=[switch]::Present; ValidateWsl=[switch]::Present; ValidateDevOps=[switch]::Present } -RequiresAdmin)
            }
        }
        '8.2' {
            if (Confirm-WpcAction -Message 'Installer ou reparer OpenClaw / OpenRouter') {
                [void](Invoke-WpcRepoScript -DisplayName 'OpenClaw / OpenRouter' -Path $InstallScript -Arguments @{ Mode='Apply'; InstallOpenClawAI=[switch]::Present; ValidateOpenClawAI=[switch]::Present } -RequiresAdmin)
            }
        }
        '8.3' {
            [void](Invoke-WpcRepoScript -DisplayName 'Qualification materielle guidee' -Path $InstallScript -Arguments @{ Mode='Verify'; ValidateHardware=[switch]::Present } -RequiresAdmin)
        }
        '9.1' { Invoke-OpenFolder -Path (Join-Path $RepoRoot 'logs') -Label 'les journaux' }
        '9.2' { Invoke-OpenFolder -Path (Join-Path $RepoRoot 'reports') -Label 'les rapports' }
        '10' { Show-Help }
        default { Write-Line "[ERREUR] Choix inconnu: $Selected" Red }
    }
}

function Show-BackupMenu {
    while ($true) {
        Write-Header
        Write-Line ' SAUVEGARDE' White
        Write-Line ''
        Write-Line '  1. Creer une nouvelle sauvegarde' White
        Write-Line '  2. Verifier une sauvegarde existante' White
        Write-Line '  0. Retour' DarkGray
        Write-Host ''
        $value = (Read-Host 'Ton choix').Trim()
        if ($value -eq '0') { return }
        if ($value -in @('1','2')) {
            Invoke-MainAction -Selected "4.$value"
            Pause-WpcMenu
        }
    }
}

function Show-RestoreMenu {
    while ($true) {
        Write-Header
        Write-Line ' RESTAURATION' White
        Write-Line ''
        Write-Line '  1. Generer un plan de restauration V7 (aucune ecriture)' White
        Write-Line '  2. Rollback des reglages geres par le depot' Yellow
        Write-Line '  0. Retour' DarkGray
        Write-Host ''
        Write-Line 'La restauration complete destructive reste volontairement non automatique.' DarkGray
        $value = (Read-Host 'Ton choix').Trim()
        if ($value -eq '0') { return }
        if ($value -in @('1','2')) {
            Invoke-MainAction -Selected "5.$value"
            Pause-WpcMenu
        }
    }
}

function Show-ComponentsMenu {
    while ($true) {
        Write-Header
        Write-Line ' COMPOSANTS SPECIFIQUES' White
        Write-Line ''
        Write-Line '  1. WSL2 + stack DevOps + validation' White
        Write-Line '  2. OpenClaw / OpenRouter + validation' White
        Write-Line '  3. Qualification materielle guidee' White
        Write-Line '  0. Retour' DarkGray
        Write-Host ''
        $value = (Read-Host 'Ton choix').Trim()
        if ($value -eq '0') { return }
        if ($value -in @('1','2','3')) {
            Invoke-MainAction -Selected "8.$value"
            Pause-WpcMenu
        }
    }
}

function Show-LogsMenu {
    while ($true) {
        Write-Header
        Write-Line ' JOURNAUX ET RAPPORTS' White
        Write-Line ''
        Write-Line '  1. Ouvrir logs\' White
        Write-Line '  2. Ouvrir reports\' White
        Write-Line '  0. Retour' DarkGray
        Write-Host ''
        $value = (Read-Host 'Ton choix').Trim()
        if ($value -eq '0') { return }
        if ($value -in @('1','2')) {
            Invoke-MainAction -Selected "9.$value"
            Pause-WpcMenu
        }
    }
}

function Show-Help {
    Write-Header
    Write-Line ' AIDE RAPIDE' White
    Write-Line ''
    Write-Line 'Installation complete' Cyan
    Write-Line '  Converge toute la workstation avec install.ps1 -FullInstall.' DarkGray
    Write-Line 'Logiciels' Cyan
    Write-Line '  Installe uniquement les applications WinGet manquantes ou non conformes.' DarkGray
    Write-Line 'Mises a jour' Cyan
    Write-Line '  Lance V11: Windows Update, WinGet, WSL, Ubuntu/APT, VS Code et DevOps pinned.' DarkGray
    Write-Line 'Sauvegarde' Cyan
    Write-Line '  Cree ou valide une sauvegarde via les mecanismes V7 existants.' DarkGray
    Write-Line 'Restauration' Cyan
    Write-Line '  Genere un plan de restauration ou rollback les reglages geres. Pas de restauration destructive automatique.' DarkGray
    Write-Line 'Audit / verification' Cyan
    Write-Line '  Audit observe; Verify exige la conformite des composants verifies.' DarkGray
    Write-Line ''
    Write-Line 'Lancement direct possible pour automatisation/test:' White
    Write-Line '  .\menu.ps1 -Choice 3 -DryRun' DarkGray
    Write-Line '  .\menu.ps1 -Choice 8.1 -DryRun' DarkGray
}

function Show-MainMenu {
    while ($true) {
        Write-Header
        Write-Line '  1. Installation complete' White
        Write-Line '  2. Installation / reparation des logiciels' White
        Write-Line '  3. Mises a jour completes' White
        Write-Line '  4. Sauvegarde' White
        Write-Line '  5. Restauration / rollback' White
        Write-Line '  6. Audit et diagnostic complet' White
        Write-Line '  7. Verification de conformite' White
        Write-Line '  8. Composants specifiques' White
        Write-Line '  9. Journaux et rapports' White
        Write-Line ' 10. Aide' White
        Write-Line '  0. Quitter' DarkGray
        Write-Host ''
        Write-Line 'Les actions deja conformes restent idempotentes: elles ne sont pas refaites inutilement.' DarkGray
        $selected = (Read-Host 'Que veux-tu faire ?').Trim()
        switch ($selected) {
            '0' { return }
            '4' { Show-BackupMenu }
            '5' { Show-RestoreMenu }
            '8' { Show-ComponentsMenu }
            '9' { Show-LogsMenu }
            default {
                Invoke-MainAction -Selected $selected
                Pause-WpcMenu
            }
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($Choice)) {
    Write-Header
    Invoke-MainAction -Selected $Choice
    exit 0
}

Show-MainMenu
