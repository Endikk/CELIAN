# Implementation Plan: golden repo SaaS B2B

**Branch**: `docs/plan-golden-repo` (fonctionnalité `001-golden-repo-saas-b2b`) | **Date**: 2026-11-21 | **Spec**: [spec.md](spec.md)

**Input**: spécification `specs/001-golden-repo-saas-b2b/spec.md` (19 exigences, 9 critères de succès, 6 récits) et sa liste de contrôle [checklists/requirements.md](checklists/requirements.md).

**Auteur** : [DEV], à la demande du DSI. Relecture du DSI puis de Lucas avant `/speckit-tasks`.

## Summary

Le golden repo est un projet SaaS B2B complet, construit à la main dans `golden/saas-b2b/`, que le blueprint Copier de la phase 3 reproduira. Il contient une API .NET réduite à un contrôle de santé et à un exemple de notes qui écrit en base et relit par le cache, un front React qui l'affiche, une couche commune et deux couches de cible.

Sur le PC, `task up` vérifie le poste, crée un cluster kind, lance le miroir zot, installe Envoy Gateway, crée les Secrets par un tube, démarre Postgres sans opérateur et Valkey, puis construit, charge et applique l'application, sans outil de boucle. Sur GCP, une racine OpenTofu écrite à la main décrit GKE Autopilot, Cloud SQL, Memorystore, Secret Manager et Config Sync. La CI la valide, contrôle ses politiques et la scanne, sans plan ni apply.

Les choix de technos viennent des ADR-004 à ADR-012, que ce plan ne rouvre pas. Il fixe ce que les ADR laissaient au golden repo : l'arborescence et la carte des couches, le routage, l'exemple applicatif, les noms des Secrets, l'ordre de `task up`, le découpage en PR et la matrice de validation. Le profil lite se livre d'abord. Le profil standard (Flux, puis Keycloak et Mailpit après leurs ADR) et la couche GCP viennent ensuite.

Documents de conception : [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md).

## Technical Context

Aucune version n'est écrite de mémoire : chacune renvoie à un ADR, à un benchmark, au catalogue ou à un script de benchmark versionné. Une version sans source est marquée « à vérifier » et renvoie au point de [research.md](research.md) qui la lèvera.

**Language/Version** :

| Partie | Version | Source |
| --- | --- | --- |
| API | .NET 10 (`net10.0`) ; images `mcr.microsoft.com/dotnet/sdk:10.0.404` et `aspnet:10.0.15`, par condensat | BENCH-005, S41 lue le 2026-11-19 ; `tests/bench/bench-005/stack/api/Dockerfile` |
| Front | React, TypeScript, Vite ; Node.js pour la construction | à vérifier (research RS-05) |
| Service du front | `nginx:1.30.7-alpine` par condensat ; variante non root à vérifier pour le profil `restricted` | BENCH-005, S38 ; `tests/bench/bench-005/stack/front/Dockerfile` ; research RS-05 |
| Scripts des tâches | bash, compatible avec le bash 3.2 de macOS, sans heredoc | ADR-007, condition 1 |
| Couche GCP | OpenTofu 1.11 au moins (mesures en 1.13.9) ; provider `hashicorp/google` 8.12.0, utilisable à partir du 2026-11-24 ; provider `random` à vérifier | ADR-008, conditions 3 et 7, règle de version |

**Primary Dependencies** :

| Cible | Brique | Version et référence | Source |
| --- | --- | --- | --- |
| `local` | kind | 0.33.0, binaire vérifié contre le SHA-256 du catalogue (quatre plateformes relevées) | ADR-004 ; `catalog/kubernetes-cluster.yaml` |
| `local` | Image de nœud | `kindest/node:v1.36.4` par condensat, mineure 1.36 | ADR-004, règle de version |
| `local` | kubectl | 1.35 à 1.37 | ADR-006, condition 5 |
| `local` | Task | à vérifier ; licence MIT, gouvernance non relevée | ADR-006, question 5 |
| `local` | Moteur de conteneurs | Docker Engine 28.0.0 au moins sous Linux ; moteur libre cité d'abord (R-26) | ADR-011, condition 3 ; ADR-004, condition 8 |
| `local` | CRD Gateway API | v1.7.0, `standard-install.yaml`, SHA-256 dans l'ADR-005 | ADR-005 |
| `local` | Envoy Gateway | 1.10.0, charts et images par SHA-256 et condensat | ADR-005, tableau « Versions et condensats » |
| `local` | Miroir | zot 2.1.23 par condensat | ADR-011, condition 8 |
| `local` | Base | `postgres:18.7-trixie` par condensat, sans opérateur | ADR-012 |
| `local` | Cache | `valkey/valkey:9.1.4-alpine` par condensat, image de l'essai ; aucun ADR ne fixe encore le moteur ni sa forme | `tests/bench/bench-005-orchestration.sh`, ligne 108 ; research RS-11 |
| `local` | GitOps (standard) | Flux 2.10.0, `install.yaml` par SHA-256, quatre contrôleurs par condensat | ADR-010 ; `tests/bench/bench-009-gitops.sh`, lignes 72 à 93 |
| `local` | Identité et mails (standard) | Keycloak, Mailpit : aucune image ni version tant que les ADR-013 et ADR-014 manquent | décision de Lucas du 2026-11-20 |
| `gcp` | Cluster | GKE Autopilot, canal Regular de référence | ADR-008 ; ADR-004 |
| `gcp` | Base | Cloud SQL for PostgreSQL, majeure 18 | ADR-008 ; ADR-012, condition 5 |
| `gcp` | Cache | Memorystore, moteur en attente (Redis mesuré par BENCH-008, Valkey préféré par l'illustration de l'ADR-009) | ADR-008, portée ; research RS-11 |
| `gcp` | Secrets | Secret Manager, synchronisé par GKE (`SecretProviderClass`, `SecretSync`) | ADR-007 |
| `gcp` | GitOps | Config Sync 1.25.2, un `RootSync` | ADR-010 |
| `gcp` | Gateway | Contrôleur Gateway de GKE, classe à fixer par [OPS] | ADR-005 |

