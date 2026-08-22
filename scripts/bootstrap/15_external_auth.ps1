[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Verify')]
    [string]$Mode = 'Audit',
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Distribution = 'Ubuntu',
    [ValidatePattern('^[a-z_][a-z0-9_-]{0,31}$')]
    [string]$LinuxUser = '',
    [switch]$RequireGitIdentity,
    [switch]$RequireGitHub,
    [switch]$RequireAws
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$reportDir = Join-Path $repoRoot 'reports\auth'
$reportPath = Join-Path $reportDir 'external-auth.json'

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'wsl.exe introuvable.' }

function Invoke-WslCapture {
    param(
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [switch]$IgnoreExitCode
    )

    $lines = @(& wsl.exe --distribution $Distribution --user $LinuxUser --exec @ArgumentList 2>&1)
    $code = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    $text = (($lines | ForEach-Object { ([string]$_) -replace "`0", '' }) -join "`n").Trim()
    if ($code -ne 0 -and -not $IgnoreExitCode) {
        throw "Commande WSL échouée (code=$code): $($ArgumentList -join ' ')"
    }
    return [pscustomobject]@{ ExitCode=[int]$code; Output=$text }
}

function Test-WslCommand {
    param([Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9._+-]+$')][string]$Name)
    $probe = Invoke-WslCapture -ArgumentList @('sh','-lc',"command -v -- '$Name' >/dev/null 2>&1") -IgnoreExitCode
    return ($probe.ExitCode -eq 0)
}

function Get-GitHubCredentialStorage {
    if (-not $ghInstalled) { return 'Unavailable' }

    $plain = Invoke-WslCapture -ArgumentList @(
        'sh','-lc',
        'f="$HOME/.config/gh/hosts.yml"; [ -f "$f" ] && grep -Eq "^[[:space:]]*oauth_token:" "$f"'
    ) -IgnoreExitCode
    if ($plain.ExitCode -eq 0) { return 'PlaintextFile' }

    $environment = Invoke-WslCapture -ArgumentList @(
        'sh','-lc',
        '[ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]'
    ) -IgnoreExitCode
    if ($environment.ExitCode -eq 0) { return 'Environment' }

    if ($githubAuthenticated) { return 'CredentialStore' }
    return 'None'
}

function Get-GitHubPlaintextState {
    $dirMode = (Invoke-WslCapture -ArgumentList @('sh','-lc','d="$HOME/.config/gh"; stat -c %a "$d" 2>/dev/null || true') -IgnoreExitCode).Output
    $hostsMode = (Invoke-WslCapture -ArgumentList @('sh','-lc','f="$HOME/.config/gh/hosts.yml"; stat -c %a "$f" 2>/dev/null || true') -IgnoreExitCode).Output
    $markerMode = (Invoke-WslCapture -ArgumentList @('sh','-lc','m="$HOME/.config/gh/.wpc-plaintext-accepted"; stat -c %a "$m" 2>/dev/null || true') -IgnoreExitCode).Output
    $markerProbe = Invoke-WslCapture -ArgumentList @('sh','-lc','test -f "$HOME/.config/gh/.wpc-plaintext-accepted"') -IgnoreExitCode
    $markerExists = ($markerProbe.ExitCode -eq 0)

    return [pscustomobject]@{
        DirectoryMode = [string]$dirMode
        HostsMode = [string]$hostsMode
        MarkerMode = [string]$markerMode
        AcceptanceMarker = $markerExists
        ProtectedPermissions = ([string]$dirMode -eq '700' -and [string]$hostsMode -eq '600')
        ExplicitlyAccepted = ($markerExists -and [string]$markerMode -eq '600')
    }
}

if ([string]::IsNullOrWhiteSpace($LinuxUser)) {
    $defaultUser = @(& wsl.exe --distribution $Distribution --exec id -un 2>&1)
    $defaultCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($defaultCode -ne 0) { throw "Impossible de déterminer l'utilisateur WSL par défaut pour $Distribution." }
    $LinuxUser = (($defaultUser | ForEach-Object { ([string]$_) -replace "`0", '' }) -join '').Trim()
}
if ($LinuxUser -eq 'root' -or $LinuxUser -notmatch '^[a-z_][a-z0-9_-]{0,31}$') {
    throw "Utilisateur WSL normal requis pour les connexions externes: '$LinuxUser'."
}

& wsl.exe --distribution $Distribution --user root --exec getent passwd $LinuxUser 1>$null 2>$null
$userCode = $LASTEXITCODE
$global:LASTEXITCODE = 0
if ($userCode -ne 0) { throw "Utilisateur WSL absent: $LinuxUser" }

$gitInstalled = Test-WslCommand -Name 'git'
$ghInstalled = Test-WslCommand -Name 'gh'
$awsInstalled = Test-WslCommand -Name 'aws'

$gitName = ''
$gitEmail = ''
if ($gitInstalled) {
    $nameProbe = Invoke-WslCapture -ArgumentList @('git','config','--global','--get','user.name') -IgnoreExitCode
    if ($nameProbe.ExitCode -eq 0) { $gitName = $nameProbe.Output }
    $emailProbe = Invoke-WslCapture -ArgumentList @('git','config','--global','--get','user.email') -IgnoreExitCode
    if ($emailProbe.ExitCode -eq 0) { $gitEmail = $emailProbe.Output }
}
$gitIdentityConfigured = (-not [string]::IsNullOrWhiteSpace($gitName) -and -not [string]::IsNullOrWhiteSpace($gitEmail))

$githubAuthenticated = $false
if ($ghInstalled) {
    $ghProbe = Invoke-WslCapture -ArgumentList @('gh','auth','status','--hostname','github.com') -IgnoreExitCode
    $githubAuthenticated = ($ghProbe.ExitCode -eq 0)
}
$githubCredentialStorage = Get-GitHubCredentialStorage
$githubPlaintextState = Get-GitHubPlaintextState
$githubPlaintextDetected = ($githubCredentialStorage -eq 'PlaintextFile')
$githubPlaintextProtected = ($githubPlaintextDetected -and $githubPlaintextState.ProtectedPermissions)
$githubPlaintextAccepted = ($githubPlaintextProtected -and $githubPlaintextState.ExplicitlyAccepted)
$githubSecureEnough = ($githubAuthenticated -and -not $githubPlaintextDetected)
$githubOperationallyAccepted = ($githubAuthenticated -and ($githubSecureEnough -or $githubPlaintextAccepted))

$awsProfiles = @()
$awsAuthenticatedProfiles = [System.Collections.Generic.List[string]]::new()
if ($awsInstalled) {
    $profilesProbe = Invoke-WslCapture -ArgumentList @('aws','configure','list-profiles') -IgnoreExitCode
    if ($profilesProbe.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($profilesProbe.Output)) {
        $awsProfiles = @($profilesProbe.Output -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[A-Za-z0-9_.@+-]+$' } | Select-Object -Unique)
    }
    foreach ($profile in $awsProfiles) {
        $identityProbe = Invoke-WslCapture -ArgumentList @(
            'env','AWS_EC2_METADATA_DISABLED=true','AWS_PAGER=',
            'aws','sts','get-caller-identity','--profile',$profile,'--output','json','--no-cli-pager',
            '--cli-connect-timeout','5','--cli-read-timeout','10'
        ) -IgnoreExitCode
        if ($identityProbe.ExitCode -eq 0) { $awsAuthenticatedProfiles.Add($profile) }
    }
}
$awsAnyAuthenticated = ($awsAuthenticatedProfiles.Count -gt 0)

$actions = [System.Collections.Generic.List[string]]::new()
if (-not $gitIdentityConfigured) { $actions.Add('Git identity') }
if (-not $githubAuthenticated) {
    $actions.Add('GitHub CLI')
} elseif ($githubPlaintextDetected -and -not $githubPlaintextProtected) {
    $actions.Add('GitHub credential permissions')
} elseif ($githubPlaintextDetected -and -not $githubPlaintextAccepted) {
    $actions.Add('GitHub credential storage consent')
}
if (-not $awsAnyAuthenticated) { $actions.Add('AWS') }

New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$report = [ordered]@{
    SchemaVersion = 3
    Timestamp = (Get-Date).ToString('o')
    Distribution = $Distribution
    LinuxUser = $LinuxUser
    Git = [ordered]@{
        Installed = $gitInstalled
        IdentityConfigured = $gitIdentityConfigured
        NameConfigured = -not [string]::IsNullOrWhiteSpace($gitName)
        EmailConfigured = -not [string]::IsNullOrWhiteSpace($gitEmail)
    }
    GitHub = [ordered]@{
        Installed = $ghInstalled
        Authenticated = $githubAuthenticated
        CredentialStorage = $githubCredentialStorage
        PlaintextCredentialDetected = $githubPlaintextDetected
        PlaintextPermissionsProtected = $githubPlaintextProtected
        PlaintextFallbackExplicitlyAccepted = $githubPlaintextAccepted
        OperationallyAccepted = $githubOperationallyAccepted
        SecureEnoughForRequiredVerify = $githubSecureEnough
    }
    Aws = [ordered]@{
        Installed = $awsInstalled
        Profiles = @($awsProfiles)
        AuthenticatedProfiles = $awsAuthenticatedProfiles.ToArray()
        AnyAuthenticated = $awsAnyAuthenticated
    }
    ActionRequired = $actions.ToArray()
    SecretMaterialRecorded = $false
}
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ''
Write-Host 'Connexions externes utilisateur' -ForegroundColor Cyan
if ($gitIdentityConfigured) { Write-Host '[DEJA OK] Identité Git globale configurée.' -ForegroundColor Green }
else { Write-Host '[ACTION REQUISE] Identité Git globale non configurée.' -ForegroundColor Yellow }

if (-not $githubAuthenticated) {
    Write-Host '[ACTION REQUISE] GitHub CLI non authentifié sur github.com.' -ForegroundColor Yellow
} elseif ($githubPlaintextDetected -and -not $githubPlaintextProtected) {
    Write-Host '[ACTION REQUISE] GitHub CLI utilise hosts.yml et ses permissions ne sont pas conformes au garde-fou 0700/0600.' -ForegroundColor Yellow
} elseif ($githubPlaintextDetected -and -not $githubPlaintextAccepted) {
    Write-Host '[ACTION REQUISE] GitHub CLI utilise un token non chiffré dans hosts.yml; permissions 0700/0600 appliquées mais fallback non accepté.' -ForegroundColor Yellow
} elseif ($githubPlaintextAccepted) {
    Write-Host '[AVERTISSEMENT] GitHub CLI utilise hosts.yml non chiffré, protégé en 0700/0600 et explicitement accepté. Un credential store système reste préférable.' -ForegroundColor Yellow
} elseif ($githubCredentialStorage -eq 'Environment') {
    Write-Host '[DEJA OK] GitHub CLI authentifié via une variable d environnement externe au dépôt.' -ForegroundColor Green
} elseif ($githubCredentialStorage -eq 'CredentialStore') {
    Write-Host '[DEJA OK] GitHub CLI authentifié via un credential store; aucun token persistant détecté dans hosts.yml.' -ForegroundColor Green
} else {
    Write-Host '[DEJA OK] GitHub CLI authentifié sur github.com.' -ForegroundColor Green
}

if ($awsAnyAuthenticated) {
    Write-Host ("[DEJA OK] AWS CLI possède {0} profil(s) authentifié(s)." -f $awsAuthenticatedProfiles.Count) -ForegroundColor Green
} elseif ($awsProfiles.Count -gt 0) {
    Write-Host ("[ACTION REQUISE] AWS CLI possède {0} profil(s), mais aucune session n'a été validée." -f $awsProfiles.Count) -ForegroundColor Yellow
} else {
    Write-Host '[ACTION REQUISE] Aucun profil AWS opérationnel détecté.' -ForegroundColor Yellow
}
Write-Host "[INFO] Rapport sans secret: $reportPath" -ForegroundColor DarkGray

$requiredFailures = [System.Collections.Generic.List[string]]::new()
if ($RequireGitIdentity -and -not $gitIdentityConfigured) { $requiredFailures.Add('Git identity') }
if ($RequireGitHub -and -not $githubSecureEnough) { $requiredFailures.Add('GitHub CLI secure storage') }
if ($RequireAws -and -not $awsAnyAuthenticated) { $requiredFailures.Add('AWS') }

if ($Mode -eq 'Verify' -and $requiredFailures.Count -gt 0) {
    throw "Connexions externes requises non conformes: $($requiredFailures -join ', ')."
}

if ($Mode -eq 'Verify' -and $requiredFailures.Count -eq 0) {
    Write-Host '[OK] Les connexions externes explicitement requises sont conformes.' -ForegroundColor Green
} else {
    Write-Host '[OK] Audit des connexions externes terminé; les services non connectés restent optionnels.' -ForegroundColor Green
}
