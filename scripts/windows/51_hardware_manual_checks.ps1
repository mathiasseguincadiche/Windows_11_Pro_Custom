[CmdletBinding()]
param(
    [ValidateSet('Show', 'Record', 'Verify', 'Reset')]
    [string]$Mode = 'Show',
    [switch]$Interactive,
    [switch]$UefiCsmDisabled,
    [switch]$Above4GEnabled,
    [switch]$ResizableBarEnabled,
    [switch]$T705InM2Slots,
    [switch]$T705CoolingVerified,
    [switch]$Memory6000Stable,
    [switch]$LatestStableBiosReviewed,
    [switch]$CurrentVendorDriversReviewed,
    [string]$Notes = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$versionPath = Join-Path $repoRoot 'VERSION'
$release = (Get-Content -Raw -LiteralPath $versionPath).Trim()
if ($release -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION invalide: $release" }
$targetPath = Join-Path $repoRoot 'config\hardware\target.json'
$stateDir = Join-Path $repoRoot 'state'
$statePath = Join-Path $stateDir 'hardware-manual.json'
$legacyStatePath = Join-Path $stateDir 'hardware-v5-manual.json'
$target = Get-Content -Raw $targetPath | ConvertFrom-Json
if ([int]$target.schemaVersion -ne 1) { throw "SchemaVersion de cible matérielle non supporté: $($target.schemaVersion)" }

$descriptions = [ordered]@{
    uefi_csm_disabled = 'UEFI démarré et CSM/Legacy désactivé.'
    above_4g_enabled = 'Above 4G Decoding activé dans lʼUEFI.'
    resizable_bar_enabled = 'Resizable BAR activé et confirmé dans Intel Graphics Software ou Intel DSA.'
    t705_in_m2_1_and_m2_2 = 'Les deux Crucial T705 sont physiquement installés dans M2_1 et M2_2.'
    t705_heatsinks_and_airflow_verified = 'Les deux T705 disposent dʼun dissipateur et dʼun flux dʼair correct.'
    memory_6000_stability_verified = 'La DDR5 6000 MT/s a passé un vrai test de stabilité mémoire sans erreur.'
    latest_stable_bios_reviewed = 'La version BIOS MSI stable actuelle a été vérifiée avant qualification.'
    current_vendor_drivers_reviewed = 'Les pilotes AMD chipset, Intel Arc et MSI ont été vérifiés depuis les sources constructeur.'
}

function New-EmptyState {
    $checks = [ordered]@{}
    foreach ($name in @($target.manualChecks)) { $checks[$name] = $false }
    return [ordered]@{ Release=$release; SchemaVersion=1; UpdatedAt=$null; Checks=$checks; Notes='' }
}

function Get-ReadableStatePath {
    if (Test-Path -LiteralPath $statePath) { return $statePath }
    if (Test-Path -LiteralPath $legacyStatePath) {
        Write-Host "[COMPAT] Ancien état de preuves matérielles lu sans modification: $legacyStatePath" -ForegroundColor DarkGray
        return $legacyStatePath
    }
    return $null
}

function Read-State {
    $state = New-EmptyState
    $readPath = Get-ReadableStatePath
    if ([string]::IsNullOrWhiteSpace($readPath)) { return $state }
    $existing = Get-Content -Raw -LiteralPath $readPath | ConvertFrom-Json
    foreach ($name in @($target.manualChecks)) {
        $property = $existing.Checks.PSObject.Properties[$name]
        if ($null -ne $property) { $state.Checks[$name] = [bool]$property.Value }
    }
    if ($null -ne $existing.UpdatedAt) { $state.UpdatedAt = [string]$existing.UpdatedAt }
    if ($null -ne $existing.Notes) { $state.Notes = [string]$existing.Notes }
    return $state
}

function Show-State {
    param([Parameter(Mandatory)]$State)
    foreach ($name in @($target.manualChecks)) {
        $value = [bool]$State.Checks[$name]
        if ($value) {
            Write-Host "[DÉJÀ OK] $name - $($descriptions[$name])" -ForegroundColor Green
        } else {
            Write-Host "[ACTION REQUISE] $name - $($descriptions[$name])" -ForegroundColor Magenta
        }
    }
    if ($State.Notes) { Write-Host "Notes: $($State.Notes)" }
}

function Read-ManualConfirmation {
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string]$Description)
    Write-Host ''
    Write-Host "Vérification: $Name" -ForegroundColor Cyan
    Write-Host $Description
    Write-Host 'Réponds O uniquement si tu as réellement contrôlé ce point. Le script ne peut pas le deviner.' -ForegroundColor Yellow
    while ($true) {
        $answer = (Read-Host 'Confirmé ? [O/N]').Trim().ToLowerInvariant()
        if ($answer -in @('o','oui','y','yes')) { return $true }
        if ($answer -in @('n','non','no')) { return $false }
        Write-Host 'Répondre O (oui, réellement vérifié) ou N (pas encore vérifié).' -ForegroundColor Yellow
    }
}

