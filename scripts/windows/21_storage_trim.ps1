[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply')]
    [string]$Mode = 'Audit'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$letters = @('C', 'D')

foreach ($letter in $letters) {
    $volume = Get-Volume -DriveLetter $letter -ErrorAction Stop
    if ($volume.FileSystem -ne 'NTFS') {
        throw "$letter`: n'est pas NTFS. Aucun réglage de stockage n'est appliqué."
    }

    Write-Host "[$letter] FS=$($volume.FileSystem) Health=$($volume.HealthStatus) Libre=$([math]::Round($volume.SizeRemaining / 1GB, 1)) GiB"
}

Write-Host (& fsutil.exe behavior query DisableDeleteNotify 2>&1 | Out-String)

if ($Mode -eq 'Audit') {
    Write-Host '[INFO] Audit uniquement. Windows Scheduled Optimize reste inchangé.'
    return
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'PowerShell administrateur requis pour ReTrim.'
}

foreach ($letter in $letters) {
    Write-Host "ReTrim du volume $letter`:" -ForegroundColor Cyan
    Optimize-Volume -DriveLetter $letter -ReTrim -Verbose
}

Write-Host '[OK] ReTrim demandé pour C: et D:. La planification Windows n’a pas été désactivée.' -ForegroundColor Green
