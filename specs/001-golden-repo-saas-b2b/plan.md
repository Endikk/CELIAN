# Implementation Plan: golden repo SaaS B2B

**Branch**: `docs/plan-golden-repo` (fonctionnalité `001-golden-repo-saas-b2b`) | **Date**: 2026-11-21, mis à jour le 2026-11-23 et le 2026-11-25 | **Spec**: [spec.md](spec.md)

**Input**: spécification `specs/001-golden-repo-saas-b2b/spec.md`, amendée par la PR #39 (22 exigences, 10 critères de succès, 7 récits), et sa liste de contrôle [checklists/requirements.md](checklists/requirements.md). Mise à jour du 2026-11-23 : amendement de la spec et décisions du 2026-11-21 et du 2026-11-23, listées dans la section « Décisions prises depuis la première version ». Mise à jour du 2026-11-25, par [ARCHI] : les écarts que les tâches ont relevés, chacun renvoyé à son numéro dans la section « Écarts relevés entre spec, plan et tâches » de [tasks.md](tasks.md).

**Auteur** : [DEV], à la demande du DSI. Relecture du DSI puis de Lucas avant `/speckit-tasks`.

## Summary

Le golden repo est un projet SaaS B2B complet, construit à la main dans `golden/saas-b2b/`, que le blueprint Copier de la phase 3 reproduira. Il contient une API .NET réduite à un contrôle de santé et à un exemple de notes qui écrit en base et relit par le cache, un front React qui l'affiche, une couche commune et deux couches de cible.

Sur le PC, `task up` vérifie le poste, crée un cluster kind, lance le miroir zot, installe Envoy Gateway, crée les Secrets par un tube, démarre Postgres sans opérateur et le cache, puis construit, charge et applique l'application, sans outil de boucle. Sur GCP, une racine OpenTofu écrite à la main décrit GKE Autopilot, Cloud SQL, Memorystore, Secret Manager et Config Sync. La CI la valide, contrôle ses politiques et la scanne, sans plan ni apply. Elle produit aussi le SBOM de chaque image construite et scanne toutes les images que la stack fait tourner (récit 7).

Les choix de technos viennent des ADR-004 à ADR-012, que ce plan ne rouvre pas. Il fixe ce que les ADR laissaient au golden repo : l'arborescence et la carte des couches, le routage, l'exemple applicatif, les noms des Secrets, l'ordre de `task up`, l'outil et le seuil du scan, le découpage en PR et la matrice de validation. Le moteur du cache attend BENCH-014 et l'ADR-015 : aucune image n'est figée d'ici là. Le profil lite se livre d'abord. Le profil standard (Flux avec sa liaison suspendue, puis Keycloak et Mailpit après leurs ADR) et la couche GCP viennent ensuite.

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
| `local` | Moteur de conteneurs | Docker Engine 28.0.0 au moins sous Linux ; moteur libre cité d'abord (R-26). Podman répond derrière `docker` avec sa propre version, que cette règle refuserait sous Linux ; rien n'est câblé pour lui (écart 16 de tasks.md) | ADR-011, condition 3 ; ADR-004, condition 8 ; research RS-08 |
| `local` | CRD Gateway API | v1.7.0, `standard-install.yaml`, SHA-256 dans l'ADR-005 | ADR-005 |
| `local` | Envoy Gateway | 1.10.0, charts et images par SHA-256 et condensat | ADR-005, tableau « Versions et condensats » |
| `local` | Miroir | zot 2.1.23 par condensat | ADR-011, condition 8 |
| `local` | Base | `postgres:18.7-trixie` par condensat, sans opérateur | ADR-012 |
| `local` | Cache | en attente de BENCH-014 et de l'ADR-015 : aucune image, version ni forme figée (décision de Lucas du 2026-11-21). L'essai de BENCH-005 utilisait `valkey/valkey:9.1.4-alpine`, repère de volume seulement | BENCH-014, brouillon ; research RS-11 |
| `local` | GitOps (standard) | Flux 2.10.0, `install.yaml` par SHA-256, quatre contrôleurs par condensat ; liaison livrée suspendue (décision de Lucas du 2026-11-21) | ADR-010 ; `tests/bench/bench-009-gitops.sh`, lignes 72 à 93 ; research RS-14 |
| `local` | Identité et mails (standard) | Keycloak, Mailpit : aucune image ni version tant que les ADR-013 et ADR-014 manquent | décision de Lucas du 2026-11-20 |
| `gcp` | Cluster | GKE Autopilot, canal Regular de référence | ADR-008 ; ADR-004 |
| `gcp` | Base | Cloud SQL for PostgreSQL, majeure 18 | ADR-008 ; ADR-012, condition 5 |
| `gcp` | Cache | Memorystore, variante et authentification en attente de BENCH-014 et de l'ADR-015 | ADR-008, portée ; research RS-11 |
| `gcp` | Secrets | Secret Manager, synchronisé par GKE (`SecretProviderClass`, `SecretSync`) | ADR-007 |
| `gcp` | GitOps | Config Sync 1.25.2, un `RootSync` | ADR-010 |
| `gcp` | Gateway | Contrôleur Gateway de GKE, classe à fixer par [OPS] | ADR-005 |
| CI | SBOM et scan des images, scan du HCL | Trivy : plancher 0.71.1 (CVE-2026-55092) ; candidate 0.76.2, publiée le 2026-11-05, binaire vérifié par SHA-256 versionné ; SBOM en CycloneDX JSON ; seuil `HIGH` | research RS-22 et RS-23, sources lues le 2026-11-23 ; ADR-008, condition 6 ; ADR-011, condition 8 |

