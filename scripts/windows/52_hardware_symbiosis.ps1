[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Verify')]
    [string]$Mode = 'Audit'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$policyPath = Join-Path $repoRoot 'config\hardware\symbiosis-v5.json'
$reportDir = Join-Path $repoRoot 'reports\hardware'
$reportPath = Join-Path $reportDir 'hardware-symbiosis-v5.json'

if (-not (Test-Path $policyPath)) {
    throw "Hardware symbiosis policy missing: $policyPath"
}

$policy = Get-Content -Raw $policyPath | ConvertFrom-Json
$warnings = [System.Collections.Generic.List[string]]::new()

function ConvertTo-VersionSafe {
    param([AllowNull()][AllowEmptyString()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    try {
        return [version]$Value.Trim()
    } catch {
        return $null
    }
}

function Get-UninstallEntries {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $entries = @()
    foreach ($path in $paths) {
        $entries += @(Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | Select-Object DisplayName, DisplayVersion, Publisher)
    }
    return @($entries)
}

function Get-HvciState {
    try {
        $value = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\State' -Name 'HVCIEnabled' -ErrorAction Stop
        return ([int]$value -eq 1)
    } catch {
        return $null
    }
}

New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

$amdPackage = @(Get-UninstallEntries | Where-Object {
    [string]$_.DisplayName -match [string]$policy.drivers.amdChipset.displayNameRegex
} | Select-Object -First 1)
$amdInstalledVersionText = if ($amdPackage.Count -gt 0) { [string]$amdPackage[0].DisplayVersion } else { $null }
$amdInstalledVersion = ConvertTo-VersionSafe -Value $amdInstalledVersionText
$amdMinimumVersion = ConvertTo-VersionSafe -Value ([string]$policy.drivers.amdChipset.minimumApprovedVersion)
$amdBaseline = $null
if ($null -ne $amdInstalledVersion -and $null -ne $amdMinimumVersion) {
    $amdBaseline = ($amdInstalledVersion -ge $amdMinimumVersion)
} else {
    $warnings.Add('AMD Chipset Software package version could not be read reliably; final vendor-driver review remains manual.')
}

$videoControllers = @(Get-CimInstance Win32_VideoController)
$arc = @($videoControllers | Where-Object {
    [string]$_.Name -match [string]$policy.drivers.intelArc.deviceNameRegex
})
$arcDriverVersionText = if ($arc.Count -gt 0) { [string]$arc[0].DriverVersion } else { $null }
$arcDriverVersion = ConvertTo-VersionSafe -Value $arcDriverVersionText
$arcMinimumVersion = ConvertTo-VersionSafe -Value ([string]$policy.drivers.intelArc.minimumApprovedVersion)
$arcDriverBaseline = ($arc.Count -gt 0 -and $null -ne $arcDriverVersion -and $null -ne $arcMinimumVersion -and $arcDriverVersion -ge $arcMinimumVersion)

$bios = Get-CimInstance Win32_BIOS | Select-Object -First 1 Manufacturer, SMBIOSBIOSVersion, ReleaseDate

$t705 = @(Get-PhysicalDisk | Where-Object {
    (([string]$_.FriendlyName + ' ' + [string]$_.Model) -match [string]$policy.storage.modelRegex)
})
$storageTelemetry = @()
$criticalTemperatureDetected = $false
foreach ($disk in $t705) {
    $reliability = $null
    try {
        $reliability = $disk | Get-StorageReliabilityCounter -ErrorAction Stop | Select-Object Temperature, TemperatureMax, Wear, PowerOnHours, ReadErrorsTotal, WriteErrorsTotal
    } catch {
        $warnings.Add("Storage reliability counters unavailable for $($disk.FriendlyName).")
    }

    if ($null -ne $reliability -and $null -ne $reliability.Temperature) {
        $temperature = [int]$reliability.Temperature
        if ($temperature -gt [int]$policy.storage.temperatureCriticalC) {
            $criticalTemperatureDetected = $true
            $warnings.Add("CRITICAL: $($disk.FriendlyName) temperature is ${temperature} C.")
        } elseif ($temperature -ge [int]$policy.storage.temperatureWarningC) {
            $warnings.Add("WARNING: $($disk.FriendlyName) temperature is ${temperature} C; review heatsink and airflow.")
        }
    }

    $storageTelemetry += [pscustomobject]@{
        FriendlyName = $disk.FriendlyName
        Model = $disk.Model
        SerialNumber = $disk.SerialNumber
        BusType = [string]$disk.BusType
        HealthStatus = [string]$disk.HealthStatus
        OperationalStatus = @($disk.OperationalStatus)
        Size = $disk.Size
        Reliability = $reliability
    }
}

$networkDrivers = @(Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceClass -eq 'NET' })
$lanDrivers = @($networkDrivers | Where-Object {
    ([string]$_.DeviceName + ' ' + [string]$_.Manufacturer) -match [string]$policy.network.lanDeviceRegex
})
$wifiDrivers = @($networkDrivers | Where-Object {
    ([string]$_.DeviceName + ' ' + [string]$_.Manufacturer) -match [string]$policy.network.wifiDeviceRegex
})

$physicalAdapters = @()
try {
    $physicalAdapters = @(Get-NetAdapter -Physical -ErrorAction Stop | Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress, DriverInformation)
} catch {
    $warnings.Add('Physical network adapter runtime state could not be read.')
}

$lanAdapters = @($physicalAdapters | Where-Object {
    ([string]$_.Name + ' ' + [string]$_.InterfaceDescription) -match [string]$policy.network.lanDeviceRegex
})
$lanRss = @()
if ($lanAdapters.Count -gt 0) {
    try {
        foreach ($adapter in $lanAdapters) {
            $lanRss += @(Get-NetAdapterRss -Name $adapter.Name -ErrorAction Stop | Select-Object Name, Enabled, NumberOfReceiveQueues, Profile)
        }
    } catch {
        $warnings.Add('RSS state could not be read for the 5 GbE adapter; no network setting was changed.')
    }
}

$deviceGuard = $null
try {
    $deviceGuard = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop
} catch {
    $warnings.Add('VBS DeviceGuard runtime state is unavailable on this Windows instance.')
}
$vbsRunning = if ($null -ne $deviceGuard) { [int]$deviceGuard.VirtualizationBasedSecurityStatus -eq 2 } else { $null }
$hvciEnabled = Get-HvciState
if ($vbsRunning -eq $false) {
    $warnings.Add('VBS is not reported as running. Review Windows Security and driver compatibility before enabling it.')
}
if ($hvciEnabled -eq $false) {
    $warnings.Add('Memory integrity/HVCI is not reported as enabled. Do not force-enable it until incompatible drivers have been reviewed.')
}

$hardChecks = [ordered]@{
    ArcB580Detected = ($arc.Count -gt 0)
    ArcDriverAtLeastApproved = $arcDriverBaseline
    T705Count = ($t705.Count -ge [int]$policy.storage.minimumCount)
    T705Healthy = ($t705.Count -ge [int]$policy.storage.minimumCount -and @($t705 | Where-Object { [string]$_.HealthStatus -ne 'Healthy' }).Count -eq 0)
    T705Nvme = ($t705.Count -ge [int]$policy.storage.minimumCount -and @($t705 | Where-Object { [string]$_.BusType -ne 'NVMe' }).Count -eq 0)
    T705TemperatureBelowCritical = (-not $criticalTemperatureDetected)
    Realtek8126Present = (-not [bool]$policy.network.requireLanDevice -or $lanDrivers.Count -gt 0)
    WifiAdapterPresent = (-not [bool]$policy.network.requireWifiDevice -or $wifiDrivers.Count -gt 0)
    AmdChipsetNotBelowApprovedBaseline = ($null -eq $amdBaseline -or [bool]$amdBaseline)
}

$advisory = [ordered]@{
    AmdChipsetDetectedVersion = $amdInstalledVersionText
    AmdChipsetMinimumApprovedVersion = [string]$policy.drivers.amdChipset.minimumApprovedVersion
    AmdChipsetAtLeastApproved = $amdBaseline
    ArcDriverDetectedVersion = $arcDriverVersionText
    ArcDriverMinimumApprovedVersion = [string]$policy.drivers.intelArc.minimumApprovedVersion
    VbsRunning = $vbsRunning
    HvciMemoryIntegrityEnabled = $hvciEnabled
    BiosVersion = if ($null -ne $bios) { [string]$bios.SMBIOSBIOSVersion } else { $null }
    BiosReleaseDate = if ($null -ne $bios) { $bios.ReleaseDate } else { $null }
    BiosAutoFlashAllowed = [bool]$policy.bios.autoFlash
    NetworkOffloadMutationAllowed = [bool]$policy.network.mutateOffloads
    UltimatePerformanceAllowed = [bool]$policy.power.allowUltimatePerformance
}

$report = [ordered]@{
    Version = 'V5'
    Timestamp = (Get-Date).ToString('o')
    Mode = $Mode
    PolicyReviewedAt = [string]$policy.reviewedAt
    HardChecks = $hardChecks
    Advisory = $advisory
    BIOS = $bios
    Arc = $arc | Select-Object Name, DriverVersion, DriverDate, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate
    Storage = $storageTelemetry
    LanDrivers = $lanDrivers | Select-Object DeviceName, Manufacturer, DriverProviderName, DriverVersion, DriverDate, InfName
    WifiDrivers = $wifiDrivers | Select-Object DeviceName, Manufacturer, DriverProviderName, DriverVersion, DriverDate, InfName
    PhysicalNetworkAdapters = $physicalAdapters
    LanRss = $lanRss
    Warnings = @($warnings)
}
$report | ConvertTo-Json -Depth 12 | Set-Content -Encoding utf8 $reportPath

foreach ($check in $hardChecks.GetEnumerator()) {
    $state = if ([bool]$check.Value) { 'OK' } else { 'KO' }
    Write-Host ("[{0}] {1}" -f $state, $check.Key)
}
foreach ($message in $warnings) {
    Write-Warning $message
}
Write-Host "[INFO] Hardware symbiosis report: $reportPath"

if ($Mode -eq 'Verify') {
    $failed = @($hardChecks.GetEnumerator() | Where-Object { -not [bool]$_.Value })
    if ($failed.Count -gt 0) {
        throw "V5 hardware symbiosis qualification failed: $($failed.Count) hard check(s). See $reportPath"
    }
    Write-Host 'VERDICT: V5 HARDWARE SYMBIOSIS READY' -ForegroundColor Green
}
