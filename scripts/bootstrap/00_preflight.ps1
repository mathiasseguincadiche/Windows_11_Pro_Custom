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
$storageSafetyScript = Join-Path $repoRoot 'scripts\bootstrap\00_storage_integrity.ps1'
$storageIdentityScript = Join-Path $repoRoot 'scripts\bootstrap\00_storage_identity.ps1'
$physicalReadinessScript = Join-Path $repoRoot 'scripts\bootstrap\02_physical_readiness.ps1'
if (-not (Test-Path -LiteralPath $windowsNativeModule)) {
    throw "Bootstrap des modules Windows introuvable: $windowsNativeModule"
}
if (-not (Test-Path -LiteralPath $rebootStateModule)) {
    throw "Détection de redémarrage Windows introuvable: $rebootStateModule"
}
if (-not (Test-Path -LiteralPath $storageSafetyScript)) {
    throw "Contrôle d'intégrité stockage introuvable: $storageSafetyScript"
}
if (-not (Test-Path -LiteralPath $storageIdentityScript)) {
    throw "Contrôle d'identité stockage introuvable: $storageIdentityScript"
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
    WindowsVersion = $os.Version
    BuildNumber = $os.BuildNumber
    TotalMemoryGB = [math]::Round($computer.TotalPhysicalMemory / 1GB, 2)
    PendingReboot = $pendingReboot
    Volumes = $volumes
    NativeModules = @($nativeModules)
    RequireFoundation = [bool]$RequireFoundation
    StorageSafetyRequired = [bool]$StrictPhysicalReadiness
    StorageIdentityRequired = [bool]$StrictPhysicalReadiness
}

$result | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 (Join-Path $reportDir 'preflight.json')

if (-not $isAdmin) {
    throw "PowerShell doit être lancé en administrateur."
}

if (-not $isWindows11) {
    throw "Windows 11 est requis. Détecté: Caption='$($os.Caption)' EditionID='$editionId'."
}

if ($isHomeEdition) {
    throw "Windows 11 Home n'est pas pris en charge par cette workstation. Détecté: Caption='$($os.Caption)' EditionID='$editionId'. Une édition Windows 11 non-Home est requise."
}

if ($pendingReboot.Pending -and ($StrictPhysicalReadiness -or -not $AllowPendingReboot)) {
    throw "Un redémarrage Windows est en attente ($($pendingReboot.Reasons -join ', ')). Redémarre Windows puis relance Installation complète: aucune convergence physique n'est autorisée tant que CBS/Windows Update n'est pas stabilisé. -AllowPendingReboot reste diagnostic-only et ne contourne jamais StrictPhysicalReadiness."
}

if ($pendingReboot.Pending) {
    Write-Warning "Redémarrage Windows en attente: $($pendingReboot.Reasons -join ', '). Le préflight non strict a été explicitement autorisé en mode diagnostic."
}

function Invoke-WpcStorageIdentityVerify {
    try {
        & $storageIdentityScript -Mode Verify
    } catch {
        $message = $_.Exception.Message
        $legacyOrIncompleteBaseline = (
            $message -match 'MISSING_HASH' -or
            $message -match 'Schéma baseline stockage invalide:\s*Roles\.C et Roles\.E sont obligatoires'
        )

        if ($legacyOrIncompleteBaseline) {
            $reenrollCommand = '.\scripts\bootstrap\00_storage_identity.ps1 -Mode Record -ConfirmHealthyTopology -ReplaceBaseline'
            throw "STORAGE_IDENTITY_BASELINE_ACTION_REQUIRED: une baseline locale héritée ou incomplète a été détectée. Aucune convergence n'a été autorisée et aucune baseline n'a été remplacée automatiquement. Vérifie humainement que C: est bien le disque système et E: le disque de données attendu, puis ré-enrôle explicitement la topologie saine avec: $reenrollCommand. Relance ensuite: .\scripts\bootstrap\00_storage_identity.ps1 -Mode Verify. Cause originale: $message"
        }

        throw
    }
}

# Ordre fail-closed : identité physique, intégrité NTFS/NVMe, puis qualification physique.
if ($StrictPhysicalReadiness) {
    Write-Host "[ANALYSE] Vérification des identités physiques C:/E:..." -ForegroundColor Cyan
    Invoke-WpcStorageIdentityVerify
    Write-Host "[ANALYSE] Qualification NTFS/NVMe avant toute mutation..." -ForegroundColor Cyan
    & $storageSafetyScript -Mode Verify
} else {
    & $storageIdentityScript -Mode Audit
    Write-Host "[INFO] Contrôle approfondi d'intégrité stockage non exécuté dans ce préflight diagnostic non strict." -ForegroundColor DarkGray
}

$c = Get-Volume -DriveLetter C -ErrorAction Stop
$e = Get-Volume -DriveLetter E -ErrorAction Stop
if ($c.FileSystem -ne 'NTFS') { throw "C: doit être NTFS." }
if ($e.FileSystem -ne 'NTFS') { throw "E: doit être NTFS. Aucun EXT4 physique n'est attendu." }

$loadedNames = @($nativeModules | Where-Object Available | ForEach-Object Module)
Write-Host "[OK] Modules Windows natifs prêts: $($loadedNames -join ', ')" -ForegroundColor Green
Write-Host "[OK] Preflight Windows 11 non-Home ($editionId) / C: NTFS / E: NTFS / aucun reboot pending bloquant" -ForegroundColor Green

Write-Host "[ANALYSE] Préqualification physique complète avant toute convergence..." -ForegroundColor Cyan
& $physicalReadinessScript -Strict:$StrictPhysicalReadiness -RequireFoundation:$RequireFoundation
