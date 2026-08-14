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
    $lastDockerOutput = ''
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        $probe = Invoke-WslUserCommand -Command 'docker info >/dev/null 2>&1' -IgnoreExitCode
        if ($probe.ExitCode -eq 0) {
            $dockerReady = $true
            break
        }
        $lastDockerOutput = $probe.Output
        Start-Sleep -Seconds 1
    }
    if (-not $dockerReady) {
        throw "Docker nʼest pas accessible sans sudo après redémarrage contrôlé de la session WSL. Dernière sortie: $lastDockerOutput"
    }
    Write-Host "[OK] Nouvelle session WSL active: groupe docker chargé et Docker Engine accessible sans sudo." -ForegroundColor Green
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
# immédiate de l’orchestrateur doit donc démarrer une nouvelle session WSL avant de
# tester docker info; sinon une première installation correcte peut être déclarée KO.
Restart-WslSessionAfterDockerGroupChange

Write-Host '[3/4] Terminal Bash DevOps' -ForegroundColor Cyan
$linuxTerminalScript = (& wsl.exe --distribution $Distribution --user $LinuxUser --exec wslpath -a -u $terminalScript).Trim()
$convertTerminal = $LASTEXITCODE
$global:LASTEXITCODE = 0
if ($convertTerminal -ne 0 -or [string]::IsNullOrWhiteSpace($linuxTerminalScript)) { throw 'Impossible de convertir le chemin du gestionnaire Terminal DevOps avec wslpath.' }
Invoke-WpcExternalCommand -Context $context -FilePath 'wsl.exe' -ArgumentList @('--distribution', $Distribution, '--user', $LinuxUser, '--exec', 'bash', $linuxTerminalScript, 'apply') -LogIdentity 'scripts/wsl/manage-devops-terminal.sh' -DisplayName 'manage-devops-terminal.sh'

Write-Host '[4/4] Extensions VS Code dans WSL' -ForegroundColor Cyan
$linuxVsCodeScript = (& wsl.exe --distribution $Distribution --user $LinuxUser --exec wslpath -a -u $vscodeWslScript).Trim()
$convertVsCode = $LASTEXITCODE
$global:LASTEXITCODE = 0
if ($convertVsCode -ne 0 -or [string]::IsNullOrWhiteSpace($linuxVsCodeScript)) { throw 'Impossible de convertir le chemin du gestionnaire VS Code WSL avec wslpath.' }
Invoke-WpcExternalCommand -Context $context -FilePath 'wsl.exe' -ArgumentList @('--distribution', $Distribution, '--user', $LinuxUser, '--exec', 'bash', $linuxVsCodeScript, 'apply') -LogIdentity 'scripts/wsl/manage-vscode-extensions.sh' -DisplayName 'manage-vscode-extensions.sh'

Write-Host '[FAIT] Stack DevOps + terminal exécutés; la session WSL a été rechargée automatiquement après Docker et chaque sous-script possède son journal dédié.' -ForegroundColor Green
