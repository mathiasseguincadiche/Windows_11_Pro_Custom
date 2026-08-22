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

$auditScript = Join-Path $PSScriptRoot '15_external_auth.ps1'
if (-not (Test-Path -LiteralPath $auditScript)) { throw "Audit des connexions absent: $auditScript" }
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'wsl.exe introuvable.' }

function Write-Section {
    param([Parameter(Mandatory)][string]$Title)
    Write-Host ''
    Write-Host ('=' * 78) -ForegroundColor DarkCyan
    Write-Host (" AUTHENTIFICATION INTERACTIVE | {0}" -f $Title) -ForegroundColor Cyan
    Write-Host ('=' * 78) -ForegroundColor DarkCyan
    Write-Host ' Aucun secret n est capturé, journalisé ou stocké par Windows_11_Pro_Custom.' -ForegroundColor DarkGray
    Write-Host ' L outil officiel prend directement le contrôle du terminal pour la saisie.' -ForegroundColor DarkGray
}

function Invoke-WslInteractive {
    param([Parameter(Mandatory)][string[]]$ArgumentList)
    & wsl.exe --distribution $Distribution --user $LinuxUser --exec @ArgumentList
    $code = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    return [int]$code
}

function Invoke-WslSimple {
    param([Parameter(Mandatory)][string[]]$ArgumentList,[switch]$IgnoreExitCode)
    $output = @(& wsl.exe --distribution $Distribution --user $LinuxUser --exec @ArgumentList 2>&1)
    $code = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($code -ne 0 -and -not $IgnoreExitCode) { throw "Commande WSL échouée (code=$code): $($ArgumentList -join ' ')" }
    return [pscustomobject]@{
        ExitCode = [int]$code
        Output = (($output | ForEach-Object { ([string]$_) -replace "`0", '' }) -join "`n").Trim()
    }
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
    Write-Host 'Le profil est seulement un alias enregistré sur cette machine pour réutiliser une connexion AWS.' -ForegroundColor DarkGray
    Write-Host 'Ce n est PAS le nom d un projet AWS, d un compte AWS, d un service ou d une ressource cloud.' -ForegroundColor Yellow
    Write-Host 'Le profil recommandé pour une configuration simple avec un seul compte est: default' -ForegroundColor DarkGray

    if (Read-YesNoLoop -Prompt 'Utiliser le profil local recommandé "default"') {
        Write-Host '[INFO] Profil AWS CLI local sélectionné: default.' -ForegroundColor Cyan
        return 'default'
    }

    while ($true) {
        $value = (Read-Host $Prompt).Trim()
        if ([string]::IsNullOrWhiteSpace($value)) {
            Write-Host '[INFO] Le nom personnalisé ne peut pas être vide. Réessaie ou utilise le profil default.' -ForegroundColor Yellow
            continue
        }
        if ($value -match '^[A-Za-z0-9_.@+-]+$') {
            Write-Host ("[INFO] Profil AWS CLI local sélectionné: {0}." -f $value) -ForegroundColor Cyan
            return $value
        }
        Write-Host '[INFO] Nom de profil AWS invalide. Caractères autorisés: lettres, chiffres, . _ @ + -' -ForegroundColor Yellow
    }
}

if ([string]::IsNullOrWhiteSpace($LinuxUser)) {
    $probe = @(& wsl.exe --distribution $Distribution --exec id -un 2>&1)
    $code = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($code -ne 0) { throw "Impossible de déterminer l utilisateur WSL par défaut pour $Distribution." }
    $LinuxUser = (($probe | ForEach-Object { ([string]$_) -replace "`0", '' }) -join '').Trim()
}
if ($LinuxUser -eq 'root' -or $LinuxUser -notmatch '^[a-z_][a-z0-9_-]{0,31}$') { throw "Utilisateur WSL normal invalide: $LinuxUser" }

function Protect-GitHubConfigPermissions {
    [void](Invoke-WslSimple -ArgumentList @(
        'sh','-lc',
        'd="$HOME/.config/gh"; if [ -d "$d" ]; then chmod 700 "$d"; for f in "$d/hosts.yml" "$d/config.yml" "$d/.wpc-plaintext-accepted"; do [ ! -f "$f" ] || chmod 600 "$f"; done; fi'
    ) -IgnoreExitCode)
}

