# BENCH-014. Moteur du cache

| Champ | Valeur |
| --- | --- |
| Identifiant | BENCH-014 |
| Sujet | Moteur du cache du projet généré : image dans le cluster kind de la cible `local`, et variante de Memorystore sur `gcp` |
| Statut | brouillon |
| Ouvert le | 2026-11-21 |
| Mis à jour le | 2026-11-24 |
| Auteur | [BENCH] |
| Relecteurs | [SECU] pour les licences et les CVE, [FINOPS] pour les coûts |
| Périmètre | Projet généré sur PC (cluster kind, ADR-004) et projet généré sur GCP (Memorystore, ADR-008) |
| Choix du PRD | Aucune ligne propre au cache. US-004 : le service de chaque brique vient du catalogue, par cible. Le brief (sections 5 et 6) prévoit Memorystore sur GCP et Valkey sur le PC |
| ADR lié | À écrire par [ARCHI], après les mesures |
| Verdict proposé | Provisoire : O1, Valkey, 78 sur 90 hors empreinte, devant Redis 7.2 (64) ; 86 contre 72 sur 100 avec la lecture provisoire de l'empreinte. La série de mesure, interrompue par une mise en veille le 2026-11-24, est à relancer (section 4.4) |

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
| O1. Valkey | `valkey/valkey:9.1.4-alpine@sha256:56729e68…b37893f0` | docker.io, aussi publiée sur ghcr.io et public.ecr.aws | Construites pour linux/amd64, linux/arm64, linux/arm/v7 et linux/ppc64le ; le tag liste amd64, arm64, arm v7 et ppc64le | La communauté Valkey, dépôt `valkey-io/valkey-container`. Hors du programme d'images officielles : `library/valkey` n'existe pas | Construction avec `provenance: false`, aucune étape de signature |
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
le script dans `versions.tsv`. C'est la machine de BENCH-011.

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
   cache, partagée avec les autres benchmarks.
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
suivante tournera avec le commit `1bcf41d` (section 4.4).

[BENCH] Inventaire des commandes qui créent, modifient ou suppriment un
conteneur ou un réseau, en tête du script pour la relecture [SECU] :
`kind create cluster`, qui lance le nœud par `docker run --privileged` et crée
le réseau `kind` s'il manque ; `kind delete cluster` ; `docker network rm
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

### 4.4 Résultats

[BENCH] État au 2026-11-24 : test de fumée réussi, série interrompue par une
mise en veille, série à relancer. Le SHA-256 de la section 4.1 a été vérifié
le 2026-11-24 à 00:42:48 UTC, avant la première mesure : il vaut toujours
`67a35b6b…96f6`.

[BENCH] Volumes au registre (M4), lus par le script le 2026-11-24, sans
tirage, en Mo compressés de 10⁶ octets. Cette lecture ne dépend ni de la
machine ni de l'alimentation : elle compte pour la note.

| Image | amd64 (noté) | arm64 | À 10 Mbit/s, amd64 |
| --- | --- | --- | --- |
| O1 `valkey/valkey:9.1.4-alpine` | 18,8 | 19,3 | 15,1 s |
| O2 `redis:7.2.17-alpine` | 16,0 | 16,5 | 12,8 s |
| Variante `valkey/valkey:9.1.4-trixie` (sensibilité) | 44,8 | 45,2 | 35,9 s |
| Variante `redis:7.2.17-bookworm` (sensibilité) | 43,2 | 43,1 | 34,6 s |

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
série se relance une fois le Mac sur secteur, capot ouvert.

[BENCH] Relevés du SHA-256 de la section 4.1, faits dans le dossier de
travail de [BENCH] et déclarés ici, faute de témoin tiers :

| Relevé | Heure UTC | SHA-256 | Remarque |
| --- | --- | --- | --- |
| Écriture des seuils | 2026-11-21, 22:05 | sans objet | Texte écrit avant toute lecture web de cette passe |
| Premier relevé | 2026-11-22, 10:23:10 | `eed23fdd2a5af33f407d7ab0bc7a4eaedc6b4fc58ad1e396035e850c7597aefa` | La passe a été coupée par la limite d'usage entre l'écriture et ce relevé ; aucune lecture entre les deux. Le texte disait « relevé au même moment », ce qui n'était plus vrai |
| Relevé de référence | 2026-11-23, 20:37:31 | `67a35b6b52de50988ea2776a04b0a32208f107fd257598c72b2d90b8d7ae96f6` | Seule différence : la phrase sur le moment du relevé, corrigée. Toujours avant toute lecture web ou de registre |

