# Guide complet WSL2 — débuter proprement pour DevOps

Ce guide explique WSL2 **depuis les bases** puis montre comment l'utiliser correctement sur cette workstation.

Il ne suppose pas que tu connais Linux, les différences de filesystem ou le fonctionnement de Docker dans WSL2.

Pour la configuration de référence condensée, voir [`06_WSL2.md`](06_WSL2.md).

---

# 1. À quoi sert WSL2 ?

WSL signifie **Windows Subsystem for Linux**.

WSL2 permet d'utiliser un vrai environnement Linux directement depuis Windows 11 sans dual boot et sans gérer une VM traditionnelle au quotidien.

Sur cette machine :

```text
Windows 11 Pro
│
├── applications Windows
│   ├── VS Code
│   ├── Windows Terminal
│   ├── navigateurs
│   ├── bureautique
│   └── gaming
│
└── WSL2
    └── Ubuntu 26.04
        ├── Bash
        ├── Git
        ├── Docker Engine
        ├── kubectl / Helm
        ├── Terraform
        ├── Ansible
        ├── AWS CLI
        └── projets DevOps
```

L'idée n'est pas de remplacer Windows par Linux.

Le modèle est :

```text
Windows = poste de travail et hôte
Linux   = environnement DevOps
```

---

# 2. Où se trouve Linux ?

Les deux SSD physiques restent en NTFS :

```text
SSD 1 — Crucial T705
└── C:\ NTFS
    └── Windows 11 Pro

SSD 2 — Crucial T705
└── E:\ NTFS
    └── WSL\Ubuntu-DevOps\
        └── VHDX WSL
            └── filesystem ext4 Linux
```

Le point essentiel :

```text
E: reste NTFS
Ubuntu utilise ext4
ext4 se trouve à l'intérieur du VHDX
```

Il n'existe donc **aucune partition EXT4 physique** à créer sur le second SSD.

---

# 3. Le modèle mental Windows / Linux

Il faut distinguer les deux univers.

## Côté Windows

Chemins :

```text
C:\Users\...
E:\DATA\...
E:\WSL\...
```

Shell principal d'administration :

```text
PowerShell 7
```

Scripts :

```text
.ps1
.cmd
.exe
```

## Côté Ubuntu

Chemins :

```text
/home/<user>
/etc
/var
/usr
```

Shell :

```text
bash
```

Scripts :

```text
.sh
```

Commandes typiques :

```text
ls
cd
grep
sudo
apt
systemctl
```

---

# 4. La règle la plus importante pour les projets DevOps

Si le projet est utilisé principalement par des outils Linux :

```text
Docker
Terraform
Ansible
kubectl
Helm
Git Linux
Node Linux
```

alors le dépôt doit vivre dans le filesystem Linux :

```text
/home/<user>/projects
/home/<user>/labs
/home/<user>/repositories
```

Les montages Windows restent accessibles sous :

```text
/mnt/c/...
/mnt/e/...
```

`/mnt/c` et `/mnt/e` restent accessibles pour des échanges ponctuels avec Windows, mais sont **interdits comme racines de projets ou de workspaces DevOps**. Les projets Linux restent dans le filesystem ext4 de la distribution.

Pourquoi :

- permissions POSIX ;
- liens symboliques ;
- nombreux petits fichiers ;
- watchers ;
- Git ;
- dépendances Node ;
- Docker ;
- outils de build.

---

# 5. Installer WSL2 avec le dépôt

La voie recommandée est l'orchestrateur. Avant sa première exécution stricte,
enrôler et vérifier l'identité de `C:` et `E:` selon
[`25_IDENTITE_STOCKAGE_ET_RECUPERATION.md`](25_IDENTITE_STOCKAGE_ET_RECUPERATION.md) :

