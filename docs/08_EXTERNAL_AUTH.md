# Connexions externes — Git, GitHub et AWS

Cette phase est volontairement séparée de la convergence système de la workstation.

## Principe

`Windows_11_Pro_Custom` peut :

- détecter qu'une identité Git est absente ;
- détecter l'état de `gh auth status` ;
- détecter les profils AWS et vérifier une session avec STS ;
- lancer les assistants officiels en mode interactif direct ;
- revalider l'état après connexion.

Le dépôt ne doit jamais :

- demander ou stocker lui-même un token GitHub ;
- extraire un token avec `gh auth token` ;
- injecter un token avec `--with-token` ;
- recevoir une Access Key ou Secret Key dans un argument PowerShell/Bash ;
- écrire un secret dans `logs/`, `reports/` ou `state/` ;
- exporter des credentials dans des variables d'environnement versionnées ;
- considérer AWS/GitHub non connectés comme une panne de la workstation.

## Centre de contrôle

Dans `menu.ps1` :

```text
8. Composants spécifiques
   8. Connexions externes interactives (Git / GitHub / AWS)
   9. Auditer les connexions externes (sans secret)
```

Après une `Installation complete` réussie, le menu exécute l'audit sans secret puis peut proposer l'assistant interactif. Le refus ou l'absence d'un compte externe ne retire pas le statut `READY` de la workstation.

## Git

Git utilise une identité de commit :

```text
user.name
user.email
```

Ces deux valeurs ne sont pas des secrets. L'assistant peut donc les demander avec `Read-Host` puis exécuter `git config --global`.

L'authentification distante n'est pas gérée par `git config user.name/user.email`.

## GitHub CLI

La connexion GitHub utilise uniquement le flux officiel :

```bash
gh auth login --hostname github.com --web --git-protocol https
gh auth setup-git --hostname github.com
gh auth status --hostname github.com
```

Le dépôt ne fournit jamais de token à `gh`, n'utilise jamais `--with-token` et ne demande jamais la valeur du token.

GitHub CLI tente normalement d'utiliser le credential store du système. Si aucun credential store Linux utilisable n'est disponible dans WSL, `gh` peut retomber sur `~/.config/gh/hosts.yml` en clair.

Dans ce cas, `Windows_11_Pro_Custom` applique un garde-fou explicite :

```text
~/.config/gh             -> 0700
~/.config/gh/hosts.yml   -> 0600
```

Le script :

1. signale clairement que ce stockage n'est pas chiffré ;
2. ne lit jamais la valeur `oauth_token` ;
3. demande un consentement explicite avant de conserver ce fallback ;
4. enregistre uniquement un marqueur **sans secret** `~/.config/gh/.wpc-plaintext-accepted` en `0600` ;
5. supprime la session GitHub si l'utilisateur refuse de conserver le token en fichier.

Un fallback `hosts.yml` protégé et explicitement accepté peut donc être opérationnel, mais il n'est jamais présenté comme équivalent à un credential store chiffré. Le mode `-RequireGitHub` reste strict et exige un stockage réellement sécurisé.

## AWS CLI sous WSL2

### Compte AWS classique — `aws login --remote`

Sous WSL2, le flux recommandé ne tente pas d'ouvrir un navigateur Linux avec `gio` ou `xdg-open`.

Le script utilise :

```bash
aws login --remote --profile <profil>
```

AWS affiche alors une URL. Elle doit être ouverte dans le navigateur Windows, puis le code d'autorisation affiché par AWS est recopié dans WSL.

Le profil `default` est proposé explicitement pour une configuration simple avec un seul compte, mais il n'est jamais choisi silencieusement.

Après la connexion :

```bash
aws sts get-caller-identity --profile <profil> --no-cli-pager
```

valide factuellement la session.

### IAM Identity Center / SSO

Pour IAM Identity Center, le script force également un flux adapté à WSL sans navigateur Linux :

```bash
aws configure sso --no-browser --use-device-code
aws sso login --profile <profil> --no-browser --use-device-code
```

Ce mode est à utiliser uniquement lorsqu'une organisation fournit une Start URL/Issuer URL et la région SSO.

### Reconnexion d'un profil existant

L'assistant détecte le mode du profil :

```text
login_session -> aws login --remote
SSO           -> aws sso login --no-browser --use-device-code
```

La configuration existante n'est pas recréée inutilement.

### Access Key / Secret Key — legacy

Quand un environnement impose encore des clés statiques, l'assistant peut lancer directement :

```bash
aws configure --profile <profil>
```

La saisie est alors gérée par AWS CLI. `Windows_11_Pro_Custom` ne lit pas les valeurs et ne les journalise pas.

Après configuration ou authentification, les permissions de `~/.aws` sont resserrées :

- répertoires : `0700` ;
- fichiers : `0600`.

Les clés statiques restent moins recommandées que les credentials temporaires ou le SSO.

## Audit sans secret

`scripts/bootstrap/15_external_auth.ps1` écrit :

```text
reports/auth/external-auth.json
```

Ce rapport contient uniquement des faits non secrets :

- présence des CLI ;
- identité Git configurée ou non ;
- GitHub authentifié ou non ;
- type de stockage GitHub détecté ;
- présence des permissions 0700/0600 ;
- acceptation explicite ou non du fallback plaintext ;
- noms de profils AWS ;
- profils AWS dont STS confirme une session valide ;
- actions utilisateur encore nécessaires.

Il contient explicitement :

```json
"SecretMaterialRecorded": false
```

Aucun Account ID, ARN, token, Access Key ou Secret Key n'est requis dans ce rapport.

## Idempotence

Si une connexion est déjà valide :

```text
[DEJA OK]
```

L'assistant ne force pas une nouvelle authentification. Un fallback GitHub déjà protégé et explicitement accepté n'est pas redemandé à chaque exécution.

AWS, GitHub et l'identité Git sont des éléments utilisateur optionnels ; la conformité système, WSL2 et DevOps reste indépendante de leur état.
