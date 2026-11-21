# Research: golden repo SaaS B2B

Phase 0 du plan ([plan.md](plan.md)). Rédigé par [DEV] le 2026-11-21.

Aucune recherche nouvelle sur Internet n'a été faite pour ce document : chaque fait vient d'un ADR, d'un benchmark, du catalogue ou d'un script de benchmark versionné, avec sa date de lecture d'origine. Ce qui manque est écrit « à vérifier », avec son porteur et l'étape qu'il bloque. Les choix déjà faits par les ADR-004 à ADR-012 ne sont pas rouverts ; les points ci-dessous fixent ce que ces ADR laissaient au golden repo.

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

Décision : une ressource « note » (identifiant, texte de 1 à 500 caractères, date de création). Écriture en base, lecture par identifiant en lecture paresseuse par le cache, liste des plus récentes depuis la base, provenance de la lecture dans la réponse. Deux routes de santé : vivant et prêt. Accès à la base par Npgsql, requêtes paramétrées, sans ORM ; client du cache compatible RESP.

Pourquoi : FR-009 et Q7 limitent le code à l'exemple. Une note relue après un rechargement prouve la conservation des données (récit 1, scénario 3) ; la provenance rend l'usage du cache testable sans regarder dans le cache. Sans ORM, il n'y a qu'une dépendance de base de données à suivre.

Alternatives : un compteur de visites, écarté parce qu'il ne prouve pas la relecture d'une donnée précise ; Entity Framework Core, écarté pour son poids face à une seule table ; aucune liste, écartée parce que le front n'aurait rien à afficher au chargement.

À vérifier avant l'étape 3 : version, licence et date de Npgsql et du client .NET du cache ; format des réponses d'erreur d'ASP.NET Core (ProblemDetails) ; verrouillage des paquets NuGet par fichier de verrouillage. Porteur : [DEV].

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

Décision : profil choisi selon la mémoire que déclare le moteur ; variable `PROFILE` pour forcer, sous les mêmes contrôles. Seuils de départ : VM de 2,0 Gio pour le lite, 2,5 Gio pour la partie connue du standard. Seuils recalculés sur la première mesure et à l'entrée de Keycloak et de Mailpit.

Pourquoi : ADR-004, condition 6 (mémoire déclarée par le moteur, pas mémoire physique) ; spec, cas limites. Les seuils sont des ordres de grandeur de [FINOPS] qui mêlent plusieurs séries.

À vérifier : la commande qui lit la mémoire déclarée, sous Docker Engine et sous le moteur libre que retiendra [OPS]. Porteur : [DEV], étape 5.

Sources : ADR-004, condition 6 ; ADR-006, conséquences ; ADR-011 et ADR-012, conséquences.

## RS-09. Taskfile et scripts

Décision : `Taskfile.yml` à la racine expose les commandes publiques et délègue aux Taskfiles inclus de `local/tasks/` et `gcp/tasks/`. La logique vit dans des scripts bash de `local/scripts/`, compatibles avec bash 3.2, sans heredoc, passés à shellcheck. Le Taskfile porte en tête l'inventaire des commandes qui créent, modifient ou suppriment un conteneur, un réseau ou un volume. Construction, chargement et application sont définis une fois et réutilisés par `task up` et `task reload`.

Pourquoi : ADR-006, condition 6 ; ADR-007, condition 1 (bash 3.2 de macOS, heredoc) ; ADR-011, condition 11.

À vérifier avant l'étape 1 : version de Task, sa syntaxe d'inclusion, le mode silencieux et la détection de sources modifiées utile à `task reload`. Porteur : [DEV].

## RS-10. Secrets locaux

Décision : `db-auth`, `cache-auth`, `db-superuser` et `gateway-tls` en profil lite ; valeurs de 40 caractères alphanumériques tirées de `/dev/urandom`, comme l'essai de BENCH-011, passées par un tube à `kubectl create -f -`, seulement si le Secret manque. Contrat : [contracts/secrets.md](contracts/secrets.md).

Pourquoi : ADR-007, condition 1 ; ADR-012, conditions 3, 8 et 10.

Non décidé : la fabrication de la clé et du certificat de `gateway-tls`. BENCH-004 écrivait la clé dans un fichier, ce que la condition 1 de l'ADR-007 interdit au projet généré. Piste : un outil qui écrit la clé et le certificat sur sa sortie standard, envoyée par un tube ; outil, disponibilité sur macOS et Linux et syntaxe à vérifier. Porteurs : [SECU] et [DEV]. Bloque l'écouteur HTTPS de l'étape 7 ; l'écouteur HTTP n'en dépend pas, ce que l'étape 7 vérifie.

