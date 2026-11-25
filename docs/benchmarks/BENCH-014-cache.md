# BENCH-014. Moteur du cache

| Champ | Valeur |
| --- | --- |
| Identifiant | BENCH-014 |
| Sujet | Moteur du cache du projet généré : image dans le cluster kind de la cible `local`, et variante de Memorystore sur `gcp` |
| Statut | relu |
| Ouvert le | 2026-11-21 |
| Mis à jour le | 2026-11-25 |
| Auteur | [BENCH] |
| Relecteurs | [SECU] pour les licences et les CVE, [FINOPS] pour les coûts |
| Périmètre | Projet généré sur PC (cluster kind, ADR-004) et projet généré sur GCP (Memorystore, ADR-008) |
| Choix du PRD | Aucune ligne propre au cache. US-004 : le service de chaque brique vient du catalogue, par cible. Le brief (sections 5 et 6) prévoit Memorystore sur GCP et Valkey sur le PC |
| ADR lié | ADR-015, à écrire par [ARCHI] d'après l'arbitrage du DSI du 2026-11-25 (section 7) |
| Verdict proposé | O1, Valkey 9.1.4 : 86/100, devant Redis 7.2.17 (69). Écart de 17 points, après la correction de maturité de [SECU] ; l'empreinte, mesurée le 2026-11-25, ne départage pas (4/5 chacune) et ne pourrait pas l'inverser (section 7). Retenu par le DSI le 2026-11-25 ; dérogation datée à ENF-03 pour `valkey/valkey` ; relectures [SECU] et [FINOPS] en section 10 |

## 1. Contexte

[BENCH] Question posée : quel moteur sert le cache du projet généré, en image
dans le cluster kind de la cible `local`, et quelle variante de Memorystore lui
répond sur `gcp`.

[BENCH] Pourquoi maintenant. L'ADR-008 laisse hors de sa décision « le moteur
du cache (Redis ou Valkey) et son authentification ». La chaîne AUTH de
Memorystore, générée par le serveur, finit en clair dans l'état, et
« l'authentification IAM du cache revient au benchmark du moteur de cache »
(conditions 2 et 3). L'ADR-007 renvoie cette chaîne au même benchmark, et
l'ADR-012 écrit que le cache « suivra le benchmark de son moteur ». Le plan du
golden repo (branche `docs/plan-golden-repo`, research
RS-11) bloque sur ce choix la ressource Memorystore de l'étape 13 et le
producteur du Secret `cache-auth` sur `gcp` [S44]. Lucas a demandé le
2026-11-21 un benchmark court, selon la méthode.

[BENCH] Ce qui en dépend. US-005 : `task up` démarre l'API, le front,
Postgres et le cache dans le cluster local, sans autre étape (principe VII).
ENF-02 : chaque brique existe sur les deux cibles, open source sur le PC,
managée sur GCP, et seule la couche de cible change. Le DSI en tire pour ce
benchmark un critère : la parité de version entre `local` et `gcp`, comme la
majeure de Postgres dans BENCH-011. ENF-03 : images figées, signées, refusées
par Kyverno sans signature. La spec du golden repo veut une API dont
l'exemple « lit et écrit dans la base et dans le cache » (FR-009) [S45].

[BENCH] Contraintes déjà posées. ADR-006, condition 2 : la couche `local`
impose un mot de passe au cache, lu dans un Secret créé par `task up`, jamais
dans `command` ni `args`. ADR-007, conditions 1 et 5 : Secrets créés par un
tube depuis `/dev/urandom`, même nom et mêmes clés sur les deux cibles. Le
contrat du plan nomme ce Secret `cache-auth`, de type `Opaque`, clé
`password` [S44]. ADR-004 : images figées par condensat. ADR-011 : le miroir
zot sert docker.io dans le profil lite, et chaque registre de plus demande une
entrée de synchronisation à essayer. ADR-012 : une dérogation datée à ENF-03
couvre les images du programme d'images officielles de Docker, et seulement
elles ; il cite `valkey/valkey` comme hors de ce programme. ADR-009 : le
catalogue note le standard exposé, `resp` pour le cache, et la brique
abstraite prend le nom du type Score `redis` (ADR-001). Principes II, III, IV,
V, VI et VIII. Risques R-04, R-05, R-20 et R-25.

[BENCH] Option pressentie : Valkey. Le brief l'écrit dans sa section 6
(« Cache : Valkey ») et dans son tableau de la section 5, et l'ADR-009 s'en
sert d'illustration pour la lecture du principe V sur le cloud. Elle est notée
comme l'autre option, avec le même script.

[BENCH] Hors champ : la persistance du cache, que le plan exclut (RS-11) ; la
haute disponibilité et le mode cluster ; le client .NET et son code ; le
dimensionnement de Memorystore et son prix, qui reviennent à [FINOPS] ; AWS,
hors MVP ; Windows (Q5).

## 2. Options étudiées

[BENCH] Règle de sélection, écrite le 2026-11-23 avant toute note. Un
candidat devient une option s'il remplit les cinq conditions suivantes.

1. Le moteur parle RESP, le standard que le catalogue retient pour le cache
   (`resp`, ADR-009), et que l'application parlera sur les deux cibles. La
   brique abstraite s'appelle `redis`, du nom du type Score (ADR-001).
2. Le même moteur existe sur `gcp` dans une variante de Memorystore, le
   service managé qu'impose le principe III. Sans cette variante, la parité
   de version demandée par le DSI ne se mesure pas, et `gcp` servirait un
   autre moteur que le PC.
3. La version locale examinée est la dernière release stable de la ligne que
   la variante Memorystore sert par défaut. BENCH-011 a fait de même, avec
   PostgreSQL 18.7 plutôt que 19.0. La dernière release stable du projet se
   note à côté, sans être mesurée.
4. Une image de conteneur publiée par le projet, ou par le programme d'images
   officielles de Docker, pour linux/amd64 et linux/arm64 (Q5).
5. Les trois critères éliminatoires du brief (section 3).

| Option | En une phrase | Version examinée | Publiée le | Sources |
| --- | --- | --- | --- | --- |
| O1. Valkey | Moteur de LF Projects, issu de Redis 7.2.4. Sur `local`, l'image `valkey/valkey` ; sur `gcp`, Memorystore for Valkey, qui sert la ligne 9.1 par défaut | 9.1.4, image `9.1.4-alpine`. Dernière stable du projet : 9.2.0, publiée le 2026-11-19, que Memorystore ne sert pas | 2026-11-18 | [S1], [S2], [S7], [S8], [S18] |
| O2. Redis 7.2 | Moteur de Redis Ltd., ligne 7.2 restée sous BSD-3-Clause. Sur `local`, l'image officielle `redis` ; sur `gcp`, Memorystore for Redis, qui sert 7.2 par défaut | 7.2.17, image `7.2.17-alpine`. Dernière stable du projet : 8.12.0, publiée le 2026-11-22, sous triple licence, que Memorystore ne sert pas | 2026-10-26 | [S9], [S10], [S14], [S24] |

[BENCH] Images, registres et plates-formes, lus le 2026-11-23 :

| Option | Image et condensat d'index | Registre | Plates-formes | Tenue par | Attestations et signature |
| --- | --- | --- | --- | --- | --- |
| O1. Valkey | `valkey/valkey:9.1.4-alpine@sha256:56729e68…b37893f0` | docker.io, aussi publiée sur ghcr.io et public.ecr.aws | Construites pour linux/amd64, linux/arm64, linux/arm/v7 et linux/ppc64le ; le tag liste amd64, arm64, arm v7 et ppc64le | La communauté Valkey, dépôt `valkey-io/valkey-container`. Hors du programme d'images officielles : `library/valkey` n'existe pas | Construction avec `provenance: false`, aucune étape de signature. Le même condensat d'index est publié sur docker.io, ghcr.io et public.ecr.aws ; aucun manifeste d'attestation dans l'index, aucun tag `sha256-*`, API d'attestations de GitHub à 404 ; le SBOM SPDX embarqué dans l'image n'est pas signé (relecture [SECU], 2026-11-25) [S55], [S56], [S57] |
| O2. Redis 7.2 | `redis:7.2.17-alpine@sha256:2f66de68…5aa1c335` | docker.io, programme d'images officielles (`library/redis`) | amd64, arm32v6, arm32v7, arm64v8, i386, ppc64le, riscv64, s390x | Huit mainteneurs, tous en `@redis.com` | Aucune signature vérifiable des images officielles depuis le retrait de Docker Content Trust (BENCH-011, S45 et S49) |

[BENCH] Sources de ce tableau : [S7], [S8], [S14], [S16], [S38]. Le condensat
de O1 vient de l'API de Docker Hub, lu par un outil qui résume les pages ; il
est identique, caractère pour caractère, à celui que fige le script de
BENCH-005 [S41]. Celui de O2 vient du dépôt
`docker-library/repo-info` [S16]. Le script vérifie au démarrage que chaque
condensat existe au registre (section 4.3).

[BENCH] Variante Alpine pour les deux options. Le plan du golden repo reprend
l'image de l'essai de BENCH-005, `valkey/valkey:9.1.4-alpine` (RS-11) [S44],
et la même base des deux côtés compare à fonction égale. Les deux images
tournent sous l'UID 999 et le GID 1000 [S7], [S15]. Les variantes Debian
(`9.1.4-trixie`, `7.2.17-bookworm`) sont lues au registre pour la
sensibilité, sans être tirées.

[BENCH] Registres et miroir (ADR-011). Les deux images viennent de docker.io,
que le miroir zot sert déjà dans le profil lite : aucune option n'ajoute de
registre.

[BENCH] Candidats repérés et non retenus, lus le 2026-11-23 :

| Candidat | Licence | Activité | Suite |
| --- | --- | --- | --- |
| KeyDB (Snap) | BSD-3-Clause [S31] | Dernière release v6.3.4 le 2023-10-30 [S31] | Éliminé : aucune release depuis 12 mois |
| Dragonfly | Dragonfly Source-Available License à partir de 2.1, avec une limite de 100 vCPU en production [S32] ; absente de la liste de l'OSI [S17] | v2.1 le 2026-11-04 [S32] | Éliminé : licence non open source |
| Redict | Non lue | Dépôt marqué archivé sur Codeberg, dernière release 7.3.6 le 2025-10-08 [S33] | Éliminé : archivé, et aucune release depuis 12 mois |
| Garnet (Microsoft) | MIT [S34] | v2.2.13 le 2026-11-16 ; images sur ghcr.io, amd64 et arm64 [S34] | Non retenu, condition 2 : aucune variante de Memorystore. Sur `gcp`, il faudrait Memorystore for Valkey, donc deux moteurs ; ghcr.io ajouterait un registre au miroir. Éditeur unique |
| Memcached | Non lue | Non lue | Non retenu, condition 1 : autre protocole que RESP. Google recommande de migrer Memorystore for Memcached vers Memorystore for Valkey [S35] |
| Redis 8.12 | RSALv2, SSPLv1 ou AGPLv3 au choix [S9], [S11] ; seule l'AGPLv3 est approuvée par l'OSI [S17] | 8.12.0 le 2026-11-22 [S10] | Non retenu, condition 3 : Memorystore ne sert pas au-delà de 7.2 [S24]. Lu en sensibilité |

[BENCH] Variantes de Memorystore non retenues comme pendant : Memorystore for
Redis Cluster, « based on open-source Redis version 7.x » [S27], parce que le
mode cluster est hors champ ; le mode cluster de Memorystore for Valkey, pour
la même raison. Memorystore for Valkey propose un mode sans cluster
(`CLUSTER_DISABLED`) [S23], [S28].

## 3. Critères éliminatoires

[BENCH] Seuil de release : 2025-11-23, douze mois avant la vérification.

| Option | Licence open source | Ni archivé ni en maintenance | Release de moins de 12 mois | Vérifié le | Résultat |
| --- | --- | --- | --- | --- | --- |
| O1. Valkey | Oui : BSD-3-Clause [S1], approuvée par l'OSI [S17] ; image sous BSD-3-Clause [S7] | Oui : dépôt non archivé, dernier push le 2026-11-23 [S1] ; ligne 9.1 maintenue jusqu'au 2029-05-19, correctifs de sécurité jusqu'au 2031-05-19 [S3] | Oui, 9.1.4 le 2026-11-18 [S2] | 2026-11-23 | Retenue |
| O2. Redis 7.2 | Oui : BSD-3-Clause pour la ligne 7.2 (`COPYING` au tag 7.2.17) [S9], [S11], approuvée par l'OSI [S17] ; empaquetage de l'image sous BSD-3-Clause [S15] | Oui : dépôt non archivé, dernier push le 2026-11-23 [S9] ; ligne 7.2 en « Extended », fin le 2029-12-01 [S12] | Oui, 7.2.17 le 2026-10-26 [S10] | 2026-11-23 | Retenue |

[BENCH] Options éliminées : aucune parmi les deux étudiées. KeyDB, Dragonfly
et Redict le sont avant l'étude (section 2).

[BENCH] Délai de 7 jours du principe VI (correction demandée par [SECU],
2026-11-25). Le tag `9.1.4-alpine` a été poussé le 2026-11-18 à 23:11:58 UTC
(`tag_last_pushed` de Docker Hub) ; le délai s'achève le 2026-11-25 à 23:12
UTC. La 9.1.4 corrige GHSA-3885-pq5f-788j : l'exception du principe VI la
couvrait de toute façon [S59].

[BENCH] Parité de version (ENF-02), lue le 2026-11-23. Aucune option n'est
éliminée à ce titre.

- O1 : Memorystore for Valkey sert 7.2, 8.0, 9.0 et 9.1, et 9.1 par défaut,
  en GA depuis le 2026-09-24. La page ne publie pas le correctif servi, et ne
  cite pas 9.2 [S18], [S19]. La version locale, 9.1.4, est de la même ligne.
- O2 : Memorystore for Redis sert de 3.2 à 7.2, et 7.2 par défaut. Il liste
  le correctif 7.2.0, à la date du 2024-02-29, et écrit qu'il « supports one
  patch version for every major OSS Redis version » [S24]. La version locale,
  7.2.17, est de la même ligne, dix-sept correctifs plus loin que celui que la
  page affiche. Ses notes de version, jusqu'au 2026-11-09, n'annoncent ni
  7.4, ni 8.x, ni retrait [S26].

[BENCH] Authentification et réseau sur `gcp`, faits qui nourrissent la
portabilité (section 5.7) :

| Point | Memorystore for Valkey | Memorystore for Redis |
| --- | --- | --- |
| Mot de passe | « basic token-based authentication », GA le 2026-09-18 ; jeton créé par le service, deux jetons au plus par utilisateur [S19], [S20] | Chaîne AUTH de 36 caractères, un UUID créé par le service ; elle change quand on coupe puis rétablit AUTH [S25] |
| IAM | Jeton d'accès IAM passé à `AUTH`, valable une heure par défaut et douze au plus, rôle `roles/memorystore.dbConnectionUser` ; le client doit aller chercher un jeton à chaque nouvelle connexion [S21] | La page d'AUTH n'en parle pas [S25] |
| OpenTofu, provider `google` 8.12.0 | `authorization_mode = "TOKEN_AUTH"`. La ressource qui lit le jeton, `google_memorystore_auth_token`, est fusionnée le 2026-11-18, après la 8.12.0 du 2026-11-17, donc pas encore publiée ; sa page prévient que le jeton est stocké en clair dans l'état [S28] | Attribut `auth_string` de `google_redis_instance`, déjà présent dans le socle de BENCH-008, et écrit en clair dans l'état [S28], [S43] |
| Réseau | Private Service Connect seulement, par une politique de connexion de service pour la classe `gcp-memorystore` ; ports 6379 et 11000 à 13047 [S22] | Accès privé aux services, le montage du socle de l'ADR-008 [S43] |
| Plus petit nœud | `shared-core-nano` : 1,4 Go, 0,5 vCPU, sans SLA, réservé au développement ; `custom-pico` : 1,25 Go, 2 vCPU, avec SLA, en mode sans cluster seulement [S23] | Non relevé |

## 4. Mesures

### 4.1 Ce qui est mesuré

[BENCH] Seuils d'empreinte écrits le 2026-11-21 à 22:05 UTC, avant toute
mesure, avant tout test de fumée et avant toute lecture de taille d'image dans
un registre pour ce rapport. Le SHA-256 de cette section, du titre « 4.1 »
jusqu'à la ligne qui précède le titre « 4.2 », est relevé dans le dossier de
travail de [BENCH] avant toute lecture web ; ses relevés et leurs heures sont
en section 4.4. Chaque option part de 5 et
perd un cran par seuil dépassé (règle de `TEMPLATE.md`, section 5.6). Le cache
est une couche de la stack : d'après la deuxième règle de la GATE 1, il se
note contre ses propres seuils, et son cumul avec la plate-forme de base va
dans la sensibilité. Les quatre seuils reprennent ceux de BENCH-011, sans
adaptation, comme le demande le DSI :

1. volume compressé des images de la couche au-delà de 112,5 Mo, lu sur
   linux_amd64 (première règle de la GATE 1) : 90 s à 10 Mbit/s, soit 10 % du
   budget de 900 s d'ENF-01 ;
2. au moins une image de la couche retéléchargée à chaque création du
   cluster, cache Docker de l'hôte plein : repris de BENCH-003, et mesuré sans
   le miroir de l'ADR-011 ;
3. installation jusqu'à « prêt » (médiane de M1) au-delà de 90 s, 10 % du
   budget, images tirées par le nœud sur le réseau du poste ;
4. mémoire de la couche au repos (médiane de M2) au-delà de 512 Mio, un
   seizième d'un portable de 8 Gio, lue au nœud moins le nœud de base
   (troisième règle de la GATE 1).

[BENCH] Deux adaptations envisagées et non retenues. Le deuxième palier de
volume que [FINOPS] proposait pour les couches à venir (BENCH-011, section
10) n'est pas ajouté : il changerait la règle de toutes les couches, ce qui
revient à Lucas et au gabarit, pas à un rapport. Le seuil 2 n'est pas relu à
travers le miroir zot de l'ADR-011 : le script ne lance aucun conteneur hors
du cluster, donc il ne peut pas mesurer ce miroir. Cette lecture va dans la
sensibilité, comme dans BENCH-011.

[BENCH] Biais à déclarer : avant l'écriture de ces seuils, [BENCH] a lu dans
le dépôt deux volumes qui touchent une option candidate. BENCH-005 donne
18,8 Mo en amd64 pour `valkey/valkey:9.1.4-alpine` (section 4.4), et
l'ADR-011 139,1 Mo pour Postgres et Valkey ensemble. Aucun seuil n'en est
tiré : les quatre valeurs sont celles de BENCH-011, posées le 2026-11-20 et
reprises de BENCH-009. Les parts elles-mêmes (10 % du budget, un seizième de
8 Gio) restent un choix de [BENCH] : le budget par étape d'ENF-01 n'est pas
fixé (R-04).

[BENCH] « Prêt » veut dire : une commande `PING` authentifiée avec le mot de
passe du Secret `cache-auth` reçoit `PONG`, par le Service que l'application
utilisera, depuis un pod client du cluster. Le contrôle passe par
`kubectl exec` dans ce pod, une fois par seconde ; l'instant retenu est le
premier de trois succès de suite, comme dans BENCH-011. Le client lit le mot
de passe dans le Secret par une variable d'environnement, jamais en argument.

| ID | Mesure | Unité | Critère alimenté | Script |
| --- | --- | --- | --- | --- |
| M1 | Installation jusqu'à « prêt » : du premier `kubectl apply` de la couche à la première réponse authentifiée, nœud neuf, images tirées par le nœud | s | Empreinte sur PC | `tests/bench/bench-014-cache.sh` |
| M2 | Mémoire de la couche au repos, 120 s après « prêt » : nœud avec la couche moins nœud de base (M9), médianes de trois échantillons espacés de 10 s ; somme des pods de la couche en sensibilité | Mio | Empreinte sur PC | idem |
| M3 | CPU des pods de la couche au même moment | % d'un cœur | Empreinte sur PC | idem |
| M4 | Volume compressé des images de la couche, par architecture, lu au registre | Mo | Empreinte sur PC (ENF-01, R-04) | idem |
| M5 | Images de la couche retéléchargées à chaque création du cluster, d'après les événements `Pulled` du nœud | oui ou non | Empreinte sur PC (R-25) | idem |
| M6 | Authentification : (a) `PING` sans mot de passe par le Service, refusé ; (b) `SET` puis `GET` avec mot de passe, réussis ; (c) mot de passe absent de la ligne de commande de chaque processus du pod du cache | oui ou non | Sécurité (ADR-006, condition 2 ; R-20) | idem |
| M7 | Retour à « prêt » après la suppression du pod du cache | s | Expérience dev | idem |
| M8 | Version servie (`INFO server`), comparée aux versions de la variante Memorystore de l'option | texte | Portabilité (ENF-02) | idem |
| M9 | Mémoire du nœud de base : kind seul, même image et même configuration (option `none` du script) | Mio | Base de M2 | idem |

