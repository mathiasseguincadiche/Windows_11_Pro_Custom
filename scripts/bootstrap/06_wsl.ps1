[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Verify')]
    [string]$Mode = 'Apply',
    [ValidateSet('standard', 'lab-heavy', 'nat-fallback')]
    [string]$Profile = 'standard',
    [string]$Distribution = 'Ubuntu',
    [string]$InstallLocation = 'D:\WSL\Ubuntu-DevOps',
    [switch]$UpdateWsl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$configSource = Join-Path $repoRoot "config\wsl\$Profile.wslconfig"
$configTarget = Join-Path $env:USERPROFILE '.wslconfig'
$runtimeContractPath = Join-Path $repoRoot 'config\wsl\runtime-contract.json'
$swapDir = 'D:\WSL\swap'

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw 'wsl.exe est introuvable. Vérifie que Windows 11 est à jour puis exécute « wsl --install --no-distribution » dans PowerShell administrateur et relance la même commande.'
}
if (-not (Test-Path $configSource)) { throw "Profil WSL introuvable: $configSource" }
if (-not (Test-Path $runtimeContractPath)) { throw "Contrat runtime WSL absent: $runtimeContractPath" }

$runtimeContract = Get-Content -Raw $runtimeContractPath | ConvertFrom-Json
$expectedDistribution = [string]$runtimeContract.distribution
$expectedVersionId = [string]$runtimeContract.expectedVersionId
$expectedCodename = [string]$runtimeContract.expectedCodename
$expectedInstallLocation = [string]$runtimeContract.installLocation

