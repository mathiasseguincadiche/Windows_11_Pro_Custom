[CmdletBinding()]
param(
    [switch]$Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$reportDir = Join-Path $repoRoot 'reports\physical-readiness'
$reportPath = Join-Path $reportDir 'physical-install-readiness.json'
$hardwareTargetPath = Join-Path $repoRoot 'config\hardware\target-v5.json'
$wslContractPath = Join-Path $repoRoot 'config\wsl\runtime-contract.json'
$appsManifestPath = Join-Path $repoRoot 'manifests\winget\apps-core.json'
$windowsNativeModule = Join-Path $repoRoot 'scripts\core\windows-native.psm1'

foreach ($path in @($hardwareTargetPath, $wslContractPath, $appsManifestPath, $windowsNativeModule)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Contrat requis introuvable: $path" }
}

Import-Module $windowsNativeModule
[void]@(Initialize-WpcWindowsNativeModules -Profile Full)

$hardwareTarget = Get-Content -Raw $hardwareTargetPath | ConvertFrom-Json
$wslContract = Get-Content -Raw $wslContractPath | ConvertFrom-Json
$appsManifest = Get-Content -Raw $appsManifestPath | ConvertFrom-Json
$checks = [System.Collections.Generic.List[object]]::new()

function Add-ReadinessCheck {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Detail,
        [bool]$Blocking = $true
    )
    $checks.Add([pscustomobject]@{
        Name = $Name
        Passed = $Passed
        Blocking = $Blocking
        Detail = $Detail
    })
}

function Test-Administrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Get-PendingRebootReasons {
    $reasons = [System.Collections.Generic.List[string]]::new()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $reasons.Add('CBS') }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $reasons.Add('WindowsUpdate') }
    try {
        $pendingRename = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction Stop
        if ($null -ne $pendingRename) { $reasons.Add('PendingFileRenameOperations') }
    } catch {}
    return @($reasons)
}

function Get-OptionalFeatureStateSafe {
    param([Parameter(Mandatory)][string]$FeatureName)
    try {
        if (-not (Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue)) {
            Import-Module Dism -ErrorAction Stop
        }
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction Stop
        return [string]$feature.State
    } catch {
        return "UNKNOWN: $($_.Exception.Message)"
    }
}

function Get-WslNames {
    try {
        $names = @((wsl.exe --list --quiet 2>$null) -replace "`0", '' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $code = $LASTEXITCODE
        $global:LASTEXITCODE = 0
        if ($code -ne 0) { return @() }
        return @($names)
    } catch { return @() }
}

function Test-TcpEndpoint {
    param([Parameter(Mandatory)][string]$HostName)
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $task = $client.ConnectAsync($HostName, 443)
        if (-not $task.Wait(2500)) { return $false }
        return $client.Connected
    } catch { return $false }
    finally { $client.Dispose() }
}

$os = Get-CimInstance Win32_OperatingSystem
$computer = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$memory = @(Get-CimInstance Win32_PhysicalMemory)
$board = Get-CimInstance Win32_BaseBoard | Select-Object -First 1
$video = @(Get-CimInstance Win32_VideoController)

$psVersion = [version]$PSVersionTable.PSVersion
$psReady = ($PSVersionTable.PSEdition -eq 'Core' -and $psVersion -ge [version]'7.4.0')
Add-ReadinessCheck -Name 'PowerShell 7 supporté' -Passed $psReady -Detail "Edition=$($PSVersionTable.PSEdition) Version=$psVersion ; minimum=7.4.0, 7.6 LTS recommandé."
Add-ReadinessCheck -Name 'Session administrateur' -Passed (Test-Administrator) -Detail "Utilisateur=$env:USERNAME"
Add-ReadinessCheck -Name 'Processus et OS 64 bits' -Passed ([Environment]::Is64BitOperatingSystem -and [Environment]::Is64BitProcess) -Detail "OS64=$([Environment]::Is64BitOperatingSystem) Process64=$([Environment]::Is64BitProcess)"

