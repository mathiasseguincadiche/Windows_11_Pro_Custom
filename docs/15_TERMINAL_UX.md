# Suivi interactif dans le terminal

L'option **1. Installation complete** doit rester comprehensible pendant toute son execution. Le terminal n'est pas un simple flux de logs : il doit indiquer en permanence ce que l'orchestrateur fait, dans quelle phase il se trouve et si une operation longue continue reellement a travailler.

## Runtime du terminal

Le suivi interactif appartient au runtime moderne du projet :

```text
PowerShell 7.6.5 minimum
PSEdition Core
processus x64
pwsh.exe
```

Windows PowerShell 5.1 n'est pas une cible de compatibilite. Le menu, les sous-processus eleves, l'orchestrateur et la CI utilisent `pwsh`.

## Contrat d'affichage

Au debut du run, le bandeau annonce :

- le numero de release et le RunId ;
- le dossier des journaux ;
- la version PowerShell 7 reelle et le minimum accepte ;
- l'activation du suivi interactif ;
- le delai du battement de vie ;
- la signification des principaux statuts.

Chaque changement de phase affiche ensuite un bandeau `ETAPE` avec :

- un numero d'etape croissant ;
- un titre humain ;
- l'objectif de la phase ;
- le temps total ecoule depuis le lancement.

Chaque script reellement execute affiche une `SOUS-ETAPE` avec :

- le nom humain de l'action ;
- le script concerne ;
- le journal detaille associe ;
- l'heure de debut et le temps total deja ecoule.

Les composants idempotents presentent explicitement leur parcours :

1. `application 1/2` si une correction est necessaire ;
2. `revalidation 2/2` juste apres la modification ;
3. `FAIT` uniquement lorsque la revalidation reussit.

Un composant deja conforme affiche `DEJA OK` et n'est pas reinstalle inutilement.

## Battement de vie

Le runtime utilise un heartbeat console independant du flux de sortie du script enfant.

Par defaut, apres **15 secondes sans nouvelle sortie**, le terminal affiche par exemple :

```text
    [ACTIF] Applications WinGet est toujours en cours | ecoule 00:00:30
```

Cela signifie que le processus n'est pas considere comme termine ou abandonne : l'orchestrateur attend toujours la sous-etape courante.

Le heartbeat est reinitialise a chaque nouvelle ligne de sortie. Il ne doit donc pas spammer le terminal lorsqu'une commande produit deja des informations regulierement.

Pour les tests automatises uniquement, l'intervalle peut etre reduit avec :

```powershell
$env:WPC_HEARTBEAT_SECONDS = '2'
```

La valeur normale reste 15 secondes.

## Fin d'une sous-etape

Une action reussie affiche sa duree et rappelle son journal :

```text
[OK]               Operation terminee
                   Duree: 18.42s | journal: ...\logs\...
```

En cas d'erreur, l'action courante, le script et le journal ont deja ete affiches avant l'echec. Le centre de controle peut ensuite reprendre le contexte structure de l'orchestrateur pour presenter la cause.

## Synthese finale

La synthese contient notamment :

- le runtime PowerShell 7 qui a execute le run ;
- la duree totale ;
- le nombre de phases visibles ;
- le nombre de sous-etapes visibles ;
- les composants deja conformes ;
- les composants modifies puis valides ;
- le nombre de scripts executes ;
- le nombre d'echecs actuels ;
- le chemin du resume JSON.

Le `summary.json` conserve egalement l'edition, la version, la version minimale, l'executable et l'architecture PowerShell.

## Exemple simplifie

```text
==============================================================================
  Windows 11 Pro Custom - Orchestrateur
  PowerShell: 7.6.5 | Core | x64 | pwsh.exe | minimum 7.6.5
==============================================================================

==============================================================================
  ETAPE 03 | Application de la configuration
  Objectif   : Applique uniquement les ecarts detectes.
  Temps total: 00:04:12
==============================================================================

  COMPOSANT 02 | Applications WinGet
[A FAIRE]          Applications WinGet
                   Correction requise: application puis revalidation automatique.
[EN COURS]         Applications WinGet - application 1/2

  SOUS-ETAPE 07 | Applications WinGet
    Script  : scripts\bootstrap\03_apps.ps1
    Journal : ...\logs\bootstrap\03_apps.log
    Demarre : 15:44:10 | ecoule global 00:04:15
[EN COURS]         Applications WinGet

    [ACTIF] Applications WinGet est toujours en cours | ecoule 00:00:15
    [FAIT] Firefox installe et revalide par WinGet.

[OK]               Applications WinGet termine
                   Duree: 42.18s | journal: ...\logs\bootstrap\03_apps.log
[EN COURS]         Applications WinGet - revalidation 2/2
...
[FAIT]             Applications WinGet
```

L'objectif est qu'un utilisateur puisse comprendre le run directement dans le terminal sans ouvrir les journaux, tout en conservant ces journaux pour le diagnostic detaille.
