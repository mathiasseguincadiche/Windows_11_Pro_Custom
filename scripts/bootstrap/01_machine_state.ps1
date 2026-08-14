[CmdletBinding()]
param(
    [ValidateSet('standard', 'lab-heavy', 'nat-fallback')]
    [string]$WslProfile = 'standard',
    [string]$Distribution = 'Ubuntu',
    [string]$WslInstallLocation = 'D:\WSL\Ubuntu-DevOps'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$runtimeModule = Join-Path $repoRoot 'scripts\core\runtime.psm1'
Import-Module $runtimeModule -Force
$context = Get-WpcRunContextFromEnvironment -RepoRoot $repoRoot
$reportDir = Join-Path $repoRoot 'reports\orchestration'
$reportPath = Join-Path $reportDir 'machine-state.json'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

function Test-Administrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Test-PendingReboot {
    $reasons = [System.Collections.Generic.List[string]]::new()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $reasons.Add('CBS') }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $reasons.Add('WindowsUpdate') }
    try {
        $pending = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction Stop
        if ($null -ne $pending) { $reasons.Add('PendingFileRenameOperations') }
    } catch {}
    return [pscustomobject]@{ Pending = ($reasons.Count -gt 0); Reasons = @($reasons) }
}

function Get-VolumeFact {
    param([Parameter(Mandatory)][char]$DriveLetter)
    try {
        $volume = Get-Volume -DriveLetter $DriveLetter -ErrorAction Stop
        return [pscustomobject]@{
            Present = $true
            Drive = "$DriveLetter`:"
            FileSystem = [string]$volume.FileSystem
            HealthStatus = [string]$volume.HealthStatus
            SizeGB = [math]::Round($volume.Size / 1GB, 1)
            FreeGB = [math]::Round($volume.SizeRemaining / 1GB, 1)
            FreePercent = if ($volume.Size -gt 0) { [math]::Round(($volume.SizeRemaining / $volume.Size) * 100, 1) } else { $null }
        }
    } catch {
        return [pscustomobject]@{ Present=$false; Drive="$DriveLetter`:"; FileSystem=$null; HealthStatus=$null; SizeGB=$null; FreeGB=$null; FreePercent=$null }
    }
}

function Test-WingetPackage {
    param([Parameter(Mandatory)][string]$Id)
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Id=$Id; State='UNKNOWN'; Evidence='WinGet unavailable' }
    }
    $text = (& winget.exe list --id $Id --exact --accept-source-agreements --disable-interactivity 2>$null | Out-String)
    $code = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($code -eq 0 -and $text -match [regex]::Escape($Id)) {
        $evidence = @($text -split "`r?`n" | Where-Object { $_ -match [regex]::Escape($Id) } | Select-Object -First 1)
        return [pscustomobject]@{ Id=$Id; State='INSTALLED'; Evidence=($evidence -join '') }
    }
    return [pscustomobject]@{ Id=$Id; State='MISSING'; Evidence='Exact WinGet ID not found' }
}

function Get-WslFacts {
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wsl) {
        return [pscustomobject]@{
            Executable = $null
            DistributionPresent = $false
            Version = $null
            ConfigPresent = $false
            ConfigMatches = $false
            InstallLocationObserved = $null
        }
    }

    $names = @()
    try {
        $names = @((wsl.exe --list --quiet 2>$null) -replace "`0", '' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $global:LASTEXITCODE = 0
    } catch {}
    $present = $names -contains $Distribution

    $version = $null
    if ($present) {
        try {
            $verbose = @((wsl.exe --list --verbose 2>$null) -replace "`0", '')
            $line = @($verbose | Where-Object { $_ -match [regex]::Escape($Distribution) } | Select-Object -First 1)
            if ($line.Count -gt 0 -and $line[0] -match '\s([12])\s*$') { $version = [int]$matches[1] }
            $global:LASTEXITCODE = 0
        } catch {}
    }

    $source = Join-Path $repoRoot "config\wsl\$WslProfile.wslconfig"
    $target = Join-Path $env:USERPROFILE '.wslconfig'
    $configPresent = Test-Path $target
    $configMatches = $false
    if ((Test-Path $source) -and $configPresent) {
        $configMatches = (Get-FileHash $source -Algorithm SHA256).Hash -eq (Get-FileHash $target -Algorithm SHA256).Hash
    }

    $basePath = $null
    try {
        $lxss = Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction Stop
        foreach ($key in $lxss) {
            $item = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
            if ([string]$item.DistributionName -eq $Distribution) {
                $basePath = [string]$item.BasePath
                break
            }
        }
    } catch {}

    return [pscustomobject]@{
        Executable = $wsl.Source
        DistributionPresent = $present
        DistributionNames = $names
        Version = $version
        ConfigPresent = $configPresent
        ConfigMatches = $configMatches
        InstallLocationRequested = $WslInstallLocation
        InstallLocationObserved = $basePath
    }
}