$isWindows11 = ([string]$os.Caption -match 'Windows 11')
$build = [int]$os.BuildNumber
Add-ReadinessCheck -Name 'Windows 11 22H2 ou ultérieur' -Passed ($isWindows11 -and $build -ge 22621) -Detail "Caption=$($os.Caption) Build=$build ; build minimal=22621 pour le réseau WSL mirrored."

$editionId = [string](Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID -ErrorAction Stop)
Add-ReadinessCheck -Name 'Édition Windows non-Home' -Passed ($editionId -notmatch '^Core') -Detail "EditionID=$editionId"

$pendingReboot = Get-PendingRebootReasons
Add-ReadinessCheck -Name 'Aucun redémarrage Windows en attente' -Passed ($pendingReboot.Count -eq 0) -Detail $(if ($pendingReboot.Count -eq 0) { 'Aucun marqueur de reboot détecté.' } else { $pendingReboot -join ', ' })

$c = $null
$d = $null
try { $c = Get-Volume -DriveLetter C -ErrorAction Stop } catch {}
try { $d = Get-Volume -DriveLetter D -ErrorAction Stop } catch {}
Add-ReadinessCheck -Name 'Volume C: NTFS sain' -Passed ($null -ne $c -and [string]$c.FileSystem -eq 'NTFS' -and [string]$c.HealthStatus -ne 'Unhealthy') -Detail $(if ($c) { "FS=$($c.FileSystem) Santé=$($c.HealthStatus) Libre=$([math]::Round($c.SizeRemaining / 1GB, 1)) Go" } else { 'C: absent ou illisible.' })
Add-ReadinessCheck -Name 'Volume D: NTFS sain' -Passed ($null -ne $d -and [string]$d.FileSystem -eq 'NTFS' -and [string]$d.HealthStatus -ne 'Unhealthy') -Detail $(if ($d) { "FS=$($d.FileSystem) Santé=$($d.HealthStatus) Libre=$([math]::Round($d.SizeRemaining / 1GB, 1)) Go" } else { 'D: absent ou illisible.' })
Add-ReadinessCheck -Name 'Espace WSL sur D:' -Passed ($null -ne $d -and $d.SizeRemaining -ge 50GB) -Detail $(if ($d) { "Libre=$([math]::Round($d.SizeRemaining / 1GB, 1)) Go ; minimum=50 Go" } else { 'D: indisponible.' })

$systemDiskGpt = $false
try {
    $systemPartition = Get-Partition -DriveLetter C -ErrorAction Stop
    $systemDisk = Get-Disk -Number $systemPartition.DiskNumber -ErrorAction Stop
    $systemDiskGpt = ([string]$systemDisk.PartitionStyle -eq 'GPT')
    $systemDiskDetail = "Disque=$($systemDisk.Number) Style=$($systemDisk.PartitionStyle)"
} catch {
    $systemDiskDetail = $_.Exception.Message
}
Add-ReadinessCheck -Name 'Disque système GPT/UEFI' -Passed $systemDiskGpt -Detail $systemDiskDetail

$secureBoot = $false
try { $secureBoot = [bool](Confirm-SecureBootUEFI -ErrorAction Stop) } catch {}
Add-ReadinessCheck -Name 'Secure Boot actif' -Passed $secureBoot -Detail "SecureBoot=$secureBoot"

$tpmReady = $false
$tpmDetail = 'TPM non lisible.'
try {
    $tpm = Get-Tpm -ErrorAction Stop
    $tpmReady = [bool]($tpm.TpmPresent -and $tpm.TpmReady -and $tpm.TpmEnabled)
    $tpmDetail = "Present=$($tpm.TpmPresent) Ready=$($tpm.TpmReady) Enabled=$($tpm.TpmEnabled)"
} catch { $tpmDetail = $_.Exception.Message }
Add-ReadinessCheck -Name 'TPM prêt' -Passed $tpmReady -Detail $tpmDetail

$virtualization = [bool]$cpu.VirtualizationFirmwareEnabled
Add-ReadinessCheck -Name 'Virtualisation firmware active' -Passed $virtualization -Detail "CPU=$($cpu.Name) VirtualizationFirmwareEnabled=$virtualization"

