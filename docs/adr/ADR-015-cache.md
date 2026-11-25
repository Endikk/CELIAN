# ADR-015. Le cache du projet généré est Valkey 9.1 sur `local` et Memorystore for Valkey sur `gcp`, authentifié par jeton, sous conditions et avec une dérogation datée à ENF-03

| Champ | Valeur |
| --- | --- |
| Statut | accepté |
| Date | 2026-11-25 |
| Auteur | [ARCHI] |
| Décideur | DSI, par délégation de Lucas pendant son absence : décisions du 2026-11-25 sur BENCH-014 ; acceptation par la fusion de la PR de cet ADR |
| BENCH lié | [BENCH-014](../benchmarks/BENCH-014-cache.md) |
| Remplace | aucun |

## Contexte et problème

Le blueprint SaaS B2B du MVP porte un cache (constitution, périmètre du MVP). FR-001 de la spec 001 veut que `task up` démarre l'API, le front, la base et le cache dans le cluster local, et FR-009 que l'exemple lise et écrive dans la base et dans le cache. Trois ADR acceptés renvoient le moteur à son benchmark. L'[ADR-008](ADR-008-modules-opentofu-gcp.md) laisse hors de sa décision « le moteur du cache (Redis ou Valkey) et son authentification » : il constate que la chaîne AUTH de Memorystore finit en clair dans l'état (condition 2) et renvoie l'authentification IAM à ce benchmark (condition 3). L'[ADR-007](ADR-007-secrets.md) et l'[ADR-012](ADR-012-postgres-local.md) font de même.

Le plan du golden repo bloque sur ce choix deux étapes. L'étape 19, couche cache locale (T075 à T081), dont dépend l'étape 9 et donc tout le profil lite. L'étape 20, Memorystore et le producteur `gcp` du Secret `cache-auth`. Lucas a demandé un benchmark court le 2026-11-21, et refusé le 2026-11-23 toute image de cache provisoire (plan, tableau des décisions).

Les exigences viennent du PRD et de la spec. ENF-02 veut chaque brique sur les deux cibles, seule la couche de cible changeant, et les écarts listés au README. ENF-03 veut que Kyverno refuse les images non signées, en phase 4. FR-004 et FR-005 règlent les secrets locaux, FR-008 fige chaque image par condensat, FR-016 veut un redémarrage sans registre public, FR-021 scanne toute image en marche.

Les décisions acceptées posent leurs contraintes. [ADR-001](ADR-001-format-spec.md) : la brique abstraite prend le nom du type Score, `redis` (condition 2). [ADR-004](ADR-004-cluster-local.md) : images par condensat (condition 3). [ADR-006](ADR-006-orchestration-locale.md) : aucun Secret sous `k8s/` (condition 1) ; un mot de passe imposé au cache, lu dans un Secret créé par `task up`, jamais dans `command` ni `args` (condition 2). ADR-007 : Secrets créés par un tube et liste des valeurs connues (condition 1), même nom et mêmes clés sur les deux cibles (condition 5) ; le contrat du plan nomme `cache-auth`, type `Opaque`, clé `password`. ADR-008 : état et plans chiffrés (condition 2), attributs `*_wo` (condition 3), conftest sur le HCL (condition 6). [ADR-009](ADR-009-catalogue.md) : sur le cloud, entre deux variantes managées, on préfère celle dont le moteur est porté par une fondation (section 2, point 2a) ; le standard du cache est `resp`. [ADR-011](ADR-011-miroir-registres.md) : toute image du nœud passe par zot, sous la liste unique de la condition 10, où docker.io figure. ADR-012 : profil `restricted` dans le namespace de l'application ; sa dérogation à ENF-03 s'arrête à `docker.io/library/` et ne couvre pas `valkey/valkey`. [ADR-016](ADR-016-images-sans-date.md) : Renovate date les images de Docker Hub. Côté risques : R-04, R-05, R-20, R-25 et R-36.

BENCH-014 a comparé Valkey 9.1.4 et Redis 7.2.17, chacun noté avec sa variante de Memorystore. La série 2 du 2026-11-25 les a mesurés, trois exécutions valides chacun. [SECU] et [FINOPS] ont relu le rapport le même jour, et le DSI a arbitré le même jour, par délégation de Lucas. Le rapport laisse à [ARCHI] l'authentification et le réseau sur `gcp`, la parité de comportement entre les deux cibles et la forme de la dérogation.

## Options considérées

Grille réconciliée par le DSI le 2026-11-25, après la correction de maturité de [SECU] :

| Option | Score BENCH (sur 100) | Verdict | Raison principale |
| --- | --- | --- | --- |
| Valkey 9.1.4, image `valkey/valkey:9.1.4-alpine` sur `local`, Memorystore for Valkey sur `gcp` | 86 | retenue | BSD-3-Clause pour le moteur et l'image ; projet de LF Projects, neuf mainteneurs chez huit organisations, aucune au-delà d'un tiers du comité ; même ligne 9.1 que celle que Memorystore sert par défaut ; M6 passé trois fois sur trois |
| Redis 7.2.17, image officielle `redis:7.2.17-alpine` sur `local`, Memorystore for Redis sur `gcp` | 69 | écartée | Ligne restée sous BSD-3-Clause, mais l'éditeur a changé deux fois de licence après elle, pour 7.4 puis pour 8.x ; éditeur unique, chaque contribution sous accord de licence ; maturité ramenée de 5 à 4 par [SECU], selon la règle de BENCH-013 |

Sensibilité, reprise du rapport et corrigée de la maturité. L'écart vaut 17 points, et il faudrait six crans de 3 points contre Valkey pour l'inverser. L'empreinte, la portabilité, l'expérience dev, la sécurité et le coût ne départagent pas. Avec 0/5 en empreinte pour Valkey et 5/5 pour Redis, il reste 78 contre 71. Avec le miroir de l'ADR-011, les deux regagnent le même cran : 88 contre 71.

Candidats repérés et non retenus (BENCH-014, section 2) : KeyDB, sans release depuis le 2023-10-30 ; Dragonfly, sous une licence que l'OSI n'approuve pas ; Redict, archivé ; Garnet, sans variante de Memorystore ; Memcached, qui ne parle pas RESP ; Redis 8.12, que Memorystore ne sert pas.

Grille, mesures et sources : [BENCH-014](../benchmarks/BENCH-014-cache.md).

## Décision

Sur la cible `local`, le projet généré fait tourner Valkey 9.1.4, image `docker.io/valkey/valkey` en variante Alpine figée par condensat, dans un Deployment d'une réplique sans persistance de la couche `local`, en profil lite comme en standard. Sur la cible `gcp`, il s'appuie sur Memorystore for Valkey : mode sans cluster, zéro réplica, un nœud `shared-core-nano`, aucun engagement d'utilisation, authentification par jeton, chiffrement en transit dès la création. L'application lit le même Secret `cache-auth`, clé `password`, sur les deux cibles. Elle parle RESP et passe cette valeur à `AUTH` sans savoir ce qui sert le cache.

Le condensat retenu est celui de la mesure : `docker.io/valkey/valkey:9.1.4-alpine@sha256:56729e68bdda139cbd3f6a2538683dc3523325fc5711ea1a379938f1b37893f0`. C'est un condensat d'index (`tests/bench/bench-014-cache.sh`, ligne 101), le même que celui de BENCH-005. Docker Hub date le tag du 2026-11-18 à 23:11:58 UTC : le délai de 7 jours du principe VI s'achève le 2026-11-25 à 23:12 UTC (relecture [SECU], S59). La 9.1.4 corrige un avis publié, si bien que l'exception de sécurité la couvrirait de toute façon (condition 2).

Le DSI a pris les décisions de la section « Décisions du DSI », le 2026-11-25, par délégation de Lucas. La fusion de la PR de cet ADR vaut acceptation. Trois questions restent ouvertes, dont une action publique laissée à Lucas.

### Répartition par couche

