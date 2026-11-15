# Feuille de route

Mise à jour le 15/11/2026, à la fin de la session 1. Le DSI tient ce fichier à
jour à la fin de chaque session.

## Phase en cours : 0, installation et cadrage

### Fait

- Dépôt initialisé : arborescence, licence Apache-2.0, `CLAUDE.md`, brief
  versionné dans `docs/brief-v1.0.md`.
- Conventions Git et CI : pre-commit (dont gitleaks et le refus du tiret
  cadratin), commitlint, CODEOWNERS, modèle de PR, CI qui rejoue les hooks et
  scanne tout l'historique (PR #1, fusionnée).
- Réglages GitHub appliqués : fusion en squash seule, titre de PR comme
  commit, suppression des branches fusionnées.
- Outils installés sur le poste : specify-cli 1.4.0, pre-commit 4.7.0.

### En cours, en attente de Lucas

- PR #2 : release-please, Renovate, ruleset de `main` sans contournement admin,
  scan de secrets sur chaque push. CI verte, à fusionner.
- PR #3 : Spec Kit et constitution. Fait partie de la GATE 0.
- PR #4 : sous-agents par rôle, plugins du projet, garde-fous cloud. CI verte,
  à fusionner.
- PR de cadrage : vision, PRD, cette feuille de route, registre des risques
  relu par [SECU] et [FINOPS]. Fait partie de la GATE 0.

### Prochain

- GATE 0 : Lucas valide la vision, le PRD (questions Q1 à Q12) et la
  constitution.
- Décisions de Lucas attendues dans `docs/risques.md` : passage du dépôt en
  public avant la phase 2 (R-01, R-16), ECC dans ce projet (R-03), règles de
  permission et jeton `gh` sans droits admin (R-07).
- Actions de Lucas : installer l'app GitHub Renovate, installer Pixel Agents,
  mettre Claude Code en 2.1.324 ou plus pour pouvoir figer les marketplaces
  (R-02).
- Plan court de la phase 1, soumis à validation avant tout benchmark.

## Les six phases du MVP

| Phase | Objectif | Rôles | Gate | État |
| --- | --- | --- | --- | --- |
| 0 | Installation et cadrage | DSI, PO | Vision, PRD, constitution validés | En cours |
| 1 | Benchmarks BENCH-001 à 007, ADR, catalogue daté | BENCH, ARCHI | ADR validés | À venir |
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
