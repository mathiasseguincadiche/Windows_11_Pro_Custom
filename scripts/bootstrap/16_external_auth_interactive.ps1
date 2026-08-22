[CmdletBinding()]
param(
    [ValidateSet('All','Git','GitHub','AWS')]
    [string]$Service = 'All',
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Distribution = 'Ubuntu',
    [ValidatePattern('^[a-z_][a-z0-9_-]{0,31}$')]
    [string]$LinuxUser = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$runtimeModule = Join-Path $repoRoot 'scripts\core\powershell-runtime.psm1'
$auditScript = Join-Path $PSScriptRoot '15_external_auth.ps1'
foreach ($required in @($runtimeModule,$auditScript)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Dépendance absente: $required" }
}
Import-Module $runtimeModule
[void](Assert-WpcPowerShellRuntime -MinimumVersion ([version]'7.6.4') -RequireWindows -PassThru)
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'wsl.exe introuvable.' }

function Write-Section {
    param([Parameter(Mandatory)][string]$Title)
    Write-Host ''
    Write-Host ('=' * 78) -ForegroundColor DarkCyan
    Write-Host (" AUTHENTIFICATION INTERACTIVE | {0}" -f $Title) -ForegroundColor Cyan
    Write-Host ('=' * 78) -ForegroundColor DarkCyan
    Write-Host ' Aucun secret n est capturé, journalisé ou stocké par Windows_11_Pro_Custom.' -ForegroundColor DarkGray
}

function Invoke-WslSimple {
    param([Parameter(Mandatory)][string[]]$ArgumentList,[switch]$IgnoreExitCode)
    $output = @(& wsl.exe --distribution $Distribution --user $LinuxUser --exec @ArgumentList 2>&1)
    $code = [int]$LASTEXITCODE
    $global:LASTEXITCODE = 0
    $text = (($output | ForEach-Object { ([string]$_) -replace "`0", '' }) -join "`n").Trim()
    if ($code -ne 0 -and -not $IgnoreExitCode) {
        throw "Commande WSL échouée (code=$code): $($ArgumentList -join ' ')"
    }
    return [pscustomobject]@{ ExitCode=$code; Output=$text }
}

function Read-YesNoLoop {
    param([Parameter(Mandatory)][string]$Prompt)
    while ($true) {
        $answer = (Read-Host "$Prompt [O/N]").Trim().ToLowerInvariant()
        if ($answer -in @('o','oui','y','yes')) { return $true }
        if ($answer -in @('n','non','no')) { return $false }
        Write-Host '[INFO] Réponse invalide. Entre O pour oui ou N pour non.' -ForegroundColor Yellow
    }
}

function Read-GitName {
    while ($true) {
        $value = (Read-Host 'Nom Git pour les commits').Trim()
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
        Write-Host '[INFO] Le nom Git ne peut pas être vide.' -ForegroundColor Yellow
    }
}

function Read-GitEmail {
    while ($true) {
        $value = (Read-Host 'E-mail Git pour les commits').Trim()
        if ($value -match '^[^\s@]+@[^\s@]+\.[^\s@]+$') { return $value }
        Write-Host '[INFO] Adresse e-mail Git invalide. Réessaie.' -ForegroundColor Yellow
    }
}

function Read-AwsProfileFromList {
    param([Parameter(Mandatory)][string[]]$Profiles,[Parameter(Mandatory)][string]$Prompt)
    while ($true) {
        $value = (Read-Host $Prompt).Trim()
        if ($value -in $Profiles) { return $value }
        Write-Host ("[INFO] Profil inconnu. Choisis parmi: {0}" -f ($Profiles -join ', ')) -ForegroundColor Yellow
    }
}

function Read-AwsProfileName {
    param([string]$Prompt = 'Nom personnalisé du profil AWS CLI')
    Write-Host ''
    Write-Host 'PROFIL AWS CLI LOCAL' -ForegroundColor Cyan
    Write-Host 'Le profil est seulement un alias local pour réutiliser une connexion AWS.' -ForegroundColor DarkGray
    Write-Host 'Ce n est PAS le nom d un projet AWS, d un compte AWS, d un service ou d une ressource cloud.' -ForegroundColor Yellow
    if (Read-YesNoLoop -Prompt 'Utiliser le profil local recommandé "default"') { return 'default' }
    while ($true) {
        $value = (Read-Host $Prompt).Trim()
        if ($value -match '^[A-Za-z0-9_.@+-]+$') { return $value }
        Write-Host '[INFO] Nom de profil AWS invalide. Caractères autorisés: lettres, chiffres, . _ @ + -' -ForegroundColor Yellow
    }
}

