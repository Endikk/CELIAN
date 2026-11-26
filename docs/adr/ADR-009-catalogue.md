# ADR-009. Un fichier YAML validé par brique, le managé d'abord sur le cloud, six mois entre deux vérifications

| Champ | Valeur |
| --- | --- |
| Statut | accepté |
| Date | 2026-11-19 |
| Auteur | [ARCHI] |
| Décideur | DSI, sur délégation de Lucas à la GATE 1 du 2026-11-20 |
| BENCH lié | aucun : le format reprend YAML et JSON Schema 2020-12, déjà retenus par l'[ADR-001](ADR-001-format-spec.md) sur la foi de BENCH-001, et la lecture des principes ne se mesure pas |
| Remplace | aucun |

## Contexte et problème

Le catalogue est le seul endroit du générateur qui nomme un service concret (principe II). Chaque entrée doit porter sa licence, sa gouvernance, son statut, la date de sa dernière vérification et au moins une source officielle, faute de quoi aucun blueprint ne peut s'en servir (principe IV). Le PRD en fait un critère testable : une entrée à qui manque l'un de ces cinq champs fait échouer la CI du générateur (US-004). `catalog/` est vide, et la première entrée attend : celle du cluster Kubernetes, que l'ADR-004 a décrite en tableau.

Trois questions sont à trancher avant d'écrire cette entrée.

La première porte sur le format. Le brief en donne un exemple indicatif (section 5) : une liste dans un seul fichier, avec la gouvernance, le statut, la date et les sources au niveau de la brique, partagés par toutes les cibles. Or l'entrée de l'ADR-004 associe kind, projet de la CNCF, à GKE, service de Google : ni la gouvernance, ni le statut, ni les sources ne sont communs. L'exemple du brief ne permet pas d'écrire cette entrée honnêtement. L'ADR-004 laisse aussi des champs ouverts (mode et canal du cluster GKE, condensats du binaire de kind pour les autres plateformes), qu'il faut pouvoir écrire sans inventer de valeur.

La deuxième porte sur deux principes qui se croisent sur le cloud. Le principe V veut qu'à fonctionnalité comparable le catalogue préfère un projet de fondation, et n'accepte un éditeur unique qu'avec un BENCH et un ADR. Le principe III impose sur une cible cloud les services managés du fournisseur, qui ont tous Google pour seul éditeur sur `gcp`. Lus à la lettre et ensemble, ils feraient de chaque service managé une dérogation. Le gabarit d'ADR dit déjà qu'un service managé imposé par le principe III ne demande pas la justification de V ([TEMPLATE.md](TEMPLATE.md)), et `ROADMAP.md` attend que Lucas valide cette lecture avant l'étape 6. Lucas étant absent, cet ADR l'écrit comme une proposition.

La troisième porte sur le vieillissement. R-06, catalogue qui se périme, est noté en probabilité forte. Sa mitigation, une revue datée à chaque phase, n'est outillée par rien : une licence qui change ou un projet archivé ne se verrait qu'au hasard d'une relecture.

Les contraintes viennent de l'ADR-001 : YAML lu par `yaml.safe_load` depuis PyYAML 5.4 au moins, JSON Schema 2020-12, aucun `$ref` distant, `pattern` et `maxLength` sur les chaînes, clés inconnues refusées. Elles viennent aussi du principe VI (critères éliminatoires, dont aucune release depuis 12 mois) et du principe VIII.

## Options considérées

Aucune option ne passe par un BENCH : le format ne fait entrer aucune techno, et la lecture des principes relève de la constitution.

