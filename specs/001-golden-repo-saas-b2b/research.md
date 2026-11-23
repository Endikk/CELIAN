# Research: golden repo SaaS B2B

Phase 0 du plan ([plan.md](plan.md)). Rédigé par [DEV] le 2026-11-21, mis à jour le 2026-11-23 après l'amendement de la spec (PR #39) et les décisions du 2026-11-21 et du 2026-11-23 (tableau « Décisions prises depuis la première version » du plan).

Pour RS-01 à RS-21, aucune recherche nouvelle sur Internet n'a été faite : chaque fait vient d'un ADR, d'un benchmark, du catalogue ou d'un script de benchmark versionné, avec sa date de lecture d'origine. RS-22 à RS-24 s'appuient en plus sur des pages officielles lues le 2026-11-23, citées avec leur adresse. Ce qui manque est écrit « à vérifier », avec son porteur et l'étape qu'il bloque. Les choix déjà faits par les ADR-004 à ADR-012 ne sont pas rouverts ; les points ci-dessous fixent ce que ces ADR laissaient au golden repo.

Format de chaque point : décision, pourquoi, alternatives écartées, sources.

## RS-01. Arborescence et carte des couches

Décision : une couche de cible tient dans un dossier, `golden/saas-b2b/local/` ou `golden/saas-b2b/gcp/`. Tout le reste est commun : code de l'application, base et overlays Kustomize, conventions Git, README, politiques et tests communs. Le détail est dans [contracts/layers.md](contracts/layers.md).

Pourquoi : le principe II veut qu'un service propre à une cible ne vive que dans sa couche, et la phase 3 devra rendre chaque couche selon les cibles choisies. Un dossier par couche rend ce rendu trivial (un dossier conditionnel) et rend la règle vérifiable par un test de chemins. Les ADR-006 et ADR-010 renvoient l'arborescence exacte à la phase 3 ; le golden repo doit pourtant en avoir une, et celle-ci garde leurs contenus par couche.

À vérifier avant l'étape 7 : les composants de Kustomize, qui portent la couche de cible au-dessus d'un overlay d'environnement, sur la documentation de Kustomize et dans la version qu'embarque kubectl. À défaut, une composition par ressources garde le même découpage. Porteur : [DEV].

Alternatives : `blueprints/saas-b2b/{common,local,gcp}` reproduit dans le golden repo, écarté parce qu'un projet qui marche n'a pas trois racines ; `k8s/app/` et `k8s/local/` de l'essai de BENCH-005, gardés dans l'esprit (`k8s/` commun, `local/k8s/` de cible) mais complétés par les overlays par environnement de l'ADR-010.

Sources : constitution 1.2.0, principe II ; ADR-006, « Répartition par couche » ; ADR-010, « Répartition par couche » et condition 1 ; CLAUDE.md, arborescence.

## RS-02. Routage sous une seule origine

Décision : une Gateway à deux écouteurs (HTTP et HTTPS) et deux HTTPRoute. Le préfixe `/api` va à l'API, `/` au front. L'API sert ses routes sous `/api` elle-même. Le front appelle des chemins relatifs.

Pourquoi : une seule origine supprime CORS et toute configuration d'adresse dans le front. L'absence de réécriture de chemin garde la couche commune dans les champs que GKE sert (ADR-005, condition 5). Le manifest mesuré par BENCH-004 n'avait qu'une règle sans correspondance de chemin : que la correspondance par préfixe de chemin fasse partie du cœur de Gateway API, et qu'elle soit servie par le contrôleur de GKE, est à vérifier sur la spécification de Gateway API v1.7.0 et sur la page de GKE avant l'étape 7.

Alternatives : deux noms d'hôte (`api.` et front), écarté parce que la résolution de noms locaux dépend du système du poste et n'a pas été relevée ; deux Gateway, refusé par l'ADR-005 (une seule Gateway, et chacune crée un équilibreur facturé sur GKE).

Sources : ADR-005, décision, condition 5 et réserves de [FINOPS] ; `tests/bench/bench-004-gateway.sh`, lignes 400 à 470.

## RS-03. Exemple applicatif

Décision : une ressource « note » (identifiant, texte de 1 à 500 caractères, date de création). Écriture en base, lecture par identifiant en lecture paresseuse par le cache, liste des plus récentes depuis la base, provenance de la lecture dans la réponse. Deux routes de santé : vivant et prêt. Accès à la base par Npgsql, requêtes paramétrées, sans ORM ; accès au cache derrière une interface, dont le client concret suit l'ADR-015 (RS-11).

Pourquoi : FR-009 et Q7 limitent le code à l'exemple. Une note relue après un rechargement prouve la conservation des données (récit 1, scénario 3) ; la provenance rend l'usage du cache testable sans regarder dans le cache. Sans ORM, il n'y a qu'une dépendance de base de données à suivre.

Alternatives : un compteur de visites, écarté parce qu'il ne prouve pas la relecture d'une donnée précise ; Entity Framework Core, écarté pour son poids face à une seule table ; aucune liste, écartée parce que le front n'aurait rien à afficher au chargement.

À vérifier avant l'étape 3 : version, licence et date de Npgsql ; celles du client .NET du cache à l'étape 19 ; format des réponses d'erreur d'ASP.NET Core (ProblemDetails) ; verrouillage des paquets NuGet par fichier de verrouillage. Porteur : [DEV].

Sources : spec, FR-009, récits 1 et 2 ; ADR-009, standards (Valkey parle RESP).

## RS-04. Création du schéma

Décision : un script SQL idempotent, embarqué dans l'API et exécuté au démarrage sous le rôle de `db-auth`, propriétaire de la base `app`.

Pourquoi : le rôle de l'application n'est pas superutilisateur (ADR-012, condition 8), et Cloud SQL n'en donne jamais ; un script exécuté par l'application marche à l'identique sur les deux cibles. Un Job Kubernetes de migration ajouterait un objet et une attente à `task up` pour une seule table.

À vérifier avant l'étape 3 : les droits de création dans le schéma `public` pour le propriétaire d'une base sous PostgreSQL 18, et les privilèges de `cloudsqlsuperuser` (ADR-012, « Parité attendue avec Cloud SQL »). Porteur : [DEV] avec [SECU].

Alternatives : migrations d'Entity Framework Core (écarté avec RS-03) ; script dans `/docker-entrypoint-initdb.d`, réservé par l'ADR-012 à la création du rôle et inexistant sur Cloud SQL.

Sources : ADR-012, conditions 2 et 8.

## RS-05. Front et image du front

Décision : React et TypeScript, construits par Vite dans une image multi-étapes ; fichiers statiques servis par nginx sur un port non privilégié, comme l'essai de BENCH-005.

Pourquoi : le brief et la spec fixent React ; nginx 1.30.7 est déjà figé par condensat dans l'essai.

À vérifier avant l'étape 4, avec la date de publication (principe VI) : versions de Node.js, React, Vite, TypeScript et du framework de test du front ; image de construction Node par condensat ; variante de nginx qui tourne sans root, exigée par le profil `restricted` que l'ADR-012 étend aux pods de l'application (condition 9). Porteur : [DEV].

Alternatives : servir le front depuis l'API .NET, écarté parce que la couche commune garde deux images indépendantes, comme l'essai mesuré.

Sources : spec, hypothèses ; BENCH-005, S38 et section 4.2 ; ADR-012, condition 9.

## RS-06. Construction des images

Décision : construction multi-étapes dans le moteur, SDK .NET dans l'image de construction ; aucun SDK .NET ni Node.js dans les prérequis du poste.

Pourquoi : la construction est reproductible d'un poste à l'autre, et les prérequis restent ceux de l'ADR-006.

