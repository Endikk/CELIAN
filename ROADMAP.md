# Feuille de route

Mise à jour le 23/11/2026, à la fin de la session 4. Le DSI tient ce fichier
à jour à la fin de chaque session.

## Phase en cours : 2, golden repo SaaS B2B

La phase 1 est terminée : la GATE 1 est passée le 20/11/2026. Lucas a validé
le même jour le plan court de la phase 2 : un golden repo SaaS B2B construit à
la main dans `golden/saas-b2b/`, spécifié par Spec Kit
(`specs/001-golden-repo-saas-b2b`).

### Plan de la phase 2

1. Spec Kit : spec 001 (PR #29, amendée par #39), plan (#37) et tâches (#40)
   fusionnés. Reste `/speckit-implement`, étape par étape.
2. Prérequis : BENCH-010 et BENCH-011 rendus (ADR-011, ADR-012) ;
   BENCH-012 (identité) mesuré, en relecture ; BENCH-013 (mail de test) en
   mesure ; BENCH-014 (cache) ouvert, mesures à venir.
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

### Prochain

1. `/speckit-implement`, étape 1 du plan (squelette du golden repo et
   vérifications de versions datées), sur feu vert de Lucas. Les étapes 2 à 5
   suivent ; l'étape 13 (GCP sans Memorystore) peut démarrer à partir du
   24/11/2026.
2. BENCH-012 : relectures [SECU] et [FINOPS] en cours, puis arbitrage, ADR-013
   et PR. Lucas tranche la voie GCP (Identity Platform ou Keycloak sur GKE)
   et confirme ou non l'élimination d'Authentik.
3. BENCH-013 : série en cours, puis relectures, arbitrage, ADR-014 et PR.
4. BENCH-011 : mesure du redémarrage du nœud, après BENCH-013, puis une PR qui
   complète le rapport.
5. BENCH-014 : test de fumée et série sous le verrou, puis relectures,
   arbitrage et ADR-015. Il débloque 57 tâches du golden repo.
6. Petite PR pour reporter dans le plan les écarts relevés par les tâches ;
   reporter dans le PRD le choix de Trivy pour le SBOM.

La PR release-please « release 0.1.0 » (#22) reste ouverte : pas de release
tant qu'il n'y a rien à publier.

Points restés ouverts : ce que lit Flux sur le PC (ADR-010, question 1) ; la
gouvernance de Task ; les identifiants de services tiers sur le PC ; la
portée de la règle de fraîcheur du catalogue ; la fabrication du certificat
HTTPS local ; le TLS vers la base et le cache.

Actions de Lucas, hors GATE :

- lire les grilles tarifaires de GKE, Cloud SQL, Memorystore, du réseau et de
  Cloud Monitoring pour la région choisie, avant la GATE 2 (R-05) ;
- terminer le changement de jeton `gh` et révoquer l'ancien jeton classique
  (R-07) ;
- installer l'app GitHub Renovate et Pixel Agents ;
- mettre Claude Code en 2.1.324 ou plus pour figer les marketplaces (R-02) ;
- redémarrer la session Claude Code une fois les agents arrêtés, pour que le
  retrait du blocage des lectures prenne effet (#33) ;
- garder le Mac branché et le capot ouvert pendant les séries de mesure : la
  veille capot fermé coupe les séries (BENCH-012) ;
- lancer `scripts/github/apply-settings.sh` quand le scan des images entrera
  dans les contrôles requis de `main` (étape 18 du plan).

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
