[CmdletBinding()]
param(
    [switch]$AllowPendingReboot,
    [switch]$StrictPhysicalReadiness,
    [switch]$RequireFoundation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$reportDir = Join-Path $repoRoot 'reports'
$windowsNativeModule = Join-Path $repoRoot 'scripts\core\windows-native.psm1'
$rebootStateModule = Join-Path $repoRoot 'scripts\core\reboot-state.psm1'
$physicalReadinessScript = Join-Path $repoRoot 'scripts\bootstrap\02_physical_readiness.ps1'
if (-not (Test-Path -LiteralPath $windowsNativeModule)) {
    throw "Bootstrap des modules Windows introuvable: $windowsNativeModule"
}
if (-not (Test-Path -LiteralPath $rebootStateModule)) {
    throw "Détection de redémarrage Windows introuvable: $rebootStateModule"
}
if (-not (Test-Path -LiteralPath $physicalReadinessScript)) {
    throw "Préqualification physique introuvable: $physicalReadinessScript"
}
Import-Module $windowsNativeModule
Import-Module $rebootStateModule -Force
$nativeModules = @(Initialize-WpcWindowsNativeModules -Profile Full)
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$os = Get-CimInstance Win32_OperatingSystem
$computer = Get-CimInstance Win32_ComputerSystem
$volumes = Get-Volume | Where-Object DriveLetter | Select-Object DriveLetter, FileSystem, HealthStatus, SizeRemaining, Size
$editionId = [string](Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID -ErrorAction Stop)
$pendingReboot = Get-WpcPendingRebootState
$isWindows11 = ($os.Caption -match 'Windows 11')
$isHomeEdition = ($editionId -match '^Core')

$result = [ordered]@{
    Timestamp = (Get-Date).ToString('o')
    IsAdministrator = $isAdmin
    Caption = $os.Caption
    EditionID = $editionId
    IsWindows11 = $isWindows11
    IsHomeEdition = $isHomeEdition
    Version = $os.Version
    BuildNumber = $os.BuildNumber
    TotalMemoryGB = [math]::Round($computer.TotalPhysicalMemory / 1GB, 2)
    PendingReboot = $pendingReboot
    Volumes = $volumes
    NativeModules = @($nativeModules)
    RequireFoundation = [bool]$RequireFoundation
}

$result | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 (Join-Path $reportDir 'preflight.json')

if (-not $isAdmin) {
    throw 'PowerShell doit être lancé en administrateur.'
}

if (-not $isWindows11) {
    throw "Windows 11 est requis. Détecté: Caption='$($os.Caption)' EditionID='$editionId'."
}

if ($isHomeEdition) {
    throw "Windows 11 Home n'est pas pris en charge par cette workstation. Détecté: Caption='$($os.Caption)' EditionID='$editionId'. Une édition Windows 11 non-Home est requise."
}

$c = Get-Volume -DriveLetter C -ErrorAction Stop
$d = Get-Volume -DriveLetter D -ErrorAction Stop

if ($c.FileSystem -ne 'NTFS') { throw 'C: doit être NTFS.' }
if ($d.FileSystem -ne 'NTFS') { throw 'D: doit être NTFS. Aucun EXT4 physique n est attendu.' }

if ($pendingReboot.Pending -and -not $AllowPendingReboot) {
    throw "Un redémarrage Windows est en attente ($($pendingReboot.Reasons -join ', ')). Redémarre Windows puis relance Installation complète: la convergence reprendra idempotemment. Le bypass n'est autorisé que pour un diagnostic volontaire via -AllowPendingReboot."
}

if ($pendingReboot.Pending) {
    Write-Warning "Redémarrage Windows en attente: $($pendingReboot.Reasons -join ', '). Le préflight a été explicitement autorisé en mode diagnostic."
}

$loadedNames = @($nativeModules | Where-Object Available | ForEach-Object Module)
Write-Host "[OK] Modules Windows natifs prêts: $($loadedNames -join ', ')" -ForegroundColor Green
Write-Host "[OK] Preflight Windows 11 non-Home ($editionId) / C: NTFS / D: NTFS / aucun reboot pending bloquant" -ForegroundColor Green
Write-Host '[ANALYSE] Préqualification physique complète avant toute convergence...' -ForegroundColor Cyan
& $physicalReadinessScript -Strict:$StrictPhysicalReadiness -RequireFoundation:$RequireFoundation