| Option | Score BENCH (sur 100) | Verdict | Raison principale |
| --- | --- | --- | --- |
| A. Un fichier YAML par brique, traçabilité par cible, schéma dans `schema/` | sans BENCH | retenue | Une PR touche un fichier ; chaque cible porte sa propre gouvernance et ses sources ; les deux cibles du MVP sont exigées côte à côte (ENF-02) |
| B. Un seul `catalog.yaml`, format indicatif du brief | sans BENCH | écartée | Gouvernance, statut et sources partagés entre des produits qui n'ont rien en commun ; un seul fichier modifié par toutes les PR du catalogue |
| C. Un fichier par brique et par cible, `catalog/<id>/<cible>.yaml` | sans BENCH | écartée | La parité entre cibles ne se lit plus dans un fichier, et le schéma ne peut plus exiger les deux cibles |

Pour la lecture des principes III et V, trois lectures étaient possibles :

| Lecture | Verdict | Raison |
| --- | --- | --- |
| Littérale : chaque service managé déroge à V, avec un ADR | écartée | Une dérogation systématique n'en est plus une, et elle noierait les vrais écarts |
| V prime : un projet de fondation qui tourne sur GKE passe devant le service managé | écartée | Contraire au texte de III, qui écrit « DOIT » |
| III fixe les candidats, V les départage | retenue | Les deux principes gardent un effet, sans dérogation de principe |

## Décision

### 1. Format du catalogue

Chaque brique abstraite a son fichier `catalog/<id>.yaml`, où `<id>` est le nom de la brique : celui de la spec quand elle la déclare (`declared_by: spec`), un nom propre au catalogue quand elle découle de la cible (`declared_by: target`, comme `kubernetes-cluster`). Le fichier porte une entrée par cible du MVP, `local` et `gcp`, toutes deux obligatoires.

Licence, gouvernance, statut, date de vérification et sources se tiennent par cible, pas par brique. C'est l'écart principal avec l'exemple du brief, qui reste indicatif.

Une cible est de type `oss` ou `managed` :

- `oss` exige une version exacte, une expression SPDX, la date de la dernière release amont, la gouvernance (`foundation`, `community` ou `single-vendor`) ;
- `managed` exige le fournisseur (`google` dans le MVP), une gouvernance `single-vendor`, et refuse le champ `license` ;
- la cible `local` n'accepte que `oss` (principe III) ;
- la cible `gcp` accepte `managed`, ou `oss` accompagné de `managed_gap`, qui dit pourquoi aucun service managé ne couvre le besoin (section 2).

Chaque cible porte aussi les ADR et BENCH qui l'ont fait entrer (`decisions`, un ADR au moins), les standards qu'elle expose (`standards`), des condensats de binaires facultatifs (`artifacts`) et la liste de ses champs ouverts (`pending`). Le détail des champs est dans [catalog/README.md](../../catalog/README.md).

Le schéma vit dans [`schema/catalog-entry.schema.json`](../../schema/catalog-entry.schema.json), pour trois raisons. `schema/` regroupe les schémas du générateur, et les conditions de l'ADR-001 (aucun `$ref` distant, chaînes bornées) s'y appliquent d'un bloc. La CLI chargera ses schémas depuis un seul dossier. `catalog/` ne contient que des entrées et son README, si bien que le contrôle lit `catalog/*.yaml` sans exception à gérer. `CLAUDE.md` décrit `schema/` comme le dossier du JSON Schema « de la spec projet » : la ligne est à compléter par le DSI.

Un champ inconnu ne s'invente pas. Un champ obligatoire inconnu empêche l'entrée d'exister. Un choix ouvert qui n'est pas un champ du schéma va dans `pending`, avec son porteur. Une cible qui a des `pending` est une entrée valide, qu'aucun blueprint ne peut encore utiliser : le principe IV interdit l'usage d'une entrée incomplète, pas son écriture.

Trois faits de l'outillage fixent des règles d'écriture :