**Storage** : PostgreSQL 18, base `app` (StatefulSet d'une réplique sur `local`, Cloud SQL sur `gcp`) ; cache sans persistance sur `local` ; volume nommé du moteur pour le miroir, hors de l'arborescence du projet.

**Testing** : tests unitaires .NET et du front (frameworks à vérifier, research RS-18), lancés dans l'image de construction, puisque le poste n'a ni SDK .NET ni Node.js (research RS-06 ; écart 11 de tasks.md, confirmé par le DSI en session 4 et appliqué aux étapes 3 et 4) ; scripts bash sur kind, passés à shellcheck ; politiques Rego exécutées par conftest (version à vérifier), dont la décision du scan, testée sur des rapports d'exemple ; validation de schéma par kubeconform, nommé par US-007, outil à confirmer avec [QA] ; `tofu validate` ; Trivy sur le HCL, pour le SBOM des images construites et pour le scan de l'inventaire des images (research RS-22 à RS-24).

**Target Platform** : postes macOS et Linux (Q5), arm64 et amd64 ; CI sur runner GitHub `ubuntu-latest` amd64, dans le dépôt de CELIAN ; GKE Autopilot pour le code GCP, validé et jamais déployé en phase 2.

**Project Type** : application web (API et front) avec son infrastructure pour deux cibles, construite comme dépôt de référence d'un générateur.

**Performance Goals** :

- démarrage à chaud sous 90 s (SC-003). Repères mesurés sur la stack d'essai : `task up` à chaud en 41,5 s (ADR-006), plate-forme à chaud en 44,6 s (ADR-005), recréation hors réseau en 34,7 s (ADR-011), Postgres prêt en 8,9 s (ADR-012) ;
- premier démarrage du profil standard mesuré et rapporté au budget de 900 s, au débit visé que fixera [FINOPS] (SC-002). Estimation hors Keycloak et Mailpit : 1 521,9 Mo en amd64, soit 135,3 % du budget à 10 Mbit/s et un débit minimal de 13,5 Mbit/s (R-04, ADR-012), qui compte encore le Valkey de l'essai (18,8 Mo) en attendant l'ADR-015. Profil lite : environ 1 263,8 Mo, calcul de ce plan (standard moins Flux réduit, 258,1 Mo), jamais mesuré ;
- rechargement : API en 6,6 s et front en 5,1 s sur la stack d'essai (ADR-006), à remesurer avec un vrai build Vite.

**Constraints** : rien n'écoute hors de 127.0.0.1 ; secrets aléatoires d'au moins 32 caractères, jamais dans un fichier, une variable affichée ni un argument ; aucune image ni dépendance par tag ; profil lite sur un portable de 8 Gio (estimation de [FINOPS] : VM du moteur de 2,0 Gio, portable de 6,0 Gio, plancher de 1 186,6 Mio ; partie connue du standard : 2,5 et 6,5 Gio, ADR-012, ordres de grandeur) ; aucune commande vers un cluster cloud (FR-019) ; ni Helm, ni Tilt, ni Docker Compose dans les prérequis de l'utilisateur (ADR-006) ; aucune faille `HIGH` ou `CRITICAL` sur `main` sans exception datée et non échue (FR-022) ; aucun déploiement réel sur GCP sans authentification (research RS-25).

**Scale/Scope** : un poste, un environnement local, un environnement GCP décrit et jamais créé (Q6) ; code applicatif limité au contrôle de santé, à l'exemple et au front (Q7, FR-009).

Aucun marqueur NEEDS CLARIFICATION ne reste : chaque inconnue est soit tranchée dans [research.md](research.md), soit écrite comme un point à vérifier, avec son porteur et l'étape qu'il bloque. Aucune ne bloque le plan lui-même.

## Constitution Check

*GATE : avant la phase 0, puis après la conception de la phase 1.* Constitution 1.2.0.

| Principe | Avant conception | Après conception | Où c'est tenu |
| --- | --- | --- | --- |
| I. Rien sans test automatique | Passe | Passe | Chaque exigence, chaque critère de succès et chaque condition d'ADR vérifiable sans cloud a son contrôle (section « Matrice de validation »), récit 7 compris (S25 à S27, U03, E25 à E27). Le cache entre avec ses contrôles à l'étape 19, après l'ADR-015 ; aucun profil n'est livré sans lui. Les essais sur GKE (ADR-007, condition 3 ; ADR-010, condition 7) attendent la GATE 2 : la combinaison `gcp` ne sera pas proposée avant. Le golden repo n'est proposé à personne |
| II. Spec abstraite, catalogue concret | Passe | Passe | Un dossier par couche (carte des couches) ; la couche commune ne nomme aucun outil ni fournisseur, contrôlée par S06 et S07. Les exceptions au scan suivent la même règle : un fichier par couche (research RS-23) |
| III. Managé sur le cloud, open source ailleurs | Passe | Passe, une réserve | `local` : kind, Envoy Gateway, zot, Postgres, Flux. `gcp` : GKE Autopilot, Cloud SQL, Memorystore, Secret Manager, Config Sync, contrôleur Gateway de GKE. Réserve : le moteur du cache, local et Memorystore, attend BENCH-014 et l'ADR-015 (research RS-11) |
| IV. Catalogue traçable | Passe | Passe | Entrées `kubernetes-cluster`, `gateway`, `secrets` et `gitops` présentes. `database` (ADR-012), l'attribut du miroir (ADR-011) et le cache (ADR-015) s'écrivent en phase 3. Le golden repo n'est pas un blueprint, comme le notent l'ADR-011 et l'ADR-012 ; le blueprint ne s'en servira qu'une fois les entrées complètes |
| V. Gouvernance ouverte d'abord | Passe | Passe | Choix des ADR. La gouvernance de Task reste à relever (ADR-006, question 5) ; zot est au niveau Sandbox de la CNCF (ADR-011). Trivy est à éditeur unique (Aqua Security) : il vient du PRD et des ADR-008 et ADR-011, comme outil de CI, hors des briques du catalogue |
| VI. Récent mais éprouvé | Passe | Passe | Délai de 7 jours : `google` 8.12.0 utilisable le 2026-11-24, Flux 2.10.1 le 2026-11-27 ; Trivy 0.76.2, publiée le 2026-11-05, le passe ; les autres versions retenues le passent déjà. Les versions du front se lisent avec leur date avant usage (R-05) |
| VII. Une commande pour démarrer | Passe | Passe | `task up` seul, prérequis listés au README (S18) ; contrats dans [contracts/task-cli.md](contracts/task-cli.md). Le scan tourne en CI et n'ajoute rien à `task up` |
| VIII. Aucun fait de mémoire | Passe | Passe | Versions sourcées dans le contexte technique ; faits sur Trivy lus le 2026-11-23 et cités avec leur adresse (research RS-22 et RS-23) ; tout le reste est marqué à vérifier dans [research.md](research.md), y compris les syntaxes d'outils tiers, que les contrats évitent en passant par des tâches |
| IX. Aucun secret dans le dépôt | Passe | Passe | Secrets nés par un tube (ADR-007, condition 1), aucun objet `Secret` versionné (S03), kubeconfig hors du dépôt (E19), miroir sans identifiant (S13), gitleaks en local et sur l'historique ; aucune action tierce de Trivy dans les workflows (S26), après la compromission de mars 2026 qui volait les secrets des pipelines |
| X. Aucune dépense cloud sans accord | Passe | Passe | Ni plan, ni apply, ni destroy en phase 2 ; CI sans identifiant cloud (S17) ; aucun contexte GKE sur le poste (FR-019, S19, E24) ; aucun déploiement réel sur GCP sans authentification, même après accord (research RS-25) |

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
└── tasks.md             # phase 2 : /speckit-tasks, 160 tâches (PR #40)
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
├── policy/                       commune : Rego de neutralité, de condensats, d'absence de Secret, décision du scan
├── security/                     commune : seuil du scan, exceptions des images construites (noms provisoires)
├── tests/                        commune : tests statiques sans cluster, parité des rendus, rapports d'exemple du scan
├── local/                        couche local
│   ├── tasks/                    local.yml, seul Taskfile de la couche depuis T009 : up, down, app, reload, mirror, secrets, check (écart 13 de tasks.md)
│   ├── scripts/                  scripts bash appelés par les tâches
│   ├── kind/cluster.yaml         configuration du cluster
│   ├── mirror/                   liste des registres, configuration zot, certs.d dérivés
│   ├── vendor/                   manifests tiers et SHA256SUMS : CRD Gateway API, Envoy Gateway rendu, Flux
│   ├── platform/                 EnvoyProxy, GatewayClass
│   ├── data/                     Postgres (StatefulSet, Service, script d'init) ; cache après l'ADR-015
│   ├── gitops/                   objets de liaison de Flux, suspendus (profil standard)
│   ├── identity/                 Keycloak, après l'ADR-013 (profil standard)
│   ├── mail/                     Mailpit, après l'ADR-014 (profil standard)
│   ├── k8s/                      compositions d'entrée : lite/, standard/, composant de cible
│   ├── policy/                   Rego propres à la couche
│   ├── security/                 images qu'aucun fichier ne nomme, exceptions des images de la couche
│   └── tests/                    contrôles préalables simulés, tests sur kind, test hors réseau, relevé des images
└── gcp/                          couche gcp
    ├── tofu/                     racine OpenTofu et .terraform.lock.hcl
    ├── k8s/                      composant de cible et composition prod/
    ├── policy/                   Rego sur le HCL et les manifests gcp
    ├── tasks/                    gcp:validate, gcp:policy, gcp:scan
    └── tests/                    Config Sync libre sur kind (x64)
```

Côté CELIAN, hors du golden repo : un workflow racine `.github/workflows/golden-saas-b2b.yml` lance les tâches du golden repo en CI (research RS-17), et ses jobs bloquants entrent dans les contrôles requis de `.github/rulesets/main.json`. Les workflows de `golden/saas-b2b/.github/` décrivent la CI du futur projet généré ; GitHub ne les lance pas depuis un sous-dossier (fait à vérifier, research RS-17), d'où le contrôle X01, qui les exerce dans une copie autonome.

**Structure Decision** : une application web en deux projets (`src/Api`, `src/front`) dans une seule arborescence de projet généré, découpée en trois couches par dossiers. Le détail de la composition Kustomize, des points d'injection de la couche de cible et de la règle de parité est dans [contracts/layers.md](contracts/layers.md).

## Conception

### Ce que fait `task up`

Ordre de l'ADR-006, complété par l'ADR-011 et l'ADR-012. Le contrat complet, entrées, sorties et cas d'échec, est dans [contracts/task-cli.md](contracts/task-cli.md).

1. Contrôles préalables, avant toute création, dans l'ordre du contrat task-cli : moteur joignable, version exacte de kind, mineure de kubectl, Docker Engine sous Linux, mémoire déclarée par le moteur qui fixe le profil, ports de l'hôte libres (écart 1 de tasks.md). Le moteur n'est accepté que derrière un socket unix local, chaque appel à `docker` est borné à 10 s, et seul « Connection refused » vaut port libre (écart 18 de tasks.md, research RS-08).
2. Cluster kind créé depuis `local/kind/cluster.yaml`, ou réutilisé s'il existe. Kubeconfig du projet écrit hors du dépôt ; chaque commande vise ce fichier et le contexte du cluster local (FR-019).
3. Miroir zot : retrait contrôlé d'un ancien conteneur du projet, puis lancement sur le réseau `kind`, sans port publié, configuration montée en lecture seule, volume du projet ; attente de sa réponse.
4. Plate-forme de base : SHA-256 de chaque fichier de `local/vendor/` vérifié, puis CRD Gateway API, Envoy Gateway, EnvoyProxy et GatewayClass. En profil standard, Flux, liaison suspendue (research RS-14).
5. Construction de l'API et du front sous l'hôte réservé `saas-b2b.invalid`, étiquette neuve, chargement par `kind load docker-image`.
6. Namespace de l'application (profil `restricted`), puis création des Secrets absents par un tube. Volume de la base présent sans ses Secrets : arrêt avec un message (ADR-012, condition 3).
7. Application de `local/k8s/<profil>` par `kubectl apply -k`.
8. Attente de « prêt » : `SELECT 1` authentifié par le Service de la base, contrôle de santé de l'API et page d'accueil du front, par la gateway.
9. Affichage des adresses, de la durée de chaque étape et du total (FR-015), et de la taille du volume du miroir.

`task reload` réutilise les étapes 5 et 7, définies une seule fois dans le Taskfile (ADR-006, condition 6). `task down`, `task app:down` et `task mirror:purge` suivent l'ADR-011.

### Routage et adresses

Une seule Gateway, deux écouteurs HTTP et HTTPS (ADR-005), dans le namespace de l'application. Deux HTTPRoute : le préfixe `/api` vers l'API, `/` vers le front. Le front et l'API partagent donc une origine : pas de CORS, et le front appelle des chemins relatifs. L'API sert elle-même ses routes sous `/api`, sans réécriture de chemin, pour n'employer que des champs du cœur de Gateway API (ADR-005, condition 5). Les deux ports de l'hôte sont publiés en `listenAddress: "127.0.0.1"` et fixés à l'étape 7 ; leurs valeurs vivent dans `local/kind/cluster.yaml` et dans les tâches, qu'un test garde d'accord. Le certificat de l'écouteur HTTPS en local reste à trancher (research RS-10).

### Exemple applicatif

Une ressource « note » : `POST /api/notes` écrit en base, `GET /api/notes/{id}` relit par le cache (lecture paresseuse, provenance dans la réponse), `GET /api/notes` liste les plus récentes depuis la base. Deux routes de santé : `/api/healthz` (processus vivant) et `/api/readyz` (base et cache joignables). Accès aux données par Npgsql avec requêtes paramétrées, sans ORM ; schéma créé au démarrage par un script SQL idempotent, sous le rôle de l'application (research RS-03 et RS-04). L'accès au cache passe par une interface, dont le client concret entre à l'étape 19 (research RS-11). Aucune authentification en local : elle arrive avec l'ADR-013, et aucun déploiement réel sur GCP ne se fait sans elle (décision du DSI du 2026-11-23, research RS-25). Détail : [contracts/http-api.md](contracts/http-api.md) et [data-model.md](data-model.md).

### Profils

`task up` lit la mémoire que déclare le moteur (ADR-004, condition 6). Au-dessus du seuil du standard, il prend le standard ; entre les deux seuils, le lite, et il le dit ; sous le seuil du lite, il refuse en donnant la mémoire qui manque. La variable `PROFILE` force un profil, sous les mêmes contrôles. Seuils de départ : VM de 2,0 Gio pour le lite et 2,5 Gio pour le standard hors Keycloak et Mailpit (ADR-011, ADR-012), recalculés sur la première mesure du golden repo, à l'entrée du cache et à celle de chaque couche du standard. Jusqu'à l'étape 12, le standard est reconnu et refusé par un message clair. Un moteur qui déclare au moins 2560 Mio, poste de mesure et runners de CI compris, arrête donc `task up` lancé sans `PROFILE` : les étapes 6 à 9 et le job `e2e-lite` passent `PROFILE=lite` (écart 14 de tasks.md). Les contrôles comparent la mémoire déclarée à 2048 et 2560 Mio, et ce que déclare une VM réglée à 2,0 Gio n'est pas mesuré : T081 recale les seuils, ceux du README compris (écart 15 de tasks.md).

### Secrets

Quatre Secrets en profil lite : `db-auth`, commun aux deux cibles (ADR-012) ; `cache-auth`, commun, créé à l'étape 19 sur `local` et produit à l'étape 20 sur `gcp`, après l'ADR-015 ; `db-superuser`, propre à `local` ; `gateway-tls`, dont la clé et le certificat naissent d'un `openssl req` sans fichier (research RS-10, 2026-11-26). Chaque mot de passe naît de `/dev/urandom` ; chaque Secret passe par un tube vers `kubectl create -f -`, seulement s'il manque, dans une tâche silencieuse. Contrat : [contracts/secrets.md](contracts/secrets.md).

### Données

Postgres selon l'ADR-012 : StatefulSet et Service dans `local/data/`, UID 999, profil `restricted`, fichiers de mot de passe, `scram-sha-256`, rôle `app` sans superutilisateur. La base vit dans le namespace de l'application, comme le propose la condition 9 de l'ADR-012 et comme Lucas l'a retenu le 2026-11-21 (question 1). Cache : moteur, image, forme et persistance fixés par l'ADR-015, après BENCH-014. Quelle que soit l'issue, son mot de passe vient de `cache-auth` et ne passe jamais en argument (ADR-006, condition 2) ; le mécanisme se vérifie sur la documentation du moteur retenu (research RS-11).

### Couche GCP

Racine OpenTofu dans `gcp/tofu/`, périmètre du socle de l'ADR-008 : API activées sur un projet existant, réseau VPC et accès privé aux services, GKE Autopilot à nœuds privés avec `dns_endpoint_config`, Cloud SQL 18 en IP privée, Memorystore à l'étape 20 après l'ADR-015, Artifact Registry à tags immuables, secrets de Secret Manager par attributs `*_wo`, identité de la CI par fédération sur identifiants numériques, compte de service des nœuds, chiffrement de l'état et des plans. Les activations dont l'attribut OpenTofu n'est pas vérifié (Gateway API, synchronisation des secrets, flotte et Config Sync) s'écrivent après lecture de la documentation du provider, ou restent en commentaire daté avec leur `pending`. Manifests de la couche dans `gcp/k8s/` : `SecretProviderClass`, `SecretSync`, `RootSync`, classe de la Gateway, règle d'admission sur les `requests`. Rien n'est appliqué nulle part.

### CI dans CELIAN

Un workflow racine, `golden-saas-b2b.yml`, appelle les tâches du golden repo : un job statique (S01 à S23, S25 à S30, S32), un job de tests unitaires (U01 à U03), un job d'export (X01), puis les jobs sur kind amd64 : `e2e-lite`, `offline-lite`, et plus tard `e2e-standard` et `gcp-on-kind`. `e2e-lite` et `e2e-standard` finissent par le relevé des images, le SBOM et le scan (E25 à E27). Les workflows du golden repo appellent les mêmes tâches, pour que la logique n'existe qu'une fois. Les runners standard sont gratuits pour le dépôt public de CELIAN (R-16, ADR-010).

La CI du golden repo tourne dans CELIAN seulement, comme le dit la spec (décision du DSI du 2026-11-21). Un dépôt miroir viendra avec le générateur, hors de ce plan. Les jobs bloquants entrent dans les contrôles requis du ruleset de `main`, que Lucas applique avec les droits admin (research RS-17).

### SBOM et scan des images

Trivy fait les deux (research RS-22). Dans `e2e-lite`, puis dans `e2e-standard`, après les tests du profil :

1. E25 relève les images en marche, dans le cluster et sur le moteur, et les compare à l'inventaire du profil (research RS-24) ;
2. Trivy écrit le SBOM CycloneDX de chaque image construite, gardé en artefact de l'exécution (E26) ;
3. Trivy scanne chaque image de l'inventaire, images construites comprises, avec une base téléchargée dans la même exécution ; une politique Rego applique le seuil `HIGH` et les exceptions valides, et nomme chaque couple image et vulnérabilité refusé (E27, research RS-23).

Les images construites sont scannées dans le job qui les fait tourner : le condensat scanné est celui qui tourne. Avant l'étape 9, la première PR de l'étape 18 fait tourner le scan des images tirées dans un job à part, sans cluster ; la seconde le place dans `e2e-lite`. Le scan est un contrôle requis : une PR qui le fait échouer ne fusionne pas (FR-022). Une faille publiée après une fusion fait échouer la PR suivante, même sans rapport avec l'image : la correction passe alors par une montée de version ou par une exception écrite par [SECU].

## Étapes livrables

Une étape tient en une PR, deux au plus. Chaque PR commence par ses tests en rouge (méthode du rôle [DEV]). Le profil lite est complet à l'étape 11, qui dépend par l'étape 9 de l'étape 19, donc de l'ADR-015. Les étapes 18 à 20 s'ajoutent le 2026-11-23 ; les numéros suivent l'ordre d'écriture, et la colonne « Dépend de » donne l'ordre de construction.

| # | Étape | Titre de PR proposé | Contenu | Contrôles mis au vert | Dépend de |
| --- | --- | --- | --- | --- | --- |
| 1 | Squelette | `chore(golden): scaffold the SaaS B2B golden repo` | Arborescence, carte des couches, `platform.yaml`, Taskfile racine sans logique, README minimal, workflow CELIAN avec job statique | hooks racine sur `golden/`, S21 (forme de `platform.yaml`) | plan validé |
| 2 | Conventions Git du projet | `ci(golden): add the generated project's Git conventions` | pre-commit, commitlint, Renovate, release-please, CODEOWNERS, modèle de PR, workflows du projet ; job d'export | X01, S17, S23 | 1 |
| 3 | API d'exemple | `feat(golden): add the example .NET API` | Santé, notes, accès Npgsql, accès au cache derrière une interface (client concret à l'étape 19), Dockerfile par condensat | U01, S20 (API), S01 (Dockerfile) | 1 |
| 4 | Front d'exemple | `feat(golden): add the example React front` | Page des notes, appels relatifs à `/api`, tests, Dockerfile | U02, S20 (front), S01 (Dockerfile) | 1 |
| 5 | Contrôles préalables | `feat(golden): add the task up preflight checks` | Versions, moteur, mémoire et profil, ports, kubeconfig leurre ; tests par binaires simulés | P01 à P05 | 1 |
| 6 | Cluster et miroir | `feat(golden): create the kind cluster and the zot mirror` | Configuration kind, kubeconfig du projet, contexte explicite, miroir, `task down`, `task mirror:purge` ; premier job sur kind ; commentaire `# renovate:` sur `KIND_VERSION` de `local/scripts/lib/preflight-checks.sh`, dans le groupe de kind et de son image de nœud (écart 17 de tasks.md) | S05, S13, S19, P06, E19, E22, E24 | 5 |
| 7 | Plate-forme de base | `feat(golden): install Gateway API and Envoy Gateway` | Fichiers vendorés et SHA256SUMS, charts rendus, EnvoyProxy, GatewayClass, ports, Gateway et HTTPRoute communes ; écouteur HTTPS et `gateway-tls` en seconde PR (écart 3 de tasks.md) | S02, S06, S22, E03 ; E03, E04 et E05 étendus à l'écouteur HTTPS (seconde PR) | 6 pour la première PR ; 8 et research RS-10 pour la seconde |
| 8 | Secrets et données | `feat(golden): add local secrets and Postgres` | Création des Secrets `db-auth` et `db-superuser`, StatefulSet Postgres et script d'init ; la partie cache passe à l'étape 19 | S03, S04, S12, E04, E05, E06, E12, E21 | 7 |
| 9 | Profil lite de bout en bout | `feat(golden): start the lite profile end to end` | Construction et chargement, application, attente de « prêt », adresses, durées, `task reload`, `task app:down` | E01, E02, E07, E08, E09, E11, E17, E18, S01 (rendus), S07 (partie locale) | 3, 4, 8, 19 |
| 10 | Hors réseau du profil lite | `test(golden): restart the lite profile without registries` | T2 en `pull` seul, purge et remplissage, essai sous UID non root, premier démarrage sans registre | E10 (lite), E20, E23, E28 | 9 |
| 11 | README | `docs(golden): write the golden repo README` | Prérequis datés, moteur libre d'abord, écarts PC et cloud, secrets en clair, mémoire par profil | S18 | 9 |
| 12 | Profil standard : Flux | `feat(golden): add Flux to the standard profile` | `install.yaml` vendoré, quatre contrôleurs, options de verrouillage, liaison suspendue ; ghcr.io par le miroir ; images de Flux dans l'inventaire du scan | S09, S10 (partie Flux), S28, E14, E15, E10 (standard), E25 à E27 (standard) | 10, 18 |
| 13 | Couche GCP : OpenTofu | `feat(golden): write the GCP layer in OpenTofu` | Racine sans Memorystore (étape 20), verrou multi-plateformes, politiques conftest, Trivy | S14, S15, S17 | 1 ; provider à partir du 2026-11-24 |
| 14 | Couche GCP : manifests | `feat(golden): add the GCP Kubernetes layer` | SecretSync de `db-auth`, RootSync, classe de Gateway, `requests`, règle d'admission ; parité complète ; Config Sync libre sur kind | S07, S08, S16, E16 ; partie `RootSync` de S10 (écart 5 de tasks.md) | 9, 13 |
| 15 | Keycloak | `feat(golden): add Keycloak to the standard profile` | Couche, Secrets, registre au miroir, images à l'inventaire, T2 standard, seuil mémoire | E10 (standard), E14, E25 à E27 (standard), contrôles fixés par l'ADR-013 | 12, ADR-013 |
| 16 | Mailpit | `feat(golden): add Mailpit to the standard profile` | Idem | E10 (standard), E14, E25 à E27 (standard), contrôles fixés par l'ADR-014 | 12, ADR-014 |
| 17 | Mesures et démo | `docs(golden): measure the first standard start` | Protocole et rapport de démo, temps et volume, mémoire du lite | D01 à D05 | 11, 14, 15, 16, 18, 19, 20 |
| 18 | SBOM et scan des images | Première PR : `ci(golden): scan the pulled images`. Seconde PR : `ci(golden): scan the images and keep their SBOM` | Première PR : seuil, fichiers d'exceptions, politique Rego de décision et ses rapports d'exemple, Trivy figé par SHA-256, scan des images déjà connues (nœud, miroir, Envoy Gateway et son proxy, Postgres). Seconde PR : relevé des images en marche, SBOM des images construites en artefact, scan dans `e2e-lite` ; jobs ajoutés aux contrôles requis | S25, S26, S27, U03, E27 sur les images tirées (première PR) ; E25, E26, E27 complet (seconde PR) | 7 pour la première PR, 9 pour la seconde |
| 19 | Couche cache locale | `feat(golden): add the local cache layer` | Image et forme fixées par l'ADR-015, Secret `cache-auth` créé par la tâche des Secrets, mot de passe sans argument, client concret de l'API, registre au miroir si ce n'est pas docker.io, image à l'inventaire | S11, E13, E04 et E05 étendus à `cache-auth` | 3, 8, ADR-015 |
| 20 | Couche GCP : Memorystore | `feat(golden): add Memorystore to the GCP layer` | Ressource Memorystore et authentification selon l'ADR-015, producteur `gcp` de `cache-auth`, politiques conftest | S14, S15, S07 (`cache-auth`) | 13, 14, ADR-015 |

Parallélisme : les étapes 3, 4, 5 et 13 partent toutes de l'étape 1. L'étape 13 ne touche aucun fichier de `local/`, et peut avancer pendant que les étapes 6 à 11 occupent le cluster de la CI. S24 (signature d'Envoy Gateway) entre dès que [SECU] fournit la commande vérifiée, en PR à part.

Sans l'ADR-015, avancent les étapes 1 à 8, 13 et la première PR de l'étape 18. Attendent l'ADR-015 : les étapes 19 et 20, puis l'étape 9 et tout ce qui en dépend (10, 11, 12, 14, 15, 16, 17 et la seconde PR de 18). L'étape 6, cluster et miroir, n'a aucun fichier du cache : la liste des registres du miroir porte déjà docker.io pour Postgres, et l'étape 19 y ajoute le registre du cache s'il diffère (research RS-11).

## Matrice de validation (principe I)

### Contrôles

Préfixes : S statique, sans cluster, en pre-commit ou en CI ; P contrôle préalable, par binaires simulés ; U test unitaire ; E test sur kind, en CI amd64 et sur le poste ; X conventions dans une copie autonome ; D mesure ou démo de la gate. Chaque contrôle nomme en cas d'échec la condition ou l'exigence qu'il porte (FR-012).

| ID | Contrôle |
| --- | --- |
| S01 | Toute image des rendus (lite, standard, gcp) et des Dockerfile porte un condensat ; seules les images sous `saas-b2b.invalid`, construites par `task up`, en sont exemptées |
| S02 | Chaque fichier de `local/vendor/` a son SHA-256 dans `SHA256SUMS`, vérifié avant application ; aucune application depuis une URL |
| S03 | Aucun objet `Secret` ni champ `secretGenerator` versionné |
| S04 | Taskfile : tâches qui manipulent un secret en `silent: true`, sans heredoc, sans `kubectl apply` de Secret, sans valeur dans une variable ; inventaire des commandes qui créent ou retirent un conteneur, un réseau ou un volume ; construction, chargement et application définis une seule fois |
| S05 | Configuration kind : `apiServerAddress` et chaque `listenAddress` à 127.0.0.1, image de nœud par condensat, mineure égale à `platform.yaml` ; ports de l'hôte identiques dans `local/kind/cluster.yaml` et dans les tâches (écart 10 de tasks.md) |
| S06 | Couche commune rendue : aucun groupe `gateway.envoyproxy.io`, `configsync.gke.io`, `*.toolkit.fluxcd.io`, `argoproj.io`, aucune annotation ni étiquette de moteur, aucune chaîne `${`, aucun objet propre à un fournisseur |
| S07 | Parité : la couche commune rendue seule se retrouve à l'identique dans le rendu `local` et dans le rendu `gcp`, aux seuls champs permis près (`gatewayClassName`) ; une seule Gateway ; mêmes références aux Secrets et à `app-config` |
| S08 | Couche commune valide contre le schéma de la version de Gateway API que sert GKE ; manifests valides contre leurs schémas |
| S09 | Chaque overlay rendu avec la version de Kustomize de Flux et avec celle de Config Sync donne le même résultat |
| S10 | Objets de liaison : `serviceAccountName` sur chaque `Kustomization`, options de verrouillage des contrôleurs de Flux, `roleRefs` et `sourceFormat: unstructured` sur le `RootSync`, export des métriques coupé, aucun `cluster-admin`, aucun `auth: token` |
| S11 | Cache (moteur de l'ADR-015) : mot de passe jamais dans `command` ni `args` |
| S12 | Postgres : UID 999, `runAsNonRoot`, capacités retirées, `seccompProfile`, aucun jeton monté, fichiers `_FILE`, `scram-sha-256`, aucune méthode `trust` ; le Secret du superutilisateur absent des manifests de l'application |
| S13 | Miroir : `hosts.toml` en capacité `pull` seule, configuration zot réduite à `sync`, aucun identifiant, fichiers dérivés de la liste unique des registres, lancement sur `kind` sans `-p`, stockage hors de l'arborescence |
| S14 | `tofu init -lockfile=readonly` puis `tofu validate`, sans backend distant ni identifiant |
| S15 | conftest sur le HCL : conditions 1 à 9 de l'ADR-008, condition 2 de l'ADR-007, version figée de Config Sync ; Trivy sur le HCL, échecs corrigés ou justifiés par écrit |
| S16 | Manifests `gcp` : `requests` sur chaque pod, règle d'admission présente |
| S17 | Workflows : aucune commande `tofu plan`, `apply` ni `destroy`, aucun identifiant cloud, aucun plan publié, actions figées par SHA, ni `pull_request_target` ni `workflow_run`, aucune permission à `write` (sauf les trois de `release-please.yml`), aucun téléchargement exécuté par un tube (écart 171) |
| S18 | README : prérequis avec version, licence et date, moteur libre d'abord, écarts PC et cloud, secrets locaux en clair, mémoire par profil, installation de kind vérifiée contre le SHA-256 du catalogue |
| S19 | Chaque appel à `kubectl` des tâches passe par le kubeconfig du projet et le contexte du cluster local ; `port-forward` seulement avec `--address 127.0.0.1` |
| S20 | L'API n'expose que les routes de [contracts/http-api.md](contracts/http-api.md) ; le front, que ses écrans |
| S21 | Mineure Kubernetes et majeure Postgres identiques dans `platform.yaml`, la configuration kind, l'image Postgres et la couche OpenTofu |
| S22 | Charts d'Envoy Gateway rendus : toute CRD de `gateway.networking.k8s.io` vient du `standard-install.yaml` vérifié ; réglages `crds.*` et image du contrôleur conformes à l'ADR-005 |
| S23 | Renovate : 7 jours, exception de sécurité, aucune autre majeure pour `postgres`, kubectl sur la mineure de `platform.yaml`, paire kind et image de nœud, paire chart et condensat d'Envoy Gateway ; relecture [SECU] |
| S24 | Signature cosign du contrôleur d'Envoy Gateway, en attente de la commande vérifiée par [SECU] |
| S25 | Inventaire des images de chaque profil livré : calculé depuis les rendus, les fichiers vendorés, la configuration kind et le miroir, plus la liste versionnée des images qu'aucun fichier ne nomme ; chaque entrée de cette liste porte un condensat (research RS-24) |
| S26 | Politique du scan : seuil écrit une seule fois dans le dépôt et lu par la tâche ; Trivy installé depuis la release, SHA-256 versionné et vérifié, version au moins 0.71.1 ; aucune action `aquasecurity/trivy-action` ni `aquasecurity/setup-trivy` ; aucune option `--skip-db-update` ni `--ignore-unfixed` ; aucune source de base autre que celles par défaut, hors du cas de E27 qui vise une adresse sous `.invalid` (CVE-2026-55092) ; aucun cache de la base entre deux exécutions ; jobs du scan parmi les contrôles requis de `.github/rulesets/main.json` |
| S27 | Fichiers d'exceptions : chaque entrée nomme la vulnérabilité et l'image, porte sa justification, sa date d'écriture et sa date d'échéance ; les entrées échues ou incomplètes sont listées en sortie |
| S28 | Flux en profil standard : `spec.suspend: true` sur chaque `Kustomization` de `local/gitops/`, et aucun objet source livré, tant que la question 1 de l'ADR-010 reste ouverte (research RS-14) |
| S29 | Registres des gestionnaires de paquets : dans tout `.npmrc`, `registry` et `@scope:registry` valent exactement `https://registry.npmjs.org/` et aucune clé d'authentification (`_auth`, `_authToken`, `_password`, `username`, `email`, seules ou préfixées par `//hôte/:`) ; dans tout `nuget.config`, `packageSources` commence par `<clear />`, ne contient que `https://api.nuget.org/v3/index.json`, et aucune section `packageSourceCredentials`. Renovate lit ces fichiers pour chercher les versions : un autre hôte détournerait ses recherches (relecture [SECU] de la PR #61) |
| S30 | Deployments et Services de l'API et du front dans la couche commune : profil `restricted` avec `readOnlyRootFilesystem`, `emptyDir` borné, `requests` et limite de mémoire, sondes sur `/api/readyz`, `/api/healthz` et `/`, Secrets montés en fichiers et jamais lus par `secretKeyRef` ni `envFrom`, étiquette `app.kubernetes.io/name: api` que les NetworkPolicy admettent, routes qui atteignent leurs Services (écart 148) |
| S32 | CI du projet généré : jobs `check`, `unit`, `e2e-lite` (`PROFILE=lite task test:e2e`, 45 minutes) et `scan-images`, kind et kubectl installés par `tests/tools/install.sh` avec somme vérifiée, aucun appel à `scripts/ci/` ni à `catalog/`, `persist-credentials: false`, aucune permission propre au job ; une seule source par version (kind dans `preflight-checks.sh`, kubectl dans `install.sh` sur la mineure de `platform.yaml`) et leurs sommes dans `SHA256SUMS`, aucun `continue-on-error` ni `if:` de job, somme de kind du catalogue égale à celle de `SHA256SUMS` dans CELIAN, garde de plate-forme de `install.sh` avant `mkdir` (écarts 26, 40 et 171 à 175) |
| P01 | kind d'une autre version, kubectl hors de la plage, Docker Engine sous 28.0.0 sur Linux : refus avec la version attendue |
| P02 | Moteur absent ou arrêté : message clair, rien de créé ; contexte Docker hors d'un socket unix local, et moteur muet au-delà de 10 s, refusés (écart 18 de tasks.md) |
| P03 | Mémoire déclarée : profil choisi et annoncé ; sous le lite, refus avec la mémoire qui manque |
| P04 | Port de l'hôte déjà pris : arrêt avant toute création, port nommé ; sonde indécidable refusée ; vraie sonde jouée sur le port 1, fermé (écart 18 de tasks.md) |
| P05 | Kubeconfig de l'utilisateur pointé sur un autre contexte : ignoré |
| P06 | Le miroir ne démarre pas sans la configuration du projet |
| U01 | API : santé, prêt, validation des notes, lecture par le cache et provenance, réponses d'erreur |
| U02 | Front : rendu, appels relatifs, erreurs affichées par champ, états de chargement |
| U03 | Politique de décision du scan, sur des rapports d'exemple et une date fixée : faille au seuil sans exception, refus qui nomme l'image et la vulnérabilité ; exception complète et non échue, passage ; exception échue, incomplète ou visant une autre image, refus ; faille sous le seuil, passage |
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
| E13 | Le cache refuse une commande sans authentification |
| E14 | Profil lite : aucun contrôleur de Flux ; profil standard : Flux et les couches entrées |
| E15 | Flux : le compte de service de la liaison d'un environnement n'a aucun droit d'écriture dans le namespace d'un autre, vérifié sans réactiver la liaison suspendue (research RS-14) |
| E16 | Couche `gcp` sur kind, Config Sync libre en version figée, runner x64 : liaison, rendu, droits de `roleRefs` |
| E17 | Durée de chaque étape et durée totale affichées ; taille du volume du miroir affichée |
| E18 | Démarrage à chaud sous 90 s |
| E19 | Kubeconfig hors du dépôt ou ignoré par Git |
| E20 | Volume du miroir hors de l'arborescence ; après purge et `task up` en ligne, il ne contient que les condensats du projet |
| E21 | Volume de la base présent sans ses Secrets : `task up` s'arrête avec son message |
| E22 | `task down` ne retire jamais un conteneur étranger au projet, même de nom voisin |
| E23 | Miroir sous UID non root, sans capacités : essai, résultat consigné pour [SECU] |
| E24 | Kubeconfig leurre en variable d'environnement : `task up` réussit et ne le modifie pas |
| E25 | Après `task up` dans chaque profil livré : l'image résolue de chaque conteneur en marche, dans le cluster (conteneurs d'initialisation compris) et sur le moteur, figure dans l'inventaire scanné ; échec qui nomme toute image absente |
| E26 | Un SBOM CycloneDX JSON par image construite, non vide, gardé en artefact de l'exécution ; échec qui nomme l'image sans SBOM |
| E27 | Scan de l'inventaire du profil, base téléchargée dans l'exécution : échec qui nomme l'image et la vulnérabilité au seuil sans exception valide ; avec une source de base qui ne résout pas, échec qui le dit, jamais de passage au vert |
| E28 | Premier démarrage sans registre joignable, miroir vide : `task up` échoue dans un délai borné, nomme le registre et dit que le premier démarrage demande le réseau ; registre lent ou qui limite : échec borné qui le nomme (cas limite de la spec, contrat task-cli ; écart 4 de tasks.md, T126 et T127) |
| X01 | Copie du golden repo dans un dépôt Git neuf : ses hooks passent, son commitlint refuse un message non conforme, actionlint passe sur ses workflows, ses actions sont figées par SHA, gitleaks passe sur son historique |
| D01 | Poste propre, personne qui ne connaît pas le dépôt : API et front qui répondent après une commande, à chaque essai |
| D02 | Premier démarrage du profil standard : durée et volume mesurés, rapportés aux 900 s et au débit nécessaire |
| D03 | Mémoire du profil lite face à un portable de 8 Gio |
| D04 | Même parcours sur un poste arm64 |
| D05 | T1 et T2 sur un poste réellement coupé du réseau, construction comprise (suite de l'ADR-011, Lucas) |

### Exigences

| Exigence | Contrôles |
| --- | --- |
| FR-001 Démarrage en une commande | E01, P02, P04, E28 |
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
| FR-016 Démarrage sans registre | E10, E28 |
| FR-017 Base selon BENCH-011 | E12, S12, conditions de l'ADR-012 ci-dessous |
| FR-018 README | S18 |
| FR-019 Cluster local ciblé explicitement | S19, P05, E24 |
| FR-020 SBOM de chaque image construite, gardé en artefact | E26 |
| FR-021 Scan de l'inventaire des images ; relevé des images en marche | S25, E25, E27 |
| FR-022 Seuil écrit dans le dépôt, exceptions datées, fusion bloquée | S26, S27, U03, E27 ; jobs du scan parmi les contrôles requis du ruleset de `main` |

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
| SC-010 0 image construite sans SBOM, 0 image en marche hors du scan, 0 fusion au seuil sans exception valide | E26, E25, E27, S26 | CI |

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
| ADR-006 | 2 Mot de passe de Valkey, appliqué au moteur de l'ADR-015 | S11, E13 | 19 |
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
| ADR-010 | Question 3, un seul acteur sur les objets de l'application : liaison suspendue, décision de Lucas du 2026-11-21 | S28, E07 | 12 |
| ADR-011 | 1 Capacité `pull` seule | S13, E10 | 6, 10 |
| ADR-011 | 2 Réseau `kind` seul | S13, E03 | 6, 7 |
| ADR-011 | 3 Docker Engine 28.0.0 sous Linux | P01, S18 | 5, 11 |
| ADR-011 | 4 Aucune référence par tag | S01, E11 | 9 |
| ADR-011 | 5 Règle de purge | E20, E17 | 10 |
| ADR-011 | 6 UID non root | E23 | 10 |
| ADR-011 | 7 Configuration montée, `sync` seule | S13, P06 | 6 |
| ADR-011 | 8 Image figée, suivie et scannée | S01, S23 ; E27 pour le scan, SBOM sans objet (image tirée, non construite) | 6, 18 |
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
| ADR-012 | 9 Un seul namespace, retenu par Lucas le 2026-11-21 | E08, E12 | 8, 9 |
| ADR-012 | 10 Test des secrets étendu | E04 | 8 |
| ADR-012 | 11 Image par le miroir | E10 | 10 |

## Décisions prises depuis la première version

Les questions ci-dessous sortent du tableau des points ouverts. Chacune garde sa date et son auteur.

| Décision | Auteur | Date | Effet sur le plan |
| --- | --- | --- | --- |
| ADR-011 et ADR-012 acceptés, avec les réponses aux questions 1 à 6 de l'ADR-011 et 1 et 2 de l'ADR-012 | Lucas | 2026-11-21 | Research RS-12 et RS-13 ; les étapes 6 et 8 ne les attendent plus |
| SBOM et scan des images dans la spec (récit 7, FR-020 à FR-022, SC-010) ; le plan fixe l'outil, le format et le seuil | Lucas | 2026-11-21 | Trivy pour les deux, CycloneDX JSON, seuil `HIGH`, exceptions par couche (research RS-22 à RS-24) ; étape 18 ; S25 à S27, U03, E25 à E27 |
| Moteur du cache par un benchmark court, BENCH-014, puis l'ADR-015 ; aucune image figée d'ici là | Lucas | 2026-11-21 | Research RS-11 ; cache retiré de l'étape 8 ; étapes 19 et 20 ; l'étape 9 dépend de l'étape 19 |
| Flux livré dans le profil standard avec sa liaison suspendue, `task reload` seul maître des objets de l'application, jusqu'à ce que Lucas tranche ce que lit Flux | Lucas | 2026-11-21 | Research RS-14 ; S28 ; E15 vérifie les droits sans réconciliation. La question 1 de l'ADR-010 reste ouverte et ne bloque aucune étape |
| Aucune authentification de l'exemple en local ; elle arrive avec l'ADR-013. Aucun déploiement réel sur GCP sans authentification | DSI | 2026-11-21 | Research RS-25 ; contrat de l'API ; l'ADR-013 demandera un amendement de FR-009 |
| CI du golden repo dans CELIAN seulement ; un dépôt miroir viendra avec le générateur, hors de ce plan | DSI | 2026-11-21 | Research RS-17 ; jobs bloquants ajoutés aux contrôles requis de `main` |
| Trivy seul pour le SBOM et le scan ; l'écart avec le PRD et le brief, qui nomment Syft, est confirmé ; reporté dans le PRD (US-009) le 2026-11-25 | Lucas | 2026-11-23 | Research RS-22 ; étape 18 |
| Si BENCH-014 tarde, le profil lite attend l'ADR-015 : aucune image de cache provisoire | Lucas | 2026-11-23 | Research RS-11 ; les étapes 1 à 8 et la première PR de l'étape 18 avancent, les étapes 9 à 11 attendent l'étape 19 |

## Ce qui n'est pas décidé ou pas mesuré

| Point | État | Porteur | Ce qui le lèvera | Étape bloquée |
| --- | --- | --- | --- | --- |
| Moteur du cache, local et Memorystore, et son authentification | BENCH-014 ouvert le 2026-11-21, lectures en cours, mesures après BENCH-012 et BENCH-013 | [BENCH], [ARCHI] | ADR-015 : image, forme, registre, clés de `cache-auth`, variante et authentification de Memorystore | 19 et 20, donc 9 et la suite du profil lite |
| Keycloak et Mailpit | BENCH-012 et BENCH-013 en cours | [BENCH], [ARCHI] | ADR-013 et ADR-014 ; image, version, registre, Secrets, mémoire | 15 et 16 |
| Flux à quatre contrôleurs | ouvert (ADR-010, question 4) | [OPS] | Décision d'[OPS] ; le plan suppose quatre contrôleurs, comme R-04 | 12 |
| Échéance maximale d'une exception, faille `UNKNOWN` | 90 jours proposés ; `UNKNOWN` non bloquant (research RS-23) | [SECU] | Relecture de la première PR de l'étape 18 | 18 |
| Nombre de failles `HIGH` et `CRITICAL` sur les images de la stack | non mesuré | [SECU], [DEV] | Premier passage du scan, première PR de l'étape 18 | 18 |
| Certificat de l'écouteur HTTPS en local | non décidé | [SECU], [DEV] | Méthode qui crée la clé sans fichier ni argument (research RS-10) | 7 |
| TLS vers la base et le cache | état du serveur local non lu ; Cloud SQL en `ENCRYPTED_ONLY`, Memorystore en TLS | [DEV], [SECU] | Lecture des documentations, choix du mode de connexion, écart listé au README | 8 pour la base, 19 pour le cache |
| Nom sous `.invalid` accepté par `kind load` et le kubelet | non essayé | [OPS] | Essai à l'étape 9, repli décrit dans research RS-07 | 9 |
| Plusieurs amonts dans zot | montages a et b non essayés | [OPS] | Premier montage qui passe T2 avec ghcr.io | 12, ou 19 si le cache vient d'un autre registre que docker.io |
| T2 en capacité `pull` seule | non mesuré | [QA], [OPS] | E10 ; un échec rouvre l'ADR-011 | 10 |
| Profil `restricted` pour l'API et le front | non vérifié | [DEV] | E12 ; image nginx non root à choisir (R-05) | 8, 9 |
| Versions du front, des frameworks de test, de Task, conftest, kubeconform, cosign, du provider `random` | à vérifier | [DEV] | Lecture datée de la source officielle avant usage (research RS-05, RS-18) | 2 à 19 |
| Points techniques du scan : code de sortie de Trivy sans base, lecture des images construites, rapport JSON, données de conftest, images préchargées du nœud | à vérifier | [DEV], [SECU], [OPS] | Lectures de la documentation de la version retenue (research RS-22 à RS-24) | 18 |
| `Kustomization` suspendue sans objet source | à vérifier sur la documentation de Flux 2.10 | [DEV] | Lecture, puis repli décrit dans research RS-14 | 12 |
| Attributs OpenTofu des activations GKE | non vérifiés (ADR-005, 007, 010) | [OPS] | Documentation du provider `google` | 13 |
| Validation OpenTofu hors ligne avec chiffrement et verrou multi-plateformes | non vérifiée (ADR-008, question 5) | [OPS] | Essai sur la racine du golden repo | 13 |
| Alerte budget | tranchée par le DSI le 2026-11-25 : racine séparée `gcp/budget/` (T110, RS-26) | [OPS], [SECU] | Racine séparée ou alias de provider | 13 |
| Signature cosign d'Envoy Gateway | emplacement non trouvé | [SECU] | Commande vérifiée sur la documentation de cosign ; un échec rouvre l'ADR-005 | S24 |
| Débit visé du critère des 15 minutes | à fixer après le golden repo | [FINOPS] | Mesure D02 | 17 |
| Méthode de mesure du volume en démo | à reprendre des scripts de BENCH | [BENCH] | Protocole de l'étape 17 | 17 |
| Redémarrage du nœud et données de Postgres | non mesuré, mesure autorisée | [BENCH] | Série `NODE_RESTART=1` après BENCH-012 et BENCH-013 | aucune ; le README ne promet rien d'ici là |
| Essais sur GKE | hors phase 2 | Lucas, [FINOPS] | GATE 2, accord et budget | aucune en phase 2 |

## Risques suivis par ce plan

- R-04 : le volume du premier `task up` standard dépasse déjà le budget à 10 Mbit/s avant Keycloak et Mailpit ; D02 le mesure, [FINOPS] fixe le débit visé.
- R-25 et R-34 : le miroir n'est prouvé que pour docker.io ; ghcr.io (Flux) et les registres du cache, de Keycloak et de Mailpit passent par E10 à chaque couche. L'image du miroir entre au scan (E27), comme le veut la condition 8 de l'ADR-011.
- R-30 : le Taskfile grossit à chaque étape ; S04 et l'inventaire relu par [SECU] le bornent.
- R-35 : Postgres écrit à la main ; S12 et E12 tiennent ses conditions.
- CVE-2026-97054 dans Envoy Gateway 1.10.0 : le scan au seuil `HIGH` la relève. Sans release 1.10.x corrigée à l'étape 18, [SECU] écrit la première exception, datée, avec la justification de l'ADR-005.
- Chaîne de Trivy : compromission de mars 2026 (CVE-2026-33634) et CVE-2026-55092, corrigée en 0.71.1. Trivy entre par un binaire figé par SHA-256, signature vérifiée par [SECU] à chaque montée, jamais par ses actions GitHub ; sa base vient des registres par défaut seulement (S26).
- Nombre d'exceptions non mesuré : FR-022 n'écarte pas les failles sans correctif, et les images de base des images officielles peuvent en porter au seuil. Chacune demande une exception écrite et datée. La première PR de l'étape 18 le mesure ; si le nombre dépasse ce que [SECU] peut justifier une par une, le seuil ou la spec se rediscutent avec Lucas.
- Limite de Docker Hub en CI : chaque job neuf tire de nouveau ses images, et le scan relit chaque image tirée depuis son registre. Le cache d'images de la CI demande une relecture [SECU] (ADR-011, condition 9).
- Calendrier : le profil lite de bout en bout (étape 9) attend l'ADR-015, donc BENCH-014, dont les mesures passent après BENCH-012 et BENCH-013.
- Exemple sans authentification : sans risque en boucle locale ; la règle du DSI interdit tout déploiement réel sur GCP sans elle (research RS-25).
- Hors spec 001 : la signature des images et le contrôle d'admission qui refuse les images non signées (Kyverno) arrivent en phase 4 ; Q8 (où publier et signer avant que GCP existe) reste ouverte. FR-020 n'en dépend pas.

## Complexity Tracking

Aucune violation de la constitution. La dérogation de l'ADR-012 à ENF-03, exigence du PRD et non principe, n'a pas d'effet dans le golden repo : aucun profil n'y embarque Kyverno. Elle se relit au plus tard le 2027-05-20 (réponse de Lucas du 2026-11-21).