**Storage** : PostgreSQL 18, base `app` (StatefulSet d'une réplique sur `local`, Cloud SQL sur `gcp`) ; cache sans persistance sur `local` ; volume nommé du moteur pour le miroir, hors de l'arborescence du projet.

**Testing** : tests unitaires .NET et du front (frameworks à vérifier, research RS-18) ; scripts bash sur kind, passés à shellcheck ; politiques Rego exécutées par conftest (version à vérifier) ; validation de schéma par kubeconform, nommé par US-007, outil à confirmer avec [QA] ; `tofu validate` ; Trivy (0.76.2 dans BENCH-008, version de la CI à fixer).

**Target Platform** : postes macOS et Linux (Q5), arm64 et amd64 ; CI sur runner GitHub `ubuntu-latest` amd64, dans le dépôt de CELIAN ; GKE Autopilot pour le code GCP, validé et jamais déployé en phase 2.

**Project Type** : application web (API et front) avec son infrastructure pour deux cibles, construite comme dépôt de référence d'un générateur.

**Performance Goals** :

- démarrage à chaud sous 90 s (SC-003). Repères mesurés sur la stack d'essai : `task up` à chaud en 41,5 s (ADR-006), plate-forme à chaud en 44,6 s (ADR-005), recréation hors réseau en 34,7 s (ADR-011), Postgres prêt en 8,9 s (ADR-012) ;
- premier démarrage du profil standard mesuré et rapporté au budget de 900 s, au débit visé que fixera [FINOPS] (SC-002). Estimation hors Keycloak et Mailpit : 1 521,9 Mo en amd64, soit 135,3 % du budget à 10 Mbit/s et un débit minimal de 13,5 Mbit/s (R-04, ADR-012). Profil lite : environ 1 263,8 Mo, calcul de ce plan (standard moins Flux réduit, 258,1 Mo), jamais mesuré ;
- rechargement : API en 6,6 s et front en 5,1 s sur la stack d'essai (ADR-006), à remesurer avec un vrai build Vite.

**Constraints** : rien n'écoute hors de 127.0.0.1 ; secrets aléatoires d'au moins 32 caractères, jamais dans un fichier, une variable affichée ni un argument ; aucune image ni dépendance par tag ; profil lite sur un portable de 8 Gio (estimation de [FINOPS] : VM du moteur de 2,0 Gio, portable de 6,0 Gio, plancher de 1 186,6 Mio ; partie connue du standard : 2,5 et 6,5 Gio, ADR-012, ordres de grandeur) ; aucune commande vers un cluster cloud (FR-019) ; ni Helm, ni Tilt, ni Docker Compose dans les prérequis de l'utilisateur (ADR-006).

**Scale/Scope** : un poste, un environnement local, un environnement GCP décrit et jamais créé (Q6) ; code applicatif limité au contrôle de santé, à l'exemple et au front (Q7, FR-009).

Aucun marqueur NEEDS CLARIFICATION ne reste : chaque inconnue est soit tranchée dans [research.md](research.md), soit écrite comme un point à vérifier, avec son porteur et l'étape qu'il bloque. Aucune ne bloque le plan lui-même.

## Constitution Check

*GATE : avant la phase 0, puis après la conception de la phase 1.* Constitution 1.2.0.

| Principe | Avant conception | Après conception | Où c'est tenu |
| --- | --- | --- | --- |
| I. Rien sans test automatique | Passe | Passe | Chaque exigence, chaque critère de succès et chaque condition d'ADR vérifiable sans cloud a son contrôle (section « Matrice de validation »). Les essais sur GKE (ADR-007, condition 3 ; ADR-010, condition 7) attendent la GATE 2 : la combinaison `gcp` ne sera pas proposée avant. Le golden repo n'est proposé à personne |
| II. Spec abstraite, catalogue concret | Passe | Passe | Un dossier par couche (carte des couches) ; la couche commune ne nomme aucun outil ni fournisseur, contrôlée par S06 et S07 |
| III. Managé sur le cloud, open source ailleurs | Passe | Passe, une réserve | `local` : kind, Envoy Gateway, zot, Postgres, Valkey, Flux. `gcp` : GKE Autopilot, Cloud SQL, Memorystore, Secret Manager, Config Sync, contrôleur Gateway de GKE. Réserve : le moteur de Memorystore reste à décider (research RS-11) |
| IV. Catalogue traçable | Passe | Passe | Entrées `kubernetes-cluster`, `gateway`, `secrets` et `gitops` présentes. `database` (ADR-012), l'attribut du miroir (ADR-011) et le cache s'écrivent en phase 3. Le golden repo n'est pas un blueprint, comme le notent l'ADR-011 et l'ADR-012 ; le blueprint ne s'en servira qu'une fois les entrées complètes |
| V. Gouvernance ouverte d'abord | Passe | Passe | Choix des ADR. La gouvernance de Task reste à relever (ADR-006, question 5) ; zot est au niveau Sandbox de la CNCF (ADR-011) |
| VI. Récent mais éprouvé | Passe | Passe | Délai de 7 jours : `google` 8.12.0 utilisable le 2026-11-24, Flux 2.10.1 le 2026-11-27 ; les autres versions retenues le passent déjà. Les versions du front se lisent avec leur date avant usage (R-05) |
| VII. Une commande pour démarrer | Passe | Passe | `task up` seul, prérequis listés au README (S18) ; contrats dans [contracts/task-cli.md](contracts/task-cli.md) |
| VIII. Aucun fait de mémoire | Passe | Passe | Versions sourcées dans le contexte technique ; tout le reste est marqué à vérifier dans [research.md](research.md), y compris les syntaxes d'outils tiers, que les contrats évitent en passant par des tâches |
| IX. Aucun secret dans le dépôt | Passe | Passe | Secrets nés par un tube (ADR-007, condition 1), aucun objet `Secret` versionné (S03), kubeconfig hors du dépôt (E19), miroir sans identifiant (S13), gitleaks en local et sur l'historique |
| X. Aucune dépense cloud sans accord | Passe | Passe | Ni plan, ni apply, ni destroy en phase 2 ; CI sans identifiant cloud (S17) ; aucun contexte GKE sur le poste (FR-019, S19, E24) |

Verdict : aucune violation, rien à justifier dans « Complexity Tracking ».

## Project Structure

### Documentation (this feature)

```text
specs/001-golden-repo-saas-b2b/
├── spec.md              # spécification (non modifiée par ce plan)
├── checklists/
│   └── requirements.md
├── plan.md              # ce fichier
├── research.md          # phase 0 : décisions et points à vérifier
├── data-model.md        # phase 1 : entités, états, valeurs partagées
├── quickstart.md        # phase 1 : scénarios de validation
├── contracts/           # phase 1
│   ├── http-api.md      # API de l'exemple
│   ├── task-cli.md      # commandes du Taskfile
│   ├── secrets.md       # noms et clés des Secrets, par cible
│   └── layers.md        # couches, composition, parité, routage
└── tasks.md             # phase 2 : /speckit-tasks, pas encore écrit
```

### Source Code (repository root)

Le golden repo vit dans `golden/saas-b2b/` du dépôt de CELIAN. Règle de structure : une couche de cible tient dans un seul dossier, `local/` ou `gcp/`, et tout ce qui est hors de ces deux dossiers appartient à la couche commune. Copier pourra ainsi rendre chaque couche par un dossier conditionnel en phase 3.

```text
golden/saas-b2b/
├── README.md                     commune : prérequis, démarrage, écarts PC et cloud
├── Taskfile.yml                  commune : tâches publiques, qui délèguent à local/ et gcp/
├── platform.yaml                 commune : valeurs partagées (mineure Kubernetes, majeure Postgres)
├── .github/                      commune : CI du projet généré, CODEOWNERS, modèle de PR
├── .pre-commit-config.yaml       commune
├── .commitlintrc.yaml            commune
├── renovate.json                 commune
├── release-please-config.json    commune
├── .release-please-manifest.json commune
├── .gitignore, .editorconfig     commune
├── src/
│   ├── Api/                      commune : API .NET (santé, notes), Dockerfile
│   ├── Api.Tests/                commune : tests unitaires de l'API
│   └── front/                    commune : React et TypeScript (Vite), tests, Dockerfile
├── k8s/
│   ├── base/                     commune : Deployments, Services, Gateway, HTTPRoute, namespace
│   └── overlays/
│       ├── local/                commune : overlay neutre de l'environnement local
│       ├── staging/              commune : prêt, non déployé (Q6)
│       └── prod/                 commune : environnement déployé sur GCP
├── policy/                       commune : Rego de neutralité, de condensats, d'absence de Secret
├── tests/                        commune : tests statiques sans cluster, parité des rendus
├── local/                        couche local
│   ├── tasks/                    Taskfiles inclus : up, down, app, reload, mirror, secrets, check
│   ├── scripts/                  scripts bash appelés par les tâches
│   ├── kind/cluster.yaml         configuration du cluster
│   ├── mirror/                   liste des registres, configuration zot, certs.d dérivés
│   ├── vendor/                   manifests tiers et SHA256SUMS : CRD Gateway API, Envoy Gateway rendu, Flux
│   ├── platform/                 EnvoyProxy, GatewayClass
│   ├── data/                     Postgres (StatefulSet, Service, script d'init), Valkey
│   ├── gitops/                   objets de liaison de Flux (profil standard)
│   ├── identity/                 Keycloak, après l'ADR-013 (profil standard)
│   ├── mail/                     Mailpit, après l'ADR-014 (profil standard)
│   ├── k8s/                      compositions d'entrée : lite/, standard/, composant de cible
│   ├── policy/                   Rego propres à la couche
│   └── tests/                    contrôles préalables simulés, tests sur kind, test hors réseau
└── gcp/                          couche gcp
    ├── tofu/                     racine OpenTofu et .terraform.lock.hcl
    ├── k8s/                      composant de cible et composition prod/
    ├── policy/                   Rego sur le HCL et les manifests gcp
    ├── tasks/                    gcp:validate, gcp:policy, gcp:scan
    └── tests/                    Config Sync libre sur kind (x64)
```

Côté CELIAN, hors du golden repo : un workflow racine `.github/workflows/golden-saas-b2b.yml` lance les tâches du golden repo en CI (research RS-17). Les workflows de `golden/saas-b2b/.github/` décrivent la CI du futur projet généré ; GitHub ne les lance pas depuis un sous-dossier (fait à vérifier, research RS-17), d'où le contrôle X01, qui les exerce dans une copie autonome.

**Structure Decision** : une application web en deux projets (`src/Api`, `src/front`) dans une seule arborescence de projet généré, découpée en trois couches par dossiers. Le détail de la composition Kustomize, des points d'injection de la couche de cible et de la règle de parité est dans [contracts/layers.md](contracts/layers.md).

## Conception

### Ce que fait `task up`

Ordre de l'ADR-006, complété par l'ADR-011 et l'ADR-012. Le contrat complet, entrées, sorties et cas d'échec, est dans [contracts/task-cli.md](contracts/task-cli.md).

1. Contrôles préalables, avant toute création : version exacte de kind, mineure de kubectl, Docker Engine sous Linux, moteur joignable, mémoire déclarée par le moteur qui fixe le profil, ports de l'hôte libres.
2. Cluster kind créé depuis `local/kind/cluster.yaml`, ou réutilisé s'il existe. Kubeconfig du projet écrit hors du dépôt ; chaque commande vise ce fichier et le contexte du cluster local (FR-019).
3. Miroir zot : retrait contrôlé d'un ancien conteneur du projet, puis lancement sur le réseau `kind`, sans port publié, configuration montée en lecture seule, volume du projet ; attente de sa réponse.
4. Plate-forme de base : SHA-256 de chaque fichier de `local/vendor/` vérifié, puis CRD Gateway API, Envoy Gateway, EnvoyProxy et GatewayClass. En profil standard, Flux.
5. Construction de l'API et du front sous l'hôte réservé `saas-b2b.invalid`, étiquette neuve, chargement par `kind load docker-image`.
6. Namespace de l'application (profil `restricted`), puis création des Secrets absents par un tube. Volume de la base présent sans ses Secrets : arrêt avec un message (ADR-012, condition 3).
7. Application de `local/k8s/<profil>` par `kubectl apply -k`.
8. Attente de « prêt » : `SELECT 1` authentifié par le Service de la base, contrôle de santé de l'API et page d'accueil du front, par la gateway.
9. Affichage des adresses, de la durée de chaque étape et du total (FR-015), et de la taille du volume du miroir.

`task reload` réutilise les étapes 5 et 7, définies une seule fois dans le Taskfile (ADR-006, condition 6). `task down`, `task app:down` et `task mirror:purge` suivent l'ADR-011.

### Routage et adresses

Une seule Gateway, deux écouteurs HTTP et HTTPS (ADR-005), dans le namespace de l'application. Deux HTTPRoute : le préfixe `/api` vers l'API, `/` vers le front. Le front et l'API partagent donc une origine : pas de CORS, et le front appelle des chemins relatifs. L'API sert elle-même ses routes sous `/api`, sans réécriture de chemin, pour n'employer que des champs du cœur de Gateway API (ADR-005, condition 5). Les deux ports de l'hôte sont publiés en `listenAddress: "127.0.0.1"` et fixés à l'étape 7 ; leurs valeurs vivent dans `local/kind/cluster.yaml` et dans les tâches, qu'un test garde d'accord. Le certificat de l'écouteur HTTPS en local reste à trancher (research RS-10).

### Exemple applicatif

Une ressource « note » : `POST /api/notes` écrit en base, `GET /api/notes/{id}` relit par le cache (lecture paresseuse, provenance dans la réponse), `GET /api/notes` liste les plus récentes depuis la base. Deux routes de santé : `/api/healthz` (processus vivant) et `/api/readyz` (base et cache joignables). Accès aux données par Npgsql avec requêtes paramétrées, sans ORM ; schéma créé au démarrage par un script SQL idempotent, sous le rôle de l'application (research RS-03 et RS-04). Détail : [contracts/http-api.md](contracts/http-api.md) et [data-model.md](data-model.md).

### Profils

`task up` lit la mémoire que déclare le moteur (ADR-004, condition 6). Au-dessus du seuil du standard, il prend le standard ; entre les deux seuils, le lite, et il le dit ; sous le seuil du lite, il refuse en donnant la mémoire qui manque. La variable `PROFILE` force un profil, sous les mêmes contrôles. Seuils de départ : VM de 2,0 Gio pour le lite et 2,5 Gio pour le standard hors Keycloak et Mailpit (ADR-011, ADR-012), recalculés sur la première mesure du golden repo et à l'entrée de chaque couche du standard. Jusqu'à l'étape 12, le standard est reconnu et refusé par un message clair.

### Secrets

Quatre Secrets en profil lite : `db-auth`, commun aux deux cibles (ADR-012) ; `cache-auth`, commun, dont le producteur sur `gcp` attend le moteur du cache ; `db-superuser`, propre à `local` ; `gateway-tls`, dont la fabrication locale reste à trancher. Chaque mot de passe naît de `/dev/urandom` ; chaque Secret passe par un tube vers `kubectl create -f -`, seulement s'il manque, dans une tâche silencieuse. Contrat : [contracts/secrets.md](contracts/secrets.md).

### Données

Postgres selon l'ADR-012 : StatefulSet et Service dans `local/data/`, UID 999, profil `restricted`, fichiers de mot de passe, `scram-sha-256`, rôle `app` sans superutilisateur. La base vit dans le namespace de l'application, comme le propose la condition 9 de l'ADR-012 (question 1 ouverte pour Lucas). Valkey en Deployment sans persistance, mot de passe lu depuis `cache-auth` et jamais en argument (ADR-006, condition 2) ; le mécanisme de lecture se vérifie sur la documentation de Valkey (research RS-11).

### Couche GCP

Racine OpenTofu dans `gcp/tofu/`, périmètre du socle de l'ADR-008 : API activées sur un projet existant, réseau VPC et accès privé aux services, GKE Autopilot à nœuds privés avec `dns_endpoint_config`, Cloud SQL 18 en IP privée, Memorystore, Artifact Registry à tags immuables, secrets de Secret Manager par attributs `*_wo`, identité de la CI par fédération sur identifiants numériques, compte de service des nœuds, chiffrement de l'état et des plans. Les activations dont l'attribut OpenTofu n'est pas vérifié (Gateway API, synchronisation des secrets, flotte et Config Sync) s'écrivent après lecture de la documentation du provider, ou restent en commentaire daté avec leur `pending`. Manifests de la couche dans `gcp/k8s/` : `SecretProviderClass`, `SecretSync`, `RootSync`, classe de la Gateway, règle d'admission sur les `requests`. Rien n'est appliqué nulle part.

### CI dans CELIAN

Un workflow racine, `golden-saas-b2b.yml`, appelle les tâches du golden repo : un job statique (S01 à S23), un job de tests unitaires (U01, U02), un job d'export (X01), puis les jobs sur kind amd64 : `e2e-lite`, `offline-lite`, et plus tard `e2e-standard` et `gcp-on-kind`. Les workflows du golden repo appellent les mêmes tâches, pour que la logique n'existe qu'une fois. Les runners standard sont gratuits pour le dépôt public de CELIAN (R-16, ADR-010).

## Étapes livrables

Une étape tient en une PR, deux au plus. Chaque PR commence par ses tests en rouge (méthode du rôle [DEV]). Le profil lite est complet à l'étape 11.

| # | Étape | Titre de PR proposé | Contenu | Contrôles mis au vert | Dépend de |
| --- | --- | --- | --- | --- | --- |
| 1 | Squelette | `chore(golden): scaffold the SaaS B2B golden repo` | Arborescence, carte des couches, `platform.yaml`, Taskfile racine sans logique, README minimal, workflow CELIAN avec job statique | hooks racine sur `golden/`, S21 (forme de `platform.yaml`) | plan validé |
| 2 | Conventions Git du projet | `ci(golden): add the generated project's Git conventions` | pre-commit, commitlint, Renovate, release-please, CODEOWNERS, modèle de PR, workflows du projet ; job d'export | X01, S17, S23 | 1 |
| 3 | API d'exemple | `feat(golden): add the example .NET API` | Santé, notes, accès Npgsql et cache, Dockerfile par condensat | U01, S20 (API), S01 (Dockerfile) | 1 |
| 4 | Front d'exemple | `feat(golden): add the example React front` | Page des notes, appels relatifs à `/api`, tests, Dockerfile | U02, S20 (front), S01 (Dockerfile) | 1 |
| 5 | Contrôles préalables | `feat(golden): add the task up preflight checks` | Versions, moteur, mémoire et profil, ports, kubeconfig leurre ; tests par binaires simulés | P01 à P05 | 1 |
| 6 | Cluster et miroir | `feat(golden): create the kind cluster and the zot mirror` | Configuration kind, kubeconfig du projet, contexte explicite, miroir, `task down`, `task mirror:purge` ; premier job sur kind | S05, S13, S19, P06, E19, E22, E24 | 5 |
| 7 | Plate-forme de base | `feat(golden): install Gateway API and Envoy Gateway` | Fichiers vendorés et SHA256SUMS, charts rendus, EnvoyProxy, GatewayClass, ports, Gateway et HTTPRoute communes | S02, S06, S22, E03 | 6 |
| 8 | Secrets et données | `feat(golden): add local secrets, Postgres and Valkey` | Création des Secrets, StatefulSet Postgres et script d'init, Valkey avec mot de passe | S03, S04, S11, S12, E04, E05, E06, E12, E13, E21 | 7 |
| 9 | Profil lite de bout en bout | `feat(golden): start the lite profile end to end` | Construction et chargement, application, attente de « prêt », adresses, durées, `task reload`, `task app:down` | E01, E02, E07, E08, E09, E11, E17, E18, S01 (rendus), S07 (partie locale) | 3, 4, 8 |
| 10 | Hors réseau du profil lite | `test(golden): restart the lite profile without registries` | T2 en `pull` seul, purge et remplissage, essai sous UID non root | E10 (lite), E20, E23 | 9 |
| 11 | README | `docs(golden): write the golden repo README` | Prérequis datés, moteur libre d'abord, écarts PC et cloud, secrets en clair, mémoire par profil | S18 | 9 |
| 12 | Profil standard : Flux | `feat(golden): add Flux to the standard profile` | `install.yaml` vendoré, quatre contrôleurs, options de verrouillage, liaison ; ghcr.io par le miroir | S09, S10, E14, E15, E10 (standard) | 10 |
| 13 | Couche GCP : OpenTofu | `feat(golden): write the GCP layer in OpenTofu` | Racine, verrou multi-plateformes, politiques conftest, Trivy | S14, S15, S17 | 1 ; provider à partir du 2026-11-24 |
| 14 | Couche GCP : manifests | `feat(golden): add the GCP Kubernetes layer` | SecretSync, RootSync, classe de Gateway, `requests`, règle d'admission ; parité complète ; Config Sync libre sur kind | S07, S08, S16, E16 | 9, 13 |
| 15 | Keycloak | `feat(golden): add Keycloak to the standard profile` | Couche, Secrets, registre au miroir, T2 standard, seuil mémoire | E10 (standard), E14, contrôles fixés par l'ADR-013 | 12, ADR-013 |
| 16 | Mailpit | `feat(golden): add Mailpit to the standard profile` | Idem | E10 (standard), E14, contrôles fixés par l'ADR-014 | 12, ADR-014 |
| 17 | Mesures et démo | `docs(golden): measure the first standard start` | Protocole et rapport de démo, temps et volume, mémoire du lite | D01 à D05 | 11, 14, 15, 16 |

Parallélisme : les étapes 3, 4, 5 et 13 partent toutes de l'étape 1. L'étape 13 ne touche aucun fichier de `local/`, et peut avancer pendant que les étapes 6 à 11 occupent le cluster de la CI. S24 (signature d'Envoy Gateway) entre dès que [SECU] fournit la commande vérifiée, en PR à part.

## Matrice de validation (principe I)

### Contrôles

Préfixes : S statique, sans cluster, en pre-commit ou en CI ; P contrôle préalable, par binaires simulés ; U test unitaire ; E test sur kind, en CI amd64 et sur le poste ; X conventions dans une copie autonome ; D mesure ou démo de la gate. Chaque contrôle nomme en cas d'échec la condition ou l'exigence qu'il porte (FR-012).

| ID | Contrôle |
| --- | --- |
| S01 | Toute image des rendus (lite, standard, gcp) et des Dockerfile porte un condensat ; seules les images sous `saas-b2b.invalid`, construites par `task up`, en sont exemptées |
| S02 | Chaque fichier de `local/vendor/` a son SHA-256 dans `SHA256SUMS`, vérifié avant application ; aucune application depuis une URL |
| S03 | Aucun objet `Secret` ni champ `secretGenerator` versionné |
| S04 | Taskfile : tâches qui manipulent un secret en `silent: true`, sans heredoc, sans `kubectl apply` de Secret, sans valeur dans une variable ; inventaire des commandes qui créent ou retirent un conteneur, un réseau ou un volume ; construction, chargement et application définis une seule fois |
| S05 | Configuration kind : `apiServerAddress` et chaque `listenAddress` à 127.0.0.1, image de nœud par condensat, mineure égale à `platform.yaml` |
| S06 | Couche commune rendue : aucun groupe `gateway.envoyproxy.io`, `configsync.gke.io`, `*.toolkit.fluxcd.io`, `argoproj.io`, aucune annotation ni étiquette de moteur, aucune chaîne `${`, aucun objet propre à un fournisseur |
| S07 | Parité : la couche commune rendue seule se retrouve à l'identique dans le rendu `local` et dans le rendu `gcp`, aux seuls champs permis près (`gatewayClassName`) ; une seule Gateway ; mêmes références aux Secrets et à `app-config` |
| S08 | Couche commune valide contre le schéma de la version de Gateway API que sert GKE ; manifests valides contre leurs schémas |
| S09 | Chaque overlay rendu avec la version de Kustomize de Flux et avec celle de Config Sync donne le même résultat |
| S10 | Objets de liaison : `serviceAccountName` sur chaque `Kustomization`, options de verrouillage des contrôleurs de Flux, `roleRefs` et `sourceFormat: unstructured` sur le `RootSync`, export des métriques coupé, aucun `cluster-admin`, aucun `auth: token` |
| S11 | Valkey : mot de passe jamais dans `command` ni `args` |
| S12 | Postgres : UID 999, `runAsNonRoot`, capacités retirées, `seccompProfile`, aucun jeton monté, fichiers `_FILE`, `scram-sha-256`, aucune méthode `trust` ; le Secret du superutilisateur absent des manifests de l'application |
| S13 | Miroir : `hosts.toml` en capacité `pull` seule, configuration zot réduite à `sync`, aucun identifiant, fichiers dérivés de la liste unique des registres, lancement sur `kind` sans `-p`, stockage hors de l'arborescence |
| S14 | `tofu init -lockfile=readonly` puis `tofu validate`, sans backend distant ni identifiant |
| S15 | conftest sur le HCL : conditions 1 à 9 de l'ADR-008, condition 2 de l'ADR-007, version figée de Config Sync ; Trivy sur le HCL, échecs corrigés ou justifiés par écrit |
| S16 | Manifests `gcp` : `requests` sur chaque pod, règle d'admission présente |
| S17 | Workflows : aucune commande `tofu plan`, `apply` ni `destroy`, aucun identifiant cloud, aucun plan publié, actions figées par SHA |
| S18 | README : prérequis avec version, licence et date, moteur libre d'abord, écarts PC et cloud, secrets locaux en clair, mémoire par profil, installation de kind vérifiée contre le SHA-256 du catalogue |
| S19 | Chaque appel à `kubectl` des tâches passe par le kubeconfig du projet et le contexte du cluster local ; `port-forward` seulement avec `--address 127.0.0.1` |
| S20 | L'API n'expose que les routes de [contracts/http-api.md](contracts/http-api.md) ; le front, que ses écrans |
| S21 | Mineure Kubernetes et majeure Postgres identiques dans `platform.yaml`, la configuration kind, l'image Postgres et la couche OpenTofu |
| S22 | Charts d'Envoy Gateway rendus : toute CRD de `gateway.networking.k8s.io` vient du `standard-install.yaml` vérifié ; réglages `crds.*` et image du contrôleur conformes à l'ADR-005 |
| S23 | Renovate : 7 jours, exception de sécurité, aucune autre majeure pour `postgres`, paire kind et image de nœud, paire chart et condensat d'Envoy Gateway ; relecture [SECU] |
| S24 | Signature cosign du contrôleur d'Envoy Gateway, en attente de la commande vérifiée par [SECU] |
| P01 | kind d'une autre version, kubectl hors de la plage, Docker Engine sous 28.0.0 sur Linux : refus avec la version attendue |
| P02 | Moteur absent ou arrêté : message clair, rien de créé |
| P03 | Mémoire déclarée : profil choisi et annoncé ; sous le lite, refus avec la mémoire qui manque |
| P04 | Port de l'hôte déjà pris : arrêt avant toute création, port nommé |
| P05 | Kubeconfig de l'utilisateur pointé sur un autre contexte : ignoré |
| P06 | Le miroir ne démarre pas sans la configuration du projet |
| U01 | API : santé, prêt, validation des notes, lecture par le cache et provenance, réponses d'erreur |
| U02 | Front : rendu, appels relatifs, erreurs affichées par champ, états de chargement |
| E01 | `task up` sans cluster : prêt sans autre étape, adresses affichées, santé et page d'accueil par la gateway |
| E02 | Une note écrite en base, relue, puis servie par le cache |
| E03 | Ports en écoute : rien sur 0.0.0.0, `[::]` ni `*` ; miroir sans port publié, relié au seul réseau `kind`, et ce qu'un pod joint du miroir relevé |
| E04 | Deux environnements neufs : aucune valeur commune, 32 caractères au moins, aucune valeur connue (`root`, `admin`, `postgres`, `password`, `changeme`, `mysecretpassword`, chaîne vide), clés de mot de passe seulement |
| E05 | Relance sur environnement existant : empreinte SHA-256 de chaque valeur inchangée, aucune annotation `last-applied-configuration`, clés exactes du contrat, données lisibles |
| E06 | Valeurs secrètes absentes de l'arborescence et de l'historique Git |
| E07 | `task reload` après modification de l'API puis du front : nouvelle version servie, pod de la base non redémarré, note relue ; sans modification, mêmes objets aux étiquettes d'image près |
| E08 | `task down` : cluster et conteneur du miroir retirés, volume gardé, reste affiché ; `task mirror:purge` : volume retiré ; `task app:down` : namespace, PVC et Secrets de la base retirés, cluster gardé |
| E09 | T1 : `task up` sur un cluster gardé ne tire aucune image, d'après les événements du nœud |
| E10 | T2 pour chaque profil livré : recréation sans registre public, capacité `pull` seule, pod en `imagePullPolicy: Always`, image `postgres:18.7-trixie` comprise |
| E11 | Pods en marche : hôtes de registre dans la liste unique, références par condensat ou sous `saas-b2b.invalid` |
| E12 | Postgres : `pg_hba` sans `trust`, connexion sans mot de passe refusée depuis un autre namespace, rôle de `db-auth` sans superutilisateur, `server_version` à la majeure attendue, pods admis par le profil `restricted` |
| E13 | Valkey refuse une commande sans authentification |
| E14 | Profil lite : aucun contrôleur de Flux ; profil standard : Flux et les couches entrées |
| E15 | Flux : un environnement n'écrit pas dans le namespace d'un autre |
| E16 | Couche `gcp` sur kind, Config Sync libre en version figée, runner x64 : liaison, rendu, droits de `roleRefs` |
| E17 | Durée de chaque étape et durée totale affichées ; taille du volume du miroir affichée |
| E18 | Démarrage à chaud sous 90 s |
| E19 | Kubeconfig hors du dépôt ou ignoré par Git |
| E20 | Volume du miroir hors de l'arborescence ; après purge et `task up` en ligne, il ne contient que les condensats du projet |
| E21 | Volume de la base présent sans ses Secrets : `task up` s'arrête avec son message |
| E22 | `task down` ne retire jamais un conteneur étranger au projet, même de nom voisin |
| E23 | Miroir sous UID non root, sans capacités : essai, résultat consigné pour [SECU] |
| E24 | Kubeconfig leurre en variable d'environnement : `task up` réussit et ne le modifie pas |
| X01 | Copie du golden repo dans un dépôt Git neuf : ses hooks passent, son commitlint refuse un message non conforme, actionlint passe sur ses workflows, ses actions sont figées par SHA, gitleaks passe sur son historique |
| D01 | Poste propre, personne qui ne connaît pas le dépôt : API et front qui répondent après une commande, à chaque essai |
| D02 | Premier démarrage du profil standard : durée et volume mesurés, rapportés aux 900 s et au débit nécessaire |
| D03 | Mémoire du profil lite face à un portable de 8 Gio |
| D04 | Même parcours sur un poste arm64 |
| D05 | T1 et T2 sur un poste réellement coupé du réseau, construction comprise (suite de l'ADR-011, Lucas) |

### Exigences

| Exigence | Contrôles |
| --- | --- |
| FR-001 Démarrage en une commande | E01, P02, P04 |
| FR-002 Adresses par la gateway, en boucle locale | E01, E03 |
| FR-003 Écoute en boucle locale, testée à chaque démarrage | E03 |
| FR-004 Secrets aléatoires, jamais écrits, gardés | E04, E05, E06, S03, S04 |
| FR-005 Test des deux environnements neufs | E04 |
| FR-006 Profils | P03, E14 ; standard complet aux étapes 15 et 16 |
| FR-007 Rechargement sans perte, arrêt documenté | E07, E08 |
| FR-008 Condensats, refus des tags | S01, S13, E11 |
| FR-009 Code limité à l'exemple | S20, U01, U02 |
| FR-010 Couches et parité | S06, S07 |
| FR-011 Cible cloud validée sans cloud | S14, S15, S17 |
| FR-012 Conditions des ADR-007, 008 et 010 sans cloud | S03, S04, S07, S09, S10, S15, S16, E16 |
| FR-013 Conventions Git | X01, S17, S23 ; titre de PR et gitleaks déjà en CI de CELIAN |
| FR-014 Tests unitaires et bout en bout en CI amd64 | U01, U02, E01 |
| FR-015 Durées affichées, volume relevé | E17, D02 |
| FR-016 Démarrage sans registre | E10 |
| FR-017 Base selon BENCH-011 | E12, S12, conditions de l'ADR-012 ci-dessous |
| FR-018 README | S18 |
| FR-019 Cluster local ciblé explicitement | S19, P05, E24 |

### Critères de succès

| Critère | Contrôles | Où |
| --- | --- | --- |
| SC-001 Une commande, 100 % des essais | E01 à chaque PR, D01 | CI, démo |
| SC-002 Durée et volume du premier démarrage standard | E17, D02 | CI pour l'affichage, démo pour la mesure |
| SC-003 Démarrage à chaud sous 90 s | E18 | CI |
| SC-004 Aucune valeur secrète partagée | E04 | CI |
| SC-005 0 adresse hors boucle locale | E03 | CI |
| SC-006 CI verte, 0 euro | contrôles requis du workflow, S17 | CI |
| SC-007 0 écart dans la couche commune | S07, S06 | CI |
| SC-008 Lite sur 8 Gio | D03 | mesure [BENCH] et [FINOPS] |
| SC-009 Redémarrage sans registre | E10, D05 | CI, poste |

### Conditions des ADR

| ADR | Condition | Contrôles | Étape |
| --- | --- | --- | --- |
| ADR-004 | 1 Boucle locale | S05, E03 | 6, 7 |
| ADR-004 | 2 Version exacte de kind | P01 | 5 |
| ADR-004 | 3 Images par condensat | S01, S05 | 3, 6, 9 |
| ADR-004 | 4 Manifests tiers versionnés | S02 | 7 |
| ADR-004 | 5 Binaire vérifié contre le catalogue | S18 ; installation de la CI vérifiée contre `catalog/kubernetes-cluster.yaml` | 6, 11 |
| ADR-004 | 6 Mémoire par profil | P03, S18 | 5, 11 |
| ADR-004 | 7 Recréation hors ligne | E10 | 10 |
| ADR-004 | 8 Moteur libre | évaluation de Podman par [OPS] ; la CI tourne sur Docker Engine sous Linux | hors CI |
| ADR-004 | 9 Kubeconfig hors du dépôt | E19 | 6 |
| ADR-004 | Règle de version | S05, S21 | 6 |
| ADR-005 | 1 Images et CRD figées | S01, S22 | 7 |
| ADR-005 | 2 Groupe Envoy cantonné à `local` | S06 | 7 |
| ADR-005 | 3 Signature du contrôleur | S24, en attente | à part |
| ADR-005 | 4 R-25 avant le golden repo | E10 | 10 |
| ADR-005 | 5 Parité du manifest | S07, S08 | 9, 14 |
| ADR-006 | 1 Secrets hors de `k8s/` | S03, S04, E05 | 8 |
| ADR-006 | 2 Mot de passe de Valkey | S11, E13 | 8 |
| ADR-006 | 3 Accès en boucle locale | E03, S19 | 7 |
| ADR-006 | 4 R-25, deux tests | E09, E10 | 9, 10 |
| ADR-006 | 5 Prérequis déclarés | P01, S18 | 5, 11 |
| ADR-006 | 6 `task up` et `task reload` couverts | E01, E07, S04 | 9 |
| ADR-006 | 7 Images construites | S01, E11 | 9 |
| ADR-007 | 1 Création sur `local` | E04, E05, S03, S04 | 8 |
| ADR-007 | 2 Synchronisation sur GKE | S15 | 13 |
| ADR-007 | 3 Essai sur GKE | hors phase 2, accord de Lucas et budget | GATE 2 |
| ADR-007 | 4 Repli sur ESO | seulement si l'essai 3 échoue | sans objet |
| ADR-007 | 5 Parité du Secret | S07, E05 | 9, 14 |
| ADR-008 | 1 à 6 Fédération, chiffrement, `*_wo`, compte des nœuds, point d'accès DNS, Trivy et conftest | S15 ; S17 pour l'absence de plan publié | 13 |
| ADR-008 | 7 Verrou en lecture seule | S14 | 13 |
| ADR-008 | 8 Aucun module tiers par tag | S15 | 13 |
| ADR-008 | 9 `requests` explicites | S16 | 14 |
| ADR-008 | 10 Démontage en deux temps | documenté au README, jamais lancé ; S17 | 11, 13 |
| ADR-010 | 1 Couche commune neutre | S06 | 7 |
| ADR-010 | 2 Même rendu des deux côtés | S09 | 12 |
| ADR-010 | 3 Droits restreints | S10, E15, E16 | 12, 14 |
| ADR-010 | 4 Identifiants Git et source | S10 ; aucun identifiant Git par défaut | 12 |
| ADR-010 | 5 Couche `gcp` testée en x64 | E16 | 14 |
| ADR-010 | 6 Images par condensat | S01 | 12 |
| ADR-010 | 7 Essai sur GKE | hors phase 2 | GATE 2 |
| ADR-010 | 8 Signature face à Kyverno | sans objet : aucun profil du golden repo n'embarque Kyverno | sans objet |
| ADR-011 | 1 Capacité `pull` seule | S13, E10 | 6, 10 |
| ADR-011 | 2 Réseau `kind` seul | S13, E03 | 6, 7 |
| ADR-011 | 3 Docker Engine 28.0.0 sous Linux | P01, S18 | 5, 11 |
| ADR-011 | 4 Aucune référence par tag | S01, E11 | 9 |
| ADR-011 | 5 Règle de purge | E20, E17 | 10 |
| ADR-011 | 6 UID non root | E23 | 10 |
| ADR-011 | 7 Configuration montée, `sync` seule | S13, P06 | 6 |
| ADR-011 | 8 Image figée et suivie | S01, S23 | 6 |
| ADR-011 | 9 Stockage jamais versionné | S13, E20 | 6, 10 |
| ADR-011 | 10 Une seule liste de registres | S13, E11, E10 par profil | 6, 9, 10, 12 |
| ADR-011 | 11 Cycle de vie contrôlé | S04, E08, E22 | 6 |
| ADR-011 | 12 Moteur libre | évaluation de Podman par [OPS] | hors CI |
| ADR-011 | 13 Aucun identifiant dans le miroir | S13 | 6 |
| ADR-012 | 1 Manifests durcis, profil `restricted` | S12, E12 | 8 |
| ADR-012 | 2 Mot de passe par fichier, aucun `trust` | S12, E12 | 8 |
| ADR-012 | 3 Secret et volume ensemble | E05, E21 | 8 |
| ADR-012 | 4 Donnée gardée au rechargement | E07 ; redémarrage du nœud mesuré par [BENCH] | 9 |
| ADR-012 | 5 Parité de majeure | S21, S23, E12 | 8, 13 |
| ADR-012 | 6 « Prêt » par une requête authentifiée | E01 | 9 |
| ADR-012 | 7 Liste fermée de la dérogation | sans objet tant qu'aucun profil n'embarque Kyverno | sans objet |
| ADR-012 | 8 Rôle sans superutilisateur | S12, E12 | 8 |
| ADR-012 | 9 Un seul namespace | E08, E12 | 8, 9 |
| ADR-012 | 10 Test des secrets étendu | E04 | 8 |
| ADR-012 | 11 Image par le miroir | E10 | 10 |

## Ce qui n'est pas décidé ou pas mesuré

| Point | État | Porteur | Ce qui le lèvera | Étape bloquée |
| --- | --- | --- | --- | --- |
| Statut des ADR-011 et ADR-012 | proposés, le plan s'appuie dessus | Lucas | Validation des deux ADR et de leurs questions (ADR-011 : 1 à 6 ; ADR-012 : 1 et 2) | 6 et 8 |
| Moteur et forme du cache | aucun ADR ; Valkey vient du brief, Memorystore for Redis du socle de BENCH-008 | DSI, [ARCHI] | Un benchmark ou un ADR du cache, avec l'authentification de Memorystore | 8 pour la forme locale, 13 pour Memorystore |
| Keycloak et Mailpit | BENCH-012 et BENCH-013 en cours | [BENCH], [ARCHI] | ADR-013 et ADR-014 ; image, version, registre, Secrets, mémoire | 15 et 16 |
| Source lue par Flux sur le PC | ouvert (ADR-010, question 1) | Lucas | Décision de Lucas ; d'ici là, Flux est installé et sa liaison reste suspendue, `task reload` seul maître des objets (research RS-14) | 12, partiellement |
| Flux à quatre contrôleurs | ouvert (ADR-010, question 4) | [OPS] | Décision d'[OPS] ; le plan suppose quatre contrôleurs, comme R-04 | 12 |
| Certificat de l'écouteur HTTPS en local | non décidé | [SECU], [DEV] | Méthode qui crée la clé sans fichier ni argument (research RS-10) | 7 |
| TLS vers la base et le cache | état du serveur local non lu ; Cloud SQL en `ENCRYPTED_ONLY`, Memorystore en TLS | [DEV], [SECU] | Lecture des documentations, choix du mode de connexion, écart listé au README | 8 |
| Nom sous `.invalid` accepté par `kind load` et le kubelet | non essayé | [OPS] | Essai à l'étape 9, repli décrit dans research RS-07 | 9 |
| Plusieurs amonts dans zot | montages a et b non essayés | [OPS] | Premier montage qui passe T2 avec ghcr.io | 12 |
| T2 en capacité `pull` seule | non mesuré | [QA], [OPS] | E10 ; un échec rouvre l'ADR-011 | 10 |
| Profil `restricted` pour l'API et le front | non vérifié | [DEV] | E12 ; image nginx non root à choisir (R-05) | 8, 9 |
| Versions du front, des frameworks de test, de Task, conftest, kubeconform, du provider `random` | à vérifier | [DEV] | Lecture datée de la source officielle avant usage (research RS-05, RS-18) | 2 à 13 |
| Attributs OpenTofu des activations GKE | non vérifiés (ADR-005, 007, 010) | [OPS] | Documentation du provider `google` | 13 |
| Validation OpenTofu hors ligne avec chiffrement et verrou multi-plateformes | non vérifiée (ADR-008, question 5) | [OPS] | Essai sur la racine du golden repo | 13 |
| Alerte budget | ouverte (ADR-008, question 1) | [OPS], [SECU] | Racine séparée ou alias de provider | 13 |
| Signature cosign d'Envoy Gateway | emplacement non trouvé | [SECU] | Commande vérifiée sur la documentation de cosign ; un échec rouvre l'ADR-005 | S24 |
| Débit visé du critère des 15 minutes | à fixer après le golden repo | [FINOPS] | Mesure D02 | 17 |
| Méthode de mesure du volume en démo | à reprendre des scripts de BENCH | [BENCH] | Protocole de l'étape 17 | 17 |
| Redémarrage du nœud et données de Postgres | non mesuré, mesure autorisée | [BENCH] | Série `NODE_RESTART=1` après BENCH-012 et BENCH-013 | aucune ; le README ne promet rien d'ici là |
| Essais sur GKE | hors phase 2 | Lucas, [FINOPS] | GATE 2, accord et budget | aucune en phase 2 |

## Risques suivis par ce plan

- R-04 : le volume du premier `task up` standard dépasse déjà le budget à 10 Mbit/s avant Keycloak et Mailpit ; D02 le mesure, [FINOPS] fixe le débit visé.
- R-25 et R-34 : le miroir n'est prouvé que pour docker.io ; ghcr.io (Flux) et les registres de Keycloak et Mailpit passent par E10 à chaque couche.
- R-30 : le Taskfile grossit à chaque étape ; S04 et l'inventaire relu par [SECU] le bornent.
- R-35 : Postgres écrit à la main ; S12 et E12 tiennent ses conditions.
- CVE-2026-97054 dans Envoy Gateway 1.10.0 : un scan Trivy d'image la relèverait ; la règle d'acceptation temporaire revient à [SECU].
- Limite de Docker Hub en CI : chaque job neuf tire de nouveau ses images ; le cache d'images de la CI demande une relecture [SECU] (ADR-011, condition 9).
- Exemple sans authentification : sans risque en boucle locale, mais ouvert à tous le jour d'un déploiement réel sur GCP. À traiter avant la GATE 2 (question pour Lucas).
- Hors spec 001 : SBOM, scan d'images et signature (US-009, ENF-03, Q8) ne sont exigés par aucune exigence de la spec ; le plan ne les ajoute pas.

## Complexity Tracking

Aucune violation de la constitution. La dérogation de l'ADR-012 à ENF-03, exigence du PRD et non principe, n'a pas d'effet dans le golden repo : aucun profil n'y embarque Kyverno.
