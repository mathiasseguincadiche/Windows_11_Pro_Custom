[CmdletBinding()]
param(
    [switch]$RequireManualChecks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$targetPath = Join-Path $repoRoot 'config\hardware\target-v5.json'
$reportDir = Join-Path $repoRoot 'reports\hardware'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$target = Get-Content -Raw $targetPath | ConvertFrom-Json

$checks = [ordered]@{}
$details = [ordered]@{}

$cpu = @(Get-CimInstance Win32_Processor)
$primaryCpu = $cpu | Select-Object -First 1
$checks.CpuModel = [bool]($primaryCpu.Name -like "*$($target.cpu.nameContains)*")
$checks.CpuCores = ([int]$primaryCpu.NumberOfCores -eq [int]$target.cpu.cores)
$checks.CpuThreads = ([int]$primaryCpu.NumberOfLogicalProcessors -eq [int]$target.cpu.threads)
$checks.VirtualizationFirmware = [bool]$primaryCpu.VirtualizationFirmwareEnabled
$details.CPU = $primaryCpu

$memory = @(Get-CimInstance Win32_PhysicalMemory)
$totalMemory = ($memory | Measure-Object -Property Capacity -Sum).Sum
$memorySpeedFailures = @($memory | Where-Object { [int]$_.ConfiguredClockSpeed -lt [int]$target.memory.targetConfiguredClockMHz })
$checks.MemoryCapacity = ([int64]$totalMemory -ge [int64]$target.memory.minimumBytes)
$checks.MemoryConfigured6000 = ($memory.Count -gt 0 -and $memorySpeedFailures.Count -eq 0)
$details.Memory = $memory

$board = Get-CimInstance Win32_BaseBoard | Select-Object -First 1
$checks.Motherboard = ([string]$board.Product -like "*$($target.motherboard.productContains)*")
$details.Motherboard = $board

$video = @(Get-CimInstance Win32_VideoController)
$arc = @($video | Where-Object { [string]$_.Name -match [string]$target.gpu.nameRegex })
$checks.ArcB580 = ($arc.Count -gt 0)
$checks.ArcDriver = ($arc.Count -gt 0 -and @($arc | Where-Object { -not $_.DriverVersion }).Count -eq 0)
$displayMatch = @($video | Where-Object {
    [int]$_.CurrentHorizontalResolution -eq [int]$target.display.width -and
    [int]$_.CurrentVerticalResolution -eq [int]$target.display.height -and
    [int]$_.CurrentRefreshRate -ge [int]$target.display.minimumRefreshHz
})
$checks.Display1440p240 = ($displayMatch.Count -gt 0)
$details.Video = $video

$physicalDisks = @(Get-PhysicalDisk)
$t705 = @($physicalDisks | Where-Object {
    (([string]$_.FriendlyName + ' ' + [string]$_.Model) -match [string]$target.storage.modelRegex)
})
$checks.T705Count = ($t705.Count -ge [int]$target.storage.minimumCount)
$checks.T705Healthy = ($t705.Count -ge [int]$target.storage.minimumCount -and @($t705 | Where-Object { [string]$_.HealthStatus -ne 'Healthy' }).Count -eq 0)
$details.T705 = $t705 | Select-Object FriendlyName, Model, SerialNumber, MediaType, BusType, HealthStatus, OperationalStatus, Size

$checks.C_NTFS = ((Get-Volume -DriveLetter C).FileSystem -eq [string]$target.storage.filesystem)
$checks.D_NTFS = ((Get-Volume -DriveLetter D).FileSystem -eq [string]$target.storage.filesystem)

$systemPartition = Get-Partition -DriveLetter C
$systemDisk = Get-Disk -Number $systemPartition.DiskNumber
$checks.SystemDiskGPT = ([string]$systemDisk.PartitionStyle -eq 'GPT')
$details.SystemDisk = $systemDisk | Select-Object Number, FriendlyName, BusType, PartitionStyle

$secureBoot = $false
try {
    $secureBoot = [bool](Confirm-SecureBootUEFI -ErrorAction Stop)
} catch {
    $secureBoot = $false
}
$checks.SecureBoot = $secureBoot

$tpmReady = $false
try {
    $tpm = Get-Tpm -ErrorAction Stop
    $tpmReady = [bool]($tpm.TpmPresent -and $tpm.TpmReady -and $tpm.TpmEnabled)
    $details.TPM = $tpm | Select-Object TpmPresent, TpmReady, TpmEnabled, TpmActivated
} catch {
    $details.TPM = $null
}
$checks.TPM = $tpmReady

$powerScheme = (& powercfg.exe /GetActiveScheme 2>&1 | Out-String).Trim()
$checks.BalancedPowerPlan = ($powerScheme -match [regex]::Escape([string]$target.power.balancedSchemeGuid))
$details.ActivePowerScheme = $powerScheme

$trim = (& fsutil.exe behavior query DisableDeleteNotify 2>&1 | Out-String).Trim()
$checks.TrimEnabled = ($trim -match 'DisableDeleteNotify\s*=\s*0')
$details.TrimStatus = $trim

try {
    & "$repoRoot\scripts\windows\52_hardware_symbiosis.ps1" -Mode Verify
    $checks.HardwareSymbiosis = $true
    $details.HardwareSymbiosisReport = 'reports\hardware\hardware-symbiosis-v5.json'
} catch {
    $checks.HardwareSymbiosis = $false
    $details.HardwareSymbiosisError = $_.Exception.Message
    $details.HardwareSymbiosisReport = 'reports\hardware\hardware-symbiosis-v5.json'
}

if ($RequireManualChecks) {
    try {
        & "$repoRoot\scripts\windows\51_hardware_manual_checks.ps1" -Mode Verify
        $checks.ManualChecks = $true
    } catch {
        $checks.ManualChecks = $false
        $details.ManualChecksError = $_.Exception.Message
    }
} else {
    $details.ManualChecks = 'Not required in this pass. Use -RequireManualChecks for final hardware qualification.'
}

$report = [ordered]@{
    Version = 'V5'
    Timestamp = (Get-Date).ToString('o')
    Checks = $checks
    Details = $details
}

$reportPath = Join-Path $reportDir 'validation-hardware-v5.json'
$report | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 $reportPath

$failed = @($checks.GetEnumerator() | Where-Object { -not [bool]$_.Value })
foreach ($check in $checks.GetEnumerator()) {
    $state = if ([bool]$check.Value) { 'OK' } else { 'KO' }
    Write-Host ("[{0}] {1}" -f $state, $check.Key)
}

if ($failed.Count -gt 0) {
    throw "V5 hardware qualification failed: $($failed.Count) check(s). See $reportPath"
}

Write-Host 'VERDICT: V5 HARDWARE READY' -ForegroundColor Green