function Get-OneDriveFact {
    $paths = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDrive.exe')
    )
    $installed = $false
    foreach ($path in $paths) { if (Test-Path $path) { $installed = $true } }
    if (Get-Process -Name OneDrive -ErrorAction SilentlyContinue) { $installed = $true }
    return [pscustomobject]@{ Installed=$installed; Running=($null -ne (Get-Process -Name OneDrive -ErrorAction SilentlyContinue)) }
}

$os = Get-CimInstance Win32_OperatingSystem
$computer = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$pendingReboot = Test-PendingReboot
$c = Get-VolumeFact -DriveLetter 'C'
$d = Get-VolumeFact -DriveLetter 'D'
$winget = Get-Command winget.exe -ErrorAction SilentlyContinue
$manifest = Get-Content -Raw (Join-Path $repoRoot 'manifests\winget\apps-core.json') | ConvertFrom-Json
$appFacts = @()
foreach ($app in @($manifest.apps | Where-Object { $_.autoInstall -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$_.wingetId) })) {
    $fact = Test-WingetPackage -Id ([string]$app.wingetId)
    $appFacts += [pscustomobject]@{ Name=[string]$app.name; Id=[string]$app.wingetId; State=$fact.State; Evidence=$fact.Evidence }
}
$installedApps = @($appFacts | Where-Object State -EQ 'INSTALLED').Count
$missingApps = @($appFacts | Where-Object State -EQ 'MISSING').Count
$unknownApps = @($appFacts | Where-Object State -EQ 'UNKNOWN').Count
$wslFacts = Get-WslFacts
$code = Get-Command code.cmd -ErrorAction SilentlyContinue
if (-not $code) { $code = Get-Command code -ErrorAction SilentlyContinue }
$wezterm = Get-Command wezterm.exe -ErrorAction SilentlyContinue
$ssh = Get-Command ssh.exe -ErrorAction SilentlyContinue
$oneDrive = Get-OneDriveFact
$defender = $null
try { $defender = Get-MpComputerStatus -ErrorAction Stop } catch {}

$signalsReady = 0
$signalsTotal = 6
if ($missingApps -eq 0 -and $unknownApps -eq 0) { $signalsReady++ }
if ($wslFacts.DistributionPresent -and $wslFacts.Version -eq 2 -and $wslFacts.ConfigMatches) { $signalsReady++ }
if ($code) { $signalsReady++ }
if ($wezterm) { $signalsReady++ }
if ($ssh) { $signalsReady++ }
if (-not $oneDrive.Installed) { $signalsReady++ }

$state = if ($signalsReady -eq $signalsTotal) { 'READY_CANDIDATE' } elseif ($signalsReady -eq 0 -and $installedApps -eq 0 -and -not $wslFacts.DistributionPresent) { 'FIRST_RUN' } else { 'PARTIAL' }

