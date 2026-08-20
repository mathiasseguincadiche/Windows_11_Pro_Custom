#Requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$powerShellRuntimeModule = Join-Path $PSScriptRoot 'powershell-runtime.psm1'
if (-not (Test-Path -LiteralPath $powerShellRuntimeModule)) { throw "Contrat PowerShell introuvable: $powerShellRuntimeModule" }
Import-Module $powerShellRuntimeModule -Force
[void](Assert-WpcPowerShellRuntime -MinimumVersion ([version]'7.6.4') -RequireWindows -PassThru)

if (-not ('Windows11ProCustom.ConsoleHeartbeat' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Threading;
namespace Windows11ProCustom {
    public sealed class ConsoleHeartbeat : IDisposable {
        private readonly object sync = new object();
        private readonly string label;
        private readonly int silenceSeconds;
        private readonly DateTime startedAt;
        private DateTime lastActivityAt;
        private Timer timer;

        public ConsoleHeartbeat(string label, int silenceSeconds) {
            this.label = String.IsNullOrWhiteSpace(label) ? "operation" : label;
            this.silenceSeconds = Math.Max(2, silenceSeconds);
            this.startedAt = DateTime.UtcNow;
            this.lastActivityAt = this.startedAt;
            this.timer = new Timer(Tick, null, this.silenceSeconds * 1000, this.silenceSeconds * 1000);
        }

        public void Touch() {
            lock (sync) { lastActivityAt = DateTime.UtcNow; }
        }

        private void Tick(object state) {
            DateTime last;
            lock (sync) { last = lastActivityAt; }
            var now = DateTime.UtcNow;
            if ((now - last).TotalSeconds < silenceSeconds) { return; }
            try {
                var previous = Console.ForegroundColor;
                Console.ForegroundColor = ConsoleColor.DarkYellow;
                Console.WriteLine("    [ACTIF] {0} est toujours en cours | ecoule {1:hh\\:mm\\:ss}", label, now - startedAt);
                Console.ForegroundColor = previous;
            } catch { }
            lock (sync) { lastActivityAt = now; }
        }

        public void Dispose() {
            lock (sync) {
                if (timer != null) {
                    timer.Dispose();
                    timer = null;
                }
            }
        }
    }
}
'@
}

function Get-WpcProjectRelease {
    param([Parameter(Mandatory)][string]$RepoRoot)
    $versionPath = Join-Path $RepoRoot 'VERSION'
    if (-not (Test-Path -LiteralPath $versionPath)) { throw "Version globale introuvable: $versionPath" }
    $release = (Get-Content -Raw -LiteralPath $versionPath).Trim()
    if ($release -notmatch '^\d+\.\d+\.\d+$') { throw "Version globale invalide dans VERSION: '$release'. Format SemVer x.y.z attendu." }
    return $release
}

function Get-WpcRelativePath {
    param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path)
    $root = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { return $full.Substring($root.Length).TrimStart('\') }
    return $full
}

function Get-WpcLogPath {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$Identity)
    $relative = $Identity -replace '/', '\'
    if ([IO.Path]::IsPathRooted($relative)) { $relative = Get-WpcRelativePath -RepoRoot $Context.RepoRoot -Path $relative }
    if ($relative.StartsWith('scripts\', [StringComparison]::OrdinalIgnoreCase)) { $relative = $relative.Substring(8) }
    $directory = Split-Path -Parent $relative
    $name = [IO.Path]::GetFileNameWithoutExtension($relative)
    if ([string]::IsNullOrWhiteSpace($directory)) { return (Join-Path $Context.LogRoot "$name.log") }
    return (Join-Path (Join-Path $Context.LogRoot $directory) "$name.log")
}

function Add-WpcLogLine {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Level,[Parameter(Mandatory)][string]$Message)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Add-Content -LiteralPath $Path -Encoding UTF8 -Value ("[{0}] [{1}] {2}" -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message)
}

function Add-WpcEvent {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][hashtable]$Data)
    $event = [ordered]@{ Timestamp=(Get-Date).ToString('o'); RunId=$Context.RunId; Release=$Context.Release }
    foreach ($key in $Data.Keys) { $event[$key] = $Data[$key] }
    ($event | ConvertTo-Json -Compress -Depth 12) | Add-Content -LiteralPath $Context.EventsPath -Encoding UTF8
}

function Get-WpcColor {
    param([string]$Status)
    switch ($Status) {
        'DEJA_OK' { 'Green' } 'FAIT' { 'Green' } 'OK' { 'Green' }
        'A_FAIRE' { 'Yellow' } 'ATTENTE' { 'Yellow' } 'AVERTISSEMENT' { 'Yellow' }
        'ACTION_REQUISE' { 'Magenta' } 'ERREUR' { 'Red' }
        'EN_COURS' { 'Cyan' } 'ANALYSE' { 'Cyan' } 'IGNORE' { 'DarkGray' }
        default { 'Gray' }
    }
}