```powershell
.\scripts\bootstrap\00_storage_identity.ps1 -Mode Audit
.\scripts\bootstrap\00_storage_identity.ps1 `
  -Mode Record `
  -ConfirmHealthyTopology
.\scripts\bootstrap\00_storage_identity.ps1 -Mode Verify
.\install.ps1 -Mode Apply -FullInstall
```

ou le centre de contrôle :

```text
START_MENU.cmd
```

Le dépôt prépare WSL selon le contrat actuel et place Ubuntu sous :

```text
E:\WSL\Ubuntu-DevOps
```

Après installation, vérifie depuis PowerShell :

```powershell
wsl --version
wsl --status
wsl -l -v
```

La distribution `Ubuntu` doit fonctionner en **WSL 2**.

---

# 6. Premier lancement Ubuntu

Lancer :

```powershell
wsl -d Ubuntu
```

Au premier démarrage, Ubuntu peut demander :

1. un nom d'utilisateur Linux ;
2. un mot de passe Linux.

Ce compte est distinct du compte Windows.

Le mot de passe Linux n'affiche aucun caractère pendant la saisie : c'est normal.

## Vérifier ton utilisateur

```bash
whoami
id
echo "$HOME"
```

Le HOME doit ressembler à :

```text
/home/<user>
```

---

# 7. Root et sudo

`root` est le super-utilisateur Linux.

Ne travaille pas quotidiennement en root.

Pour une action administrative :

```bash
sudo commande
```

Exemple :

```bash
sudo apt update
```

Le mot de passe demandé est celui de ton utilisateur Linux.

---

# 8. Mettre Ubuntu à jour

Actualiser le catalogue :

```bash
sudo apt update
```

Mettre à jour les paquets :

```bash
sudo apt upgrade
```

À retenir :

```text
apt update   -> actualise le catalogue
apt upgrade  -> met à jour les paquets
apt install  -> installe
apt remove   -> désinstalle
```

Le dépôt ne fait pas de changement majeur de distribution Ubuntu pendant une maintenance normale.

---

# 9. Répertoires de travail

Le bootstrap prépare notamment :

```text
~/projects
~/labs
~/repositories
~/workspace
~/scripts
~/backups
```

Usage conseillé :

| Répertoire | Usage |
| --- | --- |
| `projects` | projets actifs |
| `labs` | formations, tests, Kubernetes |
| `repositories` | dépôts de référence |
| `workspace` | travaux temporaires |
| `scripts` | scripts personnels Linux |
| `backups` | exports Linux ciblés, pas backup machine complet |

---

# 10. Navigation Linux essentielle

Afficher le dossier courant :

```bash
pwd
```

Lister :

```bash
ls
ls -la
```

Changer de dossier :

```bash
cd ~/projects
```

Remonter :

```bash
cd ..
```

Retour HOME :

```bash
cd ~
```

Retour dossier précédent :

```bash
cd -
```

---

# 11. Fichiers et dossiers

Créer un dossier :

```bash
mkdir demo
mkdir -p ~/projects/demo/config
```

Créer un fichier :

```bash
touch test.txt
```

Copier :

```bash
cp source.txt destination.txt
cp -r dossier dossier-copie
```

Déplacer / renommer :

```bash
mv ancien.txt nouveau.txt
```

Supprimer :

```bash
rm fichier.txt
rm -r dossier
```

> `rm` n'utilise pas une corbeille Windows. Une commande `rm -rf` mal ciblée peut détruire beaucoup de données très vite.

---

# 12. Lire et éditer du texte

Afficher :

```bash
cat fichier.txt
```

Lire un gros fichier :

```bash
less fichier.log
```

Premières lignes :

```bash
head -n 20 fichier.log
```

Dernières lignes :

```bash
tail -n 50 fichier.log
```

Suivre un log :

```bash
tail -f application.log
```

Éditeur simple :

```bash
nano fichier.txt
```

Pour un projet :

```bash
code .
```

---

# 13. Recherche

Texte :

```bash
grep "error" application.log
grep -i "error" application.log
grep -R "TODO" .
```

