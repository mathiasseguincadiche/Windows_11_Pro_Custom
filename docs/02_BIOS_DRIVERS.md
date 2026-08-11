# BIOS et pilotes

## Réglages à contrôler

- Boot UEFI.
- Secure Boot actif après validation de l'installation.
- TPM/fTPM actif.
- SVM/virtualisation AMD active pour WSL2/Hyper-V.
- Above 4G Decoding actif.
- Resizable BAR actif pour l'Intel Arc B580.
- Profil mémoire à 6000 MT/s uniquement s'il est stable sur cette plateforme.

## Pilotes

Ordre conseillé :

1. AMD Chipset.
2. Intel Arc Graphics.
3. LAN / Wi-Fi / Bluetooth MSI.
4. Audio.
5. Logitech Brio 100 si un composant spécifique est nécessaire.

Éviter les outils tiers de type driver updater automatique.
