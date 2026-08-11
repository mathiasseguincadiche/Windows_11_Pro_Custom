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