[BENCH] La section entre dans le premier commit du rapport. L'horodatage
d'un commit local reste déclaratif tant que la branche n'est pas poussée.

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

[BENCH] Notes provisoires du 2026-11-23, sur 90 : l'empreinte attend les
mesures. Chaque option est notée comme un couple, le moteur sur `local` et sa
variante de Memorystore sur `gcp`.

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
| O2. Redis 7.2 | 5/5 | 15 | Dépôt créé en 2009 ; ligne 7.2 en « Extended », maintenue jusqu'au 2029-12-01, servie par défaut par Memorystore for Redis | [S9], [S12], [S24] |

### 5.4 Activité et maintenance, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. Valkey | 5/5 | 10 | 973 commits humains en 12 mois ; cinq lignes corrigées le même jour, le 2026-11-18 (9.1.4, 9.0.8, 8.1.12, 8.0.13, 7.2.16), puis 9.2.0 le 2026-11-19 ; cinq releases de la ligne 9.1 depuis le 2026-05-19 | [S2], [S30] |
| O2. Redis 7.2 | 4/5 | 8 | 637 commits humains en 12 mois ; cinq releases de la ligne 7.2 dans la même période, de 7.2.13 à 7.2.17. Réserve : la ligne 7.2 ne reçoit que les correctifs de sécurité et les corrections critiques ; le travail du projet porte sur la ligne 8, sous une autre licence | [S10], [S12], [S30] |

### 5.5 Sécurité (CVE, réactivité), poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. Valkey | 3/5 | 6 | Neuf avis en 12 mois, huit élevés et un moyen, chacun corrigé par une release de chaque ligne maintenue ; quatre releases de sécurité pour la ligne 9.1. Signalement privé, divulgation coordonnée avec une liste d'éditeurs. La réserve demande une action : trois avis sur neuf n'ont pas de CVE, donc échappent aux scanners ; l'image n'a ni provenance ni signature, et la dérogation de l'ADR-012 ne la couvre pas, puisqu'elle sort du programme d'images officielles | [S2], [S5], [S7], [S38], [S42] |
| O2. Redis 7.2 | 3/5 | 6 | Quatre releases de sécurité de la ligne 7.2 en 12 mois, dont trois CVE publiées par avis le 2026-05-05. Le 2026-10-26, Redis et Valkey corrigent le même jour une faille de même description, un dépassement de tampon sur un `PUBLISH` relayé par le bus du cluster. Signalement par un programme de divulgation ou par GitHub. La réserve demande une action : les correctifs de 7.2.15, 7.2.16 et 7.2.17 n'ont ni avis ni CVE, d'où une veille des notes de version ; l'image officielle n'a pas de signature vérifiable, couverte par la dérogation de l'ADR-012 | [S2], [S5], [S10], [S13], [S42] |

[BENCH] Le contrôle de M6 (mot de passe imposé, absent des lignes de
commande) vaut pour les deux options, avec les mêmes manifests : il confirme
la mise en œuvre, il ne départage pas les moteurs. Un échec chez une seule
option ferait baisser sa note.

### 5.6 Empreinte sur PC (RAM, CPU, démarrage), poids 10

[BENCH] Pas encore notée : seul M4 est acquis, et la série de trois
exécutions doit encore tourner (section 4.4). La règle est celle de
`TEMPLATE.md`, avec les seuils de la section 4.1, hachés avant toute lecture
de taille d'image. Lecture provisoire, à confirmer par la série :

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. Valkey | provisoire 4/5 | provisoire 8 | Seuil 1 tenu : 18,8 Mo en amd64, 16,7 % du seuil de 112,5 Mo (mesuré). Seuil 2 franchi au test de fumée : l'image est tirée à chaque création. Seuils 3 et 4 loin au test de fumée : 5,7 s, et 4,4 Mio pour les pods de la couche | [M4] ; test de fumée pour M1, M2 et M5 |
| O2. Redis 7.2 | provisoire 4/5 | provisoire 8 | Seuil 1 tenu : 16,0 Mo en amd64, 14,2 % du seuil (mesuré). Seuil 2 franchi au test de fumée. Seuils 3 et 4 loin : 4,5 s et 4,2 Mio | [M4] ; test de fumée pour M1, M2 et M5 |

