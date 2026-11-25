# Registre des risques

Tenu par le DSI. Mis à jour le 25/11/2026. Probabilité et impact sont notés
faible, moyen ou fort : ce sont des jugements, pas des mesures. Un risque se
ferme quand sa mitigation est en place et vérifiée.

## Synthèse

| ID | Risque | Probabilité | Impact | Porteur | État |
| --- | --- | --- | --- | --- | --- |
| R-01 | Protection de `main` non appliquée | Faible | Fort dès la phase 2 | OPS | Fermé : ruleset actif |
| R-02 | Plugins tiers et utilisateur non figés ni relus | Moyenne | Fort | SECU | Ouvert |
| R-03 | Contexte d'agent surchargé, coût en tokens | Forte | Moyen | DSI, FINOPS | Atténué : ECC désactivé |
| R-04 | Critère des 15 minutes hors d'atteinte | Forte | Fort | OPS | Ouvert |
| R-05 | Dépense GCP non maîtrisée | Moyenne | Fort | FINOPS | Ouvert |
| R-06 | Catalogue qui se périme | Forte | Moyen | ARCHI | Ouvert |
| R-07 | Agents capables de lire et d'exfiltrer des secrets | Forte | Fort | SECU | Règles en place (PR #6), jeton à changer |
| R-08 | Checks contournables par le rôle admin | Certaine | Moyen | OPS | Corrigé dans la PR #2 |
| R-09 | Outils trop jeunes | Moyenne | Faible | BENCH | Atténué |
| R-10 | Artefacts AGPL copiés dans le générateur | Faible | Moyen | SECU | Ouvert |
| R-11 | `copier update` en conflit avec le code métier | Forte | Fort | ARCHI | Ouvert |
| R-12 | Dérive du périmètre | Moyenne | Fort | DSI | Atténué |
| R-13 | Dépendance au format des plugins Claude Code | Moyenne | Moyen | ARCHI | Ouvert |
| R-14 | Valeur non confirmée par de vrais utilisateurs | Moyenne | Fort | PO | Ouvert |
| R-15 | Ressources GCP qui survivent à `tofu destroy` | Moyenne | Fort | OPS, FINOPS | Ouvert |
| R-16 | Allocation GitHub Actions épuisée | Faible | Moyen | OPS, FINOPS | Atténué : dépôt public |
| R-17 | Tailles par défaut et démo allumée en permanence | Moyenne | Moyen | FINOPS | Ouvert |
| R-18 | Services GCP facturés au volume | Moyenne | Faible | FINOPS | Ouvert |
| R-19 | Identité GCP de la CI et état OpenTofu | Moyenne | Fort | SECU, OPS | Ouvert |
| R-20 | Identifiants par défaut dans le golden repo | Forte | Fort si atteint GCP | SECU, DEV | Ouvert |
| R-21 | Application Design Center couvre le même besoin sur GCP | Moyenne | Moyen | PO | Ouvert |
| R-22 | Jour 2 dépendant d'un seul outil communautaire | Faible | Fort | ARCHI | Ouvert |
| R-23 | Failles du modèle de confiance de Copier | Forte | Fort | SECU | Ouvert |
| R-24 | Outils du générateur portés par une personne ou un éditeur | Faible | Moyen | ARCHI, DEV | Ouvert |
| R-25 | Démarrage local tributaire des registres publics | Forte | Moyen, fort pour la CI de la matrice | OPS, SECU | Ouvert |
| R-26 | Moteur de conteneurs du poste sous licence payante | Moyenne | Moyen | OPS, FINOPS | Ouvert |
| R-27 | Modules OpenTofu tirés sans contrôle d'intégrité | Faible | Fort | SECU, OPS | Ouvert |
| R-28 | Secrets locaux en clair dans etcd | Moyenne | Faible, fort si un secret réel y entre | SECU, DEV | Ouvert |
| R-29 | Synchronisation des secrets de GKE lue, jamais exécutée | Moyenne | Fort | OPS, SECU | Ouvert |
| R-30 | Boucle locale maison portée par le Taskfile | Moyenne | Moyen | DEV, SECU | Ouvert |
| R-31 | Moteur GitOps différent entre le PC et GCP | Moyenne | Moyen, fort si un contrôle de sécurité diverge | OPS, SECU, QA, FINOPS | Ouvert |
| R-32 | Failles des moteurs GitOps invisibles aux scanners | Moyenne | Moyen, fort pour un moteur en `cluster-admin` | SECU, OPS | Ouvert |
| R-33 | Écrire sur la branche suivie, c'est administrer le cluster | Moyenne | Fort | SECU, OPS | Ouvert |
| R-34 | Miroir de registres sur le PC, nouvelle brique exposée | Faible | Moyen, fort si une image désignée par tag passe par lui | OPS, SECU | Ouvert |
| R-35 | Postgres local écrit à la main dans chaque projet généré | Moyenne | Moyen | DEV, SECU | Ouvert |
| R-36 | Failles connues sans paquet associé, invisibles aux scanners | Moyenne | Moyen | SECU, OPS | Ouvert |
| R-37 | Parcours de connexion différent entre le PC et GCP | Moyenne | Moyen | DEV, QA | Ouvert |
| R-38 | Mise à jour des images sans date suspendue à une personne | Moyenne | Moyen, fort pour l'image d'exécution de l'API | SECU, DSI | Ouvert |
| R-40 | Scanner de secrets du projet généré en maintenance | Forte | Moyen | SECU, DSI | Ouvert |
| R-41 | Jeton de Memorystore sans ressource publiée dans le provider | Moyenne | Moyen | OPS, SECU | Ouvert |

## Détail

### R-01. Protection de `main` non appliquée

Le dépôt était privé sur un compte GitHub Free, et l'API refusait les rulesets :
`Upgrade to GitHub Pro or make this repository public to enable this feature.`
N'importe quel push direct sur `main` passe, et le hook local saute avec
`--no-verify` ou sur un clone où personne n'a lancé `pre-commit install`. En
phase 2, l'identité de déploiement GCP sera liée à `main` : qui pousse sur
`main` déploiera. Les relecteurs obligatoires sur un environnement GitHub, la
parade habituelle, ne sont disponibles sur Free que pour les dépôts publics
(<https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments>,
relevé par [SECU] le 15/11/2026).