if ([string]::IsNullOrWhiteSpace($LinuxUser)) {
    $probe = @(& wsl.exe --distribution $Distribution --exec id -un 2>&1)
    $code = [int]$LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($code -ne 0) { throw "Impossible de déterminer l utilisateur WSL par défaut pour $Distribution." }
    $LinuxUser = (($probe | ForEach-Object { ([string]$_) -replace "`0", '' }) -join '').Trim()
}
if ($LinuxUser -eq 'root' -or $LinuxUser -notmatch '^[a-z_][a-z0-9_-]{0,31}$') {
    throw "Utilisateur WSL normal invalide: $LinuxUser"
}

function Invoke-WslTerminalInteractive {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string[]]$ArgumentList
    )
    $wt = Get-Command wt.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $wt) { throw 'Windows Terminal (wt.exe) est requis pour cette authentification interactive WSL.' }

    $wtArgs = @(
        'new-tab','--title',$Title,
        'wsl.exe','--distribution',$Distribution,'--user',$LinuxUser,'--exec'
    ) + $ArgumentList

    Write-Host ''
    Write-Host '[ACTION REQUISE] Un nouvel onglet Windows Terminal va s ouvrir.' -ForegroundColor Magenta
    Write-Host 'Termine entièrement la commande dans cet onglet. Les secrets restent dans ce terminal WSL dédié.' -ForegroundColor DarkGray
    & $wt.Source @wtArgs
    $launchCode = [int]$LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($launchCode -ne 0) { throw "Impossible d ouvrir l onglet Windows Terminal (code=$launchCode)." }
    [void](Read-Host 'Quand la commande dans le nouvel onglet est terminée, appuie sur Entrée ici')
}

function Invoke-WslInlineInteractive {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string[]]$ArgumentList
    )

    Write-Host ''
    Write-Host ("[ACTION REQUISE] {0}" -f $Label) -ForegroundColor Magenta
    Write-Host 'La commande interactive s exécute directement dans cette fenêtre PowerShell.' -ForegroundColor Cyan
    Write-Host 'stdin, stdout et stderr restent attachés au terminal courant et ne sont pas capturés par le script.' -ForegroundColor DarkGray

    & wsl.exe --distribution $Distribution --user $LinuxUser --exec @ArgumentList
    $code = [int]$LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($code -ne 0) {
        throw "Commande WSL interactive échouée (code=$code)."
    }
}

function Protect-GitHubConfigPermissions {
    [void](Invoke-WslSimple -ArgumentList @(
        'sh','-lc',
        'd="$HOME/.config/gh"; if [ -d "$d" ]; then chmod 700 "$d"; for f in "$d/hosts.yml" "$d/config.yml" "$d/.wpc-plaintext-accepted"; do [ ! -f "$f" ] || chmod 600 "$f"; done; fi'
    ) -IgnoreExitCode)
}

function Get-GitHubCredentialStorage {
    $plain = Invoke-WslSimple -ArgumentList @('sh','-lc','f="$HOME/.config/gh/hosts.yml"; [ -f "$f" ] && grep -Eq "^[[:space:]]*oauth_token:" "$f"') -IgnoreExitCode
    if ($plain.ExitCode -eq 0) { return 'PlaintextFile' }
    $environment = Invoke-WslSimple -ArgumentList @('sh','-lc','[ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]') -IgnoreExitCode
    if ($environment.ExitCode -eq 0) { return 'Environment' }
    $status = Invoke-WslSimple -ArgumentList @('gh','auth','status','--hostname','github.com') -IgnoreExitCode
    if ($status.ExitCode -eq 0) { return 'CredentialStore' }
    return 'None'
}