[BENCH] Si la série confirme le test de fumée, le critère ne départage pas
les options : chacune perd le seul cran du retéléchargement, commun à toute
image que tire un nœud neuf sans miroir.

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

[BENCH] Note de jugement, provisoire : l'essai qui la fondera est la série du
script, M1, M6 et M7 sans intervention.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. Valkey | 4/5 | 8 | Mêmes manifests, même forme de configuration et même variable client que Redis ; le fichier de configuration du dépôt documente chaque directive. Réserve : essai pas encore fait, et documentation de Memorystore for Valkey récente sur l'authentification (GA le 2026-09-18) | [S19], [S36] |
| O2. Redis 7.2 | 4/5 | 8 | Même forme ; `redis.conf` du tag 7.2.17 documente chaque directive. Réserve : essai pas encore fait, et le projet écrit « We strongly recommend using the latest available version », soit la ligne 8 | [S12], [S37] |

[BENCH] Le critère ne départage pas les options tant que l'essai n'a pas
tourné : les deux serveurs partagent l'aide, les directives et le client
utilisés par le script [S36], [S37].

### 5.9 Coût (managé ou opérationnel), poids 5

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. Valkey | 4/5 | 4 | Aucune licence ni service payant sur le PC. Sur `gcp`, grilles de prix illisibles le 2026-11-23 ; seul fait lu, le plus petit nœud, `shared-core-nano`, réservé au développement, et `custom-pico` avec SLA. Réserve : prix à lire par [FINOPS] (R-05) | [S23], [S29] |
| O2. Redis 7.2 | 4/5 | 4 | Aucune licence ni service payant sur le PC. Sur `gcp`, grille illisible, même réserve | [S29] |

[BENCH] Le critère ne départage pas les options : aucune n'a de prix lu, et
le coût de sortie de la ligne 7.2 est déjà compté en licence (5.1).

## 6. Grille pondérée

[BENCH] Grille provisoire du 2026-11-24, sur 90 ; l'empreinte complètera le
total sur 100 après la série. Avec la lecture provisoire de la section 5.6,
4/5 pour chaque option, les totaux seraient 86 et 72 sur 100.

| Critère | Poids | O1. Valkey | O2. Redis 7.2 |
| --- | --- | --- | --- |
| Critères éliminatoires (section 3) | éliminatoire | passe | passe |
| Licence et liberté d'usage | 15 | 5/5, 15 pts | 3/5, 9 pts |
| Gouvernance (fondation, multi-vendeurs) | 15 | 5/5, 15 pts | 2/5, 6 pts |
| Maturité et adoption | 15 | 4/5, 12 pts | 5/5, 15 pts |
| Activité et maintenance | 10 | 5/5, 10 pts | 4/5, 8 pts |
| Sécurité (CVE, réactivité) | 10 | 3/5, 6 pts | 3/5, 6 pts |
| Empreinte sur PC (RAM, CPU, démarrage) | 10 | en attente | en attente |
| Portabilité multi-cloud | 10 | 4/5, 8 pts | 4/5, 8 pts |
| Expérience dev et documentation | 10 | 4/5, 8 pts | 4/5, 8 pts |
| Coût (managé ou opérationnel) | 5 | 4/5, 4 pts | 4/5, 4 pts |
| Total provisoire | 90 | 78 / 90 | 64 / 90 |

## 7. Verdict proposé

[BENCH] Proposition provisoire : O1, Valkey, à 78 sur 90, devant Redis 7.2 à
64. L'écart de 14 points ne peut pas s'inverser par l'empreinte, qui vaut au
plus 10 points, et M4 en fixe déjà un cran pour chaque option : seuil 1 tenu
par les deux. Avec la lecture provisoire de l'empreinte, 86 contre 72 sur 100.

[BENCH] Pourquoi. L'écart vient de la licence (6 points) et de la gouvernance
(9 points), moins la maturité (3 points rendus à Redis), plus l'activité
(2 points). Valkey est sous BSD-3-Clause, porté par LF Projects, avec un
comité où aucune organisation ne dépasse un tiers [S4], [S6]. Redis 7.2
garde la BSD-3-Clause, mais sur une ligne figée que l'éditeur a déjà quittée
deux fois par un changement de licence [S9], [S11]. Le principe V tranche
dans le même sens que la grille.

