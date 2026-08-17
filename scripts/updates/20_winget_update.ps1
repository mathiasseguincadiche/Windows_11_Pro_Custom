[CmdletBinding()]
param(
    [ValidateSet('Audit','Apply','Verify')]
    [string]$Mode = 'Audit',
    [switch]$IncludeUnknownPackages
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$nativeProcessModule = Join-Path $repoRoot 'scripts\core\native-process.psm1'
if (-not (Test-Path $nativeProcessModule)) { throw "Module d'exécution native introuvable: $nativeProcessModule" }
Import-Module $nativeProcessModule

$wingetCommand = Get-WpcNativeApplication -Name 'winget.exe'
if (-not $wingetCommand) { throw 'winget.exe est introuvable. Installe ou répare App Installer depuis Microsoft Store.' }

function Invoke-WinGetCapture {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $result = Invoke-WpcNativeCapture -FilePath $wingetCommand.Source -ArgumentList $Arguments
    return [pscustomobject]@{ Code=$result.ExitCode; Lines=@($result.Lines) }
}

function Get-TableRows {
    param([string[]]$Lines)
    $separator = -1
    for ($i=0; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match '^\s*-{3,}') { $separator = $i; break } }
    if ($separator -lt 0) { return @() }
    $rows = New-Object System.Collections.Generic.List[string]
    for ($i=$separator+1; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i].TrimEnd(); if ([string]::IsNullOrWhiteSpace($line)) { continue }; if ($line -match '^[\-\\|/\s]+$') { continue }; $rows.Add($line)
    }
    return $rows.ToArray()
}

function Get-UpgradeInventory {
    $args = @('list','--upgrade-available','--accept-source-agreements','--disable-interactivity')
    if ($IncludeUnknownPackages) { $args += '--include-unknown' }
    $result = Invoke-WinGetCapture -Arguments $args
    if ($result.Code -ne 0 -and $result.Code -ne -1978335212) { throw ("winget list --upgrade-available a échoué (code={0}): {1}" -f $result.Code, ($result.Lines -join ' | ')) }
    $rows = Get-TableRows -Lines $result.Lines
    return [pscustomobject]@{ Rows=$rows; Raw=$result.Lines }
}

function Write-Inventory {
    param([Parameter(Mandatory)]$Inventory)
    if ($Inventory.Rows.Count -eq 0) { Write-Host '[DÉJÀ OK] Aucune mise à jour WinGet détectée.' -ForegroundColor Green; return }
    Write-Host ("[À FAIRE] {0} application(s) ont une mise à jour WinGet disponible:" -f $Inventory.Rows.Count) -ForegroundColor Yellow
    foreach ($row in $Inventory.Rows) { Write-Host ("  {0}" -f $row) }
    Write-Host '[INFO] Les packages épinglés restent exclus: le gestionnaire nʼutilise ni --include-pinned ni --force.' -ForegroundColor DarkGray
}

$inventory = Get-UpgradeInventory
Write-Inventory -Inventory $inventory
if ($Mode -eq 'Audit') { return }
if ($Mode -eq 'Verify') { if ($inventory.Rows.Count -gt 0) { throw ("{0} mise(s) à jour WinGet restent disponibles." -f $inventory.Rows.Count) }; return }

Write-Host '[EN COURS] Actualisation des sources WinGet...' -ForegroundColor Cyan
$sourceResult = Invoke-WinGetCapture -Arguments @('source','update','--disable-interactivity')
$sourceResult.Lines | ForEach-Object { if ($_){ Write-Host ("  {0}" -f $_) } }
if ($sourceResult.Code -ne 0) { throw "winget source update a échoué (code=$($sourceResult.Code))." }
$inventory = Get-UpgradeInventory
if ($inventory.Rows.Count -eq 0) { Write-Host '[DÉJÀ OK] Applications WinGet déjà à jour après actualisation des sources.' -ForegroundColor Green; return }
$args = @('upgrade','--all','--silent','--accept-package-agreements','--accept-source-agreements','--disable-interactivity')
if ($IncludeUnknownPackages) { $args += '--include-unknown' }
Write-Host '[EN COURS] Mise à jour des applications WinGet non épinglées...' -ForegroundColor Cyan
$result = Invoke-WinGetCapture -Arguments $args
$result.Lines | ForEach-Object { if ($_){ Write-Host ("  {0}" -f $_) } }
if ($result.Code -ne 0) { throw ("winget upgrade --all a signalé un échec (code={0}). Les autres composants peuvent continuer via lʼorchestrateur, mais WinGet doit être revérifié." -f $result.Code) }
$remaining = Get-UpgradeInventory
if ($remaining.Rows.Count -gt 0) {
    Write-Host '[AVERTISSEMENT] Des mises à jour WinGet restent visibles. Elles peuvent être épinglées, bloquées ou nécessiter une action utilisateur.' -ForegroundColor Yellow
    foreach ($row in $remaining.Rows) { Write-Host ("  {0}" -f $row) }
    throw ("{0} mise(s) à jour WinGet restent disponibles après Apply." -f $remaining.Rows.Count)
}
Write-Host '[FAIT] Applications WinGet mises à jour et revalidées.' -ForegroundColor Green
