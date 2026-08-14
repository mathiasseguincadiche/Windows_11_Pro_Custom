[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Verify', 'Rollback')]
    [string]$Mode = 'Audit'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$configPath = Join-Path $repoRoot 'config\windows\onedrive.json'
$stateDir = Join-Path $repoRoot 'state\onedrive'
$statePath = Join-Path $stateDir 'state.json'
$nativeProcessModule = Join-Path $repoRoot 'scripts\core\native-process.psm1'

if (-not (Test-Path $configPath)) { throw "Contrat OneDrive introuvable: $configPath" }
if (-not (Test-Path $nativeProcessModule)) { throw "Module d'exécution native introuvable: $nativeProcessModule" }
Import-Module $nativeProcessModule
$config = Get-Content -Raw $configPath | ConvertFrom-Json
if ([string]$config.desiredState -ne 'absent') { throw "Etat OneDrive non supporté: $($config.desiredState)" }

function Get-RegistrySnapshot {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Property)
    if (-not (Test-Path $Path)) { return [ordered]@{ Exists=$false; Value=$null } }
    $item = Get-ItemProperty -Path $Path -Name $Property -ErrorAction SilentlyContinue
    if ($null -eq $item) { return [ordered]@{ Exists=$false; Value=$null } }
    return [ordered]@{ Exists=$true; Value=$item.$Property }
}

function Set-RegistryDword {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Property,[Parameter(Mandatory)][int]$Value)
    New-Item -Force -Path $Path | Out-Null
    New-ItemProperty -Path $Path -Name $Property -PropertyType DWord -Value $Value -Force | Out-Null
}

function Restore-RegistrySnapshot {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Property,[Parameter(Mandatory)]$Snapshot)
    if ([bool]$Snapshot.Exists) {
        New-Item -Force -Path $Path | Out-Null
        New-ItemProperty -Path $Path -Name $Property -PropertyType DWord -Value ([int]$Snapshot.Value) -Force | Out-Null
    } elseif (Test-Path $Path) {
        Remove-ItemProperty -Path $Path -Name $Property -ErrorAction SilentlyContinue
    }
}

function Get-OneDriveExecutablePaths {
    $paths = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDrive.exe')
    )
    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) { $paths += (Join-Path $programFilesX86 'Microsoft OneDrive\OneDrive.exe') }
    return @($paths | Select-Object -Unique)
}

function Get-OneDriveWingetCommand {
    return Get-WpcNativeApplication -Name 'winget.exe'
}

function Test-OneDriveInstalled {
    if (Get-Process -Name OneDrive -ErrorAction SilentlyContinue) { return $true }
    foreach ($path in Get-OneDriveExecutablePaths) { if (Test-Path $path) { return $true } }
    $winget = Get-OneDriveWingetCommand
    if ($winget) {
        $result = Invoke-WpcNativeCapture -FilePath $winget.Source -ArgumentList @('list', '--id', [string]$config.wingetId, '--exact', '--accept-source-agreements', '--disable-interactivity') -SuppressErrorOutput
        if ($result.ExitCode -eq 0 -and $result.Text -match [regex]::Escape([string]$config.wingetId)) { return $true }
    }
    return $false
}

