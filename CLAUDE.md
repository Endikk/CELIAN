# CELIAN

Générateur de projets d'architecture dev et data, piloté par agents. Le brief
d'origine l'appelait ArchForge. Le nom CELIAN a été retenu le 15/11/2026.

La source complète est [docs/brief-v1.0.md](docs/brief-v1.0.md). Ce fichier en
garde ce qui sert à chaque session.

## Le produit

L'utilisateur répond à un entretien guidé : cible, type de projet, contraintes.
L'entretien produit une spec YAML abstraite, source de vérité. Des blueprints
Copier testés génèrent le dépôt de façon déterministe. Un agent écrit ensuite
seulement ce qui est propre au projet : les ADR et les textes du projet. Le code
métier se limite à l'exemple du blueprint (Q7, 15/11/2026). Une validation
automatique tourne avant la livraison, et renvoie l'agent corriger en cas
d'échec. Le projet généré reçoit plus tard les correctifs du blueprint par
`copier update`.

## Constitution

Dix principes non négociables, repris de la section 3 du brief. Le texte qui
fait foi est [.specify/memory/constitution.md](.specify/memory/constitution.md) ;
en cas d'écart, il l'emporte sur ce résumé.

1. Rien n'est généré sans être testé automatiquement.
2. La spec est abstraite (`database: postgres`). Le catalogue la traduit en
   service concret selon la cible.
3. Sur un cloud : services managés du fournisseur. En on-prem et sur PC :
   technos gratuites et open source, la meilleure option du marché.
4. Chaque techno du catalogue porte sa licence, sa gouvernance, son statut et
   la date de sa dernière vérification.
5. Préférer les projets portés par une fondation (CNCF, Linux Foundation,
   Apache) et soutenus par plusieurs entreprises.
6. Technos récentes mais éprouvées. Pas de projet qui vient de sortir.
7. Un projet généré démarre en une seule commande sur un PC.
8. Aucune version ni aucun fait technique écrit de mémoire. On vérifie sur la
   source officielle et on date.
9. Aucun secret dans le dépôt, jamais.
10. Aucune action cloud payante (`tofu apply`, création de ressources) sans
    accord explicite de Lucas.

## Périmètre du MVP

Dans le MVP : un blueprint SaaS B2B (.NET, React, Postgres, cache) et deux
cibles, un PC sous k3d et GCP. Entretien guidé, génération depuis la spec,
validation automatique, conventions Git complètes dans le projet généré. Le
produit prend la forme d'un plugin Claude Code (skills et sous-agents) qui
pilote une petite CLI Python. Les projets générés restent en .NET et React.

Hors MVP, à refuser poliment jusqu'à nouvel ordre : AWS, Azure, on-prem
serveurs, cloud souverain, blueprints data, IoT et mobile, agent comparateur
intégré, interface web, application autonome, version hébergée.

Critère d'acceptation : une personne qui ne connaît pas le projet lance la
commande, répond à une dizaine de questions, et obtient en moins de 15 minutes
un dépôt qui démarre sur son PC et se déploie sur GCP, avec une CI qui passe.

## L'équipe

L'agent principal est le DSI. Il pilote, arbitre entre les rôles, tient
`ROADMAP.md` et `docs/risques.md`, et refuse ce qui sort du MVP. Chaque autre
rôle est un sous-agent. Quand on change de casquette, le tag du rôle ouvre le
paragraphe.

| Tag | Rôle |
| --- | --- |
| [DSI] | Directeur SI, agent principal |
| [PO] | Product Owner : vision, PRD, user stories, non-objectifs |
| [ARCHI] | Architecte solution et cloud : spec, blueprints, C4, ADR |
| [DATA] | Architecte data, pour les blueprints data après le MVP |
| [DEV] | Tech lead : CLI, templates, code des projets générés |
| [OPS] | Platform engineer : Kubernetes, OpenTofu, GitOps, CI/CD |
| [SECU] | RSSI : chaîne d'approvisionnement, secrets, politiques |
| [FINOPS] | Coûts par cible, budgets, dimensionnement |
| [QA] | Stratégie de test, matrice de validation |
| [BENCH] | Veille et benchmarks pondérés, mesures réelles |
| [DOC] | Rédaction technique : README, guides, changelog |

