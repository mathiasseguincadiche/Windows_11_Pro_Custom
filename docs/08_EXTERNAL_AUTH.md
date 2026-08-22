# Connexions externes — Git, GitHub et AWS

Cette phase est séparée de la convergence système de la workstation. L'absence d'une session GitHub ou AWS ne retire pas le statut READY de Windows, WSL2 ou de la stack DevOps.

## Principe de sécurité

`Windows_11_Pro_Custom` peut :

- configurer `git user.name` et `git user.email` ;
- vérifier `gh auth status` ;
- vérifier les profils AWS avec `aws sts get-caller-identity` ;
- exécuter AWS CLI de manière interactive directement dans le terminal PowerShell courant ;
- ouvrir un terminal WSL dédié uniquement lorsqu'une autre frontière interactive est volontairement conservée, notamment pour GitHub CLI ;
- revalider l'état après l'action utilisateur.

Le dépôt ne doit jamais :

- lire ou journaliser un token GitHub ;
- appeler `gh auth token` ou `--show-token` ;
- injecter `--with-token` ou `--insecure-storage` ;
- recevoir une Access Key ou une Secret Access Key dans un argument PowerShell ;
- écrire un secret dans `logs/`, `reports/` ou `state/`.

## Frontières interactives

Les commandes non interactives peuvent être exécutées par un wrapper qui capture leur sortie afin de contrôler factuellement le code retour et le résultat.

Une commande AWS interactive suit désormais une règle différente : **aucune capture, aucune redirection, aucune seconde fenêtre**.

```text
Windows Terminal
└── PowerShell 7 courant
    └── wsl.exe --distribution Ubuntu --user <user> --exec ...
        └── AWS CLI interactif
```

Le processus AWS hérite directement de `stdin`, `stdout` et `stderr` de la fenêtre PowerShell. Le helper interactif AWS n'utilise ni affectation de sortie, ni pipeline, ni `2>&1`. Cela permet de conserver dans une seule fenêtre :

1. les informations affichées par AWS CLI ;
2. l'URL à ouvrir dans le navigateur ;
3. le code d'autorisation affiché par le navigateur ;
4. le collage du code dans le terminal ;
5. le résultat final de la commande.

Le comportement précédent ouvrait un second onglet Windows Terminal puis demandait de revenir dans la fenêtre principale. Cette séparation n'est plus utilisée pour AWS.

GitHub CLI conserve pour l'instant sa frontière WSL dédiée :

```text
PowerShell 7 courant
└── nouvel onglet Windows Terminal / WSL
    └── gh auth login
```

Les deux comportements sont donc volontairement distincts.

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

Le centre de contrôle exécute directement dans **la fenêtre PowerShell courante** :

```bash
aws login --remote --profile <profil> --region <region>
```

Le profil `default` est proposé explicitement. Si aucune région n'est configurée, `us-east-1` est proposée comme valeur initiale.

Le parcours devient :

1. le script reste dans la fenêtre PowerShell 7 courante ;
2. AWS CLI affiche l'URL d'authentification dans cette même fenêtre ;
3. l'utilisateur ouvre l'URL dans son navigateur Windows ;
4. le navigateur affiche le code d'autorisation ;
5. l'utilisateur copie ce code ;
6. l'utilisateur le colle directement dans la fenêtre PowerShell 7 où AWS attend déjà la saisie ;
7. AWS CLI termine la connexion ;
8. le script reprend automatiquement et valide la session.

Il n'y a plus d'onglet AWS secondaire ni de confirmation manuelle demandant de revenir dans la fenêtre initiale.

Le centre de contrôle valide ensuite :

```bash
aws sts get-caller-identity --profile <profil> --no-cli-pager
```

Pour un utilisateur ou rôle IAM, AWS peut exiger la politique gérée `SignInLocalDevelopmentAccess`. Un compte root n'a pas besoin de cette politique pour `aws login`.

## AWS IAM Identity Center / SSO

La configuration et la connexion suivent la même règle **mono-terminal** :

```bash
aws configure sso --no-browser --use-device-code
aws sso login --profile <profil> --no-browser --use-device-code
```

Ces commandes s'exécutent directement dans la fenêtre PowerShell courante via WSL, sans capture de leurs flux interactifs.

Ce mode est réservé aux environnements où une organisation fournit les informations IAM Identity Center nécessaires.

## AWS Access Key / Secret Key — legacy

Si des clés IAM statiques sont explicitement requises, le centre de contrôle exécute également dans la fenêtre courante :

```bash
aws configure --profile <profil>
```

La saisie reste directement entre l'utilisateur et AWS CLI. Le dépôt ne capture ni ne journalise les valeurs et ne les reçoit pas comme arguments PowerShell.

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
