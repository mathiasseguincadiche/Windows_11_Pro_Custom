[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Verify', 'Rollback')]
    [string]$Mode = 'Audit',

    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Distribution = 'Ubuntu'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$sourceFragment = Join-Path $repoRoot 'config\windows-terminal\profiles.fragment.json'
$sourceActions = Join-Path $repoRoot 'config\windows-terminal\actions.json'
$sourceStarship = Join-Path $repoRoot 'config\windows-terminal\starship.windows.toml'
$stateDir = Join-Path $repoRoot 'state\windows-terminal'
$stateMeta = Join-Path $stateDir 'state.json'
$backupDir = Join-Path $stateDir 'backup'

$psProfileGuid = '{a3cc45a8-6e2f-4f3d-bca6-7d6df942da41}'
$psProfileName = 'PowerShell 7 - DevOps'
$wslProfileName = 'Ubuntu - DevOps'
$actionsFileName = 'windows11-pro-custom.actions.json'
$markerBegin = '# BEGIN windows11-pro-custom:windows-terminal'
$markerEnd = '# END windows11-pro-custom:windows-terminal'

foreach ($source in @($sourceFragment, $sourceActions, $sourceStarship)) {
    if (-not (Test-Path -LiteralPath $source)) { throw "Source Windows Terminal absente: $source" }
}

function Get-TerminalSettingsPath {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $candidates[0]
}

function Get-PowerShellProfilePath {
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if (-not $pwsh) {
        return (Join-Path $HOME 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1')
    }
    $resolved = @(& $pwsh.Source -NoLogo -NoProfile -Command '$PROFILE' 2>$null | Where-Object { $_ } | Select-Object -First 1)
    if ($resolved.Count -eq 0) { throw 'PowerShell 7 est présent mais son chemin de profil nʼa pas pu être déterminé.' }
    return [string]$resolved[0]
}

function Remove-JsonComments {
    param([Parameter(Mandatory)][string]$Text)

    $sb = [System.Text.StringBuilder]::new()
    $inString = $false
    $escape = $false
    $lineComment = $false
    $blockComment = $false

    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }

        if ($lineComment) {
            if ($c -eq "`n") { $lineComment = $false; [void]$sb.Append($c) }
            continue
        }
        if ($blockComment) {
            if ($c -eq '*' -and $next -eq '/') { $blockComment = $false; $i++ }
            continue
        }
        if ($inString) {
            [void]$sb.Append($c)
            if ($escape) { $escape = $false; continue }
            if ($c -eq '\') { $escape = $true; continue }
            if ($c -eq '"') { $inString = $false }
            continue
        }
        if ($c -eq '"') { $inString = $true; [void]$sb.Append($c); continue }
        if ($c -eq '/' -and $next -eq '/') { $lineComment = $true; $i++; continue }
        if ($c -eq '/' -and $next -eq '*') { $blockComment = $true; $i++; continue }
        [void]$sb.Append($c)
    }
    return $sb.ToString()
}

function Read-TerminalSettings {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
    $clean = Remove-JsonComments -Text $raw
    $clean = [regex]::Replace($clean, ',\s*(?=[}\]])', '')
    try { return ($clean | ConvertFrom-Json) }
    catch { throw "settings.json Windows Terminal invalide ou non analysable: $Path. $($_.Exception.Message)" }
}

function Set-ObjectProperty {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string]$Name, $Value)
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
    else { $prop.Value = $Value }
}

function Test-WslDistribution {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return $false }
    $names = @((wsl.exe --list --quiet 2>$null) -replace "`0", '' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $global:LASTEXITCODE = 0
    return ($names -contains $Distribution)
}