[BENCH] Sensibilité, sur les notes provisoires :

| Lecture | O1 | O2 | En tête | Règle |
| --- | --- | --- | --- | --- |
| Grille provisoire | 78 | 64 | O1 | Sans objet |
| Licence de O2 à 4 (la ligne 7.2 seule compte) | 78 | 67 | O1 | Aucune contredite : jugement sur la trajectoire |
| Gouvernance de O2 à 3 (127 auteurs) | 78 | 67 | O1 | Aucune contredite : jugement |
| Les deux à la fois, et maturité de O1 à 3 | 75 | 70 | O1 | Aucune contredite : trois jugements |
| O2 en Redis 8.12 sous AGPLv3 | 78 | parité perdue face à Memorystore (7.2) | O1 | Contredit la condition 3 de la section 2 |
| Empreinte provisoire, 4/5 pour chacune (section 5.6) | 86 sur 100 | 72 sur 100 | O1 | Aucune contredite ; série à faire |
| Empreinte au pire pour O1 : seuil 1 tenu (mesuré), seuils 2 à 4 franchis, 2/5 ; O2 à 5/5 | 82 sur 100 | 74 sur 100 | O1 | Cas extrême, contraire au test de fumée |
| Miroir zot de l'ADR-011 : seuil 2 lu comme un retéléchargement depuis Internet ; docker.io servi pour les deux | 88 sur 100 | 74 sur 100 | O1 | Contredit la lettre du seuil 2, mesuré sans miroir |
| Volume cumulé avec la plate-forme de base (505,8 Mo, BENCH-011) contre 500 Mo : 524,6 et 521,8 Mo | 86 sur 100 | 72 sur 100 | O1 | Contredit la deuxième règle de la GATE 1 ; les deux sont au-dessus, même effet |

[BENCH] Cumul avec le premier `task up` (R-04), pour [FINOPS]. La stack de
BENCH-005, comptée dans R-04, contient déjà `valkey/valkey:9.1.4-alpine`
(18,8 Mo en amd64) : O1 ne change rien au volume du premier lancement, et O2
le réduirait de 2,8 Mo (16,0 au lieu de 18,8).