Chaque rôle sauf le DSI a son sous-agent dans `.claude/agents/<tag>.md`
(`po`, `archi`, `data`, `dev`, `ops`, `secu`, `finops`, `qa`, `bench`, `doc`),
avec les outils minimum de son domaine. Le DSI leur délègue les tâches de leur
domaine.

## Plugins du projet

Déclarés dans `.claude/settings.json`, donc versionnés et actifs pour qui clone
le dépôt :

- marketplace `claude-code-workflows` (wshobson/agents) : `cloud-infrastructure`,
  `kubernetes-operations`, `cicd-automation`, `observability-monitoring`,
  `security-scanning`, `c4-architecture`, `git-pr-workflows` ;
- marketplace `hashicorp` : `terraform`. Écrit pour Terraform, appliqué à
  OpenTofu. Toute divergence rencontrée se signale.

Deux plugins utilisateur sont désactivés dans ce projet. superpowers, parce que
sa méthode de planification double celle de Spec Kit. ECC (décision de Lucas du
15/11/2026), pour la même raison et pour son coût : environ 48 000 tokens
chargés à chaque session, mesurés le 15/11/2026 (R-03). Ses règles de
`~/.claude/rules/ecc/` ne dépendent pas du plugin et restent lues.

Ces marketplaces ne sont pas encore figées. Claude Code accepte un SHA complet
comme `ref` de marketplace à partir de la version 2.1.324
(<https://code.claude.com/docs/en/plugins/marketplace-reference.md>) ; le poste
tourne en 2.1.322, d'où l'échec de l'essai du 15/11/2026. Après la mise à jour
de Claude Code, fixer `ref` sur `9c61ab243def98f72da12abd41cfcf5bcd91af9d`
(wshobson) et `5e30fa5c867ba6777c37e4206babfd08049c396f` (HashiCorp), les
commits relus le 15/11/2026 : aucun hook, aucun serveur MCP, un seul script
lancé à la demande par un skill Helm. La mise à jour automatique est désactivée
par défaut pour les marketplaces tierces
(<https://code.claude.com/docs/en/discover-plugins.md>). Toute mise à jour
volontaire passe par une relecture [SECU], parce qu'un skill reste une
instruction suivie par un agent qui a le shell.

## Garde-fous

`.claude/settings.json` refuse aux agents `tofu apply`, `tofu destroy`, leurs
équivalents Terraform, les créations et suppressions de ressources `gcloud`, et
la lecture des fichiers `.env` et des états OpenTofu. Ces règles filtrent des
motifs de commande : un détour (script, `bash -c`) reste possible. Elles ne
remplacent pas le principe X, elles le rendent plus difficile à enfreindre par
erreur.

Contre la fuite d'identifiants (R-07), le même fichier :

- refuse `gh auth token` et les commandes `gcloud` qui impriment un jeton ;
- refuse la lecture de `~/.config/gh`, `~/.config/gcloud`, `~/.ssh`, `~/.aws`,
  `~/.kube`, `~/.docker/config.json`, `~/.netrc` et `~/.git-credentials` ;
- bloque les outils de lecture hors des dossiers de travail
  (`blockReadsOutsideWorkingDirectories`) ;
- demande une confirmation humaine pour les canaux de sortie et
  l'exécution de code arbitraire : `curl`, `wget`, `python`, `node`,
  `docker run`, `exec` et `cp`, `gh auth`, `gh gist`, `security`, l'ajout
  d'un remote et un `git push` vers une URL.

Une règle `ask` du projet passe devant un `allow` de l'utilisateur, et le mode
auto la respecte (<https://code.claude.com/docs/en/permissions>,
<https://code.claude.com/docs/en/permission-modes>, relu le 15/11/2026). Un
test sans interface l'a confirmé le même jour : `curl --version` est autorisé
sans ce fichier, et bloqué avec lui. Ces règles restent un filtre de motifs, et
un deny sur Read ne couvre pas un script qui ouvre le fichier lui-même. Les
deux vraies barrières sont un jeton GitHub sans droits admin
([docs/securite/jeton-github.md](docs/securite/jeton-github.md)) et le sandbox,
qui fera l'objet d'une PR à part une fois testé avec Docker.

## Méthode

Six phases, chacune fermée par une gate que Lucas valide. On ne passe pas à la
suite sans son accord. La phase en cours est dans `ROADMAP.md`.

Spec Kit est la seule méthode de spécification : `/speckit-specify`,
`/speckit-plan`, `/speckit-tasks`, `/speckit-implement`. Pas de BMAD, et pas
d'autre méthode de planification en parallèle.

Avant chaque phase : un plan court, puis attente de validation. Un golden repo
se construit à la main avant toute mise en template. Chaque choix structurant
passe par un benchmark (`docs/benchmarks/BENCH-XXX-sujet.md`, grille de la
section 8 du brief), puis par un ADR (`docs/adr/ADR-XXX-sujet.md`).

## Conventions

- Langue : docs de cadrage, ADR, benchmarks et README en français. Code,
  identifiants, noms de dossiers et messages de commit en anglais.
- Jamais de tiret cadratin (U+2014), ni dans les réponses ni dans les fichiers.
  Le hook `no-em-dash` le refuse.
- Trunk-based : `main` et des branches courtes `feat/`, `fix/`, `docs/`,
  `chore/`. Une PR traite un seul sujet et se rattache à une tâche ou à un ADR.
- Conventional Commits, vérifiés par commitlint : en local par le hook
  `commit-msg`, en CI sur le titre de la PR. Fusion en squash, donc le titre de
  la PR devient le commit sur `main`.
- Après un clonage : `pre-commit install`. Les mêmes hooks tournent en CI
  (`.github/workflows/ci.yml`), plus un scan gitleaks de tout l'historique.
- Versions des hooks et des actions figées par SHA, avec le tag en commentaire.
- release-please tient les versions et `CHANGELOG.md`. Renovate propose les
  mises à jour, une fois la version publiée depuis au moins 7 jours.
- Réglages GitHub en code : `scripts/github/apply-settings.sh` (fusion en
  squash seule, permissions des workflows) et `.github/rulesets/main.json`. Le
  dépôt est privé sur un compte GitHub Free, donc le ruleset ne s'applique
  qu'au passage en public. En attendant, les garde-fous sont pre-commit et la CI.
- Licence du générateur : Apache-2.0.

## Arborescence

```text
CLAUDE.md          ce fichier
ROADMAP.md         fait, en cours, prochain
docs/              vision, PRD, risques, adr/, benchmarks/
schema/            JSON Schema de la spec projet et exemples
catalog/           services par cible : licence, gouvernance, statut, date
golden/            projets de référence construits à la main
blueprints/        templates Copier : saas-b2b/{common,local,gcp}
plugin/            skills et sous-agents Claude Code du produit
cli/               CLI Python (Copier, validation)
tests/matrix/      génération croisée avec validation
tests/bench/       scripts de mesure des benchmarks
```

Le brief prévoyait `spec/` pour le schéma. Il s'appelle `schema/` parce que
Spec Kit range déjà ses spécifications de fonctionnalités dans `specs/`, et les
deux noms se confondaient.

## Travailler avec Lucas

- Répondre en français.
- Lucas a le dernier mot sur les décisions structurantes. Le challenger quand
  une décision est risquée.
- Petites étapes, petites PR, une chose à la fois.
- Mettre `ROADMAP.md` à jour à la fin de chaque session.
- Une information technique incertaine se dit, puis se vérifie. On ne devine
  pas.
- Expliquer brièvement le pourquoi de chaque choix : Lucas doit pouvoir le
  défendre en entretien ou devant un client.
