# ADR-001. Spec projet en YAML, validée par un JSON Schema 2020-12

| Champ | Valeur |
| --- | --- |
| Statut | proposé |
| Date | 2026-11-19 |
| Auteur | [ARCHI] |
| Décideur | Lucas, en attente |
| BENCH lié | [BENCH-001](../benchmarks/BENCH-001-format-spec.md) |
| Remplace | aucun |

## Contexte et problème

La spec projet est la source de vérité de CELIAN. L'entretien l'écrit, la CLI la valide, le blueprint la lit pour générer le dépôt, et elle reste versionnée dans le projet généré (US-003). Son format et son langage de schéma doivent être fixés avant la phase 3, qui écrira le schéma v1 dans `schema/`.

Les exigences viennent du PRD. US-003 demande une spec qui ne contient que des briques abstraites, porte la version de son schéma, se fait refuser en nommant le champ fautif et la raison, n'accepte que les cibles de la matrice (PC et GCP dans le MVP), et se valide par la CLI seule. US-002 et US-004 la lisent et l'écrivent, US-010 relie ses champs aux ADR, et US-012 interdit qu'elle porte un identifiant. Côté constitution, le principe II d'abord, puis I, V, VI et VIII.

Deux contraintes viennent des décisions voisines : la CLI est écrite en Python ([ADR-003](ADR-003-langage-cli.md)), et Copier ([ADR-002](ADR-002-moteur-templates.md)) charge ses données depuis un fichier YAML avec `--data-file` (BENCH-001, section 4.5).

Versionnée dans le projet généré, la spec peut être modifiée par n'importe quel contributeur de ce projet. La CLI doit donc la lire comme une entrée non fiable.

BENCH-001 laisse enfin une question de lecture à cet ADR. Le texte de JSON Schema 2020-12 n'a pas été republié depuis le 2022-06-16, et deux dépendances du validateur Python n'ont rien publié depuis plus de douze mois. Il faut dire à quoi s'applique le critère éliminatoire « release de moins de 12 mois ».

## Options considérées

| Option | Score BENCH (sur 100) | Verdict | Raison principale |
| --- | --- | --- | --- |
| A. YAML et JSON Schema 2020-12 | 91 | retenue | Format mûr sans éditeur unique, trois erreurs sur trois signalées en une passe, validation dans la CLI Python par une bibliothèque |
| D2. Spec maison avec section Score | 83 | écartée | Deux schémas à tenir, dont une section qui suit un schéma Score sans version stable |
| B. CUE | 79 | écartée | Éditeur unique (CUE Labs), une erreur à la fois avec des cascades, binaire externe à appeler depuis la CLI |
| D1. Score seul | 74 | écartée | Ni cible ni région dans la spec, et un type de ressource en chaîne libre qui laisse passer `cloud-sql` |
| C. Pkl | 68 | écartée | Éditeur unique (Apple), aucune adoption en production documentée, aucune liaison Python officielle |

Aucune option n'est éliminée, avec la lecture du critère de release fixée à la section Décision. Le brief prévoyait trois options. Lucas a ajouté Score le 2026-11-19, noté sous deux usages parce qu'il ne couvre pas les champs de projet (cible, région).

Grille, mesures et sources : [BENCH-001](../benchmarks/BENCH-001-format-spec.md).

## Décision

La spec projet s'écrit en YAML et se valide contre un JSON Schema 2020-12 rangé dans `schema/`. La CLI la valide dans son propre processus avec la bibliothèque python-jsonschema, sans binaire externe ni modèle de langage. Chaque schéma fixe `$schema` sur 2020-12, et la spec porte la version du schéma qu'elle suit ; le nom de ce champ se fixe en phase 3.

### Lecture du critère de release

Le critère « release de moins de 12 mois » s'applique au validateur maintenu, python-jsonschema. Il ne s'applique pas au texte de la spécification JSON Schema : une spécification stable n'a pas à être republiée, et sa suite se prépare au groupe de travail jsonschema de l'IETF, actif (BENCH-001, section 3). [SECU] juge cette lecture défendable.

Il ne s'applique pas non plus aux dépendances transitives du validateur, referencing (dernière version le 2025-10-13) et jsonschema-specifications (le 2025-09-08). Le critère juge un choix de techno, pas l'arbre de ses dépendances. Elles restent figées dans le verrou de la CLI, et une faille sans correctif chez l'une d'elles rouvre la décision.

La dernière version de python-jsonschema, 4.26.0, date du 2026-01-07. La décision se revérifie donc le 2027-01-07 : sans nouvelle version à cette date, le validateur tombe sous le critère (R-24).

### Conditions