Mitigation en place : le ruleset est prêt dans `.github/rulesets/main.json`,
`scripts/github/apply-settings.sh` l'appliquera dès que GitHub l'accepte, et le
scan gitleaks tourne sur chaque push de branche (PR #2). Décision attendue de
Lucas : passer le dépôt en public avant la phase 2, après un scan gitleaks de
toutes les refs. Cela débloque les rulesets, les relecteurs d'environnement et
la protection des pushs, et ferme aussi R-16.

Décision de Lucas du 15/11/2026 : le dépôt est public, c'est voulu. Reste à
appliquer le ruleset avec `scripts/github/apply-settings.sh`, qui demande les
droits admin et que Lucas lance lui-même. R-01 se ferme quand l'API montre le
ruleset actif.

Fermé le 15/11/2026 : Lucas a lancé le script, et l'API montre le ruleset
`main` en `active`, avec les règles `deletion`, `non_fast_forward`,
`required_linear_history`, `pull_request` et `required_status_checks` sur
`main`.

### R-02. Plugins tiers et utilisateur non figés ni relus

Les marketplaces wshobson et HashiCorp ne sont pas figées : un nouveau clone
récupère leur dernière version. Claude Code accepte un SHA complet comme `ref`
de marketplace à partir de la version 2.1.324
(<https://code.claude.com/docs/en/plugins/marketplace-reference.md>, lu le
15/11/2026). Le poste tourne en 2.1.322, d'où l'échec de l'essai du jour.

Une absence de hook et de serveur MCP ne suffit pas : un skill ou un sous-agent
est une instruction suivie par un agent qui dispose du shell. Une mise à jour
piégée en amont s'exécuterait avec les droits de Lucas. La relecture du
15/11/2026 ne couvre que les plugins du projet. Les plugins utilisateur actifs
dans ces sessions (ECC, claude-mem, caveman, 21st, entre autres) n'ont pas été
relus, et claude-mem conserve des observations des sessions dans
`~/.claude-mem`.

Mitigation : contenu des plugins du projet relu aux commits `9c61ab2` et
`5e30fa5`. La mise à jour automatique est désactivée par défaut pour les
marketplaces tierces
(<https://code.claude.com/docs/en/discover-plugins.md>, lu le 15/11/2026).
Actions : passer Claude Code en 2.1.324 ou plus, puis fixer `ref` sur
`9c61ab243def98f72da12abd41cfcf5bcd91af9d` et
`5e30fa5c867ba6777c37e4206babfd08049c396f`. Désactiver dans ce projet les
plugins utilisateur qui n'y servent pas.

### R-03. Contexte d'agent surchargé

Mesure `claude plugin details` du 15/11/2026 : ECC charge environ 48 000 tokens
à chaque session, les huit plugins du projet environ 8 200. Plus le contexte
fixe est lourd, moins il reste de place pour le travail, et plus les
instructions concurrentes se contredisent (ECC apporte ses propres méthodes de
planification, qui doublonnent Spec Kit).

Le coût fixe se répète à chaque délégation : un sous-agent reçoit lui aussi les
règles globales et la liste des skills. La boucle de correction de la phase 5
(« l'agent corrige et relance ») n'a pas encore de nombre d'essais maximal, et
elle consommera des tokens chez chaque utilisateur du produit. Le nombre de
tours dépend aussi du validateur : d'après BENCH-001 (2026-11-19), JSON Schema
signale trois erreurs en une passe là où CUE et Pkl n'en remontent qu'une,
soit jusqu'à trois tours au lieu d'un ([FINOPS]). Le mode de
facturation de Lucas (abonnement plafonné ou clé API à l'usage) reste à
confirmer.

Mitigation proposée : désactiver ECC dans ce projet, garder ses règles de
`~/.claude/rules/ecc/` (elles ne dépendent pas du plugin). Mesurer une tâche de
référence avant et après. Plafonner la boucle de la phase 5 à un nombre
d'essais, puis rendre la main à l'humain. Si un agent tourne un jour en CI, lui
donner une clé dédiée avec plafond de dépense.

Décision de Lucas du 15/11/2026 : ECC est désactivé dans ce projet (PR #4). La
mesure avant et après sur une tâche de référence et le plafond de la boucle de
la phase 5 restent à faire.

### R-04. Critère des 15 minutes hors d'atteinte

Le parcours complet compte l'entretien, la génération, le téléchargement des
images de conteneurs, la création du cluster local, la compilation .NET et
Node, et la CI du premier push.

BENCH-003 a mesuré le cluster seul le 2026-11-19, sur un seul poste (Apple M4
Pro, OrbStack, arm64). La création à froid prend 73,7 s avec kind, 81,0 s avec
k3d et 145,5 s avec minikube, soit 8 à 16 % du budget. La première création
télécharge 352 Mo avec kind, 853 Mo avec minikube et au plus 357 Mo avec k3d,
en volume compressé. À 10 Mbit/s utiles, une hypothèse et non une mesure, ce
téléchargement seul consomme 31 % du budget avec kind et 76 % avec minikube.
k3d et minikube retéléchargent aussi des images à chaque création, même avec
le cache plein : `task up` dépend alors du réseau et de la limite de Docker
Hub (R-25). La probabilité passe à forte si l'outil retenu télécharge plus de
500 Mo à la première création.

BENCH-004 a mesuré la gateway le 2026-11-19 sur le même poste. Avec Envoy
Gateway, cluster et gateway téléchargent 466,5 Mo en arm64 et 505,8 Mo en
amd64 à la première création, soit 41 et 45 % du budget à 10 Mbit/s utiles
(hypothèse). À froid, la création jusqu'à la première réponse prend environ
123 s, calcul de [FINOPS] qui combine BENCH-003 et BENCH-004. Chaque création
interroge Docker Hub pour 2 images, même préchargées (R-25).

Le déclencheur se lit sur le premier `task up` complet, et sur le pire cas des
systèmes visés par Q5, qui comprennent Linux amd64. Lu ainsi, il est franchi
avec Envoy Gateway avant même les images de la stack, qui ne peuvent
qu'ajouter. Le DSI a passé la probabilité à forte le 2026-11-19 ; décision
confirmée par Lucas à la GATE 1 le 2026-11-20.

BENCH-005 a mesuré la stack d'essai le 2026-11-19, à chaud seulement : le
temps à froid n'a pas pu l'être. [FINOPS] a additionné le premier `task up`
complet en amd64 : plate-forme de base 505,8 Mo, secrets créés par `task up`
0 Mo (BENCH-007), outil GitOps sur le PC 258,1 Mo (Flux réduit à ses quatre
contrôleurs, BENCH-009 en relecture), stack 632,0 Mo, soit 1 395,9 Mo. À
10 Mbit/s utiles, une hypothèse, le téléchargement seul prend 1 117 s, soit
124 % du budget de 900 s, et encore 101 % sans GitOps sur le PC. Il faut au
moins 12,4 Mbit/s pour le seul téléchargement, sans compter l'entretien, la
génération, la compilation ni la CI. Le critère d'acceptation ne tient donc pas
à 10 Mbit/s : Lucas tranche à la GATE 1 entre un débit visé écrit dans le
critère et une réduction du volume.

BENCH-010 (2026-11-20) : le miroir zot ajoute 77,68 Mo en linux_amd64 ; la
plate-forme de base passe de 505,8 à 583,5 Mo, contre un budget de 500, et le
premier `task up` du profil standard, hors Keycloak et Mailpit, de 1 395,9 à
1 473,6 Mo.

BENCH-011 (2026-11-21, relecture [FINOPS]) : les 1 395,9 Mo comptaient déjà
une image `postgres:18.7-alpine` (120,3 Mo), dans la stack de BENCH-005. Le
Postgres retenu par Lucas, `postgres:18.7-trixie` sans opérateur, la remplace
et ajoute 48,3 Mo nets. Le premier `task up` du profil standard, hors
Keycloak et Mailpit, passe à 1 444,2 Mo sans miroir et à 1 521,9 Mo avec
zot, soit 135,3 % du budget de 900 s à 10 Mbit/s. ENF-01 est à mettre à jour
dans le PRD.

BENCH-012 (2026-11-24, relecture [FINOPS]) : Keycloak ajoute 265,1 Mo en
amd64 ; le premier `task up` du profil standard, Mailpit non compté, passe à
1 787,0 Mo avec zot et le Postgres de l'ADR-012, soit 158,8 % du budget de
900 s à 10 Mbit/s et 15,9 Mbit/s au minimum. Le profil standard passe à
3,5 Gio de VM et 7,5 Gio de portable au repos. ENF-01 est à mettre à jour
dans le PRD.

BENCH-013 (2026-11-24, relecture [FINOPS]) : Mailpit ajoute 15,1 Mo en
amd64 ; le premier `task up` du profil standard passe à 1 802,1 Mo, soit
160,2 % du budget de 900 s à 10 Mbit/s et 16,0 Mbit/s au minimum. Le palier
ne change pas : 3,5 Gio de VM et 7,5 Gio de portable au repos.

Reste à mesurer : le temps à froid, la compilation de la vraie stack (front
Vite compris) sur le golden repo, et la création du cluster sur un runner
GitHub amd64.

Mitigation : fixer un budget de temps et de volume par étape d'ENF-01, avec un
plafond pour la plate-forme de base (cluster kind, CRD Gateway API et gateway),
périmètre à écrire dans le gabarit de benchmark après la GATE 1 ; écrire le
débit visé dans le critère d'acceptation ; garder le cluster entre deux
`task up` (R-25) ; précharger les images tirées à chaque création, sous le
condensat du registre ; préconstruire les images de la stack ; profil lite par
défaut, sans outil GitOps sur le PC ; un essai de phase 6 sur une ligne lente.

### R-05. Dépense GCP non maîtrisée

GKE, Cloud SQL et Memorystore facturent dès leur création. Une erreur d'IaC ou
un environnement oublié coûte de l'argent réel.

Seul le refus de `tofu apply` aux agents est en place. Une alerte budget ne
plafonne rien : la documentation Cloud Billing précise qu'un budget d'alerte
« doesn't automatically cap Google Cloud [...] usage or spending ». Les budgets
à plafond n'existent que pour quelques services (Cloud Run, Gemini API, Agent
Platform), aucun de ceux du MVP.

Mitigation, à poser avant le premier `tofu apply`, dans cet ordre :

- un projet GCP dédié aux démos, sur un compte de facturation qui ne porte rien
  d'autre ;
- un budget sur ce projet, avec seuils sur le réel et sur le prévisionnel,
  envoyé à Lucas ;
- des quotas abaissés sur ce projet (vCPU régionaux, IP externes, GPU à zéro),
  seul plafond dur possible pour ces services (mécanisme à vérifier sur la
  documentation Cloud Quotas) ;
- des labels obligatoires (`owner`, `env`, `ttl`) posés par le provider, et une
  règle conftest qui refuse un plan hors profil démo ;
- aucun identifiant GCP en CI.

Le montant du budget se calcule en phase 2, depuis les pages tarifaires, une
fois la région choisie. Il doit être prêt avant la GATE 2.

Sources lues le 15/11/2026 par [FINOPS] :
<https://docs.cloud.google.com/billing/docs/how-to/budgets>,
<https://docs.cloud.google.com/billing/docs/how-to/budgets-spend-caps>.

### R-06. Catalogue qui se périme

Licences qui changent (Terraform, Vault), projets archivés (MinIO), services
retirés (Azure Cache for Redis) : le catalogue vieillit sans bruit.

Mitigation : chaque entrée porte sa date de vérification et ses sources
(principe IV). Depuis l'ADR-009, un contrôle bloque la CI sur chaque PR et
chaque push sur `main` : une cible vérifiée il y a 6 mois ou plus, une cible
open source sans release depuis 12 mois, ou un statut autre que `active`. Le
même contrôle tourne chaque semaine, pour que l'échéance se voie sans PR.
GitHub désactive une tâche planifiée après 60 jours sans activité dans un
dépôt public : le contrôle sur PR reste donc la barrière principale. L'idée
« alertes catalogue » reste après le MVP.

### R-07. Agents capables de lire et d'exfiltrer des secrets

Les sessions tournent en mode auto : un classifieur valide les actions à la
place d'une personne. Les règles de `~/.claude/settings.json` pré-approuvent
notamment `gh auth`, `git push`, `curl`, `docker` et `python3 -c`. Avec elles,
un agent peut afficher le jeton `gh` (droits admin sur le dépôt), lire un
`.env`, un état OpenTofu ou `~/.config/gcloud` par un sous-processus, puis
l'envoyer dehors. La documentation le dit : une règle deny n'est pas une
frontière de sécurité autour d'un programme, et un deny sur Read ne s'applique
pas aux sous-processus (<https://code.claude.com/docs/en/permissions>, relevé
par [SECU] le 15/11/2026). Le vecteur le plus probable : une page web ou un
README piégé, lu par un rôle qui a à la fois WebFetch et le shell (BENCH, DEV,
OPS, SECU). Aujourd'hui fuirait le jeton `gh` ; en phase 2, les identifiants
GCP.

Mitigation proposée par [SECU] :

- dans `.claude/settings.json` du projet, des règles `ask` sur `Bash(gh *)`,
  `Bash(git push *)`, `Bash(curl *)`, `Bash(docker *)` et `Bash(python3 *)` (une
  règle ask l'emporte sur un allow) ;
- `permissions.blockReadsOutsideWorkingDirectories` à `true`, et des deny sur
  `~/.config/gcloud` et `~/.config/gh` ;
- le sandbox avec une liste blanche réseau, seule barrière que la
  documentation reconnaît ;
- au quotidien, un jeton `gh` à grain fin sans droits admin.

Décision de Lucas du 15/11/2026 : la PR #6 met en place les règles ask et
deny, `blockReadsOutsideWorkingDirectories` et la procédure de changement de
jeton (`docs/securite/jeton-github.md`). Écarts avec la proposition : ask sur
`docker run`, `exec` et `cp` plutôt que sur tout `docker`, pour ne pas bloquer
les mesures de la phase 1 ; `git push` vers `origin` reste libre, seul un push
vers une URL ou un nouveau remote demande confirmation. Le sandbox fera l'objet
d'une PR à part, après un test avec Docker. Le risque reste ouvert tant que le
jeton classique n'est pas révoqué.

### R-08. Checks contournables par le rôle admin

Le ruleset prévoyait que le rôle admin puisse contourner les checks via une PR,
pour les PR de release-please. Or une PR ouverte ou mise à jour avec le
`GITHUB_TOKEN` déclenche bien `pull_request`, dans un état qui attend
l'approbation d'une personne ayant l'accès en écriture
(<https://docs.github.com/en/actions/concepts/security/github_token>, vérifié
le 15/11/2026). Le contournement était donc inutile, et il rendait les checks
facultatifs pour toutes les PR de la seule personne qui fusionne.

Correction : `bypass_actors` retiré de `.github/rulesets/main.json` (PR #2). Sur
une PR de release, Lucas approuve l'exécution de la CI avant de fusionner.

### R-09. Outils trop jeunes

specify-cli 1.4.0 avait cinq jours au moment de l'installation, ce qui
contredit la règle des 7 jours de la constitution. Choix assumé : c'est la
version que décrit le README officiel du jour. Renovate ne voit pas non plus
les outils du poste (Claude Code, plugins, `uv tool`).

Mitigation : versions figées partout, Renovate attend 7 jours après chaque
publication pour ce qu'il gère, les benchmarks écartent les projets sans recul.
Les outils du poste se mettent à jour à la main, en notant la version dans
`ROADMAP.md`. Relevé par [SECU] le 2026-11-19 : `uv tool run --exclude-newer
"7 days"` et la clé npm `min-release-age` appliquent aussi la règle des 7 jours
aux outils lancés par `uvx` et `npx`.

### R-10. Artefacts AGPL copiés dans le générateur

Le générateur est sous Apache-2.0. Copier dans `golden/` ou `blueprints/` des
tableaux de bord ou des configurations sous AGPL (Grafana, Garage) mélangerait
les licences. Côté utilisateur le risque est plus faible : la pile LGTM ne
tourne qu'en local, et la cible GCP passe par des services managés. Les
obligations de l'AGPL pour un logiciel modifié et accessible par le réseau
(article 13) sont à vérifier sur
<https://www.gnu.org/licenses/agpl-3.0.html>.

Mitigation : référencer les artefacts amont par leur version au lieu de les
copier, scanner les licences de `golden/` et `blueprints/` en CI, signaler la
licence dans le catalogue et dans l'ADR généré.

### R-11. `copier update` en conflit avec le code métier

Le « jour 2 » est un pilier de CELIAN, même si Copier le fournit (R-22). Sur
un projet où l'équipe a
modifié des fichiers du socle, une mise à jour du blueprint produira des
conflits.

Mitigation : séparer dans le blueprint ce qui relève du socle et ce qui
appartient à l'équipe. Tester `copier update` dans la matrice de la phase 4,
sur un projet généré puis modifié.

Constat de BENCH-002 (2026-11-19) : Copier 9.19.1 rend le code de sortie 0
même quand un conflit reste à résoudre. La CLI et la matrice ne doivent pas
s'y fier : elles vérifient `git diff --name-only --diff-filter=U` et cherchent
les marqueurs de conflit.

### R-12. Dérive du périmètre

Les idées de la section 12 du brief sont attirantes et toutes hors MVP.

Mitigation : non-objectifs écrits dans la constitution et le PRD, refus
systématique par le DSI, idées notées dans `ROADMAP.md`.

### R-13. Dépendance au format des plugins Claude Code

Le produit prend la forme d'un plugin Claude Code. Le format des plugins, des
skills et des sous-agents évolue : Spec Kit a changé de syntaxe entre deux
versions récentes.

Mitigation : garder dans la CLI Python tout ce qui est déterministe
(génération, validation), pour que le plugin reste une couche fine. La CLI doit
fonctionner seule.

### R-14. Valeur non confirmée par de vrais utilisateurs

Le persona est une hypothèse du brief. Aucune personne de la cible n'a encore
vu le produit.

Mitigation : le test d'acceptation de la phase 6 se fait avec une personne
extérieure. Montrer le golden repo de la phase 2 à un ou deux devs de la cible
avancerait ce retour.

### R-15. Ressources GCP qui survivent à `tofu destroy`

Les load balancers créés par la Gateway API, les disques des PVC et leurs
adresses IP naissent de Kubernetes, hors de l'état OpenTofu. `tofu destroy` ne
les voit pas, et ils continuent de facturer. Arrêter au lieu de détruire ne
suffit pas non plus : une instance Cloud SQL arrêtée paie encore son stockage
et ses adresses IP
(<https://docs.cloud.google.com/sql/docs/postgres/start-stop-restart-instance>,
lu le 15/11/2026).

La protection contre la suppression, active par défaut sur Cloud SQL et GKE
dans les trois socles de BENCH-008 (2026-11-19), fait échouer `tofu destroy`.
Le démontage se fait donc en deux temps : un apply qui lève la protection,
lancé par l'utilisateur, puis le destroy. Sinon le cluster et l'instance
restent et facturent.

Mitigation : une procédure de démontage écrite (supprimer les Gateways et les
PVC, lever la protection contre la suppression par un apply, puis
`tofu destroy`), ou la suppression du projet entier. Contrôle le lendemain dans
le rapport de facturation filtré sur le projet. [OPS] vérifie en phase 2 ce
qu'un destroy partiel laisse derrière lui.

### R-16. Allocation GitHub Actions épuisée

Sur GitHub Free, un dépôt privé dispose chaque mois de 12 USD de calcul inclus,
500 Mo de stockage d'artefacts (partagés avec Packages) et 10 Go de cache par
dépôt. Une minute de runner Linux standard coûte 0,006 USD
(<https://docs.github.com/en/billing/concepts/product-billing/github-actions>,
lu le 15/11/2026). La matrice de la phase 4 (k3d, builds .NET et Node, scans)
lancée à chaque PR, les dépôts générés pour les tests et les images poussées
sur GHCR consommeront cette allocation. Sans moyen de paiement, la CI s'arrête
une fois l'allocation épuisée, et plus aucune PR ne peut passer.

Mitigation : lancer la matrice la nuit ou sur label, filtres de chemins,
annulation des exécutions dépassées (déjà en place), rétention courte des
artefacts, runners Linux seulement. Sur un dépôt public, les runners standard
sont gratuits : passer en public fermerait aussi R-01. Décision de Lucas du
15/11/2026 : le dépôt est public. Restent les limites de stockage et de cache,
à suivre en phase 4.

### R-17. Tailles par défaut et démo allumée en permanence

Le critère « se déploie sur GCP en moins de 15 minutes » pousse à garder un
environnement allumé, ce qui contredit le démontage de R-05 et R-15. Côté
produit, les tailles par défaut du blueprint (dev, staging, prod) deviennent la
facture de chaque utilisateur, sans estimation avant génération puisque
Infracost est hors MVP.

Mitigation : les 15 minutes couvrent un plan valide, l'apply réel étant mesuré
à part, et un seul environnement est déployé sur GCP (PRD section 7, questions
Q1 et Q6, validées à la GATE 0 le 15/11/2026). Reste à compter les apply réels
prévus aux phases 2 et 6, et à faire valider par [FINOPS] les tailles par
défaut du blueprint.

GKE Autopilot est toujours régional (BENCH-008, 2026-11-19) : le profil démo ne
peut pas être zonal pour GKE. Les frais de cluster restent couverts par l'offre
gratuite, qui vise un cluster Autopilot par mois, et Autopilot facture les
demandes de ressources des pods, pas les nœuds. Le profil démo repose donc sur
des requêtes explicites et minimales pour chaque pod (sans requête, Autopilot
applique 0,5 vCPU et 2 Gio), une réplique par Deployment, Cloud SQL zonal à
cœur partagé en édition ENTERPRISE, Memorystore BASIC, une limite
d'agrandissement du disque de Cloud SQL et une alerte budget déclarée dans le
code. Les grilles tarifaires de Cloud SQL, Memorystore et du réseau n'ont pas
pu être lues le 2026-11-19 : aucun budget de démo n'est validable avant leur
lecture (R-05).

### R-18. Services GCP facturés au volume

Cloud Logging et Cloud Monitoring facturent l'ingestion des journaux GKE et des
exports OpenTelemetry. Artifact Registry accumule chaque image avec sa
signature et son SBOM. Secret Manager facture les accès, et External Secrets
Operator interroge à chaque `refreshInterval`. Identity Platform facture au-delà
d'un seuil d'utilisateurs actifs, et chaque SMS : une connexion par téléphone
ouverte sur une démo publique expose à la fraude au SMS. Tarifs et franchises
à vérifier en phase 2.

Mitigation : filtres d'exclusion et rétention minimale des journaux, règle de
nettoyage dans Artifact Registry, registre dans la région du cluster,
`refreshInterval` raisonnable, fournisseur téléphone désactivé.

### R-19. Identité GCP de la CI et état OpenTofu

La pente naturelle est une clé JSON de compte de service rangée dans les
secrets GitHub. Avec la fédération d'identité, Google exige une condition
d'attribut, mais son exemple sur `assertion.repository_owner` admettrait
n'importe quel dépôt du compte
(<https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines>,
relevé par [SECU] le 15/11/2026). L'état distant peut contenir des mots de
passe générés (à vérifier pour OpenTofu), et le refus de `Read(**/*.tfstate)` ne
bloque ni `tofu state pull`, ni `tofu show`, ni `tofu output`. Ce câblage
partira ensuite dans le blueprint, donc chez chaque utilisateur.

Vérifié le 2026-11-19 (BENCH-008, relecture [SECU]) : la chaîne AUTH de
Memorystore (`auth_string`) est écrite en clair dans l'état dès que AUTH est
activé, et le compte de `tofu plan` lit l'état. Le provider `google` 8.12.0
offre `password_wo`, `root_password_wo` et `secret_data_wo`, et `random` 3.9.1
un `random_password` éphémère, gérés par OpenTofu à partir de 1.11. Google
déconseille de filtrer la fédération sur des noms (`repository`,
`repository_owner`), qu'un tiers peut reprendre après un renommage, et
recommande les champs `*_id`.

Mitigation : aucune clé de compte de service. Condition de fédération sur
`assertion.repository_id`, `assertion.repository_owner_id` et `assertion.ref`,
`principalSet` sur `repository_id`. Compte de service en lecture seule pour
`tofu plan`, l'apply restant manuel (principe X). Règles `ask` sur
`tofu state`, `tofu show` et `tofu output`. État et plans chiffrés par OpenTofu
avec `gcp_kms`, attributs `*_wo` obligatoires, aucun plan publié en artefact de
CI (ADR-008).

### R-20. Identifiants par défaut dans le golden repo

Keycloak, OpenBao en mode dev, Postgres et Grafana démarrent avec un mot de
passe connu ou sans mot de passe. Pour tenir `task up` en une commande, la
tentation sera de les écrire dans le dépôt, contre le principe IX, et gitleaks
ne détecte pas un mot de passe sans entropie comme `admin`. Ils partiraient
dans chaque projet généré, avec un réemploi possible sur GCP.

Mesuré par BENCH-003 le 2026-11-19 (macOS, OrbStack) : un port publié sans
adresse écoute sur toutes les interfaces (0.0.0.0 et `[::]`) avec k3d, kind et
minikube, comme tout `docker run -p`, dont c'est le défaut documenté. k3d
publie en plus par défaut l'API Kubernetes et son registre sur 0.0.0.0, et ce
registre accepte un `docker push` sans authentification : une machine du même
réseau peut y déposer une image que le cluster exécutera. kind et minikube
publient l'API sur 127.0.0.1 ; minikube y ajoute SSH, le démon Docker du nœud
(2376), son registre et le port 32443, tous en boucle locale. Sous Linux, un
port publié par Docker passe avant les règles d'ufw. Un service publié sur
toutes les interfaces avec un identifiant par défaut s'ouvre à tout le réseau
local du poste.

Complément vérifié le 2026-11-19 par BENCH-007, relu par [SECU]. La
mitigation par un `.env` est retirée : un fichier dans le dossier du projet
est lisible par tout processus du poste, agent compris (R-07), et part dans
Git le jour où le `.gitignore` manque. `kubectl apply` recopie la valeur d'un
Secret dans l'annotation `last-applied-configuration`, et sous bash 3.2 un
heredoc passe par un fichier temporaire. Task affiche chaque commande avant de
la lancer, et son option `secret: true` ne couvre ni `ps` ni la sortie des
commandes. Dans le chart d'OpenBao, le mode dev est désactivé par défaut ;
activé, il prend le jeton racine `root`. L'exemple du fournisseur `vault`
d'ESO stocke lui aussi le jeton `root`.

Mitigation : `task up` tire chaque valeur de `/dev/urandom` et la passe par un
tube à `kubectl create -f -`, seulement si le Secret n'existe pas. Jamais
`kubectl apply` pour un Secret, ni de heredoc. Aucune valeur dans un fichier,
une variable de Task ou un argument de commande ; les tâches qui manipulent un
secret sont silencieuses. Un test de la matrice lance deux `task up` sur deux
clusters neufs et échoue si une valeur se répète, fait moins de 32 caractères
ou figure dans une liste de valeurs connues (`root`, `admin`, `postgres`,
`password`, `changeme`, chaîne vide). Le mode dev d'OpenBao et l'exemple
`root` de la documentation d'ESO ne sont jamais recopiés. Le README dit que
les secrets locaux sont en clair dans le cluster (R-28). Un test de la matrice
et une politique conftest échouent si un identifiant par défaut atteint la
cible GCP. Le blueprint fixe
127.0.0.1 sur l'API et sur chaque port publié (`listenAddress` pour kind,
`--ports=127.0.0.1:…` pour minikube, `--api-port 127.0.0.1:…` et
`-p 127.0.0.1:…` pour k3d ; pour le registre de k3d, `NOM:127.0.0.1:PORT`,
documenté mais non essayé). Un test de la matrice relève les ports en écoute
après `task up` et échoue sur toute adresse 0.0.0.0, `[::]` ou `*`. Si
minikube est retenu, `task up` met `$MINIKUBE_HOME` en 700 : minikube 1.39.0
y recopie à chaque démarrage la clé client du démon Docker du nœud en mode
0777.

Complément de BENCH-005, relu par [SECU] le 2026-11-20 : la couche locale
impose un mot de passe à Valkey comme à Postgres, transmis par un Secret et
jamais en argument de commande. Aucun objet `Secret` ni `secretGenerator` sous
`k8s/` : les Secrets locaux naissent par `kubectl create -f -` avant
`kubectl apply -k`. Les valeurs locales ne passent jamais par un chart Helm,
dont les Secrets de release les garderaient, jusqu'à dix révisions par défaut.

ADR-013 (24/11/2026) : la liste des valeurs connues de la condition 1 de
l'ADR-007 reçoit trois valeurs relevées par [SECU] dans BENCH-012 :
`keycloak` (mot de passe de base du manifest de démarrage de Keycloak),
`change_me` (exemple de la page des conteneurs de Keycloak, distinct de
`changeme`) et `Password1!` (défaut de Zitadel). Le test vise toutes les clés
secrètes d'une couche, secret du client compris, et non les seuls mots de
passe.

ADR-014 (24/11/2026) : la liste des valeurs connues reçoit `password1` et
`password2`, exemple de la page de configuration de Mailpit
(`MP_UI_AUTH="user1:password1 user2:password2"`). Pour une clé de la forme
`utilisateur:mot de passe`, comme `mp-ui-auth`, le test vise la partie qui
suit le premier `:`, et le tirage exclut l'espace et le `:`.

### R-21. Application Design Center couvre le même besoin sur GCP

L'analyse des outils existants
([benchmarks/analyse-outils-existants.md](benchmarks/analyse-outils-existants.md),
15/11/2026) relève Application Design Center de Google, avec Gemini : il
touche cinq des six piliers de CELIAN, chacun en partie. Il est propriétaire,
limité à Google Cloud d'après les pages lues, sans équivalent sur PC, et nomme
des produits concrets au lieu d'une spec abstraite. Un tech lead qui ne vise
que GCP pourrait s'en contenter.

Mitigation : tenir la différence là où il ne va pas, la parité PC et la
spec abstraite indépendante du fournisseur. Revoir son périmètre avant la
GATE 1 et avant la démo de la phase 6, sources datées à l'appui.

### R-22. Jour 2 dépendant d'un seul outil communautaire

Le jour 2 de CELIAN repose sur `copier update`. D'après l'analyse, Copier est
sous licence MIT et porté par l'organisation copier-org, sans entreprise ni
fondation citée. Si le projet ralentit ou change de cap, le pilier 5 tombe
avec lui. Cookiecutter n'offre pas de repli : cruft, son outil de mise à jour,
n'a rien publié depuis plus de 12 mois.

Mitigation : BENCH-002 mesure le jour 2 de chaque option et vérifie l'activité
de Copier. Version de Copier figée dans la CLI et mise à jour par Renovate.
Repli documenté dans l'ADR : le mécanisme de JHipster, une branche dédiée au
gabarit puis une fusion Git, qui ne dépend d'aucun outil tiers.

Constat de BENCH-002 (2026-11-19) : Copier reste actif, 23 releases en 12
mois. 76 % des commits humains de l'année viennent d'un seul mainteneur, et
aucune fondation ne le porte. Le repli par branche Git dédiée puis fusion a été
essayé trois fois : même résultat que `copier update`, conflit compris.

### R-23. Failles du modèle de confiance de Copier

Copier a publié 15 avis de sécurité du 2025-08-18 au 2026-10-12, dont 8
élevés, tous corrigés vite (BENCH-002, relu par [SECU]). Trois classes : dix
évasions du mode « gabarit sûr », quatre contournements du préfixe de
confiance, et une injection d'argument Git qui exécute une commande sans
aucune confiance accordée ; l'avis cite comme vecteur un `_src_path` piégé dans
`.copier-answers.yml` au moment de `copier update`, sans l'avoir reproduit. Un correctif a lui-même introduit une faille. Le
mode sûr et la confiance ne tiennent donc pas comme barrière. Le projet généré
étant modifiable par tout contributeur, son fichier de réponses est une entrée
non fiable. De plus, 8 des 15 avis manquent à la base globale GitHub Advisory
Database et à OSV : les scanneurs qui les lisent jugent saines des versions
vulnérables (comportement exact de Renovate, Trivy et Dependency-Track à
vérifier).

Mitigation, conditions reprises dans l'ADR du moteur de templates : la CLI
refuse Copier antérieur à 9.19.0 et Jinja2 antérieur à 3.1.6 ; Copier figé
dans le verrou avec un plafond `<10` ; la CLI ne rend que les blueprints de
CELIAN, par un `vcs_ref` en SHA, et vérifie `_src_path` et `_commit` avant
toute mise à jour ; jamais `--trust` ni `unsafe=True`, aucun `_tasks`,
`_migrations` ou `_jinja_extensions` dans les blueprints, vérifié par un test ;
`COPIER_SETTINGS_PATH` pointe vers un fichier sans liste de confiance. [SECU]
relit chaque semaine la page des avis de copier-org/copier tant que la base
globale reste en retard.

### R-24. Outils du générateur portés par une personne ou un éditeur

Deux briques pressenties dépendent d'une seule personne ou d'un seul éditeur
(BENCH-001 et BENCH-006, relus par [SECU] le 2026-11-19).
python-jsonschema, le validateur de la spec : 135 des 145 commits humains des
12 derniers mois viennent de l'auteur principal, qui porte aussi ses
dépendances `referencing` et `jsonschema-specifications`. Sa dernière version
date du 2026-01-07 : sans nouvelle version au 2027-01-07, il tombe sous le
critère de release. uv, pressenti pour installer la CLI : Astral a annoncé le
2026-03-19 rejoindre OpenAI, sans rien dire de la licence ni de la gouvernance,
et uv fournit aussi l'interpréteur Python.

Mitigation : un validateur remplaçable, puisque JSON Schema est une norme ;
une vérification datée du 2027-01-07 ; aucune dépendance de la CLI à uv ; une
voie d'installation par pipx, avec un Python hors uv, documentée.

### R-25. Démarrage local tributaire des registres publics

Mesuré par BENCH-003 le 2026-11-19 : même avec un cache Docker plein, k3s
retélécharge 7 images système à chaque création d'un cluster k3d, et minikube
1.39.0 l'image de son CNI, `kindest/kindnetd`, depuis Docker Hub. kind n'en
tire aucune. Ces images sont désignées par tag, sans condensat : leur contenu
est celui que le registre sert ce jour-là, et kindnetd tourne sur le réseau de
l'hôte avec `NET_ADMIN`. Docker Hub limite les tirages anonymes à 100 par
adresse IPv4 ou sous-réseau IPv6 /64 sur 6 heures
(<https://docs.docker.com/docker-hub/usage/pulls/>, lu le 2026-11-19).
Plusieurs postes derrière une même adresse, ou la CI de la matrice qui crée un
cluster par combinaison, peuvent atteindre la limite : `task up` échoue ou
dépasse les 15 minutes (R-04). Les images du blueprint ajoutent leurs propres
tirages au premier lancement.

BENCH-004 a trouvé la cause le 2026-11-19, et [SECU] l'a vérifiée sur
l'archive. `kind load docker-image` passe par `docker save`. Avec un moteur à
magasin d'images classique, l'archive ne garde pas le condensat de l'index du
registre (<https://docs.docker.com/engine/storage/containerd/>, lu le
2026-11-19). Une image désignée par condensat et préchargée ainsi est donc
résolue de nouveau au registre à chaque création. Le dernier maillon, le
passage par containerd dans le nœud, est déduit et n'a pas été observé.
L'intégrité tient, puisque le runtime tire par condensat et vérifie le contenu.

« kind n'en tire aucune » reste vrai pour le nœud seul, et devient faux pour la
stack. Toute image du blueprint désignée par condensat (ENF-03) repasse par le
registre à chaque `task up`. Docker Hub compte un GET de manifest comme un
tirage : on attend un tirage compté par image Docker Hub et par création, chiffre
à mesurer. La condition 7 de l'ADR-004, relancer `task up` hors réseau,
échouera en l'état. Le DSI a passé la probabilité à forte le 2026-11-19, parce
que la dépendance ne tient plus à k3d ou minikube : elle touche chaque `task up`
avec kind. Décision confirmée par Lucas à la GATE 1 le 2026-11-20.

Mitigation : retenir un outil qui ne tire rien à la création, et précharger
sous le condensat du registre, pas seulement sous le tag. [OPS] essaie avant le
golden repo trois pistes :

- un registre miroir local, en boucle locale et figé par condensat (conditions
  1 et 3 de l'ADR-004) ;
- une archive OCI qui garde l'index du registre, chargée par
  `kind load image-archive` ;
- le magasin containerd du moteur, par défaut sur les installations neuves de
  Docker Engine 29.0 et plus, alors que les mesures ont tourné en overlay2.

Le reste de la mitigation : images du cluster et du blueprint figées par
condensat ; un test de la matrice qui relance `task up` hors réseau après un
premier lancement ; un cache d'images dans la CI, et les tirages authentifiés
documentés comme option. Deux reculs sont refusés : revenir à des références
par tag, contraire à la condition 3 de l'ADR-004, et `imagePullPolicy: Never`,
qui fait échouer le démarrage d'une image par condensat absente sous ce nom.

Mesuré par BENCH-005 le 2026-11-19, relu par [SECU] le 2026-11-20 : avec Tilt,
sans outil ou avec Aspire, chaque `task up` crée un nœud kind neuf, dont le
containerd ne voit pas le cache Docker du poste. Postgres, Valkey et toute
image que la stack ne construit pas sont donc retéléchargés à chaque
lancement, depuis Docker Hub, qu'ils soient figés par condensat ou non. Le
même jour, ces tirages sont restés bloqués 15 minutes et `task up` a échoué.
Aspire 17.0.0 y ajoute son tableau de bord, tiré par tag depuis MCR. La cause
vérifiée pour BENCH-004 ne fait que s'y ajouter : précharger ces images par
`kind load docker-image` ne suffirait pas. La première piste à évaluer devient
donc de garder le cluster entre deux `task up`. US-005 demande une commande qui
« arrête et supprime l'environnement » : supprimer l'application en gardant le
cluster peut s'y lire, question pour [PO] et [ARCHI].

Complément de BENCH-009, relu par [SECU] le 2026-11-19 : les images de l'outil
GitOps sont elles aussi retéléchargées à chaque création du cluster kind, quel
que soit l'outil. Les manifests amont les désignent par tag ; le blueprint les
fige par condensat (condition 3 de l'ADR-004). `IfNotPresent` ne suffit pas :
préchargées par `kind load docker-image` depuis un magasin classique, elles
perdent le condensat du registre et repassent par lui. Argo CD demande en plus
un correctif, puisque 8 de ses conteneurs sont en `imagePullPolicy: Always`,
sauf si la mitigation retenue est un miroir local déclaré à containerd.
Revenir aux tags pour faire marcher `kind load` est refusé.

Complément de BENCH-007, relu par [SECU] le 2026-11-19 : un miroir local
alimenté sur le poste ne redistribue rien. Un miroir publié par CELIAN, lui,
redistribuerait chaque image avec toutes ses couches. Pour OpenBao, la
MPL-2.0 demanderait d'indiquer où trouver le source, et sa base Alpine
contient busybox sous GPL-2.0-only. La question vaut pour toutes les images du
blueprint. Avant tout miroir publié : licences relevées couche par couche
(SBOM), et source indiqué pour les couches sous MPL ou GPL.

Complément de BENCH-010, relu par [SECU] et [FINOPS] le 2026-11-20 : le
dernier maillon est observé. Avec des archives de `docker save` chargées par
`kind load image-archive`, la recréation hors réseau échoue trois fois sur
trois, parce que containerd range chaque image sous le condensat de l'archive
et non sous celui du registre. Le kubelet repart alors au registre.
Mitigation retenue par le DSI le même jour : un miroir local zot 2.1.23, seul
mécanisme qui recrée le cluster hors réseau, sous les conditions de R-34.

### R-26. Moteur de conteneurs du poste sous licence payante

Les trois outils de cluster local mesurés par BENCH-003 tournent sur un moteur
de conteneurs que le projet généré ne fournit pas. Docker Desktop n'est
gratuit que pour les entreprises de moins de 250 salariés et de moins de
10 millions de dollars de chiffre d'affaires, pour l'usage personnel,
l'éducation et l'open source non commercial
(<https://docs.docker.com/subscription/desktop-license/>, lu le 2026-11-19).
OrbStack, qui a servi aux mesures, n'est pas libre. Un prérequis payant sur le
PC contredirait le principe III. kind et minikube documentent Podman, alors
que k3d exige Docker (BENCH-003, sources S4, S17 et S27).

Mitigation : [OPS] évalue avec Q5 un moteur libre pour chaque système visé, et
le README du projet généré le cite en premier. La matrice de validation tourne
sur au moins un moteur libre.

### R-27. Modules OpenTofu tirés sans contrôle d'intégrité

Le verrou d'OpenTofu ne suit que les providers
(<https://opentofu.org/docs/language/files/dependency-lock/>, lu le
2026-11-19). Un module tiré par un tag Git est recloné à chaque `tofu init`,
sans somme de contrôle : qui déplace le tag change le code qui crée
l'infrastructure de chaque projet généré. Au plan, une source de données
`external` exécute un programme qui reçoit l'environnement du processus,
identifiants de la CI compris (relevé par [SECU] le 2026-11-19, BENCH-008).
Mesuré par BENCH-008 : un clone par init pour Cloud Foundation Fabric, neuf
pour terraform-google-modules. Les modules servis par le registre d'OpenTofu
sont extraits par le SHA de commit qu'il a enregistré.

Mitigation : aucun module tiré par tag. Modules tiers copiés dans le blueprint
(dossiers `modules/<nom>` seuls, licence et en-têtes gardés, fichiers modifiés
signalés), ou à défaut figés par SHA complet, sans `depth`.
`tofu init -lockfile=readonly` dans la CI. Toute montée de version d'un module
copié passe par une relecture [SECU]. L'ADR-008 retient des modules écrits à la
main, ce qui écarte le risque pour le MVP tant qu'aucun module tiers n'entre.

### R-28. Secrets locaux en clair dans etcd

Sur le PC, les Secrets de l'application sont en clair dans etcd : kind ne
configure aucun chiffrement au repos, et les valeurs survivent au redémarrage
du nœud, donc sur son stockage (BENCH-007, mesures M7 et M8, 2026-11-19). Le
kubeconfig que kind écrit dans `~/.kube/config` donne l'administration du
cluster à tout processus de l'utilisateur, agent compris (R-07). Aucune des
options de BENCH-007 ne protège mieux, puisque toutes finissent dans un Secret
Kubernetes. Le risque naît quand une valeur réelle y entre : copie d'un secret
de GCP, clé d'un service tiers. Un développeur qui débogue sera tenté de le
faire.

Mitigation : valeurs aléatoires et jetables, tirées par `task up` (R-20) ;
aucune tâche ne lit Secret Manager vers le cluster local ; identifiants de
services tiers limités à des clés de test, saisis par l'entrée standard,
jamais dans un fichier du dépôt ; gitleaks en pre-commit et en CI ; le README
le dit.

### R-29. Synchronisation des secrets de GKE lue, jamais exécutée

Sur GCP, les Secrets de l'application viendront de la synchronisation de GKE
(`SecretProviderClass` et `SecretSync`), proposée par l'ADR-007. Elle est GA
depuis le 2026-04-16 et compatible Autopilot, avec GKE 1.33 ou plus et
Workload Identity Federation for GKE
(<https://docs.cloud.google.com/secret-manager/docs/release-notes> et
<https://docs.cloud.google.com/secret-manager/docs/sync-k8-secrets>, lus le
2026-11-19). BENCH-007 l'a lue sans l'exécuter (principe X). Restent ouverts
la contrainte « same region as the cluster » face à un secret global, le
câblage IAM secret par secret, et la conduite en cas de conflit avec un Secret
existant. Sans ses Secrets, le déploiement sur GCP échoue, et le critère
d'acceptation du MVP avec lui.

Avec la rotation activée, la synchronisation relit chaque secret toutes les
2 minutes par défaut, au-delà de la franchise de 10 000 accès par mois dès un
seul secret ([FINOPS], R-18).

Mitigation : un test de la matrice sur GKE Autopilot, avec l'accord de Lucas
et un budget de [FINOPS] ; version minimale 1.35.5-gke.1163012, qui recrée un
Secret supprimé ; `roles/secretmanager.secretAccessor` donné secret par secret
au compte de service Kubernetes, jamais au niveau du projet ; intervalle de
relecture d'au moins 15 minutes pour 3 secrets ; repli sur ESO, qui ne change
que la couche de cible, avec `scopedNamespace` et `scopedRBAC` essayés avant
usage.

### R-30. Boucle locale maison portée par le Taskfile

Si l'ADR-006 retient l'option sans outil de boucle (BENCH-005), `task up` et
`task reload` portent seuls la construction des images, leur chargement dans
kind, la création des Secrets locaux et l'application des manifests. Ce code
est écrit par CELIAN et copié dans chaque projet généré. Il peut dériver : un
Secret appliqué par `kubectl apply` ou par `secretGenerator` de kustomize, qui
recopie la valeur dans l'annotation `last-applied-configuration` ; un
`task reload` qui s'écarte de `task up` ; un outil de boucle installé par le
développeur sans relecture. La boucle n'a pas de rechargement à chaud : le
front se recharge en 5,1 s au lieu de 0,6 s avec Tilt, et plus lentement avec
un vrai build Vite. La gouvernance de Task, qui porte cette boucle, n'a encore
été notée par aucun benchmark.

Mitigation : `task up` et `task reload` couverts par la matrice de validation
(principe I) ; Secrets créés par `kubectl create -f -` alimenté par un tube,
avant `kubectl apply -k` ; un test ou une politique conftest refuse tout objet
`Secret` et tout `secretGenerator` sous `k8s/` ; tâches qui manipulent un
secret silencieuses (R-20) ; licence et gouvernance de Task relevées au
catalogue ; procédure documentée pour ajouter un outil de boucle facultatif
au-dessus de `k8s/`, après relecture [SECU].

### R-31. Moteur GitOps différent entre le PC et GCP

Dans le montage que propose l'ADR-010 (BENCH-009), Flux synchronise le
cluster local et Config Sync, service managé de GKE, synchronise GCP. Les
objets de liaison diffèrent, et le service managé n'a jamais tourné chez nous
(principe X) : ses faits viennent de la documentation de Google. Config Sync
ne tourne que sur des nœuds x86 : aucun poste à processeur Apple ni runner
arm64 ne teste nativement la couche `gcp`, et un pool de nœuds Arm sur GKE ne
le porterait pas. Une annotation propre à un moteur, une variable `${…}` ou
une autre version de Kustomize peuvent faire diverger la couche commune sans
bruit, contrôles de sécurité compris. Sur le PC, Flux corrige la dérive à
chaque réconciliation, et les modifications faites par `kubectl` « will be
reverted » (<https://fluxcd.io/flux/components/kustomize/kustomizations/>,
lu le 2026-11-20) : s'il synchronise l'environnement local, il défait ce que
la boucle de `task up` applique (R-30).

Les pods de Config Sync tournent dans le cluster du client. Google y fixe
environ 0,93 vCPU et 0,93 Gio par `RootSync` en Autopilot, aucune page lisible
ne les exempte de facturation, et ses métriques partent vers Cloud Monitoring,
facturé à l'échantillon ([FINOPS], 2026-11-19). S'ils sont facturés, Flux sur
les deux cibles coûterait moins cher : le montage ne tient alors que par le
principe III.

Mitigation : conditions de parité de l'ADR-010 (politique conftest sur la
couche commune, comparaison des rendus Kustomize des deux moteurs) ; nœuds
x86 pour Config Sync sur GKE ; Flux hors du profil lite, ou suspendu pendant
la boucle locale ; un seul `RootSync` dans le profil démo, export
des métriques coupé ou filtré par défaut ; écarts listés au README ; essai sur
GKE après accord de Lucas et budget de [FINOPS].

### R-32. Failles des moteurs GitOps invisibles aux scanners

Config Sync corrige des CVE sans les nommer (neuf releases en 2026) et ne
publie aucun avis : un scan des images voit ses dépendances vulnérables, pas
une faille de son propre code. Sa mise à jour automatique a été retirée en
1.21.0 (2025-05-01) : sur GKE, la montée de version se fait à la main, au
moins tous les neuf mois selon Google. Côté Flux, l'avis élevé
GHSA-mwcp-qpcg-fr7c (2026-08-11) n'a pas de CVE et manque à la base mondiale
de GitHub : Flux publie ses avis dans chaque dépôt (BENCH-009, relu par
[SECU]).

Mitigation : version de Config Sync figée dans la couche `gcp` et montée par
une PR qui passe la matrice ; relecture mensuelle des notes de version de
Config Sync et des avis des dépôts `fluxcd` par [SECU] ; scan Trivy des images
des deux moteurs à chaque montée ; procédure de montée de version dans le
runbook du projet généré.

### R-33. Écrire sur la branche suivie, c'est administrer le cluster

Les trois moteurs étudiés par BENCH-009 appliquent par défaut avec
`cluster-admin`, et chaque `RootSync` de Config Sync le reçoit sans
`roleRefs`. Qui écrit sur la branche suivie, ou intercepte sa lecture,
administre donc le cluster, et un environnement peut écrire dans un autre sur
un même cluster GKE. La documentation de Google fait créer un jeton GitHub de
portée `repo`, qui écrit dans tous les dépôts de l'utilisateur, et désactive la
vérification de l'hôte SSH quand `known_hosts` manque. Sur le PC, la pente
serait de reprendre le jeton de `gh` (R-07).

Mitigation : droits restreints des deux côtés, sans `cluster-admin` par défaut
(ADR-010) ; protection de la branche suivie dans le dépôt généré (Q3) ;
identifiant en lecture seule limité au dépôt, ou source OCI lue par Workload
Identity ; `known_hosts` obligatoire ; jamais un jeton personnel ni celui de
`gh` ; Secret jamais créé par une ressource OpenTofu (R-19) ; aucun
identifiant Git sur le PC par défaut.

### R-34. Miroir de registres sur le PC, nouvelle brique exposée

BENCH-010 retient provisoirement zot 2.1.23 comme miroir local. C'est un
serveur de plus sur chaque poste, et il devient la source des images Docker
Hub du cluster hors réseau, puis de celles que l'ADR-011 lui confiera. Il
tourne en root dans son conteneur, écoute sur 0.0.0.0:5000 et se trouve, dans
l'essai, sur les réseaux `bridge` et `kind`. Sans authentification, zot
accepte toute requête, écritures et suppressions comprises. Tout conteneur de
ces réseaux peut donc réécrire un tag, effacer le cache ou remplir le disque,
et sur Linux tout processus du poste aussi. Rien de confidentiel n'y est
gardé. Le projet a publié 21 avis de sécurité en 12 mois, dont un critique et
19 entre août et octobre 2026. Deux touchent la configuration retenue : deux
dénis de service corrigés avant la 2.1.23, dont un sur la synchronisation à
la demande. Les images de release ne sont pas signées. L'intégrité tient pour
les images désignées par condensat, puisque containerd vérifie le condensat
de tout ce qu'il reçoit. Elle ne tient pas pour un tag, que le miroir résout
sur parole tant qu'il garde la capacité `resolve`. Probabilité faible, parce
que l'exploitation demande du code déjà en marche sur le poste ou dans le
cluster.

Mitigation :

- miroir déclaré à containerd avec la seule capacité `pull`, à mesurer en T2 ;
- aucune référence par tag : le contrôle de FR-008 couvre aussi les images
  construites sur le poste, nommées sous un hôte qui ne résout vers aucun
  registre public ;
- miroir relié au seul réseau `kind`, sans port publié ;
- Docker Engine 28.0.0 au minimum sur Linux ;
- exécution sous un UID non root, sans capacités ni élévation de privilèges,
  à essayer ;
- configuration du projet toujours montée, extension `sync` seule : la
  configuration par défaut de l'image active la recherche, l'interface et la
  gestion ;
- image figée par condensat, suivie par Renovate avec l'exception de sécurité
  du principe VI, et incluse dans le SBOM et le scan Trivy du projet généré.
  Renovate ne date pas ghcr.io : chaque mise à jour attend l'approbation de
  Lucas sur le tableau de bord, qui compte les 7 jours (ADR-016, R-38) ;
- stockage jamais versionné ni publié (R-25) ;
- lecture mensuelle des avis du dépôt par [SECU] ;
- test de la condition 7 dans la matrice, avec un pod qui relève ce que le
  cluster joint du miroir.

### R-35. Postgres local écrit à la main dans chaque projet généré

Ouvert le 21/11/2026 avec BENCH-011, texte validé par [SECU]. Lucas a retenu
Postgres sans opérateur sur la cible `local`. Le StatefulSet, son
durcissement et ses règles d'initialisation deviennent du code de CELIAN,
copié dans chaque projet généré. Six dérives sont possibles :

- un Secret recréé sur un volume existant laisse l'ancien mot de passe en
  base et coupe l'application ;
- un volume monté ailleurs que sous `/var/lib/postgresql` loge la donnée
  hors du PVC ;
- une méthode `trust` glissée pour déboguer ouvre la base à tout le cluster ;
- l'utilisateur de l'application reste superutilisateur, le défaut de
  l'image, alors que Cloud SQL n'en donne jamais : une migration qui en
  dépend passe en local et échoue sur GCP ;
- Renovate propose la majeure 19, que `latest` désigne depuis le
  2026-11-19, et casse la parité avec Cloud SQL ;
- l'image ne suit plus les mineures, alors que 18.7 corrige 52
  vulnérabilités.

S'y ajoute un écart à ENF-03 : l'image officielle n'a aucune signature
vérifiable, et Kyverno ne l'admet que par dérogation.

Probabilité moyenne : chaque dérive tient à une ligne de manifest. Impact
moyen : la donnée locale est jetable, mais une dérive de privilège ou de
version ne se voit qu'au déploiement sur GCP.

Mitigation :

- conditions 1 à 8 de l'ADR-012, testées par la matrice ;
- Renovate sur le condensat de l'image, avec l'exception de sécurité du
  principe VI, sans montée de majeure hors de la valeur de la condition 5 ;
- `mysecretpassword`, valeur d'exemple de la documentation de l'image,
  ajoutée à la liste des valeurs connues de la condition 1 de l'ADR-007 ;
- dérogation à ENF-03 datée dans l'ADR-012, relue par [SECU] à chaque
  montée de condensat, et levée à la publication d'une signature Docker
  vérifiable par Kyverno ;
- relecture [SECU] de toute modification du StatefulSet de la couche
  `local`.

### R-36. Failles connues sans paquet associé, invisibles aux scanners

Ouvert le 24/11/2026 avec BENCH-012 (relecture [SECU]). Dans la base mondiale
de GitHub, une partie des failles publiées n'est associée à aucun paquet :
16 des 20 CVE de tickets de Keycloak échantillonnées, et 31 des 55 avis de
Zitadel, dont 4 des 6 critiques, sans module Go. Un scanner qui associe les
failles par paquet, comme Trivy pour les modules Go, ne les voit pas : le
scan de FR-021 peut passer au vert sur une image qui porte une faille
critique connue. Le même angle mort touchait déjà les moteurs GitOps (R-32).

BENCH-013 (2026-11-24, relecture [SECU]) : l'angle mort touche aussi les
avis publiés par un projet sans CVE ni entrée dans la base mondiale ; trois
des 18 avis de Mailpit, dont le seul élevé du dépôt, n'y figurent pas, et
Trivy ne les voit pas. La lecture mensuelle des avis du dépôt par [SECU]
couvre Mailpit.

Probabilité moyenne : le cas est fréquent dans les deux projets mesurés.
Impact moyen : une faille connue partirait dans chaque projet généré.

Mitigation : lecture mensuelle par [SECU] des avis et des tickets de sécurité
des composants de la stack, en plus du scan ; montée de version suivie à
chaque correctif publié, avec l'exception de sécurité du principe VI ;
contrôle croisé par une seconde source de failles à étudier à l'étape 18 du
plan. Rôles : SECU, OPS.

### R-37. Parcours de connexion différent entre le PC et GCP

Ouvert le 24/11/2026 avec l'ADR-013, sur proposition de [ARCHI]. Le projet
généré fait tourner Keycloak sur la cible `local` et utilise Identity Platform
sur la cible `gcp` (décision de Lucas du 24/11/2026, principe III). Le front
porte donc deux parcours de connexion : PKCE vers Keycloak d'un côté, SDK de
Google de l'autre. Une erreur dans l'implémentation `gcp` du front ou dans la
configuration d'Identity Platform ne se voit que sur GCP, au premier
déploiement réel, qui demande une dépense et l'accord de Lucas (principe X).

Probabilité moyenne : le parcours `gcp` ne tourne jamais en phase 2. Impact
moyen : la démo sur GCP échouerait à la connexion, sans fuite de données.

Mitigation :

- contrat commun de vérification des jetons dans l'API, testé sur les deux
  formats de clés (ADR-013) ;
- tests unitaires de chaque implémentation du parcours de connexion du front ;
- test du parcours réel avant toute proposition de la combinaison `gcp`, au
  premier déploiement autorisé ;
- écart listé au README du projet généré.

### R-38. Mise à jour des images sans date suspendue à une personne

Ouvert le 24/11/2026 avec l'ADR-016, sur proposition d'[ARCHI]. Renovate ne
connaît la date de publication d'une image que sur Docker Hub. Pour ghcr.io,
quay.io et mcr.microsoft.com, Lucas a choisi l'approbation manuelle : chaque
mise à jour attend qu'il coche sa case sur le tableau de bord de Renovate,
après avoir lu la date amont du condensat. Quatre images sont concernées :
zot, les contrôleurs de Flux, Keycloak et les images .NET de l'API. gitleaks
en est sorti le 25/11/2026 : Renovate le date sur Docker Hub, et l'image se tire de ghcr.io par le même condensat
(ADR-016, question 3). Une absence retarde un correctif. Une date mal lue
fait entrer un condensat de moins de 7 jours. Aucune alerte automatique ne
couvre ces images : ni `osvVulnerabilityAlerts` ni la base d'avis de GitHub
ne connaissent les images.

Probabilité moyenne : Keycloak a publié trois condensats de 26.8.2 en dix
jours, et mcr.microsoft.com modifie ses tags après leur création. Impact
moyen, fort pour l'image d'exécution de l'API, la seule des quatre qui part
sur GKE.

Mitigation :

- lecture du tableau de bord une fois par semaine, et sur alerte de [SECU]
  pour un avis publié (décision de Lucas du 24/11/2026) ;
- S23 et le contrôle du `renovate.json` de CELIAN refusent tout écart au
  bloc de l'ADR-016, et tout registre de plus passe par un ADR ;
- trace de la date lue et de sa source dans chaque PR de ces registres,
  relue par [SECU] à sa lecture mensuelle des avis ;
- jeton des agents sans droit d'écriture sur les tickets, essayé par Lucas
  avant l'installation de l'application Renovate, ancien jeton classique
  révoqué (ADR-016, conditions 3 et 5 ; R-07) ; règles `deny` sur les formes
  courantes de `gh issue edit`, des `gh api` en `PATCH` et des mutations
  GraphQL, filtre de motifs en appoint ;
- copie de Docker Hub au cas par cas : faite pour gitleaks le 25/11/2026,
  Keycloak attend l'étape 15 (ADR-016, question 3) ;
- relecture de la dérogation au plus tard le 2027-02-24, et à la fermeture de
  chacun des tickets Renovate 38656, 39064 et 38572 ; le risque se ferme avec
  le dernier registre levé.

### R-40. Scanner de secrets du projet généré en maintenance

Ouvert le 25/11/2026 par [OPS], en préparant le passage de gitleaks à Docker
Hub (ADR-016, question 3). Depuis le 21/05/2026, le README de gitleaks
annonce : « Gitleaks is feature complete… Future releases will be security
patches only », et son auteur passe à Betterleaks. Le principe VI range
« projet archivé ou en maintenance » parmi les critères éliminatoires.
gitleaks n'a jamais été comparé : il est entré à la phase 0 pour la CI de
CELIAN, puis a été recopié dans le golden repo (workflow `secrets.yml` et hook
pre-commit). Chaque projet généré en hérite. Relevé par [SECU] le
25/11/2026 : aucune release depuis v8.30.1, publiée le 21/03/2026 ; aucun
avis de sécurité publié ; depuis mai, `master` ne reçoit que des montées
d'actions. Le critère « aucune release depuis 12 mois » du principe VI tombe
le 21/03/2027 si rien ne sort d'ici là.

Probabilité forte : le statut est annoncé par l'auteur. Impact moyen : les
correctifs de sécurité sont promis, mais aucun n'est sorti depuis
l'annonce ; les nouveaux formats de secrets ne seront plus détectés, et le
principe IX repose sur ce scanner.

Mitigation : gitleaks garde son rôle tant qu'un benchmark n'a pas tranché ;
daté par Renovate sur Docker Hub et tiré de ghcr.io par le même condensat
(ADR-016, question 3), il reçoit ses correctifs avec le délai de 7 jours ;
à la lecture mensuelle des avis, [SECU] compare la dernière release GitHub au
dernier tag de Docker Hub, pour voir une release que Renovate ne verrait
pas ; un benchmark des scanners de secrets (gitleaks, Betterleaks,
TruffleHog, Kingfisher au moins), ouvert après le golden repo et avant la
mise en template de la phase 3 (décision de Lucas du 25/11/2026), et au plus
tard avant le 21/03/2027.

### R-41. Jeton de Memorystore sans ressource publiée dans le provider

Ouvert le 25/11/2026 avec l'ADR-015. Sur `gcp`, le cache est Memorystore for
Valkey, authentifié par jeton pour le MVP. Le Secret `cache-auth` doit porter ce
jeton, mais la ressource du provider `google` qui le lit n'est publiée dans
aucune version au 25/11/2026 (8.12.0 est la dernière). Sans elle, le producteur
`gcp` de `cache-auth` manque au premier apply, et l'API ne joint pas le cache.

Probabilité moyenne : la date de publication est inconnue. Impact moyen : le
cache sur GCP reste inutilisable, sans fuite ; le reste de la cible tient.

Mitigation : condition 18 de l'ADR-015 ; question 2 de l'ADR-015 reposée à
l'ouverture de la GATE 2 (déployer sans la partie cache, ou ouvrir plus tôt
l'ADR de l'IAM) ; [OPS] relit les notes de version du provider à chaque montée.
