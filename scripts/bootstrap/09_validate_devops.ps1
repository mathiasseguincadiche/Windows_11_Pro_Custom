[CmdletBinding()]
param(
    [string]$Distribution = 'Ubuntu',
    [string]$LinuxUser = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
Import-Module (Join-Path $repoRoot 'scripts\core\runtime.psm1') -Force
$context = Get-WpcRunContextFromEnvironment -RepoRoot $repoRoot
$windowsScript = Join-Path $repoRoot 'scripts\wsl\validate-devops.sh'

if (-not (Test-Path $windowsScript)) { throw "Script absent: $windowsScript" }
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'wsl.exe introuvable.' }
$installed = @((wsl.exe --list --quiet 2>$null) -replace "`0", '' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$global:LASTEXITCODE = 0
if ($installed -notcontains $Distribution) { throw "Distribution WSL absente: $Distribution" }

if ([string]::IsNullOrWhiteSpace($LinuxUser)) {
    $LinuxUser = (& wsl.exe -d $Distribution -- sh -lc 'id -un' 2>$null | Out-String).Trim()
    $userCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($userCode -ne 0 -or [string]::IsNullOrWhiteSpace($LinuxUser)) { throw 'Impossible de déterminer l’utilisateur WSL par défaut.' }
}
if ($LinuxUser -eq 'root') { throw 'Validation DevOps refusée sous root: configure d’abord un utilisateur WSL normal.' }

$linuxScript = (& wsl.exe --distribution $Distribution --user $LinuxUser --exec wslpath -a -u $windowsScript).Trim()
$convertCode = $LASTEXITCODE
$global:LASTEXITCODE = 0
if ($convertCode -ne 0 -or [string]::IsNullOrWhiteSpace($linuxScript)) { throw 'Impossible de convertir le chemin du validateur DevOps avec wslpath.' }

Invoke-WpcExternalCommand -Context $context -FilePath 'wsl.exe' -ArgumentList @('--distribution', $Distribution, '--user', $LinuxUser, '--exec', 'bash', $linuxScript) -LogIdentity 'scripts/wsl/validate-devops.sh' -DisplayName 'validate-devops.sh'
Write-Host '[OK] Stack DevOps WSL validée factuellement.' -ForegroundColor Green
