[CmdletBinding()]
param(
    [ValidateSet('Audit','Apply','Verify')]
    [string]$Mode = 'Audit'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$contractPath = Join-Path $repoRoot 'config\wsl\runtime-contract.json'
if (-not (Test-Path $contractPath)) { throw "Contrat WSL absent: $contractPath" }
$contract = Get-Content -Raw $contractPath | ConvertFrom-Json
$distribution = [string]$contract.distribution

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw 'wsl.exe est introuvable.'
}

function Invoke-Capture {
    param([string[]]$Arguments)
    $output = @(& wsl.exe @Arguments 2>&1)
    $code = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    return [pscustomobject]@{ Code=$code; Lines=@($output | ForEach-Object { ([string]$_) -replace "`0", '' }) }
}

function Test-DistributionPresent {
    $result = Invoke-Capture -Arguments @('--list','--quiet')
    if ($result.Code -ne 0) { return $false }
    return @($result.Lines | ForEach-Object { $_.Trim() }) -contains $distribution
}

function Get-WslVersionText {
    $result = Invoke-Capture -Arguments @('--version')
    if ($result.Code -ne 0) { throw "wsl --version a échoué: $($result.Lines -join ' | ')" }
    return ($result.Lines -join "`n")
}

function Get-WslUpgradeSignal {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Detectable=$false; Pending=$false; Detail='WinGet absent: disponibilité WSL non détectable sans mutation.' }
    }
    $output = @(& winget.exe list --id Microsoft.WSL --exact --upgrade-available --accept-source-agreements --disable-interactivity 2>&1)
    $global:LASTEXITCODE = 0
    $lines = @($output | ForEach-Object { [string]$_ })
    $separator = -1
    for ($i=0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*-{3,}') { $separator=$i; break }
    }
    if ($separator -lt 0) {
        return [pscustomobject]@{ Detectable=$true; Pending=$false; Detail='Aucune ligne WinGet de mise à jour WSL.' }
    }
    $rows = @($lines[($separator+1)..($lines.Count-1)] | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    return [pscustomobject]@{ Detectable=$true; Pending=($rows.Count -gt 0); Detail=($rows -join ' | ') }
}

$present = Test-DistributionPresent
$versionText = Get-WslVersionText
$signal = Get-WslUpgradeSignal

Write-Host '[INFO] Runtime WSL détecté:' -ForegroundColor Cyan
$versionText -split "`r?`n" | ForEach-Object { if ($_){ Write-Host ("  {0}" -f $_) } }
Write-Host ("[INFO] Distribution contractuelle {0} présente: {1}" -f $distribution, $present)

if ($signal.Pending) {
    Write-Host '[À FAIRE] Une mise à jour du package Microsoft.WSL est détectée par WinGet.' -ForegroundColor Yellow
    if ($signal.Detail) { Write-Host ("  {0}" -f $signal.Detail) -ForegroundColor DarkGray }
} else {
    Write-Host '[DÉJÀ OK] Aucun signal WinGet de mise à jour WSL en attente.' -ForegroundColor Green
}

if ($Mode -eq 'Audit') { return }

if ($Mode -eq 'Verify') {
    if (-not $present) { throw "Distribution WSL contractuelle absente: $distribution" }
    if ($signal.Pending) { throw 'Une mise à jour WSL est encore signalée par WinGet.' }
    Write-Host '[DÉJÀ OK] Runtime WSL accessible et distribution contractuelle présente.' -ForegroundColor Green
    return
}

Write-Host '[EN COURS] Exécution de wsl.exe --update. La commande est idempotente si WSL est déjà à jour.' -ForegroundColor Cyan
$result = Invoke-Capture -Arguments @('--update')
$result.Lines | ForEach-Object { if ($_){ Write-Host ("  {0}" -f $_) } }
if ($result.Code -ne 0) { throw "wsl --update a échoué (code=$($result.Code))." }

if (-not (Test-DistributionPresent)) { throw "Après mise à jour WSL, la distribution $distribution n’est plus visible." }
$after = Get-WslUpgradeSignal
if ($after.Pending) { throw 'wsl --update a terminé mais WinGet signale encore une mise à jour Microsoft.WSL.' }
Write-Host '[FAIT] Runtime WSL vérifié/mis à jour sans modifier la distribution Ubuntu.' -ForegroundColor Green
