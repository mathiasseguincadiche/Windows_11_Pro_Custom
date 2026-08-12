# Windows Responsiveness V8

## Objectif

La V8 corrige les comportements Windows qui peuvent donner une impression de lourdeur sans appliquer de pseudo-optimisations agressives.

La philosophie est :

```text
mesurer
  ↓
utiliser les mécanismes Windows documentés
  ↓
appliquer uniquement des réglages réversibles
  ↓
mesurer de nouveau
  ↓
rollback si régression
```

La V8 complète :

- V4 — optimisation Windows réversible ;
- V5 — qualification matérielle ;
- V6 — WSL2 ;
- V7 — sauvegarde et reprise.

## 1. Mémoire

Politique :

```text
Memory Compression               ON
Application Launch Prefetching   ON
Application PreLaunch            ON
Page Combining                   observation uniquement
Standby cache                    laissé à Windows
```

La RAM libre n'est pas un objectif. Windows peut utiliser la mémoire disponible comme cache afin d'éviter des lectures stockage inutiles.

Sont interdits :

- RAM cleaners ;
- purge automatique de Standby List ;
- `EmptyStandbyList` ;
- désactivation de Memory Compression ;
- désactivation du prefetch/prelaunch.

## 2. Pagefile et crash dump

Avec 48 Go de RAM, la cible est :

```text
Pagefile         System Managed
Crash dump       Automatic Memory Dump
CrashDumpEnabled 7
```

Le pagefile ne doit pas être supprimé sous prétexte que la machine possède beaucoup de RAM. Il augmente la limite de mémoire validée et permet à Windows de conserver une stratégie correcte de capture de dump.

Un redémarrage peut être nécessaire après un changement de gestion du pagefile.

## 3. CPU et alimentation

Cible :

```text
Power scheme   Balanced
AC Power mode  Best Performance
```

Le plan Balanced reste actif afin de conserver la gestion dynamique moderne du Ryzen 7 7700. Le mode secteur Best Performance indique à Windows de privilégier les performances lorsque la machine est alimentée.

La V8 ne touche pas :

- au core parking ;
- aux C-States ;
- au CPPC ;
- aux fréquences minimales CPU ;
- à HPET ;
- à `useplatformclock` ;
- à `disabledynamictick` ;
- à PBO/Curve Optimizer.

## 4. Interface utilisateur

La V8 désactive uniquement :

- l'animation réduire/restaurer ;
- les animations de zone cliente.

Elle conserve :

- le lissage des polices ;
- la composition du bureau ;
- l'accélération graphique normale de Windows.

Les modifications passent par l'API Windows `SystemParametersInfo`, pas par une collection de clés de registre opaques.

## 5. SSD

La V8 complète la V5 mais ne remplace pas la qualification T705.

Cible :

```text
TRIM                 ON
Scheduled Optimize   ON
espace libre          warning sous 15 %
benchmark écriture    jamais automatique
```

Pour un SSD compatible TRIM, Windows utilise ReTrim dans le mécanisme d'optimisation. La planification Windows n'est pas désactivée.

La V8 ne lance aucun benchmark d'écriture synthétique afin de ne pas écrire inutilement plusieurs dizaines ou centaines de gigaoctets sur les T705.

## 6. Applications au démarrage

La V8 inventorie les commandes de démarrage via Windows mais ne les désactive pas automatiquement.

Raison : la machine réelle peut contenir des utilitaires ou logiciels que l'utilisateur souhaite conserver au démarrage. La suppression en bloc est donc interdite.

Le rapport permet ensuite de classer manuellement :

```text
ESSENTIAL
USER-REQUIRED
ON-DEMAND
```

Les logiciels `ON-DEMAND` pourront être désactivés après installation réelle et mesure de leur impact.

## 7. Applications en arrière-plan

Aucune stratégie globale `deny all` n'est appliquée.

Les applications modernes peuvent être revues individuellement depuis Windows. Les applications desktop doivent généralement être gérées depuis leurs propres paramètres.

## 8. Mesures avant / après

Le benchmark léger existant est enrichi avec :

- RAM libre ;
- mémoire validée ;
- limite de commit ;
- pourcentage de commit ;
- état Memory Compression ;
- état prefetch/prelaunch ;
- pagefile System Managed ;
- pagefiles actifs ;
- charge CPU ;
- nombre de processus ;
- services actifs ;
- programmes de démarrage ;
- plan d'alimentation ;
- file d'attente disque ;
- lectures/écritures par seconde ;
- état Defender.

Aucun score synthétique n'est inventé.

## 9. Audit

```powershell
.\scripts\windows\53_responsiveness_v8.ps1 -Mode Audit
```

Rapport :

```text
reports/windows/v8-responsiveness.json
```

L'audit est également exécuté automatiquement avec :

```powershell
.\install.ps1 -Mode Audit
```

## 10. Apply

```powershell
.\install.ps1 -Mode Apply
```

Ordre simplifié :

```text
restore point
  ↓
benchmark BEFORE
  ↓
V4
  ↓
V8 responsiveness
  ↓
benchmark AFTER
  ↓
comparaison
```

Le premier Apply sauvegarde l'état V8 dans :

```text
state/windows-v8/responsiveness.before.json
```

## 11. Verify

```powershell
.\install.ps1 -Mode Verify
```

La V8 contrôle :

- Memory Compression ;
- Application Launch Prefetching ;
- Application PreLaunch ;
- pagefile System Managed ;
- Automatic Memory Dump ;
- plan Balanced ;
- mode secteur Best Performance lorsque l'API est disponible ;
- animations ciblées désactivées ;
- TRIM ;
- Scheduled Optimize.

Verdict :

```text
VERDICT: V8 WINDOWS RESPONSIVENESS READY
```

## 12. Rollback

```powershell
.\install.ps1 -Mode Rollback
```

La V8 restaure l'état capturé avant le premier Apply :

- MMAgent ;
- gestion du pagefile ;
- configuration de dump ;
- plan d'alimentation ;
- mode de puissance secteur ;
- animations UI.

Les programmes de démarrage n'ont pas besoin d'être restaurés car la V8 ne les modifie jamais automatiquement.

## 13. Ce que la V8 interdit

```text
RAM cleaner
Standby-list purge
pagefile désactivé
pagefile fixe sans mesure
prefetch désactivé
Scheduled Optimize désactivé
Ultimate Performance par défaut
core parking forcé OFF
C-States forcés OFF
HPET / BCD timer hacks
network offloads désactivés
mass service disable
Defender désactivé
Windows Update désactivé
```

## 14. CI

Le workflow :

```text
.github/workflows/responsiveness-v8.yml
```

vérifie :

- la politique V8 ;
- les garde-fous anti-hacks ;
- le câblage Apply/Verify ;
- la méthode de benchmark non destructive ;
- un audit réel sur runner Windows ;
- la génération du rapport V8.

L'objectif final est un Windows 11 réactif, mais toujours stable, diagnosticable et compatible avec WSL2, Defender, Windows Update et le matériel qualifié par la V5.
