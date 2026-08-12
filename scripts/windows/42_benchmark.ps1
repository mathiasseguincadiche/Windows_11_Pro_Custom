[CmdletBinding()]
param(
    [ValidateSet('before', 'after', 'snapshot')]
    [string]$Stage = 'snapshot'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$reportDir = Join-Path $repoRoot 'reports\windows'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

$os = Get-CimInstance Win32_OperatingSystem
$computer = Get-CimInstance Win32_ComputerSystem
$cpu = @(Get-CimInstance Win32_Processor)
$processes = @(Get-Process)
$services = @(Get-CimInstance Win32_Service)
$startupCommands = @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue)
$volumes = @(Get-Volume | Where-Object DriveLetter -In @('C', 'D'))
$defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
$preferences = Get-MpPreference -ErrorAction SilentlyContinue
$memoryPerf = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction SilentlyContinue
$diskPerf = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -ErrorAction SilentlyContinue | Where-Object Name -EQ '_Total' | Select-Object -First 1
$pageFiles = @(Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue)
$mmAgent = Get-MMAgent -ErrorAction SilentlyContinue

$topProcesses = @(
    $processes |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First 10 Name, Id,
            @{ Name = 'WorkingSetMB'; Expression = { [math]::Round($_.WorkingSet64 / 1MB, 1) } },
            @{ Name = 'CPUSeconds'; Expression = { if ($null -eq $_.CPU) { 0 } else { [math]::Round($_.CPU, 1) } } }
)

$volumeData = @(
    foreach ($volume in $volumes) {
        $freePercent = if ($volume.Size -gt 0) { [math]::Round(($volume.SizeRemaining / $volume.Size) * 100, 1) } else { $null }
        [pscustomobject]@{
            Drive = "$($volume.DriveLetter):"
            FileSystem = $volume.FileSystem
            SizeGB = [math]::Round($volume.Size / 1GB, 1)
            FreeGB = [math]::Round($volume.SizeRemaining / 1GB, 1)
            FreePercent = $freePercent
        }
    }
)

$cpuLoad = @($cpu | Where-Object { $null -ne $_.LoadPercentage } | Select-Object -ExpandProperty LoadPercentage)
$averageCpuLoad = if ($cpuLoad.Count -gt 0) {
    [math]::Round(($cpuLoad | Measure-Object -Average).Average, 1)
} else {
    $null
}

$activePowerScheme = (& powercfg.exe /GetActiveScheme 2>&1 | Out-String).Trim()
$committedBytes = if ($memoryPerf) { [double]$memoryPerf.CommittedBytes } else { $null }
$commitLimit = if ($memoryPerf) { [double]$memoryPerf.CommitLimit } else { $null }
$commitPercent = if ($null -ne $committedBytes -and $null -ne $commitLimit -and $commitLimit -gt 0) {
    [math]::Round(($committedBytes / $commitLimit) * 100, 1)
} else {
    $null
}

$report = [ordered]@{
    Stage = $Stage
    Timestamp = (Get-Date).ToString('o')
    Computer = $env:COMPUTERNAME
    Windows = $os.Caption
    Build = $os.BuildNumber
    UptimeHours = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 2)
    LogicalProcessors = $computer.NumberOfLogicalProcessors
    TotalMemoryGB = [math]::Round($computer.TotalPhysicalMemory / 1GB, 1)
    FreeMemoryGB = [math]::Round(($os.FreePhysicalMemory * 1KB) / 1GB, 2)
    CommittedMemoryGB = if ($null -ne $committedBytes) { [math]::Round($committedBytes / 1GB, 2) } else { $null }
    CommitLimitGB = if ($null -ne $commitLimit) { [math]::Round($commitLimit / 1GB, 2) } else { $null }
    CommitPercent = $commitPercent
    MemoryCompressionEnabled = if ($mmAgent) { [bool]$mmAgent.MemoryCompression } else { $null }
    ApplicationLaunchPrefetching = if ($mmAgent) { [bool]$mmAgent.ApplicationLaunchPrefetching } else { $null }
    ApplicationPreLaunch = if ($mmAgent) { [bool]$mmAgent.ApplicationPreLaunch } else { $null }
    AutomaticManagedPagefile = [bool]$computer.AutomaticManagedPagefile
    PageFiles = @($pageFiles | Select-Object Name, AllocatedBaseSize, CurrentUsage, PeakUsage)
    CpuLoadPercent = $averageCpuLoad
    ProcessCount = $processes.Count
    SvchostProcessCount = @($processes | Where-Object Name -EQ 'svchost').Count
    RunningServiceCount = @($services | Where-Object State -EQ 'Running').Count
    AutomaticServiceCount = @($services | Where-Object StartMode -EQ 'Auto').Count
    StartupCommandCount = $startupCommands.Count
    ActivePowerScheme = $activePowerScheme
    Disk = [ordered]@{
        CurrentQueueLength = if ($diskPerf) { [double]$diskPerf.CurrentDiskQueueLength } else { $null }
        ReadsPerSec = if ($diskPerf) { [double]$diskPerf.DiskReadsPersec } else { $null }
        WritesPerSec = if ($diskPerf) { [double]$diskPerf.DiskWritesPersec } else { $null }
    }
    Defender = [ordered]@{
        AntivirusEnabled = if ($defender) { [bool]$defender.AntivirusEnabled } else { $null }
        RealTimeProtectionEnabled = if ($defender) { [bool]$defender.RealTimeProtectionEnabled } else { $null }
        ExclusionPathCount = if ($preferences) { @($preferences.ExclusionPath).Count } else { $null }
        ExclusionProcessCount = if ($preferences) { @($preferences.ExclusionProcess).Count } else { $null }
    }
    Volumes = $volumeData
    TopProcessesByMemory = $topProcesses
    Notes = 'Lightweight responsiveness snapshot. No synthetic disk write benchmark and no standby-list purge are performed.'
}

$fileName = "v4-benchmark-$Stage.json"
$path = Join-Path $reportDir $fileName
$report | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 $path

Write-Host "[OK] Windows responsiveness benchmark snapshot: $path" -ForegroundColor Green
Write-Host ("Processes={0} | svchost={1} | services={2} | free RAM={3} GB | commit={4}% | CPU={5}%" -f $report.ProcessCount, $report.SvchostProcessCount, $report.RunningServiceCount, $report.FreeMemoryGB, $report.CommitPercent, $report.CpuLoadPercent)