if ($Mode -eq 'Reset') {
    if (Test-Path -LiteralPath $statePath) { Remove-Item -LiteralPath $statePath -Force }
    Write-Host '[FAIT] Preuves matérielles manuelles canoniques réinitialisées.' -ForegroundColor Green
    if (Test-Path -LiteralPath $legacyStatePath) {
        Write-Host "[INFO] L'ancien état de compatibilité est conservé et n'a pas été supprimé: $legacyStatePath" -ForegroundColor DarkGray
    }
    return
}

$state = Read-State
if ($Mode -eq 'Show') { Show-State -State $state; return }

if ($Mode -eq 'Record') {
    $map = [ordered]@{
        uefi_csm_disabled = $UefiCsmDisabled.IsPresent
        above_4g_enabled = $Above4GEnabled.IsPresent
        resizable_bar_enabled = $ResizableBarEnabled.IsPresent
        t705_in_m2_1_and_m2_2 = $T705InM2Slots.IsPresent
        t705_heatsinks_and_airflow_verified = $T705CoolingVerified.IsPresent
        memory_6000_stability_verified = $Memory6000Stable.IsPresent
        latest_stable_bios_reviewed = $LatestStableBiosReviewed.IsPresent
        current_vendor_drivers_reviewed = $CurrentVendorDriversReviewed.IsPresent
    }

    if ($Interactive) {
        foreach ($name in @($target.manualChecks)) {
            if ([bool]$state.Checks[$name]) {
                Write-Host "[DÉJÀ OK] $name déjà confirmé précédemment; aucune nouvelle saisie." -ForegroundColor Green
                continue
            }
            if (Read-ManualConfirmation -Name $name -Description $descriptions[$name]) { $map[$name] = $true }
        }
    }

    $changed = 0
    foreach ($entry in $map.GetEnumerator()) {
        if ($entry.Value -and -not [bool]$state.Checks[$entry.Key]) {
            $state.Checks[$entry.Key] = $true
            $changed++
        }
    }
    if ($Notes) { $state.Notes = $Notes }
    $state.Release = $release
    $state.SchemaVersion = 1
    $state.UpdatedAt = (Get-Date).ToString('o')
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    $state | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 $statePath
    if ($changed -gt 0) { Write-Host "[FAIT] $changed preuve(s) manuelle(s) ajoutée(s): $statePath" -ForegroundColor Green }
    else { Write-Host '[DÉJÀ OK] Aucune nouvelle preuve manuelle confirmée.' -ForegroundColor Green }
    Show-State -State $state
    return
}

$missing = @()
foreach ($name in @($target.manualChecks)) { if (-not [bool]$state.Checks[$name]) { $missing += $name } }
Show-State -State $state
if ($missing.Count -gt 0) {
    throw "Qualification matérielle manuelle incomplète: $($missing -join ', '). Pour une saisie guidée: .\scripts\windows\51_hardware_manual_checks.ps1 -Mode Record -Interactive"
}
Write-Host 'VERDICT: HARDWARE MANUAL CHECKS READY' -ForegroundColor Green
