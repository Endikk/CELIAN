# Feuille de route

Mise à jour le 20/11/2026, après la GATE 1. Le DSI tient ce fichier à
jour à la fin de chaque session.

## Phase en cours : 1 terminée, 2 à lancer

Les étapes 1 à 6 sont faites et la GATE 1 est passée le 20/11/2026. La phase 2
commence après la validation de son plan par Lucas.

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

### Prochain

La GATE 1 est passée. Avant la phase 2 :

1. Fusionner les PR de la GATE 1 : amendement du principe VI (#24), règles de
   notation dans le gabarit (#25), PRD aligné (#26), et celle-ci.
2. BENCH-010, en cours par [OPS] : faire démarrer `task up` sur kind sans
   réseau (R-25, condition 7 de l'ADR-004, condition 4 des ADR-005 et 006).
3. Entrées du catalogue issues des ADR : `gateway`, `secrets`, `gitops`, et le
   mode Autopilot sur la ligne `gcp` de `kubernetes-cluster`, en cours par
   [DEV].
4. Renovate : exempter les correctifs de sécurité du délai de 7 jours, une
   fois la syntaxe vérifiée par [OPS] sur sa documentation.
5. Plan court de la phase 2, le golden repo SaaS B2B, à valider par Lucas
   avant de commencer.

Points restés ouverts, repris dans les ADR (sections « Réponses de la
GATE 1 ») : quel profil sert de mesure au critère des 15 minutes ; la lecture
de « arrête et supprime l'environnement » (US-005), qui attend BENCH-010 ; la
gouvernance de Task ; ce que lit Flux sur le PC ; les identifiants de services
tiers sur le PC ; la portée de la règle de fraîcheur du catalogue.

Actions de Lucas, hors GATE :

- lire les grilles tarifaires de GKE, Cloud SQL, Memorystore, du réseau et de
  Cloud Monitoring pour la région choisie, avant la GATE 2 (R-05) ;
- terminer le changement de jeton `gh` et révoquer l'ancien jeton classique
  (R-07) ; la première tentative a échoué, le presse-papiers ne contenait pas
  le jeton ;
- installer l'app GitHub Renovate et Pixel Agents ;
- mettre Claude Code en 2.1.324 ou plus pour figer les marketplaces (R-02) ;
- les sous-agents demandent encore une autorisation Bash en mode bypass :
  `"defaultMode": "bypassPermissions"` ou « ne plus demander » à chaque
  demande.

## Les six phases du MVP

| Phase | Objectif | Rôles | Gate | État |
| --- | --- | --- | --- | --- |
| 0 | Installation et cadrage | DSI, PO | Vision, PRD, constitution validés | Terminée le 15/11/2026 |
| 1 | Benchmarks BENCH-001 à 009, ADR, catalogue daté | BENCH, ARCHI | ADR validés | Terminée le 20/11/2026 (GATE 1) |
| 2 | Golden repo SaaS B2B construit à la main | DEV, OPS, SECU | Démo du golden repo | Plan à valider |
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
