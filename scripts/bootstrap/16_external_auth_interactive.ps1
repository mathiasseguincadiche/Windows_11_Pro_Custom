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
        ExitCode = $code
        Output   = (($output | ForEach-Object { ([string]$_) -replace "`0", '' }) -join "`n").Trim()
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
        'd="$HOME/.config/gh"; if [ -d "$d" ]; then chmod 700 "$d"; for f in "$d/hosts.yml" "$d/config.yml"; do [ ! -f "$f" ] || chmod 600 "$f"; done; fi'
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

function Resolve-GitHubPlaintextFallback {
    Protect-GitHubConfigPermissions
    Write-Host ''
    Write-Host '[SECURITE] GitHub CLI a utilisé son fallback hosts.yml car aucun credential store Linux utilisable n a été trouvé.' -ForegroundColor Yellow
    Write-Host 'Le fichier est immédiatement limité à 0600, mais il ne s agit PAS d un coffre chiffré.' -ForegroundColor Yellow
    if (Read-YesNoLoop -Prompt 'Conserver temporairement cette session GitHub protégée en 0600') {
        Write-Host '[AVERTISSEMENT] Session GitHub conservée explicitement en stockage fichier 0600.' -ForegroundColor Yellow
        return 'PlaintextAccepted'
    }

    Write-Host '[EN COURS] Suppression de la session GitHub persistée en clair...' -ForegroundColor Cyan
    if ((Invoke-WslInteractive -ArgumentList @('gh','auth','logout','--hostname','github.com')) -ne 0) {
        throw 'Impossible de supprimer proprement la session GitHub après refus du stockage fichier.'
    }
    Protect-GitHubConfigPermissions
    if ((Get-GitHubCredentialStorage) -eq 'PlaintextFile') {
        throw 'Le token GitHub est toujours détecté dans hosts.yml après logout; arrêt fail-safe.'
    }
    Write-Host '[IGNORE] GitHub CLI laissé non authentifié.' -ForegroundColor Yellow
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
    Write-Host '[OK] Git configuré.' -ForegroundColor Green
}