| Couche | Contenu |
| --- | --- |
| commune | L'accès au cache de l'API : l'interface de T023 et le client concret de T080. Il lit `cache-auth`, clé `password`, par `secretKeyRef`, et l'hôte, le port et le mode TLS dans `app-config`. Aucun nom de Valkey ni de Memorystore, aucun hôte, aucun port propre à une cible (condition 17) |
| `local` | `local/data/cache/`, nom du plan : Deployment d'une réplique, conteneur d'initialisation qui écrit `cache.conf` (ACL, éviction, mémoire, persistance coupée), Service `ClusterIP`, NetworkPolicy. La tâche de `task up` qui crée `cache-auth`, et l'attente de « prêt ». Les valeurs de `app-config` qui désignent le Service, TLS coupé. La liste fermée de la dérogation, quand un profil embarque Kyverno |
| `gcp` | Dans la racine OpenTofu de l'ADR-008 : l'instance Memorystore for Valkey, la politique de connexion de service, le secret de Secret Manager qui reçoit le jeton (condition 18). Dans le composant de cible : la synchronisation de `cache-auth`, le ConfigMap de la CA, les valeurs de `app-config` qui désignent le point de terminaison, TLS actif. Rien de Valkey ne tourne dans le cluster GKE |

### Parité attendue avec Memorystore for Valkey

| Point | `local` | `gcp` | Écart au README |
| --- | --- | --- | --- |
| Moteur et ligne | Valkey 9.1.4, ligne 9.1 | Ligne 9.1 par défaut, correctif servi non publié (S18) | Le correctif |
| Authentification | Compte `default`, ACL qui porte l'empreinte SHA-256 du mot de passe de `cache-auth` (condition 4) | Compte `default`, `AUTH <jeton>`, jeton créé par le service, deux jetons au plus par utilisateur (S60) | Aucun : même `AUTH <valeur>` |
| Commandes | `-@admin` plus chaque commande que Memorystore bloque ; `@scripting` retiré si le client le permet | Liste bloquée de S62 ; `EVAL`, `FUNCTION` et `MONITOR` permis | Oui : `local` plus strict |
| Chiffrement en transit | Aucun : le trafic reste dans le nœud kind | TLS, `SERVER_AUTHENTICATION`, CA par ConfigMap (condition 7) | Oui |
| Éviction | `allkeys-lru` | `allkeys-lru` par `engine_configs` ; le défaut du service est `volatile-lru` (condition 15) | Aucun |
| Mémoire | `maxmemory 64mb`, limite du conteneur 128 Mi (condition 10) | Défaut du type de nœud : 1,12 Go inscriptibles sur `shared-core-nano` (S49) | Oui |
| Persistance | Aucune : `save ""`, `appendonly no` | `DISABLED`, sans sauvegarde automatique (condition 13) | Aucun |
| Réseau | Service `ClusterIP`, NetworkPolicy (condition 6) | Private Service Connect seulement, politique de connexion de service limitée au sous-réseau de GKE (S22, condition 7) | Sans objet |
| Disponibilité | Une réplique | Un nœud, zéro réplica, sans SLA (S49) | Aucun |

Le PC peut être plus strict que Memorystore, jamais moins ([SECU]). Une commande que le PC refuse et que GCP permet se voit dès le poste. L'inverse ne se verrait qu'au premier déploiement réel.

### Conditions

Les conditions 1 à 8 sont celles de [SECU], les conditions 9 à 15 celles de [FINOPS], retenues par le DSI le 2026-11-25 (BENCH-014, relectures). Les conditions 16 à 19 sont des ajouts de [ARCHI] : elles écrivent la condition 1 proposée par [BENCH] et trois décisions du DSI. Là où [ARCHI] complète une condition de relecture, le texte le dit. La décision ne vaut qu'avec elles. Chaque contrôle cité entre dans la matrice de validation (principe I) ; les identifiants sont ceux du plan, et [QA] attribue ceux qui manquent.

