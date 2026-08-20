[CmdletBinding()]
param(
    [string]$Distribution = 'Ubuntu',
    [string]$LinuxUser = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$runtimeModule = Join-Path $repoRoot 'scripts\core\runtime.psm1'
Import-Module $runtimeModule
$context = Get-WpcRunContextFromEnvironment -RepoRoot $repoRoot
$windowsScript = Join-Path $repoRoot 'scripts\wsl\install-devops.sh'
$terminalScript = Join-Path $repoRoot 'scripts\wsl\manage-devops-terminal.sh'
$wslConfScript = Join-Path $repoRoot 'scripts\wsl\apply-wsl-conf.ps1'
$vscodeWslScript = Join-Path $repoRoot 'scripts\wsl\manage-vscode-extensions.sh'

foreach ($path in @($windowsScript, $terminalScript, $wslConfScript, $vscodeWslScript)) {
    if (-not (Test-Path $path)) { throw "Script absent: $path" }
}
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'wsl.exe introuvable.' }

$installed = @((wsl.exe --list --quiet 2>$null) -replace "`0", '' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$global:LASTEXITCODE = 0
if ($installed -notcontains $Distribution) { throw "Distribution WSL absente: $Distribution." }

if ([string]::IsNullOrWhiteSpace($LinuxUser)) {
    $LinuxUser = (& wsl.exe -d $Distribution -- sh -lc 'id -un' 2>$null | Out-String).Trim()
    $userCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($userCode -ne 0 -or [string]::IsNullOrWhiteSpace($LinuxUser)) { throw 'Impossible de déterminer lʼutilisateur WSL par défaut.' }
}
if ($LinuxUser -eq 'root') {
    throw 'Le bootstrap DevOps refuse root. Exécute dʼabord la préparation utilisateur WSL; elle crée/configure un utilisateur normal de façon guidée.'
}

& wsl.exe -d $Distribution -u root -- sh -lc "getent passwd '$LinuxUser' >/dev/null"
$userExistsCode = $LASTEXITCODE
$global:LASTEXITCODE = 0
if ($userExistsCode -ne 0) { throw "Utilisateur WSL absent: $LinuxUser" }

function Invoke-WslUserCommand {
    param(
        [Parameter(Mandatory)][string]$Command,
        [switch]$IgnoreExitCode
    )
    $output = (& wsl.exe --distribution $Distribution --user $LinuxUser --exec sh -lc $Command 2>&1 | Out-String).Trim()
    $code = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($code -ne 0 -and -not $IgnoreExitCode) {
        throw "Commande WSL échouée pour $LinuxUser (code=$code): $Command`n$output"
    }
    return [pscustomobject]@{ ExitCode=$code; Output=$output }
}

function Restart-WslSessionAfterDockerGroupChange {
    Write-Host '[2.5/4] Rechargement de la session WSL après configuration Docker' -ForegroundColor Cyan
    & wsl.exe --terminate $Distribution
    $terminateCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($terminateCode -ne 0) { throw "Impossible de terminer $Distribution après installation Docker (code=$terminateCode)." }

    Start-Sleep -Milliseconds 750
    $groups = Invoke-WslUserCommand -Command 'id -nG'
    if (@($groups.Output -split '\s+') -notcontains 'docker') {
        throw "Le groupe docker nʼest pas visible dans la nouvelle session WSL de '$LinuxUser'. Groupes observés: $($groups.Output)"
    }

    $dockerReady = $false
    $maxAttempts = 60
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $probe = Invoke-WslUserCommand -Command 'docker info >/dev/null 2>&1' -IgnoreExitCode
        if ($probe.ExitCode -eq 0) {
            $dockerReady = $true
            Write-Host "[OK] Docker prêt après $attempt tentative(s)." -ForegroundColor Green
            break
        }
        if ($attempt -in @(1,10,20,30,45)) {
            Write-Host "[ATTENTE] Docker démarre encore... tentative $attempt/$maxAttempts" -ForegroundColor Yellow
        }
        Start-Sleep -Seconds 1
    }
    if (-not $dockerReady) {
        $serviceState = Invoke-WslUserCommand -Command 'systemctl is-active docker 2>/dev/null || true' -IgnoreExitCode
        $serviceStatus = Invoke-WslUserCommand -Command 'systemctl --no-pager --full status docker 2>&1 | tail -n 20 || true' -IgnoreExitCode
        $journal = Invoke-WslUserCommand -Command 'journalctl -u docker --no-pager -n 30 2>&1 || true' -IgnoreExitCode
        throw "Docker nʼest pas accessible sans sudo après $maxAttempts secondes. systemd=$($serviceState.Output). Status: $($serviceStatus.Output). Journal: $($journal.Output)"
    }
    Write-Host '[OK] Nouvelle session WSL active: groupe docker chargé et Docker Engine accessible sans sudo.' -ForegroundColor Green
}

