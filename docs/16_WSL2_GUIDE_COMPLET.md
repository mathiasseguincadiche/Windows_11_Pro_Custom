# Guide complet WSL2 — débuter proprement pour DevOps

## 1. À quoi sert WSL2 ?

WSL signifie **Windows Subsystem for Linux**.

WSL2 permet d'utiliser un vrai environnement Linux directement depuis Windows 11, sans dual boot et sans gérer une VM traditionnelle au quotidien.

Dans cette machine, le rôle de chaque couche est clair :

```text
Windows 11 Pro
│
├── applications Windows
│   ├── VS Code
│   ├── WezTerm
│   ├── Firefox / Brave
│   └── Office / outils desktop
│
└── WSL2
    └── Ubuntu
        ├── Bash
        ├── Git
        ├── Docker Engine
        ├── kubectl / Helm
        ├── Terraform
        ├── Ansible
        ├── AWS CLI
        └── projets DevOps
```

L'idée n'est pas de « remplacer Windows par Linux ».

L'idée est :

```text
Windows = poste de travail
Linux WSL2 = environnement DevOps
```

## 2. Architecture de cette machine

Les deux SSD physiques restent en NTFS :

```text
SSD 1 — Crucial T705
└── C:\ NTFS
    ├── Windows 11 Pro
    ├── Program Files
    └── Users

SSD 2 — Crucial T705
└── D:\ NTFS
    ├── DATA\
    ├── WSL\
    │   └── Ubuntu-DevOps\
    │       └── ext4.vhdx
    ├── ISO\
    ├── Backups\
    └── Temp\
```

Le fichier :

```text
D:\WSL\Ubuntu-DevOps\ext4.vhdx
```

est un **disque dur virtuel Linux**.

À l'intérieur de ce fichier se trouve le système de fichiers Linux ext4.

Donc :

```text
D: NTFS
└── ext4.vhdx
    └── ext4 Linux
        ├── /etc
        ├── /var
        ├── /usr
        └── /home/<user>
```

Il n'existe **aucune partition EXT4 physique** sur les SSD.

## 3. Le modèle mental le plus important

Il faut toujours distinguer les deux mondes.

### Côté Windows

Chemins :

```text
C:\Users\...
D:\DATA\...
D:\WSL\...
```

Shell :

```text
PowerShell
```

Exécutables :

```text
.exe
.ps1
```

### Côté Linux / Ubuntu

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

Commandes :

```text
ls
cd
grep
sudo
apt
systemctl
```

### Règle simple

Si le projet est utilisé principalement par des outils Linux :

```text
Docker
Terraform
Ansible
kubectl
Helm
Git Linux
```

le projet doit rester dans :

```text
/home/<user>/projects
```

et **pas** dans :

```text
/mnt/c/...
/mnt/d/...
```

Microsoft recommande de stocker les projets sur le même système de fichiers que les outils qui les utilisent afin d'éviter les pertes de performances dues aux accès croisés Windows/Linux.

## 4. Installation WSL2 dans ce dépôt

Depuis PowerShell administrateur, le projet prépare WSL avec :

```powershell
.\install.ps1 -Mode Apply
```

Le bootstrap utilise une installation du type :

```powershell
wsl --install --distribution Ubuntu --location D:\WSL\Ubuntu-DevOps --no-launch
```

Puis :

```powershell
wsl --set-default-version 2
wsl --update
```

### Vérifier l'installation

Dans PowerShell :

```powershell
wsl --version
```

Affiche la version de WSL, du noyau Linux et des composants associés.

```powershell
wsl --status
```

Affiche l'état général de WSL.

```powershell
wsl --list --verbose
```

Version courte :

```powershell
wsl -l -v
```

Exemple attendu :

```text
NAME      STATE      VERSION
Ubuntu    Stopped    2
```

Le chiffre important est :

```text
VERSION = 2
```

## 5. Premier lancement Ubuntu

Après l'installation :

```powershell
wsl -d Ubuntu
```

ou lancer Ubuntu depuis WezTerm.

Au premier démarrage, Ubuntu demande généralement :

1. un nom d'utilisateur Linux ;
2. un mot de passe Linux.

Ce compte est **différent du compte Windows**.

Exemple :

```text
Windows user : Mathias
Linux user   : mathias
```

Le mot de passe Linux n'affiche aucun caractère lorsque tu le tapes dans le terminal.

C'est normal.

## 6. Comprendre `root`, ton utilisateur et `sudo`

