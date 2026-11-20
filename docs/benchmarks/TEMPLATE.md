<!--
Gabarit des rapports de benchmark (brief, section 8).
Dupliquer ce fichier en docs/benchmarks/BENCH-XXX-sujet.md, sujet court en
minuscules et mots séparés par des tirets (ex. BENCH-003-cluster-local.md).
Remplir dans l'ordre des sections, le verdict en dernier.
Chaque paragraphe s'ouvre par le tag de son auteur : [BENCH] pour le corps,
[SECU] ou [FINOPS] dans les relectures.
Aucun fait de mémoire (principe VIII) : chaque version, licence, date ou
chiffre renvoie à une source [Sn] ou à une mesure [Mn].
Retirer tous les commentaires avant de passer le statut à « relu ».
-->

# BENCH-XXX. Sujet

| Champ | Valeur |
| --- | --- |
| Identifiant | BENCH-XXX |
| Sujet | Le choix à trancher, en quelques mots |
| Statut | brouillon |
| Ouvert le | AAAA-MM-JJ |
| Mis à jour le | AAAA-MM-JJ |
| Auteur | [BENCH] |
| Relecteurs | [SECU] pour les licences et les CVE, [FINOPS] pour les coûts |
| Périmètre | Générateur, projet généré sur PC (cluster local), projet généré sur GCP |
| Choix du PRD | Ligne du tableau des choix ouverts de `docs/prd-mvp.md` |
| ADR lié | [ADR-XXX](../adr/ADR-XXX-sujet.md), écrit par [ARCHI] |
| Verdict proposé | Option retenue et total sur 100, rempli en dernier |

<!--
Statut : « brouillon » pendant la rédaction. « relu » quand [SECU] et [FINOPS]
ont rendu leur avis et que leurs remarques sont traitées. « clos » quand l'ADR
lié a tranché : le rapport ne bouge plus, un fait nouveau ouvre un nouveau
benchmark.
Périmètre : garder seulement ce que le choix touche.
-->

## 1. Contexte

<!--
La question en une phrase, ce qui en dépend, ce qui reste hors champ. Citer
les exigences du PRD (US-xxx, ENF-xx) et les principes de la constitution
concernés. L'option pressentie par le PRD se nomme ici et ne reçoit aucun
avantage dans la notation.
-->

[BENCH] Question posée, en une phrase.

[BENCH] Ce qui en dépend : exigences du PRD, principes de la constitution,
autres benchmarks.

[BENCH] Option pressentie par le PRD, notée comme les autres.

[BENCH] Hors champ : ce que ce benchmark ne tranche pas.

## 2. Options étudiées

<!--
Deux ou trois options : celles de la section 8 du brief, sauf raison écrite
sous le tableau. Version examinée : la dernière release stable à la date de
lecture de sa source.
-->

| Option | En une phrase | Version examinée | Publiée le | Sources |
| --- | --- | --- | --- | --- |
| Option A | Ce que c'est et son rôle dans ce choix | x.y.z | AAAA-MM-JJ | [S1] |
| Option B | Ce que c'est et son rôle dans ce choix | x.y.z | AAAA-MM-JJ | [S2] |
| Option C | Ce que c'est et son rôle dans ce choix | x.y.z | AAAA-MM-JJ | [S3] |

[BENCH] Options repérées mais non étudiées, et pourquoi. Écrire « aucune »
s'il n'y en a pas.

## 3. Critères éliminatoires

<!--
Les trois critères du brief, vérifiés avant toute notation.
Licence : open source pour tout ce qui tourne sur le PC ou en on-prem, soit
une licence approuvée par l'OSI, vérifiée sur la liste de l'OSI à la date du
rapport [Sn]. Sans objet pour un service managé de la cible cloud
(principe III).
Statut : ni archivé, ni annoncé en maintenance par le dépôt, le site ou la
fondation.
Release : la dernière date de moins de 12 mois au jour de la vérification.
Pour une norme stable (JSON Schema, OpenAPI, OCI), le critère porte sur
l'outil maintenu qui la met en œuvre, pas sur le texte de la norme. Il ne
s'applique pas aux dépendances transitives, qui se signalent dans les limites.
Une exigence fonctionnelle du PRD peut éliminer une option ; elle s'écrit dans
le contexte avec sa référence (US-xxx), et le DSI l'accepte par écrit.
Une option éliminée n'est pas notée. S'il reste moins de deux options, le
signaler au DSI avant de continuer.
-->