function Test-NerdFont {
    $patterns = @('JetBrainsMono*Nerd*', 'JetBrainsMonoNerdFont*')
    foreach ($root in @((Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'), (Join-Path $env:WINDIR 'Fonts'))) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($pattern in $patterns) {
            if (Get-ChildItem -LiteralPath $root -Filter $pattern -File -ErrorAction SilentlyContinue | Select-Object -First 1) { return $true }
        }
    }
    foreach ($regPath in @('HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts', 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts')) {
        if (-not (Test-Path $regPath)) { continue }
        $props = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).PSObject.Properties
        if ($props | Where-Object { $_.Name -match '(?i)JetBrainsMono.*Nerd' -or ([string]$_.Value) -match '(?i)JetBrainsMono.*Nerd' } | Select-Object -First 1) { return $true }
    }
    return $false
}

function Get-RenderedFragment {
    return (Get-Content -Raw -LiteralPath $sourceFragment -Encoding UTF8).Replace('__WPC_DISTRIBUTION__', $Distribution)
}

function Get-ManagedPowerShellBlock {
    $template = @'
# BEGIN windows11-pro-custom:windows-terminal
$env:STARSHIP_CONFIG = Join-Path $HOME '.config\windows11-pro-custom\starship.windows.toml'

if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (& starship init powershell)
}

if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    try {
        Set-PSReadLineOption -EditMode Windows
        Set-PSReadLineOption -PredictionSource History
        Set-PSReadLineOption -HistoryNoDuplicates
    } catch {}
}

function Enter-UbuntuDevOps {
    wsl.exe -d '__WPC_DISTRIBUTION__'
}

function Get-WslStatus {
    wsl.exe --status
}

function Get-WslList {
    wsl.exe --list --verbose
}
# END windows11-pro-custom:windows-terminal
'@
    return $template.Replace('__WPC_DISTRIBUTION__', $Distribution).Trim()
}

function Get-Targets {
    $settings = Get-TerminalSettingsPath
    $settingsDir = Split-Path $settings -Parent
    return [pscustomobject]@{
        Settings = $settings
        Actions = Join-Path $settingsDir $actionsFileName
        Fragment = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\Windows11ProCustom\terminal-devops.profiles.json'
        Starship = Join-Path $HOME '.config\windows11-pro-custom\starship.windows.toml'
        PowerShellProfile = Get-PowerShellProfilePath
    }
}

function Test-FileMatch {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Target)
    if (-not (Test-Path -LiteralPath $Target)) { return $false }
    return (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash
}

function Test-FragmentMatch {
    param([Parameter(Mandatory)][string]$Target)
    if (-not (Test-Path -LiteralPath $Target)) { return $false }
    return (Get-Content -Raw -LiteralPath $Target -Encoding UTF8) -eq (Get-RenderedFragment)
}

function Test-PowerShellProfileMatch {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $content = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
    if (($content.Split($markerBegin).Count - 1) -ne 1) { return $false }
    if (($content.Split($markerEnd).Count - 1) -ne 1) { return $false }
    $pattern = '(?s)' + [regex]::Escape($markerBegin) + '.*?' + [regex]::Escape($markerEnd)
    $match = [regex]::Match($content, $pattern)
    return ($match.Success -and $match.Value.Trim() -eq (Get-ManagedPowerShellBlock))
}

function Test-SettingsMatch {
    param([Parameter(Mandatory)][string]$Path)
    $settings = Read-TerminalSettings -Path $Path
    if ($null -eq $settings) { return $false }

    $defaultOk = ($settings.PSObject.Properties['defaultProfile'] -and [string]$settings.defaultProfile -eq $psProfileGuid)
    $imports = if ($settings.PSObject.Properties['import']) { @($settings.PSObject.Properties['import'].Value) } else { @() }
    $disabled = if ($settings.PSObject.Properties['disabledProfileSources']) { @($settings.PSObject.Properties['disabledProfileSources'].Value) } else { @() }
    return ($defaultOk -and ($imports -contains $actionsFileName) -and ($disabled -contains 'Windows.Terminal.PowershellCore') -and ($disabled -contains 'Windows.Terminal.Wsl'))
}

function Get-Contract {
    $targets = Get-Targets
    $checks = [ordered]@{
        'Windows Terminal' = [bool](Get-Command wt.exe -ErrorAction SilentlyContinue)
        'PowerShell 7' = [bool](Get-Command pwsh.exe -ErrorAction SilentlyContinue)
        'Starship Windows' = [bool](Get-Command starship.exe -ErrorAction SilentlyContinue)
        'JetBrainsMono Nerd Font' = Test-NerdFont
        "WSL distribution $Distribution" = Test-WslDistribution
        'Fragment profils' = Test-FragmentMatch -Target $targets.Fragment
        'Actions importées' = Test-FileMatch -Source $sourceActions -Target $targets.Actions
        'Starship Windows config' = Test-FileMatch -Source $sourceStarship -Target $targets.Starship
        'Profil PowerShell géré' = Test-PowerShellProfileMatch -Path $targets.PowerShellProfile
        'settings.json Windows Terminal' = Test-SettingsMatch -Path $targets.Settings
    }
    return [pscustomobject]@{ Targets=$targets; Checks=$checks }
}