- PyYAML convertit une date sans guillemets en `datetime.date`, y compris par `safe_load`, et le schéma attend une chaîne. Les dates s'écrivent donc entre guillemets, ce qui rend le fichier indépendant du chargeur ;
- PyYAML ne détecte pas les clés en double, par choix documenté dans son code. Un `license` écrit deux fois garderait la dernière valeur sans bruit : le contrôle doit refuser les doublons ;
- en 2020-12, `format` n'est qu'une annotation par défaut, et python-jsonschema ne le vérifie pas sans `format_checker`. Le schéma pose donc un `pattern` sur les dates, et le contrôle vérifie qu'elles existent au calendrier.

Restent hors du catalogue : les outils du générateur (ADR-001 à ADR-003), les condensats d'images de conteneurs, qui vivent dans le blueprint et que Renovate met à jour, et les technos écartées. Les pièges connus du brief servent de liste de contrôle à l'entrée de chaque brique.

### 2. Lecture des principes III et V sur le cloud

Règle proposée : le principe III fixe l'ensemble des candidats d'une cible, le principe V les départage. Sur `local`, les candidats sont les technos libres et gratuites, et V préfère celles d'une fondation. Sur `gcp`, ce sont les services managés de Google.

1. Sur `gcp`, le service managé du fournisseur qui couvre le besoin s'impose (III). Sa gouvernance d'éditeur unique ne demande ni BENCH ni ADR au titre de V, qui ne joue qu'« à fonctionnalité comparable » entre des candidats que III a déjà réduits à Google. Le choix entre deux services managés reste un choix d'architecture, tracé par un ADR : le schéma exige `decisions.adr` sur chaque cible.

2. V garde deux effets sur le cloud.

   a. Quand le fournisseur propose deux variantes managées, on préfère celle dont le moteur ou l'interface est porté par une fondation. L'exemple proposé tient, avec une nuance. Memorystore for Valkey est disponible en GA depuis le 2025-04-02 et prend en charge Valkey 7.2, 8.0, 9.0 et 9.1. Valkey est sous BSD-3-Clause, projet de LF Projects, et sa page d'accueil le dit « backed by the Linux Foundation ». Memorystore for Redis prend en charge Redis de 3.2 à 7.2, version par défaut, listée en 7.2.0 avec la date du 2024-02-29. Redis 7.2 est encore sous BSD-3-Clause ; c'est la suite qui ne l'est plus : 7.4 sous RSALv2 ou SSPLv1, 8.0 et après sous RSALv2, SSPLv1 ou AGPLv3. La préférence pour Valkey tient donc à la trajectoire du moteur, et au même moteur des deux côtés, puisque le brief prévoit Valkey sur le PC. La décision sur le cache reviendra à l'ADR de sa brique ; elle sert ici d'illustration.

   b. Quand aucun service managé ne couvre le besoin, un composant libre tourne sur le cloud, et V s'applique comme sur le PC. L'entrée `gcp` est alors de type `oss` et porte `managed_gap`. L'exemple proposé, Argo CD sur GKE, ne tient pas tel quel, et cet ADR le retire. Config Sync est décrit par Google comme « a GitOps service included with Google Kubernetes Engine (GKE) », et ne demande plus GKE Enterprise depuis sa version 1.22.0 du 2025-09-02. Pour Argo CD, la question devient : Config Sync couvre-t-il le besoin du blueprint ? Elle reste ouverte (question 3). Aucun autre exemple n'a été vérifié pour cet ADR.

3. Le catalogue note la gouvernance réelle de chaque service managé : `single-vendor`, `Google`, imposé par le schéma. La dépendance reste visible et se compte.

4. Le catalogue note le standard exposé (`standards`), parce que c'est lui qui tient le principe II : la spec nomme la brique, et le standard est ce que `local` et `gcp` partagent. Exemples vérifiés le 2026-11-19 : GKE s'administre par l'API Kubernetes ; le contrôleur Gateway de GKE est l'implémentation de Gateway API par Google, en GA ; Cloud SQL for PostgreSQL propose PostgreSQL 9.6 à 18, 18 par défaut ; les clients de Valkey parlent RESP ; la Telemetry API de Google Cloud implémente OTLP, sans que sa page dise quels signaux sont en GA. Une liste vide est permise et dit que la couche de cible porte toute la différence ; le contrôle avertit alors.

