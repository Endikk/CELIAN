---
description: "Tâches de la fonctionnalité 001 : golden repo SaaS B2B"
---

# Tasks: golden repo SaaS B2B

**Input** : documents de conception de `specs/001-golden-repo-saas-b2b/` : [plan.md](plan.md), validé par Lucas (PR #37, `main` en cf38f91), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/) et [quickstart.md](quickstart.md). Écrit par [DEV] le 2026-11-23 avec `/speckit-tasks`.

**Prerequisites** : plan.md et spec.md présents ; constitution 1.2.0.

**Tests** : demandés. Le principe I exige un test automatique pour tout ce qui sort, et le plan fait commencer chaque PR par ses tests en rouge. Dans chaque étape, les tâches de test précèdent le code qu'elles vérifient, dans la même PR.

**Organisation** : les tâches suivent les étapes livrables du plan, une étape par PR (deux au plus, comme le plan le permet), dans l'ordre de construction de sa colonne « Dépend de ». Chaque étape est rangée dans la phase du récit qu'elle rend testable. Les récits 1 et 2, tous deux en P1 et liés par `task up`, partagent la phase 3. Une tâche porte l'étiquette du récit qu'elle sert, même quand ce n'est pas celui de sa phase.

## Format: `[ID] [P?] [Story] Description`

- **[P]** : peut avancer en même temps que les autres tâches [P] de la même étape, une fois les vérifications de l'étape faites ; fichiers distincts.
- **[Story]** : US1 à US7, les récits de la spec. Les tâches des phases Setup et Polish n'en portent pas ; leur trace dit quels récits elles servent.
- `Trace :` en fin de tâche : les exigences (FR-xxx), puis les contrôles de la matrice du plan (S statique, P préalable, U unitaire, E sur kind, X conventions, D démo). Une tâche de vérification nomme les contrôles qu'elle débloque.
- `Bloquée jusqu'à ... :` en tête d'une tâche bloquée dans une étape prête. Une étape bloquée l'est en entier, et son en-tête dit ce qu'elle attend et ce qui la débloque.
- `Porteur :` le rôle qui mène la tâche quand ce n'est pas [DEV].

## Path Conventions

- Chemins depuis la racine de CELIAN. Le golden repo vit dans `golden/saas-b2b/` et se construit à la main, avant toute mise en template (constitution, « Flux de travail »).
- Couche `local` : `golden/saas-b2b/local/` ; couche `gcp` : `golden/saas-b2b/gcp/` ; tout le reste est commun ([contracts/layers.md](contracts/layers.md)).
- Tests : un fichier par contrôle, nommé d'après son identifiant (`s05-kind-config.sh`, `e04-secrets-fresh.sh`). Contrôles statiques dans `tests/static/`, `local/tests/static/` et `gcp/tests/static/` ; tests sur kind dans `local/tests/e2e/`, `local/tests/offline/` et `local/tests/images/` ; politiques Rego et leurs tests dans `policy/`, `local/policy/` et `gcp/policy/`. Noms proposés ; T004 fixe la convention.
- Chaque vérification datée écrit la source (URL), la date de lecture et la conclusion dans la section de son point RS-xx de [research.md](research.md), et ne touche à aucune autre section.

## Règles qui valent pour toutes les tâches

- Aucune tâche ne lance `tofu plan`, `tofu apply`, `tofu destroy`, ni une commande qui crée une ressource cloud (principe X, décision de Lucas du 2026-11-20). La couche `gcp` se valide sans identifiant ni backend distant.
- Aucune version ni syntaxe d'outil tiers n'entre dans un fichier sans la tâche de vérification qui la précède (principe VIII).
- Aucun secret versionné (principe IX). Scripts en bash compatible 3.2, sans heredoc, passés à shellcheck (ADR-007, condition 1).
- Titre de PR : celui du plan pour l'étape ; les titres absents du plan sont marqués « proposé ».

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose** : squelette du golden repo et premier job de CI dans CELIAN. Prérequis commun à tous les récits.

### Étape 1 : squelette

- PR : `chore(golden): scaffold the SaaS B2B golden repo`
- Dépend de : plan validé (fait)
- État : prête
- Contrôles mis au vert : hooks racine sur `golden/`, S21 (forme de `platform.yaml`), S17 sur le workflow de CELIAN

- [X] T001 [P] Vérifier et dater Task : version retenue et date de publication (7 jours au moins, principe VI), licence, gouvernance (ADR-006, question 5), SHA-256 des binaires linux et darwin en amd64 et arm64, syntaxe d'inclusion des Taskfiles, mode silencieux, détection des sources modifiées utile à `task reload` ; consigner au point RS-09 de `specs/001-golden-repo-saas-b2b/research.md`. Trace : socle, FR-001, FR-007 ; débloque S04, S18.
- [X] T002 [P] Vérifier et dater conftest : version, date de publication, licence, gouvernance, SHA-256 des binaires ; lecture de plusieurs fichiers en une seule entrée, lecture des Dockerfile, chargement d'un fichier de données, lancement des tests Rego ; consigner au point RS-18 de `specs/001-golden-repo-saas-b2b/research.md`. Trace : socle, FR-008, FR-010, FR-012 ; débloque S01, S03, S06, S21, U03.
- [X] T003 [P] Lever les points de RS-17 à vérifier avant l'étape 1 : GitHub ne lance aucun workflow de `golden/saas-b2b/.github/` ; Renovate et release-please ne lisent pas les configurations de `golden/saas-b2b/` ; comportement d'un workflow filtré par chemin face aux contrôles requis du ruleset ; option de `check-yaml` pour les YAML à plusieurs documents ; ce qu'actionlint lit hors de `.github/workflows/` ; consigner au point RS-17 de `specs/001-golden-repo-saas-b2b/research.md`. Porteur : [OPS]. Trace : socle, FR-013 ; débloque S17, X01.
- [X] T004 [P] Écrire le lanceur des contrôles statiques `golden/saas-b2b/tests/run-static.sh` : il exécute les scripts de `tests/static/`, `local/tests/static/` et `gcp/tests/static/` et les politiques Rego, préfixe chaque échec de l'identifiant du contrôle et de la condition ou de l'exigence qu'il porte, sort en erreur si un contrôle échoue ; fixer en tête de fichier la convention de nommage des tests. Trace : socle, FR-012 ; tous les contrôles S.
- [X] T005 Écrire en rouge la politique S21 `golden/saas-b2b/policy/platform_values.rego` et ses tests `golden/saas-b2b/policy/platform_values_test.rego` : `platform.yaml` porte `kubernetes_minor` à `"1.36"` et `postgres_major` à `"18"`, en chaînes (data-model, « Valeurs partagées ») ; la règle s'étend ensuite à la configuration kind (T041), à l'image Postgres (T065) et à la couche OpenTofu (T105). Dépend de T002, T004. Trace : socle, FR-010, FR-017 ; S21.
- [X] T006 [P] Écrire en rouge `golden/saas-b2b/tests/static/s17-workflows.sh` sur `.github/workflows/golden-saas-b2b.yml` : aucune commande `tofu plan`, `apply` ni `destroy`, aucun identifiant cloud, aucun plan publié, actions figées par SHA ; l'étape 2 l'étend aux workflows du projet généré (T094), l'étape 13 aux Taskfiles de `gcp/` (T105). Dépend de T004. Trace : socle, FR-011, FR-013 ; S17.
- [X] T007 Créer l'arborescence de `golden/saas-b2b/` selon la structure du plan (`src/`, `k8s/`, `policy/`, `security/`, `tests/`, `local/`, `gcp/`), avec `golden/saas-b2b/.gitignore` et `golden/saas-b2b/.editorconfig`, et retirer `golden/.gitkeep`. Trace : socle, FR-010 ; S06, S07 plus tard.
- [X] T008 Écrire `golden/saas-b2b/platform.yaml` avec les deux valeurs partagées du data-model ; S21 au vert. Dépend de T005, T007. Trace : socle, FR-010, FR-017 ; S21.
- [X] T009 Écrire `golden/saas-b2b/Taskfile.yml` sans logique : tâches publiques `up`, `down`, `reload`, `check` et `test`, qui délèguent aux Taskfiles inclus de `local/tasks/` et `gcp/tasks/` (syntaxe de T001) ; `check` lance `tests/run-static.sh` ; une tâche pas encore livrée sort en erreur avec une phrase qui le dit ; en tête, l'inventaire, vide pour l'instant, des commandes qui créent ou retirent un conteneur, un réseau ou un volume (ADR-011, condition 11). Dépend de T001, T004, T007. Trace : socle, FR-001, FR-007 ; S04 plus tard.
- [X] T010 [P] Écrire le README minimal `golden/saas-b2b/README.md` : objet du dépôt, carte des couches reprise de `specs/001-golden-repo-saas-b2b/contracts/layers.md`, état « en construction », renvoi à la spec 001 ; le README complet vient à l'étape 11. Dépend de T007. Trace : socle, FR-018 ; S18 plus tard.
- [X] T011 Écrire `golden/saas-b2b/tests/tools/install.sh` et `golden/saas-b2b/tests/tools/SHA256SUMS` : installation de Task et de conftest depuis leurs releases, SHA-256 vérifié avant tout usage (valeurs de T001 et T002), sans action GitHub tierce. Dépend de T001, T002. Trace : socle, FR-013 ; S17.
- [X] T012 Créer `.github/workflows/golden-saas-b2b.yml` avec le job `static` : filtre de chemins selon T003, actions figées par SHA reprises de `.github/workflows/ci.yml`, permissions minimales, outils installés par `golden/saas-b2b/tests/tools/install.sh`, puis `task check` lancé depuis `golden/saas-b2b/` ; S17 et S21 au vert. Dépend de T003, T006, T009, T011. Trace : socle, FR-013 ; S17, S21.
- [X] T013 Régler `.pre-commit-config.yaml` de CELIAN pour `golden/` : vérifier que chaque hook racine s'y applique, et poser l'option de `check-yaml` pour les YAML à plusieurs documents retenue en T003. Dépend de T003. Trace : socle, FR-013 ; hooks racine sur `golden/`.
- [X] T014 Ajouter le job `static` aux contrôles requis de `.github/rulesets/main.json`, sous la forme que T003 retient pour un workflow filtré par chemin ; Lucas applique le ruleset par `scripts/github/apply-settings.sh`, avec les droits admin. Dépend de T012. Trace : socle, FR-013 ; SC-006.

**Checkpoint** : `task check` passe en local et dans le job `static` ; S17 et S21 au vert ; `golden/` couvert par les hooks racine. Les étapes 2, 3, 4, 5 et 13 peuvent démarrer en parallèle.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose** : aucune tâche propre. L'étape 1 est le seul prérequis commun à tous les récits. Les étapes 5 à 7 (contrôles préalables, cluster et miroir, plate-forme) ne bloquent que les récits locaux : elles sont rangées en phase 3, avec le récit qu'elles servent. Les récits 3 et 4 partent directement de l'étape 1.

---

## Phase 3: User Stories 1 and 2 (Priority: P1), profil lite

**Goal** : `task up` démarre le profil lite (API, front, Postgres, cache) dans kind, l'expose en 127.0.0.1 par Envoy Gateway, crée des secrets aléatoires propres au poste, et `task reload`, `task down`, `task app:down` et `task mirror:purge` tiennent leur contrat.

**Independent Test US1** : sur un poste propre, cloner, lancer `task up`, puis appeler `/api/healthz` et la page d'accueil aux adresses affichées (E01, E02, E03, E07, E08).

**Independent Test US2** : démarrer deux environnements neufs, comparer leurs valeurs secrètes, puis les chercher dans le dépôt et son historique (E04, E05, E06). Disponible dès l'étape 8, sans attendre l'ADR-015.

### Étape 3 : API d'exemple

- PR : `feat(golden): add the example .NET API`
- Dépend de : étape 1
- État : prête
- Contrôles mis au vert : U01, S20 (API), S01 (Dockerfile)

- [X] T015 [P] [US1] Vérifier et dater avant tout code de l'étape 3 : Npgsql (version, licence, date de publication), framework de test .NET, format des détails de problème d'ASP.NET Core en .NET 10, verrouillage des paquets NuGet par fichier, format de description machine des routes et sa version ; consigner aux points RS-03 et RS-18 de `specs/001-golden-repo-saas-b2b/research.md`. Trace : FR-009 ; débloque U01, S20.
- [X] T016 [P] [US1] Vérifier les droits de création dans le schéma `public` du propriétaire d'une base sous PostgreSQL 18 et les privilèges de `cloudsqlsuperuser` (ADR-012, « Parité attendue avec Cloud SQL ») ; consigner au point RS-04 de `specs/001-golden-repo-saas-b2b/research.md`. Porteurs : [DEV] et [SECU]. Trace : FR-017 ; débloque U01, E12.
- [X] T017 [US1] Écrire en rouge les tests unitaires U01 dans `golden/saas-b2b/src/Api.Tests/`, d'après `specs/001-golden-repo-saas-b2b/contracts/http-api.md` : `/api/healthz` répond 200 `{"status": "ok"}` sans toucher la base ni le cache ; `/api/readyz` répond 200 ou 503 avec `database` et `cache` à `ok` ou `error`, sans détail d'erreur ; `POST /api/notes` exige `body`, « de 1 à 500 caractères après suppression des blancs de début et de fin », refuse tout autre champ, répond 201 avec l'en-tête d'emplacement, ou 400 en nommant `body` ; `GET /api/notes/{id}` répond 400 hors UUID, 404 sans rien mettre au cache, puis `servedFrom` à `database` et ensuite à `cache` (double de l'interface du cache) ; `GET /api/notes?limit=` accepte un « entier de 1 à 50, 20 par défaut » et répond 400 en nommant `limit` hors bornes ; aucune trace de pile ni message de la base dans une erreur. Dépend de T015. Trace : FR-009, FR-014 ; U01.
- [X] T018 [P] [US5] Écrire en rouge le contrôle S20 côté API `golden/saas-b2b/tests/static/s20-api-routes.sh` : les routes de la description machine retenue en T015 sont exactement celles du contrat http-api, ni plus ni moins. Dépend de T015. Trace : FR-009 ; S20.
- [X] T019 [P] [US1] Écrire en rouge la politique S01 `golden/saas-b2b/policy/image_digests.rego` et ses tests : toute image de base d'un Dockerfile porte un condensat ; seules les images sous `saas-b2b.invalid` en sont exemptées ; l'étape 9 l'étend aux rendus (T086). Dépend de T002. Trace : FR-008 ; S01.
- [X] T020 [US1] Créer le projet `golden/saas-b2b/src/Api/` en `net10.0` avec `/api/healthz` et `/api/readyz`, l'API servant elle-même ses routes sous `/api` (plan, « Routage et adresses »). Dépend de T017. Trace : FR-009 ; U01.
- [X] T021 [US1] Écrire l'accès à la base dans `golden/saas-b2b/src/Api/` : Npgsql, requêtes paramétrées seulement, sans ORM ; hôte, port, nom de base et mode TLS lus dans `app-config`, mot de passe lu dans le fichier monté de `db-auth` (`specs/001-golden-repo-saas-b2b/contracts/secrets.md`) ; fixer les noms des clés d'`app-config`, cache compris, et les ajouter à la section « `app-config` » de `specs/001-golden-repo-saas-b2b/contracts/layers.md`. Dépend de T020. Trace : FR-009, FR-017 ; U01, S07 plus tard.
- [X] T022 [US1] Écrire le script SQL idempotent de la table `notes` dans `golden/saas-b2b/src/Api/`, exécuté au démarrage sous le rôle de `db-auth` (RS-04, conclusion de T016) : `id` UUID « tiré par l'API à l'écriture ; jamais fourni par le client », `body` texte obligatoire, `created_at` horodatage avec fuseau « posé par la base à l'insertion ». Dépend de T016, T021. Trace : FR-009, FR-017 ; U01.
- [X] T023 [US1] Écrire l'interface d'accès au cache et la lecture paresseuse dans `golden/saas-b2b/src/Api/` : clé `note:<id>`, valeur JSON des trois champs, durée de vie en constante nommée (valeur fixée ici), note absente jamais mise en cache, écriture sans toucher au cache, liste toujours lue en base ; aucun client concret avant l'étape 19 (RS-11). Dépend de T020. Trace : FR-009 ; U01.
- [X] T024 [US1] Écrire les routes des notes et leur validation côté serveur dans `golden/saas-b2b/src/Api/` : réponses en camelCase limitées aux champs du contrat, erreurs au format retenu en T015 ; U01 et S20 au vert. Dépend de T018, T021, T022, T023. Trace : FR-009 ; U01, S20.
- [X] T025 [US1] Écrire `golden/saas-b2b/src/Api/Dockerfile` multi-étapes : `mcr.microsoft.com/dotnet/sdk:10.0.404` et `aspnet:10.0.15` par les condensats de `tests/bench/bench-005/stack/api/Dockerfile`, utilisateur non root, étape de test qui lance U01 dans l'image de construction, sans SDK sur le poste (RS-06) ; S01 au vert. Dépend de T019, T024. Trace : FR-008, FR-009 ; S01, U01.
- [X] T026 [US1] Brancher U01 sur `task test` (tests lancés dans l'image de construction) et créer le job `unit` dans `.github/workflows/golden-saas-b2b.yml`, ajouté aux contrôles requis de `.github/rulesets/main.json` ; si l'étape 4 a déjà créé ce job, y ajouter U01. Dépend de T025. Trace : FR-014 ; U01.

### Étape 4 : front d'exemple

- PR : `feat(golden): add the example React front`
- Dépend de : étape 1
- État : prête
- Contrôles mis au vert : U02, S20 (front), S01 (Dockerfile)

- [X] T027 [P] [US1] Vérifier et dater avant tout code de l'étape 4, avec leur date de publication (principe VI, R-05) : Node.js, React, Vite, TypeScript, framework de test du front, outil de verrouillage des dépendances, image de construction Node par condensat, variante de nginx qui tourne sans root pour le profil `restricted` (repère : `nginx:1.30.7-alpine` de `tests/bench/bench-005/stack/front/Dockerfile`) ; consigner aux points RS-05 et RS-18 de `specs/001-golden-repo-saas-b2b/research.md`. Trace : FR-009 ; débloque U02, S01, E12.
- [X] T028 [US1] Écrire en rouge les tests U02 dans `golden/saas-b2b/src/front/` : liste affichée au chargement, appels par chemins relatifs sous `/api` sans adresse configurée, formulaire d'ajout avec son état de chargement, erreur affichée sous le champ `body`, provenance de la dernière lecture (`servedFrom`). Dépend de T027. Trace : FR-009, FR-014 ; U02.
- [X] T029 [P] [US5] Écrire en rouge le contrôle S20 côté front `golden/saas-b2b/tests/static/s20-front-screens.sh` : un seul écran, celui des notes, qui n'appelle que les routes du contrat http-api. Dépend de T027. Trace : FR-009 ; S20.
- [X] T030 [US1] Écrire l'application `golden/saas-b2b/src/front/` en React et TypeScript, construite par Vite : écran des notes et client des routes du contrat ; U02 et S20 au vert. Dépend de T028, T029. Trace : FR-009 ; U02, S20.
- [X] T031 [US1] Écrire `golden/saas-b2b/src/front/Dockerfile` multi-étapes : construction par l'image Node de T027, service par nginx non root sur un port non privilégié, images par condensat, étape de test qui lance U02 ; S01 au vert par la politique de T019, qui entre dans cette PR si l'étape 3 n'est pas encore fusionnée. Dépend de T030. Trace : FR-008, FR-009 ; S01, U02.
- [X] T032 [US1] Brancher U02 sur `task test` et sur le job `unit` de `.github/workflows/golden-saas-b2b.yml`, en créant ce job comme en T026 si l'étape 3 ne l'a pas fait. Dépend de T031. Trace : FR-014 ; U02.

### Étape 5 : contrôles préalables

- PR : `feat(golden): add the task up preflight checks`
- Dépend de : étape 1
- État : prête
- Contrôles mis au vert : P01 à P05

- [X] T033 [P] [US1] Vérifier et dater la lecture de la mémoire déclarée par le moteur, sous Docker Engine et sous le moteur libre que retiendra [OPS], et la lecture des versions de Docker Engine, de kind et de kubectl ; consigner au point RS-08 de `specs/001-golden-repo-saas-b2b/research.md`. Trace : FR-006 ; débloque P01, P03.
- [X] T034 [US1] Écrire les binaires simulés de `golden/saas-b2b/local/tests/preflight/fakes/` (moteur, kind, kubectl), puis en rouge `golden/saas-b2b/local/tests/preflight/p01-versions.sh` et `p02-engine.sh` : kind autre que 0.33.0, kubectl hors de 1.35 à 1.37, Docker Engine sous 28.0.0 sous Linux, refusés avec la version trouvée, la version attendue et le renvoi au README ; moteur absent ou arrêté, message clair et rien de créé. Dépend de T033. Trace : FR-001 ; P01, P02.
- [X] T035 [P] [US1] Écrire en rouge `golden/saas-b2b/local/tests/preflight/p03-memory.sh` : au-dessus du seuil du standard (VM de 2,5 Gio), standard ; entre les seuils, lite annoncé ; sous le seuil du lite (VM de 2,0 Gio), refus avec la mémoire qui manque ; `PROFILE` force un profil sous les mêmes contrôles ; standard reconnu puis refusé par un message clair jusqu'à l'étape 12. Dépend de T034. Trace : FR-006 ; P03.
- [X] T036 [P] [US1] Écrire en rouge `golden/saas-b2b/local/tests/preflight/p04-ports.sh` et `p05-kubeconfig.sh` : un port de l'hôte déjà pris arrête tout avant la moindre création, en nommant le port (ports injectés par le test, valeurs réelles fixées en T059) ; un kubeconfig de l'utilisateur pointé sur un autre contexte est ignoré. Dépend de T034. Trace : FR-001, FR-019 ; P04, P05.
- [X] T037 [US1] Écrire `golden/saas-b2b/local/scripts/preflight.sh` dans l'ordre du contrat task-cli : moteur joignable, versions, mémoire et profil, ports ; seuils en constantes nommées ; P01 à P05 au vert. Dépend de T034, T035, T036. Trace : FR-001, FR-006, FR-019 ; P01 à P05.
- [X] T038 [US1] Brancher `preflight.sh` en tête de `task up` dans `golden/saas-b2b/local/tasks/up.yml`, et P01 à P05 sur `task check`. Dépend de T037. Trace : FR-001 ; P01 à P05.

### Étape 6 : cluster et miroir

- PR : `feat(golden): create the kind cluster and the zot mirror`
- Dépend de : étape 5
- État : prête dès l'étape 5 fusionnée
- Contrôles mis au vert : S05, S13, S19, P06, P07, E19, E22, E24 ; en plus, les parties de E03 et de E08 qui portent sur ce que l'étape crée (voir « Écarts relevés », point 2)

- [X] T039 [US1] Trancher avec [SECU] l'emplacement du kubeconfig du projet, hors du dépôt, au regard de R-07 ; consigner au point RS-21 de `specs/001-golden-repo-saas-b2b/research.md`. Porteurs : [DEV] et [SECU]. Trace : FR-019 ; débloque E19.
- [X] T040 [P] [US1] Vérifier et dater pour la CI : version de Docker Engine sur `ubuntu-latest` (28.0.0 au moins, ADR-011, condition 3) et version de kubectl à installer dans la plage 1.35 à 1.37, avec sa date de publication et son SHA-256 ; consigner aux points RS-17 et RS-18 de `specs/001-golden-repo-saas-b2b/research.md`. Porteur : [OPS]. Trace : FR-014 ; débloque E19, E22, E24.
- [X] T041 [P] [US1] Écrire en rouge `golden/saas-b2b/local/tests/static/s05-kind-config.sh` et étendre `golden/saas-b2b/policy/platform_values.rego` : `apiServerAddress` et chaque `listenAddress` à 127.0.0.1, image de nœud par condensat, mineure égale à `kubernetes_minor` de `platform.yaml`. Trace : FR-003, FR-008 ; S05, S21.
- [X] T042 [P] [US6] Écrire en rouge `golden/saas-b2b/local/tests/static/s13-mirror.sh` et `golden/saas-b2b/local/tests/preflight/p06-mirror-config.sh` : `hosts.toml` en capacité `pull` seule, configuration zot réduite à `sync`, aucun identifiant, fichiers dérivés d'accord avec `local/mirror/registries`, lancement sur le réseau `kind` sans port publié, stockage hors de l'arborescence ; le miroir refuse de démarrer sans la configuration du projet. Trace : FR-008, FR-016 ; S13, P06.
- [X] T043 [P] [US1] Écrire en rouge `golden/saas-b2b/local/tests/static/s19-kubectl-context.sh` et la partie inventaire de `golden/saas-b2b/local/tests/static/s04-taskfile.sh` : chaque appel à `kubectl` des tâches et des scripts passe par le kubeconfig du projet et le contexte du cluster local, `port-forward` seulement avec `--address 127.0.0.1` ; chaque commande qui crée ou retire un conteneur, un réseau ou un volume figure à l'inventaire en tête du Taskfile. Trace : FR-019 ; S19, S04.
- [X] T044 [US1] Écrire en rouge `golden/saas-b2b/local/tests/e2e/e19-kubeconfig.sh`, `e22-foreign-container.sh` et `e24-decoy-kubeconfig.sh` : kubeconfig hors du dépôt ou ignoré par Git ; `task down` ne retire jamais un conteneur étranger au projet, même de nom voisin ; avec un kubeconfig leurre en variable d'environnement, `task up` réussit et ne le modifie pas. Dépend de T039. Trace : FR-019 ; E19, E22, E24.
- [X] T045 [US1] Écrire en rouge `golden/saas-b2b/local/tests/e2e/e03-loopback.sh`, partie cluster et miroir, et `golden/saas-b2b/local/tests/e2e/e08-down.sh`, partie `task down` et `task mirror:purge` : rien en écoute sur 0.0.0.0, `[::]` ni `*` ; miroir sans port publié, relié au seul réseau `kind` ; `task down` retire le cluster et le conteneur du miroir, garde le volume et affiche ce qui reste ; `task mirror:purge` dit d'abord que le démarrage suivant demandera le réseau, puis retire ce seul volume. Trace : FR-003, FR-007, FR-016 ; E03, E08.
- [X] T046 [US1] Écrire `golden/saas-b2b/local/kind/cluster.yaml` : `kindest/node:v1.36.4` par condensat (ADR-004), `apiServerAddress` à 127.0.0.1, registre du nœud dirigé vers le miroir ; S05 et S21 au vert. Dépend de T041. Trace : FR-003, FR-008 ; S05, S21.
- [X] T047 [US6] Écrire `golden/saas-b2b/local/mirror/registries`, liste unique des registres des images des étapes 6 à 8 (ADR-005, ADR-012), puis la configuration zot et les `hosts.toml` qui en dérivent ; image zot 2.1.23 par condensat (ADR-011, condition 8) ; S13 au vert. Dépend de T042. Trace : FR-008, FR-016 ; S13.
- [X] T048 [US1] Écrire `golden/saas-b2b/local/scripts/cluster.sh` : création ou réutilisation du cluster depuis `local/kind/cluster.yaml`, kubeconfig du projet à l'emplacement de T039, contexte explicite à chaque commande. Dépend de T039, T046. Trace : FR-001, FR-019 ; E19, E24, S19.
- [X] T049 [US6] Écrire `golden/saas-b2b/local/scripts/mirror.sh` : retrait contrôlé d'un ancien conteneur du projet (nom, étiquette et image vérifiés), lancement sur le réseau `kind` sans port publié, configuration montée en lecture seule, volume du projet, attente de sa réponse ; P06 au vert. Dépend de T047. Trace : FR-016 ; P06, S13, E22.
- [X] T050 [US1] Écrire `golden/saas-b2b/local/tasks/down.yml` et `golden/saas-b2b/local/tasks/mirror.yml` (`task down`, `task mirror:purge`) selon le contrat task-cli, brancher cluster et miroir dans `task up`, compléter l'inventaire du Taskfile ; S04, S19, E03, E08 et E22 au vert. Dépend de T043, T045, T048, T049. Trace : FR-001, FR-007, FR-016 ; S04, S19, E03, E08, E22.
- [X] T051 [US1] Créer `task test:e2e` dans `golden/saas-b2b/local/tasks/test.yml` et le job `e2e-lite` dans `.github/workflows/golden-saas-b2b.yml` : runner `ubuntu-latest` amd64, kind 0.33.0 vérifié contre le SHA-256 de `catalog/kubernetes-cluster.yaml` (ADR-004, condition 5), kubectl de T040 ; ajouter le job aux contrôles requis de `.github/rulesets/main.json`. Dépend de T040, T044, T050. Trace : FR-014 ; E19, E22, E24.

### Étape 7 : plate-forme de base, première PR

- PR : `feat(golden): install Gateway API and Envoy Gateway`
- Dépend de : étape 6
- État : prête dès l'étape 6 fusionnée ; l'écouteur HTTPS passe dans la seconde PR, bloquée (plus bas)
- Contrôles mis au vert : S02, S06, S22, E03

- [X] T052 [P] [US5] Vérifier sur la documentation de Kustomize, et dans la version qu'embarque kubectl, les composants qui portent la couche de cible au-dessus d'un overlay ; à défaut, retenir la composition par ressources ; consigner au point RS-01 de `specs/001-golden-repo-saas-b2b/research.md`. Trace : FR-010 ; débloque S06, S07.
- [X] T053 [P] [US1] Vérifier sur la spécification de Gateway API v1.7.0 que la correspondance par préfixe de chemin fait partie du cœur, et sur la documentation de GKE que son contrôleur la sert ; consigner au point RS-02 de `specs/001-golden-repo-saas-b2b/research.md`. Trace : FR-002, FR-010 ; débloque S07, S08.
- [X] T054 [P] [US1] Écrire en rouge `golden/saas-b2b/local/tests/static/s02-vendor-sums.sh` et `golden/saas-b2b/local/tests/static/s22-envoy-charts.sh` : chaque fichier de `local/vendor/` a son SHA-256 dans `SHA256SUMS`, vérifié avant application, et rien ne s'applique depuis une URL ; toute CRD de `gateway.networking.k8s.io` vient du `standard-install.yaml` vérifié ; réglages `crds.*` et image du contrôleur conformes à l'ADR-005. Trace : FR-008 ; S02, S22.
- [X] T055 [P] [US5] Écrire en rouge la politique S06 `golden/saas-b2b/policy/common_neutral.rego` et ses tests : la couche commune rendue ne contient aucun groupe `gateway.envoyproxy.io`, `configsync.gke.io`, `*.toolkit.fluxcd.io` ni `argoproj.io`, aucune annotation ni étiquette de moteur, aucune chaîne `${`, aucun objet propre à un fournisseur. Dépend de T052. Trace : FR-010 ; S06.
- [X] T056 [US1] Étendre en rouge `golden/saas-b2b/local/tests/e2e/e03-loopback.sh` aux deux ports de l'hôte de la gateway, et `golden/saas-b2b/local/tests/static/s05-kind-config.sh` à l'accord entre les ports de `local/kind/cluster.yaml` et ceux des tâches. Trace : FR-002, FR-003 ; E03, S05.
- [X] T057 [US1] Exclure `golden/saas-b2b/local/vendor/` des hooks de `.pre-commit-config.yaml` qui réécrivent les fichiers, sur le modèle de `tests/bench/*/vendor/`, pour que les sommes restent justes. Trace : FR-008 ; S02.
- [X] T058 [US1] Vendorer dans `golden/saas-b2b/local/vendor/` le `standard-install.yaml` de Gateway API v1.7.0 et le rendu des charts d'Envoy Gateway 1.10.0, avec `golden/saas-b2b/local/vendor/SHA256SUMS` (sommes et condensats du tableau « Versions et condensats » de l'ADR-005, méthode de rendu de `tests/bench/bench-004-gateway.sh`) ; S02 et S22 au vert. Dépend de T054, T057. Trace : FR-008 ; S02, S22.
- [X] T059 [US1] Écrire `golden/saas-b2b/local/platform/` (EnvoyProxy qui publie le proxy en NodePort à ports fixes, GatewayClass) et fixer les deux ports de l'hôte en `listenAddress: "127.0.0.1"` dans `local/kind/cluster.yaml` et dans les tâches (RS-20). Dépend de T056, T058. Trace : FR-002, FR-003 ; E03, S05.
- [X] T060 [US1] Écrire `golden/saas-b2b/k8s/base/` et `golden/saas-b2b/k8s/overlays/local/` : namespace `saas-b2b` au profil `restricted`, une Gateway à écouteur HTTP, HTTPRoute `api` sur le préfixe `/api` et `front` sur `/`, routes admises du même namespace, sans réécriture de chemin ; S06 au vert. Dépend de T052, T053, T055. Trace : FR-002, FR-010 ; S06.
- [X] T061 [US1] Écrire `golden/saas-b2b/local/scripts/platform.sh` : SHA-256 de chaque fichier vendoré vérifié, puis CRD, Envoy Gateway, EnvoyProxy et GatewayClass ; le brancher dans `task up` ; E03 au vert dans `e2e-lite`. Dépend de T059, T060. Trace : FR-002, FR-003 ; E03, S02.

### Étape 8 : secrets et données

- PR : `feat(golden): add local secrets and Postgres`
- Dépend de : étape 7
- État : prête dès l'étape 7 fusionnée ; la partie cache passe à l'étape 19
- Contrôles mis au vert : S03, S04, S12, E04, E05, E06, E12, E21

- [ ] T062 [P] [US1] Vérifier et dater pour l'image `postgres:18.7-trixie` : état TLS du serveur, `readOnlyRootFilesystem`, effet de `pg_isready` sur les journaux, script d'initialisation sous `scram-sha-256` local ; choisir le mode de connexion de l'API face à Cloud SQL en `ENCRYPTED_ONLY` et noter l'écart pour le README ; sur `gcp`, refuser `DATABASE_SSL_MODE` à `Disable`, `Allow` ou `Prefer`, sauf derrière un proxy sur localhost, `Prefer` ne validant aucun certificat (relecture [SECU] de l'étape 3) ; consigner au point RS-12 de `specs/001-golden-repo-saas-b2b/research.md`. Porteurs : [DEV] et [SECU]. Trace : FR-017, FR-018 ; débloque S12, E12.
- [ ] T063 [P] [US2] Écrire en rouge la politique S03 `golden/saas-b2b/policy/no_secret.rego` et ses tests : aucun objet `Secret` ni champ `secretGenerator` versionné. Trace : FR-004 ; S03.
- [ ] T064 [P] [US2] Étendre en rouge `golden/saas-b2b/local/tests/static/s04-taskfile.sh` : tâches qui manipulent un secret en `silent: true`, sans heredoc, sans `kubectl apply` de Secret, sans valeur dans une variable. Trace : FR-004 ; S04.
- [ ] T065 [P] [US1] Écrire en rouge `golden/saas-b2b/local/tests/static/s12-postgres.sh` et étendre `golden/saas-b2b/policy/platform_values.rego` à l'image Postgres : UID 999, `runAsNonRoot`, capacités retirées, `seccompProfile`, aucun jeton monté, fichiers `_FILE`, `scram-sha-256`, aucune méthode `trust`, Secret du superutilisateur absent des manifests de l'application ; majeure de l'image égale à `postgres_major`. Dépend de T062. Trace : FR-017 ; S12, S21.
- [ ] T066 [US2] Écrire en rouge `golden/saas-b2b/local/tests/e2e/e04-secrets-fresh.sh`, `e05-secrets-kept.sh` et `e06-secrets-not-in-repo.sh` : deux environnements neufs sans aucune valeur de mot de passe commune, chacune de 32 caractères au moins, aucune de la liste `root`, `admin`, `postgres`, `password`, `changeme`, `mysecretpassword`, chaîne vide, `username` hors comparaison ; au second `task up`, empreinte SHA-256 de chaque valeur inchangée, aucune annotation `kubectl.kubernetes.io/last-applied-configuration`, clés exactes du contrat, données lisibles ; aucune valeur dans l'arborescence ni dans l'historique Git. Trace : FR-004, FR-005 ; E04, E05, E06.
- [ ] T067 [US1] Écrire en rouge `golden/saas-b2b/local/tests/e2e/e12-postgres.sh` et `e21-volume-without-secrets.sh` : `pg_hba` sans `trust`, connexion sans mot de passe refusée depuis un autre namespace, rôle de `db-auth` sans superutilisateur, `server_version` à la majeure 18, pods admis par le profil `restricted` ; volume de la base présent sans ses Secrets, `task up` s'arrête et propose de supprimer les deux. Dépend de T062. Trace : FR-004, FR-017 ; E12, E21.
- [ ] T068 [US2] Écrire `golden/saas-b2b/local/scripts/secrets.sh` et sa tâche silencieuse dans `golden/saas-b2b/local/tasks/secrets.yml` : namespace créé d'abord, puis `db-auth` (`kubernetes.io/basic-auth`, `username` à `app`) et `db-superuser` (`kubernetes.io/basic-auth`) seulement s'ils manquent ; mots de passe de « 40 caractères alphanumériques tirés de `/dev/urandom` », passés par un tube à `kubectl create -f -`, jamais par `kubectl apply`, un fichier, une variable ni un argument ; arrêt si le volume de la base existe sans ses Secrets. Dépend de T063, T064, T066. Trace : FR-004 ; S03, S04, E04, E05, E21.
- [ ] T069 [US1] Écrire `golden/saas-b2b/local/data/` : StatefulSet d'une réplique sur `postgres:18.7-trixie` par condensat (ADR-012), Service, script d'initialisation qui crée le rôle `app` sans superutilisateur, mots de passe par fichiers, `scram-sha-256`, contexte de sécurité du profil `restricted` ; S12 et S21 au vert. Dépend de T065. Trace : FR-017 ; S12, S21, E12.
- [ ] T070 [US1] Écrire le composant de cible `golden/saas-b2b/local/k8s/component/` (Postgres) et la composition `golden/saas-b2b/local/k8s/lite/` selon le mécanisme de T052 ; brancher Secrets et données dans `task up` ; E04, E05, E06, E12 et E21 au vert dans `e2e-lite`. Dépend de T052, T067, T068, T069. Trace : FR-001, FR-004, FR-017 ; E04, E05, E06, E12, E21.

**Note** : si la première PR de l'étape 18 est fusionnée avant celle-ci, l'image Postgres entre d'elle-même dans l'inventaire calculé (S25), et cette PR doit passer son scan ; [SECU] écrit l'exception si une faille au seuil l'exige.

### Étape 7 : plate-forme de base, seconde PR (écouteur HTTPS)

- PR : `feat(golden): add the HTTPS listener` (proposé)
- Dépend de : étape 8, pour la tâche des Secrets ; décision de RS-10
- État : bloquée. Attend la décision de [SECU] et [DEV] sur la fabrication de `gateway-tls` sans fichier ni argument (T071)
- Contrôles étendus : E03, E04, E05, S04, S06

- [ ] T071 [US2] Trancher la fabrication de la clé et du certificat de `gateway-tls` sans fichier ni argument : outil, disponibilité sous macOS et Linux, syntaxe vérifiée et datée ; consigner au point RS-10 de `specs/001-golden-repo-saas-b2b/research.md`. Porteurs : [SECU] et [DEV]. Trace : FR-004 ; débloque T072 à T074.
- [ ] T072 [US2] Bloquée jusqu'à T071 : étendre en rouge `golden/saas-b2b/local/tests/e2e/e04-secrets-fresh.sh` et `e05-secrets-kept.sh` à `gateway-tls` (`kubernetes.io/tls`, clés `tls.crt` et `tls.key`, gardé d'un démarrage à l'autre), `golden/saas-b2b/local/tests/static/s04-taskfile.sh` à sa création, et `golden/saas-b2b/local/tests/e2e/e03-loopback.sh` à l'écouteur HTTPS. Trace : FR-003, FR-004 ; E03, E04, E05, S04.
- [ ] T073 [US2] Bloquée jusqu'à T071 : créer `gateway-tls` dans `golden/saas-b2b/local/scripts/secrets.sh` par la méthode de T071, seulement s'il manque. Dépend de T072. Trace : FR-004 ; E04, E05, S04.
- [ ] T074 [US1] Bloquée jusqu'à T071 : ajouter l'écouteur HTTPS à la Gateway de `golden/saas-b2b/k8s/base/`, avec le certificat de `gateway-tls` ; S06 et E03 au vert. Dépend de T073. Trace : FR-002 ; E03, S06.

### Étape 19 : couche cache locale

- PR : `feat(golden): add the local cache layer`
- Dépend de : étapes 3 et 8, ADR-015
- État : bloquée. Attend l'ADR-015, qui suit BENCH-014, dont les mesures passent après BENCH-012 et BENCH-013. Décision de Lucas du 2026-11-23 : aucune image de cache provisoire
- Contrôles mis au vert : S11, E13, E04 et E05 étendus à `cache-auth`

- [ ] T075 [US1] Relever dans l'ADR-015 l'image, la forme, la persistance, le registre et les clés de `cache-auth`, puis vérifier et dater sur la documentation du moteur retenu : passage du mot de passe sans argument, mode TLS face à Memorystore, client .NET avec version, licence et date, prise en charge de RESP ; consigner au point RS-11 de `specs/001-golden-repo-saas-b2b/research.md`. Porteurs : [DEV] et [SECU]. Trace : FR-001, FR-009 ; débloque S11, E13.
- [ ] T076 [P] [US2] Écrire en rouge `golden/saas-b2b/local/tests/static/s11-cache-password.sh`, et étendre `e04-secrets-fresh.sh` et `e05-secrets-kept.sh` de `golden/saas-b2b/local/tests/e2e/` à `cache-auth` (`Opaque`, clés de l'ADR-015) : mot de passe jamais dans `command` ni `args`. Dépend de T075. Trace : FR-004, FR-005 ; S11, E04, E05.
- [ ] T077 [P] [US1] Écrire en rouge `golden/saas-b2b/local/tests/e2e/e13-cache-auth.sh` et les tests unitaires du client concret dans `golden/saas-b2b/src/Api.Tests/` : le cache refuse une commande sans authentification. Dépend de T075. Trace : FR-001, FR-009 ; E13, U01.
- [ ] T078 [US2] Ajouter `cache-auth` à `golden/saas-b2b/local/scripts/secrets.sh`, aux mêmes règles que T068. Dépend de T076. Trace : FR-004 ; E04, E05, S04.
- [ ] T079 [US1] Écrire `golden/saas-b2b/local/data/cache/` selon l'ADR-015, image par condensat, mot de passe lu dans `cache-auth` sans argument, et l'ajouter à `local/k8s/component/` ; ajouter son registre à `local/mirror/registries` et aux fichiers dérivés s'il diffère de docker.io (montage à plusieurs amonts, RS-13) ; S11, S13 et E13 au vert. Dépend de T077, T078. Trace : FR-001, FR-008, FR-016 ; S11, S13, E13.
- [ ] T080 [US1] Écrire le client concret du cache dans `golden/saas-b2b/src/Api/`, derrière l'interface de T023, et brancher `/api/readyz` sur le cache ; U01 au vert. Dépend de T077. Trace : FR-009 ; U01.
- [ ] T081 [US1] Recalculer le seuil de mémoire du profil lite à l'entrée du cache (RS-08) dans `golden/saas-b2b/local/scripts/preflight.sh` et `golden/saas-b2b/local/tests/preflight/p03-memory.sh`, avec la source de la mesure. Porteurs : [DEV], sur la mesure de [BENCH] et [FINOPS]. Trace : FR-006 ; P03.

### Étape 9 : profil lite de bout en bout

- PR : `feat(golden): start the lite profile end to end`
- Dépend de : étapes 3, 4, 8 et 19
- État : bloquée par l'étape 19, donc par l'ADR-015
- Contrôles mis au vert : E01, E02, E07, E08, E09, E11, E17, E18, S01 (rendus), S07 (partie locale)

- [ ] T082 [US1] Essayer `kind load docker-image` et le kubelet avec les noms `saas-b2b.invalid/api` et `saas-b2b.invalid/front` ; en cas d'échec, retenir avec [SECU] un autre hôte qui ne résout vers aucun registre public (RS-07) ; consigner au point RS-07 de `specs/001-golden-repo-saas-b2b/research.md`. Porteur : [OPS]. Trace : FR-001, FR-008 ; débloque E11, S01.
- [ ] T083 [P] [US1] Écrire en rouge `golden/saas-b2b/local/tests/e2e/e01-up-from-scratch.sh` et `e02-note-cache.sh` : `task up` sans cluster atteint « prêt » sans autre étape (`SELECT 1` authentifié par le Service de la base, `/api/healthz` et page d'accueil par la gateway) et affiche `http://127.0.0.1:<port>/` et `http://127.0.0.1:<port>/api/` ; une note écrite est relue avec `servedFrom` à `database`, puis à `cache`. Trace : FR-001, FR-002, FR-009, FR-014 ; E01, E02.
- [ ] T084 [P] [US1] Écrire en rouge `golden/saas-b2b/local/tests/e2e/e07-reload.sh` et compléter `e08-down.sh` : après modification de l'API puis du front, `task reload` sert la nouvelle version sans redémarrer le pod de la base, et la note reste lisible ; sans modification, mêmes objets aux étiquettes d'image près ; `task app:down` retire le conteneur du miroir, le namespace, le PVC et les Secrets de la base, garde le cluster et affiche la mémoire qu'il garde. Trace : FR-007 ; E07, E08.
- [ ] T085 [P] [US1] Écrire en rouge `golden/saas-b2b/local/tests/e2e/e09-warm-no-pull.sh`, `e11-running-images.sh`, `e17-durations.sh` et `e18-warm-under-90s.sh` : sur un cluster gardé, `task up` ne tire aucune image d'après les événements du nœud ; hôtes de registre des pods dans la liste unique, références par condensat ou sous `saas-b2b.invalid` ; durée de chaque étape, durée totale et taille du volume du miroir affichées ; démarrage à chaud sous 90 s. Trace : FR-008, FR-015, FR-016 ; E09, E11, E17, E18.
- [ ] T086 [P] [US5] Écrire en rouge la partie locale de `golden/saas-b2b/tests/static/s07-parity.sh` et étendre `golden/saas-b2b/policy/image_digests.rego` aux rendus : la couche commune rendue seule se retrouve à l'identique dans le rendu `local`, `spec.gatewayClassName` à part ; une seule Gateway ; mêmes références aux Secrets et à `app-config` ; toute image des rendus porte un condensat, sauf sous `saas-b2b.invalid` ; aucun rendu ne pose `ASPNETCORE_ENVIRONMENT` ni `DOTNET_ENVIRONMENT` à `Development`, qui afficherait la trace de pile (relecture [SECU] de l'étape 3). Trace : FR-008, FR-010 ; S07, S01.
- [ ] T087 [US1] Écrire dans `golden/saas-b2b/k8s/base/` les Deployments et Services de l'API et du front (sondes sur `/api/healthz` et `/api/readyz`, Secrets lus par fichiers montés, références à `app-config`, contexte de sécurité du profil `restricted`, avec `readOnlyRootFilesystem: true` et, pour le front, un `emptyDir` borné par `sizeLimit` sur `/tmp`, où nginx écrit son PID et ses fichiers temporaires) ; ajouter l'`app-config` local, aux clés de T021, à `golden/saas-b2b/local/k8s/component/` ; étendre `golden/saas-b2b/local/tests/e2e/e12-postgres.sh` à l'admission des pods de l'application par le profil `restricted`. Trace : FR-001, FR-009, FR-010 ; S07, S01, E12.
- [ ] T088 [US1] Écrire `golden/saas-b2b/local/scripts/app.sh` : construction sous l'hôte de T082 avec une étiquette neuve posée par Kustomize, `kind load docker-image`, application de `local/k8s/<profil>` par `kubectl apply -k`, chacune définie une seule fois (ADR-006, condition 6) ; attente bornée de « prêt » ; affichage des adresses, des durées et de la taille du volume du miroir (FR-015). Dépend de T082, T087. Trace : FR-001, FR-002, FR-015 ; E01, E17.
- [ ] T089 [US1] Écrire `task reload` et `task app:down` dans `golden/saas-b2b/local/tasks/app.yml` en réutilisant les étapes de `app.sh`, et compléter l'inventaire du Taskfile ; E01, E02, E07, E08, E09, E11, E17, E18, S01 et S07 au vert dans `e2e-lite`. Dépend de T083, T084, T085, T086, T088. Trace : FR-001, FR-007 ; E01, E02, E07, E08, E09, E11, E17, E18.

### Étape 11 : README

- PR : `docs(golden): write the golden repo README`
- Dépend de : étape 9
- État : bloquée par l'étape 9
- Contrôles mis au vert : S18

- [ ] T090 [P] [US1] Vérifier et dater les prérequis du README, avec version, licence et date : moteur libre à citer d'abord, selon l'évaluation d'[OPS] (ADR-004, condition 8 ; ADR-011, condition 12 ; R-26), Docker Engine, kind, kubectl, Task, Git ; consigner aux points RS-09 et RS-18 de `specs/001-golden-repo-saas-b2b/research.md`. Porteurs : [DEV] et [OPS]. Trace : FR-018 ; débloque S18.
- [ ] T091 [US1] Écrire en rouge `golden/saas-b2b/tests/static/s18-readme.sh` : prérequis avec version, licence et date ; moteur libre cité d'abord ; écarts entre PC et cloud ; secrets locaux en clair dans le cluster ; mémoire par profil ; installation de kind vérifiée contre le SHA-256 du catalogue. Trace : FR-018 ; S18.
- [ ] T092 [US1] Écrire `golden/saas-b2b/README.md` : prérequis de T090, `task up` et les commandes du contrat task-cli, écarts PC et cloud (ENF-02, dont `db-superuser` et le mode TLS de T062), secrets en clair (R-28), mémoire par profil, démontage en deux temps de l'ADR-008 (condition 10) décrit sans être lancé, rien de promis sur les données après un redémarrage du nœud ; S18 au vert. Dépend de T090, T091. Trace : FR-018 ; S18.

**Checkpoint** : profil lite qui démarre par `task up` ; US1 et US2 testables seuls (E01 à E09, E11 à E13, E17 à E21, U01, U02, P01 à P06 au vert).

---

## Phase 4: User Story 4 (Priority: P2), conventions Git

**Goal** : les conventions Git du projet généré (hooks, commitlint, Renovate, release-please, workflows) tournent dans une copie autonome du golden repo.

**Independent Test** : dans une copie initialisée comme dépôt Git neuf, un message de commit non conforme est refusé et un message conforme passe (X01).

### Étape 2 : conventions Git du projet

- PR : `ci(golden): add the generated project's Git conventions`
- Dépend de : étape 1
- État : prête
- Contrôles mis au vert : X01, S17, S23

- [X] T093 [P] [US4] Vérifier et dater le validateur de configuration de Renovate (version, licence, date, usage hors ligne) ; relever dans la configuration de CELIAN (`renovate.json`, `release-please-config.json`, `.pre-commit-config.yaml`, `.github/workflows/`) les réglages et les SHA déjà figés que le golden repo reprend ; consigner au point RS-18 de `specs/001-golden-repo-saas-b2b/research.md`. Trace : FR-013 ; débloque S23, X01.
- [X] T094 [P] [US4] Étendre en rouge `golden/saas-b2b/tests/static/s17-workflows.sh` aux workflows de `golden/saas-b2b/.github/workflows/`. Trace : FR-011, FR-013 ; S17.
- [X] T095 [P] [US4] Écrire en rouge `golden/saas-b2b/tests/static/s23-renovate.sh` : délai de 7 jours, exception de sécurité, aucune autre majeure pour `postgres`, paire kind et image de nœud, paire chart et condensat d'Envoy Gateway. Dépend de T093. Trace : FR-013 ; S23.
- [X] T096 [US4] Écrire en rouge `golden/saas-b2b/tests/export/x01-standalone-copy.sh` : copie du golden repo dans un dépôt Git neuf, hooks qui passent, commitlint qui refuse un message non conforme et accepte un message conforme, actionlint qui passe sur ses workflows, actions figées par SHA, gitleaks qui passe sur son historique. Trace : FR-013 ; X01.
- [X] T097 [US4] Écrire `golden/saas-b2b/.pre-commit-config.yaml` et `golden/saas-b2b/.commitlintrc.yaml`, hooks et SHA repris de la racine de CELIAN (T093), `no-em-dash`, gitleaks, actionlint et shellcheck compris. Dépend de T093. Trace : FR-013 ; X01.
- [X] T098 [US4] Écrire `golden/saas-b2b/renovate.json` : 7 jours, exception de sécurité (principe VI, constitution 1.2.0), règles de S23 ; relecture [SECU] demandée dans la PR ; S23 au vert. Dépend de T095. Trace : FR-013 ; S23.
- [X] T099 [P] [US4] Écrire `golden/saas-b2b/release-please-config.json`, `golden/saas-b2b/.release-please-manifest.json`, `golden/saas-b2b/.github/CODEOWNERS` et `golden/saas-b2b/.github/pull_request_template.md`. Dépend de T093. Trace : FR-013 ; X01.
- [X] T100 [US4] Écrire les workflows du projet généré dans `golden/saas-b2b/.github/workflows/` : hooks, recherche de secrets sur tout l'historique, titre de PR par commitlint, `task check` et `task test`, release-please ; actions figées par SHA ; S17 au vert. Dépend de T094, T097, T099. Trace : FR-013, FR-014 ; S17, X01.
- [X] T101 [US4] Ajouter le job `export` à `.github/workflows/golden-saas-b2b.yml`, qui lance X01 ; X01 au vert. Dépend de T096, T100. Trace : FR-013 ; X01.

**Checkpoint** : US4 testable seul ; X01, S17 et S23 au vert.

---

## Phase 5: User Story 3 (Priority: P2), cible cloud sans dépense

**Goal** : la racine OpenTofu de la couche `gcp` passe la validation, les politiques et le scan en CI, sans identifiant cloud, sans plan ni apply.

**Independent Test** : une PR qui touche `golden/saas-b2b/gcp/` fait tourner `gcp:validate`, `gcp:policy` et `gcp:scan`, et un module tiers tiré par tag fait échouer `gcp:policy` en nommant la condition 8 de l'ADR-008 (S14, S15, S17).

### Étape 13 : couche GCP en OpenTofu

- PR : `feat(golden): write the GCP layer in OpenTofu`
- Dépend de : étape 1 ; provider `google` 8.12.0 utilisable à partir du 2026-11-24, sinon la version précédente qui passe le délai (RS-16)
- État : prête à partir du 2026-11-24 ; l'alerte budget reste bloquée (T110)
- Contrôles mis au vert : S14, S15, S17

- [X] T102 [P] [US3] Lever les points de RS-16 : option qui désactive le backend à l'init ; validation d'une configuration de chiffrement `gcp_kms` sans accès à la clé ; commande qui inscrit les sommes de chaque plateforme dans le verrou et effet de `-lockfile=readonly` sur une plateforme absente (ADR-008, question 5) ; lecture de `platform.yaml` par une fonction de décodage YAML ; attributs des activations (Gateway API, synchronisation des secrets, flotte, Config Sync) ; version du provider `random` ; version d'OpenTofu à installer en CI (1.11 au moins) avec son SHA-256 ; date effective de `google` 8.12.0 ; consigner au point RS-16 de `specs/001-golden-repo-saas-b2b/research.md`. Porteurs : [OPS] et [DEV]. Trace : FR-011 ; débloque S14, S15.
- [X] T103 [P] [US3] Vérifier et dater Trivy 0.76.2 : SHA-256 des binaires depuis le fichier de sommes de la release, signature sigstore vérifiée par cosign (version et commande de cosign vérifiées et datées), documentation de cette version ; inscrire Trivy dans `golden/saas-b2b/tests/tools/SHA256SUMS` et `golden/saas-b2b/tests/tools/install.sh` ; consigner au point RS-22 de `specs/001-golden-repo-saas-b2b/research.md`. Porteurs : [DEV] et [SECU]. Trace : FR-011, FR-021 ; débloque S15, S26.
- [X] T104 [US3] Écrire en rouge les politiques de `golden/saas-b2b/gcp/policy/` et leurs cas d'échec dans `golden/saas-b2b/gcp/policy/testdata/` : conditions 1 à 6 et 8 de l'ADR-008 (fédération sur identifiants numériques, chiffrement de l'état et des plans, attributs `*_wo`, compte de service des nœuds, `dns_endpoint_config`, Trivy et conftest, aucun module tiers par tag), condition 2 de l'ADR-007, version figée de Config Sync ; chaque refus nomme sa condition. Dépend de T102. Trace : FR-011, FR-012 ; S15.
- [X] T105 [US3] Écrire en rouge `golden/saas-b2b/gcp/tasks/gcp.yml` (`gcp:validate`, `gcp:policy`, `gcp:scan`), sans tâche `gcp:plan`, `gcp:apply` ni `gcp:destroy` ; étendre `golden/saas-b2b/tests/static/s17-workflows.sh` aux Taskfiles et `golden/saas-b2b/policy/platform_values.rego` aux valeurs de la couche OpenTofu. Dépend de T102, T103. Trace : FR-010, FR-011, FR-019 ; S14, S15, S17, S21.
- [X] T106 [US3] Écrire la racine `golden/saas-b2b/gcp/tofu/`, partie réseau et cluster : API activées sur un projet existant, réseau VPC et accès privé aux services, GKE Autopilot à nœuds privés avec `dns_endpoint_config`, canal Regular, compte de service des nœuds ; activations dont l'attribut n'est pas vérifié en T102 laissées en commentaire daté avec leur `pending`. Dépend de T104. Trace : FR-011, FR-012 ; S14, S15.
- [X] T107 [US3] Écrire la racine `golden/saas-b2b/gcp/tofu/`, partie données et secrets : Cloud SQL for PostgreSQL à la majeure de `platform.yaml`, en IP privée ; Artifact Registry à tags immuables ; secret de `db-auth` dans Secret Manager par attributs `*_wo` ; aucun Memorystore avant l'étape 20. Utilisateur de `db-auth` : écrire l'hypothèse de RS-04 (relecture [SECU] de l'étape 3), lister l'écart de privilèges dans ENF-02 et au modèle de menaces (R-39), et prévoir pour E12, au premier apply autorisé, la lecture du propriétaire de `app`, du droit `CREATE` sur `public` et de `inherit_option`. Dépend de T106. Trace : FR-011, FR-017 ; S14, S15, S21.
- [X] T108 [US3] Écrire la racine `golden/saas-b2b/gcp/tofu/`, partie identité et chiffrement : identité de la CI par fédération sur identifiants numériques, chiffrement de l'état et des plans ; puis `golden/saas-b2b/gcp/tofu/.terraform.lock.hcl` multi-plateformes par la commande de T102. Dépend de T107. Trace : FR-011 ; S14, S15.
- [X] T109 [US3] Brancher `gcp:validate` (`tofu init -lockfile=readonly` puis `tofu validate`, sans backend distant ni identifiant), `gcp:policy` et `gcp:scan` (Trivy sur le HCL, chaque échec corrigé ou justifié par écrit à côté de la ressource) sur `task check` de `golden/saas-b2b/Taskfile.yml`, donc sur le job `static` de `.github/workflows/golden-saas-b2b.yml` ; S14, S15, S17 et S21 au vert. Dépend de T105, T108. Trace : FR-011 ; S14, S15, S17, S21.
- [ ] T110 [US3] Décision du DSI du 2026-11-25 sur l'alerte budget (ADR-008, question 1) : une racine séparée, `golden/saas-b2b/gcp/budget/`, appliquée à la main avant la racine principale. Conditions de [SECU] : l'identité de la racine principale n'a aucun rôle de base Owner ni Editor, qui portent `billing.resourcebudgets.write` (relevé par [SECU], à relire sur la page des rôles de Google avant l'écriture) ; la racine du budget s'applique à la main, avec `roles/billing.costsManager` sur le compte de facturation, jamais par la CI ; elle a son propre préfixe d'état, avec le même chiffrement KMS ; elle est détruite en dernier ; S14 et S15 la couvrent. À écrire : l'alerte budget dans cette racine et sa politique dans `golden/saas-b2b/gcp/policy/`, avec son cas d'échec. Trace : FR-011 ; S15.

**Checkpoint** : US3 testable seul pour la partie OpenTofu ; S14, S15 et S17 au vert, aucun euro dépensé (SC-006).

---

## Phase 6: User Story 7 (Priority: P2), SBOM et scan des images

**Goal** : la CI produit le SBOM de chaque image construite, scanne toutes les images que le profil fait tourner et bloque la fusion au seuil `HIGH`, sauf exception datée et valide.

**Independent Test** : U03 joue la décision sur des rapports d'exemple à date fixée (refus, exception valide, exception échue) ; puis, dans `e2e-lite`, E25 à E27 relèvent, documentent et scannent les images en marche.

### Étape 18 : SBOM et scan des images, première PR

- PR : `ci(golden): scan the images and keep their SBOM`
- Dépend de : étape 7 ; T103 (Trivy figé à l'étape 13)
- État : prête dès l'étape 7 fusionnée et T103 fait
- Contrôles mis au vert : S25, S26, S27, U03, E27 sur les images tirées

- [ ] T111 [P] [US7] Vérifier et dater sur la documentation de Trivy 0.76.2 : code de sortie quand aucun registre de la base ne répond, structure du rapport JSON, rapport filtré au seuil sans échec ; sur celle de conftest, chargement d'un fichier de données et passage de la date en donnée ; consigner aux points RS-22 et RS-23 de `specs/001-golden-repo-saas-b2b/research.md`. Porteurs : [DEV] et [SECU]. Trace : FR-021, FR-022 ; débloque U03, E27.
- [ ] T112 [US7] Écrire en rouge la politique de décision `golden/saas-b2b/policy/scan_decision.rego`, ses tests et les rapports d'exemple de `golden/saas-b2b/tests/scan-reports/`, à date fixée : faille au seuil sans exception, refus qui nomme l'image et la vulnérabilité ; exception complète et non échue, passage ; exception échue, incomplète ou visant une autre image, refus ; faille sous le seuil, passage ; faille `UNKNOWN` listée sans bloquer. Dépend de T111. Trace : FR-022 ; U03.
- [ ] T113 [P] [US7] Écrire en rouge `golden/saas-b2b/tests/static/s26-scan-policy.sh` et `golden/saas-b2b/tests/static/s27-exceptions.sh` : seuil écrit une seule fois et lu par la tâche ; Trivy installé depuis la release, SHA-256 vérifié, version 0.71.1 au moins ; aucune action `aquasecurity/trivy-action` ni `aquasecurity/setup-trivy` ; aucune option `--skip-db-update` ni `--ignore-unfixed` ; aucune source de base autre que celles par défaut, hors du cas de E27 sous `.invalid` ; aucun cache de la base entre deux exécutions ; jobs du scan parmi les contrôles requis de `.github/rulesets/main.json` ; chaque exception nomme la vulnérabilité et l'image (dépôt sans condensat), porte sa justification, sa date d'écriture et sa date d'échéance « AAAA-MM-JJ, postérieure à la date d'écriture ; 90 jours au plus proposés, à confirmer par [SECU] », et les entrées échues ou incomplètes sont listées. Trace : FR-021, FR-022 ; S26, S27.
- [ ] T114 [P] [US7] Écrire en rouge `golden/saas-b2b/local/tests/static/s25-inventory.sh` : l'inventaire d'un profil se calcule depuis les fichiers présents (configuration kind, tâche du miroir, fichiers vendorés, manifests de `local/data/`, rendus quand ils existent) et la liste `local/security/unlisted-images`, dont chaque entrée porte un condensat. Trace : FR-021 ; S25.
- [ ] T115 [US7] Écrire `golden/saas-b2b/security/scan-policy.yaml` (seuil `HIGH`), `golden/saas-b2b/security/scan-exceptions.yaml`, `golden/saas-b2b/local/security/scan-exceptions.yaml` et `golden/saas-b2b/local/security/unlisted-images` (image du proxy d'Envoy Gateway, par le condensat relevé par BENCH-004) ; S27 au vert. Dépend de T113. Trace : FR-021, FR-022 ; S25, S27.
- [ ] T116 [US7] Écrire `golden/saas-b2b/local/scripts/image-inventory.sh` (inventaire par profil) et `golden/saas-b2b/tests/scan/scan-images.sh` (rapport JSON de Trivy par image au seuil, base téléchargée dans l'exécution, décision par la politique de T112 avec la date du jour) ; S25, S26 et U03 au vert, U03 branché sur `task test`. Dépend de T103, T112, T114, T115. Trace : FR-021, FR-022 ; S25, S26, U03.
- [ ] T117 [US7] Ajouter à `.github/workflows/golden-saas-b2b.yml` le job du scan des images tirées, sans cluster, avec le cas de E27 où une source de base sous `.invalid` doit échouer en le disant ; ajouter le job aux contrôles requis de `.github/rulesets/main.json`. Dépend de T116. Trace : FR-021, FR-022 ; E27, S26.
- [ ] T118 [US7] Faire le premier passage du scan, relever le nombre de failles `HIGH` et `CRITICAL` par image, et écrire les exceptions nécessaires dans `golden/saas-b2b/local/security/scan-exceptions.yaml`, dont CVE-2026-97054 si aucune release 1.10.x corrigée d'Envoy Gateway n'existe, avec la justification de l'ADR-005 ; confirmer l'échéance maximale et le sort des failles `UNKNOWN` ; si le nombre dépasse ce qui se justifie une par une, remonter au DSI (seuil ou spec à rediscuter avec Lucas). Porteur : [SECU]. Dépend de T117. Trace : FR-022 ; E27, S27.

### Étape 18 : SBOM et scan des images, seconde PR

- PR : `ci(golden): scan the running images of the lite profile` (proposé)
- Dépend de : étape 9, première PR de l'étape 18
- État : bloquée par l'étape 9, donc par l'ADR-015
- Contrôles mis au vert : E25, E26, E27 complet

- [ ] T119 [US7] Vérifier et dater : champ du statut des pods qui porte l'image résolue ; référence des images préchargées par l'image du nœud et leur scan par Trivy depuis leur registre, ou à défaut leur export vers une archive ; lecture par Trivy d'une image construite dans le moteur du runner ou par une archive ; version et SHA de l'action d'envoi d'artefacts ; consigner aux points RS-22 et RS-24 de `specs/001-golden-repo-saas-b2b/research.md`. Porteurs : [DEV] et [OPS]. Trace : FR-020, FR-021 ; débloque E25, E26.
- [ ] T120 [P] [US7] Écrire en rouge `golden/saas-b2b/local/tests/images/e25-running-images.sh` et `golden/saas-b2b/local/tests/images/e26-sbom.sh` : image résolue de chaque conteneur en marche, conteneurs d'initialisation compris, dans le cluster et sur le moteur, présente dans l'inventaire scanné, et échec qui nomme toute image absente ; un SBOM CycloneDX JSON non vide par image construite, et échec qui nomme l'image sans SBOM. Dépend de T119. Trace : FR-020, FR-021 ; E25, E26.
- [ ] T121 [P] [US7] Compléter `golden/saas-b2b/local/security/unlisted-images` avec les images préchargées par l'image du nœud, par condensat. Dépend de T119. Trace : FR-021 ; S25, E25.
- [ ] T122 [US7] Écrire `task test:images` dans `golden/saas-b2b/local/tasks/test.yml` : relevé des images en marche, SBOM CycloneDX de chaque image construite, scan de l'inventaire du profil courant, images construites comprises. Dépend de T120, T121. Trace : FR-020, FR-021, FR-022 ; E25, E26, E27.
- [ ] T123 [US7] Lancer `task test:images` à la fin du job `e2e-lite` de `.github/workflows/golden-saas-b2b.yml`, garder les SBOM en artefacts de l'exécution, retirer le job à part de T117, mettre à jour les contrôles requis de `.github/rulesets/main.json`, et ajouter les jobs du SBOM et du scan aux workflows de `golden/saas-b2b/.github/workflows/` ; E25, E26, E27 et S26 au vert. Dépend de T122. Trace : FR-020, FR-021, FR-022 ; E25, E26, E27, S26.

**Checkpoint** : US7 testable pour le profil lite ; 0 image construite sans SBOM, 0 image en marche hors du scan (SC-010).

---

## Phase 7: User Story 6 (Priority: P3), redémarrage sans réseau

**Goal** : après un premier démarrage en ligne, le profil lite redémarre sans registre public, cluster supprimé puis recréé.

**Independent Test** : premier `task up` en ligne, `task down`, puis `task test:offline` jusqu'à l'état prêt (E10).

### Étape 10 : hors réseau du profil lite

- PR : `test(golden): restart the lite profile without registries`
- Dépend de : étape 9
- État : bloquée par l'étape 9, donc par l'ADR-015
- Contrôles mis au vert : E10 (lite), E20, E23 ; plus le test du premier démarrage sans registre, absent de la matrice (« Écarts relevés », point 4)

- [ ] T124 [P] [US6] Écrire en rouge `golden/saas-b2b/local/tests/offline/e10-offline-restart.sh` : premier `task up` en ligne, `task down`, registres publics coupés pour le seul cluster selon la méthode de `tests/bench/bench-010-offline.sh`, puis `task up` qui recrée le cluster et atteint « prêt » par le miroir en capacité `pull` seule, avec un pod en `imagePullPolicy: Always` et l'image `postgres:18.7-trixie` comprise. Trace : FR-016 ; E10.
- [ ] T125 [P] [US6] Écrire en rouge `golden/saas-b2b/local/tests/offline/e20-mirror-volume.sh` et `golden/saas-b2b/local/tests/offline/e23-mirror-nonroot.sh` : volume du miroir hors de l'arborescence et, après `task mirror:purge` puis un `task up` en ligne, réduit aux condensats du projet ; essai du miroir sous un UID non root sans capacités, résultat consigné pour [SECU]. Trace : FR-016 ; E20, E23.
- [ ] T126 [P] [US6] Écrire en rouge `golden/saas-b2b/local/tests/offline/first-start-no-registry.sh` : sans registre joignable et miroir vide, `task up` échoue dans un délai borné, nomme le registre et dit que le premier démarrage demande le réseau (cas limite de la spec, contrat task-cli). Trace : FR-001, FR-016 ; contrôle à numéroter dans le plan.
- [ ] T127 [US6] Borner chaque attente de tirage dans `golden/saas-b2b/local/scripts/` par des constantes nommées, et écrire les messages du contrat task-cli pour un registre lent ou injoignable ; T126 au vert. Dépend de T126. Trace : FR-001, FR-016.
- [ ] T128 [US6] Écrire `task test:offline` dans `golden/saas-b2b/local/tasks/test.yml` et le job `offline-lite` dans `.github/workflows/golden-saas-b2b.yml` et dans les workflows de `golden/saas-b2b/.github/workflows/` ; E10, E20 et E23 au vert ; un échec de E10 en capacité `pull` seule rouvre l'ADR-011 et remonte au DSI. Dépend de T124, T125, T127. Trace : FR-016 ; E10, E20, E23.

**Checkpoint** : US6 testable pour le profil lite (SC-009 sur lite). Le profil lite est livré : étapes 1 à 11, 18 et 19 fusionnées.

---

## Phase 8: User Story 5 (Priority: P3), parité des couches et couche GCP complète

**Goal** : la couche commune rendue se retrouve à l'identique dans les rendus `local` et `gcp` ; la couche `gcp` porte ses manifests et, après l'ADR-015, Memorystore.

**Independent Test** : `task check` rend les deux cibles et les compare (S06, S07, S08) ; `gcp-on-kind` applique la couche `gcp` sur kind avec Config Sync libre (E16).

### Étape 14 : couche GCP, manifests

- PR : `feat(golden): add the GCP Kubernetes layer`
- Dépend de : étapes 9 et 13
- État : bloquée par l'étape 9, donc par l'ADR-015
- Contrôles mis au vert : S07, S08, S16, E16 ; plus la partie `RootSync` de S10 (« Écarts relevés », point 5)

- [ ] T129 [P] [US5] Vérifier et dater : version de Gateway API que sert GKE et son schéma ; kubeconform (version, licence, date, SHA-256), choix confirmé avec [QA] ; manifests et condensats de Config Sync 1.25.2 libre pour kind ; classe de Gateway de GKE (avec [OPS]) ; fabrication de `gateway-tls` sur `gcp` (avec [OPS] et [SECU]) ; consigner aux points RS-16 et RS-18 de `specs/001-golden-repo-saas-b2b/research.md`. Trace : FR-010, FR-012 ; débloque S08, E16.
- [ ] T130 [P] [US5] Étendre en rouge `golden/saas-b2b/tests/static/s07-parity.sh` au rendu `gcp` et écrire `golden/saas-b2b/tests/static/s08-schemas.sh` : couche commune identique dans les rendus `local` et `gcp`, `spec.gatewayClassName` à part ; tout objet absent de la couche commune vient de la couche de sa cible ; une seule Gateway ; mêmes références aux Secrets et à `app-config` (nom, clés, lecture par fichier) ; couche commune valide contre le schéma de Gateway API servi par GKE, manifests valides contre leurs schémas. Dépend de T129. Trace : FR-010 ; S07, S08.
- [ ] T131 [P] [US3] Écrire en rouge `golden/saas-b2b/gcp/policy/requests.rego` et ses tests, et la partie `RootSync` de S10 dans `golden/saas-b2b/gcp/policy/rootsync.rego` : `requests` sur chaque pod, règle d'admission présente ; `roleRefs`, `sourceFormat: unstructured` et export des métriques coupé sur le `RootSync`. Trace : FR-012 ; S16, S10.
- [ ] T132 [US3] Écrire en rouge `golden/saas-b2b/gcp/tests/e16-configsync-kind.sh` : couche `gcp` sur kind avec Config Sync libre en version figée, runner x64 : liaison, rendu et droits de `roleRefs`. Dépend de T129. Trace : FR-012 ; E16.
- [ ] T133 [US5] Écrire `golden/saas-b2b/k8s/overlays/staging/` et `golden/saas-b2b/k8s/overlays/prod/`, neutres vis-à-vis de l'outil et du fournisseur (ADR-010, condition 1) ; S06 au vert. Trace : FR-010 ; S06, S07.
- [ ] T134 [US3] Écrire le composant de cible `golden/saas-b2b/gcp/k8s/component/` (`gatewayClassName` de T129, `app-config` de GCP aux clés de T021, `SecretProviderClass` et `SecretSync` de `db-auth`, règle d'admission sur les `requests`), la composition `golden/saas-b2b/gcp/k8s/prod/` et le `RootSync`, jamais appliqué sur GKE ; S07, S08, S10 et S16 au vert. Dépend de T130, T131, T133. Trace : FR-010, FR-012 ; S07, S08, S10, S16.
- [ ] T135 [US3] Ajouter le job `gcp-on-kind` à `.github/workflows/golden-saas-b2b.yml` et aux workflows de `golden/saas-b2b/.github/workflows/` ; E16 au vert. Dépend de T132, T134. Trace : FR-012 ; E16.

### Étape 20 : couche GCP, Memorystore

- PR : `feat(golden): add Memorystore to the GCP layer`
- Dépend de : étapes 13 et 14, ADR-015
- État : bloquée par l'ADR-015 et par l'étape 14
- Contrôles mis au vert : S14, S15, S07 (`cache-auth`)

- [ ] T136 [US3] Relever dans l'ADR-015 la variante et l'authentification de Memorystore, puis vérifier et dater les attributs correspondants du provider `google` ; consigner au point RS-11 de `specs/001-golden-repo-saas-b2b/research.md`. Porteurs : [DEV] et [OPS]. Trace : FR-011 ; débloque S15.
- [ ] T137 [US3] Écrire en rouge les politiques de Memorystore dans `golden/saas-b2b/gcp/policy/`, avec leurs cas d'échec, et étendre `golden/saas-b2b/tests/static/s07-parity.sh` à `cache-auth`. Dépend de T136. Trace : FR-011, FR-012 ; S15, S07.
- [ ] T138 [US3] Écrire la ressource Memorystore et son authentification dans `golden/saas-b2b/gcp/tofu/`, le producteur `gcp` de `cache-auth` dans `golden/saas-b2b/gcp/k8s/component/` et les valeurs du cache dans l'`app-config` de GCP ; mettre à jour le verrou si un provider change ; S14, S15 et S07 au vert, sans plan ni apply. Dépend de T137. Trace : FR-011 ; S14, S15, S07.

**Checkpoint** : US5 testable seul (SC-007 : 0 écart dans la couche commune) ; couche `gcp` complète et validée sans dépense.

---

## Phase 9: profil standard (User Story 1, FR-006)

**Goal** : le profil standard, mesure du critère des 15 minutes, ajoute Flux à liaison suspendue, puis Keycloak et Mailpit après leurs ADR.

**Independent Test** : `PROFILE=standard task up` démarre Flux sans réconciliation ; E14, E15, E10 et E25 à E27 passent en standard.

### Étape 12 : profil standard, Flux

- PR : `feat(golden): add Flux to the standard profile`
- Dépend de : étapes 10 et 18 (seconde PR) ; décision d'[OPS] sur le nombre de contrôleurs (ADR-010, question 4)
- État : bloquée par les étapes 10 et 18, donc par l'ADR-015, et par la décision d'[OPS] (T139)
- Contrôles mis au vert : S09, S10, S28, E14, E15, E10 (standard), E25 à E27 (standard)

- [ ] T139 [US1] Obtenir la décision d'[OPS] sur le nombre de contrôleurs de Flux (ADR-010, question 4 ; le plan en suppose quatre) et la consigner au point RS-14 de `specs/001-golden-repo-saas-b2b/research.md`. Porteur : [OPS]. Trace : FR-006 ; débloque T143, T145, T146.
- [ ] T140 [P] [US1] Vérifier et dater : version de Flux (2.10.0 de l'ADR-010, ou 2.10.1 utilisable à partir du 2026-11-27), SHA-256 de `install.yaml` et condensats des contrôleurs (`tests/bench/bench-009-gitops.sh`, lignes 72 à 93) ; `Kustomization` suspendue sans objet source, admise et inerte (RS-14) ; mécanisme qui interroge les droits d'un compte de service ; versions de Kustomize qu'embarquent Flux 2.10 et Config Sync 1.25.2 ; montages a et b de zot à plusieurs amonts avec ghcr.io (RS-13, avec [OPS]) ; consigner aux points RS-13 et RS-14 de `specs/001-golden-repo-saas-b2b/research.md`. Trace : FR-006, FR-012, FR-016 ; débloque S09, S10, S28, E15, E10.
- [ ] T141 [P] [US1] Écrire en rouge `golden/saas-b2b/tests/static/s09-kustomize-versions.sh`, `golden/saas-b2b/local/tests/static/s10-flux-binding.sh` (partie Flux de S10) et `golden/saas-b2b/local/tests/static/s28-flux-suspended.sh` : chaque overlay rendu avec la version de Kustomize de Flux et avec celle de Config Sync donne le même résultat ; `serviceAccountName` sur chaque `Kustomization`, options de verrouillage des contrôleurs, aucun `cluster-admin`, aucun `auth: token` ; `spec.suspend: true` sur chaque `Kustomization` de `local/gitops/` et aucun objet source livré. Dépend de T140. Trace : FR-006, FR-012 ; S09, S10, S28.
- [ ] T142 [P] [US1] Écrire en rouge `golden/saas-b2b/local/tests/e2e/e14-profile-components.sh` et `e15-flux-rights.sh`, et étendre `golden/saas-b2b/local/tests/offline/e10-offline-restart.sh` au profil standard : en lite, aucun contrôleur de Flux ; en standard, Flux et les couches entrées ; le compte de service de la liaison d'un environnement n'a aucun droit d'écriture dans le namespace d'un autre, vérifié sans réactiver la liaison ; T2 du standard avec ghcr.io par le miroir. Dépend de T140. Trace : FR-006, FR-012, FR-016 ; E14, E15, E10.
- [ ] T143 [US1] Vendorer `install.yaml` de Flux dans `golden/saas-b2b/local/vendor/` avec son SHA-256, contrôleurs par condensat et options de verrouillage (ADR-010, condition 3), et écrire les objets de liaison suspendus de `golden/saas-b2b/local/gitops/`, ou le repli de RS-14 (contrôleurs seuls) ; S02, S10 et S28 au vert. Dépend de T139, T141. Trace : FR-006, FR-012 ; S02, S10, S28.
- [ ] T144 [US1] Ajouter ghcr.io à `golden/saas-b2b/local/mirror/registries` et aux fichiers dérivés, selon le montage retenu en T140 ; S13 au vert. Dépend de T140. Trace : FR-016 ; S13, E10.
- [ ] T145 [US1] Écrire `golden/saas-b2b/local/k8s/standard/` ; faire installer Flux par `task up` en standard ; faire suspendre la liaison par `task app:down` si elle ne l'est pas ; accepter le standard dans `golden/saas-b2b/local/scripts/preflight.sh` et `p03-memory.sh`, seuil recalculé ; S09, P03, E14 et E15 au vert. Dépend de T142, T143, T144. Trace : FR-006, FR-007 ; S09, P03, E14, E15.
- [ ] T146 [US1] Ajouter à `.github/workflows/golden-saas-b2b.yml` et aux workflows de `golden/saas-b2b/.github/workflows/` le job `e2e-standard`, terminé par `task test:images`, et le job `offline-standard` (nom proposé) ; ajouter `e2e-standard` aux contrôles requis de `.github/rulesets/main.json` ; E10, E25, E26 et E27 au vert en standard. Dépend de T145. Trace : FR-006, FR-016, FR-021 ; E10, E25, E26, E27.

### Étape 15 : profil standard, Keycloak

- PR : `feat(golden): add Keycloak to the standard profile`
- Dépend de : étape 12, ADR-013 (après BENCH-012)
- État : bloquée par l'étape 12 et l'ADR-013
- Contrôles mis au vert : E10 (standard), E14, E25 à E27 (standard), contrôles fixés par l'ADR-013

- [ ] T147 [US1] Relever dans l'ADR-013 l'image, la version, le registre, les Secrets, la mémoire et les contrôles à écrire, puis vérifier et dater ce qui dépend d'une source tierce ; consigner au point RS-15 de `specs/001-golden-repo-saas-b2b/research.md`. Trace : FR-006 ; débloque T148, T149.
- [ ] T148 [US1] Écrire en rouge les contrôles fixés par l'ADR-013 dans `golden/saas-b2b/local/tests/`, et étendre `e04-secrets-fresh.sh`, `e05-secrets-kept.sh` et `e14-profile-components.sh` de `golden/saas-b2b/local/tests/e2e/` à la couche Keycloak. Dépend de T147. Trace : FR-004, FR-006 ; E04, E05, E14.
- [ ] T149 [US1] Écrire `golden/saas-b2b/local/identity/` (et la base de Keycloak si BENCH-012 en demande une), ses Secrets dans `local/scripts/secrets.sh`, son registre dans `local/mirror/registries`, ses images dans l'inventaire, son entrée dans `local/k8s/standard/`, et le seuil de mémoire recalculé ; l'API n'appelle pas Keycloak (RS-25) ; E10, E14, E25, E26 et E27 au vert en standard. Dépend de T148. Trace : FR-006, FR-016, FR-021 ; E10, E14, E25, E26, E27.

### Étape 16 : profil standard, Mailpit

- PR : `feat(golden): add Mailpit to the standard profile`
- Dépend de : étape 12, ADR-014 (après BENCH-013)
- État : bloquée par l'étape 12 et l'ADR-014
- Contrôles mis au vert : E10 (standard), E14, E25 à E27 (standard), contrôles fixés par l'ADR-014

- [ ] T150 [US1] Relever dans l'ADR-014 l'image, la version, le registre, les Secrets, la mémoire et les contrôles à écrire, puis vérifier et dater ce qui dépend d'une source tierce ; consigner au point RS-15 de `specs/001-golden-repo-saas-b2b/research.md`. Trace : FR-006 ; débloque T151, T152.
- [ ] T151 [US1] Écrire en rouge les contrôles fixés par l'ADR-014 dans `golden/saas-b2b/local/tests/`, et étendre `e04-secrets-fresh.sh`, `e05-secrets-kept.sh` et `e14-profile-components.sh` de `golden/saas-b2b/local/tests/e2e/` à la couche Mailpit si elle a des Secrets. Dépend de T150. Trace : FR-004, FR-006 ; E04, E05, E14.
- [ ] T152 [US1] Écrire `golden/saas-b2b/local/mail/`, ses Secrets s'il en a, son registre dans `local/mirror/registries`, ses images dans l'inventaire, son entrée dans `local/k8s/standard/`, et le seuil de mémoire recalculé ; E10, E14, E25, E26 et E27 au vert en standard. Dépend de T151. Trace : FR-006, FR-016, FR-021 ; E10, E14, E25, E26, E27.

**Checkpoint** : profil standard livré, FR-006 complet.

---

## Phase 10: Polish & Cross-Cutting Concerns, mesures de la gate

**Purpose** : démo de la gate de la phase 2 (R-04) et tâches transverses.

### Étape 17 : mesures et démo

- PR : `docs(golden): measure the first standard start`
- Dépend de : étapes 11, 14, 15, 16, 18, 19 et 20
- État : bloquée, en dernier
- Contrôles : D01 à D05

- [ ] T153 Fixer avec [BENCH] la méthode de mesure du volume et du temps en démo, reprise des scripts de BENCH (RS-19), et écrire le protocole dans `specs/001-golden-repo-saas-b2b/demo-protocol.md` : poste propre, connexion notée, profil standard, personne qui ne connaît pas le dépôt. Porteurs : [DEV] et [BENCH]. Trace : US1, FR-015 ; D01, D02.
- [ ] T154 Dérouler D01 et D02 sur un poste propre : API et front qui répondent après une seule commande, à chaque essai ; durée totale et par étape, volume du premier démarrage standard, rapportés aux 900 s et au débit nécessaire ; relevés bruts dans `specs/001-golden-repo-saas-b2b/demo-report.md`. Porteurs : Lucas et [BENCH]. Dépend de T153. Trace : US1, FR-001, FR-015 ; D01, D02, SC-001, SC-002.
- [ ] T155 [P] Relever D03 (mémoire du profil lite face à un portable de 8 Gio) et D04 (même parcours sur un poste arm64) ; relevés bruts dans `specs/001-golden-repo-saas-b2b/demo-report.md`. Porteurs : [BENCH] et [FINOPS]. Dépend de T153. Trace : US1, FR-006 ; D03, D04, SC-008.
- [ ] T156 [P] Dérouler D05 : T1 et T2 sur un poste réellement coupé du réseau, construction comprise (suite de l'ADR-011) ; relevés bruts dans `specs/001-golden-repo-saas-b2b/demo-report.md`. Porteur : Lucas. Trace : US6, FR-016 ; D05, SC-009.
- [ ] T157 Écrire le rapport `specs/001-golden-repo-saas-b2b/demo-report.md` : mesures de T154 à T156, débit visé fixé par [FINOPS] après D02, écart au budget (R-04), scénarios 1 à 9 de `specs/001-golden-repo-saas-b2b/quickstart.md` rejoués. Dépend de T154, T155, T156. Trace : US1, US6, FR-015 ; D01 à D05.

### Transverses

- [ ] T158 [P] Bloquée jusqu'à la commande cosign vérifiée par [SECU] : écrire S24, contrôle de la signature du contrôleur d'Envoy Gateway, dans `golden/saas-b2b/local/tests/static/s24-envoy-signature.sh`, en PR à part (ADR-005, condition 3) ; un échec rouvre l'ADR-005. Trace : US1, FR-008 ; S24.
- [ ] T159 [P] Écrire dans `docs/prd-mvp.md` l'écart d'US-009 du PRD : Trivy pour le SBOM et le scan à la place de Syft, confirmé par Lucas le 2026-11-23 (RS-22). Porteur : [PO]. Trace : US7, FR-020.
- [ ] T160 [P] Mesurer le redémarrage du nœud avec les données de Postgres (série `NODE_RESTART=1`, après BENCH-012 et BENCH-013) et mettre à jour `golden/saas-b2b/README.md` si la mesure le permet. Porteur : [BENCH]. Trace : US1, FR-017 ; aucune étape bloquée.

---

## Dependencies & Execution Order

### Phase Dependencies

- Phase 1 (étape 1) : aucune dépendance, prête.
- Phase 2 : sans tâche.
- Phase 3 : étapes 3, 4 et 5 après la phase 1 ; 6 après 5 ; 7 après 6 ; 8 après 7 ; seconde PR de 7 après 8 et T071 ; 19 après 3, 8 et l'ADR-015 ; 9 après 3, 4, 8 et 19 ; 11 après 9.
- Phase 4 (étape 2) : après la phase 1.
- Phase 5 (étape 13) : après la phase 1, à partir du 2026-11-24.
- Phase 6 : première PR de 18 après l'étape 7 et T103 ; seconde PR après l'étape 9.
- Phase 7 (étape 10) : après l'étape 9.
- Phase 8 : 14 après 9 et 13 ; 20 après 13, 14 et l'ADR-015.
- Phase 9 : 12 après 10, la seconde PR de 18 et T139 ; 15 après 12 et l'ADR-013 ; 16 après 12 et l'ADR-014.
- Phase 10 : 17 après 11, 14, 15, 16, 18, 19 et 20 ; T158 dès que [SECU] fournit la commande ; T159 libre ; T160 après BENCH-012 et BENCH-013.

### Étapes, dépendances et état au 2026-11-23

| Étape | Tâches | Dépend de | État | Débloquée par |
| --- | --- | --- | --- | --- |
| 1 Squelette | T001 à T014 | plan validé | prête | |
| 2 Conventions Git | T093 à T101 | 1 | prête après 1 | |
| 3 API | T015 à T026 | 1 | prête après 1 | |
| 4 Front | T027 à T032 | 1 | prête après 1 | |
| 5 Contrôles préalables | T033 à T038 | 1 | prête après 1 | |
| 6 Cluster et miroir | T039 à T051 | 5 | prête après 5 | |
| 7 Plate-forme, première PR | T052 à T061 | 6 | prête après 6 | |
| 8 Secrets et données | T062 à T070 | 7 | prête après 7 | |
| 7 Écouteur HTTPS, seconde PR | T071 à T074 | 8, RS-10 | bloquée | décision de [SECU] et [DEV] (T071) |
| 13 OpenTofu | T102 à T110 | 1 | prête le 2026-11-24 ; T110 bloquée | `google` 8.12.0 le 2026-11-24 ; décision d'[OPS] et [SECU] sur l'alerte budget (T110) |
| 18 Scan, première PR | T111 à T118 | 7, T103 | prête après 7 et T103 | |
| 19 Cache local | T075 à T081 | 3, 8, ADR-015 | bloquée | ADR-015, après BENCH-014 |
| 9 Lite de bout en bout | T082 à T089 | 3, 4, 8, 19 | bloquée | étape 19 |
| 11 README | T090 à T092 | 9 | bloquée | étape 9 |
| 18 Scan, seconde PR | T119 à T123 | 9, 18 première PR | bloquée | étape 9 |
| 10 Hors réseau lite | T124 à T128 | 9 | bloquée | étape 9 |
| 14 Manifests GCP | T129 à T135 | 9, 13 | bloquée | étapes 9 et 13 |
| 20 Memorystore | T136 à T138 | 13, 14, ADR-015 | bloquée | ADR-015 et étape 14 |
| 12 Flux | T139 à T146 | 10, 18 seconde PR | bloquée | étapes 10 et 18, décision d'[OPS] (T139) |
| 15 Keycloak | T147 à T149 | 12, ADR-013 | bloquée | étape 12 et ADR-013, après BENCH-012 |
| 16 Mailpit | T150 à T152 | 12, ADR-014 | bloquée | étape 12 et ADR-014, après BENCH-013 |
| 17 Démo | T153 à T157 | 11, 14, 15, 16, 18, 19, 20 | bloquée, en dernier | tout le reste |
| S24 | T158 | | bloquée | commande cosign vérifiée par [SECU] |

Toute la chaîne bloquée part de l'ADR-015 : l'étape 19 l'attend, l'étape 9 attend l'étape 19, et les étapes 10, 11, 12, 14, la seconde PR de 18, puis 15, 16 et 17 attendent l'étape 9 (décision de Lucas du 2026-11-23 : aucune image de cache provisoire). Les tâches de vérification d'une étape bloquée qui ne lisent qu'une documentation publiée peuvent avancer avant leur étape ; restent à part T075, T136, T147 et T150, qui lisent un ADR à venir, T082, qui demande un essai sur kind, et T139, qui attend une décision.

### Within Each Step

- Vérifications datées d'abord, puis tests en rouge, puis code, puis branchement en CI.
- Chaque PR finit avec ses contrôles au vert ; un contrôle porté par une étape plus tardive se signale dans « Écarts relevés ».
- Une PR touche une seule étape ; les tâches marquées « si l'étape N n'est pas fusionnée » règlent l'ordre entre les étapes 3 et 4.

### Parallel Opportunities

- Après l'étape 1 : les étapes 2, 3, 4, 5 et 13 avancent en même temps. L'étape 13 ne touche aucun fichier de `local/`, et peut avancer pendant que les étapes 6 à 8 occupent le cluster de la CI.
- La première PR de l'étape 18 avance en parallèle de l'étape 8, dès l'étape 7 fusionnée.
- Après l'étape 9 : les étapes 10, 11, 14 et la seconde PR de 18 avancent en même temps.
- Après l'étape 12 : les étapes 15 et 16 avancent en même temps.
- Dans une étape : les tâches [P], une fois ses vérifications faites.

---

## Parallel Example: étapes 3, 4 et 5 après l'étape 1

```text
# Vérifications, lecture seule :
Task: "T015 Vérifier Npgsql, framework de test .NET, ProblemDetails, NuGet"
Task: "T027 Vérifier Node.js, React, Vite, TypeScript, nginx non root"
Task: "T033 Vérifier la lecture de la mémoire déclarée par le moteur"

# Tests en rouge, fichiers distincts :
Task: "T017 U01 dans golden/saas-b2b/src/Api.Tests/"
Task: "T028 U02 dans golden/saas-b2b/src/front/"
Task: "T035 P03 dans golden/saas-b2b/local/tests/preflight/p03-memory.sh"
Task: "T036 P04 et P05 dans golden/saas-b2b/local/tests/preflight/"
```

## Parallel Example: étape 8

```text
Task: "T063 S03 dans golden/saas-b2b/policy/no_secret.rego"
Task: "T064 S04 dans golden/saas-b2b/local/tests/static/s04-taskfile.sh"
Task: "T065 S12 dans golden/saas-b2b/local/tests/static/s12-postgres.sh"
```

---

## Implementation Strategy

### MVP First

Le MVP de ce plan est le profil lite qui démarre : phases 1 et 3 (étapes 1, 3 à 9, 19 et 11). Il rend testables US1 et US2. US2 se vérifie dès l'étape 8, avant l'ADR-015 ; US1 attend l'étape 19. Arrêt et validation à la fin de la phase 3 : `task up` sur un poste propre, E01 à E09 au vert.

Le profil lite est livré quand les contrôles de chaque profil livré passent en lite : il faut aussi l'étape 10 (FR-016) et la seconde PR de l'étape 18 (FR-021), soit les étapes 1 à 11, 18 et 19.

### Incremental Delivery

1. Étape 1, puis en parallèle les étapes 2, 3, 4, 5 et 13 (à partir du 2026-11-24).
2. Étapes 6, 7, 8, et la première PR de 18 : tout ce qui avance sans l'ADR-015. US2, US3 (partie OpenTofu) et US4 sont alors testables.
3. À l'ADR-015 : étape 19, puis 9 (US1), puis 10, 11, 14, 20 et la seconde PR de 18 : profil lite livré, couche GCP complète, US5, US6 et US7 testables.
4. Étape 12, puis 15 et 16 après leurs ADR : profil standard.
5. Étape 17 : démo de la gate, mesurée.

---

## Écarts relevés entre spec, plan et tâches

Aucun ne demande de modifier spec.md ni plan.md avant de commencer. Chacun est réglé dans les tâches comme dit ci-dessous ; les points 1, 3, 4, 5, 10 et 11 méritent une ligne dans le plan à sa prochaine mise à jour.

1. Ordre des contrôles préalables : le plan (« Ce que fait `task up` », point 1) cite les versions avant le moteur joignable ; le contrat task-cli impose le moteur d'abord, « dans cet ordre », et la version de Docker Engine ne se lit qu'avec un moteur joignable. T037 suit le contrat.
2. L'étape 6 livre `task down` et `task mirror:purge`, mais E08 n'est placé qu'à l'étape 9, et la partie miroir de E03 qu'à l'étape 7. Pour que la PR porte ses tests (principe I), T045 écrit dès l'étape 6 la partie de E03 et de E08 qui vise ce qu'elle crée ; T056 et T084 les complètent.
3. L'écouteur HTTPS est rangé à l'étape 7, mais `gateway-tls` demande la tâche des Secrets de l'étape 8 et la décision de RS-10. Il passe dans une seconde PR de l'étape 7, après l'étape 8 (T071 à T074). Aucun contrôle de la matrice ne vérifie que l'écouteur HTTPS répond : T072 étend E03, E04 et E05.
4. Le cas limite de la spec « un registre public répond mal ou limite les tirages » et la ligne du contrat task-cli « premier démarrage sans réseau » n'ont aucun contrôle dans la matrice. T126 et T127 les couvrent ; le contrôle reste à numéroter dans le plan.
5. S10 est placé à l'étape 12, mais ses points sur le `RootSync` portent sur un objet écrit à l'étape 14. La partie Flux de S10 reste à l'étape 12 (T141), la partie `RootSync` passe à l'étape 14 (T131).
6. Trivy sert dès l'étape 13 (S15) alors que l'étape 18 le fige (S26). T103 le fige à l'étape 13, et la première PR de l'étape 18 en dépend.
7. S17 est placé aux étapes 2 et 13, qui peuvent passer l'une avant l'autre, alors que le workflow de CELIAN naît à l'étape 1. T006 écrit S17 dès l'étape 1 ; T094 et T105 l'étendent.
8. La première PR de l'étape 18 scanne Postgres mais ne dépend que de l'étape 7. L'inventaire étant calculé (S25), Postgres y entre avec l'étape 8 quel que soit l'ordre (note de l'étape 8).
9. Les étapes 3 et 4 portent toutes deux S01 sur leur Dockerfile et le job `unit`, et peuvent passer dans n'importe quel ordre : la première fusionnée crée la politique et le job (T019, T026, T031, T032).
10. Le test qui garde d'accord les ports de `local/kind/cluster.yaml` et ceux des tâches (plan, « Routage et adresses ») n'a pas d'identifiant ; T056 le range dans S05.
11. Le plan ne dit pas où tournent les tests unitaires alors que le poste n'a ni SDK .NET ni Node.js (RS-06) : les tâches les lancent dans l'image de construction (T025, T031). À confirmer par le DSI.
12. E08 ne vérifie ni le message de `task mirror:purge` avant d'agir (récit 6, scénario 3) ni le retrait du conteneur du miroir par `task app:down` (data-model) ; T045 et T084 les ajoutent.
13. Relevé à l'étape 5 : T038 nomme `up.yml`, mais la couche `local` n'a qu'un Taskfile depuis T009, `local/tasks/local.yml` ; les contrôles préalables y sont branchés.
14. Relevé à l'étape 5 : le profil standard est reconnu puis refusé jusqu'à l'étape 12. Sur un moteur qui déclare au moins 2560 Mio, ce Mac et les runners de CI compris, `task up` sans `PROFILE` s'arrête : les étapes 6 à 9 et le job `e2e-lite` passent `PROFILE=lite`.
15. Relevé à l'étape 5 : les seuils comparent la mémoire déclarée par le moteur à 2048 et 2560 Mio, alors que RS-08 parle d'une VM de 2,0 et 2,5 Gio. Ce que déclare une VM réglée à 2,0 Gio n'a pas été mesuré. T081 tranche, et change aussi les seuils écrits dans le README.
16. Relevé à l'étape 5 : Podman, que [OPS] n'a pas encore retenu (R-26), répond derrière `docker` avec sa propre version ; sous Linux, la règle des 28.0.0 de Docker Engine le refuserait. Rien n'est câblé pour lui.
17. Relevé à l'étape 5 : Renovate ne voit pas `KIND_VERSION` de `local/scripts/preflight.sh`. L'étape 6 lui donne un commentaire `# renovate:` et le range dans le groupe de kind et de son image de nœud.
18. Relevé à l'étape 5, repris après la relecture [SECU] de la PR #57 : `docker context inspect` et `docker info` sont bornés à 10 s (`DOCKER_TIMEOUT_SECONDS`, RS-08), et P02 le vérifie avec un faux moteur qui ne répond jamais. La sonde d'un port ne conclut « libre » que sur « Connection refused » ; tout autre résultat, un bash compilé sans `/dev/tcp` compris, est refusé comme indécidable. P04 joue la vraie sonde sur le port 1, fermé, et la remplace par un faux pour les ports pris ou indécidables. Un port réellement pris n'est vérifié qu'à la main (RS-08), puis par E03 sur kind.
19. Relevé à l'étape 6 : T049 à T051 nomment `down.yml`, `mirror.yml` et `test.yml`. Comme à l'écart 13, tout entre dans `local/tasks/local.yml` (tâches internes `down`, `mirror-purge` et `test-e2e`), et le Taskfile racine expose `task mirror:purge` et `task test:e2e`. `task up` finit en succès après le cluster et le miroir, comme E24 l'exige, et dit que la suite arrive aux étapes 7 à 9.
20. Relevé à l'étape 6 : le plan (« Ce que fait `task up` », point 3) et T049 demandent d'attendre la réponse du miroir. L'image publiée de zot n'a pas de sonde de santé ni de shell, le miroir ne publie aucun port et `docker exec` n'est pas employé : la réponse HTTP ne se demande pas depuis le poste (RS-13). `local/scripts/mirror.sh` attend l'état `running`, puis vérifie qu'il tient 2 s plus tard. Un tirage par le miroir en capacité `pull` seule a été constaté à la main sur le poste ; le premier contrôle automatique d'un tirage par le miroir vient avec les images d'Envoy Gateway à l'étape 7, puis E10 à l'étape 10.
21. Relevé à l'étape 6 : E03 relève aussi « ce qu'un pod joint du miroir » (ADR-011, condition 2). Cette partie demande une image de pod, et l'étape 6 n'en fait tourner aucune : elle passe à l'étape 7 avec T056, ou à l'étape 8 sur l'image de Postgres.
22. Relevé à l'étape 6 : E22 crée ses leurres par `docker container create` sur l'image de zot déjà tirée (`--pull never`), sur le réseau `none`, sans jamais les démarrer, et les retire à la fin. L'accord de Lucas du 2026-11-25 vise `docker run` pour le seul miroir : ces conteneurs jamais démarrés sont à confirmer par le DSI.
23. Relevé à l'étape 6 : en plus de la décision du DSI sur `KIND_EXPERIMENTAL_PROVIDER`, les contrôles préalables refusent `KIND_EXPERIMENTAL_DOCKER_NETWORK` posée à autre chose que `kind`, réseau du miroir (RS-08). Ajout d'[OPS], à confirmer par le DSI.
24. Relevé à l'étape 6 : S23 compte trois gestionnaires maison dans les deux `renovate.json` : les images des workflows ; Task, conftest et kind (`KIND_VERSION` de `local/scripts/lib/preflight-checks.sh`) ; les images de la couche `local` (image de nœud de `local/kind/cluster.yaml`, `MIRROR_IMAGE` de `local/tasks/local.yml`). `ENGINE_VERSION` de `preflight-checks.sh` devient `ENGINE_VERSION_FOUND`, pour que le contrôle des commentaires `# renovate:` ne le prenne pas pour une version suivie.
25. Relevé à l'étape 6 : T039 a été tranchée par [SECU] à la relecture de la PR #65, le 2026-11-25 : l'emplacement `$HOME/.kube/kind-saas-b2b`, proposé par [OPS] et câblé (RS-21), est validé. Un autre emplacement ne changerait que `local/scripts/lib/local-env.sh`, S19 et E19.
26. Relevé à l'étape 6 : le job `e2e-lite` tourne dans le workflow de CELIAN seulement. Les workflows du projet généré (`golden/saas-b2b/.github/workflows/`) ne lancent pas encore `task test:e2e`, faute d'installation vérifiée de kind sans le catalogue de CELIAN : à reprendre avec le README de l'étape 11, qui décrit cette installation (S18).
27. Relevé à l'étape 6 : les leurres de E22 (conteneurs créés par `docker container create`, jamais démarrés, sur le réseau `none`, sur l'image de zot déjà tirée) sont confirmés par le DSI (écart 22).
28. Relevé à l'étape 6, après la relecture de [SECU] : `task test:e2e` ne retire jamais ce qu'il n'a pas créé. `local/tests/e2e/run.sh` refuse de démarrer, en nommant ce qui existe, si le cluster `saas-b2b`, le conteneur `saas-b2b-mirror` ou le volume `saas-b2b-mirror` sont déjà là (`local/tests/e2e/lib/guard.sh`, prouvé par P07) ; la CI, au runner neuf, n'est pas touchée. `mirror.sh check` passe avant `cluster.sh up` : un conteneur ou un volume étranger arrête `task up` avant la création du cluster ; seul le réseau `kind`, que kind crée, se contrôle après. S13 verrouille `--cap-drop ALL`, `no-new-privileges` et `--read-only` du miroir, refuse `--user`, `-u`, `--privileged` et `--cap-add`, et E03 relit `CapDrop`, `ReadonlyRootfs`, `SecurityOpt` et `Privileged` du conteneur lancé. S04 et S19 voient `kind delete clusters`, et S19 refuse toute option globale de `docker`.
29. À faire à l'étape 10, avec E23 : essayer la politique anonyme en lecture seule de zot, `"accessControl": {"repositories": {"**": {"anonymousPolicy": ["read"]}}}`. Sans authentification, elle refuserait les écritures et les suppressions depuis le réseau `kind` (zot 2.1.23, `pkg/api/routes.go`, lignes 127 à 144 : le contrôle d'accès « anonymous policy only » s'active dès que `accessControl` est présent ; lu par [OPS] le 2026-11-25). Vérifier que la synchronisation à la demande remplit toujours le cache. `local/policy/mirror_config.rego` devra alors accepter cette clé : `zot_top_keys` (ligne 78) ne laisse aujourd'hui que `distSpecVersion`, `storage`, `http`, `log` et `extensions`.
30. Relevé à l'étape 3 : le magasin Npgsql, le script de schéma et la sonde de la base ne touchent aucun vrai Postgres avant l'étape 9 (E01, E02, E12). U01 travaille avec des doubles.
31. Relevé à l'étape 3 : `/api/readyz` répond 503, cache en erreur, jusqu'à l'étape 19, faute de client de cache concret avant elle. Voulu.
32. Relevé à l'étape 3 : l'API répond 415 à un corps qui n'est pas du JSON et 413 au-delà de 16 Kio, deux codes absents du contrat http-api. Le DSI les retient et complète le contrat (2026-11-24).
33. Relevé à l'étape 3 : la version de Docker sur `ubuntu-latest` reste à vérifier (T040) ; la sortie `--output type=cacheonly` du job `unit` n'a été essayée qu'en local (Docker 29.8.2, BuildKit 0.33.1), la CI de la PR la vérifie.
34. Relevé à l'étape 7 : la partie de E03 « ce qu'un pod joint du miroir » (écart 21) demande une image qui porte un shell, et ni le contrôleur ni le proxy d'Envoy Gateway n'en ont. Elle passe à l'étape 8, sur l'image de Postgres. Le premier contrôle automatique d'un tirage par le miroir (écart 20) entre, lui, dans E03 : le journal de zot montre un GET en 200 du manifeste du proxy, avec `ns=docker.io`.
35. Relevé à l'étape 7 : `contracts/layers.md` (« Composition Kustomize ») met le `gatewayClassName` d'Envoy Gateway dans le composant de cible `local`. La Gateway commune demande la classe `saas-b2b`, et la couche `local` déclare une GatewayClass de ce nom (`local/platform/gateway-class.yaml`) : le composant `local` n'a rien à corriger, seul le composant `gcp` remplacera la classe par celle de GKE (étape 14). S07 garde `gatewayClassName` comme seul champ qui peut différer. Ligne à reprendre dans le contrat.
36. Relevé à l'étape 7 : tant que `task up` n'applique pas la couche de l'application (étape 8, T070), E03 applique lui-même `k8s/overlays/local`, attend la Gateway `Programmed`, interroge `/` et `/api/healthz` sur le port HTTP, puis retire ce qu'il a appliqué. L'étape 8 retire cette application de E03. Les Services n'existant qu'à l'étape 9, la gateway répond 500 sur les deux routes, comme le veut Gateway API (RS-02) ; E03 refuse un 404, la réponse d'Envoy quand aucune route ne correspond.
37. Relevé à l'étape 7 : l'EnvoyProxy ne fixe que le `nodePort` du port 80. Le correctif fusionne sur la clé `port` des ports du Service, et un port 443 que le Service n'a pas y entrerait sans nom (RS-02). La seconde PR ajoute le port 443 à l'EnvoyProxy avec l'écouteur HTTPS (T074) ; les deux ports de l'hôte sont publiés dès l'étape 7.
38. Relevé à l'étape 7 : au second `task up`, les ports de la gateway sont tenus par le nœud du cluster, et la sonde de P04 les dirait pris. Les contrôles préalables lisent donc les nœuds du cluster du projet (`docker container ls` et `docker container inspect`, en lecture seule) : avec un nœud, chaque port doit y être publié en 127.0.0.1, sinon `task up` demande `task down` ; sans nœud, la sonde décide. P04 compte cinq cas de plus (RS-20).
39. Relevé à l'étape 7 : le rendu des CRD d'Envoy Gateway pèse 2,86 Mo et contient un tiret cadratin dans la description d'une CRD ; `standard-install.yaml` a deux lignes qui finissent par une espace. T057 sort `local/vendor/` des hooks qui réécrivent les fichiers, de `check-added-large-files` et de `no-em-dash`, à la racine de CELIAN et dans le golden repo. La règle de `CLAUDE.md` sur le tiret cadratin vise ce que le projet écrit ; ce sont ici des octets de tiers, que `SHA256SUMS` garde tels quels. À confirmer par le DSI. Chaque montée d'Envoy Gateway ajoutera environ 3 Mo à l'historique.
40. Relevé à l'étape 7 : S06 rend la couche commune avec le Kustomize de kubectl. Le job `static` installe donc kubectl par `scripts/ci/install-kind-kubectl.sh`, et `KUBECTL_VERSION` et `KUBECTL_SHA256` montent au niveau du workflow, partagés avec `e2e-lite`. Le workflow `checks.yml` du projet généré lance `task check` avec le kubectl de l'image du runner, sans somme vérifiée : à reprendre avec l'écart 26, à l'étape 11.
41. Relevé à l'étape 7 : Renovate suit Envoy Gateway par trois variables de `local/tasks/local.yml`, `ENVOY_GATEWAY_IMAGE`, `ENVOY_GATEWAY_HELM_IMAGE` et `ENVOY_GATEWAY_CRDS_HELM_IMAGE`, les deux dernières pour les artefacts OCI des charts, que Renovate cherche par la source `docker` (RS-02). Elles passent par le gestionnaire existant des images de la couche `local` : S23 ne change pas, seules les descriptions des deux `renovate.json` le disent. Aucun Renovate n'a tourné sur ces lignes. `platform.sh` et S22 refusent un rendu d'une autre release que celle de ces variables.
42. Relevé à l'étape 7 : la configuration rendue du contrôleur nomme l'image `ratelimit` par tag. La limitation de débit n'est pas activée, et S22 refuse son activation sans image par condensat (ADR-005, condition 1). Aucun réglage n'est ajouté aux deux de l'ADR-005.
43. Relevé à la relecture [SECU] de l'étape 7 : le ClusterRole du contrôleur lit les Secrets de tout le cluster (`get`, `list`, `watch`) et peut `patch` et `update` les pods (`gateway-helm.yaml`, lignes 108 à 116 et 190 à 200). À réduire avant que l'étape 8 dépose les identifiants Postgres dans un namespace : `config.envoyGateway.provider.kubernetes.watch` avec `type: Namespaces` et `namespaces` (champs `watch`, `type` et `namespaces` de `KubernetesWatchMode`, `api/v1alpha1/envoygateway_types.go` de la v1.10.0, lu par [OPS] le 2026-11-25). Le réglage restreint ce que le contrôleur réconcilie ; le ClusterRole rendu ne change pas de lui-même, et seule la lecture du rendu après le réglage dira ce qui reste. Il s'ajoute aux deux réglages de l'ADR-005 par une PR à part, que le DSI ouvre ; S22 refuse d'ici là tout verbe `*` et toute liaison à `cluster-admin`.
44. Relevé à la relecture [SECU] de l'étape 7 : S22 compare le rendu vendu à des références, mais rien ne le refait. Avant la première PR de montée d'Envoy Gateway, un job de CI refait `helm template` depuis l'artefact OCI désigné par condensat (`ENVOY_GATEWAY_HELM_IMAGE` et `ENVOY_GATEWAY_CRDS_HELM_IMAGE`) avec les valeurs de l'ADR-005, et compare au rendu de `local/vendor/` octet pour octet. Sans ce job, un rendu édité à la main et un `SHA256SUMS` refait passent S02 et S22. [X] Traité le 2026-11-25 : job `envoy-render` de `.github/workflows/golden-saas-b2b.yml`, qui lance `scripts/ci/check-envoy-gateway-render.sh` avec Helm v4.3.2 figé par version et somme (`scripts/ci/install-helm.sh`) et les commandes de RS-02, et compare octet pour octet. Il n'est pas encore un contrôle requis de `.github/rulesets/main.json` : le DSI décide après un passage sur `main`. Essai local avec Helm v4.3.2 : les deux rendus sont identiques aux fichiers de `local/vendor/envoy-gateway/`.
45. Relevé à la relecture [SECU] de l'étape 7 : les HTTPRoute de la couche commune ne fixent pas de `hostnames`, et la gateway répond à toute valeur de `Host` sur 127.0.0.1. Une page web quelconque peut, par rebinding DNS, atteindre l'application locale. À l'étape 9, fixer les `hostnames` des HTTPRoute, avec la valeur que le README donne à l'utilisateur.
46. Relevé à l'étape 4 : U02 est câblé en CI avant le code, comme U01 à l'étape 3, pour que le commit rouge poussé montre U02 en échec dans le job `unit` (T032 placé avant T030 et T031 ; décision du DSI du 2026-11-24).
47. Relevé à l'étape 4 : le démarrage de nginx sous le profil `restricted` n'est pas essayé, faute de `docker run` sur le poste ; seul `nginx -t` sous l'UID 101 l'est. Le vrai démarrage se vérifie par E12 à l'étape 9.
48. Relevé à l'étape 4 : les binaires amd64 musl de la construction du front (Rolldown, lightningcss, TypeScript 7) ne sont vérifiés que par le job `unit` de la CI ; le poste n'a construit qu'en arm64.
49. Relevé à l'étape 4, pour [FINOPS] (R-04) : le premier `task up` télécharge en plus environ 28,5 Mio de paquets npm, l'image Node (63,0 Mo en amd64) et l'image nginx (5,7 Mo). L'estimation du plan ne comptait que nginx, d'après l'essai de BENCH-005.
50. Relevé à l'étape 4 : les textes de l'écran sont en anglais, comme les messages d'erreur de l'API et le code (décision du DSI du 2026-11-24). Leur traduction sort du MVP.
51. Relevé par la relecture [SECU] de l'étape 4 : aucune tâche ne pose la redirection de HTTP vers HTTPS sur `gcp`, HSTS sur l'écouteur HTTPS, ni `nosniff` sur `/api`, que l'API ne pose pas. Sans eux, sur GCP, un attaquant placé sur le réseau réécrit la page servie en clair et lit les notes. Une tâche de la seconde PR de l'étape 7, portée par [OPS] et [SECU], les pose à la gateway, en remplacement (`set`) pour ne pas doubler les en-têtes de nginx ; la syntaxe Gateway API se vérifie et se date à ce moment-là (décision du DSI du 2026-11-24).
52. Relevé par la relecture [SECU] de l'étape 4, à traiter dans une PR à part : S20 côté front vérifie le contrat sans protéger, la vraie barrière est la CSP. S20 rate la navigation (`location.`, `window.open`), WebRTC, `WebTransport`, une adresse `"//hôte"`, les fichiers autres que `.ts` et `.tsx`, et une devDependency importée dans `src/`. Fermé par la PR qui suit l'étape 4 : S20 refuse la navigation (`location`, `window.open`, `http-equiv`), WebRTC, `WebTransport`, une adresse `//hôte`, `fetch` hors appel direct (alias, `globalThis.fetch`, `window["fetch"]`) et un nom de canal passé en chaîne ; il retire les commentaires sans sauter la ligne qui porte du code après eux ; il lit `.js`, `.jsx`, `.mjs`, `.cjs`, `.css` et `.html` ; la politique refuse tout import nu hors de `react`, `react/jsx-runtime` et `react-dom/client`. Reste ouvert, faute de moyen simple sans faux positifs : un nom assemblé (`"fe" + "tch"`), `eval` et `Function`, une expression régulière qui contient un guillemet et masque la fin de sa ligne, une adresse calculée dans `src/api.ts`, les fichiers `.svg` et `.json`, les fichiers `*.test.*` de `src/` (non lus). La CSP de `nginx.conf` répond de ces cas.
53. Relevé par la relecture [SECU] de la PR #61 : Renovate lit un `.npmrc` et un `nuget.config` du dépôt, et un registre tiers y détournerait ses recherches vers un registre qui date ses versions comme il veut. Le contrôle S29 (`tests/static/s29-package-registries.sh`), ajouté à la matrice du plan sans tâche propre, refuse dans ces fichiers tout registre autre que `registry.npmjs.org` et `api.nuget.org`, et tout identifiant (décision du DSI du 2026-11-25).

## Notes

- [P] : fichiers distincts, aucune dépendance sur une tâche non finie de la même étape.
- Les tâches de vérification écrivent chacune dans sa seule section de research.md ; deux PR qui touchent des sections distinctes ne se chevauchent pas.
- Un contrôle échoue en nommant la condition ou l'exigence qu'il porte (FR-012).
- Contrôles requis du ruleset : les tâches ajoutent `static`, `unit`, `e2e-lite`, le job du scan et `e2e-standard`, que RS-17 nomme. `offline-lite`, `offline-standard`, `gcp-on-kind` et `export` restent hors des contrôles requis jusqu'à décision du DSI.
- Après chaque étape : mettre à jour `ROADMAP.md` (DSI).