$report = [ordered]@{
    Version = 'V9'
    Timestamp = (Get-Date).ToString('o')
    InstallationState = $state
    EvidencePolicy = 'Machine facts are re-read on every run. Repository state files are history/rollback data, never the source of truth.'
    Session = [ordered]@{
        Computer = $env:COMPUTERNAME
        User = $env:USERNAME
        Administrator = Test-Administrator
        PowerShellVersion = [string]$PSVersionTable.PSVersion
        PowerShellEdition = [string]$PSVersionTable.PSEdition
        PendingReboot = $pendingReboot
    }
    Windows = [ordered]@{
        Caption = [string]$os.Caption
        Version = [string]$os.Version
        Build = [string]$os.BuildNumber
        Architecture = [string]$os.OSArchitecture
    }
    Hardware = [ordered]@{
        Manufacturer = [string]$computer.Manufacturer
        Model = [string]$computer.Model
        TotalMemoryGB = [math]::Round($computer.TotalPhysicalMemory / 1GB, 1)
        Cpu = [string]$cpu.Name
        LogicalProcessors = [int]$computer.NumberOfLogicalProcessors
    }
    Storage = @($c, $d)
    WinGet = [ordered]@{
        Available = ($null -ne $winget)
        Path = if ($winget) { $winget.Source } else { $null }
        RequiredApps = $appFacts
        InstalledCount = $installedApps
        MissingCount = $missingApps
        UnknownCount = $unknownApps
    }
    WSL = $wslFacts
    Workstation = [ordered]@{
        VSCodeCli = if ($code) { $code.Source } else { $null }
        WezTermCli = if ($wezterm) { $wezterm.Source } else { $null }
        SshCli = if ($ssh) { $ssh.Source } else { $null }
    }
    OneDrive = $oneDrive
    Defender = [ordered]@{
        Available = ($null -ne $defender)
        AntivirusEnabled = if ($defender) { [bool]$defender.AntivirusEnabled } else { $null }
        RealTimeProtectionEnabled = if ($defender) { [bool]$defender.RealTimeProtectionEnabled } else { $null }
    }
    Signals = [ordered]@{ Ready=$signalsReady; Total=$signalsTotal }
}
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ''
Write-Host 'ÉTAT RÉEL DE LA MACHINE' -ForegroundColor Cyan
Write-Host ('-' * 70) -ForegroundColor DarkCyan
switch ($state) {
    'FIRST_RUN' { Write-WpcStatus -Status 'A_FAIRE' -Message 'Première installation détectée' -Detail 'Les indicateurs principaux sont absents; le plan Apply peut commencer.' -Context $context }
    'PARTIAL' { Write-WpcStatus -Status 'A_FAIRE' -Message 'Installation partielle détectée' -Detail 'Une partie de la cible est déjà présente; seules les différences devront être appliquées.' -Context $context }
    'READY_CANDIDATE' { Write-WpcStatus -Status 'DEJA_OK' -Message 'Machine proche de la cible complète' -Detail 'Les signaux principaux sont conformes; Verify reste lʼautorité finale.' -Context $context }
}
Write-WpcStatus -Status $(if ($c.Present -and $c.FileSystem -eq 'NTFS') { 'DEJA_OK' } else { 'A_FAIRE' }) -Message 'Volume C:' -Detail "Présent=$($c.Present) FS=$($c.FileSystem) Santé=$($c.HealthStatus) Libre=$($c.FreeGB) Go" -Context $context
Write-WpcStatus -Status $(if ($d.Present -and $d.FileSystem -eq 'NTFS') { 'DEJA_OK' } else { 'A_FAIRE' }) -Message 'Volume D:' -Detail "Présent=$($d.Present) FS=$($d.FileSystem) Santé=$($d.HealthStatus) Libre=$($d.FreeGB) Go" -Context $context
if ($unknownApps -gt 0) {
    Write-WpcStatus -Status 'AVERTISSEMENT' -Message 'Applications WinGet' -Detail 'WinGet indisponible: état des applications non déterminable sans inventer.' -Context $context
} elseif ($missingApps -gt 0) {
    Write-WpcStatus -Status 'A_FAIRE' -Message 'Applications WinGet' -Detail "$installedApps installées, $missingApps manquantes." -Context $context
} else {
    Write-WpcStatus -Status 'DEJA_OK' -Message 'Applications WinGet' -Detail "$installedApps/$($appFacts.Count) applications automatiques détectées." -Context $context
}
Write-WpcStatus -Status $(if ($wslFacts.DistributionPresent -and $wslFacts.Version -eq 2 -and $wslFacts.ConfigMatches) { 'DEJA_OK' } else { 'A_FAIRE' }) -Message 'WSL2' -Detail "Distribution=$($wslFacts.DistributionPresent) Version=$($wslFacts.Version) Profil=$($wslFacts.ConfigMatches)" -Context $context
Write-WpcStatus -Status $(if (-not $oneDrive.Installed) { 'DEJA_OK' } else { 'A_FAIRE' }) -Message 'OneDrive' -Detail "Installé=$($oneDrive.Installed) Actif=$($oneDrive.Running)" -Context $context
if ($pendingReboot.Pending) {
    Write-WpcStatus -Status 'ACTION_REQUISE' -Message 'Redémarrage Windows en attente' -Detail ($pendingReboot.Reasons -join ', ') -Context $context
}
Write-Host "Rapport factuel: $reportPath" -ForegroundColor DarkGray