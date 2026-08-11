[CmdletBinding()]
param(
    [ValidateSet('standard', 'lab-heavy', 'nat-fallback')]
    [string]$WslProfile = 'standard',
    [string]$Distribution = 'Ubuntu'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$configSource = Join-Path $repoRoot "config\wsl\$WslProfile.wslconfig"
$configTarget = Join-Path $env:USERPROFILE '.wslconfig'
$reportDir = Join-Path $repoRoot 'reports\wsl'
$reportPath = Join-Path $reportDir 'validation-v6.json'

$expected = switch ($WslProfile) {
    'standard' { [ordered]@{ MemoryGB = 20; Processors = 8; SwapGB = 8; Network = 'mirrored' } }
    'lab-heavy' { [ordered]@{ MemoryGB = 28; Processors = 12; SwapGB = 12; Network = 'mirrored' } }
    'nat-fallback' { [ordered]@{ MemoryGB = 20; Processors = 8; SwapGB = 8; Network = 'nat' } }
}

if (-not (Test-Path $configSource)) { throw "Profil source absent: $configSource" }
if (-not (Test-Path $configTarget)) { throw '.wslconfig absent du profil utilisateur.' }

$sourceHash = (Get-FileHash $configSource -Algorithm SHA256).Hash
$targetHash = (Get-FileHash $configTarget -Algorithm SHA256).Hash
if ($sourceHash -ne $targetHash) { throw ".wslconfig actif différent du profil $WslProfile versionné." }

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'wsl.exe introuvable.' }
$wslVersion = (& wsl.exe --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw 'wsl --version a échoué. Mettre WSL à jour.' }

$listVerbose = (& wsl.exe --list --verbose 2>&1 | Out-String) -replace "`0", ''
if ($listVerbose -notmatch [regex]::Escape($Distribution)) { throw "Distribution WSL absente: $Distribution" }
if ($listVerbose -notmatch "(?m)^\s*\*?\s*$([regex]::Escape($Distribution))\s+\S+\s+2\s*$") {
    throw "$Distribution n'est pas qualifiée en WSL2."
}

function Invoke-LinuxValue {
    param([Parameter(Mandatory)][string]$Command)
    $value = (& wsl.exe -d $Distribution -- bash -lc $Command 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Commande Linux échouée: $Command`n$value" }
    return $value
}

$processors = [int](Invoke-LinuxValue 'nproc')
$memoryBytes = [int64](Invoke-LinuxValue "free -b | sed -n '2p' | tr -s ' ' | cut -d ' ' -f 2")
$memoryGB = [math]::Round($memoryBytes / 1GB, 2)
$swapBytes = [int64](Invoke-LinuxValue "free -b | sed -n '3p' | tr -s ' ' | cut -d ' ' -f 2")
$swapGB = [math]::Round($swapBytes / 1GB, 2)
$pid1 = Invoke-LinuxValue 'ps -p 1 -o comm='
$homeFs = Invoke-LinuxValue 'findmnt -T "$HOME" -n -o FSTYPE'
$projectsPath = Invoke-LinuxValue 'printf "%s" "$HOME/projects"'
$projectsExists = (Invoke-LinuxValue 'test -d "$HOME/projects" && echo true || echo false') -eq 'true'

if ($processors -ne $expected.Processors) {
    throw "CPU WSL inattendu: $processors threads vus, attendu $($expected.Processors). Exécuter wsl --shutdown puis relancer."
}
if ($memoryGB -lt ($expected.MemoryGB - 1) -or $memoryGB -gt ($expected.MemoryGB + 1)) {
    throw "RAM WSL inattendue: $memoryGB Go vus, cible $($expected.MemoryGB) Go."
}
if ($swapGB -lt ($expected.SwapGB - 1) -or $swapGB -gt ($expected.SwapGB + 1)) {
    throw "Swap WSL inattendu: $swapGB Go vus, cible $($expected.SwapGB) Go."
}
if ($pid1 -ne 'systemd') { throw "PID 1 Linux inattendu: $pid1 ; systemd attendu." }
if ($homeFs -notmatch '^ext4') { throw "HOME WSL n'est pas sur ext4: $homeFs" }
if (-not $projectsExists) { throw "Répertoire projets WSL absent: $projectsPath" }

$pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if (-not $pwsh) { throw 'PowerShell 7 (pwsh.exe) est absent du socle Windows.' }
$pwshVersionText = (& $pwsh.Source -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' | Out-String).Trim()
$pwshVersion = [version]$pwshVersionText
if ($pwshVersion.Major -lt 7) { throw "Version PowerShell moderne invalide: $pwshVersion" }

New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
[ordered]@{
    Timestamp = (Get-Date).ToString('o')
    Profile = $WslProfile
    Distribution = $Distribution
    WslVersion = $wslVersion
    Expected = $expected
    Measured = [ordered]@{
        Processors = $processors
        MemoryGB = $memoryGB
        SwapGB = $swapGB
        Pid1 = $pid1
        HomeFilesystem = $homeFs
        ProjectsPath = $projectsPath
        ProjectsExists = $projectsExists
        PowerShell = $pwshVersion.ToString()
    }
    ConfigHash = $targetHash
} | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 $reportPath

Write-Host "[OK] WSL2 V6 runtime validé: $WslProfile" -ForegroundColor Green
Write-Host "[OK] $processors threads | $memoryGB Go RAM | $swapGB Go swap | $homeFs | PowerShell $pwshVersion" -ForegroundColor Green
Write-Host 'VERDICT: V6 WSL2 PLATFORM READY' -ForegroundColor Green