Fichiers :

```bash
find . -name "*.tf"
find ~/projects -type f -name "*.sh"
```

Le profil DevOps fournit aussi des outils modernes comme `ripgrep` (`rg`) et `fd` lorsqu'ils sont installés.

---

# 14. Permissions

Afficher :

```bash
ls -l
```

Exemple :

```text
-rwxr-xr-x
```

Signification :

```text
r = read
w = write
x = execute
```

Rendre un script exécutable :

```bash
chmod +x script.sh
```

Ne résous pas un problème de permissions avec :

```bash
chmod -R 777 ...
```

sans comprendre la cause.

---

# 15. Informations système

Distribution :

```bash
cat /etc/os-release
```

Noyau :

```bash
uname -a
```

CPU :

```bash
lscpu
nproc
```

Mémoire :

```bash
free -h
```

Swap :

```bash
swapon --show
```

Filesystems :

```bash
df -h
findmnt -T "$HOME"
```

Taille d'un dossier :

```bash
du -sh ~/projects
```

---

# 16. Processus et services

Processus :

```bash
ps aux
```

Filtrer :

```bash
ps aux | grep docker
```

Vue interactive :

```bash
top
```

Trouver un PID :

```bash
pgrep -a dockerd
```

Arrêter proprement :

```bash
kill PID
```

`kill -9` doit rester un dernier recours.

---

# 17. systemd

La distribution utilise systemd.

Vérifier PID 1 :

```bash
ps -p 1 -o comm=
```

Attendu :

```text
systemd
```

État d'un service :

```bash
systemctl status docker
```

Démarrer :

```bash
sudo systemctl start docker
```

Redémarrer :

```bash
sudo systemctl restart docker
```

Logs :

```bash
journalctl -u docker -n 100
journalctl -u docker -f
```

---

# 18. Réseau Linux

Interfaces :

```bash
ip addr
```

Routes :

```bash
ip route
```

DNS :

```bash
getent hosts github.com
```

Connectivité :

```bash
ping -c 4 github.com
curl -I https://github.com
```

Ports :

```bash
ss -lntup
```

---

# 19. Pipes et redirections

Pipe :

```bash
ps aux | grep terraform
```

Écraser/créer un fichier :

```bash
echo "bonjour" > test.txt
```

Ajouter :

```bash
echo "ligne" >> test.txt
```

À retenir :

```text
>  écrase
>> ajoute
```

---

# 20. Variables d'environnement

Afficher :

```bash
echo "$HOME"
```

Variable temporaire :

```bash
export DEMO=value
```

Afficher l'environnement :

```bash
env
```

Ne mets jamais de secret AWS, token GitHub ou clé API dans un dépôt Git.

---

# 21. PATH

Afficher :

```bash
echo "$PATH"
```

Trouver une commande :

```bash
command -v terraform
command -v kubectl
```

Voir son type :

```bash
type terraform
```

---

# 22. Git dans WSL

Configurer :

```bash
git config --global user.name "Ton Nom"
git config --global user.email "ton-adresse@example.com"
```

Cloner **dans Linux** :

```bash
cd ~/projects
git clone <URL_DU_DEPOT>
```

Puis :

```bash
cd mon-projet
git status
```

Le dépôt Windows lui-même reste naturellement côté Windows ; les projets Linux opérationnels vont sous `/home`.

---

# 23. VS Code + WSL

Depuis un projet Linux :

```bash
cd ~/projects/mon-projet
code .
```

VS Code Windows ouvre alors une fenêtre connectée à Ubuntu.

Le résultat recherché :

```text
VS Code UI        Windows
projet            Linux ext4
terminal intégré  Bash WSL
Terraform         Linux
Docker            Linux
Git               Linux
```

Cela évite les incohérences d'environnement.

---

# 24. Explorer les fichiers Linux depuis Windows

Depuis WSL :

```bash
explorer.exe .
```

Ou via :