Linux possède un super-utilisateur :

```text
root
```

Il peut tout modifier.

Pour le travail quotidien, **ne travaille pas en root**.

Ton compte normal ressemble à :

```text
mathias
```

Quand une opération exige les droits administrateur Linux :

```bash
sudo commande
```

Exemple :

```bash
sudo apt update
```

Linux demande alors ton mot de passe Linux.

### Vérifier qui tu es

```bash
whoami
```

### Afficher ton UID et tes groupes

```bash
id
```

### Voir ton dossier personnel

```bash
echo "$HOME"
```

Attendu :

```text
/home/<user>
```

## 7. Première mise à jour Ubuntu

Après le premier lancement :

```bash
sudo apt update
```

Cette commande actualise la liste des paquets disponibles.

Puis :

```bash
sudo apt upgrade
```

Cette commande installe les mises à jour disponibles.

Version non interactive :

```bash
sudo apt update && sudo apt upgrade -y
```

### À retenir

```text
apt update  = actualise le catalogue
apt upgrade = met les logiciels à jour
apt install = installe un paquet
apt remove  = désinstalle un paquet
```

## 8. Ton espace de travail Linux

Le bootstrap DevOps crée notamment :

```text
/home/<user>/
├── projects/
├── labs/
├── repositories/
├── workspace/
└── backups/
```

Usage recommandé :

```text
projects/      projets actifs
labs/          tests temporaires / Kubernetes / formations
repositories/  dépôts de référence
workspace/     travaux transitoires
backups/       exports Linux locaux ciblés
```

Pour aller dans tes projets :

```bash
cd ~/projects
```

`~` signifie :

```text
mon HOME
```

Donc :

```bash
cd ~
```

équivaut à :

```bash
cd /home/<user>
```

## 9. Commandes Linux essentielles — navigation

### `pwd`

```bash
pwd
```

Affiche le dossier courant.

Exemple :

```text
/home/mathias/projects
```

### `ls`

```bash
ls
```

Liste les fichiers.

Plus détaillé :

```bash
ls -l
```

Inclure les fichiers cachés :

```bash
ls -la
```

Dans le profil fourni par le dépôt :

```bash
ll
```

est un alias pratique pour une liste détaillée.

### `cd`

Entrer dans un dossier :

```bash
cd projects
```

Remonter d'un niveau :

```bash
cd ..
```

Retour au HOME :

```bash
cd ~
```

Retour au dossier précédent :

```bash
cd -
```

## 10. Fichiers et dossiers

### Créer un dossier

```bash
mkdir demo
```

Créer plusieurs niveaux :

```bash
mkdir -p ~/projects/demo/config
```

### Créer un fichier vide

```bash
touch test.txt
```

### Copier

```bash
cp source.txt destination.txt
```

Copier un dossier :

```bash
cp -r dossier-source dossier-copie
```

### Déplacer ou renommer

```bash
mv ancien.txt nouveau.txt
```

Déplacer :

```bash
mv fichier.txt ~/projects/demo/
```

### Supprimer un fichier

```bash
rm fichier.txt
```

### Supprimer un dossier vide

```bash
rmdir dossier
```

### Supprimer récursivement

```bash
rm -r dossier
```

**Attention** : Linux ne possède pas de corbeille automatique pour `rm`.

Une commande du type :

```bash
rm -rf ...
```

peut détruire très rapidement beaucoup de données. Ne l'utilise jamais en recopiant une commande sans comprendre le chemin ciblé.

## 11. Lire et éditer du texte

Afficher un petit fichier :

```bash
cat fichier.txt
```

Lire confortablement un gros fichier :

```bash
less fichier.log
```

Quitter `less` :

```text
q
```

Premières lignes :

```bash
head fichier.log
```

20 premières lignes :

```bash
head -n 20 fichier.log
```

Dernières lignes :

```bash
tail fichier.log
```

Suivre un log en direct :

```bash
tail -f application.log
```

Éditeur simple :

```bash
nano fichier.txt
```

Dans Nano :

```text
Ctrl+O  enregistrer
Entrée   confirmer
Ctrl+X  quitter
```

Pour les projets, VS Code reste préférable :

```bash
code .
```

## 12. Rechercher

### `grep`

Chercher du texte :

```bash
grep "error" application.log
```

Sans respecter majuscules/minuscules :

```bash
grep -i "error" application.log
```

Récursivement dans un dossier :

```bash
grep -R "TODO" .
```

