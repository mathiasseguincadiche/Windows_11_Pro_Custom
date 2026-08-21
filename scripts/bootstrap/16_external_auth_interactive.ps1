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
    return [pscustomobject]@{ ExitCode=$code; Output=(($output | ForEach-Object { ([string]$_) -replace "`0", '' }) -join "`n").Trim() }
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

function Read-NewAwsProfileName {
    while ($true) {
        $value = (Read-Host 'Nom du profil AWS à configurer (ex: devops)').Trim()
        if ($value -match '^[A-Za-z0-9_.@+-]+$') { return $value }
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
    Write-Host 'Sous Linux/WSL, GitHub CLI utilise Secret Service lorsqu il est disponible; sinon il peut retomber sur ce fichier.' -ForegroundColor DarkGray
    if (Read-YesNoLoop -Prompt 'Conserver temporairement cette session GitHub protégée en 0600') {
        Write-Host '[AVERTISSEMENT] Session GitHub conservée explicitement en stockage fichier 0600. Aucun secret n est copié dans le dépôt, les logs ou les rapports.' -ForegroundColor Yellow
        return 'PlaintextAccepted'
    }

    Write-Host '[EN COURS] Suppression de la session GitHub persistée en clair...' -ForegroundColor Cyan
    if ((Invoke-WslInteractive -ArgumentList @('gh','auth','logout','--hostname','github.com')) -ne 0) {
        throw 'Impossible de supprimer proprement la session GitHub après refus du stockage fichier.'
    }
    Protect-GitHubConfigPermissions
    $storageAfter = Get-GitHubCredentialStorage
    if ($storageAfter -eq 'PlaintextFile') {
        throw 'Le token GitHub est toujours détecté dans hosts.yml après logout; arrêt fail-safe.'
    }
    Write-Host '[IGNORE] GitHub CLI laissé non authentifié: aucun token persistant en clair n est accepté sans accord explicite.' -ForegroundColor Yellow
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

        if ($storage -eq 'CredentialStore') {
            Write-Host '[DEJA OK] GitHub CLI est authentifié et aucun token persistant n est présent dans hosts.yml.' -ForegroundColor Green
        } elseif ($storage -eq 'Environment') {
            Write-Host '[DEJA OK] GitHub CLI est authentifié via une variable d environnement externe au dépôt.' -ForegroundColor Green
        } else {
            Write-Host '[DEJA OK] GitHub CLI est authentifié.' -ForegroundColor Green
        }
        if (-not (Read-YesNoLoop -Prompt 'Veux-tu refaire la connexion GitHub')) {
            Write-Host '[OK] GitHub configuré.' -ForegroundColor Green
            return
        }
    }

    Write-Host '[ACTION REQUISE] GitHub va utiliser son flux officiel navigateur / device code.' -ForegroundColor Magenta
    Write-Host 'GitHub CLI essaiera son credential store système par défaut. Le script vérifiera ensuite qu il n a pas utilisé silencieusement hosts.yml.' -ForegroundColor DarkGray
    Write-Host 'Aucun token ne doit être collé dans Windows_11_Pro_Custom.' -ForegroundColor DarkGray
    if ((Invoke-WslInteractive -ArgumentList @('gh','auth','login','--hostname','github.com','--web','--git-protocol','https')) -ne 0) {
        throw 'Authentification GitHub interrompue ou échouée.'
    }
    if ((Invoke-WslInteractive -ArgumentList @('gh','auth','setup-git','--hostname','github.com')) -ne 0) {
        throw 'Configuration de Git pour utiliser GitHub CLI échouée.'
    }
    $verify = Invoke-WslSimple -ArgumentList @('gh','auth','status','--hostname','github.com') -IgnoreExitCode
    if ($verify.ExitCode -ne 0) { throw 'GitHub CLI ne confirme pas la session après authentification.' }

    $storage = Get-GitHubCredentialStorage
    if ($storage -eq 'PlaintextFile') {
        $resolution = Resolve-GitHubPlaintextFallback
        if ($resolution -eq 'LoggedOut') { return }
        Write-Host '[OK] GitHub authentifié; stockage fichier 0600 explicitement accepté.' -ForegroundColor Green
        return
    }

    if ($storage -eq 'CredentialStore') {
        Write-Host '[OK] GitHub CLI authentifié; aucun token persistant détecté dans hosts.yml.' -ForegroundColor Green
    } elseif ($storage -eq 'Environment') {
        Write-Host '[OK] GitHub CLI authentifié via une variable d environnement externe au dépôt.' -ForegroundColor Green
    } else {
        Write-Host '[OK] GitHub CLI authentifié et Git configuré pour github.com.' -ForegroundColor Green
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

function Set-AwsCredentialPermissions {
    [void](Invoke-WslSimple -ArgumentList @('sh','-lc','if [ -d "$HOME/.aws" ]; then chmod 700 "$HOME/.aws"; find "$HOME/.aws" -maxdepth 1 -type f -exec chmod 600 {} +; fi') -IgnoreExitCode)
}

function Get-AwsOfferPrompt {
    param([int]$ExistingProfileCount = 0)
    $existing = if ($ExistingProfileCount -gt 0) {
        "AWS possède déjà $ExistingProfileCount profil(s). Si ce sont des profils SSO dont la session a expiré, l option 2 est généralement la bonne."
    } else {
        'Aucun profil AWS n est encore configuré.'
    }

    return @"
$existing

Avant de décider, voici tes possibilités :
  1. IAM Identity Center / SSO — recommandé pour un utilisateur humain.
     Connexion via navigateur/device code, sans clé secrète statique à saisir dans ce script.
  2. Reconnecter un profil SSO existant.
     À utiliser si ~/.aws/config contient déjà ton profil et que la session a expiré.
  3. Access Key / Secret Key — legacy.
     À utiliser seulement si AWS ou un administrateur t a fourni des clés IAM statiques.
  0. Ne rien configurer maintenant.

Si tu n utilises pas encore AWS, tu peux répondre N sans rendre la workstation non conforme.
Veux-tu configurer AWS maintenant
"@
}

function Get-AwsMethodPrompt {
    return @"
Choisis la méthode AWS :

  1. IAM Identity Center / SSO — RECOMMANDÉ
     Quand la choisir :
       - compte AWS d entreprise, d école, de client ou d organisation utilisant IAM Identity Center / SSO ;
       - tu disposes généralement d une URL de portail SSO et d une région SSO.
     Ce que tu vas faire :
       - AWS CLI lance "aws configure sso" ;
       - tu renseignes la session SSO, l URL de démarrage et la région SSO ;
       - le navigateur ou un device code gère la connexion ;
       - tu sélectionnes le compte et le rôle autorisés ;
       - tu donnes un nom au profil AWS.
     Ce que le script fait ensuite :
       - lance "aws sso login --profile <profil>" ;
       - vérifie l identité avec "aws sts get-caller-identity".
     Stockage : configuration dans ~/.aws/config ; pas de Secret Access Key statique gérée par ce dépôt.

  2. Reconnecter un profil SSO existant
     Quand la choisir :
       - ton profil AWS existe déjà dans ~/.aws/config ;
       - la configuration est correcte mais la session SSO a expiré.
     Ce que tu vas faire :
       - choisir un profil dans la liste détectée.
     Ce que le script fait ensuite :
       - lance seulement "aws sso login --profile <profil>" ;
       - vérifie la session avec STS ;
       - ne recrée pas inutilement le profil.

  3. Access Key / Secret Key — LEGACY
     Quand la choisir :
       - uniquement si AWS ou un administrateur t a explicitement fourni des clés IAM statiques ;
       - à éviter pour un utilisateur humain lorsque SSO est disponible.
     Ce que tu vas faire dans AWS CLI :
       - saisir AWS Access Key ID ;
       - saisir AWS Secret Access Key ;
       - choisir la région par défaut et éventuellement le format de sortie.
     Ce que le script fait ensuite :
       - ne lit ni ne journalise la valeur des clés ;
       - protège ~/.aws en 0700 et ses fichiers en 0600 ;
       - vérifie le profil avec STS.
     Stockage : AWS CLI utilise ~/.aws/credentials pour les clés statiques.

  0. Retour / plus tard
     Aucun changement AWS. La workstation reste READY.

Choix [0-3]
"@
}

function Read-AwsMethodChoice {
    while ($true) {
        $choice = (Read-Host (Get-AwsMethodPrompt)).Trim()
        if ($choice -in @('0','1','2','3')) { return $choice }
        Write-Host '[INFO] Choix invalide. Entre 0, 1, 2 ou 3.' -ForegroundColor Yellow
    }
}

function Configure-Aws {
    Write-Section -Title 'AWS CLI'
    $profiles = @(Get-AwsProfiles)
    $valid = @($profiles | Where-Object { Test-AwsProfile -Profile $_ })

    if ($valid.Count -gt 0) {
        $validNames = ($valid -join ', ')
        $managePrompt = @"
AWS possède déjà $($valid.Count) profil(s) avec une session valide : $validNames

Tu peux :
  - répondre N pour ne rien changer ;
  - répondre O puis choisir 1 pour créer/configurer un autre SSO ;
  - répondre O puis choisir 2 pour reconnecter un profil SSO ;
  - répondre O puis choisir 3 seulement si tu dois utiliser des clés IAM statiques.
Veux-tu configurer ou reconnecter un profil AWS
"@
        if (-not (Read-YesNoLoop -Prompt $managePrompt)) {
            Write-Host '[OK] AWS déjà configuré.' -ForegroundColor Green
            return
        }
    } else {
        if (-not (Read-YesNoLoop -Prompt (Get-AwsOfferPrompt -ExistingProfileCount $profiles.Count))) {
            Write-Host '[IGNORE] AWS non configuré pour le moment.' -ForegroundColor Yellow
            return
        }
    }

    while ($true) {
        $choice = Read-AwsMethodChoice

        switch ($choice) {
            '0' {
                Write-Host '[RETOUR] Configuration AWS quittée sans erreur.' -ForegroundColor Yellow
                return
            }
            '1' {
                Write-Host '[ACTION REQUISE] AWS CLI va maintenant gérer directement la configuration SSO.' -ForegroundColor Magenta
                if ((Invoke-WslInteractive -ArgumentList @('aws','configure','sso')) -ne 0) { throw 'aws configure sso a échoué.' }
                $profiles = @(Get-AwsProfiles)
                if ($profiles.Count -eq 0) {
                    Write-Host '[INFO] Aucun profil AWS trouvé après la configuration SSO. Retour au menu AWS.' -ForegroundColor Yellow
                    continue
                }
                Write-Host ("Profils disponibles: {0}" -f ($profiles -join ', ')) -ForegroundColor DarkGray
                $profile = Read-AwsProfileFromList -Profiles $profiles -Prompt 'Profil AWS à connecter'
                if ((Invoke-WslInteractive -ArgumentList @('aws','sso','login','--profile',$profile)) -ne 0) { throw 'aws sso login a échoué.' }
                if (-not (Test-AwsProfile -Profile $profile)) { throw "La session AWS du profil '$profile' n est pas valide après connexion." }
                Write-Host "[OK] Profil AWS '$profile' connecté et vérifié." -ForegroundColor Green
                return
            }
            '2' {
                $profiles = @(Get-AwsProfiles)
                if ($profiles.Count -eq 0) {
                    Write-Host '[INFO] Aucun profil AWS existant à reconnecter. Retour au menu AWS.' -ForegroundColor Yellow
                    continue
                }
                Write-Host ("Profils disponibles: {0}" -f ($profiles -join ', ')) -ForegroundColor DarkGray
                $profile = Read-AwsProfileFromList -Profiles $profiles -Prompt 'Profil SSO à reconnecter'
                if ((Invoke-WslInteractive -ArgumentList @('aws','sso','login','--profile',$profile)) -ne 0) { throw 'aws sso login a échoué.' }
                if (-not (Test-AwsProfile -Profile $profile)) { throw "La session AWS du profil '$profile' reste invalide." }
                Write-Host "[OK] Session AWS '$profile' vérifiée." -ForegroundColor Green
                return
            }
            '3' {
                Write-Host '[AVERTISSEMENT] Le dépôt ne lit pas les clés. La saisie est entièrement gérée par AWS CLI.' -ForegroundColor Yellow
                $profile = Read-NewAwsProfileName
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