function Get-WpcLabel {
    param([string]$Status)
    switch ($Status) {
        'DEJA_OK' { 'DEJA OK' } 'A_FAIRE' { 'A FAIRE' } 'ACTION_REQUISE' { 'ACTION REQUISE' }
        'EN_COURS' { 'EN COURS' } 'AVERTISSEMENT' { 'AVERTISSEMENT' } 'ATTENTE' { 'EN ATTENTE' }
        default { $Status.Replace('_', ' ') }
    }
}

function Get-WpcElapsedText {
    param([Parameter(Mandatory)][datetime]$StartedAt)
    $elapsed = (Get-Date) - $StartedAt
    return ('{0:00}:{1:00}:{2:00}' -f [int]$elapsed.TotalHours, $elapsed.Minutes, $elapsed.Seconds)
}

function Get-WpcHeartbeatSeconds {
    $value = [Environment]::GetEnvironmentVariable('WPC_HEARTBEAT_SECONDS')
    $seconds = 0
    if ([int]::TryParse($value, [ref]$seconds) -and $seconds -ge 2 -and $seconds -le 300) { return $seconds }
    return 15
}

function New-WpcHeartbeat {
    param([Parameter(Mandatory)][string]$Label)
    return [Windows11ProCustom.ConsoleHeartbeat]::new($Label, (Get-WpcHeartbeatSeconds))
}

function Get-WpcPhasePresentation {
    param([string]$Phase)
    switch ($Phase) {
        'Discovery' { return [pscustomobject]@{ Title='Decouverte et preflight'; Detail='Observe la machine, les prerequis et le materiel avant toute decision.' } }
        'Safety' { return [pscustomobject]@{ Title='Protection avant modification'; Detail='Cree ou verifie les garde-fous avant toute convergence.' } }
        'Foundation' { return [pscustomobject]@{ Title='Fondations Windows'; Detail='Prepare WSL, Virtual Machine Platform, WinGet et les composants de base.' } }
        'FoundationValidation' { return [pscustomobject]@{ Title='Revalidation des fondations'; Detail='Confirme que les fondations sont operationnelles avant de continuer.' } }
        'Apply' { return [pscustomobject]@{ Title='Application de la configuration'; Detail='Applique uniquement les ecarts detectes.' } }
        'VerifyAfterApply' { return [pscustomobject]@{ Title='Revalidation apres modification'; Detail='Prouve que chaque correction vient bien de converger.' } }
        'Measurement' { return [pscustomobject]@{ Title='Mesures avant et apres'; Detail='Produit les preuves factuelles de l etat de la workstation.' } }
        'FinalValidation' { return [pscustomobject]@{ Title='Validation finale'; Detail='Controle Windows, WSL, DevOps et le materiel critique selon la demande.' } }
        'DevOps' { return [pscustomobject]@{ Title='Configuration DevOps WSL2'; Detail='Installe ou verifie les outils Linux, Docker et les composants DevOps.' } }
        'Backup' { return [pscustomobject]@{ Title='Sauvegarde'; Detail='Execute l operation de sauvegarde demandee.' } }
        'Rollback' { return [pscustomobject]@{ Title='Rollback'; Detail='Restaure uniquement les etats precedemment geres par le depot.' } }
        'Audit' { return [pscustomobject]@{ Title='Audit'; Detail='Observe sans modifier la machine.' } }
        'Verify' { return [pscustomobject]@{ Title='Verification de conformite'; Detail='Valide strictement les contrats demandes.' } }
        'ManualEvidence' { return [pscustomobject]@{ Title='Preuves manuelles'; Detail='Enregistre les controles qui ne peuvent pas etre deduits automatiquement.' } }
        'External' { return [pscustomobject]@{ Title='Commande externe'; Detail='Execute un outil externe tout en conservant un suivi visible.' } }
        default { return [pscustomobject]@{ Title=$Phase; Detail='Execution de la phase courante.' } }
    }
}

function Write-WpcPhaseHeader {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$Phase)
    if ([string]::IsNullOrWhiteSpace($Phase) -or $Phase -eq 'Probe') { return }
    if ($Context.CurrentPhase -eq $Phase) { return }
    $Context.CurrentPhase = $Phase
    $Context.PhaseNumber = [int]$Context.PhaseNumber + 1
    $meta = Get-WpcPhasePresentation -Phase $Phase
    Write-Host ''
    Write-Host ('=' * 78) -ForegroundColor DarkCyan
    Write-Host ("  ETAPE {0:00} | {1}" -f $Context.PhaseNumber, $meta.Title) -ForegroundColor Cyan
    Write-Host ("  Objectif   : {0}" -f $meta.Detail) -ForegroundColor DarkGray
    Write-Host ("  Temps total: {0}" -f (Get-WpcElapsedText -StartedAt $Context.StartedAt)) -ForegroundColor DarkGray
    Write-Host ('=' * 78) -ForegroundColor DarkCyan
    Add-WpcLogLine -Path $Context.OrchestratorLogPath -Level 'PHASE' -Message ("Phase={0} Title={1}" -f $Phase,$meta.Title)
}

