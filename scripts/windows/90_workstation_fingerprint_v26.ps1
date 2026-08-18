[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Record', 'Verify')]
    [string]$Mode = 'Audit',

    [ValidateSet('AUTO', 'SIMULATED', 'PHYSICAL')]
    [string]$EvidenceLevel = 'AUTO',

    [switch]$ConfirmPhysicalEvidence,

    [switch]$ConfirmHealthyState,

    [switch]$ReplaceBaseline,

    [string]$ReplacementReason = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ReportRoot = Join-Path $RepoRoot 'reports\workstation-v26'
$LocalBaselineRoot = Join-Path $env:ProgramData 'Windows11ProCustom\workstation-v26'
$LocalBaselinePath = Join-Path $LocalBaselineRoot 'workstation-fingerprint.json'
$LocalBaselineHashPath = "$LocalBaselinePath.sha256"
$StorageIdentityPath = Join-Path $env:ProgramData 'Windows11ProCustom\storage-v25\volume-identity.json'

function Resolve-EvidenceLevel {
    $isGitHubRunner = [string]$env:GITHUB_ACTIONS -eq 'true'
    if ($isGitHubRunner) {
        if ($EvidenceLevel -eq 'PHYSICAL') {
            throw 'Un runner GitHub Actions ne peut jamais produire une preuve PHYSICAL.'
        }
        return 'SIMULATED'
    }
    if ($EvidenceLevel -eq 'AUTO') { return 'SIMULATED' }
    if ($EvidenceLevel -eq 'PHYSICAL' -and -not $ConfirmPhysicalEvidence) {
        throw 'Le niveau PHYSICAL exige -ConfirmPhysicalEvidence sur la workstation réelle.'
    }
    return $EvidenceLevel
}

function Get-WpcBaselineIntegrity {
    param(
        [Parameter(Mandatory)][string]$BaselinePath,
        [Parameter(Mandatory)][string]$HashPath
    )

    if (-not (Test-Path -LiteralPath $BaselinePath)) {
        throw "Baseline V26 absente: $BaselinePath"
    }
    $actual = (Get-FileHash -LiteralPath $BaselinePath -Algorithm SHA256).Hash.ToUpperInvariant()
    if (-not (Test-Path -LiteralPath $HashPath)) {
        return [pscustomobject]@{ Status = 'LEGACY_UNVERIFIED'; Sha256 = $actual }
    }

    $text = (Get-Content -Raw -LiteralPath $HashPath).Trim()
    if ($text -notmatch '^(?<hash>[A-Fa-f0-9]{64})\s{2}(?<file>[^\r\n]+)$') {
        throw "Sidecar SHA-256 de baseline invalide: $HashPath"
    }
    $expectedFileName = [IO.Path]::GetFileName($BaselinePath)
    if ($Matches.file -ne $expectedFileName) {
        throw "Le sidecar SHA-256 référence un fichier inattendu: $($Matches.file)"
    }
    $expected = $Matches.hash.ToUpperInvariant()
    if ($actual -ne $expected) {
        throw "Intégrité de baseline V26 invalide. attendu=$expected actuel=$actual"
    }
    return [pscustomobject]@{ Status = 'VERIFIED'; Sha256 = $actual }
}

function Write-WpcBaselineWithHash {
    param(
        [Parameter(Mandatory)][string]$Json,
        [Parameter(Mandatory)][string]$BaselinePath,
        [Parameter(Mandatory)][string]$HashPath
    )

    $parent = Split-Path -Parent $BaselinePath
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $token = [guid]::NewGuid().ToString('N')
    $temporaryBaseline = "$BaselinePath.$token.tmp"
    $temporaryHash = "$HashPath.$token.tmp"
    $baselineMoved = $false
    $hashMoved = $false
    try {
        $Json | Set-Content -LiteralPath $temporaryBaseline -Encoding UTF8
        $hash = (Get-FileHash -LiteralPath $temporaryBaseline -Algorithm SHA256).Hash.ToUpperInvariant()
        "$hash  $([IO.Path]::GetFileName($BaselinePath))" | Set-Content -LiteralPath $temporaryHash -Encoding ASCII
        Move-Item -LiteralPath $temporaryBaseline -Destination $BaselinePath -Force
        $baselineMoved = $true
        Move-Item -LiteralPath $temporaryHash -Destination $HashPath -Force
        $hashMoved = $true
        return $hash
    } catch {
        if ($baselineMoved -and -not $hashMoved) {
            Remove-Item -LiteralPath $BaselinePath -Force -ErrorAction SilentlyContinue
        }
        if ($hashMoved -and -not $baselineMoved) {
            Remove-Item -LiteralPath $HashPath -Force -ErrorAction SilentlyContinue
        }
        throw
    } finally {
        Remove-Item -LiteralPath $temporaryBaseline, $temporaryHash -Force -ErrorAction SilentlyContinue
    }
}

function Get-RepositoryRevision {
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($null -eq $git) { $git = Get-Command git -ErrorAction SilentlyContinue }
    if ($null -eq $git) { return $null }
    $revision = @(& $git.Source -C $RepoRoot rev-parse HEAD 2>$null)
    $exitCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($exitCode -ne 0 -or $revision.Count -eq 0) { return $null }
    $candidate = ([string]$revision[0]).Trim()
    if ($candidate -notmatch '^[a-fA-F0-9]{40}$') { return $null }
    return $candidate.ToLowerInvariant()
}

function ConvertTo-FlatFingerprintMap {
    param(
        $Value,
        [string]$Path = '$',
        [hashtable]$Map = @{}
    )
    if ($null -eq $Value) {
        $Map[$Path] = '<null>'
        return $Map
    }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in @($Value.Keys | Sort-Object)) {
            [void](ConvertTo-FlatFingerprintMap -Value $Value[$key] -Path "$Path.$key" -Map $Map)
        }
        return $Map
    }
    if ($Value -is [pscustomobject]) {
        foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) {
            [void](ConvertTo-FlatFingerprintMap -Value $property.Value -Path "$Path.$($property.Name)" -Map $Map)
        }
        return $Map
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $index = 0
        foreach ($item in @($Value)) {
            [void](ConvertTo-FlatFingerprintMap -Value $item -Path "$Path[$index]" -Map $Map)
            $index++
        }
        if ($index -eq 0) { $Map[$Path] = '<empty-array>' }
        return $Map
    }
    $Map[$Path] = [string]$Value
    return $Map
}