Write-Host '[1/4] /etc/wsl.conf et systemd' -ForegroundColor Cyan
[void](Invoke-WpcManagedScript -Context $context -Path $wslConfScript -DisplayName 'Configuration /etc/wsl.conf' -Arguments @{ Distribution=$Distribution; LinuxUser=$LinuxUser } -Phase 'DevOps')

Write-Host '[2/4] Stack DevOps Linux' -ForegroundColor Cyan
$linuxScript = (& wsl.exe --distribution $Distribution --user $LinuxUser --exec wslpath -a -u $windowsScript).Trim()
$convertCode = $LASTEXITCODE
$global:LASTEXITCODE = 0
if ($convertCode -ne 0 -or [string]::IsNullOrWhiteSpace($linuxScript)) { throw 'Impossible de convertir le chemin du bootstrap DevOps avec wslpath.' }
Invoke-WpcExternalCommand -Context $context -FilePath 'wsl.exe' -ArgumentList @('--distribution', $Distribution, '--user', $LinuxUser, '--exec', 'bash', $linuxScript) -LogIdentity 'scripts/wsl/install-devops.sh' -DisplayName 'install-devops.sh'

# install-devops.sh ajoute l’utilisateur au groupe docker. Les groupes auxiliaires d’une
# session Linux déjà ouverte ne sont pas recalculés dynamiquement. La revalidation
# immédiate de l’orchestrateur démarre donc une nouvelle session WSL puis attend
# Docker jusqu’à 60 secondes avec diagnostics systemd/journal en cas d’échec.
Restart-WslSessionAfterDockerGroupChange

Write-Host '[3/4] Terminal Bash DevOps' -ForegroundColor Cyan
$linuxTerminalScript = (& wsl.exe --distribution $Distribution --user $LinuxUser --exec wslpath -a -u $terminalScript).Trim()
$convertTerminal = $LASTEXITCODE
$global:LASTEXITCODE = 0
if ($convertTerminal -ne 0 -or [string]::IsNullOrWhiteSpace($linuxTerminalScript)) { throw 'Impossible de convertir le chemin du gestionnaire Terminal DevOps avec wslpath.' }
Invoke-WpcExternalCommand -Context $context -FilePath 'wsl.exe' -ArgumentList @('--distribution', $Distribution, '--user', $LinuxUser, '--exec', 'bash', $linuxTerminalScript, 'apply') -LogIdentity 'scripts/wsl/manage-devops-terminal.sh' -DisplayName 'manage-devops-terminal.sh'

Write-Host '[4/4] Extensions VS Code dans WSL (advisory)' -ForegroundColor Cyan
$linuxVsCodeScript = (& wsl.exe --distribution $Distribution --user $LinuxUser --exec wslpath -a -u $vscodeWslScript).Trim()
$convertVsCode = $LASTEXITCODE
$global:LASTEXITCODE = 0
if ($convertVsCode -ne 0 -or [string]::IsNullOrWhiteSpace($linuxVsCodeScript)) {
    Write-WpcStatus -Status 'AVERTISSEMENT' -Message 'Intégration VS Code WSL non exécutée' -Detail 'wslpath n a pas pu convertir le chemin. La stack DevOps cœur reste valide.' -Context $context
} else {
    Invoke-WpcExternalCommand -Context $context -FilePath 'wsl.exe' -ArgumentList @('--distribution', $Distribution, '--user', $LinuxUser, '--exec', 'bash', $linuxVsCodeScript, 'apply') -LogIdentity 'scripts/wsl/manage-vscode-extensions.sh' -DisplayName 'manage-vscode-extensions.sh'
}

Write-Host '[FAIT] Stack DevOps cœur + terminal exécutés; Docker a été revalidé après redémarrage de session. VS Code WSL reste un complément non bloquant.' -ForegroundColor Green
