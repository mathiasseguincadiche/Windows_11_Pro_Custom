# Optimisation Windows

## Objectif

La machine dispose de 48 Go de RAM et de deux SSD PCIe 5.0. L'objectif n'est pas de supprimer des composants Windows au hasard, mais de réduire le bruit inutile sans casser Windows Update, Microsoft Store, Defender, WSL2, Hyper-V ou le gaming.

La V2 automatise uniquement des réglages documentés et réversibles. Aucun service système critique n'est désactivé.

## Moteur de tuning

```powershell
.\scripts\windows\10_tune.ps1 -Mode Audit
.\scripts\windows\10_tune.ps1 -Mode Apply
.\scripts\windows\10_tune.ps1 -Mode Verify
.\scripts\windows\10_tune.ps1 -Mode Rollback
```

Lors du premier `Apply`, les valeurs d'origine sont sauvegardées dans :

```text
state/windows-tweaks-backup.json
```

Cette sauvegarde n'est pas écrasée lors des exécutions suivantes afin de conserver le véritable état initial.

## Réglages automatisés

- affichage des extensions de fichiers ;
- affichage des fichiers cachés ;
- suppression des notifications publicitaires de l'Explorateur ;
- masquage des Widgets de la barre des tâches ;
- désactivation de l'identifiant publicitaire ;
- désactivation des expériences personnalisées fondées sur les données de diagnostic ;
- désactivation des installations silencieuses d'applications suggérées ;
- désactivation des conseils et suggestions Windows non essentiels ;
- désactivation des « Windows consumer features » sur Windows Pro ;
- niveau de diagnostic maintenu au niveau requis, pas de tentative de neutralisation complète de la télémétrie.

## Ce que le script ne touche pas

- Windows Update ;
- Microsoft Store ;
- Microsoft Defender ;
- SmartScreen ;
- Windows Firewall ;
- Hyper-V / WSL ;
- journalisation Windows ;
- compression mémoire ;
- fichier d'échange ;
- services réseau ;
- services audio ;
- pilotes GPU ;
- Secure Boot / TPM.

## WinUtil

WinUtil peut servir de référence pour comparer les réglages, mais aucun preset global n'est exécuté automatiquement. Toute évolution inspirée de WinUtil doit être ajoutée individuellement au moteur de tuning et posséder un chemin de rollback.
