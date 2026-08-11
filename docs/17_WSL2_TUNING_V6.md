# WSL2 Tuning V6 — profil matériel 48 Go / Ryzen 7 7700

## Objectif

Ce document décrit la configuration WSL2 retenue pour cette machine afin d'obtenir un comportement prévisible, performant et stable pour Docker, Kubernetes, Terraform, Ansible, Git et les outils de qualification.

Matériel concerné :

```text
CPU        AMD Ryzen 7 7700 — 8 cœurs / 16 threads
RAM        48 Go DDR5
SSD WSL    Crucial T705 PCIe 5.0 sur D:
Windows    Windows 11 Pro
Linux      Ubuntu WSL2
```

La priorité n'est pas de donner le maximum de ressources possible à WSL2. La priorité est d'éviter qu'un build, un cluster ou un cache Linux ne dégrade le poste Windows entier.

## 1. Ce que ferait WSL sans profil explicite

WSL2 dispose de valeurs par défaut dynamiques. Sur une machine avec 48 Go de RAM et 16 processeurs logiques, cela peut lui permettre d'utiliser une part importante des ressources Windows.

La V6 remplace ce comportement implicite par trois profils versionnés et contrôlés.

## 2. Profil `standard` — quotidien

Fichier :

```text
config/wsl/standard.wslconfig
```

Configuration :

```ini
[wsl2]
memory=20GB
processors=8
swap=8GB
swapFile=D:\\WSL\\swap\\wsl-swap.vhdx
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

### Pourquoi 20 Go de RAM ?

20 Go donnent une marge confortable à Docker et aux petits clusters tout en conservant environ 28 Go physiques pour Windows.

Ce profil est adapté à :

- VS Code connecté à WSL ;
- plusieurs conteneurs Docker ;
- Terraform ;
- Ansible ;
- Helm / kubectl ;
- Minikube ou kind raisonnable ;
- navigation web et applications Windows simultanées.

### Pourquoi 8 threads ?

Le Ryzen 7 7700 fournit 16 threads logiques. Le profil standard en expose 8 à WSL et en laisse 8 disponibles à Windows.

Cela évite qu'une compilation, un scan Trivy ou un build Docker lancé avec parallélisme maximum ne monopolise tout le CPU logique de la machine.

### Pourquoi 8 Go de swap ?

Le swap n'est pas utilisé comme RAM normale. Il sert de filet de sécurité lors d'un pic ponctuel.

La V6 préfère :

```text
RAM pleine
   ↓
ralentissement temporaire / swap
   ↓
processus conservé
```

plutôt que :

```text
RAM pleine
   ↓
OOM killer
   ↓