### 4.2 Machine de mesure

[BENCH] Relevé le 2026-11-24 par `sysctl`, `sw_vers` et `docker info`, et par
le script dans `versions.tsv`. C'est la machine de BENCH-011. Le
`versions.tsv` de la série 2, le 2026-11-25, porte les mêmes versions et la
même machine virtuelle (14 CPU, 12 598 894 592 octets).

| Élément | Valeur |
| --- | --- |
| Modèle | Apple Mac16,7 |
| Processeur | Apple M4 Pro, 14 cœurs |
| Mémoire | 24 Gio |
| Système | macOS 27.2.1 (build 26B131) |
| Moteur de conteneurs | OrbStack, Docker Engine 29.8.2, buildx 0.37.2, cgroup v2 (non libre, R-26) |
| Ressources allouées | Machine virtuelle d'OrbStack : 14 CPU, 11,73 Gio (`docker info`) |
| Versions mesurées | kind 0.33.0, `kindest/node:v1.36.4` figée par condensat, kubectl 1.37.1 ; O1 `valkey/valkey:9.1.4-alpine` ; O2 `redis:7.2.17-alpine`. Toutes figées par condensat dans le script ; au démarrage, chaque tag désignait encore le condensat figé (`tag-matches`) |
| Alimentation | Secteur, capot ouvert, vérifiés au démarrage et avant chaque exécution ; `pmset -g log` relu à la fin de chaque exécution (`power.tsv`) |
| Horloge | `gdate`, à la nanoseconde affichée |
| Charge parasite | Applications de bureau ouvertes, sessions Claude Code. Le verrou `bench-lock-s4` empêche deux séries simultanées ; le script note la charge et les clusters kind présents dans `load.tsv` |

[BENCH] Mise en œuvre, identique pour les deux options. Un Service `cache` et
un Deployment d'une réplique, sans persistance (RS-11), écrits dans le script.
Le namespace applique le profil `restricted` des Pod Security Standards : UID
999, GID 1000, `runAsNonRoot`, élévation interdite, capacités retirées,
`seccompProfile` en `RuntimeDefault`, système de fichiers racine en lecture
seule, aucun jeton de compte de service monté. C'est la condition 1 de
l'ADR-012, appliquée au cache. Un conteneur d'initialisation, de la même
image, écrit la configuration dans un volume en mémoire : `save ""` et
`appendonly no` coupent les instantanés et le journal, `requirepass` porte le
mot de passe, lu dans le fichier du Secret par `cat` et une redirection. Le
serveur démarre sur ce fichier (`valkey-server /etc/cache/cache.conf`, ou
`redis-server`), forme que les deux binaires documentent dans leur aide
[S36], [S37]. Le mot de passe ne passe donc dans aucun argument ni aucune
variable d'environnement du serveur, comme le veut la condition 2 de
l'ADR-006.

[BENCH] Le mot de passe sort de `/dev/urandom` et passe par un tube à
`kubectl create -f -` (ADR-007, condition 1) : 40 caractères
alphanumériques, dans le Secret `cache-auth`, type `Opaque`, clé `password`,
le contrat du plan [S44]. Le script n'en garde rien, ni empreinte ni préfixe.
Le pod client utilise l'image de l'option, déjà tirée par le nœud, et lit le
mot de passe par la variable `REDISCLI_AUTH`, que `redis-cli` lit et que
`valkey-cli` lit à défaut de `VALKEYCLI_AUTH` [S36], [S37].

### 4.3 Protocole

1. État de départ : aucun cluster `celian-bench-014`. Le script ne construit
   ni ne retire aucune image : chaque exécution crée un nœud kind neuf, qui
   tire l'image de l'option sur le réseau (R-25). L'image du nœud reste en
   cache, partagée avec les autres benchmarks ; `kind create cluster` la tire
   si elle manque au cache de l'hôte (précision de [SECU]).
2. Commandes, identiques à chaque exécution : création du cluster, namespace,
   Secret, puis `kubectl apply` du cache et du client.
3. Fin de M1 : le premier de trois `PING` authentifiés de suite qui reçoivent
   `PONG`, lancés une fois par seconde par `kubectl exec` dans le pod client.
4. Authentification (M6), juste après « prêt » : `PING` sans mot de passe, la
   variable retirée ; `SET` puis `GET` avec mot de passe ; dans le conteneur
   du cache, compte des lignes de commande de `/proc` qui contiennent le mot
   de passe, le fichier du Secret servant de motif à `grep -F -f`.
5. Repos (M2, M3) : le pod client est arrêté, puis trois échantillons à partir
   de 120 s après « prêt », espacés de 10 s, médiane des trois. Nœud par
   `docker stats --no-stream` ; pods de la couche par l'API Summary du
   kubelet. Le nœud de base (M9) suit le même relevé, sans couche.
6. Retour (M7) : suppression du pod du cache ; l'instant retenu est le premier
   de trois `PONG` de suite une fois l'ancien pod disparu. La clé écrite en M6
   est relue : sans persistance, elle doit être perdue.
7. Téléchargements : événements `Pulled` du nœud (M5) ; volumes lus au
   registre par `docker manifest inspect -v`, sans tirage (M4).
8. Trois exécutions par option, entrelacées dans l'ordre nœud de base, O1,
   O2, avec 15 s de pause entre deux. Le script prend le verrou commun au
   démarrage et le rend à la fin, erreur comprise.
9. Alimentation (règle posée après BENCH-012, contrôle repris du script de
   BENCH-011) : le script refuse de démarrer, et refuse chaque exécution,
   hors secteur ou capot fermé. Une exécution pendant laquelle
   `pmset -g log` montre une entrée `Sleep`, ou qui finit hors secteur ou
   capot fermé, est marquée invalide dans `power.tsv` et sort du résumé.
   Pendant la série, le script tient `caffeinate -i -s`, qui empêche la
   veille sur inactivité et, sur secteur, la veille du système ; fermer le
   capot endort quand même le Mac.

[BENCH] Pour refaire la mesure :

```bash
BENCH_LOCK=/chemin/vers/un/verrou tests/bench/bench-014-cache.sh /chemin/vers/un/dossier/vide
```

[BENCH] Sans argument, le script crée un dossier temporaire ; un dossier passé
en argument doit être absent ou vide. `OPTIONS`, `RUNS`, `IDLE_WAIT` et
`BENCH_LOCK` règlent l'essai. Avant tout cluster, le script vérifie les
versions et que chaque condensat figé existe au registre ; un tag qui a bougé
depuis est seulement noté. Il refuse de démarrer si le cluster
`celian-bench-014` existe, et son `trap` n'est posé qu'après ces contrôles et
le verrou : un refus ne supprime rien. Il passe shellcheck 0.11.0 et
`bash -n` sous le bash 3.2 de macOS, et ses manifests rendus passent le hook
`check-yaml` du dépôt, vérifiés le 2026-11-23. Le test de fumée et la série 1
ont tourné avec le commit `14a4384` (SHA-256
`1426ddca5ecd877cfb0190ce3b1525d643b9d2307702c8ea86cdf1a5c1a8d1cb`), qui
ajoute au commit d'ouverture le contrôle d'alimentation du point 9. La série
2 a tourné avec le commit `1bcf41d` (section 4.4).

[BENCH] Le rebase de la branche sur `main` (`3ffb996`), le 2026-11-25, a
changé les SHA des commits : `14a4384` est devenu `33cf0dd`, et `1bcf41d`
est devenu `0b6c8ad`. Le script y est identique, vérifié par `git show` et
`shasum -a 256` : `1426ddca…` pour le premier, `16daad12…` pour le second.
Les SHA-256 du script font foi ; la fusion en squash changera encore les SHA
de commit.

[BENCH] Inventaire des commandes qui créent, modifient ou suppriment un
conteneur ou un réseau, en tête du script pour la relecture [SECU] :
`kind create cluster`, qui lance le nœud par `docker run --privileged`, avec
aussi `seccomp=unconfined`, `apparmor=unconfined` et `--restart=on-failure:1`,
et crée le réseau `kind` par `docker network create -d=bridge` s'il manque
[S65] ; `kind delete cluster` ; `docker network rm
kind`, seulement si le script a créé ce réseau et qu'il est vide. Aucun
`docker run`, `start`, `stop`, `restart`, `exec`, `cp` ni `create` : le
redémarrage du nœud de BENCH-011 n'existe pas ici. Les autres appels à Docker
lisent seulement : `ps`, `stats`, `manifest inspect`,
`buildx imagetools inspect`, `network inspect`, `version`, `info`. Le
contrôle d'alimentation ne fait que lire : `pmset -g ps`, `pmset -g log`,
`ioreg -r -k AppleClamshellState`. Ni curl,
ni wget, ni python, ni node, ni perl : l'horloge vient de `gdate` s'il est
installé, sinon de `date +%s`, à la seconde, et le choix est noté dans
`versions.tsv`.

[BENCH] Compléments de l'inventaire, demandés par [SECU] le 2026-11-25. Hors
du dossier d'essai, le script n'écrit que le dossier du verrou, quand
`BENCH_LOCK` est défini, et tient une assertion `caffeinate` libérée à sa
sortie. Dans le cluster, il écrit par `kubectl apply`, `create`, `scale`,
`delete pod` et `exec`, toujours vers `celian-bench-014`, par un `KUBECONFIG`
du dossier d'essai. Il ne sort du poste que par `docker manifest inspect`,
`docker buildx imagetools inspect` et les tirages du nœud, tous vers Docker
Hub. `docker ps -q`, qui manquait dans BENCH-013, figure ici parmi les
lectures. [SECU] confirme l'inventaire du script `16daad12…`, exact et complet
pour ce qui crée, modifie ou supprime un conteneur ou un réseau.

[BENCH] Correction non appliquée. [SECU] demande que l'en-tête du script, qui
dit « no port is published to the host », devienne « no port is published
outside the loopback », puisque kind publie l'API sur 127.0.0.1 (R-20). Le
script du rapport a pour SHA-256 `16daad12…` et les relectures le citent : le
modifier changerait ce condensat. La correction se fera à la prochaine
modification du script, comme l'écrit [SECU].

### 4.4 Résultats

[BENCH] État au 2026-11-25 : la série 2 est complète, et elle seule fonde la
note (sous-section « Série 2, retenue », plus bas). Le test de fumée et la
série 1, interrompue, restent décrits dans l'ordre où ils ont tourné ; aucune
de leurs valeurs n'entre dans la note, sauf M4. Le SHA-256 de la section 4.1
a été vérifié le 2026-11-24 à 00:42:48 UTC, avant la première mesure : il
vaut toujours `67a35b6b…96f6`.

[BENCH] Volumes au registre (M4), lus par le script le 2026-11-24, sans
tirage, en Mo compressés de 10⁶ octets. Cette lecture ne dépend ni de la
machine ni de l'alimentation : elle compte pour la note.

| Image | amd64 (noté) | arm64 | À 10 Mbit/s, amd64 |
| --- | --- | --- | --- |
| O1 `valkey/valkey:9.1.4-alpine` | 18,8 | 19,3 | 15,1 s |
| O2 `redis:7.2.17-alpine` | 16,0 | 16,5 | 12,8 s |
| Variante `valkey/valkey:9.1.4-trixie` (sensibilité) | 44,8 | 45,2 | 35,9 s |
| Variante `redis:7.2.17-bookworm` (sensibilité) | 43,2 | 43,1 | 34,6 s |

[BENCH] La série 2 a relu ces volumes le 2026-11-25 : son `images.tsv` est
identique, à l'octet près, à ceux du test de fumée et de la série 1 (O1
18 830 089 octets en amd64, O2 16 024 750).

[BENCH] Test de fumée, le 2026-11-24 de 00:44:48 à 00:50:59 UTC, verrou
`bench-lock-s4` pris, une exécution par option, `IDLE_WAIT=30` au lieu de 120
(dossier `smoke-1` du dossier de travail de [BENCH]). Les trois exécutions sont
valides : secteur, capot ouvert, aucune entrée `Sleep`. Résultats indicatifs,
non retenus pour la note (une exécution, repos raccourci) :

| Mesure | O1. Valkey | O2. Redis 7.2 | Nœud de base |
| --- | --- | --- | --- |
| M1, « prêt » | 5,7 s | 4,5 s | sans objet |
| Nœud au repos | 544,3 Mio | 576,4 Mio | 577,8 Mio |
| Somme des pods de la couche | 4,4 Mio | 4,2 Mio | sans objet |
| M3, CPU des pods | 0,3 % | 0,2 % | sans objet |
| M5, image tirée à la création | oui | oui | sans objet |
| M6, sans mot de passe refusé ; `SET` et `GET` ; mot de passe dans une ligne de commande | oui ; oui ; 0 | oui ; oui ; 0 | sans objet |
| M7, retour à « prêt » | 2,2 s | 2,3 s | sans objet |
| M8, version servie | valkey 9.1.4 | redis 7.2.17 | sans objet |

[BENCH] Le nœud avec Valkey pèse moins que le nœud de base dans ce test :
c'est le bruit du nœud, que BENCH-011 a mesuré jusqu'à 58 Mio d'une
exécution à l'autre, alors que la couche ne pèse que 4 Mio par ses pods. M2
n'aura de sens qu'en médiane sur trois exécutions, et restera loin du seuil
de 512 Mio.

[BENCH] Série 1, lancée le 2026-11-24 à 00:51:53 UTC avec le script du commit
`14a4384`, verrou pris (dossier `series-1`). Le nœud de base, exécution 1, est
valide : 620,9 Mio au repos. L'exécution 1 de Valkey atteint « prêt » en
4,6 s, et M6 passe (refus sans mot de passe, `SET` et `GET`, 0 ligne de
commande). À 00:57:58 UTC, pendant le repos, `pmset -g log` note « Entering
Sleep state due to 'Clamshell Sleep' […] Using Batt (Charge:80%) » : le capot
est fermé et le Mac sur batterie. La machine alterne ensuite veille et
réveils de maintenance. Le script reprend pendant ces réveils, échoue sur
« Unable to connect to the server: net/http: TLS handshake timeout », puis
supprime le cluster et rend le verrou à 06:47:40 UTC. L'exécution de Valkey
est invalide, et la série n'a pas atteint Redis. Aucun résultat de cette
série n'est retenu, sauf M4, qui ne dépend pas de la machine.

[BENCH] Suite donnée. Le script du commit `1bcf41d` (SHA-256
`16daad12e24371de41ffdeff19cf518cc0200820045f1f945486939ee79bc62f`) garde le
Mac éveillé sur secteur pendant la série (`caffeinate -i -s`), et écrit la
ligne de `power.tsv` d'une exécution interrompue. Le réglage `sleep` du Mac
sur secteur vaut 1 minute (`pmset -g custom`) : sans cette assertion, une
veille sur inactivité restait possible. Elle n'empêche pas la veille capot
fermé [S46]. Le 2026-11-24 à 19:19:02 UTC, le Mac était sur batterie à 80 %, et le
script a refusé de démarrer, sans prendre le verrou ni créer de cluster. La
série se relance une fois le Mac sur secteur, capot ouvert : c'est la série
2, plus bas.

[BENCH] Relevés du SHA-256 de la section 4.1, faits dans le dossier de
travail de [BENCH] et déclarés ici, faute de témoin tiers :

| Relevé | Heure UTC | SHA-256 | Remarque |
| --- | --- | --- | --- |
| Écriture des seuils | 2026-11-21, 22:05 | sans objet | Texte écrit avant toute lecture web de cette passe |
| Premier relevé | 2026-11-22, 10:23:10 | `eed23fdd2a5af33f407d7ab0bc7a4eaedc6b4fc58ad1e396035e850c7597aefa` | La passe a été coupée par la limite d'usage entre l'écriture et ce relevé ; aucune lecture entre les deux. Le texte disait « relevé au même moment », ce qui n'était plus vrai |
| Relevé de référence | 2026-11-23, 20:37:31 | `67a35b6b52de50988ea2776a04b0a32208f107fd257598c72b2d90b8d7ae96f6` | Seule différence : la phrase sur le moment du relevé, corrigée. Toujours avant toute lecture web ou de registre |
| Vérification après la série 2 | 2026-11-25, 11:12:21 | `67a35b6b52de50988ea2776a04b0a32208f107fd257598c72b2d90b8d7ae96f6` | Inchangé. Texte identique à `section-4.1-2026-11-23.md` (`diff`) et à la section du commit d'ouverture (`6843021` après le rebase) |

[BENCH] La section entre dans le premier commit du rapport. L'horodatage
d'un commit local reste déclaratif tant que la branche n'est pas poussée.

#### Série 2, retenue (2026-11-25)

[BENCH] Série lancée le 2026-11-25 à 10:34:35 UTC et finie à 11:05:55 UTC,
soit de 11:34:35 à 12:05:55 à l'heure de Paris (`power.tsv`), avec le code
de retour 0 (dossier `series-2`, journal `series-2.out`). L'enveloppe
d'attente écrite par le DSI le 2026-11-24 (`series-wait.sh`) l'a lancée dès
que le Mac était sur secteur, capot ouvert, verrou libre ; son journal n'a
aucune ligne entre 23:29:39 UTC la veille et ce démarrage. Le script est
celui du commit `1bcf41d` : le fichier du dossier de travail, propre au début
de cette passe, a pour SHA-256 `16daad12…`. Réglages : `RUNS=3`,
`IDLE_WAIT=120` par défaut, verrou `bench-lock-s4`, `caffeinate -i -s` tenu.
Ordre : nœud de base, O1, O2, trois fois, 15 s de pause entre deux
exécutions.

[BENCH] Validité. Les neuf exécutions sont valides (`power.tsv`) : secteur du
début à la fin, batterie de 96 à 100 %, capot ouvert, aucune entrée `Sleep`.
Au démarrage, chaque tag désignait encore le condensat figé (`tag-matches`).
Aucun autre conteneur ni cluster kind ne tournait au début de chaque
exécution (`load.tsv`). Aucun conteneur de la couche n'a redémarré (colonne
`restarts` de `runs.tsv`). La charge de l'hôte sur une minute valait de 2,21
à 6,31 au début des exécutions 1 et 3, et de 6,01 à 11,13 au début des
exécutions 2, dont 11,13 pour Redis. Sur quinze minutes, elle descend de 7,96
au premier démarrage à 5,80 au dernier. La série 1 n'a aucune mesure valide
hors M4, et aucune de ses valeurs n'entre ci-dessous.

| Mesure | Option | Exécution 1 | Exécution 2 | Exécution 3 | Médiane | Écart |
| --- | --- | --- | --- | --- | --- | --- |
| Création du cluster, jusqu'au nœud et à `kube-system` prêts (sensibilité) | kind seul | 28,7 s | 27,4 s | 36,0 s | 28,7 s | 8,6 s |
| Création du cluster | O1. Valkey | 27,2 s | 27,1 s | 35,5 s | 27,2 s | 8,4 s |
| Création du cluster | O2. Redis 7.2 | 27,5 s | 27,3 s | 27,2 s | 27,3 s | 0,3 s |
| M1, installation jusqu'à « prêt » | O1. Valkey | 5,5 s | 6,5 s | 5,5 s | 5,5 s | 1,0 s |
| M1 | O2. Redis 7.2 | 5,5 s | 6,5 s | 4,4 s | 5,5 s | 2,1 s |
| Nœud au repos | O1. Valkey | 634,4 Mio | 644,6 Mio | 644,5 Mio | 644,5 Mio | 10,2 Mio |
| Nœud au repos | O2. Redis 7.2 | 594,1 Mio | 635,7 Mio | 580,2 Mio | 594,1 Mio | 55,5 Mio |
| M9, nœud de base | kind seul | 588,2 Mio | 610,1 Mio | 574,0 Mio | 588,2 Mio | 36,1 Mio |
| M2, couche au nœud | O1. Valkey | | | | 56,3 Mio | |
| M2 | O2. Redis 7.2 | | | | 5,9 Mio | |
| Somme des pods de la couche (sensibilité) | O1. Valkey | 6,4 Mio | 6,5 Mio | 6,2 Mio | 6,4 Mio | 0,3 Mio |
| Somme des pods | O2. Redis 7.2 | 4,3 Mio | 5,8 Mio | 5,8 Mio | 5,8 Mio | 1,5 Mio |
| M3, CPU des pods au repos | O1. Valkey | 0,2 % | 0,1 % | 0,2 % | 0,2 % | 0,1 % |
| M3 | O2. Redis 7.2 | 0,1 % | 0,1 % | 0,1 % | 0,1 % | 0,0 % |
| CPU du nœud au repos (sensibilité) | O1. Valkey | 3,9 % | 6,7 % | 7,0 % | 6,7 % | 3,1 % |
| CPU du nœud | O2. Redis 7.2 | 3,8 % | 6,2 % | 4,6 % | 4,6 % | 2,4 % |
| CPU du nœud | kind seul | 5,5 % | 8,0 % | 7,9 % | 7,9 % | 2,5 % |
| M7, retour à « prêt » après suppression du pod | O1. Valkey | 2,3 s | 2,2 s | 2,2 s | 2,2 s | 0,1 s |
| M7 | O2. Redis 7.2 | 2,1 s | 2,2 s | 2,2 s | 2,2 s | 0,1 s |

