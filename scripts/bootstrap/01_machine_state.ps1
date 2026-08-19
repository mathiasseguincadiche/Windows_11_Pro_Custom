[CmdletBinding()]
param(
    [ValidateSet('standard', 'lab-heavy', 'nat-fallback')]
    [string]$WslProfile = 'standard',
    [string]$Distribution = 'Ubuntu',
    [string]$WslInstallLocation = 'E:\WSL\Ubuntu-DevOps'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$runtimeModule = Join-Path $repoRoot 'scripts\core\runtime.psm1'
$wslDetectionModule = Join-Path $repoRoot 'scripts\core\wsl-detection.psm1'
$nativeProcessModule = Join-Path $repoRoot 'scripts\core\native-process.psm1'
$rebootStateModule = Join-Path $repoRoot 'scripts\core\reboot-state.psm1'
Import-Module $runtimeModule
Import-Module $wslDetectionModule
Import-Module $nativeProcessModule
Import-Module $rebootStateModule -Force
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
    return Get-WpcPendingRebootState
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

function Get-WingetInventory {
    $wingetCommand = Get-WpcNativeApplication -Name 'winget.exe'
    if (-not $wingetCommand) {
        return [pscustomobject]@{ Available=$false; Success=$false; Lines=@(); Error='WinGet unavailable' }
    }

    $result = Invoke-WpcNativeCapture -FilePath $wingetCommand.Source -ArgumentList @('list', '--accept-source-agreements', '--disable-interactivity') -SuppressErrorOutput
    $lines = @($result.Lines)
    if ($result.ExitCode -ne 0) {
        return [pscustomobject]@{ Available=$true; Success=$false; Lines=$lines; Error="winget list failed with exit code $($result.ExitCode)" }
    }
    return [pscustomobject]@{ Available=$true; Success=$true; Lines=$lines; Error='' }
}

function Get-WingetPackageFact {
    param(
        [Parameter(Mandatory)]$Inventory,
        [Parameter(Mandatory)][string]$Id
    )
    if (-not $Inventory.Available) {
        return [pscustomobject]@{ Id=$Id; State='UNKNOWN'; Evidence='WinGet unavailable' }
    }
    if (-not $Inventory.Success) {
        return [pscustomobject]@{ Id=$Id; State='UNKNOWN'; Evidence=$Inventory.Error }
    }

    $line = @($Inventory.Lines | Where-Object { $_ -match [regex]::Escape($Id) } | Select-Object -First 1)
    if ($line.Count -gt 0) {
        return [pscustomobject]@{ Id=$Id; State='INSTALLED'; Evidence=[string]$line[0] }
    }

    # Le tableau global WinGet peut tronquer un identifiant selon la largeur du terminal.
    # On ne paie donc le coût d'un appel exact que pour les candidats apparemment absents.
    $wingetCommand = Get-WpcNativeApplication -Name 'winget.exe'
    if (-not $wingetCommand) {
        return [pscustomobject]@{ Id=$Id; State='UNKNOWN'; Evidence='WinGet unavailable during exact fallback' }
    }
    $exactResult = Invoke-WpcNativeCapture -FilePath $wingetCommand.Source -ArgumentList @('list', '--id', $Id, '--exact', '--accept-source-agreements', '--disable-interactivity') -SuppressErrorOutput
    $exactText = $exactResult.Text
    $exactLine = @($exactText -split "`r?`n" | Where-Object { $_ -match [regex]::Escape($Id) } | Select-Object -First 1)
    if ($exactResult.ExitCode -eq 0 -and $exactLine.Count -gt 0) {
        return [pscustomobject]@{ Id=$Id; State='INSTALLED'; Evidence="Exact fallback: $([string]$exactLine[0])" }
    }

    return [pscustomobject]@{ Id=$Id; State='MISSING'; Evidence='Exact WinGet ID absent après vérification ciblée' }
}

function Get-WslFacts {
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wsl) {
        return [pscustomobject]@{
            Executable = $null
            DistributionPresent = $false
            DistributionNames = @()
            Version = $null
            ConfigPresent = $false
            ConfigMatches = $false
            InstallLocationRequested = $WslInstallLocation
            InstallLocationObserved = $null
            DetectionSource = 'wsl.exe absent'
        }
    }

    $registration = Get-WpcWslRegistrationFact -Distribution $Distribution
    $names = @()
    $present = $false
    $basePath = $null
    $detectionSource = 'registry'

    if ($registration.Known) {
        $names = @($registration.Names)
        $present = [bool]$registration.Present
        $basePath = [string]$registration.BasePath
    } else {
        $detectionSource = 'wsl.exe fallback'
        try {
            $names = @((wsl.exe --list --quiet 2>$null) -replace "`0", '' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $global:LASTEXITCODE = 0
        } catch {}
        $present = $names -contains $Distribution
    }

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

    return [pscustomobject]@{
        Executable = $wsl.Source
        DistributionPresent = $present
        DistributionNames = $names
        Version = $version
        ConfigPresent = $configPresent
        ConfigMatches = $configMatches
        InstallLocationRequested = $WslInstallLocation
        InstallLocationObserved = $basePath
        DetectionSource = $detectionSource
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

Write-Host '[INFO] Découverte machine: Windows, matériel et volumes...' -ForegroundColor DarkGray
$os = Get-CimInstance Win32_OperatingSystem
$computer = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$pendingReboot = Test-PendingReboot
$c = Get-VolumeFact -DriveLetter 'C'
$e = Get-VolumeFact -DriveLetter 'E'

$winget = Get-WpcNativeApplication -Name 'winget.exe'
$manifest = Get-Content -Raw (Join-Path $repoRoot 'manifests\winget\apps-core.json') | ConvertFrom-Json
$requiredApps = @($manifest.apps | Where-Object { $_.autoInstall -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$_.wingetId) })
Write-Host "[INFO] Inventaire WinGet global: $($requiredApps.Count) applications cibles..." -ForegroundColor DarkGray
$wingetInventory = Get-WingetInventory
$appFacts = @()
foreach ($app in $requiredApps) {
    $fact = Get-WingetPackageFact -Inventory $wingetInventory -Id ([string]$app.wingetId)
    $appFacts += [pscustomobject]@{ Name=[string]$app.name; Id=[string]$app.wingetId; State=$fact.State; Evidence=$fact.Evidence }
}
$installedApps = @($appFacts | Where-Object State -EQ 'INSTALLED').Count
$missingApps = @($appFacts | Where-Object State -EQ 'MISSING').Count
$unknownApps = @($appFacts | Where-Object State -EQ 'UNKNOWN').Count

Write-Host '[INFO] Découverte WSL2...' -ForegroundColor DarkGray
$wslFacts = Get-WslFacts
Write-Host '[INFO] Découverte outils Windows, OneDrive et Defender...' -ForegroundColor DarkGray
$code = Get-Command code.cmd -ErrorAction SilentlyContinue
if (-not $code) { $code = Get-Command code -ErrorAction SilentlyContinue }
$terminal = Get-Command wt.exe -ErrorAction SilentlyContinue
$ssh = Get-Command ssh.exe -ErrorAction SilentlyContinue
$oneDrive = Get-OneDriveFact
$defender = $null
try { $defender = Get-MpComputerStatus -ErrorAction Stop } catch {}

$signalsReady = 0
$signalsTotal = 6
if ($missingApps -eq 0 -and $unknownApps -eq 0) { $signalsReady++ }
if ($wslFacts.DistributionPresent -and $wslFacts.Version -eq 2 -and $wslFacts.ConfigMatches) { $signalsReady++ }
if ($code) { $signalsReady++ }
if ($terminal) { $signalsReady++ }
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
    Storage = @($c, $e)
    WinGet = [ordered]@{
        Available = ($null -ne $winget)
        InventorySuccess = [bool]$wingetInventory.Success
        InventoryError = [string]$wingetInventory.Error
        Path = if ($winget) { $winget.Source } else { $null }
        RequiredApps = $appFacts
        InstalledCount = $installedApps
        MissingCount = $missingApps
        UnknownCount = $unknownApps
    }
    WSL = $wslFacts
    Workstation = [ordered]@{
        VSCodeCli = if ($code) { $code.Source } else { $null }
        WindowsTerminalCli = if ($terminal) { $terminal.Source } else { $null }
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
Write-WpcStatus -Status $(if ($e.Present -and $e.FileSystem -eq 'NTFS') { 'DEJA_OK' } else { 'A_FAIRE' }) -Message 'Volume E:' -Detail "Présent=$($e.Present) FS=$($e.FileSystem) Santé=$($e.HealthStatus) Libre=$($e.FreeGB) Go" -Context $context
if ($unknownApps -gt 0) {
    Write-WpcStatus -Status 'AVERTISSEMENT' -Message 'Applications WinGet' -Detail "État incomplet: $unknownApps application(s) indéterminée(s). $($wingetInventory.Error)" -Context $context
} elseif ($missingApps -gt 0) {
    Write-WpcStatus -Status 'A_FAIRE' -Message 'Applications WinGet' -Detail "$installedApps installées, $missingApps manquantes." -Context $context
} else {
    Write-WpcStatus -Status 'DEJA_OK' -Message 'Applications WinGet' -Detail "$installedApps/$($appFacts.Count) applications automatiques détectées." -Context $context
}
Write-WpcStatus -Status $(if ($wslFacts.DistributionPresent -and $wslFacts.Version -eq 2 -and $wslFacts.ConfigMatches) { 'DEJA_OK' } else { 'A_FAIRE' }) -Message 'WSL2' -Detail "Distribution=$($wslFacts.DistributionPresent) Version=$($wslFacts.Version) Profil=$($wslFacts.ConfigMatches) Détection=$($wslFacts.DetectionSource)" -Context $context
Write-WpcStatus -Status $(if (-not $oneDrive.Installed) { 'DEJA_OK' } else { 'A_FAIRE' }) -Message 'OneDrive' -Detail "Installé=$($oneDrive.Installed) Actif=$($oneDrive.Running)" -Context $context
if ($pendingReboot.Pending) {
    Write-WpcStatus -Status 'ACTION_REQUISE' -Message 'Redémarrage Windows en attente' -Detail ($pendingReboot.Reasons -join ', ') -Context $context
} elseif ($pendingReboot.Advisory) {
    Write-WpcStatus -Status 'AVERTISSEMENT' -Message 'Signal de renommage de fichiers observé' -Detail "PendingFileRenameOperations=$($pendingReboot.PendingFileRenameOperationsCount) entrée(s), non bloquant sans marqueur CBS/Windows Update." -Context $context
}
Write-Host "Rapport factuel: $reportPath" -ForegroundColor DarkGray