| Option | Licence open source | Ni archivé ni en maintenance | Release de moins de 12 mois | Vérifié le | Résultat |
| --- | --- | --- | --- | --- | --- |
| Option A | Oui ou non, licence exacte [Sn] | Oui ou non, preuve [Sn] | Oui ou non, dernière le AAAA-MM-JJ [Sn] | AAAA-MM-JJ | Retenue ou éliminée |
| Option B | Oui ou non, licence exacte [Sn] | Oui ou non, preuve [Sn] | Oui ou non, dernière le AAAA-MM-JJ [Sn] | AAAA-MM-JJ | Retenue ou éliminée |
| Option C | Oui ou non, licence exacte [Sn] | Oui ou non, preuve [Sn] | Oui ou non, dernière le AAAA-MM-JJ [Sn] | AAAA-MM-JJ | Retenue ou éliminée |

[BENCH] Options éliminées et critère en cause. Écrire « aucune » s'il n'y en
a pas.

## 4. Mesures

<!--
Une mesure réelle pour chaque critère où elle a un sens, en général
l'empreinte sur PC (ENF-02). Si aucune n'en a, le dire en une phrase et
retirer les sous-sections.
-->

### 4.1 Ce qui est mesuré

| ID | Mesure | Unité | Critère alimenté | Script |
| --- | --- | --- | --- | --- |
| M1 | RAM au repos après démarrage | Mio | Empreinte sur PC | `tests/bench/bench-XXX-measure.sh` |
| M2 | Temps de démarrage jusqu'à l'état prêt | s | Empreinte sur PC | `tests/bench/bench-XXX-measure.sh` |

### 4.2 Machine de mesure

| Élément | Valeur |
| --- | --- |
| Modèle | Marque et modèle |
| Processeur | Modèle et nombre de cœurs |
| Mémoire | RAM totale |
| Système | Nom et version |
| Moteur de conteneurs | Nom et version |
| Ressources allouées | CPU et RAM de la machine virtuelle du moteur, s'il y en a une |
| Versions mesurées | Version de chaque option, figée dans le script |
| Charge parasite | Applications ouvertes pendant la mesure |

### 4.3 Protocole

<!--
Assez précis pour qu'un tiers refasse la mesure. Au moins trois exécutions
par option et par mesure. Dire si les images sont déjà en cache : le temps de
démarrage en dépend.
-->

1. État de départ : ce qui est supprimé ou nettoyé avant chaque exécution.
2. Commande lancée, identique pour chaque option.
3. Fin de la mesure : l'événement qui l'arrête.
4. Relevé : outil utilisé et moment du relevé.
5. Nombre d'exécutions, au moins trois, et pause entre deux.

<!--
Le script vit dans tests/bench/, en shell, nommé en anglais comme le reste
du code. Il fige les versions des options, affiche chaque exécution et passe
shellcheck.
-->

Pour refaire la mesure :

```bash
tests/bench/bench-XXX-measure.sh
```

### 4.4 Résultats

<!--
Une ligne par mesure et par option. La médiane sert à la notation, l'écart
(maximum moins minimum) montre la dispersion. Ajouter une colonne par
exécution au-delà de trois.
-->

[BENCH] Mesures lancées le AAAA-MM-JJ, sur la machine de la section 4.2.

| Mesure | Option | Exécution 1 | Exécution 2 | Exécution 3 | Médiane | Écart |
| --- | --- | --- | --- | --- | --- | --- |
| M1 | Option A | valeur | valeur | valeur | valeur | valeur |
| M1 | Option B | valeur | valeur | valeur | valeur | valeur |
| M1 | Option C | valeur | valeur | valeur | valeur | valeur |

## 5. Notation par critère

Chaque option retenue reçoit une note entière de 0 à 5 sur chaque critère.
Les points valent note × poids / 5. Un cran de note vaut donc 3 points sur un
critère de poids 15, 2 points sur un poids 10 et 1 point sur le coût. Les
poids sont ceux de la section 8 du brief et ne changent pas d'un rapport à
l'autre.

| Note | Sens |
| --- | --- |
| 5 | Répond pleinement au critère, preuve directe |
| 4 | Répond, avec une réserve mineure écrite |
| 3 | Répond en partie, la réserve demande une action |
| 2 | Répond mal, il faut contourner |
| 1 | Répond à peine |
| 0 | Ne répond pas |

- Chaque note cite au moins une source [Sn] ou une mesure [Mn]. Une note sans
  preuve n'entre pas dans la grille, et le rapport reste en brouillon tant
  qu'elle manque.
- Un critère qui ne départage pas les options reçoit la même note pour
  toutes, avec la raison écrite.
- Une option éliminée à la section 3 n'est pas notée.

### 5.1 Licence et liberté d'usage, poids 15

