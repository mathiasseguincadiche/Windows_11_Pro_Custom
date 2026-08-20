[CmdletBinding()]
param([switch]$RequireManualChecks)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$release = (Get-Content -Raw (Join-Path $repoRoot 'VERSION')).Trim()
if ($release -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION invalide: $release" }
$targetPath = Join-Path $repoRoot 'config\hardware\target.json'
$reportDir = Join-Path $repoRoot 'reports\hardware'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$target = Get-Content -Raw $targetPath | ConvertFrom-Json
if ([int]$target.schemaVersion -ne 1) { throw "SchemaVersion de cible matérielle non supporté: $($target.schemaVersion)" }
$checks = [ordered]@{}
$advisoryChecks = [ordered]@{}
$details = [ordered]@{}

$cpu = @(Get-CimInstance Win32_Processor); $primaryCpu = $cpu | Select-Object -First 1
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
$checks.MotherboardManufacturer = ([string]$board.Manufacturer -like "*$($target.motherboard.manufacturerContains)*")
$checks.MotherboardProduct = ([string]$board.Product -like "*$($target.motherboard.productContains)*")
$details.Motherboard = $board

$video = @(Get-CimInstance Win32_VideoController)
$arc = @($video | Where-Object { [string]$_.Name -match [string]$target.gpu.nameRegex })
$checks.ArcB580 = ($arc.Count -gt 0)
$advisoryChecks.ArcDriver = ($arc.Count -gt 0 -and @($arc | Where-Object { -not $_.DriverVersion }).Count -eq 0)
$displayMatch = @($video | Where-Object { [int]$_.CurrentHorizontalResolution -eq [int]$target.display.width -and [int]$_.CurrentVerticalResolution -eq [int]$target.display.height -and [int]$_.CurrentRefreshRate -ge [int]$target.display.minimumRefreshHz })
$advisoryChecks.Display1440p240 = ($displayMatch.Count -gt 0)
$details.Video = $video

$physicalDisks = @(Get-PhysicalDisk)
$t705 = @($physicalDisks | Where-Object { (([string]$_.FriendlyName + ' ' + [string]$_.Model) -match [string]$target.storage.modelRegex) })
$checks.T705Count = ($t705.Count -ge [int]$target.storage.minimumCount)
$checks.T705Healthy = ($t705.Count -ge [int]$target.storage.minimumCount -and @($t705 | Where-Object { [string]$_.HealthStatus -ne 'Healthy' }).Count -eq 0)
$details.T705 = $t705 | Select-Object FriendlyName, Model, SerialNumber, MediaType, BusType, HealthStatus, OperationalStatus, Size
$checks.C_NTFS = ((Get-Volume -DriveLetter C).FileSystem -eq [string]$target.storage.filesystem)
$checks.E_NTFS = ((Get-Volume -DriveLetter E).FileSystem -eq [string]$target.storage.filesystem)

$systemPartition = Get-Partition -DriveLetter C; $systemDisk = Get-Disk -Number $systemPartition.DiskNumber
$checks.SystemDiskGPT = ([string]$systemDisk.PartitionStyle -eq 'GPT')
$details.SystemDisk = $systemDisk | Select-Object Number, FriendlyName, BusType, PartitionStyle
$secureBoot = $false; try { $secureBoot = [bool](Confirm-SecureBootUEFI -ErrorAction Stop) } catch {}; $checks.SecureBoot = $secureBoot
$tpmReady = $false
try { $tpm=Get-Tpm -ErrorAction Stop; $tpmReady=[bool]($tpm.TpmPresent -and $tpm.TpmReady -and $tpm.TpmEnabled); $details.TPM=$tpm | Select-Object TpmPresent,TpmReady,TpmEnabled,TpmActivated } catch { $details.TPM=$null }
$checks.TPM = $tpmReady
$powerScheme = (& powercfg.exe /GetActiveScheme 2>&1 | Out-String).Trim(); $checks.BalancedPowerPlan = ($powerScheme -match [regex]::Escape([string]$target.power.balancedSchemeGuid)); $details.ActivePowerScheme=$powerScheme
$trim = (& fsutil.exe behavior query DisableDeleteNotify 2>&1 | Out-String).Trim(); $checks.TrimEnabled=($trim -match 'DisableDeleteNotify\s*=\s*0'); $details.TrimStatus=$trim

try { & "$repoRoot\scripts\windows\52_hardware_symbiosis.ps1" -Mode Verify; $checks.HardwareSymbiosis=$true; $details.HardwareSymbiosisReport='reports\hardware\hardware-symbiosis.json' }
catch { $checks.HardwareSymbiosis=$false; $details.HardwareSymbiosisError=$_.Exception.Message; $details.HardwareSymbiosisReport='reports\hardware\hardware-symbiosis.json' }

if ($RequireManualChecks) {
    try {
        & "$repoRoot\scripts\windows\51_hardware_manual_checks.ps1" -Mode Verify -Strict
        $advisoryChecks.ManualChecks = $true
        $details.ManualChecks = 'Toutes les preuves manuelles strictes sont confirmees.'
    } catch {
        $advisoryChecks.ManualChecks = $false
        $details.ManualChecksError = $_.Exception.Message
        $details.ManualChecks = 'Preuves manuelles incompletes: information de conformite, non bloquante pour Installation complete.'
    }
} else {
    $details.ManualChecks='Not required in this pass. Use -RequireManualChecks to surface the manual-evidence advisory.'
}

$report = [ordered]@{ Release=$release; SchemaVersion=2; Timestamp=(Get-Date).ToString('o'); Checks=$checks; AdvisoryChecks=$advisoryChecks; Details=$details }
$reportPath = Join-Path $reportDir 'validation-hardware.json'
$report | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 $reportPath
$failed = @($checks.GetEnumerator() | Where-Object { -not [bool]$_.Value })
$advisories = @($advisoryChecks.GetEnumerator() | Where-Object { -not [bool]$_.Value })
foreach ($check in $checks.GetEnumerator()) { $state=if ([bool]$check.Value) {'OK'} else {'KO'}; Write-Host ("[{0}] {1}" -f $state,$check.Key) -ForegroundColor $(if ([bool]$check.Value) {'Green'} else {'Red'}) }
foreach ($check in $advisoryChecks.GetEnumerator()) { $state=if ([bool]$check.Value) {'INFO OK'} else {'AVERTISSEMENT'}; Write-Host ("[{0}] {1} | non bloquant" -f $state,$check.Key) -ForegroundColor $(if ([bool]$check.Value) {'Green'} else {'Yellow'}) }
Write-Host "Rapport détaillé: $reportPath" -ForegroundColor DarkGray
if ($failed.Count -gt 0) { throw "Qualification matérielle critique échouée: $($failed.Count) contrôle(s). Voir $reportPath" }
if ($advisories.Count -gt 0) { Write-Host "VERDICT: HARDWARE READY — $($advisories.Count) avertissement(s) non bloquant(s)." -ForegroundColor Yellow }
else { Write-Host 'VERDICT: HARDWARE READY' -ForegroundColor Green }