### `find`

Trouver des fichiers :

```bash
find . -name "*.tf"
```

Trouver des scripts shell :

```bash
find ~/projects -type f -name "*.sh"
```

## 13. Permissions Linux

Afficher les permissions :

```bash
ls -l
```

Exemple :

```text
-rwxr-xr-x
```

Les trois groupes représentent :

```text
user | group | others
```

et les lettres :

```text
r = read
w = write
x = execute
```

Rendre un script exécutable :

```bash
chmod +x script.sh
```

Puis :

```bash
./script.sh
```

Changer le propriétaire :

```bash
sudo chown utilisateur:utilisateur fichier
```

Ne fais pas de :

```bash
chmod -R 777 ...
```

pour résoudre un problème de permissions sans comprendre la cause.

## 14. Informations système Linux

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
```

Mémoire :

```bash
free -h
```

Disques / systèmes de fichiers :

```bash
df -h
```

Taille d'un dossier :

```bash
du -sh ~/projects
```

Dossiers les plus lourds :

```bash
du -h --max-depth=1 ~ | sort -h
```

## 15. Processus

Lister les processus :

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

Trouver un processus par nom :

```bash
pgrep -a dockerd
```

Arrêter proprement un processus :

```bash
kill PID
```

Forcer en dernier recours :

```bash
kill -9 PID
```

`kill -9` ne doit pas être ton premier réflexe : il empêche le processus de se fermer proprement.

## 16. Réseau Linux

Interfaces et IP :

```bash
ip addr
```

Routes :

```bash
ip route
```

Tester une résolution DNS :

```bash
getent hosts github.com
```

Tester la connectivité :

```bash
ping -c 4 github.com
```

Tester HTTP :

```bash
curl -I https://github.com
```

Ports en écoute :

```bash
ss -lntup
```

## 17. Comprendre les pipes `|`

Le pipe envoie la sortie d'une commande vers une autre.

Exemple :

```bash
ps aux | grep terraform
```

Étape 1 :

```bash
ps aux
```

produit la liste des processus.

Étape 2 :

```bash
grep terraform
```

filtre les lignes contenant `terraform`.

Autre exemple :

```bash
systemctl list-units --type=service | grep docker
```

## 18. Redirections `>` et `>>`

Écraser/créer un fichier :

```bash
echo "bonjour" > test.txt
```

Ajouter à la fin :

```bash
echo "deuxieme ligne" >> test.txt
```

Attention :

```text
>  écrase
>> ajoute
```

## 19. Variables d'environnement

Afficher :

```bash
echo "$HOME"
```

Créer temporairement :

```bash
export DEMO=value
```

Lire :

```bash
echo "$DEMO"
```

Lister l'environnement :

```bash
env
```

Ne stocke jamais des secrets AWS, tokens GitHub ou mots de passe directement dans un dépôt Git.

## 20. `PATH`

`PATH` contient les dossiers dans lesquels Linux cherche les commandes.

Afficher :

```bash
echo "$PATH"
```

Trouver une commande :

```bash
command -v terraform
```

ou :

```bash
which terraform
```

Voir le type d'une commande :

```bash
type kubectl
```

## 21. Git — débuter dans WSL

Vérifier :

```bash
git --version
```

Configurer ton nom :

```bash
git config --global user.name "Ton Nom"
```

Configurer ton adresse Git :

```bash
git config --global user.email "ton-adresse@example.com"
```

Voir la configuration :

```bash
git config --global --list
```

Cloner dans le système Linux :

```bash
cd ~/projects
git clone <URL_DU_DEPOT>
```

Statut :

```bash
git status
```

Le profil ajoute :

```bash
gst
```

comme alias de statut court.

## 22. Ouvrir un projet avec VS Code

Depuis WSL :

```bash
cd ~/projects/mon-projet
code .
```

VS Code Windows ouvre alors le dossier **dans le contexte WSL**.

C'est le comportement recherché.

Dans VS Code, vérifie en bas à gauche que la fenêtre indique un contexte WSL/Ubuntu.

Les extensions DevOps importantes sont installées dans l'hôte WSL afin qu'elles voient les binaires Linux :

```text
terraform
kubectl
docker
shellcheck
```

## 23. Accéder à Linux depuis l'Explorateur Windows

Depuis WSL :

```bash
explorer.exe .
```

Cela ouvre le dossier Linux courant dans l'Explorateur.

Tu peux aussi saisir :

```text
\\wsl$\Ubuntu\home\<user>
```

ou selon les versions :

```text
\\wsl.localhost\Ubuntu\home\<user>
```

Évite de modifier le fichier `ext4.vhdx` directement.

## 24. Accéder aux disques Windows depuis Linux

Windows `C:` apparaît dans :

```text
/mnt/c
```

Windows `D:` apparaît dans :

```text
/mnt/d
```

Exemple :

```bash
ls /mnt/d
```

C'est utile pour échanger des fichiers.

Ce n'est **pas** l'emplacement conseillé pour les dépôts Docker/Terraform utilisés intensivement depuis Linux.

## 25. Exécuter une commande Windows depuis WSL

Windows et Linux sont interopérables.

Depuis Ubuntu :

```bash
notepad.exe fichier.txt
```

```bash
explorer.exe .
```

```bash
powershell.exe -Command "Get-Date"
```

Tu peux aussi appeler :

```bash
ipconfig.exe
```

## 26. Exécuter Linux depuis PowerShell

Depuis PowerShell :

```powershell
wsl ls -la
```

Commande dans Ubuntu :

```powershell
wsl -d Ubuntu -- uname -a
```

Exécuter via Bash :

```powershell
wsl -d Ubuntu -- bash -lc "cd ~/projects && pwd && ls -la"
```

Cette technique est très utile pour l'automatisation Windows → Linux.

## 27. Commandes WSL de base — côté PowerShell

### Aide

```powershell
wsl --help
```

### Version

```powershell
wsl --version
```

### État

```powershell
wsl --status
```

### Distributions installées

```powershell
wsl -l -v
```

### Distributions disponibles en ligne

```powershell
wsl --list --online
```

### Lancer Ubuntu

```powershell
wsl -d Ubuntu
```

### Lancer directement dans le HOME

```powershell
wsl ~
```

### Définir Ubuntu par défaut

```powershell
wsl --set-default Ubuntu
```

### Mettre WSL à jour

```powershell
wsl --update
```

## 28. Arrêter WSL correctement

Arrêter **toutes** les distributions et la VM WSL2 :

```powershell
wsl --shutdown
```

C'est nécessaire après certaines modifications de `.wslconfig`.

Arrêter uniquement Ubuntu :

```powershell
wsl --terminate Ubuntu
```

ou :

```powershell
wsl -t Ubuntu
```

Voir ensuite :

```powershell
wsl -l -v
```

## 29. `.wslconfig` — configuration globale WSL2

Le fichier Windows :

```text
%USERPROFILE%\.wslconfig
```

configure globalement la VM WSL2.

Profil quotidien du dépôt :

```ini
[wsl2]
memory=16GB
processors=6
swap=8GB
networkingMode=mirrored
dnsTunneling=true
firewall=true
autoProxy=true

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
```

### `memory=16GB`

WSL peut utiliser jusqu'à 16 Go de RAM pour le profil quotidien.

Ce n'est pas 16 Go réservés en permanence.

### `processors=6`

WSL voit jusqu'à 6 processeurs logiques pour le profil quotidien.

### `swap=8GB`

Un espace de swap Linux de 8 Go est disponible si la mémoire devient insuffisante.

### `networkingMode=mirrored`

WSL utilise le mode réseau miroir de Windows 11.

Il simplifie notamment `localhost`, IPv6 et certains scénarios VPN.

### `dnsTunneling=true`

Les requêtes DNS WSL passent par le mécanisme de tunneling WSL/Windows.

### `autoMemoryReclaim=gradual`

WSL restitue progressivement à Windows de la mémoire utilisée comme cache Linux.

### `sparseVhd=true`

Les nouveaux VHD WSL sont configurés pour une gestion dynamique/sparse de l'espace.

Après modification :

```powershell
wsl --shutdown
```

puis relancer Ubuntu.

## 30. Profils WSL du dépôt

### Standard

```text
6 CPU
16 Go RAM
8 Go swap
mirrored networking
```

Usage :

```text
travail quotidien
Terraform
Docker
petits clusters
Ansible
Git
```

### Lab-heavy

```text
10 CPU
24 Go RAM
12 Go swap
```

Usage :

```text
Minikube lourd
kind multi-node
plusieurs conteneurs
labs Kubernetes
```

### NAT fallback

Ressources proches du profil standard, mais :

```text
networkingMode=nat
```

À utiliser uniquement si un VPN ou une contrainte réseau particulière pose problème avec `mirrored`.

Changer de profil :

```powershell
.\scripts\wsl\switch-profile.ps1 -Profile lab-heavy
```

Puis :

```powershell
wsl --shutdown
```

## 31. `/etc/wsl.conf` — configuration de la distribution

Contrairement à `.wslconfig`, ce fichier se trouve **dans Linux** :

```text
/etc/wsl.conf
```

Le dépôt l'utilise notamment pour systemd et l'interop.

Différence :

```text
.wslconfig
└── Windows
    └── réglages globaux de la VM WSL2

