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

## RS-18. Outils de test

Décision : scripts bash pour les tests sur kind et les contrôles préalables, comme les scripts de BENCH ; politiques en Rego exécutées par conftest, outil que nomment les ADR-005 à ADR-011 ; validation de schéma par kubeconform, nommé par US-007, outil à confirmer avec [QA] (ADR-005, condition 5) ; Trivy pour le HCL, le SBOM et le scan des images (RS-22) ; conftest aussi pour la décision du scan (RS-23).

À vérifier avant usage, avec version, licence, date et somme de contrôle du binaire : conftest, kubeconform, cosign (qui vérifie aussi la signature de Trivy à chaque montée, RS-22), le framework de test .NET, celui du front, le validateur de configuration de Renovate. Trivy : 0.76.2 lue le 2026-11-23 (RS-22), somme et signature à vérifier à l'installation. Porteur : [DEV], avec [QA] pour le choix final.

Alternatives : des tests en Python, écartés parce que le projet généré n'aurait pas Python dans ses prérequis d'exécution (ENF-07) ; Kyverno en CLI, réservé au profil full.

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
