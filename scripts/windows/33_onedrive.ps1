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

if (-not (Test-Path $configPath)) {
    throw "Contrat OneDrive introuvable: $configPath"
}

$config = Get-Content -Raw $configPath | ConvertFrom-Json
if ([string]$config.desiredState -ne 'absent') {
    throw "Etat OneDrive non supporte: $($config.desiredState)"
}

function Get-RegistrySnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Property
    )

    if (-not (Test-Path $Path)) {
        return [ordered]@{ Exists = $false; Value = $null }
    }

    $item = Get-ItemProperty -Path $Path -Name $Property -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return [ordered]@{ Exists = $false; Value = $null }
    }

    return [ordered]@{ Exists = $true; Value = $item.$Property }
}

function Set-RegistryDword {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Property,
        [Parameter(Mandatory = $true)][int]$Value
    )

    New-Item -Force -Path $Path | Out-Null
    New-ItemProperty -Path $Path -Name $Property -PropertyType DWord -Value $Value -Force | Out-Null
}

function Restore-RegistrySnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Property,
        [Parameter(Mandatory = $true)]$Snapshot
    )

    if ([bool]$Snapshot.Exists) {
        New-Item -Force -Path $Path | Out-Null
        New-ItemProperty -Path $Path -Name $Property -PropertyType DWord -Value ([int]$Snapshot.Value) -Force | Out-Null
        return
    }

    if (Test-Path $Path) {
        Remove-ItemProperty -Path $Path -Name $Property -ErrorAction SilentlyContinue
    }
}

function Get-OneDriveExecutablePaths {
    $paths = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDrive.exe')
    )

    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
        $paths += (Join-Path $programFilesX86 'Microsoft OneDrive\OneDrive.exe')
    }

    return @($paths | Select-Object -Unique)
}

function Test-OneDriveInstalled {
    if (Get-Process -Name OneDrive -ErrorAction SilentlyContinue) {
        return $true
    }

    foreach ($path in Get-OneDriveExecutablePaths) {
        if (Test-Path $path) {
            return $true
        }
    }

    if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
        $output = (& winget.exe list --id $config.wingetId --exact --accept-source-agreements --disable-interactivity 2>$null | Out-String)
        if ($LASTEXITCODE -eq 0 -and $output -match [regex]::Escape([string]$config.wingetId)) {
            return $true
        }
    }

    return $false
}

function Stop-OneDriveProcess {
    Get-Process -Name OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Remove-OneDriveClient {
    Stop-OneDriveProcess
    if (-not (Test-OneDriveInstalled)) {
        return
    }

    if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
        Write-Host "[INFO] Desinstallation ciblee de $($config.wingetId) via WinGet..."
        & winget.exe uninstall --id $config.wingetId --exact --source winget --silent --accept-source-agreements --disable-interactivity
    }

    Stop-OneDriveProcess
    if (Test-OneDriveInstalled) {
        foreach ($setup in @(
            (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe'),
            (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe')
        )) {
            if (Test-Path $setup) {
                Write-Host "[INFO] Fallback Microsoft: $setup /uninstall"
                Start-Process -FilePath $setup -ArgumentList '/uninstall' -Wait | Out-Null
                Stop-OneDriveProcess
                if (-not (Test-OneDriveInstalled)) { break }
            }
        }
    }

    if (Test-OneDriveInstalled) {
        throw 'OneDrive reste installe apres les methodes de desinstallation ciblees.'
    }
}

function Install-OneDriveClient {
    if (Test-OneDriveInstalled) {
        return
    }

    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw 'Rollback OneDrive impossible: WinGet est introuvable.'
    }

    & winget.exe install --id $config.wingetId --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0 -or -not (Test-OneDriveInstalled)) {
        throw "Rollback OneDrive impossible: la reinstallation n'a pas ete confirmee."
    }
}

$syncPolicy = $config.disableFileSyncPolicy
$networkPolicy = $config.preventNetworkTrafficPolicy
$installed = Test-OneDriveInstalled
$syncBefore = Get-RegistrySnapshot -Path $syncPolicy.path -Property $syncPolicy.property
$networkBefore = Get-RegistrySnapshot -Path $networkPolicy.path -Property $networkPolicy.property
$running = $null -ne (Get-Process -Name OneDrive -ErrorAction SilentlyContinue)

if ($Mode -eq 'Audit') {
    Write-Host "OneDrive installe: $installed"
    Write-Host "OneDrive actif: $running"
    Write-Host "$($syncPolicy.property): $(if ($syncBefore.Exists) { $syncBefore.Value } else { '<absent>' })"
    Write-Host "$($networkPolicy.property): $(if ($networkBefore.Exists) { $networkBefore.Value } else { '<absent>' })"
    return
}

if ($Mode -eq 'Apply') {
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    if (-not (Test-Path $statePath)) {
        [ordered]@{
            InstalledBefore = $installed
            DisableFileSyncPolicyBefore = $syncBefore
            PreventNetworkTrafficPolicyBefore = $networkBefore
            RecordedAt = (Get-Date).ToString('o')
        } | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 $statePath
    }

    Set-RegistryDword -Path $syncPolicy.path -Property $syncPolicy.property -Value ([int]$syncPolicy.value)
    Set-RegistryDword -Path $networkPolicy.path -Property $networkPolicy.property -Value ([int]$networkPolicy.value)
    Remove-OneDriveClient
    & $PSCommandPath -Mode Verify
    Write-Host '[OK] Baseline Windows sans OneDrive appliquee.' -ForegroundColor Green
    return
}

if ($Mode -eq 'Verify') {
    $syncNow = Get-RegistrySnapshot -Path $syncPolicy.path -Property $syncPolicy.property
    $networkNow = Get-RegistrySnapshot -Path $networkPolicy.path -Property $networkPolicy.property

    if (Test-OneDriveInstalled) { throw 'OneDrive est installe alors que le contrat exige son absence.' }
    if (Get-Process -Name OneDrive -ErrorAction SilentlyContinue) { throw 'OneDrive.exe est actif.' }
    if (-not $syncNow.Exists -or [int]$syncNow.Value -ne [int]$syncPolicy.value) {
        throw "Strategie OneDrive invalide: $($syncPolicy.property)."
    }
    if (-not $networkNow.Exists -or [int]$networkNow.Value -ne [int]$networkPolicy.value) {
        throw "Strategie OneDrive invalide: $($networkPolicy.property)."
    }

    Write-Host '[OK] Contrat OneDrive: absent et bloque.' -ForegroundColor Green
    return
}

if (-not (Test-Path $statePath)) {
    Write-Warning 'Etat initial OneDrive absent: aucun rollback effectue.'
    return
}

$state = Get-Content -Raw $statePath | ConvertFrom-Json
Restore-RegistrySnapshot -Path $syncPolicy.path -Property $syncPolicy.property -Snapshot $state.DisableFileSyncPolicyBefore
Restore-RegistrySnapshot -Path $networkPolicy.path -Property $networkPolicy.property -Snapshot $state.PreventNetworkTrafficPolicyBefore

if ([bool]$state.InstalledBefore) {
    Install-OneDriveClient
} else {
    Remove-OneDriveClient
}

Write-Host '[OK] Etat OneDrive anterieur restaure.' -ForegroundColor Green