function Test-GitHubPlaintextAccepted {
    $probe = Invoke-WslSimple -ArgumentList @(
        'sh','-lc',
        'd="$HOME/.config/gh"; f="$d/hosts.yml"; m="$d/.wpc-plaintext-accepted"; [ -d "$d" ] && [ -f "$f" ] && [ -f "$m" ] && [ "$(stat -c %a "$d" 2>/dev/null)" = 700 ] && [ "$(stat -c %a "$f" 2>/dev/null)" = 600 ] && [ "$(stat -c %a "$m" 2>/dev/null)" = 600 ]'
    ) -IgnoreExitCode
    return ($probe.ExitCode -eq 0)
}

function Set-GitHubPlaintextAcceptance {
    param([Parameter(Mandatory)][bool]$Accepted)
    if ($Accepted) {
        [void](Invoke-WslSimple -ArgumentList @('sh','-lc','d="$HOME/.config/gh"; mkdir -p "$d"; chmod 700 "$d"; : > "$d/.wpc-plaintext-accepted"; chmod 600 "$d/.wpc-plaintext-accepted"'))
    } else {
        [void](Invoke-WslSimple -ArgumentList @('sh','-lc','rm -f "$HOME/.config/gh/.wpc-plaintext-accepted"') -IgnoreExitCode)
    }
}

function Resolve-GitHubPlaintextFallback {
    Protect-GitHubConfigPermissions
    Write-Host ''
    Write-Host '[SECURITE] GitHub CLI utilise hosts.yml car aucun credential store Linux exploitable n est disponible.' -ForegroundColor Yellow
    Write-Host 'Le dépôt impose ~/.config/gh=0700 et hosts.yml=0600, mais le token reste non chiffré.' -ForegroundColor Yellow
    if (Test-GitHubPlaintextAccepted) {
        Write-Host '[DEJA OK] Ce fallback protégé a déjà été explicitement accepté.' -ForegroundColor Green
        return 'PlaintextAccepted'
    }
    if (Read-YesNoLoop -Prompt 'Conserver temporairement cette session GitHub protégée en 0600') {
        Set-GitHubPlaintextAcceptance -Accepted $true
        Protect-GitHubConfigPermissions
        Write-Host '[AVERTISSEMENT] Fallback fichier 0600 explicitement accepté; un credential store chiffré reste préférable.' -ForegroundColor Yellow
        return 'PlaintextAccepted'
    }
    Set-GitHubPlaintextAcceptance -Accepted $false
    [void](Invoke-WslSimple -ArgumentList @('gh','auth','logout','--hostname','github.com') -IgnoreExitCode)
    Protect-GitHubConfigPermissions
    if ((Get-GitHubCredentialStorage) -eq 'PlaintextFile') { throw 'Le token GitHub reste présent après logout; arrêt fail-safe.' }
    Write-Host '[IGNORE] GitHub laissé non authentifié plutôt que de conserver un secret en clair sans consentement.' -ForegroundColor Yellow
    return 'LoggedOut'
}

function Configure-GitIdentity {
    Write-Section -Title 'Git — identité de commit'
    $nameProbe = Invoke-WslSimple -ArgumentList @('git','config','--global','--get','user.name') -IgnoreExitCode
    $emailProbe = Invoke-WslSimple -ArgumentList @('git','config','--global','--get','user.email') -IgnoreExitCode
    $name = if ($nameProbe.ExitCode -eq 0) { $nameProbe.Output } else { '' }
    $email = if ($emailProbe.ExitCode -eq 0) { $emailProbe.Output } else { '' }
    if ($name -and $email) {
        Write-Host '[DEJA OK] Une identité Git globale existe déjà.' -ForegroundColor Green
        if (-not (Read-YesNoLoop -Prompt 'Veux-tu la modifier')) { return }
    }
    $newName = Read-GitName
    $newEmail = Read-GitEmail
    [void](Invoke-WslSimple -ArgumentList @('git','config','--global','user.name',$newName))
    [void](Invoke-WslSimple -ArgumentList @('git','config','--global','user.email',$newEmail))
    Write-Host '[OK] Identité Git globale configurée.' -ForegroundColor Green
}

