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
Import-Module $runtimeModule
$context = Get-WpcRunContextFromEnvironment -RepoRoot $repoRoot
$linuxScriptWindows = Join-Path $repoRoot 'scripts\wsl\reconcile-pinned-devops.sh'

if (-not (Test-Path $linuxScriptWindows)) { throw "Script DevOps absent: $linuxScriptWindows" }
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'wsl.exe introuvable.' }

$installed = @((wsl.exe --list --quiet 2>$null) -replace "`0", '' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$global:LASTEXITCODE = 0
if ($installed -notcontains $Distribution) { throw "Distribution WSL absente: $Distribution" }

if ([string]::IsNullOrWhiteSpace($LinuxUser)) {
    $LinuxUser = (& wsl.exe -d $Distribution -- sh -lc 'id -un' 2>$null | Out-String).Trim()
    $userCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($userCode -ne 0 -or [string]::IsNullOrWhiteSpace($LinuxUser)) { throw 'Impossible de déterminer lʼutilisateur WSL par défaut.' }
}
if ($LinuxUser -eq 'root') { throw 'La réconciliation DevOps doit sʼexécuter avec lʼutilisateur WSL normal, pas root.' }

$linuxScript = (& wsl.exe --distribution $Distribution --user $LinuxUser --exec wslpath -a -u $linuxScriptWindows).Trim()
$convertCode = $LASTEXITCODE
$global:LASTEXITCODE = 0
if ($convertCode -ne 0 -or [string]::IsNullOrWhiteSpace($linuxScript)) { throw 'Impossible de convertir le chemin reconcile-pinned-devops.sh avec wslpath.' }

$modeLower = $Mode.ToLowerInvariant()
$result = Invoke-WpcExternalCommand -Context $context -FilePath 'wsl.exe' -ArgumentList @('--distribution',$Distribution,'--user',$LinuxUser,'--exec','bash',$linuxScript,$modeLower) -LogIdentity 'scripts/wsl/reconcile-pinned-devops.sh' -DisplayName 'DevOps pinned versions' -AllowFailure
if (-not $result.Success) { throw "Réconciliation DevOps en échec: $($result.Error)" }

if ($Mode -eq 'Apply') {
    Write-Host '[FAIT] Outils DevOps réconciliés vers les versions définies dans le dépôt.' -ForegroundColor Green
} elseif ($Mode -eq 'Verify') {
    Write-Host '[DÉJÀ OK] Versions DevOps épinglées conformes.' -ForegroundColor Green
}