function Write-WpcActionHeader {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$Identity,
        [Parameter(Mandatory)][string]$LogPath
    )
    $Context.ActionNumber = [int]$Context.ActionNumber + 1
    Write-Host ''
    Write-Host ("  SOUS-ETAPE {0:00} | {1}" -f $Context.ActionNumber, $DisplayName) -ForegroundColor White
    Write-Host ("    Script  : {0}" -f $Identity) -ForegroundColor DarkGray
    Write-Host ("    Journal : {0}" -f $LogPath) -ForegroundColor DarkGray
    Write-Host ("    Demarre : {0} | ecoule global {1}" -f (Get-Date -Format 'HH:mm:ss'), (Get-WpcElapsedText -StartedAt $Context.StartedAt)) -ForegroundColor DarkGray
}

function Write-WpcStatus {
    param([Parameter(Mandatory)][string]$Status,[Parameter(Mandatory)][string]$Message,[string]$Detail='',$Context=$null)
    $label = Get-WpcLabel -Status $Status
    Write-Host ("[{0,-18}] {1}" -f $label, $Message) -ForegroundColor (Get-WpcColor -Status $Status)
    if (-not [string]::IsNullOrWhiteSpace($Detail)) { Write-Host ("                     {0}" -f $Detail) -ForegroundColor DarkGray }
    if ($Context) { Add-WpcLogLine -Path $Context.OrchestratorLogPath -Level $label -Message ($Message + $(if ($Detail) { " | $Detail" } else { '' })) }
}

function Write-WpcBanner {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$Title)
    Write-Host ''
    Write-Host ('=' * 78) -ForegroundColor DarkCyan
    Write-Host ("  {0}" -f $Title) -ForegroundColor Cyan
    Write-Host ("  Release : {0}" -f $Context.Release) -ForegroundColor White
    Write-Host ("  Run     : {0}" -f $Context.RunId) -ForegroundColor DarkGray
    Write-Host ("  Logs    : {0}" -f $Context.LogRoot) -ForegroundColor DarkGray
    Write-Host ("  PowerShell: {0} | Core | x64 | pwsh.exe | minimum 7.6.4" -f $PSVersionTable.PSVersion) -ForegroundColor DarkGray
    Write-Host ('=' * 78) -ForegroundColor DarkCyan
    Write-Host '  Suivi interactif actif : phases, sous-etapes, durees et journaux sont affiches.' -ForegroundColor White
    Write-Host ("  Battement de vie       : apres {0}s sans sortie, [ACTIF] confirme que le traitement continue." -f (Get-WpcHeartbeatSeconds)) -ForegroundColor DarkGray
    Write-Host '  Legende                 : DEJA OK=rien a faire | A FAIRE=changement | EN COURS=travail | FAIT=termine | AVERTISSEMENT=non bloquant' -ForegroundColor DarkGray
    Add-WpcLogLine -Path $Context.OrchestratorLogPath -Level 'RUN' -Message "$Title | Release=$($Context.Release) | RunId=$($Context.RunId) | PowerShell=$($PSVersionTable.PSVersion) Core x64 pwsh.exe"
}

function New-WpcRunContext {
    param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Mode,[switch]$NonInteractive,[string]$ExistingRunId='')
    $runId = $ExistingRunId
    if ([string]::IsNullOrWhiteSpace($runId)) { $runId = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,8)) }
    $release = Get-WpcProjectRelease -RepoRoot $RepoRoot
    $logRoot = Join-Path $RepoRoot 'logs'
    $runDir = Join-Path (Join-Path $logRoot 'runs') $runId
    $eventsPath = Join-Path $runDir 'events.ndjson'
    $orchestratorLog = Join-Path $logRoot 'install.log'
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    if (-not $ExistingRunId -or -not (Test-Path $eventsPath)) { Set-Content -LiteralPath $eventsPath -Encoding UTF8 -Value '' }
    $context = [pscustomobject]@{
        RepoRoot=[IO.Path]::GetFullPath($RepoRoot); Release=$release; RunId=$runId; Mode=$Mode; LogRoot=$logRoot; RunDir=$runDir
        EventsPath=$eventsPath; OrchestratorLogPath=$orchestratorLog; NonInteractive=[bool]$NonInteractive; StartedAt=(Get-Date)
        CurrentPhase=''; PhaseNumber=0; ActionNumber=0; ComponentNumber=0
    }
    $env:W11_CUSTOM_RELEASE = $context.Release
    $env:W11_CUSTOM_RUN_ID = $context.RunId
    $env:W11_CUSTOM_REPO_ROOT = $context.RepoRoot
    $env:W11_CUSTOM_LOG_ROOT = $context.LogRoot
    $env:W11_CUSTOM_RUN_DIR = $context.RunDir
    $env:W11_CUSTOM_NONINTERACTIVE = if ($context.NonInteractive) { '1' } else { '0' }
    return $context
}