1. Parseur YAML. La CLI lit la spec comme une entrée non fiable. Avec PyYAML, elle n'appelle que `yaml.safe_load` et exige PyYAML 5.4 au minimum : quatre failles critiques permettaient d'exécuter du code depuis un YAML hostile par `load` ou `full_load`, corrigées en 5.1, 5.2, 5.3.1 et 5.4. Le choix du parseur revient à [DEV] (BENCH-001, section 8). Un autre parseur passe d'abord par une relecture [SECU] de son mode de chargement.
2. Noms des composants. Les briques abstraites prennent les noms des types de Score (`postgres`, `redis`). Cela ne coûte rien et garde ouverte l'option D2, par une version majeure du schéma de spec, si Score publie un schéma stable.
3. Aucune référence distante. Aucun `$ref` des schémas de `schema/` ne vise une adresse réseau. Un schéma tiers se copie dans le dépôt sans modification, se fige par son empreinte, et garde son avis de licence et de copyright (Apache-2.0, section 4). L'essai du BENCH le fait déjà pour le schéma Score, dans `tests/bench/bench-001/vendor/score-spec/`.
4. Chaînes du schéma v1. Toute chaîne qui finit dans un chemin, un nom de ressource ou une commande porte un `pattern` strict et une `maxLength`. Le schéma de l'essai pose un `pattern` sur le nom du projet et la région, sans `maxLength` : la phase 3 complète. Le schéma refuse aussi les clés inconnues, comme dans l'essai, et ne déclare aucun champ destiné à un secret.

### Portée

La décision fixe le contenant de toutes les briques abstraites, sans en ajouter aucune. Elle traite les cibles `local` et `gcp` de la même façon : une cible est une valeur de la spec, et seul le catalogue nomme le service concret (principe II).

JSON Schema et python-jsonschema sont des outils du générateur, pas des briques des projets générés. Ils n'entrent pas dans `catalog/`, qui traduit une brique pour une cible. Leur licence, leur gouvernance, leur statut et leur date de vérification sont dans BENCH-001, et leur version se fige dans le verrou de la CLI.

Restent hors de cette décision : le contenu du schéma v1 (phase 3), les questions de l'entretien (phase 5), la structure de `catalog/`, le choix du parseur YAML par [DEV], et l'usage de check-jsonschema en pre-commit ou en CI.

## Conséquences

### Positives

- La CLI couvre les cinq points de US-003 sans rien appeler hors de son processus (BENCH-001, section 4.5).
- Toutes les erreurs arrivent en une passe : trois sur trois dans l'essai, chacune avec le chemin du champ et la raison. Une spec fautive demande un tour de la boucle de correction de la phase 5, là où CUE et Pkl en demanderaient jusqu'à trois, chacun payé en tokens par l'utilisateur (R-03).
- Un produit concret à la place d'une brique abstraite est refusé : `cloud-sql` échoue sur l'énumération des composants, alors que le schéma de Score seul le laisse passer.
- Copier reçoit la spec telle quelle, et l'éditeur la complète et la valide par le serveur de langage YAML, qui prend en charge 2020-12.
- La validation coûte 123,5 ms et 41,0 Mio par uvx, presque tout pour le démarrage de Python. Dans la CLI, elle ne relancera pas l'interpréteur.

### Négatives

- Le validateur repose sur un auteur principal (135 des 145 commits humains des 12 derniers mois), n'a publié qu'une version en douze mois et ne maintient que la dernière. Sa politique de sécurité tient en une adresse et une réponse « de son mieux » sous 48 heures (R-24). D'autres validateurs prennent en charge 2020-12, dont Ajv en JavaScript ; aucun validateur Python de remplacement n'a été évalué.
- JSON Schema n'a ni fondation ni entité juridique, et ses règles de gouvernance ne sont pas ratifiées. Son entrée à l'OpenJS, annoncée en 2022, n'a jamais abouti.
- La future norme de l'IETF pourra s'écarter de 2020-12. Le `$schema` figé protège la spec, mais une migration demandera un nouvel ADR.
- Les messages donnent un chemin JSON, sans numéro de ligne. [DEV] jugera s'il faut retrouver la ligne depuis le chemin.
- Une règle conditionnelle (`if` et `then`), comme la région exigée dès que `gcp` est ciblé, rend le schéma verbeux.
- Le BENCH n'a pas évalué le parseur YAML : sa sûreté repose sur la condition 1.

### Effet sur les cibles hors MVP

La porte reste ouverte. Une cible est une valeur d'énumération : ajouter AWS ou Azure revient à publier une version du schéma qui accepte cette valeur, le jour où la matrice la couvre (US-003), et à ajouter leurs lignes au catalogue.

### Questions ouvertes

Question de [FINOPS], non tranchée ici : la CI des projets générés revalidera-t-elle la spec ? Si oui, chaque exécution consomme des minutes, décomptées de l'allocation du compte sur un dépôt privé (R-16). Le schéma et un validateur entreraient aussi dans le projet généré, qui doit fonctionner sans CELIAN (ENF-07), et leur place au catalogue se reposerait.

