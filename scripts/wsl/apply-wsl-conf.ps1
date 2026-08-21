[CmdletBinding()]
param(
    [string]$Distribution = 'Ubuntu',
    [string]$LinuxUser = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$source = Join-Path $repoRoot 'config\wsl\wsl.conf'
$wslConfModule = Join-Path $repoRoot 'scripts\core\wsl-conf.psm1'

if (-not (Test-Path -LiteralPath $source)) { throw 'config/wsl/wsl.conf introuvable.' }
if (-not (Test-Path -LiteralPath $wslConfModule)) { throw "Module wsl.conf introuvable: $wslConfModule" }
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'wsl.exe introuvable.' }
Import-Module $wslConfModule -Force

function Invoke-WslRootNativeText {
    param(
        [Parameter(Mandatory)][string]$Command,
        [string[]]$Arguments = @()
    )

    $text = (& wsl.exe -d $Distribution -u root -- $Command @Arguments 2>&1 | Out-String).Trim()
    $code = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($code -ne 0) {
        throw "Commande WSL root échouée: $Command $(@($Arguments) -join ' ')`n$text"
    }
    return $text
}

function Get-WslConfLines {
    & wsl.exe -d $Distribution -u root -- test -f /etc/wsl.conf 1>$null 2>$null
    $existsCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($existsCode -ne 0) { return @() }

    $rawLines = @(& wsl.exe -d $Distribution -u root -- cat /etc/wsl.conf 2>&1)
    $code = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    $cleanLines = @($rawLines | ForEach-Object { ([string]$_) -replace "`0", '' })
    if ($code -ne 0) {
        throw "Impossible de lire /etc/wsl.conf dans $Distribution (code=$code): $($cleanLines -join ' | ')"
    }
    return $cleanLines
}

function Write-WslConfLines {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    $desiredText = ConvertTo-WpcWslConfText -Lines $Lines
    $tempPath = "/etc/.wpc-wsl.conf.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $desiredText | & wsl.exe -d $Distribution -u root -- tee $tempPath 1>$null
        $teeCode = $LASTEXITCODE
        $global:LASTEXITCODE = 0
        if ($teeCode -ne 0) { throw "Écriture temporaire de /etc/wsl.conf échouée (code=$teeCode)." }

        [void](Invoke-WslRootNativeText -Command 'chmod' -Arguments @('0644', $tempPath))
        [void](Invoke-WslRootNativeText -Command 'chown' -Arguments @('root:root', $tempPath))
        [void](Invoke-WslRootNativeText -Command 'mv' -Arguments @('-f', $tempPath, '/etc/wsl.conf'))
    } finally {
        & wsl.exe -d $Distribution -u root -- rm -f $tempPath 1>$null 2>$null
        $global:LASTEXITCODE = 0
    }

    $afterLines = @(Get-WslConfLines)
    $afterText = ConvertTo-WpcWslConfText -Lines $afterLines
    if ($afterText -ne $desiredText) { throw 'Le contenu /etc/wsl.conf ne correspond pas à la cible après écriture atomique.' }
}

$currentLines = @(Get-WslConfLines)
if ([string]::IsNullOrWhiteSpace($LinuxUser)) {
    $LinuxUser = Get-WpcWslConfDefaultUser -Lines $currentLines
}

$desiredLines = @(Get-Content -LiteralPath $source)
if (-not [string]::IsNullOrWhiteSpace($LinuxUser)) {
    if ($LinuxUser -notmatch '^[a-z_][a-z0-9_-]{0,31}$') { throw "Nom utilisateur Linux invalide: $LinuxUser" }
    $desiredLines = @(Set-WpcWslConfDefaultUser -Lines $desiredLines -User $LinuxUser)
}

$desiredText = ConvertTo-WpcWslConfText -Lines $desiredLines
$currentText = ConvertTo-WpcWslConfText -Lines $currentLines
if ($currentText -eq $desiredText) {
    Write-Host '[DÉJÀ OK] /etc/wsl.conf est déjà exactement conforme; aucune écriture ni arrêt WSL.' -ForegroundColor Green
    return
}

Write-Host '[EN COURS] Mise en conformité atomique de /etc/wsl.conf...' -ForegroundColor Cyan
Write-WslConfLines -Lines $desiredLines
$afterLines = @(Get-WslConfLines)
$afterText = ConvertTo-WpcWslConfText -Lines $afterLines
if ($afterText -ne $desiredText) { throw 'Le contenu /etc/wsl.conf ne correspond pas à la cible après relecture.' }
if (-not [string]::IsNullOrWhiteSpace($LinuxUser)) {
    $confirmedUser = Get-WpcWslConfDefaultUser -Lines $afterLines
    if ($confirmedUser -ne $LinuxUser) {
        throw "Utilisateur WSL par défaut non confirmé après écriture: observé='$confirmedUser' attendu='$LinuxUser'."
    }
}

& wsl.exe --terminate $Distribution
$terminateCode = $LASTEXITCODE
$global:LASTEXITCODE = 0
if ($terminateCode -ne 0) { throw "Impossible de terminer $Distribution après modification de wsl.conf." }
Write-Host '[FAIT] /etc/wsl.conf appliqué, relu et distribution terminée pour prise en compte.' -ForegroundColor Green