function Get-GitHubCredentialStorage {
    $plain = Invoke-WslSimple -ArgumentList @(
        'sh','-lc',
        'f="$HOME/.config/gh/hosts.yml"; [ -f "$f" ] && grep -Eq "^[[:space:]]*oauth_token:" "$f"'
    ) -IgnoreExitCode
    if ($plain.ExitCode -eq 0) { return 'PlaintextFile' }

    $environment = Invoke-WslSimple -ArgumentList @(
        'sh','-lc',
        '[ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]'
    ) -IgnoreExitCode
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
        [void](Invoke-WslSimple -ArgumentList @(
            'sh','-lc',
            'd="$HOME/.config/gh"; mkdir -p "$d"; chmod 700 "$d"; : > "$d/.wpc-plaintext-accepted"; chmod 600 "$d/.wpc-plaintext-accepted"'
        ))
    } else {
        [void](Invoke-WslSimple -ArgumentList @('sh','-lc','rm -f "$HOME/.config/gh/.wpc-plaintext-accepted"') -IgnoreExitCode)
    }
}

function Resolve-GitHubPlaintextFallback {
    Protect-GitHubConfigPermissions
    Write-Host ''
    Write-Host '[SECURITE] GitHub CLI n a pas trouvé de credential store système utilisable et a utilisé hosts.yml.' -ForegroundColor Yellow
    Write-Host 'Le dépôt impose immédiatement ~/.config/gh=0700 et hosts.yml=0600, mais le token reste non chiffré.' -ForegroundColor Yellow
    Write-Host 'Windows_11_Pro_Custom ne lit jamais la valeur du token et ne la copie jamais ailleurs.' -ForegroundColor DarkGray

    if (Test-GitHubPlaintextAccepted) {
        Write-Host '[DEJA OK] Ce fallback protégé a déjà été explicitement accepté sur cette workstation.' -ForegroundColor Green
        return 'PlaintextAccepted'
    }

    if (Read-YesNoLoop -Prompt 'Conserver temporairement cette session GitHub protégée en 0600') {
        Set-GitHubPlaintextAcceptance -Accepted $true
        Protect-GitHubConfigPermissions
        Write-Host '[AVERTISSEMENT] Fallback fichier 0600 explicitement accepté; un credential store chiffré reste préférable.' -ForegroundColor Yellow
        return 'PlaintextAccepted'
    }

    Set-GitHubPlaintextAcceptance -Accepted $false
    Write-Host '[EN COURS] Suppression de la session GitHub persistée en clair...' -ForegroundColor Cyan
    if ((Invoke-WslInteractive -ArgumentList @('gh','auth','logout','--hostname','github.com')) -ne 0) {
        throw 'Impossible de supprimer proprement la session GitHub après refus du stockage fichier.'
    }
    Protect-GitHubConfigPermissions
    if ((Get-GitHubCredentialStorage) -eq 'PlaintextFile') {
        throw 'Le token GitHub est toujours détecté dans hosts.yml après logout; arrêt fail-safe.'
    }
    Write-Host '[IGNORE] GitHub CLI laissé non authentifié plutôt que de conserver un secret en clair sans consentement.' -ForegroundColor Yellow
    return 'LoggedOut'
}

function Configure-GitIdentity {
    Write-Section -Title 'Git — identité de commit'
    $name = (Invoke-WslSimple -ArgumentList @('git','config','--global','--get','user.name') -IgnoreExitCode).Output
    $email = (Invoke-WslSimple -ArgumentList @('git','config','--global','--get','user.email') -IgnoreExitCode).Output
    if ($name -and $email) {
        Write-Host '[DEJA OK] Une identité Git globale existe déjà.' -ForegroundColor Green
        if (-not (Read-YesNoLoop -Prompt 'Veux-tu la modifier')) {
            Write-Host '[OK] Git configuré.' -ForegroundColor Green
            return
        }
    }
    $newName = Read-GitName
    $newEmail = Read-GitEmail
    if ((Invoke-WslInteractive -ArgumentList @('git','config','--global','user.name',$newName)) -ne 0) { throw 'Configuration git user.name échouée.' }
    if ((Invoke-WslInteractive -ArgumentList @('git','config','--global','user.email',$newEmail)) -ne 0) { throw 'Configuration git user.email échouée.' }
    Write-Host '[OK] Identité Git globale configurée sous l utilisateur WSL.' -ForegroundColor Green
}

