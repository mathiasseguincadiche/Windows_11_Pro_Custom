#Requires -Version 7.6
[CmdletBinding()]
param(
    [switch]$Strict,
    [switch]$RequireFoundation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$release = (Get-Content -Raw (Join-Path $repoRoot 'VERSION')).Trim()
if ($release -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION invalide: $release" }
$reportDir = Join-Path $repoRoot 'reports\physical-readiness'
$reportPath = Join-Path $reportDir 'physical-install-readiness.json'
$hardwareTargetPath = Join-Path $repoRoot 'config\hardware\target.json'
$wslContractPath = Join-Path $repoRoot 'config\wsl\runtime-contract.json'
$appsManifestPath = Join-Path $repoRoot 'manifests\winget\apps-core.json'
$windowsNativeModule = Join-Path $repoRoot 'scripts\core\windows-native.psm1'
$nativeProcessModule = Join-Path $repoRoot 'scripts\core\native-process.psm1'
$rebootStateModule = Join-Path $repoRoot 'scripts\core\reboot-state.psm1'
$powerShellRuntimeModule = Join-Path $repoRoot 'scripts\core\powershell-runtime.psm1'
$hardwareSymbiosisScript = Join-Path $repoRoot 'scripts\windows\52_hardware_symbiosis.ps1'
$hardwareSymbiosisReport = Join-Path $repoRoot 'reports\hardware\hardware-symbiosis.json'
foreach ($path in @($hardwareTargetPath,$wslContractPath,$appsManifestPath,$windowsNativeModule,$nativeProcessModule,$rebootStateModule,$powerShellRuntimeModule,$hardwareSymbiosisScript)) { if (-not (Test-Path -LiteralPath $path)) { throw "Contrat requis introuvable: $path" } }
Import-Module $powerShellRuntimeModule -Force
$powerShellRuntimeFact = Assert-WpcPowerShellRuntime -MinimumVersion ([version]'7.6.5') -RequireWindows -PassThru
Import-Module $windowsNativeModule
Import-Module $nativeProcessModule
Import-Module $rebootStateModule -Force
[void]@(Initialize-WpcWindowsNativeModules -Profile Full)
$hardwareTarget = Get-Content -Raw $hardwareTargetPath | ConvertFrom-Json
$wslContract = Get-Content -Raw $wslContractPath | ConvertFrom-Json
$appsManifest = Get-Content -Raw $appsManifestPath | ConvertFrom-Json
$checks = [System.Collections.Generic.List[object]]::new()

function Add-ReadinessCheck {
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][bool]$Passed,[Parameter(Mandatory)][string]$Detail,[bool]$Blocking=$true)
    $checks.Add([pscustomobject]@{ Name=$Name; Passed=$Passed; Blocking=$Blocking; Detail=$Detail })
}
function Test-Administrator {
    try { $identity=[Security.Principal.WindowsIdentity]::GetCurrent(); $principal=[Security.Principal.WindowsPrincipal]::new($identity); return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { return $false }
}
function Get-PendingRebootReasons { $state=Get-WpcPendingRebootState; return @($state.Reasons) }
function Get-OptionalFeatureStateSafe {
    param([Parameter(Mandatory)][string]$FeatureName)
    try { if (-not (Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue)) { Import-Module Dism -ErrorAction Stop }; $feature=Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction Stop; return [string]$feature.State }
    catch { return "UNKNOWN: $($_.Exception.Message)" }
}
function Get-WslNames {
    try {
        $wslCommand=Get-WpcNativeApplication -Name 'wsl.exe'; if (-not $wslCommand) { $explicit=Join-Path $env:WINDIR 'System32\wsl.exe'; if (Test-Path -LiteralPath $explicit) { $wslCommand=[pscustomobject]@{Source=$explicit} } }
        if (-not $wslCommand) { return @() }
        $result=Invoke-WpcNativeCapture -FilePath $wslCommand.Source -ArgumentList @('--list','--quiet') -SuppressErrorOutput; if ($result.ExitCode -ne 0) { return @() }
        return @($result.Lines -replace "`0", '' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    } catch { return @() }
}
function Test-TcpEndpoint {
    param([Parameter(Mandatory)][string]$HostName)
    $client=[Net.Sockets.TcpClient]::new(); try { $task=$client.ConnectAsync($HostName,443); if (-not $task.Wait(2500)) { return $false }; return $client.Connected } catch { return $false } finally { $client.Dispose() }
}

$os=Get-CimInstance Win32_OperatingSystem; $computer=Get-CimInstance Win32_ComputerSystem; $cpu=Get-CimInstance Win32_Processor | Select-Object -First 1
$memory=@(Get-CimInstance Win32_PhysicalMemory); $board=Get-CimInstance Win32_BaseBoard | Select-Object -First 1; $video=@(Get-CimInstance Win32_VideoController)
$psVersion=[version]$powerShellRuntimeFact.Version
Add-ReadinessCheck -Name 'PowerShell 7.6.5+ Core x64' -Passed $true -Detail "Edition=$($powerShellRuntimeFact.Edition) Version=$psVersion Executable=$($powerShellRuntimeFact.ExecutableName) Process64=$($powerShellRuntimeFact.Is64BitProcess) ; minimum=7.6.5. Windows PowerShell 5.1 non supporté."
Add-ReadinessCheck -Name 'Session administrateur' -Passed (Test-Administrator) -Detail "Utilisateur=$env:USERNAME"
Add-ReadinessCheck -Name 'Processus et OS 64 bits' -Passed ([Environment]::Is64BitOperatingSystem -and [Environment]::Is64BitProcess) -Detail "OS64=$([Environment]::Is64BitOperatingSystem) Process64=$([Environment]::Is64BitProcess)"

$isWindows11=([string]$os.Caption -match 'Windows 11'); $build=[int]$os.BuildNumber; $featureCompatible=($isWindows11 -and $build -ge 22621)
Add-ReadinessCheck -Name 'Windows 11 22H2 ou ultérieur' -Passed $featureCompatible -Detail "FEATURE_COMPATIBLE=$featureCompatible ; Caption=$($os.Caption) Build=$build ; build minimal=22621 pour le réseau WSL mirrored."
$displayVersion='UNKNOWN'; try { $displayVersion=[string](Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name DisplayVersion -ErrorAction Stop) } catch {}
$homeProSupportEnds=@{ '22H2'=[datetime]'2024-10-08'; '23H2'=[datetime]'2025-11-11'; '24H2'=[datetime]'2026-10-13'; '25H2'=[datetime]'2027-10-12'; '26H1'=[datetime]'2028-03-14' }
$supportEnd=if ($homeProSupportEnds.ContainsKey($displayVersion)) {$homeProSupportEnds[$displayVersion]} else {$null}
$supportState=if (-not $isWindows11) {'UNSUPPORTED'} elseif ($null -eq $supportEnd) {'UNKNOWN'} elseif ((Get-Date).Date -le $supportEnd.Date) {'SUPPORTED'} else {'UNSUPPORTED'}
$supportEndText=if ($supportEnd) {$supportEnd.ToString('yyyy-MM-dd')} else {'unknown'}
Add-ReadinessCheck -Name 'Support Windows 11 Home/Pro' -Passed ($supportState -eq 'SUPPORTED') -Detail "SUPPORTED_OS=$supportState ; DisplayVersion=$displayVersion ; supportEnd=$supportEndText" -Blocking $false
$recommendedOs=($displayVersion -eq '25H2'); Add-ReadinessCheck -Name 'Baseline Windows recommandée' -Passed $recommendedOs -Detail "RECOMMENDED_OS=$recommendedOs ; cible recommandée pour une workstation existante=25H2" -Blocking $false
$editionId=[string](Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID -ErrorAction Stop)
Add-ReadinessCheck -Name 'Édition Windows non-Home' -Passed ($editionId -notmatch '^Core') -Detail "EditionID=$editionId"

$pendingReboot=@(Get-PendingRebootReasons); $pendingRebootState=Get-WpcPendingRebootState
Add-ReadinessCheck -Name 'Aucun redémarrage Windows en attente' -Passed ($pendingReboot.Count -eq 0) -Detail $(if ($pendingReboot.Count -eq 0) {'Aucun marqueur CBS/Windows Update bloquant détecté.'} else {$pendingReboot -join ', '})
Add-ReadinessCheck -Name 'PendingFileRenameOperations non bloquant' -Passed (-not $pendingRebootState.Advisory) -Detail $(if ($pendingRebootState.Advisory) {"Signal observé: $($pendingRebootState.PendingFileRenameOperationsCount) entrée(s). À lui seul, ce marqueur ne force plus un reboot et ne bloque pas la convergence."} else {'Aucune opération de renommage différée observée.'}) -Blocking $false

$c=$null; $e=$null; try {$c=Get-Volume -DriveLetter C -ErrorAction Stop} catch {}; try {$e=Get-Volume -DriveLetter E -ErrorAction Stop} catch {}
Add-ReadinessCheck -Name 'Volume C: NTFS sain' -Passed ($null -ne $c -and [string]$c.FileSystem -eq 'NTFS' -and [string]$c.HealthStatus -ne 'Unhealthy') -Detail $(if ($c) {"FS=$($c.FileSystem) Santé=$($c.HealthStatus) Libre=$([math]::Round($c.SizeRemaining/1GB,1)) Go"} else {'C: absent ou illisible.'})
Add-ReadinessCheck -Name 'Volume E: NTFS sain' -Passed ($null -ne $e -and [string]$e.FileSystem -eq 'NTFS' -and [string]$e.HealthStatus -ne 'Unhealthy') -Detail $(if ($e) {"FS=$($e.FileSystem) Santé=$($e.HealthStatus) Libre=$([math]::Round($e.SizeRemaining/1GB,1)) Go"} else {'E: absent ou illisible.'})
Add-ReadinessCheck -Name 'Espace WSL sur E:' -Passed ($null -ne $e -and $e.SizeRemaining -ge 50GB) -Detail $(if ($e) {"Libre=$([math]::Round($e.SizeRemaining/1GB,1)) Go ; minimum=50 Go"} else {'E: indisponible.'})

$systemDiskGpt=$false; try {$systemPartition=Get-Partition -DriveLetter C -ErrorAction Stop; $systemDisk=Get-Disk -Number $systemPartition.DiskNumber -ErrorAction Stop; $systemDiskGpt=([string]$systemDisk.PartitionStyle -eq 'GPT'); $systemDiskDetail="Disque=$($systemDisk.Number) Style=$($systemDisk.PartitionStyle)"} catch {$systemDiskDetail=$_.Exception.Message}
Add-ReadinessCheck -Name 'Disque système GPT/UEFI' -Passed $systemDiskGpt -Detail $systemDiskDetail
$secureBoot=$false; try {$secureBoot=[bool](Confirm-SecureBootUEFI -ErrorAction Stop)} catch {}; Add-ReadinessCheck -Name 'Secure Boot actif' -Passed $secureBoot -Detail "SecureBoot=$secureBoot"
$tpmReady=$false; $tpmDetail='TPM non lisible.'; try {$tpm=Get-Tpm -ErrorAction Stop; $tpmReady=[bool]($tpm.TpmPresent -and $tpm.TpmReady -and $tpm.TpmEnabled); $tpmDetail="Present=$($tpm.TpmPresent) Ready=$($tpm.TpmReady) Enabled=$($tpm.TpmEnabled)"} catch {$tpmDetail=$_.Exception.Message}
Add-ReadinessCheck -Name 'TPM prêt' -Passed $tpmReady -Detail $tpmDetail
$virtualization=[bool]$cpu.VirtualizationFirmwareEnabled; Add-ReadinessCheck -Name 'Virtualisation firmware active' -Passed $virtualization -Detail "CPU=$($cpu.Name) VirtualizationFirmwareEnabled=$virtualization"

$hardwareFailures=[System.Collections.Generic.List[string]]::new()
if ([string]$cpu.Name -notlike "*$($hardwareTarget.cpu.nameContains)*") {$hardwareFailures.Add("CPU=$($cpu.Name)")}
if ([int]$cpu.NumberOfCores -ne [int]$hardwareTarget.cpu.cores) {$hardwareFailures.Add("Cœurs=$($cpu.NumberOfCores)")}
if ([int]$cpu.NumberOfLogicalProcessors -ne [int]$hardwareTarget.cpu.threads) {$hardwareFailures.Add("Threads=$($cpu.NumberOfLogicalProcessors)")}
$totalMemory=($memory | Measure-Object -Property Capacity -Sum).Sum
if ([int64]$totalMemory -lt [int64]$hardwareTarget.memory.minimumBytes) {$hardwareFailures.Add("RAM=$([math]::Round($totalMemory/1GB,1)) Go")}
if (@($memory | Where-Object {[int]$_.ConfiguredClockSpeed -lt [int]$hardwareTarget.memory.targetConfiguredClockMHz}).Count -gt 0) {$hardwareFailures.Add('DDR5 configurée sous 6000 MT/s')}
if ([string]$board.Product -notlike "*$($hardwareTarget.motherboard.productContains)*") {$hardwareFailures.Add("Carte mère=$($board.Product)")}
$arc=@($video | Where-Object {[string]$_.Name -match [string]$hardwareTarget.gpu.nameRegex}); if ($arc.Count -eq 0) {$hardwareFailures.Add('Intel Arc B580 non détectée')}
Add-ReadinessCheck -Name 'Matériel cible essentiel détecté' -Passed ($hardwareFailures.Count -eq 0) -Detail $(if ($hardwareFailures.Count -eq 0) {'CPU, RAM 6000, carte mère et Arc B580 correspondent à la cible.'} else {$hardwareFailures -join '; '})
$displayMatch=@($video | Where-Object {[int]$_.CurrentHorizontalResolution -eq [int]$hardwareTarget.display.width -and [int]$_.CurrentVerticalResolution -eq [int]$hardwareTarget.display.height -and [int]$_.CurrentRefreshRate -ge [int]$hardwareTarget.display.minimumRefreshHz})
$displayObserved=@($video | ForEach-Object {"$($_.Name): $($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution) @$($_.CurrentRefreshRate)Hz"}) -join ' | '
Add-ReadinessCheck -Name 'Affichage cible 1440p240' -Passed ($displayMatch.Count -gt 0) -Detail $(if ($displayMatch.Count -gt 0) {'Affichage 2560x1440 >=239 Hz détecté.'} else {"Non détecté actuellement. Observé: $displayObserved. Information uniquement; ne bloque pas l'installation."}) -Blocking $false

# La symbiose est auditée ici. Seuls les HardCheckFailures matériels critiques deviennent bloquants.
$symbiosisReady=$false
$symbiosisDetail='Qualification matérielle non exécutée.'
$driverFindings=@()
try {
    [void]@(& $hardwareSymbiosisScript -Mode Audit *>&1)
    if (-not (Test-Path -LiteralPath $hardwareSymbiosisReport)) { throw "Rapport de symbiose introuvable après audit: $hardwareSymbiosisReport" }
    $symbiosisReport=Get-Content -Raw -LiteralPath $hardwareSymbiosisReport | ConvertFrom-Json
    $hardFailures=@($symbiosisReport.HardCheckFailures)
    $driverFindings=@($symbiosisReport.DriverFindings)
    $symbiosisReady=($hardFailures.Count -eq 0)
    $symbiosisDetail=if ($symbiosisReady) {
        "Matériel critique conforme. Informations pilotes à vérifier=$($driverFindings.Count). Ces informations ne bloquent pas l'installation."
    } else {
        @($hardFailures | ForEach-Object { "$($_.Name): $($_.Detail)" }) -join ' | '
    }
} catch {
    $symbiosisDetail=$_.Exception.Message
}
Add-ReadinessCheck -Name 'Symbiose matérielle critique' -Passed $symbiosisReady -Detail $symbiosisDetail
foreach ($finding in $driverFindings) {
    Add-ReadinessCheck -Name ("Pilote à vérifier: {0}" -f [string]$finding.Name) -Passed $false -Detail ("{0}. Installation non bloquée; le rapport détaillé reste disponible dans reports\hardware\hardware-symbiosis.json." -f [string]$finding.Detail) -Blocking $false
}
if ($driverFindings.Count -eq 0) {
    Add-ReadinessCheck -Name 'Pilotes observés' -Passed $true -Detail 'Aucun écart de présence/version détecté par la politique de pilotes.' -Blocking $false
}

$foundationBlocking=[bool]$RequireFoundation
$wslFeatureState=Get-OptionalFeatureStateSafe -FeatureName 'Microsoft-Windows-Subsystem-Linux'; $vmpFeatureState=Get-OptionalFeatureStateSafe -FeatureName 'VirtualMachinePlatform'
Add-ReadinessCheck -Name 'Fonctionnalité Windows WSL active' -Passed ($wslFeatureState -eq 'Enabled') -Detail "Microsoft-Windows-Subsystem-Linux=$wslFeatureState. FullInstall peut l’activer puis demander un redémarrage." -Blocking $foundationBlocking
Add-ReadinessCheck -Name 'VirtualMachinePlatform active' -Passed ($vmpFeatureState -eq 'Enabled') -Detail "VirtualMachinePlatform=$vmpFeatureState. FullInstall peut l’activer puis demander un redémarrage." -Blocking $foundationBlocking

$restorePointProviderReady=$false; $restorePointDetail=''
try {
    $systemRestoreClass=Get-CimClass -Namespace 'root/default' -ClassName SystemRestore -ErrorAction Stop
    $methodNames=@($systemRestoreClass.CimClassMethods.Keys)
    $restorePointProviderReady=($methodNames -contains 'CreateRestorePoint' -and $methodNames -contains 'Enable')
    $restorePointDetail="SystemRestore CIM/WMI présent; CreateRestorePoint=$($methodNames -contains 'CreateRestorePoint'); Enable=$($methodNames -contains 'Enable'); aucun powershell.exe requis."
} catch {$restorePointDetail=$_.Exception.Message}
Add-ReadinessCheck -Name 'Garde-fou point de restauration disponible' -Passed $restorePointProviderReady -Detail $restorePointDetail

$winget=Get-WpcNativeApplication -Name 'winget.exe'; if (-not $winget) {$wingetAlias=Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'; if (Test-Path -LiteralPath $wingetAlias) {$winget=[pscustomobject]@{Source=$wingetAlias}}}
$wingetReady=$null -ne $winget; $wingetVersion=''
if ($wingetReady) {$versionResult=Invoke-WpcNativeCapture -FilePath $winget.Source -ArgumentList @('--version') -SuppressErrorOutput; $wingetVersion=$versionResult.Text.Trim(); $wingetReady=($versionResult.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($wingetVersion))}
Add-ReadinessCheck -Name 'WinGet opérationnel' -Passed $wingetReady -Detail $(if ($wingetReady) {"Version=$wingetVersion Path=$($winget.Source)"} else {'WinGet/App Installer absent ou non fonctionnel; FullInstall tentera la réparation Microsoft.WinGet.Client sous PowerShell 7.'}) -Blocking $foundationBlocking
$unresolvedApps=[System.Collections.Generic.List[string]]::new()
if ($wingetReady) {foreach ($app in @($appsManifest.apps | Where-Object {[bool]$_.autoInstall})) {$id=[string]$app.wingetId; $showResult=Invoke-WpcNativeCapture -FilePath $winget.Source -ArgumentList @('show','--id',$id,'--exact','--source','winget','--accept-source-agreements','--disable-interactivity'); if ($showResult.ExitCode -ne 0) {$unresolvedApps.Add("$($app.name) [$id]")}}}
Add-ReadinessCheck -Name 'Catalogue WinGet résolvable' -Passed ($wingetReady -and $unresolvedApps.Count -eq 0) -Detail $(if (-not $wingetReady) {'WinGet indisponible avant bootstrap.'} elseif ($unresolvedApps.Count -eq 0) {'Tous les IDs autoInstall sont résolus avant convergence applicative.'} else {$unresolvedApps -join '; '}) -Blocking $foundationBlocking

$wsl=Get-WpcNativeApplication -Name 'wsl.exe'; if (-not $wsl) {$wslExplicit=Join-Path $env:WINDIR 'System32\wsl.exe'; if (Test-Path -LiteralPath $wslExplicit) {$wsl=[pscustomobject]@{Source=$wslExplicit}}}
$wslVersionReady=$false; $wslVersionText=''; if ($wsl) {$wslVersionResult=Invoke-WpcNativeCapture -FilePath $wsl.Source -ArgumentList @('--version'); $wslVersionText=$wslVersionResult.Text.Trim(); $wslVersionReady=($wslVersionResult.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($wslVersionText))}
Add-ReadinessCheck -Name 'Runtime WSL Store opérationnel' -Passed ($null -ne $wsl -and $wslVersionReady) -Detail $(if ($wslVersionReady) {($wslVersionText -split "`r?`n" | Select-Object -First 1)} else {'wsl --version a échoué; FullInstall tentera wsl --update --web-download après activation des fonctionnalités.'}) -Blocking $foundationBlocking
$distribution=[string]$wslContract.distribution; $sourceDistribution=[string]$wslContract.sourceDistribution; $wslNames=if ($wsl -and $wslVersionReady) {Get-WslNames} else {@()}; $distributionPresent=$wslNames -contains $distribution
Add-ReadinessCheck -Name 'Nom de distribution WSL cible cohérent' -Passed (-not [string]::IsNullOrWhiteSpace($distribution) -and -not [string]::IsNullOrWhiteSpace($sourceDistribution)) -Detail "Nom enregistré=$distribution ; source épinglée=$sourceDistribution"
if (-not $distributionPresent -and $wslVersionReady) {
    $wslHelpResult=Invoke-WpcNativeCapture -FilePath $wsl.Source -ArgumentList @('--help'); $wslHelp=$wslHelpResult.Text; $installCapabilities=($wslHelp -match '--location' -and $wslHelp -match '--name' -and $wslHelp -match '--no-launch')
    Add-ReadinessCheck -Name 'WSL sait installer avec nom et emplacement explicites' -Passed $installCapabilities -Detail 'Options requises: --location, --name, --no-launch. Le bootstrap tente wsl --update --web-download si nécessaire.' -Blocking $foundationBlocking
    $onlineResult=Invoke-WpcNativeCapture -FilePath $wsl.Source -ArgumentList @('--list','--online'); $online=$onlineResult.Text -replace "`0", ''; $sourceAvailable=($onlineResult.ExitCode -eq 0 -and $online -match "(?m)^\s*$([regex]::Escape($sourceDistribution))\s")
    Add-ReadinessCheck -Name 'Ubuntu 26.04 explicite disponible dans WSL' -Passed $sourceAvailable -Detail "Source attendue=$sourceDistribution" -Blocking $foundationBlocking
} elseif ($distributionPresent) {Add-ReadinessCheck -Name 'Distribution WSL déjà enregistrée' -Passed $true -Detail "$distribution est déjà présente; sa version et son emplacement seront revalidés par 06_wsl.ps1."}

$networkHosts=@('github.com','dl.k8s.io','get.helm.sh','releases.hashicorp.com','awscli.amazonaws.com','storage.googleapis.com','download.docker.com','cli.github.com','aquasecurity.github.io')
$unreachable=[System.Collections.Generic.List[string]]::new(); foreach ($hostName in $networkHosts) {if (-not (Test-TcpEndpoint -HostName $hostName)) {$unreachable.Add($hostName)}}
Add-ReadinessCheck -Name 'Accès réseau aux fournisseurs DevOps' -Passed ($unreachable.Count -eq 0) -Detail $(if ($unreachable.Count -eq 0) {'TCP/443 joignable pour tous les fournisseurs requis.'} else {"Non joignables actuellement: $($unreachable -join ', '). Les téléchargements réels disposent néanmoins de leurs propres vérifications/retries."}) -Blocking $false

New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$blockers=@($checks | Where-Object {$_.Blocking -and -not $_.Passed}); $warnings=@($checks | Where-Object {-not $_.Blocking -and -not $_.Passed})
[ordered]@{ Release=$release; SchemaVersion=2; Timestamp=(Get-Date).ToString('o'); Strict=[bool]$Strict; RequireFoundation=[bool]$RequireFoundation; Computer=$env:COMPUTERNAME; User=$env:USERNAME; PowerShell=[ordered]@{Edition=[string]$powerShellRuntimeFact.Edition; Version=$psVersion.ToString(); MinimumVersion='7.6.5'; Executable=[string]$powerShellRuntimeFact.ExecutableName; Is64BitProcess=[bool]$powerShellRuntimeFact.Is64BitProcess; WindowsPowerShellSupported=$false}; Windows=[ordered]@{Caption=[string]$os.Caption; Build=$build; DisplayVersion=$displayVersion; EditionID=$editionId; FeatureCompatible=$featureCompatible; SupportState=$supportState; SupportEnd=$supportEndText; Recommended=$recommendedOs}; Wsl=[ordered]@{Distribution=$distribution; SourceDistribution=$sourceDistribution; Present=$distributionPresent}; Checks=$checks.ToArray(); DriverFindingCount=$driverFindings.Count; BlockerCount=$blockers.Count; WarningCount=$warnings.Count; Ready=($blockers.Count -eq 0) } | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 $reportPath

Write-Host ''; Write-Host ('='*78) -ForegroundColor DarkCyan; Write-Host '  PRÉQUALIFICATION INSTALLATION PHYSIQUE' -ForegroundColor Cyan; Write-Host ('='*78) -ForegroundColor DarkCyan
foreach ($check in $checks) {if ($check.Passed) {Write-Host "[OK] $($check.Name) | $($check.Detail)" -ForegroundColor Green} elseif ($check.Blocking) {Write-Host "[KO] $($check.Name) | $($check.Detail)" -ForegroundColor Red} else {Write-Host "[AVERTISSEMENT] $($check.Name) | $($check.Detail)" -ForegroundColor Yellow}}
Write-Host "Rapport détaillé: $reportPath" -ForegroundColor DarkGray
if ($blockers.Count -gt 0) {Write-Host "VERDICT: PHYSICAL INSTALL NOT READY ($($blockers.Count) bloqueur(s), $($warnings.Count) avertissement(s))" -ForegroundColor Red; if ($Strict) {throw "Préqualification physique échouée: $($blockers.Name -join '; '). Corrige uniquement les prérequis bloquants puis relance; les informations pilotes ne bloquent jamais l'installation."}; return}
if ($warnings.Count -gt 0 -and -not $RequireFoundation) {Write-Host "VERDICT: PHYSICAL INSTALL READY FOR FOUNDATION BOOTSTRAP ($($warnings.Count) avertissement(s) non bloquant(s))" -ForegroundColor Green} else {Write-Host "VERDICT: PHYSICAL INSTALL READY ($($warnings.Count) avertissement(s) non bloquant(s))" -ForegroundColor Green}
