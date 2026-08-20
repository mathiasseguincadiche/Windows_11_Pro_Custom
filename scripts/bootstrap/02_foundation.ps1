#Requires -Version 7.6
[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Verify')]
    [string]$Mode = 'Apply'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$nativeProcessModule = Join-Path $repoRoot 'scripts\core\native-process.psm1'
$powerShellRuntimeModule = Join-Path $repoRoot 'scripts\core\powershell-runtime.psm1'
foreach ($required in @($nativeProcessModule,$powerShellRuntimeModule)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Helper requis introuvable: $required" }
}
Import-Module $powerShellRuntimeModule -Force
[void](Assert-WpcPowerShellRuntime -MinimumVersion ([version]'7.6.4') -RequireWindows -PassThru)
Import-Module $nativeProcessModule -Force

function Get-OptionalFeatureStateSafe {
    param([Parameter(Mandatory)][string]$FeatureName)
    if (-not (Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue)) {
        Import-Module Dism -ErrorAction Stop
    }
    $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction Stop
    return [string]$feature.State
}

function Get-WinGetFact {
    $command = Get-WpcNativeApplication -Name 'winget.exe'
    if (-not $command) {
        $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
        if (Test-Path -LiteralPath $alias) {
            $command = [pscustomobject]@{ Source = $alias }
        }
    }
    if (-not $command) {
        return [pscustomobject]@{ Ready=$false; Source=$null; Version=''; Detail='winget.exe introuvable.' }
    }

    try {
        $result = Invoke-WpcNativeCapture -FilePath $command.Source -ArgumentList @('--version') -SuppressErrorOutput
        $version = $result.Text.Trim()
        $ready = ($result.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($version))
        return [pscustomobject]@{
            Ready = $ready
            Source = [string]$command.Source
            Version = $version
            Detail = if ($ready) { "Version=$version Path=$($command.Source)" } else { "winget --version a échoué (code=$($result.ExitCode))." }
        }
    } catch {
        return [pscustomobject]@{ Ready=$false; Source=[string]$command.Source; Version=''; Detail=$_.Exception.Message }
    }
}

function Get-WslFact {
    $command = Get-WpcNativeApplication -Name 'wsl.exe'
    if (-not $command) {
        $explicit = Join-Path $env:WINDIR 'System32\wsl.exe'
        if (Test-Path -LiteralPath $explicit) { $command = [pscustomobject]@{ Source=$explicit } }
    }
    if (-not $command) {
        return [pscustomobject]@{ Ready=$false; Source=$null; Version=''; Detail='wsl.exe introuvable.' }
    }

    try {
        $result = Invoke-WpcNativeCapture -FilePath $command.Source -ArgumentList @('--version') -SuppressErrorOutput
        $text = $result.Text.Trim()
        return [pscustomobject]@{
            Ready = ($result.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($text))
            Source = [string]$command.Source
            Version = $text
            Detail = if ($result.ExitCode -eq 0) { ($text -split "`r?`n" | Select-Object -First 1) } else { "wsl --version a échoué (code=$($result.ExitCode))." }
        }
    } catch {
        return [pscustomobject]@{ Ready=$false; Source=[string]$command.Source; Version=''; Detail=$_.Exception.Message }
    }
}

function Repair-WpcWinGetPowerShell7 {
    Write-Host '[EN COURS] Réparation WinGet via Microsoft.WinGet.Client dans PowerShell 7...' -ForegroundColor Cyan
    $originalPolicy = $null
    $gallery = $null
    try {
        Install-PackageProvider -Name NuGet -Force -ForceBootstrap -Confirm:$false | Out-Null
        $gallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if (-not $gallery) {
            Register-PSRepository -Default
            $gallery = Get-PSRepository -Name PSGallery -ErrorAction Stop
        }
        $originalPolicy = [string]$gallery.InstallationPolicy
        if ($originalPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }
        Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -Scope AllUsers -AllowClobber -Confirm:$false | Out-Null
        Import-Module Microsoft.WinGet.Client -Force -ErrorAction Stop
        if (-not (Get-Command Repair-WinGetPackageManager -ErrorAction SilentlyContinue)) {
            throw 'Repair-WinGetPackageManager est absent après import de Microsoft.WinGet.Client.'
        }
        Repair-WinGetPackageManager -Force -Latest
    }
    finally {
        if ($gallery -and $originalPolicy -and $originalPolicy -ne 'Trusted') {
            try { Set-PSRepository -Name PSGallery -InstallationPolicy $originalPolicy } catch {}
        }
    }
}

function Show-FoundationState {
    param(
        [string]$WslState,
        [string]$VmpState,
        $WinGetFact,
        $WslFact
    )
    Write-Host "WSL optional feature : $WslState"
    Write-Host "VirtualMachinePlatform: $VmpState"
    Write-Host "WinGet               : $($WinGetFact.Detail)"
    Write-Host "WSL runtime          : $($WslFact.Detail)"
}

$wslFeatureState = Get-OptionalFeatureStateSafe -FeatureName 'Microsoft-Windows-Subsystem-Linux'
$vmpFeatureState = Get-OptionalFeatureStateSafe -FeatureName 'VirtualMachinePlatform'
$wingetFact = Get-WinGetFact
$wslFact = Get-WslFact

if ($Mode -eq 'Audit') {
    Show-FoundationState -WslState $wslFeatureState -VmpState $vmpFeatureState -WinGetFact $wingetFact -WslFact $wslFact
    return
}

$foundationReady = (
    $wslFeatureState -eq 'Enabled' -and
    $vmpFeatureState -eq 'Enabled' -and
    [bool]$wingetFact.Ready -and
    [bool]$wslFact.Ready
)

if ($Mode -eq 'Verify') {
    if (-not $foundationReady) {
        $failures = [System.Collections.Generic.List[string]]::new()
        if ($wslFeatureState -ne 'Enabled') { $failures.Add("Microsoft-Windows-Subsystem-Linux=$wslFeatureState") }
        if ($vmpFeatureState -ne 'Enabled') { $failures.Add("VirtualMachinePlatform=$vmpFeatureState") }
        if (-not $wingetFact.Ready) { $failures.Add("WinGet: $($wingetFact.Detail)") }
        if (-not $wslFact.Ready) { $failures.Add("WSL runtime: $($wslFact.Detail)") }
        throw "Fondations Windows non conformes: $($failures -join '; ')"
    }
    Write-Host '[OK] Fondations Windows prêtes: PowerShell 7, WSL/VMP, WinGet et runtime WSL opérationnels.' -ForegroundColor Green
    return
}

$changes = [System.Collections.Generic.List[string]]::new()
$restartRequired = $false

foreach ($featureName in @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')) {
    $state = Get-OptionalFeatureStateSafe -FeatureName $featureName
    if ($state -eq 'Enabled') {
        Write-Host "[DÉJÀ OK] Fonctionnalité Windows $featureName déjà active." -ForegroundColor Green
        continue
    }

    Write-Host "[EN COURS] Activation de la fonctionnalité Windows $featureName..." -ForegroundColor Cyan
    $featureResult = Enable-WindowsOptionalFeature -Online -FeatureName $featureName -All -NoRestart -ErrorAction Stop
    $afterState = Get-OptionalFeatureStateSafe -FeatureName $featureName
    if ($afterState -ne 'Enabled' -and $afterState -ne 'EnablePending') {
        throw "Activation de $featureName non confirmée. État observé=$afterState"
    }
    $changes.Add("$featureName activée")
    $restartRequired = $true
    if ($featureResult.RestartNeeded) { $restartRequired = $true }
}

if ($restartRequired) {
    Write-Host "[ACTION REQUISE] Les composants WSL/VMP viennent d'être activés. Redémarre Windows puis relance exactement Installation complète." -ForegroundColor Yellow
    throw 'REDÉMARRAGE REQUIS: fondations WSL/VMP activées avec succès. Aucune convergence applicative/WSL ne doit continuer avant le redémarrage. Après reboot, relance menu.ps1 > Installation complète; les étapes déjà conformes seront ignorées.'
}

$wingetFact = Get-WinGetFact
if (-not $wingetFact.Ready) {
    Repair-WpcWinGetPowerShell7
    $changes.Add('WinGet réparé/bootstrapé via Microsoft.WinGet.Client sous PowerShell 7')
}

$wingetFact = Get-WinGetFact
if (-not $wingetFact.Ready) {
    throw "WinGet reste indisponible après réparation PowerShell 7. Détail: $($wingetFact.Detail)"
}
Write-Host "[OK] WinGet opérationnel: $($wingetFact.Detail)" -ForegroundColor Green

$wslFact = Get-WslFact
if (-not $wslFact.Ready) {
    if (-not $wslFact.Source) { throw 'wsl.exe introuvable après activation des fonctionnalités Windows.' }
    Write-Host '[EN COURS] Mise à jour du runtime WSL Store via téléchargement web...' -ForegroundColor Cyan
    $updateResult = Invoke-WpcNativeCapture -FilePath $wslFact.Source -ArgumentList @('--update','--web-download')
    if ($updateResult.ExitCode -ne 0) {
        throw "wsl --update --web-download a échoué (code=$($updateResult.ExitCode)). Détail: $($updateResult.Text.Trim())"
    }
    $changes.Add('runtime WSL mis à jour')
    $wslFact = Get-WslFact
}

if (-not $wslFact.Ready) {
    throw "Runtime WSL toujours indisponible après mise à jour. Détail: $($wslFact.Detail)"
}
Write-Host "[OK] Runtime WSL opérationnel: $($wslFact.Detail)" -ForegroundColor Green

$wslFeatureState = Get-OptionalFeatureStateSafe -FeatureName 'Microsoft-Windows-Subsystem-Linux'
$vmpFeatureState = Get-OptionalFeatureStateSafe -FeatureName 'VirtualMachinePlatform'
if ($wslFeatureState -ne 'Enabled' -or $vmpFeatureState -ne 'Enabled') {
    throw "Fondations Windows non stabilisées après Apply: WSL=$wslFeatureState VMP=$vmpFeatureState"
}

if ($changes.Count -eq 0) {
    Write-Host '[DÉJÀ OK] Fondations Windows déjà conformes; aucune mutation effectuée.' -ForegroundColor Green
} else {
    Write-Host "[FAIT] Fondations Windows préparées: $($changes -join '; ')." -ForegroundColor Green
}
Write-Host 'VERDICT: WINDOWS FOUNDATION READY - POWERSHELL 7 ONLY' -ForegroundColor Green