function Configure-GitHub {
    Write-Section -Title 'GitHub CLI'
    $status = Invoke-WslSimple -ArgumentList @('gh','auth','status','--hostname','github.com') -IgnoreExitCode
    $storage = Get-GitHubCredentialStorage

    if ($status.ExitCode -eq 0) {
        if ($storage -eq 'PlaintextFile') {
            $resolution = Resolve-GitHubPlaintextFallback
            if ($resolution -eq 'LoggedOut') { return }
            Write-Host '[OK] GitHub authentifié; fallback fichier explicitement accepté et permissions durcies.' -ForegroundColor Green
            return
        }
        Set-GitHubPlaintextAcceptance -Accepted $false
        Write-Host '[DEJA OK] GitHub CLI est authentifié via un stockage autre que hosts.yml en clair.' -ForegroundColor Green
        if (-not (Read-YesNoLoop -Prompt 'Veux-tu refaire la connexion GitHub')) {
            Write-Host '[OK] GitHub configuré.' -ForegroundColor Green
            return
        }
    }

    Set-GitHubPlaintextAcceptance -Accepted $false
    Write-Host '[ACTION REQUISE] GitHub va utiliser son flux officiel navigateur / device code.' -ForegroundColor Magenta
    if ((Invoke-WslInteractive -ArgumentList @('gh','auth','login','--hostname','github.com','--web','--git-protocol','https')) -ne 0) {
        throw 'Authentification GitHub interrompue ou échouée.'
    }
    if ((Invoke-WslInteractive -ArgumentList @('gh','auth','setup-git','--hostname','github.com')) -ne 0) {
        throw 'Configuration de Git pour utiliser GitHub CLI échouée.'
    }
    if ((Invoke-WslSimple -ArgumentList @('gh','auth','status','--hostname','github.com') -IgnoreExitCode).ExitCode -ne 0) {
        throw 'GitHub CLI ne confirme pas la session après authentification.'
    }

    if ((Get-GitHubCredentialStorage) -eq 'PlaintextFile') {
        $resolution = Resolve-GitHubPlaintextFallback
        if ($resolution -eq 'LoggedOut') { return }
    } else {
        Set-GitHubPlaintextAcceptance -Accepted $false
    }
    Write-Host '[OK] GitHub configuré.' -ForegroundColor Green
}