function Get-WpcRunContextFromEnvironment {
    param([Parameter(Mandatory)][string]$RepoRoot)
    $runId = [Environment]::GetEnvironmentVariable('W11_CUSTOM_RUN_ID')
    if ([string]::IsNullOrWhiteSpace($runId)) { return New-WpcRunContext -RepoRoot $RepoRoot -Mode 'Nested' }
    $nonInteractive = [Environment]::GetEnvironmentVariable('W11_CUSTOM_NONINTERACTIVE') -eq '1'
    return New-WpcRunContext -RepoRoot $RepoRoot -Mode 'Nested' -ExistingRunId $runId -NonInteractive:$nonInteractive
}

function ConvertTo-WpcSafeArgumentText {
    param([hashtable]$Arguments)
    $parts = foreach ($entry in ($Arguments.GetEnumerator() | Sort-Object Key)) {
        $key = [string]$entry.Key
        $sensitive = $key -match '(?i)(password|passwd|secret|token|credential|api.?key|private.?key)'
        $value = if ($sensitive) { '<REDACTED>' } elseif ($entry.Value -is [System.Management.Automation.SwitchParameter]) { [bool]$entry.Value } else { $entry.Value }
        "-$key=$value"
    }
    return (@($parts) -join ' ')
}

function Protect-WpcCommandText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
    $safe = $Text
    $safe = $safe -replace '(?i)((?:password|passwd|secret|token|api[_-]?key|credential)\s*[=:]\s*)\S+', '$1<REDACTED>'
    return $safe
}

function Write-WpcChildLine {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Line,[Parameter(Mandatory)][string]$LogPath,[switch]$Quiet)
    if ([string]::IsNullOrWhiteSpace($Line)) { return }
    Add-WpcLogLine -Path $LogPath -Level 'OUTPUT' -Message (Protect-WpcCommandText -Text $Line)
    if ($Quiet) { return }
    $color = 'Gray'
    if ($Line -match '^\s*\[(OK|DEJA OK|D\u00c9J\u00c0 OK|FAIT|READY)\]') { $color='Green' }
    elseif ($Line -match '^\s*\[(WARN|WARNING|AVERTISSEMENT|A FAIRE|\u00c0 FAIRE|TODO)\]') { $color='Yellow' }
    elseif ($Line -match '^\s*\[(KO|ERROR|ERREUR|FAILED)\]') { $color='Red' }
    elseif ($Line -match '^\s*\[(ACTION|ACTION REQUISE|USER ACTION)\]') { $color='Magenta' }
    elseif ($Line -match '^\s*\[(INFO|ANALYSE|EN COURS|ATTENTE|ACTIF)\]') { $color='Cyan' }
    Write-Host ("    {0}" -f $Line) -ForegroundColor $color
}

