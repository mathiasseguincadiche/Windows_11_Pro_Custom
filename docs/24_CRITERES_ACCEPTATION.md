# Critères d'acceptation — quand le projet est réellement terminé

Cette page transforme le résultat attendu de `Windows_11_Pro_Custom` en **critères de validation concrets**.

Elle ne remplace pas [`11_VALIDATION.md`](11_VALIDATION.md), qui explique les mécanismes de preuve, ni [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md), qui décrit l'ordre d'exécution.

> Le projet n'est pas terminé parce qu'une installation a été lancée. Il est terminé lorsque l'état réel final est conforme, vérifié, explicable et récupérable.

---

## 1. Dépôt et orchestration

- [ ] le dépôt utilisé correspond à la branche/révision volontairement choisie ;
- [ ] `install.ps1 -Mode Audit` s'exécute et produit des preuves exploitables ;
- [ ] le plan du périmètre choisi peut être calculé avec `-PlanOnly` ;
- [ ] les composants déjà conformes sont identifiés comme tels ;
- [ ] les actions humaines nécessaires sont explicitement signalées ;
- [ ] les erreurs ne sont pas masquées par un faux verdict positif ;
- [ ] une seconde planification après convergence ne repropose pas inutilement les mêmes modifications.

Preuves principales :

```text
logs\runs\<RunId>\summary.json
reports\orchestration\latest-run.json
```

---

## 2. Windows 11 Pro

- [ ] Windows 11 Pro est l'hôte réel de la workstation ;
- [ ] Windows Update reste disponible ;
- [ ] Microsoft Defender respecte la politique du projet ;
- [ ] PowerShell 7 est disponible ;
- [ ] les applications automatisables attendues sont conformes ;
- [ ] OneDrive correspond à la baseline définie par le dépôt ;
- [ ] les réglages Windows gérés passent leur validation.

---

## 3. Matériel

- [ ] AMD Ryzen 7 7700 détecté conformément au contrat ;
- [ ] la mémoire disponible respecte le minimum attendu ;
- [ ] la MSI MAG B850M Mortar WiFi est correctement identifiée ;
- [ ] l'Intel Arc B580 est détectée avec un pilote ;
- [ ] les deux Crucial T705 sont présents et sains ;
- [ ] le système utilise GPT/UEFI ;
- [ ] Secure Boot est actif ;
- [ ] TPM est disponible ;
- [ ] la virtualisation firmware est disponible ;
- [ ] les preuves manuelles demandées par la qualification matérielle sont renseignées ;
- [ ] les réglages matériels expérimentaux ne sont pas supposés conformes sans preuve de stabilité.

Validation :

```powershell
.\install.ps1 -Mode Verify -ValidateHardware
```

---

## 4. Stockage

- [ ] `C:` contient Windows et le système ;
- [ ] `D:` est le volume de données/WSL attendu ;
- [ ] `D:` reste NTFS ;
- [ ] le stockage WSL est sous `D:\WSL\Ubuntu-DevOps` ;
- [ ] le swap WSL utilise l'emplacement prévu par le profil ;
- [ ] le filesystem Linux est fourni par le VHDX WSL2 ;
- [ ] le support de sauvegarde de référence est distinct des deux SSD internes.

---

## 5. WSL2

- [ ] la distribution s'appelle `Ubuntu` ;
- [ ] elle fonctionne en WSL2 ;
- [ ] la release est Ubuntu 26.04 / `resolute` ;
- [ ] l'emplacement correspond au contrat ;
- [ ] le profil `.wslconfig` correspond au profil demandé ;
- [ ] le profil standard expose les ressources attendues ;
- [ ] systemd fonctionne ;
- [ ] le HOME utilisateur se trouve sur le filesystem Linux ;
- [ ] `~/projects`, `~/labs` et `~/repositories` sont les racines de travail DevOps ;
- [ ] `/mnt/c` et `/mnt/d` ne sont pas utilisés comme racines quotidiennes des projets Linux.

Validation :

```powershell
.\install.ps1 -Mode Verify -ValidateWsl
```

---

## 6. Stack DevOps

- [ ] Docker Engine est disponible ;
- [ ] Docker Compose est disponible ;
- [ ] Buildx est disponible ;
- [ ] kubectl est conforme ;
- [ ] Helm est conforme ;
- [ ] Minikube est conforme ;
- [ ] kind est conforme ;
- [ ] Terraform est conforme ;
- [ ] Ansible est disponible ;
- [ ] AWS CLI est conforme ;
- [ ] GitHub CLI est disponible ;
- [ ] Trivy et les outils qualité attendus sont disponibles ;
- [ ] les outils épinglés correspondent à `config/devops/tool-versions.env`.

Validation :

```powershell
.\install.ps1 -Mode Verify -ValidateDevOps
```

---

## 7. WezTerm et VS Code

### WezTerm