<!--
Licence exacte, ce qu'elle impose au générateur (Apache-2.0) et aux projets
générés, changement de licence passé. Preuves : fichier de licence du dépôt,
annonce officielle.
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Option A | n/5 | p | Une ou deux phrases | [Sn] |
| Option B | n/5 | p | Une ou deux phrases | [Sn] |
| Option C | n/5 | p | Une ou deux phrases | [Sn] |

### 5.2 Gouvernance (fondation, multi-vendeurs), poids 15

<!--
Fondation porteuse, éditeur unique ou communauté, nombre d'entreprises parmi
les mainteneurs (principe V). Preuves : page du projet chez la fondation,
fichier des mainteneurs, statistiques de contribution datées.
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Option A | n/5 | p | Une ou deux phrases | [Sn] |
| Option B | n/5 | p | Une ou deux phrases | [Sn] |
| Option C | n/5 | p | Une ou deux phrases | [Sn] |

### 5.3 Maturité et adoption, poids 15

<!--
Ancienneté, niveau de maturité dans la fondation, adoption en production
déclarée (principe VI : pas de projet qui vient de sortir). Preuves : page de
la fondation, liste d'adoptants en précisant qui la tient.
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Option A | n/5 | p | Une ou deux phrases | [Sn] |
| Option B | n/5 | p | Une ou deux phrases | [Sn] |
| Option C | n/5 | p | Une ou deux phrases | [Sn] |

### 5.4 Activité et maintenance, poids 10

<!--
Rythme des releases sur 12 mois, contributeurs actifs, délai de réponse aux
tickets. Preuves : page des releases, statistiques du dépôt, datées.
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Option A | n/5 | p | Une ou deux phrases | [Sn] |
| Option B | n/5 | p | Une ou deux phrases | [Sn] |
| Option C | n/5 | p | Une ou deux phrases | [Sn] |

### 5.5 Sécurité (CVE, réactivité), poids 10

<!--
Politique de signalement, avis de sécurité publiés, délai entre signalement
et correctif, CVE encore ouvertes. Relu par [SECU]. Preuves : politique de
sécurité du projet, base de CVE, avis du projet.
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Option A | n/5 | p | Une ou deux phrases | [Sn] |
| Option B | n/5 | p | Une ou deux phrases | [Sn] |
| Option C | n/5 | p | Une ou deux phrases | [Sn] |

### 5.6 Empreinte sur PC (RAM, CPU, démarrage), poids 10

<!--
RAM au repos, CPU, temps de démarrage sur le PC (ENF-02). Preuve : la médiane
des mesures de la section 4.

