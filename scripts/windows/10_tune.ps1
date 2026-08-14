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
    @{ Name='Show file extensions'; Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Property='HideFileExt'; Value=0; Type='DWord' },
    @{ Name='Show hidden files'; Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Property='Hidden'; Value=1; Type='DWord' },
    @{ Name='Disable Explorer sync-provider ads'; Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Property='ShowSyncProviderNotifications'; Value=0; Type='DWord' },
    @{ Name='Hide taskbar widgets'; Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Property='TaskbarDa'; Value=0; Type='DWord' },
    @{ Name='Disable advertising identifier'; Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Property='Enabled'; Value=0; Type='DWord' },
    @{ Name='Disable tailored experiences'; Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'; Property='TailoredExperiencesWithDiagnosticDataEnabled'; Value=0; Type='DWord' },
    @{ Name='Disable suggested app silent install'; Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Property='SilentInstalledAppsEnabled'; Value=0; Type='DWord' },
    @{ Name='Disable Windows tips'; Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Property='SoftLandingEnabled'; Value=0; Type='DWord' },
    @{ Name='Disable Start suggestions'; Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Property='SystemPaneSuggestionsEnabled'; Value=0; Type='DWord' },
    @{ Name='Disable Windows consumer features'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Property='DisableWindowsConsumerFeatures'; Value=1; Type='DWord' },
    @{ Name='Keep diagnostic data at required level'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Property='AllowTelemetry'; Value=1; Type='DWord' }
)

function Get-RegistryState {
    param([hashtable]$Tweak)
    if (-not (Test-Path -LiteralPath $Tweak.Path)) { return [pscustomobject]@{ Exists=$false; Value=$null; Kind=$null } }
    $item = Get-Item -LiteralPath $Tweak.Path
    try {
        $value = $item.GetValue($Tweak.Property, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($null -eq $value) { return [pscustomobject]@{ Exists=$false; Value=$null; Kind=$null } }
        return [pscustomobject]@{ Exists=$true; Value=$value; Kind=$item.GetValueKind($Tweak.Property).ToString() }
    } catch { return [pscustomobject]@{ Exists=$false; Value=$null; Kind=$null } }
}

function Test-TweakMatch {
    param([hashtable]$Tweak)
    $current = Get-RegistryState -Tweak $Tweak
    return ($current.Exists -and ([int64]$current.Value -eq [int64]$Tweak.Value))
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Ce mode doit être exécuté dans PowerShell administrateur.' }
}

function Set-ManagedRegistryValue {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Property,
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)]$Value
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        try {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        } catch {
            throw "Création de clé registre impossible pour '$Name' [$Path]: $($_.Exception.Message)"
        }
    }

    try {
        New-ItemProperty -LiteralPath $Path -Name $Property -PropertyType $Type -Value $Value -Force -ErrorAction Stop | Out-Null
    } catch {
        throw "Écriture registre impossible pour '$Name' [$Path\\$Property]: $($_.Exception.Message)"
    }
}

function Show-Status {
    foreach ($tweak in $tweaks) {
        $current = Get-RegistryState -Tweak $tweak
        $ok = $current.Exists -and ([int64]$current.Value -eq [int64]$tweak.Value)
        $label = if ($ok) { 'DÉJÀ OK' } else { 'À FAIRE' }
        Write-Host ("[{0}] {1} | actuel={2} cible={3}" -f $label, $tweak.Name, $(if ($current.Exists) { $current.Value } else { '<absent>' }), $tweak.Value) -ForegroundColor $(if ($ok) { 'Green' } else { 'Yellow' })
    }
}

switch ($Mode) {
    'Audit' {
        Show-Status
    }
    'Apply' {
        $pending = @($tweaks | Where-Object { -not (Test-TweakMatch -Tweak $_) })
        if ($pending.Count -eq 0) {
            Write-Host '[DÉJÀ OK] Réglages Windows de base déjà conformes; aucune écriture registre.' -ForegroundColor Green
            return
        }

        Assert-Administrator
        New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
        if (-not (Test-Path $statePath)) {
            $backup = foreach ($tweak in $tweaks) {
                $state = Get-RegistryState -Tweak $tweak
                [pscustomobject]@{ Path=$tweak.Path; Property=$tweak.Property; Exists=$state.Exists; Value=$state.Value; Kind=$state.Kind }
            }
            $backup | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 $statePath
            Write-Host "[OK] État initial sauvegardé: $statePath"
        } else {
            Write-Host '[DÉJÀ OK] Sauvegarde initiale déjà présente; elle reste inchangée.' -ForegroundColor Green
        }

        foreach ($tweak in $pending) {
            Write-Host "[EN COURS] $($tweak.Name)" -ForegroundColor Cyan
            Set-ManagedRegistryValue -Name $tweak.Name -Path $tweak.Path -Property $tweak.Property -Type $tweak.Type -Value $tweak.Value
            if (-not (Test-TweakMatch -Tweak $tweak)) { throw "Revalidation échouée après écriture: $($tweak.Name)" }
            Write-Host "[FAIT] $($tweak.Name)" -ForegroundColor Green
        }
        Write-Host "[FAIT] Réglages Windows: $($pending.Count) différence(s) corrigée(s), aucune écriture inutile sur les éléments déjà conformes." -ForegroundColor Green
    }
    'Verify' {
        $failed = [System.Collections.Generic.List[string]]::new()
        foreach ($tweak in $tweaks) {
            if (Test-TweakMatch -Tweak $tweak) {
                Write-Host "[OK] $($tweak.Name)" -ForegroundColor Green
            } else {
                Write-Host "[KO] $($tweak.Name)" -ForegroundColor Red
                $failed.Add($tweak.Name)
            }
        }
        if ($failed.Count -gt 0) { throw "Réglages Windows non conformes: $($failed -join ', ')" }
        Write-Host '[OK] Réglages Windows de base vérifiés.' -ForegroundColor Green
    }
    'Rollback' {
        Assert-Administrator
        if (-not (Test-Path $statePath)) {
            Write-Host '[DÉJÀ OK] Aucune sauvegarde initiale: aucun réglage géré par le dépôt à restaurer.' -ForegroundColor Green
            return
        }
        $backup = Get-Content -Raw $statePath | ConvertFrom-Json
        foreach ($entry in $backup) {
            if ($entry.Exists) {
                $kind = if ($entry.Kind) { $entry.Kind } else { 'DWord' }
                Set-ManagedRegistryValue -Name "Rollback $($entry.Property)" -Path $entry.Path -Property $entry.Property -Type $kind -Value $entry.Value
            } elseif (Test-Path -LiteralPath $entry.Path) {
                Remove-ItemProperty -LiteralPath $entry.Path -Name $entry.Property -ErrorAction SilentlyContinue
            }
        }
        Write-Host '[FAIT] Réglages Windows restaurés depuis la sauvegarde initiale.' -ForegroundColor Green
    }
}
