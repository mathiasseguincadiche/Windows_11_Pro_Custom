[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Verify', 'Rollback')]
    [string]$Mode = 'Audit'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$settingsSource = Join-Path $repoRoot 'config\vscode\settings.json'
$extensionsSource = Join-Path $repoRoot 'config\vscode\extensions.txt'
$settingsTarget = Join-Path $env:APPDATA 'Code\User\settings.json'
$stateDir = Join-Path $repoRoot 'state\vscode'
$stateMeta = Join-Path $stateDir 'state.json'
$backupSettings = Join-Path $stateDir 'settings.before.json'

function Resolve-CodeCommand {
    $candidate = Get-Command code.cmd -ErrorAction SilentlyContinue
    if ($candidate) { return $candidate.Source }
    $candidate = Get-Command code -ErrorAction SilentlyContinue
    if ($candidate) { return $candidate.Source }

    $paths = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'),
        (Join-Path $env:ProgramFiles 'Microsoft VS Code\bin\code.cmd')
    )
    foreach ($path in $paths) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

function Get-RequestedExtensions {
    @(Get-Content $extensionsSource | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
}

if (-not (Test-Path $settingsSource)) { throw "Configuration VS Code absente: $settingsSource" }
if (-not (Test-Path $extensionsSource)) { throw "Liste extensions absente: $extensionsSource" }
$code = Resolve-CodeCommand

if ($Mode -eq 'Audit') {
    Write-Host "VS Code CLI: $(if ($code) { $code } else { 'ABSENT' })"
    Write-Host "Settings cible: $settingsTarget"
    Write-Host "Settings présents: $(Test-Path $settingsTarget)"
    Write-Host 'Extensions V3 demandées:'
    Get-RequestedExtensions | ForEach-Object { Write-Host "  $_" }
    return
}

if (-not $code) { throw 'VS Code est absent ou son CLI est introuvable.' }

if ($Mode -eq 'Apply') {
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path $settingsTarget) | Out-Null

    if (-not (Test-Path $stateMeta)) {
        $existingExtensions = @(& $code --list-extensions 2>$null)
        $settingsExisted = Test-Path $settingsTarget
        if ($settingsExisted) { Copy-Item -Force $settingsTarget $backupSettings }
        [ordered]@{
            SettingsExisted = $settingsExisted
            ExtensionsBefore = $existingExtensions
        } | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 $stateMeta
    }

    Copy-Item -Force $settingsSource $settingsTarget
    foreach ($extension in Get-RequestedExtensions) {
        & $code --install-extension $extension --force
        if ($LASTEXITCODE -ne 0) { throw "Installation extension VS Code échouée: $extension" }
    }
    Write-Host '[OK] VS Code configuré pour le poste DevOps/WSL.' -ForegroundColor Green
    return
}

if ($Mode -eq 'Verify') {
    if (-not (Test-Path $settingsTarget)) { throw 'settings.json VS Code absent.' }
    $sourceHash = (Get-FileHash $settingsSource -Algorithm SHA256).Hash
    $targetHash = (Get-FileHash $settingsTarget -Algorithm SHA256).Hash
    if ($sourceHash -ne $targetHash) { throw 'settings.json VS Code diffère de la configuration V3.' }

    $installed = @(& $code --list-extensions 2>$null | ForEach-Object { $_.Trim().ToLowerInvariant() })
    foreach ($extension in Get-RequestedExtensions) {
        if ($installed -notcontains $extension.ToLowerInvariant()) { throw "Extension VS Code absente: $extension" }
    }
    Write-Host '[OK] VS Code V3 validé.' -ForegroundColor Green
    return
}

if (-not (Test-Path $stateMeta)) { throw "État VS Code absent: $stateMeta" }
$state = Get-Content -Raw $stateMeta | ConvertFrom-Json
if ($state.SettingsExisted) {
    if (-not (Test-Path $backupSettings)) { throw 'Sauvegarde settings VS Code absente.' }
    Copy-Item -Force $backupSettings $settingsTarget
} else {
    Remove-Item -Force $settingsTarget -ErrorAction SilentlyContinue
}

$currentExtensions = @(& $code --list-extensions 2>$null)
$before = @($state.ExtensionsBefore)
foreach ($extension in Get-RequestedExtensions) {
    if ($currentExtensions -contains $extension -and $before -notcontains $extension) {
        & $code --uninstall-extension $extension
        if ($LASTEXITCODE -ne 0) { throw "Désinstallation extension VS Code échouée: $extension" }
    }
}
Write-Host '[OK] Configuration VS Code restaurée.' -ForegroundColor Green
