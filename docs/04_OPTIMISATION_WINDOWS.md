# Optimisation Windows

## Philosophie

La machine dispose de 48 Go de RAM et de deux SSD PCIe 5.0. L'objectif n'est donc pas de supprimer des composants au hasard, mais de réduire le bruit inutile sans casser Windows Update, Microsoft Store, Defender, WSL2, Hyper-V ou le gaming.

## Catégories

- démarrage et applications en arrière-plan ;
- télémétrie et suggestions non essentielles ;
- Explorer et interface ;
- alimentation ;
- stockage ;
- services réellement inutilisés ;
- gaming ;
- Defender après mesure ;
- WSL2.

Chaque futur tweak automatisé doit avoir `AUDIT`, `APPLY`, `VERIFY` et `ROLLBACK`.

WinUtil peut servir de référence, mais aucun preset global n'est appliqué aveuglément.