## Conformité à la constitution

Vérifiée contre la [constitution](../../.specify/memory/constitution.md) en version 1.0.0.

| Principe | Effet | Justification |
| --- | --- | --- |
| I. Rien sans test automatique | respecté | La CLI valide chaque spec avant toute génération, et les exemples de spec de la phase 3 passent dans la CI du générateur (US-003) |
| II. Spec abstraite, catalogue concret | respecté | Les composants sont des énumérations de briques abstraites, un produit concret est refusé, et un test vérifie qu'aucun nom du catalogue n'apparaît dans la spec (US-003) |
| III. Managé sur le cloud, open source ailleurs | sans objet | Format de la spec, pas un service d'une cible |
| IV. Catalogue traçable | sans objet | Aucune entrée au catalogue : outils du générateur, tracés dans BENCH-001 |
| V. Gouvernance ouverte d'abord | respecté | Aucun éditeur unique ; le seul projet de fondation, Score, ne couvre pas la même fonction (voir ci-dessous) |
| VI. Récent mais éprouvé | respecté | Aucun critère éliminatoire touché avec la lecture fixée ici ; 2020-12 stable depuis le 2022-06-16 |
| VII. Une commande pour démarrer | sans objet | La validation tourne à la génération, hors de `task up` |
| VIII. Aucun fait de mémoire | respecté | Chaque fait renvoie à BENCH-001, sources lues le 2026-11-19 |
| IX. Aucun secret dans le dépôt | respecté | Le schéma ne déclare aucun champ pour un secret et refuse les clés inconnues (condition 4, US-012) |
| X. Aucune dépense cloud sans accord | sans objet | Aucune ressource cloud |

Principe V, précisé comme le demande BENCH-001. JSON Schema ne dépend d'aucun éditeur sans être porté par une fondation : sa normalisation passe par l'IETF. Score est le seul projet de fondation parmi les options (CNCF Sandbox), mais il ne décrit que des charges de travail, sans cible ni région. La préférence du principe joue « à fonctionnalité comparable », ce qui n'est pas le cas ici. Le validateur Python, porté par une personne, est suivi par R-24.

### Dérogations

Aucune.

## Condition de révision

La décision se rouvre si l'un de ces faits se vérifie :

- au 2027-01-07, python-jsonschema n'a publié aucune version après 4.26.0 ; la première piste est alors un autre validateur 2020-12, le format restant le même ;
- python-jsonschema, referencing ou jsonschema-specifications fait l'objet d'un avis de sécurité sans version corrigée ;
- python-jsonschema change de licence, passe en maintenance ou est archivé ;
- Score publie une version stable de son schéma : D2 s'évalue, par une version majeure du schéma de spec ;
- l'IETF publie la norme JSON Schema (jalon du 2027-05-31) ;
- l'essai refait sur le schéma v1 en phase 3 place une autre option devant A.

Sans l'un de ces faits, prochaine vérification le 2027-05-19.

## Sources

Ce que BENCH-001 établit se cite par lui ; ses propres sources sont dans sa section 9.

| Source | Lue le | Ce qu'elle établit |
| --- | --- | --- |
| [BENCH-001](../benchmarks/BENCH-001-format-spec.md), sections 3 et 10 | 2026-11-19 | Critères éliminatoires ; texte de 2020-12 non republié depuis le 2022-06-16 ; dépendances transitives sans release depuis plus de 12 mois ; avis de [SECU] sur la lecture du critère |
| BENCH-001, sections 4.4 et 4.5 | 2026-11-19 | Mesures M1 à M3 ; essai : trois erreurs en une passe, chemin JSON sans ligne, clés inconnues refusées, `cloud-sql` accepté par le schéma Score ; `copier copy --data-file` |
| BENCH-001, sections 5 à 7 | 2026-11-19 | Notes et totaux ; gouvernance de JSON Schema et de Score ; réserves sur python-jsonschema ; vérification du 2027-01-07 ; réserve PyYAML ; suites sur les noms Score, les références distantes, `pattern` et `maxLength` |
| BENCH-001, section 8 | 2026-11-19 | Parseur YAML non évalué ; essai à refaire sur le schéma v1 |
| [docs/prd-mvp.md](../prd-mvp.md), US-002, US-003, US-004, US-010, US-012, ENF-07 | 2026-11-19 | Exigences sur la spec et sur le projet généré |
| [docs/risques.md](../risques.md), R-03, R-16, R-24 | 2026-11-19 | Coût des tours de correction ; allocation GitHub Actions d'un dépôt privé ; validateur porté par une personne, 135 des 145 commits humains |
