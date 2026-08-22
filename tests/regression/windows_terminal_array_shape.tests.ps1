[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modulePath = Join-Path $repoRoot 'scripts\core\windows-terminal-settings.psm1'
$contractPath = Join-Path $repoRoot 'config\windows-terminal\settings.contract.json'

Import-Module $modulePath -Force

$expectedProfile = '{a3cc45a8-6e2f-4f3d-bca6-7d6df942da41}'
$legacyImport = 'windows11-pro-custom.actions.json'
$contract = Get-Content -Raw -LiteralPath $contractPath -Encoding UTF8 | ConvertFrom-Json

function Assert-ManagedArrays {
    param(
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)][string]$Context
    )

    foreach ($name in @('themes','schemes','newTabMenu','disabledProfileSources')) {
        $prop = $Settings.PSObject.Properties[$name]
        if ($null -eq $prop) { throw "$Context: propriété '$name' absente." }
        if ($prop.Value -isnot [System.Array]) {
            throw "$Context: '$name' doit être System.Array, type observé=$($prop.Value.GetType().FullName)."
        }
    }
}

function Assert-SerializedArrayShape {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Context
    )

    $shape = Get-WpcTerminalSettingsJsonShapeEvidence -Text $Text
    if (-not $shape.IsCompliant) {
        throw "$Context: forme JSON invalide: $($shape.Mismatches -join ', ')."
    }
    if ($Text -notmatch '"themes"\s*:\s*\[') {
        throw "$Context: le JSON doit contenir 'themes' sous forme de tableau."
    }
    if ($Text -match '"themes"\s*:\s*\{') {
        throw "$Context: la forme scalaire 'themes: { ... }' est interdite."
    }
}

# 1. Cas physique recherché: settings frais, aucun thème utilisateur, un seul thème géré.
$fresh = Set-WpcTerminalSettingsContract `
    -Settings $null `
    -ExpectedDefaultProfile $expectedProfile `
    -LegacyImportName $legacyImport `
    -Contract $contract

Assert-ManagedArrays -Settings $fresh -Context 'fresh-object'
$freshEvidence = Get-WpcTerminalSettingsEvidence `
    -Settings $fresh `
    -ExpectedDefaultProfile $expectedProfile `
    -LegacyImportName $legacyImport `
    -Contract $contract
if (-not $freshEvidence.IsCompliant) {
    throw "fresh-object: contrat non conforme: $($freshEvidence | ConvertTo-Json -Depth 20 -Compress)"
}

$freshText = ConvertTo-WpcTerminalSettingsText -Settings $fresh
Assert-SerializedArrayShape -Text $freshText -Context 'fresh-json'
$freshParsed = ConvertFrom-WpcTerminalSettingsText -Text $freshText
Assert-ManagedArrays -Settings $freshParsed -Context 'fresh-roundtrip'
if (@($freshParsed.themes).Count -ne 1) {
    throw "fresh-roundtrip: exactement un thème WPC est attendu, observé=$(@($freshParsed.themes).Count)."
}

# 2. Le validateur doit détecter les mauvais types même si le contenu reste plausible.
$malformed = ConvertFrom-WpcTerminalSettingsText -Text $freshText
$malformed.themes = $malformed.themes[0]
$malformed.schemes = $malformed.schemes[0]
$malformed.newTabMenu = $malformed.newTabMenu[0]
$malformed.disabledProfileSources = $malformed.disabledProfileSources[0]

$badEvidence = Get-WpcTerminalSettingsEvidence `
    -Settings $malformed `
    -ExpectedDefaultProfile $expectedProfile `
    -LegacyImportName $legacyImport `
    -Contract $contract
if ($badEvidence.IsCompliant) {
    throw 'Le validateur a accepté des propriétés Windows Terminal scalaires à la place de tableaux.'
}
foreach ($needle in @('themes:not-array-or-absent','schemes:not-array-or-absent','newTabMenu:not-array-or-absent','disabledProfileSources:not-array-or-absent')) {
    if ($badEvidence.ArrayShapeEvidence.Mismatches -notcontains $needle) {
        throw "Écart structurel non détecté: $needle"
    }
}

$rawMalformedText = (($malformed | ConvertTo-Json -Depth 100) + "`n")
$rawMalformedShape = Get-WpcTerminalSettingsJsonShapeEvidence -Text $rawMalformedText
if ($rawMalformedShape.IsCompliant) {
    throw 'Le contrôle JsonDocument a accepté des propriétés scalaires.'
}
if ($rawMalformedText -notmatch '"themes"\s*:\s*\{') {
    throw 'La fixture invalide ne reproduit pas réellement la forme themes: { ... }.'
}

$serializerRejected = $false
try {
    [void](ConvertTo-WpcTerminalSettingsText -Settings $malformed)
} catch {
    $serializerRejected = $true
}
if (-not $serializerRejected) {
    throw 'Le sérialiseur géré doit refuser un settings.json dont les propriétés de collection ne sont pas des tableaux.'
}

# 3. Apply doit pouvoir réparer cette forme sans reconstruire aveuglément tout le document.
$repaired = Set-WpcTerminalSettingsContract `
    -Settings $malformed `
    -ExpectedDefaultProfile $expectedProfile `
    -LegacyImportName $legacyImport `
    -Contract $contract
Assert-ManagedArrays -Settings $repaired -Context 'repaired-object'

$repairedText = ConvertTo-WpcTerminalSettingsText -Settings $repaired
Assert-SerializedArrayShape -Text $repairedText -Context 'repaired-json'
$repairedParsed = ConvertFrom-WpcTerminalSettingsText -Text $repairedText
Assert-ManagedArrays -Settings $repairedParsed -Context 'repaired-roundtrip'
$repairedEvidence = Get-WpcTerminalSettingsEvidence `
    -Settings $repairedParsed `
    -ExpectedDefaultProfile $expectedProfile `
    -LegacyImportName $legacyImport `
    -Contract $contract
if (-not $repairedEvidence.IsCompliant) {
    throw "repaired-roundtrip: contrat non conforme: $($repairedEvidence | ConvertTo-Json -Depth 20 -Compress)"
}

# 4. Une collection optionnelle à un élément doit elle aussi rester un tableau.
$singleImport = ConvertFrom-WpcTerminalSettingsText -Text $freshText
$singleImport | Add-Member -NotePropertyName 'import' -NotePropertyValue ([string[]]@('keep-user-import.json')) -Force
$singleImport = Set-WpcTerminalSettingsContract `
    -Settings $singleImport `
    -ExpectedDefaultProfile $expectedProfile `
    -LegacyImportName $legacyImport `
    -Contract $contract
$singleImportText = ConvertTo-WpcTerminalSettingsText -Settings $singleImport
$singleImportParsed = ConvertFrom-WpcTerminalSettingsText -Text $singleImportText
if ($singleImportParsed.import -isnot [System.Array]) {
    throw "single-import: import doit rester un tableau JSON, type=$($singleImportParsed.import.GetType().FullName)."
}
if (@($singleImportParsed.import).Count -ne 1 -or [string]$singleImportParsed.import[0] -ne 'keep-user-import.json') {
    throw 'single-import: la valeur utilisateur a été perdue ou modifiée.'
}

Write-Host '[OK] Windows Terminal array-shape regression contract validated.' -ForegroundColor Green
