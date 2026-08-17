[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$BackupSessionPath,

    [ValidateSet('Verify', 'Sandbox')]
    [string]$Mode = 'Verify',

    [string]$ScratchRoot,

    [switch]$ConfirmIsolatedRestoreDrill
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SessionRoot = (Resolve-Path -LiteralPath $BackupSessionPath).Path
$ManifestPath = Join-Path $SessionRoot 'metadata\backup-manifest.json'
$StorageIdentityPath = Join-Path $SessionRoot 'metadata\storage-identity-v25.json'
$StorageIdentityHashPath = Join-Path $SessionRoot 'metadata\storage-identity-v25.sha256'
$WslDirectory = Join-Path $SessionRoot 'WSL'

function Get-ExpectedHashFromFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Fichier SHA-256 absent: $Path" }
    $text = (Get-Content -Raw -LiteralPath $Path).Trim()
    if ($text -notmatch '^([A-Fa-f0-9]{64})\s+') { throw "Format SHA-256 invalide: $Path" }
    return $Matches[1].ToUpperInvariant()
}

function Assert-Hash {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Expected)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Fichier requis absent: $Path" }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actual -ne $Expected.ToUpperInvariant()) {
        throw "SHA-256 invalide pour $Path. attendu=$Expected actuel=$actual"
    }
}

function Get-WbadminVersionIdentifiers {
    param([string[]]$Lines)
    $identifiers = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($Lines)) {
        $text = [string]$line
        if ($text -match '(?i)^\s*(?:Version identifier|Identificateur de version)\s*:\s*(?<id>.+?)\s*$') {
            $identifiers.Add($Matches.id.Trim())
            continue
        }
        if ($text -match '(?<id>\d{1,4}[/-]\d{1,2}[/-]\d{1,4}-\d{1,2}:\d{2})') {
            $identifiers.Add($Matches.id.Trim())
        }
    }
    return @($identifiers | Sort-Object -Unique)
}

foreach ($command in @('wsl.exe', 'wbadmin.exe')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Commande requise indisponible: $command"
    }
}

if (-not (Test-Path -LiteralPath $ManifestPath)) { throw "Manifest de backup absent: $ManifestPath" }
$Manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
if ([string]$Manifest.version -ne 'V7') { throw "Version de backup non supportée: $($Manifest.version)" }

$VhdxCandidates = @(Get-ChildItem -LiteralPath $WslDirectory -File -Filter '*.vhdx')
if ($VhdxCandidates.Count -ne 1) {
    throw "Le drill exige exactement un export WSL VHDX dans $WslDirectory. Détecté=$($VhdxCandidates.Count)"
}
$VhdxPath = $VhdxCandidates[0].FullName
$ExpectedWslHash = [string]$Manifest.wsl.sha256
if ([string]::IsNullOrWhiteSpace($ExpectedWslHash)) { throw 'SHA-256 WSL absent du manifest.' }
Assert-Hash -Path $VhdxPath -Expected $ExpectedWslHash

$ExpectedStorageHash = Get-ExpectedHashFromFile -Path $StorageIdentityHashPath
Assert-Hash -Path $StorageIdentityPath -Expected $ExpectedStorageHash
if ([string]$Manifest.storageIdentity.sha256 -ne $ExpectedStorageHash) {
    throw 'Le SHA-256 de la baseline V25 diverge entre backup-manifest.json et storage-identity-v25.sha256.'
}

