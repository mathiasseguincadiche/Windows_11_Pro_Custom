[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$reportDir = Join-Path $repoRoot 'reports\defender'
$trace = Join-Path $reportDir 'Defender-scans.etl'
if (-not (Test-Path $trace)) { throw 'Trace absente. Lancez 01_record.ps1 auparavant.' }

$raw = Get-MpPerformanceReport -Path $trace -TopFiles 20 -TopProcesses 20 -TopPaths 20 -TopExtensions 20 -Raw
$raw | ConvertTo-Json -Depth 12 | Set-Content -Encoding utf8 (Join-Path $reportDir 'performance-report.json')
Get-MpPerformanceReport -Path $trace -TopFiles 10 -TopProcesses 10 -TopPaths 10 -TopExtensions 10