Coût : l'image du SDK pèse 362,8 Mo en amd64 au premier `task up`. Le levier de [FINOPS] (compiler sur le poste, ADR-006, question 3) reste ouvert ; il pose une question de reproductibilité que [DEV] et [SECU] tranchent, et la mesure D02 dira s'il faut le reprendre.

Sources : ADR-006, question 3 ; BENCH-005, détail amd64.

## RS-07. Nom des images construites

Décision : `saas-b2b.invalid/api` et `saas-b2b.invalid/front`, avec une étiquette neuve à chaque construction posée par Kustomize.

Pourquoi : sans hôte, Kubernetes suppose Docker Hub, et une image absente du nœud partirait vers le miroir puis vers un espace de noms qui n'appartient pas au projet (ADR-011, condition 4). Le domaine `.invalid` ne résout vers aucun registre.

Non essayé : que `kind load docker-image` et le kubelet acceptent ce nom. Porteur : [OPS], essai au début de l'étape 9. Repli si l'essai échoue : un autre hôte qui ne résout vers aucun registre public, retenu avec [SECU] et contrôlé par S01 et E11 de la même façon.

Sources : ADR-011, condition 4 ; ADR-006, condition 7.

## RS-08. Profils et mémoire

Décision : profil choisi selon la mémoire que déclare le moteur ; variable `PROFILE` pour forcer, sous les mêmes contrôles. Seuils de départ : VM de 2,0 Gio pour le lite, 2,5 Gio pour la partie connue du standard. Seuils recalculés sur la première mesure, à l'entrée du cache retenu par l'ADR-015, et à celle de Keycloak et de Mailpit.

Pourquoi : ADR-004, condition 6 (mémoire déclarée par le moteur, pas mémoire physique) ; spec, cas limites. Les seuils sont des ordres de grandeur de [FINOPS] qui mêlent plusieurs séries.

À vérifier : la commande qui lit la mémoire déclarée, sous Docker Engine et sous le moteur libre que retiendra [OPS]. Porteur : [DEV], étape 5.

Sources : ADR-004, condition 6 ; ADR-006, conséquences ; ADR-011 et ADR-012, conséquences.

## RS-09. Taskfile et scripts

Décision : `Taskfile.yml` à la racine expose les commandes publiques et délègue aux Taskfiles inclus de `local/tasks/` et `gcp/tasks/`. La logique vit dans des scripts bash de `local/scripts/`, compatibles avec bash 3.2, sans heredoc, passés à shellcheck. Le Taskfile porte en tête l'inventaire des commandes qui créent, modifient ou suppriment un conteneur, un réseau ou un volume. Construction, chargement et application sont définis une fois et réutilisés par `task up` et `task reload`.

Pourquoi : ADR-006, condition 6 ; ADR-007, condition 1 (bash 3.2 de macOS, heredoc) ; ADR-011, condition 11.

À vérifier avant l'étape 1 : version de Task, sa syntaxe d'inclusion, le mode silencieux et la détection de sources modifiées utile à `task reload`. Porteur : [DEV].

### Relevé du 2026-11-23 (T001)

Fait par [DEV]. Sources officielles seulement : l'API GitHub du dépôt `go-task/task`, lue par `gh api`, et la documentation de taskfile.dev, dont chaque page lue s'annonce en v3.54.0.

Version retenue : Task v3.54.0, publiée le 2026-10-01, dernière release stable (la release `nightly` est une pré-version, écartée). Elle a 53 jours au 2026-11-23 et passe le délai de 7 jours (principe VI). Licence MIT.

Gouvernance (ADR-006, question 5) : le dépôt appartient à l'organisation `go-task`, qui compte trois membres publics, `andreynering`, `pd93` et `vmaerten`. Aucune fondation n'est citée. Sur un an, du 2025-11-23 au 2026-11-23, le dépôt reçoit 401 commits, dont 326 d'auteurs humains (robots `renovate[bot]`, `dependabot[bot]` et `task-bot` exclus), venus de 50 auteurs. `vmaerten` en signe 158 (48,5 %), `andreynering` 76 (23,3 %) et `pd93` 26 (8,0 %) : 79,8 % pour les trois membres. Employeurs déclarés sur leur profil GitHub : « @charmbracelet » pour `andreynering`, « Senior Software Engineer @oneid » pour `pd93`, aucun pour `vmaerten`. Lecture : un projet communautaire, sans fondation, porté par trois personnes, sans entreprise dominante déclarée. Ce relevé donne les faits ; le classement au titre du principe V reste à Lucas, et la question 5 de l'ADR-006 n'est pas close par lui.

Intégrité : la release publie un fichier de sommes, `task_checksums.txt`. Elle n'est pas immuable (`immutable: false`) et l'API des attestations répond 404 pour le binaire linux amd64. Comme pour kind (ADR-004, condition 5), la somme publiée dans la même release protège de la corruption, pas d'une substitution. Les sommes ci-dessous sont lues dans `task_checksums.txt` (asset 604090275, lu par l'API) ; elles sont égales au champ `digest` que l'API des releases donne pour chaque archive.

| Archive | SHA-256 |
| --- | --- |
| `task_linux_amd64.tar.gz` | `680859dbb4d881a9c72d4d9a8f510825450849af8567deacd7302c01124416fb` |
| `task_linux_arm64.tar.gz` | `d7189d439d4a6058e39e1b2acd7c8b27acd4856691b408f23b242e4294e1df5b` |
| `task_darwin_amd64.tar.gz` | `0543b0844a725814c0412d3f4bed12873ce9ed0da207b15775f63a97d734aac0` |
| `task_darwin_arm64.tar.gz` | `12a69fcf37bb8d5bc9150c44f9a936775b73e59ff044c2c245232f198c135637` |

Inclusion des Taskfiles : clé `includes`, forme courte (`nom: chemin`) ou longue (`taskfile:` et `dir:`). Sans `dir`, une tâche incluse s'exécute dans le dossier d'exécution du Taskfile qui l'inclut, pas dans celui de son fichier. `optional: true` tolère un fichier absent ; `internal: true` cache toutes les tâches du fichier, qui ne servent plus qu'aux tâches publiques ; `flatten: true` les expose sans espace de noms. Une tâche incluse s'appelle `espace:tache`, en ligne de commande comme depuis les `cmds` d'une autre tâche. Les Taskfiles inclus portent la même version de schéma, `version: '3'`.

Mode silencieux : `silent: true` à la racine, sur une tâche ou sur une commande, ou l'option `--silent` (`-s`). Il cache le texte de la commande que Task affiche, pas la sortie de la commande, et la page le dit : « Silent mode is not a substitute for secret masking. » C'est ce que l'ADR-007 (condition 1, S53) relevait déjà : une valeur ne passe jamais par un argument ni une variable de Task.

Sources modifiées : `sources` et `generates` acceptent fichiers et motifs, relatifs au dossier de la tâche, avec des entrées `exclude:`. La méthode par défaut, `checksum`, compare le contenu des sources à une empreinte gardée dans `.task/`, sous le dossier du projet (à ignorer dans Git ; `TASK_TEMP_DIR` le déplace). `timestamp` et `none` sont les deux autres méthodes ; `status` saute la tâche quand chaque contrôle sort en 0 ; `--force` (`-f`) la relance. Pour `task reload`, `sources` sur `src/Api/` et `src/front/` avec la méthode `checksum` permettrait de ne reconstruire que l'image touchée ; le choix se fait à l'étape 9.

Exécution : Task lance les commandes par son interpréteur intégré, sans le shell de l'utilisateur ; chaque entrée de `cmds` a son propre contexte, et un script bash s'appelle explicitement par `bash`. Une commande en échec arrête sa tâche. Codes de sortie de la CLI : 201 pour une commande en échec, 200 pour une tâche inconnue, 202 pour l'appel direct d'une tâche interne.