$BackupTargetDrive = Split-Path -Qualifier $SessionRoot
if ([string]::IsNullOrWhiteSpace($BackupTargetDrive)) { throw "Impossible de déterminer le volume de backup depuis $SessionRoot" }
$VersionsOutput = @(& wbadmin.exe get versions "-backupTarget:$BackupTargetDrive" 2>&1)
$VersionsExitCode = $LASTEXITCODE
if ($VersionsExitCode -ne 0 -or $VersionsOutput.Count -eq 0) {
    throw "wbadmin ne peut pas énumérer de version récupérable sur $BackupTargetDrive. code=$VersionsExitCode"
}
$EnumeratedVersionIdentifiers = @(Get-WbadminVersionIdentifiers -Lines $VersionsOutput)
$WbadminIdentifierProperty = $Manifest.PSObject.Properties['wbadminVersionIdentifier']
$ExpectedWbadminVersionIdentifier = if ($null -eq $WbadminIdentifierProperty) { '' } else { [string]$WbadminIdentifierProperty.Value }
if (-not [string]::IsNullOrWhiteSpace($ExpectedWbadminVersionIdentifier)) {
    if ($EnumeratedVersionIdentifiers -notcontains $ExpectedWbadminVersionIdentifier) {
        throw "La version wbadmin liée au manifeste est introuvable sur $BackupTargetDrive. attendue=$ExpectedWbadminVersionIdentifier"
    }
    Write-Host "[OK] Version wbadmin du manifeste retrouvée: $ExpectedWbadminVersionIdentifier" -ForegroundColor Green
} else {
    Write-Warning 'Ancien manifeste sans wbadminVersionIdentifier: énumération validée, mais liaison exacte session/image non prouvée.'
}

Write-Host '[OK] Manifest Golden Backup conforme.' -ForegroundColor Green
Write-Host '[OK] SHA-256 du VHDX WSL valide.' -ForegroundColor Green
Write-Host '[OK] SHA-256 de la baseline V25 valide.' -ForegroundColor Green
Write-Host '[OK] wbadmin énumère au moins une version récupérable.' -ForegroundColor Green

if ($Mode -eq 'Verify') {
    Write-Host 'VERDICT: RESTORE DRILL VERIFY READY' -ForegroundColor Green
    return
}

if (-not $ConfirmIsolatedRestoreDrill) {
    throw 'Le mode Sandbox exige -ConfirmIsolatedRestoreDrill.'
}
if ([string]::IsNullOrWhiteSpace($ScratchRoot)) {
    throw "Le mode Sandbox exige -ScratchRoot sur un emplacement disposant de suffisamment d'espace libre."
}

$ScratchRootFull = [IO.Path]::GetFullPath($ScratchRoot)
New-Item -ItemType Directory -Force -Path $ScratchRootFull | Out-Null
$ScratchPathRoot = [IO.Path]::GetPathRoot($ScratchRootFull)
if ([string]::IsNullOrWhiteSpace($ScratchPathRoot)) {
    throw "Impossible de déterminer le volume du scratch depuis $ScratchRootFull"
}
try {
    $ScratchDrive = [IO.DriveInfo]::new($ScratchPathRoot)
    $RequiredScratchBytes = [long][math]::Ceiling(([long](Get-Item -LiteralPath $VhdxPath).Length * 1.10) + 1GB)
    if ($ScratchDrive.AvailableFreeSpace -lt $RequiredScratchBytes) {
        throw "Espace scratch insuffisant. requis=$([math]::Round($RequiredScratchBytes / 1GB, 2)) Go disponible=$([math]::Round($ScratchDrive.AvailableFreeSpace / 1GB, 2)) Go"
    }
    Write-Host "[OK] Capacité scratch validée: $([math]::Round($ScratchDrive.AvailableFreeSpace / 1GB, 2)) Go disponibles." -ForegroundColor Green
} catch {
    throw "Impossible de valider la capacité du scratch $ScratchPathRoot. $($_.Exception.Message)"
}
$DrillId = (Get-Date -Format 'yyyyMMddHHmmss') + '-' + ([guid]::NewGuid().ToString('N').Substring(0, 8))
$TemporaryDistribution = "W11PC-RestoreDrill-$DrillId"
if ($TemporaryDistribution -eq [string]$Manifest.wsl.distribution -or $TemporaryDistribution -eq 'Ubuntu') {
    throw 'Nom de distribution temporaire invalide: collision avec la distribution de production.'
}
$DrillRoot = Join-Path $ScratchRootFull $TemporaryDistribution
$CopiedVhdx = Join-Path $DrillRoot 'ext4.vhdx'
$Imported = $false
$DrillFailure = $null
$CleanupFailures = New-Object System.Collections.Generic.List[string]