5. Principe IV pour un service managé. La licence est sans objet : un service managé est propriétaire et tourne sous les conditions du fournisseur, ce que disent `type: managed` et `provider`. Le schéma refuse `license` sur une cible `managed`, pour qu'aucun identifiant SPDX de façade n'y apparaisse.

Cette lecture a un effet immédiat sur BENCH-004, en cours. Sur `gcp`, le contrôleur Gateway de GKE est le service managé qui implémente Gateway API. L'option que BENCH-004 retiendra vaudra pour `local`, et pour `gcp` seulement avec un `managed_gap`.

### 3. Règle de fraîcheur

Le contrôle du catalogue échoue :

- quand `verified_on` a six mois calendaires ou plus : une entrée vérifiée le 2026-11-19 échoue à partir du 2027-05-19. Il avertit pendant le dernier mois ;
- quand une cible `oss` n'a pas eu de release depuis 12 mois calendaires, d'après `last_release_on`. C'est le critère éliminatoire du principe VI, calculé au lieu d'être relu. Pour kind, l'échéance tombe le 2027-08-26, la date que l'ADR-004 donne déjà ;
- quand `status` vaut autre chose que `active` ;
- quand `verified_on` diffère du `read_on` le plus récent des sources de la cible. On ne peut pas avancer la date sans avoir relu au moins une source ;
- quand un `read_on` des sources a six mois calendaires ou plus, avec le même avertissement pendant le dernier mois. Ajout de la relecture [SECU] du 2026-11-19 : sans cette règle, une entrée relue aujourd'hui passerait avec une source lue en 2023, et la relecture de la PR serait seule à le voir.

Le mois calendaire se compte au jour anniversaire ; quand ce jour n'existe pas (un 31, un 29 février), on prend le dernier jour du mois. Le jour de référence est la date UTC de l'exécution.

Le contrôle tourne sur chaque PR et chaque push sur `main`, sur toutes les entrées et pas seulement celles que la PR modifie, en bloquant. Il tourne aussi chaque semaine sur `main`, par une tâche planifiée. La PR est la vraie barrière ; la tâche planifiée sert d'alarme quand personne n'ouvre de PR. Seule, elle ne suffirait pas : GitHub désactive les tâches planifiées d'un dépôt public après 60 jours sans activité, n'en notifie que le dernier auteur de la ligne `cron`, et peut les retarder en période de charge.

Pourquoi six mois :

- c'est la cadence que les ADR se donnent déjà : l'ADR-001 et l'ADR-004 fixent leur prochaine vérification au 2027-05-19, six mois après leur date ;
- le critère des 12 mois sans release se calcule désormais sans relecture. Ce qui reste à attraper en relisant, c'est un changement de licence, de statut ou de gouvernance, et six mois bornent ce retard à la moitié de la fenêtre du principe VI ;
- trois mois doubleraient les relectures pour une équipe d'une personne. Douze mois égaleraient la fenêtre du principe VI, et un projet archivé pourrait rester un an au catalogue.

La charge se mesure en phase 3, quand le nombre de briques sera connu.

### Portée

Restent hors de cette décision : le contenu du schéma de spec v1 et le lien entre ses composants et les fichiers du catalogue (phase 3), le comportement de la CLI chez l'utilisateur quand son catalogue a vieilli (phase 5), et les entrées autres que `kubernetes-cluster`, chacune avec son ADR. Le contrôle en CI est écrit par [DEV] dans la même PR que cet ADR (`scripts/catalog/`, `tests/catalog/`).

## Conséquences

### Positives

