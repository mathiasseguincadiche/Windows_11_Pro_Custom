[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Verify')]
    [string]$Mode = 'Audit'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$release = (Get-Content -Raw (Join-Path $repoRoot 'VERSION')).Trim()
if ($release -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION invalide: $release" }
$policyPath = Join-Path $repoRoot 'config\hardware\symbiosis.json'
$reportDir = Join-Path $repoRoot 'reports\hardware'
$reportPath = Join-Path $reportDir 'hardware-symbiosis.json'

if (-not (Test-Path $policyPath)) { throw "Politique de qualification matérielle absente: $policyPath" }
$policy = Get-Content -Raw $policyPath | ConvertFrom-Json
if ([int]$policy.schemaVersion -ne 1) { throw "SchemaVersion de politique matérielle non supporté: $($policy.schemaVersion)" }
$warnings = [System.Collections.Generic.List[string]]::new()

function ConvertTo-VersionSafe {
    param([AllowNull()][AllowEmptyString()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    try { return [version]$Value.Trim() } catch { return $null }
}

function Get-UninstallEntries {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $entries = @()
    foreach ($path in $paths) { $entries += @(Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | Select-Object DisplayName, DisplayVersion, Publisher) }
    return @($entries)
}

function Get-HvciState {
    try {
        $value = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\State' -Name 'HVCIEnabled' -ErrorAction Stop
        return ([int]$value -eq 1)
    } catch { return $null }
}

New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$amdPackage = @(Get-UninstallEntries | Where-Object { [string]$_.DisplayName -match [string]$policy.drivers.amdChipset.displayNameRegex } | Select-Object -First 1)
$amdInstalledVersionText = if ($amdPackage.Count -gt 0) { [string]$amdPackage[0].DisplayVersion } else { $null }
$amdInstalledVersion = ConvertTo-VersionSafe -Value $amdInstalledVersionText
$amdMinimumVersion = ConvertTo-VersionSafe -Value ([string]$policy.drivers.amdChipset.minimumApprovedVersion)
$amdBaseline = $null
if ($null -ne $amdInstalledVersion -and $null -ne $amdMinimumVersion) { $amdBaseline = ($amdInstalledVersion -ge $amdMinimumVersion) }
else { $warnings.Add('La version du package AMD Chipset Software ne peut pas être lue de façon fiable; la revue finale des pilotes constructeur reste manuelle.') }

$videoControllers = @(Get-CimInstance Win32_VideoController)
$arc = @($videoControllers | Where-Object { [string]$_.Name -match [string]$policy.drivers.intelArc.deviceNameRegex })
$arcDriverVersionText = if ($arc.Count -gt 0) { [string]$arc[0].DriverVersion } else { $null }
$arcDriverVersion = ConvertTo-VersionSafe -Value $arcDriverVersionText
$arcMinimumVersion = ConvertTo-VersionSafe -Value ([string]$policy.drivers.intelArc.minimumApprovedVersion)
$arcDriverBaseline = ($arc.Count -gt 0 -and $null -ne $arcDriverVersion -and $null -ne $arcMinimumVersion -and $arcDriverVersion -ge $arcMinimumVersion)
$bios = Get-CimInstance Win32_BIOS | Select-Object -First 1 Manufacturer, SMBIOSBIOSVersion, ReleaseDate

$t705 = @(Get-PhysicalDisk | Where-Object { (([string]$_.FriendlyName + ' ' + [string]$_.Model) -match [string]$policy.storage.modelRegex) })
$storageTelemetry = @()
$criticalTemperatureDetected = $false
foreach ($disk in $t705) {
    $reliability = $null
    try { $reliability = $disk | Get-StorageReliabilityCounter -ErrorAction Stop | Select-Object Temperature, TemperatureMax, Wear, PowerOnHours, ReadErrorsTotal, WriteErrorsTotal }
    catch { $warnings.Add("Compteurs de fiabilité stockage indisponibles pour $($disk.FriendlyName).") }
    if ($null -ne $reliability -and $null -ne $reliability.Temperature) {
        $temperature = [int]$reliability.Temperature
        if ($temperature -gt [int]$policy.storage.temperatureCriticalC) { $criticalTemperatureDetected = $true; $warnings.Add("CRITIQUE: température $($disk.FriendlyName) = ${temperature} C.") }
        elseif ($temperature -ge [int]$policy.storage.temperatureWarningC) { $warnings.Add("AVERTISSEMENT: température $($disk.FriendlyName) = ${temperature} C; vérifier dissipateur et airflow.") }
    }
    $storageTelemetry += [pscustomobject]@{
        FriendlyName=$disk.FriendlyName; Model=$disk.Model; SerialNumber=$disk.SerialNumber; BusType=[string]$disk.BusType
        HealthStatus=[string]$disk.HealthStatus; OperationalStatus=@($disk.OperationalStatus); Size=$disk.Size; Reliability=$reliability
    }
}

$networkDrivers = @(Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceClass -eq 'NET' })
$lanDrivers = @($networkDrivers | Where-Object { ([string]$_.DeviceName + ' ' + [string]$_.Manufacturer) -match [string]$policy.network.lanDeviceRegex })
$wifiDrivers = @($networkDrivers | Where-Object { ([string]$_.DeviceName + ' ' + [string]$_.Manufacturer) -match [string]$policy.network.wifiDeviceRegex })
$physicalAdapters = @()
try { $physicalAdapters = @(Get-NetAdapter -Physical -ErrorAction Stop | Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress, DriverInformation) }
catch { $warnings.Add('État runtime des interfaces réseau physiques indisponible.') }
$lanAdapters = @($physicalAdapters | Where-Object { ([string]$_.Name + ' ' + [string]$_.InterfaceDescription) -match [string]$policy.network.lanDeviceRegex })
$lanRss = @()
if ($lanAdapters.Count -gt 0) {
    try { foreach ($adapter in $lanAdapters) { $lanRss += @(Get-NetAdapterRss -Name $adapter.Name -ErrorAction Stop | Select-Object Name, Enabled, NumberOfReceiveQueues, Profile) } }
    catch { $warnings.Add("État RSS illisible pour l'adaptateur 5 GbE; aucun réglage réseau n'a été modifié.") }
}

$deviceGuard = $null
try { $deviceGuard = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop }
catch { $warnings.Add('État runtime VBS DeviceGuard indisponible sur cette instance Windows.') }
$vbsRunning = if ($null -ne $deviceGuard) { [int]$deviceGuard.VirtualizationBasedSecurityStatus -eq 2 } else { $null }
$hvciEnabled = Get-HvciState
if ($vbsRunning -eq $false) { $warnings.Add("VBS n'est pas signalé actif. Vérifier Windows Security et la compatibilité pilotes avant toute activation.") }
if ($hvciEnabled -eq $false) { $warnings.Add("Memory Integrity/HVCI n'est pas signalé actif. Ne pas forcer son activation avant revue des pilotes incompatibles.") }

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

$arcDetectedText = if ($arc.Count -gt 0) { @($arc | ForEach-Object { [string]$_.Name }) -join ', ' } else { 'aucune Arc B580 détectée' }
$arcVersionText = if ([string]::IsNullOrWhiteSpace($arcDriverVersionText)) { 'inconnue' } else { $arcDriverVersionText }
$amdVersionText = if ([string]::IsNullOrWhiteSpace($amdInstalledVersionText)) { 'inconnue' } else { $amdInstalledVersionText }
$unhealthyT705 = @($t705 | Where-Object { [string]$_.HealthStatus -ne 'Healthy' } | ForEach-Object { "$($_.FriendlyName)=$($_.HealthStatus)" })
$nonNvmeT705 = @($t705 | Where-Object { [string]$_.BusType -ne 'NVMe' } | ForEach-Object { "$($_.FriendlyName)=$($_.BusType)" })
$temperatureEvidence = @(
    $storageTelemetry | ForEach-Object {
        if ($null -ne $_.Reliability -and $null -ne $_.Reliability.Temperature) { "$($_.FriendlyName)=$([int]$_.Reliability.Temperature)C" }
    }
)

function Get-HardCheckDetail {
    param([Parameter(Mandatory)][string]$Name)
    switch ($Name) {
        'ArcB580Detected' { return "détecté=$arcDetectedText ; attenduRegex=$([string]$policy.drivers.intelArc.deviceNameRegex)" }
        'ArcDriverAtLeastApproved' { return "versionDétectée=$arcVersionText ; minimum=$([string]$policy.drivers.intelArc.minimumApprovedVersion)" }
        'T705Count' { return "détectés=$($t705.Count) ; minimum=$([int]$policy.storage.minimumCount)" }
        'T705Healthy' { return $(if ($unhealthyT705.Count -eq 0) { 'tous les T705 détectés sont Healthy' } else { $unhealthyT705 -join ', ' }) }
        'T705Nvme' { return $(if ($nonNvmeT705.Count -eq 0) { 'tous les T705 détectés sont NVMe' } else { $nonNvmeT705 -join ', ' }) }
        'T705TemperatureBelowCritical' { return "températures=$(if ($temperatureEvidence.Count -gt 0) { $temperatureEvidence -join ', ' } else { 'télémétrie indisponible' }) ; critique>$([int]$policy.storage.temperatureCriticalC)C" }
        'Realtek8126Present' { return "correspondances=$($lanDrivers.Count) ; attenduRegex=$([string]$policy.network.lanDeviceRegex)" }
        'WifiAdapterPresent' { return "correspondances=$($wifiDrivers.Count) ; attenduRegex=$([string]$policy.network.wifiDeviceRegex)" }
        'AmdChipsetNotBelowApprovedBaseline' { return "versionDétectée=$amdVersionText ; minimum=$([string]$policy.drivers.amdChipset.minimumApprovedVersion)" }
        default { return 'aucun détail spécifique disponible' }
    }
}

$hardCheckFailures = @(
    $hardChecks.GetEnumerator() |
        Where-Object { -not [bool]$_.Value } |
        ForEach-Object { [pscustomobject]@{ Name=[string]$_.Key; Detail=(Get-HardCheckDetail -Name ([string]$_.Key)) } }
)

$advisory = [ordered]@{
    AmdChipsetDetectedVersion=$amdInstalledVersionText
    AmdChipsetMinimumApprovedVersion=[string]$policy.drivers.amdChipset.minimumApprovedVersion
    AmdChipsetAtLeastApproved=$amdBaseline
    ArcDriverDetectedVersion=$arcDriverVersionText
    ArcDriverMinimumApprovedVersion=[string]$policy.drivers.intelArc.minimumApprovedVersion
    VbsRunning=$vbsRunning
    HvciMemoryIntegrityEnabled=$hvciEnabled
    BiosVersion=if ($null -ne $bios) { [string]$bios.SMBIOSBIOSVersion } else { $null }
    BiosReleaseDate=if ($null -ne $bios) { $bios.ReleaseDate } else { $null }
    BiosAutoFlashAllowed=[bool]$policy.bios.autoFlash
    NetworkOffloadMutationAllowed=[bool]$policy.network.mutateOffloads
    UltimatePerformanceAllowed=[bool]$policy.power.allowUltimatePerformance
}

$report = [ordered]@{
    Release=$release
    SchemaVersion=1
    Timestamp=(Get-Date).ToString('o')
    Mode=$Mode
    PolicyReviewedAt=[string]$policy.reviewedAt
    HardChecks=$hardChecks
    HardCheckFailures=$hardCheckFailures
    Advisory=$advisory
    BIOS=$bios
    Arc=$arc | Select-Object Name, DriverVersion, DriverDate, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate
    Storage=$storageTelemetry
    LanDrivers=$lanDrivers | Select-Object DeviceName, Manufacturer, DriverProviderName, DriverVersion, DriverDate, InfName
    WifiDrivers=$wifiDrivers | Select-Object DeviceName, Manufacturer, DriverProviderName, DriverVersion, DriverDate, InfName
    PhysicalNetworkAdapters=$physicalAdapters
    LanRss=$lanRss
    Warnings=$warnings.ToArray()
}
$report | ConvertTo-Json -Depth 12 | Set-Content -Encoding utf8 $reportPath
foreach ($check in $hardChecks.GetEnumerator()) {
    $state = if ([bool]$check.Value) { 'OK' } else { 'KO' }
    $detail = Get-HardCheckDetail -Name ([string]$check.Key)
    Write-Host ("[{0}] {1} | {2}" -f $state, $check.Key, $detail)
}
foreach ($message in $warnings) { Write-Warning $message }
Write-Host "[INFO] Rapport de qualification matérielle: $reportPath"
if ($Mode -eq 'Verify') {
    if ($hardCheckFailures.Count -gt 0) {
        $failureText = @($hardCheckFailures | ForEach-Object { "$($_.Name) ($($_.Detail))" }) -join ' | '
        throw "Qualification de symbiose matérielle échouée: $($hardCheckFailures.Count) contrôle(s) bloquant(s): $failureText. Voir $reportPath"
    }
    Write-Host 'VERDICT: HARDWARE SYMBIOSIS READY' -ForegroundColor Green
}