function Get-FingerprintDifferences {
    param([Parameter(Mandatory)]$Expected, [Parameter(Mandatory)]$Actual)
    $expectedMap = ConvertTo-FlatFingerprintMap -Value (Get-ComparableFingerprint -Fingerprint $Expected)
    $actualMap = ConvertTo-FlatFingerprintMap -Value (Get-ComparableFingerprint -Fingerprint $Actual)
    $paths = @($expectedMap.Keys + $actualMap.Keys | Sort-Object -Unique)
    $differences = New-Object System.Collections.Generic.List[object]
    foreach ($path in $paths) {
        $expectedValue = if ($expectedMap.ContainsKey($path)) { $expectedMap[$path] } else { '<absent>' }
        $actualValue = if ($actualMap.ContainsKey($path)) { $actualMap[$path] } else { '<absent>' }
        if ($expectedValue -ne $actualValue) {
            $differences.Add([ordered]@{ path = $path; expected = $expectedValue; actual = $actualValue })
        }
    }
    return $differences.ToArray()
}

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
    return [ordered]@{ sha256 = $digest; files = $entries.ToArray() }
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
        evidenceLevel = $script:ResolvedEvidenceLevel
        repositoryRevision = Get-RepositoryRevision
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
    $repositoryRevision = $null
    if ($Fingerprint -is [System.Collections.IDictionary]) {
        if ($Fingerprint.Contains('repositoryRevision')) { $repositoryRevision = $Fingerprint.repositoryRevision }
    } else {
        $revisionProperty = $Fingerprint.PSObject.Properties['repositoryRevision']
        if ($null -ne $revisionProperty) { $repositoryRevision = $revisionProperty.Value }
    }
    return [ordered]@{
        contractVersion = [string]$Fingerprint.contractVersion
        repositoryRevision = [string]$repositoryRevision
        windows = $Fingerprint.windows
        hardware = $Fingerprint.hardware
        wsl = $Fingerprint.wsl
        storageIdentityV25Sha256 = $Fingerprint.storageIdentityV25Sha256
        contractDigestSha256 = $Fingerprint.contractDigestSha256
        contractFiles = $Fingerprint.contractFiles
    }
}