/etc/wsl.conf
└── Ubuntu
    └── réglages propres à cette distribution
```

## 32. systemd

`systemd` est le gestionnaire de services Linux moderne.

Avec systemd, tu peux gérer Docker comme sur un serveur Linux classique.

État global :

```bash
systemctl status
```

État Docker :

```bash
systemctl status docker
```

Démarrer :

```bash
sudo systemctl start docker
```

Arrêter :

```bash
sudo systemctl stop docker
```

Redémarrer :

```bash
sudo systemctl restart docker
```

Activer au démarrage :

```bash
sudo systemctl enable docker
```

Voir les services :

```bash
systemctl list-units --type=service
```

Voir les services installés :

```bash
systemctl list-unit-files --type=service
```

## 33. Logs systemd avec `journalctl`

Logs Docker :

```bash
journalctl -u docker
```

Dernières lignes :

```bash
journalctl -u docker -n 100
```

Suivre en direct :

```bash
journalctl -u docker -f
```

Depuis le dernier boot :

```bash
journalctl -b
```

Erreurs importantes du boot :

```bash
journalctl -b -p err
```

## 34. Docker dans WSL2

Dans cette architecture :

```text
Docker Desktop = non requis
Docker Engine  = installé directement dans Ubuntu
```

Vérifier :

```bash
docker --version
```

```bash
docker compose version
```

```bash
systemctl is-active docker
```

Tester :

```bash
docker run --rm hello-world
```

Lister les conteneurs :

```bash
docker ps
```

Tous les conteneurs :

```bash
docker ps -a
```

Images :

```bash
docker images
```

Espace Docker :

```bash
docker system df
```

### Nettoyage

Voir d'abord :

```bash
docker system df
```

Puis seulement si tu sais ce qui est inutile :

```bash
docker image prune
```

Évite de lancer :

```bash
docker system prune -a
```

sans avoir vérifié ce qui va être supprimé.

## 35. Kubernetes — premières commandes

Client :

```bash
kubectl version --client
```

Contexte courant :

```bash
kubectl config current-context
```

Contextes :

```bash
kubectl config get-contexts
```

Pods :

```bash
kubectl get pods -A
```

Services :

```bash
kubectl get svc -A
```

Nœuds :

```bash
kubectl get nodes
```

Détails d'une ressource :

```bash
kubectl describe pod <nom> -n <namespace>
```

Logs :

```bash
kubectl logs <pod> -n <namespace>
```

## 36. Minikube / kind

Minikube :

```bash
minikube status
```

Démarrer :

```bash
minikube start
```

Arrêter :

```bash
minikube stop
```

Supprimer un cluster Minikube :

```bash
minikube delete
```

`delete` détruit le cluster local : vérifier avant exécution.

kind :

```bash
kind get clusters
```

## 37. Terraform — commandes de base

Version :

```bash
terraform version
```

Initialiser un projet :

```bash
terraform init
```

Formater :

```bash
terraform fmt -recursive
```

Valider :

```bash
terraform validate
```

Prévisualiser :

```bash
terraform plan
```

Appliquer :

```bash
terraform apply
```

`terraform apply` peut créer/modifier des ressources cloud payantes. Toujours lire le plan.

Détruire :

```bash
terraform destroy
```

`destroy` est destructif : ne jamais le lancer par automatisme.

## 38. Ansible

Version :

```bash
ansible --version
```

Tester localhost :

```bash
ansible localhost -m ping
```

Lister un inventaire :

```bash
ansible-inventory -i inventory.ini --list
```

Vérifier la syntaxe d'un playbook :

```bash
ansible-playbook playbook.yml --syntax-check
```

## 39. Outils qualité présents

Vérifier :

```bash
shellcheck --version
shfmt --version
terraform-docs --version
actionlint --version
yq --version
tflint --version
trivy --version
```

Utilité :

```text
ShellCheck       qualité Bash
shfmt            formatage shell
terraform-docs   documentation Terraform
actionlint       validation GitHub Actions
yq               manipulation YAML
tflint            lint Terraform
Trivy            analyse sécurité
```

## 40. Réseau WSL2 mirrored

La configuration cible utilise :

```ini
networkingMode=mirrored
```

Dans ce mode, Windows 11 et WSL coopèrent plus directement sur le réseau.

Cas courant : une application écoute dans WSL sur le port 8080.

Exemple :

```bash
python3 -m http.server 8080
```

Depuis Windows, tester :

```text
http://localhost:8080
```

### Vérifier les ports Linux

```bash
ss -lntp
```

### IP WSL

Depuis PowerShell :

```powershell
wsl -d Ubuntu hostname -I
```

### IP / routes depuis Linux

```bash
ip addr
ip route
```

## 41. DNS

Tester :

```bash
getent hosts github.com
```

Puis :

```bash
curl -I https://github.com
```

Si DNS échoue :

1. vérifier Internet côté Windows ;
2. vérifier le VPN ;
3. `wsl --shutdown` ;
4. relancer ;
5. comparer `mirrored` avec le profil `nat-fallback` si nécessaire.

Ne commence pas par modifier `/etc/resolv.conf` au hasard.

## 42. Sauvegarder WSL — règle essentielle

Le fichier VHDX sur D: n'est pas une vraie sauvegarde s'il reste sur le même SSD.

Deux niveaux :

```text
VHDX de travail  -> D:\WSL\...
backup/export    -> autre disque / stockage externe / autre machine
```

### Export TAR

Dans PowerShell :

```powershell
wsl --shutdown
wsl --export Ubuntu D:\Backups\Ubuntu-DevOps.tar
```

### Export VHD

WSL2 permet aussi un export VHD/VHDX selon la version :

```powershell
wsl --export Ubuntu D:\Backups\Ubuntu-DevOps.vhdx --vhd
```

Sur les versions récentes, la syntaxe de format peut également être exposée par `wsl --help`. Toujours vérifier l'aide locale avant un workflow de restauration critique.

### Vérifier le fichier

```powershell
Get-Item D:\Backups\Ubuntu-DevOps.tar
```

Ne supprime jamais une distribution tant que l'export n'est pas présent et vérifié.

## 43. Restaurer / importer

Importer un TAR :

```powershell
wsl --import Ubuntu-Restore D:\WSL\Ubuntu-Restore D:\Backups\Ubuntu-DevOps.tar --version 2
```

Lister :

```powershell
wsl -l -v
```

Tester la nouvelle distribution **avant** de supprimer l'ancienne.

## 44. `wsl --unregister` — commande dangereuse

```powershell
wsl --unregister Ubuntu
```

Cette commande supprime l'enregistrement de la distribution et ses données associées.

Considère-la comme destructive.

Avant toute utilisation :

```text
1. wsl --shutdown
2. export vérifié
3. copie de sauvegarde hors du SSD de travail
4. seulement ensuite unregister si réellement nécessaire
```

## 45. Espace disque WSL2

Dans Ubuntu :

```bash
df -h /
```

Taille des dossiers :

```bash
sudo du -xhd1 / | sort -h
```

HOME :

```bash
du -h --max-depth=1 ~ | sort -h
```

Docker :

```bash
docker system df
```

APT cache :

```bash
du -sh /var/cache/apt
```

Nettoyage APT raisonnable :

```bash
sudo apt clean
```

Ne supprime jamais manuellement des fichiers dans `/var/lib/docker`.

## 46. Comprendre la croissance du VHDX

Quand Linux écrit des données :

```text
ext4.vhdx grossit
```

Supprimer des fichiers dans Linux libère de l'espace **dans ext4**, mais le fichier VHDX Windows ne rétrécit pas forcément immédiatement de la même quantité.

Le profil utilise :

```ini
sparseVhd=true
```

pour améliorer la gestion dynamique sur les VHD compatibles.

Avant toute opération avancée de compaction/réparation, faire un export de sauvegarde.

## 47. Vérifier WSL après un problème

PowerShell :

```powershell
wsl --status
wsl --version
wsl -l -v
```

Puis :

```powershell
wsl --shutdown
```

Relancer Ubuntu.

Dans Linux :

```bash
uname -a
free -h
df -h
systemctl --failed
journalctl -b -p err
```

## 48. Docker ne démarre pas

```bash
systemctl status docker
```

Puis :

```bash
journalctl -u docker -n 100 --no-pager
```

Essayer :

```bash
sudo systemctl restart docker
```

Vérifier :

```bash
docker info
```

Si `docker` fonctionne seulement avec `sudo`, vérifier les groupes :

```bash
groups
```

Après ajout au groupe docker, il peut être nécessaire de fermer WSL :

```powershell
wsl --shutdown
```

## 49. `code` n'est pas trouvé dans WSL

Vérifier :

```bash
command -v code
```

Puis :

1. vérifier VS Code côté Windows ;
2. vérifier l'extension WSL ;
3. fermer/réouvrir WezTerm ;
4. au besoin `wsl --shutdown`.

Le script de qualification DevOps vérifie aussi les extensions côté hôte WSL.

## 50. Problèmes de droits dans un projet

Voir :

```bash
ls -la
```

Voir le propriétaire :

```bash
stat fichier
```

Évite de faire :

```bash
sudo git ...
sudo code ...
sudo docker ...
```

pour contourner les permissions.

Les fichiers de `~/projects` doivent normalement appartenir à ton utilisateur Linux.

## 51. Différence entre `sudo` et PowerShell administrateur

Ce sont **deux niveaux différents**.

```text
PowerShell Administrateur
└── privilèges Windows

