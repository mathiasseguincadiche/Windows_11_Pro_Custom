# Applications Windows — socle géré

La source de vérité applicative est :

```text
manifests/winget/apps-core.json
```

Le bootstrap ne cherche jamais une application « au nom approximatif » : pour les applications automatiques, il exige un identifiant WinGet exact, vérifie qu'il est résolu, détecte si l'application est déjà présente et revalide l'installation après exécution.

---

## Applications automatiques actuelles

| Application | ID WinGet |
|---|---|
| Visual Studio Code | `Microsoft.VisualStudioCode` |
| PowerShell 7 | `Microsoft.PowerShell` |
| JetBrainsMono Nerd Font | `DEVCOM.JetBrainsMonoNerdFont` |
| VLC | `VideoLAN.VLC` |
| Notion | `Notion.Notion` |
| Firefox | `Mozilla.Firefox` |
| Brave | `Brave.Brave` |
| FileZilla | `TimKosse.FileZilla.Client` |
| WezTerm | `wez.wezterm` |
| LibreOffice | `TheDocumentFoundation.LibreOffice` |
| Steam | `Valve.Steam` |
| Notepad++ | `Notepad++.Notepad++` |
| draw.io | `JGraph.Draw` |
| Bitwarden | `Bitwarden.Bitwarden` |

---

## Applications volontairement manuelles

```text
MarkText
Microsoft Office
PDFgear
Files
```

Elles restent déclarées dans le manifeste, mais `autoInstall=false`.

Pourquoi ?

- le canal d'installation exact peut être ambigu ou dépendre d'un compte/licence ;
- une automatisation fragile est pire qu'une action manuelle explicite ;
- le dépôt préfère afficher `ACTION REQUISE` plutôt que prétendre avoir installé le mauvais package.

Microsoft Office, en particulier, peut nécessiter une licence et une authentification ; aucune installation silencieuse n'est supposée.

---

## Installer / réparer uniquement les logiciels

Via le menu V12 :

```text
2. Installation / réparation des logiciels
```

ou directement :

```powershell
.\scripts\bootstrap\03_apps.ps1 -Mode Apply
```

### Audit

```powershell
.\scripts\bootstrap\03_apps.ps1 -Mode Audit
```

### Vérification

```powershell
.\scripts\bootstrap\03_apps.ps1 -Mode Verify
```

---

## Comportement idempotent

Pour chaque package automatique :

```text
winget show ID exact
        ↓
package valide ?
        ↓
winget list ID exact
        ↓
présent ?
├── oui -> DEJA_OK
└── non -> install
             ↓
          winget list
             ↓
          preuve réelle
```

Une relance ne doit donc pas réinstaller les logiciels déjà détectés.

---

## Pourquoi PowerShell 7 est dans le socle

Le projet utilise PowerShell pour son orchestration. Windows PowerShell 5.1 reste disponible pour compatibilité système, mais PowerShell 7 est le shell moderne recommandé pour l'utilisation quotidienne et est également accessible dans WezTerm/VS Code.

---

## Pourquoi la Nerd Font est dans le socle

JetBrainsMono Nerd Font fournit les glyphes utilisés par Starship et le terminal DevOps V10 dans :

- WezTerm ;
- le terminal intégré VS Code.

Elle est donc un composant fonctionnel de l'expérience terminal, pas seulement un choix esthétique.

---

## WSL2 n'est pas une application WinGet du socle

WSL2 appartient au socle système et est provisionné par :

```text
scripts/bootstrap/06_wsl.ps1
```

Cela évite de confondre :

```text
application Windows
vs
capacité/runtime système
```

OpenSSH Client suit également une gestion système dédiée.

---

## OneDrive : volontairement absent

La workstation cible un état **sans Microsoft OneDrive**.

Le contrat est :

```text
config/windows/onedrive.json
```

et le composant :

```text
scripts/windows/33_onedrive.ps1
```

En `Apply`, le dépôt :

- enregistre l'état antérieur ;
- arrête OneDrive s'il tourne ;
- désinstalle uniquement le package OneDrive avec fallback contrôlé ;
- applique les stratégies prévues ;
- revalide l'absence du package/processus et la présence des stratégies.

### Protection des données

Le script ne supprime jamais les dossiers OneDrive ni les fichiers utilisateur.

Si Documents/Bureau/Images ont déjà été redirigés/synchronisés par OneDrive, sécurise d'abord les données locales avant de supprimer le client.

### Rollback

Le rollback restaure les stratégies antérieures et ne réinstalle OneDrive que s'il était réellement présent avant l'Apply du dépôt.

---

## Mises à jour applicatives

L'installation initiale et les mises à jour sont deux responsabilités différentes :

```text
Installation / réparation -> scripts/bootstrap/03_apps.ps1
Mises à jour régulières   -> update.ps1 / V11
```

V11 respecte les pins WinGet et ne force pas les packages volontairement bloqués.

Voir [`22_SYSTEM_UPDATE_MANAGER_V11.md`](22_SYSTEM_UPDATE_MANAGER_V11.md).