function Show-Contract {
    param([Parameter(Mandatory)]$Contract, [switch]$FailOnError)
    $failed = [System.Collections.Generic.List[string]]::new()
    foreach ($check in $Contract.Checks.GetEnumerator()) {
        if ($check.Value) { Write-Host "[OK] $($check.Key)" -ForegroundColor Green }
        else { Write-Host "[KO] $($check.Key)" -ForegroundColor $(if ($FailOnError) { 'Red' } else { 'Yellow' }); $failed.Add([string]$check.Key) }
    }
    if ($FailOnError -and $failed.Count -gt 0) { throw "Windows Terminal DevOps non conforme: $($failed -join ', ')" }
    return $failed.Count
}

function Save-InitialState {
    param([Parameter(Mandatory)]$Targets)
    if (Test-Path -LiteralPath $stateMeta) { return }
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

    $map = [ordered]@{
        Settings = [ordered]@{ Path=$Targets.Settings; Backup=(Join-Path $backupDir 'settings.json') }
        Actions = [ordered]@{ Path=$Targets.Actions; Backup=(Join-Path $backupDir 'actions.json') }
        Fragment = [ordered]@{ Path=$Targets.Fragment; Backup=(Join-Path $backupDir 'profiles.fragment.json') }
        Starship = [ordered]@{ Path=$Targets.Starship; Backup=(Join-Path $backupDir 'starship.windows.toml') }
        PowerShellProfile = [ordered]@{ Path=$Targets.PowerShellProfile; Backup=(Join-Path $backupDir 'Microsoft.PowerShell_profile.ps1') }
    }
    foreach ($entry in $map.GetEnumerator()) {
        $existed = Test-Path -LiteralPath $entry.Value.Path
        $entry.Value.Existed = $existed
        if ($existed) { Copy-Item -LiteralPath $entry.Value.Path -Destination $entry.Value.Backup -Force }
    }
    $state = [ordered]@{ RecordedAt=(Get-Date).ToString('o'); Distribution=$Distribution; Files=$map }
    $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $stateMeta -Encoding UTF8
    Write-Host "[OK] État initial Windows Terminal sauvegardé: $stateMeta" -ForegroundColor Green
}

