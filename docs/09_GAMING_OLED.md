# Gaming, Intel Arc et affichage

La workstation est conçue pour rester un **vrai poste desktop et gaming** en plus de son rôle DevOps/Ops.

Le projet ne crée pas un « Windows gaming » séparé et ne désactive pas les composants nécessaires à WSL2 ou à la sécurité pour gagner quelques points de benchmark.

---

## Objectif

L'équilibre recherché est :

```text
Windows stable et sécurisé
+
Intel Arc correctement configurée
+
affichage 1440p haut rafraîchissement
+
WSL2 disponible pour DevOps
+
aucun tweak gaming destructif
```

---

## Intel Arc B580

La machine cible utilise une **Intel Arc B580 12 Go**.

Les points importants sont :

- pilote Intel Arc officiel et stable ;
- Above 4G Decoding actif ;
- Resizable BAR actif ;
- aucun overclocking ou undervolt imposé par le dépôt ;
- résolution et fréquence d'écran correctement détectées.

Les réglages UEFI ne sont pas modifiés automatiquement. Ils sont qualifiés comme preuves manuelles dans [`12_HARDWARE_QUALIFICATION.md`](12_HARDWARE_QUALIFICATION.md).

---

## Écran

La cible actuelle est un affichage :

```text
2560 × 1440
haut taux de rafraîchissement
VRR / Adaptive Sync lorsque disponible
HDR selon l'usage et la calibration
```

Après installation du pilote GPU, vérifie dans Windows :

```text
Paramètres
→ Système
→ Affichage
→ Affichage avancé
```

Contrôle :

- résolution native ;
- fréquence maximale réellement souhaitée ;
- bon écran sélectionné ;
- VRR lorsque l'écran/pilote le permet.

---

## OLED

Si l'écran utilisé est OLED :

- conserver les mécanismes de protection de la dalle ;
- laisser fonctionner les cycles de compensation prévus par le constructeur ;
- éviter un affichage statique extrêmement lumineux pendant des périodes très longues ;
- utiliser le masquage de la barre des tâches uniquement si cela convient à l'usage ;
- ne pas désactiver les protections du moniteur dans le but d'obtenir une luminosité permanente plus élevée.

Le dépôt ne modifie pas automatiquement le firmware ou les paramètres internes du moniteur.

---

## HDR

HDR est un choix d'usage, pas un réglage que le projet force globalement.

Si HDR est utilisé :

1. activer HDR dans Windows ;
2. utiliser l'outil de calibration Windows adapté ;
3. vérifier les réglages du moniteur ;
4. valider le rendu dans les jeux ou contenus réellement utilisés.

Une capture CI ne peut pas prouver la qualité visuelle réelle d'un écran.

---

## Game Mode

Le projet conserve **Game Mode**.

Il peut en revanche réduire des fonctions de capture en arrière-plan lorsqu'elles ne sont pas utilisées.

L'objectif est de limiter les tâches inutiles sans casser Xbox/Game Bar ou d'autres fonctions dont l'utilisateur pourrait avoir besoin.

---

## Plan d'alimentation

Le plan Windows de référence reste **Balanced**.

La machine n'a pas besoin d'un plan « Ultimate Performance » permanent pour être performante en jeu.

Le Ryzen 7 7700 et Windows savent adapter la fréquence à la charge. Le projet privilégie une politique mesurée plutôt qu'une consommation maximale constante.

Voir [`04_OPTIMISATION_WINDOWS.md`](04_OPTIMISATION_WINDOWS.md).

---

## WSL2 avant une session gaming

Lorsque les workloads Linux ne sont pas nécessaires :

```powershell
wsl --shutdown
```

Cette commande :

- arrête la VM WSL2 ;
- libère la RAM utilisée par Ubuntu ;
- arrête les services Docker/systemd Linux ;
- conserve intacte la configuration pour la prochaine session DevOps.

Il n'est pas nécessaire de désinstaller Docker, WSL2 ou les outils DevOps pour jouer.

---

## Profil WSL quotidien

La configuration quotidienne de WSL2 est déjà bornée afin de préserver les ressources Windows.

Le profil standard ne donne ni toute la RAM ni tous les threads du Ryzen à Linux.

Pour les détails : [`06_WSL2.md`](06_WSL2.md).

---

## Ce que le projet refuse

Le dépôt ne doit pas automatiquement :

- overclocker le GPU ;
- undervolter le GPU ;
- modifier le BIOS pour des gains gaming ;
- désactiver Defender ;
- désactiver le firewall ;
- désactiver la compression mémoire ;
- supprimer le pagefile ;
- désactiver les C-States ou core parking globalement ;
- appliquer des tweaks HPET/BCD non mesurés ;
- désactiver WSL/Hyper-V à chaque session ;
- lancer de gros benchmarks d'écriture SSD.

---

## Benchmark utile

Le dépôt privilégie les mesures légères et reproductibles :

- état mémoire ;
- pagefile ;
- plan d'alimentation ;
- file d'attente disque ;
- état des composants Windows importants.

Pour les performances gaming, les métriques les plus utiles restent celles du **jeu réel** : stabilité des frametimes, absence de crash, température, fréquence et comportement du pilote.

---

## Après une mise à jour du pilote Intel

Après une mise à jour GPU importante :

1. vérifier le Gestionnaire de périphériques ;
2. vérifier résolution/fréquence ;
3. vérifier ReBAR si un problème de performance apparaît ;
4. tester un ou deux jeux représentatifs ;
5. confirmer qu'aucune instabilité nouvelle n'existe ;
6. envisager une nouvelle sauvegarde de référence seulement après stabilisation.

---

## Résultat attendu

```text
Arc B580 reconnue et stable
+
ReBAR / Above 4G confirmés
+
écran à sa résolution/fréquence cible
+
VRR/HDR configurés selon l'usage
+
Windows toujours sécurisé
+
WSL2 disponible lorsque nécessaire
```

Le gaming est donc une **capacité de la workstation**, pas une excuse pour dégrader le socle DevOps ou la sécurité de Windows.
