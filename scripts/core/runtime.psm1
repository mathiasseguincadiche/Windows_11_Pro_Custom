Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
        'DEJA_OK' { 'DÉJÀ OK' } 'A_FAIRE' { 'À FAIRE' } 'ACTION_REQUISE' { 'ACTION REQUISE' }
        'EN_COURS' { 'EN COURS' } 'AVERTISSEMENT' { 'AVERTISSEMENT' } 'ATTENTE' { 'EN ATTENTE' }
        default { $Status.Replace('_', ' ') }
    }
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
    Write-Host ('=' * 78) -ForegroundColor DarkCyan
    Add-WpcLogLine -Path $Context.OrchestratorLogPath -Level 'RUN' -Message "$Title | Release=$($Context.Release) | RunId=$($Context.RunId)"
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
    if ($Line -match '^\s*\[(OK|DÉJÀ OK|DEJA OK|FAIT|READY)\]') { $color='Green' }
    elseif ($Line -match '^\s*\[(WARN|WARNING|AVERTISSEMENT|À FAIRE|A FAIRE|TODO)\]') { $color='Yellow' }
    elseif ($Line -match '^\s*\[(KO|ERROR|ERREUR|FAILED)\]') { $color='Red' }
    elseif ($Line -match '^\s*\[(ACTION|ACTION REQUISE|USER ACTION)\]') { $color='Magenta' }
    elseif ($Line -match '^\s*\[(INFO|ANALYSE|EN COURS)\]') { $color='Cyan' }
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
    Add-WpcLogLine -Path $logPath -Level 'HOST' -Message "Computer=$env:COMPUTERNAME User=$env:USERNAME PowerShell=$($PSVersionTable.PSVersion)"
    if (-not $Quiet) { Write-WpcStatus -Status 'EN_COURS' -Message $DisplayName -Detail $relative -Context $Context }

    $success=$false; $errorText=''; $sawAlready=$false; $sawChanged=$false; $sawUserAction=$false
    $oldParent = [Environment]::GetEnvironmentVariable('W11_CUSTOM_PARENT_PURPOSE')
    try {
        if ($Purpose -eq 'Probe') { $env:W11_CUSTOM_PARENT_PURPOSE='Probe' }
        & $Path @Arguments 2>&1 3>&1 4>&1 5>&1 6>&1 | ForEach-Object {
            foreach ($line in @(([string]$_) -split "`r?`n")) {
                if ($line -match '\[(DÉJÀ OK|DEJA OK)\]') { $sawAlready=$true }
                if ($line -match '\[(FAIT|CHANGED)\]') { $sawChanged=$true }
                if ($line -match '\[(ACTION REQUISE|USER ACTION)\]') { $sawUserAction=$true }
                Write-WpcChildLine -Line $line -LogPath $logPath -Quiet:$Quiet
            }
        }
        $success=$true
    } catch {
        $errorText=$_.Exception.Message
        Add-WpcLogLine -Path $logPath -Level 'ERROR' -Message (Protect-WpcCommandText -Text $errorText)
        if (-not $Quiet) { Write-WpcStatus -Status $(if ($Purpose -eq 'Probe') { 'A_FAIRE' } else { 'ERREUR' }) -Message $DisplayName -Detail $errorText -Context $Context }
    } finally {
        if ($null -eq $oldParent) { Remove-Item Env:W11_CUSTOM_PARENT_PURPOSE -ErrorAction SilentlyContinue } else { $env:W11_CUSTOM_PARENT_PURPOSE=$oldParent }
    }
    $duration=[math]::Round(((Get-Date)-$started).TotalSeconds,2)
    $outcome = if (-not $success) { 'FAILED' } elseif ($sawUserAction) { 'ACTION_REQUISE' } elseif ($sawChanged) { 'FAIT' } elseif ($sawAlready) { 'DEJA_OK' } else { 'OK' }
    if ($Purpose -eq 'Probe') { $outcome=if ($success) { 'DEJA_OK' } else { 'A_FAIRE' } }
    Add-WpcLogLine -Path $logPath -Level 'END' -Message "Outcome=$outcome DurationSeconds=$duration"
    Add-WpcEvent -Context $Context -Data @{ Kind='SCRIPT'; Purpose=$effectivePurpose; Phase=$Phase; Script=$relative; DisplayName=$DisplayName; Outcome=$outcome; Success=$success; DurationSeconds=$duration; LogPath=$logPath; Error=(Protect-WpcCommandText -Text $errorText) }
    $result=[pscustomobject]@{ Success=$success; Outcome=$outcome; Error=$errorText; LogPath=$logPath; DurationSeconds=$duration }
    if (-not $success -and -not $AllowFailure) { throw "$DisplayName a échoué: $errorText" }
    return $result
}

