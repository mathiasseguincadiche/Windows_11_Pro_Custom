[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Verify')]
    [string]$Mode = 'Audit',

    [string]$Root = 'D:\AI\OpenClaw',
    [string]$ControlPlanePath = 'D:\AI\OpenClaw\control-plane',
    [string]$Repository = '',
    [string]$RepositoryRef = '',
    [switch]$OnboardOpenRouter,
    [switch]$InstallGateway
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ControlPlaneConfigPath = Join-Path $RepoRoot 'config\openclaw\control-plane.json'
if (-not (Test-Path $ControlPlaneConfigPath)) {
    throw "Configuration OpenClaw absente: $ControlPlaneConfigPath"
}
$ControlPlaneConfig = Get-Content -Raw $ControlPlaneConfigPath | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($Repository)) {
    $Repository = [string]$ControlPlaneConfig.repository
}
if ([string]::IsNullOrWhiteSpace($RepositoryRef)) {
    $RepositoryRef = [string]$ControlPlaneConfig.ref
}
if ([string]::IsNullOrWhiteSpace($Repository) -or [string]::IsNullOrWhiteSpace($RepositoryRef)) {
    throw 'La configuration OpenClaw doit fournir repository et ref.'
}

$InstallerRelativePath = 'scripts\windows\00_install_openclaw_windows.ps1'

function Write-Section([string]$Message) {
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Get-CommandPath([string]$Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        return $null
    }
    return $command.Source
}

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath"
}

function Assert-TargetDrive {
    $driveName = [System.IO.Path]::GetPathRoot($Root).TrimEnd('\').TrimEnd(':')
    $drive = Get-Volume -DriveLetter $driveName -ErrorAction Stop
    if ($drive.DriveLetter -ne 'D') {
        throw "La pile IA est volontairement limitée au volume D:. Racine demandée: $Root"
    }
    if ($drive.FileSystem -ne 'NTFS') {
        throw "D: doit être NTFS pour cette configuration. Détecté: $($drive.FileSystem)"
    }
}

function Assert-Git {
    if (Get-Command git.exe -ErrorAction SilentlyContinue) {
        return
    }
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw 'Git est absent et WinGet est indisponible.'
    }

    Write-Host '[INFO] Installation de Git for Windows via WinGet.' -ForegroundColor Yellow
    & winget.exe install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        throw "Échec WinGet Git: code $LASTEXITCODE"
    }
    Refresh-ProcessPath
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        throw 'Git a été installé mais reste introuvable dans le PATH courant. Ouvrez un nouveau PowerShell puis relancez.'
    }
}

function Get-ControlPlaneInstaller {
    return Join-Path $ControlPlanePath $InstallerRelativePath
}

function Get-ControlPlaneHead {
    if (-not (Test-Path (Join-Path $ControlPlanePath '.git'))) {
        return $null
    }
    Push-Location $ControlPlanePath
    try {
        $head = (& git.exe rev-parse HEAD 2>$null)
        if ($LASTEXITCODE -ne 0) {
            return $null
        }
        return ([string]$head).Trim()
    }
    finally {
        Pop-Location
    }
}

function Assert-PinnedHead {
    $head = Get-ControlPlaneHead
    if ([string]::IsNullOrWhiteSpace($head)) {
        throw 'Impossible de déterminer le commit du plan de contrôle OpenClaw.'
    }
    if ($RepositoryRef -match '^[0-9a-fA-F]{40}$' -and $head.ToLowerInvariant() -ne $RepositoryRef.ToLowerInvariant()) {
        throw "Le plan de contrôle n'est pas sur le commit épinglé. Attendu=$RepositoryRef Détecté=$head"
    }
    return $head
}

