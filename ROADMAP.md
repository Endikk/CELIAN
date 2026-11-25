# Feuille de route

Mise à jour le 25/11/2026, en fin de session 5. Le DSI tient ce fichier à jour
à la fin de chaque session.

## Phase en cours : 2, golden repo SaaS B2B

La phase 1 est terminée : la GATE 1 est passée le 20/11/2026. Lucas a validé
le même jour le plan court de la phase 2 : un golden repo SaaS B2B construit à
la main dans `golden/saas-b2b/`, spécifié par Spec Kit
(`specs/001-golden-repo-saas-b2b`).

### Plan de la phase 2

1. Spec Kit : spec 001 (PR #29, amendée par #39), plan (#37) et tâches (#40)
   fusionnés. Reste `/speckit-implement`, étape par étape.
2. Prérequis : BENCH-010 à BENCH-013 rendus, ADR-011 à ADR-014 acceptés.
   BENCH-014 (cache) rendu (#66), ADR-015 écrit (#67).
3. Squelette : couches commune, `local` et `gcp`, Taskfile, kind, conventions
   Git.
4. Application d'exemple : API .NET et front React.
5. Cible PC : Envoy Gateway, miroir zot, Secrets créés par `task up`,
   Postgres, cache, profils lite et standard.
6. Cible GCP : OpenTofu écrit à la main, `tofu validate`, conftest et Trivy,
   sans `plan` ni `apply`.
7. Tests et CI, dont le SBOM et le scan des images.

Gate de la phase : une démo de `task up` sur un poste propre, en profil
standard, avec le temps et le volume mesurés (R-04).

### Fait

- Phase 0 terminée le 15/11/2026 : dépôt, conventions Git et CI, release-please
  et Renovate, sous-agents et plugins, Spec Kit et constitution 1.0.0, vision,
  PRD, registre des risques, garde-fous contre la fuite d'identifiants, ruleset
  de `main` actif (PR #1 à #8).
- Étape 1 : gabarits de benchmark et d'ADR (PR #9).
- Étape 2 : analyse de douze outils existants (Q12). Aucun ne couvre entièrement
  plus de deux piliers ; Copier couvre la génération et le jour 2 (PR #10).
- Étape 3 : BENCH-006, BENCH-001 et BENCH-002, relus par [SECU] et [FINOPS],
  puis ADR-001 (spec en YAML et JSON Schema), ADR-002 (Copier, sous
  conditions) et ADR-003 (CLI en Python), au statut proposé. Risques R-23 et
  R-24 ouverts.
- Étape 4 : BENCH-003 mesuré sur le poste (k3d, kind, minikube), relu par
  [SECU] et [FINOPS], puis ADR-004 (kind, sous conditions), au statut proposé.
  Règle d'empreinte à seuils absolus entrée dans le gabarit de benchmark.
  R-04 et R-20 complétés par les mesures, R-25 et R-26 ouverts. Amendement de
  la constitution en 1.1.0 dans une PR dédiée (#13).
- Étape 5 : cinq benchmarks mesurés sur kind ou lus sans action cloud, chacun
  relu par [SECU] et [FINOPS], chacun suivi d'un ADR au statut proposé :
  - BENCH-008 et ADR-008 : code OpenTofu écrit à la main sur le provider
    `google`, GKE Autopilot, dix conditions (PR #16) ;
  - BENCH-004 et ADR-005 : Envoy Gateway sur le PC, contrôleur Gateway de GKE
    sur GCP, 86 contre 81 et 78 (PR #17) ;
  - BENCH-007 et ADR-007 : Secrets Kubernetes créés par `task up` sur le PC,
    synchronisés depuis Secret Manager par GKE sur GCP, à égalité avec ESO
    (82) et retenus par arbitrage du DSI (PR #18) ;
  - BENCH-005 et ADR-006 : aucun outil de boucle derrière `task up`
    (`docker build`, `kind load`, `kubectl apply`), 88 contre Tilt 74 et
    Aspire 63 (PR #19) ;
  - BENCH-009, ouvert par le DSI, et ADR-010 : Flux sur le PC, Config Sync
    sur GKE, 88 contre Argo CD 86 (PR #20).
- Étape 6 : catalogue des services, un fichier YAML par brique validé par
  JSON Schema, contrôle en CI avec règle de fraîcheur à 6 mois, et ADR-009 sur
  le format du catalogue et la lecture des principes III et V (PR #15).
- Risques : R-27 à R-33 ouverts ; R-04 et R-25 passés en probabilité forte ;
  R-15, R-17, R-19, R-20 et R-25 complétés par les mesures.
- GATE 1 passée le 20/11/2026, PR #23 à #28 fusionnées : release-please
  démarré à 0.1.0, principe VI amendé (constitution 1.2.0), règles de notation
  dans le gabarit de benchmark, PRD aligné, ADR-001 à ADR-010 acceptés,
  entrées `gateway`, `secrets` et `gitops` du catalogue.
- Phase 2, sessions 3 et 4 (20 au 23/11/2026), PR #29 à #40 :
  - spec 001 (#29), décisions de phase 2 dans le PRD et la feuille de route
    (#30), exception de sécurité de Renovate au délai de 7 jours (#31) ;
  - BENCH-010 (#32) et ADR-011 (#34) : miroir local zot 2.1.23 lancé par
    `task up`, seul mécanisme qui recrée le cluster hors réseau ; R-34 ouvert ;
  - BENCH-011 (#35) et ADR-012 (#36) : Postgres sans opérateur sur `local`
    (87 contre CloudNativePG 83), dérogation datée à ENF-03 pour les images
    officielles Docker ; R-35 ouvert ;
  - ADR-011 et ADR-012 acceptés (#38) ;
  - moins de demandes de confirmation dans les réglages du projet (#33) ;
  - spec 001 alignée sur les ADR-011 et 012, SBOM et scan des images ajoutés
    (#39) ; plan (#37) et 160 tâches (#40).
- Phase 2, fin de la session 4 (23 et 24/11/2026), PR #41 à #52 :
  - feuille de route (#41) ;
  - golden repo, étape 1 : squelette, CI `static` et `export` (#42) ; étape 2 :
    conventions Git du projet généré (#46) ;
  - BENCH-012 (#43) et ADR-013 (#44), accepté (#45) : Keycloak sur le PC,
    Identity Platform sur GCP ; R-36 et R-37 ouverts ;
  - BENCH-013 (#47) et ADR-014 (#49), accepté (#50) : Mailpit v1.34.0 sur le
    PC, rien sur GCP ;
  - redémarrage du nœud de BENCH-011 mesuré (#48), puis reporté dans
    l'ADR-012 (#51) ;
  - réglages du projet sans aucune règle `ask` (#52).
- Pause du 24/11/2026 au soir, le temps de supprimer les dernières demandes
  d'autorisation (#52). Reprise le même soir.
- Phase 2, session 5 (24/11/2026), PR #51, #53 et #55 :
  - ADR-016 et sa règle (#53) : les images de ghcr.io, quay.io et
    mcr.microsoft.com, que Renovate ne sait pas dater, attendent l'approbation
    de Lucas sur le tableau de bord ; dérogation datée au principe VI ;
    `renovate.json` de CELIAN contrôlé en CI ; règles `deny` contre l'écriture
    des agents dans le ticket du tableau de bord ; R-38 ouvert ;
  - règles du golden repo appliquées par le Renovate de CELIAN, Task et
    conftest suivis par Renovate, S23 durci après la relecture [SECU] (#55) ;
  - étape 3 du golden repo, API .NET, ouverte en PR (#54) ; R-39 ouvert.
- Phase 2, fin de la session 5 (25/11/2026), PR #54 à #70, fusionnées dans
  l'ordre :
  - golden repo, étape 5 (#57) : contrôles préalables de `task up`, soit le
    moteur local joint par socket unix seulement, les versions, la mémoire et
    le profil, les ports, et un kubeconfig ignoré ;
  - écarts relevés par les tâches reportés dans le plan, Trivy seul dans le
    PRD (US-009) (#58) ;
  - gitleaks daté par Renovate sur Docker Hub mais tiré de ghcr.io par le même
    condensat (#59) ; R-40 ouvert, gitleaks étant en maintenance ;
  - `CDPATH` ignoré dans tous les scripts, avec une garde (#60) ;
  - S23 refuse les entrées Renovate qui coupent, séparent ou détournent une
    mise à jour surveillée, et les gestionnaires maison hors des deux connus
    (#61) ;
  - étape 6 (#65) : cluster kind et miroir zot, job `e2e-lite` en CI ;
  - BENCH-014 (#66) : Valkey 9.1.4 à 86 contre Redis 7.2.17 à 69 ;
  - ADR-015 (#67), accepté par le DSI sur délégation de Lucas : Valkey sur `local`, Memorystore for Valkey sur `gcp`, avec
    un jeton pour le MVP ; dérogation datée à ENF-03 pour `valkey/valkey` ;
    R-41 ouvert ;
  - étape 3, API .NET (#54), fusionnée à 18 h 46 à Paris (17:46 UTC), quand les condensats .NET
    ont atteint 7 jours ; R-39 ouvert sur `cloudsqlsuperuser` ;
  - étape 13 (#64) : couche GCP écrite en OpenTofu, validée sans aucune action
    cloud ;
  - bits d'exécution de cinq scripts rétablis (#69) ;
  - cinq points `pending` du catalogue fermés (#70).
- Restent ouvertes en fin de session : #62 (étape 4, front React), #63
  (durcissement de S20, empilée sur #62), #68 (étape 7, Gateway API et Envoy
  Gateway, relecture [SECU] en cours) et #22 (release-please).

### Décisions de Lucas

- 15/11/2026 : GATE 0 validée, Q1 à Q12 tranchées, ECC désactivé, dépôt public
  voulu, plan de la phase 1 validé.
- 19/11/2026 : Score entre dans les options de BENCH-001. BENCH-008 est créé
  pour les modules OpenTofu de GCP. Deux risques sont ajoutés (R-21, R-22). La
  section « Ce qui le distingue » de la vision parle désormais d'assemblage.
  Copier est accepté comme seule option de BENCH-002, avec le prérequis du jour
  2 (US-011). La mise à jour d'un projet généré passe par la CLI de CELIAN ; les
  montées de version de sécurité de Copier échappent au délai de 7 jours ; les
  seuils de bascule vers le repli de R-22 sont validés (ADR-002). Pour BENCH-003,
  la règle d'empreinte de [FINOPS] est validée et kind est retenu pour la cible
  PC ; la clé en 0777 relevée chez minikube n'est pas signalée. Lucas autorise
  le DSI à avancer seul pendant son absence, sans poser de question, les points
  à trancher étant gardés pour son retour.
- 20/11/2026 : Lucas fusionne les PR #13 à #21. Puis GATE 1 : Lucas retient la
  lecture des principes III et V de l'ADR-009 (III fixe les candidats d'une
  cible, V départage) ; un débit visé entre dans le critère d'acceptation,
  valeur proposée par [FINOPS] après le golden repo, et le profil lite
  n'embarque pas GitOps ; les trois règles de notation provisoires entrent
  dans le gabarit de benchmark ; le principe VI est amendé pour laisser passer
  les correctifs de sécurité qui passent la matrice ; aucun contexte GKE sur
  le poste avant la GATE 2 ; Lucas lit lui-même les grilles tarifaires de GCP
  avant la GATE 2. Il confirme les quatre décisions du DSI ci-dessous, et
  délègue au DSI l'acceptation des ADR : les ADR-001 à ADR-010 passent au
  statut accepté.
- 20/11/2026, lancement de la phase 2 : Lucas valide le plan court du golden
  repo. Postgres local passe d'abord par un benchmark (BENCH-011), avant
  l'écriture de la couche locale. Aucun déploiement réel sur GCP pendant la
  phase 2. Le critère des 15 minutes se mesure en profil standard, et non en
  profil lite. Le profil standard est le profil lite plus Flux, Keycloak et
  Mailpit ; Keycloak et Mailpit passent chacun par un benchmark avant d'entrer
  dans le golden repo (BENCH-012, BENCH-013). Ces décisions sont reportées dans
  le PRD (US-005, ENF-01, ENF-05, section 7).
- 20/11/2026, session 4 : `docker run` autorisé pour le seul registre miroir
  de BENCH-010.
- 21/11/2026 : réglages du projet sans les 8 règles `ask` fréquentes ni le
  blocage des lectures (#33) ; Postgres sans opérateur sur `local` ;
  dérogation datée à ENF-03 pour les images officielles Docker ; mesure du
  redémarrage du nœud de BENCH-011 autorisée ; ADR-011 et ADR-012 acceptés
  avec les réponses proposées ; moteur du cache par un benchmark court
  (BENCH-014) ; Flux livré avec sa liaison suspendue dans le profil standard ;
  SBOM et scan des images dans la spec 001.
- 23/11/2026 : Trivy seul pour le SBOM et le scan (écart avec Syft, nommé par
  le PRD, à reporter dans le PRD) ; aucune image de cache provisoire, le
  profil lite attend l'ADR-015.
- 24/11/2026 : Identity Platform sur `gcp`, élimination d'Authentik
  maintenue, dérogation datée à ENF-03 pour Keycloak ; rien sur `gcp` pour le
  mail de test, dérogation datée pour Mailpit ; ADR-013 et ADR-014 acceptés ;
  plus aucune règle `ask` dans les réglages du projet (#52). Pour les images
  sans date, approbation manuelle sur le tableau de bord de Renovate, cochée
  par Lucas seul. Réponses aux questions de l'ADR-016 : dans le projet généré,
  une personne qui maintient le projet coche, jamais un agent ; dérogation
  relue au plus tard le 2027-02-24 ; tableau de bord lu chaque semaine et sur
  alerte de [SECU] ; gitleaks tiré de Docker Hub, à essayer dans une PR à
  part.
- 25/11/2026 : BENCH-014 lancé quand le Mac était sur secteur ; benchmark des
  scanners de secrets (gitleaks, Betterleaks, TruffleHog, Kingfisher au
  moins) après le golden repo, avant la mise en template, et au plus tard le
  2027-03-21 ; gitleaks daté sur Docker Hub, tiré de ghcr.io ; feu vert aux
  étapes 6 et 13, puis délégation complète au DSI pendant son absence,
  fusions comprises, avec le choix du modèle des agents selon la tâche.

### Décisions du DSI pendant l'absence de Lucas, confirmées à la GATE 1

- Règles de notation provisoires, appliquées à tous les benchmarks de
  l'étape 5 : volume noté sur linux_amd64, pire cas des systèmes de Q5 ;
  plate-forme de base (cluster kind, CRD Gateway API, gateway) comptée contre
  500 Mo, chaque couche suivante contre ses propres seuils, le cumul en
  sensibilité ; mémoire d'une couche lue au nœud, moins le nœud kind seul.
- BENCH-005 : US-005 (« démarrent dans le cluster local ») sert de critère
  éliminatoire, ce qui écarte Docker Compose et la boucle locale d'Aspire ;
  une option sans outil de boucle est ajoutée après la première série.
- BENCH-007 : à égalité, les Secrets natifs sont retenus par le principe III,
  dans la lecture de l'ADR-009.
- BENCH-009 : une règle d'égalité, posée avant la série de référence, qui
  aurait gardé Argo CD ; elle n'a pas joué.
- R-04 et R-25 passés en probabilité forte.

### Décisions du DSI, session 4

- Arbitrages de BENCH-010 (zot dans tous les profils, garder le cluster en
  commande explicite seulement) et de BENCH-011 (grille réconciliée des deux
  relectures).
- BENCH-012 : Authentik éliminé sur le critère de licence, à titre provisoire
  (code sous licence non OSI chargé au démarrage de l'image officielle) ;
  Keycloak mesuré en mode `start` ; le fournisseur d'identité partage le
  Postgres de la stack, avec sa propre base et son propre rôle.
- BENCH-013 : l'interface web est requise ; Mailpit mesuré en v1.34.0 sous
  l'exception de sécurité du principe VI.
- BENCH-014 : la version locale du cache suit la ligne que Memorystore sert
  par défaut.
- Golden repo : aucune authentification de l'exemple en local, elle arrive
  avec l'ADR-013, et aucun déploiement réel sur GCP sans elle ; CI du golden
  repo dans CELIAN seulement ; tests unitaires dans l'image de construction.
- Pas de deuxième palier de volume pour BENCH-012 et BENCH-013, dont les
  seuils étaient déjà hachés ; il ira dans le gabarit pour les suivants.

### Décisions du DSI, session 5

- ADR-016 accepté dans sa propre PR, Lucas ayant tranché toutes ses
  questions. S23 va plus loin que la proposition de [SECU] : l'entrée de
  l'ADR est exigée, et l'approbation refusée hors de `packageRules`. Le
  contrôle de CELIAN tourne dans le job `pre-commit`, déjà requis. Le job
  `export` reste non requis jusqu'à l'étape 18.
- RS-17, point 2 : les Dockerfile du golden repo restent suivis par le
  Renovate de CELIAN.
- Étape 3 : l'historique de `dotnet/versions` date un condensat passé de
  mcr.microsoft.com ; codes 413 et 415 ajoutés au contrat de l'API ;
  condensats .NET du 2026-11-18 gardés après la relecture [SECU]. NU1900
  (données d'audit NuGet injoignables) reste un avertissement.
- Étape 4 lancée sur la branche de l'étape 3 ; sa PR s'ouvre après la fusion
  de #54.
- 25/11/2026 :
  - les étapes fusionnent dans l'ordre des dates où leurs images atteignent
    7 jours ; les écarts des tâches sont renumérotés à chaque rebase ;
  - S23 reste strict pour le projet généré aussi : un groupe ou un registre de
    plus passe par une PR relue ;
  - S29 : un `.npmrc` ou un `nuget.config` ne nomme que le registre
    officiel ;
  - `KIND_EXPERIMENTAL_PROVIDER` et `KIND_EXPERIMENTAL_DOCKER_NETWORK` sont
    refusés ;
  - les leurres de E22 se créent par `docker container create` ;
  - T110 vit dans une racine séparée, `gcp/budget/`, pour qu'aucun rôle Owner
    ni Editor n'aille à l'identité de la racine principale ;
  - Cloud SQL plafonné à 2 vCPU, journaux de flux à 15 minutes et 10 %, Trivy
    sans requête sortante et avec ses règles embarquées ;
  - arbitrage de BENCH-014 : un jeton pour Memorystore, pas de deuxième palier
    de volume, le majorant pour la note et le pod pour le dimensionnement ;
  - le ticket chez `valkey-container` est laissé à Lucas ;
  - `local/vendor/` sort des hooks `no-em-dash` et de taille : ce sont des
    octets de tiers, vérifiés par `SHA256SUMS` ;
  - étape 7 lancée par délégation.

### Prochain

1. Étape 4, front React (#62) : fusion à partir du 2026-11-26 à 01:50 UTC,
   délai de nginx. Puis #63, le durcissement de S20, empilée sur #62.
2. Étape 7, Gateway API et Envoy Gateway (#68) : finir après la relecture
   [SECU], qui est en cours.
3. Ensuite l'étape 8 (secrets et données), l'étape 19 (cache local, débloquée
   par l'ADR-015), l'étape 9 (profil lite de bout en bout), l'étape 18 (SBOM
   et scan) et l'étape 14.
4. Benchmark des scanners de secrets (gitleaks, Betterleaks, TruffleHog,
   Kingfisher au moins) après le golden repo et avant la mise en template, au
   plus tard le 2027-03-21 (R-40).
5. Image `aspnet` chiseled pour l'API, qui retirerait 97 paquets Ubuntu :
   benchmark et ADR, après l'étape 9.
6. Suites de Renovate : la règle des presets qui lisent `registryUrl` dans
   les commentaires ; le registre `registry.opentofu.org`, que S23 empêche
   aujourd'hui de déclarer (`registryUrls` refusé) : à trancher.

La PR release-please « release 0.1.0 » (#22) reste ouverte : pas de release
tant qu'il n'y a rien à publier.

Points restés ouverts : ce que lit Flux sur le PC (ADR-010, question 1) ; la
gouvernance de Task ; les identifiants de services tiers sur le PC ; la
portée de la règle de fraîcheur du catalogue ; la fabrication du certificat
HTTPS local ; le TLS vers la base et le cache ; le propriétaire de la base
`app` sur Cloud SQL et les privilèges de l'API (R-39, T107).

Actions de Lucas, hors GATE :

- lire les grilles tarifaires de GKE, Cloud SQL, Memorystore, Config Sync, du
  réseau et de Cloud Monitoring pour la région choisie, avant la GATE 2
  (R-05) ;
- décider du ticket chez `valkey-container` (ADR-015) ;
- révoquer l'ancien jeton classique et terminer le passage au jeton fin
  (R-07), point de sécurité le plus urgent ; puis essayer le jeton des agents
  sur un ticket de test, qui doit recevoir un 403 en REST et en GraphQL
  (ADR-016, condition 3) ;
- installer l'app GitHub Renovate, seulement après ces deux points ; Pixel
  Agents ;
- mettre Claude Code en 2.1.324 ou plus pour figer les marketplaces (R-02) ;
- garder le Mac branché et le capot ouvert pendant les étapes qui lancent
  kind : la veille capot fermé coupe les séries (BENCH-012, BENCH-014) ;
- lancer `scripts/github/apply-settings.sh`, pour rendre les jobs `unit` et
  `e2e-lite` requis sur `main`, puis de nouveau quand le scan des images
  entrera dans les contrôles requis (étape 18 du plan).

## Les six phases du MVP

| Phase | Objectif | Rôles | Gate | État |
| --- | --- | --- | --- | --- |
| 0 | Installation et cadrage | DSI, PO | Vision, PRD, constitution validés | Terminée le 15/11/2026 |
| 1 | Benchmarks BENCH-001 à 009, ADR, catalogue daté | BENCH, ARCHI | ADR validés | Terminée le 20/11/2026 (GATE 1) |
| 2 | Golden repo SaaS B2B construit à la main | DEV, OPS, SECU | Démo du golden repo | En cours depuis le 20/11/2026 |
| 3 | Template Copier, JSON Schema de la spec v1 | ARCHI, DEV | Génération depuis un exemple de spec | À venir |
| 4 | Pipeline de validation blueprint et cible | QA, OPS | Matrice verte | À venir |
| 5 | Plugin Claude Code : entretien, génération, validation | ARCHI, DEV, PO | Projet généré de bout en bout | À venir |
| 6 | Acceptation avec une personne extérieure, démo | QA, DOC, DSI | MVP livré | À venir |

## Après le MVP, ordre proposé

1. Cible AWS. Elle révélera ce qui était trop lié à GCP.
2. Cible Azure.
3. Cible on-prem serveurs (Talos ou RKE2) et cloud souverain.
4. Blueprint data platform.
5. Agent comparateur intégré au produit.
6. Les autres idées ci-dessous.

## Idées hors MVP

Gardées ici pour ne pas les perdre. Aucune n'est planifiée.

- Auditeur de projets existants : C4, score sur la même grille, PR de
  correction.
- Agent comparateur pendant l'entretien, avec mesure sur le cluster local et
  ADR.
- Alertes catalogue : une brique devient obsolète, le générateur ouvre une PR
  dans les projets générés.
- Migration de cible en changeant la cible dans la spec.
- Estimation des coûts avant génération (Infracost, dimensionnement on-prem).
- Pack conformité : correspondance RGPD et ISO 27001.
- Badge OpenSSF Scorecard dans le README des projets générés.
- Blueprints data platform, IoT et supervision industrielle, mobile.
- Site de documentation généré par projet.
- Mode démo avec Pixel Agents pour le portfolio et GitHub.
