[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Verify')]
    [string]$Mode = 'Audit',
    [string]$Distribution = 'Ubuntu',
    [string]$LinuxUser = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
Import-Module (Join-Path $repoRoot 'scripts\core\runtime.psm1')
$context = Get-WpcRunContextFromEnvironment -RepoRoot $repoRoot
$usernamePattern = '^[a-z_][a-z0-9_-]{0,31}$'

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'wsl.exe introuvable.' }
$installed = @((wsl.exe --list --quiet 2>$null) -replace "`0", '' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$global:LASTEXITCODE = 0
if ($installed -notcontains $Distribution) { throw "Distribution WSL absente: $Distribution" }

function Invoke-WslText {
    param(
        [Parameter(Mandatory)][string]$User,
        [Parameter(Mandatory)][string]$Command
    )
    $text = (& wsl.exe -d $Distribution -u $User -- sh -lc $Command 2>&1 | Out-String).Trim()
    $code = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($code -ne 0) { throw "Commande WSL échouée (user=$User): $Command`n$text" }
    return $text
}

function Get-DefaultLinuxUser {
    $value = (& wsl.exe -d $Distribution -- sh -lc 'id -un' 2>$null | Out-String).Trim()
    $code = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($code -ne 0) { return $null }
    return $value
}

function Test-LinuxUserExists {
    param([Parameter(Mandatory)][string]$Name)
    & wsl.exe -d $Distribution -u root -- sh -lc "getent passwd '$Name' >/dev/null" 2>$null
    $code = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    return ($code -eq 0)
}

function Test-LinuxUserSudo {
    param([Parameter(Mandatory)][string]$Name)
    if (-not (Test-LinuxUserExists -Name $Name)) { return $false }
    $groups = Invoke-WslText -User root -Command "id -nG '$Name'"
    return (@($groups -split '\s+') -contains 'sudo')
}

function Get-ConfiguredDefaultUser {
    try {
        $value = Invoke-WslText -User root -Command "awk 'BEGIN{inuser=0} /^\[user\]/{inuser=1;next} /^\[/{inuser=0} inuser && /^default=/{sub(/^default=/,\"\"); print; exit}' /etc/wsl.conf 2>/dev/null || true"
        if ([string]::IsNullOrWhiteSpace($value)) { return $null }
        return $value.Trim()
    } catch { return $null }
}

function Set-ConfiguredDefaultUser {
    param([Parameter(Mandatory)][string]$Name)
    $script = @'
set -eu
file=/etc/wsl.conf
tmp="$(mktemp)"
user='__USER__'
touch "$file"
awk -v user="$user" '
BEGIN { inuser=0; wrote=0 }
/^\[user\]$/ {
  if (!wrote) { print "[user]"; print "default=" user; wrote=1 }
  inuser=1
  next
}
/^\[/ { inuser=0 }
{ if (!inuser) print }
END {
  if (!wrote) { print ""; print "[user]"; print "default=" user }
}
' "$file" > "$tmp"
install -m 0644 "$tmp" "$file"
rm -f "$tmp"
'@
    $script = $script.Replace('__USER__', $Name)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
    [void](Invoke-WslText -User root -Command "printf '%s' '$encoded' | base64 -d | sh")
}

$defaultUser = Get-DefaultLinuxUser
$configuredUser = Get-ConfiguredDefaultUser
$targetUser = if (-not [string]::IsNullOrWhiteSpace($LinuxUser)) { $LinuxUser } elseif ($configuredUser) { $configuredUser } elseif ($defaultUser -and $defaultUser -ne 'root') { $defaultUser } else { '' }
$exists = if ($targetUser) { Test-LinuxUserExists -Name $targetUser } else { $false }
$sudo = if ($targetUser -and $exists) { Test-LinuxUserSudo -Name $targetUser } else { $false }
$compliant = $targetUser -and $exists -and $sudo -and ($defaultUser -eq $targetUser) -and ($configuredUser -eq $targetUser)

if ($Mode -eq 'Audit') {
    Write-Host "Utilisateur WSL par défaut observé: $(if ($defaultUser) { $defaultUser } else { '<indéterminé>' })"
    Write-Host "Utilisateur déclaré dans /etc/wsl.conf: $(if ($configuredUser) { $configuredUser } else { '<absent>' })"
    Write-Host "Utilisateur cible: $(if ($targetUser) { $targetUser } else { '<à fournir>' })"
    if ($compliant) {
        Write-Host "[DÉJÀ OK] Utilisateur WSL '$targetUser' présent, membre de sudo et réellement utilisé par défaut." -ForegroundColor Green
    } elseif (-not $targetUser) {
        Write-Host '[ACTION REQUISE] Aucun utilisateur Linux non-root nʼest encore défini. Apply te demandera un nom dʼutilisateur.' -ForegroundColor Magenta
    } else {
        Write-Host "[À FAIRE] Utilisateur WSL '$targetUser' incomplet: présent=$exists sudo=$sudo défaut=$defaultUser config=$configuredUser" -ForegroundColor Yellow
    }
    return
}

if ($Mode -eq 'Verify') {
    if (-not $targetUser) { throw 'Aucun utilisateur Linux cible nʼest connu. Fournis -WslUser à install.ps1 ou exécute le mode Apply interactif.' }
    if (-not $exists) { throw "Utilisateur Linux absent: $targetUser" }
    if (-not $sudo) { throw "Utilisateur Linux '$targetUser' nʼest pas membre du groupe sudo." }
    if ($configuredUser -ne $targetUser) { throw "/etc/wsl.conf ne définit pas '$targetUser' comme utilisateur par défaut." }
    if ($defaultUser -ne $targetUser) { throw "WSL démarre actuellement avec '$defaultUser', attendu '$targetUser'. Exécute wsl --terminate $Distribution puis relance." }
    Write-Host "[OK] Utilisateur WSL '$targetUser' vérifié: non-root, sudo, utilisateur par défaut." -ForegroundColor Green
    return
}

if (-not $targetUser) {
    $targetUser = Read-WpcRequiredValue -Context $context -Name 'WslUser' -CurrentValue $LinuxUser -Prompt 'Choisis le nom de ton utilisateur Linux WSL (minuscules, sans espace)' -Example 'mathias' -Pattern $usernamePattern
}
if ($targetUser -notmatch $usernamePattern) { throw "Nom utilisateur Linux invalide: '$targetUser'. Exemple valide: mathias" }

if (-not (Test-LinuxUserExists -Name $targetUser)) {
    if ($context.NonInteractive) {
        throw "Utilisateur WSL '$targetUser' absent. Sa création nécessite une saisie interactive sécurisée du mot de passe. Relance sans -NonInteractive ou crée-le manuellement puis relance."
    }
    Write-Host ''
    Write-Host "[ACTION REQUISE] Création de lʼutilisateur Linux '$targetUser'." -ForegroundColor Magenta
    Write-Host 'Linux va te demander un mot de passe deux fois. La saisie est masquée par adduser et nʼest jamais passée dans une variable, un argument ou un fichier log.' -ForegroundColor Yellow
    Write-Host 'Les champs complémentaires sont laissés vides automatiquement.' -ForegroundColor DarkGray
    & wsl.exe -d $Distribution -u root -- adduser --gecos '' $targetUser
    $addUserCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($addUserCode -ne 0) { throw "Création Linux de '$targetUser' échouée (code=$addUserCode)." }
    if (-not (Test-LinuxUserExists -Name $targetUser)) { throw "Lʼutilisateur '$targetUser' nʼest pas détecté après adduser." }
    Write-Host "[FAIT] Utilisateur Linux '$targetUser' créé et vérifié." -ForegroundColor Green
} else {
    Write-Host "[DÉJÀ OK] Utilisateur Linux '$targetUser' existe déjà." -ForegroundColor Green
}

if (-not (Test-LinuxUserSudo -Name $targetUser)) {
    [void](Invoke-WslText -User root -Command "usermod -aG sudo '$targetUser'")
    if (-not (Test-LinuxUserSudo -Name $targetUser)) { throw "Impossible dʼajouter '$targetUser' au groupe sudo." }
    Write-Host "[FAIT] '$targetUser' ajouté au groupe sudo." -ForegroundColor Green
} else {
    Write-Host "[DÉJÀ OK] '$targetUser' est déjà membre de sudo." -ForegroundColor Green
}

$configuredUser = Get-ConfiguredDefaultUser
if ($configuredUser -ne $targetUser) {
    Set-ConfiguredDefaultUser -Name $targetUser
    $configuredUser = Get-ConfiguredDefaultUser
    if ($configuredUser -ne $targetUser) { throw 'Échec de configuration de lʼutilisateur WSL par défaut.' }
    Write-Host "[FAIT] /etc/wsl.conf: default=$targetUser" -ForegroundColor Green
} else {
    Write-Host "[DÉJÀ OK] /etc/wsl.conf utilise déjà '$targetUser' par défaut." -ForegroundColor Green
}

Write-Host "[EN COURS] Redémarrage logique de $Distribution pour appliquer lʼutilisateur par défaut..." -ForegroundColor Cyan
& wsl.exe --terminate $Distribution
$terminateCode = $LASTEXITCODE
$global:LASTEXITCODE = 0
if ($terminateCode -ne 0) { throw "Impossible de terminer $Distribution (code=$terminateCode)." }
Start-Sleep -Milliseconds 500
$defaultUser = Get-DefaultLinuxUser
if ($defaultUser -ne $targetUser) { throw "Utilisateur WSL par défaut après redémarrage='$defaultUser', attendu='$targetUser'." }
Write-Host "[FAIT] Utilisateur WSL '$targetUser' prêt et réellement actif par défaut." -ForegroundColor Green