- Une entrée incomplète échoue au schéma, avec le chemin du champ et la raison (US-004). Les exemples invalides de `tests/catalog/invalid/` le montrent, chacun avec son test.
- Le principe III se lit dans le schéma : pas de service managé sur le PC, pas de composant libre sur `gcp` sans raison écrite.
- La dépendance à Google se compte : chaque cible `gcp` dit sa gouvernance et le standard qui permettrait d'en sortir.
- R-06 passe d'une revue à faire de mémoire à une échéance que la CI fait respecter, et le critère des 12 mois du principe VI se calcule seul.
- L'entrée de l'ADR-004 s'écrit sans inventer de valeur : le mode et le canal de GKE sont dans `pending`. Les condensats de kind, d'abord en `pending`, ont été recoupés sur les fichiers `.sha256sum` de la release v0.33.0 le 2026-11-19, puis ajoutés.

### Négatives

- Une entrée qui atteint six mois bloque toutes les PR, y compris celles qui n'y touchent pas, jusqu'à sa relecture. C'est voulu, et l'avertissement d'un mois sert à ne pas en arriver là.
- Le schéma ne porte pas tout : dates par rapport au jour, nom du fichier, existence des ADR, licences acceptées et doublons demandent un script, écrit et testé dans `scripts/catalog/`.
- Les licences acceptées sont une liste blanche écrite par CELIAN (`scripts/catalog/accepted-licenses.yaml`), chacune avec sa source d'approbation sur opensource.org et sa date de lecture. La liste SPDX complète n'est pas versionnée : sa licence n'est déclarée nulle part (relecture [SECU] du 2026-11-19, cinq sources officielles lues). Chaque licence ajoutée passe par une PR relue par [SECU].
- Les listes fermées du schéma (standards, fournisseur, plateformes, rôles) demandent une PR sur le schéma pour chaque valeur nouvelle.
- Un service managé n'a pas de champ de licence. La lecture du principe IV qui le permet est à valider (question 2).
- Le `$` du module `re` de Python accepte aussi la position « just before the newline at the end of the string ». Si python-jsonschema évalue `pattern` avec ce module, point non vérifié pour cet ADR, une chaîne écrite en bloc YAML peut passer un `pattern` qui devrait la refuser. [DEV] le vérifie, et le contrôle refuse à part toute chaîne qui finit par un saut de ligne.
- Le nom `kubernetes-cluster` reste provisoire, comme l'écrit l'ADR-004, jusqu'à la phase 3.

### Effet sur les cibles hors MVP

La porte reste ouverte. Une cible AWS ou Azure s'ajoute par une version du schéma qui déclare sa clé sous `targets`, sur le modèle de `gcp`, et une valeur de plus dans la liste des fournisseurs. Une cible on-prem serveurs suivrait le modèle de `local`, en `oss` seulement, comme le veut le principe III. Les entrées existantes ne changent pas, sinon pour recevoir leur ligne de plus.

### Questions ouvertes

1. Lecture des principes III et V (section 2), pour Lucas à la GATE 1.
2. Principe IV pour un service managé : `type: managed` et `provider` à la place d'une licence (section 2, point 5), pour Lucas.
3. GitOps sur `gcp` : Config Sync est inclus dans GKE, alors que le brief prévoit Argo CD et que Q6 parle d'une « structure Argo CD ». Avec la lecture proposée, Argo CD sur GKE demande un `managed_gap` qui établit ce que Config Sync ne couvre pas. Le DSI a ouvert BENCH-009 le 2026-11-19 pour trancher avant le golden repo de la phase 2.
4. Valeur de six mois et blocage de toutes les PR (section 3), pour Lucas. La relecture [SECU] du 2026-11-19 relève qu'une entrée expirée bloquerait aussi les correctifs de sécurité, sans acteur de contournement dans le ruleset de `main`. Son avis : les règles de date ne bloquent que les PR qui touchent `catalog/` et les PR de release, et la tâche hebdomadaire ouvre une issue en cas d'échec. Le changement tient à `always_run` dans `.pre-commit-config.yaml` et aux constantes de `scripts/catalog/catalog_rules.py`.
5. Lecture stricte des expressions de licence : chaque opérande d'un `OR` doit figurer dans la liste blanche, et aucune exception `WITH` n'est acceptée tant que la liste des exceptions est vide. Gardée par [SECU], pour Lucas.