1. Image et dérogation à ENF-03. `docker.io/valkey/valkey`, variante Alpine, est désignée par tag et condensat et tirée depuis docker.io par zot. docker.io figure déjà dans la liste de la condition 10 de l'ADR-011, et Renovate le date (ADR-016). La dérogation datée de la section « Dérogations » admet l'image par sa référence exacte, condensat compris, dans une liste fermée. À chaque condensat neuf, [SECU] vérifie que docker.io, ghcr.io et public.ecr.aws donnent le même condensat d'index (S55). Les copies de ghcr.io et de public.ecr.aws ne servent qu'à cette comparaison : le nœud ne les tire jamais. Porteurs : [SECU] pour la liste et la comparaison, [OPS] pour Kyverno en phase 4. Contrôles : S01 ; E11 ; E25 ; dès qu'un profil embarque Kyverno, le contrôle de la condition 7 de l'ADR-012 étendu à `docker.io/valkey/valkey`.
2. Suivi des failles et version (R-36). Le scan de FR-021 ne voit que les paquets d'Alpine. Trivy 0.76.2 ne trouve aucun paquet `valkey` dans l'image, dont le moteur est compilé depuis l'archive des sources, et aucun des douze avis de Valkey et de Redis n'est dans la base mondiale de GitHub (S53, S54). R-36 s'étend donc à tout le moteur, pour Valkey comme pour toute image qui compile son moteur. [SECU] lit chaque mois les avis de `valkey-io/valkey` et les notes des releases marquées « SECURITY ». Renovate ne suit que les versions correctives de la ligne de la condition 16, en variante Alpine ; une version qui corrige un avis passe par l'exception du principe VI, matrice comprise. La 9.1.4 se fige après le 2026-11-25 à 23:12 UTC. Une seconde source fondée sur la CPE du SBOM embarqué, `/usr/local/valkey.spdx.json`, s'étudie à l'étape 18 du plan, avec sa limite écrite : NVD en retard, trois avis sans CVE (S57, S66). Porteurs : [SECU] ; [DEV] pour Renovate ; [SECU] et [OPS] pour l'étape 18. Contrôles : S23 étendu à `valkey/valkey`, une seule ligne et une seule variante ; E25 et E27.
3. Durcissement du pod sur `local`. Le namespace applique le profil `restricted`. Le pod a `runAsNonRoot`, l'UID 999 et le GID 1000 explicites, `allowPrivilegeEscalation: false`, les capacités `ALL` retirées, `seccompProfile: RuntimeDefault`, `readOnlyRootFilesystem: true` et `automountServiceAccountToken: false`. L'UID explicite est indispensable : l'image ne déclare aucun `USER`, et son entrypoint ne descend à l'utilisateur `valkey` que s'il démarre en root (S54, S57). Aucune persistance : `save ""` et `appendonly no`. `/data` est un `emptyDir` borné par `sizeLimit`. Demandes, limites et `maxmemory` suivent la condition 10. Porteurs : [DEV] et [OPS]. Contrôles : la matrice échoue sur un pod refusé par le profil ; S11 étendu à ces champs et au `sizeLimit`.
4. ACL à la place de `requirepass`. Le conteneur d'initialisation calcule l'empreinte SHA-256 du mot de passe depuis le fichier du Secret, par l'entrée standard. Il écrit dans `cache.conf` la ligne `user default on #<empreinte> ~* &* +@all -@admin`, suivie du refus explicite de chaque commande que Memorystore bloque et que `@admin` ne couvre pas, d'après la page relue et datée (S62). Le mot de passe en clair ne figure plus dans `cache.conf`. Seul le conteneur d'initialisation monte le Secret ; le serveur ne le monte pas. Ni `rename-command`, ni `requirepass`. `enable-protected-configs`, `enable-debug-command` et `enable-module-command` restent à `no`, leur défaut en 9.1.4 (S58). `@scripting` est retiré si le client .NET fonctionne sans, ce que [DEV] vérifie sur le golden repo ; sinon, transposition de [ARCHI], la PR de l'étape 19 dit pourquoi il reste, [SECU] la relit, et le README le liste. Porteurs : [DEV], relu par [SECU]. Contrôles : E13 étendu, où `PING` sans mot de passe reçoit `NOAUTH`, où `CONFIG GET`, `DEBUG`, `SAVE`, `ACL LIST` et `MODULE LIST` reçoivent un refus, et où `cache.conf` ne contient pas la valeur du Secret ; S11 refuse `requirepass` et `rename-command`.
5. Mot de passe hors des arguments et de l'environnement du serveur. Un contrôle statique du rendu refuse, sur le conteneur du cache, tout `env` et tout `envFrom`, dont `VALKEY_EXTRA_FLAGS`. L'entrypoint de l'image finit par `exec "$@" $VALKEY_EXTRA_FLAGS` : une variable posée sur le conteneur deviendrait un argument du serveur (S57). Le contrôle refuse aussi, dans `command` ou `args` de tout conteneur, toute option de mot de passe (`requirepass`, `-a`, `--pass`, `--user`). M6 entre dans la matrice, sa partie (c) étendue à `/proc/*/environ`. Le client lit le mot de passe par `secretKeyRef` ou par fichier, jamais en argument. Porteurs : [DEV] et [QA]. Contrôles : S11 étendu ; E13 étendu à M6.
6. Réseau sur `local`. Service `ClusterIP` seulement, sans `NodePort`, `LoadBalancer` ni route TCP. Une NetworkPolicy n'admet sur 6379 que les pods de l'API, et refuse toute sortie au pod du cache. Précision de [ARCHI] : la politique admet aussi le pod de sonde de `task up` et de la matrice (condition 17). kind applique les NetworkPolicy depuis sa v0.24.0 (S65) ; [OPS] vérifie qu'elles s'appliquent sous kind 0.33.0, comme pour la condition 4 de l'ADR-014. Porteur : [OPS]. Contrôles : un pod non admis n'atteint pas 6379, l'API l'atteint ; un contrôle statique sur le type du Service ; E03.
7. `gcp` : jeton, TLS, état. `authorization_mode = "TOKEN_AUTH"` et `transit_encryption_mode = "SERVER_AUTHENTICATION"` dès la création, puisque ce second attribut est immuable (S64 ; page relue par [ARCHI] le 2026-11-25). La CA arrive au pod par la couche de cible, sous la forme d'un ConfigMap, puisqu'elle n'a rien de secret ; [OPS] choisit entre CA par instance et CA régionale (S63). Le jeton vient de `google_memorystore_auth_token`, dans une version publiée du provider depuis 7 jours, dont [SECU] relit la page (condition 18). Il part vers Secret Manager par `secret_data_wo`, puis vers `cache-auth`, clé `password`, par la synchronisation de GKE (ADR-007). Aucun `output` ne le porte, et l'état comme le plan sont chiffrés (condition 2 de l'ADR-008). La rotation suit les deux jetons par utilisateur et s'écrit au README (S60). Une politique conftest refuse un autre mode d'autorisation, `TRANSIT_ENCRYPTION_DISABLED`, et toute règle d'`acl_policy` qui contient `>`, signe d'un mot de passe en clair dans le HCL. La politique de connexion de service n'admet que le sous-réseau de GKE, sur les seuls ports du mode sans cluster, que [OPS] lit (S22). L'authentification IAM passe par son propre ADR. Porteurs : [OPS], relu par [SECU]. Contrôles : S14 ; S15 étendu à ces règles ; S17.
8. Écarts et catalogue. Le README liste TLS sur `gcp` seulement, et l'ACL de `local` plus stricte que Memorystore (ENF-02). L'entrée du catalogue porte BSD-3-Clause, gouvernance `foundation` (LF Projects), statut actif, date et sources (section « Entrée au catalogue »). Toute autre image ou tout module, `valkey-bundle` compris, passe par une relecture [SECU] avant d'entrer. Porteurs : [DOC] pour le README, le DSI pour l'entrée, [SECU] pour les relectures. Contrôles : S18 ; le contrôle du catalogue dans la PR de schéma de la phase 3.
9. Volume, de [FINOPS]. L'image reste la variante Alpine de `valkey/valkey`, figée par condensat. Le cache n'ajoute rien au premier `task up` : la stack de BENCH-005, déjà comptée dans R-04, contenait cette image, 18,8 Mo en amd64. Le premier `task up` reste à 1 802,1 Mo en profil standard, 160,2 % du budget de 900 s à 10 Mbit/s, et à environ 1 263,8 Mo en profil lite avec zot, 112,3 %. La variante `trixie` ajouterait 26,0 Mo et rouvrirait R-04 avec un nouveau chiffre. Porteurs : [FINOPS] et [OPS]. Contrôles : D02 ; la règle de Renovate de la condition 2 ne propose que la variante Alpine (S23).
10. Demandes et limites du pod sur `local`, de [FINOPS]. Explicites dans le manifest : 64 Mi de mémoire demandés et 128 Mi en limite, 25m de CPU demandés, sans limite de CPU. `maxmemory 64mb` et `maxmemory-policy allkeys-lru` figurent dans la configuration écrite par le conteneur d'initialisation. Sans `maxmemory`, Valkey n'a aucune limite sur 64 bits (S51), et le pod grossirait jusqu'à sa limite de conteneur. Le pod reste en classe Burstable (S52). Ce sont des valeurs de départ, à confirmer sur le golden repo. Porteurs : [DEV] et [FINOPS]. Contrôles : un contrôle statique sur la présence des demandes, des limites et de `maxmemory` ; dans la matrice, une écriture au-delà de `maxmemory`, avec zéro redémarrage et un working set sous la limite.
11. Plancher mémoire, de [FINOPS]. La couche entre dans les planchers pour la plus grande de ses deux valeurs : 56,3 Mio au nœud, majorant 70,6, et non les 6,4 Mio du pod. Le lite reste à 2,0 Gio de VM et 6,0 Gio de portable, avec 108 à 122 Mio de marge avant le palier suivant. Le standard reste à 3,5 Gio de VM et 7,5 Gio de portable, avec 8 à 23 Mio de marge avant le palier de 4,0 Gio, qui tient encore sur 8 Gio. Le golden repo mesure le nœud avec toute la stack et remplace ces ordres de grandeur. Porteurs : [FINOPS] ; [DEV] pour T081. Contrôles : P03 au seuil recalculé ; D03.
12. Cause des 50,4 Mio, de [FINOPS]. Le nœud avec Valkey pèse 50,4 Mio de plus que le nœud avec Redis, dont 49,9 hors du pod, sans cause établie. Avant que le plancher s'écrive dans le PRD, [BENCH] lance une série courte : `memory.stat` du nœud et RSS par processus à chaque échantillon, témoins sans serveur pour les deux images, ordre permuté, cinq exécutions au moins par option, échantillons du nœud écrits en TSV. Si l'écart est dans le cache de pages, le plancher peut redescendre vers la valeur du pod. Porteurs : [BENCH] et [FINOPS]. Contrôle : aucun dans la matrice, puisque c'est une mesure ; son résultat remplace les valeurs de la condition 11 dans P03 et D03.
13. Taille de l'instance sur `gcp`, de [FINOPS]. Mode `CLUSTER_DISABLED`, zéro réplica, un nœud, `shared-core-nano` en développement et pour la démo ; `custom-pico` seulement avec un besoin de SLA. Tout autre type, tout réplica et tout mode cluster exigent un budget revalidé (principe X). Aucun engagement d'utilisation : ils se paient chaque heure et ne s'annulent pas (S48). La politique conftest de l'ADR-008 sur le tier s'étend au type de nœud, au mode et au nombre de réplicas. Ajout de [ARCHI] : `persistence_config` s'écrit en `DISABLED`, sans `automated_backup_config`, comme sur `local`. La persistance est hors du besoin (research RS-11), et le coût des sauvegardes n'est pas lu. Porteurs : [FINOPS] et [OPS]. Contrôle : S15 étendu, qui refuse un plan hors de ces valeurs.
14. Budget avant la GATE 2 (principe X, R-05), de [FINOPS]. Lucas lit la grille de Memorystore for Valkey pour la région choisie : le 2026-11-25, l'outil n'y a trouvé que le titre de la page (S50). [FINOPS] calcule alors les nœuds facturables, fois les heures allumées, fois le prix horaire du type de nœud. S'y ajoutent les postes non lus : le point de terminaison Private Service Connect, son trafic, et les sauvegardes, nulles sous la condition 13. Aucun `tofu apply` avant l'accord de Lucas sur ce montant. Les ressources portent les étiquettes `owner`, `env` et `ttl`. Porteurs : Lucas et [FINOPS]. Contrôles : S17 ; la règle conftest des étiquettes de R-05, dans S15.
15. Parité d'éviction, de [FINOPS]. La politique d'éviction par défaut de Memorystore for Valkey est `volatile-lru`, et `maxmemory-policy` se règle à la création ou à la mise à jour de l'instance (page des configurations, lue par [ARCHI] le 2026-11-25). Choix de [ARCHI] : `allkeys-lru` sur les deux cibles, plutôt que le défaut de Google. `volatile-lru` n'évince que les clés qui ont une durée de vie, et se comporte comme `noeviction` quand aucune ne l'a ; `allkeys-lru` ne dépend pas de ce que l'application pose, et Valkey le conseille quand on hésite (S51, relue le 2026-11-25). Sur `gcp`, l'instance le reçoit par `engine_configs`, attribut de `google_memorystore_instance` en 8.12.0 (page relue le 2026-11-25). `maxmemory` garde sur `gcp` le défaut du type de nœud, que Google déconseille de dépasser (S49), et vaut `64mb` sur `local` : l'écart se liste au README. Porteurs : [OPS] et [DEV]. Contrôles : un contrôle statique lit `maxmemory-policy` dans la configuration du conteneur d'initialisation et dans `engine_configs` ; S15 refuse une autre valeur.
16. Ligne commune, ajout de [ARCHI], qui reprend la condition 1 proposée par [BENCH] et la décision 1 du DSI. La ligne de Valkey est celle que Memorystore for Valkey sert par défaut, 9.1 au 2026-11-23 (S18). Elle se relève à chaque release du blueprint et tient en une seule valeur pour les deux couches, comme la majeure de Postgres (condition 5 de l'ADR-012) : `local` en tire le tag de l'image, `gcp` l'attribut `engine_version`. La valeur de cet attribut pour la ligne 9.1 n'a pas été lue ; l'exemple du provider écrit `VALKEY_7_2` ([OPS]). La 9.2.0, sortie le 2026-11-19, n'entre pas tant que Memorystore ne la sert pas par défaut. Un écart de correctif est admis et listé au README, Google ne publiant pas le correctif servi (S18). Porteurs : [OPS] et [DEV]. Contrôles : S21 étendu à la ligne du cache ; la matrice compare `valkey_version` de `INFO server` (M8) à la valeur ; sur `gcp`, le contrôle reste statique jusqu'au premier apply autorisé, où `INFO server` se lit (GATE 2). Que l'ACL de la condition 4 laisse passer `INFO` se vérifie sur le golden repo ([DEV]).
17. Client unique et couche commune neutre, ajout de [ARCHI]. Ni la couche commune ni le code commun ne nomment Valkey, Memorystore, leurs hôtes ou leurs ports. L'API a un seul chemin de connexion : l'hôte, le port, le mode TLS et la référence de la CA viennent de `app-config` et de la couche de cible, le mot de passe de `cache-auth`. Aucun code propre à `gcp`, ce qui tient l'IAM hors du MVP (décision 2 du DSI). « Prêt » veut dire un `PING` authentifié qui reçoit `PONG` par le Service, comme dans BENCH-014, et non un pod `Ready` : l'attente de `task up` et le contrôle de démarrage passent par lui, et `/api/readyz` interroge le cache (T080). Porteur : [DEV]. Contrôles : S06 et S07 ; U01 ; E13.
18. Producteur de `cache-auth` sur `gcp`, écart pour l'étape 20, ajout de [ARCHI] qui écrit la décision 2 du DSI. La ressource `google_memorystore_auth_token`, fusionnée le 2026-11-18, n'est publiée dans aucune version du provider le 2026-11-25. 8.12.0, du 2026-11-17, reste la dernière, et ses notes de version ne la citent pas (S28, S64 ; page des releases relue par [ARCHI] le 2026-11-25). L'étape 20 avance sans elle : l'instance, la politique de connexion de service, les politiques conftest et l'`app-config` de GCP. Le producteur de `cache-auth`, le secret de Secret Manager qui reçoit le jeton et l'extension de S07 à `cache-auth` sur `gcp` attendent trois choses : la publication de la ressource, 7 jours de plus (principe VI), et la relecture de sa page par [SECU]. Aucun contournement : ni jeton recopié à la main, ni `gcloud` dans un script, ni `output`. D'ici là, la ligne `gcp` de l'entrée garde ce point en `pending`, et aucun blueprint ne s'en sert (principe IV). Porteurs : [OPS] et [SECU] ; le DSI inscrit l'écart dans `tasks.md`. Contrôles : S15 refuse un `output` qui porte le jeton ; S07 sur `cache-auth`, à la levée.
19. Valeurs connues, ajout de [ARCHI] qui écrit la décision 5 du DSI (R-20). `foobared`, l'exemple de `requirepass` dans `valkey.conf` (S58), et `password123`, l'exemple de règle de `google_memorystore_acl_policy` (S64), entrent dans la liste des valeurs connues de la condition 1 de l'ADR-007. Les deux tombent déjà sous la règle des 32 caractères. Porteurs : [SECU] et [DEV]. Contrôles : E04 ; E05 étendu à `cache-auth`.

Les conditions des ADR-004 à ADR-014 restent en vigueur, en particulier les images par condensat (condition 3 de l'ADR-004), l'absence de Secret sous `k8s/` (condition 1 de l'ADR-006), la création des Secrets par un tube et la parité de leur nom et de leurs clés (conditions 1 et 5 de l'ADR-007), l'état chiffré (condition 2 de l'ADR-008), la liste unique des registres (condition 10 de l'ADR-011) et le profil `restricted` du namespace de l'application (conditions 1 et 9 de l'ADR-012).

### Mémoire et volume

[FINOPS] compte le profil lite sans Flux. [ARCHI] confirme cette lecture : les réponses de la GATE 1 à l'ADR-010 sortent Flux du profil lite. Le cache pèse 18,8 Mo dans le premier `task up`, 15,1 s à 10 Mbit/s, 1,7 % du budget : même sans cache, le lite resterait à 110,7 %. Le choix du moteur ne peut donc ni faire tenir le critère des 15 minutes, ni le faire manquer (R-04).

En mémoire, Valkey figurait déjà dans les planchers des ADR-012 à ADR-014, sans part isolée. [FINOPS] ajoute la couche par majorant, sans rien retirer : les chiffres de la condition 11 comptent donc le cache deux fois, et mêlent des séries de jours différents. Ce sont des ordres de grandeur, que D02 et D03 remplaceront sur le golden repo.

### Ce que l'ADR change ailleurs

Aucun de ces fichiers n'est modifié par cet ADR. Chaque changement passe par sa PR, chez son porteur.

- Étape 19 du plan, pour [DEV] : débloquée. T075 trouve ici l'image, la forme, la persistance, le registre et les clés de `cache-auth` ; il reste à lire et dater le client .NET (version, licence, date) et à vérifier qu'il fonctionne sous l'ACL. T076 : S11 couvre aussi `env`, `envFrom`, `VALKEY_EXTRA_FLAGS` et les options de mot de passe (conditions 3 à 5). T077 : E13 reçoit les contrôles des conditions 4, 5, 6, 10 et 17. T078 : `cache-auth`, clé `password`. T079 : aucun registre à ajouter au miroir, docker.io y est déjà ; le Secret n'est monté que dans le conteneur d'initialisation. T080 : client unique, TLS par configuration (condition 17). T081 : seuil recalculé sur la condition 11. La PR qui fige l'image passe après le 2026-11-25 à 23:12 UTC, ou sous l'exception de sécurité.
- Étape 20 du plan, pour [DEV] et [OPS]. T136 trouve ici la variante et l'authentification. T137 écrit les politiques des conditions 7, 13 et 15. T138 écrit l'instance et la politique de connexion de service, sans le producteur de `cache-auth` ni l'extension de S07 à `cache-auth` (condition 18) : l'écart s'inscrit dans `tasks.md`, et l'étape ne se ferme qu'à sa levée. L'accès privé aux services de l'étape 13 reste, pour Cloud SQL.
- Spec 001, pour [PO] puis Lucas. `spec.md` ne change pas : FR-001 et FR-009 tiennent, et l'hypothèse « un cache Valkey » peut renvoyer à cet ADR. `contracts/secrets.md` : la clé `password` de `cache-auth` devient définitive, et le producteur `gcp` est le jeton de Memorystore, par Secret Manager et la synchronisation de GKE, en attente de la condition 18. `research.md`, RS-11 : ce que consignent T075 et T136. `data-model.md` : les paliers de la condition 11. `plan.md`, matrice : S11, S15, S21, S23, E04 et E13 étendus comme le disent les conditions.
- Catalogue, pour la PR de schéma de la phase 3 : l'entrée du cache (section « Entrée au catalogue »). Aucun ajout au schéma : `resp`, `foundation` et `BSD-3-Clause` y sont déjà.
- Registre des risques, pour le DSI. R-04 reçoit le chiffre du lite, 1 263,8 Mo avec zot, 112,3 % du budget, et le plancher de la condition 11 ; le standard reste à 1 802,1 Mo. R-05 reçoit la facturation de Memorystore for Valkey, par nœud et par heure, et ses postes non lus. R-20 reçoit `foobared` et `password123`. R-25 note les deux événements `Pulled` par création pour la même image, que zot rend sans objet après le premier `task up`. R-36 s'étend au moteur entier, Valkey compris, et sa mitigation cite la CPE du SBOM pour l'étape 18. [ARCHI] propose au DSI de juger s'il ouvre un risque pour l'attente de la ressource du provider avant la GATE 2 (question 3).
- ADR-007, pour [SECU] et [DEV]. Il n'est pas remplacé. La liste des valeurs connues reçoit deux entrées (condition 19). `cache-auth` garde le même nom et la même clé sur les deux cibles, et sa condition 5 reste tenue.
- ADR-008, pour [OPS]. Il n'est pas remplacé. Sa portée citait Memorystore for Redis en tier basique, dans le socle de BENCH-008 : le golden repo écrit Memorystore for Valkey à la place, par Private Service Connect. Sa condition 6 sur le tier devient : mode, type de nœud, réplicas, mode d'autorisation, chiffrement en transit, persistance et éviction écrits (conditions 7, 13 et 15). Sa conséquence négative sur la chaîne AUTH dans l'état vaut pour le jeton, tant que l'IAM n'est pas en place.
- ADR-011. Il n'est pas remplacé. Sa ligne docker.io porte déjà Valkey 9.1.4, servie par zot au test T2 trois fois sur trois. Aucun amont ne s'ajoute.
- ADR-012. Il n'est pas remplacé. Sa dérogation reste limitée à `docker.io/library/`, et le contrôle de sa condition 7 s'étend à `docker.io/valkey/valkey`.
- PRD, pour [PO] : la dérogation à ENF-03 citée sous l'exigence, avec celles des ADR-012 à ADR-014 ; le chiffre du lite sous ENF-01.
- README du projet généré, pour [DOC] : TLS sur `gcp` seulement ; l'ACL de `local` plus stricte ; `maxmemory` différent ; les données du cache perdues au redémarrage du pod ; la rotation du jeton ; l'écart de correctif.

### Portée

La spec déclare la brique du cache, de valeur `redis` (principe II, ADR-001). Elle ne nomme ni Valkey, ni l'image, ni Memorystore, qui vivent dans les couches de cible et au catalogue. La décision couvre la cible `local`, profils lite et standard, une réplique, et la cible `gcp`, une instance sans cluster.

Restent hors de cette décision :

- l'authentification IAM de Memorystore, qui passe par son propre ADR ;
- la persistance, la haute disponibilité et le mode cluster, sur les deux cibles ;
- le client .NET, sa version et son code, que [DEV] choisit à T075 sous les conditions 4, 5 et 17 ;
- le montant du budget sur `gcp` (condition 14) ;
- les modules de Valkey et l'image `valkey-bundle` (condition 8) ;
- l'on-prem serveurs et Windows (Q5).

## Conséquences

### Positives

- Licence BSD-3-Clause pour le moteur et l'image. Projet de LF Projects : neuf mainteneurs chez huit organisations, aucune au-delà d'un tiers du comité, 184 auteurs en douze mois.
- Même moteur et même ligne sur les deux cibles, tenus par une seule valeur (condition 16) ; même contrat `cache-auth` ; même forme `AUTH <valeur>`. L'application ne sait pas ce qui sert le cache.
- Rien de plus au premier `task up` : l'image, 18,8 Mo en amd64, était déjà comptée dans R-04. Aucun registre de plus pour le miroir, et l'image est déjà servie par zot au test T2.
- Prête en 5,5 s de médiane (M1), de retour en 2,2 s après la suppression du pod (M7), pod de 6,4 Mio au repos, mot de passe imposé et absent des lignes de commande trois fois sur trois (M6).
- Le mot de passe local ne figure plus en clair dans `cache.conf`, et le serveur ne monte plus le Secret (condition 4).
- Sur `gcp`, la plus petite instance, sans engagement ; aucun mot de passe dans le HCL ; TLS imposé dès la création.
- Un service managé dont le moteur est porté par une fondation, ce que préfère la lecture du principe V de l'ADR-009.

### Négatives

- ENF-03 n'est pas tenu : aucune signature ni attestation, d'où une dérogation de plus. Chaque condensat neuf refait confiance à Docker Hub, ce que tempère la comparaison des trois registres sans prouver l'auteur.
- R-36 : Trivy ne voit pas le moteur. Valkey a publié neuf avis en douze mois, dont huit élevés ; tous ceux de la ligne 9.1 demandent un client authentifié (S53). Seule la lecture mensuelle de [SECU] les couvre.
- `valkey-container` ne republie `9.1.4-alpine` qu'à une release de Valkey ou à la main, et `FROM alpine:3.24` n'a pas de condensat (S57). Les correctifs d'Alpine attendent : 16 constats faibles et moyens sur OpenSSL et zlib, déjà corrigés par Alpine (S54).
- Le jeton est une valeur statique, dans l'état OpenTofu protégé par son seul chiffrement, puis dans Secret Manager. L'IAM l'éviterait, au prix de code propre à `gcp`.
- Le producteur de `cache-auth` sur `gcp` dépend d'une ressource du provider non publiée : l'étape 20 ne se ferme pas avant (condition 18).
- La couche `gcp` ajoute Private Service Connect au socle de l'ADR-008 ; les ports utiles en mode sans cluster et le coût du point de terminaison ne sont pas lus.
- TLS ne joue que sur `gcp` : un défaut du client sous TLS ou de la CA ne se voit qu'au premier déploiement réel, comme le parcours de connexion de R-37.
- Mémoire : 56,3 Mio au nœud sans cause établie (condition 12), et un profil standard à 8 à 23 Mio du palier de 4,0 Gio.
- Prix de Memorystore for Valkey non lus (R-05).
- Mesures d'un seul poste, arm64 sous OrbStack, moteur non libre (R-26). Restent non mesurés : la NetworkPolicy, l'ACL avec le client .NET, le pod sous ses limites et plein, TLS avec la CA, le démarrage sur amd64.

### Effet sur les cibles hors MVP

La porte reste ouverte. Valkey tourne sur tout cluster conforme, et RESP reste le standard que l'entrée note. Une cible AWS ou Azure recevrait une ligne de plus dans l'entrée, avec le service managé de son fournisseur, ce que cet ADR n'a pas vérifié. La valeur unique de la ligne suivrait la logique de l'ADR-012 : le jour où deux clouds coexisteront, la ligne commune demandera un nouvel ADR. Une cible on-prem serveurs aurait son propre benchmark, où pèseraient la persistance et la haute disponibilité.

### Suites

- [DEV] et [OPS], étape 19 : la couche cache sous les conditions 1 à 6, 9 à 11, 16, 17 et 19 ; le client .NET et `@scripting` ; `INFO` sous l'ACL ; la NetworkPolicy sous kind.
- [OPS], étape 20 : l'instance sous les conditions 7, 13, 15 et 16 ; la valeur d'`engine_version` ; les ports de Private Service Connect ; la CA ; le producteur à la levée de la condition 18.
- [SECU] : la liste fermée et la comparaison des trois registres à chaque condensat ; la lecture mensuelle des avis ; la page de la ressource du jeton à sa publication ; l'application de `google_memorystore_acl_policy` en `TOKEN_AUTH`, non vérifiée ; la seconde source de l'étape 18.
- [QA] : les identifiants des contrôles.
- [BENCH] et [FINOPS] : la série de la condition 12 ; le budget de la condition 14 avant la GATE 2.
- [PO] : le PRD et la spec 001.
- [DOC] : les lignes du README.
- DSI : R-04, R-05, R-20, R-25, R-36 ; l'écart de l'étape 20 dans `tasks.md` ; le suivi de la levée de la dérogation ; l'entrée du catalogue dans la PR de la phase 3.

### Questions ouvertes

1. Ticket amont chez `valkey-io/valkey-container`, pour Lucas (décision 7 du DSI). Le workflow de publication a déjà la permission `id-token: write` pour AWS (S57) : une signature sans clé ou une attestation de provenance lui coûterait peu, et lèverait la dérogation. Ouvrir le ticket est une action publique, que le DSI laisse à Lucas. Avis de [ARCHI] : l'ouvrir, en citant l'absence de signature et d'attestation relevée par [SECU]. Rien dans cet ADR n'en dépend.
2. Attente de la ressource du provider, pour Lucas et le DSI. Si `google_memorystore_auth_token` n'est pas publiée, plus 7 jours, avant la GATE 2, le producteur `gcp` de `cache-auth` manque au premier apply. Deux voies : déployer d'abord sans la partie cache, l'API n'étant pas prête, ou ouvrir plus tôt l'ADR de l'IAM. Avis de [ARCHI] : attendre, et reposer la question à l'ouverture de la GATE 2 ; l'IAM ajoute du code propre à `gcp` dans l'API (condition 17).

### Décisions du DSI (2026-11-25)

Lucas a délégué au DSI les choix à faire pendant son absence. Le DSI a pris le 2026-11-25 ces décisions, que cet ADR écrit comme telles :

1. Valkey 9.1.4 sur `local`, 86 contre 69 pour Redis 7.2.17 ; la version locale suit la ligne que Memorystore sert par défaut (condition 16). Memorystore for Valkey sur `gcp` (principe III), mode sans cluster, zéro réplica, `shared-core-nano`, aucun engagement ; les prix, non lus, sont lus par Lucas avant la GATE 2 (conditions 13 et 14).
2. Authentification de Memorystore par jeton pour le MVP, l'IAM en évolution, puisqu'elle demanderait du code propre à `gcp` dans l'API. Le jeton passe par l'état OpenTofu chiffré. TLS activé à la création, le réglage étant immuable. Le Secret `cache-auth` sur `gcp` reste bloqué jusqu'à la publication de la ressource du provider (conditions 7, 17 et 18).
3. Dérogation datée à ENF-03 pour `valkey/valkey`, sur le modèle de l'ADR-014 : levée quand l'amont signe ses images, relecture au plus tard le 2027-05-23 et à chaque nouveau condensat, et comparaison du condensat sur docker.io, ghcr.io et public.ecr.aws à chaque montée (condition 1, section « Dérogations »).
4. Sur `local` : ACL qui stocke l'empreinte du mot de passe et refuse au moins les commandes que Memorystore bloque ; NetworkPolicy ; refus statique de `VALKEY_EXTRA_FLAGS` ; dimensionnement de [FINOPS] ; persistance coupée selon [SECU] et [FINOPS] (conditions 3 à 6 et 10).
5. `foobared` et `password123` entrent dans la liste des valeurs connues de la condition 1 de l'ADR-007 (condition 19).
6. Trivy ne voit pas le moteur dans les images ; la lecture mensuelle des avis par [SECU] couvre Valkey (condition 2, R-36).
7. Le ticket qui demande la signature chez `valkey-container` n'est pas ouvert : action publique, laissée à Lucas (question 1).
8. Lecture d'une couche dans le bruit, question ouverte depuis BENCH-013 : le majorant compte pour la note et le plancher, la valeur du pod pour le dimensionnement (arbitrage de BENCH-014). La condition 11 applique ce majorant.
9. Choix d'[ARCHI] confirmés par le DSI : éviction `allkeys-lru` sur les deux cibles, posée sur `gcp` par `engine_configs` plutôt que le défaut `volatile-lru` de Google (condition 15) ; persistance coupée sur `gcp` aussi, sans sauvegarde automatique (condition 13) ; la brique s'appelle `cache` dans la spec abstraite, de valeur `redis` comme le disent le README du catalogue et BENCH-014, le nom du fichier du catalogue se fixant en phase 3.
10. Le producteur de `cache-auth` sur `gcp` dépend d'une ressource du provider sans date de publication : risque R-41 ouvert au registre.

## Conformité à la constitution

Vérifiée contre la [constitution](../../.specify/memory/constitution.md) en version 1.2.0.

| Principe | Effet | Justification |
| --- | --- | --- |
| I. Rien sans test automatique | respecté | La matrice porte les contrôles des conditions 1 à 19 ; ce qui ne se vérifie qu'au premier apply, `INFO server` et TLS sur `gcp`, attend la GATE 2 et l'accord de Lucas |
| II. Spec abstraite, catalogue concret | respecté | La spec déclare la brique de valeur `redis` ; Valkey vit dans la couche `local`, Memorystore dans la couche `gcp`, et la couche commune ne nomme ni l'un ni l'autre (condition 17) |
| III. Managé sur le cloud, open source ailleurs | respecté | Sur `local`, Valkey sous BSD-3-Clause, gratuit ; sur `gcp`, Memorystore for Valkey, service managé de Google |
| IV. Catalogue traçable | respecté sous réserve | L'entrée porte licence, gouvernance, statut, dates et sources ; sa ligne `gcp` garde des `pending`, dont le producteur du jeton (condition 18), et aucun blueprint ne s'en sert d'ici là. Le golden repo n'est pas un blueprint |
| V. Gouvernance ouverte d'abord | respecté | Valkey est un projet de LF Projects, multi-organisations ; entre les deux variantes managées, l'ADR-009 préfère celle dont le moteur est porté par une fondation. Memorystore, imposé par III, ne demande pas de justification |
| VI. Récent mais éprouvé | respecté | Aucun critère éliminatoire : BSD-3-Clause, dépôt actif, 9.1.4 du 2026-11-18, ligne maintenue jusqu'au 2029-05-19. Servi en GA par Memorystore depuis le 2025-04-02. Tag figé après 7 jours, ou sous l'exception de sécurité ; ressource du provider retenue 7 jours après sa publication |
| VII. Une commande pour démarrer | respecté | `task up` crée `cache-auth`, applique la couche et attend un `PING` authentifié, sans prérequis nouveau |
| VIII. Aucun fait de mémoire | respecté | Les faits renvoient à BENCH-014, à ses relectures, à son script et aux pages relues par [ARCHI] le 2026-11-25. Sont signalés comme non vérifiés : le client .NET sous l'ACL, sans `@scripting` et sous TLS ; `INFO` sous l'ACL ; la valeur d'`engine_version` pour la ligne 9.1 ; les ports de Private Service Connect en mode sans cluster ; `google_memorystore_acl_policy` en `TOKEN_AUTH` ; la NetworkPolicy sous kind 0.33.0 ; la cause des 50,4 Mio ; les prix ; ce que containerd garde sur disque de l'environnement d'un conteneur ; la lecture du SBOM embarqué par Syft ou Dependency-Track |
| IX. Aucun secret dans le dépôt | respecté | Aucun objet `Secret` versionné ; `cache-auth` naît par un tube sur `local` ; `cache.conf` ne porte que l'empreinte ; le jeton ne passe par aucun `output` ni aucun HCL en clair ; `foobared` et `password123` sont refusés |
| X. Aucune dépense cloud sans accord | respecté | Rien n'est créé sur GCP ; l'instance attend la grille lue par Lucas, le budget de [FINOPS] et l'accord de Lucas (condition 14) |

### Dérogations

Une dérogation, décidée par le DSI le 2026-11-25 par délégation de Lucas, sur le modèle de celle de l'ADR-014. Elle ne vise aucun principe de la constitution : ENF-03 est une exigence du PRD. Elle s'écrit ici parce que la section « Gouvernance » de la constitution veut qu'une dérogation se justifie dans un ADR, avec sa durée et la condition qui la lèvera, et parce que les dérogations des ADR-012 à ADR-014 ne couvrent pas `docker.io/valkey/valkey`.

| Principe | Écart | Justification | Durée | Condition de levée |
| --- | --- | --- | --- | --- |
| Aucun : exigence ENF-03 du PRD, « Kyverno refuse les images non signées » | L'image `docker.io/valkey/valkey` n'a aucune signature vérifiable. Kyverno l'admet par sa référence exacte, condensat compris, inscrite dans une liste fermée | FR-008 reste tenu : le condensat fige le contenu, que containerd vérifie. Le workflow de `valkey-container` construit avec `provenance: false` et ne signe pas ; l'index n'a aucun manifeste d'attestation, docker.io et ghcr.io n'ont aucun tag de signature, et l'API d'attestations de GitHub répond 404 (S55 à S57). Le même condensat est publié sur trois registres par trois identifiants distincts, ce qui permet un contrôle croisé. Une image reconstruite et signée par CELIAN placerait CELIAN dans la chaîne de chaque projet généré (ENF-07). Docker Hardened Images reste écartée pour le compte Docker qu'elle exige (ADR-012). [SECU] recommande cette voie | Depuis le 2026-11-25, jusqu'à sa levée. Relecture au plus tard le 2027-05-23, date de la prochaine vérification de BENCH-014, et par [SECU] à chaque condensat neuf, avec la comparaison des trois registres | Valkey publie pour cette image une signature, ou une attestation signée, que Kyverno sait vérifier : la politique la vérifie alors, et la liste fermée disparaît pour cette image |

Portée. La seule image `docker.io/valkey/valkey`, en variante Alpine. Ni les copies de ghcr.io et de public.ecr.aws, ni `valkey/valkey-bundle`, ni un autre dépôt de docker.io hors de `library/`. Une autre image sans signature entre par son propre ADR.

Tenue de la liste. Elle naît avec le premier profil qui embarque Kyverno, en phase 4 ; d'ici là, la dérogation n'a pas d'effet. Elle change dans la même PR que le manifest qui change l'image, PR de Renovate comprise. [SECU] relit chaque condensat neuf et compare les trois registres : un condensat présent sur Docker Hub seul trahirait une publication hors du workflow, par un jeton volé par exemple. Le contrôle de la condition 1 refuse tout écart entre la liste et les images en marche. Le DSI suit la levée au registre des risques.

## Entrée au catalogue

Brique abstraite : `cache`, déclarée par la spec (`declared_by: spec`), de valeur `redis`, le type Score (ADR-001, condition 2). BENCH-014, la relecture [SECU] et `catalog/README.md` la nomment `redis` : le nom du fichier se fixe en phase 3 avec le schéma de spec, comme celui de `database` (ADR-012). L'entrée s'écrit au format de l'[ADR-009](ADR-009-catalogue.md), dans la PR de schéma de la phase 3 ; cet ADR ne crée pas le fichier.

| Cible | Service | Type | Licence | Gouvernance | Statut | Vérifié le | Source |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `local` | Valkey, image `docker.io/valkey/valkey` dans un Deployment de la couche `local` | `oss` | BSD-3-Clause | Fondation : LF Projects, « backed by the Linux Foundation » ; neuf mainteneurs chez huit organisations | actif | 2026-11-25 | <https://github.com/valkey-io/valkey>, <https://valkey.io/topics/releases/> |
| `gcp` | Memorystore for Valkey | `managed` | service propriétaire du fournisseur | Éditeur unique : Google | actif | 2026-11-25 | <https://docs.cloud.google.com/memorystore/docs/valkey/supported-versions> |

Ce que porte la ligne `local`, d'après BENCH-014 et ses relectures :

| Champ | Valeur |
| --- | --- |
| `service` | Valkey, image `docker.io/valkey/valkey` dans un Deployment de la couche `local` |
| `version` | 9.1.4 |
| `license` | `BSD-3-Clause`, présent dans `scripts/catalog/accepted-licenses.yaml`, approuvée par l'OSI (S17) ; image sous BSD-3-Clause (S7, S67). L'image embarque des paquets d'Alpine sous leurs propres licences, sans AGPL (S54), et CELIAN n'en redistribue rien (condition 9 de l'ADR-011) |
| `governance` | `foundation` ; `body` : `LF Projects` ; neuf mainteneurs chez huit organisations, une organisation au plus pour un tiers du comité (S4, S67) ; image tenue par le projet, dépôt `valkey-io/valkey-container` |
| `status` | `active` : dépôt non archivé ; ligne 9.1 maintenue jusqu'au 2029-05-19, correctifs de sécurité jusqu'au 2031-05-19 (S1, S3) |
| `last_release_on` | 2026-11-19, Valkey 9.2.0, dernière release amont ; la version servie, 9.1.4, date du 2026-11-18 (S2) |
| `verified_on` | 2026-11-25, le `read_on` le plus récent : S67, relue ce jour par [SECU] |
| `standards` | `resp`, déjà dans la liste fermée |
| `sources` | S1 à S4, S6, S7 et S67 de BENCH-014, avec leurs URL et leurs dates |
| `decisions` | ADR-015, BENCH-014 |
| `pending` | client .NET sous l'ACL et sans `@scripting` ([DEV]) ; NetworkPolicy sous kind ([OPS]) ; demandes et limites mesurées ([DEV], [FINOPS]) ; cause des 50,4 Mio ([BENCH], condition 12) |

La ligne `gcp` est de type `managed`, `provider: google`, gouvernance `single-vendor` Google, `version` 9.1, la ligne de la valeur unique (condition 16), standard `resp`. Ses décisions sont ADR-008 et ADR-015, avec BENCH-014. Elle n'a pas de `managed_gap`. Ses sources sont S18, lue le 2026-11-23, S22, S49 et S60 à S63, lues le 2026-11-25, et la page des configurations de Memorystore, lue par [ARCHI] le 2026-11-25. Ses `pending` : le producteur du jeton (condition 18, [OPS] et [SECU]) ; la valeur d'`engine_version` et les ports de Private Service Connect ([OPS]) ; `google_memorystore_acl_policy` en `TOKEN_AUTH` ([SECU]) ; le client .NET sous TLS ([DEV]) ; le prix (R-05, Lucas et [FINOPS]).

Le condensat de l'image reste dans le blueprint, que Renovate met à jour, comme le veut l'ADR-009. Le contrôle du catalogue en tirerait ces échéances pour la ligne `local` : le critère des 12 mois tombe le 2027-11-19 sans nouvelle release ; les sources lues le 2026-11-23 expirent le 2027-05-23, date que BENCH-014 propose pour sa prochaine vérification, et `verified_on` le 2027-05-25.

## Condition de révision

Bascule par un nouvel ADR qui remplace celui-ci dans ces cas :

- Valkey touche un critère éliminatoire : dépôt archivé ou en maintenance, licence qui n'est plus open source, ou aucune release pendant 12 mois, décompte parti du 2026-11-19 ;
- Valkey quitte LF Projects, ou son comité passe sous une seule organisation ;
- Google retire Memorystore for Valkey ou annonce sa fin.

La décision se rouvre, sans basculer d'office, dans ces cas :

- la ressource du jeton n'arrive pas avant la GATE 2, ou ne produit pas un jeton utilisable (question 2) : l'IAM passe alors par son ADR ;
- le client .NET ne fonctionne pas sous l'ACL de la condition 4, ou sous TLS avec la CA sur `gcp` ;
- la NetworkPolicy ne s'applique pas sous kind, ou le profil `restricted` refuse le pod dans la configuration retenue ;
- la série de la condition 12 montre un coût propre au serveur qui fait changer un profil de palier ;
- `valkey-container` cesse de publier le même condensat sur les trois registres, ce qui retire le contrôle de la dérogation ;
- [SECU] juge la lecture mensuelle des avis insuffisante face à R-36.

La levée de la dérogation ne rouvre pas la décision : la PR qui retire la liste fermée l'indique ici par un lien. Une version corrective de la ligne 9.1 ne la rouvre pas non plus : elle passe par Renovate et la matrice (condition 2). Le passage de Memorystore à une autre ligne par défaut passe par la valeur unique de la condition 16, dans une release du blueprint, avec une relecture [SECU] de la licence et des avis de la nouvelle ligne. Sans l'un de ces faits, prochaine vérification au plus tard le 2027-05-23, date proposée par BENCH-014.

## Sources

Ce que BENCH-014 établit se cite par lui. Ses sources S1 à S46 sont dans sa section 9 ; celles des relectures, S47 à S52 pour [FINOPS] et S53 à S67 pour [SECU], y sont recopiées avec les relectures.

| Source | Lue le | Ce qu'elle établit |
| --- | --- | --- |
| [BENCH-014](../benchmarks/BENCH-014-cache.md), sections 1 à 3, commit `17469f0` | 2026-11-25 | Question posée et contraintes ; règle de sélection ; options, images, registres ; candidats écartés ; critères éliminatoires ; parité de version ; authentification, réseau et plus petit nœud de Memorystore (S18 à S28) |
| BENCH-014, section 4 | 2026-11-25 | Seuils, protocole, mise en œuvre durcie, Secret par un tube ; série 2 : M1 5,5 s, M2 56,3 Mio pour Valkey, pod de 6,4 Mio, M4 18,8 Mo en amd64, M5 oui, M6 trois fois sur trois, M7 2,2 s, M8 9.1.4 ; condensat recoupé avec BENCH-005 |
| BENCH-014, sections 5 à 7 | 2026-11-25 | Notes et grille avant relectures, 86 et 72 ; sensibilité ; conditions proposées 1 à 5 ; décision du DSI sur la ligne locale ; entrée proposée au catalogue |
| BENCH-014, sections 8 et 9 | 2026-11-25 | Limites ; sources S1 à S46 citées ici |
| Relecture [SECU] de BENCH-014 | 2026-11-25 | Maturité de Redis à 4, total 69 ; licences et gouvernance confirmées ; moteur invisible au scan dans les deux images ; avis de la ligne 9.1 authentifiés ; absence de signature et d'attestation, même condensat sur trois registres ; texte de la dérogation ; `VALKEY_EXTRA_FLAGS` ; ACL et empreinte ; commandes bloquées par Memorystore ; jeton plutôt qu'IAM ; TLS immuable ; ressource du jeton non publiée ; `foobared` et `password123` ; conditions 1 à 8 ; S53 à S67 |
| Relecture [FINOPS] de BENCH-014 | 2026-11-25 | Recalcul de la série 2 ; écart de 50,4 Mio et mesures pour le trancher ; empreinte à 4/5 confirmée ; cumul du lite à 1 263,8 Mo avec zot et du standard à 1 802,1 Mo ; planchers et paliers ; facturation par nœud et par heure, engagements ; types de nœud ; dimensionnement du pod ; conditions 1 à 7 ; S47 à S52 |
| `tests/bench/bench-014-cache.sh`, ligne 101, branche `docs/bench-014-cache` | 2026-11-25 | Condensat d'index `sha256:56729e68bdda139cbd3f6a2538683dc3523325fc5711ea1a379938f1b37893f0` de `valkey/valkey:9.1.4-alpine` |
| <https://docs.cloud.google.com/memorystore/docs/valkey/supported-instance-configurations> | 2026-11-25 | `maxmemory-policy` par défaut à `volatile-lru`, modifiable à la création ou à la mise à jour ; valeurs admises, dont `allkeys-lru` ; `maxmemory` réglé par nœud ; aucune date de mise à jour visible ; lue par un outil qui résume |
| <https://github.com/hashicorp/terraform-provider-google>, `website/docs/r/memorystore_instance.html.markdown` au tag v8.12.0 | 2026-11-25 | `engine_configs` ; `transit_encryption_mode` immuable, `TRANSIT_ENCRYPTION_DISABLED` ou `SERVER_AUTHENTICATION` ; `authorization_mode` `AUTH_DISABLED`, `IAM_AUTH` ou `TOKEN_AUTH` ; `mode` `CLUSTER` ou `CLUSTER_DISABLED` ; `replica_count` à 0 par défaut ; `persistence_config.mode` `DISABLED`, `RDB` ou `AOF` ; `automated_backup_config` ; `desired_auto_created_endpoints` ; `engine_version` sans défaut écrit, `VALKEY_7_2` dans l'exemple ; lue par un outil qui résume |
| <https://github.com/hashicorp/terraform-provider-google/releases> | 2026-11-25 | v8.12.0 marquée « Latest », du 17 novembre, aucune plus récente ; aucune note ne cite `google_memorystore_auth_token` ; `TOKEN_AUTH` ajouté à `google_memorystore_instance` en 8.8.0 ; lue par un outil qui résume |
| <https://valkey.io/topics/lru-cache/> (S51 de BENCH-014) | 2026-11-25 | `volatile-lru` n'évince que les clés qui ont une durée de vie ; les politiques `volatile-*` se comportent comme `noeviction` sans clé éligible ; `allkeys-lru` conseillé quand on hésite ; `maxmemory` sans limite par défaut sur 64 bits ; lue par un outil qui résume |
| [docs/risques.md](../risques.md), R-04, R-05, R-20, R-25, R-36 | 2026-11-25 | Premier `task up` du standard à 1 802,1 Mo ; dépense GCP et mitigation ; liste des valeurs connues ; registres publics ; failles invisibles au scan, lecture mensuelle |
| [ADR-001](ADR-001-format-spec.md), condition 2 | 2026-11-25 | Briques nommées d'après les types Score, `redis` |
| [ADR-006](ADR-006-orchestration-locale.md), conditions 1 et 2 | 2026-11-25 | Aucun Secret sous `k8s/` ; mot de passe du cache par un Secret, jamais en argument |
| [ADR-007](ADR-007-secrets.md), conditions 1 et 5 | 2026-11-25 | Création par un tube, liste des valeurs connues ; parité du nom et des clés |
| [ADR-008](ADR-008-modules-opentofu-gcp.md), conditions 2, 3, 6 et 9, portée | 2026-11-25 | État chiffré à cause de la chaîne AUTH ; attributs `*_wo` ; conftest sur le tier ; moteur et authentification du cache hors décision ; Memorystore for Redis dans le socle de BENCH-008 |
| [ADR-009](ADR-009-catalogue.md), section 2 | 2026-11-25 | III fixe les candidats, V les départage ; préférence pour la variante managée dont le moteur est porté par une fondation, avec Valkey en exemple ; standard `resp` |
| [ADR-010](ADR-010-gitops.md), réponses de la GATE 1 | 2026-11-25 | Le profil lite n'embarque pas Flux |
| [ADR-011](ADR-011-miroir-registres.md), tableau des registres, conditions 9 et 10 | 2026-11-25 | docker.io servi par zot, Valkey 9.1.4 mesurée au test T2 ; aucune redistribution ; liste unique des registres |
| [ADR-012](ADR-012-postgres-local.md), conditions 1, 5, 6, 7 et 9, dérogation | 2026-11-25 | Profil `restricted` ; valeur unique de la majeure ; « prêt » par une requête authentifiée ; contrôle de la liste fermée ; dérogation limitée à `docker.io/library/`, `valkey/valkey` hors de son champ |
| [ADR-013](ADR-013-fournisseur-identite.md) et [ADR-014](ADR-014-serveur-mails-test.md), conditions et dérogations | 2026-11-25 | Modèle de dérogation datée pour une image tierce ; NetworkPolicy sous kind à vérifier par [OPS] |
| [ADR-016](ADR-016-images-sans-date.md), décision | 2026-11-25 | Renovate date les images de Docker Hub, Valkey comprise ; ghcr.io et public.ecr.aws non datés |
| [`catalog/README.md`](../../catalog/README.md), `scripts/catalog/accepted-licenses.yaml` | 2026-11-25 | Champs d'une cible, standards admis dont `resp`, règles d'expiration ; `BSD-3-Clause` dans la liste blanche |
| [specs/001-golden-repo-saas-b2b/spec.md](../../specs/001-golden-repo-saas-b2b/spec.md), FR-001, FR-009, hypothèses | 2026-11-25 | Le cache démarre par une commande ; l'exemple lit et écrit dans le cache ; un cache Valkey |
| [plan.md](../../specs/001-golden-repo-saas-b2b/plan.md), étapes 13, 19 et 20, matrice ; [tasks.md](../../specs/001-golden-repo-saas-b2b/tasks.md), T023, T075 à T081, T107, T136 à T138 ; [research.md](../../specs/001-golden-repo-saas-b2b/research.md), RS-11 ; `contracts/secrets.md` | 2026-11-25 | Étapes bloquées par cet ADR ; contrôles S01, S06, S07, S11, S14, S15, S17, S18, S21, S23, E03 à E05, E11, E13, E25, E27, D02, D03, P03, U01 ; `cache-auth`, `Opaque`, clé `password` |
| [Constitution](../../.specify/memory/constitution.md), version 1.2.0 | 2026-11-25 | Principes I à X ; dérogation justifiée dans un ADR ; exception de sécurité au délai de 7 jours |
