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
$terminalSettingsModule = Join-Path $repoRoot 'scripts\core\windows-terminal-settings.psm1'
$stateDir = Join-Path $repoRoot 'state\windows-terminal'
$stateMeta = Join-Path $stateDir 'state.json'
$backupDir = Join-Path $stateDir 'backup'

$psProfileGuid = '{a3cc45a8-6e2f-4f3d-bca6-7d6df942da41}'
$actionsFileName = 'windows11-pro-custom.actions.json'
$markerBegin = '# BEGIN windows11-pro-custom:windows-terminal'
$markerEnd = '# END windows11-pro-custom:windows-terminal'

foreach ($source in @($sourceFragment, $sourceActions, $sourceStarship, $terminalSettingsModule)) {
    if (-not (Test-Path -LiteralPath $source)) { throw "Source Windows Terminal absente: $source" }
}
Import-Module $terminalSettingsModule -Force

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

function Read-TerminalSettings {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
    try {
        return ConvertFrom-WpcTerminalSettingsText -Text $raw
    } catch {
        throw "settings.json Windows Terminal invalide ou non analysable: $Path. $($_.Exception.Message)"
    }
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
    $fragmentRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\Windows11ProCustom'
    return [pscustomobject]@{
        Settings = $settings
        Actions = Join-Path $settingsDir $actionsFileName
        Fragment = Join-Path $fragmentRoot 'terminal-devops.profiles.json'
        ActionsFragment = Join-Path $fragmentRoot 'terminal-devops.actions.json'
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

function Get-SettingsEvidence {
    param([Parameter(Mandatory)][string]$Path)
    $settings = Read-TerminalSettings -Path $Path
    return Get-WpcTerminalSettingsEvidence -Settings $settings -ExpectedDefaultProfile $psProfileGuid -LegacyImportName $actionsFileName
}

function Get-Contract {
    $targets = Get-Targets
    $settingsEvidence = Get-SettingsEvidence -Path $targets.Settings
    $checks = [ordered]@{
        'Windows Terminal' = [bool](Get-Command wt.exe -ErrorAction SilentlyContinue)
        'PowerShell 7' = [bool](Get-Command pwsh.exe -ErrorAction SilentlyContinue)
        'Starship Windows' = [bool](Get-Command starship.exe -ErrorAction SilentlyContinue)
        'JetBrainsMono Nerd Font' = Test-NerdFont
        "WSL distribution $Distribution" = Test-WslDistribution
        'Fragment profils' = Test-FragmentMatch -Target $targets.Fragment
        'Fragment actions' = Test-FileMatch -Source $sourceActions -Target $targets.ActionsFragment
        'Ancien import actions retiré' = -not (Test-Path -LiteralPath $targets.Actions)
        'Starship Windows config' = Test-FileMatch -Source $sourceStarship -Target $targets.Starship
        'Profil PowerShell géré' = Test-PowerShellProfileMatch -Path $targets.PowerShellProfile
        'settings.json Windows Terminal' = [bool]$settingsEvidence.IsCompliant
    }
    return [pscustomobject]@{ Targets=$targets; Checks=$checks; SettingsEvidence=$settingsEvidence }
}

function Show-Contract {
    param([Parameter(Mandatory)]$Contract, [switch]$FailOnError)
    $failed = [System.Collections.Generic.List[string]]::new()
    foreach ($check in $Contract.Checks.GetEnumerator()) {
        if ($check.Value) {
            Write-Host "[OK] $($check.Key)" -ForegroundColor Green
        } else {
            Write-Host "[KO] $($check.Key)" -ForegroundColor $(if ($FailOnError) { 'Red' } else { 'Yellow' })
            if ($check.Key -eq 'settings.json Windows Terminal') {
                $e = $Contract.SettingsEvidence
                Write-Host "     defaultProfile='$($e.DefaultProfile)' attendu='$psProfileGuid' | legacyImportAbsent=$($e.LegacyImportAbsent) | PowerShellCoreDisabled=$($e.PowerShellCoreDisabled) | WslDisabled=$($e.WslDisabled)" -ForegroundColor DarkGray
            }
            $failed.Add([string]$check.Key)
        }
    }
    if ($FailOnError -and $failed.Count -gt 0) { throw "Windows Terminal DevOps non conforme: $($failed -join ', ')" }
    return $failed.Count
}

function Get-StateTargetMap {
    param([Parameter(Mandatory)]$Targets)
    return [ordered]@{
        Settings = [ordered]@{ Path=$Targets.Settings; Backup=(Join-Path $backupDir 'settings.json') }
        Actions = [ordered]@{ Path=$Targets.Actions; Backup=(Join-Path $backupDir 'actions.json') }
        Fragment = [ordered]@{ Path=$Targets.Fragment; Backup=(Join-Path $backupDir 'profiles.fragment.json') }
        ActionsFragment = [ordered]@{ Path=$Targets.ActionsFragment; Backup=(Join-Path $backupDir 'actions.fragment.json') }
        Starship = [ordered]@{ Path=$Targets.Starship; Backup=(Join-Path $backupDir 'starship.windows.toml') }
        PowerShellProfile = [ordered]@{ Path=$Targets.PowerShellProfile; Backup=(Join-Path $backupDir 'Microsoft.PowerShell_profile.ps1') }
    }
}

function Save-InitialState {
    param([Parameter(Mandatory)]$Targets)

    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $existing = if (Test-Path -LiteralPath $stateMeta) {
        Get-Content -Raw -LiteralPath $stateMeta -Encoding UTF8 | ConvertFrom-Json
    } else {
        $null
    }

    $files = [ordered]@{}
    if ($existing -and $existing.PSObject.Properties['Files']) {
        foreach ($prop in $existing.Files.PSObject.Properties) {
            $entry = $prop.Value
            $files[$prop.Name] = [ordered]@{
                Path = [string]$entry.Path
                Backup = [string]$entry.Backup
                Existed = [bool]$entry.Existed
            }
        }
    }

    $extended = $false
    foreach ($entry in (Get-StateTargetMap -Targets $Targets).GetEnumerator()) {
        if ($files.Contains($entry.Key)) { continue }
        $existed = Test-Path -LiteralPath $entry.Value.Path
        $entry.Value.Existed = $existed
        if ($existed) { Copy-Item -LiteralPath $entry.Value.Path -Destination $entry.Value.Backup -Force }
        $files[$entry.Key] = $entry.Value
        $extended = $true
    }

    $state = [ordered]@{
        RecordedAt = if ($existing -and $existing.PSObject.Properties['RecordedAt']) { [string]$existing.RecordedAt } else { (Get-Date).ToString('o') }
        LastExtendedAt = (Get-Date).ToString('o')
        Distribution = $Distribution
        Files = $files
    }
    $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $stateMeta -Encoding UTF8

    if ($existing -and $extended) {
        Write-Host "[OK] État initial Windows Terminal conservé et étendu pour le fragment d'actions: $stateMeta" -ForegroundColor Green
    } elseif (-not $existing) {
        Write-Host "[OK] État initial Windows Terminal sauvegardé: $stateMeta" -ForegroundColor Green
    }
}

function Set-TerminalSettings {
    param([Parameter(Mandatory)][string]$Path)

    $settings = Read-TerminalSettings -Path $Path
    $settings = Set-WpcTerminalSettingsContract -Settings $settings -ExpectedDefaultProfile $psProfileGuid -LegacyImportName $actionsFileName
    $text = ConvertTo-WpcTerminalSettingsText -Settings $settings

    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    [System.IO.File]::WriteAllText($Path, $text, [System.Text.UTF8Encoding]::new($false))
}

function Set-PowerShellProfile {
    param([Parameter(Mandatory)][string]$Path)
    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    $content = if (Test-Path -LiteralPath $Path) { Get-Content -Raw -LiteralPath $Path -Encoding UTF8 } else { '' }
    $pattern = '(?s)' + [regex]::Escape($markerBegin) + '.*?' + [regex]::Escape($markerEnd)
    $block = Get-ManagedPowerShellBlock
    if ([regex]::IsMatch($content, $pattern)) {
        $content = [regex]::Replace($content, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $block })
    } else {
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

New-Item -ItemType Directory -Force -Path (Split-Path $contract.Targets.ActionsFragment -Parent) | Out-Null
Copy-Item -LiteralPath $sourceActions -Destination $contract.Targets.ActionsFragment -Force

# Migration depuis l'ancien mécanisme settings.json -> import -> fichier voisin du settings.json.
# Les actions sont maintenant un fragment natif Windows Terminal (supporté depuis Terminal 1.21).
Remove-Item -LiteralPath $contract.Targets.Actions -Force -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Force -Path (Split-Path $contract.Targets.Starship -Parent) | Out-Null
Copy-Item -LiteralPath $sourceStarship -Destination $contract.Targets.Starship -Force

Set-PowerShellProfile -Path $contract.Targets.PowerShellProfile
Set-TerminalSettings -Path $contract.Targets.Settings

$verified = Get-Contract
[void](Show-Contract -Contract $verified -FailOnError)
Write-Host '[FAIT] Windows Terminal DevOps configuré et revalidé via fragments natifs (profils + actions).' -ForegroundColor Green
