# Applications Windows

Le socle demandé est conservé dans `manifests/winget/apps-core.json`.

L'installation automatisée vérifie d'abord qu'un identifiant WinGet exact existe avant de lancer le package. Un identifiant non résolu est ignoré avec un avertissement au lieu d'installer un résultat approximatif.

## Automatisées si disponibles

VS Code, VLC, Notion, Firefox, Brave, FileZilla, WezTerm, LibreOffice, Steam, Notepad++ et draw.io.

## Conservées manuelles dans cette étape

- MarkText ;
- Microsoft Office ;
- PDFgear ;
- Files.

Ces quatre entrées restent dans le manifeste et seront automatisées uniquement après validation de leur canal d'installation exact.

## OneDrive : volontairement absent

La workstation cible un état **sans Microsoft OneDrive**.

Le contrat est défini dans `config/windows/onedrive.json` et appliqué par `scripts/windows/33_onedrive.ps1` dans les modes `Audit`, `Apply`, `Verify` et `Rollback` du poste de travail.

En `Apply`, le dépôt :

- enregistre d'abord l'état antérieur de OneDrive et des stratégies concernées ;
- arrête le processus OneDrive s'il est actif ;
- désinstalle uniquement le package `Microsoft.OneDrive`, avec fallback vers `OneDriveSetup.exe /uninstall` si nécessaire ;
- active la stratégie Windows `DisableFileSyncNGSC=1` ;
- active `PreventNetworkTrafficPreUserSignIn=1` ;
- vérifie que OneDrive n'est plus installé, qu'aucun `OneDrive.exe` n'est actif et que les deux stratégies sont présentes.

Le script ne supprime jamais les dossiers OneDrive ni les fichiers utilisateur. Si OneDrive a déjà été utilisé pour synchroniser ou rediriger Documents/Bureau/Images, les données doivent être sécurisées localement avant d'appliquer cette suppression.

Le mode `Rollback` restaure les valeurs de stratégie antérieures et ne réinstalle OneDrive que s'il était présent avant l'application du dépôt.