conteneur ou processus tué brutalement
```

## 3. Profil `lab-heavy` — temporaire

Fichier :

```text
config/wsl/lab-heavy.wslconfig
```

Cible :

```text
RAM          28 Go
CPU          12 threads
Swap         12 Go
Réseau       mirrored
```

À utiliser pour :

- plusieurs namespaces Kubernetes ;
- images Docker lourdes ;
- builds parallèles ;
- tests E2E ;
- scans de sécurité importants ;
- labs OpenClassrooms nécessitant davantage de pods.

Ce profil ne doit pas rester actif par défaut.

### Activer

```powershell
.\scripts\bootstrap\06_wsl.ps1 -Profile lab-heavy
wsl --shutdown
wsl -d Ubuntu
```

### Revenir au quotidien

```powershell
.\scripts\bootstrap\06_wsl.ps1 -Profile standard
wsl --shutdown
wsl -d Ubuntu
```

## 4. Profil `nat-fallback`

Même budget CPU/RAM/swap que `standard`, mais avec :

```ini
networkingMode=nat
```

Il est uniquement destiné aux cas où un VPN ou un réseau spécifique ne fonctionne pas correctement avec le mode mirrored.

## 5. Pourquoi `networkingMode=mirrored`

Le profil quotidien utilise le réseau mirrored pour rapprocher la pile réseau WSL2 du comportement de Windows.

Avantages recherchés :

- accès simplifié à `localhost` ;
- meilleure compatibilité réseau moderne ;
- comportement plus naturel avec certains VPN ;
- règles de firewall Windows/Hyper-V conservées.

La configuration conserve :

```ini
dnsTunneling=true
firewall=true
autoProxy=true
```

Aucun firewall n'est désactivé pour « simplifier » WSL.

## 6. DNS

Le DNS tunneling reste actif :

```ini
dnsTunneling=true
```

Le fichier `/etc/wsl.conf` conserve :

```ini
[network]
generateHosts=true
generateResolvConf=true
```

La V6 n'écrit donc pas un `/etc/resolv.conf` statique avec un serveur public arbitraire.

`bestEffortDnsParsing=true` est activé afin de rendre le tunneling DNS plus tolérant face à certains enregistrements ou environnements atypiques.

## 7. Loopback hôte

En mirrored :

```ini
hostAddressLoopback=true
```

permet d'utiliser également les adresses IPv4 attribuées à Windows lorsque c'est nécessaire pour certains labs réseau.

Pour le quotidien, `127.0.0.1` / `localhost` reste le choix le plus simple.

## 8. Swap dédié au second T705

Par défaut, WSL peut stocker son fichier swap sous le profil temporaire Windows.

La V6 force :

```text
D:\WSL\swap\wsl-swap.vhdx
```

Le bootstrap crée automatiquement :

```text
D:\WSL\swap\
```

Cela maintient les I/O WSL sur le SSD DATA dédié.

## 9. VHDX Ubuntu

Ubuntu reste dans :

```text
D:\WSL\Ubuntu-DevOps\
```

Le filesystem Linux est contenu dans :

```text
ext4.vhdx
```

Les dépôts DevOps doivent rester dans :

```text
/home/<user>/projects
```

et non sous :

```text
/mnt/c
/mnt/d
```

pour les workloads Linux intensifs.

## 10. Récupération mémoire

La V6 conserve :

```ini
autoMemoryReclaim=gradual
```

Après un build ou un lab, Linux peut avoir beaucoup de mémoire en cache. La récupération graduelle permet de rendre progressivement cette mémoire à Windows.

La V6 n'utilise pas `disabled`.

Elle n'impose pas non plus `dropCache` pour le profil quotidien, car une récupération immédiate et agressive peut provoquer davantage de relectures disque et réduire l'intérêt du cache Linux.

## 11. VHD sparse

```ini
sparseVhd=true
```

est conservé afin que les nouveaux VHD n'allouent pas immédiatement leur taille maximale sur le SSD.

Attention : un VHDX dynamique peut croître. Il faut surveiller l'espace libre de `D:`.

## 12. Crash dumps

```ini
maxCrashDumpCount=3
```

La machine n'a pas besoin de conserver dix dumps WSL historiques. Trois fichiers suffisent pour diagnostiquer un problème récent tout en limitant l'accumulation.

## 13. Virtualisation imbriquée

```ini
nestedVirtualization=false
```

La stack cible utilise :

- Docker Engine ;
- kind ;
- Minikube avec Docker ;
- Kubernetes ;
- Terraform ;
- Ansible.

Elle n'exige pas KVM ou Hyper-V à l'intérieur de WSL2.

Si un futur projet exige réellement de la virtualisation imbriquée, créer un profil spécifique plutôt que modifier le profil quotidien.

## 14. systemd

`/etc/wsl.conf` active :

```ini
[boot]
systemd=true
```

Vérifier :

```bash
ps -p 1 -o comm=
```

Attendu :

```text
systemd
```

Docker est donc géré comme sur un Linux moderne :

```bash
systemctl status docker
sudo systemctl restart docker
journalctl -u docker
```

## 15. Interop Windows/Linux

La V6 conserve :

```ini
[interop]
enabled=true
appendWindowsPath=true
```

C'est utile pour :

```bash
code .
explorer.exe .
notepad.exe fichier.txt
```

Il ne faut cependant pas confondre interop et stockage de travail : l'interop est activée, mais les projets Linux restent sur EXT4.

## 16. Contrôle après démarrage

### CPU

```bash
nproc
```

Standard :

```text
8
```

Lab-heavy :

```text
12
```

### Mémoire

```bash
free -h
```

### Swap

```bash
swapon --show
```

### systemd

```bash
ps -p 1 -o comm=
```

### Filesystem HOME

```bash
findmnt -T "$HOME"
```

### Docker

```bash
systemctl is-active docker
docker info
docker run --rm hello-world
```

## 17. Contrôle côté Windows

```powershell
wsl --version
wsl --status
wsl -l -v
wsl --list --running
```

Voir la consommation WSL :

```powershell
Get-Process -Name vmmemWSL -ErrorAction SilentlyContinue |
    Select-Object Name,CPU,WorkingSet64,PrivateMemorySize64
