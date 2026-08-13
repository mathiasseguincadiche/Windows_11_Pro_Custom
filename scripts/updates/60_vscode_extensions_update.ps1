[CmdletBinding()]
param(
    [ValidateSet('Audit','Apply','Verify')]
    [string]$Mode = 'Audit',
    [string]$Distribution = 'Ubuntu',
    [string]$LinuxUser = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$runtimeModule = Join-Path $repoRoot 'scripts\core\runtime.psm1'
Import-Module $runtimeModule -Force
$context = Get-WpcRunContextFromEnvironment -RepoRoot $repoRoot
$windowsVerify = Join-Path $repoRoot 'scripts\windows\30_vscode.ps1'
$wslManagerWindows = Join-Path $repoRoot 'scripts\wsl\manage-vscode-extensions.sh'

if (-not (Get-Command code.cmd -ErrorAction SilentlyContinue) -and -not (Get-Command code.exe -ErrorAction SilentlyContinue) -and -not (Get-Command code -ErrorAction SilentlyContinue)) {
    throw 'CLI VS Code introuvable dans PATH.'
}
$codeCommand = if (Get-Command code.cmd -ErrorAction SilentlyContinue) { 'code.cmd' } elseif (Get-Command code.exe -ErrorAction SilentlyContinue) { 'code.exe' } else { 'code' }

function Get-LinuxUser {
    if (-not [string]::IsNullOrWhiteSpace($LinuxUser)) { return $LinuxUser }
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return '' }
    $value = (& wsl.exe -d $Distribution -- sh -lc 'id -un' 2>$null | Out-String).Trim()
    $global:LASTEXITCODE = 0
    return $value
}

function Invoke-WslExtensionManager {
    param([Parameter(Mandatory)][string]$Action)
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'wsl.exe introuvable.' }
    $user = Get-LinuxUser
    if ([string]::IsNullOrWhiteSpace($user) -or $user -eq 'root') { throw 'Utilisateur WSL normal introuvable pour VS Code.' }
    $linuxManager = (& wsl.exe --distribution $Distribution --user $user --exec wslpath -a -u $wslManagerWindows).Trim()
    $convertCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($convertCode -ne 0 -or [string]::IsNullOrWhiteSpace($linuxManager)) { throw 'Impossible de convertir le chemin manage-vscode-extensions.sh.' }
    return Invoke-WpcExternalCommand -Context $context -FilePath 'wsl.exe' -ArgumentList @('--distribution',$Distribution,'--user',$user,'--exec','bash',$linuxManager,$Action) -LogIdentity 'scripts/wsl/manage-vscode-extensions.sh' -DisplayName "VS Code extensions WSL ($Action)" -AllowFailure
}

$version = @(& $codeCommand --version 2>$null)
$global:LASTEXITCODE = 0
Write-Host ("[INFO] VS Code CLI: {0}" -f (($version | Select-Object -First 1) -join '')) -ForegroundColor Cyan

if ($Mode -eq 'Audit') {
    Write-Host '[INFO] Le CLI VS Code ne propose pas de dry-run des mises à jour dʼextensions; Apply utilisera --update-extensions, qui ne modifie que les extensions réellement obsolètes.' -ForegroundColor DarkGray
    [void](Invoke-WpcManagedScript -Context $context -Path $windowsVerify -Arguments @{ Mode='Verify' } -DisplayName 'VS Code Windows managed set' -Phase 'Updates' -Purpose 'Probe' -AllowFailure)
    [void](Invoke-WslExtensionManager -Action 'audit')
    return
}

if ($Mode -eq 'Verify') {
    [void](Invoke-WpcManagedScript -Context $context -Path $windowsVerify -Arguments @{ Mode='Verify' } -DisplayName 'VS Code Windows managed set' -Phase 'Updates')
    $wslResult = Invoke-WslExtensionManager -Action 'verify'
    if (-not $wslResult.Success) { throw "Extensions VS Code WSL non conformes: $($wslResult.Error)" }
    Write-Host '[DÉJÀ OK] Ensembles dʼextensions VS Code Windows/WSL conformes au dépôt.' -ForegroundColor Green
    return
}

Write-Host '[EN COURS] Mise à jour des extensions VS Code Windows...' -ForegroundColor Cyan
$windowsUpdate = Invoke-WpcExternalCommand -Context $context -FilePath $codeCommand -ArgumentList @('--update-extensions') -LogIdentity 'scripts/updates/vscode-windows-extensions' -DisplayName 'VS Code Windows extension updates' -AllowFailure
if (-not $windowsUpdate.Success) { throw "Mise à jour extensions VS Code Windows en échec: $($windowsUpdate.Error)" }

$user = Get-LinuxUser
if ([string]::IsNullOrWhiteSpace($user) -or $user -eq 'root') { throw 'Utilisateur WSL normal introuvable pour mettre à jour les extensions distantes.' }
Write-Host '[EN COURS] Mise à jour des extensions VS Code dans le contexte Ubuntu WSL...' -ForegroundColor Cyan
$wslCodeUpdate = Invoke-WpcExternalCommand -Context $context -FilePath 'wsl.exe' -ArgumentList @('--distribution',$Distribution,'--user',$user,'--exec','bash','-lc','code --update-extensions') -LogIdentity 'scripts/updates/vscode-wsl-extension-update' -DisplayName 'VS Code WSL extension updates' -AllowFailure
if (-not $wslCodeUpdate.Success) { throw "Mise à jour extensions VS Code WSL en échec: $($wslCodeUpdate.Error)" }

[void](Invoke-WpcManagedScript -Context $context -Path $windowsVerify -Arguments @{ Mode='Verify' } -DisplayName 'VS Code Windows managed set' -Phase 'Updates')
$wslVerify = Invoke-WslExtensionManager -Action 'verify'
if (-not $wslVerify.Success) { throw "Extensions VS Code WSL non conformes après mise à jour: $($wslVerify.Error)" }
Write-Host '[FAIT] Extensions VS Code Windows/WSL mises à jour lorsque nécessaire et ensemble géré revalidé.' -ForegroundColor Green
