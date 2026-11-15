# Constitution de CELIAN

Elle s'impose à toute spécification, tout plan, toute tâche et toute PR du
générateur. Les dix principes viennent de la section 3 du brief
([docs/brief-v1.0.md](../../docs/brief-v1.0.md)).

## Principes fondamentaux

### I. Rien sans test automatique

Aucun fichier ne sort du générateur sans avoir passé une validation
automatique : `tofu validate`, lint, tests, démarrage local. Une combinaison
blueprint et cible non couverte par la matrice de validation ne DOIT pas être
proposée à l'utilisateur.

Pourquoi : un socle généré qui casse au premier lancement détruit la confiance
dans tout le reste.

### II. Spec abstraite, catalogue concret

La spec projet décrit des besoins (`database: postgres`), jamais des produits
(Cloud SQL, RDS). Seul le catalogue traduit une brique abstraite en service
concret pour une cible donnée. Un blueprint ne DOIT pas coder en dur un service
propre à une cible ailleurs que dans sa couche de cible.

Pourquoi : changer de cible doit revenir à changer une ligne de la spec.

### III. Managé sur le cloud, open source ailleurs

Sur une cible cloud, le générateur DOIT utiliser les services managés du
fournisseur. Sur une cible on-prem ou PC, il DOIT utiliser des technos gratuites
et open source, en retenant la meilleure option du marché selon la grille de
benchmark.

Pourquoi : sur un cloud, l'équipe paie pour ne pas opérer. Chez elle, elle ne
doit dépendre d'aucune licence.

### IV. Catalogue traçable

Chaque entrée du catalogue DOIT porter sa licence, sa gouvernance (fondation ou
éditeur unique), son statut (actif, maintenance, archivé), la date de sa
dernière vérification et au moins une source officielle. Une entrée incomplète
ne DOIT pas être utilisée par un blueprint.

Pourquoi : une licence qui change ou un projet archivé (MinIO, Terraform,
Vault) doit se voir avant d'arriver dans les projets des utilisateurs.

### V. Gouvernance ouverte d'abord

À fonctionnalité comparable, le catalogue DOIT préférer un projet porté par une
fondation (CNCF, Linux Foundation, Apache) et soutenu par plusieurs
entreprises. Un projet à éditeur unique est accepté seulement si un benchmark
justifie l'écart, avec un ADR.

Pourquoi : un projet porté par plusieurs entreprises survit au changement de
stratégie de l'une d'elles.

### VI. Récent mais éprouvé

Une techno entre au catalogue seulement si elle est maintenue activement et
déjà adoptée en production. Les critères éliminatoires du benchmark
s'appliquent : projet archivé ou en maintenance, aucune release depuis 12 mois,
licence non open source pour une cible on-prem. Les mises à jour automatiques
attendent qu'une version soit publiée depuis au moins 7 jours.

Pourquoi : l'utilisateur hérite de nos choix pendant des années. Il ne doit pas
essuyer les plâtres.

### VII. Une commande pour démarrer

Tout projet généré DOIT démarrer sur un PC avec une seule commande (`task up`),
sans étape manuelle préalable autre que l'installation des prérequis listés
dans son README.

Pourquoi : c'est la promesse de parité locale, et c'est le critère
d'acceptation du MVP.

### VIII. Aucun fait de mémoire

Aucune version, aucune syntaxe de commande, aucun fait technique ne DOIT être
écrit de mémoire, par un humain comme par un agent. Chaque fait se vérifie sur
la source officielle et se date. Une information non vérifiée se signale comme
telle.

Pourquoi : les écosystèmes changent plus vite que la mémoire d'un modèle. Spec
Kit a changé de syntaxe entre deux versions récentes.

### IX. Aucun secret dans le dépôt

Aucun secret, jeton, clé ou mot de passe ne DOIT être versionné, ni dans le
générateur ni dans un projet généré. La détection de secrets DOIT tourner en
local (pre-commit) et en CI sur tout l'historique. Un secret exposé se révoque
d'abord, puis l'historique se réécrit.

Pourquoi : supprimer un secret dans un nouveau commit ne l'efface pas de
l'historique.

### X. Aucune dépense cloud sans accord

Aucune action qui crée des ressources payantes (`tofu apply`, création de
ressources par une CLI cloud) ne DOIT être lancée sans l'accord explicite de
Lucas et un budget validé par le rôle FinOps. Les agents ne DOIVENT pas pouvoir
lancer ces commandes.

Pourquoi : une erreur d'IaC se paie en euros, et elle ne se rembourse pas.

## Périmètre du MVP

Le MVP comprend un seul blueprint (SaaS B2B : .NET, React, Postgres, cache) et
deux cibles (PC sous k3d, GCP). Il couvre l'entretien guidé, la génération
depuis la spec, la validation automatique et des conventions Git complètes dans
le projet généré. Le produit prend la forme d'un plugin Claude Code qui pilote
une CLI Python.

Hors MVP jusqu'à décision contraire de Lucas : AWS, Azure, on-prem serveurs,
cloud souverain, blueprints data, IoT et mobile, agent comparateur intégré,
interface web, application autonome, version hébergée. Une demande hors
périmètre se refuse, se note dans `ROADMAP.md`, et ne se code pas.

Critère d'acceptation : une personne qui ne connaît pas le projet lance la
commande, répond à une dizaine de questions, et obtient en moins de 15 minutes
un dépôt qui démarre sur son PC et se déploie sur GCP, avec une CI qui passe.

## Flux de travail et portes de qualité

- Le projet avance en six phases. Chacune se ferme par une gate que Lucas
  valide, et la phase suivante ne commence pas avant.
- Un golden repo se construit à la main avant toute mise en template. On ne
  transforme pas en template un projet jamais construit.
- Chaque choix structurant passe par un benchmark daté et sourcé
  (`docs/benchmarks/`), puis par un ADR (`docs/adr/`).
- Les fonctionnalités suivent Spec Kit : `/speckit-specify`, `/speckit-plan`,
  `/speckit-tasks`, `/speckit-implement`.
- Développement trunk-based : branches courtes, une PR par sujet, fusion en
  squash, titre de PR au format Conventional Commits. Une PR se rattache à une
  tâche ou à un ADR.
- Une PR ne fusionne que si la CI passe : hooks pre-commit, scan de secrets, et
  à terme la matrice de validation.
- Langue : documentation en français, code, identifiants et messages de commit
  en anglais. Le tiret cadratin (U+2014) est refusé partout.

## Gouvernance

Cette constitution prime sur toute autre pratique du dépôt. `CLAUDE.md` en
donne le résumé opérationnel pour les sessions d'agents ; en cas d'écart, la
constitution l'emporte et `CLAUDE.md` se corrige.

Un amendement passe par une PR dédiée qui explique le pourquoi, et n'entre en
vigueur qu'après validation de Lucas. La version suit le versionnage
sémantique : majeure pour un principe retiré ou redéfini, mineure pour un
principe ou une section ajoutés, correctif pour une reformulation sans effet
sur les règles.

Chaque revue de PR vérifie la conformité aux principes. Une dérogation se
justifie dans un ADR, avec sa durée et la condition qui la lèvera.

**Version** : 1.0.0 | **Ratifiée** : 2026-11-15, par Lucas à la GATE 0 |
**Dernier amendement** : 2026-11-15
