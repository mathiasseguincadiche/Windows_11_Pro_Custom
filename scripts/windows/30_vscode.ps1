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
    foreach ($path in $paths) { if (Test-Path $path) { return $path } }
    return $null
}

function Get-RequestedExtensions {
    @(Get-Content $extensionsSource | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
}

function Get-InstalledExtensions {
    param([string]$CodePath)
    if (-not $CodePath) { return @() }
    @(& $CodePath --list-extensions 2>$null | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
}

function Test-SettingsMatch {
    if (-not (Test-Path $settingsTarget)) { return $false }
    return (Get-FileHash $settingsSource -Algorithm SHA256).Hash -eq (Get-FileHash $settingsTarget -Algorithm SHA256).Hash
}

if (-not (Test-Path $settingsSource)) { throw "Configuration VS Code absente: $settingsSource" }
if (-not (Test-Path $extensionsSource)) { throw "Liste extensions absente: $extensionsSource" }
$code = Resolve-CodeCommand
$requested = @(Get-RequestedExtensions)
$installed = @(Get-InstalledExtensions -CodePath $code)
$missing = @($requested | Where-Object { $installed -notcontains $_.ToLowerInvariant() })
$settingsMatch = Test-SettingsMatch

if ($Mode -eq 'Audit') {
    Write-Host "VS Code CLI: $(if ($code) { $code } else { 'ABSENT' })"
    Write-Host "Settings: $(if ($settingsMatch) { 'CONFORMES' } elseif (Test-Path $settingsTarget) { 'DIFFÉRENTS' } else { 'ABSENTS' })"
    foreach ($extension in $requested) {
        if ($installed -contains $extension.ToLowerInvariant()) {
            Write-Host "[DÉJÀ OK] extension $extension" -ForegroundColor Green
        } else {
            Write-Host "[À FAIRE] extension $extension" -ForegroundColor Yellow
        }
    }
    if ($code -and $settingsMatch -and $missing.Count -eq 0) {
        Write-Host '[DÉJÀ OK] VS Code est conforme.' -ForegroundColor Green
    }
    return
}

if (-not $code) { throw 'VS Code est absent ou son CLI est introuvable. Le bootstrap applications doit dʼabord installer Microsoft.VisualStudioCode.' }

if ($Mode -eq 'Verify') {
    $failures = [System.Collections.Generic.List[string]]::new()
    if (-not $settingsMatch) { $failures.Add('settings.json différent/absent') }
    foreach ($extension in $missing) { $failures.Add("extension absente: $extension") }
    if ($failures.Count -gt 0) { throw "VS Code non conforme: $($failures -join '; ')" }
    Write-Host '[OK] VS Code validé: settings et extensions conformes.' -ForegroundColor Green
    return
}

if ($Mode -eq 'Apply') {
    if ($settingsMatch -and $missing.Count -eq 0) {
        Write-Host '[DÉJÀ OK] VS Code est déjà conforme; aucune copie ni réinstallation dʼextension.' -ForegroundColor Green
        return
    }

    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path $settingsTarget) | Out-Null
    if (-not (Test-Path $stateMeta)) {
        $settingsExisted = Test-Path $settingsTarget
        if ($settingsExisted) { Copy-Item -Force $settingsTarget $backupSettings }
        [ordered]@{
            SettingsExisted = $settingsExisted
            ExtensionsBefore = @(Get-InstalledExtensions -CodePath $code)
            RecordedAt = (Get-Date).ToString('o')
        } | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 $stateMeta
        Write-Host "[OK] État initial VS Code sauvegardé: $stateMeta"
    }

    $changes = [System.Collections.Generic.List[string]]::new()
    if (-not $settingsMatch) {
        Copy-Item -Force $settingsSource $settingsTarget
        $changes.Add('settings.json')
        Write-Host '[FAIT] settings.json mis en conformité.' -ForegroundColor Green
    } else {
        Write-Host '[DÉJÀ OK] settings.json déjà conforme.' -ForegroundColor Green
    }

    foreach ($extension in $missing) {
        Write-Host "[EN COURS] Installation extension $extension" -ForegroundColor Cyan
        & $code --install-extension $extension
        $installCode = $LASTEXITCODE
        $global:LASTEXITCODE = 0
        if ($installCode -ne 0) { throw "Installation extension VS Code échouée: $extension (code=$installCode)" }
        $nowInstalled = @(Get-InstalledExtensions -CodePath $code)
        if ($nowInstalled -notcontains $extension.ToLowerInvariant()) { throw "Extension $extension non prouvée après installation." }
        $changes.Add("extension:$extension")
        Write-Host "[FAIT] extension $extension installée et revalidée." -ForegroundColor Green
    }

    & $PSCommandPath -Mode Verify
    Write-Host "[FAIT] VS Code corrigé: $($changes -join ', ')." -ForegroundColor Green
    return
}

if (-not (Test-Path $stateMeta)) {
    Write-Host '[DÉJÀ OK] Aucun état initial VS Code géré par le dépôt; rollback inutile.' -ForegroundColor Green
    return
}
$state = Get-Content -Raw $stateMeta | ConvertFrom-Json
if ($state.SettingsExisted) {
    if (-not (Test-Path $backupSettings)) { throw 'Sauvegarde settings VS Code absente.' }
    Copy-Item -Force $backupSettings $settingsTarget
} else {
    Remove-Item -Force $settingsTarget -ErrorAction SilentlyContinue
}

$currentExtensions = @(Get-InstalledExtensions -CodePath $code)
$before = @($state.ExtensionsBefore | ForEach-Object { ([string]$_).ToLowerInvariant() })
foreach ($extension in $requested) {
    $id = $extension.ToLowerInvariant()
    if ($currentExtensions -contains $id -and $before -notcontains $id) {
        & $code --uninstall-extension $extension
        $removeCode = $LASTEXITCODE
        $global:LASTEXITCODE = 0
        if ($removeCode -ne 0) { throw "Désinstallation extension VS Code échouée: $extension" }
    }
}
Write-Host '[FAIT] Configuration VS Code restaurée à lʼétat initial enregistré.' -ForegroundColor Green
