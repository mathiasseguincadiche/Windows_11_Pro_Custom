[CmdletBinding()]
param(
    [string]$Distribution = 'Ubuntu',
    [string]$LinuxUser = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$runtimeModule = Join-Path $repoRoot 'scripts\core\runtime.psm1'
Import-Module $runtimeModule -Force
$context = Get-WpcRunContextFromEnvironment -RepoRoot $repoRoot
$windowsScript = Join-Path $repoRoot 'scripts\wsl\install-devops.sh'
$wslConfScript = Join-Path $repoRoot 'scripts\wsl\apply-wsl-conf.ps1'
$vscodeWslScript = Join-Path $repoRoot 'scripts\wsl\manage-vscode-extensions.sh'

if (-not (Test-Path $windowsScript)) { throw "Script absent: $windowsScript" }
if (-not (Test-Path $wslConfScript)) { throw "Script absent: $wslConfScript" }
if (-not (Test-Path $vscodeWslScript)) { throw "Script absent: $vscodeWslScript" }
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'wsl.exe introuvable.' }

$installed = @((wsl.exe --list --quiet 2>$null) -replace "`0", '' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$global:LASTEXITCODE = 0
if ($installed -notcontains $Distribution) { throw "Distribution WSL absente: $Distribution." }

if ([string]::IsNullOrWhiteSpace($LinuxUser)) {
    $LinuxUser = (& wsl.exe -d $Distribution -- sh -lc 'id -un' 2>$null | Out-String).Trim()
    $userCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($userCode -ne 0 -or [string]::IsNullOrWhiteSpace($LinuxUser)) { throw 'Impossible de déterminer l’utilisateur WSL par défaut.' }
}
if ($LinuxUser -eq 'root') {
    throw 'Le bootstrap DevOps refuse root. Exécute d’abord la préparation utilisateur WSL V9; elle crée/configure un utilisateur normal de façon guidée.'
}

& wsl.exe -d $Distribution -u root -- sh -lc "getent passwd '$LinuxUser' >/dev/null"
$userExistsCode = $LASTEXITCODE
$global:LASTEXITCODE = 0
if ($userExistsCode -ne 0) { throw "Utilisateur WSL absent: $LinuxUser" }

Write-Host '[1/3] /etc/wsl.conf et systemd' -ForegroundColor Cyan
[void](Invoke-WpcManagedScript -Context $context -Path $wslConfScript -DisplayName 'Configuration /etc/wsl.conf' -Arguments @{ Distribution=$Distribution; LinuxUser=$LinuxUser } -Phase 'DevOps')

Write-Host '[2/3] Stack DevOps Linux' -ForegroundColor Cyan
$linuxScript = (& wsl.exe --distribution $Distribution --user $LinuxUser --exec wslpath -a -u $windowsScript).Trim()
$convertCode = $LASTEXITCODE
$global:LASTEXITCODE = 0
if ($convertCode -ne 0 -or [string]::IsNullOrWhiteSpace($linuxScript)) { throw 'Impossible de convertir le chemin du bootstrap DevOps avec wslpath.' }
Invoke-WpcExternalCommand -Context $context -FilePath 'wsl.exe' -ArgumentList @('--distribution', $Distribution, '--user', $LinuxUser, '--exec', 'bash', $linuxScript) -LogIdentity 'scripts/wsl/install-devops.sh' -DisplayName 'install-devops.sh'

Write-Host '[3/3] Extensions VS Code dans WSL' -ForegroundColor Cyan
$linuxVsCodeScript = (& wsl.exe --distribution $Distribution --user $LinuxUser --exec wslpath -a -u $vscodeWslScript).Trim()
$convertVsCode = $LASTEXITCODE
$global:LASTEXITCODE = 0
if ($convertVsCode -ne 0 -or [string]::IsNullOrWhiteSpace($linuxVsCodeScript)) { throw 'Impossible de convertir le chemin du gestionnaire VS Code WSL avec wslpath.' }
Invoke-WpcExternalCommand -Context $context -FilePath 'wsl.exe' -ArgumentList @('--distribution', $Distribution, '--user', $LinuxUser, '--exec', 'bash', $linuxVsCodeScript, 'apply') -LogIdentity 'scripts/wsl/manage-vscode-extensions.sh' -DisplayName 'manage-vscode-extensions.sh'

Write-Host '[FAIT] Stack DevOps exécutée; chaque sous-script possède son journal dédié.' -ForegroundColor Green
Write-Host '[ACTION REQUISE] Si Docker vient d’ajouter ton utilisateur au groupe docker, exécute « wsl --shutdown » avant le premier usage Docker.' -ForegroundColor Magenta