function Configure-GitHub {
    Write-Section -Title 'GitHub CLI'
    $status = Invoke-WslSimple -ArgumentList @('gh','auth','status','--hostname','github.com') -IgnoreExitCode
    $storage = Get-GitHubCredentialStorage

    if ($status.ExitCode -eq 0) {
        if ($storage -eq 'PlaintextFile') {
            Write-Host '[AVERTISSEMENT] GitHub CLI est authentifié, mais le token est actuellement persisté dans hosts.yml.' -ForegroundColor Yellow
            $resolution = Resolve-GitHubPlaintextFallback
            if ($resolution -eq 'LoggedOut') { return }
            Write-Host '[OK] GitHub authentifié; stockage fichier 0600 explicitement accepté.' -ForegroundColor Green
            return
        }
        Write-Host '[DEJA OK] GitHub CLI est authentifié.' -ForegroundColor Green
        if (-not (Read-YesNoLoop -Prompt 'Veux-tu refaire la connexion GitHub')) {
            Write-Host '[OK] GitHub configuré.' -ForegroundColor Green
            return
        }
    }

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
  1. Connexion AWS Console par navigateur — RECOMMANDÉE pour un compte classique.
     Utilise tes identifiants habituels de la console AWS avec "aws login".
  2. IAM Identity Center / SSO.
     Seulement si une organisation t a fourni un portail / une URL SSO.
  3. Reconnecter un profil existant.
     Le script détecte automatiquement un profil aws login ou SSO.
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

  1. CONNEXION AWS CONSOLE PAR NAVIGATEUR — RECOMMANDÉE
     Choisis cette option si tu te connectes normalement sur la console AWS avec :
       - le compte root créé avec ton compte AWS ;
       - un utilisateur IAM ;
       - ou une identité fédérée IAM.
     Ce que tu fais :
       - le script te propose le profil AWS CLI local "default" ;
       - ce profil est seulement un alias local, PAS le nom d un projet AWS ;
       - tu peux choisir un nom personnalisé si tu gères plusieurs comptes ou rôles ;
       - AWS CLI lance "aws login --profile <profil>" ;
       - ton navigateur s ouvre et tu te connectes avec tes identifiants AWS habituels.
     Ce que tu N AS PAS besoin de connaître :
       - aucun nom de projet AWS ;
       - aucune URL de portail SSO ;
       - aucune région SSO ;
       - aucune Secret Access Key statique.
     Sécurité : credentials temporaires, rafraîchis par AWS CLI, session jusqu à 12 h.
     Cache local : ~/.aws/login/cache, durci en 0700/0600 par ce script.

  2. IAM IDENTITY CENTER / SSO
     Choisis cette option uniquement si ton entreprise, école, client ou organisation utilise IAM Identity Center.
     Il te faut une URL de portail / Start URL (ou Issuer URL) et la région SSO fournies par l organisation.
     Le script lance "aws configure sso", puis "aws sso login --profile <profil>" et vérifie STS.

  3. RECONNECTER UN PROFIL EXISTANT
     Choisis cette option si ~/.aws/config contient déjà un profil mais que sa session a expiré.
     Le script détecte automatiquement :
       - login_session  -> "aws login --profile <profil>" ;
       - SSO            -> "aws sso login --profile <profil>".
     La configuration existante n est pas recréée inutilement.

  4. ACCESS KEY / SECRET KEY — LEGACY
     À utiliser seulement si AWS ou un administrateur t a explicitement fourni des clés IAM statiques.
     AWS CLI te demandera Access Key ID, Secret Access Key, région et format de sortie.
     Le dépôt ne lit ni ne journalise les valeurs. Stockage AWS CLI : ~/.aws/credentials.

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
                Write-Host ("[ACTION REQUISE] Ouverture de la connexion AWS Console pour le profil local '{0}'." -f $profile) -ForegroundColor Magenta
                Write-Host 'Le compte et l identité AWS réels seront choisis dans le navigateur puis vérifiés avec AWS STS.' -ForegroundColor DarkGray
                Write-Host 'Aucune URL SSO, clé statique ou nom de projet AWS n est demandé par ce flux.' -ForegroundColor DarkGray
                if ((Invoke-WslInteractive -ArgumentList @('aws','login','--profile',$profile)) -ne 0) { throw 'aws login a échoué ou a été interrompu.' }
                Set-AwsCredentialPermissions
                if (-not (Test-AwsProfile -Profile $profile)) { throw "La session AWS du profil '$profile' n est pas valide après aws login." }
                Write-Host "[OK] Profil AWS '$profile' connecté par credentials temporaires et vérifié avec STS." -ForegroundColor Green
                return
            }
            '2' {
                Write-Host '[ACTION REQUISE] Configuration IAM Identity Center / SSO.' -ForegroundColor Magenta
                Write-Host 'Continue uniquement si ton organisation t a fourni une Start URL/Issuer URL et une région SSO.' -ForegroundColor Yellow
                if ((Invoke-WslInteractive -ArgumentList @('aws','configure','sso')) -ne 0) { throw 'aws configure sso a échoué.' }
                $profiles = @(Get-AwsProfiles)
                if ($profiles.Count -eq 0) {
                    Write-Host '[INFO] Aucun profil AWS trouvé après la configuration SSO. Retour au menu AWS.' -ForegroundColor Yellow
                    continue
                }
                Write-Host ("Profils disponibles: {0}" -f ($profiles -join ', ')) -ForegroundColor DarkGray
                $profile = Read-AwsProfileFromList -Profiles $profiles -Prompt 'Profil SSO AWS à connecter'
                if ((Invoke-WslInteractive -ArgumentList @('aws','sso','login','--profile',$profile)) -ne 0) { throw 'aws sso login a échoué.' }
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
                        if ((Invoke-WslInteractive -ArgumentList @('aws','login','--profile',$profile)) -ne 0) { throw 'aws login a échoué.' }
                    }
                    'SSO' {
                        if ((Invoke-WslInteractive -ArgumentList @('aws','sso','login','--profile',$profile)) -ne 0) { throw 'aws sso login a échoué.' }
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