```text
\\wsl$\Ubuntu\home\<user>
```

selon le contexte Windows.

Ne manipule jamais directement le fichier VHDX comme un fichier ordinaire pendant que WSL l'utilise.

---

# 25. Accéder aux disques Windows depuis Ubuntu

```text
C: -> /mnt/c
E: -> /mnt/e
```

Exemple :

```bash
ls /mnt/e
```

Utilise ces chemins uniquement pour des échanges ponctuels avec Windows : `/mnt/c` et `/mnt/e` sont **interdits comme racines de projets ou de workspaces DevOps**.

---

# 26. Interop Windows / Linux

Depuis Ubuntu :

```bash
explorer.exe .
powershell.exe -Command "Get-Date"
ipconfig.exe
```

Depuis PowerShell :

```powershell
wsl -d Ubuntu -- uname -a
wsl -d Ubuntu -- bash -lc "cd ~/projects && pwd && ls -la"
```

Cette interop est utile pour l'orchestration Windows → Linux.

---

# 27. Commandes WSL côté PowerShell

Aide :

```powershell
wsl --help
```

Version :

```powershell
wsl --version
```

État :

```powershell
wsl --status
```

Distributions :

```powershell
wsl -l -v
```

Lancer Ubuntu :

```powershell
wsl -d Ubuntu
```

Arrêter toutes les distributions :

```powershell
wsl --shutdown
```

Arrêter Ubuntu uniquement :

```powershell
wsl --terminate Ubuntu
```

Mettre le runtime WSL à jour :

```powershell
wsl --update
```

---

# 28. `.wslconfig` — configuration globale

Le fichier :

```text
%USERPROFILE%\.wslconfig
```

définit les ressources globales de la VM WSL2.

## Profil quotidien actuel

```ini
[wsl2]
memory=20GB
processors=8
swap=8GB
swapFile=E:\\WSL\\swap\\wsl-swap.vhdx
networkingMode=mirrored
dnsTunneling=true
firewall=true
autoProxy=true
nestedVirtualization=false
maxCrashDumpCount=3

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
bestEffortDnsParsing=true
hostAddressLoopback=true
```

### `memory=20GB`

WSL peut utiliser jusqu'à environ 20 Go pour le profil quotidien.

Ce n'est pas 20 Go réservés en permanence.

### `processors=8`

Ubuntu voit 8 threads sur les 16 threads logiques du Ryzen 7 7700.

### `swap=8GB`

Le swap absorbe les pics mémoire au lieu de provoquer immédiatement un OOM.

### `networkingMode=mirrored`

Le mode mirrored facilite l'intégration réseau avec Windows moderne.

### `dnsTunneling=true`

Le DNS passe par le mécanisme WSL/Windows prévu.

### `firewall=true`

La sécurité réseau WSL/Hyper-V reste active.

### `autoMemoryReclaim=gradual`

WSL restitue progressivement de la mémoire de cache à Windows.

### `sparseVhd=true`

Le VHDX peut gérer plus efficacement l'allocation physique de l'espace.

Après modification :

```powershell
wsl --shutdown
```

---

# 29. Profils de ressources

## Standard

```text
8 threads
20 Go RAM
8 Go swap
mirrored networking
```

Usage : quotidien DevOps.

## Lab-heavy

```text
12 threads
28 Go RAM
12 Go swap
mirrored networking
```

Usage : clusters locaux, builds lourds, labs Kubernetes.

## NAT fallback

Même philosophie de ressources que le profil standard, avec réseau NAT pour les cas de compatibilité VPN/réseau.

Changer de profil avec le mécanisme du dépôt puis exécuter :

```powershell
wsl --shutdown
```

Le profil lourd doit rester **temporaire**.

---

# 30. Pourquoi ne pas donner 48 Go et 16 threads à WSL ?

Parce que la workstation doit rester équilibrée.

Windows utilise aussi :

