# BENCH-001. Format de la spec projet

| Champ | Valeur |
| --- | --- |
| Identifiant | BENCH-001 |
| Sujet | Format et langage de validation de la spec projet, source de vérité du générateur |
| Statut | brouillon |
| Ouvert le | 2026-11-19 |
| Mis à jour le | 2026-11-19 |
| Auteur | [BENCH] |
| Relecteurs | [SECU] pour les licences et les CVE, [FINOPS] pour les coûts |
| Périmètre | Générateur (CLI et plugin). La spec est aussi versionnée dans le projet généré (US-003) |
| Choix du PRD | Format de la spec : YAML validé par un JSON Schema rangé dans `schema/` (option pressentie) |
| ADR lié | À écrire par [ARCHI], numéro à attribuer |
| Verdict proposé | Option A, YAML validé par JSON Schema 2020-12 : 93/100, soit 10 points devant l'option D2 |

## 1. Contexte

[BENCH] Question posée : dans quel format l'entretien écrit-il la spec projet, et avec quel langage de schéma la CLI la valide-t-elle ?

[BENCH] Ce qui en dépend. US-003 demande une spec abstraite (`database: postgres`), qui porte la version de son schéma, qu'une validation refuse en nommant le champ fautif et la raison, qui refuse toute cible hors de la matrice, et que la CLI valide seule. US-002 et US-004 lisent et écrivent cette spec ; US-010 relie ses champs aux ADR. Principes concernés : II (spec abstraite, catalogue concret), I (rien sans test), V (gouvernance ouverte), VI (récent mais éprouvé), VIII (aucun fait de mémoire). La phase 3 écrira le schéma v1 dans `schema/`. Le PRD retient une CLI en Python (BENCH-006 en trace le pourquoi), et BENCH-002 évalue Copier, qui lit ses réponses dans un fichier YAML.

[BENCH] Option pressentie par le PRD : YAML validé par un JSON Schema. Elle est notée comme les autres.

[BENCH] Hors champ : le contenu exact du schéma v1 (phase 3), la liste des questions de l'entretien (phase 5), le choix du moteur de templates (BENCH-002) et la structure de `catalog/`.

## 2. Options étudiées

| Option | En une phrase | Version examinée | Publiée le | Sources |
| --- | --- | --- | --- | --- |
| A. YAML et JSON Schema | Spec en YAML, schéma en JSON Schema 2020-12, validé en Python par python-jsonschema (check-jsonschema pour l'essai) | JSON Schema 2020-12 ; python-jsonschema 4.26.0 ; check-jsonschema 0.39.0 | 2022-06-16 ; 2026-01-07 ; 2026-10-26 | [S1], [S2], [S10], [S12] |
| B. CUE | Langage de contraintes ; schéma en CUE, qui valide directement un fichier YAML (`cue vet`) | v0.17.1 | 2026-07-16 | [S18], [S20], [S21] |
| C. Pkl | Langage de configuration typé ; spec écrite en Pkl qui étend un module de schéma, ou YAML relu par un module Pkl | 0.33.1 | 2026-11-18 | [S33], [S36] |
| D1. Score seul | Une spec de charge de travail Score (`score.dev/v1b1`) par composant, sans spec projet | schéma `score-v1b1.json` du dépôt score-spec/spec 0.4.1 ; score-compose 0.50.0 | 2026-05-25 ; 2026-11-14 | [S46], [S47], [S48], [S54] |
| D2. Spec maison avec section Score | Spec YAML et JSON Schema comme A, dont la section des composants reprend le schéma Score par référence | mêmes versions que A et D1 | idem | [S47], [S48] |

[BENCH] Quatre options au lieu des deux ou trois prévues par le gabarit. Le brief en listait trois (YAML et JSON Schema, CUE, Pkl). Lucas a ajouté Score le 2026-11-19, à la suite de l'analyse des outils existants (section 4.2 et tableau 6.4 de [l'analyse](analyse-outils-existants.md)), parce que Score définit déjà des types abstraits (`postgres`, `redis`) dans un schéma JSON. Score ne couvre pas les champs de projet (cible, région, budget) : il est donc noté sous deux usages, D1 et D2, qui reçoivent chacun leur colonne.

[BENCH] Options repérées mais non étudiées : d'autres langages de configuration existent (KCL, Jsonnet, Dhall, Nickel). Ils n'ont été ni lus ni vérifiés pour ce rapport, la liste des options ayant été fixée par Lucas.

## 3. Critères éliminatoires

| Option | Licence open source | Ni archivé ni en maintenance | Release de moins de 12 mois | Vérifié le | Résultat |
| --- | --- | --- | --- | --- | --- |
| A | Oui : spécification BSD-3-Clause ou AFL-3.0, python-jsonschema MIT, check-jsonschema Apache-2.0, toutes approuvées par l'OSI [S3], [S9], [S13], [S60] | Oui : groupe de travail IETF actif, billet du projet du 2026-07-06 [S5], [S6] | Oui : python-jsonschema le 2026-01-07, check-jsonschema le 2026-10-26 [S10], [S12] | 2026-11-19 | Retenue |
| B | Oui, Apache-2.0 [S19], [S60] | Oui, préversions v0.18 en cours [S26] | Oui, v0.17.1 le 2026-07-16 [S21] | 2026-11-19 | Retenue |
| C | Oui, Apache-2.0 [S34], [S60] | Oui [S36] | Oui, 0.33.1 le 2026-11-18 [S36] | 2026-11-19 | Retenue |
| D1, D2 | Oui, Apache-2.0 pour la spécification et score-compose [S46], [S55], [S60] | Oui, CNCF Sandbox [S53] | Oui : spécification 0.4.1 le 2026-05-25, score-compose 0.50.0 le 2026-11-14 [S48], [S54] | 2026-11-19 | Retenue |

