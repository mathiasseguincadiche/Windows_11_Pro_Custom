#Requires -Version 7.6
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
$VersionPath = Join-Path $RepoRoot 'VERSION'
if (-not (Test-Path -LiteralPath $VersionPath)) { throw "Version globale introuvable: $VersionPath" }
$ProjectRelease = (Get-Content -Raw -LiteralPath $VersionPath).Trim()
if ($ProjectRelease -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION invalide: $ProjectRelease" }
$InstallScript = Join-Path $RepoRoot 'install.ps1'
$UpdateScript = Join-Path $RepoRoot 'update.ps1'
$AppsScript = Join-Path $RepoRoot 'scripts\bootstrap\03_apps.ps1'
$ExternalAuthAuditScript = Join-Path $RepoRoot 'scripts\bootstrap\15_external_auth.ps1'
$ExternalAuthInteractiveScript = Join-Path $RepoRoot 'scripts\bootstrap\16_external_auth_interactive.ps1'
$FingerprintScript = Join-Path $RepoRoot 'scripts\windows\90_workstation_fingerprint.ps1'
$RestoreDrillScript = Join-Path $RepoRoot 'scripts\backup\63_restore_drill.ps1'
$RebootStateModule = Join-Path $RepoRoot 'scripts\core\reboot-state.psm1'
$PowerShellRuntimeModule = Join-Path $RepoRoot 'scripts\core\powershell-runtime.psm1'
$script:LastActionRequiresReboot = $false

foreach ($required in @($InstallScript,$UpdateScript,$AppsScript,$ExternalAuthAuditScript,$ExternalAuthInteractiveScript,$FingerprintScript,$RestoreDrillScript,$RebootStateModule,$PowerShellRuntimeModule)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Point d'entree introuvable: $required" }
}
Import-Module $PowerShellRuntimeModule -Force
$PowerShellRuntimeFact = Assert-WpcPowerShellRuntime -MinimumVersion ([version]'7.6.4') -RequireWindows -PassThru
Import-Module $RebootStateModule -Force

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}
function Get-PowerShellExecutable {
    $processPath = [string]$PowerShellRuntimeFact.ExecutablePath
    if ([string]::IsNullOrWhiteSpace($processPath) -or -not (Test-Path -LiteralPath $processPath)) {
        $pwsh = Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $pwsh) { throw 'pwsh.exe est introuvable alors que le runtime PowerShell 7 a déjà été validé.' }
        $processPath = [string]$pwsh.Source
    }
    if ([IO.Path]::GetFileName($processPath) -ine 'pwsh.exe') { throw "Exécutable PowerShell non autorisé: $processPath. pwsh.exe est requis." }
    return $processPath
}
function Assert-WpcRebootStateCommands {
    $requiredCommands=@('Get-WpcPendingRebootState','Test-WpcRebootRequiredMessage')
    $missing=@($requiredCommands|Where-Object {-not (Get-Command $_ -ErrorAction SilentlyContinue)})
    if ($missing.Count -gt 0) {Import-Module $RebootStateModule -Force;$missing=@($requiredCommands|Where-Object {-not (Get-Command $_ -ErrorAction SilentlyContinue)})}
    if ($missing.Count -gt 0) {throw "Contrat reboot-state incomplet dans le centre de contrôle: $($missing -join ', ')."}
}
function Clear-WpcScreen {if (-not $NoClear -and -not $DryRun) {Clear-Host}}
function Write-Line {param([string]$Text='',[ConsoleColor]$Color=[ConsoleColor]::Gray);Write-Host $Text -ForegroundColor $Color}
function Write-WpcLiveChildLine {
    param([AllowEmptyString()][string]$Line='')
    if ([string]::IsNullOrWhiteSpace($Line)) { Write-Host ''; return }
    $plain = $Line -replace "`e\[[0-9;?]*[ -/]*[@-~]", ''
    $trimmed = $plain.TrimStart()
    $color = [ConsoleColor]::Gray
    if ($trimmed -match '^={8,}$') { $color = [ConsoleColor]::DarkCyan }
    elseif ($trimmed -match '^(ETAPE|SOUS-ETAPE|COMPOSANT)\b') { $color = [ConsoleColor]::Cyan }
    elseif ($trimmed -match '^\[(OK|DEJA OK|DÉJÀ OK|FAIT|READY|TERMINE)\]') { $color = [ConsoleColor]::Green }
    elseif ($trimmed -match '^\[(ERREUR|ERROR|KO|FAILED)\]') { $color = [ConsoleColor]::Red }
    elseif ($trimmed -match '^\[(A FAIRE|À FAIRE|AVERTISSEMENT|WARN|WARNING|ATTENTE|EN ATTENTE)\]') { $color = [ConsoleColor]::Yellow }
    elseif ($trimmed -match '^\[(ACTION REQUISE|ACTION|USER ACTION)\]') { $color = [ConsoleColor]::Magenta }
    elseif ($trimmed -match '^\[(EN COURS|ANALYSE|INFO|ACTIF)\]') { $color = [ConsoleColor]::Cyan }
    elseif ($trimmed -match '^(Objectif|Script|Journal|Demarre|Démarré|Temps total|Run|Logs|Release|PowerShell)\s*:') { $color = [ConsoleColor]::DarkGray }
    Write-Host $plain -ForegroundColor $color
}
function Invoke-WpcVisibleChildProcess {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string[]]$ArgumentList
    )
    & $Executable @ArgumentList 2>&1 | ForEach-Object {
        $text = [string]$_
        $parts = @($text -split "`r?`n")
        if ($parts.Count -eq 0) { Write-WpcLiveChildLine -Line ''; return }
        foreach ($line in $parts) { Write-WpcLiveChildLine -Line $line }
    }
    return [int]$LASTEXITCODE
}
function Write-Header {
    Clear-WpcScreen
    $admin=Test-IsAdministrator;$adminText=if ($admin) {'OUI'} else {'NON'};$adminColor=if ($admin) {[ConsoleColor]::Green} else {[ConsoleColor]::Yellow}
    Write-Line ('='*78) DarkCyan;Write-Line ' WINDOWS 11 PRO CUSTOM - CENTRE DE CONTROLE' Cyan;Write-Line ('='*78) DarkCyan
    Write-Host ' Release : ' -NoNewline -ForegroundColor DarkGray;Write-Host $ProjectRelease -ForegroundColor White
    Write-Host ' PowerShell : ' -NoNewline -ForegroundColor DarkGray;Write-Host ("{0} | Core | x64 | pwsh.exe" -f $PowerShellRuntimeFact.Version) -ForegroundColor White
    Write-Host ' Runtime minimum : ' -NoNewline -ForegroundColor DarkGray;Write-Host '7.6.4' -ForegroundColor Green
    Write-Host ' Administrateur : ' -NoNewline -ForegroundColor DarkGray;Write-Host $adminText -ForegroundColor $adminColor
    Write-Host ' Depot : ' -NoNewline -ForegroundColor DarkGray;Write-Host $RepoRoot -ForegroundColor White
    Write-Line ('-'*78) DarkCyan
}
function Pause-WpcMenu {if ($NoPause -or $DryRun -or -not [string]::IsNullOrWhiteSpace($Choice)) {return};Write-Host '';[void](Read-Host 'Appuie sur Entree pour revenir au menu')}
function Confirm-WpcAction {
    param([Parameter(Mandatory)][string]$Message,[switch]$Dangerous)
    if ($DryRun) {return $true};Write-Host '';if ($Dangerous) {Write-Line '[ATTENTION] Cette action modifie ou restaure des reglages geres par le depot.' Yellow}
    $answer=(Read-Host "$Message [O/N]").Trim().ToLowerInvariant();return $answer -in @('o','oui','y','yes')
}
function Read-WpcMenuValue {param([Parameter(Mandatory)][string]$Prompt,[Parameter(Mandatory)][string]$DryRunValue);if ($DryRun) {return $DryRunValue};$value=(Read-Host $Prompt).Trim();if ([string]::IsNullOrWhiteSpace($value)) {throw "Valeur obligatoire absente: $Prompt"};return $value}
function Invoke-WpcRestartComputer {
    if ($DryRun) {Write-Line '[DRY-RUN] Redemarrage Windows demande.' Green;return}
    Write-Line '[ACTION] Redemarrage Windows en cours. Apres reconnexion, relance Installation complete.' Yellow
    if (Test-IsAdministrator) {Restart-Computer -Force;return}
    $shutdown=Join-Path $env:WINDIR 'System32\shutdown.exe';Start-Process -FilePath $shutdown -Verb RunAs -ArgumentList @('/r','/t','0')|Out-Null
}
function Invoke-WpcPendingRebootGate {
    param([string]$Context='avant la convergence',[switch]$ForceRequired)
    if ($DryRun) {return $false};Assert-WpcRebootStateCommands;$state=Get-WpcPendingRebootState;if (-not $state.Pending -and -not $ForceRequired) {return $false}
    $reasonText=if ($state.Pending) {$state.Reasons -join ', '} else {'demande explicite de l orchestrateur'};Write-Host ''
    Write-Line ("[ACTION REQUISE] Un redemarrage Windows est requis {0}: {1}." -f $Context,$reasonText) Yellow
    Write-Line 'La convergence reste volontairement bloquee tant que Windows n a pas finalise ce redemarrage.' DarkGray
    Write-Line 'Apres reboot, relance simplement Installation complete: les etapes deja conformes seront ignorees.' DarkGray
    if (-not [string]::IsNullOrWhiteSpace($Choice)) {Write-Line 'Mode -Choice: aucun redemarrage automatique. Redemarre Windows puis relance la commande.' Yellow;return $true}
    if (Confirm-WpcAction -Message 'Redemarrer Windows maintenant pour reprendre ensuite l installation') {Invoke-WpcRestartComputer};return $true
}
function Convert-ArgumentsForElevation {
    param([hashtable]$Arguments)
    $list=New-Object System.Collections.Generic.List[string]
    foreach ($key in $Arguments.Keys) {$value=$Arguments[$key];if ($value -is [System.Management.Automation.SwitchParameter]) {if ($value.IsPresent) {$list.Add("-$key")};continue};if ($value -is [bool]) {if ($value) {$list.Add("-$key")};continue};if ($null -eq $value) {continue};if ($value -is [Array]) {if ($value.Count -gt 0) {$list.Add("-$key");foreach ($item in $value) {$list.Add([string]$item)}};continue};$list.Add("-$key");$list.Add([string]$value)}
    return $list.ToArray()
}
function Format-WpcCommand {
    param([string]$Path,[hashtable]$Arguments)
    $parts=New-Object System.Collections.Generic.List[string];$parts.Add("& '$Path'")
    foreach ($key in $Arguments.Keys) {$value=$Arguments[$key];if ($value -is [System.Management.Automation.SwitchParameter]) {if ($value.IsPresent) {$parts.Add("-$key")}} elseif ($value -is [bool]) {if ($value) {$parts.Add("-$key")}} elseif ($value -is [Array]) {if ($value.Count -gt 0) {$quoted=@($value|ForEach-Object {"'$_'"}) -join ',';$parts.Add("-$key $quoted")}} elseif ($null -ne $value) {$parts.Add("-$key '$value'")}}
    return ($parts -join ' ')
}
function Get-WpcFailureSummaryCandidates {
    param([Parameter(Mandatory)][datetime]$NotBefore)
    $paths=New-Object System.Collections.Generic.List[string]
    $latest=Join-Path $RepoRoot 'reports\orchestration\latest-run.json'
    if (Test-Path -LiteralPath $latest) {$paths.Add($latest)}
    $runsRoot=Join-Path $RepoRoot 'logs\runs'
    if (Test-Path -LiteralPath $runsRoot) {
        foreach ($runDir in @(Get-ChildItem -LiteralPath $runsRoot -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 10)) {
            $candidate=Join-Path $runDir.FullName 'summary.json'
            if (-not (Test-Path -LiteralPath $candidate)) {continue}
            if ($paths -notcontains $candidate) {$paths.Add($candidate)}
        }
    }
    return $paths.ToArray()
}
function Read-WpcFailureSummaryContext {
    param([Parameter(Mandatory)][string]$SummaryPath,[Parameter(Mandatory)][datetime]$NotBefore)
    try {
        $file=Get-Item -LiteralPath $SummaryPath -ErrorAction Stop
        if ($file.LastWriteTimeUtc -lt $NotBefore.ToUniversalTime().AddSeconds(-10)) {return $null}
        $summary=Get-Content -Raw -LiteralPath $SummaryPath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $successProperty=$summary.PSObject.Properties['Success']
        if ($null -ne $successProperty -and [bool]$successProperty.Value) {return $null}
        $states=@()
        $latestStateProperty=$summary.PSObject.Properties['LatestScriptState']
        if ($null -ne $latestStateProperty) {$states=@($latestStateProperty.Value)}
        if ($states.Count -eq 0) {
            $scriptExecutionsProperty=$summary.PSObject.Properties['ScriptExecutions']
            if ($null -ne $scriptExecutionsProperty) {$states=@($scriptExecutionsProperty.Value)}
        }
        $failed=@($states | Where-Object { $_.Success -eq $false -or [string]$_.Outcome -eq 'FAILED' } | Sort-Object Timestamp | Select-Object -Last 1)
        $event=if ($failed.Count -gt 0) {$failed[0]} else {$null}
        $failureProperty=$summary.PSObject.Properties['FailureMessage']
        $failureMessage=if ($null -ne $failureProperty) {[string]$failureProperty.Value} else {''}
        $step=if ($null -ne $event -and -not [string]::IsNullOrWhiteSpace([string]$event.DisplayName)) {[string]$event.DisplayName} else {'Orchestration'}
        $script=if ($null -ne $event -and -not [string]::IsNullOrWhiteSpace([string]$event.Script)) {[string]$event.Script} else {''}
        $cause=if ($null -ne $event -and -not [string]::IsNullOrWhiteSpace([string]$event.Error)) {[string]$event.Error} else {$failureMessage}
        $log=if ($null -ne $event -and -not [string]::IsNullOrWhiteSpace([string]$event.LogPath)) {[string]$event.LogPath} else {''}
        $runIdProperty=$summary.PSObject.Properties['RunId']
        $runId=if ($null -ne $runIdProperty) {[string]$runIdProperty.Value} else {''}
        if ([string]::IsNullOrWhiteSpace($cause) -and $null -eq $event) {return $null}
        return [pscustomobject]@{Step=$step;Script=$script;Cause=$cause;LogPath=$log;SummaryPath=$SummaryPath;RunId=$runId}
    } catch { return $null }
}
function Get-WpcOrchestratorFailureContext {
    param([Parameter(Mandatory)][datetime]$NotBefore)
    $logPath=Join-Path $RepoRoot 'logs\install.log'
    try {
        if (-not (Test-Path -LiteralPath $logPath)) {return $null}
        $file=Get-Item -LiteralPath $logPath -ErrorAction Stop
        if ($file.LastWriteTimeUtc -lt $NotBefore.ToUniversalTime().AddSeconds(-10)) {return $null}
        $errorLines=@(Get-Content -LiteralPath $logPath -Tail 120 -ErrorAction Stop | Where-Object { $_ -match '\[(ERREUR|ERROR)\]' })
        if ($errorLines.Count -eq 0) {return $null}
        $last=[string]$errorLines[-1]
        $cause=($last -replace '^\[[^\]]+\]\s+\[(?:ERREUR|ERROR)\]\s*','').Trim()
        if ([string]::IsNullOrWhiteSpace($cause)) {$cause=$last}
        return [pscustomobject]@{Step='Orchestration';Script='';Cause=$cause;LogPath=$logPath;SummaryPath='';RunId=''}
    } catch { return $null }
}
function Get-WpcLatestFailureContext {
    param([Parameter(Mandatory)][datetime]$NotBefore)
    foreach ($summaryPath in @(Get-WpcFailureSummaryCandidates -NotBefore $NotBefore)) {
        $context=Read-WpcFailureSummaryContext -SummaryPath $summaryPath -NotBefore $NotBefore
        if ($null -ne $context) {return $context}
    }
    return (Get-WpcOrchestratorFailureContext -NotBefore $NotBefore)
}
function Format-WpcProcessFailure {
    param([Parameter(Mandatory)][string]$DisplayName,[Parameter(Mandatory)][int]$ExitCode,[Parameter(Mandatory)][datetime]$StartedAt)
    $context=Get-WpcLatestFailureContext -NotBefore $StartedAt
    $lines=New-Object System.Collections.Generic.List[string]
    $lines.Add("Le processus PowerShell isolé '$DisplayName' a retourné le code $ExitCode.")
    if ($null -eq $context) {
        $fallbackLog=Join-Path $RepoRoot 'logs\install.log'
        $lines.Add("  Cause   : contexte structuré indisponible; la dernière erreur n'a pas pu être relue automatiquement.")
        $lines.Add("  Journal : $fallbackLog")
        return ($lines -join [Environment]::NewLine)
    }
    if ($context.RunId) {$lines.Add("  Run     : $($context.RunId)")}
    $lines.Add("  Étape   : $($context.Step)")
    if ($context.Script) {$lines.Add("  Script  : $($context.Script)")}
    if ($context.Cause) {$lines.Add("  Cause   : $($context.Cause)")}
    if ($context.LogPath) {$lines.Add("  Journal : $($context.LogPath)")}
    if ($context.SummaryPath) {$lines.Add("  Résumé  : $($context.SummaryPath)")}
    return ($lines -join [Environment]::NewLine)
}
function Invoke-WpcRepoScript {
    param([Parameter(Mandatory)][string]$DisplayName,[Parameter(Mandatory)][string]$Path,[hashtable]$Arguments=@{},[switch]$RequiresAdmin)
    Write-Host ''
    Write-Line ("[ACTION] {0}" -f $DisplayName) Cyan
    Write-Line ("Commande: {0}" -f (Format-WpcCommand -Path $Path -Arguments $Arguments)) DarkGray
    Write-Line ('-'*78) DarkCyan
    Write-Line (" SUIVI EN DIRECT | {0}" -f $DisplayName) Cyan
    Write-Line (" Demarre : {0}" -f (Get-Date -Format 'HH:mm:ss')) DarkGray
    Write-Line ' Les phases, sous-etapes, statuts et durees de l orchestrateur apparaissent ci-dessous.' DarkGray
    Write-Line ('-'*78) DarkCyan
    $script:LastActionRequiresReboot=$false
    if ($DryRun) {Write-Line '[DRY-RUN] Aucune commande executee.' Green;return $true}
    $actionStartedAt=Get-Date
    try {
        $exe=Get-PowerShellExecutable;$argList=New-Object System.Collections.Generic.List[string];$argList.Add('-NoProfile');$argList.Add('-ExecutionPolicy');$argList.Add('Bypass');$argList.Add('-File');$argList.Add($Path);foreach ($arg in (Convert-ArgumentsForElevation -Arguments $Arguments)) {$argList.Add($arg)};$childArgs=$argList.ToArray();$exitCode=0
        if ($RequiresAdmin -and -not (Test-IsAdministrator)) {
            Write-Line '[ADMIN] Elevation UAC requise. Le suivi live se poursuivra dans la fenetre PowerShell 7 elevee.' Yellow
            $process=Start-Process -FilePath $exe -Verb RunAs -ArgumentList $childArgs -Wait -PassThru
            $exitCode=$process.ExitCode
        } else {
            $exitCode=Invoke-WpcVisibleChildProcess -Executable $exe -ArgumentList $childArgs
        }
        if ($exitCode -ne 0) {Assert-WpcRebootStateCommands;$state=Get-WpcPendingRebootState;if ($state.Pending) {$script:LastActionRequiresReboot=$true;throw "REDÉMARRAGE REQUIS: le processus PowerShell 7 isolé s'est arrêté avec un redémarrage Windows en attente ($($state.Reasons -join ', '))."};throw (Format-WpcProcessFailure -DisplayName $DisplayName -ExitCode $exitCode -StartedAt $actionStartedAt)}
        $elapsed=(Get-Date)-$actionStartedAt
        Write-Line ('-'*78) DarkCyan
        Write-Line ("[TERMINE] Action terminee | Duree: {0:hh\:mm\:ss}" -f $elapsed) Green
        return $true
    } catch {$message=$_.Exception.Message;Assert-WpcRebootStateCommands;if (Test-WpcRebootRequiredMessage -Message $message) {$script:LastActionRequiresReboot=$true;Write-Line ("[ACTION REQUISE] {0}" -f $message) Yellow;return $false};Write-Line ("[ERREUR] {0}" -f $message) Red;return $false}
}
function Invoke-WpcInteractiveRepoScript {
    param([Parameter(Mandatory)][string]$DisplayName,[Parameter(Mandatory)][string]$Path,[hashtable]$Arguments=@{})
    Write-Host ''
    Write-Line ('='*78) DarkCyan
    Write-Line (" INTERACTIF DIRECT | {0}" -f $DisplayName) Magenta
    Write-Line ('='*78) DarkCyan
    Write-Line 'Cette phase n utilise PAS le relais de logs stdout/stderr du menu.' DarkGray
    Write-Line 'Les saisies restent entre toi et l outil officiel (GitHub CLI / AWS CLI).' DarkGray
    Write-Line 'Aucun token, mot de passe ou secret ne doit apparaitre dans reports/, logs/ ou state/.' DarkGray
    if ($DryRun) {Write-Line '[DRY-RUN] Assistant interactif non execute.' Green;return $true}
    $exe=Get-PowerShellExecutable
    $argList=New-Object System.Collections.Generic.List[string]
    foreach ($item in @('-NoProfile','-ExecutionPolicy','Bypass','-File',$Path)) {$argList.Add($item)}
    foreach ($arg in (Convert-ArgumentsForElevation -Arguments $Arguments)) {$argList.Add($arg)}
    $childArgs=$argList.ToArray()
    & $exe @childArgs
    $exitCode=[int]$LASTEXITCODE
    $global:LASTEXITCODE=0
    if ($exitCode -ne 0) {Write-Line ("[ERREUR] Assistant interactif termine avec le code {0}." -f $exitCode) Red;return $false}
    Write-Line '[TERMINE] Assistant interactif termine.' Green
    return $true
}
function Invoke-WpcExternalAuthOffer {
    if ($DryRun -or -not [string]::IsNullOrWhiteSpace($Choice)) {return}
    Write-Host ''
    Write-Line '[ANALYSE] Connexions externes optionnelles (Git / GitHub / AWS)' Cyan
    [void](Invoke-WpcRepoScript -DisplayName 'Audit des connexions externes' -Path $ExternalAuthAuditScript -Arguments @{Mode='Audit'})
    Write-Line 'Ces connexions sont optionnelles: leur absence ne retire pas le statut READY de la workstation.' DarkGray
    if (Confirm-WpcAction -Message 'Ouvrir maintenant l assistant interactif de connexions externes') {
        [void](Invoke-WpcInteractiveRepoScript -DisplayName 'Connexions externes' -Path $ExternalAuthInteractiveScript -Arguments @{Service='All'})
    } else {
        Write-Line '[IGNORE] Connexions externes laissées pour plus tard. Option disponible dans Composants specifiques.' Yellow
    }
}
function Invoke-OpenFolder {param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Label);Write-Host '';Write-Line ("[ACTION] Ouvrir {0}" -f $Label) Cyan;if ($DryRun) {Write-Line ("[DRY-RUN] explorer.exe '$Path'") Green;return};New-Item -ItemType Directory -Force -Path $Path|Out-Null;Start-Process explorer.exe -ArgumentList @($Path)}