function Test-WpcManagedScript {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$Path,[hashtable]$Arguments=@{},[string]$DisplayName='')
    if ([string]::IsNullOrWhiteSpace($DisplayName)) { $DisplayName=[IO.Path]::GetFileName($Path) }
    Write-WpcStatus -Status 'ANALYSE' -Message $DisplayName -Detail 'Lecture de lʼétat réel de la machine avant décision.' -Context $Context
    $result=Invoke-WpcManagedScript -Context $Context -Path $Path -Arguments $Arguments -DisplayName $DisplayName -Phase 'Probe' -Purpose 'Probe' -AllowFailure -Quiet
    if ($result.Success) { Write-WpcStatus -Status 'DEJA_OK' -Message $DisplayName -Detail 'La cible est déjà conforme; aucune modification nécessaire.' -Context $Context; return $true }
    Write-WpcStatus -Status 'A_FAIRE' -Message $DisplayName -Detail 'La cible nʼest pas conforme; cette étape est planifiée.' -Context $Context
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
    $compliant=$false
    if ($KnownState -eq 'Compliant') { $compliant=$true }
    elseif ($KnownState -eq 'NeedsChange') { $compliant=$false }
    else { $compliant=Test-WpcManagedScript -Context $Context -Path $VerifyPath -Arguments $VerifyArguments -DisplayName $DisplayName }
    if ($compliant) {
        Add-WpcComponentResult -Context $Context -DisplayName $DisplayName -Identity $VerifyPath -Outcome 'DEJA_OK'
        return [pscustomobject]@{ Changed=$false; Success=$true; Outcome='DEJA_OK' }
    }
    Write-WpcStatus -Status 'A_FAIRE' -Message $DisplayName -Detail 'Application uniquement de ce qui manque, puis revalidation factuelle.' -Context $Context
    [void](Invoke-WpcManagedScript -Context $Context -Path $ApplyPath -Arguments $ApplyArguments -DisplayName $DisplayName -Phase 'Apply' -Purpose 'Apply')
    [void](Invoke-WpcManagedScript -Context $Context -Path $VerifyPath -Arguments $VerifyArguments -DisplayName $DisplayName -Phase 'VerifyAfterApply' -Purpose 'VerifyAfterApply')
    Write-WpcStatus -Status 'FAIT' -Message $DisplayName -Detail 'Écart corrigé et état final vérifié.' -Context $Context
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
    if (-not $Quiet) { Write-WpcStatus -Status 'EN_COURS' -Message $DisplayName -Detail $LogIdentity -Context $Context }
    $started=Get-Date
    & $FilePath @ArgumentList 2>&1 | ForEach-Object { foreach ($line in @(([string]$_) -split "`r?`n")) { Write-WpcChildLine -Line $line -LogPath $logPath -Quiet:$Quiet } }
    $exitCode=$LASTEXITCODE; $global:LASTEXITCODE=0
    $duration=[math]::Round(((Get-Date)-$started).TotalSeconds,2)
    $parentPurpose=[Environment]::GetEnvironmentVariable('W11_CUSTOM_PARENT_PURPOSE')
    $purpose=if ($parentPurpose -match '^Probe') { 'ProbeNested' } else { 'External' }
    if ($exitCode -ne 0) {
        Add-WpcLogLine -Path $logPath -Level 'ERROR' -Message "ExitCode=$exitCode"
        Add-WpcEvent -Context $Context -Data @{ Kind='SCRIPT'; Purpose=$purpose; Phase='Run'; Script=$LogIdentity; DisplayName=$DisplayName; Outcome='FAILED'; Success=$false; DurationSeconds=$duration; LogPath=$logPath; Error="ExitCode=$exitCode" }
        $errorText="$DisplayName a échoué avec le code $exitCode. Voir $logPath"
        $result=[pscustomobject]@{ Success=$false; Outcome='FAILED'; Error=$errorText; ExitCode=$exitCode; LogPath=$logPath; DurationSeconds=$duration }
        if (-not $AllowFailure) { throw $errorText }
        return $result
    }
    Add-WpcLogLine -Path $logPath -Level 'END' -Message "Outcome=OK DurationSeconds=$duration"
    Add-WpcEvent -Context $Context -Data @{ Kind='SCRIPT'; Purpose=$purpose; Phase='Run'; Script=$LogIdentity; DisplayName=$DisplayName; Outcome='OK'; Success=$true; DurationSeconds=$duration; LogPath=$logPath; Error='' }
    return [pscustomobject]@{ Success=$true; Outcome='OK'; Error=''; ExitCode=0; LogPath=$logPath; DurationSeconds=$duration }
}