function Get-AwsProfiles {
    $probe = Invoke-WslSimple -ArgumentList @('aws','configure','list-profiles') -IgnoreExitCode
    if ($probe.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($probe.Output)) { return @() }
    return @($probe.Output -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[A-Za-z0-9_.@+-]+$' } | Select-Object -Unique)
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
    $loginSession = (Invoke-WslSimple -ArgumentList @('aws','configure','get','login_session','--profile',$Profile) -IgnoreExitCode).Output
    if (-not [string]::IsNullOrWhiteSpace($loginSession)) { return 'Login' }

    $ssoSession = (Invoke-WslSimple -ArgumentList @('aws','configure','get','sso_session','--profile',$Profile) -IgnoreExitCode).Output
    $ssoStartUrl = (Invoke-WslSimple -ArgumentList @('aws','configure','get','sso_start_url','--profile',$Profile) -IgnoreExitCode).Output
    if (-not [string]::IsNullOrWhiteSpace($ssoSession) -or -not [string]::IsNullOrWhiteSpace($ssoStartUrl)) { return 'SSO' }
    return 'Other'
}

function Set-AwsCredentialPermissions {
    [void](Invoke-WslSimple -ArgumentList @(
        'sh','-lc',
        'if [ -d "$HOME/.aws" ]; then find "$HOME/.aws" -type d -exec chmod 700 {} +; find "$HOME/.aws" -type f -exec chmod 600 {} +; fi'
    ) -IgnoreExitCode)
}

function Get-AwsOfferPrompt {
    param([int]$ExistingProfileCount = 0)
    $existing = if ($ExistingProfileCount -gt 0) { "AWS possède déjà $ExistingProfileCount profil(s)." } else { 'Aucun profil AWS n est encore configuré.' }
    return @"
$existing

Méthodes disponibles :
  1. Connexion AWS Console par navigateur Windows — RECOMMANDÉE pour un compte classique.
     WSL utilise "aws login --remote" : aucune tentative gio/xdg-open n est faite dans Ubuntu.
  2. IAM Identity Center / SSO.
     WSL utilise le device-code et n essaie pas d ouvrir un navigateur Linux.
  3. Reconnecter un profil existant.
     Le script détecte automatiquement un profil aws login ou SSO et réutilise le flux WSL-safe.
  4. Access Key / Secret Key — legacy.
     Seulement si AWS ou un administrateur t a explicitement fourni des clés IAM statiques.
  0. Ne rien configurer maintenant.

Si tu n utilises pas encore AWS, tu peux répondre N sans rendre la workstation non conforme.
Veux-tu configurer AWS maintenant
"@
}

function Get-AwsMethodPrompt {
    return @"
Choisis la méthode AWS :

  1. CONNEXION AWS CONSOLE PAR NAVIGATEUR WINDOWS — RECOMMANDÉE
     - profil local recommandé: default ;
     - commande WSL: aws login --remote --profile <profil> ;
     - AWS affiche une URL à ouvrir dans ton navigateur Windows ;
     - tu recopies ensuite le code d autorisation dans WSL ;
     - STS vérifie immédiatement la session.

  2. IAM IDENTITY CENTER / SSO
     - uniquement si ton organisation fournit une Start URL/Issuer URL et une région SSO ;
     - configuration et login utilisent --no-browser --use-device-code ;
     - aucun navigateur Linux n est requis.

  3. RECONNECTER UN PROFIL EXISTANT
     - login_session -> aws login --remote ;
     - SSO -> aws sso login --no-browser --use-device-code.

  4. ACCESS KEY / SECRET KEY — LEGACY
     - uniquement si des clés IAM statiques t ont été fournies explicitement ;
     - AWS CLI gère directement la saisie ; le dépôt ne lit ni ne journalise les valeurs.

  0. RETOUR / PLUS TARD
     Aucun changement AWS. La workstation reste READY.

Choix [0-4]
"@
}

function Read-AwsMethodChoice {
    while ($true) {
        $choice = (Read-Host (Get-AwsMethodPrompt)).Trim()
        if ($choice -in @('0','1','2','3','4')) { return $choice }
        Write-Host '[INFO] Choix invalide. Entre 0, 1, 2, 3 ou 4.' -ForegroundColor Yellow
    }
}

function Invoke-AwsRemoteLogin {
    param([Parameter(Mandatory)][string]$Profile)
    Write-Host "[ACTION REQUISE] Ouvre dans Windows l URL affichée par AWS puis recopie ici le code d autorisation." -ForegroundColor Magenta
    return (Invoke-WslInteractive -ArgumentList @('aws','login','--remote','--profile',$Profile))
}

function Invoke-AwsDeviceSsoLogin {
    param([Parameter(Mandatory)][string]$Profile)
    Write-Host '[ACTION REQUISE] Ouvre dans Windows l URL device-code affichée par AWS.' -ForegroundColor Magenta
    return (Invoke-WslInteractive -ArgumentList @('aws','sso','login','--profile',$Profile,'--no-browser','--use-device-code'))
}

function Configure-Aws {
    Write-Section -Title 'AWS CLI'
    $profiles = @(Get-AwsProfiles)
    $valid = @($profiles | Where-Object { Test-AwsProfile -Profile $_ })

    if ($valid.Count -gt 0) {
        Write-Host ("[DEJA OK] AWS possède {0} profil(s) avec une session valide: {1}" -f $valid.Count,($valid -join ', ')) -ForegroundColor Green
        if (-not (Read-YesNoLoop -Prompt 'Veux-tu gérer une autre connexion AWS')) {
            Write-Host '[OK] AWS déjà configuré.' -ForegroundColor Green
            return
        }
    } elseif (-not (Read-YesNoLoop -Prompt (Get-AwsOfferPrompt -ExistingProfileCount $profiles.Count))) {
        Write-Host '[IGNORE] AWS non configuré pour le moment.' -ForegroundColor Yellow
        return
    }

    while ($true) {
        $choice = Read-AwsMethodChoice
        switch ($choice) {
            '0' {
                Write-Host '[RETOUR] Configuration AWS quittée sans erreur.' -ForegroundColor Yellow
                return
            }
            '1' {
                if (-not (Test-AwsLoginSupported)) {
                    Write-Host '[ERREUR] aws login nécessite AWS CLI 2.32.0 minimum. Mets AWS CLI à jour ou choisis une autre méthode.' -ForegroundColor Red
                    continue
                }
                $profile = Read-AwsProfileName
                Write-Host ("[INFO] Profil AWS CLI local sélectionné: {0}." -f $profile) -ForegroundColor Cyan
                if ((Invoke-AwsRemoteLogin -Profile $profile) -ne 0) { throw 'aws login --remote a échoué ou a été interrompu.' }
                Set-AwsCredentialPermissions
                if (-not (Test-AwsProfile -Profile $profile)) { throw "La session AWS du profil '$profile' n est pas valide après aws login --remote." }
                Write-Host "[OK] Profil AWS '$profile' connecté par credentials temporaires et vérifié avec STS." -ForegroundColor Green
                return
            }
            '2' {
                Write-Host '[ACTION REQUISE] Configuration IAM Identity Center / SSO en device-code.' -ForegroundColor Magenta
                Write-Host 'Continue uniquement si ton organisation t a fourni une Start URL/Issuer URL et une région SSO.' -ForegroundColor Yellow
                if ((Invoke-WslInteractive -ArgumentList @('aws','configure','sso','--no-browser','--use-device-code')) -ne 0) { throw 'aws configure sso en device-code a échoué.' }
                $profiles = @(Get-AwsProfiles)
                if ($profiles.Count -eq 0) {
                    Write-Host '[INFO] Aucun profil AWS trouvé après la configuration SSO. Retour au menu AWS.' -ForegroundColor Yellow
                    continue
                }
                Write-Host ("Profils disponibles: {0}" -f ($profiles -join ', ')) -ForegroundColor DarkGray
                $profile = Read-AwsProfileFromList -Profiles $profiles -Prompt 'Profil SSO AWS à connecter'
                if ((Invoke-AwsDeviceSsoLogin -Profile $profile) -ne 0) { throw 'aws sso login en device-code a échoué.' }
                Set-AwsCredentialPermissions
                if (-not (Test-AwsProfile -Profile $profile)) { throw "La session SSO AWS du profil '$profile' n est pas valide." }
                Write-Host "[OK] Profil SSO AWS '$profile' connecté et vérifié." -ForegroundColor Green
                return
            }
            '3' {
                $profiles = @(Get-AwsProfiles)
                if ($profiles.Count -eq 0) {
                    Write-Host '[INFO] Aucun profil AWS existant à reconnecter. Retour au menu AWS.' -ForegroundColor Yellow
                    continue
                }
                Write-Host ("Profils disponibles: {0}" -f ($profiles -join ', ')) -ForegroundColor DarkGray
                $profile = Read-AwsProfileFromList -Profiles $profiles -Prompt 'Profil AWS à reconnecter'
                $mode = Get-AwsProfileAuthMode -Profile $profile
                switch ($mode) {
                    'Login' {
                        if (-not (Test-AwsLoginSupported)) { throw 'Ce profil utilise aws login mais AWS CLI est trop ancien.' }
                        if ((Invoke-AwsRemoteLogin -Profile $profile) -ne 0) { throw 'aws login --remote a échoué.' }
                    }
                    'SSO' {
                        if ((Invoke-AwsDeviceSsoLogin -Profile $profile) -ne 0) { throw 'aws sso login en device-code a échoué.' }
                    }
                    default {
                        if (Test-AwsProfile -Profile $profile) {
                            Write-Host "[DEJA OK] Profil AWS '$profile' déjà valide." -ForegroundColor Green
                            return
                        }
                        Write-Host "[INFO] Le profil '$profile' n utilise ni login_session ni SSO. Utilise l option 4 seulement s il repose sur des clés IAM statiques." -ForegroundColor Yellow
                        continue
                    }
                }
                Set-AwsCredentialPermissions
                if (-not (Test-AwsProfile -Profile $profile)) { throw "La session AWS du profil '$profile' reste invalide." }
                Write-Host "[OK] Session AWS '$profile' reconnectée et vérifiée." -ForegroundColor Green
                return
            }
            '4' {
                Write-Host '[AVERTISSEMENT] Mode legacy: AWS CLI gère directement la saisie des clés IAM statiques.' -ForegroundColor Yellow
                $profile = Read-AwsProfileName -Prompt 'Nom personnalisé du profil AWS CLI pour les clés statiques'
                if ((Invoke-WslInteractive -ArgumentList @('aws','configure','--profile',$profile)) -ne 0) { throw 'aws configure a échoué.' }
                Set-AwsCredentialPermissions
                if (-not (Test-AwsProfile -Profile $profile)) { throw "Le profil AWS '$profile' est configuré mais STS ne le valide pas." }
                Write-Host "[OK] Profil AWS '$profile' configuré et vérifié." -ForegroundColor Green
                return
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
