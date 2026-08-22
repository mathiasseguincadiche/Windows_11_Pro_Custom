# Connexions externes — Git, GitHub et AWS

Cette phase est séparée de la convergence système de la workstation. L'absence d'une session GitHub ou AWS ne retire pas le statut READY de Windows, WSL2 ou de la stack DevOps.

## Principe de sécurité

`Windows_11_Pro_Custom` peut :

- configurer `git user.name` et `git user.email` ;
- vérifier `gh auth status` ;
- vérifier les profils AWS avec `aws sts get-caller-identity` ;
- ouvrir un terminal WSL dédié pour les commandes qui demandent réellement une saisie ;
- revalider l'état après l'action utilisateur.

Le dépôt ne doit jamais :

- lire ou journaliser un token GitHub ;
- appeler `gh auth token` ou `--show-token` ;
- injecter `--with-token` ou `--insecure-storage` ;
- recevoir une Access Key ou une Secret Access Key dans un argument PowerShell ;
- écrire un secret dans `logs/`, `reports/` ou `state/`.

## Pourquoi les commandes interactives utilisent un onglet Windows Terminal dédié

Le centre de contrôle s'exécute dans PowerShell Windows. Une commande interactive lancée directement par la chaîne :

```text
PowerShell -> wsl.exe -> AWS CLI / GitHub CLI
```

peut ne pas recevoir un véritable stdin Linux interactif. Ce cas a été observé physiquement avec AWS CLI 2.36.21 : `aws login --remote` recevait une réponse vide et AWS CLI terminait avec une erreur interne `NoneType` avant que l'utilisateur puisse saisir le code.

Le contrat courant évite cette classe de panne. Les commandes qui ont besoin d'un terminal sont lancées dans un **nouvel onglet Windows Terminal exécutant directement WSL** :

```text
Centre de contrôle PowerShell
        |
        +--> Windows Terminal / WSL interactif réel
                |
                +--> gh auth login
                +--> aws login --remote
                +--> aws configure sso
                +--> aws sso login
                +--> aws configure
```

Le centre de contrôle attend ensuite la confirmation de l'utilisateur puis vérifie factuellement le résultat.

## Git

L'identité Git globale est non secrète :

```bash
git config --global user.name
git config --global user.email
```

Le script peut la lire et la modifier directement.

## GitHub CLI

L'authentification interactive utilise dans l'onglet WSL dédié :

```bash
gh auth login --hostname github.com --web --git-protocol https
```

Après le retour dans le centre de contrôle :

```bash
gh auth status --hostname github.com
gh auth setup-git --hostname github.com
```

sont utilisés pour vérifier et configurer Git.

### Fallback `hosts.yml`

Si GitHub CLI ne trouve aucun credential store Linux exploitable, il peut écrire le token dans :

```text
~/.config/gh/hosts.yml
```

Dans ce cas le dépôt applique :

```text
~/.config/gh             -> 0700
~/.config/gh/hosts.yml   -> 0600
```

Le script demande un consentement explicite avant de conserver ce fallback et mémorise uniquement un marqueur sans secret :

```text
~/.config/gh/.wpc-plaintext-accepted
```

Un credential store réellement sécurisé reste préférable et le mode strict continue de le distinguer du fallback plaintext.

## AWS CLI — compte classique

AWS CLI 2.32.0 minimum est requis pour `aws login`.

Le centre de contrôle ouvre un onglet WSL dédié et exécute :

```bash
aws login --remote --profile <profil> --region <region>
```

Le profil `default` est proposé explicitement. Si aucune région n'est configurée, `us-east-1` est proposée comme valeur initiale afin d'éviter que AWS CLI tente d'ouvrir un prompt caché dans le processus WSL parent.

Dans l'onglet WSL dédié :

1. AWS affiche l'URL d'authentification ;
2. l'utilisateur ouvre cette URL dans son navigateur Windows ;
3. l'utilisateur recopie le code d'autorisation dans le véritable terminal WSL ;
4. AWS CLI termine la connexion.

Le centre de contrôle valide ensuite :

```bash
aws sts get-caller-identity --profile <profil> --no-cli-pager
```

Pour un utilisateur ou rôle IAM, AWS peut exiger la politique gérée `SignInLocalDevelopmentAccess`. Un compte root n'a pas besoin de cette politique pour `aws login`.

## AWS IAM Identity Center / SSO

La configuration et la connexion utilisent elles aussi le terminal WSL dédié :

```bash
aws configure sso --no-browser --use-device-code
aws sso login --profile <profil> --no-browser --use-device-code
```

Ce mode est réservé aux environnements où une organisation fournit les informations IAM Identity Center nécessaires.

## AWS Access Key / Secret Key — legacy

Si des clés IAM statiques sont explicitement requises, le centre de contrôle lance dans l'onglet WSL dédié :

```bash
aws configure --profile <profil>
```

La saisie reste donc entre l'utilisateur et AWS CLI. Le dépôt ne lit ni ne journalise les valeurs.

Après une configuration AWS, les permissions locales sous `~/.aws` sont resserrées : répertoires `0700`, fichiers `0600`.

## Audit sans secret

Le script `scripts/bootstrap/15_external_auth.ps1` écrit :

```text
reports/auth/external-auth.json
```

Le rapport contient uniquement des faits non secrets : présence des CLI, identité Git, état GitHub, type de stockage GitHub, permissions, profils AWS et résultat STS.

Il contient explicitement :

```json
"SecretMaterialRecorded": false
```

Aucun Account ID, ARN, token, Access Key ou Secret Key n'est requis dans ce rapport.