[BENCH] Sources : `runs.tsv` et `summary.tsv`. J'ai recalculé la somme des
pods et M3 depuis `idle-pods.tsv`, M7 depuis `pod-restart.tsv`, et chaque
médiane depuis `runs.tsv` : mêmes valeurs au dixième près. Chaque exécution
prend la médiane de ses trois échantillons, puis la série prend la médiane
des trois exécutions. Le pourcentage de CPU est celui d'un cœur.

[BENCH] M2 se lit en médianes, d'après la troisième règle de la GATE 1 :
médiane du nœud de l'option moins médiane du nœud de base (M9). Pour O1,
644,5 moins 588,2 font 56,3 Mio ; pour O2, 594,1 moins 588,2 font 5,9 Mio. La
somme des pods de la couche, lue par l'API Summary, va en sensibilité : 6,4
Mio pour O1, 5,8 pour O2.

[BENCH] Images retéléchargées (M5), d'après les événements `Pulled` de
`node-images.tsv`. À chaque exécution, le nœud neuf tire l'image de l'option
sur le réseau : un premier « Successfully pulled » en 2,5 à 2,6 s pour O1, en
2,3 à 2,5 s pour O2, puis un second de la même image, en 574 à 622 ms. Le
fichier ne rattache pas ces événements à leur conteneur. Les autres images
(kindnetd, local-path-provisioner, CoreDNS, kube-proxy) sont « already
present » : elles viennent de l'image du nœud. M5 vaut donc oui, 3 fois sur
3, pour chaque option.

[BENCH] Authentification (M6), 3 fois sur 3 pour chaque option (`auth.tsv`) :
`PING` sans mot de passe refusé ; `SET` puis `GET` réussis avec le mot de
passe ; aucune ligne de commande du conteneur du cache ne contient le mot de
passe. Après la suppression du pod (M7), la clé écrite en M6 est perdue 6
fois sur 6, comme le veut l'absence de persistance (`pod-restart.tsv`).
Version servie (M8), identique aux trois exécutions : `valkey` 9.1.4, de la
ligne 9.1 que Memorystore for Valkey sert par défaut [S18] ; `redis` 7.2.17,
de la ligne 7.2 que Memorystore for Redis sert par défaut [S24].

[BENCH] Quatre mesures à lire avec réserve. Aucune ne change une note.

1. M2 de O1. Les deux couches pèsent presque autant par leurs pods (6,4 et
   5,8 Mio), mais le nœud avec Valkey pèse 50,4 Mio de plus que le nœud avec
   Redis, en médianes. Les trois valeurs de O1 (634,4 à 644,6 Mio) dépassent
   le maximum du nœud de base (610,1) ; deux des trois valeurs de O2 tombent
   dans sa plage (574,0 à 610,1). L'écart entre le nœud et les pods vaut
   49,9 Mio pour O1, 0,1 Mio pour O2. Le script ne mesure pas où va cette
   mémoire (containerd, kubelet, serveur d'API) : la cause n'est pas établie.
   La charge de l'hôte ne l'explique pas : l'exécution 3 de O1, sous une
   charge de 2,21, donne 644,5 Mio. Exécution par exécution, contre le nœud
   de base de la même ronde, M2 vaut 46,2, 34,5 et 70,5 Mio pour O1, et 5,9,
   25,6 et 6,2 Mio pour O2. M2 de O2 tient dans le bruit du nœud de base,
   dont l'écart vaut 36,1 Mio. La plus haute valeur, 70,5 Mio, fait 13,8 %
   du seuil de 512 Mio.
   Précisions de [FINOPS], 2026-11-25. Les 70,5 Mio sont l'écart d'une même
   ronde ; le majorant de la règle de BENCH-013 (nœud d'option le plus haut
   moins nœud de base le plus bas) vaut 70,6 Mio pour O1 (644,6 moins 574,0).
   Les bornes se recouvrent : O1 entre 24,3 et 70,6 Mio, O2 entre moins 29,9
   et 61,7 Mio. Le script écrit seulement la médiane des trois échantillons de
   nœud de chaque exécution (`runs.tsv`), pas les échantillons : les médianes
   d'exécution ne peuvent pas être refaites, contrairement aux pods
   (`idle-pods.tsv`). Hypothèse de [FINOPS], non mesurée : le cache de pages
   actif et la mémoire du noyau, comptés par `docker stats` au nœud et
   absents des pods [S47] ; Valkey est le nœud le plus lourd des trois
   rondes, une chance sur 27 si l'ordre était aléatoire, et le protocole a un
   ordre fixe.
2. M1 et sa résolution. Les six valeurs se rangent sur trois niveaux, 4,4,
   5,5 et 6,5 s, espacés d'environ une seconde, le pas de la sonde. Les deux
   options ont la même médiane, 5,5 s, et leur écart est sous la résolution
   de la mesure. Les exécutions 2, les plus chargées, donnent 6,5 s aux deux.
3. Création du cluster. Les exécutions 3 du nœud de base et de O1 prennent
   36,0 et 35,5 s, contre 27,1 à 28,7 s pour les sept autres. Pour
   l'exécution 3 de O1, les événements `Pulled` listent aussi les images du
   plan de contrôle (etcd, kube-apiserver, kube-controller-manager,
   kube-scheduler), absentes des cinq autres exécutions avec couche. La cause
   n'est pas établie. Aucun seuil ne porte sur ce temps, et M1 ne commence
   qu'après la création.
4. CPU du nœud. Le nœud avec la couche consomme moins que le nœud de base, en
   médianes 6,7 % et 4,6 % contre 7,9 % : le bruit dépasse la couche
   elle-même (0,2 et 0,1 %). Aucun seuil ne porte sur la CPU.

## 5. Notation par critère

[BENCH] Chaque option retenue reçoit une note entière de 0 à 5 sur chaque
critère. Les points valent note × poids / 5. Un cran de note vaut donc 3
points sur un critère de poids 15, 2 points sur un poids 10 et 1 point sur le
coût. Les poids sont ceux de la section 8 du brief et ne changent pas d'un
rapport à l'autre.

| Note | Sens |
| --- | --- |
| 5 | Répond pleinement au critère, preuve directe |
| 4 | Répond, avec une réserve mineure écrite |
| 3 | Répond en partie, la réserve demande une action |
| 2 | Répond mal, il faut contourner |
| 1 | Répond à peine |
| 0 | Ne répond pas |

- Chaque note cite au moins une source [Sn] ou une mesure [Mn]. Une note sans
  preuve n'entre pas dans la grille, et le rapport reste en brouillon tant
  qu'elle manque.
- Un critère qui ne départage pas les options reçoit la même note pour
  toutes, avec la raison écrite.
- Une option éliminée à la section 3 n'est pas notée.

[BENCH] Notes de lecture du 2026-11-23, sur 90, complétées le 2026-11-25 par
l'empreinte mesurée (section 5.6). Chaque option est notée comme un couple,
le moteur sur `local` et sa variante de Memorystore sur `gcp`. Une seule note
a changé depuis la lecture : la maturité de Redis 7.2, de 5 à 4, sur la
relecture de [SECU] (section 5.3, correction appliquée).

### 5.1 Licence et liberté d'usage, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. Valkey | 5/5 | 15 | BSD-3-Clause, approuvée par l'OSI, pour le moteur et pour l'image ; aucun changement de licence depuis la création du dépôt, le 2024-03-22. La marque appartient à LF Projects | [S1], [S6], [S7], [S17] |
| O2. Redis 7.2 | 3/5 | 9 | La ligne 7.2 reste sous BSD-3-Clause jusqu'à sa fin, le 2029-12-01. La réserve demande une action : Redis a changé de licence deux fois, en 2024 vers RSALv2 ou SSPLv1, non libres, puis en 2025 vers un triple choix qui ajoute l'AGPLv3. Le blueprint doit plafonner l'image à la ligne 7.2, alors que les tags `7` et `latest` désignent 7.4.12 et 8.12.0, et la sortie de 7.2 imposera un choix de licence ou de moteur | [S9], [S11], [S12], [S14], [S17] |

### 5.2 Gouvernance (fondation, multi-vendeurs), poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. Valkey | 5/5 | 15 | Projet de LF Projects, « backed by the Linux Foundation ». Le comité technique réunit les neuf mainteneurs, chez huit organisations (Amazon deux fois, Tencent, Apple, Percona, Google, Oracle, Alibaba, Ericsson), et une organisation n'y dépasse pas un tiers. 184 auteurs en 12 mois ; les auteurs du top 10 qui déclarent AWS font 32 % des commits. L'image est tenue par le projet lui-même | [S4], [S6], [S7], [S30] |
| O2. Redis 7.2 | 2/5 | 6 | Éditeur unique, Redis Ltd. Chaque contribution passe par un accord de licence qui a permis les deux changements. Les huit mainteneurs de l'image officielle sont tous en `@redis.com`. 127 auteurs en 12 mois ; les auteurs du top 10 qui déclarent Redis font 30 % des commits, et quatre du top 10 ne déclarent pas d'employeur. Le principe V demanderait un ADR pour justifier l'écart | [S9], [S14], [S30] |

### 5.3 Maturité et adoption, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. Valkey | 4/5 | 12 | Code issu de Redis 7.2.4 ; première version GA, 7.2.5, le 2024-04-16. Google le sert en GA dans Memorystore depuis le 2025-04-02, et 9.1 y est la version par défaut. La page du projet liste 23 organisations participantes. Politique de support écrite : trois ans de maintenance par mineure, cinq ans de sécurité pour la dernière mineure de chaque majeure. Réserve : projet de deux ans et huit mois, liste de participants déclarative, aucun niveau de maturité de fondation | [S3], [S6], [S18], [S40] |
| O2. Redis 7.2 | 4/5 | 12 | Dépôt créé en 2009 ; ligne 7.2 en « Extended », maintenue jusqu'au 2029-12-01, servie par défaut par Memorystore for Redis. Réserve (correction de [SECU], 2026-11-25) : le 5 revient aux projets gradués à la CNCF qui tiennent une liste d'adoptants (Cilium, Argo CD, Flux) et à minikube ; un projet sans fondation, sans liste d'adoptants tenue par lui-même, a reçu 4 (k3d, Traefik, Config Sync, Mailpit). Redis 7.2 n'a pas de liste d'adoptants : l'âge du dépôt, la ligne Extended et Memorystore ne suffisent pas à la règle de BENCH-013 | [S9], [S12], [S24] |

### 5.4 Activité et maintenance, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. Valkey | 5/5 | 10 | 973 commits humains en 12 mois ; cinq lignes corrigées le même jour, le 2026-11-18 (9.1.4, 9.0.8, 8.1.12, 8.0.13, 7.2.16), puis 9.2.0 le 2026-11-19 ; cinq releases de la ligne 9.1 depuis le 2026-05-19 | [S2], [S30] |
| O2. Redis 7.2 | 4/5 | 8 | 637 commits humains en 12 mois ; cinq releases de la ligne 7.2 dans la même période, de 7.2.13 à 7.2.17. Réserve : la ligne 7.2 ne reçoit que les correctifs de sécurité et les corrections critiques ; le travail du projet porte sur la ligne 8, sous une autre licence | [S10], [S12], [S30] |

### 5.5 Sécurité (CVE, réactivité), poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. Valkey | 3/5 | 6 | Neuf avis en 12 mois, huit élevés et un moyen, chacun corrigé par une release de chaque ligne maintenue ; quatre releases de sécurité pour la ligne 9.1. Signalement privé, divulgation coordonnée avec une liste d'éditeurs. La réserve demande une action : Trivy 0.76.2 ne voit pas le moteur, compilé depuis les sources hors de tout gestionnaire de paquets (23 paquets d'Alpine, aucun paquet `valkey`), et aucun des douze avis, neuf de Valkey et trois de Redis, n'est dans la base mondiale de GitHub, dont trois sans CVE (correction de [SECU], 2026-11-25) ; une seconde source par la CPE du SBOM embarqué (`cpe:2.3:a:lfprojects:valkey:9.1.4`) se heurte au retard de NVD, CVE-2026-63639 y étant « Awaiting Analysis » le 2026-11-25. Les six avis qui touchent la ligne 9.1 sont corrigés au plus tard par la 9.1.4 et demandent tous un client authentifié. L'image n'a ni provenance ni signature (index sans manifeste d'attestation, aucun tag `sha256-*`, API d'attestations à 404), et la dérogation de l'ADR-012 ne la couvre pas, puisqu'elle sort du programme d'images officielles | [S2], [S5], [S7], [S38], [S42], [S53], [S54], [S55], [S56], [S57], [S66] |
| O2. Redis 7.2 | 3/5 | 6 | Quatre releases de sécurité de la ligne 7.2 en 12 mois, dont trois CVE publiées par avis le 2026-05-05. Le 2026-10-26, Redis et Valkey corrigent le même jour une faille de même description, un dépassement de tampon sur un `PUBLISH` relayé par le bus du cluster. Signalement par un programme de divulgation ou par GitHub. La réserve demande une action : les correctifs de 7.2.15, 7.2.16 et 7.2.17 n'ont ni avis ni CVE, d'où une veille des notes de version. Même angle mort que Valkey (correction de [SECU], 2026-11-25) : Trivy 0.76.2 ne voit pas le moteur dans l'image (20 paquets d'Alpine, aucun paquet `redis`), et aucun des trois avis n'est dans la base mondiale ; ils demandent un client authentifié. L'image officielle n'a pas de signature vérifiable, couverte par la dérogation de l'ADR-012 | [S2], [S5], [S10], [S13], [S42], [S53], [S54] |

[BENCH] Le contrôle de M6 (mot de passe imposé, absent des lignes de
commande) vaut pour les deux options, avec les mêmes manifests : il confirme
la mise en œuvre, il ne départage pas les moteurs. Un échec chez une seule
option ferait baisser sa note. La série 2 le confirme : M6 passe 3 fois sur
3 pour chaque option (section 4.4), et les notes restent à 3/5.

### 5.6 Empreinte sur PC (RAM, CPU, démarrage), poids 10

[BENCH] Règle de `TEMPLATE.md` (section 5.6), seuils écrits et hachés en 4.1
avant toute mesure : chaque option part de 5 et perd un cran par seuil
dépassé. Règles de la GATE 1 : volume lu sur l'amd64 (première), couche
notée contre ses propres seuils (deuxième), mémoire lue au nœud moins le
nœud kind seul, en médianes (troisième). Mesures de la série 2 du
2026-11-25 (section 4.4).

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. Valkey | 4/5 | 8 | Un seuil dépassé : image retéléchargée à chaque création, 3 fois sur 3 (seuil 2). 18,8 Mo en amd64, 16,7 % du seuil 1 ; prête en 5,5 s, 6,1 % du seuil 3 ; 56,3 Mio au nœud, 11,0 % du seuil 4 (pod de 6,4 Mio) | [M1], [M2], [M4], [M5] |
| O2. Redis 7.2 | 4/5 | 8 | Un seuil dépassé : image retéléchargée à chaque création, 3 fois sur 3 (seuil 2). 16,0 Mo en amd64, 14,2 % du seuil 1 ; prête en 5,5 s, 6,1 % du seuil 3 ; 5,9 Mio au nœud, 1,2 % du seuil 4, dans le bruit du nœud de base (pod de 5,8 Mio) | [M1], [M2], [M4], [M5] |

[BENCH] Le critère ne départage pas les options, comme l'annonçait la
lecture provisoire du 2026-11-24 : chacune perd le seul cran du
retéléchargement, commun à toute image que tire un nœud neuf sans miroir.
Aucune option n'est à moins de 10 % d'un seuil chiffré ; la plus proche est
O1, à 16,7 % du seuil de volume. Le seuil 2 se lit par oui ou non.

