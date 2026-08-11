[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$reportDir = Join-Path $repoRoot 'reports\defender'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

Get-MpComputerStatus | Select-Object AntivirusEnabled, RealTimeProtectionEnabled, BehaviorMonitorEnabled, IoavProtectionEnabled, AntivirusSignatureVersion, AntivirusSignatureLastUpdated |
    ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $reportDir 'status.json')

Get-MpPreference | Select-Object ExclusionPath, ExclusionProcess, ExclusionExtension, DisableRealtimeMonitoring |
    ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 (Join-Path $reportDir 'preferences.json')

Write-Host '[OK] Audit Defender enregistre dans reports\defender.' -ForegroundColor Green
