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

function Confirm-Choice {
    param([Parameter(Mandatory)][string]$Prompt)
    $answer = (Read-Host "$Prompt [O/N]").Trim().ToLowerInvariant()
    return ($answer -in @('o','oui','y','yes'))
}

if ([string]::IsNullOrWhiteSpace($LinuxUser)) {
    $probe = @(& wsl.exe --distribution $Distribution --exec id -un 2>&1)
    $code = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($code -ne 0) { throw "Impossible de déterminer l utilisateur WSL par défaut pour $Distribution." }
    $LinuxUser = (($probe | ForEach-Object { ([string]$_) -replace "`0", '' }) -join '').Trim()
}
if ($LinuxUser -eq 'root' -or $LinuxUser -notmatch '^[a-z_][a-z0-9_-]{0,31}$') { throw "Utilisateur WSL normal invalide: $LinuxUser" }

function Configure-GitIdentity {
    Write-Section -Title 'Git — identité de commit'
    $name = (Invoke-WslSimple -ArgumentList @('git','config','--global','--get','user.name') -IgnoreExitCode).Output
    $email = (Invoke-WslSimple -ArgumentList @('git','config','--global','--get','user.email') -IgnoreExitCode).Output
    if ($name -and $email) {
        Write-Host '[DEJA OK] Une identité Git globale existe déjà.' -ForegroundColor Green
        if (-not (Confirm-Choice -Prompt 'Veux-tu la modifier')) { return }
    }
    $newName = (Read-Host 'Nom Git pour les commits').Trim()
    if ([string]::IsNullOrWhiteSpace($newName)) { throw 'Nom Git obligatoire.' }
    $newEmail = (Read-Host 'E-mail Git pour les commits').Trim()
    if ($newEmail -notmatch '^[^\s@]+@[^\s@]+\.[^\s@]+$') { throw 'Adresse e-mail Git invalide.' }
    if ((Invoke-WslInteractive -ArgumentList @('git','config','--global','user.name',$newName)) -ne 0) { throw 'Configuration git user.name échouée.' }
    if ((Invoke-WslInteractive -ArgumentList @('git','config','--global','user.email',$newEmail)) -ne 0) { throw 'Configuration git user.email échouée.' }
    Write-Host '[OK] Identité Git globale configurée sous l utilisateur WSL.' -ForegroundColor Green
}