[BENCH] Aucune option éliminée. Pour A, le critère de release s'applique au validateur : le texte de la spécification JSON Schema 2020-12 n'a pas été republié depuis le 2022-06-16 [S2], ce qui est le propre d'un standard stable, et le projet travaille à sa normalisation à l'IETF [S5], [S6]. Cette lecture du critère pour une spécification est à confirmer par [ARCHI].

## 4. Mesures

### 4.1 Ce qui est mesuré

[BENCH] La validation tourne une fois par génération, sur le PC de l'utilisateur. On mesure ce qu'elle coûte, puis on consigne l'essai pratique qui fonde la note d'expérience dev.

| ID | Mesure | Unité | Critère alimenté | Script |
| --- | --- | --- | --- | --- |
| M1 | Temps de validation de la spec valide, démarrage de l'outil compris | ms | Empreinte sur PC | `tests/bench/bench-001-validate.sh` |
| M2 | Mémoire résidente maximale pendant la validation | Mio | Empreinte sur PC | `tests/bench/bench-001-validate.sh` |
| M3 | Taille de l'outil sur disque | Mio | Empreinte sur PC | `tests/bench/bench-001-validate.sh`, sauf l'environnement Python (relevé à la main, section 4.4) |
| M4 | Essai fonctionnel : spec valide acceptée, spec à trois erreurs refusée, messages comparés | constat | Expérience dev, portabilité | `tests/bench/bench-001-validate.sh` |

### 4.2 Machine de mesure

| Élément | Valeur |
| --- | --- |
| Modèle | Apple, identifiant matériel Mac16,7 |
| Processeur | Apple M4 Pro, 14 cœurs |
| Mémoire | 24 Gio |
| Système | macOS 27.2.1 (build 26B131) |
| Moteur de conteneurs | Aucun, la mesure n'en utilise pas |
| Ressources allouées | Sans objet |
| Versions mesurées | check-jsonschema 0.39.0 lancé par uv 0.12.23 (CPython 3.13 géré par uv), cue 0.17.1, pkl 0.33.1, score-compose 0.50.0, figées dans le script |
| Installation | cue et pkl par leurs formules homebrew-core [S45], [S44], documentées par les projets [S18], [S33] ; score-compose par le tap officiel `score-spec/tap` [S58], [S59] ; check-jsonschema par uvx |
| Charge parasite | D'autres agents travaillaient en parallèle sur la machine : charge moyenne de 5,19 sur une minute au lancement (14 cœurs) |

### 4.3 Protocole

1. État de départ : outils installés aux versions du script, caches chauds (environnement uvx de check-jsonschema, schéma Score téléchargé), état de score-compose initialisé dans un dossier temporaire supprimé en fin de script.
2. Commande : chaque option valide sa spec valide (`yaml/valid.yaml` pour A et B, `pkl/valid.pkl` et `yaml/valid.yaml` pour C, `score/valid.score.yaml` pour D1, `score-section/valid.yaml` pour D2).
3. Fin de la mesure : la sortie du processus de validation.
4. Relevé : horloge `date +%s%N` autour de `/usr/bin/time -l`, qui donne la mémoire résidente maximale. Le temps inclut le lancement de `/usr/bin/time`, le même pour toutes les options.
5. Une exécution d'échauffement, puis cinq exécutions mesurées par option, enchaînées sans pause.

[BENCH] Deux points du protocole biaisent la comparaison, et la section 8 les reprend. L'option A est mesurée à travers uvx et check-jsonschema : la ligne A0 mesure ce démarrage seul (`--version`), sans validation. score-compose n'a pas de commande de validation seule : `generate` valide, provisionne les ressources et écrit un fichier Compose.

Pour refaire la mesure :

```bash
tests/bench/bench-001-validate.sh 5
```

### 4.4 Résultats

[BENCH] Mesures lancées le 2026-11-19 à 00:37 UTC, sur la machine de la section 4.2. Un passage complet lancé juste avant donnait des médianes voisines : 123,3 ms pour A, 14,9 ms pour B, 16,3 ms pour C.

| Mesure | Option | Exécution 1 | Exécution 2 | Exécution 3 | Exécution 4 | Exécution 5 | Médiane | Écart |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| M1 | A0, démarrage seul (`--version`) | 131,9 | 129,8 | 126,8 | 133,5 | 136,3 | 131,9 | 9,5 |
| M1 | A, check-jsonschema | 131,6 | 133,2 | 134,8 | 131,8 | 134,4 | 133,2 | 3,2 |
| M1 | B, `cue vet` | 15,8 | 16,4 | 15,6 | 15,1 | 15,7 | 15,7 | 1,3 |
| M1 | C, `pkl eval` sur la spec Pkl | 16,3 | 16,2 | 15,8 | 16,4 | 16,6 | 16,3 | 0,8 |
| M1 | C, `pkl eval` sur la spec YAML | 16,7 | 16,4 | 17,4 | 16,7 | 16,3 | 16,7 | 1,1 |
| M1 | D1, check-jsonschema et schéma Score | 187,3 | 214,5 | 185,9 | 199,2 | 198,8 | 198,8 | 28,6 |
| M1 | D1, `score-compose generate` | 24,4 | 23,6 | 25,3 | 23,7 | 23,8 | 23,8 | 1,7 |
| M1 | D2, check-jsonschema | 191,6 | 178,4 | 180,2 | 190,7 | 179,3 | 180,2 | 13,2 |
| M2 | A0, démarrage seul | 40,6 | 40,8 | 40,7 | 40,7 | 40,8 | 40,7 | 0,2 |
| M2 | A, check-jsonschema | 40,9 | 40,9 | 41,1 | 41,3 | 41,0 | 41,0 | 0,4 |
| M2 | B, `cue vet` | 21,2 | 21,1 | 21,1 | 21,4 | 21,3 | 21,2 | 0,3 |
| M2 | C, spec Pkl | 22,9 | 22,9 | 22,9 | 22,9 | 22,9 | 22,9 | 0,0 |
| M2 | C, spec YAML | 24,6 | 24,6 | 24,6 | 24,6 | 24,6 | 24,6 | 0,0 |
| M2 | D1, check-jsonschema | 46,1 | 45,9 | 46,2 | 46,0 | 46,0 | 46,0 | 0,3 |
| M2 | D1, `score-compose generate` | 24,1 | 24,2 | 24,2 | 24,1 | 24,3 | 24,2 | 0,2 |
| M2 | D2, check-jsonschema | 46,0 | 45,8 | 46,2 | 45,9 | 46,0 | 46,0 | 0,4 |