Effets : `golden/saas-b2b/Taskfile.yml` (T009) inclut `local/tasks/` en `internal` et `gcp/tasks/` en `optional` ; `golden/saas-b2b/tests/tools/install.sh` et `SHA256SUMS` (T011) installent v3.54.0 par ces sommes.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://api.github.com/repos/go-task/task/releases> | 2026-11-23 | v3.54.0 publiée le 2026-10-01, dernière stable ; `nightly` en pré-version ; release non immuable |
| <https://github.com/go-task/task/releases/download/v3.54.0/task_checksums.txt> | 2026-11-23 | Les quatre SHA-256 du tableau, lus par l'API (asset 604090275) |
| <https://api.github.com/repos/go-task/task> | 2026-11-23 | Licence MIT, dépôt non archivé, organisation `go-task` |
| <https://api.github.com/orgs/go-task/public_members> | 2026-11-23 | Trois membres publics |
| <https://api.github.com/repos/go-task/task/commits?since=2025-11-23T00:00:00Z> | 2026-11-23 | Commits de l'année par auteur |
| <https://api.github.com/repos/go-task/task/attestations/sha256:680859dbb4d881a9c72d4d9a8f510825450849af8567deacd7302c01124416fb> | 2026-11-23 | 404 : aucune attestation |
| <https://taskfile.dev/docs/guide/includes> | 2026-11-23 | Syntaxe d'inclusion, `dir`, `optional`, `internal`, `flatten`, appel `espace:tache` |
| <https://taskfile.dev/docs/guide/output> | 2026-11-23 | Mode silencieux et sa limite |
| <https://taskfile.dev/docs/guide/up-to-date> | 2026-11-23 | `sources`, `generates`, `method`, `.task/`, `status`, `--force` |
| <https://taskfile.dev/docs/guide/defining-tasks> | 2026-11-23 | `version: '3'`, `desc`, `dir`, tâche `internal` |
| <https://taskfile.dev/docs/guide/errors-and-cleanup> | 2026-11-23 | Une commande en échec arrête sa tâche ; exemples en `exit 1` |
| <https://taskfile.dev/docs/guide/platforms> | 2026-11-23 | Interpréteur intégré, contexte par entrée de `cmds`, appel explicite de `bash` |
| <https://taskfile.dev/docs/reference/cli> | 2026-11-23 | Codes de sortie, `--silent`, `--dir`, `--taskfile`, `--list` |

## RS-10. Secrets locaux

Décision : `db-auth`, `cache-auth`, `db-superuser` et `gateway-tls` en profil lite, `cache-auth` à partir de l'étape 19 (RS-11) ; valeurs de 40 caractères alphanumériques tirées de `/dev/urandom`, comme l'essai de BENCH-011, passées par un tube à `kubectl create -f -`, seulement si le Secret manque. Contrat : [contracts/secrets.md](contracts/secrets.md).

Pourquoi : ADR-007, condition 1 ; ADR-012, conditions 3, 8 et 10.

Non décidé : la fabrication de la clé et du certificat de `gateway-tls`. BENCH-004 écrivait la clé dans un fichier, ce que la condition 1 de l'ADR-007 interdit au projet généré. Piste : un outil qui écrit la clé et le certificat sur sa sortie standard, envoyée par un tube ; outil, disponibilité sur macOS et Linux et syntaxe à vérifier. Porteurs : [SECU] et [DEV]. Bloque l'écouteur HTTPS de l'étape 7 ; l'écouteur HTTP n'en dépend pas, ce que l'étape 7 vérifie.

## RS-11. Cache