- [ ] WezTerm est disponible ;
- [ ] `%USERPROFILE%\.wezterm.lua` correspond à la configuration versionnée ;
- [ ] `Ubuntu DevOps (WSL2)` est le profil par défaut ;
- [ ] `PowerShell 7` reste disponible comme contexte Windows ;
- [ ] `OpenClaw / clawops (Windows)` est présent comme contexte IA Windows-native ;
- [ ] le profil OpenClaw prépare uniquement sa session et ne remplace pas le bootstrap OpenClaw ;
- [ ] les trois profils conservent les frontières Windows/WSL2 définies par l'architecture.

Validation de la configuration terminal :

```powershell
.\install.ps1 -Mode Verify
```

### VS Code

- [ ] VS Code ouvre correctement les projets WSL ;
- [ ] les projets Linux restent sous `/home/<user>/...` ;
- [ ] le terminal et les extensions du projet utilisent le contexte Linux attendu ;
- [ ] les secrets de connexion ne sont pas versionnés dans Git.

---

## 8. Sécurité et réversibilité

- [ ] les mécanismes essentiels de Windows restent disponibles ;
- [ ] les profils gérés conservent leurs limites documentées ;
- [ ] les états initiaux utiles à la réversibilité sont conservés lorsqu'ils existent ;
- [ ] le projet ne déclare pas restaurable automatiquement un état qu'il ne sait pas reproduire.

---

## 9. Maintenance

- [ ] `update.ps1 -Mode Audit` produit un état compréhensible ;
- [ ] Windows Update, WinGet, WSL, Ubuntu, DevOps et VS Code restent des domaines distincts ;
- [ ] les catégories optionnelles restent explicitement choisies ;
- [ ] un changement majeur d'Ubuntu n'est pas assimilé à une maintenance ordinaire ;
- [ ] les versions DevOps restent pilotées par le dépôt ;
- [ ] le besoin de redémarrage reste explicite lorsqu'il existe.

---

## 10. OpenClaw/OpenRouter — uniquement si utilisé

- [ ] la racine est `D:\AI\OpenClaw` ;
- [ ] le control-plane correspond au ref approuvé par `config/openclaw/control-plane.json` ;
- [ ] les données locales du checkout sont comprises avant synchronisation ;
- [ ] OpenClaw Windows est validé ;
- [ ] `clawops` est validé ;
- [ ] le backend WSL2 DevOps associé est validé lorsque nécessaire ;
- [ ] le profil `OpenClaw / clawops (Windows)` permet d'atteindre les deux CLI ;
- [ ] les informations d'authentification OpenRouter restent hors de Git.

Validation structurée :

```powershell
.\install.ps1 -Mode Verify -ValidateOpenClawAI
```

Smoke test CLI :

```powershell
openclaw --version
clawops version
clawops platform check
```

Le smoke test ne remplace pas `-ValidateOpenClawAI`.

---

## 11. Logs et preuves

- [ ] chaque exécution importante possède un `RunId` identifiable ;
- [ ] les logs par script sont lisibles ;
- [ ] les événements NDJSON existent pour les runs concernés ;
- [ ] les rapports structurés permettent de relier état observé et verdict ;
- [ ] la documentation et les arguments journalisés ne contiennent pas volontairement de secret.

---

## 12. Idempotence

L'idempotence doit être prouvée sur **le même périmètre que celui réellement installé**.

### Core sans OpenClaw

```powershell
.\install.ps1 `
  -Mode Apply `
  -InstallDevOps `
  -ValidateWsl `
  -ValidateDevOps `
  -ValidateHardware `
  -PlanOnly
```

### Périmètre complet avec OpenClaw

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Critères :

- [ ] la majorité des composants sont `DÉJÀ OK` ;
- [ ] aucun composant ne boucle entre Apply et Verify sans cause comprise ;
- [ ] une relance ne repropose pas arbitrairement l'ensemble de la workstation ;
- [ ] la configuration WezTerm reste stable après une seconde convergence.

---

## 13. Sauvegarde et reprise

- [ ] une sauvegarde de référence existe sur un support séparé ;
- [ ] sa capacité et sa structure ont été vérifiées ;
- [ ] l'export WSL attendu est inclus dans la stratégie de protection ;
- [ ] l'état OpenClaw utile est pris en compte lorsque l'intégration est utilisée ;
- [ ] l'intégrité prévue par le projet est vérifiable ;
- [ ] un plan de reprise peut être préparé ;
- [ ] la reconstruction complète reste une procédure explicitement documentée.

Guide : [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

---

# Verdict final

Le projet peut être déclaré **prêt** lorsque les validations applicables sont réussies et que les éventuelles actions humaines obligatoires sont closes.

Qualification core :

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

Si OpenClaw fait partie du périmètre :

```powershell
.\install.ps1 -Mode Verify -ValidateOpenClawAI
```

Puis vérifier l'idempotence du périmètre choisi et la sauvegarde de référence.

Le résultat attendu n'est pas une machine « optimisée au maximum ». C'est une workstation **cohérente, performante, maintenable, reproductible et récupérable**.