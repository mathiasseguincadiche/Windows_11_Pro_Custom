[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Verify', 'Rollback')]
    [string]$Mode = 'Audit',
    [ValidateSet('standard', 'privacy', 'gaming', 'optional')]
    [string]$Profile = 'standard'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$profilePath = Join-Path $repoRoot "config\windows\v4\$Profile.json"
$stateDir = Join-Path $repoRoot 'state\windows-v4'
$statePath = Join-Path $stateDir "$Profile.before.json"
if (-not (Test-Path $profilePath)) { throw "V4 profile not found: $profilePath" }
$config = Get-Content -Raw $profilePath | ConvertFrom-Json

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Apply and Rollback require an elevated PowerShell session.' }
}

function Get-RegistryState {
    param([Parameter(Mandatory)]$Entry)
    if (-not (Test-Path $Entry.path)) { return [pscustomobject]@{ Exists=$false; Value=$null; Kind=$null } }
    $item = Get-Item -LiteralPath $Entry.path
    try {
        $value = $item.GetValue($Entry.property, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($null -eq $value) { return [pscustomobject]@{ Exists=$false; Value=$null; Kind=$null } }
        return [pscustomobject]@{ Exists=$true; Value=$value; Kind=$item.GetValueKind($Entry.property).ToString() }
    } catch { return [pscustomobject]@{ Exists=$false; Value=$null; Kind=$null } }
}

function Test-RegistryMatch {
    param([Parameter(Mandatory)]$Entry,[Parameter(Mandatory)]$State)
    if (-not $State.Exists) { return $false }
    if ($Entry.type -eq 'String') { return ([string]$State.Value -ceq [string]$Entry.value) }
    return ([int64]$State.Value -eq [int64]$Entry.value)
}

function Get-ServiceState {
    param([Parameter(Mandatory)]$Entry)
    $service = Get-CimInstance Win32_Service | Where-Object Name -EQ $Entry.name | Select-Object -First 1
    if (-not $service) { return [pscustomobject]@{ Exists=$false; StartMode=$null; State=$null } }
    return [pscustomobject]@{ Exists=$true; StartMode=[string]$service.StartMode; State=[string]$service.State }
}

function Convert-StartupTypeToCimMode {
    param([string]$StartupType)
    switch ($StartupType) { 'Automatic' { 'Auto' } 'Manual' { 'Manual' } 'Disabled' { 'Disabled' } default { $StartupType } }
}

function Get-PendingChanges {
    $registry = @()
    foreach ($entry in @($config.registry)) {
        $current = Get-RegistryState -Entry $entry
        if (-not (Test-RegistryMatch -Entry $entry -State $current)) { $registry += $entry }
    }
    $services = @()
    foreach ($entry in @($config.services)) {
        $current = Get-ServiceState -Entry $entry
        $target = Convert-StartupTypeToCimMode -StartupType $entry.startupType
        if (-not ($current.Exists -and $current.StartMode -eq $target)) { $services += $entry }
    }
    return [pscustomobject]@{ Registry=@($registry); Services=@($services) }
}

function Show-ProfileStatus {
    Write-Host "V4 profile: $Profile" -ForegroundColor Cyan
    Write-Host $config.description
    foreach ($entry in @($config.registry)) {
        $current = Get-RegistryState -Entry $entry
        $ok = Test-RegistryMatch -Entry $entry -State $current
        Write-Host ("[{0}] REG {1} | actuel={2} cible={3}" -f $(if ($ok) { 'DÉJÀ OK' } else { 'À FAIRE' }), $entry.name, $(if ($current.Exists) { $current.Value } else { '<absent>' }), $entry.value) -ForegroundColor $(if ($ok) { 'Green' } else { 'Yellow' })
    }
    foreach ($entry in @($config.services)) {
        $current = Get-ServiceState -Entry $entry
        $target = Convert-StartupTypeToCimMode -StartupType $entry.startupType
        $ok = $current.Exists -and ($current.StartMode -eq $target)
        Write-Host ("[{0}] SVC {1} | startup={2} cible={3} runtime={4}" -f $(if ($ok) { 'DÉJÀ OK' } else { 'À FAIRE' }), $entry.name, $current.StartMode, $target, $current.State) -ForegroundColor $(if ($ok) { 'Green' } else { 'Yellow' })
    }
}

switch ($Mode) {
    'Audit' { Show-ProfileStatus }
    'Apply' {
        $pending = Get-PendingChanges
        if ($pending.Registry.Count -eq 0 -and $pending.Services.Count -eq 0) {
            Write-Host "[DÉJÀ OK] Profil V4 '$Profile' déjà conforme; aucune écriture registre/service." -ForegroundColor Green
            return
        }
        Assert-Administrator
        New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
        if (-not (Test-Path $statePath)) {
            $registryBackup = @(
                foreach ($entry in @($config.registry)) {
                    $state = Get-RegistryState -Entry $entry
                    [pscustomobject]@{ Name=$entry.name; Path=$entry.path; Property=$entry.property; Exists=$state.Exists; Value=$state.Value; Kind=$state.Kind }
                }
            )
            $serviceBackup = @(
                foreach ($entry in @($config.services)) {
                    $state = Get-ServiceState -Entry $entry
                    [pscustomobject]@{ Name=$entry.name; Exists=$state.Exists; StartMode=$state.StartMode }
                }
            )
            [ordered]@{ Profile=$Profile; CapturedAt=(Get-Date).ToString('o'); Registry=$registryBackup; Services=$serviceBackup } | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 $statePath
            Write-Host "[OK] État initial V4 sauvegardé: $statePath" -ForegroundColor Green
        } else {
            Write-Host "[DÉJÀ OK] Sauvegarde initiale V4 préservée: $statePath" -ForegroundColor Green
        }

        foreach ($entry in @($pending.Registry)) {
            Write-Host "[EN COURS] REG $($entry.name)" -ForegroundColor Cyan
            New-Item -Force -Path $entry.path | Out-Null
            New-ItemProperty -Path $entry.path -Name $entry.property -PropertyType $entry.type -Value $entry.value -Force | Out-Null
            $now = Get-RegistryState -Entry $entry
            if (-not (Test-RegistryMatch -Entry $entry -State $now)) { throw "Revalidation registre échouée: $($entry.name)" }
            Write-Host "[FAIT] REG $($entry.name)" -ForegroundColor Green
        }
        foreach ($entry in @($pending.Services)) {
            $current = Get-ServiceState -Entry $entry
            if (-not $current.Exists) {
                Write-Warning "Service non présent: $($entry.name). Impossible de déclarer conforme."
                continue
            }
            Write-Host "[EN COURS] SVC $($entry.name) -> $($entry.startupType)" -ForegroundColor Cyan
            Set-Service -Name $entry.name -StartupType $entry.startupType
            $after = Get-ServiceState -Entry $entry
            $target = Convert-StartupTypeToCimMode -StartupType $entry.startupType
            if ($after.StartMode -ne $target) { throw "Revalidation service échouée: $($entry.name)" }
            Write-Host "[FAIT] SVC $($entry.name)" -ForegroundColor Green
        }
        $afterPending = Get-PendingChanges
        if ($afterPending.Registry.Count -gt 0 -or $afterPending.Services.Count -gt 0) {
            throw "Profil V4 '$Profile' encore incomplet après Apply."
        }
        Write-Host "[FAIT] Profil V4 '$Profile': $($pending.Registry.Count) registre(s), $($pending.Services.Count) service(s) corrigé(s)." -ForegroundColor Green
        if ($config.rebootRecommended) { Write-Host '[ACTION REQUISE] Redémarrage recommandé pour stabiliser ce profil.' -ForegroundColor Magenta }
    }
    'Verify' {
        $pending = Get-PendingChanges
        if ($pending.Registry.Count -gt 0 -or $pending.Services.Count -gt 0) {
            $items = @($pending.Registry | ForEach-Object { "REG:$($_.name)" }) + @($pending.Services | ForEach-Object { "SVC:$($_.name)" })
            throw "V4 profile '$Profile' non conforme: $($items -join ', ')"
        }
        Write-Host "[OK] V4 profile '$Profile' verified." -ForegroundColor Green
    }
    'Rollback' {
        Assert-Administrator
        if (-not (Test-Path $statePath)) {
            Write-Host "[DÉJÀ OK] Aucun état initial V4 '$Profile' enregistré; rollback inutile." -ForegroundColor Green
            return
        }
        $backup = Get-Content -Raw $statePath | ConvertFrom-Json
        foreach ($entry in @($backup.Registry)) {
            if ($entry.Exists) {
                New-Item -Force -Path $entry.Path | Out-Null
                $kind = if ($entry.Kind) { [string]$entry.Kind } else { 'DWord' }
                New-ItemProperty -Path $entry.Path -Name $entry.Property -PropertyType $kind -Value $entry.Value -Force | Out-Null
            } elseif (Test-Path $entry.Path) { Remove-ItemProperty -Path $entry.Path -Name $entry.Property -ErrorAction SilentlyContinue }
        }
        foreach ($entry in @($backup.Services)) {
            if (-not $entry.Exists) { continue }
            $startupType = switch ([string]$entry.StartMode) { 'Auto' { 'Automatic' } 'Manual' { 'Manual' } 'Disabled' { 'Disabled' } default { $null } }
            if ($startupType) { Set-Service -Name $entry.Name -StartupType $startupType }
        }
        Write-Host "[FAIT] Profil V4 '$Profile' restauré depuis lʼétat initial." -ForegroundColor Green
    }
}
