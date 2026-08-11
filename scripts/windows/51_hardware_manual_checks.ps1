[CmdletBinding()]
param(
    [ValidateSet('Show', 'Record', 'Verify', 'Reset')]
    [string]$Mode = 'Show',

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
$targetPath = Join-Path $repoRoot 'config\hardware\target-v5.json'
$stateDir = Join-Path $repoRoot 'state'
$statePath = Join-Path $stateDir 'hardware-v5-manual.json'
$target = Get-Content -Raw $targetPath | ConvertFrom-Json

$descriptions = [ordered]@{
    uefi_csm_disabled = 'UEFI boot confirmed and CSM/Legacy disabled.'
    above_4g_enabled = 'Above 4G Decoding enabled in UEFI.'
    resizable_bar_enabled = 'Resizable BAR enabled and confirmed in Intel Graphics Software or Intel DSA.'
    t705_in_m2_1_and_m2_2 = 'The two Crucial T705 drives are physically installed in M2_1 and M2_2.'
    t705_heatsinks_and_airflow_verified = 'Both T705 drives have a motherboard/SSD heatsink and usable airflow.'
    memory_6000_stability_verified = 'DDR5 6000 MT/s has passed a deliberate memory stability test without errors.'
    latest_stable_bios_reviewed = 'The current MSI stable BIOS was reviewed before qualification.'
    current_vendor_drivers_reviewed = 'AMD chipset, Intel Arc and MSI device drivers were reviewed from vendor sources.'
}

function New-EmptyState {
    $checks = [ordered]@{}
    foreach ($name in @($target.manualChecks)) {
        $checks[$name] = $false
    }
    return [ordered]@{
        Version = 'V5'
        UpdatedAt = $null
        Checks = $checks
        Notes = ''
    }
}

function Read-State {
    $state = New-EmptyState
    if (-not (Test-Path $statePath)) {
        return $state
    }

    $existing = Get-Content -Raw $statePath | ConvertFrom-Json
    foreach ($name in @($target.manualChecks)) {
        $property = $existing.Checks.PSObject.Properties[$name]
        if ($null -ne $property) {
            $state.Checks[$name] = [bool]$property.Value
        }
    }
    if ($null -ne $existing.UpdatedAt) {
        $state.UpdatedAt = [string]$existing.UpdatedAt
    }
    if ($null -ne $existing.Notes) {
        $state.Notes = [string]$existing.Notes
    }
    return $state
}

function Show-State {
    param([Parameter(Mandatory)]$State)
    foreach ($name in @($target.manualChecks)) {
        $value = [bool]$State.Checks[$name]
        $status = if ($value) { 'OK' } else { 'TODO' }
        Write-Host ("[{0}] {1} - {2}" -f $status, $name, $descriptions[$name])
    }
    if ($State.Notes) {
        Write-Host "Notes: $($State.Notes)"
    }
}

if ($Mode -eq 'Reset') {
    if (Test-Path $statePath) {
        Remove-Item -LiteralPath $statePath -Force
    }
    Write-Host '[OK] V5 manual hardware proof reset.' -ForegroundColor Green
    return
}

$state = Read-State

if ($Mode -eq 'Show') {
    Show-State -State $state
    return
}

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

    foreach ($entry in $map.GetEnumerator()) {
        if ($entry.Value) {
            $state.Checks[$entry.Key] = $true
        }
    }
    if ($Notes) {
        $state.Notes = $Notes
    }
    $state.UpdatedAt = (Get-Date).ToString('o')

    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    $state | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 $statePath
    Write-Host "[OK] V5 manual proof updated: $statePath" -ForegroundColor Green
    Show-State -State $state
    return
}

$missing = @()
foreach ($name in @($target.manualChecks)) {
    if (-not [bool]$state.Checks[$name]) {
        $missing += $name
    }
}

Show-State -State $state
if ($missing.Count -gt 0) {
    throw "V5 manual hardware qualification incomplete: $($missing -join ', ')"
}

Write-Host 'VERDICT: V5 HARDWARE MANUAL CHECKS READY' -ForegroundColor Green