[BENCH] Gouvernance : l'option proposée ne dépend pas d'un éditeur unique.
Sur `gcp`, Memorystore reste un service de Google seul, comme toute cible
managée (lecture de l'ADR-009).

[BENCH] Réserves. L'image `valkey/valkey` n'a ni signature ni provenance, et
sort de la dérogation de l'ADR-012 : il lui faut sa propre dérogation à
ENF-03, ou une autre voie (question 3). La ligne 9.2 est sortie le
2026-11-19, et Memorystore ne la sert pas : la ligne locale suit celle de
Memorystore, pas la dernière du projet. Prochaine vérification : à la sortie
d'une ligne 9.2 dans Memorystore, ou au plus tard le 2027-05-23.

[BENCH] Conditions proposées pour l'ADR, à confirmer après les mesures et les
relectures, chacune vérifiable par la matrice (principe I) :

1. Ligne commune. La ligne de Valkey est celle que Memorystore sert par
   défaut, relevée à chaque release du blueprint et tenue en une seule valeur
   pour les deux couches, comme la majeure de Postgres dans l'ADR-012.
   Contrôle : la matrice compare `valkey_version` (M8) à cette valeur.
2. Image et durcissement. Image par condensat, Deployment d'une réplique sans
   persistance, profil `restricted`, configuration écrite depuis le Secret par
   un conteneur d'initialisation, comme dans le script. Contrôle : la matrice
   rejoue M6, et échoue si un manifest porte le mot de passe dans `command`,
   `args` ou `env` du serveur.
3. Secret `cache-auth`, type `Opaque`, clé `password`, sur les deux cibles. Sur
   `gcp`, `authorization_mode = "TOKEN_AUTH"` ; le producteur du Secret
   attend la ressource `google_memorystore_auth_token` dans une version
   publiée du provider, et le jeton tombe dans l'état chiffré (condition 2 de
   l'ADR-008). L'authentification IAM reste une évolution, avec son propre
   ADR, puisqu'elle change le code client sur `gcp`.
4. Réseau `gcp` : une politique de connexion de service pour
   `gcp-memorystore`, et les ports de la section 3 ouverts au seul cluster
   GKE. [OPS] l'écrit, [SECU] relit.
5. Mode sans cluster (`CLUSTER_DISABLED`) et type de nœud écrit, la politique
   conftest de l'ADR-008 sur le tier s'étendant au type de nœud ; le choix
   revient à [FINOPS].

[BENCH] Suites. Les mesures, puis les relectures [SECU] et [FINOPS], puis
l'ADR de [ARCHI]. Une entrée `redis` au catalogue (ADR-009) : ligne `local`
en `oss`, « Valkey, image `valkey/valkey` dans un Deployment de la couche
`local` », BSD-3-Clause, gouvernance `foundation` (LF Projects), statut actif,
sources [S1], [S3], [S6] ; ligne `gcp` en `managed`, Memorystore for Valkey
[S18]. Standard exposé : `resp`.

## 8. Limites et biais

| Limite | Effet possible sur le verdict | Ce qui la lèverait |
| --- | --- | --- |
| Série interrompue le 2026-11-24 par une veille capot fermé, sur batterie ; seuls M4 et un test de fumée d'une exécution sont acquis | Empreinte notée provisoirement ; elle ne peut pas inverser l'ordre (section 7) | Relancer la série, Mac sur secteur et capot ouvert, script du commit `1bcf41d` |
| Test de fumée à repos raccourci (30 s au lieu de 120) | Mémoire et CPU au repos relevés plus tôt que le protocole | La série, au protocole de la section 4.3 |
| Bruit du nœud plus grand que la couche (4 Mio par les pods) | M2 au nœud peut sortir négatif ou au hasard ; aucune incidence sur la note tant qu'il reste loin de 512 Mio | Médianes de trois exécutions ; somme des pods en sensibilité |
| Condensat de O1 lu par un outil qui résume les pages | Une erreur de recopie | Recoupé avec le condensat de BENCH-005 ; le script refuse un condensat absent du registre |
| Seuils écrits le 2026-11-21, relevés le 2026-11-22 puis le 2026-11-23, après une coupure | L'antériorité des seuils repose sur la déclaration de [BENCH] | Pousser la branche, qui date le texte chez GitHub |
| Volumes de Valkey connus avant les seuils (BENCH-005, ADR-011) | Seuils taillés sur mesure | Seuils repris de BENCH-011 sans changement (section 4.1) |
| Employeurs déclarés sur les profils GitHub | Parts de AWS et de Redis approximatives ; quatre auteurs du top 10 de Redis sans employeur déclaré | Statistiques de la fondation, ou fichier de mainteneurs |
| Correctif servi par Memorystore non publié pour Valkey, affiché à 7.2.0 pour Redis | Parité de correctif inconnue sur `gcp` | Lire `INFO server` sur une instance, au premier apply de la GATE 2 |
| Grilles de prix de Memorystore illisibles le 2026-11-23 | Coût noté sans prix | Lecture par [FINOPS] ou par Lucas (R-05) |
| M6 (c) lit les processus du conteneur du cache, pas ceux du nœud | Un argument vu par containerd échappe au contrôle | Le contrôle statique de la condition 2 sur les manifests |
| Option pressentie par le brief : Valkey | Aucune note ne lui donne d'avantage | Sans objet |

## 9. Sources

[BENCH] Lues le 2026-11-23, sauf mention. Les fichiers de dépôt GitHub ont été
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

## 10. Relectures

| Relecteur | Porte sur | Date | Avis |
| --- | --- | --- | --- |
| [SECU] | Licences, critères éliminatoires, sécurité, inventaire du script | à venir | à venir |
| [FINOPS] | Coût, seuils d'empreinte | à venir | à venir |

[BENCH] Points à relire en priorité. Pour [SECU] : l'inventaire en tête du
script, la dérogation à ENF-03 que demanderait `valkey/valkey`, la mise en
œuvre du mot de passe (conteneur d'initialisation, volume en mémoire), et la
note de licence de Redis 7.2. Pour [FINOPS] : les prix de Memorystore, et les
seuils de la section 4.1 repris de BENCH-011.