function Read-WpcRequiredValue {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$Name,[string]$CurrentValue='',[Parameter(Mandatory)][string]$Prompt,[Parameter(Mandatory)][string]$Example,[string]$Pattern='.+')
    if (-not [string]::IsNullOrWhiteSpace($CurrentValue) -and $CurrentValue -match $Pattern) { return $CurrentValue }
    Write-WpcStatus -Status 'ACTION_REQUISE' -Message "Valeur requise: $Name" -Detail "$Prompt Exemple: $Example" -Context $Context
    if ($Context.NonInteractive) { throw "Paramètre $Name requis. Exemple: $Example" }
    while ($true) {
        $value=Read-Host $Prompt
        if (-not [string]::IsNullOrWhiteSpace($value) -and $value -match $Pattern) { return $value }
        Write-WpcStatus -Status 'AVERTISSEMENT' -Message "Valeur invalide pour $Name" -Detail "Exemple valide: $Example" -Context $Context
    }
}

function Confirm-WpcChanges {
    param([Parameter(Mandatory)]$Context,[switch]$Yes)
    if ($Yes) { return }
    if ($Context.NonInteractive) { throw 'Mode Apply non interactif: ajoute -Yes pour autoriser les modifications après le plan factuel.' }
    Write-Host ''
    Write-Host 'Les étapes marquées À FAIRE vont maintenant être appliquées.' -ForegroundColor Yellow
    while ($true) {
        $answer=(Read-Host 'Continuer ? [O/N]').Trim().ToLowerInvariant()
        if ($answer -in @('o','oui','y','yes')) { return }
        if ($answer -in @('n','non','no')) { throw 'Exécution annulée avant toute modification planifiée.' }
        Write-Host 'Répondre O (oui) ou N (non).' -ForegroundColor Yellow
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
    $summary=[ordered]@{
        Release=$Context.Release; SchemaVersion=1; RunId=$Context.RunId; Mode=$Context.Mode; StartedAt=$Context.StartedAt.ToString('o'); CompletedAt=(Get-Date).ToString('o')
        Success=$Success; FailureMessage=(Protect-WpcCommandText -Text $FailureMessage); Components=$finalEvents; ScriptExecutions=$scriptEvents; LatestScriptState=$latestScriptEvents
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
    Write-Host "  SYNTHÈSE D’EXÉCUTION — RELEASE $($Context.Release)" -ForegroundColor Cyan
    Write-Host ('-' * 78) -ForegroundColor DarkCyan
    Write-Host ("  Déjà conformes : {0}" -f $summary.Counts.AlreadyOk) -ForegroundColor Green
    Write-Host ("  Modifiés/validés : {0}" -f $summary.Counts.Changed) -ForegroundColor Green
    Write-Host ("  Scripts exécutés : {0}" -f $summary.Counts.ExecutedScripts)
    Write-Host ("  Échecs actuels    : {0}" -f $summary.Counts.FailedScripts) -ForegroundColor $(if ($summary.Counts.FailedScripts -gt 0) { 'Red' } else { 'Green' })
    Write-Host ("  Résumé            : {0}" -f $summaryPath) -ForegroundColor DarkGray
    if ($Success) { Write-Host '  VERDICT: exécution terminée sans erreur.' -ForegroundColor Green }
    else { Write-Host ("  VERDICT: exécution interrompue - {0}" -f $FailureMessage) -ForegroundColor Red }
    Write-Host ('-' * 78) -ForegroundColor DarkCyan
}

Export-ModuleMember -Function Get-WpcProjectRelease, New-WpcRunContext, Get-WpcRunContextFromEnvironment, Write-WpcStatus, Write-WpcBanner, Invoke-WpcManagedScript, Test-WpcManagedScript, Invoke-WpcPlannedComponent, Invoke-WpcIdempotentScript, Invoke-WpcExternalCommand, Read-WpcRequiredValue, Confirm-WpcChanges, Complete-WpcRun, Get-WpcLogPath, Add-WpcComponentResult