function Configure-GitHub {
    Write-Section -Title 'GitHub CLI'
    $status = Invoke-WslSimple -ArgumentList @('gh','auth','status','--hostname','github.com') -IgnoreExitCode
    if ($status.ExitCode -eq 0) {
        Write-Host '[DEJA OK] GitHub CLI est déjà authentifié sur github.com.' -ForegroundColor Green
        if (-not (Confirm-Choice -Prompt 'Veux-tu refaire la connexion GitHub')) { return }
    }
    Write-Host '[ACTION REQUISE] GitHub va utiliser son flux officiel navigateur / device code.' -ForegroundColor Magenta
    Write-Host 'Aucun token ne doit être collé dans Windows_11_Pro_Custom.' -ForegroundColor DarkGray
    if ((Invoke-WslInteractive -ArgumentList @('gh','auth','login','--hostname','github.com','--web','--git-protocol','https')) -ne 0) {
        throw 'Authentification GitHub interrompue ou échouée.'
    }
    if ((Invoke-WslInteractive -ArgumentList @('gh','auth','setup-git','--hostname','github.com')) -ne 0) {
        throw 'Configuration de Git pour utiliser GitHub CLI échouée.'
    }
    $verify = Invoke-WslSimple -ArgumentList @('gh','auth','status','--hostname','github.com') -IgnoreExitCode
    if ($verify.ExitCode -ne 0) { throw 'GitHub CLI ne confirme pas la session après authentification.' }
    Write-Host '[OK] GitHub CLI authentifié et Git configuré pour github.com.' -ForegroundColor Green
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

function Configure-Aws {
    Write-Section -Title 'AWS CLI'
    $profiles = @(Get-AwsProfiles)
    $valid = @($profiles | Where-Object { Test-AwsProfile -Profile $_ })
    if ($valid.Count -gt 0) {
        Write-Host ("[DEJA OK] AWS possède {0} profil(s) avec une session valide." -f $valid.Count) -ForegroundColor Green
        if (-not (Confirm-Choice -Prompt 'Veux-tu configurer ou reconnecter un profil AWS')) { return }
    }

    Write-Host ''
    Write-Host '  1. AWS IAM Identity Center / SSO (recommandé)' -ForegroundColor White
    Write-Host '  2. Reconnecter un profil SSO existant' -ForegroundColor White
    Write-Host '  3. Access Key / Secret Key via aws configure (legacy)' -ForegroundColor Yellow
    Write-Host '  0. Ignorer AWS pour le moment' -ForegroundColor DarkGray
    $choice = (Read-Host 'Ton choix').Trim()
    switch ($choice) {
        '0' { Write-Host '[IGNORE] AWS laissé non configuré.' -ForegroundColor Yellow; return }
        '1' {
            Write-Host '[ACTION REQUISE] AWS CLI va maintenant gérer directement la configuration SSO.' -ForegroundColor Magenta
            if ((Invoke-WslInteractive -ArgumentList @('aws','configure','sso')) -ne 0) { throw 'aws configure sso a échoué.' }
            $profiles = @(Get-AwsProfiles)
            if ($profiles.Count -eq 0) { throw 'Aucun profil AWS trouvé après aws configure sso.' }
            Write-Host ("Profils disponibles: {0}" -f ($profiles -join ', ')) -ForegroundColor DarkGray
            $profile = (Read-Host 'Profil AWS à connecter').Trim()
            if ($profile -notin $profiles) { throw "Profil AWS inconnu: $profile" }
            if ((Invoke-WslInteractive -ArgumentList @('aws','sso','login','--profile',$profile)) -ne 0) { throw 'aws sso login a échoué.' }
            if (-not (Test-AwsProfile -Profile $profile)) { throw "La session AWS du profil '$profile' n est pas valide après connexion." }
            Write-Host "[OK] Profil AWS '$profile' connecté et vérifié." -ForegroundColor Green
        }
        '2' {
            $profiles = @(Get-AwsProfiles)
            if ($profiles.Count -eq 0) { throw 'Aucun profil AWS existant à reconnecter.' }
            Write-Host ("Profils disponibles: {0}" -f ($profiles -join ', ')) -ForegroundColor DarkGray
            $profile = (Read-Host 'Profil SSO à reconnecter').Trim()
            if ($profile -notin $profiles) { throw "Profil AWS inconnu: $profile" }
            if ((Invoke-WslInteractive -ArgumentList @('aws','sso','login','--profile',$profile)) -ne 0) { throw 'aws sso login a échoué.' }
            if (-not (Test-AwsProfile -Profile $profile)) { throw "La session AWS du profil '$profile' reste invalide." }
            Write-Host "[OK] Session AWS '$profile' vérifiée." -ForegroundColor Green
        }
        '3' {
            Write-Host '[AVERTISSEMENT] Le dépôt ne lit pas les clés. La saisie est entièrement gérée par AWS CLI.' -ForegroundColor Yellow
            $profile = (Read-Host 'Nom du profil AWS à configurer (ex: devops)').Trim()
            if ($profile -notmatch '^[A-Za-z0-9_.@+-]+$') { throw 'Nom de profil AWS invalide.' }
            if ((Invoke-WslInteractive -ArgumentList @('aws','configure','--profile',$profile)) -ne 0) { throw 'aws configure a échoué.' }
            Set-AwsCredentialPermissions
            if (-not (Test-AwsProfile -Profile $profile)) { throw "Le profil AWS '$profile' est configuré mais STS ne le valide pas." }
            Write-Host "[OK] Profil AWS '$profile' configuré et vérifié." -ForegroundColor Green
        }
        default { throw "Choix AWS inconnu: $choice" }
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