function Configure-GitHub {
    Write-Section -Title 'GitHub CLI'
    $status = Invoke-WslSimple -ArgumentList @('gh','auth','status','--hostname','github.com') -IgnoreExitCode
    if ($status.ExitCode -eq 0) {
        $storage = Get-GitHubCredentialStorage
        if ($storage -eq 'PlaintextFile') {
            $resolution = Resolve-GitHubPlaintextFallback
            if ($resolution -eq 'LoggedOut') { return }
            Write-Host '[DEJA OK] GitHub est déjà configuré.' -ForegroundColor Green
            Write-Host 'Compte/session : OK' -ForegroundColor Green
            Write-Host 'Stockage : fallback protégé 0600 déjà accepté' -ForegroundColor DarkGray
        } else {
            Set-GitHubPlaintextAcceptance -Accepted $false
            Write-Host '[DEJA OK] GitHub est déjà configuré.' -ForegroundColor Green
            Write-Host 'Compte/session : OK' -ForegroundColor Green
            switch ($storage) {
                'CredentialStore' { Write-Host 'Stockage : credential store' -ForegroundColor DarkGray }
                'Environment' { Write-Host 'Stockage : variables d environnement' -ForegroundColor DarkGray }
                default { Write-Host ("Stockage : {0}" -f $storage) -ForegroundColor DarkGray }
            }
        }

        if (-not (Read-YesNoLoop -Prompt 'Veux-tu modifier/refaire la connexion GitHub')) {
            Write-Host '[DEJA OK] Connexion GitHub conservée sans modification.' -ForegroundColor Green
            return
        }
    }

    Set-GitHubPlaintextAcceptance -Accepted $false
    Invoke-WslTerminalInteractive -Title 'GitHub CLI login' -ArgumentList @('gh','auth','login','--hostname','github.com','--web','--git-protocol','https')
    if ((Invoke-WslSimple -ArgumentList @('gh','auth','status','--hostname','github.com') -IgnoreExitCode).ExitCode -ne 0) {
        Write-Host '[ERREUR] GitHub CLI ne confirme pas la session. Relance cette option pour réessayer.' -ForegroundColor Red
        return
    }
    [void](Invoke-WslSimple -ArgumentList @('gh','auth','setup-git','--hostname','github.com'))
    if ((Get-GitHubCredentialStorage) -eq 'PlaintextFile') {
        $resolution = Resolve-GitHubPlaintextFallback
        if ($resolution -eq 'LoggedOut') { return }
    }
    Write-Host '[OK] GitHub configuré.' -ForegroundColor Green
}