sudo
└── privilèges Linux dans Ubuntu
```

Être administrateur Windows ne signifie pas être root Linux.

Être root Linux ne signifie pas être administrateur Windows.

## 52. Commandes WSL avancées utiles

### Lancer avec un utilisateur précis

```powershell
wsl -d Ubuntu --user root
```

À utiliser uniquement pour maintenance ciblée.

### Exécuter une commande root sans session interactive

```powershell
wsl -d Ubuntu --user root -- cat /etc/wsl.conf
```

### Exécuter plusieurs commandes

```powershell
wsl -d Ubuntu -- bash -lc "cd ~/projects && git status"
```

### Arrêter une seule distribution

```powershell
wsl -t Ubuntu
```

### Définir la version par défaut pour les nouvelles distributions

```powershell
wsl --set-default-version 2
```

### Convertir une distribution existante

```powershell
wsl --set-version Ubuntu 2
```

Dans ce projet Ubuntu doit déjà être en WSL2 ; cette commande sert surtout au diagnostic/migration.

## 53. Interop et chemins avec `wslpath`

Convertir un chemin Windows vers Linux :

```bash
wslpath 'D:\DATA\demo.txt'
```

Résultat typique :

```text
/mnt/d/DATA/demo.txt
```

Convertir un chemin Linux vers Windows :

```bash
wslpath -w ~/projects
```

Très utile dans les scripts hybrides.

## 54. Routine quotidienne recommandée

Démarrage :

```bash
cd ~/projects
```

Vérifications rapides :

```bash
git --version
docker info >/dev/null && echo "Docker OK"
kubectl version --client
terraform version
```

Entrer dans un projet :

```bash
cd ~/projects/mon-projet
```

Ouvrir VS Code :

```bash
code .
```

En fin de journée, inutile de faire `wsl --shutdown` systématiquement. WSL gère son cycle de vie. Utilise `--shutdown` après une modification de configuration, pour libérer immédiatement la VM, ou pour un diagnostic.

## 55. Routine de maintenance

Périodiquement :

Windows :

```powershell
wsl --update
```

Ubuntu :

```bash
sudo apt update
sudo apt upgrade
```

Docker :

```bash
docker system df
```

Disque Linux :

```bash
df -h /
```

Logs système en erreur :

```bash
systemctl --failed
```

## 56. Ce qu'il ne faut pas faire

Évite :

```text
- travailler quotidiennement en root ;
- placer les projets Docker lourds sous /mnt/c ou /mnt/d ;
- modifier ext4.vhdx à la main ;
- lancer wsl --unregister sans export ;
- exécuter rm -rf sans vérifier le chemin ;
- faire chmod -R 777 pour "réparer" des permissions ;
- stocker des tokens dans Git ;
- nettoyer /var/lib/docker manuellement ;
- modifier DNS, kernel ou réseau avant d'avoir diagnostiqué le problème ;
- copier des commandes sudo inconnues depuis Internet ;
- installer Docker Desktop en plus du Docker Engine WSL sans raison précise.
```

## 57. Exercices pour prendre en main WSL2

### Exercice 1 — navigation

```bash
cd ~
mkdir -p labs/wsl-debutant
cd labs/wsl-debutant
pwd
ls -la
```

### Exercice 2 — fichier

```bash
echo "Bonjour WSL2" > hello.txt
cat hello.txt
```

### Exercice 3 — recherche

```bash
echo "Terraform" >> hello.txt
grep -i terraform hello.txt
```

### Exercice 4 — script Bash

```bash
cat > hello.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "Utilisateur: $(whoami)"
echo "Dossier: $(pwd)"
echo "Kernel: $(uname -r)"
EOF