$script:ResolvedEvidenceLevel = Resolve-EvidenceLevel
if ($Mode -in @('Record', 'Verify') -and $script:ResolvedEvidenceLevel -ne 'PHYSICAL') {
    throw "$Mode exige une preuve PHYSICAL. Ajoute -EvidenceLevel PHYSICAL -ConfirmPhysicalEvidence sur la workstation réelle."
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
        $baselinePresent = Test-Path -LiteralPath $LocalBaselinePath
        if ($baselinePresent -and -not $ReplaceBaseline) {
            throw "Baseline V26 déjà présente: $LocalBaselinePath. Aucun remplacement silencieux n'est autorisé."
        }
        if (-not $baselinePresent -and $ReplaceBaseline) {
            throw 'ReplaceBaseline a été demandé mais aucune baseline V26 existante nʼest présente.'
        }
        if ($ReplaceBaseline -and [string]::IsNullOrWhiteSpace($ReplacementReason)) {
            throw 'ReplaceBaseline exige -ReplacementReason afin de conserver la justification de maintenance.'
        }
        New-Item -ItemType Directory -Force -Path $LocalBaselineRoot | Out-Null
        if ($baselinePresent) {
            $previousIntegrity = Get-WpcBaselineIntegrity -BaselinePath $LocalBaselinePath -HashPath $LocalBaselineHashPath
            if ($previousIntegrity.Status -eq 'LEGACY_UNVERIFIED') {
                Write-Warning 'Baseline V26 antérieure sans sidecar SHA-256: elle sera archivée comme preuve historique non vérifiée.'
            }
            $previous = Get-Content -Raw -LiteralPath $LocalBaselinePath | ConvertFrom-Json
            $previousHash = $previousIntegrity.Sha256
            $historyRoot = Join-Path $LocalBaselineRoot 'history'
            New-Item -ItemType Directory -Force -Path $historyRoot | Out-Null
            $archivePath = Join-Path $historyRoot "workstation-fingerprint-$timestamp-$($previousHash.Substring(0, 12)).json"
            Copy-Item -LiteralPath $LocalBaselinePath -Destination $archivePath
            "$previousHash  $([IO.Path]::GetFileName($archivePath))" | Set-Content -LiteralPath "$archivePath.sha256" -Encoding ASCII
            $replacement = [ordered]@{
                contractVersion = 'V26'
                replacedAt = (Get-Date).ToString('o')
                reason = $ReplacementReason.Trim()
                previousBaselineSha256 = $previousHash
                previousBaselineIntegrity = $previousIntegrity.Status
                previousBaselineArchive = $archivePath
                differences = @(Get-FingerprintDifferences -Expected $previous -Actual $fingerprint)
            }
            $replacementPath = Join-Path $ReportRoot "baseline-replacement-$timestamp.json"
            $replacement | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $replacementPath -Encoding UTF8
            Copy-Item -LiteralPath $replacementPath -Destination (Join-Path $historyRoot ([IO.Path]::GetFileName($replacementPath)))
            Write-Host "[INFO] Ancienne baseline archivée: $archivePath" -ForegroundColor Cyan
            Write-Host "[INFO] Justification et diff: $replacementPath" -ForegroundColor Cyan
        }
        $baselineHash = Write-WpcBaselineWithHash -Json $json -BaselinePath $LocalBaselinePath -HashPath $LocalBaselineHashPath
        Write-Host "[OK] Baseline V26 enregistrée: $LocalBaselinePath" -ForegroundColor Green
        Write-Host "[OK] Intégrité baseline SHA-256: $baselineHash" -ForegroundColor Green
        Write-Host 'VERDICT: WORKSTATION FINGERPRINT RECORDED' -ForegroundColor Green
        return
    }
    'Verify' {
        if (-not (Test-Path -LiteralPath $LocalBaselinePath)) {
            throw "Baseline V26 absente: $LocalBaselinePath. Exécuter d'abord Audit puis Record sur un état sain."
        }
        $baselineIntegrity = Get-WpcBaselineIntegrity -BaselinePath $LocalBaselinePath -HashPath $LocalBaselineHashPath
        if ($baselineIntegrity.Status -eq 'LEGACY_UNVERIFIED') {
            Write-Warning 'Baseline V26 antérieure sans sidecar SHA-256: vérification compatible, mais remplacement contrôlé recommandé après requalification.'
        } else {
            Write-Host "[OK] Intégrité de la baseline V26 vérifiée: $($baselineIntegrity.Sha256)" -ForegroundColor Green
        }
        $expected = Get-Content -Raw -LiteralPath $LocalBaselinePath | ConvertFrom-Json
        if ([string]$expected.contractVersion -ne 'V26') {
            throw "Version de baseline inattendue: $($expected.contractVersion)"
        }
        $differences = @(Get-FingerprintDifferences -Expected $expected -Actual $fingerprint)
        if ($differences.Count -gt 0) {
            $driftPath = Join-Path $ReportRoot "workstation-drift-$timestamp.json"
            [ordered]@{
                contractVersion = 'V26'
                detectedAt = (Get-Date).ToString('o')
                baselinePath = $LocalBaselinePath
                actualReportPath = $reportPath
                differences = $differences
            } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $driftPath -Encoding UTF8
            Write-Host "[ERROR] Dérive V26 détectée: $($differences.Count) différence(s)." -ForegroundColor Red
            foreach ($difference in @($differences | Select-Object -First 50)) {
                Write-Host "  $($difference.path): attendu='$($difference.expected)' actuel='$($difference.actual)'" -ForegroundColor Red
            }
            Write-Host "[INFO] Rapport de dérive: $driftPath" -ForegroundColor Cyan
            throw 'WORKSTATION FINGERPRINT DRIFT'
        }
        Write-Host '[OK] Aucune dérive V26 détectée.' -ForegroundColor Green
        Write-Host 'VERDICT: WORKSTATION FINGERPRINT READY' -ForegroundColor Green
    }
}
