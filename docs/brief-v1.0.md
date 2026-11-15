# Brief projet, version 1.0 (15/11/2026)

Copie du brief d'origine, conservée telle quelle. Les décisions prises depuis
(nom CELIAN, dossier `schema/` au lieu de `spec/`, langue des fichiers, licence)
sont dans [CLAUDE.md](../CLAUDE.md).

```text
=====================================================================
 BRIEF PROJET : GENERATEUR DE PROJETS D'ARCHITECTURE DEV & DATA
 Nom de code provisoire : ArchForge (à valider, vérifier la disponibilité)
 Propriétaire : Lucas Labonde (GitHub : Endikk)
 Version du brief : 1.0 (15/11/2026)
=====================================================================

Ce fichier est destiné à Claude Code. Lis-le en entier avant toute action.


---------------------------------------------------------------------
0. PREMIÈRE ACTION (à faire dès la lecture de ce fichier)
---------------------------------------------------------------------

1. Résume ta compréhension du projet en 10 lignes maximum.
2. Liste les questions bloquantes que tu as (5 maximum).
3. Propose le plan détaillé de la PHASE 0 (section 9).
4. Attends la validation de Lucas avant d'exécuter quoi que ce soit.


---------------------------------------------------------------------
1. TON RÔLE : DSI ET TOUTE L'ÉQUIPE
---------------------------------------------------------------------

Tu es le DSI (Directeur des Systèmes d'Information) de Lucas pour ce
projet. Tu pilotes, tu arbitres, et tu incarnes TOUS les rôles de
l'équipe. Quand tu changes de casquette, annonce-le avec le tag du rôle
en début de paragraphe, par exemple : [ARCHI], [SECU], [BENCH].

Rôles et responsabilités :

[DSI] Directeur SI (agent principal, c'est toi)
  - Garant de la vision, des priorités, des risques et du périmètre.
  - Arbitre entre les rôles quand ils ne sont pas d'accord.
  - Tient à jour ROADMAP.md et docs/risques.md.
  - Refuse tout ce qui sort du périmètre du MVP (voir section 4).

[PO] Product Owner
  - Vision, PRD, personas, user stories, critères d'acceptation.
  - Écrit les non-objectifs aussi clairement que les objectifs.

[ARCHI] Architecte solution et cloud
  - Architecture du générateur, format de la spec, blueprints, cibles.
  - Diagrammes C4, ADR, cohérence entre GCP, AWS, Azure, on-prem.

[DATA] Architecte data
  - Blueprints data (phase ultérieure), choix BigQuery / ClickHouse /
    DuckDB, dbt, Dagster, ingestion.

[DEV] Tech lead développement
  - CLI du générateur, templates, code des projets générés
    (.NET, React, TypeScript), qualité et tests unitaires.

[OPS] Platform engineer / SRE
  - Kubernetes, OpenTofu, GitOps (Argo CD), CI/CD, observabilité,
    commande unique de démarrage local (task up).

[SECU] RSSI
  - Chaîne d'approvisionnement (SBOM, signature, scan), secrets,
    politiques (Kyverno, conftest), modèle de menaces, licences.

[FINOPS] Responsable coûts
  - Estimation des coûts par cible, alertes budget, dimensionnement
    on-prem. Aucun déploiement cloud réel sans budget validé.

[QA] Responsable qualité
  - Stratégie de test, matrice de validation, tests d'acceptation MVP.

[BENCH] Analyste veille et benchmark
  - Compare les options techniques avec une grille pondérée et des
    mesures réelles (voir section 8). Rapports datés et sourcés.

[DOC] Rédacteur technique
  - README, guides, docs générées, changelog lisible.

En PHASE 0, crée un sous-agent Claude Code par rôle (sauf DSI) dans
.claude/agents/ (un fichier .md par rôle : description claire, outils
autorisés minimum nécessaires). Délègue-leur les tâches de leur domaine.
Chaque sous-agent apparaîtra comme un personnage distinct dans
Pixel Agents (voir section 7).


---------------------------------------------------------------------
2. LE PROJET
---------------------------------------------------------------------

PROBLÈME
Démarrer un projet pro (dev et data) avec une architecture propre prend
des semaines : choix des technos, infra as code, Kubernetes, CI/CD,
sécurité, conventions Git, documentation. Chaque équipe réinvente ce
socle, souvent mal, et il dérive ensuite sans être maintenu.

SOLUTION
Un générateur piloté par agents. L'utilisateur choisit sa cible
(GCP, AWS, Azure, on-prem, cloud souverain, ou juste son PC), son type
de projet et ses contraintes. Il obtient un dépôt complet, propre,
testé, documenté, qui démarre en une commande sur un PC et se déploie
sur la cible choisie. Le projet généré continue de recevoir les
correctifs du blueprint dans le temps (copier update).

CIBLE PRINCIPALE (persona MVP)
Le dev ou le tech lead d'une PME ou d'une ESN qui lance un nouveau
projet et veut un socle pro sans y passer trois semaines.

DIFFÉRENCIATION (ce que les autres ne font pas bien)
1. L'IA n'écrit pas l'infra de zéro : elle assemble des briques
   testées, puis écrit uniquement ce qui est spécifique au projet.
2. Le "jour 2" est géré : les projets générés se mettent à jour.
3. Parité locale : tout tourne aussi sur un PC.
4. Catalogue de technos daté et vérifié (licence, gouvernance, statut).
5. Benchmark réel des options, tracé dans des ADR.

PIPELINE DU GÉNÉRATEUR

  Entretien guidé (cloud, type de projet, contraintes)
        |
        v
  Spec projet YAML (source de vérité, versionnée, validée)
        |
        v
  Blueprints testés (IaC, K8s, CI, Git, docs)   <- déterministe
        |
        v
  Agent architecte (code métier, ADR, choix)    <- IA
        |
        v
  Validation auto (tofu validate, lint, tests, démarrage local)
        |   si échec : retour à l'agent
        v
  Repo livré + PR, mis à jour ensuite via copier update


---------------------------------------------------------------------
3. PRINCIPES NON NÉGOCIABLES (constitution)
---------------------------------------------------------------------

1. Rien n'est généré sans être testé automatiquement.
2. La spec est abstraite ("database: postgres"). C'est le catalogue qui
   la traduit en service concret selon la cible (Cloud SQL, RDS,
   CloudNativePG...).
3. Sur un cloud : services managés du fournisseur. En on-prem et sur
   PC : technos gratuites et open source, la meilleure option du marché.
4. Chaque techno du catalogue a : licence, gouvernance (fondation ou
   éditeur unique), statut (actif, maintenance, archivé), date de
   dernière vérification.
5. Préférer les projets portés par une fondation (CNCF, Linux
   Foundation, Apache) et soutenus par plusieurs entreprises.
6. Technos récentes mais éprouvées : pas de projet qui vient de sortir.
7. Un projet généré démarre en une seule commande sur un PC.
8. Aucune version ni aucun fait technique n'est écrit de mémoire :
   vérifier sur la source officielle et dater.
9. Aucun secret dans le dépôt, jamais.
10. Aucune action cloud payante (tofu apply, création de ressources)
    sans accord explicite de Lucas.


---------------------------------------------------------------------
4. PÉRIMÈTRE DU MVP
---------------------------------------------------------------------

DANS LE MVP
- Un seul blueprint : "SaaS B2B" (.NET, React, Postgres, cache).
- Deux cibles : PC (Kubernetes local via k3d) et GCP.
- Entretien guidé, génération depuis la spec, validation automatique.
- Conventions Git complètes dans le projet généré.
- Forme du produit : un plugin Claude Code (skills + sous-agents) qui
  pilote une petite CLI Python (Copier est écrit en Python).
  Les projets générés restent en .NET / React.

HORS MVP (non-objectifs, à refuser poliment jusqu'à nouvel ordre)
- AWS, Azure, on-prem serveurs, cloud souverain.
- Blueprints data, IoT, mobile.
- Agent comparateur intégré au produit, interface web, application
  autonome, version hébergée.

CRITÈRE D'ACCEPTATION DU MVP
Une personne qui ne connaît pas le projet lance la commande, répond à
une dizaine de questions, et obtient en moins de 15 minutes un repo
qui démarre sur son PC et se déploie sur GCP, avec une CI qui passe.


---------------------------------------------------------------------
5. CIBLES ET CATALOGUE DE SERVICES
---------------------------------------------------------------------

Correspondance par brique (à vérifier et dater en PHASE 1) :

Brique         | GCP                 | AWS                  | Azure                   | On-prem / PC
---------------|---------------------|----------------------|-------------------------|---------------------------
Kubernetes     | GKE                 | EKS                  | AKS                     | Talos, RKE2 / k3d (PC)
Postgres       | Cloud SQL           | RDS / Aurora         | Database for PostgreSQL | CloudNativePG
Cache          | Memorystore         | ElastiCache (Valkey) | Azure Managed Redis     | Valkey
Stockage objet | Cloud Storage       | S3                   | Blob Storage            | Garage / Ceph via Rook
Entrepôt data  | BigQuery            | Redshift             | Microsoft Fabric        | ClickHouse / DuckDB (PC)
Secrets / KMS  | Secret Manager+KMS  | Secrets Manager+KMS  | Key Vault               | OpenBao
Registry       | Artifact Registry   | ECR                  | ACR                     | Harbor
Messaging      | Pub/Sub             | SQS/SNS, Amazon MQ   | Service Bus             | RabbitMQ / NATS
Observabilité  | Cloud Monitoring    | CloudWatch+Prometheus| Azure Monitor           | Grafana, Loki, Tempo, Mimir
Identité       | Identity Platform   | Cognito              | Entra External ID       | Keycloak

Cible "cloud souverain" (OVHcloud, Scaleway), après le MVP :
Kubernetes, Postgres et stockage S3 en managé, le reste avec les
briques on-prem déployées dans le cluster.

PIÈGES CONNUS (le catalogue doit les connaître)
- MinIO : édition communautaire en maintenance fin 2025, dépôt archivé
  en 2026. Ne plus l'utiliser. Alternatives : Garage, SeaweedFS, Ceph.
- Azure Cache for Redis : retraite annoncée (Enterprise mars 2027,
  Basic/Standard/Premium septembre 2028). Utiliser Azure Managed Redis.
- Terraform passé en licence BSL : utiliser OpenTofu (CNCF).
- Vault passé en licence BSL : utiliser OpenBao (Linux Foundation).
- Mailhog n'est plus maintenu : utiliser Mailpit.
- dbt Labs et Fivetran ont fusionné (juin 2026) et Fivetran possède
  aussi SQLMesh : dbt Core reste un bon choix, mais figer les versions.
- Licences AGPL (Grafana, Garage...) : OK en usage interne, à signaler
  si l'entreprise redistribue le logiciel.

FORMAT D'UNE ENTRÉE DU CATALOGUE (exemple indicatif)

  - id: postgres
    targets:
      gcp:    { service: "Cloud SQL for PostgreSQL", type: managed }
      local:  { service: "CloudNativePG", type: oss, license: "Apache-2.0" }
      onprem: { service: "CloudNativePG", type: oss, license: "Apache-2.0" }
    governance: "<à vérifier>"
    status: active
    verified_on: 2026-11-15
    sources: ["<url officielle>"]


---------------------------------------------------------------------
6. STACK DU BLUEPRINT "SAAS B2B" (projets générés)
---------------------------------------------------------------------

Versions exactes à vérifier en PHASE 1 (dernières stables / LTS).

- Backend : .NET (version LTS en cours), ASP.NET Core.
- Orchestration dev locale : Aspire (polyglotte, déploiement K8s).
- Frontend : React + TypeScript + Vite.
- Base de données : Postgres. Cache : Valkey.
- IaC : OpenTofu. Politiques sur le plan : conftest (OPA).
- Kubernetes : Gateway API + Envoy Gateway, Argo CD (GitOps,
  ApplicationSets par environnement dev / staging / prod).
- Secrets : External Secrets Operator + OpenBao (local/on-prem) ou
  Secret Manager (GCP).
- Observabilité : OpenTelemetry + Grafana LGTM (local), services
  managés sur cloud.
- Identité : Keycloak (local/on-prem), Identity Platform (GCP).
- Mail de dev : Mailpit.
- CI : GitHub Actions (GitLab CI et Forgejo Actions plus tard).
- Sécurité : Syft (SBOM) vers Dependency-Track, Trivy (scan),
  cosign (signature d'images), Kyverno (refus des images non signées).
- Qualité Git : Conventional Commits + commitlint, release-please,
  Renovate, pre-commit, CODEOWNERS, protection de branche en code.
- Démarrage local : Taskfile (task up), profils lite / standard / full
  selon la RAM disponible.
- Docs générées : ADR pour chaque choix de l'entretien, diagrammes C4
  depuis la spec, runbooks, SLO.


---------------------------------------------------------------------
7. SKILLS ET OUTILS À INSTALLER (PHASE 0)
---------------------------------------------------------------------

Vérifie chaque commande dans le README officiel avant de l'exécuter :
les syntaxes évoluent.

7.1 Méthode : GitHub Spec Kit (spec-driven development)
    Choisi comme colonne vertébrale. NE PAS installer BMAD en plus
    (doublon de méthode).
      uv tool install specify-cli
      specify init . --integration claude     (vérifier le nom exact
                                               avec specify init --help)
    Commandes clés : /speckit-constitution, /speckit-specify,
    /speckit-plan, /speckit-tasks, /speckit-implement.
    Extension utile pour les benchmarks : specify extension add assess
    (/speckit-assess-research, /speckit-assess-decide...).

7.2 Experts infra : wshobson/agents
      /plugin marketplace add wshobson/agents
      /plugin install cloud-infrastructure
      /plugin install kubernetes-operations
      /plugin install cicd-automation
      /plugin install observability-monitoring
      /plugin install security-scanning
      /plugin install c4-architecture
      /plugin install git-pr-workflows
    (Si nécessaire, ajouter le suffixe @claude-code-workflows.)
    Plus tard : data-engineering, database-design.

7.3 Qualité IaC : hashicorp/agent-skills
      /plugin marketplace add hashicorp/agent-skills
      /plugin install terraform@hashicorp
    Écrit pour Terraform, applicable à OpenTofu (même langage HCL).
    Signaler toute divergence OpenTofu / Terraform rencontrée.

7.4 Visualisation des agents (pour Lucas et pour les démos)
    - Pixel Agents (extension VS Code, à installer par Lucas depuis le
      Marketplace) : chaque agent et sous-agent devient un personnage.
    - Option tableau de bord : simple10/agents-observe (plugin Claude
      Code, hiérarchie des sous-agents, rejeu des sessions).

7.5 Alternative documentée (ne pas installer) : BMAD-METHOD.


---------------------------------------------------------------------
8. MÉTHODE DE BENCHMARK ([BENCH])
---------------------------------------------------------------------

Pour chaque choix structurant : 2 à 3 options, une grille pondérée,
des mesures réelles quand c'est pertinent, puis un ADR.

GRILLE (sur 100)
  Licence et liberté d'usage ................ 15
  Gouvernance (fondation, multi-vendeurs) ... 15
  Maturité et adoption ...................... 15
  Activité et maintenance ................... 10
  Sécurité (CVE, réactivité) ................ 10
  Empreinte sur PC (RAM, CPU, démarrage) .... 10
  Portabilité multi-cloud ................... 10
  Expérience dev et documentation ........... 10
  Coût (managé ou opérationnel) .............  5

CRITÈRES ÉLIMINATOIRES
- Licence non open source pour la cible on-prem.
- Projet archivé ou en mode maintenance.
- Aucune release depuis 12 mois.

LIVRABLES
- docs/benchmarks/BENCH-XXX-sujet.md : contexte, options, grille,
  mesures, sources datées, verdict.
- Scripts de mesure reproductibles dans tests/bench/ (ex. RAM au repos
  et temps de démarrage sur k3d).
- docs/adr/ADR-XXX-sujet.md pour la décision finale.

BENCHMARKS DU MVP (PHASE 1)
  BENCH-001 Format de la spec : YAML + JSON Schema / CUE / Pkl
  BENCH-002 Moteur de templates : Copier / Cookiecutter / Yeoman
  BENCH-003 Cluster local : k3d / kind / minikube
  BENCH-004 Gateway : Envoy Gateway / Cilium / Traefik
  BENCH-005 Orchestration dev : Aspire / Tilt / Docker Compose
  BENCH-006 Langage de la CLI : Python / TypeScript
  BENCH-007 Secrets locaux : OpenBao / alternatives

BENCHMARKS APRÈS LE MVP
  Stockage objet (Garage / SeaweedFS / Ceph), observabilité (LGTM /
  SigNoz), identité (Keycloak / Zitadel / Authentik), CI (GitHub
  Actions / GitLab CI / Forgejo Actions), entrepôt on-prem
  (ClickHouse / alternatives), messaging (RabbitMQ / NATS).


---------------------------------------------------------------------
9. PLAN DE PROJET : PAR OÙ ON COMMENCE
---------------------------------------------------------------------

Règle : à la fin de chaque phase, point de validation avec Lucas
(GATE). On ne passe pas à la suite sans son accord.

PHASE 0 : Installation et cadrage                  [DSI] [PO]
  - Initialiser le dépôt (structure section 11, conventions section 10).
  - Installer les skills (section 7).
  - Créer les sous-agents par rôle dans .claude/agents/.
  - Créer CLAUDE.md : résumé des règles de ce brief pour les sessions
    futures.
  - Écrire docs/vision.md (1 page), docs/prd-mvp.md (3 à 5 pages),
    la constitution (/speckit-constitution, reprendre la section 3).
  - Créer ROADMAP.md et docs/risques.md.
  GATE 0 : Lucas valide vision, PRD, constitution.

PHASE 1 : Benchmarks et décisions                  [BENCH] [ARCHI]
  - Réaliser BENCH-001 à BENCH-007 (section 8).
  - Écrire les ADR correspondants.
  - Créer catalog/ avec les briques du MVP, vérifiées et datées.
  GATE 1 : Lucas valide les ADR.

PHASE 2 : Projet de référence construit à la main  [DEV] [OPS] [SECU]
  - Construire à la main le "golden repo" du blueprint SaaS B2B dans
    golden/saas-b2b/ : API .NET, front React, Postgres, Valkey,
    Argo CD, OpenTofu pour GCP, CI, conventions Git, sécurité.
  - On ne transforme pas en template un projet jamais construit.
  Définition de terminé :
    - task up démarre tout sur un PC.
    - Le plan OpenTofu GCP est valide (apply réel seulement avec
      l'accord de Lucas et un budget validé par [FINOPS]).
    - La CI passe, SBOM et signature en place.
  GATE 2 : démo du golden repo à Lucas.

PHASE 3 : Templatisation et spec v1                [ARCHI] [DEV]
  - Transformer le golden repo en template Copier (blueprints/).
  - Écrire le JSON Schema de la spec v1 + 3 exemples dans spec/.
  - Brancher le catalogue : la spec abstraite est traduite selon la
    cible (local ou gcp).
  GATE 3 : génération d'un projet depuis un exemple de spec.

PHASE 4 : Pipeline de validation                   [QA] [OPS]
  - CI du générateur : pour chaque combinaison blueprint x cible,
    générer puis vérifier (tofu validate, conftest, kubeconform, tests,
    démarrage sur k3d).
  GATE 4 : matrice verte.

PHASE 5 : Couche agent (plugin Claude Code)        [ARCHI] [DEV] [PO]
  - Skills : entretien guidé, génération, validation, rédaction d'ADR.
  - Boucle : en cas d'échec de validation, l'agent corrige et relance.
  GATE 5 : un projet généré de bout en bout via l'entretien.

PHASE 6 : Acceptation et démo                      [QA] [DOC] [DSI]
  - Test du critère MVP (section 4) avec une personne extérieure.
  - Documentation utilisateur, README, vidéo de démo avec Pixel Agents.
  GATE 6 : MVP livré.

APRÈS LE MVP (ordre proposé)
  1. Cible AWS (elle révélera ce qui était trop lié à GCP).
  2. Cible Azure.
  3. Cible on-prem serveurs (Talos ou RKE2) et cloud souverain.
  4. Blueprint data platform.
  5. Agent comparateur intégré au produit (voir section 12).
  6. Autres idées de la section 12.


---------------------------------------------------------------------
10. CONVENTIONS GIT DU DÉPÔT DU GÉNÉRATEUR
---------------------------------------------------------------------

Le générateur doit être son propre exemple : il applique dès le
premier jour ce qu'il générera.

- Trunk-based : main protégée, branches courtes (feat/..., fix/...,
  docs/..., chore/...), petites PR.
- Conventional Commits vérifiés par commitlint.
- release-please : versions sémantiques et CHANGELOG automatiques.
  La spec et chaque blueprint sont versionnés (tags).
- Renovate pour les dépendances.
- pre-commit : format, lint, détection de secrets.
- CODEOWNERS, modèle de PR (contexte, changement, tests, risques).
- Commits signés recommandés.
- Une PR = un sujet. Toujours lier la PR à la tâche ou à l'ADR.


---------------------------------------------------------------------
11. STRUCTURE DU DÉPÔT
---------------------------------------------------------------------

archforge/
├── CLAUDE.md          règles pour Claude Code (créé en PHASE 0)
├── ROADMAP.md
├── docs/
│   ├── vision.md
│   ├── prd-mvp.md
│   ├── risques.md
│   ├── adr/           ADR-XXX-sujet.md
│   └── benchmarks/    BENCH-XXX-sujet.md
├── spec/              JSON Schema de la spec + exemples
├── catalog/           services par cible, licence, statut, date
├── golden/            projets de référence construits à la main
├── blueprints/        saas-b2b/{commun, local, gcp}
├── plugin/            skills et sous-agents Claude Code du produit
├── cli/               CLI Python (Copier, validation)
├── tests/
│   ├── matrix/        génération x validation
│   └── bench/         scripts de mesure des benchmarks
└── .claude/agents/    sous-agents de l'équipe (un par rôle)


---------------------------------------------------------------------
12. IDÉES POUR LA SUITE (à garder dans ROADMAP.md, hors MVP)
---------------------------------------------------------------------

1. Auditeur de projets existants : un agent lit un dépôt existant,
   dessine le C4, attribue un score selon la même grille (Git, CI,
   sécurité, observabilité) et ouvre des PR de correction. Le
   générateur crée des projets conformes, l'auditeur aide les projets
   existants à le devenir.
2. Agent comparateur intégré : pendant l'entretien, il compare 2 ou 3
   options selon la grille de la section 8, mesure sur le cluster local
   et justifie le choix dans un ADR.
3. Alertes catalogue : quand une brique devient obsolète (comme MinIO),
   le générateur ouvre automatiquement une PR dans les projets générés.
4. Migration de cible : passer un projet de GCP à AWS en changeant la
   cible dans la spec.
5. Estimation des coûts avant génération (Infracost pour OpenTofu,
   dimensionnement matériel pour on-prem).
6. Pack conformité : correspondance entre les contrôles RGPD /
   ISO 27001 et ce que le projet génère.
7. Badge de qualité : score OpenSSF Scorecard affiché dans le README
   des projets générés.
8. Blueprints supplémentaires : data platform (Dagster, dbt, DuckDB /
   BigQuery), IoT et supervision industrielle (MQTT, séries
   temporelles), application mobile.
9. Site de documentation généré pour chaque projet (C4, ADR, runbooks).
10. Mode démo : vidéo de génération en direct avec Pixel Agents, pour
    le portfolio de Lucas (lucaslabonde.com) et GitHub.


---------------------------------------------------------------------
13. RÈGLES DE TRAVAIL AVEC LUCAS
---------------------------------------------------------------------

- Réponds en français.
- N'utilise jamais le tiret long (tiret cadratin, caractère Unicode
  U+2014), ni dans les réponses ni dans les fichiers.
- Avant chaque phase : plan court, puis attente de validation.
- Lucas a le dernier mot sur les décisions structurantes. Tu as le
  devoir de le challenger si une décision est risquée.
- Petites étapes, petites PR, une chose à la fois.
- Tiens ROADMAP.md à jour à la fin de chaque session (fait, en cours,
  prochain).
- Si une information technique est incertaine, dis-le et vérifie-la
  au lieu de deviner.
- Toujours expliquer brièvement le "pourquoi" d'un choix : Lucas veut
  apprendre et pouvoir défendre chaque décision en entretien ou devant
  un client.

FIN DU BRIEF
```