function Invoke-WpcManagedScript {
    param(
        [Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$Path,[hashtable]$Arguments=@{},[string]$DisplayName='',
        [string]$Phase='Run',[string]$Purpose='Execution',[switch]$AllowFailure,[switch]$Quiet,[string]$LogIdentity=''
    )
    if (-not (Test-Path $Path)) { throw "Script introuvable: $Path" }
    if ([string]::IsNullOrWhiteSpace($DisplayName)) { $DisplayName=[IO.Path]::GetFileName($Path) }
    if ([string]::IsNullOrWhiteSpace($LogIdentity)) { $LogIdentity=$Path }
    $logPath = Get-WpcLogPath -Context $Context -Identity $LogIdentity
    $relative = Get-WpcRelativePath -RepoRoot $Context.RepoRoot -Path $Path
    $parentPurpose = [Environment]::GetEnvironmentVariable('W11_CUSTOM_PARENT_PURPOSE')
    $effectivePurpose = if ($parentPurpose -match '^Probe') { 'ProbeNested' } else { $Purpose }
    $started = Get-Date
    $argText = ConvertTo-WpcSafeArgumentText -Arguments $Arguments
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $logPath) | Out-Null
    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value ''
    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value ('=' * 96)
    Add-WpcLogLine -Path $logPath -Level 'START' -Message "Run=$($Context.RunId) Release=$($Context.Release) Phase=$Phase Purpose=$effectivePurpose Script=$relative Args=$argText"
    Add-WpcLogLine -Path $logPath -Level 'HOST' -Message "Computer=$env:COMPUTERNAME User=$env:USERNAME PowerShell=$($PSVersionTable.PSVersion) Core x64 pwsh.exe"
    if (-not $Quiet -and $Purpose -ne 'Probe') {
        Write-WpcPhaseHeader -Context $Context -Phase $Phase
        Write-WpcActionHeader -Context $Context -DisplayName $DisplayName -Identity $relative -LogPath $logPath
    }
    if (-not $Quiet) { Write-WpcStatus -Status 'EN_COURS' -Message $DisplayName -Detail $relative -Context $Context }

    $success=$false; $errorText=''; $sawAlready=$false; $sawChanged=$false; $sawUserAction=$false
    $oldParent = [Environment]::GetEnvironmentVariable('W11_CUSTOM_PARENT_PURPOSE')
    $heartbeat = New-WpcHeartbeat -Label $(if ($Purpose -eq 'Probe') { "Analyse: $DisplayName" } else { $DisplayName })
    try {
        if ($Purpose -eq 'Probe') { $env:W11_CUSTOM_PARENT_PURPOSE='Probe' }
        & $Path @Arguments 2>&1 3>&1 4>&1 5>&1 6>&1 | ForEach-Object {
            foreach ($line in @(([string]$_) -split "`r?`n")) {
                if ($line -match '\[(DEJA OK|D\u00c9J\u00c0 OK)\]') { $sawAlready=$true }
                if ($line -match '\[(FAIT|CHANGED)\]') { $sawChanged=$true }
                if ($line -match '\[(ACTION REQUISE|USER ACTION)\]') { $sawUserAction=$true }
                $heartbeat.Touch()
                Write-WpcChildLine -Line $line -LogPath $logPath -Quiet:$Quiet
            }
        }
        $success=$true
    } catch {
        $errorText=$_.Exception.Message
        Add-WpcLogLine -Path $logPath -Level 'ERROR' -Message (Protect-WpcCommandText -Text $errorText)
        if (-not $Quiet) { Write-WpcStatus -Status $(if ($Purpose -eq 'Probe') { 'A_FAIRE' } else { 'ERREUR' }) -Message $DisplayName -Detail $errorText -Context $Context }
    } finally {
        if ($null -ne $heartbeat) { $heartbeat.Dispose() }
        if ($null -eq $oldParent) { Remove-Item Env:W11_CUSTOM_PARENT_PURPOSE -ErrorAction SilentlyContinue } else { $env:W11_CUSTOM_PARENT_PURPOSE=$oldParent }
    }
    $duration=[math]::Round(((Get-Date)-$started).TotalSeconds,2)
    $outcome = if (-not $success) { 'FAILED' } elseif ($sawUserAction) { 'ACTION_REQUISE' } elseif ($sawChanged) { 'FAIT' } elseif ($sawAlready) { 'DEJA_OK' } else { 'OK' }
    if ($Purpose -eq 'Probe') { $outcome=if ($success) { 'DEJA_OK' } else { 'A_FAIRE' } }
    Add-WpcLogLine -Path $logPath -Level 'END' -Message "Outcome=$outcome DurationSeconds=$duration"
    Add-WpcEvent -Context $Context -Data @{ Kind='SCRIPT'; Purpose=$effectivePurpose; Phase=$Phase; Script=$relative; DisplayName=$DisplayName; Outcome=$outcome; Success=$success; DurationSeconds=$duration; LogPath=$logPath; Error=(Protect-WpcCommandText -Text $errorText) }
    if (-not $Quiet -and $success -and $Purpose -ne 'Probe') {
        Write-WpcStatus -Status 'OK' -Message "$DisplayName termine" -Detail ("Duree: {0:n2}s | journal: {1}" -f $duration,$logPath) -Context $Context
    }
    $result=[pscustomobject]@{ Success=$success; Outcome=$outcome; Error=$errorText; LogPath=$logPath; DurationSeconds=$duration }
    if (-not $success -and -not $AllowFailure) { throw "$DisplayName a echoue: $errorText" }
    return $result
}

function Test-WpcManagedScript {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$Path,[hashtable]$Arguments=@{},[string]$DisplayName='')
    if ([string]::IsNullOrWhiteSpace($DisplayName)) { $DisplayName=[IO.Path]::GetFileName($Path) }
    Write-WpcStatus -Status 'ANALYSE' -Message $DisplayName -Detail 'Lecture de l etat reel de la machine avant decision.' -Context $Context
    $result=Invoke-WpcManagedScript -Context $Context -Path $Path -Arguments $Arguments -DisplayName $DisplayName -Phase 'Probe' -Purpose 'Probe' -AllowFailure -Quiet
    if ($result.Success) { Write-WpcStatus -Status 'DEJA_OK' -Message $DisplayName -Detail 'La cible est deja conforme; aucune modification necessaire.' -Context $Context; return $true }
    Write-WpcStatus -Status 'A_FAIRE' -Message $DisplayName -Detail 'La cible n est pas conforme; cette etape est planifiee.' -Context $Context
    return $false
}

