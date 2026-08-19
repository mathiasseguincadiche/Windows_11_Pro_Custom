# Applications Windows — socle géré

La source de vérité applicative est :

```text
manifests/winget/apps-core.json
```

Le bootstrap ne cherche jamais une application « au nom approximatif ». Pour les applications automatiques, il exige un identifiant WinGet exact, vérifie qu'il est résolu, détecte si l'application est déjà présente et revalide l'installation après exécution.

---

## Applications automatiques actuelles

| Application | ID WinGet |
| --- | --- |
| Visual Studio Code | `Microsoft.VisualStudioCode` |
| PowerShell 7 | `Microsoft.PowerShell` |
| Windows Terminal | `Microsoft.WindowsTerminal` |
| Starship | `Starship.Starship` |
| JetBrainsMono Nerd Font | `DEVCOM.JetBrainsMonoNerdFont` |
| VLC | `VideoLAN.VLC` |
| Notion | `Notion.Notion` |
| Firefox | `Mozilla.Firefox` |
| Brave | `Brave.Brave` |
| LibreOffice | `TheDocumentFoundation.LibreOffice` |
| Steam | `Valve.Steam` |
| Notepad++ | `Notepad++.Notepad++` |
| draw.io | `JGraph.Draw` |
| Bitwarden | `Bitwarden.Bitwarden` |

Le manifeste versionné reste la source de vérité si cette liste évolue.

---

## Applications volontairement manuelles

Certaines applications restent déclarées avec `autoInstall=false` lorsqu'une licence, un compte ou un canal d'installation ambigu empêche une automatisation fiable.

| Application | Contrat |
| --- | --- |
| MarkText | `autoInstall=false` |
| FileZilla | `autoInstall=false` |
| Microsoft Office | `autoInstall=false` |
| PDFgear | `autoInstall=false` |
| Files | `autoInstall=false` |

FileZilla ne possède volontairement aucun `wingetId` approuvé dans le manifeste courant. Il reste donc manuel tant qu'une décision explicite n'a pas validé un package et son canal d'installation.

Le principe est :

```text
package fiable et vérifiable
        ↓
automatisation

package ambigu / licence / compte
        ↓
ACTION REQUISE
```

Une automatisation fragile est pire qu'une action manuelle explicite.

---

## Installer ou réparer uniquement les logiciels

Via le centre de contrôle :

```text
2. Installation / réparation des logiciels
```

ou directement :

```powershell
.\scripts\bootstrap\03_apps.ps1 -Mode Apply
```

Cette commande directe est un composant ciblé : elle ne remplace pas la préqualification complète de la workstation. Avant un `Apply` direct, vérifier au minimum les garde-fous V25 et V24 ; pour une convergence globale, utiliser `install.ps1`.

```powershell
.\scripts\bootstrap\00_storage_identity_v25.ps1 -Mode Verify
.\scripts\bootstrap\00_storage_integrity_v24.ps1 -Mode Verify
```

Audit :

```powershell
.\scripts\bootstrap\03_apps.ps1 -Mode Audit
```

Vérification :

```powershell
.\scripts\bootstrap\03_apps.ps1 -Mode Verify
```

---

## Comportement idempotent

Pour chaque package automatique :

```text
résoudre l'ID WinGet exact
        ↓
package valide ?
        ↓
vérifier la présence
        ↓
présent ?
├── oui -> DÉJÀ OK
└── non -> installer
             ↓
          re-vérifier
             ↓
          preuve réelle
```

Une relance ne doit pas réinstaller les logiciels déjà conformes.

---

## Windows Terminal, PowerShell 7 et Starship

**Windows Terminal** est le terminal natif géré de la workstation. Sa configuration DevOps est appliquée séparément par :

```text
scripts/windows/31_windows_terminal.ps1
```

Le composant expose deux profils explicites :

```text
PowerShell 7 - DevOps -> profil par défaut Windows Terminal
Ubuntu - DevOps       -> distribution WSL2 Ubuntu
```

PowerShell 7 reste le shell moderne recommandé pour l'administration Windows et du dépôt. Windows PowerShell 5.1 reste disponible pour les composants système qui en dépendent.

Starship fournit le prompt PowerShell géré par le dépôt ; le shell Bash/Starship d'Ubuntu reste géré par les scripts WSL existants et n'est pas dupliqué par le composant Windows Terminal.

---

## JetBrainsMono Nerd Font

La Nerd Font fournit les glyphes utilisés par Starship et l'environnement terminal :

- Windows Terminal ;
- terminal intégré VS Code.

Elle est donc un composant fonctionnel de l'expérience CLI, pas seulement un choix esthétique.

---

## WSL2 n'est pas une application WinGet

WSL2 appartient au socle système et possède sa propre gestion.

Cela évite de confondre :

```text
application Windows
vs
capacité système
vs
distribution Linux
```

Guide : [`06_WSL2.md`](06_WSL2.md).

---

## OpenSSH Client

Le client OpenSSH Windows est géré comme capacité système afin de permettre :

- SSH depuis PowerShell ;
- Remote - SSH depuis VS Code ;
- administration distante.

Le serveur OpenSSH Windows n'est pas installé par défaut : la workstation n'a pas besoin d'exposer un serveur SSH entrant pour ses usages normaux.

---

## OneDrive : volontairement absent

La workstation cible actuellement un état **sans Microsoft OneDrive**.

Le contrat se trouve dans :

```text
config/windows/onedrive.json
```

et le composant dédié dans :

```text
scripts/windows/33_onedrive.ps1
```

En application, le dépôt :

- observe l'état antérieur ;
- arrête OneDrive s'il tourne ;
- désinstalle uniquement le client concerné ;
- applique les stratégies prévues ;
- revalide l'état.

### Protection des données

Le script ne doit pas supprimer les dossiers personnels ni les fichiers utilisateur.

Si Documents/Bureau/Images ont été redirigés ou synchronisés par OneDrive, sécurise d'abord les données locales avant toute suppression du client.

### Rollback

Le rollback restaure les stratégies antérieures et ne réinstalle le client que si son état précédent le justifie.

---

## Installation et mise à jour sont deux responsabilités différentes

```text
Installation / réparation
        ↓
scripts/bootstrap/03_apps.ps1

Maintenance régulière
        ↓
update.ps1
```

Le gestionnaire de mises à jour respecte les pins et les exclusions du dépôt.

Guide : [`15_MISES_A_JOUR.md`](15_MISES_A_JOUR.md).

---

## Règles de sécurité

Le socle applicatif ne doit jamais :

- installer un package dont l'identifiant n'est pas résolu proprement ;
- traiter un logiciel déjà présent comme absent sans vérification ;
- contourner une licence ;
- stocker des identifiants ou tokens dans le manifeste ;
- ajouter un logiciel simplement parce qu'il est populaire ;
- remplacer une application manuelle par un package différent portant un nom similaire.

L'objectif est un **socle cohérent et reproductible**, pas un catalogue le plus long possible.
