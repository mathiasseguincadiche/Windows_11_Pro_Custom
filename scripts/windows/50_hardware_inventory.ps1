[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$reportDir = Join-Path $repoRoot 'reports\hardware'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

$cpu = Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, VirtualizationFirmwareEnabled
$board = Get-CimInstance Win32_BaseBoard | Select-Object Manufacturer, Product, Version, SerialNumber
$bios = Get-CimInstance Win32_BIOS | Select-Object Manufacturer, SMBIOSBIOSVersion, ReleaseDate
$memory = Get-CimInstance Win32_PhysicalMemory | Select-Object Manufacturer, PartNumber, Capacity, Speed, ConfiguredClockSpeed
$computer = Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model, TotalPhysicalMemory, HypervisorPresent
$video = Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, DriverDate, AdapterRAM, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate

$physicalDisks = @()
foreach ($disk in @(Get-PhysicalDisk)) {
    $reliability = $null
    try {
        $reliability = $disk | Get-StorageReliabilityCounter -ErrorAction Stop | Select-Object Temperature, TemperatureMax, Wear, PowerOnHours, ReadErrorsTotal, WriteErrorsTotal
    } catch {
        $reliability = $null
    }

    $physicalDisks += [pscustomobject]@{
        FriendlyName = $disk.FriendlyName
        Manufacturer = $disk.Manufacturer
        Model = $disk.Model
        SerialNumber = $disk.SerialNumber
        MediaType = $disk.MediaType
        BusType = $disk.BusType
        HealthStatus = $disk.HealthStatus
        OperationalStatus = @($disk.OperationalStatus)
        Size = $disk.Size
        Reliability = $reliability
    }
}

$volumes = foreach ($letter in @('C', 'D')) {
    try {
        Get-Volume -DriveLetter $letter | Select-Object DriveLetter, FileSystem, FileSystemLabel, HealthStatus, Size, SizeRemaining
    } catch {
        [pscustomobject]@{ DriveLetter = $letter; Error = $_.Exception.Message }
    }
}

$systemPartition = $null
try {
    $systemPartition = Get-Partition -DriveLetter C -ErrorAction Stop
    $systemDisk = Get-Disk -Number $systemPartition.DiskNumber -ErrorAction Stop
    $systemPartition = [pscustomobject]@{
        DiskNumber = $systemDisk.Number
        FriendlyName = $systemDisk.FriendlyName
        PartitionStyle = [string]$systemDisk.PartitionStyle
        BusType = [string]$systemDisk.BusType
    }
} catch {
    $systemPartition = [pscustomobject]@{ Error = $_.Exception.Message }
}

$secureBoot = $null
try {
    $secureBoot = Confirm-SecureBootUEFI -ErrorAction Stop
} catch {
    $secureBoot = $null
}

$tpm = $null
try {
    $tpmInfo = Get-Tpm -ErrorAction Stop
    $tpm = [pscustomobject]@{
        Present = $tpmInfo.TpmPresent
        Ready = $tpmInfo.TpmReady
        Enabled = $tpmInfo.TpmEnabled
        Activated = $tpmInfo.TpmActivated
    }
} catch {
    $tpm = $null
}

$powerScheme = (& powercfg.exe /GetActiveScheme 2>&1 | Out-String).Trim()
$trim = (& fsutil.exe behavior query DisableDeleteNotify 2>&1 | Out-String).Trim()

$drivers = Get-CimInstance Win32_PnPSignedDriver | Where-Object {
    $_.DeviceClass -in @('DISPLAY', 'NET', 'MEDIA', 'BLUETOOTH', 'SYSTEM') -and
    ($_.Manufacturer -match 'AMD|Intel|Realtek|Micro-Star|MSI|MediaTek|Qualcomm')
} | Select-Object DeviceName, DeviceClass, Manufacturer, DriverProviderName, DriverVersion, DriverDate, InfName

$report = [ordered]@{
    Timestamp = (Get-Date).ToString('o')
    Computer = $computer
    CPU = $cpu
    Motherboard = $board
    BIOS = $bios
    Memory = $memory
    GPU = $video
    PhysicalDisks = $physicalDisks
    Volumes = $volumes
    SystemDisk = $systemPartition
    SecureBoot = $secureBoot
    TPM = $tpm
    ActivePowerScheme = $powerScheme
    TrimStatus = $trim
    Drivers = $drivers
}

$path = Join-Path $reportDir 'hardware-inventory-v5.json'
$report | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 $path

Write-Host "[OK] Inventaire matériel: $path" -ForegroundColor Green
Write-Host $powerScheme
$cpu | Format-Table -AutoSize
$memory | Format-Table -AutoSize
$video | Format-Table -AutoSize
$physicalDisks | Select-Object FriendlyName, Model, HealthStatus, BusType, Size | Format-Table -AutoSize
