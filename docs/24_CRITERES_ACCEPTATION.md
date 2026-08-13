# Critères d’acceptation — quand le projet est réellement terminé

Cette page transforme le résultat attendu du projet en **critères de validation concrets**.

Elle ne remplace pas [`11_VALIDATION.md`](11_VALIDATION.md), qui explique les mécanismes de preuve, ni [`20_RUNBOOK_OPERATIONNEL.md`](20_RUNBOOK_OPERATIONNEL.md), qui décrit l’ordre d’exécution.

Le principe est :

> Le projet n’est pas terminé parce qu’une installation a été lancée. Il est terminé lorsque l’état réel final est conforme, vérifié, explicable et récupérable.

---

## 1. Dépôt et orchestration

- [ ] le dépôt utilisé correspond à la branche/révision volontairement choisie ;
- [ ] `install.ps1 -Mode Audit` s’exécute et produit des preuves exploitables ;
- [ ] le plan complet peut être calculé avec `-PlanOnly` ;
- [ ] les composants déjà conformes sont identifiés comme tels ;
- [ ] les actions humaines nécessaires sont explicitement signalées ;
- [ ] les erreurs ne sont pas masquées par un faux verdict positif ;
- [ ] une seconde planification après convergence ne repropose pas inutilement les mêmes modifications.

### Preuve attendue

```text
logs\runs\<RunId>\summary.json
reports\orchestration\latest-run.json
```

---

## 2. Windows 11 Pro

- [ ] Windows 11 Pro est l’hôte réel de la workstation ;
- [ ] Windows Update reste disponible ;
- [ ] Microsoft Defender reste actif selon la politique du projet ;
- [ ] le firewall n’est pas désactivé pour faire fonctionner WSL ou les outils DevOps ;
- [ ] PowerShell 7 est disponible ;
- [ ] les applications automatisables attendues sont conformes ;
- [ ] OneDrive correspond à la baseline définie par le dépôt ;
- [ ] les réglages Windows gérés passent leur validation.

---

## 3. Matériel

- [ ] AMD Ryzen 7 7700 détecté conformément au contrat ;
- [ ] la mémoire disponible respecte le minimum attendu ;
- [ ] la MSI MAG B850M Mortar WiFi est correctement identifiée ;
- [ ] l’Intel Arc B580 est détectée avec un pilote ;
- [ ] les deux Crucial T705 sont présents et sains ;
- [ ] le système utilise GPT/UEFI ;
- [ ] Secure Boot est actif ;
- [ ] TPM est disponible ;
- [ ] la virtualisation firmware est disponible ;
- [ ] les preuves manuelles demandées par la qualification matérielle sont renseignées ;
- [ ] les réglages matériels expérimentaux ne sont pas supposés conformes sans preuve de stabilité.

Validation principale :

```powershell
.\install.ps1 -Mode Verify -ValidateHardware
```

---

## 4. Stockage

- [ ] `C:` contient Windows et le système ;
- [ ] `D:` est le volume de données/WSL attendu ;
- [ ] `D:` reste NTFS ;
- [ ] le stockage WSL est sous `D:\WSL\Ubuntu-DevOps` ;
- [ ] le swap WSL utilise l’emplacement prévu par le profil ;
- [ ] aucune partition EXT4 physique n’est nécessaire pour satisfaire le projet ;
- [ ] le support de sauvegarde de référence est distinct des deux SSD internes.

---

## 5. WSL2

- [ ] la distribution s’appelle `Ubuntu` ;
- [ ] elle fonctionne en WSL2 ;
- [ ] la release est Ubuntu 26.04 / `resolute` ;
- [ ] l’emplacement correspond au contrat ;
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

## 7. Terminal et VS Code

- [ ] WezTerm est disponible ;
- [ ] Ubuntu/Bash est l’environnement DevOps principal dans le terminal ;
- [ ] PowerShell 7 reste accessible pour Windows ;
- [ ] VS Code ouvre correctement les projets WSL ;
- [ ] les extensions Windows et WSL restent séparées lorsque nécessaire ;
- [ ] les secrets de connexion ne sont pas versionnés dans Git.

---

## 8. Sécurité et réversibilité

- [ ] Defender n’a pas été désactivé pour gagner en performance ;
- [ ] aucune exclusion large non approuvée n’a été ajoutée ;
- [ ] Windows Update reste fonctionnel ;
- [ ] les profils Windows gérés conservent leurs limites de sécurité ;
- [ ] les états initiaux utiles au rollback sont conservés lorsqu’ils existent ;
- [ ] le projet ne prétend pas rollbacker automatiquement ce qu’il ne peut pas restaurer honnêtement.

---

## 9. Maintenance

- [ ] `update.ps1 -Mode Audit` produit un état compréhensible ;
- [ ] Windows Update, WinGet, WSL, Ubuntu, DevOps et VS Code restent des domaines distincts ;
- [ ] les drivers et mises à jour facultatives ne sont pas inclus par défaut ;
- [ ] aucun changement majeur d’Ubuntu n’est assimilé à une maintenance ordinaire ;
- [ ] les versions DevOps restent pilotées par le dépôt ;
- [ ] le besoin de redémarrage reste explicite.

---

## 10. OpenClaw/OpenRouter — uniquement si utilisé

- [ ] la racine est `D:\AI\OpenClaw` ;
- [ ] le control-plane correspond au ref approuvé ;
- [ ] le checkout n’écrase pas des modifications locales non comprises ;
- [ ] OpenClaw Windows est validé ;
- [ ] le backend WSL2 DevOps associé est validé ;
- [ ] les secrets OpenRouter restent hors de Git.

Validation :

```powershell
.\install.ps1 -Mode Verify -ValidateOpenClawAI
```

---

## 11. Logs et preuves

- [ ] chaque exécution importante possède un `RunId` identifiable ;
- [ ] les logs par script sont lisibles ;
- [ ] les événements NDJSON existent pour les runs concernés ;
- [ ] les rapports structurés permettent de relier état observé et verdict ;
- [ ] aucun secret n’est volontairement écrit dans la documentation ou les arguments journalisés.

---

## 12. Idempotence

Après convergence, relancer :

```powershell
.\install.ps1 -Mode Apply -FullInstall -PlanOnly
```

Critère :

- [ ] la majorité des composants sont `DÉJÀ OK` ;
- [ ] aucun composant ne boucle entre Apply et Verify sans cause comprise ;
- [ ] une relance ne réinstalle pas arbitrairement la workstation entière.

---

## 13. Sauvegarde et reprise

- [ ] une sauvegarde de référence existe sur un support séparé ;
- [ ] sa capacité et sa structure ont été vérifiées ;
- [ ] l’export WSL attendu est inclus dans la stratégie de protection ;
- [ ] l’intégrité prévue par le projet est vérifiable ;
- [ ] un plan de reprise peut être généré ;
- [ ] la restauration complète reste une décision explicite et documentée.

Guide : [`10_BACKUP_RESTORE.md`](10_BACKUP_RESTORE.md).

---

# Verdict final

Le projet peut être déclaré **prêt** lorsque les validations applicables sont réussies et que les éventuelles actions humaines obligatoires sont closes.

Commande centrale de qualification :

```powershell
.\install.ps1 `
  -Mode Verify `
  -ValidateHardware `
  -ValidateWsl `
  -ValidateDevOps
```

Puis vérifier l’idempotence et la sauvegarde de référence.

Le résultat attendu n’est pas une machine « optimisée au maximum ». C’est une workstation **cohérente, performante, sécurisée, maintenable, reproductible et récupérable**.