if ($Distribution -ne $expectedDistribution) {
    throw "Distribution non conforme au contrat WSL. Demandée=$Distribution Attendue=$expectedDistribution"
}
if ([System.IO.Path]::GetFullPath($InstallLocation).TrimEnd('\') -ne [System.IO.Path]::GetFullPath($expectedInstallLocation).TrimEnd('\')) {
    throw "Emplacement WSL non conforme. Demandé=$InstallLocation Attendu=$expectedInstallLocation"
}

function Get-WslNames {
    try {
        $names = @((wsl.exe --list --quiet 2>$null) -replace "`0", '') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        $global:LASTEXITCODE = 0
        return @($names)
    } catch { return @() }
}

function Get-WslVersionNumber {
    param([Parameter(Mandatory)][string]$Name)
    try {
        $lines = @((wsl.exe --list --verbose 2>$null) -replace "`0", '')
        $global:LASTEXITCODE = 0
        $line = @($lines | Where-Object { $_ -match [regex]::Escape($Name) } | Select-Object -First 1)
        if ($line.Count -gt 0 -and $line[0] -match '\s([12])\s*$') { return [int]$matches[1] }
    } catch {}
    return $null
}

function Test-WslConfigMatch {
    if (-not (Test-Path $configTarget)) { return $false }
    return (Get-FileHash $configSource -Algorithm SHA256).Hash -eq (Get-FileHash $configTarget -Algorithm SHA256).Hash
}

function Get-WslBasePath {
    try {
        foreach ($key in Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction Stop) {
            $item = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
            if ([string]$item.DistributionName -eq $Distribution) { return [string]$item.BasePath }
        }
    } catch {}
    return $null
}

function Normalize-WindowsPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $value = [Environment]::ExpandEnvironmentVariables($Path) -replace '^\\\\\?\\', ''
    try { return [IO.Path]::GetFullPath($value).TrimEnd('\').ToLowerInvariant() } catch { return $value.TrimEnd('\').ToLowerInvariant() }
}

function Test-WslLocationMatch {
    $base = Normalize-WindowsPath (Get-WslBasePath)
    $expected = Normalize-WindowsPath $InstallLocation
    if (-not $base) { return $null }
    return ($base -eq $expected -or $base.StartsWith($expected + '\'))
}

function Get-WslRelease {
    $value = (& wsl.exe -d $Distribution -u root -- bash -lc ". /etc/os-release; printf '%s|%s' \"`$VERSION_ID\" \"`$VERSION_CODENAME\"" 2>&1 | Out-String).Trim()
    $code = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($code -ne 0 -or $value -notmatch '^([^|]+)\|(.+)$') {
        throw "Impossible de lire /etc/os-release dans $Distribution. Sortie: $value"
    }
    return [pscustomobject]@{ VersionId=$matches[1]; Codename=$matches[2] }
}

function Get-WslState {
    param([switch]$ReadRelease)
    $names = Get-WslNames
    $present = $names -contains $Distribution
    $release = $null
    if ($present -and $ReadRelease) { $release = Get-WslRelease }
    return [pscustomobject]@{
        Present = $present
        Version = if ($present) { Get-WslVersionNumber -Name $Distribution } else { $null }
        ConfigMatches = Test-WslConfigMatch
        BasePath = if ($present) { Get-WslBasePath } else { $null }
        LocationMatches = if ($present) { Test-WslLocationMatch } else { $false }
        Release = $release
    }
}

$dVolume = Get-Volume -DriveLetter D -ErrorAction Stop
if ($dVolume.FileSystem -ne 'NTFS') { throw 'D: doit rester NTFS.' }
if ($Mode -eq 'Apply' -and $dVolume.SizeRemaining -lt 50GB) { throw "D: dispose de moins de 50 Go libres. Libère de lʼespace avant lʼinstallation WSL." }

$readRelease = $Mode -eq 'Verify'
$state = Get-WslState -ReadRelease:$readRelease

if ($Mode -eq 'Audit') {
    Write-Host "WSL executable: $((Get-Command wsl.exe).Source)"
    Write-Host "Distribution $Distribution présente: $($state.Present)"
    Write-Host "Version WSL de la distribution: $($state.Version)"
    Write-Host "Profil $Profile conforme: $($state.ConfigMatches)"
    Write-Host "Emplacement observé: $(if ($state.BasePath) { $state.BasePath } else { '<non disponible>' })"
    if ($state.Present -and $state.LocationMatches -eq $true -and $state.Version -eq 2 -and $state.ConfigMatches) {
        Write-Host '[DÉJÀ OK] WSL2 est déjà conforme aux éléments vérifiables sans démarrer la distribution.' -ForegroundColor Green
    } else {
        Write-Host '[À FAIRE] WSL2 présente au moins un écart vérifiable; Apply corrigera uniquement ces écarts.' -ForegroundColor Yellow
    }
    return
}

if ($Mode -eq 'Verify') {
    $failures = [System.Collections.Generic.List[string]]::new()
    if (-not $state.Present) { $failures.Add("Distribution absente: $Distribution") }
    if ($state.Present -and $state.Version -ne 2) { $failures.Add("$Distribution nʼest pas en WSL2 (version=$($state.Version))") }
    if (-not $state.ConfigMatches) { $failures.Add("$configTarget diffère du profil $Profile") }
    if ($state.Present -and $state.LocationMatches -ne $true) { $failures.Add("emplacement non prouvé/conforme: observé=$($state.BasePath) attendu=$InstallLocation") }
    if ($state.Release) {
        if ($state.Release.VersionId -ne $expectedVersionId -or $state.Release.Codename -ne $expectedCodename) {
            $failures.Add("release Ubuntu=$($state.Release.VersionId)/$($state.Release.Codename), attendue=$expectedVersionId/$expectedCodename")
        }
    }
    if ($failures.Count -gt 0) { throw "WSL2 non conforme: $($failures -join '; ')" }
    Write-Host "[OK] WSL2 vérifié: $Distribution WSL2, Ubuntu $expectedVersionId ($expectedCodename), profil $Profile, stockage D:." -ForegroundColor Green
    return
}

$changes = [System.Collections.Generic.List[string]]::new()

if ($state.Present -and $state.Version -eq 2 -and $state.ConfigMatches -and $state.LocationMatches -eq $true) {
    $releaseNow = Get-WslRelease
    if ($releaseNow.VersionId -eq $expectedVersionId -and $releaseNow.Codename -eq $expectedCodename -and -not $UpdateWsl) {
        Write-Host "[DÉJÀ OK] WSL2 est entièrement conforme: aucune réinstallation, copie de profil, conversion ou shutdown inutile." -ForegroundColor Green
        return
    }
}

New-Item -ItemType Directory -Force -Path (Split-Path $InstallLocation) | Out-Null
New-Item -ItemType Directory -Force -Path $swapDir | Out-Null

if ($UpdateWsl -or -not $state.Present) {
    Write-Host '[EN COURS] Vérification/mise à jour du runtime WSL Store...'
    wsl.exe --update
    $updateCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($updateCode -ne 0) {
        Write-Warning 'wsl --update nʼa pas abouti. Le script continue avec le runtime disponible; vérifie Microsoft Store/Windows Update si lʼinstallation échoue.'
    } else {
        $changes.Add('runtime WSL vérifié/mis à jour')
    }
}

if (-not $state.Present) {
    Write-Host "[EN COURS] Installation de $Distribution dans $InstallLocation" -ForegroundColor Cyan
    wsl.exe --set-default-version 2
    $defaultCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($defaultCode -ne 0) { throw 'Échec de wsl --set-default-version 2.' }

    wsl.exe --install --distribution $Distribution --location $InstallLocation --no-launch
    $installCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($installCode -ne 0) {
        throw 'Installation WSL interrompue. Si Windows demande un redémarrage: redémarre Windows puis relance exactement la même commande; les étapes déjà conformes seront ignorées.'
    }
    $changes.Add("distribution $Distribution installée")
    $state = Get-WslState
} elseif ($state.Version -ne 2) {
    Write-Host "[EN COURS] Conversion de $Distribution vers WSL2..." -ForegroundColor Cyan
    wsl.exe --set-version $Distribution 2
    $convertCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($convertCode -ne 0) { throw "Conversion WSL2 échouée pour $Distribution." }
    $changes.Add("distribution $Distribution convertie en WSL2")
}

if (-not (Test-WslConfigMatch)) {
    Copy-Item -Force $configSource $configTarget
    $changes.Add("profil $Profile installé dans $configTarget")
}

$locationMatch = Test-WslLocationMatch
if ($locationMatch -ne $true) {
    throw "La distribution existe mais son emplacement nʼest pas conforme/prouvable. Observé=$(Get-WslBasePath) Attendu=$InstallLocation. Aucune suppression automatique nʼest effectuée."
}

$release = Get-WslRelease
if ($release.VersionId -ne $expectedVersionId -or $release.Codename -ne $expectedCodename) {
    throw "Release Ubuntu non conforme: VERSION_ID=$($release.VersionId) CODENAME=$($release.Codename) ; attendu $expectedVersionId/$expectedCodename. Aucune suppression automatique nʼest effectuée."
}

if ($changes.Count -gt 0) {
    wsl.exe --shutdown
    $global:LASTEXITCODE = 0
    Write-Host "[FAIT] WSL2 configuré et revalidé: $($changes -join '; ')." -ForegroundColor Green
} else {
    Write-Host '[DÉJÀ OK] WSL2 conforme; aucune mutation requise.' -ForegroundColor Green
}
Write-Host "[OK] Contrat Ubuntu validé: $Distribution $($release.VersionId) ($($release.Codename))" -ForegroundColor Green