function Get-AwsProfiles {
    $probe = Invoke-WslSimple -ArgumentList @('aws','configure','list-profiles') -IgnoreExitCode
    if ($probe.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($probe.Output)) { return @() }
    return @($probe.Output -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[A-Za-z0-9_.@+-]+$' } | Select-Object -Unique)
}

function Get-AwsConfigValue {
    param(
        [Parameter(Mandatory)][string]$Profile,
        [Parameter(Mandatory)][ValidateSet('region','login_session','sso_session','sso_start_url')][string]$Name
    )
    $probe = Invoke-WslSimple -ArgumentList @('aws','configure','get',$Name,'--profile',$Profile) -IgnoreExitCode
    if ($probe.ExitCode -ne 0) { return '' }
    return $probe.Output.Trim()
}

function Test-AwsProfile {
    param([Parameter(Mandatory)][string]$Profile)
    $probe = Invoke-WslSimple -ArgumentList @(
        'env','AWS_EC2_METADATA_DISABLED=true','AWS_PAGER=',
        'aws','sts','get-caller-identity','--profile',$Profile,'--output','json','--no-cli-pager',
        '--cli-connect-timeout','5','--cli-read-timeout','10'
    ) -IgnoreExitCode
    return ($probe.ExitCode -eq 0)
}

function Test-AwsLoginSupported {
    $probe = Invoke-WslSimple -ArgumentList @('aws','--version') -IgnoreExitCode
    if ($probe.ExitCode -ne 0 -or $probe.Output -notmatch 'aws-cli/(\d+\.\d+\.\d+)') { return $false }
    return ([version]$Matches[1] -ge [version]'2.32.0')
}

function Get-AwsProfileAuthMode {
    param([Parameter(Mandatory)][string]$Profile)
    if (-not [string]::IsNullOrWhiteSpace((Get-AwsConfigValue -Profile $Profile -Name 'login_session'))) { return 'Login' }
    $ssoSession = Get-AwsConfigValue -Profile $Profile -Name 'sso_session'
    $ssoStartUrl = Get-AwsConfigValue -Profile $Profile -Name 'sso_start_url'
    if (-not [string]::IsNullOrWhiteSpace($ssoSession) -or -not [string]::IsNullOrWhiteSpace($ssoStartUrl)) { return 'SSO' }
    return 'Other'
}

function Set-AwsCredentialPermissions {
    [void](Invoke-WslSimple -ArgumentList @(
        'sh','-lc',
        'if [ -d "$HOME/.aws" ]; then find "$HOME/.aws" -type d -exec chmod 700 {} +; find "$HOME/.aws" -type f -exec chmod 600 {} +; fi'
    ) -IgnoreExitCode)
}

function Test-AwsRegionName {
    param([AllowEmptyString()][string]$Region)
    return (-not [string]::IsNullOrWhiteSpace($Region) -and $Region -match '^[a-z]{2}(-gov)?-[a-z0-9-]+-\d+$')
}

function Resolve-AwsRegion {
    param([Parameter(Mandatory)][string]$Profile)
    $configured = Get-AwsConfigValue -Profile $Profile -Name 'region'
    if (Test-AwsRegionName -Region $configured) { return $configured }

    Write-Host '[INFO] Aucune région AWS valide n est encore définie pour ce profil.' -ForegroundColor Cyan
    Write-Host 'La valeur recommandée par défaut est us-east-1. Elle pourra être changée plus tard.' -ForegroundColor DarkGray
    if (Read-YesNoLoop -Prompt 'Utiliser us-east-1 pour ce profil') { return 'us-east-1' }
    while ($true) {
        $region = (Read-Host 'Région AWS (exemple: eu-west-3)').Trim()
        if (Test-AwsRegionName -Region $region) { return $region }
        Write-Host '[INFO] Région AWS invalide.' -ForegroundColor Yellow
    }
}

function Ensure-AwsWindowsBrowserBridge {
    $interop = Invoke-WslSimple -ArgumentList @('sh','-lc','command -v pwsh.exe >/dev/null 2>&1') -IgnoreExitCode
    if ($interop.ExitCode -ne 0) {
        throw 'Interop WSL vers Windows indisponible: pwsh.exe Windows est introuvable depuis Ubuntu.'
    }

    $bridgeProvision = @'
set -eu
install_dir="$HOME/.local/bin"
bridge="$install_dir/wpc-open-windows-browser"
mkdir -p "$install_dir"
umask 077
cat > "$bridge" <<'EOF'
#!/bin/sh
set -eu
if [ "$#" -ne 1 ]; then
    exit 64
fi
exec pwsh.exe -NoLogo -NoProfile -NonInteractive -CommandWithArgs 'Start-Process -FilePath $args[0] -ErrorAction Stop' "$1"
EOF
chmod 700 "$bridge"
printf '%s' "$bridge"
'@

    $probe = Invoke-WslSimple -ArgumentList @('sh','-lc',$bridgeProvision)
    $bridge = $probe.Output.Trim()
    if ([string]::IsNullOrWhiteSpace($bridge) -or $bridge -notmatch '^/.+/wpc-open-windows-browser$') {
        throw 'Impossible de déterminer le bridge navigateur Windows créé dans WSL.'
    }
    $executable = Invoke-WslSimple -ArgumentList @('test','-x',$bridge) -IgnoreExitCode
    if ($executable.ExitCode -ne 0) {
        throw "Bridge navigateur Windows non exécutable: $bridge"
    }
    return $bridge
}

function Invoke-AwsSameDeviceLoginInline {
    param([Parameter(Mandatory)][string]$Profile)
    if (-not (Test-AwsLoginSupported)) { throw 'aws login nécessite AWS CLI 2.32.0 minimum.' }
    $region = Resolve-AwsRegion -Profile $Profile
    if (-not (Test-AwsRegionName -Region $region)) { throw "Région AWS refusée avant lancement: '$region'." }
    $browserBridge = Ensure-AwsWindowsBrowserBridge

    Write-Host ''
    Write-Host '[INFO] AWS va utiliser le flux same-device recommandé.' -ForegroundColor Cyan
    Write-Host 'Le navigateur Windows doit s ouvrir automatiquement. Aucun code n est à copier/coller dans le terminal.' -ForegroundColor Green
    Write-Host 'Si le navigateur ne s ouvre pas, utilise simplement l URL affichée par AWS dans ce même navigateur Windows.' -ForegroundColor DarkGray

    Invoke-WslInlineInteractive -Label "AWS login | profil $Profile" -ArgumentList @(
        'env',"BROWSER=$browserBridge",'AWS_PAGER=','AWS_CLI_AUTO_PROMPT=off',
        'aws','login','--profile',$Profile,'--region',$region,'--no-cli-pager','--no-cli-auto-prompt'
    )
    Set-AwsCredentialPermissions
    return (Test-AwsProfile -Profile $Profile)
}

function Invoke-AwsSsoLoginInline {
    param([Parameter(Mandatory)][string]$Profile)
    Invoke-WslInlineInteractive -Label "AWS SSO login | profil $Profile" -ArgumentList @(
        'aws','sso','login','--profile',$Profile,'--no-browser','--use-device-code','--no-cli-pager'
    )
    Set-AwsCredentialPermissions
    return (Test-AwsProfile -Profile $Profile)
}

function Get-AwsOfferPrompt {
    param([int]$ExistingProfileCount = 0)
    $existing = if ($ExistingProfileCount -gt 0) { "AWS possède déjà $ExistingProfileCount profil(s)." } else { 'Aucun profil AWS n est encore configuré.' }
    return @"
$existing

Méthodes disponibles :
  1. Connexion AWS Console — RECOMMANDÉE pour un compte classique.
     aws login ouvre automatiquement le navigateur Windows et récupère le retour OAuth via localhost. Aucun code à coller.
  2. IAM Identity Center / SSO.
     La configuration et le device-code restent dans cette fenêtre.
  3. Reconnecter un profil existant.
  4. Access Key / Secret Key — legacy, uniquement si elles t ont été fournies explicitement.
  0. Ne rien configurer maintenant.

Veux-tu configurer AWS maintenant
"@
}

function Read-AwsMethodChoice {
    while ($true) {
        Write-Host ''
        Write-Host 'Choisis la méthode AWS :' -ForegroundColor Cyan
        Write-Host '  1. Connexion AWS Console (aws login + navigateur Windows automatique)'
        Write-Host '  2. IAM Identity Center / SSO'
        Write-Host '  3. Reconnecter un profil existant'
        Write-Host '  4. Access Key / Secret Key — legacy'
        Write-Host '  0. Retour / plus tard'
        $choice = (Read-Host 'Choix [0-4]').Trim()
        if ($choice -in @('0','1','2','3','4')) { return $choice }
        Write-Host '[INFO] Choix invalide.' -ForegroundColor Yellow
    }
}

function Configure-Aws {
    Write-Section -Title 'AWS CLI'
    $profiles = @(Get-AwsProfiles)
    $valid = @($profiles | Where-Object { Test-AwsProfile -Profile $_ })
    if ($valid.Count -gt 0) {
        Write-Host ("[DEJA OK] AWS possède {0} profil(s) valide(s): {1}" -f $valid.Count,($valid -join ', ')) -ForegroundColor Green
        if (-not (Read-YesNoLoop -Prompt 'Veux-tu gérer une autre connexion AWS')) { return }
    } elseif (-not (Read-YesNoLoop -Prompt (Get-AwsOfferPrompt -ExistingProfileCount $profiles.Count))) {
        Write-Host '[IGNORE] AWS non configuré pour le moment.' -ForegroundColor Yellow
        return
    }

    while ($true) {
        switch (Read-AwsMethodChoice) {
            '0' { Write-Host '[RETOUR] Configuration AWS quittée.' -ForegroundColor Yellow; return }
            '1' {
                $profile = Read-AwsProfileName
                if (Invoke-AwsSameDeviceLoginInline -Profile $profile) {
                    Write-Host "[OK] Profil AWS '$profile' connecté et vérifié avec STS." -ForegroundColor Green
                    return
                }
                Write-Host '[ERREUR] STS ne valide pas la connexion. Vérifie le résultat AWS affiché ci-dessus puis réessaie.' -ForegroundColor Red
                Write-Host '[INFO] Pour un utilisateur IAM, la politique SignInLocalDevelopmentAccess peut être requise. Un compte root n en a pas besoin.' -ForegroundColor Yellow
            }
            '2' {
                Invoke-WslInlineInteractive -Label 'AWS SSO configuration' -ArgumentList @('aws','configure','sso','--no-browser','--use-device-code')
                $profiles = @(Get-AwsProfiles)
                if ($profiles.Count -eq 0) { Write-Host '[ERREUR] Aucun profil SSO trouvé après configuration.' -ForegroundColor Red; continue }
                Write-Host ("Profils disponibles: {0}" -f ($profiles -join ', ')) -ForegroundColor DarkGray
                $profile = Read-AwsProfileFromList -Profiles $profiles -Prompt 'Profil SSO AWS à connecter'
                if (Invoke-AwsSsoLoginInline -Profile $profile) {
                    Write-Host "[OK] Profil SSO AWS '$profile' connecté et vérifié." -ForegroundColor Green
                    return
                }
                Write-Host '[ERREUR] La session SSO n est pas validée par STS.' -ForegroundColor Red
            }
            '3' {
                $profiles = @(Get-AwsProfiles)
                if ($profiles.Count -eq 0) { Write-Host '[INFO] Aucun profil AWS existant.' -ForegroundColor Yellow; continue }
                Write-Host ("Profils disponibles: {0}" -f ($profiles -join ', ')) -ForegroundColor DarkGray
                $profile = Read-AwsProfileFromList -Profiles $profiles -Prompt 'Profil AWS à reconnecter'
                $mode = Get-AwsProfileAuthMode -Profile $profile
                $ok = $false
                if ($mode -eq 'Login') { $ok = Invoke-AwsSameDeviceLoginInline -Profile $profile }
                elseif ($mode -eq 'SSO') { $ok = Invoke-AwsSsoLoginInline -Profile $profile }
                elseif (Test-AwsProfile -Profile $profile) { $ok = $true }
                else { Write-Host '[INFO] Ce profil n utilise ni login_session ni SSO. Utilise l option 4 seulement pour des clés IAM statiques.' -ForegroundColor Yellow; continue }
                if ($ok) { Write-Host "[OK] Session AWS '$profile' reconnectée et vérifiée." -ForegroundColor Green; return }
                Write-Host '[ERREUR] Reconnexion AWS non validée par STS.' -ForegroundColor Red
            }
            '4' {
                Write-Host '[AVERTISSEMENT] Mode legacy: la saisie des clés reste directement entre toi et AWS CLI dans cette fenêtre; le script ne capture pas les valeurs.' -ForegroundColor Yellow
                $profile = Read-AwsProfileName -Prompt 'Nom du profil AWS CLI pour les clés statiques'
                Invoke-WslInlineInteractive -Label "AWS configure | profil $profile" -ArgumentList @('aws','configure','--profile',$profile)
                Set-AwsCredentialPermissions
                if (Test-AwsProfile -Profile $profile) { Write-Host "[OK] Profil AWS '$profile' configuré et vérifié." -ForegroundColor Green; return }
                Write-Host '[ERREUR] Le profil est présent mais STS ne le valide pas.' -ForegroundColor Red
            }
        }
    }
}

$services = if ($Service -eq 'All') { @('Git','GitHub','AWS') } else { @($Service) }
foreach ($item in $services) {
    switch ($item) {
        'Git' { Configure-GitIdentity }
        'GitHub' { Configure-GitHub }
        'AWS' { Configure-Aws }
    }
}

Write-Host ''
Write-Host '[ANALYSE] Revalidation sans secret des connexions externes...' -ForegroundColor Cyan
& $auditScript -Mode Audit -Distribution $Distribution -LinuxUser $LinuxUser
if ($LASTEXITCODE -ne 0) { throw 'La revalidation des connexions externes a échoué.' }
Write-Host '[TERMINE] Assistant de connexions externes terminé.' -ForegroundColor Green
