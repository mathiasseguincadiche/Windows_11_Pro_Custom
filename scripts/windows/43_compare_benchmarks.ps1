[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$reportDir = Join-Path $repoRoot 'reports\windows'
$beforePath = Join-Path $reportDir 'v4-benchmark-before.json'
$afterPath = Join-Path $reportDir 'v4-benchmark-after.json'
$comparisonPath = Join-Path $reportDir 'v4-benchmark-comparison.json'

if (-not (Test-Path $beforePath)) { throw "Missing benchmark: $beforePath" }
if (-not (Test-Path $afterPath)) { throw "Missing benchmark: $afterPath" }

$before = Get-Content -Raw $beforePath | ConvertFrom-Json
$after = Get-Content -Raw $afterPath | ConvertFrom-Json

function Get-Delta {
    param($BeforeValue, $AfterValue)
    if ($null -eq $BeforeValue -or $null -eq $AfterValue) { return $null }
    return [math]::Round(([double]$AfterValue - [double]$BeforeValue), 2)
}

$comparison = [ordered]@{
    GeneratedAt = (Get-Date).ToString('o')
    BeforeTimestamp = $before.Timestamp
    AfterTimestamp = $after.Timestamp
    ProcessCount = [ordered]@{
        Before = $before.ProcessCount
        After = $after.ProcessCount
        Delta = Get-Delta $before.ProcessCount $after.ProcessCount
    }
    SvchostProcessCount = [ordered]@{
        Before = $before.SvchostProcessCount
        After = $after.SvchostProcessCount
        Delta = Get-Delta $before.SvchostProcessCount $after.SvchostProcessCount
    }
    RunningServiceCount = [ordered]@{
        Before = $before.RunningServiceCount
        After = $after.RunningServiceCount
        Delta = Get-Delta $before.RunningServiceCount $after.RunningServiceCount
    }
    AutomaticServiceCount = [ordered]@{
        Before = $before.AutomaticServiceCount
        After = $after.AutomaticServiceCount
        Delta = Get-Delta $before.AutomaticServiceCount $after.AutomaticServiceCount
    }
    StartupCommandCount = [ordered]@{
        Before = $before.StartupCommandCount
        After = $after.StartupCommandCount
        Delta = Get-Delta $before.StartupCommandCount $after.StartupCommandCount
    }
    FreeMemoryGB = [ordered]@{
        Before = $before.FreeMemoryGB
        After = $after.FreeMemoryGB
        Delta = Get-Delta $before.FreeMemoryGB $after.FreeMemoryGB
    }
    CpuLoadPercent = [ordered]@{
        Before = $before.CpuLoadPercent
        After = $after.CpuLoadPercent
        Delta = Get-Delta $before.CpuLoadPercent $after.CpuLoadPercent
    }
    DefenderStillEnabled = [bool]($after.Defender.AntivirusEnabled -and $after.Defender.RealTimeProtectionEnabled)
    Interpretation = 'These snapshots are observational. Reboot, workload and background activity can affect deltas; they are not synthetic performance scores.'
}

$comparison | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 $comparisonPath
$comparison | ConvertTo-Json -Depth 8
Write-Host "[OK] V4 comparison written to $comparisonPath" -ForegroundColor Green
