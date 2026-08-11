[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Verify', 'Rollback')]
    [string]$Mode = 'Audit'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$stateDir = Join-Path $repoRoot 'state'
$statePath = Join-Path $stateDir 'windows-tweaks-backup.json'

$tweaks = @(
    @{ Name = 'Show file extensions'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Property = 'HideFileExt'; Value = 0; Type = 'DWord' },
    @{ Name = 'Show hidden files'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Property = 'Hidden'; Value = 1; Type = 'DWord' },
    @{ Name = 'Disable Explorer sync-provider ads'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Property = 'ShowSyncProviderNotifications'; Value = 0; Type = 'DWord' },
    @{ Name = 'Hide taskbar widgets'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Property = 'TaskbarDa'; Value = 0; Type = 'DWord' },
    @{ Name = 'Disable advertising identifier'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Property = 'Enabled'; Value = 0; Type = 'DWord' },
    @{ Name = 'Disable tailored experiences'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'; Property = 'TailoredExperiencesWithDiagnosticDataEnabled'; Value = 0; Type = 'DWord' },
    @{ Name = 'Disable suggested app silent install'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Property = 'SilentInstalledAppsEnabled'; Value = 0; Type = 'DWord' },
    @{ Name = 'Disable Windows tips'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Property = 'SoftLandingEnabled'; Value = 0; Type = 'DWord' },
    @{ Name = 'Disable Start suggestions'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Property = 'SystemPaneSuggestionsEnabled'; Value = 0; Type = 'DWord' },
    @{ Name = 'Disable Windows consumer features'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Property = 'DisableWindowsConsumerFeatures'; Value = 1; Type = 'DWord' },
    @{ Name = 'Keep diagnostic data at required level'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Property = 'AllowTelemetry'; Value = 1; Type = 'DWord' }
)

function Get-RegistryState {
    param([hashtable]$Tweak)

    if (-not (Test-Path $Tweak.Path)) {
        return [pscustomobject]@{ Exists = $false; Value = $null; Kind = $null }
    }

    $item = Get-Item -LiteralPath $Tweak.Path
    try {
        $value = $item.GetValue($Tweak.Property, $null, 'DoNotExpandEnvironmentNames')
        if ($null -eq $value) {
            return [pscustomobject]@{ Exists = $false; Value = $null; Kind = $null }
        }
        $kind = $item.GetValueKind($Tweak.Property).ToString()
        [pscustomobject]@{ Exists = $true; Value = $value; Kind = $kind }
    } catch {
        [pscustomobject]@{ Exists = $false; Value = $null; Kind = $null }
    }
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Ce mode doit être exécuté dans PowerShell administrateur.'
    }
}

function Show-Status {
    foreach ($tweak in $tweaks) {
        $current = Get-RegistryState -Tweak $tweak
        $ok = $current.Exists -and ([int64]$current.Value -eq [int64]$tweak.Value)
        $label = if ($ok) { 'OK' } else { 'DIFF' }
        Write-Host ("[{0}] {1} -> actuel={2} cible={3}" -f $label, $tweak.Name, $current.Value, $tweak.Value)
    }
}

switch ($Mode) {
    'Audit' {
        Show-Status
    }
    'Apply' {
        Assert-Administrator
        New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

        if (-not (Test-Path $statePath)) {
            $backup = foreach ($tweak in $tweaks) {
                $state = Get-RegistryState -Tweak $tweak
                [pscustomobject]@{
                    Path = $tweak.Path
                    Property = $tweak.Property
                    Exists = $state.Exists
                    Value = $state.Value
                    Kind = $state.Kind
                }
            }
            $backup | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 $statePath
            Write-Host "[OK] État initial sauvegardé: $statePath"
        } else {
            Write-Host '[INFO] Sauvegarde initiale déjà présente, elle n’est pas écrasée.'
        }

        foreach ($tweak in $tweaks) {
            New-Item -Force -Path $tweak.Path | Out-Null
            New-ItemProperty -Path $tweak.Path -Name $tweak.Property -PropertyType $tweak.Type -Value $tweak.Value -Force | Out-Null
        }
        Show-Status
    }
    'Verify' {
        $failed = 0
        foreach ($tweak in $tweaks) {
            $current = Get-RegistryState -Tweak $tweak
            if (-not ($current.Exists -and ([int64]$current.Value -eq [int64]$tweak.Value))) {
                Write-Error "Échec: $($tweak.Name)"
                $failed++
            } else {
                Write-Host "[OK] $($tweak.Name)"
            }
        }
        if ($failed -gt 0) { exit 1 }
    }
    'Rollback' {
        Assert-Administrator
        if (-not (Test-Path $statePath)) { throw "Sauvegarde absente: $statePath" }
        $backup = Get-Content -Raw $statePath | ConvertFrom-Json
        foreach ($entry in $backup) {
            if ($entry.Exists) {
                New-Item -Force -Path $entry.Path | Out-Null
                $kind = if ($entry.Kind) { $entry.Kind } else { 'DWord' }
                New-ItemProperty -Path $entry.Path -Name $entry.Property -PropertyType $kind -Value $entry.Value -Force | Out-Null
            } elseif (Test-Path $entry.Path) {
                Remove-ItemProperty -Path $entry.Path -Name $entry.Property -ErrorAction SilentlyContinue
            }
        }
        Write-Host '[OK] Réglages Windows restaurés depuis la sauvegarde initiale.' -ForegroundColor Green
    }
}