### Réponses de la GATE 1 (2026-11-20)

- Lecture des principes III et V : Lucas retient celle de cet ADR. III fixe
  les candidats d'une cible, V départage.
- Non tranchées, donc gardées telles qu'écrites : la portée de la règle de
  fraîcheur, qui bloque toutes les PR (l'avis de [SECU] proposait de ne
  bloquer que les PR qui touchent `catalog/` et les PR de release), et la
  lecture stricte des expressions de licence.

### Complément du 2026-11-26 : le principe III devient une option

Décision de Lucas du 2026-11-26 : sur un cloud, le service managé est une option
parmi d'autres, et l'analyse de l'entretien choisit brique par brique, avec une
raison écrite. Le principe III passe en version 2.0.0 de la constitution. Le
texte ci-dessus reste celui du 2026-11-19 ; voici ce que le complément en
change.

1. Le principe III ne fixe plus un candidat unique sur une cible cloud. Les
   candidats d'une brique sont l'option managée, l'option auto-hébergée dans le
   cluster et les montages hybrides. La lecture « III fixe les candidats, V
   départage » tient, sur un ensemble de candidats plus large. La phrase de la
   section 2 selon laquelle le service managé « s'impose » sur `gcp`, et
   l'obligation de `managed_gap` qui en découle, décrivaient la version 1.2.0 :
   elles ne valent plus.
2. Le catalogue liste, par cible cloud, l'option managée et l'option
   auto-hébergée quand les deux existent. Chacune porte ses propres faits
   (fournisseur ou licence, gouvernance, statut, date, sources, standards
   exposés), ceux dont l'entretien a besoin pour peser les critères du
   principe III : coût, charge d'exploitation, niveau de service, conformité et
   souveraineté, résidence des données, portabilité, compétences, volumétrie.
3. Le principe V départage toujours, entre options de même nature : deux
   services managés entre eux (section 2, point 2a), deux composants libres
   entre eux. Le choix entre managé et auto-hébergé revient à l'entretien, qui
   l'écrit dans la spec et dans un ADR du projet généré.
4. Sur `local`, rien ne change : `oss` seul, la meilleure option libre.

Le format des entrées (plusieurs options par cible, fin de `managed_gap`) est
entré le 2026-11-26, sur décision du DSI, sans attendre la phase 3 : la cible
`gcp` prend une option seule ou une liste de deux options, managée puis libre,
chacune avec `choose_when`, `validation` et `offered` ; une option non couverte
n'est jamais proposée (`schema/catalog-entry.schema.json`, `catalog/README.md`,
contrôle de `scripts/catalog/`). Le lien avec le champ de mode d'hébergement de
la spec v1 (US-013 du PRD) reste à la phase 3. Les ADR et benchmarks qui citent
`managed_gap` comme repli ou voie écartée décrivent l'état d'avant ; [ARCHI] les
relit et ne les complète que si une décision en dépend. Les entrées existantes
restent valides. Le tableau
de conformité ci-dessous date du 2026-11-19 et se lit contre la version 1.0.0.

## Conformité à la constitution

Vérifiée contre la [constitution](../../.specify/memory/constitution.md) en version 1.0.0. L'amendement 1.1.0 (PR #13) ne touche que la section « Périmètre du MVP ».

