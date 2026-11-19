# Feuille de route

Mise à jour le 19/11/2026, pendant la session 2. Le DSI tient ce fichier à
jour à la fin de chaque session.

## Phase en cours : 1, benchmarks et décisions

### Fait

- Phase 0 terminée le 15/11/2026 : dépôt, conventions Git et CI, release-please
  et Renovate, sous-agents et plugins, Spec Kit et constitution 1.0.0, vision,
  PRD, registre des risques, garde-fous contre la fuite d'identifiants, ruleset
  de `main` actif (PR #1 à #8).
- Étape 1 : gabarits de benchmark et d'ADR (PR #9).
- Étape 2 : analyse de douze outils existants (Q12). Aucun ne couvre entièrement
  plus de deux piliers ; Copier couvre la génération et le jour 2.

### Décisions de Lucas

- 15/11/2026 : GATE 0 validée, Q1 à Q12 tranchées, ECC désactivé, dépôt public
  voulu, plan de la phase 1 validé.
- 19/11/2026 : Score entre dans les options de BENCH-001. BENCH-008 est créé
  pour les modules OpenTofu de GCP. Deux risques sont ajoutés (R-21, R-22). La
  section « Ce qui le distingue » de la vision parle désormais d'assemblage.

### Prochain

- Étape 3 : BENCH-006 en version courte, puis BENCH-001 et BENCH-002.
- Étapes suivantes : BENCH-003 avec mesures, puis 004, 005, 007 sur le cluster
  retenu, BENCH-008, enfin `catalog/` avec son check CI. GATE 1 : Lucas valide
  les ADR.
- Lucas termine le changement de jeton `gh` et révoque l'ancien jeton classique
  (R-07). À reprendre : la première tentative a échoué, le presse-papiers ne
  contenait pas le jeton.
- Lucas valide la lecture des principes III et V pour les services managés de
  GCP, avant l'étape 6.
- Actions de Lucas : installer l'app GitHub Renovate, installer Pixel Agents,
  mettre Claude Code en 2.1.324 ou plus pour figer les marketplaces (R-02).

## Les six phases du MVP

| Phase | Objectif | Rôles | Gate | État |
| --- | --- | --- | --- | --- |
| 0 | Installation et cadrage | DSI, PO | Vision, PRD, constitution validés | Terminée le 15/11/2026 |
| 1 | Benchmarks BENCH-001 à 008, ADR, catalogue daté | BENCH, ARCHI | ADR validés | En cours, étapes 1 et 2 faites |
| 2 | Golden repo SaaS B2B construit à la main | DEV, OPS, SECU | Démo du golden repo | À venir |
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
