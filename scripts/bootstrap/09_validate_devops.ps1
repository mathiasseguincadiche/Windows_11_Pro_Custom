[CmdletBinding()]
param(
    [string]$Distribution = 'Ubuntu',
    [string]$LinuxUser = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
Import-Module (Join-Path $repoRoot 'scripts\core\runtime.psm1')
$context = Get-WpcRunContextFromEnvironment -RepoRoot $repoRoot
$windowsScript = Join-Path $repoRoot 'scripts\wsl\validate-devops.sh'
$terminalScript = Join-Path $repoRoot 'scripts\wsl\validate-devops-terminal.sh'

foreach ($path in @($windowsScript, $terminalScript)) {
    if (-not (Test-Path $path)) { throw "Script absent: $path" }
}
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
if ($LinuxUser -eq 'root') { throw 'Validation DevOps refusée sous root: configure dʼabord un utilisateur WSL normal.' }

foreach ($item in @(
    @{ WindowsPath=$windowsScript; Log='scripts/wsl/validate-devops.sh'; Name='validate-devops.sh' },
    @{ WindowsPath=$terminalScript; Log='scripts/wsl/validate-devops-terminal.sh'; Name='validate-devops-terminal.sh' }
)) {
    $linuxScript = (& wsl.exe --distribution $Distribution --user $LinuxUser --exec wslpath -a -u $item.WindowsPath).Trim()
    $convertCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($convertCode -ne 0 -or [string]::IsNullOrWhiteSpace($linuxScript)) { throw "Impossible de convertir le chemin de $($item.Name) avec wslpath." }
    Invoke-WpcExternalCommand -Context $context -FilePath 'wsl.exe' -ArgumentList @('--distribution', $Distribution, '--user', $LinuxUser, '--exec', 'bash', $linuxScript) -LogIdentity $item.Log -DisplayName $item.Name
}

Write-Host '[OK] Stack DevOps + terminal validés factuellement.' -ForegroundColor Green
