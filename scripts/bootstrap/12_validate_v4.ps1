[CmdletBinding()]
param(
    [ValidateSet('standard', 'privacy', 'gaming', 'optional')]
    [string[]]$OptimizationProfiles = @('standard')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$reportDir = Join-Path $repoRoot 'reports'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

$checks = [ordered]@{}
$details = [ordered]@{}

$defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
$checks.DefenderAntivirusEnabled = [bool]($defender -and $defender.AntivirusEnabled)
$checks.DefenderRealtimeEnabled = [bool]($defender -and $defender.RealTimeProtectionEnabled)
$checks.C_NTFS = ((Get-Volume -DriveLetter C).FileSystem -eq 'NTFS')
$checks.D_NTFS = ((Get-Volume -DriveLetter D).FileSystem -eq 'NTFS')

$forbiddenServices = @(
    'SharedAccess',
    'StorSvc',
    'wuauserv',
    'WinDefend',
    'mpssvc',
    'vmcompute',
    'hns'
)

$forbiddenRegistryFragments = @(
    '\Windows Defender',
    '\WindowsUpdate',
    '\WindowsFirewall'
)

$profileResults = @()
foreach ($profile in $OptimizationProfiles) {
    $profilePath = Join-Path $repoRoot "config\windows\v4\$profile.json"
    if (-not (Test-Path $profilePath)) {
        $profileResults += [pscustomobject]@{ Profile = $profile; Verified = $false; Reason = 'Profile file missing' }
        continue
    }

    $config = Get-Content -Raw $profilePath | ConvertFrom-Json
    $unsafeServices = @($config.services | Where-Object { $_.name -in $forbiddenServices } | Select-Object -ExpandProperty name)
    $unsafeRegistry = @(
        foreach ($entry in @($config.registry)) {
            foreach ($fragment in $forbiddenRegistryFragments) {
                if ([string]$entry.path -like "*$fragment*") {
                    $entry.path
                    break
                }
            }
        }
    )

    if ($unsafeServices.Count -gt 0 -or $unsafeRegistry.Count -gt 0) {
        $profileResults += [pscustomobject]@{
            Profile = $profile
            Verified = $false
            Reason = "Unsafe target in profile: services=$($unsafeServices -join ',') registry=$($unsafeRegistry -join ',')"
        }
        continue
    }

    try {
        & "$repoRoot\scripts\windows\40_v4_optimize.ps1" -Mode Verify -Profile $profile
        $profileResults += [pscustomobject]@{ Profile = $profile; Verified = $true; Reason = 'OK' }
    } catch {
        $profileResults += [pscustomobject]@{ Profile = $profile; Verified = $false; Reason = $_.Exception.Message }
    }
}

$checks.ProfilesVerified = (@($profileResults | Where-Object { -not $_.Verified }).Count -eq 0)
$checks.BenchmarkBeforeExists = Test-Path (Join-Path $repoRoot 'reports\windows\v4-benchmark-before.json')
$checks.BenchmarkAfterExists = Test-Path (Join-Path $repoRoot 'reports\windows\v4-benchmark-after.json')
$checks.BenchmarkComparisonExists = Test-Path (Join-Path $repoRoot 'reports\windows\v4-benchmark-comparison.json')

$details.Profiles = $profileResults
$details.ForbiddenServices = $forbiddenServices
$details.OptimizationProfiles = $OptimizationProfiles

$report = [ordered]@{
    Version = 'V4'
    Timestamp = (Get-Date).ToString('o')
    Checks = $checks
    Details = $details
}

$reportPath = Join-Path $reportDir 'validation-v4.json'
$report | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 $reportPath

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value })
foreach ($check in $checks.GetEnumerator()) {
    $state = if ($check.Value) { 'OK' } else { 'KO' }
    Write-Host ("[{0}] {1}" -f $state, $check.Key)
}

if ($failed.Count -gt 0) {
    throw "V4 qualification failed: $($failed.Count) check(s). See $reportPath"
}

Write-Host 'VERDICT: V4 WINDOWS OPTIMIZATION READY' -ForegroundColor Green