[BENCH] M1 en millisecondes, M2 en Mio. Pour A, presque tout le temps part dans le démarrage d'uvx et de Python : 133,2 ms contre 131,9 ms sans validation. D1 et D2 passent par un schéma distant, que check-jsonschema garde en cache d'après sa date de modification [S15] ; l'écart plus large de ces deux lignes vient probablement de cette vérification réseau, non isolée ici.

| M3 | Taille |
| --- | --- |
| cue | 22,5 Mio (23 076 Kio), binaire unique |
| pkl | 84,9 Mio (86 924 Kio), binaire natif |
| score-compose | 23,1 Mio (23 664 Kio), binaire unique |
| check-jsonschema | 15,9 Mio (16 316 Kio) de paquets Python, hors interpréteur, relevé une fois avec `du -sk` sur l'environnement uvx |

### 4.5 Essai fonctionnel

[BENCH] La même spec minimale est écrite dans chaque format : un projet `demo-saas` sur le blueprint `saas-b2b`, `database: postgres`, `cache: redis`, cibles `local` et `gcp`, région GCP obligatoire dès que `gcp` est ciblé. La version invalide porte trois erreurs : la cible `aws`, hors matrice ; `cloud-sql`, un produit concret à la place d'un composant abstrait ; la région absente alors que `gcp` est ciblé. Les fichiers sont sous `tests/bench/bench-001/`.

| Option | Spec valide | Erreurs signalées en une passe | Position donnée | Constat |
| --- | --- | --- | --- | --- |
| A | Acceptée | 3 sur 3 | Chemin JSON (`$.targets[2]`, `$.components.database`), sans numéro de ligne | Messages courts : `'aws' is not one of ['local', 'gcp']`, `'gcp' is a required property` |
| B | Acceptée | 1 sur 3, en six messages | Ligne et colonne dans le schéma et dans le YAML | L'erreur sur `aws` déclenche une cascade (`empty disjunction`, `error in call to list.Contains`) qui masque les deux autres. Elles n'apparaissent qu'en corrigeant puis relançant. La région absente donne `incomplete value =~"^[a-z]+-[a-z]+[0-9]+$"` |
| C, spec en Pkl | Acceptée | 1 sur 3 | Ligne et extrait du fichier fautif | Arrêt à la première erreur. Message clair (``Expected value of type `"local"\|"gcp"`, but got `"aws"`.``), contrainte affichée en diagramme de valeurs |
| C, spec en YAML | Acceptée | 1 sur 3 | Ligne du schéma, jamais celle du YAML | Demande un module de correspondance écrit à la main (`pkl/yaml-check.pkl`) qui recopie la structure du schéma. Une clé inconnue est ignorée au lieu d'être refusée, au premier niveau comme dans une classe |
| D1 | Acceptée par le schéma et par score-compose | 1 sur 3 | Chemin JSON | La cible n'a pas de place : `targets` est refusé (`Additional properties are not allowed`). `cloud-sql` passe le schéma, où le type est une chaîne libre, et n'échoue qu'au provisionnement : `resource 'cloud-sql.default#api.db' is not supported by any provisioner`. La région n'est pas exprimable |
| D2 | Acceptée | 3 sur 3 | Chemin JSON | Comme A. Le schéma Score est bien appliqué par référence : retirer `containers` donne `'containers' is a required property`. La référence pointe vers une URL, récupérée à la validation |

[BENCH] Clés inconnues : A et B refusent une clé ajoutée au premier niveau ou dans `project` (`Additional properties are not allowed`, `field not allowed` avec sa ligne). C refuse une propriété inconnue dans une spec écrite en Pkl (``Cannot find property `owner` in object of type `Spec#Project`.``), mais l'ignore quand la spec est en YAML.

[BENCH] Couverture de US-003. A et D2 couvrent les cinq points : types abstraits par énumération, version du schéma (`specVersion`), champ fautif et raison, cibles limitées à la matrice, validation par la CLI Python seule grâce à la bibliothèque python-jsonschema [S9]. B et C couvrent les quatre premiers. Pour le cinquième, la CLI devrait appeler un binaire externe, faute de liaison Python utilisable : cue-py se dit en chantier (« expect constant churn and breakage ») [S31], et Pkl n'a pas de liaison Python officielle [S41]. D1 ne couvre ni les cibles ni la région.

