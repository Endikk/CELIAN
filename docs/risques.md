# Registre des risques

Tenu par le DSI. Mis à jour le 15/11/2026. Probabilité et impact sont notés
faible, moyen ou fort : ce sont des jugements, pas des mesures. Un risque se
ferme quand sa mitigation est en place et vérifiée.

## Synthèse

| ID | Risque | Probabilité | Impact | Porteur | État |
| --- | --- | --- | --- | --- | --- |
| R-01 | Protection de `main` non appliquée | Certaine | Fort dès la phase 2 | OPS | Ruleset à appliquer par Lucas |
| R-02 | Plugins tiers et utilisateur non figés ni relus | Moyenne | Fort | SECU | Ouvert |
| R-03 | Contexte d'agent surchargé, coût en tokens | Forte | Moyen | DSI, FINOPS | Atténué : ECC désactivé |
| R-04 | Critère des 15 minutes hors d'atteinte | Moyenne | Fort | OPS | Ouvert |
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
elle consommera des tokens chez chaque utilisateur du produit. Le mode de
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
images de conteneurs, la création du cluster k3d et la compilation .NET et
Node. Rien n'est encore mesuré.

Mitigation : mesurer dès la phase 1 (BENCH-003 et BENCH-005), avec des scripts
dans `tests/bench/`. Pistes à évaluer : images préconstruites, cache local
d'images, profil lite par défaut.

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
(principe IV). Revue datée à chaque phase. L'idée « alertes catalogue » reste
après le MVP.

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
`ROADMAP.md`.

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

Le « jour 2 » est un point de différenciation. Sur un projet où l'équipe a
modifié des fichiers du socle, une mise à jour du blueprint produira des
conflits.

Mitigation : séparer dans le blueprint ce qui relève du socle et ce qui
appartient à l'équipe. Tester `copier update` dans la matrice de la phase 4,
sur un projet généré puis modifié.

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

Mitigation : une procédure de démontage écrite (supprimer les Gateways et les
PVC, puis `tofu destroy`), ou la suppression du projet entier. Contrôle le
lendemain dans le rapport de facturation filtré sur le projet.

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
prévus aux phases 2 et 6, à prévoir un profil démo zonal et minimal, et à faire
valider par [FINOPS] les tailles par défaut du blueprint.

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

Mitigation : aucune clé de compte de service. Condition sur
`assertion.repository` et `assertion.ref`. Compte de service en lecture seule
pour `tofu plan`, l'apply restant manuel (principe X). Règles `ask` sur
`tofu state`, `tofu show` et `tofu output`. Mots de passe hors de l'état, état
chiffré : syntaxes à vérifier en phase 1.

### R-20. Identifiants par défaut dans le golden repo

Keycloak, OpenBao en mode dev, Postgres et Grafana démarrent avec un mot de
passe connu ou sans mot de passe. Pour tenir `task up` en une commande, la
tentation sera de les écrire dans le dépôt, contre le principe IX, et gitleaks
ne détecte pas un mot de passe sans entropie comme `admin`. Ils partiraient
dans chaque projet généré, avec un réemploi possible sur GCP. Les ports publiés
par k3d et Docker écoutent peut-être sur toutes les interfaces (à vérifier).

Mitigation : `task up` génère des secrets aléatoires au premier lancement, dans
un `.env` ignoré par Git. Les ports se lient à `127.0.0.1`. Un test de la
matrice et une politique conftest échouent si un identifiant par défaut atteint
la cible GCP.