| Principe | Effet | Justification |
| --- | --- | --- |
| I. Rien sans test automatique | respecté | Chaque entrée passe le schéma et le contrôle en CI, et le contrôle a ses exemples valides et invalides |
| II. Spec abstraite, catalogue concret | respecté | Seul le catalogue nomme un service, et le champ `standards` dit ce que les deux cibles partagent |
| III. Managé sur le cloud, open source ailleurs | respecté | Le schéma refuse un service managé sur `local` et un composant libre sur `gcp` sans `managed_gap` |
| IV. Catalogue traçable | respecté | Licence, gouvernance, statut, date et source sont exigés par cible ; pour un service managé, la licence est sans objet (question 2) |
| V. Gouvernance ouverte d'abord | respecté | Lecture précisée en section 2 : V départage les candidats que III autorise |
| VI. Récent mais éprouvé | respecté | Le critère des 12 mois sans release et le statut se contrôlent à chaque PR |
| VII. Une commande pour démarrer | sans objet | Le catalogue est lu à la génération, pas au démarrage |
| VIII. Aucun fait de mémoire | respecté | Chaque source porte sa date de lecture, `verified_on` suit la plus récente, et les exemples de cet ADR sont sourcés ci-dessous |
| IX. Aucun secret dans le dépôt | respecté | Le schéma ne déclare aucun champ pour un secret et refuse les clés inconnues |
| X. Aucune dépense cloud sans accord | sans objet | Aucune ressource cloud |

### Dérogations

Aucune.

## Condition de révision

La décision se rouvre si l'un de ces faits se vérifie :

- Lucas ne retient pas la lecture des principes III et V, ou celle du principe IV pour les services managés ;
- un changement de licence, de statut ou de gouvernance reste plus de trois mois au catalogue avant d'être vu : la fenêtre de six mois se raccourcit ;
- la charge de relecture mesurée en phase 3 dépasse ce que l'équipe tient ;
- GitHub change le fonctionnement des tâches planifiées au point que l'alarme hebdomadaire ne tourne plus ;
- une cible hors MVP est ouverte : le schéma reçoit sa clé.

Sans l'un de ces faits, prochaine vérification le 2027-05-19.

## Sources

