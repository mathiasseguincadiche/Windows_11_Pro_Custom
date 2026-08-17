[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Record', 'Verify')]
    [string]$Mode = 'Audit',

    [switch]$ConfirmHealthyState
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ReportRoot = Join-Path $RepoRoot 'reports\workstation-v26'
$LocalBaselineRoot = Join-Path $env:ProgramData 'Windows11ProCustom\workstation-v26'
$LocalBaselinePath = Join-Path $LocalBaselineRoot 'workstation-fingerprint.json'
$StorageIdentityPath = Join-Path $env:ProgramData 'Windows11ProCustom\storage-v25\volume-identity.json'

function Get-RelativePathPortable {
    param([Parameter(Mandatory)][string]$BasePath, [Parameter(Mandatory)][string]$ChildPath)
    $baseUri = [Uri]((Resolve-Path $BasePath).Path.TrimEnd('\') + '\')
    $childUri = [Uri](Resolve-Path $ChildPath).Path
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($childUri).ToString()).Replace('/', '\')
}

function Get-ContractDigest {
    $roots = @('config', 'manifests')
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($rootName in $roots) {
        $root = Join-Path $RepoRoot $rootName
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse | Sort-Object FullName) {
            $entries.Add([ordered]@{
                path = Get-RelativePathPortable -BasePath $RepoRoot -ChildPath $file.FullName
                sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            })
        }
    }
    $canonical = ($entries | ConvertTo-Json -Depth 4 -Compress)
    $bytes = [Text.Encoding]::UTF8.GetBytes($canonical)
    $stream = [IO.MemoryStream]::new($bytes)
    try {
        $digest = (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash
    } finally {
        $stream.Dispose()
    }
    return [ordered]@{ sha256 = $digest; files = @($entries) }
}

function Get-WslSnapshot {
    $command = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        return [ordered]@{ available = $false; version = $null; distributions = @() }
    }
    $versionOutput = @(& wsl.exe --version 2>$null | ForEach-Object { ($_ -replace "`0", '').TrimEnd() })
    $versionExit = $LASTEXITCODE
    $distroOutput = @(& wsl.exe --list --quiet 2>$null | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
    $distroExit = $LASTEXITCODE
    return [ordered]@{
        available = $true
        versionQueryExitCode = $versionExit
        version = if ($versionExit -eq 0) { $versionOutput -join ' | ' } else { $null }
        distributionQueryExitCode = $distroExit
        distributions = if ($distroExit -eq 0) { @($distroOutput | Sort-Object) } else { @() }
    }
}

function Get-WorkstationFingerprint {
    $os = Get-CimInstance Win32_OperatingSystem
    $computer = Get-CimInstance Win32_ComputerSystem
    $cpu = @(Get-CimInstance Win32_Processor | ForEach-Object { $_.Name.Trim() } | Sort-Object)
    $board = @(Get-CimInstance Win32_BaseBoard | ForEach-Object { "$($_.Manufacturer) $($_.Product)".Trim() } | Sort-Object)
    $gpu = @(Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name.Trim() } | Sort-Object -Unique)
    $storageIdentityHash = $null
    if (Test-Path -LiteralPath $StorageIdentityPath) {
        $storageIdentityHash = (Get-FileHash -LiteralPath $StorageIdentityPath -Algorithm SHA256).Hash
    }
    $contract = Get-ContractDigest
    return [ordered]@{
        contractVersion = 'V26'
        capturedAt = (Get-Date).ToString('o')
        evidenceLevel = 'PHYSICAL'
        windows = [ordered]@{
            caption = [string]$os.Caption
            version = [string]$os.Version
            buildNumber = [string]$os.BuildNumber
        }
        hardware = [ordered]@{
            manufacturer = [string]$computer.Manufacturer
            model = [string]$computer.Model
            totalPhysicalMemoryBytes = [long]$computer.TotalPhysicalMemory
            cpu = $cpu
            baseboard = $board
            gpu = $gpu
        }
        wsl = Get-WslSnapshot
        storageIdentityV25Sha256 = $storageIdentityHash
        contractDigestSha256 = $contract.sha256
        contractFiles = $contract.files
    }
}

function Get-ComparableFingerprint {
    param([Parameter(Mandatory)]$Fingerprint)
    return [ordered]@{
        contractVersion = [string]$Fingerprint.contractVersion
        windows = $Fingerprint.windows
        hardware = $Fingerprint.hardware
        wsl = $Fingerprint.wsl
        storageIdentityV25Sha256 = $Fingerprint.storageIdentityV25Sha256
        contractDigestSha256 = $Fingerprint.contractDigestSha256
        contractFiles = $Fingerprint.contractFiles
    }
}

New-Item -ItemType Directory -Force -Path $ReportRoot | Out-Null
$fingerprint = Get-WorkstationFingerprint
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportPath = Join-Path $ReportRoot "workstation-fingerprint-$timestamp.json"
$latestPath = Join-Path $ReportRoot 'latest.json'
$json = $fingerprint | ConvertTo-Json -Depth 10
$json | Set-Content -LiteralPath $reportPath -Encoding UTF8
$json | Set-Content -LiteralPath $latestPath -Encoding UTF8
$hash = Get-FileHash -LiteralPath $reportPath -Algorithm SHA256
"$($hash.Hash)  $([IO.Path]::GetFileName($reportPath))" | Set-Content -LiteralPath "$reportPath.sha256" -Encoding ASCII

Write-Host "[INFO] Empreinte V26: $reportPath" -ForegroundColor Cyan
Write-Host "[INFO] SHA-256: $($hash.Hash)" -ForegroundColor Cyan

switch ($Mode) {
    'Audit' {
        Write-Host 'VERDICT: WORKSTATION FINGERPRINT AUDITED' -ForegroundColor Green
        return
    }
    'Record' {
        if (-not $ConfirmHealthyState) {
            throw 'Record exige -ConfirmHealthyState après validation physique complète de la workstation.'
        }
        if (Test-Path -LiteralPath $LocalBaselinePath) {
            throw "Baseline V26 déjà présente: $LocalBaselinePath. Aucun remplacement silencieux n'est autorisé."
        }
        New-Item -ItemType Directory -Force -Path $LocalBaselineRoot | Out-Null
        $json | Set-Content -LiteralPath $LocalBaselinePath -Encoding UTF8
        Write-Host "[OK] Baseline V26 enregistrée: $LocalBaselinePath" -ForegroundColor Green
        Write-Host 'VERDICT: WORKSTATION FINGERPRINT RECORDED' -ForegroundColor Green
        return
    }
    'Verify' {
        if (-not (Test-Path -LiteralPath $LocalBaselinePath)) {
            throw "Baseline V26 absente: $LocalBaselinePath. Exécuter d'abord Audit puis Record sur un état sain."
        }
        $expected = Get-Content -Raw -LiteralPath $LocalBaselinePath | ConvertFrom-Json
        if ([string]$expected.contractVersion -ne 'V26') {
            throw "Version de baseline inattendue: $($expected.contractVersion)"
        }
        $expectedComparable = Get-ComparableFingerprint -Fingerprint $expected | ConvertTo-Json -Depth 10 -Compress
        $actualComparable = Get-ComparableFingerprint -Fingerprint $fingerprint | ConvertTo-Json -Depth 10 -Compress
        if ($expectedComparable -ne $actualComparable) {
            Write-Host '[ERROR] Dérive V26 détectée. Comparer la baseline locale et reports/workstation-v26/latest.json.' -ForegroundColor Red
            throw 'WORKSTATION FINGERPRINT DRIFT'
        }
        Write-Host '[OK] Aucune dérive V26 détectée.' -ForegroundColor Green
        Write-Host 'VERDICT: WORKSTATION FINGERPRINT READY' -ForegroundColor Green
    }
}
