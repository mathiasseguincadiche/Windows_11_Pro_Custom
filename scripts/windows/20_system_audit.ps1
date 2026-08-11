[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$reportDir = Join-Path $repoRoot 'reports\windows'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

$cpu = Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed
$memory = Get-CimInstance Win32_PhysicalMemory | Select-Object Manufacturer, PartNumber, Capacity, Speed, ConfiguredClockSpeed
$gpu = Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate
$physicalDisks = Get-PhysicalDisk | Select-Object FriendlyName, MediaType, BusType, HealthStatus, OperationalStatus, Size
$volumes = foreach ($letter in @('C', 'D')) {
    try {
        Get-Volume -DriveLetter $letter | Select-Object DriveLetter, FileSystem, FileSystemLabel, DriveType, HealthStatus, Size, SizeRemaining
    } catch {
        [pscustomobject]@{ DriveLetter = $letter; Error = $_.Exception.Message }
    }
}

$memoryAgent = try { Get-MMAgent | Select-Object MemoryCompression, PageCombining, ApplicationLaunchPrefetching, ApplicationPreLaunch } catch { $null }
$powerScheme = (& powercfg.exe /GetActiveScheme 2>&1 | Out-String).Trim()
$trim = (& fsutil.exe behavior query DisableDeleteNotify 2>&1 | Out-String).Trim()
$wslStatus = if (Get-Command wsl.exe -ErrorAction SilentlyContinue) { (& wsl.exe --status 2>&1 | Out-String).Trim() } else { 'wsl.exe absent' }
$defender = try {
    Get-MpComputerStatus | Select-Object AntivirusEnabled, RealTimeProtectionEnabled, BehaviorMonitorEnabled, IoavProtectionEnabled, NISEnabled, AntivirusSignatureLastUpdated
} catch { $null }

$report = [ordered]@{
    Timestamp = (Get-Date).ToString('o')
    Computer = $env:COMPUTERNAME
    CPU = $cpu
    Memory = $memory
    GPU = $gpu
    PhysicalDisks = $physicalDisks
    Volumes = $volumes
    MemoryManager = $memoryAgent
    ActivePowerScheme = $powerScheme
    TrimStatus = $trim
    WslStatus = $wslStatus
    Defender = $defender
}

$path = Join-Path $reportDir 'system-audit.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 $path

Write-Host "[OK] Audit matériel / Windows: $path" -ForegroundColor Green
Write-Host $powerScheme
Write-Host $trim
$volumes | Format-Table -AutoSize
$gpu | Format-Table -AutoSize
