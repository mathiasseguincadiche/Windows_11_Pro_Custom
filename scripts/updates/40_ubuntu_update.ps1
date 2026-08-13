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
$linuxScriptWindows = Join-Path $repoRoot 'scripts\wsl\update-system-packages.sh'

if (-not (Test-Path $linuxScriptWindows)) { throw "Script Ubuntu absent: $linuxScriptWindows" }
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
if ($LinuxUser -eq 'root') { throw 'La mise à jour Ubuntu doit s’exécuter avec l’utilisateur WSL normal, pas root.' }

$linuxScript = (& wsl.exe --distribution $Distribution --user $LinuxUser --exec wslpath -a -u $linuxScriptWindows).Trim()
$convertCode = $LASTEXITCODE
$global:LASTEXITCODE = 0
if ($convertCode -ne 0 -or [string]::IsNullOrWhiteSpace($linuxScript)) { throw 'Impossible de convertir le chemin update-system-packages.sh avec wslpath.' }

$modeLower = $Mode.ToLowerInvariant()
$result = Invoke-WpcExternalCommand -Context $context -FilePath 'wsl.exe' -ArgumentList @('--distribution',$Distribution,'--user',$LinuxUser,'--exec','bash',$linuxScript,$modeLower) -LogIdentity 'scripts/wsl/update-system-packages.sh' -DisplayName 'Ubuntu 26.04 / APT updates' -AllowFailure
if (-not $result.Success) { throw "Mise à jour Ubuntu en échec: $($result.Error)" }

if ($Mode -eq 'Apply') {
    Write-Host '[FAIT] Ubuntu/apt exécuté puis revalidé dans WSL.' -ForegroundColor Green
} elseif ($Mode -eq 'Verify') {
    Write-Host '[DÉJÀ OK] Ubuntu/apt ne signale plus de mise à jour installable.' -ForegroundColor Green
}