## RS-11. Cache

Décision pour le golden repo : sur `local`, Valkey en Deployment d'une réplique, sans persistance, image de l'essai de BENCH-005, mot de passe lu depuis `cache-auth`.

Pourquoi : le brief et la spec nomment Valkey ; un cache n'a pas de donnée à garder entre deux démarrages.

Non décidé : le moteur de Memorystore (Redis, mesuré dans le socle de BENCH-008, ou Valkey, préféré par l'illustration de l'ADR-009), son authentification (chaîne AUTH générée par le serveur et écrite en clair dans l'état, ADR-008) et donc le producteur de `cache-auth` sur `gcp`. L'ADR-008 et l'ADR-012 renvoient tous deux à un « benchmark du moteur de cache » qui n'est pas ouvert. Porteurs : DSI et [ARCHI]. Bloque la ressource Memorystore de l'étape 13 et la ligne `gcp` de `cache-auth`.

À vérifier avant l'étape 8 : la façon de transmettre le mot de passe à Valkey sans argument de commande, sur sa documentation (ADR-006, condition 2) ; le mode TLS face à Memorystore. Porteur : [DEV].

Sources : ADR-006, condition 2 ; ADR-008, portée et condition 3 ; ADR-009, section 2 ; `tests/bench/bench-005-orchestration.sh`, ligne 108.

## RS-12. Postgres local

Décision : l'ADR-012 tel quel. Namespace unique pour la base et l'application, comme le propose sa condition 9.

Ouvert : la question 1 de l'ADR-012 (namespace à part) attend Lucas. Si Lucas retient un namespace à part, `task up` tient deux exemplaires de `db-auth`, et E08 change. Restent à faire sur le golden repo, d'après les suites de l'ADR-012 : `readOnlyRootFilesystem`, l'effet de `pg_isready` sur les journaux, le script d'initialisation sous `scram-sha-256` local, l'état TLS du serveur.

## RS-13. Miroir

Décision : l'ADR-011 tel quel, avec ses noms provisoires (`task down`, `task app:down`, `task mirror:purge`). La liste des registres vit dans `local/mirror/registries`. La configuration zot et les `hosts.toml` en sont dérivés et versionnés ; S13 vérifie qu'ils restent d'accord, ce qui évite de générer du JSON à l'exécution sans outil dédié.

Ouvert : les montages a et b pour plusieurs amonts, essayés à l'étape 12 avec ghcr.io ; le mécanisme de purge par défaut (commande explicite, avis d'[ARCHI]) ; le temps de démarrage du miroir, mesuré par E17.

## RS-14. Flux dans le profil standard

Décision proposée : `task up` installe Flux depuis son `install.yaml` vendoré, quatre contrôleurs, options de verrouillage de la condition 3 de l'ADR-010. Tant que Lucas n'a pas dit ce que lit Flux sur le PC (ADR-010, question 1), la liaison est livrée suspendue : `task up` et `task reload` restent les seuls à appliquer les objets de l'application, ce que l'ADR-010 demande (question 3, un seul acteur).

Pourquoi : la mesure du profil standard (SC-002) compte les images et la mémoire de Flux, qui ne dépendent pas de la source. Une source choisie sans Lucas engagerait soit un identifiant sur le poste, soit une image non mesurée.

Alternatives : attendre la décision avant l'étape 12, écarté parce que D02 attendrait aussi ; un dépôt distant public, qui garde la dépendance au réseau contre l'ADR-011.

## RS-15. Keycloak et Mailpit

Décision : aucune image, version ni manifest avant les ADR-013 et ADR-014. Chaque couche entre par le même chemin : un dossier de `local/`, un ajout à la composition `local/k8s/standard`, ses Secrets créés selon l'ADR-007, son registre ajouté à la liste du miroir, E10 rejoué en standard, seuil de mémoire recalculé.

Ouvert : Keycloak est-il branché sur l'API ? FR-009 limite le code à l'exemple ; tant que la spec ne le demande pas, Keycloak tourne sans être appelé par l'API. Une base pour Keycloak, si BENCH-012 en demande une, s'ajoute dans la même couche.

## RS-16. Couche GCP