function Add-WpcComponentResult {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$DisplayName,[Parameter(Mandatory)][string]$Identity,[Parameter(Mandatory)][string]$Outcome,[bool]$Success=$true,[string]$Error='')
    Add-WpcEvent -Context $Context -Data @{ Kind='COMPONENT'; Purpose='Final'; Phase=$Context.Mode; Script=$Identity; DisplayName=$DisplayName; Outcome=$Outcome; Success=$Success; DurationSeconds=0; LogPath=(Get-WpcLogPath -Context $Context -Identity $Identity); Error=(Protect-WpcCommandText -Text $Error) }
}

function Invoke-WpcPlannedComponent {
    param(
        [Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$VerifyPath,[hashtable]$VerifyArguments=@{},
        [Parameter(Mandatory)][string]$ApplyPath,[hashtable]$ApplyArguments=@{},
        [ValidateSet('Unknown','Compliant','NeedsChange')][string]$KnownState='Unknown'
    )
    $Context.ComponentNumber = [int]$Context.ComponentNumber + 1
    Write-Host ''
    Write-Host ("  COMPOSANT {0:00} | {1}" -f $Context.ComponentNumber,$DisplayName) -ForegroundColor White
    $compliant=$false
    if ($KnownState -eq 'Compliant') { $compliant=$true }
    elseif ($KnownState -eq 'NeedsChange') { $compliant=$false }
    else { $compliant=Test-WpcManagedScript -Context $Context -Path $VerifyPath -Arguments $VerifyArguments -DisplayName $DisplayName }
    if ($compliant) {
        Write-WpcStatus -Status 'DEJA_OK' -Message $DisplayName -Detail 'Composant deja conforme: aucune modification ni reinstallation.' -Context $Context
        Add-WpcComponentResult -Context $Context -DisplayName $DisplayName -Identity $VerifyPath -Outcome 'DEJA_OK'
        return [pscustomobject]@{ Changed=$false; Success=$true; Outcome='DEJA_OK' }
    }
    Write-WpcStatus -Status 'A_FAIRE' -Message $DisplayName -Detail 'Correction requise: application puis revalidation automatique.' -Context $Context
    Write-WpcStatus -Status 'EN_COURS' -Message "$DisplayName - application 1/2" -Detail 'Le script applique uniquement ce qui manque.' -Context $Context
    [void](Invoke-WpcManagedScript -Context $Context -Path $ApplyPath -Arguments $ApplyArguments -DisplayName $DisplayName -Phase 'Apply' -Purpose 'Apply')
    Write-WpcStatus -Status 'EN_COURS' -Message "$DisplayName - revalidation 2/2" -Detail 'Le script prouve immediatement le resultat apres modification.' -Context $Context
    [void](Invoke-WpcManagedScript -Context $Context -Path $VerifyPath -Arguments $VerifyArguments -DisplayName $DisplayName -Phase 'VerifyAfterApply' -Purpose 'VerifyAfterApply')
    Write-WpcStatus -Status 'FAIT' -Message $DisplayName -Detail 'Ecart corrige et etat final verifie.' -Context $Context
    Add-WpcComponentResult -Context $Context -DisplayName $DisplayName -Identity $VerifyPath -Outcome 'FAIT'
    return [pscustomobject]@{ Changed=$true; Success=$true; Outcome='FAIT' }
}

function Invoke-WpcIdempotentScript {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$Path,[hashtable]$VerifyArguments=@{},[hashtable]$ApplyArguments=@{},[string]$DisplayName='',[ValidateSet('Unknown','Compliant','NeedsChange')][string]$KnownState='Unknown')
    return Invoke-WpcPlannedComponent -Context $Context -DisplayName $DisplayName -VerifyPath $Path -VerifyArguments $VerifyArguments -ApplyPath $Path -ApplyArguments $ApplyArguments -KnownState $KnownState
}