try {
    New-Item -ItemType Directory -Force -Path $DrillRoot | Out-Null
    Write-Host "[INFO] Copie isolée du VHDX vers $CopiedVhdx" -ForegroundColor Cyan
    Copy-Item -LiteralPath $VhdxPath -Destination $CopiedVhdx -Force
    Assert-Hash -Path $CopiedVhdx -Expected $ExpectedWslHash

    $ExistingNames = @(& wsl.exe --list --quiet 2>$null | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
    if ($ExistingNames -contains $TemporaryDistribution) {
        throw "Collision inattendue avec une distribution existante: $TemporaryDistribution"
    }

    Write-Host "[INFO] Import WSL isolé: $TemporaryDistribution" -ForegroundColor Cyan
    & wsl.exe --import-in-place $TemporaryDistribution $CopiedVhdx
    if ($LASTEXITCODE -ne 0) { throw "wsl --import-in-place a échoué avec le code $LASTEXITCODE" }
    $Imported = $true

    $Probe = @(& wsl.exe -d $TemporaryDistribution -- bash -lc 'set -e; test -r /etc/os-release; . /etc/os-release; printf "ID=%s VERSION_ID=%s\n" "$ID" "$VERSION_ID"; findmnt -n -o FSTYPE /; test -d /home' 2>&1)
    $ProbeExit = $LASTEXITCODE
    if ($ProbeExit -ne 0) {
        throw "La distribution restaurée ne passe pas le probe Linux. code=$ProbeExit sortie=$($Probe -join ' | ')"
    }
    $ProbeText = $Probe -join ' | '
    if ($ProbeText -notmatch 'ID=ubuntu' -or $ProbeText -notmatch 'VERSION_ID=26\.04' -or $ProbeText -notmatch 'ext4') {
        throw "Le VHDX restauré ne correspond pas au contrat Ubuntu 26.04/ext4 attendu. sortie=$ProbeText"
    }

    Write-Host "[OK] VHDX restauré et amorcé sous $TemporaryDistribution." -ForegroundColor Green
    Write-Host '[OK] Ubuntu 26.04 et racine ext4 confirmés dans le sandbox.' -ForegroundColor Green
}
catch {
    $DrillFailure = $_
}
finally {
    if ($Imported) {
        Write-Host "[INFO] Désenregistrement de la distribution temporaire $TemporaryDistribution" -ForegroundColor Yellow
        & wsl.exe --terminate $TemporaryDistribution 2>$null
        $TerminateExitCode = $LASTEXITCODE
        if ($TerminateExitCode -ne 0) {
            Write-Warning "wsl --terminate a échoué pour la distribution temporaire. code=$TerminateExitCode"
        }
        & wsl.exe --unregister $TemporaryDistribution 2>$null
        $UnregisterExitCode = $LASTEXITCODE
        if ($UnregisterExitCode -ne 0) {
            $CleanupFailures.Add("wsl --unregister a échoué pour $TemporaryDistribution. code=$UnregisterExitCode")
        } else {
            $RemainingNames = @(& wsl.exe --list --quiet 2>$null | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
            $ListExitCode = $LASTEXITCODE
            if ($ListExitCode -ne 0) {
                $CleanupFailures.Add("Impossible de confirmer le désenregistrement de $TemporaryDistribution. code=$ListExitCode")
            } elseif ($RemainingNames -contains $TemporaryDistribution) {
                $CleanupFailures.Add("La distribution temporaire reste enregistrée après wsl --unregister: $TemporaryDistribution")
            } else {
                $Imported = $false
            }
        }
    }
    if (-not $Imported -and (Test-Path -LiteralPath $DrillRoot)) {
        try {
            Remove-Item -LiteralPath $DrillRoot -Recurse -Force
        } catch {
            $CleanupFailures.Add("Impossible de supprimer la copie scratch $DrillRoot. $($_.Exception.Message)")
        }
    } elseif ($Imported) {
        Write-Warning "Copie scratch conservée pour éviter de supprimer le VHDX d'une distribution encore enregistrée: $DrillRoot"
    }
}

if ($null -ne $DrillFailure) {
    if ($CleanupFailures.Count -gt 0) {
        throw "$($DrillFailure.Exception.Message) Échec(s) de nettoyage: $($CleanupFailures.ToArray() -join ' | ')"
    }
    throw $DrillFailure
}
if ($CleanupFailures.Count -gt 0) {
    throw "Le drill a réussi, mais son nettoyage isolé a échoué: $($CleanupFailures.ToArray() -join ' | ')"
}
Write-Host 'VERDICT: RESTORE DRILL SANDBOX READY' -ForegroundColor Green