$hardwareFailures = [System.Collections.Generic.List[string]]::new()
if ([string]$cpu.Name -notlike "*$($hardwareTarget.cpu.nameContains)*") { $hardwareFailures.Add("CPU=$($cpu.Name)") }
if ([int]$cpu.NumberOfCores -ne [int]$hardwareTarget.cpu.cores) { $hardwareFailures.Add("Cœurs=$($cpu.NumberOfCores)") }
if ([int]$cpu.NumberOfLogicalProcessors -ne [int]$hardwareTarget.cpu.threads) { $hardwareFailures.Add("Threads=$($cpu.NumberOfLogicalProcessors)") }
$totalMemory = ($memory | Measure-Object -Property Capacity -Sum).Sum
if ([int64]$totalMemory -lt [int64]$hardwareTarget.memory.minimumBytes) { $hardwareFailures.Add("RAM=$([math]::Round($totalMemory / 1GB, 1)) Go") }
if (@($memory | Where-Object { [int]$_.ConfiguredClockSpeed -lt [int]$hardwareTarget.memory.targetConfiguredClockMHz }).Count -gt 0) { $hardwareFailures.Add('DDR5 configurée sous 6000 MT/s') }
if ([string]$board.Product -notlike "*$($hardwareTarget.motherboard.productContains)*") { $hardwareFailures.Add("Carte mère=$($board.Product)") }
$arc = @($video | Where-Object { [string]$_.Name -match [string]$hardwareTarget.gpu.nameRegex })
if ($arc.Count -eq 0) { $hardwareFailures.Add('Intel Arc B580 non détectée') }
$displayMatch = @($video | Where-Object {
    [int]$_.CurrentHorizontalResolution -eq [int]$hardwareTarget.display.width -and
    [int]$_.CurrentVerticalResolution -eq [int]$hardwareTarget.display.height -and
    [int]$_.CurrentRefreshRate -ge [int]$hardwareTarget.display.minimumRefreshHz
})
if ($displayMatch.Count -eq 0) { $hardwareFailures.Add('Affichage 2560x1440 >=239 Hz non détecté') }
Add-ReadinessCheck -Name 'Matériel cible V5 détecté' -Passed ($hardwareFailures.Count -eq 0) -Detail $(if ($hardwareFailures.Count -eq 0) { 'CPU, RAM 6000, carte mère, Arc B580 et affichage correspondent à la cible.' } else { $hardwareFailures -join '; ' })

$symbiosisReady = $false
$symbiosisDetail = 'Qualification non exécutée.'
try {
    $symbiosisOutput = @(& (Join-Path $repoRoot 'scripts\windows\52_hardware_symbiosis.ps1') -Mode Verify *>&1 | ForEach-Object { [string]$_ })
    $symbiosisReady = $true
    $symbiosisDetail = (@($symbiosisOutput | Select-Object -Last 3) -join ' | ')
} catch {
    $symbiosisDetail = $_.Exception.Message
}
Add-ReadinessCheck -Name 'Symbiose matériel/pilotes' -Passed $symbiosisReady -Detail $symbiosisDetail

$wslFeatureState = Get-OptionalFeatureStateSafe -FeatureName 'Microsoft-Windows-Subsystem-Linux'
$vmpFeatureState = Get-OptionalFeatureStateSafe -FeatureName 'VirtualMachinePlatform'
Add-ReadinessCheck -Name 'Fonctionnalité Windows WSL active' -Passed ($wslFeatureState -eq 'Enabled') -Detail "Microsoft-Windows-Subsystem-Linux=$wslFeatureState. Si désactivée: active-la puis redémarre Windows avant FullInstall."
Add-ReadinessCheck -Name 'VirtualMachinePlatform active' -Passed ($vmpFeatureState -eq 'Enabled') -Detail "VirtualMachinePlatform=$vmpFeatureState. Si désactivée: active-la puis redémarre Windows avant FullInstall."