- VS Code ;
- navigateurs ;
- applications desktop ;
- Defender ;
- gaming ;
- cache système ;
- pilotes GPU ;
- outils d'administration.

Le bon objectif n'est pas :

```text
WSL le plus gros possible
```

mais :

```text
WSL assez puissant
+
Windows toujours réactif
```

---

# 31. `/etc/wsl.conf`

Ce fichier vit **dans Ubuntu** :

```text
/etc/wsl.conf
```

Contrat courant :

```ini
[boot]
systemd=true

[automount]
enabled=true
mountFsTab=true

[interop]
enabled=true
appendWindowsPath=true

[network]
generateHosts=true
generateResolvConf=true
```

Différence :

```text
.wslconfig     -> Windows -> VM WSL2 globale
/etc/wsl.conf  -> Ubuntu  -> distribution Linux
```

---

# 32. Docker Engine sans Docker Desktop

Docker fonctionne directement dans Ubuntu.

Vérifier :

```bash
systemctl status docker
docker info
docker run --rm hello-world
```

Après ajout de l'utilisateur au groupe `docker`, exécute :

```powershell
wsl --shutdown
```

puis relance Ubuntu.

L'accès Docker sans sudo est pratique mais donne un niveau de privilège important dans la distribution : il faut le considérer comme tel.

---

# 33. Docker et stockage WSL

Les images, layers et volumes Docker sont stockés dans le filesystem Linux du VHDX.

Surveiller :

```bash
docker system df
```

Ne lance pas automatiquement :

```bash
docker system prune -a
```

sur une machine de travail sans vérifier ce qui serait supprimé.

Le daemon utilise une politique de logs bornée pour limiter la croissance silencieuse du VHDX.

---

# 34. Kubernetes local

Deux usages principaux :

```text
Minikube -> cluster local simple
kind     -> clusters Kubernetes dans Docker
```

Exemple :

```bash
minikube start --driver=docker
```

Avant un lab lourd, le profil `lab-heavy` peut être utile.

Après le lab, reviens au profil quotidien.

---

# 35. Terraform

Vérifier :

```bash
terraform version
```

Workflow classique :

```bash
terraform fmt
terraform init
terraform validate
terraform plan
```

N'applique jamais un plan Terraform sur un compte Cloud sans avoir vérifié le contexte, les credentials et les ressources qui seront créées.

---

# 36. Ansible

Vérifier :

```bash
ansible-playbook --version
```

Ansible s'exécute côté Linux, ce qui évite de transformer Windows en environnement Ansible natif non standard.

---

# 37. AWS CLI et secrets

Vérifier :

```bash
aws --version
```

Ne commit jamais :

- Access Key ;
- Secret Key ;
- session token ;
- fichiers `.env` contenant des secrets ;
- credentials OpenRouter ;
- tokens GitHub.

Le fait qu'un projet vive dans WSL ne change pas les règles de sécurité Git.

---

# 38. SSH

Générer une clé si nécessaire :

```bash
ssh-keygen -t ed25519
```

Les clés privées restent locales et protégées.

Le poste dispose également du client OpenSSH côté Windows pour VS Code Remote - SSH et l'administration Windows.

---

# 39. Sauvegarder WSL2

La stratégie de la workstation inclut un export de la distribution avec vérification d'intégrité.

Utilise les mécanismes documentés dans :