Règle de notation, validée par Lucas le 2026-11-19 (BENCH-003) : des seuils
absolus, jamais un écart à la meilleure option. Chaque seuil est une valeur
ronde tirée du PRD (budget de 900 s d'ENF-01, portable de 8 Gio) ou d'un débit
bas pris comme hypothèse (10 Mbit/s). Les seuils s'écrivent dans la section
4.1 avant la première mesure, avec leur origine. Chaque option part de 5 et
perd un cran par seuil dépassé. Une option à moins de 10 % d'un seuil voit
ses deux notes possibles écrites dans la sensibilité de la section 7.

Seuils de BENCH-003, à reprendre ou à adapter au sujet, en disant pourquoi :
volume compressé à télécharger au premier lancement au-delà de 500 Mo (400 s
à 10 Mbit/s) ; au moins une image retéléchargée à chaque lancement, cache
plein ; démarrage à chaud au-delà de 90 s (10 % du budget) ; mémoire au repos
au-delà de 1 Gio (un huitième d'un portable de 8 Gio).
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Option A | n/5 | p | Une ou deux phrases | [Mn] |
| Option B | n/5 | p | Une ou deux phrases | [Mn] |
| Option C | n/5 | p | Une ou deux phrases | [Mn] |

### 5.7 Portabilité multi-cloud, poids 10

<!--
Fonctionne sur les deux cibles du MVP sans code propre à l'une (principe II),
et resterait utilisable sur un autre cloud ou en on-prem. Preuves :
documentation officielle d'installation par plateforme.
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Option A | n/5 | p | Une ou deux phrases | [Sn] |
| Option B | n/5 | p | Une ou deux phrases | [Sn] |
| Option C | n/5 | p | Une ou deux phrases | [Sn] |

### 5.8 Expérience dev et documentation, poids 10

<!--
Qualité et fraîcheur de la documentation officielle, clarté des erreurs,
temps pour faire tourner un exemple minimal. Note de jugement : décrire
l'essai qui la fonde. Preuves : documentation officielle, essai consigné.
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Option A | n/5 | p | Une ou deux phrases | [Sn] |
| Option B | n/5 | p | Une ou deux phrases | [Sn] |
| Option C | n/5 | p | Une ou deux phrases | [Sn] |

### 5.9 Coût (managé ou opérationnel), poids 5

<!--
Coût du service managé sur GCP, ou coût d'exploitation sur le PC et en
on-prem (temps, licence, support). Relu par [FINOPS]. Preuves : page de tarifs
officielle datée, estimation de [FINOPS].
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Option A | n/5 | p | Une ou deux phrases | [Sn] |
| Option B | n/5 | p | Une ou deux phrases | [Sn] |
| Option C | n/5 | p | Une ou deux phrases | [Sn] |

## 6. Grille pondérée

<!--
Reporter notes et points de la section 5. Total : somme des points, sur 100.
Une option éliminée garde sa colonne, avec « éliminée » dans chaque case.
-->

| Critère | Poids | Option A | Option B | Option C |
| --- | --- | --- | --- | --- |
| Critères éliminatoires (section 3) | éliminatoire | passe | passe | passe |
| Licence et liberté d'usage | 15 | n/5, p pts | n/5, p pts | n/5, p pts |
| Gouvernance (fondation, multi-vendeurs) | 15 | n/5, p pts | n/5, p pts | n/5, p pts |
| Maturité et adoption | 15 | n/5, p pts | n/5, p pts | n/5, p pts |
| Activité et maintenance | 10 | n/5, p pts | n/5, p pts | n/5, p pts |
| Sécurité (CVE, réactivité) | 10 | n/5, p pts | n/5, p pts | n/5, p pts |
| Empreinte sur PC (RAM, CPU, démarrage) | 10 | n/5, p pts | n/5, p pts | n/5, p pts |
| Portabilité multi-cloud | 10 | n/5, p pts | n/5, p pts | n/5, p pts |
| Expérience dev et documentation | 10 | n/5, p pts | n/5, p pts | n/5, p pts |
| Coût (managé ou opérationnel) | 5 | n/5, p pts | n/5, p pts | n/5, p pts |
| Total | 100 | p / 100 | p / 100 | p / 100 |

## 7. Verdict proposé

<!--
Une proposition. L'ADR lié, écrit par [ARCHI], tranche, et Lucas valide.
-->

[BENCH] Option proposée, son total, et son écart en points avec la suivante.

[BENCH] Pourquoi : les critères qui font la différence, avec leurs sources.

[BENCH] Sensibilité : les notes qui, changées d'un cran, inverseraient le
classement. Si l'écart tient dans un seul cran, le verdict repose sur ce
critère : le dire.

[BENCH] Gouvernance : si l'option proposée dépend d'un éditeur unique, ce qui
justifie l'écart au principe V. Sinon, retirer ce paragraphe.

[BENCH] Réserves : ce qu'il faut surveiller, et la date de la prochaine
vérification.

[BENCH] Suites : l'ADR lié, les entrées de `catalog/` à créer avec licence,
gouvernance, statut, date et source (principe IV), les risques à ajouter à
`docs/risques.md`.

## 8. Limites et biais

<!--
Ce qui peut fausser le verdict, dit une fois et précisément, avec ce qui
lèverait la limite. Pistes : une seule machine de mesure, machine différente
du PC de référence de la phase 6 (pas encore défini, ENF-02), images en
cache, source tenue par l'éditeur lui-même, note de jugement, option
pressentie par le PRD.
-->

| Limite | Effet possible sur le verdict | Ce qui la lèverait |
| --- | --- | --- |
| Une seule machine de mesure | Empreinte propre à ce matériel | Relancer le script sur une deuxième machine |

## 9. Sources

<!--
Une ligne par source, citée [Sn] dans le rapport. Source officielle d'abord
(principe VIII) : dépôt, documentation, site du projet ou de la fondation.
Une source tierce se signale dans la dernière colonne et ne justifie pas seule
une note. URL entre chevrons, par exemple <https://example.org/page>.
-->

| ID | URL | Lue le | Ce que la source établit | Officielle |
| --- | --- | --- | --- | --- |
| S1 | URL complète | AAAA-MM-JJ | Le fait précis, par exemple la licence de l'option A | Oui |

## 10. Relectures

<!--
[SECU] relit licences, critères éliminatoires et sécurité. [FINOPS] relit le
coût. Le statut passe à « relu » quand les deux avis sont rendus et leurs
remarques traitées.
-->

| Relecteur | Porte sur | Date | Avis |
| --- | --- | --- | --- |
| [SECU] | Licences, critères éliminatoires, sécurité | AAAA-MM-JJ | Favorable, réservé ou défavorable |
| [FINOPS] | Coût | AAAA-MM-JJ | Favorable, réservé ou défavorable |

[SECU] Remarques et suite donnée.

[FINOPS] Remarques et suite donnée.
