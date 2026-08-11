[CmdletBinding()]
param(
    [ValidateRange(10, 600)]
    [int]$Seconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$reportDir = Join-Path $repoRoot 'reports\defender'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$trace = Join-Path $reportDir 'Defender-scans.etl'

Write-Host "Capture Defender pendant $Seconds secondes. Reproduisez le workload DevOps reel." -ForegroundColor Cyan
New-MpPerformanceRecording -RecordTo $trace -Seconds $Seconds
Write-Host "[OK] Trace: $trace" -ForegroundColor Green