$restorePointProviderReady = $false
$restorePointDetail = ''
try {
    [void](Get-CimClass -Namespace 'root/default' -ClassName SystemRestore -ErrorAction Stop)
    $windowsPowerShell = Get-Command powershell.exe -ErrorAction Stop
    $checkpointName = (& $windowsPowerShell.Source -NoLogo -NoProfile -NonInteractive -Command "(Get-Command Checkpoint-Computer -ErrorAction SilentlyContinue).Name" 2>$null | Out-String).Trim()
    $restoreCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    $restorePointProviderReady = ($restoreCode -eq 0 -and $checkpointName -eq 'Checkpoint-Computer')
    $restorePointDetail = "SystemRestore WMI présent; powershell.exe=$($windowsPowerShell.Source); Checkpoint-Computer=$restorePointProviderReady"
} catch { $restorePointDetail = $_.Exception.Message }
Add-ReadinessCheck -Name 'Garde-fou point de restauration disponible' -Passed $restorePointProviderReady -Detail $restorePointDetail

$winget = Get-Command winget.exe -ErrorAction SilentlyContinue
$wingetReady = $null -ne $winget
$wingetVersion = ''
if ($wingetReady) {
    $wingetVersion = (& winget.exe --version 2>&1 | Out-String).Trim()
    $versionCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    $wingetReady = ($versionCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($wingetVersion))
}
Add-ReadinessCheck -Name 'WinGet opérationnel' -Passed $wingetReady -Detail $(if ($wingetReady) { "Version=$wingetVersion Path=$($winget.Source)" } else { 'WinGet/App Installer absent ou non fonctionnel.' })

$unresolvedApps = [System.Collections.Generic.List[string]]::new()
if ($wingetReady) {
    foreach ($app in @($appsManifest.apps | Where-Object { [bool]$_.autoInstall })) {
        $id = [string]$app.wingetId
        & winget.exe show --id $id --exact --source winget --accept-source-agreements --disable-interactivity *> $null
        $code = $LASTEXITCODE
        $global:LASTEXITCODE = 0
        if ($code -ne 0) { $unresolvedApps.Add("$($app.name) [$id]") }
    }
}
Add-ReadinessCheck -Name 'Catalogue WinGet résolvable' -Passed ($wingetReady -and $unresolvedApps.Count -eq 0) -Detail $(if (-not $wingetReady) { 'WinGet indisponible.' } elseif ($unresolvedApps.Count -eq 0) { 'Tous les IDs autoInstall sont résolus avant toute mutation.' } else { $unresolvedApps -join '; ' })

$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
$wslVersionReady = $false
$wslVersionText = ''
if ($wsl) {
    $wslVersionText = (& wsl.exe --version 2>&1 | Out-String).Trim()
    $wslVersionCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    $wslVersionReady = ($wslVersionCode -eq 0)
}
Add-ReadinessCheck -Name 'Runtime WSL Store opérationnel' -Passed ($null -ne $wsl -and $wslVersionReady) -Detail $(if ($wslVersionReady) { ($wslVersionText -split "`r?`n" | Select-Object -First 1) } else { 'wsl --version a échoué. Exécute wsl --update après activation des fonctionnalités Windows.' })

$distribution = [string]$wslContract.distribution
$sourceDistribution = [string]$wslContract.sourceDistribution
$wslNames = if ($wsl) { Get-WslNames } else { @() }
$distributionPresent = $wslNames -contains $distribution
Add-ReadinessCheck -Name 'Nom de distribution WSL cible cohérent' -Passed (-not [string]::IsNullOrWhiteSpace($distribution) -and -not [string]::IsNullOrWhiteSpace($sourceDistribution)) -Detail "Nom enregistré=$distribution ; source épinglée=$sourceDistribution"

