[CmdletBinding()]
param(
    [ValidateSet('standard', 'lab-heavy', 'nat-fallback')]
    [string]$WslProfile = 'standard',
    [string]$Distribution = 'Ubuntu'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$release = (Get-Content -Raw (Join-Path $repoRoot 'VERSION')).Trim()
if ($release -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION invalide: $release" }
$configSource = Join-Path $repoRoot "config\wsl\$WslProfile.wslconfig"
$configTarget = Join-Path $env:USERPROFILE '.wslconfig'
$runtimeContractPath = Join-Path $repoRoot 'config\wsl\runtime-contract.json'
$reportDir = Join-Path $repoRoot 'reports\wsl'
$reportPath = Join-Path $reportDir 'validation.json'

$expected = switch ($WslProfile) {
    'standard' { [ordered]@{ MemoryGB=20; Processors=8; SwapGB=8; Network='mirrored' } }
    'lab-heavy' { [ordered]@{ MemoryGB=28; Processors=12; SwapGB=12; Network='mirrored' } }
    'nat-fallback' { [ordered]@{ MemoryGB=20; Processors=8; SwapGB=8; Network='nat' } }
}
if (-not (Test-Path $configSource)) { throw "Profil source absent: $configSource" }
if (-not (Test-Path $configTarget)) { throw '.wslconfig absent du profil utilisateur.' }
if (-not (Test-Path $runtimeContractPath)) { throw "Contrat runtime WSL absent: $runtimeContractPath" }
$runtimeContract = Get-Content -Raw $runtimeContractPath | ConvertFrom-Json
if ($Distribution -ne [string]$runtimeContract.distribution) { throw "Distribution WSL différente du contrat. Demandée=$Distribution Attendue=$($runtimeContract.distribution)" }

$workingRoots = @($runtimeContract.workingRoots); $utilityRoots=@($runtimeContract.utilityRoots); $forbiddenRoots=@($runtimeContract.forbiddenRoots)
if ($workingRoots.Count -eq 0) { throw 'Contrat WSL invalide: workingRoots est vide.' }
if ($forbiddenRoots.Count -eq 0) { throw 'Contrat WSL invalide: forbiddenRoots est vide.' }
foreach ($root in @($workingRoots + $utilityRoots)) { if ([string]$root -notmatch '^~/[A-Za-z0-9._/-]+$') { throw "Racine Linux gérée invalide dans le contrat: $root" } }
foreach ($root in $forbiddenRoots) { if ([string]$root -notmatch '^/[A-Za-z0-9._/-]+$') { throw "Racine interdite invalide dans le contrat: $root" } }

$sourceHash=(Get-FileHash $configSource -Algorithm SHA256).Hash; $targetHash=(Get-FileHash $configTarget -Algorithm SHA256).Hash
if ($sourceHash -ne $targetHash) { throw ".wslconfig actif différent du profil $WslProfile versionné." }
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'wsl.exe introuvable.' }
$wslVersion=(& wsl.exe --version 2>&1 | Out-String).Trim(); if ($LASTEXITCODE -ne 0) { throw 'wsl --version a échoué. Mettre WSL à jour.' }
$listVerbose=(& wsl.exe --list --verbose 2>&1 | Out-String) -replace "`0", ''
if ($listVerbose -notmatch [regex]::Escape($Distribution)) { throw "Distribution WSL absente: $Distribution" }
if ($listVerbose -notmatch "(?m)^\s*\*?\s*$([regex]::Escape($Distribution))\s+\S+\s+2\s*$") { throw "$Distribution n'est pas qualifiée en WSL2." }

function Invoke-LinuxValue {
    param([Parameter(Mandatory)][string]$Command)
    $value=(& wsl.exe -d $Distribution -- bash -lc $Command 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Commande Linux échouée: $Command`n$value" }
    return $value
}
function Resolve-ManagedLinuxRoot {
    param([Parameter(Mandatory)][string]$DeclaredRoot)
    $relative=$DeclaredRoot.Substring(2)
    return Invoke-LinuxValue "printf '%s' \"`$HOME/$relative\""
}

$versionId=Invoke-LinuxValue ". /etc/os-release; printf '%s' \"`$VERSION_ID\""
$codename=Invoke-LinuxValue ". /etc/os-release; printf '%s' \"`$VERSION_CODENAME\""
if ($versionId -ne [string]$runtimeContract.expectedVersionId) { throw "Ubuntu VERSION_ID inattendu: $versionId ; attendu $($runtimeContract.expectedVersionId)." }
if ($codename -ne [string]$runtimeContract.expectedCodename) { throw "Ubuntu VERSION_CODENAME inattendu: $codename ; attendu $($runtimeContract.expectedCodename)." }
$processors=[int](Invoke-LinuxValue 'nproc')
$memoryBytes=[int64](Invoke-LinuxValue "free -b | sed -n '2p' | tr -s ' ' | cut -d ' ' -f 2"); $memoryGB=[math]::Round($memoryBytes/1GB,2)
$swapBytes=[int64](Invoke-LinuxValue "free -b | sed -n '3p' | tr -s ' ' | cut -d ' ' -f 2"); $swapGB=[math]::Round($swapBytes/1GB,2)
$pid1=Invoke-LinuxValue 'ps -p 1 -o comm='; $homeFs=Invoke-LinuxValue 'findmnt -T "$HOME" -n -o FSTYPE'
if ($processors -ne $expected.Processors) { throw "CPU WSL inattendu: $processors threads vus, attendu $($expected.Processors). Exécuter wsl --shutdown puis relancer." }
if ($memoryGB -lt ($expected.MemoryGB-1) -or $memoryGB -gt ($expected.MemoryGB+1)) { throw "RAM WSL inattendue: $memoryGB Go vus, cible $($expected.MemoryGB) Go." }
if ($swapGB -lt ($expected.SwapGB-1) -or $swapGB -gt ($expected.SwapGB+1)) { throw "Swap WSL inattendu: $swapGB Go vus, cible $($expected.SwapGB) Go." }
if ($pid1 -ne 'systemd') { throw "PID 1 Linux inattendu: $pid1 ; systemd attendu." }
if ($homeFs -notmatch '^ext4') { throw "HOME WSL n'est pas sur ext4: $homeFs" }

$managedRootMeasurements=@()
foreach ($declaredRoot in @($workingRoots + $utilityRoots)) {
    $path=Resolve-ManagedLinuxRoot -DeclaredRoot ([string]$declaredRoot)
    $exists=(Invoke-LinuxValue "test -d '$path' && echo true || echo false") -eq 'true'
    if (-not $exists) { throw "Répertoire Linux géré absent: $path" }
    foreach ($forbiddenRoot in $forbiddenRoots) { $forbidden=[string]$forbiddenRoot; if ($path -eq $forbidden -or $path.StartsWith("$forbidden/",[System.StringComparison]::Ordinal)) { throw "Racine Linux gérée sur montage Windows interdit: $path" } }
    $pathFs=Invoke-LinuxValue "findmnt -T '$path' -n -o FSTYPE"; if ($pathFs -notmatch '^ext4') { throw "Racine Linux gérée hors ext4: $path ($pathFs)" }
    $managedRootMeasurements += [ordered]@{ Declared=[string]$declaredRoot; Path=$path; Exists=$exists; Filesystem=$pathFs; Kind=if ($workingRoots -contains [string]$declaredRoot) {'working'} else {'utility'} }
}

$pwsh=Get-Command pwsh.exe -ErrorAction SilentlyContinue; if (-not $pwsh) { throw 'PowerShell 7 (pwsh.exe) est absent du socle Windows.' }
$pwshVersion=[version]((& $pwsh.Source -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' | Out-String).Trim())
if ($pwshVersion.Major -lt 7) { throw "Version PowerShell moderne invalide: $pwshVersion" }

New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
[ordered]@{
    Release=$release; SchemaVersion=1; Timestamp=(Get-Date).ToString('o'); Profile=$WslProfile; Distribution=$Distribution
    UbuntuVersionId=$versionId; UbuntuCodename=$codename; WslVersion=$wslVersion; Expected=$expected; RuntimeContract=$runtimeContract
    Measured=[ordered]@{ Processors=$processors; MemoryGB=$memoryGB; SwapGB=$swapGB; Pid1=$pid1; HomeFilesystem=$homeFs; ManagedRoots=$managedRootMeasurements; PowerShell=$pwshVersion.ToString() }
    ConfigHash=$targetHash
} | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 $reportPath
Write-Host "[OK] WSL2 runtime validé: $WslProfile" -ForegroundColor Green
Write-Host "[OK] Ubuntu $versionId ($codename) | $processors threads | $memoryGB Go RAM | $swapGB Go swap | $homeFs | PowerShell $pwshVersion" -ForegroundColor Green
Write-Host 'VERDICT: WSL2 PLATFORM READY' -ForegroundColor Green