Décision : racine OpenTofu unique dans `gcp/tofu/`, ressources du socle de l'ADR-008, provider `google` 8.12.0 et provider `random` dans un verrou versionné. Validation en CI par `tofu init -lockfile=readonly` puis `tofu validate`, sans backend distant ni identifiant.

À vérifier avant l'étape 13 (porteur [OPS], avec [DEV]) : l'option qui désactive le backend à l'init ; la validation d'une configuration de chiffrement `gcp_kms` sans accès à la clé ; la commande qui inscrit les sommes de chaque plateforme dans le verrou et le comportement de `-lockfile=readonly` sur une plateforme absente (ADR-008, question 5) ; la lecture de `platform.yaml` par une fonction de décodage YAML d'OpenTofu ; les attributs des activations (Gateway API, synchronisation des secrets, flotte, Config Sync) ; la version du provider `random`.

Contrainte de date : `google` 8.12.0 ne passe le délai de 7 jours que le 2026-11-24 (ADR-008, règle de version, point 2). Avant cette date, l'étape 13 prend la version précédente qui passe le délai, ou attend.

## RS-17. CI du golden repo dans CELIAN

Décision : un workflow racine de CELIAN, `golden-saas-b2b.yml`, appelle les tâches du golden repo ; les workflows du golden repo appellent les mêmes tâches. Le contrôle X01 copie le golden repo dans un dépôt Git neuf pour exercer ses propres hooks et sa configuration.

Pourquoi : la spec fait tourner la CI du golden repo dans le dépôt de CELIAN. Une logique écrite une fois, dans les tâches, ne peut pas diverger entre les deux workflows.

À vérifier avant l'étape 1 (porteur [OPS]) : que GitHub ne lance pas de workflow depuis un sous-dossier, et que Renovate et release-please ne lisent pas une configuration placée dans `golden/saas-b2b/` ; le comportement d'un workflow filtré par chemin face aux contrôles requis du ruleset de `main` ; l'option de `check-yaml` pour les fichiers YAML à plusieurs documents ; ce qu'actionlint lit hors de `.github/workflows/` à la racine ; la présence et la version de Docker sur les runners `ubuntu-latest` (Docker Engine 28.0.0 au moins, ADR-011) ; la disponibilité de runners arm64 pour un dépôt public.

Alternative : un dépôt GitHub à part, miroir du golden repo, où ses workflows tourneraient tels quels. Écartée par défaut : la spec place la CI dans CELIAN, et un nouveau dépôt est une décision de Lucas (question ouverte).

## RS-18. Outils de test

Décision : scripts bash pour les tests sur kind et les contrôles préalables, comme les scripts de BENCH ; politiques en Rego exécutées par conftest, outil que nomment les ADR-005 à ADR-011 ; validation de schéma par kubeconform, nommé par US-007, outil à confirmer avec [QA] (ADR-005, condition 5) ; Trivy pour le HCL.

À vérifier avant usage, avec version, licence, date et somme de contrôle du binaire : conftest, kubeconform, Trivy (0.76.2 dans BENCH-008), cosign, le framework de test .NET, celui du front, le validateur de configuration de Renovate. Porteur : [DEV], avec [QA] pour le choix final.

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

## Synthèse des points à vérifier

| Point | Porteur | Étape bloquée |
| --- | --- | --- |
| Versions du front, des frameworks de test, de Task, conftest, kubeconform, cosign, provider `random`, Npgsql, client du cache | [DEV] | 1 à 13, chacun à son entrée |
| Correspondance par préfixe de chemin dans le cœur de Gateway API et chez GKE | [DEV] | 7 |
| Composants de Kustomize dans la version qu'embarque kubectl | [DEV] | 7 |
| Fabrication de `gateway-tls` sans fichier | [SECU], [DEV] | 7 (HTTPS) |
| Mot de passe de Valkey sans argument ; TLS vers la base et le cache | [DEV], [SECU] | 8 |
| Moteur et authentification de Memorystore | DSI, [ARCHI] | 13 |
| Nom sous `.invalid` avec `kind load` | [OPS] | 9 |
| Lecture de la mémoire déclarée par le moteur | [DEV] | 5 |
| Comportement de GitHub, Renovate, release-please et actionlint face au sous-dossier ; runners | [OPS] | 1, 2 |
| Validation OpenTofu hors ligne, verrou multi-plateformes, attributs des activations | [OPS] | 13 |
| Emplacement du kubeconfig | [SECU] | 6 |
| Montages de zot à plusieurs amonts | [OPS] | 12 |
