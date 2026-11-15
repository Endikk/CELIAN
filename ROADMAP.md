# Feuille de route

Mise à jour le 15/11/2026, à la fin de la session 1. Le DSI tient ce fichier à
jour à la fin de chaque session.

## Phase 0 terminée, phase 1 à démarrer

### Fait

- Dépôt initialisé : arborescence, licence Apache-2.0, `CLAUDE.md`, brief
  versionné dans `docs/brief-v1.0.md`.
- Conventions Git et CI : pre-commit (dont gitleaks et le refus du tiret
  cadratin), commitlint, CODEOWNERS, modèle de PR, CI qui rejoue les hooks
  (PR #1).
- release-please, Renovate avec délai de 7 jours, ruleset de `main` en code,
  scan de secrets sur chaque push (PR #2).
- Dix sous-agents par rôle, plugins du projet, refus de `tofu apply` et des
  créations `gcloud` (PR #4).
- Spec Kit 1.4.0 et constitution 1.0.0 ratifiée (PR #3).
- Vision, PRD, cette feuille de route, registre de 20 risques (PR #5).
- Garde-fous contre la fuite d'identifiants et procédure de changement du
  jeton `gh` (PR #6, R-07).
- Réglages GitHub appliqués : fusion en squash seule, titre de PR comme
  commit, suppression des branches fusionnées.

### Décisions de Lucas du 15/11/2026

- GATE 0 validée : vision, constitution 1.0.0 et PRD, avec les propositions du
  PO pour les questions Q1 à Q12.
- Q1 : les 15 minutes couvrent l'entretien, la génération, le démarrage local,
  le plan GCP et la CI du premier push. L'apply se mesure à part.
- Q2 : l'utilisateur lance l'apply, jamais l'agent.
- Q7 : l'agent écrit les ADR et les textes du projet. Le code métier se limite
  à l'exemple du blueprint. Le brief est resserré sur ce point.
- ECC est désactivé dans ce projet (R-03).
- Plan de la phase 1 validé.
- Le dépôt est public, c'est voulu (R-01, R-16).

### Prochain

- Lucas lance `scripts/github/apply-settings.sh` pour appliquer le ruleset de
  `main`. Le DSI vérifie ensuite par l'API qu'il est actif (R-01).
- Lucas remplace son jeton `gh` classique en suivant
  `docs/securite/jeton-github.md`, puis le révoque (R-07).
- Actions de Lucas : installer l'app GitHub Renovate, installer Pixel Agents,
  mettre Claude Code en 2.1.324 ou plus pour pouvoir figer les marketplaces
  (R-02).
- Phase 1, dans une nouvelle session : gabarits de benchmark et d'ADR, analyse
  des outils existants (Q12), puis BENCH-006, 001, 002, 003, et 004, 005, 007
  mesurés sur le cluster retenu, enfin `catalog/` avec son check CI.

## Les six phases du MVP

| Phase | Objectif | Rôles | Gate | État |
| --- | --- | --- | --- | --- |
| 0 | Installation et cadrage | DSI, PO | Vision, PRD, constitution validés | Terminée le 15/11/2026 |
| 1 | Benchmarks BENCH-001 à 007, ADR, catalogue daté | BENCH, ARCHI | ADR validés | Plan validé, à démarrer |
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