[`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

Ne considère pas `~/backups` comme la sauvegarde complète de la distribution : une panne du SSD interne détruirait aussi ce dossier.

---

# 40. Restaurer WSL sans détruire l'actuel

Une restauration doit d'abord être importée sous un nom distinct, par exemple :

```text
Ubuntu-Restore
```

Puis valider :

```text
boot
utilisateur
projets
Docker
DevOps
permissions
```

Avant toute décision de remplacement.

Évite :

```powershell
wsl --unregister Ubuntu
```

sans sauvegarde et sans validation de la copie de restauration.

---

# 41. Dépannage : WSL ne démarre pas

Depuis PowerShell :

```powershell
wsl --status
wsl -l -v
wsl --shutdown
wsl --update
```

Puis relance :

```powershell
wsl -d Ubuntu
```

Si le problème suit une modification de profil, reviens à la configuration standard avant d'envisager une réinstallation.

---

# 42. Dépannage : Docker ne fonctionne pas

Dans Ubuntu :

```bash
systemctl status docker
journalctl -u docker -n 100
id
```

Vérifie :

- service actif ;
- utilisateur membre du groupe attendu ;
- disque non plein ;
- filesystem HOME correct.

Ne réinstalle pas Docker avant d'avoir compris le symptôme.

---

# 43. Dépannage : réseau / DNS

Contrôles :

```bash
ip addr
ip route
getent hosts github.com
curl -I https://github.com
```

Si le réseau mirrored pose un problème avec un VPN ou un réseau particulier, le profil NAT fallback existe pour ce cas.

Ne désactive pas le firewall globalement pour contourner un problème de DNS.

---

# 44. Dépannage : WSL consomme trop de RAM

Vérifie d'abord :

```bash
free -h
ps aux --sort=-%mem | head
```

Côté Windows, si la session Linux n'est plus nécessaire :

```powershell
wsl --shutdown
```

Le profil standard et `autoMemoryReclaim=gradual` sont justement conçus pour éviter une consommation incontrôlée en usage quotidien.

---

# 45. Dépannage : disque WSL grossit

Chercher les gros consommateurs :

```bash
du -h --max-depth=1 ~ | sort -h
docker system df
```

Contrôle aussi :

- images Docker obsolètes ;
- caches de builds ;
- dépendances locales ;
- logs applicatifs ;
- gros artefacts de labs.

Ne supprime pas aveuglément les données Docker ou les projets.

---

# 46. Validation complète WSL2

Depuis PowerShell :

```powershell
.\install.ps1 -Mode Verify -ValidateWsl
```

Pour inclure l'environnement DevOps :

```powershell
.\install.ps1 -Mode Verify -ValidateWsl -ValidateDevOps
```

La validation doit contrôler l'état réel :

```text
Ubuntu 26.04
WSL 2
E:\WSL\Ubuntu-DevOps
HOME ext4
systemd
ressources du profil
Docker
outils DevOps
racines de travail
```

Guide de validation : [`11_VALIDATION.md`](11_VALIDATION.md).

---

# 47. Routine quotidienne recommandée

Ouvrir Windows Terminal avec le profil `Ubuntu - DevOps` ou VS Code WSL.

Dans Ubuntu :

```bash
cd ~/projects
```

Avant un lab :

```bash
docker info
```

Pour un lab lourd, passer temporairement au profil adapté.

Après la session :

- arrêter les clusters locaux inutiles ;
- ne pas laisser des conteneurs consommer des ressources sans raison ;
- revenir au profil standard si tu avais utilisé un profil lourd.

Avant une session gaming sans besoin Linux :

```powershell
wsl --shutdown
```

---

# 48. Ce qu'il faut retenir

Si tu ne retiens que dix règles :

1. Windows reste l'hôte ; Ubuntu est le backend DevOps.
2. Le second SSD reste NTFS.
3. Le filesystem Linux est dans un VHDX ext4.
4. Les projets Linux actifs vivent dans `/home/<user>/...`.
5. `/mnt/c` et `/mnt/e` servent surtout aux échanges.
6. Le profil quotidien est 20 Go RAM / 8 threads / 8 Go swap.
7. `wsl --shutdown` recharge complètement la configuration.
8. Docker tourne directement dans Ubuntu avec systemd.
9. Les secrets ne vont jamais dans Git.
10. Une restauration WSL se valide d'abord en parallèle avant toute suppression.

WSL2 est alors moins une « couche magique » qu'un **serveur Linux personnel intégré à la workstation Windows**, avec des frontières claires et des ressources maîtrisées.
