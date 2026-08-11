[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$reportDir = Join-Path $repoRoot 'reports'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

$status = Get-MpComputerStatus
$preferences = Get-MpPreference

[ordered]@{
    Timestamp = (Get-Date).ToString('o')
    AntivirusEnabled = $status.AntivirusEnabled
    RealTimeProtectionEnabled = $status.RealTimeProtectionEnabled
    BehaviorMonitorEnabled = $status.BehaviorMonitorEnabled
    IoavProtectionEnabled = $status.IoavProtectionEnabled
    ExclusionPath = @($preferences.ExclusionPath)
    ExclusionProcess = @($preferences.ExclusionProcess)
    ExclusionExtension = @($preferences.ExclusionExtension)
} | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 (Join-Path $reportDir 'defender-baseline.json')

if (-not $status.RealTimeProtectionEnabled) {
    Write-Warning 'La protection temps reel Defender est desactivee.'
} else {
    Write-Host '[OK] Defender actif; aucune exclusion ajoutee par le bootstrap.' -ForegroundColor Green
}
