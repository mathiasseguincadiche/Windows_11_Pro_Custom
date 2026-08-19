[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Verify', 'Rollback')]
    [string]$Mode = 'Audit'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$release = (Get-Content -Raw (Join-Path $repoRoot 'VERSION')).Trim()
if ($release -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION invalide: $release" }
$policyPath = Join-Path $repoRoot 'config\windows\responsiveness.json'
$stateDir = Join-Path $repoRoot 'state\windows-responsiveness'
$statePath = Join-Path $stateDir 'responsiveness.before.json'
$legacyStatePath = Join-Path $repoRoot 'state\windows-v8\responsiveness.before.json'
$reportDir = Join-Path $repoRoot 'reports\windows'
$reportPath = Join-Path $reportDir 'responsiveness.json'
$policy = Get-Content -Raw $policyPath | ConvertFrom-Json
if ([int]$policy.schemaVersion -ne 1) { throw "SchemaVersion de politique de réactivité non supporté: $($policy.schemaVersion)" }

if (-not ('Windows11ProCustom.PowerModeNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Windows11ProCustom {
    public static class PowerModeNative {
        [DllImport("powrprof.dll", SetLastError=true)] public static extern uint PowerGetUserConfiguredACPowerMode(out Guid powerModeGuid);
        [DllImport("powrprof.dll", SetLastError=true)] public static extern uint PowerSetUserConfiguredACPowerMode(ref Guid powerModeGuid);
    }
    [StructLayout(LayoutKind.Sequential)] public struct AnimationInfo { public uint cbSize; public int iMinAnimate; }
    public static class UiNative {
        [DllImport("user32.dll", SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool SystemParametersInfo(uint action, uint param, ref AnimationInfo value, uint flags);
        [DllImport("user32.dll", SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool SystemParametersInfo(uint action, uint param, ref bool value, uint flags);
    }
}
'@
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'PowerShell administrateur requis pour Apply/Rollback de la réactivité Windows.' }
}
function Get-ActivePowerSchemeGuid {
    $text = (& powercfg.exe /GetActiveScheme 2>&1 | Out-String)
    $match = [regex]::Match($text, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
    if ($match.Success) { return $match.Value.ToLowerInvariant() }
    return $null
}
function Get-AcPowerModeGuid {
    $guid = [guid]::Empty
    try { if ([Windows11ProCustom.PowerModeNative]::PowerGetUserConfiguredACPowerMode([ref]$guid) -eq 0) { return $guid.ToString().ToLowerInvariant() } } catch {}
    return $null
}
function Set-AcPowerModeGuid {
    param([Parameter(Mandatory)][string]$Guid)
    $value = [guid]$Guid
    $result = [Windows11ProCustom.PowerModeNative]::PowerSetUserConfiguredACPowerMode([ref]$value)
    if ($result -ne 0) { throw "PowerSetUserConfiguredACPowerMode failed with code $result." }
}
function Get-UiAnimationState {
    $info = [Windows11ProCustom.AnimationInfo]::new()
    $info.cbSize = [Runtime.InteropServices.Marshal]::SizeOf([type][Windows11ProCustom.AnimationInfo])
    $animationOk = [Windows11ProCustom.UiNative]::SystemParametersInfo(0x0048, $info.cbSize, [ref]$info, 0)
    $clientArea = $true
    $clientOk = [Windows11ProCustom.UiNative]::SystemParametersInfo(0x1042, 0, [ref]$clientArea, 0)
    [pscustomobject]@{ MinimizeRestoreAnimation=if ($animationOk) { [bool]($info.iMinAnimate -ne 0) } else { $null }; ClientAreaAnimations=if ($clientOk) { [bool]$clientArea } else { $null } }
}
function Set-UiAnimationState {
    param([Parameter(Mandatory)][bool]$MinimizeRestoreAnimation,[Parameter(Mandatory)][bool]$ClientAreaAnimations)
    $flags = 0x0001 -bor 0x0002
    $info = [Windows11ProCustom.AnimationInfo]::new(); $info.cbSize = [Runtime.InteropServices.Marshal]::SizeOf([type][Windows11ProCustom.AnimationInfo]); $info.iMinAnimate = if ($MinimizeRestoreAnimation) { 1 } else { 0 }
    if (-not [Windows11ProCustom.UiNative]::SystemParametersInfo(0x0049, $info.cbSize, [ref]$info, $flags)) { throw 'Failed to update minimize/restore animation state.' }
    $clientArea = $ClientAreaAnimations
    if (-not [Windows11ProCustom.UiNative]::SystemParametersInfo(0x1043, 0, [ref]$clientArea, $flags)) { throw 'Failed to update client-area animation state.' }
}
function Get-MemoryManagerState {
    try {
        $mm = Get-MMAgent -ErrorAction Stop
        [pscustomobject]@{ MemoryCompression=[bool]$mm.MemoryCompression; ApplicationLaunchPrefetching=[bool]$mm.ApplicationLaunchPrefetching; ApplicationPreLaunch=[bool]$mm.ApplicationPreLaunch; PageCombining=[bool]$mm.PageCombining }
    } catch { [pscustomobject]@{ MemoryCompression=$null; ApplicationLaunchPrefetching=$null; ApplicationPreLaunch=$null; PageCombining=$null } }
}
function Set-MemoryFeatureState {
    param([Parameter(Mandatory)][ValidateSet('MemoryCompression','ApplicationLaunchPrefetching','ApplicationPreLaunch')][string]$Feature,[Parameter(Mandatory)][bool]$Enabled)
    switch ($Feature) {
        'MemoryCompression' { if ($Enabled) { Enable-MMAgent -MemoryCompression } else { Disable-MMAgent -MemoryCompression } }
        'ApplicationLaunchPrefetching' { if ($Enabled) { Enable-MMAgent -ApplicationLaunchPrefetching } else { Disable-MMAgent -ApplicationLaunchPrefetching } }
        'ApplicationPreLaunch' { if ($Enabled) { Enable-MMAgent -ApplicationPreLaunch } else { Disable-MMAgent -ApplicationPreLaunch } }
    }
}
function Get-PageFileState {
    $computer = Get-CimInstance Win32_ComputerSystem | Select-Object -First 1
    $pagingFiles = $null; try { $pagingFiles = @(Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name PagingFiles -ErrorAction Stop) } catch {}
    $crashDumpEnabled = $null; try { $crashDumpEnabled = [int](Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name CrashDumpEnabled -ErrorAction Stop) } catch {}
    [pscustomobject]@{ AutomaticManagedPagefile=[bool]$computer.AutomaticManagedPagefile; PagingFiles=$pagingFiles; CrashDumpEnabled=$crashDumpEnabled }
}
function Get-StorageState {
    $trimText = (& fsutil.exe behavior query DisableDeleteNotify 2>&1 | Out-String).Trim()
    $scheduledOptimize = $null
    try { $task = Get-ScheduledTask -TaskPath '\Microsoft\Windows\Defrag\' -TaskName 'ScheduledDefrag' -ErrorAction Stop; $scheduledOptimize = ($task.State -ne 'Disabled') } catch {}
    $volumes = @(Get-Volume | Where-Object DriveLetter -In @('C','E') | ForEach-Object { [pscustomobject]@{ Drive="$($_.DriveLetter):"; FileSystem=$_.FileSystem; HealthStatus=[string]$_.HealthStatus; FreeGB=[math]::Round($_.SizeRemaining/1GB,1); FreePercent=if ($_.Size -gt 0) { [math]::Round(($_.SizeRemaining/$_.Size)*100,1) } else { $null } } })
    [pscustomobject]@{ TrimEnabled=($trimText -match 'DisableDeleteNotify\s*=\s*0'); TrimRaw=$trimText; ScheduledOptimizeEnabled=$scheduledOptimize; Volumes=$volumes }
}
function Get-StartupInventory { @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue | Select-Object Name, Command, Location, User) }
function Get-CurrentState {
    [pscustomobject]@{ Timestamp=(Get-Date).ToString('o'); Memory=Get-MemoryManagerState; PageFile=Get-PageFileState; ActivePowerSchemeGuid=Get-ActivePowerSchemeGuid; AcPowerModeGuid=Get-AcPowerModeGuid; UI=Get-UiAnimationState; Storage=Get-StorageState; Startup=Get-StartupInventory }
}
function Get-InitialStatePath {
    if (Test-Path -LiteralPath $statePath) { return $statePath }
    if (Test-Path -LiteralPath $legacyStatePath) { Write-Host "[COMPAT] État initial historique utilisé: $legacyStatePath" -ForegroundColor DarkGray; return $legacyStatePath }
    return $statePath
}
function Write-Report {
    param([Parameter(Mandatory)]$State)
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
    $warnings = [System.Collections.Generic.List[string]]::new()
    if ($State.PageFile.AutomaticManagedPagefile -ne $true) { $warnings.Add('Pagefile is not system-managed.') }
    if ($State.PageFile.CrashDumpEnabled -ne [int]$policy.pageFile.crashDumpEnabled) { $warnings.Add('Automatic Memory Dump is not configured.') }
    if ($State.Memory.MemoryCompression -eq $false) { $warnings.Add('Memory Compression is disabled.') }
    if ($State.Memory.ApplicationLaunchPrefetching -eq $false) { $warnings.Add('Application launch prefetching is disabled.') }
    if ($State.Memory.ApplicationPreLaunch -eq $false) { $warnings.Add('Application prelaunch is disabled.') }
    if ($State.ActivePowerSchemeGuid -and $State.ActivePowerSchemeGuid -ne [string]$policy.power.activeSchemeGuid) { $warnings.Add('Active power scheme is not Balanced.') }
    if ([string]$policy.power.acPowerModeManagement -eq 'enforce' -and $State.AcPowerModeGuid -and $State.AcPowerModeGuid -ne [string]$policy.power.acPowerModeGuid) { $warnings.Add('AC power mode does not match the managed policy.') }
    if ($State.Storage.TrimEnabled -eq $false) { $warnings.Add('TRIM is disabled.') }
    if ($State.Storage.ScheduledOptimizeEnabled -eq $false) { $warnings.Add('Windows Scheduled Optimize is disabled.') }
    foreach ($volume in $State.Storage.Volumes) { if ($null -ne $volume.FreePercent -and $volume.FreePercent -lt [double]$policy.storage.minimumFreePercentWarning) { $warnings.Add("$($volume.Drive) free space is below $($policy.storage.minimumFreePercentWarning) percent.") } }
    $report = [ordered]@{ Release=$release; SchemaVersion=1; Mode=$Mode; PolicyReviewedAt=[string]$policy.reviewedAt; AcPowerModeManagement=[string]$policy.power.acPowerModeManagement; State=$State; StartupAutomaticDisable=[bool]$policy.startup.automaticDisable; BackgroundGlobalDisable=[bool]$policy.backgroundApps.globalDisable; Warnings=$warnings.ToArray() }
    $report | ConvertTo-Json -Depth 12 | Set-Content -Encoding utf8 $reportPath
    foreach ($warning in $warnings) { Write-Warning $warning }
    Write-Host "[INFO] Rapport de réactivité Windows: $reportPath"
}

if ($Mode -eq 'Apply') {
    Assert-Administrator
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    $initialStatePath = Get-InitialStatePath
    if (-not (Test-Path -LiteralPath $initialStatePath)) { Get-CurrentState | ConvertTo-Json -Depth 12 | Set-Content -Encoding utf8 $statePath; Write-Host "[OK] État initial de réactivité enregistré: $statePath" }
    else { Write-Host "[DÉJÀ OK] État initial préservé: $initialStatePath" -ForegroundColor Green }

    $mm = Get-MemoryManagerState
    if ($mm.MemoryCompression -eq $false) { Enable-MMAgent -MemoryCompression }
    if ($mm.ApplicationLaunchPrefetching -eq $false) { Enable-MMAgent -ApplicationLaunchPrefetching }
    if ($mm.ApplicationPreLaunch -eq $false) { Enable-MMAgent -ApplicationPreLaunch }
    $computer = Get-CimInstance Win32_ComputerSystem | Select-Object -First 1
    if (-not [bool]$computer.AutomaticManagedPagefile) { Set-CimInstance -InputObject $computer -Property @{ AutomaticManagedPagefile=$true } | Out-Null }
    if (-not (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl')) { New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Force | Out-Null }
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name CrashDumpEnabled -PropertyType DWord -Value ([int]$policy.pageFile.crashDumpEnabled) -Force | Out-Null
    if ((Get-ActivePowerSchemeGuid) -ne [string]$policy.power.activeSchemeGuid) { & powercfg.exe /SetActive ([string]$policy.power.activeSchemeGuid) | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'Failed to activate Balanced power scheme.' } }
    if ([string]$policy.power.acPowerModeManagement -eq 'enforce') { if (Get-AcPowerModeGuid) { Set-AcPowerModeGuid -Guid ([string]$policy.power.acPowerModeGuid) } else { Write-Warning 'Windows AC power-mode API unavailable; the managed AC power mode could not be applied.' } }
    else { Write-Host '[INFO] Mode de puissance secteur observé uniquement; le réglage Windows actuel est conservé.' }
    Set-UiAnimationState -MinimizeRestoreAnimation ([bool]$policy.ui.minimizeRestoreAnimation) -ClientAreaAnimations ([bool]$policy.ui.clientAreaAnimations)
    Write-Host '[INFO] Les applications de démarrage sont uniquement inventoriées; aucune n’est désactivée automatiquement.'
}
elseif ($Mode -eq 'Rollback') {
    Assert-Administrator
    $initialStatePath = Get-InitialStatePath
    if (-not (Test-Path -LiteralPath $initialStatePath)) { throw "État initial de réactivité absent: $initialStatePath" }
    $before = Get-Content -Raw $initialStatePath | ConvertFrom-Json
    $mmNow = Get-MemoryManagerState
    foreach ($feature in @('MemoryCompression','ApplicationLaunchPrefetching','ApplicationPreLaunch')) { $original=$before.Memory.$feature; $current=$mmNow.$feature; if ($null -ne $original -and $original -ne $current) { Set-MemoryFeatureState -Feature $feature -Enabled ([bool]$original) } }
    $computer = Get-CimInstance Win32_ComputerSystem | Select-Object -First 1
    Set-CimInstance -InputObject $computer -Property @{ AutomaticManagedPagefile=[bool]$before.PageFile.AutomaticManagedPagefile } | Out-Null
    if ($null -ne $before.PageFile.PagingFiles) { New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name PagingFiles -PropertyType MultiString -Value @($before.PageFile.PagingFiles) -Force | Out-Null }
    if ($null -ne $before.PageFile.CrashDumpEnabled) { New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name CrashDumpEnabled -PropertyType DWord -Value ([int]$before.PageFile.CrashDumpEnabled) -Force | Out-Null }
    if ($before.ActivePowerSchemeGuid) { & powercfg.exe /SetActive ([string]$before.ActivePowerSchemeGuid) | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'Failed to restore previous power scheme.' } }
    if ($before.AcPowerModeGuid) { Set-AcPowerModeGuid -Guid ([string]$before.AcPowerModeGuid) }
    if ($null -ne $before.UI.MinimizeRestoreAnimation -and $null -ne $before.UI.ClientAreaAnimations) { Set-UiAnimationState -MinimizeRestoreAnimation ([bool]$before.UI.MinimizeRestoreAnimation) -ClientAreaAnimations ([bool]$before.UI.ClientAreaAnimations) }
    Write-Host "[OK] État de réactivité Windows restauré depuis $initialStatePath. Un redémarrage peut être nécessaire pour les changements de pagefile." -ForegroundColor Green
}

$current = Get-CurrentState
Write-Report -State $current
if ($Mode -eq 'Verify') {
    $failed = [System.Collections.Generic.List[string]]::new()
    if ($current.Memory.MemoryCompression -ne $true) { $failed.Add('MemoryCompression') }
    if ($current.Memory.ApplicationLaunchPrefetching -ne $true) { $failed.Add('ApplicationLaunchPrefetching') }
    if ($current.Memory.ApplicationPreLaunch -ne $true) { $failed.Add('ApplicationPreLaunch') }
    if ($current.PageFile.AutomaticManagedPagefile -ne $true) { $failed.Add('SystemManagedPagefile') }
    if ($current.PageFile.CrashDumpEnabled -ne [int]$policy.pageFile.crashDumpEnabled) { $failed.Add('AutomaticMemoryDump') }
    if ($current.ActivePowerSchemeGuid -ne [string]$policy.power.activeSchemeGuid) { $failed.Add('BalancedPowerScheme') }
    if ([string]$policy.power.acPowerModeManagement -eq 'enforce' -and $current.AcPowerModeGuid -and $current.AcPowerModeGuid -ne [string]$policy.power.acPowerModeGuid) { $failed.Add('ManagedAcPowerMode') }
    if ($current.UI.MinimizeRestoreAnimation -ne [bool]$policy.ui.minimizeRestoreAnimation) { $failed.Add('MinimizeRestoreAnimation') }
    if ($current.UI.ClientAreaAnimations -ne [bool]$policy.ui.clientAreaAnimations) { $failed.Add('ClientAreaAnimations') }
    if ($current.Storage.TrimEnabled -ne $true) { $failed.Add('TrimEnabled') }
    if ($current.Storage.ScheduledOptimizeEnabled -eq $false) { $failed.Add('ScheduledOptimize') }
    if ($failed.Count -gt 0) { throw "Vérification de réactivité Windows échouée: $($failed -join ', '). Voir $reportPath" }
    Write-Host 'VERDICT: WINDOWS RESPONSIVENESS READY' -ForegroundColor Green
}