[BENCH] Lien avec Copier : `copier copy --data-file` charge des données depuis un fichier YAML (aide de Copier 9.19.1, lue le 2026-11-19 pendant l'essai). Une spec YAML (A, B, D2) lui passe telle quelle. Une spec Pkl demande d'abord `pkl eval --format yaml`.

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

[BENCH] Règle propre à ce rapport : D2 dépend à la fois de la pile de A et du schéma Score. Sur chaque critère, D2 reçoit la plus basse des deux notes, sauf quand l'assemblage change la réponse, ce qui est alors écrit.

### 5.1 Licence et liberté d'usage, poids 15

[BENCH] Le critère ne départage pas : toutes les licences sont permissives et approuvées par l'OSI, aucune n'impose de condition au générateur sous Apache-2.0 ni aux projets générés, et aucun changement de licence n'apparaît dans les sources lues.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| A | 5/5 | 15 | Spécification sous BSD-3-Clause ou AFL-3.0 au choix, validateurs sous MIT et Apache-2.0 | [S3], [S9], [S13], [S60] |
| B | 5/5 | 15 | Apache-2.0 | [S19], [S60] |
| C | 5/5 | 15 | Apache-2.0 | [S34], [S60] |
| D1 | 5/5 | 15 | Apache-2.0 pour la spécification et score-compose | [S46], [S55], [S60] |
| D2 | 5/5 | 15 | Licences de A et de D1, toutes permissives | [S3], [S9], [S46] |

### 5.2 Gouvernance (fondation, multi-vendeurs), poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| A | 4/5 | 12 | Aucun éditeur unique : un comité technique communautaire, qui plafonnera la part d'un employeur à moins de 50 % au-delà de dix membres, et un groupe de travail IETF actif qui vise un standard proposé pour le 2027-05-31. Réserves : pas de fondation (l'entrée à l'OpenJS, annoncée en 2022, « n'a jamais abouti »), pas d'entité juridique, règles de gouvernance non ratifiées. Le validateur Python repose sur un auteur principal | [S4], [S5], [S6], [S7], [S8], [S9] |
| B | 2/5 | 6 | Éditeur unique : CUE Labs se présente comme « steward » du projet, financé par des fonds de capital-risque, sur un modèle open core annoncé le 2025-10-30. Aucun fichier de gouvernance ni de mainteneurs dans le dépôt | [S19], [S30] |
| C | 2/5 | 6 | Éditeur unique : dépôt de l'organisation Apple, failles signalées à Apple, quatre mainteneurs sans affiliation affichée, aucun document de gouvernance | [S34], [S35], [S37] |
| D1 | 4/5 | 12 | Projet CNCF Sandbox depuis le 2024-07-08. Mainteneurs chez Oracle, Docker, Checkly et un indépendant, décisions par consensus et vote des mainteneurs. Réserve : Sandbox est le premier niveau de la CNCF | [S49], [S50], [S53] |
| D2 | 4/5 | 12 | Note commune à A et à D1 | [S4], [S53] |

### 5.3 Maturité et adoption, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| A | 5/5 | 15 | Premier brouillon publié le 2009-12-05, version 2020-12 stable. OpenAPI 3.1.0 définit son Schema Object comme un sur-ensemble de JSON Schema 2020-12 depuis le 2021-02-15. Validateur Python et serveur de langage YAML prennent en charge 2020-12 | [S2], [S9], [S16], [S17] |
| B | 3/5 | 9 | Premier module publié le 2019-06-22, mais toujours en v0.x avec une v0.18 en préversion. Aucune liste d'adoptants officielle lue. Action : figer la version et suivre les changements du langage | [S20], [S25], [S26] |
| C | 2/5 | 6 | Publié en open source le 2024-02-01, encore en 0.x. Aucune adoption en production documentée dans les sources lues, alors que le principe VI la demande avant l'entrée au catalogue | [S36], [S40] |
| D1 | 2/5 | 6 | Version d'API `score.dev/v1b1`, sans version stable du schéma ni date annoncée dans la feuille de route. Six adoptants déclarés par le projet, qui déploient tous avec `humctl`, l'outil de Humanitec, dont Humanitec lui-même | [S46], [S51], [S52] |
| D2 | 3/5 | 9 | Socle de A, mature. La section Score suit un schéma sans version stable : une évolution de Score imposerait une nouvelle version du schéma de spec | [S2], [S52] |

### 5.4 Activité et maintenance, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| A | 4/5 | 8 | check-jsonschema : dix releases entre le 2026-02-16 et le 2026-10-26. Groupe IETF actif. Réserve : une seule release de python-jsonschema en douze mois (4.26.0, le 2026-01-07) | [S6], [S10], [S12] |
| B | 5/5 | 10 | v0.16.0 le 2026-03-03, v0.16.1 le 2026-04-08, v0.17.0 le 2026-06-22, v0.17.1 le 2026-07-16, préversions v0.18 jusqu'au 2026-11-11 | [S21], [S22], [S23], [S24], [S26] |
| C | 5/5 | 10 | Dix releases du 2025-11-20 (0.30.0) au 2026-11-18 (0.33.1) | [S36] |
| D1 | 5/5 | 10 | score-compose : dix releases du 2026-06-05 au 2026-11-14. Spécification : 0.4.0 le 2026-04-17, 0.4.1 le 2026-05-25 | [S48], [S54] |
| D2 | 4/5 | 8 | Note de A, la plus basse des deux | [S10], [S54] |

### 5.5 Sécurité (CVE, réactivité), poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| A | 5/5 | 10 | python-jsonschema : politique publiée, accusé de réception visé sous 48 h, aucun avis publié ni vulnérabilité dans OSV. check-jsonschema : une CVE (CVE-2024-53848, cache des schémas distants), corrigée en 0.30.0. Format déclaratif : la spec ne contient pas de code | [S11], [S14], [S61] |
| B | 4/5 | 8 | Aucun avis publié, aucune vulnérabilité dans OSV. Réserve : politique réduite à une adresse de signalement, sans délai annoncé | [S27], [S28], [S29] |
| C | 3/5 | 6 | Deux avis publiés le 2026-07-08 (sévérités modérée et faible), le premier corrigé en 0.32.0 publiée le même jour. Mais une spec Pkl est un programme : par défaut, elle peut charger des modules par `https:` et des paquets. Action : restreindre l'évaluation avec `--allowed-modules` et `--allowed-resources` | [S33], [S36], [S38], [S39] |
| D1 | 4/5 | 8 | Politique publiée, réponse visée sous dix jours ouvrés, aucun avis publié ni vulnérabilité dans OSV. Réserve : les provisionneurs `cmd://` exécutent des commandes à la génération | [S56], [S57], [S62], [S64] |
| D2 | 4/5 | 8 | Base de A, mais la référence au schéma Score se télécharge à la validation. Une étiquette Git se déplace : il faudra copier le schéma dans le dépôt et le figer | [S15], [S47] |

### 5.6 Empreinte sur PC (RAM, CPU, démarrage), poids 10

[BENCH] Toutes les validations tiennent sous 0,2 s et 50 Mio, une fois par génération : c'est négligeable devant un cluster local. La taille sur disque départage seule.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| A | 5/5 | 10 | 133,2 ms et 41,0 Mio, presque tout pour le démarrage d'uvx et de Python (131,9 ms sans validation). 15,9 Mio de paquets pour check-jsonschema, à côté de l'interpréteur Python que la CLI demande déjà | [M1], [M2], [M3] |
| B | 5/5 | 10 | 15,7 ms et 21,2 Mio, binaire de 22,5 Mio | [M1], [M2], [M3] |
| C | 4/5 | 8 | 16,3 ms et 22,9 Mio. Réserve : binaire de 84,9 Mio, près de quatre fois les autres | [M1], [M2], [M3] |
| D1 | 5/5 | 10 | 23,8 ms et 24,2 Mio avec score-compose, provisionnement compris. Binaire de 23,1 Mio | [M1], [M2], [M3] |
| D2 | 5/5 | 10 | 180,2 ms et 46,0 Mio par check-jsonschema, même pile que A | [M1], [M2] |

### 5.7 Portabilité multi-cloud, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| A | 5/5 | 10 | Format neutre : les cibles sont des valeurs de la spec. Validateurs disponibles au moins en Python et en JavaScript | [S9], [S65], [M4] |
| B | 5/5 | 10 | Format neutre. Binaires pour Linux, Windows et macOS | [S18], [M4] |
| C | 4/5 | 8 | Format neutre. Réserve : exécutable natif macOS pour aarch64 seulement. Un Mac Intel passe par l'exécutable Java, qui demande Java 17 ou plus | [S33], [M4] |
| D1 | 3/5 | 6 | Types de ressources abstraits, traduits par score-compose ou score-k8s. Mais la cible n'est pas dans la spec, et aucun provisionneur par défaut ne vise un service managé de GCP. Action : porter les cibles hors de Score | [S46], [S63], [M4] |
| D2 | 5/5 | 10 | Cibles dans la partie maison, composants nommés avec les types Score. Changer de cible revient à changer une ligne (principe II) | [M4] |

### 5.8 Expérience dev et documentation, poids 10

[BENCH] Note fondée sur l'essai de la section 4.5, mené sur une seule spec minimale. Les quatre projets publient une documentation officielle, lue pendant l'essai [S15], [S32], [S43], [S58].

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| A | 4/5 | 8 | Trois erreurs sur trois en une passe, chemin du champ et raison. Bibliothèque Python dans la CLI, spec passée telle quelle à Copier, complétion dans l'éditeur par le serveur de langage YAML. Réserves : pas de numéro de ligne, schéma verbeux pour une condition (`if` et `then`) | [M4], [S9], [S17] |
| B | 3/5 | 6 | Schéma concis, ligne et colonne dans le YAML. Mais une erreur à la fois avec des cascades, un message cryptique pour un champ manquant, et un binaire à appeler depuis la CLI | [M4], [S31], [S32] |
| C | 2/5 | 4 | Messages clairs mais arrêt à la première erreur. Spec en Pkl, contraire au YAML prévu par le PRD, ou module de correspondance qui recopie le schéma et laisse passer les clés inconnues. Binaire à appeler, export YAML avant Copier | [M4], [S41], [S42] |
| D1 | 1/5 | 2 | La spec minimale ne s'écrit pas : cible et région n'ont pas de place, et un produit concret (`cloud-sql`) passe le schéma | [M4], [S47] |
| D2 | 3/5 | 6 | Messages de A. Mais deux schémas à tenir, un champ `containers` imposé par Score alors que l'image vient du blueprint, et une section à extraire pour la passer à score-compose | [M4], [S47] |

### 5.9 Coût (managé ou opérationnel), poids 5

[BENCH] Le critère ne départage pas : aucune option n'a de licence payante ni de service à héberger. Le temps passé à installer un binaire supplémentaire est déjà compté en expérience dev. À relire par [FINOPS].

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| A | 5/5 | 5 | Gratuit, rien à héberger | [S9], [S13] |
| B | 5/5 | 5 | Gratuit, rien à héberger | [S19] |
| C | 5/5 | 5 | Gratuit, rien à héberger | [S34] |
| D1 | 5/5 | 5 | Gratuit, rien à héberger | [S46], [S55] |
| D2 | 5/5 | 5 | Gratuit, rien à héberger | [S9], [S46] |

## 6. Grille pondérée

| Critère | Poids | A. YAML et JSON Schema | B. CUE | C. Pkl | D1. Score seul | D2. Section Score |
| --- | --- | --- | --- | --- | --- | --- |
| Critères éliminatoires (section 3) | éliminatoire | passe | passe | passe | passe | passe |
| Licence et liberté d'usage | 15 | 5/5, 15 pts | 5/5, 15 pts | 5/5, 15 pts | 5/5, 15 pts | 5/5, 15 pts |
| Gouvernance (fondation, multi-vendeurs) | 15 | 4/5, 12 pts | 2/5, 6 pts | 2/5, 6 pts | 4/5, 12 pts | 4/5, 12 pts |
| Maturité et adoption | 15 | 5/5, 15 pts | 3/5, 9 pts | 2/5, 6 pts | 2/5, 6 pts | 3/5, 9 pts |
| Activité et maintenance | 10 | 4/5, 8 pts | 5/5, 10 pts | 5/5, 10 pts | 5/5, 10 pts | 4/5, 8 pts |
| Sécurité (CVE, réactivité) | 10 | 5/5, 10 pts | 4/5, 8 pts | 3/5, 6 pts | 4/5, 8 pts | 4/5, 8 pts |
| Empreinte sur PC (RAM, CPU, démarrage) | 10 | 5/5, 10 pts | 5/5, 10 pts | 4/5, 8 pts | 5/5, 10 pts | 5/5, 10 pts |
| Portabilité multi-cloud | 10 | 5/5, 10 pts | 5/5, 10 pts | 4/5, 8 pts | 3/5, 6 pts | 5/5, 10 pts |
| Expérience dev et documentation | 10 | 4/5, 8 pts | 3/5, 6 pts | 2/5, 4 pts | 1/5, 2 pts | 3/5, 6 pts |
| Coût (managé ou opérationnel) | 5 | 5/5, 5 pts | 5/5, 5 pts | 5/5, 5 pts | 5/5, 5 pts | 5/5, 5 pts |
| Total | 100 | 93 / 100 | 79 / 100 | 68 / 100 | 74 / 100 | 83 / 100 |

## 7. Verdict proposé

[BENCH] Option proposée : A, une spec YAML validée par un JSON Schema 2020-12, avec 93 points. Elle devance D2 de 10 points, B de 14, D1 de 19 et C de 25.

[BENCH] Pourquoi. A est la seule option qui cumule un format mûr et une gouvernance sans éditeur unique : 27 points sur 30 pour ces deux critères, contre 15 pour CUE et 12 pour Pkl [S2], [S5], [S30], [S35]. L'essai la place aussi en tête : trois erreurs signalées en une passe, et une validation que la CLI Python fait seule, comme US-003 le demande [M4], [S9]. CUE et Pkl obligeraient la CLI à appeler un binaire externe [S31], [S41]. Score seul ne peut pas porter la spec : il n'a ni cible ni région, et son type de ressource reste une chaîne libre [S47], [M4].

[BENCH] Sensibilité. Pour égaler A, D2 devrait gagner deux crans en maturité et deux en expérience dev, ce que seule une version stable du schéma Score rendrait plausible. Un cran de moins pour A en gouvernance (3 points) ou en expérience dev (2 points) la laisse devant. Le verdict ne repose pas sur une note isolée.

[BENCH] Gouvernance. A ne dépend d'aucun éditeur, sans être portée par une fondation : sa normalisation passe par l'IETF [S5], [S6]. Score est le seul projet de fondation (CNCF), mais il ne couvre que les charges de travail ; la préférence du principe V joue « à fonctionnalité comparable », ce qui n'est pas le cas ici. L'ADR doit l'écrire.

[BENCH] Réserves. Le validateur Python repose sur un auteur principal et n'a publié qu'une release en douze mois [S9], [S10]. Si le projet s'arrêtait, d'autres validateurs prennent en charge 2020-12 [S65]. La spec à venir de l'IETF pourra s'écarter de 2020-12 [S5] : le schéma de CELIAN fixe `$schema` sur 2020-12. Les erreurs n'ont pas de numéro de ligne ; [DEV] jugera s'il faut le retrouver depuis le chemin JSON. Prochaine vérification : le 2027-05-19, ou au jalon IETF du 2027-05-31 [S6].

[BENCH] Suites.

- ADR de [ARCHI] sur le format de la spec, en citant la lecture du critère de release pour une spécification (section 3).
- Nommer les composants avec les types de Score (`postgres`, `redis`), comme le proposait l'analyse des outils (section 6.3). Cela ne coûte rien et garde ouvert un passage à D2 par une version majeure du schéma de spec, si Score publie un schéma stable.
- Aucune référence distante dans les schémas de `schema/` : tout schéma tiers se copie dans le dépôt et se fige.
- Entrées de `catalog/` à créer avec licence, gouvernance, statut, date et source : JSON Schema 2020-12, python-jsonschema, check-jsonschema s'il sert en pre-commit et en CI.
- Risque à proposer au DSI pour `docs/risques.md` : un validateur Python porté par une personne (R-23 si le DSI le retient).

## 8. Limites et biais

| Limite | Effet possible sur le verdict | Ce qui la lèverait |
| --- | --- | --- |
| Une seule machine, Apple Silicon sous macOS | Empreinte propre à ce matériel. Linux, prévu par Q5, n'est pas mesuré | Relancer le script sur Linux ; il gère GNU time |
| Autres agents actifs pendant la mesure (charge de 5,19) | Temps un peu gonflés, dans les mêmes proportions pour toutes les options | Relancer sur une machine au repos |
| A mesurée via uvx et check-jsonschema | M1 surestime A : la CLI validera dans son propre processus, sans relancer Python | Mesurer la validation en processus quand la CLI existera |
| D1 et D2 avec un schéma distant | Le temps inclut une vérification réseau du cache | Copier le schéma Score en local |
| Schémas écrits par l'auteur du rapport | Un schéma CUE écrit autrement, sans la compréhension `if list.Contains`, produirait peut-être moins de cascades | Faire relire le schéma CUE par un connaisseur |
| Note d'expérience dev fondée sur une seule spec minimale | Une spec plus grande peut changer l'écart | Refaire l'essai sur le schéma v1 en phase 3 |
| Option pressentie par le PRD classée première | Biais de confirmation | Notes sourcées ; relecture par [SECU] et [ARCHI] |
| Pkl 0.33.1 publiée la veille de l'essai | Le principe VI fait attendre sept jours avant une mise à jour automatique | Sans effet sur le verdict ; figer une version de plus de sept jours si Pkl était retenu |
| Affiliations des membres du comité JSON Schema non trouvées | La note multi-vendeurs de A repose sur les règles, pas sur les personnes | Lire la liste des membres du comité |
| Adoptants de Score déclarés par le projet lui-même | Adoption peut-être surestimée ou sous-estimée | Source indépendante |
| Dates des releases CUE lues sur le proxy des modules Go | La page GitHub n'affichait pas l'année | Sans objet, le proxy est la source officielle des modules Go |
| Critère de release appliqué au validateur et non au texte de JSON Schema | A pourrait être jugée autrement par [ARCHI] | Règle à fixer dans l'ADR |

## 9. Sources

| ID | URL | Lue le | Ce que la source établit | Officielle |
| --- | --- | --- | --- | --- |
| S1 | <https://json-schema.org/specification> | 2026-11-19 | Version courante 2020-12 | Oui |
| S2 | <https://json-schema.org/specification-links> | 2026-11-19 | 2020-12 publiée le 2022-06-16 ; premier brouillon le 2009-12-05 | Oui |
| S3 | <https://github.com/json-schema-org/json-schema-spec> | 2026-11-19 | Contenu sous BSD-3-Clause ou AFL-3.0 | Oui |
| S4 | <https://github.com/json-schema-org/community/blob/main/GOVERNANCE.md> | 2026-11-19 | Comité technique, document non ratifié, pas d'entité juridique, plafond par employeur au-delà de dix membres | Oui |
| S5 | <https://json-schema.org/blog/posts/ietf-cooperation> | 2026-11-19 | Billet du 2026-07-06 : entrée à l'OpenJS jamais aboutie, travail avec l'IETF | Oui |
| S6 | <https://datatracker.ietf.org/group/jsonschema/about/> | 2026-11-19 | Groupe IETF jsonschema actif, jalon au 2027-05-31 | Oui |
| S7 | <https://json-schema.org/blog/posts/json-schema-joins-the-openjsf> | 2026-11-19 | Annonce du 2022-02-11 : JSON Schema entre en incubation à l'OpenJS | Oui |
| S8 | <https://openjsf.org/projects> | 2026-11-19 | JSON Schema absent de la liste des projets de l'OpenJS | Oui |
| S9 | <https://github.com/python-jsonschema/jsonschema> | 2026-11-19 | MIT, prise en charge de 2020-12, auteur Julian Berman, financement Tidelift | Oui |
| S10 | <https://github.com/python-jsonschema/jsonschema/releases.atom> | 2026-11-19 | v4.26.0 le 2026-01-07, v4.25.1 le 2025-08-18 | Oui |
| S11 | <https://github.com/python-jsonschema/jsonschema/security> | 2026-11-19 | Politique de sécurité, accusé visé sous 48 h, aucun avis publié | Oui |
| S12 | <https://github.com/python-jsonschema/check-jsonschema/releases.atom> | 2026-11-19 | Dix releases, de 0.36.2 le 2026-02-16 à 0.39.0 le 2026-10-26 | Oui |
| S13 | <https://github.com/python-jsonschema/check-jsonschema/blob/main/LICENSE> | 2026-11-19 | Apache-2.0 | Oui |
| S14 | <https://github.com/advisories/GHSA-q6mv-284r-mp36> | 2026-11-19 | CVE-2024-53848, versions antérieures à 0.30.0, corrigée en 0.30.0 | Oui |
| S15 | <https://check-jsonschema.readthedocs.io/en/stable/usage.html> | 2026-11-19 | Schémas distants et références mis en cache | Oui |
| S16 | <https://spec.openapis.org/oas/v3.1.0.html> | 2026-11-19 | OpenAPI 3.1.0, du 2021-02-15, sur-ensemble de JSON Schema 2020-12 | Oui |
| S17 | <https://github.com/redhat-developer/yaml-language-server> | 2026-11-19 | Validation et complétion YAML par JSON Schema, 2020-12 pris en charge, MIT | Oui |
| S18 | <https://cuelang.org/docs/introduction/installation/> | 2026-11-19 | `brew install cue`, binaires Linux, Windows et macOS | Oui |
| S19 | <https://github.com/cue-lang/cue> | 2026-11-19 | Apache-2.0, organisation cue-lang, ni GOVERNANCE ni MAINTAINERS | Oui |
| S20 | <https://github.com/cue-lang/cue/releases> | 2026-11-19 | v0.17.1 marquée « Latest », v0.18 en préversions | Oui |
| S21 | <https://proxy.golang.org/cuelang.org/go/@v/v0.17.1.info> | 2026-11-19 | v0.17.1 le 2026-07-16 | Oui |
| S22 | <https://proxy.golang.org/cuelang.org/go/@v/v0.17.0.info> | 2026-11-19 | v0.17.0 le 2026-06-22 | Oui |
| S23 | <https://proxy.golang.org/cuelang.org/go/@v/v0.16.1.info> | 2026-11-19 | v0.16.1 le 2026-04-08 | Oui |
| S24 | <https://proxy.golang.org/cuelang.org/go/@v/v0.16.0.info> | 2026-11-19 | v0.16.0 le 2026-03-03 | Oui |
| S25 | <https://proxy.golang.org/cuelang.org/go/@v/v0.0.2.info> | 2026-11-19 | v0.0.2 le 2019-06-22 | Oui |
| S26 | <https://github.com/cue-lang/cue/releases.atom> | 2026-11-19 | v0.18.0-rc.4 le 2026-11-11 | Oui |
| S27 | <https://github.com/cue-lang/cue/blob/master/SECURITY.md> | 2026-11-19 | Signalement par courriel à une adresse dédiée du domaine cuelang.org, aucun délai annoncé | Oui |
| S28 | <https://osv.dev/list?q=cuelang.org%2Fgo&ecosystem=Go> | 2026-11-19 | Aucune vulnérabilité pour cuelang.org/go | Oui, base OSV |
| S29 | <https://github.com/cue-lang/cue/security> | 2026-11-19 | Aucun avis de sécurité publié | Oui |
| S30 | <https://cue.dev/blog/announcing-cue-labs> | 2026-11-19 | CUE Labs, le 2025-10-30 : « stewards » du projet, modèle open core, fonds de capital-risque | Oui |
| S31 | <https://github.com/cue-lang/cue-py> | 2026-11-19 | Liaison Python en chantier, aucune release | Oui |
| S32 | <https://cuelang.org/docs/concept/how-cue-works-with-yaml/> | 2026-11-19 | Validation d'un YAML par `cue vet -c -d` | Oui |
| S33 | <https://pkl-lang.org/main/current/pkl-cli/index.html> | 2026-11-19 | `brew install pkl`, version 0.33.1, plateformes natives, Java 17 pour `jpkl`, options `--allowed-modules` (défaut avec `https:`) et `--allowed-resources` | Oui |
| S34 | <https://github.com/apple/pkl> | 2026-11-19 | Apache-2.0, organisation apple, pas de GOVERNANCE | Oui |
| S35 | <https://github.com/apple/pkl/blob/main/MAINTAINERS.adoc> | 2026-11-19 | Quatre mainteneurs, aucune affiliation affichée | Oui |
| S36 | <https://github.com/apple/pkl/releases.atom> | 2026-11-19 | Dix releases, de 0.30.0 le 2025-11-20 à 0.33.1 le 2026-11-18 | Oui |
| S37 | <https://github.com/apple/pkl/blob/main/SECURITY.md> | 2026-11-19 | Signalement par le formulaire d'Apple, aucun délai annoncé | Oui |
| S38 | <https://github.com/apple/pkl/security> | 2026-11-19 | Deux avis publiés le 2026-07-08, modéré et faible | Oui |
| S39 | <https://github.com/apple/pkl/security/advisories/GHSA-87qh-25w9-mh34> | 2026-11-19 | Avis modéré, corrigé en 0.32.0, sans CVE | Oui |
| S40 | <https://pkl-lang.org/blog/introducing-pkl.html> | 2026-11-19 | Première release open source annoncée le 2024-02-01 | Oui |
| S41 | <https://pkl-lang.org/main/current/language-bindings.html> | 2026-11-19 | Liaisons officielles Java, Kotlin, Swift, Go et libpkl, pas de Python | Oui |
| S42 | <https://pkl-lang.org/package-docs/pkl/current/base/Dynamic.html> | 2026-11-19 | Méthode `toTyped` | Oui |
| S43 | <https://pkl-lang.org/main/current/language-tutorial/03_writing_a_template.html> | 2026-11-19 | `amends`, propriétés typées, `pkl eval` | Oui |
| S44 | <https://formulae.brew.sh/formula/pkl> | 2026-11-19 | Formule homebrew-core pkl 0.33.1 | Oui, Homebrew |
| S45 | <https://formulae.brew.sh/formula/cue> | 2026-11-19 | Formule homebrew-core cue 0.17.1 | Oui, Homebrew |
| S46 | <https://github.com/score-spec/spec> | 2026-11-19 | Apache-2.0, schéma `score-v1b1.json`, score-compose et score-k8s | Oui |
| S47 | <https://raw.githubusercontent.com/score-spec/spec/main/score-v1b1.json> | 2026-11-19 | `additionalProperties: false` au premier niveau, `type` de ressource en chaîne libre | Oui |
| S48 | <https://github.com/score-spec/spec/releases.atom> | 2026-11-19 | 0.4.0 le 2026-04-17, 0.4.1 le 2026-05-25 | Oui |
| S49 | <https://github.com/score-spec/spec/blob/main/MAINTAINERS.md> | 2026-11-19 | Mainteneurs chez Oracle, Docker, Checkly et un indépendant | Oui |
| S50 | <https://github.com/score-spec/spec/blob/main/GOVERNANCE.md> | 2026-11-19 | Consensus, vote des mainteneurs, rien sur la version du schéma | Oui |
| S51 | <https://github.com/score-spec/spec/blob/main/ADOPTERS.md> | 2026-11-19 | Six adoptants, qui déploient tous avec `humctl` de Humanitec | Oui, tenue par le projet |
| S52 | <https://github.com/score-spec/spec/blob/main/roadmap.md> | 2026-11-19 | Aucune version stable ni date annoncée | Oui |
| S53 | <https://www.cncf.io/projects/score/> | 2026-11-19 | CNCF Sandbox depuis le 2024-07-08 | Oui |
| S54 | <https://github.com/score-spec/score-compose/releases.atom> | 2026-11-19 | Dix releases, de 0.41.0 le 2026-06-05 à 0.50.0 le 2026-11-14 | Oui |
| S55 | <https://github.com/score-spec/score-compose> | 2026-11-19 | Apache-2.0 | Oui |
| S56 | <https://github.com/score-spec/score-compose/security> | 2026-11-19 | Politique de sécurité, réponse visée sous dix jours ouvrés, aucun avis | Oui |
| S57 | <https://github.com/score-spec/spec/security> | 2026-11-19 | Même politique, aucun avis | Oui |
| S58 | <https://docs.score.dev/docs/score-implementation/score-compose/installation/> | 2026-11-19 | `brew install score-spec/tap/score-compose`, Go, Docker, téléchargement manuel | Oui |
| S59 | <https://github.com/score-spec/homebrew-tap> | 2026-11-19 | Tap Homebrew tenu par l'organisation score-spec | Oui |
| S60 | <https://opensource.org/licenses> | 2026-11-19 | Apache-2.0, MIT, BSD-3-Clause et AFL-3.0 approuvées par l'OSI | Oui |
| S61 | <https://osv.dev/list?q=jsonschema&ecosystem=PyPI> | 2026-11-19 | Aucune vulnérabilité pour jsonschema ; check-jsonschema : la CVE de S14 | Oui, base OSV |
| S62 | <https://osv.dev/list?q=github.com%2Fscore-spec&ecosystem=Go> | 2026-11-19 | Aucune vulnérabilité pour les modules score-spec | Oui, base OSV |
| S63 | <https://docs.score.dev/docs/score-implementation/score-k8s/resources-provisioners/> | 2026-11-19 | Types par défaut de score-k8s, aucun service managé de GCP | Oui |
| S64 | <https://docs.score.dev/docs/score-implementation/score-compose/resources-provisioners/> | 2026-11-19 | Types par défaut de score-compose dont `postgres` et `redis`, provisionneurs `cmd://` | Oui |
| S65 | <https://json-schema.org/tools?query=&sortBy=name&sortOrder=ascending&groupBy=toolingTypes&licenses=&languages=&drafts=2020-12&toolingTypes=validator> | 2026-11-19 | Validateurs JavaScript prenant en charge 2020-12, dont Ajv | Oui |

## 10. Relectures

| Relecteur | Porte sur | Date | Avis |
| --- | --- | --- | --- |
| [SECU] | Licences, critères éliminatoires, sécurité | à venir | à venir |
| [FINOPS] | Coût | à venir | à venir |

[SECU] Remarques et suite donnée.

[FINOPS] Remarques et suite donnée.
