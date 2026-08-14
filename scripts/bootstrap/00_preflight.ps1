[CmdletBinding()]
param(
    [switch]$AllowPendingReboot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$reportDir = Join-Path $repoRoot 'reports'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

function Get-PendingRebootState {
    $reasons = [System.Collections.Generic.List[string]]::new()

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $reasons.Add('CBS')
    }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $reasons.Add('WindowsUpdate')
    }
    try {
        $pendingRename = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction Stop
        if ($null -ne $pendingRename) {
            $reasons.Add('PendingFileRenameOperations')
        }
    } catch {}

    return [pscustomobject]@{
        Pending = ($reasons.Count -gt 0)
        Reasons = @($reasons)
    }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$os = Get-CimInstance Win32_OperatingSystem
$computer = Get-CimInstance Win32_ComputerSystem
$volumes = Get-Volume | Where-Object DriveLetter | Select-Object DriveLetter, FileSystem, HealthStatus, SizeRemaining, Size
$editionId = [string](Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID -ErrorAction Stop)
$pendingReboot = Get-PendingRebootState
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
}

$result | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 (Join-Path $reportDir 'preflight.json')

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
    throw "Un redémarrage Windows est en attente ($($pendingReboot.Reasons -join ', ')). Redémarre Windows avant de lancer la convergence. Le bypass n'est autorisé que pour un diagnostic volontaire via -AllowPendingReboot."
}

if ($pendingReboot.Pending) {
    Write-Warning "Redémarrage Windows en attente: $($pendingReboot.Reasons -join ', '). Le préflight a été explicitement autorisé en mode diagnostic."
}

Write-Host "[OK] Preflight Windows 11 non-Home ($editionId) / C: NTFS / D: NTFS / aucun reboot pending bloquant" -ForegroundColor Green
