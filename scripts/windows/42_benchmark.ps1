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

$topProcesses = @(
    $processes |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First 10 Name, Id,
            @{ Name = 'WorkingSetMB'; Expression = { [math]::Round($_.WorkingSet64 / 1MB, 1) } },
            @{ Name = 'CPUSeconds'; Expression = { if ($null -eq $_.CPU) { 0 } else { [math]::Round($_.CPU, 1) } } }
)

$volumeData = @(
    foreach ($volume in $volumes) {
        [pscustomobject]@{
            Drive = "$($volume.DriveLetter):"
            FileSystem = $volume.FileSystem
            SizeGB = [math]::Round($volume.Size / 1GB, 1)
            FreeGB = [math]::Round($volume.SizeRemaining / 1GB, 1)
        }
    }
)

$cpuLoad = @($cpu | Where-Object { $null -ne $_.LoadPercentage } | Select-Object -ExpandProperty LoadPercentage)
$averageCpuLoad = if ($cpuLoad.Count -gt 0) {
    [math]::Round(($cpuLoad | Measure-Object -Average).Average, 1)
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
    CpuLoadPercent = $averageCpuLoad
    ProcessCount = $processes.Count
    SvchostProcessCount = @($processes | Where-Object Name -EQ 'svchost').Count
    RunningServiceCount = @($services | Where-Object State -EQ 'Running').Count
    AutomaticServiceCount = @($services | Where-Object StartMode -EQ 'Auto').Count
    StartupCommandCount = $startupCommands.Count
    Defender = [ordered]@{
        AntivirusEnabled = if ($defender) { [bool]$defender.AntivirusEnabled } else { $null }
        RealTimeProtectionEnabled = if ($defender) { [bool]$defender.RealTimeProtectionEnabled } else { $null }
        ExclusionPathCount = if ($preferences) { @($preferences.ExclusionPath).Count } else { $null }
        ExclusionProcessCount = if ($preferences) { @($preferences.ExclusionProcess).Count } else { $null }
    }
    Volumes = $volumeData
    TopProcessesByMemory = $topProcesses
    Notes = 'Lightweight snapshot only. No synthetic disk write benchmark is performed.'
}

$fileName = "v4-benchmark-$Stage.json"
$path = Join-Path $reportDir $fileName
$report | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 $path

Write-Host "[OK] V4 benchmark snapshot: $path" -ForegroundColor Green
Write-Host ("Processes={0} | svchost={1} | running services={2} | free RAM={3} GB | CPU={4}%" -f $report.ProcessCount, $report.SvchostProcessCount, $report.RunningServiceCount, $report.FreeMemoryGB, $report.CpuLoadPercent)