function Sync-ControlPlane {
    Assert-Git
    $parent = Split-Path -Parent $ControlPlanePath
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    if (-not (Test-Path $ControlPlanePath)) {
        Write-Host "[INFO] Clone du plan de contrôle OpenClaw vers $ControlPlanePath" -ForegroundColor Yellow
        & git.exe clone --no-checkout $Repository $ControlPlanePath
        if ($LASTEXITCODE -ne 0) {
            throw 'Échec du clone. Le dépôt OpenClaw est privé : vérifiez que Git Credential Manager est authentifié sur GitHub.'
        }
    }

    $gitDir = Join-Path $ControlPlanePath '.git'
    if (-not (Test-Path $gitDir)) {
        throw "Le dossier existe mais n'est pas un dépôt Git: $ControlPlanePath"
    }

    Push-Location $ControlPlanePath
    try {
        $dirty = (& git.exe status --porcelain)
        if ($LASTEXITCODE -ne 0) {
            throw 'Impossible de lire le statut Git du plan de contrôle.'
        }
        if (@($dirty).Count -gt 0) {
            throw 'Le plan de contrôle contient des modifications locales. Synchronisation refusée pour ne rien écraser.'
        }

        & git.exe fetch --prune origin $RepositoryRef
        if ($LASTEXITCODE -ne 0) {
            throw "Échec git fetch origin $RepositoryRef"
        }
        & git.exe checkout --detach FETCH_HEAD
        if ($LASTEXITCODE -ne 0) {
            throw "Échec git checkout du ref épinglé $RepositoryRef"
        }
    }
    finally {
        Pop-Location
    }

    [void](Assert-PinnedHead)
    $installer = Get-ControlPlaneInstaller
    if (-not (Test-Path $installer)) {
        throw "Installateur Windows OpenClaw introuvable après synchronisation: $installer"
    }
    return $installer
}

function Show-Audit {
    Write-Section 'Audit intégration OpenClaw + OpenRouter'
    Assert-TargetDrive
    $installer = Get-ControlPlaneInstaller
    $facts = [ordered]@{
        Root = $Root
        ControlPlanePath = $ControlPlanePath
        Repository = $Repository
        RepositoryRef = $RepositoryRef
        ControlPlaneHead = Get-ControlPlaneHead
        Git = Get-CommandPath 'git.exe'
        ControlPlanePresent = Test-Path $ControlPlanePath
        InstallerPresent = Test-Path $installer
        OpenClawLauncher = Test-Path (Join-Path $Root 'npm-global\openclaw.cmd')
        ClawOpsLauncher = Test-Path (Join-Path $Root 'venv\Scripts\clawops.exe')
        OPENCLAW_STATE_DIR = [Environment]::GetEnvironmentVariable('OPENCLAW_STATE_DIR', 'User')
        CLAWOPS_HOME = [Environment]::GetEnvironmentVariable('CLAWOPS_HOME', 'User')
    }
    $facts | ConvertTo-Json -Depth 3
}

function Apply-Integration {
    Write-Section 'Déploiement OpenClaw + OpenRouter sur D:'
    Assert-TargetDrive
    $installer = Sync-ControlPlane

    $parameters = @{
        Mode = 'Apply'
        Root = $Root
    }
    if ($OnboardOpenRouter) {
        $parameters.OnboardOpenRouter = $true
    }
    if ($InstallGateway) {
        $parameters.InstallGateway = $true
    }

    & $installer @parameters
    if (-not $?) {
        throw 'L installateur OpenClaw a échoué.'
    }
    $head = Assert-PinnedHead
    Write-Host "[OK] OpenClaw control-plane pin: $head" -ForegroundColor Green
    Write-Host 'VERDICT: OPENCLAW AI INSTALLED' -ForegroundColor Green
}

function Verify-Integration {
    Write-Section 'Qualification intégration OpenClaw + OpenRouter'
    Assert-TargetDrive
    $installer = Get-ControlPlaneInstaller
    if (-not (Test-Path $installer)) {
        throw "Plan de contrôle absent ou incomplet: $installer"
    }

    $head = Assert-PinnedHead
    & $installer -Mode Verify -Root $Root
    if (-not $?) {
        throw 'La validation OpenClaw a échoué.'
    }
    Write-Host "[OK] OpenClaw control-plane pin: $head" -ForegroundColor Green
    Write-Host 'VERDICT: OPENCLAW AI READY' -ForegroundColor Green
}

switch ($Mode) {
    'Audit' { Show-Audit }
    'Apply' { Apply-Integration }
    'Verify' { Verify-Integration }
}