Décision de Lucas (2026-11-21) : le moteur du cache passe par un benchmark court, BENCH-014, ouvert le 2026-11-21 (lectures en cours, mesures après BENCH-012 et BENCH-013), puis par son ADR, l'ADR-015, réservé. Le plan garde le cache comme une couche en attente : aucune image, aucune version ni aucune forme (Deployment, persistance) n'est figée avant l'ADR-015, sur `local` comme sur `gcp`. Le moteur de Memorystore et son authentification, que l'ADR-008 laissait ouverts (chaîne AUTH écrite en clair dans l'état), entrent dans le même benchmark.

Ce que le plan fixe sans attendre, parce que rien n'y dépend du moteur :

- le Secret `cache-auth`, son nom et sa lecture par fichier, communs aux deux cibles ([contracts/secrets.md](contracts/secrets.md)) ; ses clés exactes suivent l'ADR-015 ;
- le mot de passe jamais en argument de commande (ADR-006, condition 2), contrôlé par S11 ;
- les clés d'`app-config` pour l'hôte, le port et le mode TLS du cache ;
- l'accès au cache dans l'API derrière une interface, testée par U01 avec un double ; le client concret entre à l'étape 19.

Effet sur les étapes : la partie cache de l'étape 8 devient l'étape 19 (couche cache locale). La ressource Memorystore de l'étape 13 et le producteur `gcp` de `cache-auth` deviennent l'étape 20. L'étape 9, qui démarre le profil lite de bout en bout, dépend de l'étape 19 : sans cache, FR-001 n'est pas tenu.

Ce qui avance sans BENCH-014. L'étape 6 (cluster et miroir) ne contient aucun fichier du cache. Son seul lien avec lui est la liste des registres du miroir : docker.io y entre déjà pour Postgres. Si l'ADR-015 retient une image d'un autre registre, l'étape 19 l'ajoute à la liste et rejoue E10 (ADR-011, condition 10), après le réglage du montage à plusieurs amonts (RS-13). L'étape 6 de `task up`, qui crée les Secrets, avance aussi : elle crée `db-auth` et `db-superuser`, et l'étape 19 ajoute `cache-auth` à la même tâche. Avancent de même les étapes 1 à 5 et 7, l'étape 8 sans le cache, l'étape 13 sans Memorystore et la première PR de l'étape 18.

Repère, et non choix : l'essai de BENCH-005 utilisait `valkey/valkey:9.1.4-alpine`, 18,8 Mo en amd64, que l'estimation de volume de R-04 compte encore.

À vérifier à l'entrée de l'étape 19 (porteurs [DEV] et [SECU]) : la façon de passer le mot de passe au moteur retenu sans argument, sur sa documentation ; le mode TLS face à Memorystore ; le client .NET, avec sa version, sa licence et sa date. RESP est un protocole conçu pour Redis, que parlent les clients de Valkey (ADR-009, sources) ; que toutes les options de BENCH-014 le parlent, ce qui garderait l'interface de l'API telle quelle, est à confirmer par [BENCH].

Sources : décision de Lucas du 2026-11-21 ; BENCH-014, brouillon du 2026-11-21 ; ADR-006, condition 2 ; ADR-008, portée et condition 3 ; ADR-009, section 2 et sources ; BENCH-005, section 4.4 ; `tests/bench/bench-005-orchestration.sh`, ligne 108.

## RS-12. Postgres local

Décision : l'ADR-012 tel quel, accepté par Lucas le 2026-11-21. Namespace unique pour la base et l'application, comme le propose sa condition 9 : réponse de Lucas à la question 1, `task app:down` efface la donnée locale avec ses deux Secrets. La dérogation à ENF-03 se relit au plus tard le 2027-05-20, et par [SECU] à chaque montée de condensat (question 2) ; elle reste sans effet dans le golden repo, qui n'embarque pas Kyverno.

Restent à faire sur le golden repo, d'après les suites de l'ADR-012 : `readOnlyRootFilesystem`, l'effet de `pg_isready` sur les journaux, le script d'initialisation sous `scram-sha-256` local, l'état TLS du serveur.

## RS-13. Miroir

Décision : l'ADR-011 tel quel, accepté par Lucas le 2026-11-21 avec ses réponses. `task down` supprime le cluster et `task app:down` le garde, noms provisoires que [PO] confirme en phase 5 ; le conteneur du miroir est retiré à chaque `task down`, son volume reste ; la purge passe par une commande explicite, `task mirror:purge`, et la rétention de zot n'entre qu'après un essai en `dryRun` et une relecture [SECU] ; un volume par projet. La liste des registres vit dans `local/mirror/registries`. La configuration zot et les `hosts.toml` en sont dérivés et versionnés ; S13 vérifie qu'ils restent d'accord, ce qui évite de générer du JSON à l'exécution sans outil dédié.

Ouvert : les montages a et b pour plusieurs amonts, essayés à l'étape 12 avec ghcr.io, ou à l'étape 19 si le cache vient d'un autre registre que docker.io ; le temps de démarrage du miroir, mesuré par E17.

## RS-14. Flux dans le profil standard

Décision de Lucas (2026-11-21) : Flux est livré dans le profil standard avec sa liaison suspendue (`spec.suspend`), et `task reload` reste seul maître des objets de l'application, jusqu'à ce que Lucas tranche ce que lit Flux sur le PC (ADR-010, question 1). `task up` installe Flux depuis son `install.yaml` vendoré, quatre contrôleurs, options de verrouillage de la condition 3 de l'ADR-010. Un seul acteur tient ainsi les objets de l'application, comme le demande la question 3 de l'ADR-010. S28 vérifie la suspension.

Pourquoi : la mesure du profil standard (SC-002) compte les images et la mémoire de Flux, qui ne dépendent pas de la source. Une source choisie sans Lucas engagerait soit un identifiant sur le poste, soit une image non mesurée.

Conséquence sur E15. Une liaison suspendue ne réconcilie rien : E15 ne peut pas regarder Flux écrire. Il interroge à la place les droits du compte de service de chaque liaison auprès de l'API du cluster, sans réactiver la liaison, et échoue si un environnement peut écrire dans le namespace d'un autre. La réconciliation réelle se testera quand la source sera choisie.

À vérifier à l'étape 12 (porteur [DEV]) : qu'une `Kustomization` suspendue dont l'objet source n'est pas livré soit admise et reste inerte, sur la documentation de Flux 2.10 ; le mécanisme qui interroge les droits d'un compte de service. Repli : livrer les contrôleurs seuls, sans objet de liaison ; S10 et S28 portent alors sur les contrôleurs, et E15 sur les rôles livrés.

Reste ouvert, sans bloquer aucune étape : la question 1 de l'ADR-010.

Alternatives : attendre la décision avant l'étape 12, écarté parce que D02 attendrait aussi ; un dépôt distant public, qui garde la dépendance au réseau contre l'ADR-011.

## RS-15. Keycloak et Mailpit

Décision : aucune image, version ni manifest avant les ADR-013 et ADR-014. Chaque couche entre par le même chemin : un dossier de `local/`, un ajout à la composition `local/k8s/standard`, ses Secrets créés selon l'ADR-007, son registre ajouté à la liste du miroir, ses images ajoutées à l'inventaire du scan (RS-24), E10 et E25 rejoués en standard, seuil de mémoire recalculé.

Keycloak tourne sans être appelé par l'API jusqu'à l'ADR-013 et à l'amendement de la spec qu'il demandera (RS-25). Une base pour Keycloak, si BENCH-012 en demande une, s'ajoute dans la même couche.

## RS-16. Couche GCP

Décision : racine OpenTofu unique dans `gcp/tofu/`, ressources du socle de l'ADR-008, Memorystore mis à part jusqu'à l'ADR-015 (étape 20, RS-11), provider `google` 8.12.0 et provider `random` dans un verrou versionné. Validation en CI par `tofu init -lockfile=readonly` puis `tofu validate`, sans backend distant ni identifiant.

À vérifier avant l'étape 13 (porteur [OPS], avec [DEV]) : l'option qui désactive le backend à l'init ; la validation d'une configuration de chiffrement `gcp_kms` sans accès à la clé ; la commande qui inscrit les sommes de chaque plateforme dans le verrou et le comportement de `-lockfile=readonly` sur une plateforme absente (ADR-008, question 5) ; la lecture de `platform.yaml` par une fonction de décodage YAML d'OpenTofu ; les attributs des activations (Gateway API, synchronisation des secrets, flotte, Config Sync) ; la version du provider `random`.

Contrainte de date : `google` 8.12.0 ne passe le délai de 7 jours que le 2026-11-24 (ADR-008, règle de version, point 2). Avant cette date, l'étape 13 prend la version précédente qui passe le délai, ou attend.

## RS-17. CI du golden repo dans CELIAN

Décision : un workflow racine de CELIAN, `golden-saas-b2b.yml`, appelle les tâches du golden repo ; les workflows du golden repo appellent les mêmes tâches. Le contrôle X01 copie le golden repo dans un dépôt Git neuf pour exercer ses propres hooks et sa configuration.

Pourquoi : la spec fait tourner la CI du golden repo dans le dépôt de CELIAN. Une logique écrite une fois, dans les tâches, ne peut pas diverger entre les deux workflows.

Décision du DSI (2026-11-21) : la CI du golden repo tourne dans CELIAN seulement, comme le dit la spec. Les workflows de `golden/saas-b2b/.github/`, jobs du SBOM et du scan compris, décrivent la CI du futur projet généré ; X01 les exerce dans une copie autonome, sans les lancer sur GitHub. Un dépôt miroir, où ils tourneraient tels quels, viendra avec le générateur, hors de ce plan.

Les jobs du workflow racine qui doivent bloquer la fusion (statique, tests unitaires, bout en bout et scan des images, FR-022) entrent dans les contrôles requis du ruleset de `main`, `.github/rulesets/main.json`, qui ne compte aujourd'hui que `pre-commit` et `secrets (full history)`. Le script qui applique le ruleset demande les droits admin : Lucas le lance.

À vérifier avant l'étape 1 (porteur [OPS]) : que GitHub ne lance pas de workflow depuis un sous-dossier, et que Renovate et release-please ne lisent pas une configuration placée dans `golden/saas-b2b/` ; le comportement d'un workflow filtré par chemin face aux contrôles requis du ruleset de `main` ; l'option de `check-yaml` pour les fichiers YAML à plusieurs documents ; ce qu'actionlint lit hors de `.github/workflows/` à la racine ; la présence et la version de Docker sur les runners `ubuntu-latest` (Docker Engine 28.0.0 au moins, ADR-011) ; la disponibilité de runners arm64 pour un dépôt public.

### Relevé du 2026-11-23 (T003)

Fait par [DEV] à la place d'[OPS], porteur désigné, qui relit. Il lève les cinq points que T003 attend avant l'étape 1. Docker sur `ubuntu-latest` reste à T040, les runners arm64 restent ouverts.

1. Workflows d'un sous-dossier. GitHub ne lit les workflows que dans `.github/workflows` à la racine du dépôt : « You must store workflow files in the `.github/workflows` directory of your repository. » Rien de `golden/saas-b2b/.github/` ne tourne dans CELIAN, et X01 reste le seul moyen d'exercer ces workflows.
2. Renovate et release-please. Renovate lit un seul fichier de configuration, le premier trouvé dans une liste fixe de chemins (`renovate.json`, `.github/renovate.json`, `.gitlab/renovate.json`, `.renovaterc` et leurs variantes, `package.json`) : `golden/saas-b2b/renovate.json` n'en fait pas partie et n'est jamais lu. En revanche, les gestionnaires de la configuration de CELIAN trouvent leurs fichiers dans tout le dépôt. Celui des actions GitHub lit `(^|/)(workflow-templates|\.(?:github|gitea|forgejo)/(?:workflows|actions))/.+\.ya?ml$` et `(^|/)action\.ya?ml$`, celui de pre-commit `(^|/)\.pre-commit-config\.ya?ml$` ; ce dernier est coupé par défaut, mais `renovate.json` de CELIAN l'active. Les PR de mise à jour des workflows et des hooks du golden repo viendront donc de la configuration de CELIAN, sous ses règles (7 jours, exception de sécurité). Conséquence pour S23 et T098 : `golden/saas-b2b/renovate.json` se contrôle de façon statique et ne s'exerce que dans X01 ou dans le futur dépôt miroir. Le gestionnaire maison de CELIAN pour les variables `_IMAGE` reste limité à `^\.github/workflows/`. release-please ne lit que les chemins que lui passe le workflow de CELIAN (`config-file`, « Path to the release-please config in the repository », et `manifest-file`) : les fichiers release-please du golden repo sont ignorés. Le paquet `.` de CELIAN couvre tout le dépôt, et un commit sur `golden/` compte dans le journal des versions de CELIAN.
3. Workflow filtré par chemin et contrôles requis. Un workflow sauté par un filtre de chemins, de branches ou par le message de commit laisse ses contrôles en attente (« Pending ») et bloque la fusion ; la page conseille : « Avoid requiring workflows that can be skipped. » Un job sauté par sa condition `if` rend « Success » ; un job qui dépend d'un job en échec est sauté et peut ne pas bloquer la fusion, d'où `always()` avec `needs` pour un contrôle requis. Seuls comptent les contrôles nés d'événements éligibles, dont `push` et `pull_request`. Décision : le workflow `golden-saas-b2b.yml` ne porte aucun filtre de chemins, et son job `static`, rapide, tourne à chaque PR de CELIAN. Un job coûteux (sur kind, à partir de T051) qui voudrait un filtre passera par une condition de job alimentée par un job de détection des changements, avec la garde `always()`, à trancher avec [OPS] à ce moment-là. Le ruleset de `main` nomme déjà ses contrôles par le `name` de leur job (`pre-commit`, `secrets (full history)`) ; le job s'appelle donc `static`, et T014 l'ajoute sous ce nom.
4. YAML à plusieurs documents. `check-yaml` de pre-commit-hooks v6.0.0 (le tag pointe sur le SHA figé dans `.pre-commit-config.yaml`) accepte `--allow-multiple-documents`. `--unsafe` l'implique mais ne fait plus qu'une analyse de syntaxe, « removes all guarantees of portability » : écarté. Décision : une seconde entrée de `check-yaml` avec `--allow-multiple-documents`, limitée à `golden/`, où vivront les manifests Kubernetes ; le reste de CELIAN garde la règle d'un document par fichier (T013).
5. actionlint hors de `.github/workflows/`. Le hook `actionlint` de v1.7.12 (tag égal au SHA figé) porte `files: ^\.github/workflows/` : il ne voit pas `golden/saas-b2b/.github/workflows/`. actionlint vérifie tout fichier passé en argument : « When paths to YAML workflow files are given as arguments, actionlint checks them. » Décision : T013 élargit `files` du hook aux workflows du golden repo, avant qu'ils arrivent à l'étape 2.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax> | 2026-11-23 | Emplacement des workflows ; contrôles en attente si le workflow est sauté par un filtre ; `permissions` (`id-token`, `contents`) |
| <https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/troubleshooting-required-status-checks> | 2026-11-23 | Contrôles requis sautés, job sauté qui rend « Success », dépendance en échec et `always()`, événements éligibles, rulesets |
| <https://docs.renovatebot.com/configuration-options/> | 2026-11-23 | Liste des fichiers de configuration, premier trouvé |
| <https://docs.renovatebot.com/modules/manager/github-actions/> | 2026-11-23 | Motifs de fichiers par défaut du gestionnaire des actions |
| <https://docs.renovatebot.com/modules/manager/pre-commit/> | 2026-11-23 | Motif par défaut, gestionnaire coupé par défaut |
| <https://github.com/googleapis/release-please-action/blob/45996ed1f6d02564a971a2fa1b5860e934307cf7/README.md> | 2026-11-23 | Entrées `config-file`, `manifest-file` et `path` de la version figée dans CELIAN |
| <https://github.com/googleapis/release-please/blob/main/docs/manifest-releaser.md> | 2026-11-23 | Paquet `.` à la racine du dépôt, chemins relatifs à la racine |
| <https://github.com/pre-commit/pre-commit-hooks/blob/3e8a8703264a2f4a69428a0aa4dcb512790b2c8c/README.md> | 2026-11-23 | Options `--allow-multiple-documents` et `--unsafe` de `check-yaml` ; tag v6.0.0 égal à ce SHA |
| <https://github.com/rhysd/actionlint/blob/914e7df21a07ef503a81201c76d2b11c789d3fca/.pre-commit-hooks.yaml> | 2026-11-23 | `files: ^\.github/workflows/` du hook ; tag v1.7.12 égal à ce SHA |
| <https://github.com/rhysd/actionlint/blob/914e7df21a07ef503a81201c76d2b11c789d3fca/docs/usage.md> | 2026-11-23 | Fichiers passés en argument vérifiés |

## RS-18. Outils de test

Décision : scripts bash pour les tests sur kind et les contrôles préalables, comme les scripts de BENCH ; politiques en Rego exécutées par conftest, outil que nomment les ADR-005 à ADR-011 ; validation de schéma par kubeconform, nommé par US-007, outil à confirmer avec [QA] (ADR-005, condition 5) ; Trivy pour le HCL, le SBOM et le scan des images (RS-22) ; conftest aussi pour la décision du scan (RS-23).

À vérifier avant usage, avec version, licence, date et somme de contrôle du binaire : conftest, kubeconform, cosign (qui vérifie aussi la signature de Trivy à chaque montée, RS-22), le framework de test .NET, celui du front, le validateur de configuration de Renovate. Trivy : 0.76.2 lue le 2026-11-23 (RS-22), somme et signature à vérifier à l'installation. Porteur : [DEV], avec [QA] pour le choix final.

Alternatives : des tests en Python, écartés parce que le projet généré n'aurait pas Python dans ses prérequis d'exécution (ENF-07) ; Kyverno en CLI, réservé au profil full.

### Relevé du 2026-11-23 : conftest (T002)

Fait par [DEV]. Sources : l'API GitHub du dépôt `open-policy-agent/conftest`, lue par `gh api`, ses fichiers au tag v0.71.1, et les pages de conftest.dev et de la CNCF.

Version retenue : conftest v0.71.1, publiée le 2026-10-06, dernière release. Elle a 48 jours au 2026-11-23 et passe le délai de 7 jours (principe VI). Licence Apache-2.0, d'après le fichier `LICENSE` (« Licensed under the Apache License, Version 2.0 ») ; l'API GitHub, elle, répond `NOASSERTION`, parce que le fichier commence par un en-tête de copyright.

Gouvernance : le dépôt appartient à l'organisation `open-policy-agent`, celle d'OPA, projet gradué à la CNCF (accepté le 2018-03-29, gradué le 2021-01-29). La page de la CNCF ne nomme pas conftest. La gouvernance de l'organisation (`GOVERNANCE.md` d'OPA) vote par organisation, « so that no single organization can dominate an area of expertise ». `MAINTAINERS.md` d'OPA donne à conftest un seul mainteneur propre, James Alseth (`@jalseth`, « Independent », renouvelé le 2026-09-30), plus deux mainteneurs de tous les dépôts, employés d'Apple. Sur un an, du 2025-11-23 au 2026-11-23, 157 commits, dont 51 humains, de 23 auteurs ; `jalseth` en signe 24 (47 %). Lecture : porté par l'organisation d'un projet de fondation, avec un seul mainteneur actif déclaré pour conftest.