| Source | Lue le | Ce qu'elle établit |
| --- | --- | --- |
| [Constitution](../../.specify/memory/constitution.md), version 1.0.0 | 2026-11-19 | Principes II à VI et VIII ; dérogation par ADR |
| [docs/prd-mvp.md](../prd-mvp.md), US-003, US-004, ENF-02, ENF-06, Q6 | 2026-11-19 | Entrée incomplète qui fait échouer la CI ; brique présente sur les deux cibles ; « structure Argo CD » |
| [docs/brief-v1.0.md](../brief-v1.0.md), sections 5 et 6 | 2026-11-19 | Format indicatif d'une entrée ; pièges connus ; Valkey en cache, Argo CD en GitOps |
| [ADR-001](ADR-001-format-spec.md), conditions 1, 3 et 4 | 2026-11-19 | `yaml.safe_load`, PyYAML 5.4 au moins ; aucun `$ref` distant ; `pattern` et `maxLength` |
| [ADR-004](ADR-004-cluster-local.md), sections « Entrée au catalogue » et « Condition de révision » | 2026-11-19 | Entrée du cluster ; condensat darwin-arm64 ; champs ouverts ; échéance du 2027-08-26 |
| [docs/risques.md](../risques.md), R-06 | 2026-11-19 | Catalogue qui se périme, probabilité forte |
| <https://raw.githubusercontent.com/yaml/pyyaml/main/lib/yaml/constructor.py> | 2026-11-19 | `construct_yaml_timestamp` rend un `datetime.date` pour une valeur sans heure, et il est enregistré sur `SafeConstructor` ; aucune détection des clés en double, omission voulue selon un commentaire du code |
| <https://docs.python.org/3/library/re.html> | 2026-11-19 | `$` « Matches the end of the string or just before the newline at the end of the string » |
| <https://json-schema.org/draft/2020-12/json-schema-validation> | 2026-11-19 | Section 7.2.1 : l'évaluation de `format` comme assertion « MUST be disabled by default » ; `date` suit `full-date` de la RFC 3339 |
| <https://python-jsonschema.readthedocs.io/en/stable/validate/> | 2026-11-19 | « By default, as per the specification, no validation is enforced » pour `format` ; activation par un `format_checker` |
| <https://spdx.github.io/spdx-spec/v2.3.1/SPDX-license-expressions/> | 2026-11-19 | Grammaire des expressions SPDX ; opérateurs sensibles à la casse, identifiants non |
| <https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows> | 2026-11-19 | Tâches planifiées désactivées après 60 jours sans activité dans un dépôt public ; notification au dernier auteur du `cron` ; branche par défaut seule ; retards en période de charge |
| <https://docs.cloud.google.com/memorystore/docs/valkey/product-overview> | 2026-11-19 | Valkey 7.2, 8.0, 9.0 et 9.1 pris en charge |
| <https://docs.cloud.google.com/memorystore/docs/valkey/release-notes> | 2026-11-19 | GA le 2025-04-02 ; Valkey 9.1 en GA le 2026-09-24 |
| <https://docs.cloud.google.com/memorystore/docs/redis/supported-versions> | 2026-11-19 | Redis 3.2 à 7.2, 7.2 par défaut, correctif 7.2.0 du 2024-02-29 |
| <https://redis.io/legal/licenses/> | 2026-11-19 | Redis 7.2 et avant sous BSD-3-Clause ; 7.4 sous RSALv2 ou SSPLv1 ; 8.0 et après sous RSALv2, SSPLv1 ou AGPLv3 |
| <https://valkey.io/> | 2026-11-19 | Valkey « open source (BSD) », « backed by the Linux Foundation » |
| <https://github.com/valkey-io/valkey> | 2026-11-19 | Licence BSD-3-Clause ; « open community project under LF Projects » |
| <https://valkey.io/topics/protocol/> | 2026-11-19 | Les clients de Valkey parlent RESP, protocole conçu pour Redis |
| <https://docs.cloud.google.com/kubernetes-engine/config-sync/docs/overview> | 2026-11-19 | Config Sync, « a GitOps service included with Google Kubernetes Engine (GKE) » |
| <https://docs.cloud.google.com/kubernetes-engine/config-sync/docs/release-notes> | 2026-11-19 | 1.22.0 du 2025-09-02 : plus besoin de GKE Enterprise ; dernière version 1.25.2 du 2026-11-09 |
| <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/kubernetes-engine-overview> | 2026-11-19 | GKE, « a managed implementation of the Kubernetes open source container orchestration platform », piloté par l'API Kubernetes ; Autopilot recommandé, Standard pour des besoins précis |
| <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/gateway-api> | 2026-11-19 | Contrôleur Gateway de GKE, « Google's implementation of the Gateway API », en GA |
| <https://docs.cloud.google.com/sql/docs/postgres/db-versions> | 2026-11-19 | PostgreSQL 9.6 à 18, 18 par défaut |
| <https://www.postgresql.org/docs/current/protocol.html> | 2026-11-19 | Protocole frontend/backend en version 3.2, introduite avec PostgreSQL 18 |
| <https://docs.cloud.google.com/stackdriver/docs/reference/telemetry/overview> | 2026-11-19 | La Telemetry API « implements the OpenTelemetry Protocol » ; statut GA des signaux non indiqué |
| <https://www.cncf.io/projects/kubernetes/> | 2026-11-19 | Kubernetes gradué le 2018-03-06 |
| <https://www.cncf.io/projects/opentelemetry/> | 2026-11-19 | OpenTelemetry gradué le 2026-05-11 |
| <https://github.com/kubernetes-sigs/gateway-api> | 2026-11-19 | Gateway API, « a part of SIG Network », Apache-2.0 |
| <https://www.rfc-editor.org/rfc/rfc2606.html> | 2026-11-19 | Le domaine `.invalid` est réservé aux noms « sure to be invalid », d'où son usage dans `$id` et dans les exemples de test |
