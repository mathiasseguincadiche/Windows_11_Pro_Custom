[CmdletBinding()]
param(
    [string]$Distribution = 'Ubuntu',
    [string]$LinuxUser = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$source = Join-Path $repoRoot 'config\wsl\wsl.conf'

if (-not (Test-Path $source)) { throw 'config/wsl/wsl.conf introuvable.' }
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'wsl.exe introuvable.' }

function Invoke-WslRootText {
    param([Parameter(Mandatory)][string]$Command)
    $text = (& wsl.exe --distribution $Distribution --user root -- sh -lc $Command 2>&1 | Out-String).Trim()
    $code = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($code -ne 0) { throw "Commande WSL root échouée: $Command`n$text" }
    return $text
}

if ([string]::IsNullOrWhiteSpace($LinuxUser)) {
    try {
        $LinuxUser = Invoke-WslRootText "awk 'BEGIN{inuser=0} /^\[user\]/{inuser=1;next} /^\[/{inuser=0} inuser && /^default=/{sub(/^default=/,\"\"); print; exit}' /etc/wsl.conf 2>/dev/null || true"
    } catch { $LinuxUser = '' }
}

$desired = Get-Content -Raw $source
if (-not [string]::IsNullOrWhiteSpace($LinuxUser)) {
    if ($LinuxUser -notmatch '^[a-z_][a-z0-9_-]{0,31}$') { throw "Nom utilisateur Linux invalide: $LinuxUser" }
    $desired = $desired.TrimEnd() + "`n`n[user]`ndefault=$LinuxUser`n"
}

$encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($desired))
$currentEncoded = Invoke-WslRootText "test -f /etc/wsl.conf && base64 -w0 /etc/wsl.conf || true"
if ($currentEncoded -eq $encoded) {
    Write-Host '[DÉJÀ OK] /etc/wsl.conf est déjà exactement conforme; aucune écriture ni arrêt WSL.' -ForegroundColor Green
    return
}

Write-Host '[EN COURS] Mise en conformité de /etc/wsl.conf...' -ForegroundColor Cyan
[void](Invoke-WslRootText "printf '%s' '$encoded' | base64 -d > /etc/wsl.conf && chmod 0644 /etc/wsl.conf")
$afterEncoded = Invoke-WslRootText "base64 -w0 /etc/wsl.conf"
if ($afterEncoded -ne $encoded) { throw 'Le contenu /etc/wsl.conf ne correspond pas à la cible après écriture.' }

& wsl.exe --terminate $Distribution
$terminateCode = $LASTEXITCODE
$global:LASTEXITCODE = 0
if ($terminateCode -ne 0) { throw "Impossible de terminer $Distribution après modification de wsl.conf." }
Write-Host '[FAIT] /etc/wsl.conf appliqué, revalidé et distribution redémarrable.' -ForegroundColor Green