function Invoke-MainAction {
    param([Parameter(Mandatory)][string]$Selected)
    switch ($Selected.ToLowerInvariant()) {
        '1' {if (Invoke-WpcPendingRebootGate -Context 'avant l installation complete') {return};if (Confirm-WpcAction -Message 'Lancer l installation COMPLETE de la workstation') {$completed=Invoke-WpcRepoScript -DisplayName 'Installation complete' -Path $InstallScript -Arguments @{Mode='Apply';FullInstall=[switch]::Present} -RequiresAdmin;if (-not $completed -and $script:LastActionRequiresReboot) {[void](Invoke-WpcPendingRebootGate -Context 'pour poursuivre l installation complete' -ForceRequired)} elseif ($completed) {Invoke-WpcExternalAuthOffer}}}
        '2' {if (Confirm-WpcAction -Message 'Installer ou reparer uniquement les logiciels Windows geres par WinGet') {[void](Invoke-WpcRepoScript -DisplayName 'Installation / reparation des logiciels' -Path $AppsScript -Arguments @{Mode='Apply'} -RequiresAdmin)}}
        '3' {if (Confirm-WpcAction -Message 'Lancer les mises a jour completes du systeme') {[void](Invoke-WpcRepoScript -DisplayName 'Gestionnaire de mises a jour' -Path $UpdateScript -Arguments @{Mode='Apply'} -RequiresAdmin)}}
        '4.1' {[void](Invoke-WpcRepoScript -DisplayName 'Creer une sauvegarde' -Path $InstallScript -Arguments @{BackupAction='Create'} -RequiresAdmin)}
        '4.2' {[void](Invoke-WpcRepoScript -DisplayName 'Verifier une sauvegarde' -Path $InstallScript -Arguments @{BackupAction='Verify'})}
        '4.3' {$session=Read-WpcMenuValue -Prompt 'Chemin complet de la session Golden Backup' -DryRunValue 'F:\Windows_11_Pro_Custom_Backup\sessions\SESSION';[void](Invoke-WpcRepoScript -DisplayName 'Verifier la restaurabilite' -Path $RestoreDrillScript -Arguments @{BackupSessionPath=$session;Mode='Verify'} -RequiresAdmin)}
        '5.1' {Write-Line '[SECURITE] Cette option genere uniquement un plan de restauration. Elle ne restaure rien automatiquement.' Yellow;[void](Invoke-WpcRepoScript -DisplayName 'Plan de restauration' -Path $InstallScript -Arguments @{BackupAction='RestorePlan'})}
        '5.2' {if (Confirm-WpcAction -Message 'Rollback des reglages Windows geres par le depot' -Dangerous) {[void](Invoke-WpcRepoScript -DisplayName 'Rollback des reglages geres' -Path $InstallScript -Arguments @{Mode='Rollback'} -RequiresAdmin)}}
        '5.3' {$session=Read-WpcMenuValue -Prompt 'Chemin complet de la session Golden Backup' -DryRunValue 'F:\Windows_11_Pro_Custom_Backup\sessions\SESSION';$scratch=Read-WpcMenuValue -Prompt 'Repertoire scratch local et isole' -DryRunValue 'E:\WSL-RestoreDrill';if (Confirm-WpcAction -Message 'Lancer le drill WSL isole puis supprimer uniquement sa copie temporaire') {[void](Invoke-WpcRepoScript -DisplayName 'Drill WSL isole' -Path $RestoreDrillScript -Arguments @{BackupSessionPath=$session;Mode='Sandbox';ScratchRoot=$scratch;ConfirmIsolatedRestoreDrill=[switch]::Present} -RequiresAdmin)}}
        '6' {[void](Invoke-WpcRepoScript -DisplayName 'Audit et diagnostic global' -Path $InstallScript -Arguments @{Mode='Audit'})}
        '7' {[void](Invoke-WpcRepoScript -DisplayName 'Verification de conformite globale' -Path $InstallScript -Arguments @{Mode='Verify';ValidateHardware=[switch]::Present;ValidateWsl=[switch]::Present;ValidateDevOps=[switch]::Present} -RequiresAdmin)}
        '8.1' {if (Confirm-WpcAction -Message 'Installer ou reparer WSL2 et la stack DevOps') {[void](Invoke-WpcRepoScript -DisplayName 'WSL2 + stack DevOps' -Path $InstallScript -Arguments @{Mode='Apply';InstallDevOps=[switch]::Present;ValidateWsl=[switch]::Present;ValidateDevOps=[switch]::Present} -RequiresAdmin)}}
        '8.2' {[void](Invoke-WpcRepoScript -DisplayName 'Qualification materielle guidee' -Path $InstallScript -Arguments @{Mode='Verify';ValidateHardware=[switch]::Present} -RequiresAdmin)}
        '8.3' {[void](Invoke-WpcRepoScript -DisplayName 'Audit empreinte SIMULATED' -Path $FingerprintScript -Arguments @{Mode='Audit'})}
        '8.4' {[void](Invoke-WpcRepoScript -DisplayName 'Audit empreinte PHYSICAL' -Path $FingerprintScript -Arguments @{Mode='Audit';EvidenceLevel='PHYSICAL';ConfirmPhysicalEvidence=[switch]::Present} -RequiresAdmin)}
        '8.5' {[void](Invoke-WpcRepoScript -DisplayName 'Verification de derive PHYSICAL' -Path $FingerprintScript -Arguments @{Mode='Verify';EvidenceLevel='PHYSICAL';ConfirmPhysicalEvidence=[switch]::Present} -RequiresAdmin)}
        '8.6' {if (Confirm-WpcAction -Message 'Enregistrer la baseline PHYSICAL uniquement apres validation complete') {[void](Invoke-WpcRepoScript -DisplayName 'Enregistrer baseline PHYSICAL' -Path $FingerprintScript -Arguments @{Mode='Record';EvidenceLevel='PHYSICAL';ConfirmPhysicalEvidence=[switch]::Present;ConfirmHealthyState=[switch]::Present} -RequiresAdmin)}}
        '8.7' {$reason=Read-WpcMenuValue -Prompt 'Justification du remplacement de baseline' -DryRunValue 'Maintenance validee et requalification complete reussie';if (Confirm-WpcAction -Message 'Archiver et remplacer la baseline PHYSICAL apres investigation') {[void](Invoke-WpcRepoScript -DisplayName 'Remplacer baseline PHYSICAL' -Path $FingerprintScript -Arguments @{Mode='Record';EvidenceLevel='PHYSICAL';ConfirmPhysicalEvidence=[switch]::Present;ConfirmHealthyState=[switch]::Present;ReplaceBaseline=[switch]::Present;ReplacementReason=$reason} -RequiresAdmin)}}
        '8.8' {[void](Invoke-WpcInteractiveRepoScript -DisplayName 'Connexions externes' -Path $ExternalAuthInteractiveScript -Arguments @{Service='All'})}
        '8.9' {[void](Invoke-WpcRepoScript -DisplayName 'Audit des connexions externes' -Path $ExternalAuthAuditScript -Arguments @{Mode='Audit'})}
        '9.1' {Invoke-OpenFolder -Path (Join-Path $RepoRoot 'logs') -Label 'les journaux'}
        '9.2' {Invoke-OpenFolder -Path (Join-Path $RepoRoot 'reports') -Label 'les rapports'}
        '10' {Show-Help}
        default {Write-Line "[ERREUR] Choix inconnu: $Selected" Red}
    }
}
function Show-BackupMenu {while ($true) {Write-Header;Write-Line ' SAUVEGARDE' White;Write-Line '';Write-Line '  1. Creer une nouvelle sauvegarde' White;Write-Line '  2. Verifier une sauvegarde existante' White;Write-Line '  3. Verifier la restaurabilite d une session' White;Write-Line '  0. Retour' DarkGray;Write-Host '';$value=(Read-Host 'Ton choix').Trim();if ($value -eq '0') {return};if ($value -in @('1','2','3')) {Invoke-MainAction -Selected "4.$value";Pause-WpcMenu}}}
function Show-RestoreMenu {while ($true) {Write-Header;Write-Line ' RESTAURATION' White;Write-Line '';Write-Line '  1. Generer un plan de restauration (aucune ecriture)' White;Write-Line '  2. Rollback des reglages geres par le depot' Yellow;Write-Line '  3. Drill WSL isole' White;Write-Line '  0. Retour' DarkGray;Write-Host '';Write-Line 'La restauration complete destructive reste volontairement non automatique.' DarkGray;$value=(Read-Host 'Ton choix').Trim();if ($value -eq '0') {return};if ($value -in @('1','2','3')) {Invoke-MainAction -Selected "5.$value";Pause-WpcMenu}}}
function Show-ComponentsMenu {while ($true) {Write-Header;Write-Line ' COMPOSANTS SPECIFIQUES' White;Write-Line '';Write-Line '  1. WSL2 + stack DevOps + validation' White;Write-Line '  2. Qualification materielle guidee' White;Write-Line '  3. Audit empreinte SIMULATED' White;Write-Line '  4. Audit empreinte PHYSICAL' White;Write-Line '  5. Verifier la derive PHYSICAL' White;Write-Line '  6. Enregistrer la baseline PHYSICAL' White;Write-Line '  7. Remplacer la baseline PHYSICAL (archive + justification)' Yellow;Write-Line '  8. Connexions externes interactives (Git / GitHub / AWS)' Magenta;Write-Line '  9. Auditer les connexions externes (sans secret)' White;Write-Line '  0. Retour' DarkGray;Write-Host '';$value=(Read-Host 'Ton choix').Trim();if ($value -eq '0') {return};if ($value -in @('1','2','3','4','5','6','7','8','9')) {Invoke-MainAction -Selected "8.$value";Pause-WpcMenu}}}
function Show-LogsMenu {while ($true) {Write-Header;Write-Line ' JOURNAUX ET RAPPORTS' White;Write-Line '';Write-Line '  1. Ouvrir logs\' White;Write-Line '  2. Ouvrir reports\' White;Write-Line '  0. Retour' DarkGray;Write-Host '';$value=(Read-Host 'Ton choix').Trim();if ($value -eq '0') {return};if ($value -in @('1','2')) {Invoke-MainAction -Selected "9.$value";Pause-WpcMenu}}}
function Show-Help {
    Write-Header;Write-Line ' AIDE RAPIDE' White;Write-Line ''
    Write-Line 'PowerShell' Cyan;Write-Line '  Runtime unique: PowerShell 7.6.4 minimum, edition Core, processus x64, executable pwsh.exe.' DarkGray;Write-Line '  Windows PowerShell 5.1 peut rester installe dans Windows mais ce depot ne l execute jamais et ne l utilise pas comme fallback.' DarkGray
    Write-Line 'Installation complete' Cyan;Write-Line '  Converge toute la workstation avec install.ps1 -FullInstall.' DarkGray;Write-Line '  Le menu relaie en direct les phases, sous-etapes, statuts, durees et sorties de l orchestrateur.' DarkGray;Write-Line '  Une fois READY, un audit sans secret peut proposer les connexions Git/GitHub/AWS dans un canal interactif direct.' DarkGray;Write-Line '  Si Windows exige un reboot, le menu bloque proprement puis propose le redemarrage; relancer ensuite la meme option reprend idempotemment.' DarkGray
    Write-Line 'Logiciels' Cyan;Write-Line '  Installe uniquement les applications WinGet manquantes ou non conformes.' DarkGray
    Write-Line 'Mises a jour' Cyan;Write-Line '  Gere Windows Update, WinGet, WSL, Ubuntu/APT, VS Code et les outils DevOps epingles.' DarkGray
    Write-Line 'Connexions externes' Cyan;Write-Line '  Git: configure uniquement user.name/user.email.' DarkGray;Write-Line '  GitHub: gh auth login --web puis gh auth setup-git; aucun token n est fourni par le depot.' DarkGray;Write-Line '  AWS: SSO recommande, reconnexion SSO ou aws configure legacy; les saisies restent dans AWS CLI.' DarkGray;Write-Line '  Leur absence reste optionnelle et ne rend pas la workstation non conforme.' DarkGray
    Write-Line 'Sauvegarde' Cyan;Write-Line '  Cree ou valide la sauvegarde de reference de la workstation.' DarkGray
    Write-Line 'Restauration' Cyan;Write-Line '  Genere un plan de restauration ou rollback les reglages geres. Pas de restauration destructive automatique.' DarkGray
    Write-Line 'Audit / verification' Cyan;Write-Line '  Audit observe; Verify exige les prérequis matériels critiques. Les écarts de pilotes sont affichés mais restent non bloquants.' DarkGray;Write-Line ''
    Write-Line 'OpenClaw / OpenRouter ne sont pas geres par ce depot.' Yellow;Write-Line 'Leur installation et leur configuration appartiennent au depot openclaw_openrouter.' DarkGray;Write-Line '';Write-Line 'Lancement direct possible pour automatisation/test:' White;Write-Line '  .\menu.ps1 -Choice 3 -DryRun' DarkGray;Write-Line '  .\menu.ps1 -Choice 8.1 -DryRun' DarkGray;Write-Line '  .\menu.ps1 -Choice 8.9 -DryRun' DarkGray
}
function Show-MainMenu {while ($true) {Write-Header;Write-Line '  1. Installation complete' White;Write-Line '  2. Installation / reparation des logiciels' White;Write-Line '  3. Mises a jour completes' White;Write-Line '  4. Sauvegarde' White;Write-Line '  5. Restauration / rollback' White;Write-Line '  6. Audit et diagnostic complet' White;Write-Line '  7. Verification de conformite' White;Write-Line '  8. Composants specifiques' White;Write-Line '  9. Journaux et rapports' White;Write-Line ' 10. Aide' White;Write-Line '  0. Quitter' DarkGray;Write-Host '';Write-Line 'Les actions deja conformes restent idempotentes: elles ne sont pas refaites inutilement.' DarkGray;$selected=(Read-Host 'Que veux-tu faire ?').Trim();switch ($selected) {'0' {return};'4' {Show-BackupMenu};'5' {Show-RestoreMenu};'8' {Show-ComponentsMenu};'9' {Show-LogsMenu};default {Invoke-MainAction -Selected $selected;Pause-WpcMenu}}}}

if (-not [string]::IsNullOrWhiteSpace($Choice)) {Write-Header;Invoke-MainAction -Selected $Choice;exit 0}
Show-MainMenu