chmod +x hello.sh
./hello.sh
```

### Exercice 5 — interop Windows

```bash
explorer.exe .
```

Puis :

```bash
notepad.exe hello.txt
```

### Exercice 6 — VS Code

```bash
code .
```

### Exercice 7 — systemd

```bash
systemctl status docker --no-pager
```

### Exercice 8 — Docker

```bash
docker run --rm hello-world
```

Après ces exercices, supprimer uniquement le lab :

```bash
cd ~
rm -r ~/labs/wsl-debutant
```

Vérifie le chemin avant `rm`.

## 58. Mini antisèche Linux

| Besoin | Commande |
|---|---|
| Où suis-je ? | `pwd` |
| Lister | `ls -la` |
| Changer de dossier | `cd dossier` |
| HOME | `cd ~` |
| Créer dossier | `mkdir -p dossier` |
| Copier | `cp` |
| Déplacer/renommer | `mv` |
| Supprimer fichier | `rm fichier` |
| Lire | `cat`, `less` |
| Chercher texte | `grep` |
| Chercher fichier | `find` |
| Espace disque | `df -h` |
| Taille dossier | `du -sh dossier` |
| RAM | `free -h` |
| Processus | `ps aux`, `top` |
| Réseau | `ip addr`, `ip route` |
| Ports | `ss -lntup` |
| Paquets | `apt` |
| Service | `systemctl` |
| Logs service | `journalctl` |
| Utilisateur | `whoami`, `id` |
| Rendre exécutable | `chmod +x` |

## 59. Mini antisèche WSL — PowerShell

| Besoin | Commande |
|---|---|
| Version WSL | `wsl --version` |
| État | `wsl --status` |
| Distros | `wsl -l -v` |
| Lancer Ubuntu | `wsl -d Ubuntu` |
| HOME Linux | `wsl ~` |
| Mise à jour WSL | `wsl --update` |
| Arrêter Ubuntu | `wsl -t Ubuntu` |
| Arrêter tout WSL | `wsl --shutdown` |
| Distro par défaut | `wsl --set-default Ubuntu` |
| Commande Linux | `wsl -d Ubuntu -- <commande>` |
| Export | `wsl --export Ubuntu <fichier>` |
| Import | `wsl --import ...` |
| Aide | `wsl --help` |

## 60. Ordre d'apprentissage conseillé

Ne cherche pas à tout retenir immédiatement.

### Niveau 1

Maîtriser :

```text
pwd
ls
cd
mkdir
cp
mv
rm
cat
nano
sudo
apt
```

### Niveau 2

Ajouter :

```text
grep
find
chmod
ps
kill
free
df
du
ip
ss
curl
```

### Niveau 3

Ajouter :

```text
systemctl
journalctl
pipes
redirections
variables PATH
Git
Docker
```

### Niveau 4 DevOps

Puis :

```text
Terraform
Ansible
kubectl
Helm
Minikube/kind
CI/CD
observabilité
sécurité
```

Le but n'est pas de mémoriser chaque option. Le but est de comprendre **où tu te trouves, quel système exécute la commande, quels fichiers elle touche et si elle est destructive**.

## 61. Qualification du dépôt

Après installation complète :

```powershell
.\install.ps1 -Mode Verify -ValidateDevOps
```

Verdicts attendus :

```text
VERDICT: V3 WINDOWS READY
VERDICT: V3 DEVOPS READY
VERDICT: V4 WINDOWS OPTIMIZATION READY
```

La V5 matériel ajoute sa propre qualification séparée.

## 62. Références officielles utilisées

Ce guide est aligné sur la documentation Microsoft WSL actuelle, notamment :

- installation de WSL ;
- commandes WSL de base ;
- bonnes pratiques d'environnement de développement ;
- travail entre systèmes de fichiers Windows/Linux ;
- configuration `.wslconfig` / `wsl.conf` ;
- systemd sous WSL ;
- réseau WSL et mode mirrored ;
- gestion de l'espace disque WSL ;
- import/export et sauvegarde des distributions.
