# ADR-002. Copier génère et met à jour les projets, sous conditions

| Champ | Valeur |
| --- | --- |
| Statut | accepté |
| Date | 2026-11-19 |
| Auteur | [ARCHI] |
| Décideur | DSI, sur délégation de Lucas à la GATE 1 du 2026-11-20 |
| BENCH lié | [BENCH-002](../benchmarks/BENCH-002-moteur-templates.md) |
| Remplace | aucun |

## Contexte et problème

La CLI doit générer un dépôt depuis le blueprint SaaS B2B, puis le mettre à jour quand le blueprint évolue. Le moteur de templates porte ces deux gestes, et son choix pèse sur la forme des blueprints que la phase 3 écrira.

US-004 veut que deux générations depuis la même spec et la même version du blueprint donnent une partie déterministe identique, fichier par fichier. US-011 veut qu'un projet généré en version N reçoive la version N+1 sans repasser par l'entretien, que les modifications de l'équipe soient conservées hors conflit, et que les conflits soient listés fichier par fichier ; la matrice de la phase 4 rejoue ce passage. ENF-06 demande que le dépôt enregistre la version du blueprint qui l'a produit. ENF-07 veut qu'il fonctionne sans CELIAN, seule la mise à jour demandant le moteur. S'y ajoutent les principes I, V, VI et VIII, et trois risques : R-11 (conflits de mise à jour), R-22 (jour 2 dépendant d'un seul outil communautaire) et R-23 (modèle de confiance de Copier).

La grille du brief (section 8) ne contient pas la mise à jour. BENCH-002 l'a donc posée comme prérequis éliminatoire, tiré de US-011 : une option qui ne sait pas mettre à jour un projet modifié localement, en gardant ses modifications, est éliminée. Tout le verdict repose sur ce prérequis. Sans lui, Cookiecutter et Yeoman resteraient en lice et seraient notés. Le DSI l'a accepté le 2026-11-19, et Lucas a accepté le même jour le prérequis et le verdict à une seule option qui en découle.

Le moteur relira, à chaque mise à jour, un fichier versionné dans le projet généré. N'importe quel contributeur du projet peut le modifier : c'est une entrée non fiable (R-23).

## Options considérées

| Option | Score BENCH (sur 100) | Verdict | Raison principale |
| --- | --- | --- | --- |
| Copier | 80 | retenue | Seule option qui met à jour un projet modifié : fusion propre, conflit signalé, fichiers de l'équipe conservés, trois exécutions sur trois |
| Cookiecutter, avec cruft pour la mise à jour | éliminée, non notée | éliminée | Jour 2 : Cookiecutter seul n'a aucune commande de mise à jour et écrase ou ignore en silence ; cruft, qui fusionne, n'a rien publié depuis le 2024-12-25 (critère de release) |
| Yeoman | éliminée, non notée | éliminée | Jour 2 : chaque fichier existant se garde ou s'écrase, sans fusion ; en mode non interactif, échec ou écrasement silencieux |

Le verdict repose sur une seule option notée : le total de 80 ne se compare à aucun autre. Le repli de R-22, une branche dédiée au gabarit puis une fusion Git (le mécanisme de JHipster), a été essayé à titre de référence, sans être noté. Il a donné le même résultat que Copier sur le gabarit jouet, conflit compris, trois fois sur trois.

Grille, mesures et sources : [BENCH-002](../benchmarks/BENCH-002-moteur-templates.md).

## Décision

La CLI de CELIAN utilise Copier pour générer un projet depuis un blueprint et pour le mettre à jour. Elle l'appelle comme bibliothèque, dans son processus, par `run_copy` et `run_update` ([ADR-003](ADR-003-langage-cli.md)).

Le verdict repose sur une seule option notée et sur le prérequis du jour 2, que Lucas a acceptés le 2026-11-19. La validation d'ensemble de cet ADR reste à faire à la GATE 1.

### Conditions

Elles reprennent les mesures de R-23, le constat de R-11 et la section 7 de BENCH-002. La décision ne vaut qu'avec elles.

1. Versions minimales. La CLI refuse de démarrer avec Copier antérieur à 9.19.0 ou Jinja2 antérieur à 3.1.6, versions lues par `importlib.metadata`. Jinja2 3.1.6 corrige la dernière évasion du bac à sable de Jinja2 relevée par le BENCH (CVE-2025-27516).
2. Version figée. Copier se fige dans le verrou de la CLI, en 9.19.1 à la date de cet ADR, avec un plafond `<10`. La version minimale suit le dernier avis de sécurité : chaque avis la relève et demande une release de la CLI.
3. Source des blueprints. La CLI ne rend que les blueprints de CELIAN, désignés par un `vcs_ref` qui est un SHA de commit, jamais une étiquette ni une branche.
4. Contrôle avant mise à jour. La CLI vérifie `_src_path` et `_commit` dans `.copier-answers.yml` avant toute mise à jour : la source doit être un blueprint de CELIAN, et le commit un SHA de ce blueprint. Sinon, elle refuse. Un `_src_path` piégé est le vecteur que cite GHSA-g3fv-fhjg-54xh pour les versions 9.14.0 à 9.18.x, sans que l'auteur de l'avis l'ait reproduit.
5. Aucune confiance accordée. Jamais `--trust` ni `unsafe=True`.
6. Blueprints sans code exécuté. Aucun `_tasks`, `_migrations` ni `_jinja_extensions` dans les blueprints. Un test de la CI du générateur le vérifie.
7. Réglages isolés. La CLI pointe `COPIER_SETTINGS_PATH` vers un fichier de réglages sans liste `trust`, pour qu'aucun réglage du poste n'accorde la confiance à un gabarit.
8. Veille. [SECU] relit chaque semaine la page des avis de copier-org/copier, tant que la base mondiale des avis de GitHub et OSV restent en retard : 8 des 15 avis y manquent, et les scanneurs qui les lisent jugent saines des versions vulnérables. Une montée de version de sécurité se décide à la main après cette relecture. Elle n'attend pas les 7 jours que le principe VI impose aux mises à jour automatiques : lecture de la constitution validée par Lucas le 2026-11-19.
9. Conflits contrôlés par Git. La CLI ne se fie pas au code de sortie : Copier 9.19.1 rend 0 même quand un conflit reste (R-11). Après chaque mise à jour, elle lit `git diff --name-only --diff-filter=U`, cherche les marqueurs de conflit et liste les fichiers concernés, comme US-011 le demande. Avant, elle vérifie que le dépôt Git est propre, ce que Copier exige. La matrice de la phase 4 fait les mêmes contrôles.
10. Repli prêt. Le repli de R-22 reste la sortie prévue : régénérer la nouvelle version du gabarit sur une branche dédiée, partie du commit de génération, puis la fusionner par Git. Essayé trois fois avec Cookiecutter comme moteur de rendu, il a donné le même résultat que Copier, et il rend en plus le code 1 en cas de conflit. Il ne dépend d'aucun outil de mise à jour tiers, mais CELIAN devrait l'écrire et le maintenir. Le script `tests/bench/bench-002-day2.sh` le rejoue à chaque vérification de cette décision.

### Portée

Le moteur tourne sur le poste qui génère. Les cibles `local` et `gcp` ne le voient pas, et le contenu propre à chaque cible reste dans sa couche du blueprint (principe II).

Copier n'entre pas dans `catalog/` : c'est une dépendance de la CLI, pas un service d'une cible. Sa licence (MIT), sa gouvernance (organisation communautaire copier-org, sans fondation), son statut (actif) et sa date de vérification (2026-11-19) sont dans BENCH-002, et sa version se fige dans le verrou de la CLI.

Restent hors de cette décision : la découpe du blueprint entre socle et code de l'équipe (mitigation de R-11, phase 3), la matrice de la phase 4, et le nom de la commande de mise à jour (phase 5).

## Conséquences

### Positives

- US-011 tenu sur le gabarit jouet : fusion propre là où c'est possible, conflit signalé dans le fichier et marqué non fusionné par Git, fichiers de l'équipe conservés, trois exécutions sur trois.
- US-004 tenu : deux générations depuis les mêmes entrées donnent des fichiers identiques, trois fois sur trois.
- ENF-06 : le fichier de réponses enregistre la version du blueprint dans `_commit`.
- ENF-07 : le projet généré n'a besoin de Copier que pour se mettre à jour.
- Une génération coûte 0,48 s et 54,4 Mio au plus, lanceur uvx compris, et rien ne reste en mémoire ensuite.
- Le projet est actif : 23 releases et 21 contributeurs humains sur 12 mois.

### Négatives

- Ni fondation ni entreprise derrière Copier, et un mainteneur porte 76 % des commits humains de l'année (R-22).
- 15 avis de sécurité du 2025-08-18 au 2026-10-12, dont 8 élevés : dix évasions du mode « gabarit sûr », quatre contournements du préfixe de confiance, une injection d'argument Git. Un correctif a lui-même ouvert une faille. Le mode sûr et la confiance ne tiennent pas comme barrière (R-23), d'où les conditions 1 à 8.
- Coût d'exploitation relevé par [FINOPS] : la veille hebdomadaire, et une release de la CLI à chaque avis, soit 13 avis sur les 12 derniers mois.
- Le BENCH n'a mesuré qu'un gabarit jouet de quatre fichiers. Le vrai blueprint produira d'autres conflits, que la matrice de la phase 4 rejouera.
- Coût conditionnel : écrire et maintenir le repli si Copier ralentit.
- Les conditions ne tiennent que si la mise à jour passe par la CLI de CELIAN : Lucas l'a décidé le 2026-11-19 (voir plus bas).

### Effet sur les cibles hors MVP

La porte reste ouverte. Le moteur ignore la cible : une cible AWS ou Azure s'ajoutera comme une couche de plus du blueprint, sans changer de moteur.

### Questions ouvertes

1. Question de [FINOPS], non tranchée ici : le blueprint livrera-t-il un workflow planifié de `copier update` ? Sur un dépôt privé, chaque exécution consommerait des minutes décomptées de l'allocation du compte (R-16). Ce workflow lancerait aussi Copier en CI sur un fichier de réponses modifiable par tout contributeur : s'il existe, il tient les mêmes conditions que la CLI.

### Tranché par Lucas le 2026-11-19

Chemin de la mise à jour : elle passe par la CLI de CELIAN, qui appelle Copier sous les conditions ci-dessus. US-011 et le parcours du PRD sont modifiés en conséquence. Lancer `copier update` à la main reste possible, hors des garanties de CELIAN. Contexte de la question : US-011 et le parcours du PRD (section 3) faisaient lancer `copier update` par l'utilisateur. Lancée à la main, la mise à jour échappe à la plupart des conditions : la version de Copier est celle du poste, la source n'est pas vérifiée, réglages et confiance sont ceux de l'utilisateur, et les conflits ne sont pas listés. Faire passer la mise à jour par la CLI demanderait CELIAN pour le jour 2. ENF-07 ne l'interdit pas, puisqu'il ne range pas la mise à jour parmi ce qui fonctionne sans CELIAN, mais le texte de US-011 change.

## Conformité à la constitution

Vérifiée contre la [constitution](../../.specify/memory/constitution.md) en version 1.0.0.

| Principe | Effet | Justification |
| --- | --- | --- |
| I. Rien sans test automatique | respecté | Génération déterministe mesurée ; la matrice de la phase 4 rejoue la mise à jour de N à N+1 (US-011) ; un test refuse `_tasks`, `_migrations` et `_jinja_extensions` |
| II. Spec abstraite, catalogue concret | respecté | Le moteur ignore la cible ; le contenu propre à une cible reste dans sa couche du blueprint |
| III. Managé sur le cloud, open source ailleurs | sans objet | Outil du générateur, pas un service d'une cible |
| IV. Catalogue traçable | sans objet | Aucune entrée au catalogue ; licence, gouvernance, statut et date de Copier sont tracés dans BENCH-002 |
| V. Gouvernance ouverte d'abord | respecté, écart justifié | Pas de fondation et un mainteneur principal ; écart accepté par la clause du principe (voir ci-dessous) |
| VI. Récent mais éprouvé | respecté | Aucun critère éliminatoire touché : MIT, actif, 9.19.1 du 2026-10-13, majeure 9 stable depuis le 2023-10-22 |
| VII. Une commande pour démarrer | respecté | Le projet généré démarre sans Copier (ENF-07) |
| VIII. Aucun fait de mémoire | respecté | Chaque fait renvoie à BENCH-002, sources lues le 2026-11-19 |
| IX. Aucun secret dans le dépôt | respecté | Le fichier de réponses est versionné dans le projet, et aucune question de l'entretien ne demande un secret (US-002) |
| X. Aucune dépense cloud sans accord | sans objet | Aucune ressource cloud ; l'interdiction des `_tasks` retire aussi toute commande lancée à la génération |

Principe V. Copier n'a pas d'éditeur unique, mais pas de fondation non plus : l'organisation copier-org compte deux membres publics, et un seul mainteneur signe 91 des 120 commits humains des 12 derniers mois. Le principe accepte un tel écart quand un benchmark le justifie, avec un ADR. Le critère qui l'emporte est le prérequis du jour 2 (US-011), qu'aucune autre option ne remplit : l'outil de mise à jour de Cookiecutter n'a rien publié depuis le 2024-12-25, et Yeoman ne fusionne pas. La préférence du principe joue « à fonctionnalité comparable », et il n'existe pas d'option comparable. Dans la grille, l'activité (5/5, 23 releases en 12 mois) montre un projet vivant malgré cette concentration, et le repli de R-22, essayé, borne la dépendance.

### Dérogations

Aucune.

## Condition de révision

Bascule vers le repli de R-22, par un nouvel ADR qui remplace celui-ci, si l'un de ces faits se vérifie :

- Copier touche un critère éliminatoire : dépôt archivé ou en maintenance, licence qui n'est plus open source, ou aucune release pendant 12 mois (le décompte part de 9.19.1, du 2026-10-13, dernière release à ce jour) ;
- un avis de sécurité élevé ou critique touche la version figée et reste sans version corrigée 30 jours après sa publication, alors que tous les correctifs sont sortis jusqu'ici au plus tard le jour de l'avis ;
- sur le vrai blueprint, la matrice de la phase 4 montre que la mise à jour par Copier perd une modification de l'équipe ou tait un conflit, et que le repli passe.

La décision se rouvre, sans basculer d'office, dans trois cas :

- aucune release de Copier pendant 6 mois : le repli s'écrit avant d'en avoir besoin ;
- un correctif de sécurité publié seulement en version 10 : relever le plafond `<10` passe par une relecture [SECU] ;
- un fait nouveau sur une option éliminée, comme une release de cruft ou une fusion à trois voies dans Yeoman.

Les seuils de 30 jours et de 6 mois, proposés par [ARCHI], sont validés par Lucas le 2026-11-19. Sans l'un de ces faits, prochaine vérification le 2027-05-19, ou plus tôt si un avis touche Copier. Un changement de moteur rouvre aussi [ADR-003](ADR-003-langage-cli.md).

## Sources

Ce que BENCH-002 établit se cite par lui ; ses propres sources sont dans sa section 9.

| Source | Lue le | Ce qu'elle établit |
| --- | --- | --- |
| [BENCH-002](../benchmarks/BENCH-002-moteur-templates.md), sections 1 et 3 | 2026-11-19 | Prérequis du jour 2, son origine et son acceptation par le DSI ; éliminations de Cookiecutter, cruft et Yeoman |
| BENCH-002, sections 4.3 et 4.4 | 2026-11-19 | Mesures M1 à M4 ; code de sortie 0 malgré un conflit ; repli de R-22 essayé trois fois ; script `tests/bench/bench-002-day2.sh` |
| BENCH-002, sections 5 à 7 | 2026-11-19 | Notes et total ; gouvernance et activité de Copier ; avis de sécurité, leurs classes et leurs délais ; conditions de [SECU] ; prochaine vérification |
| BENCH-002, sections 8 et 10 | 2026-11-19 | Gabarit jouet de quatre fichiers ; avis de [SECU] et de [FINOPS] |
| [BENCH-006](../benchmarks/BENCH-006-langage-cli.md), section 5.8 | 2026-11-19 | API Python de Copier : `run_copy` et `run_update` |
| [docs/prd-mvp.md](../prd-mvp.md), section 3, US-002, US-004, US-011, ENF-06, ENF-07 | 2026-11-19 | Parcours du jour 2 et exigences sur la génération et la mise à jour |
| [docs/risques.md](../risques.md), R-11, R-16, R-22, R-23 | 2026-11-19 | Conflits de mise à jour ; allocation GitHub Actions d'un dépôt privé ; repli par branche Git ; mesures sur le modèle de confiance |
| Message du DSI à [ARCHI] | 2026-11-19 | Acceptation par Lucas, le 2026-11-19, du verdict à une seule option et du prérequis du jour 2 |