[BENCH] Sensibilité. La somme des pods à la place du nœud (6,4 et 5,8 Mio)
ne franchit aucun seuil. M2 lu exécution par exécution non plus : au plus
70,5 Mio pour O1 (écart d'une même ronde), 13,8 % du seuil 4 ; le majorant de
la règle de BENCH-013, nœud d'option le plus haut moins nœud de base le plus
bas, vaut 70,6 Mio pour O1 et 61,7 pour O2, soit 13,8 % et 12,1 %
(correction de [FINOPS], 2026-11-25). L'écart de 50,4 Mio entre les nœuds des
deux options, sans cause établie (section 4.4, point 1), reste sans effet sur
la note. Avec le miroir zot de l'ADR-011, si le seuil 2 se lit comme un
retéléchargement depuis Internet, les deux options regagnent un cran, 5/5 :
le classement ne change pas (section 7). Cumul avec la plate-forme de base,
en sensibilité (deuxième règle) : 524,6 Mo pour O1 et 521,8 Mo pour O2,
au-dessus des 500 Mo tous les deux. Avec la base mesurée avec le miroir zot
(583,5 Mo, BENCH-010) : 602,3 et 599,5 Mo, même effet (correction de
[FINOPS], 2026-11-25).

### 5.7 Portabilité multi-cloud, poids 10

[BENCH] La note mesure trois choses : le même moteur et la même ligne sur les
deux cibles (ENF-02), le contrat du Secret `cache-auth` tenu sur les deux
(ADR-007, condition 5), et ce que la couche `gcp` doit ajouter au socle de
l'ADR-008.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. Valkey | 4/5 | 8 | Même moteur et même ligne 9.1 sur les deux cibles. Le jeton de Memorystore tient le contrat `cache-auth`, une valeur passée à `AUTH`. Réserve : la couche `gcp` passe par Private Service Connect, que le socle de l'ADR-008 n'a pas, et la ressource OpenTofu qui lit le jeton n'est pas publiée au 2026-11-23. L'authentification IAM éviterait tout secret statique, mais demande un code client propre à `gcp` | [S18], [S20], [S21], [S22], [S28], [S43] |
| O2. Redis 7.2 | 4/5 | 8 | Même moteur et même ligne 7.2 sur les deux cibles ; chaîne AUTH lue par un attribut déjà mesuré dans le socle de l'ADR-008, contrat `cache-auth` tenu. Réserve : Memorystore affiche le correctif 7.2.0, dix-sept correctifs derrière 7.2.17, et ne sert rien au-delà de 7.2 ; la parité tient tant que le PC reste lui aussi sur une ligne figée | [S24], [S25], [S26], [S28], [S43] |

[BENCH] Le critère ne départage pas les options : chacune perd un cran pour
une réserve différente, la couche réseau et le jeton pour Valkey, le
correctif affiché et le plafond de version pour Redis.

### 5.8 Expérience dev et documentation, poids 10

[BENCH] Note de jugement. L'essai qui la fonde : la série 2 du 2026-11-25,
trois exécutions par option, M1, M6 et M7 sans intervention (section 4.4).

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. Valkey | 4/5 | 8 | Mêmes manifests, même forme de configuration et même variable client que Redis ; le fichier de configuration du dépôt documente chaque directive. Prête sans intervention 3 fois sur 3, M6 passé 3 fois sur 3, de retour en 2,2 s après la suppression du pod, aucun redémarrage. Réserve : documentation de Memorystore for Valkey récente sur l'authentification (GA le 2026-09-18) | [M1], [M6], [M7], [S19], [S36] |
| O2. Redis 7.2 | 4/5 | 8 | Même forme ; `redis.conf` du tag 7.2.17 documente chaque directive. Prête sans intervention 3 fois sur 3, M6 passé 3 fois sur 3, de retour en 2,2 s, aucun redémarrage. Réserve : le projet écrit « We strongly recommend using the latest available version », soit la ligne 8 | [M1], [M6], [M7], [S12], [S37] |

[BENCH] Le critère ne départage pas les options. L'essai donne les mêmes
résultats aux deux : même médiane de M1, même M7 au dixième près, même M6. Les
deux serveurs partagent l'aide, les directives et le client utilisés par le
script [S36], [S37].

### 5.9 Coût (managé ou opérationnel), poids 5

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. Valkey | 4/5 | 4 | Aucune licence ni service payant sur le PC. Sur `gcp`, grilles de prix illisibles le 2026-11-23 et le 2026-11-25. Mode de facturation lu (correction de [FINOPS], 2026-11-25) : par nœud et par heure, un réplica doublant la facture d'une instance à une partition ; engagements à 20 % (un an) et 40 % (trois ans), payés chaque heure et non annulables, hors stockage, sauvegardes, persistance et sortie de données. Plus petit nœud : `shared-core-nano`, réservé au développement, et `custom-pico` avec SLA. Postes non lus : point de terminaison Private Service Connect, trafic qui le traverse, stockage des sauvegardes. Réserve : prix à lire avec la région par Lucas (R-05) | [S23], [S29], [S48], [S49], [S50] |
| O2. Redis 7.2 | 4/5 | 4 | Aucune licence ni service payant sur le PC. Sur `gcp`, grille illisible (404 le 2026-11-23), même réserve | [S29] |

[BENCH] Le critère ne départage pas les options : aucune n'a de prix lu, et
le coût de sortie de la ligne 7.2 est déjà compté en licence (5.1). [FINOPS]
confirme 4/5 pour les deux ; la réserve passe de « prix illisibles » à
« prix à lire avec la région ».

## 6. Grille pondérée

[BENCH] Grille du 2026-11-25, sur 100, après les relectures. L'empreinte
vient de la série 2 (section 5.6) ; les autres notes sont celles du
2026-11-23, et seules les justifications de 5.5 et de 5.8 reçoivent le
résultat de la série, sans changement de note. Seule la maturité de Redis 7.2
change, de 5 à 4, sur la relecture de [SECU] : 69 au lieu de 72.

| Critère | Poids | O1. Valkey | O2. Redis 7.2 |
| --- | --- | --- | --- |
| Critères éliminatoires (section 3) | éliminatoire | passe | passe |
| Licence et liberté d'usage | 15 | 5/5, 15 pts | 3/5, 9 pts |
| Gouvernance (fondation, multi-vendeurs) | 15 | 5/5, 15 pts | 2/5, 6 pts |
| Maturité et adoption | 15 | 4/5, 12 pts | 4/5, 12 pts |
| Activité et maintenance | 10 | 5/5, 10 pts | 4/5, 8 pts |
| Sécurité (CVE, réactivité) | 10 | 3/5, 6 pts | 3/5, 6 pts |
| Empreinte sur PC (RAM, CPU, démarrage) | 10 | 4/5, 8 pts | 4/5, 8 pts |
| Portabilité multi-cloud | 10 | 4/5, 8 pts | 4/5, 8 pts |
| Expérience dev et documentation | 10 | 4/5, 8 pts | 4/5, 8 pts |
| Coût (managé ou opérationnel) | 5 | 4/5, 4 pts | 4/5, 4 pts |
| Total | 100 | 86 / 100 | 69 / 100 |

## 7. Verdict proposé

[BENCH] Proposition : O1, Valkey 9.1.4, à 86 sur 100, devant Redis 7.2.17 à
69. L'écart de 17 points vient tout entier des notes de lecture : l'empreinte,
mesurée par la série 2, donne 4/5 aux deux options. Elle ne pourrait pas
l'inverser : même à 0/5 pour O1 et 5/5 pour O2, il resterait 78 contre 71.
Avant la relecture de [SECU], la maturité de Redis valait 5 et le total 72,
soit 14 points d'écart.

[BENCH] Pourquoi. L'écart vient de la licence (6 points), de la gouvernance
(9 points) et de l'activité (2 points) ; la maturité, à 4/5 chacune, ne
départage plus. Valkey est sous BSD-3-Clause, porté par LF Projects, avec un
comité où aucune organisation ne dépasse un tiers [S4], [S6]. Redis 7.2
garde la BSD-3-Clause, mais sur une ligne figée que l'éditeur a déjà quittée
deux fois par un changement de licence [S9], [S11]. Le principe V tranche
dans le même sens que la grille.

[BENCH] Sensibilité, sur 100 :

| Lecture | O1 | O2 | En tête | Règle |
| --- | --- | --- | --- | --- |
| Grille (section 6) | 86 | 69 | O1 | Sans objet |
| Licence de O2 à 4 (la ligne 7.2 seule compte) | 86 | 72 | O1 | Aucune contredite : jugement sur la trajectoire |
| Gouvernance de O2 à 3 (127 auteurs) | 86 | 72 | O1 | Aucune contredite : jugement |
| Les deux à la fois, et maturité de O1 à 3 | 83 | 75 | O1 | Aucune contredite : trois jugements |
| O2 en Redis 8.12 sous AGPLv3 | 86 | parité perdue face à Memorystore (7.2) | O1 | Contredit la condition 3 de la section 2 et la décision du DSI sur la ligne locale |
| Empreinte au pire pour O1 (0/5) et au mieux pour O2 (5/5) | 78 | 71 | O1 | Contredit les mesures de la série 2 ; borne de ce que le critère peut changer |
| Somme des pods à la place du nœud (6,4 et 5,8 Mio), ou M2 exécution par exécution (au plus 70,5 Mio) | 86 | 69 | O1 | Contredit la troisième règle de la GATE 1 ; aucun seuil franchi, même effet |
| Miroir zot de l'ADR-011 : seuil 2 lu comme un retéléchargement depuis Internet ; docker.io servi pour les deux | 88 | 71 | O1 | Contredit la lettre du seuil 2, mesuré sans miroir |
| Volume cumulé avec la plate-forme de base (505,8 Mo, BENCH-011) contre 500 Mo : 524,6 et 521,8 Mo | 86 | 69 | O1 | Contredit la deuxième règle de la GATE 1 ; les deux sont au-dessus, même effet |

[BENCH] Aucune lecture n'inverse le classement. Pour que Redis 7.2 passe
devant, il faudrait au moins six crans de note contre O1, tous sur des
critères de poids 15 : l'écart vaut 17 points, et un cran en vaut au plus 3
(cinq crans pour un écart de 14, avant la correction de maturité).

[BENCH] Cumul avec le premier `task up` (R-04), pour [FINOPS]. La stack de
BENCH-005, comptée dans R-04, contient déjà `valkey/valkey:9.1.4-alpine`
(18,8 Mo en amd64) : O1 ne change rien au volume du premier lancement, et O2
le réduirait de 2,8 Mo (16,0 au lieu de 18,8). Chiffres de [FINOPS], 2026-11-25
(correction demandée) : le premier `task up` du profil standard reste à
1 802,1 Mo avec O1 (160,2 % du budget de 900 s à 10 Mbit/s, 16,0 Mbit/s au
minimum) et passe à 1 799,3 Mo avec O2 (159,9 %). Le profil lite, sans Flux
(ADR-010), Keycloak ni Mailpit, vaut 1 263,8 Mo avec zot : 1 011,0 s à
10 Mbit/s, 112,3 % du budget, 11,2 Mbit/s au minimum pour le seul
téléchargement ; calcul de [FINOPS] sur des séries de jours différents, un
ordre de grandeur. Le cache pèse 18,8 Mo là-dedans, 1,7 % du budget : même
sans cache, le lite resterait à 110,7 %, et le choix du moteur ne peut ni
faire tenir ni faire manquer le critère des 15 minutes. Plancher mémoire, par
la méthode de BENCH-005 et le majorant : le lite reste à 2,0 Gio de VM et
6,0 Gio de portable, avec 108 à 122 Mio avant le palier suivant ; le standard
à 3,5 Gio de VM et 7,5 Gio de portable, avec 8 à 23 Mio avant le palier de
4,0 Gio, qui tient encore sur 8 Gio. Le moteur ne décide aucun de ces
paliers : Valkey est déjà dans les planchers de l'ADR-012 et de BENCH-013.

[BENCH] Gouvernance : l'option proposée ne dépend pas d'un éditeur unique.
Sur `gcp`, Memorystore reste un service de Google seul, comme toute cible
managée (lecture de l'ADR-009).

[BENCH] Réserves. L'image `valkey/valkey` n'a ni signature ni provenance, et
sort de la dérogation de l'ADR-012 : il lui faut sa propre dérogation à
ENF-03, ou une autre voie (question 3). La ligne 9.2 est sortie le
2026-11-19, et Memorystore ne la sert pas : la ligne locale suit celle de
Memorystore, pas la dernière du projet. Le DSI l'a décidé en session 4,
décision transmise à [BENCH] le 2026-11-25 : la version locale suit la ligne
que Memorystore sert par défaut, 9.1 au 2026-11-23 [S18]. Prochaine
vérification : à la sortie d'une ligne 9.2 dans Memorystore, ou au plus tard
le 2027-05-23.

[BENCH] Conditions proposées pour l'ADR, avant les relectures et corrigées
selon leurs demandes (conditions 2, 3 et 5). Les conditions complètes de
[SECU] (1 à 8) et de [FINOPS] (1 à 7) figurent en section 10 ; l'ADR-015
reprend celles-ci. Chacune est vérifiable par la matrice (principe I) :

1. Ligne commune. La ligne de Valkey est celle que Memorystore sert par
   défaut, relevée à chaque release du blueprint et tenue en une seule valeur
   pour les deux couches, comme la majeure de Postgres dans l'ADR-012.
   Contrôle : la matrice compare `valkey_version` (M8) à cette valeur.
2. Image et durcissement. Image par condensat, Deployment d'une réplique sans
   persistance, profil `restricted`, configuration écrite depuis le Secret par
   un conteneur d'initialisation, comme dans le script. Contrôle : la matrice
   rejoue M6, et échoue si un manifest porte le mot de passe dans `command`,
   `args` ou `env` du serveur. Ajout demandé par [SECU] : une ACL sur le compte
   `default` (`-@admin` et le refus des commandes que Memorystore bloque) à la
   place de `requirepass`, le conteneur d'initialisation n'écrivant que
   l'empreinte SHA-256 du mot de passe (condition 4 de [SECU], section 10).
3. Secret `cache-auth`, type `Opaque`, clé `password`, sur les deux cibles. Sur
   `gcp`, `authorization_mode = "TOKEN_AUTH"` ; le producteur du Secret
   attend la ressource `google_memorystore_auth_token` dans une version
   publiée du provider, et le jeton tombe dans l'état chiffré (condition 2 de
   l'ADR-008). L'authentification IAM reste une évolution, avec son propre
   ADR, puisqu'elle change le code client sur `gcp`. Ajouts demandés par
   [SECU] : `transit_encryption_mode = "SERVER_AUTHENTICATION"` dès la
   création, l'attribut étant immuable ; la rotation par les deux jetons de
   chaque utilisateur ; et les contrôles conftest de la condition 7 de [SECU]
   (autre mode d'autorisation, `TRANSIT_ENCRYPTION_DISABLED` et mot de passe en
   clair dans une règle `acl_policy` refusés).
4. Réseau `gcp` : une politique de connexion de service pour
   `gcp-memorystore`, et les ports de la section 3 ouverts au seul cluster
   GKE. [OPS] l'écrit, [SECU] relit.
5. Mode sans cluster (`CLUSTER_DISABLED`), zéro réplica, un nœud de type
   `shared-core-nano` en dev et pour la démo (`custom-pico` seulement avec un
   besoin de SLA), la politique conftest de l'ADR-008 sur le tier s'étendant
   au type de nœud et au nombre de réplicas (condition 5 de [FINOPS]).

[BENCH] Suites. Les relectures [SECU] et [FINOPS], l'arbitrage du DSI, puis
l'ADR de [ARCHI]. Une entrée `redis` au catalogue (ADR-009) : ligne `local`
en `oss`, « Valkey, image `valkey/valkey` dans un Deployment de la couche
`local` », BSD-3-Clause, gouvernance `foundation` (LF Projects), statut actif,
sources [S1], [S3], [S6] ; ligne `gcp` en `managed`, Memorystore for Valkey
[S18]. Standard exposé : `resp`.

### Arbitrage du DSI

[DSI] Arbitrage du 2026-11-25, après les relectures de [SECU] et de
[FINOPS]. Valkey 9.1.4 est retenu comme moteur du cache, à 86 sur 100 contre
69 pour Redis 7.2.17, dans la grille corrigée. La version locale suit la
ligne que Memorystore sert par défaut, 9.1 : c'est la décision de la
session 4, que le rapport applique. Sur `gcp`, la variante est Memorystore
for Valkey.

[DSI] Grille. Les deux relectures sont acceptées. Aucune note ne change, sauf
la maturité de Redis 7.2, ramenée de 5 à 4 par [SECU] selon la règle de
BENCH-013 : 72 devient 69, et l'écart passe de 14 à 17 points. Les
corrections de [FINOPS] portent sur des chiffres et des phrases, pas sur des
notes.

[DSI] Une couche dans le bruit du nœud. Question ouverte depuis BENCH-013,
tranchée : le majorant (nœud d'option le plus haut moins nœud de base le plus
bas) compte pour la note ; la mémoire du pod compte pour le dimensionnement.
La règle vaut pour les rapports à venir. Pas de deuxième palier de volume
dans le gabarit, sur l'avis de [FINOPS] : les volumes de couche des quatre
rapports ne présentent aucune coupure naturelle, et le budget par étape
d'ENF-01 fait mieux le travail (R-04).

[DSI] Écart de 50 Mio de M2. L'hypothèse de [FINOPS] est retenue : le cache du
noyau, compté au nœud par `docker stats` et absent des pods. Elle n'a aucun
effet sur la note, aucune valeur possible n'étant à moins de 10 % du seuil de
512 Mio. Elle se mesure (`memory.stat` du nœud, témoins sans serveur, ordre
permuté) si une couche future frôle un seuil ; pas avant.

[DSI] Suites portées par l'ADR-015, que [ARCHI] écrit. Un : le jeton de
Memorystore pour le MVP, l'authentification IAM en évolution avec son propre
ADR. Deux : une dérogation datée à ENF-03 pour `docker.io/valkey/valkey`, sur
le modèle de l'ADR-014, texte proposé par [SECU], avec le contrôle des trois
registres à chaque condensat neuf. Trois : une ACL et une NetworkPolicy sur
`local`, le compte `default` plus strict que sur Memorystore. Quatre :
`VALKEY_EXTRA_FLAGS` refusé par le contrôle statique du rendu. Cinq : le
dimensionnement de [FINOPS], sur `local` comme sur `gcp`. Six : `foobared` et
`password123` ajoutés à la liste des valeurs connues de l'ADR-007 (R-20). Les
conditions 1 à 8 de [SECU] et 1 à 7 de [FINOPS], en section 10, sont reprises
telles quelles, sauf contre-ordre de [ARCHI] ou de Lucas.

[DSI] Ticket amont. Le ticket que [SECU] propose chez `valkey-container`
(demande de signature ou d'attestation de l'image) n'est pas ouvert : c'est
une action publique, laissée à Lucas.

[DSI] R-04. Selon le calcul de [FINOPS], le profil lite pèse environ 112 % du
budget de 900 s à 10 Mbit/s. Le point est reporté à R-04. Il ne change rien
au choix du moteur : sans cache, le lite resterait à environ 111 %.

## 8. Limites et biais

| Limite | Effet possible sur le verdict | Ce qui la lèverait |
| --- | --- | --- |
| Série 1 interrompue le 2026-11-24 par une veille capot fermé, sur batterie | Aucun : aucune de ses valeurs n'entre dans la note, sauf M4, identique à l'octet près dans la série 2 | Levée par la série 2 du 2026-11-25, au protocole |
| Test de fumée à repos raccourci (30 s au lieu de 120) | Aucun : ses valeurs restent indicatives et n'entrent pas dans la note | Levée par la série 2, à 120 s |
| Bruit du nœud plus grand que la couche (6 Mio par les pods) : M9 varie de 36,1 Mio, le nœud avec Redis de 55,5 Mio, et le nœud avec Valkey pèse 50,4 Mio de plus que celui avec Redis sans cause établie | M2 de O2 (5,9 Mio) tient dans le bruit, et celui de O1 (56,3 Mio) n'est pas expliqué par ses pods ; aucune incidence sur la note, au plus 13,8 % du seuil de 512 Mio (bornes de [FINOPS] : O1 de 24,3 à 70,6 Mio, O2 de moins 29,9 à 61,7). Les trois échantillons du nœud de chaque exécution ne sont écrits dans aucun TSV, seule leur médiane l'est : les médianes d'exécution ne se refont pas. Le protocole a un ordre fixe (base, O1, O2), qui ne sépare pas l'effet de l'option de celui de son prédécesseur. Hypothèse retenue par le DSI, non mesurée : cache du noyau compté au nœud | `memory.stat` du nœud et RSS par processus à chaque échantillon, témoins sans serveur, ordre permuté, au moins cinq exécutions, échantillons du nœud écrits en TSV, si une couche future frôle un seuil |
| M1 relevé par une sonde par seconde, par `kubectl exec` | Écart entre les options sous la résolution (valeurs sur 4,4, 5,5 et 6,5 s) ; sans effet, à 6,1 % du seuil de 90 s | Sonde plus fine, utile seulement près d'un seuil |
| Charge de l'hôte plus haute aux exécutions 2 (6,01 à 11,13 sur une minute) | Les exécutions 2 donnent le M1 le plus long aux deux options, et le nœud le plus lourd au nœud de base et à Redis | Série sur un poste sans autre activité |
| Création du cluster plus longue de 8 s aux exécutions 3 du nœud de base et de O1, cause non établie | Aucun : aucun seuil ne porte sur ce temps, et M1 commence après | Relever les redémarrages du plan de contrôle à chaque exécution |
| Le script n'écrit pas son propre SHA-256 dans `versions.tsv` | La version du script de la série 2 repose sur l'état du dossier de travail relu après coup (`16daad12…`) | Écrire le SHA-256 du script dans `versions.tsv` au démarrage |
| Heure de la série : le journal `series-2.out` et `attempts.log` sont en UTC, `power.tsv` en heure locale (UTC+1) | Une heure citée sans fuseau se lit faux d'une heure | Les heures de ce rapport sont en UTC, sauf mention |
| Condensat de O1 lu par un outil qui résume les pages | Une erreur de recopie | Recoupé avec le condensat de BENCH-005 ; le script refuse un condensat absent du registre |
| Seuils écrits le 2026-11-21, relevés le 2026-11-22 puis le 2026-11-23, après une coupure | L'antériorité des seuils repose sur la déclaration de [BENCH] | Pousser la branche, qui date le texte chez GitHub |
| Volumes de Valkey connus avant les seuils (BENCH-005, ADR-011) | Seuils taillés sur mesure | Seuils repris de BENCH-011 sans changement (section 4.1) |
| Employeurs déclarés sur les profils GitHub | Parts de AWS et de Redis approximatives ; quatre auteurs du top 10 de Redis sans employeur déclaré | Statistiques de la fondation, ou fichier de mainteneurs |
| Correctif servi par Memorystore non publié pour Valkey, affiché à 7.2.0 pour Redis | Parité de correctif inconnue sur `gcp` | Lire `INFO server` sur une instance, au premier apply de la GATE 2 |
| Grilles de prix de Memorystore illisibles le 2026-11-23 | Coût noté sans prix | Lecture par [FINOPS] ou par Lucas (R-05) |
| M6 (c) lit `/proc/[0-9]*/cmdline` dans l'espace de noms de processus du conteneur du cache, au moment du contrôle (correction de [SECU], 2026-11-25) | Trois lieux lui échappent : le conteneur d'initialisation, déjà terminé ; les environnements des processus (`/proc/*/environ`) ; le nœud (kubelet, containerd, volumes en mémoire où la valeur est en clair par construction). Un argument se lit dans le manifest rendu, ce que couvre le contrôle statique. Aucune incidence sur la note : le contrôle vaut pour les deux options. Sur le PC, lire le nœud demande d'être root dans la machine virtuelle de Docker, et le mot de passe local est jetable (R-20) | Le contrôle statique du rendu (`env` et `envFrom` refusés sur le conteneur du cache, `VALKEY_EXTRA_FLAGS` compris ; aucune option de mot de passe dans `command` ou `args`), et M6 (c) étendu à `/proc/*/environ` (condition 5 de [SECU]) |
| Trivy 0.76.2 ne voit le moteur dans aucune des deux images, compilé depuis les sources ; aucun des douze avis n'est dans la base mondiale de GitHub (R-36) | Le scan de FR-021 ne voit aucun avis du moteur, pour les deux options à égalité ; la note de sécurité ne départage pas | Lecture mensuelle des avis du dépôt par [SECU] ; seconde source par la CPE du SBOM embarqué, limitée par le retard de NVD et par les avis sans CVE |
| Option pressentie par le brief : Valkey | Aucune note ne lui donne d'avantage | Sans objet |

## 9. Sources

[BENCH] Lues le 2026-11-23, sauf mention, et S47 à S67 le 2026-11-25 (relectures de [FINOPS] et de [SECU]). Les fichiers de dépôt GitHub ont été
lus par l'API de GitHub (`gh api`), au tag ou au commit indiqué. Les comptes de
commits portent sur la branche par défaut, du 2025-11-23 au 2026-11-23, bots
exclus.

| ID | URL | Lue le | Ce que la source établit | Officielle |
| --- | --- | --- | --- | --- |
| S1 | <https://github.com/valkey-io/valkey> | 2026-11-23 | BSD-3-Clause, dépôt créé le 2024-03-22, non archivé, dernier push le 2026-11-23 | Oui |
| S2 | <https://github.com/valkey-io/valkey/releases> | 2026-11-23 | 9.2.0 le 2026-11-19 ; 9.1.4, 9.0.8, 8.1.12, 8.0.13 et 7.2.16 le 2026-11-18 ; 9.1.0 le 2026-05-19 ; 9.1.4 en urgence SECURITY (CVE-2026-130822) | Oui |
| S3 | <https://valkey.io/topics/releases/> | 2026-11-23 | Politique de support ; 9.1 maintenue jusqu'au 2029-05-19, sécurité jusqu'au 2031-05-19 ; 9.2 du 2026-11-19 | Oui |
| S4 | <https://github.com/valkey-io/valkey/blob/unstable/MAINTAINERS.md>, `GOVERNANCE.md` | 2026-11-23 | Neuf mainteneurs chez huit organisations ; comité technique formé des mainteneurs, une organisation au plus pour un tiers | Oui |
| S5 | <https://github.com/valkey-io/valkey/security/advisories>, `SECURITY.md` ; <https://github.com/redis/redis/security/advisories> | 2026-11-23 | Valkey : neuf avis en 12 mois, huit élevés, un moyen, trois sans CVE ; signalement à `security@lists.valkey.io`. Redis : trois avis le 2026-05-05, CVE-2026-25243, CVE-2026-23631, CVE-2026-23479 | Oui |
| S6 | <https://valkey.io/> | 2026-11-23 | « open source (BSD) », « backed by the Linux Foundation », marque de LF Projects ; 23 organisations participantes | Oui |
| S7 | <https://github.com/valkey-io/valkey-container> (`README.md`, `9.1/alpine/Dockerfile`, `docker-entrypoint.sh`, `.github/workflows/ci.yml`, `.github/actions/build-image/action.yml`) | 2026-11-23 | Image tenue par la communauté Valkey, publiée sur docker.io, ghcr.io et public.ecr.aws ; BSD-3-Clause ; alpine 3.24, UID 999, GID 1000, `tini` ; plates-formes amd64, arm64, arm/v7, ppc64le ; `provenance: false`, aucune signature | Oui |
| S8 | <https://hub.docker.com/v2/namespaces/valkey/repositories/valkey/tags/9.1.4-alpine>, idem `9.1.4-trixie` | 2026-11-23 | Condensats d'index `sha256:56729e68…b37893f0` et `sha256:3ab0eca8…41e81b0e` ; architectures du tag | Oui, lu par un outil qui résume |
| S9 | <https://github.com/redis/redis> (`LICENSE.txt` et son historique, `README.md`, `COPYING` au tag 7.2.17) | 2026-11-23 | Triple licence à partir de 8.0, AGPLv3 ajoutée le 2025-05-01, RSALv2 et SSPLv1 le 2024-03-20 ; 7.2.x sous BSD-3-Clause ; accord de licence des contributeurs ; dépôt créé le 2009-03-21, non archivé | Oui |
| S10 | <https://github.com/redis/redis/releases> | 2026-11-23 | 8.12.0 le 2026-11-22 ; 7.2.13 à 7.2.17 en 12 mois, 7.2.14 à 7.2.17 en urgence SECURITY ; seules les notes de 7.2.14 citent des CVE | Oui |
| S11 | <https://redis.io/legal/licenses/> | 2026-11-23 | 7.2 et avant sous BSD-3-Clause, 7.4 sous RSALv2 ou SSPLv1, 8 et après au choix RSALv2, SSPLv1 ou AGPLv3 ; « RSALv2 is not an open source license » | Oui |
| S12 | <https://redis.io/docs/latest/operate/oss_and_stack/install/version-mgmt/> | 2026-11-23 | 7.2 en « Extended », fin le 2029-12-01 ; définition des lignes Standard et Extended | Oui |
| S13 | <https://github.com/redis/redis/blob/unstable/SECURITY.md> | 2026-11-23 | 7.2.x « support extended till 7.4 end of support » ; signalement par le programme de divulgation ou par GitHub | Oui |
| S14 | <https://github.com/docker-library/official-images/blob/master/library/redis> | 2026-11-23 | Huit mainteneurs en `@redis.com` ; tags `7.2.17-alpine` et leurs architectures ; `7` désigne 7.4.12, `latest` 8.12.0 | Oui |
| S15 | <https://github.com/redis/docker-library-redis/tree/v7.2.17> (`alpine/Dockerfile`, `alpine/docker-entrypoint.sh`) | 2026-11-23 | BSD-3-Clause ; alpine 3.22, UID 999, GID 1000 | Oui |
| S16 | <https://github.com/docker-library/repo-info/blob/master/repos/redis/remote/7.2.17-alpine.md>, `7.2.17-bookworm.md` | 2026-11-23 | Condensats d'index `sha256:2f66de68…5aa1c335` et `sha256:5b816bb3…dca887962f`, commit du 2026-11-12 | Oui |
| S17 | <https://opensource.org/licenses> | 2026-11-23 | AGPL-3.0, BSD-3-Clause, MIT et LGPL-3.0 approuvées ; ni SSPL ni Business Source License | Oui |
| S18 | <https://docs.cloud.google.com/memorystore/docs/valkey/supported-versions> | 2026-11-23 | Valkey 7.2, 8.0, 9.0 et 9.1, 9.1 par défaut ; aucun correctif publié ; 9.2 absente | Oui |
| S19 | <https://docs.cloud.google.com/memorystore/docs/valkey/release-notes> | 2026-11-23 | 9.1 en GA le 2026-09-24 ; authentification par jeton en GA le 2026-09-18 ; politiques ACL le 2026-08-31 | Oui |
| S20 | <https://docs.cloud.google.com/memorystore/docs/valkey/manage-basic-auth> | 2026-11-23 | Jeton créé par le service ; utilisateur `default` et `AUTH <jeton>` ; deux jetons au plus ; TLS recommandé | Oui |
| S21 | <https://docs.cloud.google.com/memorystore/docs/valkey/about-iam-auth> | 2026-11-23 | Jeton IAM d'une heure par défaut, douze au plus ; rôle `roles/memorystore.dbConnectionUser` ; récupération à chaque nouvelle connexion | Oui |
| S22 | <https://docs.cloud.google.com/memorystore/docs/valkey/networking> | 2026-11-23 | Private Service Connect seul moyen de connexion ; politique de connexion de service `gcp-memorystore` ; ports 6379 et 11000 à 13047 | Oui |
| S23 | <https://docs.cloud.google.com/memorystore/docs/valkey/instance-node-specification> | 2026-11-23 | `shared-core-nano` 1,4 Go, 0,5 vCPU, sans SLA ; `custom-pico` 1,25 Go, 2 vCPU, avec SLA, mode sans cluster seulement | Oui |
| S24 | <https://docs.cloud.google.com/memorystore/docs/redis/supported-versions> | 2026-11-23 | Redis 3.2 à 7.2, 7.2 par défaut, correctif 7.2.0 au 2024-02-29 ; un correctif par majeure | Oui |
| S25 | <https://docs.cloud.google.com/memorystore/docs/redis/auth-overview> | 2026-11-23 | Chaîne AUTH de 36 caractères, un UUID généré par le service ; changée en coupant puis rétablissant AUTH | Oui |
| S26 | <https://docs.cloud.google.com/memorystore/docs/redis/release-notes> | 2026-11-23 | Entrées jusqu'au 2026-11-09 ; ni 7.4, ni 8.x, ni retrait annoncé | Oui |
| S27 | <https://docs.cloud.google.com/memorystore/docs/cluster/memorystore-for-redis-cluster-overview> | 2026-11-23 | « based on open-source Redis version 7.x » | Oui |
| S28 | <https://github.com/hashicorp/terraform-provider-google>, `website/docs/r/memorystore_instance.html.markdown` au tag v8.12.0, `memorystore_auth_token.html.markdown` (commit `fb0c73b6`), `memorystore_token_auth_user.html.markdown` (commit `866b42eb`), `redis_instance.html.markdown` | 2026-11-23 | 8.12.0 du 2026-11-17 : `authorization_mode` (`AUTH_DISABLED`, `IAM_AUTH`, `TOKEN_AUTH`), `mode` (`CLUSTER`, `CLUSTER_DISABLED`), `node_type` ; ressources de jeton fusionnées le 2026-11-18, absentes du tag ; jeton « stored in the raw state as plain text » ; `auth_string` de `google_redis_instance` | Oui |
| S29 | <https://cloud.google.com/memorystore/valkey/pricing>, <https://cloud.google.com/memorystore/docs/redis/pricing> | 2026-11-23 | Aucun prix lisible : page vide de chiffres pour Valkey, erreur 404 pour Redis | Oui |
| S30 | API de GitHub : commits de `valkey-io/valkey` et `redis/redis`, profils de leurs dix premiers auteurs | 2026-11-23 | Valkey : 973 commits humains, 184 auteurs, 32 % par les auteurs du top 10 qui déclarent AWS, 14 % Tencent. Redis : 637 commits humains, 127 auteurs, 30 % par ceux qui déclarent Redis | Oui, employeurs déclarés |
| S31 | <https://github.com/Snapchat/KeyDB/releases> | 2026-11-23 | BSD-3-Clause ; v6.3.4 le 2023-10-30, dernière release | Oui |
| S32 | <https://github.com/dragonflydb/dragonfly/blob/main/LICENSE.md>, releases | 2026-11-23 | Dragonfly Source-Available License à partir de 2.1, limite de 100 vCPU en production ; v2.1 le 2026-11-04 | Oui |
| S33 | <https://codeberg.org/redict/redict/releases> | 2026-11-23 | Dépôt marqué archivé ; 7.3.6 le 2025-10-08, dernière release | Oui |
| S34 | <https://github.com/microsoft/garnet> (`LICENSE`, releases, `.github/workflows/docker-linux.yml`) | 2026-11-23 | MIT ; v2.2.13 le 2026-11-16 ; images sur ghcr.io pour amd64 et arm64, `provenance: false` | Oui |
| S35 | <https://docs.cloud.google.com/memorystore/docs/memcached/deprecation/migrate-to-valkey> | 2026-11-23 | « We recommend that you migrate your Memorystore for Memcached workloads to Memorystore for Valkey » | Oui |
| S36 | <https://github.com/valkey-io/valkey/tree/9.1.4> (`src/valkey-cli.c`, `src/server.c`, `src/version.h`, `valkey.conf`) | 2026-11-23 | `VALKEYCLI_AUTH`, puis `REDISCLI_AUTH` à défaut ; usage `valkey-server [/path/to/valkey.conf] [options] [-]` ; champs `server_name`, `valkey_version`, `redis_version` fixé à 7.2.4 ; mode protégé seulement sans mot de passe ; `save ""` coupe les instantanés | Oui |
| S37 | <https://github.com/redis/redis/tree/7.2.17> (`src/redis-cli.c`, `src/server.c`, `redis.conf`) | 2026-11-23 | `REDISCLI_AUTH` ; même usage du serveur ; même mode protégé ; `save ""` | Oui |
| S38 | <https://github.com/docker-library/official-images/tree/master/library> | 2026-11-23 | Aucun fichier `library/valkey` : pas d'image officielle Docker de Valkey | Oui |
| S39 | <https://docs.docker.com/reference/cli/docker/buildx/imagetools/inspect/> | 2026-11-23 | `--format "{{json .Manifest}}"` et son champ `digest`, utilisés par le contrôle de démarrage du script | Oui |
| S40 | [ADR-009](../adr/ADR-009-catalogue.md), section 2, et ses sources | 2026-11-19 | Memorystore for Valkey en GA depuis le 2025-04-02 ; standard `resp` | Oui, interne |
| S41 | `tests/bench/bench-005-orchestration.sh`, ligne 108 | 2026-11-21 | `valkey/valkey:9.1.4-alpine@sha256:56729e68…b37893f0`, ligne entrée par le commit `e516c10` du 2026-11-20 | Oui, interne |
| S42 | [ADR-012](../adr/ADR-012-postgres-local.md), portée de la dérogation | 2026-11-21 | Dérogation à ENF-03 limitée aux images de `library/` ; `valkey/valkey` hors de son champ | Oui, interne |
| S43 | [ADR-008](../adr/ADR-008-modules-opentofu-gcp.md), conditions 2, 3 et 6, portée | 2026-11-21 | Socle avec accès privé aux services et Memorystore for Redis en tier basique ; chaîne AUTH en clair dans l'état ; moteur du cache hors décision | Oui, interne |
| S44 | Branche `docs/plan-golden-repo`, commit `13be333d` : `specs/001-golden-repo-saas-b2b/research.md` (RS-10, RS-11), `contracts/secrets.md` | 2026-11-21 | Valkey en Deployment sans persistance, image de BENCH-005 ; `cache-auth`, `Opaque`, clé `password` ; producteur `gcp` en attente de ce benchmark | Oui, interne, non fusionné |
| S45 | `specs/001-golden-repo-saas-b2b/spec.md` | 2026-11-21 | FR-001 et FR-009 : la base et le cache démarrent par une commande ; l'exemple lit et écrit dans le cache | Oui, interne |
| S46 | `man caffeinate` et `pmset -g custom`, sur la machine de mesure | 2026-11-24 | `-i` empêche la veille sur inactivité, `-s` la veille du système sur secteur seulement, `-w` libère l'assertion à la fin du processus ; réglage `sleep` à 1 minute sur secteur | Oui, documentation du système |
| S47 | <https://docs.docker.com/reference/cli/docker/container/stats/> | 2026-11-25 | Sur Linux, le CLI retranche le cache de l'usage total ; cache = `inactive_file` sur cgroup v2 ; l'API rend l'usage total et le cache (relevé de [FINOPS]) | Oui |
| S48 | <https://docs.cloud.google.com/memorystore/docs/valkey/cuds> | 2026-11-25 | Facturation par nœud et par heure ; engagements à 20 % (un an) et 40 % (trois ans), payés chaque heure, non annulables ; stockage, sauvegardes, persistance et sortie de données exclus ; outil qui résume (relevé de [FINOPS]) | Oui |
| S49 | <https://docs.cloud.google.com/memorystore/docs/valkey/instance-node-specification> | 2026-11-25 | Types de nœud, mémoire totale et clés inscriptibles par défaut, vCPU, SLA, mode ; 0 à 5 réplicas ; capacité minimale d'un nœud ; `shared-core-nano` limité à 1,12 Go ; outil qui résume (relevé de [FINOPS]) | Oui |
| S50 | <https://cloud.google.com/memorystore/valkey/pricing> | 2026-11-25 | Le titre seulement : aucune grille, aucune unité, aucune région lisible ; l'adresse de `docs.cloud.google.com/memorystore/docs/valkey/pricing` y redirige (301) (relevé de [FINOPS]) | Oui |
| S51 | <https://valkey.io/topics/lru-cache/> | 2026-11-25 | `maxmemory` : sans limite par défaut sur 64 bits ; `allkeys-lru` conseillé pour un cache quand on hésite ; tampons de réplication et de journal non comptés dans `maxmemory` ; outil qui résume (relevé de [FINOPS]) | Oui |
| S52 | <https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/> | 2026-11-25 | Guaranteed : demande égale à la limite, mémoire et CPU, pour chaque conteneur ; texte lu jusqu'au caractère 100 000 sur 106 127 (relevé de [FINOPS]) | Oui |
| S53 | API de GitHub : `repos/valkey-io/valkey/security-advisories`, `repos/redis/redis/security-advisories`, `advisories/<GHSA>` et `advisories?cve_id=` | 2026-11-25 | Valkey : neuf avis du 2026-02-23 au 2026-11-19, versions touchées, vecteurs CVSS (`PR:L` pour les six avis de la ligne 9.1 ; `PR:N` pour GHSA-93p9 et GHSA-c677, jusqu'à 9.0.2) ; Redis : trois avis du 2026-05-05, authentifiés. Aucun des douze dans la base mondiale, ni par GHSA ni par CVE, revu ou non (relevé de [SECU]) | Oui |
| S54 | Trivy 0.76.2, `trivy image --image-src remote --platform linux/amd64 --scanners vuln,license --list-all-pkgs`, sur les deux images figées par condensat | 2026-11-25 | Valkey : Alpine 3.24.4, 23 paquets, aucun paquet `valkey`, 16 constats (6 faibles, 10 moyens) sur OpenSSL 3.5.9-r0 et zlib 1.3.2-r1, corrigés dans Alpine ; Redis : Alpine 3.22.8, 20 paquets, aucun paquet `redis`, mêmes six CVE en 11 constats ; aucun `USER` dans les deux configurations ; licences des paquets (GPL-2.0, MPL-2.0, Apache-2.0, MIT), aucune AGPL (relevé de [SECU]) | Oui, outil |
| S55 | `docker buildx imagetools inspect` sur `docker.io/valkey/valkey`, `ghcr.io/valkey-io/valkey` et `public.ecr.aws/valkey/valkey`, tag `9.1.4-alpine` | 2026-11-25 | Index OCI `sha256:56729e68…` identique sur les trois registres ; quatre manifestes de plate-forme, aucun manifeste d'attestation ; ni `sha256-56729e68….sig` ni `.att` sur docker.io, ni `.sig` ni tag de référents sur ghcr.io (relevé de [SECU]) | Oui, registres |
| S56 | API de GitHub : `repos/valkey-io/valkey-container/attestations/<condensat>`, `orgs/valkey-io/attestations/<condensat>` | 2026-11-25 | 404 aux deux : aucune attestation GitHub pour le condensat figé (relevé de [SECU]) | Oui |
| S57 | <https://github.com/valkey-io/valkey-container> : `.github/workflows/ci.yml` et `.github/actions/build-image/action.yml` au commit `5b08693a`, `9.1/alpine/Dockerfile` et `docker-entrypoint.sh` au commit `32d10db6` | 2026-11-25 | Tâche planifiée limitée à `unstable` ; publication des versions dont le dossier ou `versions.json` change, ou à la main ; trois identifiants (jeton Docker Hub, jeton GitHub, rôle AWS par OIDC) ; `id-token: write` ; `provenance: false`, aucune signature ; `FROM alpine:3.24` sans condensat ; archive vérifiée par SHA-256 ; `BUILD_TLS=yes`, sans RDMA ; aucun `USER`, `setpriv` depuis root ; SBOM `/usr/local/valkey.spdx.json` avec la CPE `cpe:2.3:a:lfprojects:valkey:9.1.4` ; `exec "$@" $VALKEY_EXTRA_FLAGS` | Oui |
| S58 | <https://github.com/valkey-io/valkey/blob/9.1.4/valkey.conf>, `src/acl.c` au tag 9.1.4 | 2026-11-25 | `enable-protected-configs`, `enable-debug-command`, `enable-module-command` à `no` par défaut ; `rename-command` déconseillé au profit des ACL ; `requirepass` couche de compatibilité du compte `default` ; catégories `@admin`, `@dangerous`, `@scripting` ; un million d'essais de mot de passe par seconde ; empreinte `#` de 64 caractères hexadécimaux acceptée ; exemple `requirepass foobared` | Oui |
| S59 | <https://hub.docker.com/v2/namespaces/valkey/repositories/valkey/tags/9.1.4-alpine>, idem `library/redis` tag `7.2.17-alpine` | 2026-11-25 | Valkey : condensat `sha256:56729e68…`, `tag_last_pushed` 2026-11-18T23:11:58Z ; Redis : `sha256:2f66de68…`, `tag_last_pushed` 2026-11-12T00:05:00Z ; outil qui résume (relevé de [SECU]) | Oui |
| S60 | <https://docs.cloud.google.com/memorystore/docs/valkey/manage-basic-auth> | 2026-11-25 | Compte `default` créé par le service, `AUTH <jeton>` ou `AUTH <utilisateur> <jeton>` ; deux jetons au plus par utilisateur, rotation sans coupure ; jetons créés par le service ; TLS recommandé ; `default` garde ses droits ; outil qui résume (relevé de [SECU]) | Oui |
| S61 | <https://docs.cloud.google.com/memorystore/docs/valkey/about-iam-auth> | 2026-11-25 | Jeton d'une heure, douze au plus ; permission `memorystore.instances.connect` ; jeton présenté à chaque nouvelle connexion, impossible à écrire en dur ; fournisseurs dynamiques de GLIDE et redis-py, rien sur .NET ; débit de connexions freiné ; TLS recommandé ; outil qui résume (relevé de [SECU]) | Oui |
| S62 | <https://docs.cloud.google.com/memorystore/docs/valkey/supported-commands> | 2026-11-25 | Commandes bloquées (`NOPERM`) : `ACL`, `SAVE`, `BGSAVE`, `BGREWRITEAOF`, `CONFIG GET`, `SET`, `REWRITE`, `RESETSTAT`, `DEBUG`, `MODULE` sauf `HELP`, `SHUTDOWN`, `REPLICAOF`, `FAILOVER`, `MIGRATE`, `MOVE`, `SWAPDB`, `PSYNC`, `SYNC`, entre autres ; `EVAL`, `FUNCTION`, `KEYS`, `FLUSHALL`, `MONITOR` permis ; outil qui résume (relevé de [SECU]) | Oui |
| S63 | <https://docs.cloud.google.com/memorystore/docs/valkey/about-in-transit-encryption> | 2026-11-25 | TLS 1.2 et plus ; CA par instance, partagée par région ou gérée par le client ; certificat du serveur renouvelé chaque semaine ; clients sans TLS bloqués ; perte de performance possible ; outil qui résume (relevé de [SECU]) | Oui |
| S64 | <https://github.com/hashicorp/terraform-provider-google>, tag v8.12.0 : `memorystore_instance.html.markdown`, `memorystore_acl_policy.html.markdown` ; releases | 2026-11-25 | `transit_encryption_mode` immuable (`TRANSIT_ENCRYPTION_DISABLED`, `SERVER_AUTHENTICATION`) ; `acl_policy` ; ressource `google_memorystore_acl_policy`, règle en syntaxe Valkey, exemple `on >password123 ~* +@all` ; v8.12.0 du 2026-11-17, dernière release au 2026-11-25 | Oui |
| S65 | <https://github.com/kubernetes-sigs/kind>, tag v0.33.0 : `pkg/cluster/internal/providers/docker/provision.go` et `network.go` ; notes de la release v0.24.0 | 2026-11-25 | Nœud lancé par `docker run` avec `--privileged`, `seccomp=unconfined`, `apparmor=unconfined`, `--restart=on-failure:1` ; réseau par `docker network create -d=bridge` ; NetworkPolicy prises en charge depuis v0.24.0 par kube-network-policies | Oui |
| S66 | <https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2026-63639>, idem `CVE-2025-67733` | 2026-11-25 | CVE-2026-63639 : « Awaiting Analysis », aucune configuration CPE ; CVE-2025-67733 : CPE `cpe:2.3:a:lfprojects:valkey`, plages de versions ; outil qui résume (relevé de [SECU]) | Oui |
| S67 | <https://github.com/valkey-io/valkey> : `COPYING`, `deps/` au tag 9.1.4, `MAINTAINERS.md` ; `valkey-io/valkey-container` (licence) ; `redis/redis`, `COPYING` au tag 7.2.17 | 2026-11-25 | Deux textes BSD-3-Clause ; dépendances sous BSD, MIT, Boost, domaine public, Apache-2.0 ou MIT ; neuf mainteneurs, huit organisations ; `valkey-container` sous BSD-3-Clause ; Redis 7.2.17 sous BSD-3-Clause | Oui |

## 10. Relectures

| Relecteur | Porte sur | Date | Avis |
| --- | --- | --- | --- |
| [SECU] | Licences, critères éliminatoires, sécurité, inventaire du script | 2026-11-25 | Réservé, favorable à Valkey 9.1.4 sous conditions. Licences, gouvernance et critères éliminatoires sont confirmés sur les sources, sans AGPL dans aucune image. La maturité de Redis 7.2 passe à 4 par la règle de BENCH-013 : 86 contre 69. Trivy 0.76.2 ne voit le moteur dans aucune des deux images, compilé depuis les sources, et aucun des douze avis n'est dans la base mondiale : R-36 couvre tout le moteur, pas trois avis sur neuf. Tous les avis de la ligne 9.1 demandent un client authentifié. `valkey/valkey` n'a ni signature ni attestation : dérogation datée dans l'ADR-015, avec comparaison du condensat sur trois registres. M6 (c) tient pour ce qu'il vise ; un contrôle statique le complète, `VALKEY_EXTRA_FLAGS` compris. L'inventaire `16daad12…` est exact. Jeton plutôt qu'IAM sur `gcp`, TLS dès la création. Aucun secret dans les données ni dans les commits. Conditions 1 à 8. |
| [FINOPS] | Coût, seuils d'empreinte | 2026-11-25 | Favorable, avec corrections. M2, la somme des pods, M3, M4 et M5 se retrouvent dans les données brutes de `series-2` ; les échantillons du nœud ne sont écrits dans aucun TSV. Seuils de 4.1 appliqués tels qu'écrits : 4/5 pour les deux, le coût à 4/5 pour les deux, le classement inchangé. Écart de 50,4 Mio entre les nœuds : hypothèse de cache de pages, non mesurée, sans effet sur la note (au plus 13,8 % du seuil). O1 n'ajoute rien au premier `task up` : 1 802,1 Mo pour le standard (160,2 % du budget de 900 s à 10 Mbit/s), 1 799,3 avec O2 ; le lite, environ 1 263,8 Mo, 112,3 %, sans que le moteur décide. Plancher mémoire : lite 2,0 Gio de VM, standard 3,5 Gio, à 8 à 23 Mio du palier de 4,0 Gio. Memorystore for Valkey se facture par nœud et par heure ; aucun prix lisible, région non choisie (R-05). Dimensionnement proposé : pod à 64 Mi demandés et 128 Mi en limite, `maxmemory 64mb` ; `gcp` en `CLUSTER_DISABLED`, zéro réplica, `shared-core-nano`. Pas de deuxième palier de volume. Conditions 1 à 7. (Ligne rédigée par [BENCH] d'après la relecture, qui n'en fournissait pas.) |

[BENCH] Points à relire en priorité. Pour [SECU] : la dérogation à ENF-03 que
demanderait `valkey/valkey`, sans signature ni provenance et hors du champ de
l'ADR-012 ; l'inventaire en tête du script, dans sa version de la série
(`16daad12…`) ; la mise en œuvre du mot de passe (conteneur d'initialisation,
volume en mémoire) et la portée de M6 (c), limitée aux processus du conteneur
du cache ; la note de licence de Redis 7.2. Pour [FINOPS] : le recalcul de M2
depuis `runs.tsv`, et l'écart de 50,4 Mio entre les nœuds des deux options,
sans cause établie (section 4.4, point 1) ; la note d'empreinte à 4/5 pour
les deux ; les prix de Memorystore, toujours illisibles (R-05) ; les seuils
de la section 4.1 repris de BENCH-011.

### Relecture [SECU]

[SECU] Ce que j'ai relu, le 2026-11-25. Le rapport au commit `17469f0` de la branche `docs/bench-014-cache`, et le script. J'ai aussi relu la série 2 en entier : `auth.tsv`, `pod-restart.tsv`, `power.tsv`, `versions.tsv`, les journaux et les manifests rendus, avec `series-2.out`, `attempts.log` et les `render-*.yaml`. Le script du worktree a pour SHA-256 `16daad12…`, identique au fichier du commit `0b6c8ad` ; celui de `33cf0dd` donne `1426ddca…`, comme l'écrit la section 4.3. La section 4.1 extraite du rapport, celle de `section-4.1-2026-11-23.md` et celle du commit `6843021` donnent toutes trois `67a35b6b…96f6`. Les faits externes viennent de `gh api`, de `docker buildx imagetools inspect`, de Trivy 0.76.2 à distance et de WebFetch, tous lus le même jour (S53 à S67, en fin de relecture). Je n'ai lancé ni `docker run`, ni cluster, ni action cloud.

[SECU] Licences (5.1). Je confirme 5 pour Valkey et 3 pour Redis 7.2. Le `COPYING` du tag 9.1.4 contient deux textes BSD-3-Clause, celui des contributeurs de Valkey et celui de Redis Ltd. pour 2006 à 2020. Les dépendances de `deps/` sont toutes sous licence permissive : jemalloc, libvalkey et linenoise sous BSD, Lua sous MIT, fpconv sous Boost, hdr_histogram dans le domaine public ou sous BSD, fast_float au choix sous Apache-2.0, MIT ou Boost [S67]. `valkey-container` est sous BSD-3-Clause, comme le `COPYING` de Redis au tag 7.2.17 [S67]. Dans les images, Trivy relève les licences des paquets d'Alpine : GPL-2.0 pour busybox, apk-tools et alpine-baselayout, MPL-2.0 pour les certificats, Apache-2.0 pour OpenSSL [S54]. Aucune AGPL dans l'une ou l'autre image. CELIAN ne redistribue aucune image, puisque le miroir zot n'en transmet de copie à personne (ADR-011, condition 9). La réserve sur Redis tient : `7` et `latest` désignent des lignes hors BSD [S14], et si Redis revenait, Renovate devrait plafonner son image sous 7.4.

[SECU] Gouvernance (5.2). Je confirme 5 et 2. `MAINTAINERS.md` liste toujours neuf mainteneurs chez huit organisations, Amazon deux fois [S67]. L'image est construite et publiée par un workflow de `valkey-io/valkey-container`, dans l'organisation du projet [S57].

[SECU] Maturité (5.3). Je ramène Redis 7.2 à 4, par la règle appliquée dans BENCH-013. La note 5 revient aux projets gradués à la CNCF qui tiennent une liste d'adoptants (Cilium, Argo CD, Flux) et à minikube. Un projet sans fondation a reçu 4 : k3d, Traefik, Config Sync, Mailpit. Le rapport justifie le 5 de Redis par l'âge du dépôt, la ligne Extended et Memorystore, sans liste d'adoptants tenue par le projet. Valkey reste à 4. Effet : Redis passe de 72 à 69, et l'écart de 14 à 17 points. Chaque ligne de sensibilité perd 3 points pour O2, aucune n'inverse le classement, et il faudrait désormais six crans de 3 points contre O1 au lieu de cinq.

[SECU] Avis de sécurité sur 12 mois (5.5). Les comptes du rapport sont exacts. Valkey a publié neuf avis du 2026-02-23 au 2026-11-19, huit élevés et un moyen, dont trois sans CVE : GHSA-f4q9-j22m-xqq9, GHSA-jcj7-v34w-v9vv et GHSA-fq2f-crmw-q97r. Redis a publié trois avis le 2026-05-05 [S53]. Gravité réelle pour la 9.1.4 : six avis touchaient la ligne 9.1, tous corrigés au plus tard par la 9.1.4, et tous demandent un client authentifié (vecteur CVSS `PR:L`) [S53]. Deux ne s'appliquent pas à notre montage : GHSA-f4q9 ne vise que le mode cluster, GHSA-jcj7 que RDMA, que le Dockerfile ne compile pas [S57]. GHSA-53mc-f3m3-99vh ne vise qu'un serveur en TLS. GHSA-3885-pq5f-788j, corrigé par la 9.1.4, demande l'éviction des clients, inactive par défaut. GHSA-fq2f porte « Unauthenticated » dans son titre, mais son texte et son vecteur exigent de pouvoir lancer des scripts. Les deux seuls avis sans authentification de la période, GHSA-93p9-5vc7-8wgr et GHSA-c677-q3wr-gggq, s'arrêtent à 9.0.2. Les trois avis de Redis demandent eux aussi un client authentifié. Deux avis de Valkey et un de Redis passent par Lua : retirer `@scripting` réduit la surface (condition 4). Sur le PC, seuls l'application et `task up` tiennent le mot de passe, et la gravité réelle reste faible tant que les correctifs suivent.

[SECU] R-36 : le scan ne voit pas le moteur, dans aucune des deux images. Le rapport écrit que « trois avis sur neuf n'ont pas de CVE, donc échappent aux scanners ». L'angle mort est plus large. Les deux images compilent le moteur depuis l'archive des sources, hors de tout gestionnaire de paquets [S57]. Trivy 0.76.2 n'y trouve que des paquets d'Alpine, 23 pour Valkey et 20 pour Redis, et aucun paquet `valkey` ni `redis` [S54]. Aucun des douze GHSA n'est dans la base mondiale de GitHub, ni par son identifiant, ni par sa CVE, en avis revu comme non revu [S53]. Le scan de FR-021 ne peut donc voir aucun des neuf avis de Valkey ni aucun des trois de Redis. Une seconde source fondée sur la CPE ne comblerait qu'une partie du trou. L'image de Valkey embarque un SBOM SPDX, `/usr/local/valkey.spdx.json`, qui porte la CPE `cpe:2.3:a:lfprojects:valkey:9.1.4` [S57], celle que NVD emploie pour CVE-2025-67733. Mais CVE-2026-63639, publiée par le projet le 2026-07-22, reste « Awaiting Analysis » chez NVD le 2026-11-25, sans configuration [S66], et les trois avis sans CVE n'y entreront jamais. Trivy ne remonte pas ce fichier comme un paquet [S54]. Les deux options sont aussi aveugles l'une que l'autre, donc la note ne départage pas.

[SECU] Je maintiens 3/5 aux deux options. La justification change : le moteur est invisible au scan dans les deux images ; l'image de Valkey n'a ni signature ni attestation ; celle de Redis n'a pas de signature vérifiable, couverte par l'ADR-012.

[SECU] Base de l'image et délai du principe VI. Dans l'image de Valkey, Trivy relève 16 constats, 6 faibles et 10 moyens, aucun élevé ni critique, sur OpenSSL 3.5.9-r0 et zlib 1.3.2-r1 ; Alpine les a tous corrigés (3.5.9-r1, 1.4-r0). Redis porte les mêmes six CVE, en 11 constats [S54]. D'après son workflow, `valkey-container` ne republie une version que si son dossier ou `versions.json` change, ou sur lancement manuel ; la tâche planifiée quotidienne ne construit que `unstable`, et `FROM alpine:3.24` n'a pas de condensat [S57]. Un correctif d'Alpine n'arrive donc dans `9.1.4-alpine` qu'avec une release de Valkey ou une reconstruction manuelle. Docker Hub date le tag, donc Renovate aussi (ADR-016) : `tag_last_pushed` vaut 2026-11-18T23:11:58Z, et le délai de 7 jours s'achève le 2026-11-25 à 23:12 UTC [S59]. La 9.1.4 corrige GHSA-3885 : l'exception du principe VI la couvrait de toute façon.

[SECU] Point 1 de [BENCH] : signature et dérogation. J'ai vérifié le 2026-11-25 que l'index OCI `sha256:56729e68…` ne contient que ses quatre manifestes de plate-forme, sans manifeste d'attestation. Docker Hub ne porte ni tag `sha256-56729e68….sig` ni `.att`, ghcr.io ni `.sig` ni tag de référents `sha256-56729e68…`, et l'API d'attestations de GitHub répond 404 pour ce condensat, au dépôt comme à l'organisation [S55], [S56]. L'action de construction garde `provenance: false`, et aucune étape ne signe [S57]. Il faut donc une dérogation datée dans l'ADR-015. Celle de l'ADR-012 s'arrête à `docker.io/library/`, et celles des ADR-013 et ADR-014 nomment chacune une seule image. Je recommande le modèle de l'ADR-014 plutôt que les deux autres voies. Reconstruire et signer l'image dans la CI de CELIAN mettrait un registre et une chaîne de construction de CELIAN sous chaque projet généré, contre ENF-07, et ajouterait un registre à la liste de la condition 10 de l'ADR-011. Docker Hardened Images a été écartée par l'ADR-012 pour le compte Docker qu'elle exige. Je n'ai pas cherché d'autre image signée de Valkey.

[SECU] Contrôle compensatoire, à ajouter à la tenue de la liste. Le même condensat d'index, `sha256:56729e68…`, est publié sur docker.io, ghcr.io et public.ecr.aws [S55]. Le workflow pousse avec trois identifiants distincts : un jeton Docker Hub gardé dans les secrets du dépôt, le jeton éphémère de GitHub et un rôle AWS obtenu par OIDC [S57]. À chaque condensat neuf, [SECU] vérifie que les trois registres donnent le même. Le contrôle ne prouve pas l'auteur, puisque le workflow est commun. Il détecte en revanche un condensat poussé sur Docker Hub seul, avec un jeton volé. Le nœud continue de tirer depuis docker.io, que Renovate sait dater ; les copies de ghcr.io et d'ECR, que Renovate ne date pas (ADR-016), ne servent qu'à la comparaison.

[SECU] Texte proposé pour la section « Dérogations » de l'ADR-015 :

| Principe | Écart | Justification | Durée | Condition de levée |
| --- | --- | --- | --- | --- |
| Aucun : exigence ENF-03 du PRD, « Kyverno refuse les images non signées » | L'image `docker.io/valkey/valkey` n'a aucune signature vérifiable. Kyverno l'admet par sa référence exacte, condensat compris, inscrite dans une liste fermée | FR-008 reste tenu : le condensat fige le contenu, que containerd vérifie. Le workflow de `valkey-container` construit avec `provenance: false` et ne signe pas ; l'index n'a aucun manifeste d'attestation, docker.io et ghcr.io n'ont aucun tag de signature, et l'API d'attestations de GitHub répond 404 (BENCH-014, S55 à S57). Le même condensat est publié sur trois registres par trois identifiants distincts, ce qui permet un contrôle croisé. Une image reconstruite et signée par CELIAN placerait CELIAN dans la chaîne de chaque projet généré (ENF-07). [SECU] recommande cette voie | Depuis la décision de Lucas, jusqu'à sa levée. Relecture au plus tard le 2027-05-23, date de la prochaine vérification de BENCH-014, et par [SECU] à chaque condensat neuf | Valkey publie pour cette image une signature, ou une attestation signée, que Kyverno sait vérifier : la politique la vérifie alors, et la liste fermée disparaît pour cette image |

[SECU] Portée proposée : la seule image `docker.io/valkey/valkey`, en variante Alpine. Les copies de ghcr.io et de public.ecr.aws n'entrent pas, ni `valkey/valkey-bundle`, ni un autre dépôt de docker.io hors de `library/`. Tenue de la liste : elle naît avec le premier profil qui embarque Kyverno, et change dans la même PR que le manifest, PR de Renovate comprise. [SECU] relit chaque condensat neuf, avec la comparaison des trois registres.

[SECU] Point 2 de [BENCH] : portée de M6 (c). Le contrôle fait ce qu'il annonce, et rien de plus. Il lit `/proc/[0-9]*/cmdline` dans l'espace de noms de processus du conteneur `cache`, au moment du contrôle : `tini`, le serveur, et le shell du `kubectl exec` lui-même. Trois lieux lui échappent. Le conteneur d'initialisation, déjà terminé. Les environnements des processus (`/proc/*/environ`). Le nœud enfin : kubelet, containerd, et les volumes en mémoire où la valeur est en clair par construction, le Secret monté et `cache.conf`. Sur le PC, lire le nœud demande d'être root dans la machine virtuelle de Docker, ce qui donne déjà tout le cluster, et le mot de passe local est jetable (R-20). Le résultat tient pour ce qu'il vise : 0 ligne sur six exécutions, jamais `err` (`auth.tsv`). Deux contrôles le complètent (condition 5) : un contrôle statique du rendu, et la lecture d'`environ` à côté de `cmdline`. La ligne de la section 8, « Un argument vu par containerd échappe au contrôle », est à corriger. Un argument se lit dans le manifest rendu, et c'est le rôle du contrôle statique ; ce qui échappe à M6 (c), ce sont les trois lieux ci-dessus. Le vrai piège vient de l'image : son entrypoint finit par `exec "$@" $VALKEY_EXTRA_FLAGS` [S57], si bien qu'une variable posée sur le conteneur devient un argument du serveur. Le contrôle statique doit la refuser.

[SECU] Point 3 de [BENCH] : inventaire du script `16daad12…`. Il est exact et complet pour ce qui crée, modifie ou supprime un conteneur ou un réseau. `kind create cluster` lance bien le nœud par `docker run --privileged`, avec aussi `seccomp=unconfined`, `apparmor=unconfined` et `--restart=on-failure:1`, et crée le réseau par `docker network create -d=bridge` s'il manque [S65]. Les autres appels à Docker ne font que lire, `docker ps -q` compris, qui manquait dans BENCH-013 et figure ici. Trois précisions à ajouter. `kind create cluster` tire `kindest/node` s'il manque au cache de l'hôte : la phrase « le script ne construit ni ne retire aucune image » reste vraie, mais il faut ajouter ce tirage possible. Hors du dossier d'essai, le script n'écrit que le dossier du verrou, quand `BENCH_LOCK` est défini, et tient une assertion `caffeinate` libérée à sa sortie. L'en-tête dit « no port is published to the host », alors que kind publie l'API sur 127.0.0.1 (R-20) : il faut écrire « aucun port hors de la boucle locale ». Le script ne sort du poste que par `docker manifest inspect`, `docker buildx imagetools inspect` et les tirages du nœud, tous vers Docker Hub. Dans le cluster, il écrit par `kubectl apply`, `create`, `scale`, `delete pod` et `exec`, toujours vers `celian-bench-014`, par un `KUBECONFIG` du dossier d'essai.

[SECU] Secrets (R-20, ADR-007). Le Secret `cache-auth` sort de `/dev/urandom` par `tr` et `head`, puis passe par un tube à `kubectl create -f -`. Pas de `kubectl apply`, donc pas d'annotation `last-applied-configuration` (ADR-007, condition 1). La valeur fait 40 caractères alphanumériques, environ 238 bits. Valkey ne limite pas les essais d'`AUTH` et écrit qu'un attaquant peut tenter un million de mots de passe par seconde [S58] : c'est l'entropie qui tient lieu de limitation, et elle suffit. Le serveur lit le mot de passe dans un fichier, le client dans `REDISCLI_AUTH` par `secretKeyRef`. Dans `series-2`, `series-2.out`, `attempts.log` et les `render-*.yaml`, je ne trouve aucune chaîne de 40 caractères alphanumériques hors des condensats, ni `requirepass`, ni `stringData`. Les journaux ne gardent que « secret/cache-auth created », et le `kubeconfig` fait 28 octets. Les journaux de kind gardent le chemin absolu du dossier de travail, nom du compte compris : ils restent hors du dépôt. Les lignes ajoutées par la branche ne contiennent ni `/Users/`, ni `/private/tmp`, ni nom de compte, ni tiret cadratin, et les cinq commits portent l'adresse noreply. Je n'ai pas lancé gitleaks, comme demandé.

[SECU] Valeurs connues à ajouter à la condition 1 de l'ADR-007 : `foobared`, l'exemple de `requirepass` dans `valkey.conf` [S58], et `password123`, l'exemple de règle de `google_memorystore_acl_policy` [S64]. Les deux tombent déjà sous la règle des 32 caractères.

[SECU] Durcissement sur `local`, ce que la série prouve. Le namespace porte `pod-security.kubernetes.io/enforce: restricted`, et les pods du cache et du client y ont été admis dans les six exécutions. Ils tournent sous l'UID 999 et le GID 1000, sans élévation, capacités retirées, `seccompProfile: RuntimeDefault`, racine en lecture seule, sans jeton de compte de service. L'UID explicite est indispensable : aucune des deux images ne déclare de `USER` [S54], et l'entrypoint de Valkey ne descend à l'utilisateur `valkey` par `setpriv` que s'il démarre en root [S57]. La persistance est coupée (`save ""`, `appendonly no`), et la clé perdue 6 fois sur 6 le confirme. TLS : je ne le demande pas sur `local`. Le trafic reste dans un nœud kind sur le poste, et le mot de passe est local et jetable ; l'écart avec `gcp` va au README (ENF-02).

[SECU] Trois points restent ouverts dans les manifests de l'essai, sans effet sur la mesure. Le volume `/data` est un `emptyDir` sans `sizeLimit`, où un client authentifié peut encore écrire un instantané par `SAVE`. Le compte `default` a tous les droits, et `requirepass` écrit le mot de passe en clair dans `cache.conf`. Aucune NetworkPolicy ne protège le port : tout pod du cluster joint 6379.

[SECU] Commandes dangereuses, ACL ou mot de passe. Pas de `rename-command` : `valkey.conf` le déconseille et renvoie aux ACL [S58]. Les défauts de la 9.1.4 bloquent déjà `DEBUG`, `MODULE` et la modification par `CONFIG SET` des réglages qui désignent des fichiers, comme `dir` et `dbfilename` : `enable-protected-configs`, `enable-debug-command` et `enable-module-command` valent `no` [S58]. Le reste passe par une ACL sur le compte `default`, plutôt que par `requirepass`, qui n'en est qu'une couche de compatibilité [S58]. Valkey accepte le mot de passe sous la forme de son empreinte SHA-256, `#` suivi de 64 caractères hexadécimaux [S58]. Le conteneur d'initialisation calcule donc l'empreinte depuis le fichier du Secret, par l'entrée standard, puis écrit une ligne `user default on #… ~* &* +@all -@admin …`. Le mot de passe en clair ne figure plus dans `cache.conf`, et le serveur n'a plus besoin de monter le Secret. Le client garde `AUTH <mot de passe>`, la forme du compte `default`, celle de Memorystore [S60].

[SECU] Parité avec Memorystore for Valkey. Memorystore authentifie le compte `default` par `AUTH <jeton>`. Le jeton est créé par le service, et chaque utilisateur peut en avoir deux, pour une rotation sans coupure [S60]. Le compte `default` garde tous ses droits, hors d'une liste de commandes bloquées : `ACL`, `SAVE`, `BGSAVE`, `CONFIG GET` et `SET`, `DEBUG`, `MODULE LOAD`, `SHUTDOWN`, `REPLICAOF`, `MIGRATE`, `SWAPDB`, entre autres. `EVAL`, `FUNCTION`, `KEYS`, `FLUSHALL` et `MONITOR` restent permis [S62]. Refuser sur `local` au moins cette liste fait échouer l'application sur le PC comme elle échouerait sur GCP. `-@admin` va plus loin, puisqu'il refuse aussi `MONITOR`, et c'est acceptable : le PC peut être plus strict, jamais moins. Une ressource `google_memorystore_acl_policy` existe dans le provider 8.12.0, avec la syntaxe d'ACL de Valkey ; sa page parle d'utilisateurs IAM et de comptes de service, et je n'ai pas vérifié qu'elle s'applique en mode `TOKEN_AUTH` [S64]. TLS : `transit_encryption_mode` est immuable [S64], donc le choix se fait à la création de l'instance. Memorystore accepte TLS 1.2 et plus, renouvelle chaque semaine le certificat du serveur, et propose une CA par instance, une CA partagée par région, ou une CA gérée par le client ; il bloque les clients sans TLS, et prévient d'une perte de performance [S63]. Le correctif servi n'est pas publié [S18] : `INFO server` le lira à la GATE 2.

[SECU] Jeton ou IAM, mon avis pour l'ADR-015 : le jeton pour le MVP, et l'IAM en évolution, comme le propose [BENCH]. La force de l'IAM : aucun secret statique, donc rien dans l'état, rien dans Secret Manager, aucune rotation. Ses coûts : le jeton d'accès vit une heure par défaut, ne peut pas être écrit en dur, et doit être présenté à chaque nouvelle connexion. Google renvoie aux fournisseurs d'identifiants dynamiques de Valkey GLIDE et de redis-py, sans rien dire de .NET, et l'IAM freine l'ouverture des connexions [S61]. L'API aurait sur `gcp` un chemin d'authentification à elle, donc du code hors de la couche de cible (ENF-02). Le jeton garde le même client et le même contrat `cache-auth` sur les deux cibles. Son prix : une valeur statique qui passe par l'état OpenTofu, chiffré par la condition 2 de l'ADR-008, puis par Secret Manager. La condition 7 le borne. La ressource qui lit le jeton n'est toujours pas publiée : 8.12.0 reste la dernière version du provider le 2026-11-25 [S64]. Le producteur de `cache-auth` sur `gcp` reste bloqué jusqu'à sa publication, plus les 7 jours du principe VI.

#### Corrections demandées au rapport par [SECU]

1. Section 5.3 : Redis 7.2 à 4/5, 12 points, avec la règle de BENCH-013 en justification. Section 6 : total de O2 à 69. Section 7 : écart de 17 points, sensibilité recalculée pour O2 (moins 3 sur chaque ligne), « six crans » au lieu de « cinq ». En-tête et verdict proposé : 86 contre 69.
2. Section 5.5, les deux options : remplacer « trois avis sur neuf n'ont pas de CVE, donc échappent aux scanners » par le fait mesuré. Trivy 0.76.2 ne voit pas le moteur, compilé depuis les sources, dans aucune des deux images ; aucun des douze GHSA n'est dans la base mondiale de GitHub [S53], [S54]. Ajouter la CPE du SBOM embarqué et le retard de NVD comme limite d'une seconde source [S57], [S66].
3. Section 2, colonne « Attestations et signature » de O1 : même condensat sur trois registres, aucun tag `sha256-*`, API d'attestations à 404, SBOM SPDX embarqué non signé [S55] à [S57].
4. Section 8, ligne M6 (c) : écrire ce que le contrôle couvre (lignes de commande des processus du conteneur du cache, au moment du contrôle), ce qui lui échappe (conteneur d'initialisation, environnements, nœud), et ce qui le lève (condition 5 ci-dessous). Retirer « Un argument vu par containerd ».
5. Section 4.3, inventaire : ajouter le tirage possible de `kindest/node` par kind, les options `seccomp=unconfined`, `apparmor=unconfined` et `--restart=on-failure:1` du nœud [S65], et le dossier du verrou comme seule écriture hors du dossier d'essai. En-tête du script, à sa prochaine modification : « no port is published outside the loopback ».
6. Section 3 ou 5.5 : le tag `9.1.4-alpine` poussé le 2026-11-18 à 23:11:58 UTC, délai de 7 jours échu le 2026-11-25 à 23:12 UTC, exception du principe VI applicable [S59].
7. Section 7, conditions proposées : la condition 3 gagne TLS à la création, la rotation et les contrôles conftest de la condition 7 ci-dessous. La condition 2 gagne l'ACL de la condition 4 ci-dessous.
8. Section 9 : ajouter S53 à S67. Section 10 : la ligne [SECU] ci-dessous.

#### Conditions de [SECU] pour l'ADR-015

1. Image et dérogation à ENF-03. `docker.io/valkey/valkey`, variante Alpine, est désignée par tag et condensat, tirée depuis docker.io par zot. docker.io figure déjà dans la liste de la condition 10 de l'ADR-011, et Renovate le date (ADR-016). La dérogation datée ci-dessus admet l'image par sa référence exacte, condensat compris, dans une liste fermée. À chaque condensat neuf, [SECU] vérifie que docker.io, ghcr.io et public.ecr.aws donnent le même condensat d'index. Contrôles : S01 ; E11 ; dès qu'un profil embarque Kyverno, le contrôle de la condition 7 de l'ADR-012 étendu à `docker.io/valkey/valkey`.
2. Suivi des failles (R-36) et version. R-36 s'étend à tout le moteur, pour Valkey comme pour toute image qui compile son moteur depuis les sources : le scan de FR-021 ne couvre que les paquets d'Alpine. [SECU] lit chaque mois les avis de `valkey-io/valkey` et les notes des releases marquées « SECURITY ». Renovate suit les versions correctives de `9.1.x-alpine` ; une version qui corrige un avis passe par l'exception du principe VI, matrice comprise. La 9.1.4 se fige après le 2026-11-25 à 23:12 UTC. Une seconde source par la CPE du SBOM embarqué s'étudie à l'étape 18 du plan, avec sa limite écrite (NVD en retard, trois avis sans CVE).
3. Durcissement du pod sur `local`, repris de l'essai. Le namespace applique le profil `restricted` ; le pod a `runAsNonRoot`, l'UID 999 et le GID 1000 explicites, `allowPrivilegeEscalation: false`, les capacités `ALL` retirées, `seccompProfile: RuntimeDefault`, `readOnlyRootFilesystem: true` et `automountServiceAccountToken: false`. Pas de persistance (`save ""`, `appendonly no`). `/data` est un `emptyDir` borné par `sizeLimit`. Demandes, limites et `maxmemory` selon la condition 2 de [FINOPS]. Contrôle : la matrice échoue sur un pod refusé par le profil.
4. ACL à la place de `requirepass`. Le conteneur d'initialisation écrit `user default on #<empreinte SHA-256> ~* &* +@all -@admin`, suivi du refus explicite de chaque commande que Memorystore bloque et que `@admin` ne couvre pas, d'après la page relue et datée [S62]. L'empreinte se calcule depuis le fichier du Secret par l'entrée standard. Le serveur ne monte pas le Secret. Ni `rename-command`, ni `requirepass` ; `enable-protected-configs`, `enable-debug-command` et `enable-module-command` restent à `no`. `@scripting` est retiré si le client .NET fonctionne sans, ce que [DEV] vérifie sur le golden repo ; sinon l'ADR écrit pourquoi. Contrôles : `PING` sans mot de passe reçoit `NOAUTH` ; `CONFIG GET`, `DEBUG`, `SAVE`, `ACL LIST` et `MODULE LIST` reçoivent un refus ; `cache.conf` ne contient pas la valeur du Secret.
5. Mot de passe hors des arguments et de l'environnement du serveur. Un contrôle statique du rendu refuse sur le conteneur du cache tout `env` et `envFrom`, dont `VALKEY_EXTRA_FLAGS`, et dans `command` ou `args` de tout conteneur toute option de mot de passe (`requirepass`, `-a`, `--pass`, `--user`). M6 entre dans la matrice, sa partie (c) étendue à `/proc/*/environ`. Le client lit le mot de passe par `secretKeyRef` ou par fichier, jamais en argument.
6. Réseau sur `local`. Service `ClusterIP` seulement, sans `NodePort`, `LoadBalancer` ni route TCP. Une NetworkPolicy n'admet sur 6379 que les pods de l'API, et refuse toute sortie au pod du cache. kind applique les NetworkPolicy depuis sa v0.24.0 [S65] ; [OPS] vérifie qu'elles s'appliquent sous kind 0.33.0, comme pour la condition 4 de l'ADR-014. Contrôle : un pod non admis n'atteint pas 6379, l'API l'atteint.
7. `gcp` : jeton, TLS, état. `authorization_mode = "TOKEN_AUTH"` et `transit_encryption_mode = "SERVER_AUTHENTICATION"` dès la création, puisque ce second attribut est immuable [S64]. La CA arrive au pod par la couche de cible, sous la forme d'un ConfigMap, puisqu'elle n'a rien de secret ; [OPS] choisit entre CA par instance et CA régionale. Le jeton vient de `google_memorystore_auth_token`, dans une version publiée du provider depuis 7 jours, dont [SECU] relit la page. Il part vers Secret Manager par `secret_data_wo`, puis vers `cache-auth`, clé `password`, par la synchronisation de GKE (ADR-007). Aucun `output` ne le porte, et l'état comme le plan sont chiffrés (ADR-008, condition 2). La rotation suit les deux jetons par utilisateur et s'écrit au README [S60]. Une politique conftest refuse un autre mode d'autorisation, `TRANSIT_ENCRYPTION_DISABLED`, et toute règle d'`acl_policy` contenant `>`, soit un mot de passe en clair dans le HCL. La politique de connexion de service n'admet que le sous-réseau de GKE, sur les seuls ports du mode sans cluster, que [OPS] lit. L'IAM passe par son propre ADR.
8. Écarts et catalogue. Le README liste TLS sur `gcp` seulement, et l'ACL de `local` plus stricte que Memorystore (ENF-02). L'entrée `redis` du catalogue porte BSD-3-Clause, gouvernance `foundation` (LF Projects), statut actif, date et sources. Toute autre image ou tout module, `valkey-bundle` compris, passe par une relecture [SECU] avant d'entrer.

[SECU] D'accord, avec réserves : Valkey 9.1.4 reste devant, 86 contre 69 après la correction de maturité. Le choix tient sur la licence et la gouvernance, que mes lectures confirment. La sécurité ne départage pas. Aucune des deux images ne laisse voir son moteur au scan, aucune n'a de signature vérifiable, et chaque avis de la ligne 9.1 demande un client authentifié. Ce qui distingue Valkey ici : il faut une dérogation de plus, et le compte `default` doit être restreint sur le PC pour se comporter comme Memorystore. Les conditions 1, 2 et 4 couvrent ces deux points.

[SECU] Non vérifié : que le client .NET fonctionne sous `-@admin`, sans `@scripting`, puis avec TLS et la CA sur `gcp` ; que `google_memorystore_acl_policy` s'applique à une instance en `TOKEN_AUTH` ; les ports utiles à Private Service Connect en mode sans cluster ; que les NetworkPolicy s'appliquent sous kind 0.33.0 ; qu'un commit qui ne touche que `versions.json` republie toutes les versions, que je lis dans le workflow sans l'avoir observé ; ce que containerd garde sur disque de l'environnement d'un conteneur ; que Syft ou Dependency-Track lisent `/usr/local/valkey.spdx.json`. Les faits de S59 à S63 viennent d'un outil qui résume les pages. La page TLS de Memorystore écrit que TLS est requis pour ne pas exposer les jetons, tandis que la page IAM le dit seulement recommandé : la condition 7 l'impose de toute façon.

[SECU] Question pour Lucas, facultative. Le workflow de `valkey-container` a déjà `id-token: write` pour AWS [S57], donc une signature sans clé ou une attestation de provenance lui coûterait peu. Un ticket amont accélérerait la levée de la dérogation. Je n'en ai ouvert aucun : c'est une action publique, qui revient à Lucas.

[BENCH] Suite donnée aux corrections demandées par [SECU] (2026-11-25), sans réécrire la relecture ci-dessus. Appliquées : 1 (maturité de Redis 7.2 à 4/5, grille à 86 contre 69, écart de 17 points, six crans, sensibilité recalculée, en-tête et section 7), 2 (sections 5.5 et 8, R-36), 3 (section 2), 4 (section 8, ligne M6 (c)), 5 (section 4.3, sauf l'en-tête du script), 6 (section 3), 7 (conditions 2 et 3 de la section 7), 8 (sources S53 à S67 en section 9, ligne de ce tableau). Non appliquée : l'en-tête du script (« no port is published outside the loopback »), parce que le script du rapport a pour SHA-256 `16daad12…` et que les relectures le citent ; elle attend la prochaine modification du script. Les sections « Ligne du tableau de la section 10 » et « Sources de [SECU] à ajouter à la section 9 » de la relecture ont été déplacées dans le tableau de cette section et dans la section 9, au mot près. Le total de 86 contre 69 est celui de la grille corrigée.

### Relecture [FINOPS]

[FINOPS] Recalcul depuis la série 2 du 2026-11-25. J'ai relu `runs.tsv`, `summary.tsv`, `idle-pods.tsv`, `images.tsv`, `node-images.tsv` et `load.tsv` de `series-2`. Je n'ai pas relu `auth.tsv`, `pod-restart.tsv` ni `power.tsv`. Les médianes des nœuds, par exécution : Valkey 634,4, 644,6 et 644,5 Mio, soit 644,5 ; Redis 594,1, 635,7 et 580,2, soit 594,1 ; nœud de base 588,2, 610,1 et 574,0, soit 588,2. M2 vaut donc 56,3 Mio pour O1 et 5,9 pour O2, comme dans le rapport, avec les mêmes écarts (10,2, 55,5 et 36,1 Mio). La somme des pods se retrouve échantillon par échantillon dans `idle-pods.tsv` : médianes d'exécution de 6,4, 6,5 et 6,2 Mio pour Valkey, de 4,3, 5,8 et 5,8 pour Redis, d'où 6,4 et 5,8. M3 se retrouve aussi (0,2 et 0,1 % d'un cœur). M4 se retrouve aux octets : 18 830 089 et 16 024 750 en amd64, soit 15,1 et 12,8 s à 10 Mbit/s. M5 : chaque exécution porte deux événements `Pulled` de l'image de l'option, 2,3 à 2,6 s puis 574 à 622 ms, donc oui trois fois sur trois. Un seul écart de méthode : les trois échantillons de nœud de chaque exécution ne sont écrits dans aucun TSV, seule leur médiane l'est (`runs.tsv`). Je ne peux donc pas refaire ces médianes d'exécution, seulement celles de la série. Pour la couche on a les pods échantillon par échantillon, pour le nœud non.

[FINOPS] Écart de 50,4 Mio entre les nœuds. Ce que les données montrent. Le nœud de Redis suit celui de base ronde par ronde, à plus 5,9, 25,6 et 6,2 Mio. Celui de Valkey ne le suit pas : 634,4, 644,6 et 644,5 Mio pour une base qui varie de 36,1, d'où des écarts de 46,2, 34,5 et 70,5 Mio. Valkey est le nœud le plus lourd de chacune des trois rondes. Si l'ordre était aléatoire, cela arriverait une fois sur 27, soit 3,7 % (mon calcul) : faible, mais trois tirages n'établissent pas un effet. L'écart ne vient pas du pod, qui pèse 6,4 Mio : 49,9 Mio sont hors pod. Enfin les bornes se recouvrent. Si l'on prend le nœud d'option le plus haut moins le nœud de base le plus bas, Valkey tient entre 24,3 Mio (634,4 moins 610,1) et 70,6 (644,6 moins 574,0), Redis entre moins 29,9 et 61,7. Médiane des écarts de chaque ronde au lieu d'écart des médianes : 46,2 pour Valkey, 6,2 pour Redis, soit 40,0 d'écart entre les options au lieu de 50,4.

[FINOPS] Explication la plus probable, et elle reste une hypothèse. La mémoire que lit `docker stats` est celle de tout le conteneur du nœud, et le CLI n'en retranche que le cache inactif (`inactive_file` sur cgroup v2) [S47]. Le cache de pages actif et la mémoire du noyau restent comptés : blobs de l'image tirée, couche dépaquetée, binaire exécuté, objets du système de fichiers. Aucun de ces postes n'est un processus du pod, donc la somme des pods ne les voit pas, et leur part dépend de l'image et de l'état du nœud à l'instant du relevé. Les 2,8 Mo de volume compressé de plus pour Valkey n'expliquent que quelques Mio, pas 50. Le reste se partage entre une vraie contribution de l'image de Valkey, que seule une mesure séparera, et la chance, vu les 3,7 % ci-dessus et un nœud de base qui varie déjà de 36,1 Mio. Je classe la chance et un cache de pages variable devant une cause propre au serveur : le pod, qui contient son propre cache de pages dans son working set, ne pèse que 6,4 Mio. Rien de ce qui précède n'a été mesuré. Le protocole a aussi un ordre fixe (base, Valkey, Redis, à chaque ronde), qui interdit de séparer l'effet de l'option de l'effet de son prédécesseur.

[FINOPS] Ce qu'il faudrait mesurer pour trancher, sans toucher à la note. Un, au moment de chaque échantillon, le `memory.stat` du cgroup du nœud (`anon`, `file`, `active_file`, `inactive_file`, `slab`, `kernel_stack`, `pagetables`) et le RSS par processus (containerd, kubelet, kube-apiserver, etcd, les shims). Si l'écart est dans `file` ou `slab`, c'est du cache : le noyau le rend sous pression, et il ne compte pas dans un plancher. S'il est dans `anon`, il faut trouver le processus. Deux, des témoins : le nœud avec l'image de Valkey lancée en `sleep` (sans serveur), le même pour Redis, pour séparer l'image du serveur. Trois, l'ordre permuté (base, Redis, Valkey, puis aléatoire) et au moins cinq exécutions par option. Quatre, écrire les échantillons du nœud dans un TSV (`idle-node.tsv`), comme le fait déjà `idle-pods.tsv` pour les pods. Cela se prête à une série courte, sans action payante.

[FINOPS] Effet sur une note : aucun. Seuil 4 : 56,3 Mio font 11,0 % de 512, 70,6 en font 13,8 % ; Redis, 5,9 et 61,7 Mio, 1,2 et 12,1 %. Aucune des valeurs possibles n'est à moins de 10 % du seuil, donc aucune seconde note à écrire. Pour franchir 512 Mio il faudrait un écart sept fois plus grand que le pire cas mesuré. Cela change en revanche le dimensionnement, voir plus bas : la plus grande des deux valeurs, couche au nœud ou pod, est celle qu'on compte (règle que j'ai proposée dans la relecture de BENCH-013, toujours à confirmer par Lucas). Pour O1 c'est 56,3 Mio, majorant 70,6. Pour O2, 5,9, majorant 61,7.

[FINOPS] Seuils de 4.1. Le rapport indique que la section n'a pas bougé depuis son relevé du 2026-11-23, avant toute lecture web ; je n'ai pas le condensat de référence sous les yeux, je me fie à la déclaration de [BENCH], comme pour BENCH-012 et BENCH-013. Seuil 1 : non franchi (18,8 et 16,0 Mo pour 112,5 : 16,7 % et 14,2 %). Seuil 2 : franchi par les deux, un `Pulled` à chaque exécution. Seuil 3 : non franchi (5,5 s pour 90 : 6,1 %). Seuil 4 : non franchi, ni à la valeur de la règle, ni au majorant. Chaque option perd donc un cran et finit à 4/5, comme dans le rapport. Je confirme la note d'empreinte. Le critère ne départage pas, et je n'ai rien à lui reprocher : les 2,8 Mo d'écart de volume font 2,2 s à 10 Mbit/s, soit 0,2 % du budget de 900 s.

[FINOPS] Lecture du seuil 2. D'accord avec la lecture à la lettre, comme dans BENCH-013 : la série a tourné sans miroir. Avec le miroir de l'ADR-011, les deux options regagnent un cran, 88 et 74 ; le classement ne bouge pas. L'image vient de docker.io pour les deux, donc aucun amont de plus pour zot. Le nœud émet deux `Pulled` par création pour la même image, sans que le fichier dise pourquoi (le second, en moins d'une seconde, ressemble à une nouvelle résolution au registre, ce que je ne peux pas confirmer). Il vaut la peine de le relever pour R-25, parce que chaque résolution sans miroir sort vers Docker Hub, pour les deux options à égalité.

[FINOPS] Cumul avec le premier `task up` (R-04). O1 n'ajoute rien : la stack de BENCH-005, déjà comptée, contient `valkey/valkey:9.1.4-alpine` à 18,8 Mo, et le rapport l'écrit juste. Le premier `task up` du profil standard reste à 1 802,1 Mo avec O1 (160,2 % du budget de 900 s à 10 Mbit/s, 16,0 Mbit/s au minimum), et passe à 1 799,3 Mo avec O2 (159,9 %). Pour le profil lite, qui n'a ni Flux (ADR-010, GATE 1), ni Keycloak, ni Mailpit, je retire 258,1 Mo de Flux aux 1 521,9 Mo de BENCH-011 : 1 263,8 Mo avec zot, 1 011,0 s à 10 Mbit/s, 112,3 % du budget, 11,2 Mbit/s au minimum pour le seul téléchargement. Sans zot, 1 186,1 Mo : 948,9 s, 105,4 %. C'est un calcul de [FINOPS] qui additionne des séries de plusieurs jours, un ordre de grandeur. Le cache pèse 18,8 Mo là-dedans, 15,1 s à 10 Mbit/s, 1,7 % du budget : même sans cache le lite resterait à 110,7 %. Le choix du moteur ne peut donc pas faire tenir le critère des 15 minutes, et ne peut pas non plus le faire manquer. Côté temps de démarrage, M1 vaut 5,5 s, image tirée comprise, soit 0,6 % du budget même si la couche passait en série avec les autres. Le cumul de la sensibilité du rapport se retrouve : 505,8 plus 18,8 font 524,6, et plus 16,0 font 521,8. Avec zot, la base vaut 583,5 Mo (BENCH-010) : 602,3 et 599,5, même effet.

[FINOPS] Mémoire. J'applique la méthode de BENCH-005, reprise de BENCH-010 à BENCH-013 : plancher multiplié par 1,5, arrondi au demi-gibioctet supérieur, plus 4 Gio pour le portable. Les planchers de l'ADR-012 et de BENCH-013 contiennent déjà le Valkey de BENCH-005, sans que sa part y soit isolée. Je compte donc par majorant, qui ajoute la couche sans rien retirer, comme dans BENCH-011. Profil lite : 1 186,6 Mio (ADR-012) plus 56,3 font 1 242,9, soit 1,8 Gio de plancher agrandi, donc 2,0 Gio de VM et 6,0 de portable, sans changer de palier. Il reste 122,4 Mio avant le palier de 2,5 Gio (108,1 avec le majorant de 70,6). Avec O2, plus 5,9, il en reste 172,8 (117,0 avec 61,7). Sur un portable de 8 Gio, la VM peut monter à 4,0 Gio, et le lite y garde 1 487,8 Mio de plancher. Profil standard : 2 310,3 Mio (BENCH-013, Mailpit au pod) plus 56,3 font 2 366,6, soit 3,5 Gio de VM et 7,5 de portable. Il ne reste que 22,7 Mio avant le palier de 4,0 Gio (8,4 avec le majorant), et ce palier tient encore sur 8 Gio, avec 364,1 Mio de plancher de reste (349,8 au majorant). Avec la somme des pods seule, 6,4 Mio, la marge est de 72,6. Le standard est donc sur 8 Gio dans tous les cas, mais à la limite d'un palier de VM, sans que le choix du moteur le décide, puisque Valkey est déjà dans ces planchers. Même réserve que dans BENCH-013 : ces chiffres mêlent des séries de jours différents.

[FINOPS] Côté GCP, je n'ai lancé aucune action cloud, et aucun budget n'est validable : la région n'est pas choisie et la grille de prix reste illisible (R-05). Le 2026-11-25, l'outil lit la page `https://cloud.google.com/memorystore/valkey/pricing` mais n'y trouve que son titre : ni grille, ni unité, ni région. Un extrait de moteur de recherche annonce un prix à l'heure pour une région américaine ; je ne l'écris pas, parce que je ne l'ai pas lu sur la page. Lucas lit la grille de Memorystore for Valkey avec le sélecteur de région, comme pour les autres services (R-05).

[FINOPS] Ce que je peux dire sans prix, pour Memorystore for Valkey, d'après les pages de Google lues le 2026-11-25 par un outil qui résume. Facturation par nœud et par heure : la page des engagements compte des nœuds facturables, un primaire et ses réplicas par partition [S48]. Le nombre de nœuds facturables est donc le nombre de partitions plus le nombre de réplicas, et un réplica double la facture d'une instance à une partition. Les engagements, à 20 % pour un an et 40 % pour trois ans, se paient chaque heure qu'on les utilise ou non, ne s'annulent pas, et ne couvrent ni le stockage, ni les sauvegardes, ni la persistance, ni la sortie de données [S48]. Pour une démo démontable (R-05, R-15) je n'en prends aucun. Tailles, d'après la page des nœuds [S49] : `shared-core-nano`, 1,4 Go au total dont 1,12 de clés inscriptibles, 0,5 vCPU, sans SLA, limite dure de 1,12 Go non modifiable, réservé au développement et aux essais, avec ou sans mode cluster ; `custom-pico`, 1,25 Go dont 1,08 inscriptibles, 2 vCPU, avec SLA, sans cluster seulement ; `custom-micro`, 2,5 Go dont 2 ; `custom-mini`, 3,75 Go dont 3 ; `standard-small`, 6,5 Go dont 5,2, avec ou sans cluster. La capacité minimale est celle d'un nœud, et une instance peut n'avoir aucun réplica (0 à 5 d'après la page). Memorystore met de côté une part de chaque nœud contre les dépassements de mémoire, et la page déconseille de dépasser la valeur par défaut de `maxmemory`. L'unité de « Go » n'est pas dite (Go ou Gio, 2 % d'écart, déjà soulevé dans BENCH-013). La formule du coût mensuel, sans chiffre : nœuds facturables, fois heures allumées (730 pour un mois plein), fois le prix horaire du type de nœud dans la région. Elle ne dépend d'aucun autre paramètre pour la partie nœuds.

[FINOPS] Trois postes de coût de Memorystore restent non lus : le point de terminaison Private Service Connect que la couche `gcp` ajoute au socle de l'ADR-008 (BENCH-014, section 5.7), le trafic qui le traverse, et le stockage des sauvegardes si elles sont actives. Je n'ai lu aucune fonction d'arrêt d'une instance, ni de franchise gratuite : une instance facture dès sa création, au prix de son type de nœud, même vide. Le plus petit nœud avec SLA (`custom-pico`) a un keyspace par défaut de 1,08 Go, soit environ huit fois la limite de 128 Mi que je propose pour le pod local : aucune taille de Memorystore ne colle au besoin de l'exemple (FR-009), qui tient en quelques dizaines de Mio, donc on prend le plus petit et on ne cherche pas à ajuster.

[FINOPS] Dimensionnement local, proposé pour l'ADR-015. Le pod au repos pèse 6,4 Mio et 0,2 % d'un cœur (soit environ 2 millicœurs), clés vides : aucune mesure sous charge n'existe. Je propose, comme valeurs de départ à vérifier sur le golden repo : demande mémoire de 64 Mi, limite de 128 Mi ; demande de CPU de 25m, sans limite de CPU (le cache n'a aucune raison d'être bridé sur un portable). Les 64 Mi font dix fois le repos, les 128 Mi vingt fois. Le pod est ainsi en classe Burstable, sous sa demande tant qu'il reste petit, donc peu exposé à l'éviction. En classe Guaranteed, le pod devrait avoir demande égale à la limite sur la mémoire et le CPU de chaque conteneur [S52], ce qui ne se justifie pas ici. Le moteur reçoit `maxmemory 64mb` (la moitié de la limite, pour les tampons de sortie des clients et la fragmentation) et `maxmemory-policy allkeys-lru`, que la doc de Valkey présente comme un bon choix quand on hésite, pour un cache sans persistance [S51]. Sans `maxmemory`, la doc dit que la limite par défaut sur 64 bits est l'absence de limite : le pod grossit jusqu'à sa limite de conteneur. Le contrôle est une écriture au-delà de `maxmemory` dans la matrice : zéro redémarrage (colonne `restarts` du script), working set sous la limite. Au pire, le cache plein coûterait 128 Mio, 121,6 de plus qu'au repos, soit 1,5 % d'un portable de 8 Gio.

[FINOPS] Dimensionnement sur `gcp`, pour l'ADR-015. Mode `CLUSTER_DISABLED`, zéro réplica, un seul nœud, de type `shared-core-nano` en dev et pour la démo. `custom-pico` seulement si un environnement demande un SLA. Tout autre type de nœud, tout réplica et tout mode cluster passent par un budget revalidé (principe X). La politique conftest de l'ADR-008 sur le tier s'étend au type de nœud et au nombre de réplicas : elle refuse un plan hors de ces valeurs, sans que l'ajout d'un nœud ne passe par un simple changement de variable. Le budget se calcule avec la formule ci-dessus, une fois la grille lue pour la région choisie, avant la GATE 2. Une alerte budget ne plafonne rien (R-05) : le seul garde-fou réel est le démontage et le `ttl` en étiquette. L'instance est étiquetée `owner`, `env` et `ttl`.

[FINOPS] Note de coût. Je confirme 4/5 pour les deux options, comme dans BENCH-012 et BENCH-013. Sur le PC, ni licence ni service payant. Sur `gcp`, les deux variantes de Memorystore se facturent par nœud et par heure, et je n'ai lu le prix d'aucune : la page de Redis donnait une 404 le 2026-11-23 (S29), celle de Valkey n'a pas de grille lisible. Le coût ne départage pas, les totaux restent 86 et 72. La réserve du critère passe de « prix illisibles » à « prix à lire avec la région » : aucune action de l'équipe n'y change rien.

[FINOPS] Le deuxième palier de volume. Mon avis est non, et je retire la proposition que je faisais dans BENCH-011. Les quatre rapports donnent des volumes de couche de 15,1 Mo (Mailpit), 18,8 Mo (Valkey), 127,0 (CloudNativePG), 176,9 (smtp4dev), 265,1 (Keycloak), 463,8 (Zitadel) et 679,5 (Zalando). Il n'y a pas de coupure naturelle dans cette suite. Un palier à 225 Mo, par exemple, enlèverait un cran à Keycloak, retenu, et à Zitadel, au même titre, sans les séparer ; il faudrait un troisième palier vers 450 Mo pour isoler Zitadel. Aucun verdict de BENCH-011 à BENCH-014 n'en dépend : Zalando finit dernier avec ou sans, et la différence de volume entre Keycloak et Zitadel (198,7 Mo, 159 s à 10 Mbit/s) se lit déjà dans la ligne de budget que chaque relecture écrit. BENCH-014 montre le même défaut vu de l'autre côté : les deux options sont sous le seuil et la règle ne les distingue pas, alors que ce qui compte pour R-04 est le cumul. Le vrai outil est le budget par étape d'ENF-01, déjà dans la mitigation de R-04 et pas encore fixé. Règle si Lucas répond oui malgré tout : un seul cran de plus, à 225 Mo (180 s à 10 Mbit/s, 20 % du budget de 900 s), écrit dans le gabarit par Lucas, haché en 4.1, valable pour les couches à venir seulement. Sans rétroaction sur les notes existantes. Et seulement s'il remplace le budget par couche de R-04, pas en plus.

[FINOPS] D'accord. Le coût ne départage pas, l'empreinte non plus, et le verdict tient sur la licence et la gouvernance, avec 14 points d'écart. Sur le PC, O1 ne coûte rien au premier `task up`, et O2 économiserait 2,8 Mo. Les conditions ci-dessous sont à reprendre dans l'ADR-015.

[FINOPS] Questions ouvertes. L'origine des 50,4 Mio (hypothèse de cache de pages à confirmer par `memory.stat` et par un témoin, non bloquante pour l'ADR). La politique d'éviction par défaut de Memorystore for Valkey, non lue : celle du pod local doit lui être égale pour la parité de comportement. Les prix de Memorystore pour la région choisie, et le coût du point de terminaison Private Service Connect, du trafic et des sauvegardes. L'unité des « Go » des pages de Google. Le lite, composé sans Flux : ma lecture de l'ADR-010, à confirmer par [ARCHI]. La lecture d'une couche dans le bruit (majorant pour la note, pod pour le dimensionnement), toujours en attente de Lucas depuis BENCH-013.

#### Corrections demandées au rapport par [FINOPS]

1. Section 4.4, point 1, et section 8 : ajouter que les échantillons du nœud ne sont pas écrits en TSV, et les bornes (Valkey 24,3 à 70,6 Mio, Redis moins 29,9 à 61,7).
2. Section 4.4, point 1, et 5.6 : « au plus 70,5 Mio » vaut pour l'écart d'une même ronde ; le majorant de la règle de BENCH-013 vaut 70,6 (644,6 moins 574,0). Écrire les deux.
3. Section 5.6, sensibilité : ajouter le cumul avec la base mesurée avec zot (583,5 Mo, BENCH-010), soit 602,3 et 599,5 Mo, même effet.
4. Section 7, paragraphe R-04 : ajouter le chiffre du profil lite (1 263,8 Mo, 112,3 %, 11,2 Mbit/s), le standard (1 802,1 Mo avec O1, 1 799,3 avec O2), et le plancher mémoire (section Mémoire de cette relecture).
5. Section 5.9 : remplacer « grilles illisibles » par le mode de facturation lu (nœud et heure, engagements) et la liste des postes non lus (point de terminaison, trafic, sauvegardes).
6. Section 7, condition 5 : ajouter le nombre de réplicas à la politique conftest, et fixer le type de nœud et le mode ci-dessous.
7. Section 9 : ajouter S47 à S52 ci-dessous. Section 10 : mettre à jour la ligne [FINOPS].

#### Conditions de [FINOPS] pour l'ADR-015

1. Volume. L'image reste la variante Alpine de `valkey/valkey` figée par condensat : le cache ajoute 0 Mo net au premier `task up` (R-04 : 1 802,1 Mo pour le standard, 160,2 % du budget à 10 Mbit/s ; lite environ 1 263,8 Mo, 112,3 %). Passer à la variante trixie ajoute 26,0 Mo (44,8 contre 18,8) et rouvre R-04 avec un nouveau chiffre.
2. Demandes et limites du pod sur `local`, explicites dans le manifest : mémoire 64 Mi demandés et 128 Mi en limite, CPU 25m demandés et pas de limite de CPU ; `maxmemory 64mb` et `maxmemory-policy allkeys-lru` écrits dans la configuration du conteneur d'initialisation. Valeurs de départ à confirmer sur le golden repo. Contrôle de la matrice : écriture au-delà de `maxmemory`, zéro redémarrage, working set sous la limite.
3. Plancher mémoire. La couche entre dans les planchers pour la plus grande de ses deux valeurs, 56,3 Mio (majorant 70,6). Le lite reste à 2,0 Gio de VM et 6,0 Gio de portable, avec 108 à 122 Mio avant le palier suivant. Le standard reste à 3,5 Gio de VM et 7,5 Gio de portable, avec 8 à 23 Mio avant le palier de 4,0 Gio, qui tient encore sur 8 Gio. Le golden repo mesure le nœud avec toute la stack et remplace ces ordres de grandeur.
4. Cause des 50,4 Mio. Une série courte de [BENCH], avant d'écrire le plancher dans le PRD : `memory.stat` du nœud et RSS par processus à chaque échantillon, témoins sans serveur pour les deux images, ordre permuté, cinq exécutions au moins par option, échantillons du nœud écrits en TSV. Si l'écart est dans le cache de pages, le plancher peut redescendre vers la valeur du pod.
5. Taille de l'instance sur `gcp`. Mode `CLUSTER_DISABLED`, zéro réplica, un nœud, `shared-core-nano` en dev et pour la démo ; `custom-pico` seulement avec un besoin de SLA ; tout autre type, tout réplica et tout mode cluster exigent un budget revalidé. La politique conftest de l'ADR-008 refuse un plan hors de ces valeurs. Aucun engagement d'utilisation.
6. Budget avant la GATE 2 (principe X, R-05). Lucas lit la grille de Memorystore for Valkey pour la région choisie. [FINOPS] calcule alors : nœuds facturables, fois heures allumées, fois prix horaire du type de nœud, plus les trois postes non lus (point de terminaison Private Service Connect, trafic, sauvegardes). Aucun `tofu apply` avant l'accord de Lucas sur ce montant. Ressources étiquetées `owner`, `env`, `ttl`.
7. Parité d'éviction. La politique d'éviction par défaut de Memorystore for Valkey est lue et datée avant l'ADR ; celle de `local` lui est égale, ou l'écart est écrit dans l'ADR.

[BENCH] Suite donnée aux corrections demandées par [FINOPS] (2026-11-25), sans réécrire la relecture ci-dessus. Appliquées : 1 (section 4.4 point 1 et section 8 : échantillons du nœud non écrits, bornes), 2 (4.4 et 5.6 : 70,5 d'une même ronde, majorant 70,6), 3 (5.6 : cumul avec la base mesurée avec zot), 4 (section 7 : profils lite et standard, plancher mémoire), 5 (5.9 : facturation lue, postes non lus), 6 (condition 5 de la section 7), 7 (sources S47 à S52 en section 9, ligne de ce tableau). Les sections « Corrections demandées » et « Sources de [FINOPS] » sont conservées ou déplacées au mot près ; la ligne du tableau de cette section est rédigée par [BENCH], la relecture n'en fournissant pas. Les totaux cités dans la relecture (86 et 72, 88 et 74, 14 points) précèdent la correction de maturité de [SECU] : ils valent 86 et 69, 88 et 71, 17 points. Les 7 conditions de [FINOPS] et les 8 de [SECU] vont à l'ADR-015.
