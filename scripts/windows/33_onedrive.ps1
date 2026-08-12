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
    throw "État OneDrive non supporté: $($config.desiredState)"
}

function Get-RegistryValueState {
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

function Set-DwordPolicy {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Property,
        [Parameter(Mandatory = $true)][int]$Value
    )

    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    New-ItemProperty -Path $Path -Name $Property -PropertyType DWord -Value $Value -Force | Out-Null
}

function Restore-RegistryValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Property,
        [Parameter(Mandatory = $true)]$State
    )

    if ([bool]$State.Exists) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
        New-ItemProperty -Path $Path -Name $Property -PropertyType DWord -Value ([int]$State.Value) -Force | Out-Null
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

    $appx = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match 'OneDrive'
    })
    if ($appx.Count -gt 0) {
        return $true
    }

    if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
        $output = (& winget.exe list --id $config.wingetId --exact --accept-source-agreements --disable-interactivity 2>$null | Out-String)
        if ($LASTEXITCODE -eq 0 -and $output -match [regex]::Escape([string]$config.wingetId)) {
            return $true
        }
    }

    return $false
}

function Stop-OneDriveProcesses {
    Get-Process -Name OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Invoke-OneDriveSetupUninstallFallback {
    $candidates = @(
        (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe'),
        (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe')
    )

    foreach ($candidate in $candidates) {
        if (-not (Test-Path $candidate)) {
            continue
        }

        Write-Host "[INFO] Fallback OneDriveSetup.exe: $candidate"
        $process = Start-Process -FilePath $candidate -ArgumentList '/uninstall' -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            return
        }
    }
}

function Ensure-OneDriveAbsent {
    Stop-OneDriveProcesses

    if (-not (Test-OneDriveInstalled)) {
        Write-Host '[OK] OneDrive est déjà absent.' -ForegroundColor Green
        return
    }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($null -ne $winget) {
        Write-Host "[INFO] Désinstallation ciblée de $($config.wingetId) via WinGet..."
        & winget.exe uninstall --id $config.wingetId --exact --source winget --silent --accept-source-agreements --disable-interactivity
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "WinGet n'a pas confirmé la désinstallation de $($config.wingetId). Tentative du fallback Microsoft."
        }
    }

    Stop-OneDriveProcesses
    if (Test-OneDriveInstalled) {
        Invoke-OneDriveSetupUninstallFallback
    }

    Stop-OneDriveProcesses
    if (Test-OneDriveInstalled) {
        throw 'OneDrive reste installé après les méthodes de désinstallation ciblées.'
    }

    Write-Host '[OK] OneDrive est absent.' -ForegroundColor Green
}

function Ensure-OneDrivePresent {
    if (Test-OneDriveInstalled) {
        return
    }

    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw 'Rollback OneDrive impossible: WinGet est introuvable.'
    }

    Write-Host "[INFO] Restauration de OneDrive via WinGet ($($config.wingetId))..."
    & winget.exe install --id $config.wingetId --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0 -or -not (Test-OneDriveInstalled)) {
        throw 'Rollback OneDrive impossible: la réinstallation n’a pas été confirmée.'
    }
}

$syncPolicy = $config.disableFileSyncPolicy
$networkPolicy = $config.preventNetworkTrafficPolicy
$installed = Test-OneDriveInstalled
$syncState = Get-RegistryValueState -Path $syncPolicy.path -Property $syncPolicy.property
$networkState = Get-RegistryValueState -Path $networkPolicy.path -Property $networkPolicy.property
$running = $null -ne (Get-Process -Name OneDrive -ErrorAction SilentlyContinue)

if ($Mode -eq 'Audit') {
    Write-Host "OneDrive installé: $installed"
    Write-Host "OneDrive en cours d'exécution: $running"
    Write-Host "$($syncPolicy.property): $(if ($syncState.Exists) { $syncState.Value } else { '<absent>' })"
    Write-Host "$($networkPolicy.property): $(if ($networkState.Exists) { $networkState.Value } else { '<absent>' })"
    return
}

if ($Mode -eq 'Apply') {
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    if (-not (Test-Path $statePath)) {
        [ordered]@{
            InstalledBefore = $installed
            DisableFileSyncPolicyBefore = $syncState
            PreventNetworkTrafficPolicyBefore = $networkState
            RecordedAt = (Get-Date).ToString('o')
        } | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 $statePath
    }

    Set-DwordPolicy -Path $syncPolicy.path -Property $syncPolicy.property -Value ([int]$syncPolicy.value)
    Set-DwordPolicy -Path $networkPolicy.path -Property $networkPolicy.property -Value ([int]$networkPolicy.value)
    Ensure-OneDriveAbsent

    & $PSCommandPath -Mode Verify
    Write-Host '[OK] Baseline Windows sans OneDrive appliquée.' -ForegroundColor Green
    return
}

if ($Mode -eq 'Verify') {
    $installedNow = Test-OneDriveInstalled
    $runningNow = $null -ne (Get-Process -Name OneDrive -ErrorAction SilentlyContinue)
    $syncNow = Get-RegistryValueState -Path $syncPolicy.path -Property $syncPolicy.property
    $networkNow = Get-RegistryValueState -Path $networkPolicy.path -Property $networkPolicy.property

    if ($installedNow) { throw 'OneDrive est installé alors que le contrat exige son absence.' }
    if ($runningNow) { throw 'OneDrive.exe est actif alors que le contrat exige son absence.' }
    if (-not $syncNow.Exists -or [int]$syncNow.Value -ne [int]$syncPolicy.value) {
        throw "Stratégie OneDrive invalide: $($syncPolicy.property)."
    }
    if (-not $networkNow.Exists -or [int]$networkNow.Value -ne [int]$networkPolicy.value) {
        throw "Stratégie OneDrive invalide: $($networkPolicy.property)."
    }

    Write-Host '[OK] Contrat OneDrive: absent et bloqué.' -ForegroundColor Green
    return
}

if (-not (Test-Path $statePath)) {
    Write-Warning 'État initial OneDrive absent : aucun rollback effectué.'
    return
}

$state = Get-Content -Raw $statePath | ConvertFrom-Json
Restore-RegistryValue -Path $syncPolicy.path -Property $syncPolicy.property -State $state.DisableFileSyncPolicyBefore
Restore-RegistryValue -Path $networkPolicy.path -Property $networkPolicy.property -State $state.PreventNetworkTrafficPolicyBefore

if ([bool]$state.InstalledBefore) {
    Ensure-OneDrivePresent
} else {
    Ensure-OneDriveAbsent
}

Write-Host '[OK] État OneDrive antérieur restauré.' -ForegroundColor Green
