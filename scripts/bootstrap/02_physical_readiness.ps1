[CmdletBinding()]
param(
    [switch]$Strict,
    [switch]$RequireFoundation
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
$nativeProcessModule = Join-Path $repoRoot 'scripts\core\native-process.psm1'

foreach ($path in @($hardwareTargetPath, $wslContractPath, $appsManifestPath, $windowsNativeModule, $nativeProcessModule)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Contrat requis introuvable: $path" }
}

Import-Module $windowsNativeModule
Import-Module $nativeProcessModule
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
    return $reasons.ToArray()
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

function Get-WindowsPowerShell51Path {
    $explicit = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $explicit) { return $explicit }
    $command = Get-WpcNativeApplication -Name 'powershell.exe'
    if ($command) { return [string]$command.Source }
    return $null
}

function Get-WslNames {
    try {
        $wslCommand = Get-WpcNativeApplication -Name 'wsl.exe'
        if (-not $wslCommand) {
            $explicit = Join-Path $env:WINDIR 'System32\wsl.exe'
            if (Test-Path -LiteralPath $explicit) { $wslCommand = [pscustomobject]@{ Source=$explicit } }
        }
        if (-not $wslCommand) { return @() }
        $result = Invoke-WpcNativeCapture -FilePath $wslCommand.Source -ArgumentList @('--list', '--quiet') -SuppressErrorOutput
        if ($result.ExitCode -ne 0) { return @() }
        $names = @(($result.Lines -replace "`0", '') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
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
$featureCompatible = ($isWindows11 -and $build -ge 22621)
Add-ReadinessCheck `
    -Name 'Windows 11 22H2 ou ultérieur' `
    -Passed $featureCompatible `
    -Detail "FEATURE_COMPATIBLE=$featureCompatible ; Caption=$($os.Caption) Build=$build ; build minimal=22621 pour le réseau WSL mirrored."

$displayVersion = 'UNKNOWN'
try {
    $displayVersion = [string](Get-ItemPropertyValue `
        -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' `
        -Name DisplayVersion `
        -ErrorAction Stop)
} catch {}

$homeProSupportEnds = @{
    '22H2' = [datetime]'2024-10-08'
    '23H2' = [datetime]'2025-11-11'
    '24H2' = [datetime]'2026-10-13'
    '25H2' = [datetime]'2027-10-12'
    '26H1' = [datetime]'2028-03-14'
}

$supportEnd = $null
if ($homeProSupportEnds.ContainsKey($displayVersion)) {
    $supportEnd = $homeProSupportEnds[$displayVersion]
}

$supportState = if (-not $isWindows11) {
    'UNSUPPORTED'
} elseif ($null -eq $supportEnd) {
    'UNKNOWN'
} elseif ((Get-Date).Date -le $supportEnd.Date) {
    'SUPPORTED'
} else {
    'UNSUPPORTED'
}

$supportEndText = if ($null -ne $supportEnd) {
    $supportEnd.ToString('yyyy-MM-dd')
} else {
    'unknown'
}

Add-ReadinessCheck `
    -Name 'Support Windows 11 Home/Pro' `
    -Passed ($supportState -eq 'SUPPORTED') `
    -Detail "SUPPORTED_OS=$supportState ; DisplayVersion=$displayVersion ; supportEnd=$supportEndText" `
    -Blocking $false

$recommendedOs = ($displayVersion -eq '25H2')
Add-ReadinessCheck `
    -Name 'Baseline Windows recommandée' `
    -Passed $recommendedOs `
    -Detail "RECOMMENDED_OS=$recommendedOs ; cible recommandée pour une workstation existante=25H2" `
    -Blocking $false

$editionId = [string](Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID -ErrorAction Stop)
Add-ReadinessCheck -Name 'Édition Windows non-Home' -Passed ($editionId -notmatch '^Core') -Detail "EditionID=$editionId"

# Une fonction PowerShell déroule sa collection dans le pipeline. Sans @(...),
# 0 raison devient $null et 1 raison devient un scalaire ; sous StrictMode,
# l'accès direct à .Count n'est alors pas fiable. Matérialiser explicitement.
$pendingReboot = @(Get-PendingRebootReasons)
Add-ReadinessCheck -Name 'Aucun redémarrage Windows en attente' -Passed ($pendingReboot.Count -eq 0) -Detail $(if ($pendingReboot.Count -eq 0) { 'Aucun marqueur de reboot détecté.' } else { $pendingReboot -join ', ' })

$c = $null
$e = $null
try { $c = Get-Volume -DriveLetter C -ErrorAction Stop } catch {}
try { $e = Get-Volume -DriveLetter E -ErrorAction Stop } catch {}
Add-ReadinessCheck -Name 'Volume C: NTFS sain' -Passed ($null -ne $c -and [string]$c.FileSystem -eq 'NTFS' -and [string]$c.HealthStatus -ne 'Unhealthy') -Detail $(if ($c) { "FS=$($c.FileSystem) Santé=$($c.HealthStatus) Libre=$([math]::Round($c.SizeRemaining / 1GB, 1)) Go" } else { 'C: absent ou illisible.' })
Add-ReadinessCheck -Name 'Volume E: NTFS sain' -Passed ($null -ne $e -and [string]$e.FileSystem -eq 'NTFS' -and [string]$e.HealthStatus -ne 'Unhealthy') -Detail $(if ($e) { "FS=$($e.FileSystem) Santé=$($e.HealthStatus) Libre=$([math]::Round($e.SizeRemaining / 1GB, 1)) Go" } else { 'E: absent ou illisible.' })
Add-ReadinessCheck -Name 'Espace WSL sur E:' -Passed ($null -ne $e -and $e.SizeRemaining -ge 50GB) -Detail $(if ($e) { "Libre=$([math]::Round($e.SizeRemaining / 1GB, 1)) Go ; minimum=50 Go" } else { 'E: indisponible.' })

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
Add-ReadinessCheck -Name 'Matériel cible V5 essentiel détecté' -Passed ($hardwareFailures.Count -eq 0) -Detail $(if ($hardwareFailures.Count -eq 0) { 'CPU, RAM 6000, carte mère et Arc B580 correspondent à la cible.' } else { $hardwareFailures -join '; ' })

$displayMatch = @($video | Where-Object {
    [int]$_.CurrentHorizontalResolution -eq [int]$hardwareTarget.display.width -and
    [int]$_.CurrentVerticalResolution -eq [int]$hardwareTarget.display.height -and
    [int]$_.CurrentRefreshRate -ge [int]$hardwareTarget.display.minimumRefreshHz
})
$displayObserved = @($video | ForEach-Object { "$($_.Name): $($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution) @$($_.CurrentRefreshRate)Hz" }) -join ' | '
Add-ReadinessCheck -Name 'Affichage cible V5 1440p240' -Passed ($displayMatch.Count -gt 0) -Detail $(if ($displayMatch.Count -gt 0) { 'Affichage 2560x1440 >=239 Hz détecté.' } else { "Non détecté avant bootstrap/pilotes. Observé: $displayObserved. La qualification matérielle finale V5 reste stricte." }) -Blocking $false

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

$foundationBlocking = [bool]$RequireFoundation
$wslFeatureState = Get-OptionalFeatureStateSafe -FeatureName 'Microsoft-Windows-Subsystem-Linux'
$vmpFeatureState = Get-OptionalFeatureStateSafe -FeatureName 'VirtualMachinePlatform'
Add-ReadinessCheck -Name 'Fonctionnalité Windows WSL active' -Passed ($wslFeatureState -eq 'Enabled') -Detail "Microsoft-Windows-Subsystem-Linux=$wslFeatureState. FullInstall peut l’activer puis demander un redémarrage." -Blocking $foundationBlocking
Add-ReadinessCheck -Name 'VirtualMachinePlatform active' -Passed ($vmpFeatureState -eq 'Enabled') -Detail "VirtualMachinePlatform=$vmpFeatureState. FullInstall peut l’activer puis demander un redémarrage." -Blocking $foundationBlocking

$restorePointProviderReady = $false
$restorePointDetail = ''
try {
    [void](Get-CimClass -Namespace 'root/default' -ClassName SystemRestore -ErrorAction Stop)
    $windowsPowerShell = Get-WindowsPowerShell51Path
    if (-not $windowsPowerShell) { throw 'Windows PowerShell 5.1 introuvable.' }

    # V22: ne jamais déduire la disponibilité de Checkpoint-Computer depuis
    # sa sortie texte. Windows PowerShell 5.1 peut produire un flux encodé
    # différemment selon l'hôte physique. Le contrat est désormais binaire:
    # code 0 = cmdlet présent, code 3 = cmdlet absent.
    $checkpointProbe = 'if ($null -eq (Get-Command Checkpoint-Computer -ErrorAction SilentlyContinue)) { [Environment]::Exit(3) } else { [Environment]::Exit(0) }'
    $checkpointResult = Invoke-WpcNativeCapture -FilePath $windowsPowerShell -ArgumentList @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', $checkpointProbe) -SuppressErrorOutput
    $restorePointProviderReady = ($checkpointResult.ExitCode -eq 0)
    $restorePointDetail = "SystemRestore WMI présent; powershell.exe=$windowsPowerShell; Checkpoint-Computer=$restorePointProviderReady; ProbeExitCode=$($checkpointResult.ExitCode)"
} catch { $restorePointDetail = $_.Exception.Message }
Add-ReadinessCheck -Name 'Garde-fou point de restauration disponible' -Passed $restorePointProviderReady -Detail $restorePointDetail

$winget = Get-WpcNativeApplication -Name 'winget.exe'
if (-not $winget) {
    $wingetAlias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path -LiteralPath $wingetAlias) { $winget = [pscustomobject]@{ Source=$wingetAlias } }
}
$wingetReady = $null -ne $winget
$wingetVersion = ''
if ($wingetReady) {
    $versionResult = Invoke-WpcNativeCapture -FilePath $winget.Source -ArgumentList @('--version') -SuppressErrorOutput
    $wingetVersion = $versionResult.Text.Trim()
    $wingetReady = ($versionResult.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($wingetVersion))
}
Add-ReadinessCheck -Name 'WinGet opérationnel' -Passed $wingetReady -Detail $(if ($wingetReady) { "Version=$wingetVersion Path=$($winget.Source)" } else { 'WinGet/App Installer absent ou non fonctionnel; FullInstall tentera le réenregistrement ou la réparation supportée.' }) -Blocking $foundationBlocking

$unresolvedApps = [System.Collections.Generic.List[string]]::new()
if ($wingetReady) {
    foreach ($app in @($appsManifest.apps | Where-Object { [bool]$_.autoInstall })) {
        $id = [string]$app.wingetId
        $showResult = Invoke-WpcNativeCapture -FilePath $winget.Source -ArgumentList @('show', '--id', $id, '--exact', '--source', 'winget', '--accept-source-agreements', '--disable-interactivity')
        if ($showResult.ExitCode -ne 0) { $unresolvedApps.Add("$($app.name) [$id]") }
    }
}
Add-ReadinessCheck -Name 'Catalogue WinGet résolvable' -Passed ($wingetReady -and $unresolvedApps.Count -eq 0) -Detail $(if (-not $wingetReady) { 'WinGet indisponible avant bootstrap.' } elseif ($unresolvedApps.Count -eq 0) { 'Tous les IDs autoInstall sont résolus avant convergence applicative.' } else { $unresolvedApps -join '; ' }) -Blocking $foundationBlocking

$wsl = Get-WpcNativeApplication -Name 'wsl.exe'
if (-not $wsl) {
    $wslExplicit = Join-Path $env:WINDIR 'System32\wsl.exe'
    if (Test-Path -LiteralPath $wslExplicit) { $wsl = [pscustomobject]@{ Source=$wslExplicit } }
}
$wslVersionReady = $false
$wslVersionText = ''
if ($wsl) {
    $wslVersionResult = Invoke-WpcNativeCapture -FilePath $wsl.Source -ArgumentList @('--version')
    $wslVersionText = $wslVersionResult.Text.Trim()
    $wslVersionReady = ($wslVersionResult.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($wslVersionText))
}
Add-ReadinessCheck -Name 'Runtime WSL Store opérationnel' -Passed ($null -ne $wsl -and $wslVersionReady) -Detail $(if ($wslVersionReady) { ($wslVersionText -split "`r?`n" | Select-Object -First 1) } else { 'wsl --version a échoué; FullInstall tentera wsl --update --web-download après activation des fonctionnalités.' }) -Blocking $foundationBlocking

$distribution = [string]$wslContract.distribution
$sourceDistribution = [string]$wslContract.sourceDistribution
$wslNames = if ($wsl -and $wslVersionReady) { Get-WslNames } else { @() }
$distributionPresent = $wslNames -contains $distribution
Add-ReadinessCheck -Name 'Nom de distribution WSL cible cohérent' -Passed (-not [string]::IsNullOrWhiteSpace($distribution) -and -not [string]::IsNullOrWhiteSpace($sourceDistribution)) -Detail "Nom enregistré=$distribution ; source épinglée=$sourceDistribution"

if (-not $distributionPresent -and $wslVersionReady) {
    $wslHelpResult = Invoke-WpcNativeCapture -FilePath $wsl.Source -ArgumentList @('--help')
    $wslHelp = $wslHelpResult.Text
    $installCapabilities = ($wslHelp -match '--location' -and $wslHelp -match '--name' -and $wslHelp -match '--no-launch')
    Add-ReadinessCheck -Name 'WSL sait installer avec nom et emplacement explicites' -Passed $installCapabilities -Detail 'Options requises: --location, --name, --no-launch. Le bootstrap tente wsl --update --web-download si nécessaire.' -Blocking $foundationBlocking

    $onlineResult = Invoke-WpcNativeCapture -FilePath $wsl.Source -ArgumentList @('--list', '--online')
    $online = $onlineResult.Text -replace "`0", ''
    $sourceAvailable = ($onlineResult.ExitCode -eq 0 -and $online -match "(?m)^\s*$([regex]::Escape($sourceDistribution))\s")
    Add-ReadinessCheck -Name 'Ubuntu 26.04 explicite disponible dans WSL' -Passed $sourceAvailable -Detail "Source attendue=$sourceDistribution" -Blocking $foundationBlocking
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
    Version = 'V22'
    Timestamp = (Get-Date).ToString('o')
    Strict = [bool]$Strict
    RequireFoundation = [bool]$RequireFoundation
    Computer = $env:COMPUTERNAME
    User = $env:USERNAME
    PowerShell = [ordered]@{ Edition=[string]$PSVersionTable.PSEdition; Version=$psVersion.ToString() }
    Windows = [ordered]@{
        Caption = [string]$os.Caption
        Build = $build
        DisplayVersion = $displayVersion
        EditionID = $editionId
        FeatureCompatible = $featureCompatible
        SupportState = $supportState
        SupportEnd = $supportEndText
        Recommended = $recommendedOs
    }
    Wsl = [ordered]@{ Distribution=$distribution; SourceDistribution=$sourceDistribution; Present=$distributionPresent }
    Checks = $checks.ToArray()
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

if ($warnings.Count -gt 0 -and -not $RequireFoundation) {
    Write-Host "VERDICT: PHYSICAL INSTALL READY FOR FOUNDATION BOOTSTRAP ($($warnings.Count) élément(s) à préparer avant convergence)" -ForegroundColor Green
} else {
    Write-Host "VERDICT: PHYSICAL INSTALL READY ($($warnings.Count) avertissement(s))" -ForegroundColor Green
}