function Invoke-WpcExternalCommand {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList=@(),
        [Parameter(Mandatory)][string]$LogIdentity,
        [string]$DisplayName='',
        [switch]$AllowFailure,
        [switch]$Quiet
    )
    if ([string]::IsNullOrWhiteSpace($DisplayName)) { $DisplayName=[IO.Path]::GetFileName($LogIdentity) }
    $logPath=Get-WpcLogPath -Context $Context -Identity $LogIdentity
    $safeArgs=Protect-WpcCommandText -Text ($ArgumentList -join ' ')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $logPath) | Out-Null
    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value ''
    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value ('=' * 96)
    Add-WpcLogLine -Path $logPath -Level 'START' -Message "Run=$($Context.RunId) Release=$($Context.Release) Command=$FilePath $safeArgs"
    if (-not $Quiet) {
        $phaseName = if ($LogIdentity -like 'scripts/wsl/*') { 'DevOps' } else { 'External' }
        Write-WpcPhaseHeader -Context $Context -Phase $phaseName
        Write-WpcActionHeader -Context $Context -DisplayName $DisplayName -Identity $LogIdentity -LogPath $logPath
        Write-WpcStatus -Status 'EN_COURS' -Message $DisplayName -Detail $LogIdentity -Context $Context
    }
    $started=Get-Date
    $heartbeat=New-WpcHeartbeat -Label $DisplayName
    try {
        & $FilePath @ArgumentList 2>&1 | ForEach-Object {
            foreach ($line in @(([string]$_) -split "`r?`n")) {
                $heartbeat.Touch()
                Write-WpcChildLine -Line $line -LogPath $logPath -Quiet:$Quiet
            }
        }
        $exitCode=$LASTEXITCODE
        $global:LASTEXITCODE=0
    } finally {
        if ($null -ne $heartbeat) { $heartbeat.Dispose() }
    }
    $duration=[math]::Round(((Get-Date)-$started).TotalSeconds,2)
    $parentPurpose=[Environment]::GetEnvironmentVariable('W11_CUSTOM_PARENT_PURPOSE')
    $purpose=if ($parentPurpose -match '^Probe') { 'ProbeNested' } else { 'External' }
    if ($exitCode -ne 0) {
        Add-WpcLogLine -Path $logPath -Level 'ERROR' -Message "ExitCode=$exitCode"
        Add-WpcEvent -Context $Context -Data @{ Kind='SCRIPT'; Purpose=$purpose; Phase='Run'; Script=$LogIdentity; DisplayName=$DisplayName; Outcome='FAILED'; Success=$false; DurationSeconds=$duration; LogPath=$logPath; Error="ExitCode=$exitCode" }
        $errorText="$DisplayName a echoue avec le code $exitCode. Voir $logPath"
        $result=[pscustomobject]@{ Success=$false; Outcome='FAILED'; Error=$errorText; ExitCode=$exitCode; LogPath=$logPath; DurationSeconds=$duration }
        if (-not $AllowFailure) { throw $errorText }
        return $result
    }
    Add-WpcLogLine -Path $logPath -Level 'END' -Message "Outcome=OK DurationSeconds=$duration"
    Add-WpcEvent -Context $Context -Data @{ Kind='SCRIPT'; Purpose=$purpose; Phase='Run'; Script=$LogIdentity; DisplayName=$DisplayName; Outcome='OK'; Success=$true; DurationSeconds=$duration; LogPath=$logPath; Error='' }
    if (-not $Quiet) { Write-WpcStatus -Status 'OK' -Message "$DisplayName termine" -Detail ("Duree: {0:n2}s | journal: {1}" -f $duration,$logPath) -Context $Context }
    return [pscustomobject]@{ Success=$true; Outcome='OK'; Error=''; ExitCode=0; LogPath=$logPath; DurationSeconds=$duration }
}

function Read-WpcRequiredValue {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$Name,[string]$CurrentValue='',[Parameter(Mandatory)][string]$Prompt,[Parameter(Mandatory)][string]$Example,[string]$Pattern='.+')
    if (-not [string]::IsNullOrWhiteSpace($CurrentValue) -and $CurrentValue -match $Pattern) { return $CurrentValue }
    Write-WpcStatus -Status 'ACTION_REQUISE' -Message "Valeur requise: $Name" -Detail "$Prompt Exemple: $Example" -Context $Context
    if ($Context.NonInteractive) { throw "Parametre $Name requis. Exemple: $Example" }
    while ($true) {
        $value=Read-Host $Prompt
        if (-not [string]::IsNullOrWhiteSpace($value) -and $value -match $Pattern) { return $value }
        Write-WpcStatus -Status 'AVERTISSEMENT' -Message "Valeur invalide pour $Name" -Detail "Exemple valide: $Example" -Context $Context
    }
}

function Confirm-WpcChanges {
    param([Parameter(Mandatory)]$Context,[switch]$Yes)
    if ($Yes) { return }
    if ($Context.NonInteractive) { throw 'Mode Apply non interactif: ajoute -Yes pour autoriser les modifications apres le plan factuel.' }
    Write-Host ''
    Write-Host 'Les etapes marquees A FAIRE vont maintenant etre appliquees.' -ForegroundColor Yellow
    while ($true) {
        $answer=(Read-Host 'Continuer ? [O/N]').Trim().ToLowerInvariant()
        if ($answer -in @('o','oui','y','yes')) { return }
        if ($answer -in @('n','non','no')) { throw 'Execution annulee avant toute modification planifiee.' }
        Write-Host 'Repondre O (oui) ou N (non).' -ForegroundColor Yellow
    }
}

