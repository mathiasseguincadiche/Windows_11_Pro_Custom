[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$release = (Get-Content -Raw (Join-Path $repoRoot 'VERSION')).Trim()
if ($release -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION invalide: $release" }
$reportDir = Join-Path $repoRoot 'reports\windows'
$beforePath = Join-Path $reportDir 'benchmark-before.json'
$afterPath = Join-Path $reportDir 'benchmark-after.json'
$comparisonPath = Join-Path $reportDir 'benchmark-comparison.json'
$legacyBeforePath = Join-Path $reportDir 'v4-benchmark-before.json'
$legacyAfterPath = Join-Path $reportDir 'v4-benchmark-after.json'

if (-not (Test-Path $beforePath) -and (Test-Path $legacyBeforePath)) { $beforePath = $legacyBeforePath }
if (-not (Test-Path $afterPath) -and (Test-Path $legacyAfterPath)) { $afterPath = $legacyAfterPath }
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
    Release = $release
    SchemaVersion = 1
    GeneratedAt = (Get-Date).ToString('o')
    BeforeTimestamp = $before.Timestamp
    AfterTimestamp = $after.Timestamp
    ProcessCount = [ordered]@{ Before=$before.ProcessCount; After=$after.ProcessCount; Delta=(Get-Delta $before.ProcessCount $after.ProcessCount) }
    SvchostProcessCount = [ordered]@{ Before=$before.SvchostProcessCount; After=$after.SvchostProcessCount; Delta=(Get-Delta $before.SvchostProcessCount $after.SvchostProcessCount) }
    RunningServiceCount = [ordered]@{ Before=$before.RunningServiceCount; After=$after.RunningServiceCount; Delta=(Get-Delta $before.RunningServiceCount $after.RunningServiceCount) }
    AutomaticServiceCount = [ordered]@{ Before=$before.AutomaticServiceCount; After=$after.AutomaticServiceCount; Delta=(Get-Delta $before.AutomaticServiceCount $after.AutomaticServiceCount) }
    StartupCommandCount = [ordered]@{ Before=$before.StartupCommandCount; After=$after.StartupCommandCount; Delta=(Get-Delta $before.StartupCommandCount $after.StartupCommandCount) }
    FreeMemoryGB = [ordered]@{ Before=$before.FreeMemoryGB; After=$after.FreeMemoryGB; Delta=(Get-Delta $before.FreeMemoryGB $after.FreeMemoryGB) }
    CommittedMemoryGB = [ordered]@{ Before=$before.CommittedMemoryGB; After=$after.CommittedMemoryGB; Delta=(Get-Delta $before.CommittedMemoryGB $after.CommittedMemoryGB) }
    CommitPercent = [ordered]@{ Before=$before.CommitPercent; After=$after.CommitPercent; Delta=(Get-Delta $before.CommitPercent $after.CommitPercent) }
    CpuLoadPercent = [ordered]@{ Before=$before.CpuLoadPercent; After=$after.CpuLoadPercent; Delta=(Get-Delta $before.CpuLoadPercent $after.CpuLoadPercent) }
    DiskQueueLength = [ordered]@{ Before=$before.Disk.CurrentQueueLength; After=$after.Disk.CurrentQueueLength; Delta=(Get-Delta $before.Disk.CurrentQueueLength $after.Disk.CurrentQueueLength) }
    MemoryCompressionEnabledAfter = $after.MemoryCompressionEnabled
    ApplicationLaunchPrefetchingAfter = $after.ApplicationLaunchPrefetching
    ApplicationPreLaunchAfter = $after.ApplicationPreLaunch
    AutomaticManagedPagefileAfter = $after.AutomaticManagedPagefile
    ActivePowerSchemeAfter = $after.ActivePowerScheme
    DefenderStillEnabled = [bool]($after.Defender.AntivirusEnabled -and $after.Defender.RealTimeProtectionEnabled)
    Interpretation = 'Snapshots are observational. Reboot, workload, cache warm-up and background activity can affect deltas. No synthetic disk writes or RAM purges are used.'
}

$comparison | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 $comparisonPath
$comparison | ConvertTo-Json -Depth 8
Write-Host "[OK] Windows responsiveness comparison written to $comparisonPath" -ForegroundColor Green
