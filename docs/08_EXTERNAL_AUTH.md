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

- demander ou stocker un token GitHub ;
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

Ces deux valeurs ne sont pas des secrets. L'assistant peut donc les demander avec `Read-Host` puis exécuter :

```bash
git config --global user.name ...
git config --global user.email ...
```

L'authentification distante n'est pas gérée par `git config user.name/user.email`.

## GitHub CLI

La connexion GitHub utilise uniquement le flux officiel :

```bash
gh auth login --hostname github.com --web --git-protocol https
gh auth setup-git --hostname github.com
gh auth status --hostname github.com
```

Le dépôt ne fournit jamais de token à `gh` et n'utilise jamais `--with-token`.

Le stockage réel de la session est sous la responsabilité de GitHub CLI et de son mécanisme de credential store disponible dans l'environnement WSL.

## AWS CLI

### IAM Identity Center / SSO — recommandé

Le chemin recommandé est :

```bash
aws configure sso
aws sso login --profile <profil>
aws sts get-caller-identity --profile <profil>
```

L'authentification navigateur/device flow reste entièrement gérée par AWS CLI.

### Reconnexion d'un profil SSO existant

L'assistant liste les profils connus, demande lequel reconnecter, puis lance :

```bash
aws sso login --profile <profil>
```

### Access Key / Secret Key — legacy

Quand un environnement impose encore des clés statiques, l'assistant peut lancer directement :

```bash
aws configure --profile <profil>
```

La saisie est alors gérée par AWS CLI. `Windows_11_Pro_Custom` ne lit pas les valeurs et ne les journalise pas.

Après configuration, les permissions de `~/.aws` sont resserrées :

- répertoire : `0700` ;
- fichiers : `0600`.

Les clés statiques restent moins recommandées que le SSO ou des credentials temporaires.

## Audit sans secret

`scripts/bootstrap/15_external_auth.ps1` écrit :

```text
reports/auth/external-auth.json
```

Ce rapport ne contient que des faits non secrets :

- présence des CLI ;
- identité Git configurée ou non ;
- GitHub authentifié ou non ;
- noms de profils AWS ;
- profils AWS dont STS confirme une session valide ;
- actions utilisateur encore nécessaires.

Il contient explicitement :

```json
"SecretMaterialRecorded": false
```

Aucun Account ID, ARN, token, Access Key ou Secret Key n'est requis pour ce rapport.

## Idempotence

Si une connexion est déjà valide :

```text
[DEJA OK]
```

L'assistant ne force pas une nouvelle authentification. Il peut proposer une reconnexion volontaire.

AWS, GitHub et l'identité Git sont des éléments utilisateur optionnels ; la conformité système, WSL2 et DevOps reste indépendante de leur état.
