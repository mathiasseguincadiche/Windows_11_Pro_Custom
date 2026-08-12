[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Verify', 'Rollback')]
    [string]$Mode = 'Audit'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$stateDir = Join-Path $repoRoot 'state\openssh-client'
$statePath = Join-Path $stateDir 'state.json'
$capabilityName = 'OpenSSH.Client~~~~0.0.1.0'

function Get-OpenSshClientCapability {
    $capability = Get-WindowsCapability -Online -Name $capabilityName -ErrorAction Stop
    if (-not $capability) { throw "Capacité Windows introuvable: $capabilityName" }
    return $capability
}

function Test-SshCommand {
    $ssh = Get-Command ssh.exe -ErrorAction SilentlyContinue
    return ($null -ne $ssh)
}

$capability = Get-OpenSshClientCapability
$installed = $capability.State -eq 'Installed'
$sshPresent = Test-SshCommand

if ($Mode -eq 'Audit') {
    Write-Host "OpenSSH Client capability: $($capability.State)"
    Write-Host "ssh.exe disponible: $sshPresent"
    if ($installed -and $sshPresent) {
        Write-Host '[DÉJÀ OK] OpenSSH Client est prêt.' -ForegroundColor Green
    } else {
        Write-Host '[À FAIRE] OpenSSH Client doit être installé/réparé.' -ForegroundColor Yellow
    }
    return
}

if ($Mode -eq 'Verify') {
    if (-not $installed) { throw 'OpenSSH Client Windows est absent.' }
    if (-not $sshPresent) { throw 'ssh.exe est introuvable malgré OpenSSH Client installé.' }
    Write-Host '[OK] OpenSSH Client validé.' -ForegroundColor Green
    return
}

if ($Mode -eq 'Apply') {
    if ($installed -and $sshPresent) {
        Write-Host '[DÉJÀ OK] OpenSSH Client est déjà installé et ssh.exe est disponible; aucune réinstallation.' -ForegroundColor Green
        return
    }

    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    if (-not (Test-Path $statePath)) {
        [ordered]@{ InstalledBefore=$installed; RecordedAt=(Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -Encoding utf8 $statePath
    }
    if (-not $installed) {
        Write-Host '[EN COURS] Installation du client OpenSSH Windows...' -ForegroundColor Cyan
        $result = Add-WindowsCapability -Online -Name $capabilityName
        if ($result.RestartNeeded) {
            Write-Host '[ACTION REQUISE] Windows indique quʼun redémarrage est nécessaire pour OpenSSH Client.' -ForegroundColor Magenta
        }
    }
    $capability = Get-OpenSshClientCapability
    if ($capability.State -ne 'Installed') { throw 'OpenSSH Client nʼest pas installé après Apply.' }
    if (-not (Test-SshCommand)) { throw 'OpenSSH Client est installé mais ssh.exe reste introuvable.' }
    Write-Host '[FAIT] OpenSSH Client installé/réparé et revalidé.' -ForegroundColor Green
    return
}

if (-not (Test-Path $statePath)) {
    Write-Host '[DÉJÀ OK] Aucun changement OpenSSH enregistré par le dépôt; rollback inutile.' -ForegroundColor Green
    return
}
$state = Get-Content -Raw $statePath | ConvertFrom-Json
if (-not [bool]$state.InstalledBefore -and $installed) {
    Write-Host '[EN COURS] Restauration de lʼétat initial: suppression du client OpenSSH ajouté par le dépôt.' -ForegroundColor Cyan
    $result = Remove-WindowsCapability -Online -Name $capabilityName
    if ($result.RestartNeeded) {
        Write-Host '[ACTION REQUISE] Un redémarrage Windows est nécessaire pour terminer le rollback OpenSSH.' -ForegroundColor Magenta
    }
    Write-Host '[FAIT] OpenSSH Client restauré à lʼétat initial.' -ForegroundColor Green
} else {
    Write-Host '[DÉJÀ OK] OpenSSH Client était déjà présent avant le dépôt; aucun retrait effectué.' -ForegroundColor Green
}
