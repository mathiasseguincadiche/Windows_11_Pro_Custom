# Connexions externes — Git, GitHub et AWS

Cette phase est séparée de la convergence système de la workstation. L'absence d'une session GitHub ou AWS ne retire pas le statut READY de Windows, WSL2 ou de la stack DevOps.

## Principe de sécurité

`Windows_11_Pro_Custom` peut :

- configurer `git user.name` et `git user.email` ;
- vérifier `gh auth status` ;
- vérifier les profils AWS avec `aws sts get-caller-identity` ;
- exécuter AWS CLI de manière interactive directement dans le terminal PowerShell courant ;
- ouvrir le navigateur Windows par un bridge WSL non secret pour le flux AWS same-device ;
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

Une commande AWS interactive suit une règle différente : **aucune capture, aucune redirection, aucune seconde fenêtre AWS**.

```text
Windows Terminal
└── PowerShell 7 courant
    └── wsl.exe --distribution Ubuntu --user <user> --exec ...
        └── AWS CLI
```

Le processus AWS hérite directement de `stdin`, `stdout` et `stderr` de la fenêtre PowerShell. Le helper interactif AWS n'utilise ni affectation de sortie, ni pipeline, ni redirection de flux.

Pour la connexion AWS Console classique, le flux est encore plus simple : il ne dépend plus du clavier Linux. `aws login` utilise l'authentification **same-device** et le navigateur Windows renvoie automatiquement le callback OAuth à AWS CLI via `localhost`.

GitHub CLI conserve pour l'instant sa frontière WSL dédiée :

```text
PowerShell 7 courant
└── nouvel onglet Windows Terminal / WSL
    └── gh auth login
```

Les deux comportements sont volontairement distincts.

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

### Pourquoi `--remote` n'est plus utilisé

AWS distingue deux flux :

- `aws login` : **same-device**, prévu lorsque le navigateur et AWS CLI sont sur la même machine ;
- `aws login --remote` : **cross-device**, prévu pour un hôte réellement distant ou sans navigateur.

Sur cette workstation, Windows et WSL2 sont deux environnements de la **même machine** et un navigateur Windows est disponible. Le flux same-device est donc le contrat correct.

Le flux cross-device a en plus montré une incompatibilité physique dans la chaîne PowerShell → `wsl.exe` → AWS CLI : la lecture interactive du code pouvait revenir vide. AWS CLI tentait alors de décoder une valeur absente et terminait avec l'erreur `argument should be a bytes-like object or ASCII string, not 'NoneType'`.

Le dépôt interdit donc désormais `aws login --remote` pour le parcours compte classique.

### Flux retenu

Le centre de contrôle exécute dans la fenêtre PowerShell courante :

```bash
aws login --profile <profil> --region <region>
```

Le profil `default` est proposé explicitement. Si aucune région n'est configurée, `us-east-1` est proposée comme valeur initiale.

Avant la commande, le dépôt prépare un petit bridge navigateur non secret dans WSL :

```text
~/.local/bin/wpc-open-windows-browser
```

Il est limité au compte Linux (`0700`) et appelle directement l'exécutable Windows Explorer par l'interop WSL :

```bash
explorer.exe "$1"
```

Le bridge ne passe volontairement **pas** par `cmd.exe /c start`. Une URL OAuth AWS contient plusieurs paramètres séparés par `&`; `cmd.exe` peut interpréter ces caractères comme des séparateurs de commandes et tronquer l'URL. Le passage direct à `explorer.exe` conserve l'URL complète comme un seul argument et laisse Windows l'ouvrir avec le gestionnaire HTTP/HTTPS par défaut.

Le chemin du bridge est fourni temporairement à AWS CLI via la variable d'environnement standard `BROWSER`.

Le parcours devient :

1. le script reste dans la fenêtre PowerShell 7 courante ;
2. AWS CLI démarre un callback OAuth local ;
3. le bridge transmet l'URL OAuth complète à Windows sans passer par `cmd.exe` ;
4. le navigateur Windows par défaut s'ouvre ;
5. l'utilisateur se connecte normalement sur le site AWS ;
6. le navigateur renvoie automatiquement le callback vers `127.0.0.1` ;
7. AWS CLI récupère l'autorisation sans demander de code à copier/coller ;
8. le script valide la session avec STS.

Si le navigateur ne s'ouvre pas automatiquement, AWS CLI affiche également l'URL. Il suffit alors d'ouvrir cette URL dans le navigateur Windows ; le retour reste automatique via le callback local.

Le centre de contrôle valide ensuite :

```bash
aws sts get-caller-identity --profile <profil> --no-cli-pager
```

Pour un utilisateur ou rôle IAM, AWS peut exiger la politique gérée `SignInLocalDevelopmentAccess`. Un compte root n'a pas besoin de cette politique pour `aws login`.

## AWS IAM Identity Center / SSO

La configuration et la connexion suivent la règle **mono-terminal** :

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
