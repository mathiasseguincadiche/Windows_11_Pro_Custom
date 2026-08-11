# Installation Windows 11 Pro

## Ordre recommandé

1. Mettre à jour l'UEFI/BIOS avec une version stable adaptée à la MSI MAG B850M Mortar WiFi.
2. Installer Windows 11 Pro en UEFI sur le premier Crucial T705.
3. Créer `C:` en NTFS pour Windows.
4. Initialiser le second Crucial T705 en GPT et créer `D:` en NTFS.
5. Terminer Windows Update avant les optimisations.
6. Installer les pilotes AMD chipset, Intel Arc, réseau, Wi-Fi/Bluetooth et audio depuis les sources constructeurs.
7. Cloner ce dépôt.
8. Exécuter `install.ps1 -Mode Audit`.
9. Vérifier `reports/preflight.json`.
10. Exécuter `install.ps1 -Mode Apply`.

Aucun script du dépôt ne formate les SSD.
