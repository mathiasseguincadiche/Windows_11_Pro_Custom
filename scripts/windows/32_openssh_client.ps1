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

if ($Mode -eq 'Audit') {
    Write-Host "OpenSSH Client capability: $($capability.State)"
    Write-Host "ssh.exe disponible: $(Test-SshCommand)"
    return
}

if ($Mode -eq 'Apply') {
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    if (-not (Test-Path $statePath)) {
        [ordered]@{
            InstalledBefore = $installed
            RecordedAt = (Get-Date).ToString('o')
        } | ConvertTo-Json | Set-Content -Encoding utf8 $statePath
    }

    if (-not $installed) {
        Write-Host '[INFO] Installation du client OpenSSH Windows...'
        $result = Add-WindowsCapability -Online -Name $capabilityName
        if ($result.RestartNeeded) {
            Write-Warning "OpenSSH Client indique qu’un redémarrage Windows est nécessaire."
        }
    }

    $capability = Get-OpenSshClientCapability
    if ($capability.State -ne 'Installed') { throw "OpenSSH Client n’est pas installé après Apply." }
    if (-not (Test-SshCommand)) { throw 'OpenSSH Client est installé mais ssh.exe reste introuvable.' }

    Write-Host '[OK] OpenSSH Client prêt pour VS Code Remote - SSH.' -ForegroundColor Green
    return
}

if ($Mode -eq 'Verify') {
    if ($capability.State -ne 'Installed') { throw 'OpenSSH Client Windows est absent.' }
    if (-not (Test-SshCommand)) { throw 'ssh.exe est introuvable malgré OpenSSH Client installé.' }
    Write-Host '[OK] OpenSSH Client validé.' -ForegroundColor Green
    return
}

if (-not (Test-Path $statePath)) {
    Write-Warning 'État initial OpenSSH Client absent : aucun rollback effectué.'
    return
}

$state = Get-Content -Raw $statePath | ConvertFrom-Json
if (-not [bool]$state.InstalledBefore -and $installed) {
    Write-Host "[INFO] Restauration de l’état initial : suppression du client OpenSSH ajouté par le dépôt."
    $result = Remove-WindowsCapability -Online -Name $capabilityName
    if ($result.RestartNeeded) {
        Write-Warning "La suppression OpenSSH Client indique qu’un redémarrage Windows est nécessaire."
    }
}

Write-Host '[OK] État OpenSSH Client restauré.' -ForegroundColor Green