function Stop-OneDriveProcess {
    Get-Process -Name OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Remove-OneDriveClient {
    Stop-OneDriveProcess
    if (-not (Test-OneDriveInstalled)) { return }
    $winget = Get-OneDriveWingetCommand
    if ($winget) {
        Write-Host "[EN COURS] Désinstallation ciblée de $($config.wingetId) via WinGet..." -ForegroundColor Cyan
        & $winget.Source uninstall --id $config.wingetId --exact --source winget --silent --accept-source-agreements --disable-interactivity
        $wingetExitCode = $LASTEXITCODE
        $global:LASTEXITCODE = 0
        if ($wingetExitCode -ne 0) { Write-Warning 'WinGet nʼa pas confirmé la désinstallation; fallback Microsoft autorisé.' }
    }
    Stop-OneDriveProcess
    if (Test-OneDriveInstalled) {
        foreach ($setup in @((Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe'),(Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe'))) {
            if (Test-Path $setup) {
                Write-Host "[EN COURS] Fallback Microsoft: $setup /uninstall" -ForegroundColor Cyan
                Start-Process -FilePath $setup -ArgumentList '/uninstall' -Wait | Out-Null
                Stop-OneDriveProcess
                if (-not (Test-OneDriveInstalled)) { break }
            }
        }
    }
    if (Test-OneDriveInstalled) { throw 'OneDrive reste installé après les méthodes de désinstallation ciblées.' }
}

function Install-OneDriveClient {
    if (Test-OneDriveInstalled) { return }
    $winget = Get-OneDriveWingetCommand
    if (-not $winget) { throw 'Rollback OneDrive impossible: WinGet est introuvable.' }
    & $winget.Source install --id $config.wingetId --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    $wingetExitCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($wingetExitCode -ne 0 -or -not (Test-OneDriveInstalled)) { throw 'Rollback OneDrive impossible: la réinstallation nʼa pas été confirmée.' }
}

$syncPolicy = $config.disableFileSyncPolicy
$networkPolicy = $config.preventNetworkTrafficPolicy

function Get-OneDriveState {
    $installed = Test-OneDriveInstalled
    $running = $null -ne (Get-Process -Name OneDrive -ErrorAction SilentlyContinue)
    $sync = Get-RegistrySnapshot -Path $syncPolicy.path -Property $syncPolicy.property
    $network = Get-RegistrySnapshot -Path $networkPolicy.path -Property $networkPolicy.property
    $desired = (-not $installed) -and (-not $running) -and $sync.Exists -and ([int]$sync.Value -eq [int]$syncPolicy.value) -and $network.Exists -and ([int]$network.Value -eq [int]$networkPolicy.value)
    return [pscustomobject]@{ Installed=$installed; Running=$running; Sync=$sync; Network=$network; Desired=$desired }
}

$current = Get-OneDriveState

if ($Mode -eq 'Audit') {
    Write-Host "OneDrive installé: $($current.Installed)"
    Write-Host "OneDrive actif: $($current.Running)"
    Write-Host "$($syncPolicy.property): $(if ($current.Sync.Exists) { $current.Sync.Value } else { '<absent>' })"
    Write-Host "$($networkPolicy.property): $(if ($current.Network.Exists) { $current.Network.Value } else { '<absent>' })"
    if ($current.Desired) { Write-Host '[DÉJÀ OK] Contrat OneDrive déjà satisfait.' -ForegroundColor Green }
    else { Write-Host '[À FAIRE] Contrat OneDrive non satisfait; Apply corrigera uniquement les écarts.' -ForegroundColor Yellow }
    return
}

if ($Mode -eq 'Verify') {
    if ($current.Desired) {
        Write-Host '[OK] Contrat OneDrive: absent et bloqué.' -ForegroundColor Green
        return
    }
    $failures = [System.Collections.Generic.List[string]]::new()
    if ($current.Installed) { $failures.Add('client installé') }
    if ($current.Running) { $failures.Add('processus actif') }
    if (-not $current.Sync.Exists -or [int]$current.Sync.Value -ne [int]$syncPolicy.value) { $failures.Add("stratégie $($syncPolicy.property)") }
    if (-not $current.Network.Exists -or [int]$current.Network.Value -ne [int]$networkPolicy.value) { $failures.Add("stratégie $($networkPolicy.property)") }
    throw "Contrat OneDrive non conforme: $($failures -join ', ')"
}

if ($Mode -eq 'Apply') {
    if ($current.Desired) {
        Write-Host '[DÉJÀ OK] OneDrive est déjà absent et les stratégies sont conformes; aucune écriture/désinstallation.' -ForegroundColor Green
        return
    }
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    if (-not (Test-Path $statePath)) {
        [ordered]@{
            InstalledBefore = $current.Installed
            DisableFileSyncPolicyBefore = $current.Sync
            PreventNetworkTrafficPolicyBefore = $current.Network
            RecordedAt = (Get-Date).ToString('o')
        } | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 $statePath
        Write-Host "[OK] État initial OneDrive sauvegardé: $statePath"
    }

    $changes = [System.Collections.Generic.List[string]]::new()
    if (-not $current.Sync.Exists -or [int]$current.Sync.Value -ne [int]$syncPolicy.value) {
        Set-RegistryDword -Path $syncPolicy.path -Property $syncPolicy.property -Value ([int]$syncPolicy.value)
        $changes.Add($syncPolicy.property)
    } else { Write-Host "[DÉJÀ OK] $($syncPolicy.property)" -ForegroundColor Green }

    if (-not $current.Network.Exists -or [int]$current.Network.Value -ne [int]$networkPolicy.value) {
        Set-RegistryDword -Path $networkPolicy.path -Property $networkPolicy.property -Value ([int]$networkPolicy.value)
        $changes.Add($networkPolicy.property)
    } else { Write-Host "[DÉJÀ OK] $($networkPolicy.property)" -ForegroundColor Green }

    if ($current.Installed -or $current.Running) {
        Remove-OneDriveClient
        $changes.Add('client OneDrive supprimé')
    } else { Write-Host '[DÉJÀ OK] Client OneDrive déjà absent.' -ForegroundColor Green }

    $after = Get-OneDriveState
    if (-not $after.Desired) { throw 'État OneDrive toujours non conforme après Apply.' }
    Write-Host "[FAIT] Baseline sans OneDrive appliquée et revalidée: $($changes -join ', ')." -ForegroundColor Green
    return
}

if (-not (Test-Path $statePath)) {
    Write-Host '[DÉJÀ OK] Aucun état initial OneDrive enregistré; rollback inutile.' -ForegroundColor Green
    return
}
$state = Get-Content -Raw $statePath | ConvertFrom-Json
Restore-RegistrySnapshot -Path $syncPolicy.path -Property $syncPolicy.property -Snapshot $state.DisableFileSyncPolicyBefore
Restore-RegistrySnapshot -Path $networkPolicy.path -Property $networkPolicy.property -Snapshot $state.PreventNetworkTrafficPolicyBefore
if ([bool]$state.InstalledBefore) { Install-OneDriveClient } else { Remove-OneDriveClient }
Write-Host '[FAIT] État OneDrive antérieur restauré.' -ForegroundColor Green