if (-not $distributionPresent -and $wslVersionReady) {
    $wslHelp = (& wsl.exe --help 2>&1 | Out-String)
    $installCapabilities = ($wslHelp -match '--location' -and $wslHelp -match '--name' -and $wslHelp -match '--no-launch')
    Add-ReadinessCheck -Name 'WSL sait installer avec nom et emplacement explicites' -Passed $installCapabilities -Detail 'Options requises: --location, --name, --no-launch. Si absentes: wsl --update puis redémarrage.'

    $online = (& wsl.exe --list --online 2>&1 | Out-String) -replace "`0", ''
    $onlineCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    $sourceAvailable = ($onlineCode -eq 0 -and $online -match "(?m)^\s*$([regex]::Escape($sourceDistribution))\s")
    Add-ReadinessCheck -Name 'Ubuntu 26.04 explicite disponible dans WSL' -Passed $sourceAvailable -Detail "Source attendue=$sourceDistribution"
} elseif ($distributionPresent) {
    Add-ReadinessCheck -Name 'Distribution WSL déjà enregistrée' -Passed $true -Detail "$distribution est déjà présente; sa version et son emplacement seront revalidés par 06_wsl.ps1."
}

$networkHosts = @(
    'github.com',
    'dl.k8s.io',
    'get.helm.sh',
    'releases.hashicorp.com',
    'awscli.amazonaws.com',
    'storage.googleapis.com',
    'download.docker.com',
    'cli.github.com',
    'aquasecurity.github.io'
)
$unreachable = [System.Collections.Generic.List[string]]::new()
foreach ($hostName in $networkHosts) {
    if (-not (Test-TcpEndpoint -HostName $hostName)) { $unreachable.Add($hostName) }
}
Add-ReadinessCheck -Name 'Accès réseau aux fournisseurs DevOps' -Passed ($unreachable.Count -eq 0) -Detail $(if ($unreachable.Count -eq 0) { 'TCP/443 joignable pour tous les fournisseurs requis.' } else { "Non joignables actuellement: $($unreachable -join ', '). Les téléchargements réels disposent néanmoins de leurs propres vérifications/retries." }) -Blocking $false

New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$blockers = @($checks | Where-Object { $_.Blocking -and -not $_.Passed })
$warnings = @($checks | Where-Object { -not $_.Blocking -and -not $_.Passed })

[ordered]@{
    Version = 'V17'
    Timestamp = (Get-Date).ToString('o')
    Strict = [bool]$Strict
    Computer = $env:COMPUTERNAME
    User = $env:USERNAME
    PowerShell = [ordered]@{ Edition=[string]$PSVersionTable.PSEdition; Version=$psVersion.ToString() }
    Windows = [ordered]@{ Caption=[string]$os.Caption; Build=$build; EditionID=$editionId }
    Wsl = [ordered]@{ Distribution=$distribution; SourceDistribution=$sourceDistribution; Present=$distributionPresent }
    Checks = @($checks)
    BlockerCount = $blockers.Count
    WarningCount = $warnings.Count
    Ready = ($blockers.Count -eq 0)
} | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 $reportPath

Write-Host ''
Write-Host ('=' * 78) -ForegroundColor DarkCyan
Write-Host '  PRÉQUALIFICATION INSTALLATION PHYSIQUE' -ForegroundColor Cyan
Write-Host ('=' * 78) -ForegroundColor DarkCyan
foreach ($check in $checks) {
    if ($check.Passed) {
        Write-Host "[OK] $($check.Name) | $($check.Detail)" -ForegroundColor Green
    } elseif ($check.Blocking) {
        Write-Host "[KO] $($check.Name) | $($check.Detail)" -ForegroundColor Red
    } else {
        Write-Warning "$($check.Name) | $($check.Detail)"
    }
}
Write-Host "Rapport: $reportPath" -ForegroundColor DarkGray

if ($blockers.Count -gt 0) {
    Write-Host "VERDICT: PHYSICAL INSTALL NOT READY ($($blockers.Count) bloqueur(s), $($warnings.Count) avertissement(s))" -ForegroundColor Red
    if ($Strict) {
        throw "Préqualification physique échouée: $($blockers.Name -join '; '). Corrige ces prérequis puis relance; aucune convergence ne doit commencer avant un verdict READY."
    }
    return
}

Write-Host "VERDICT: PHYSICAL INSTALL READY ($($warnings.Count) avertissement(s))" -ForegroundColor Green