Intégrité : la release publie `checksums.txt` et un SBOM par archive ; elle n'est pas immuable. L'API des attestations en donne une pour l'archive linux amd64 ; elle n'est pas vérifiée ici, faute d'archive téléchargée, et pourra l'être par [SECU]. Les sommes ci-dessous sont lues dans `checksums.txt` (asset 614476987, lu par l'API) ; elles sont égales au champ `digest` de l'API des releases.

| Archive | SHA-256 |
| --- | --- |
| `conftest_0.71.1_Linux_x86_64.tar.gz` | `c3f6b2a753bd56e377a1e51a95ae3e057f926f2e9139f7d5b5dfbbaf810f7985` |
| `conftest_0.71.1_Linux_arm64.tar.gz` | `218c682e110ae7e826dc14a746a6f9b43eb782643dbe730b771fd305634e3f47` |
| `conftest_0.71.1_Darwin_x86_64.tar.gz` | `a309853b5763c18486768157442d440248ee683b20a2aa1f6b28214e818bd780` |
| `conftest_0.71.1_Darwin_arm64.tar.gz` | `e1cc50d2590b6c5e3da6912666a71264bae82d60bdd62d7ae2b99971ccc8eedd` |

Fonctions relevées :

- plusieurs fichiers en une seule entrée : `conftest test --combine`. L'entrée devient une liste dont chaque élément porte `path`, « the relative file path of the file being evaluated », et `contents`, le document lu. S21 s'en sert pour comparer `platform.yaml` aux fichiers qui répètent ses valeurs ;
- Dockerfile : analyseur `dockerfile`, choisi d'office pour un fichier nommé `Dockerfile`, `Dockerfile.*` ou `*.Dockerfile` (`parser/parser.go` au tag), forçable par `--parser` ;
- fichier de données : `--data` (`-d`), qui cherche récursivement les fichiers JSON et YAML des chemins donnés et les expose sous `data.` ;
- tests Rego : `conftest verify --policy <dossier>` lance les règles `test_` ; `--namespace` ne garde que les résultats des paquets nommés, et le code de sortie est non nul si un test échoue ;
- syntaxe : `--rego-version` vaut `v1` par défaut, pour `test` comme pour `verify` (règles en `deny contains msg if`). conftest v0.71.1 embarque OPA v1.21.1 (`go.mod`) ; `regex.match`, `is_string`, `object.get`, `sprintf` et `count` existent depuis OPA v0.23.0 au plus tard ;
- `conftest test` lit le paquet `main` par défaut, `--namespace` en choisit un autre, et sort en 1 quand une politique échoue ;
- piège : un nom de paquet qui n'existe pas ne lève aucune erreur, ni pour `test` ni pour `verify` (`runner/test.go` et `runner/verify.go` au tag), et le contrôle passe sans rien vérifier. Le lanceur des contrôles statiques (T004) refuse donc une politique dont le paquet ne porte pas le nom du fichier, ou qui n'a pas son fichier de tests dans le même paquet.

Effets : les politiques de `golden/saas-b2b/policy/` sont en Rego v1, un paquet par fichier, nommé comme lui, avec ses tests dans le même paquet ; `golden/saas-b2b/tests/tools/install.sh` et `SHA256SUMS` (T011) installent v0.71.1 par ces sommes.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://api.github.com/repos/open-policy-agent/conftest/releases> | 2026-11-23 | v0.71.1 publiée le 2026-10-06, dernière release, non immuable |
| <https://github.com/open-policy-agent/conftest/releases/download/v0.71.1/checksums.txt> | 2026-11-23 | Les quatre SHA-256 du tableau, lus par l'API (asset 614476987) |
| <https://github.com/open-policy-agent/conftest/blob/v0.71.1/LICENSE> | 2026-11-23 | Apache-2.0 |
| <https://api.github.com/repos/open-policy-agent/conftest/attestations/sha256:c3f6b2a753bd56e377a1e51a95ae3e057f926f2e9139f7d5b5dfbbaf810f7985> | 2026-11-23 | Une attestation, non vérifiée |
| <https://github.com/open-policy-agent/opa/blob/main/GOVERNANCE.md> | 2026-11-23 | Vote par organisation |
| <https://github.com/open-policy-agent/opa/blob/main/MAINTAINERS.md> | 2026-11-23 | Mainteneur de conftest, mainteneurs de tous les dépôts |
| <https://www.cncf.io/projects/open-policy-agent-opa/> | 2026-11-23 | OPA gradué, dates ; conftest non nommé |
| <https://api.github.com/repos/open-policy-agent/conftest/commits?since=2025-11-23T00:00:00Z> | 2026-11-23 | Commits de l'année par auteur |
| <https://www.conftest.dev/options/> | 2026-11-23 | `--combine`, `--data`, `--parser`, `--policy`, sorties, code de sortie |
| <https://github.com/open-policy-agent/conftest/blob/v0.71.1/docs/options.md> | 2026-11-23 | Clés `path` et `contents` de l'entrée combinée |
| <https://github.com/open-policy-agent/conftest/blob/v0.71.1/docs/index.md> | 2026-11-23 | `conftest verify`, tests en `test_` avec `with input as`, syntaxe v1 des exemples |
| <https://github.com/open-policy-agent/conftest/blob/v0.71.1/parser/parser.go> | 2026-11-23 | Détection des Dockerfile, analyseurs disponibles |
| <https://github.com/open-policy-agent/conftest/blob/v0.71.1/internal/commands/test.go> | 2026-11-23 | Options de `test`, `--rego-version` à `v1`, paquet `main` par défaut |
| <https://github.com/open-policy-agent/conftest/blob/v0.71.1/internal/commands/verify.go> | 2026-11-23 | Options de `verify`, sortie non nulle sur échec |
| <https://github.com/open-policy-agent/conftest/blob/v0.71.1/runner/verify.go> | 2026-11-23 | Filtre de `--namespace` sur le paquet des tests ; aucun paquet trouvé, aucune erreur |
| <https://github.com/open-policy-agent/conftest/blob/v0.71.1/runner/test.go> | 2026-11-23 | Paquet nommé lu tel quel, sans contrôle d'existence |
| <https://github.com/open-policy-agent/conftest/blob/v0.71.1/go.mod> | 2026-11-23 | OPA v1.21.1 |
| <https://www.openpolicyagent.org/docs/policy-reference/builtins> | 2026-11-23 | Signatures et version d'apparition des fonctions citées |

## RS-19. Mesures de la gate

Décision : la démo de l'étape 17 reprend la méthode des scripts de BENCH pour le volume et le temps, sur un poste propre, en profil standard, et rapporte le volume au budget de 900 s et au débit qu'il exige.

À fixer : la méthode exacte de mesure du volume en démo, avec [BENCH] ; le poste et sa connexion, notés dans le rapport.

## RS-20. Ports de l'hôte

Décision : deux ports de l'hôte, HTTP et HTTPS, en `listenAddress: "127.0.0.1"`, valeurs fixées à l'étape 7 et vérifiées libres avant toute création (P04). Ils se fixent à la création du cluster : la configuration les déclare d'emblée.

Sources : ADR-004, condition 1 et conséquences ; ADR-005, portée ; spec, cas limites.

## RS-21. Kubeconfig et contexte

Décision : `task up` écrit le kubeconfig du cluster dans un fichier propre au projet, hors du dépôt, et passe ce fichier à chaque commande ; le kubeconfig par défaut de l'utilisateur n'est ni lu ni modifié.

Pourquoi : ADR-004, condition 9 ; FR-019 ; décision de la GATE 1 (aucun contexte GKE sur le poste avant la GATE 2). Un fichier dédié évite aussi qu'un contexte cloud courant reçoive une commande par erreur.

À trancher avec [SECU] à l'étape 6 : l'emplacement exact du fichier, au regard de R-07 (ce kubeconfig lit tous les Secrets du cluster).

## RS-22. Outil du SBOM et du scan, format du SBOM

Décision : Trivy pour les deux, SBOM au format CycloneDX en JSON. Un seul binaire produit le SBOM de chaque image construite et scanne chaque image de l'inventaire (RS-24). C'est déjà l'outil du scan du HCL (ADR-008, condition 6), et l'ADR-011 (condition 8) comme R-34 parlent du « SBOM et [du] scan Trivy du projet généré ». Trivy ne figure pas encore dans la CI de CELIAN : ni `.github/workflows/` ni `.pre-commit-config.yaml` ne l'appellent au 2026-11-23. Il n'a tourné qu'à la main, chez [SECU], pour BENCH-004 et BENCH-008.

Pourquoi :

- un outil de moins à figer, vérifier et suivre. La chaîne de Trivy a elle-même été compromise en mars 2026 (plus bas) : chaque outil de CI est une porte d'entrée ;
- CycloneDX, parce que Dependency-Track, que le brief et le PRD prévoient pour plus tard (Q9), consomme des BOM CycloneDX. Trivy écrit CycloneDX en JSON seulement (`--format cyclonedx`, XML non pris en charge), et SPDX en texte ou en JSON.

Écart au PRD : le PRD (US-009) et le brief nomment Syft pour le SBOM. Le plan s'en écarte pour la raison ci-dessus, écart confirmé par Lucas le 2026-11-23 ; il s'écrira dans le PRD.

Installation : binaire de la release, SHA-256 écrit dans le dépôt et vérifié avant chaque usage, sur le modèle de kind (ADR-004, condition 5). À chaque montée de version, [SECU] vérifie par cosign la signature sigstore de la release avant d'écrire la somme. Jamais par les actions `aquasecurity/trivy-action` ni `aquasecurity/setup-trivy` (S26). Plancher : 0.71.1, qui corrige CVE-2026-55092. Candidate : 0.76.2, celle de BENCH-008, publiée le 2026-11-05 en release immuable avec son fichier de sommes et ses bundles sigstore ; elle passe le délai de 7 jours (principe VI). Licence Apache-2.0 ; projet d'Aqua Security, éditeur unique.

Base de vulnérabilités : téléchargée à chaque exécution depuis ses registres par défaut, `mirror.gcr.io/aquasec` puis `ghcr.io/aquasecurity`. Jamais mise en cache d'une exécution à l'autre, jamais sautée (`--skip-db-update` interdit, S26) : une base périmée tirée d'un cache passerait au vert sans avoir vu les avis du jour, ce que refuse le cas limite de la spec.

Conservation : les SBOM sont des artefacts de l'exécution, à la rétention par défaut de GitHub, 90 jours, le maximum permis pour un dépôt public.

Compromission de mars 2026 : CVE-2026-33634 (GHSA-69fq-xp46-6x23, critique, publiée le 2026-03-21). Une v0.69.4 malveillante est partie sur tous les canaux de distribution ; 76 des 77 tags de `trivy-action` et les 7 tags de `setup-trivy` ont été réécrits vers du code qui volait les secrets des pipelines. L'avis recommande d'épingler les actions par SHA complet et de vérifier les binaires par cosign ; les images désignées par condensat n'étaient pas touchées. S'y ajoute CVE-2026-55092 (GHSA-mcj4-mphf-j9ff, élevée, publiée le 2026-06-15) : un artefact OCI hostile, base de vulnérabilités comprise, fait écrire Trivy hors de son dossier, sur les versions antérieures à 0.71.1.

À vérifier avant l'étape 18 (porteur [DEV], avec [SECU]) :

- la documentation de la version retenue : la page des filtres lue le 2026-11-23 s'annonce comme une version antérieure à la dernière (ses liens visent v0.67.2) ;
- le code de sortie de Trivy quand aucun registre de la base ne répond : la page de la base décrit le repli d'un registre à l'autre sur erreur transitoire, pas l'échec total. E27 le joue ;
- la lecture d'une image construite dans le moteur du runner, ou par une archive ;
- la commande cosign qui vérifie le bundle sigstore, et la version de cosign.

Alternatives : Syft pour le SBOM, nommé par le PRD, écarté pour l'outil de plus ; SPDX, écarté parce que Dependency-Track lit CycloneDX ; l'image de Trivy par condensat, sur le modèle de gitleaks dans `.github/workflows/secrets.yml`, gardée en repli, parce que la lecture des images construites depuis un conteneur reste à vérifier.

Sources :

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://trivy.dev/latest/docs/supply-chain/sbom/> | 2026-11-23 | Formats CycloneDX (`--format cyclonedx`, JSON seulement) et SPDX ; scan d'un SBOM en entrée |
| <https://trivy.dev/latest/docs/configuration/db/> | 2026-11-23 | Registres de la base, `--skip-db-update`, repli entre registres sur erreur transitoire ; échec total non décrit |
| <https://github.com/aquasecurity/trivy/security/advisories/GHSA-69fq-xp46-6x23> | 2026-11-23 | CVE-2026-33634 : versions, fenêtres, actions réécrites, remède (SHA, cosign) |
| <https://github.com/aquasecurity/trivy/security/advisories/GHSA-mcj4-mphf-j9ff> | 2026-11-23 | CVE-2026-55092, corrigée en 0.71.1 |
| <https://api.github.com/repos/aquasecurity/trivy/releases/latest> | 2026-11-23 | v0.76.2, publiée le 2026-11-05, release immuable, fichier de sommes et bundles sigstore |
| <https://github.com/aquasecurity/trivy> | 2026-11-23 | Apache-2.0 ; « an Aqua Security open source project » ; dépôt non archivé |
| <https://docs.dependencytrack.org/usage/cicd/> | 2026-11-23 | Dependency-Track consomme des BOM CycloneDX |
| <https://docs.github.com/en/organizations/managing-organization-settings/configuring-the-retention-period-for-github-actions-artifacts-and-logs-in-your-organization> | 2026-11-23 | Rétention des artefacts : 90 jours par défaut, de 1 à 90 jours pour un dépôt public |

## RS-23. Seuil de gravité et exceptions

Décision : seuil `HIGH`. Une vulnérabilité `HIGH` ou `CRITICAL` fait échouer le scan, sauf exception valide. Le seuil est écrit une seule fois, dans `security/scan-policy.yaml` (nom provisoire), et la tâche de scan le lit là (S26).

Pourquoi `HIGH` : la seule faille connue de la stack, CVE-2026-97054 dans le contrôleur d'Envoy Gateway 1.10.0, est élevée (ADR-005). Un seuil `CRITICAL` la laisserait passer en silence, ce que le récit 7 veut éviter. `MEDIUM` n'est pas retenu d'emblée : le nombre de failles moyennes sur les images de la stack n'est pas mesuré, et des exceptions en série finiraient signées sans être lues. La première PR de l'étape 18 donne ces nombres ; [SECU] pourra alors proposer d'abaisser le seuil. Niveaux relevés dans la documentation de Trivy : `UNKNOWN`, `LOW`, `MEDIUM`, `HIGH`, `CRITICAL`. Une faille `UNKNOWN` ne bloque pas et reste listée dans le rapport ; [SECU] relit ce choix.

Failles sans correctif : aucune option ne les écarte (`--ignore-unfixed` interdit, S26). FR-022 ne distingue pas une faille corrigée d'une faille qui ne l'est pas : au seuil, la seconde demande une exception, avec son échéance.

Exceptions : un fichier par couche, `security/scan-exceptions.yaml` pour les images construites et `local/security/scan-exceptions.yaml` pour les images de la couche `local` (noms provisoires), pour que la phase 3 rende chaque couche avec les siennes. Chaque entrée porte l'identifiant de la vulnérabilité, l'image visée, la justification, la date d'écriture et la date d'échéance. L'image se désigne par son dépôt, sans condensat, pour qu'une montée de condensat par Renovate ne fasse pas tomber l'exception avant son échéance. Proposé, à confirmer par [SECU] : une échéance à 90 jours au plus de la date d'écriture.

Décision du passage : Trivy écrit un rapport JSON par image, filtré au seuil, sans échouer. Une politique Rego, exécutée par conftest, reçoit ce rapport, les exceptions et la date du jour, que la tâche lui passe en donnée. Elle refuse chaque couple image et vulnérabilité au seuil sans exception valide, en les nommant (récit 7, scénario 3). Une exception échue, incomplète ou qui vise une autre image ne compte pas (scénarios 4 et 5). Passer la date en donnée rend la politique testable sur des rapports d'exemple (U03), sans réseau ni image vulnérable.

Première exception attendue : CVE-2026-97054, si aucune release 1.10.x corrigée n'est sortie à l'étape 18. [SECU] l'écrit, avec la justification de l'ADR-005 : les serveurs touchés ne sont joignables que depuis le cluster.

Alternatives : le fichier `.trivyignore.yaml` de Trivy, écarté. Son format est marqué expérimental, il n'a ni portée par image ni date d'écriture, une entrée incomplète n'y est pas refusée, et la page ne dit pas ce que devient une entrée échue. Seuils `CRITICAL` et `MEDIUM`, écartés plus haut.

À vérifier avant l'étape 18 (porteur [DEV]) : la structure du rapport JSON de Trivy dans la version retenue ; l'option de conftest qui charge un fichier de données ; le passage de la date en donnée.

Sources : <https://trivy.dev/latest/docs/configuration/filtering/>, lue le 2026-11-23 (`--severity`, niveaux de l'exemple, `--ignore-unfixed`, format expérimental de `.trivyignore.yaml` et ses champs `id`, `paths`, `purls`, `expired_at`, `statement`) ; ADR-005, CVE-2026-97054 ; spec, FR-022.

## RS-24. Inventaire des images

Décision : l'inventaire d'un profil se calcule à chaque exécution, sans recopier les condensats. Il réunit les images des rendus du profil, celles des fichiers vendorés (Envoy Gateway, Flux), l'image du nœud de la configuration kind, celle du miroir et les images construites sous `saas-b2b.invalid`. S'y ajoute une courte liste versionnée, `local/security/unlisted-images` (nom provisoire), des images qu'aucun fichier du projet ne nomme : celles que l'image du nœud précharge (plan de contrôle, réseau, DNS, provisionneur de volumes), et l'image du proxy, que le contrôleur d'Envoy Gateway porte figée par condensat dans son binaire (BENCH-004).

E25 relève, après `task up` dans chaque profil livré, l'image résolue (son condensat) de chaque conteneur en marche dans le cluster, conteneurs d'initialisation compris, et de chaque conteneur du moteur. Sur le runner de CI, le moteur ne porte que les conteneurs du projet ; sur un poste, seuls ceux du projet sont relevés. E25 échoue sur toute image absente de l'inventaire scanné. Une montée de l'image du nœud ou d'Envoy Gateway qui change ces images fait donc échouer E25 tant que la liste n'est pas à jour : c'est le contrôle que FR-021 demande.

Hors de l'inventaire : les images de construction (SDK .NET, Node.js), qui ne tournent ni dans le cluster ni sur le moteur une fois `task up` fini ; ce qu'elles laissent dans l'image finale figure dans le SBOM des images construites. Les images de Config Sync du test E16 ne tournent pas sur le poste : elles se scannent aussi, au titre de R-32, sans entrer dans l'inventaire.

Pourquoi : un inventaire tenu à la main en double des manifests ferait échouer chaque PR de Renovate ; une liste seulement calculée manquerait les images qu'aucun manifest ne nomme, celles que vise FR-021.

À vérifier avant la seconde PR de l'étape 18 (porteur [DEV], avec [OPS]) : le champ du statut des pods qui porte l'image résolue ; la référence des images préchargées dans le nœud (registre amont, condensat d'index ou de plate-forme) et leur scan par Trivy depuis ce registre ; à défaut, leur export depuis le nœud vers une archive scannée, commande à vérifier.

Sources : spec, FR-021 et entité « Inventaire des images » ; BENCH-004, image du proxy figée dans le binaire du contrôleur ; R-32.

## RS-25. Authentification de l'exemple

Décision du DSI (2026-11-21) : aucune authentification en local. Elle arrive avec l'ADR-013, qui choisira le fournisseur d'identité après BENCH-012, en cours. Règle : aucun déploiement réel sur GCP sans authentification. La phase 2 n'en fait aucun (décision de Lucas du 2026-11-20).

Pourquoi : l'exemple n'a pas d'utilisateur, et rien n'écoute hors de la boucle locale (FR-003). Sur GCP, la Gateway publierait l'API à tous.

Conséquence à suivre : brancher l'API sur le fournisseur d'identité ajoute du code au-delà de FR-009 (santé, exemple, front). L'ADR-013 demandera donc un amendement de la spec, ou une lecture de Q7 par [PO]. Jusque-là, Keycloak tourne sans être appelé par l'API (RS-15).

## Synthèse des points à vérifier

| Point | Porteur | Étape bloquée |
| --- | --- | --- |
| Versions du front, des frameworks de test, de Task, conftest, kubeconform, cosign, provider `random`, Npgsql, client du cache | [DEV] | 1 à 19, chacun à son entrée |
| Correspondance par préfixe de chemin dans le cœur de Gateway API et chez GKE | [DEV] | 7 |
| Composants de Kustomize dans la version qu'embarque kubectl | [DEV] | 7 |
| Fabrication de `gateway-tls` sans fichier | [SECU], [DEV] | 7 (HTTPS) |
| TLS vers la base | [DEV], [SECU] | 8 |
| Moteur du cache, local et Memorystore, et son authentification : BENCH-014 puis ADR-015 | [BENCH], [ARCHI] | 19 et 20, donc 9 et la suite du profil lite |
| Mot de passe du cache sans argument ; TLS vers le cache ; RESP pour toutes les options de BENCH-014 | [DEV], [SECU], [BENCH] | 19 |
| Nom sous `.invalid` avec `kind load` | [OPS] | 9 |
| Lecture de la mémoire déclarée par le moteur | [DEV] | 5 |
| Comportement de GitHub, Renovate, release-please et actionlint face au sous-dossier ; contrôles requis d'un workflow filtré par chemin ; runners | [OPS] | 1, 2, 18 |
| Validation OpenTofu hors ligne, verrou multi-plateformes, attributs des activations | [OPS] | 13 |
| Emplacement du kubeconfig | [SECU] | 6 |
| Montages de zot à plusieurs amonts | [OPS] | 12, ou 19 selon le registre du cache |
| `Kustomization` suspendue sans objet source ; interrogation des droits d'un compte de service | [DEV] | 12 |
| Trivy : documentation de 0.76.2, code de sortie sans base, lecture des images construites, rapport JSON ; cosign pour son bundle | [DEV], [SECU] | 18 |
| conftest : fichier de données et date passée en donnée | [DEV] | 18 |
| Image résolue dans le statut des pods ; images préchargées du nœud et leur scan | [DEV], [OPS] | 18, seconde PR |