function Set-TerminalSettings {
    param([Parameter(Mandatory)][string]$Path)
    $settings = Read-TerminalSettings -Path $Path
    if ($null -eq $settings) {
        $settings = [pscustomobject][ordered]@{
            '$schema' = 'https://aka.ms/terminal-profiles-schema'
            defaultProfile = $psProfileGuid
            import = @($actionsFileName)
            disabledProfileSources = @('Windows.Terminal.PowershellCore', 'Windows.Terminal.Wsl')
            profiles = [pscustomobject][ordered]@{ list=@() }
        }
    } else {
        Set-ObjectProperty -Object $settings -Name 'defaultProfile' -Value $psProfileGuid
        $imports = if ($settings.PSObject.Properties['import']) { @($settings.PSObject.Properties['import'].Value) } else { @() }
        if ($imports -notcontains $actionsFileName) { $imports += $actionsFileName }
        Set-ObjectProperty -Object $settings -Name 'import' -Value $imports

        $disabled = if ($settings.PSObject.Properties['disabledProfileSources']) { @($settings.PSObject.Properties['disabledProfileSources'].Value) } else { @() }
        foreach ($source in @('Windows.Terminal.PowershellCore', 'Windows.Terminal.Wsl')) {
            if ($disabled -notcontains $source) { $disabled += $source }
        }
        Set-ObjectProperty -Object $settings -Name 'disabledProfileSources' -Value $disabled
    }

    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    $settings | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Set-PowerShellProfile {
    param([Parameter(Mandatory)][string]$Path)
    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    $content = if (Test-Path -LiteralPath $Path) { Get-Content -Raw -LiteralPath $Path -Encoding UTF8 } else { '' }
    $pattern = '(?s)' + [regex]::Escape($markerBegin) + '.*?' + [regex]::Escape($markerEnd)
    $block = Get-ManagedPowerShellBlock
    if ([regex]::IsMatch($content, $pattern)) { $content = [regex]::Replace($content, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $block }) }
    else {
        if ($content -and -not $content.EndsWith("`n")) { $content += "`r`n" }
        $content += "`r`n$block`r`n"
    }
    Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

function Restore-InitialState {
    if (-not (Test-Path -LiteralPath $stateMeta)) {
        Write-Host '[DÉJÀ OK] Aucun état initial Windows Terminal enregistré; rollback inutile.' -ForegroundColor Green
        return
    }
    $state = Get-Content -Raw -LiteralPath $stateMeta -Encoding UTF8 | ConvertFrom-Json
    foreach ($prop in $state.Files.PSObject.Properties) {
        $entry = $prop.Value
        if ([bool]$entry.Existed) {
            if (-not (Test-Path -LiteralPath ([string]$entry.Backup))) { throw "Sauvegarde absente pour $($prop.Name): $($entry.Backup)" }
            New-Item -ItemType Directory -Force -Path (Split-Path ([string]$entry.Path) -Parent) | Out-Null
            Copy-Item -LiteralPath ([string]$entry.Backup) -Destination ([string]$entry.Path) -Force
        } else {
            Remove-Item -LiteralPath ([string]$entry.Path) -Force -ErrorAction SilentlyContinue
        }
    }
    Remove-Item -LiteralPath $stateDir -Recurse -Force
    Write-Host '[FAIT] Configuration Windows Terminal restaurée à lʼétat initial enregistré.' -ForegroundColor Green
}

if ($Mode -eq 'Rollback') { Restore-InitialState; return }

$contract = Get-Contract
if ($Mode -eq 'Audit') {
    $remaining = Show-Contract -Contract $contract
    if ($remaining -eq 0) { Write-Host '[DÉJÀ OK] Windows Terminal DevOps est conforme.' -ForegroundColor Green }
    else { Write-Host "[À FAIRE] Windows Terminal DevOps: $remaining contrôle(s) à corriger." -ForegroundColor Yellow }
    return
}

if ($Mode -eq 'Verify') {
    [void](Show-Contract -Contract $contract -FailOnError)
    Write-Host '[OK] Windows Terminal DevOps validé.' -ForegroundColor Green
    return
}

$dependencyChecks = @('Windows Terminal', 'PowerShell 7', 'Starship Windows', 'JetBrainsMono Nerd Font', "WSL distribution $Distribution")
$missingDependencies = @($dependencyChecks | Where-Object { -not [bool]$contract.Checks[$_] })
if ($missingDependencies.Count -gt 0) {
    throw "Prérequis Windows Terminal absents: $($missingDependencies -join ', '). Le bootstrap applications/WSL doit converger avant le poste de travail."
}

if ((Show-Contract -Contract $contract) -eq 0) {
    Write-Host '[DÉJÀ OK] Windows Terminal DevOps déjà conforme; aucune réécriture.' -ForegroundColor Green
    return
}

# Valider le JSONC existant avant toute mutation, afin de ne jamais masquer un fichier utilisateur invalide.
if (Test-Path -LiteralPath $contract.Targets.Settings) { [void](Read-TerminalSettings -Path $contract.Targets.Settings) }
Save-InitialState -Targets $contract.Targets

New-Item -ItemType Directory -Force -Path (Split-Path $contract.Targets.Fragment -Parent) | Out-Null
[System.IO.File]::WriteAllText($contract.Targets.Fragment, (Get-RenderedFragment), [System.Text.UTF8Encoding]::new($false))

New-Item -ItemType Directory -Force -Path (Split-Path $contract.Targets.Actions -Parent) | Out-Null
Copy-Item -LiteralPath $sourceActions -Destination $contract.Targets.Actions -Force

New-Item -ItemType Directory -Force -Path (Split-Path $contract.Targets.Starship -Parent) | Out-Null
Copy-Item -LiteralPath $sourceStarship -Destination $contract.Targets.Starship -Force

Set-PowerShellProfile -Path $contract.Targets.PowerShellProfile
Set-TerminalSettings -Path $contract.Targets.Settings

$verified = Get-Contract
[void](Show-Contract -Contract $verified -FailOnError)
Write-Host '[FAIT] Windows Terminal DevOps configuré et revalidé.' -ForegroundColor Green