function Complete-WpcRun {
    param([Parameter(Mandatory)]$Context,[bool]$Success=$true,[string]$FailureMessage='')
    $events=@()
    if (Test-Path $Context.EventsPath) {
        foreach ($line in Get-Content -LiteralPath $Context.EventsPath) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $events += ($line | ConvertFrom-Json) } catch {}
        }
    }
    $finalEvents=@($events | Where-Object { $_.Kind -eq 'COMPONENT' })
    $scriptEvents=@($events | Where-Object { $_.Kind -eq 'SCRIPT' -and $_.Purpose -notmatch '^Probe' })
    $latestScriptEvents=@()
    foreach ($group in ($scriptEvents | Group-Object Script)) { $latestScriptEvents += @($group.Group | Sort-Object Timestamp | Select-Object -Last 1) }
    $totalDuration=[math]::Round(((Get-Date)-$Context.StartedAt).TotalSeconds,2)
    $summary=[ordered]@{
        Release=$Context.Release; SchemaVersion=1; RunId=$Context.RunId; Mode=$Context.Mode; StartedAt=$Context.StartedAt.ToString('o'); CompletedAt=(Get-Date).ToString('o')
        Success=$Success; FailureMessage=(Protect-WpcCommandText -Text $FailureMessage); Components=$finalEvents; ScriptExecutions=$scriptEvents; LatestScriptState=$latestScriptEvents
        PowerShell=[ordered]@{ Edition=[string]$PSVersionTable.PSEdition; Version=[string]$PSVersionTable.PSVersion; MinimumVersion='7.6.4'; Executable='pwsh.exe'; Architecture='x64'; WindowsPowerShellSupported=$false }
        TotalDurationSeconds=$totalDuration; VisiblePhases=[int]$Context.PhaseNumber; VisibleActions=[int]$Context.ActionNumber
        Counts=[ordered]@{
            AlreadyOk=@($finalEvents | Where-Object Outcome -EQ 'DEJA_OK').Count
            Changed=@($finalEvents | Where-Object Outcome -EQ 'FAIT').Count
            FailedScripts=@($latestScriptEvents | Where-Object Success -EQ $false).Count
            ExecutedScripts=$scriptEvents.Count
        }
    }
    $summaryPath=Join-Path $Context.RunDir 'summary.json'
    $latestDir=Join-Path $Context.RepoRoot 'reports\orchestration'
    New-Item -ItemType Directory -Force -Path $latestDir | Out-Null
    $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $latestDir 'latest-run.json') -Encoding UTF8
    Write-Host ''
    Write-Host ('-' * 78) -ForegroundColor DarkCyan
    Write-Host "  SYNTHESE D EXECUTION - RELEASE $($Context.Release)" -ForegroundColor Cyan
    Write-Host ('-' * 78) -ForegroundColor DarkCyan
    Write-Host ("  PowerShell         : {0} | Core | x64 | pwsh.exe" -f $PSVersionTable.PSVersion) -ForegroundColor White
    Write-Host ("  Duree totale       : {0}" -f (Get-WpcElapsedText -StartedAt $Context.StartedAt)) -ForegroundColor White
    Write-Host ("  Phases visibles    : {0}" -f $summary.VisiblePhases)
    Write-Host ("  Sous-etapes        : {0}" -f $summary.VisibleActions)
    Write-Host ("  Deja conformes     : {0}" -f $summary.Counts.AlreadyOk) -ForegroundColor Green
    Write-Host ("  Modifies/valides   : {0}" -f $summary.Counts.Changed) -ForegroundColor Green
    Write-Host ("  Scripts executes   : {0}" -f $summary.Counts.ExecutedScripts)
    Write-Host ("  Echecs actuels     : {0}" -f $summary.Counts.FailedScripts) -ForegroundColor $(if ($summary.Counts.FailedScripts -gt 0) { 'Red' } else { 'Green' })
    Write-Host ("  Resume             : {0}" -f $summaryPath) -ForegroundColor DarkGray
    if ($Success) { Write-Host '  VERDICT: execution terminee sans erreur.' -ForegroundColor Green }
    else { Write-Host ("  VERDICT: execution interrompue - {0}" -f $FailureMessage) -ForegroundColor Red }
    Write-Host ('-' * 78) -ForegroundColor DarkCyan
}

Export-ModuleMember -Function Get-WpcProjectRelease, New-WpcRunContext, Get-WpcRunContextFromEnvironment, Write-WpcStatus, Write-WpcBanner, Invoke-WpcManagedScript, Test-WpcManagedScript, Invoke-WpcPlannedComponent, Invoke-WpcIdempotentScript, Invoke-WpcExternalCommand, Read-WpcRequiredValue, Confirm-WpcChanges, Complete-WpcRun, Get-WpcLogPath, Add-WpcComponentResult, Write-WpcPhaseHeader, Write-WpcActionHeader
