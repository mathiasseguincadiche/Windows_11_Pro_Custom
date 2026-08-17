[CmdletBinding()]
param(
    [ValidateSet('Audit','Apply','Verify')]
    [string]$Mode = 'Audit',
    [switch]$IncludeDrivers,
    [switch]$IncludeOptionalUpdates
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-BrowseOnly {
    param([Parameter(Mandatory)]$Update)
    try { return [bool]$Update.BrowseOnly } catch { return $false }
}

function Get-UpdateInventory {
    $session = New-Object -ComObject 'Microsoft.Update.Session'
    $session.ClientApplicationID = 'Windows_11_Pro_Custom'
    $searcher = $session.CreateUpdateSearcher()
    $result = $searcher.Search('IsInstalled=0 and IsHidden=0')
    $selected = New-Object System.Collections.Generic.List[object]
    $ignored = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $result.Updates.Count; $i++) {
        $update = $result.Updates.Item($i)
        $isDriver = $false
        try { $isDriver = ([int]$update.Type -eq 2) } catch { $isDriver = $false }
        $browseOnly = Get-BrowseOnly -Update $update

        $reason = ''
        $include = $true
        if ($isDriver -and -not $IncludeDrivers) { $include = $false; $reason = 'pilote exclu par défaut' }
        elseif (-not $isDriver -and $browseOnly -and -not $IncludeOptionalUpdates) { $include = $false; $reason = 'mise à jour facultative exclue par défaut' }

        $kb = ''
        try { if ($update.KBArticleIDs -and $update.KBArticleIDs.Count -gt 0) { $kb = 'KB' + (($update.KBArticleIDs | ForEach-Object { [string]$_ }) -join ',KB') } } catch {}
        $item = [pscustomobject]@{ Update=$update; Title=[string]$update.Title; KB=$kb; IsDriver=$isDriver; Optional=$browseOnly; Reason=$reason }
        if ($include) { $selected.Add($item) } else { $ignored.Add($item) }
    }
    return [pscustomobject]@{ Session=$session; Selected=$selected.ToArray(); Ignored=$ignored.ToArray() }
}

function Write-Inventory {
    param([Parameter(Mandatory)]$Inventory)
    foreach ($item in $Inventory.Selected) {
        $kind = if ($item.IsDriver) { 'DRIVER' } elseif ($item.Optional) { 'OPTIONNELLE' } else { 'STANDARD' }
        $prefix = if ($item.KB) { "$($item.KB) - " } else { '' }
        Write-Host ("[À FAIRE] [{0}] {1}{2}" -f $kind, $prefix, $item.Title) -ForegroundColor Yellow
    }
    foreach ($item in $Inventory.Ignored) {
        $prefix = if ($item.KB) { "$($item.KB) - " } else { '' }
        Write-Host ("[IGNORÉ] {0}{1} ({2})" -f $prefix, $item.Title, $item.Reason) -ForegroundColor DarkGray
    }
}

$inventory = Get-UpdateInventory
Write-Inventory -Inventory $inventory

if ($Mode -eq 'Audit') {
    if ($inventory.Selected.Count -eq 0) { Write-Host '[DÉJÀ OK] Aucune mise à jour Windows sélectionnée par la politique actuelle.' -ForegroundColor Green }
    else { Write-Host ("[À FAIRE] {0} mise(s) à jour Windows sélectionnée(s)." -f $inventory.Selected.Count) -ForegroundColor Yellow }
    if ($inventory.Ignored.Count -gt 0) { Write-Host ("[INFO] {0} mise(s) à jour ignorée(s) par la politique actuelle." -f $inventory.Ignored.Count) -ForegroundColor DarkGray }
    return
}

if ($Mode -eq 'Verify') {
    if ($inventory.Selected.Count -gt 0) { throw ("{0} mise(s) à jour Windows restent disponibles selon la politique actuelle." -f $inventory.Selected.Count) }
    Write-Host '[DÉJÀ OK] Windows Update ne présente plus de mise à jour sélectionnée.' -ForegroundColor Green
    return
}

if (-not (Test-IsAdministrator)) { throw 'Apply Windows Update nécessite PowerShell exécuté en administrateur.' }
if ($inventory.Selected.Count -eq 0) { Write-Host '[DÉJÀ OK] Windows Update: aucune installation nécessaire.' -ForegroundColor Green; return }

$collection = New-Object -ComObject 'Microsoft.Update.UpdateColl'
foreach ($item in $inventory.Selected) { if (-not $item.Update.EulaAccepted) { $item.Update.AcceptEula() }; [void]$collection.Add($item.Update) }
Write-Host ("[EN COURS] Téléchargement de {0} mise(s) à jour Windows..." -f $collection.Count) -ForegroundColor Cyan
$downloader = $inventory.Session.CreateUpdateDownloader(); $downloader.Updates = $collection; $downloadResult = $downloader.Download()
if ([int]$downloadResult.ResultCode -ge 4) { throw ("Téléchargement Windows Update en échec. ResultCode={0}" -f [int]$downloadResult.ResultCode) }

Write-Host '[EN COURS] Installation Windows Update...' -ForegroundColor Cyan
$installer = $inventory.Session.CreateUpdateInstaller(); $installer.Updates = $collection; $installResult = $installer.Install()
$failed = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $collection.Count; $i++) {
    $update = $collection.Item($i); $result = $installResult.GetUpdateResult($i); $code = [int]$result.ResultCode
    if ($code -in @(2,3)) { Write-Host ("[FAIT] {0}" -f $update.Title) -ForegroundColor Green }
    else { $failed.Add(("{0} (ResultCode={1}, HResult=0x{2:X8})" -f $update.Title, $code, ([uint32]$result.HResult))); Write-Host ("[ERREUR] {0} - ResultCode={1}" -f $update.Title, $code) -ForegroundColor Red }
}
if ($installResult.RebootRequired) { Write-Host '[ACTION REQUISE] Windows signale quʼun redémarrage est requis. Aucun redémarrage automatique ne sera lancé.' -ForegroundColor Magenta }
if ($failed.Count -gt 0) { throw ('Certaines mises à jour Windows ont échoué: ' + ($failed -join '; ')) }
$remaining = Get-UpdateInventory
if ($remaining.Selected.Count -gt 0) { throw ("Installation terminée mais {0} mise(s) à jour sélectionnée(s) restent détectées; relance le gestionnaire après le redémarrage si nécessaire." -f $remaining.Selected.Count) }
Write-Host '[FAIT] Windows Update installé et revalidé.' -ForegroundColor Green
