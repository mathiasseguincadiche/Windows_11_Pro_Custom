[CmdletBinding()]
param(
    [string]$Description = 'Windows_11_Pro_Custom before optimization'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'La création du point de restauration exige une session PowerShell administrateur.'
}

function New-WpcRestorePointCurrentHost {
    param([Parameter(Mandatory)][string]$RestorePointDescription)

    if (-not (Get-Command Checkpoint-Computer -ErrorAction SilentlyContinue)) {
        return $false
    }

    $systemDrive = "$($env:SystemDrive)\"
    if (Get-Command Enable-ComputerRestore -ErrorAction SilentlyContinue) {
        Enable-ComputerRestore -Drive $systemDrive -ErrorAction Stop
    }
    Checkpoint-Computer -Description $RestorePointDescription -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    return $true
}

function New-WpcRestorePointWindowsPowerShell {
    param([Parameter(Mandatory)][string]$RestorePointDescription)

    $windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if (-not $windowsPowerShell) {
        throw 'Checkpoint-Computer est indisponible dans cet hôte et Windows PowerShell 5.1 est introuvable.'
    }

    $escapedDescription = $RestorePointDescription.Replace("'", "''")
    $command = @'
$ErrorActionPreference = 'Stop'
$systemDrive = "$env:SystemDrive\"
if (Get-Command Enable-ComputerRestore -ErrorAction SilentlyContinue) {
    Enable-ComputerRestore -Drive $systemDrive -ErrorAction Stop
}
Checkpoint-Computer -Description '__DESCRIPTION__' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
'@
    $command = $command.Replace('__DESCRIPTION__', $escapedDescription)

    & $windowsPowerShell.Source -NoLogo -NoProfile -ExecutionPolicy Bypass -Command $command
    $exitCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($exitCode -ne 0) {
        throw "Windows PowerShell n'a pas pu créer le point de restauration (code=$exitCode)."
    }
}

try {
    $createdInCurrentHost = New-WpcRestorePointCurrentHost -RestorePointDescription $Description
    if (-not $createdInCurrentHost) {
        Write-Host '[INFO] Checkpoint-Computer indisponible dans cet hôte; bascule vers Windows PowerShell 5.1.' -ForegroundColor Cyan
        New-WpcRestorePointWindowsPowerShell -RestorePointDescription $Description
    }
    Write-Host '[OK] Point de restauration Windows créé avant les modifications.' -ForegroundColor Green
} catch {
    throw "Impossible de créer le point de restauration de sécurité. Aucune optimisation ne doit continuer sans ce garde-fou, sauf choix explicite via -SkipV4RestorePoint. Détail: $($_.Exception.Message)"
}