```

## 18. Le piège du `.wslconfig` non appliqué

Modifier `.wslconfig` puis fermer seulement le terminal Ubuntu ne garantit pas que la VM WSL est arrêtée.

Toujours faire :

```powershell
wsl --shutdown
```

Puis relancer :

```powershell
wsl -d Ubuntu
```

La V6 détecte ce problème en comparant les ressources réellement vues dans Linux avec le profil sélectionné.

## 19. Validation V6

```powershell
.\install.ps1 -Mode Verify -ValidateWsl
```

Contrôles :

```text
.wslconfig                 hash exact
WSL                        version accessible
Ubuntu                     WSL version 2
CPU Linux                  conforme au profil
RAM Linux                  conforme au profil
swap Linux                 conforme au profil
PID 1                      systemd
HOME                       ext4
~/projects                 présent
PowerShell Windows         >= 7
```

Verdict :

```text
VERDICT: V6 WSL2 PLATFORM READY
```

Rapport :

```text
reports/wsl/validation-v6.json
```

## 20. Qualification complète DevOps

```powershell
.\install.ps1 -Mode Verify -ValidateWsl -ValidateDevOps
```

Le validateur Linux vérifie ensuite Docker, Compose, kubectl, Helm, Terraform, AWS CLI, Ansible, GitHub CLI, Trivy, ShellCheck, shfmt, Minikube, kind et les outils IaC.

## 21. Quand arrêter complètement WSL

Avant :

- une grosse session gaming ;
- un benchmark GPU ;
- une mise à jour BIOS ;
- certaines opérations de sauvegarde VHDX ;
- une modification `.wslconfig`.

Utiliser :

```powershell
wsl --shutdown
```

## 22. Diagnostic si WSL consomme trop de RAM

Dans Ubuntu :

```bash
free -h
docker stats --no-stream
docker system df
ps aux --sort=-%mem | head -20
```

Puis :

```bash
docker ps
```

Arrêter ce qui n'est plus nécessaire.

Ne pas « résoudre » le problème en mettant `swap=0` ou en limitant WSL à quelques Go : cela masque le workload au lieu de le gérer.

## 23. Diagnostic CPU

```bash
top
```

ou :

```bash
ps aux --sort=-%cpu | head -20
```

Docker :

```bash
docker stats
```

## 24. Diagnostic espace disque

```bash
df -h /
du -sh ~/projects/* 2>/dev/null | sort -h
docker system df
```

Nettoyage Docker contrôlé :

```bash
docker image prune
```

Ne pas lancer automatiquement :

```bash
docker system prune -a --volumes
```

car cette commande peut supprimer des données nécessaires.

## 25. Sauvegarde avant manipulation du VHDX

Dans PowerShell :

```powershell
wsl --shutdown
wsl --export Ubuntu D:\Backups\Ubuntu-DevOps.tar
```

Vérifier l'archive avant toute opération destructive.

## 26. Règle quotidienne

```text
Début de journée
    ↓
WezTerm / Ubuntu
    ↓
cd ~/projects
    ↓
Docker / Terraform / kubectl / Ansible

Fin d'un gros lab
    ↓
arrêter les ressources inutiles
    ↓
revenir au profil standard si lab-heavy

Gaming ou maintenance
    ↓
wsl --shutdown
```

## 27. Réglage final recommandé

Le profil `standard` est la référence quotidienne :

```text
20 Go RAM
8 threads
8 Go swap sur D:
mirrored networking
DNS tunneling
firewall actif
autoMemoryReclaim gradual
VHD sparse
systemd
EXT4 pour les projets
```

Le profil `lab-heavy` est un outil temporaire, pas une valeur par défaut.
