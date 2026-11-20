# BENCH-011. Postgres dans le cluster local

| Champ | Valeur |
| --- | --- |
| Identifiant | BENCH-011 |
| Sujet | Forme de Postgres dans le cluster kind de la cible `local` : manifests écrits à la main ou opérateur |
| Statut | brouillon |
| Ouvert le | 2026-11-20 |
| Mis à jour le | 2026-11-20 |
| Auteur | [BENCH] |
| Relecteurs | [SECU] pour les licences et les CVE, [FINOPS] pour les coûts |
| Périmètre | Projet généré sur PC (cluster kind, ADR-004). La cible `gcp` garde Cloud SQL (principe III) |
| Choix du PRD | US-004 : « CloudNativePG en local, Cloud SQL sur GCP », exemple du brief à confirmer en phase 1 |
| ADR lié | ADR-012, à écrire par [ARCHI] |
| Verdict proposé | O1, Postgres sans opérateur (StatefulSet écrit à la main, image officielle) : 88/100, devant CloudNativePG (83) et l'opérateur de Zalando (62). L'écart avec CloudNativePG tient en deux crans de notes de jugement (section 7) |

## 1. Contexte

[BENCH] Question posée : sous quelle forme Postgres tourne dans le cluster kind
du projet généré, sur la cible `local` : des manifests écrits à la main autour
de l'image officielle, ou un opérateur.

[BENCH] Pourquoi maintenant. L'[ADR-006](../adr/ADR-006-orchestration-locale.md)
a laissé hors de sa décision « la forme de Postgres et du cache dans la couche
`local`, manifest simple comme dans l'essai ou opérateur ». La spec du golden
repo en fait une exigence : « La base de données locale MUST suivre le verdict
de BENCH-011 ; tant qu'il n'est pas rendu, la couche locale de la base reste à
écrire » (FR-017) [S40]. Lucas a demandé le 2026-11-20 un benchmark avant
cette couche. Sur `gcp`, la base est Cloud SQL, service managé imposé par le
principe III ([ADR-008](../adr/ADR-008-modules-opentofu-gcp.md)) : ce
benchmark ne la touche pas.

[BENCH] Ce qui en dépend. US-005 : `task up` démarre l'API, le front, Postgres
et le cache dans le cluster local sans autre étape (principe VII), et le profil
suit la RAM disponible. La spec du golden repo [S40] précise : le
rechargement redéploie le composant modifié « sans redémarrer la base ni
perdre ses données » (US-1, scénario 3 ; FR-007) ; une relance garde les
secrets existants « et les données restent lisibles » (US-2, scénario 3) ; les
secrets locaux sont aléatoires, d'au moins 32 caractères, jamais dans un
fichier, une variable affichée ou un argument (FR-004) ; chaque image et chaque
dépendance tirées d'un registre sont figées par condensat ou par somme de
contrôle (FR-008) ; le profil lite tient sur un portable de 8 Gio (SC-008).
ENF-01 fixe le budget de 15 minutes, ENF-02 la parité : seule la couche de
cible change. Le DSI en tire pour ce benchmark une exigence de plus : la même
version majeure que Cloud SQL.

[BENCH] Contraintes déjà posées par les ADR. ADR-006 : aucun outil de boucle
derrière `task up`, qui enchaîne `docker build`, `kind load` et
`kubectl apply -k`, et Helm reste hors des prérequis ; un opérateur s'installe
donc par ses manifests publiés, versionnés avec leur SHA-256 (condition 4 de
l'[ADR-004](../adr/ADR-004-cluster-local.md)). ADR-007 : `task up` crée les
Secrets par un tube, avec des valeurs aléatoires, et le nom et les clés de
chaque Secret sont les mêmes sur les deux cibles (conditions 1 et 5).
ADR-004 : mineure 1.36 de Kubernetes, images figées par condensat. ADR-005 et
ADR-010 : rien d'un outil propre à une cible dans la couche commune. Principes
II, III, V, VI et VIII. Risques R-04 (15 minutes), R-20 (identifiants par
défaut), R-25 (registres publics) et R-28 (secrets locaux en clair).

[BENCH] Option pressentie : CloudNativePG. US-004 du PRD cite l'exemple du
brief, « CloudNativePG en local, Cloud SQL sur GCP », « à confirmer en
phase 1 » [S41]. Elle est notée comme les autres, avec le même script.

[BENCH] Hors champ : le cache (Valkey) ; Cloud SQL et sa configuration
(ADR-008) ; les sauvegardes, la haute disponibilité et les montées de version
majeure en local, le profil lite ne demandant qu'une instance ; la solution de
R-25, que traite BENCH-010 ; Windows (Q5).

## 2. Options étudiées

| Option | En une phrase | Version examinée | Publiée le | Sources |
| --- | --- | --- | --- | --- |
| O1. Sans opérateur | Un StatefulSet et un Service écrits à la main, l'image officielle `postgres`, un volume de la classe de stockage par défaut de kind | PostgreSQL 18.7, image `postgres:18.7-trixie` | 2026-11-12 (PostgreSQL 18.7) | [S1], [S2], [S3] |
| O2. CloudNativePG | Opérateur de la CNCF : un objet `Cluster` décrit l'instance ; l'opérateur crée le pod, le volume, les Services et l'utilisateur de l'application | 1.30.2, fichier `cnpg-1.30.2.yaml` de la release ; opérande `postgresql:18.7-minimal-trixie` | 2026-11-17 | [S5], [S6], [S7], [S8] |
| O3. Opérateur de Zalando | Opérateur de Zalando SE : un objet `postgresql` décrit l'instance, servie par l'image Spilo (Postgres et Patroni) | 2.0.3, manifests kustomize du tag ; Spilo `spilo-18:4.1-p2`, image par défaut de sa configuration | 2026-10-02 | [S17], [S18], [S19], [S20] |

[BENCH] Image de O1. La variante Debian (`trixie`) plutôt qu'Alpine, pour
comparer à fonction égale : l'opérande de CloudNativePG est construite sur
Debian avec les paquets du PGDG [S8], et la documentation de l'image
officielle rappelle que les variantes Alpine reposent sur musl, dont la gestion
des locales diffère de glibc [S2]. La variante `18.7-alpine`, celle de la
stack d'essai de BENCH-005, va dans la sensibilité.

[BENCH] Image de O2. L'image `minimal`, la plus légère que le projet maintient.
L'image par défaut de 1.30.2 est `18.7-system-trixie` [S6], que le dépôt des
images annonce dépréciée ; la variante `standard` ajoute PGAudit, pgvector,
toutes les locales et JIT [S8]. Leurs volumes vont dans la sensibilité.

[BENCH] Version de O2. La 1.30.2 a trois jours le jour de la lecture, alors que
le principe VI fait attendre 7 jours aux mises à jour automatiques. Elle est
mesurée parce que c'est la dernière stable, comme le veut le gabarit. Le
blueprint pourrait la prendre dès le 2026-11-24, ou tout de suite au titre de
l'exception de sécurité du principe VI : ses notes listent des correctifs de
vulnérabilités Go (GO-2026-6617 et suivantes) et passent l'opérande par défaut
à 18.7, « which fixes several CVEs » [S6] ; le billet du projet dit l'avoir
avancée « given the security relevance of the PostgreSQL 18.7 release »
[S47]. La 1.30.1 date du 2026-09-23 [S9].

[BENCH] Choix de la troisième option. Cinq opérateurs Postgres repérés hors
CloudNativePG, lus le 2026-11-20 :

| Opérateur | Licence | Gouvernance | Activité sur 12 mois | Suite |
| --- | --- | --- | --- | --- |
| Zalando | MIT [S17] | Éditeur unique, Zalando SE ; 7 mainteneurs, tous en `@zalando.de` [S21] ; 41 auteurs humains, dont 56 % des commits par les auteurs du top 10 qui déclarent Zalando | 5 releases stables, 115 commits humains [S22], [S23] | Retenu |
| Percona | Apache-2.0, avec la mention de copyright de Crunchy Data [S30] | Éditeur unique, Percona ; 19 auteurs humains, dont 78 % des commits par les auteurs du top 10 qui déclarent Percona | 5 releases stables, 407 commits humains [S31], [S23] | Non retenu |
| Crunchy Data (PGO) | Code sous Apache-2.0 ; les images que l'installation documentée télécharge relèvent des « Crunchy Data Developer Program terms » [S32] | Éditeur unique | 6.0.4 et 5.8.10 le 2026-11-16 [S33] | Non retenu : l'installation de référence n'est pas libre, il faudrait construire ses propres images |
| StackGres (OnGres) | AGPL-3.0, approuvée OSI [S34] | Éditeur unique | Dépôt GitHub en miroir de GitLab, sans release publiée sur GitHub [S34] | Non retenu : AGPL (R-10), installation documentée par une commande en une ligne et non par un manifest de release |
| Kubegres | Apache-2.0 [S35] | Éditeur unique, Reactive Tech | Dernière release v1.19 le 2025-01-04 [S35] | Éliminé : aucune release depuis 12 mois |

[BENCH] Entre Zalando et Percona, la licence ne départage pas : MIT et
Apache-2.0 sont toutes deux approuvées par l'OSI [S4]. Percona est plus actif,
407 commits humains contre 115, pour le même nombre de releases. Zalando
l'emporte sur la gouvernance, critère de poids 15 : deux fois plus d'auteurs,
et une part plus faible de l'éditeur. Deux faits hors de la demande du DSI
vont dans le même sens. La maturité : un dépôt créé en 2017, contre 2021 pour
Percona [S31], et un usage « in production for over five years » chez Zalando,
déclaré par le projet [S17]. La portabilité : le guide de démarrage de Zalando
cite kind [S19], alors que la page des prérequis de Percona 3.1.0 liste
minikube sans citer kind, et ne déclare GKE que de 1.34 à 1.35 [S31]. Les
comptes de commits et les employeurs viennent de l'API de GitHub, employeurs
déclarés sur les profils [S23].

[BENCH] Options repérées mais non étudiées : Percona, Crunchy Data, StackGres
et Kubegres, pour les raisons du tableau ; Helm, exclu de `task up` par
l'ADR-006, n'est pas une option mais une voie d'installation, écartée pour les
trois.

## 3. Critères éliminatoires

[BENCH] Seuil de release : 2025-11-20, douze mois avant la vérification.

| Option | Licence open source | Ni archivé ni en maintenance | Release de moins de 12 mois | Vérifié le | Résultat |
| --- | --- | --- | --- | --- | --- |
| O1. Sans opérateur | Oui : PostgreSQL License [S10], approuvée OSI [S4] ; empaquetage de l'image sous MIT [S3] | Oui : PostgreSQL 18 maintenu jusqu'au 2030-11-14 [S1] ; dépôt de l'image non archivé, dernier commit le 2026-11-19 [S3] | Oui, PostgreSQL 18.7 le 2026-11-12 [S11] | 2026-11-20 | Retenue |
| O2. CloudNativePG | Oui : Apache-2.0 pour l'opérateur et pour les images d'opérande [S5], [S8], approuvée OSI [S4] | Oui : dépôt non archivé, dernier commit le 2026-11-20 [S5] ; 1.30 maintenue jusqu'à environ mars 2027 [S7] | Oui, 1.30.2 le 2026-11-17 [S6] | 2026-11-20 | Retenue |
| O3. Opérateur de Zalando | Oui : MIT pour l'opérateur [S17], Apache-2.0 pour Spilo [S20], approuvées OSI [S4] | Oui : dépôt non archivé, dernier commit le 2026-11-19 [S17] | Oui, 2.0.3 le 2026-10-02 [S18] | 2026-11-20 | Retenue |

[BENCH] Parité de version (ENF-02). Cloud SQL propose PostgreSQL 9.6 à 18,
avec 18 par défaut et 18.6 comme mineure courante [S12]. Les trois options
servent PostgreSQL 18 (M8) ; aucune n'est éliminée à ce titre. PostgreSQL 19 est
sorti le 2026-11-19 [S1], mais ni Cloud SQL ni CloudNativePG 1.30 (15 à 18)
ne le proposent [S7], [S12].

[BENCH] Options éliminées : aucune parmi les trois étudiées. Kubegres l'est
avant l'étude (section 2).

## 4. Mesures

### 4.1 Ce qui est mesuré

[BENCH] Seuils d'empreinte écrits le 2026-11-20 à 20:06 UTC, avant toute
mesure et avant tout test de fumée. Le SHA-256 de cette section, du titre
« 4.1 » jusqu'à la ligne qui précède le titre « 4.2 », est relevé au même
moment dans le dossier de travail de [BENCH] (section 8). Chaque option part
de 5 et perd un cran par seuil dépassé (règle de `TEMPLATE.md`, section 5.6).
Postgres est une couche de la stack : d'après la deuxième règle de la GATE 1,
il se note contre ses propres seuils, et son cumul avec la plate-forme de base
va dans la sensibilité. Les quatre seuils reprennent ceux de la dernière
couche notée, l'outil GitOps de BENCH-009, sans adaptation :

1. volume compressé des images de la couche au-delà de 112,5 Mo, lu sur
   linux_amd64 (première règle de la GATE 1) : 90 s à 10 Mbit/s, soit 10 % du
   budget de 900 s d'ENF-01 ;
2. au moins une image de la couche retéléchargée à chaque création du
   cluster, cache Docker de l'hôte plein : repris de BENCH-003 ;
3. installation jusqu'à « prêt » (médiane de M1) au-delà de 90 s, 10 % du
   budget, images tirées par le nœud sur le réseau du poste ;
4. mémoire de la couche au repos (médiane de M2) au-delà de 512 Mio, un
   seizième d'un portable de 8 Gio, lue au nœud moins le nœud de base (troisième
   règle de la GATE 1).

[BENCH] Biais à déclarer : les tailles compressées de plusieurs images
candidates ont été lues dans les registres pendant la recherche, avant
l'écriture de ces seuils. Aucun seuil n'en est tiré : les quatre valeurs sont
celles de BENCH-009, posées le 2026-11-19, et découlent du budget d'ENF-01, du
débit de 10 Mbit/s et du portable de 8 Gio. Les parts elles-mêmes (10 % du
budget, un seizième de 8 Gio) restent un choix de [BENCH] : le budget par
étape d'ENF-01 n'est pas fixé (R-04).

[BENCH] « Prêt » veut dire : une requête `SELECT 1` réussit avec le mot de
passe de l'application, par le Service que l'application utilisera, depuis un
pod client du cluster. Le contrôle passe par `kubectl exec` dans ce pod, une
fois par seconde ; l'instant retenu est le premier de trois succès de suite,
comme dans BENCH-009.

| ID | Mesure | Unité | Critère alimenté | Script |
| --- | --- | --- | --- | --- |
| M1 | Installation jusqu'à « prêt » : du premier `kubectl apply` de la couche (opérateur compris) à la première requête authentifiée réussie, nœud neuf, images tirées par le nœud | s | Empreinte sur PC | `tests/bench/bench-011-postgres.sh` |
| M2 | Mémoire de la couche au repos, 120 s après « prêt » : nœud avec la couche moins nœud de base (M9), médianes de trois échantillons espacés de 10 s ; somme des pods de la couche en sensibilité | Mio | Empreinte sur PC | idem |
| M3 | CPU des pods de la couche au même moment | % d'un cœur | Empreinte sur PC | idem |
| M4 | Volume compressé des images de la couche, par architecture, lu au registre | Mo | Empreinte sur PC (ENF-01, R-04) | idem |
| M5 | Images de la couche retéléchargées à chaque création du cluster, d'après les événements `Pulled` du nœud | oui ou non | Empreinte sur PC (R-25) | idem |
| M6 | Donnée gardée : une ligne écrite, puis relue après (a) suppression du pod Postgres, (b) réapplication des manifests de la couche, (c) suppression de l'objet qui porte Postgres puis réapplication, cluster gardé | oui ou non | Expérience dev, portabilité | idem |
| M7 | Retour à « prêt » après la suppression du pod Postgres de M6 (a) | s | Expérience dev | idem |
| M8 | Version servie (`SHOW server_version`), comparée à la version par défaut de Cloud SQL | texte | Portabilité (ENF-02) | idem |
| M9 | Mémoire du nœud de base : kind seul, même image et même configuration (option `none` du script) | Mio | Base de M2 | idem |

### 4.2 Machine de mesure

| Élément | Valeur |
| --- | --- |
| Modèle | Apple Mac16,7 |
| Processeur | Apple M4 Pro, 14 cœurs |
| Mémoire | 24 Gio |
| Système | macOS 27.2.1 (build 26B131) |
| Moteur de conteneurs | OrbStack, Docker Engine 29.8.2, cgroup v2 (non libre, R-26) |
| Ressources allouées | Machine virtuelle d'OrbStack : 14 CPU, 11,73 Gio (`docker info`) |
| Versions mesurées | kind 0.33.0, `kindest/node:v1.36.4` figée par condensat, kubectl 1.37.1 ; O1 `postgres:18.7-trixie` ; O2 CloudNativePG 1.30.2 et `postgresql:18.7-minimal-trixie` ; O3 opérateur de Zalando 2.0.3 et `spilo-18:4.1-p2`. Toutes figées par condensat dans le script, vérifiées au démarrage |
| Charge parasite | Applications de bureau ouvertes, sessions Claude Code. BENCH-010 partage le moteur : le verrou `bench-lock-s4` empêche deux séries simultanées, et le script relève les clusters kind présents dans `load.tsv` |

[BENCH] Mise en œuvre par option, chacune par sa voie documentée sans Helm
(ADR-006) :

- O1 : un Service `postgres` et un StatefulSet d'une réplique, écrits dans le
  script. L'image lit l'utilisateur et le mot de passe dans les fichiers du
  Secret (`POSTGRES_USER_FILE`, `POSTGRES_PASSWORD_FILE`) [S2], tourne sous
  l'UID 999 sans privilège (`runAsNonRoot`, capacités retirées), et garde ses
  données sous `/var/lib/postgresql`, le volume de l'image à partir de
  PostgreSQL 18 [S2]. Le volume vient d'un `volumeClaimTemplate` de 1 Gio.
- O2 : `kubectl apply --server-side` du fichier `cnpg-1.30.2.yaml` de la
  release, commande documentée [S26], puis un `Cluster` d'une instance dont
  `bootstrap.initdb.secret` désigne le Secret créé par le script [S27], et
  dont `imageName` porte le tag et le condensat de l'opérande, la majeure étant
  lue dans le tag [S28]. Le
  manifest nomme l'image de l'opérateur deux fois, dans `image` et dans la
  variable `OPERATOR_IMAGE_NAME` qui sert aux pods de Postgres : le script fige
  les deux par condensat [S42].
- O3 : `kubectl apply -k` des quatre fichiers de `manifests/kustomization.yaml`
  au commit du tag v2.0.3, voie documentée [S19], puis un objet `postgresql`
  d'une instance, version 18. L'opérateur enregistre lui-même ses CRD au
  démarrage [S24]. Le Secret de l'utilisateur `app` porte le nom imposé par le
  gabarit `secret_name_template` de la configuration [S25] ; le script le crée
  sous ce nom avant l'objet, pour voir si l'opérateur le garde (M6).

[BENCH] Dans les trois cas, le mot de passe sort de `/dev/urandom` et passe par
un tube à `kubectl create -f -`, comme le veut la condition 1 de l'ADR-007 :
40 caractères alphanumériques, jamais dans un fichier, une variable ou un
argument. Le pod client utilise l'image de serveur de l'option, déjà tirée par
le nœud, pour ne rien ajouter au volume ; il lit le mot de passe dans le
Secret par une variable d'environnement.

### 4.3 Protocole

1. État de départ : aucun cluster `celian-bench-011`. Le script ne construit
   ni ne retire aucune image : chaque exécution crée un nœud kind neuf, dont
   le containerd ne voit pas le cache Docker du poste, et qui tire donc toutes
   les images de la couche sur le réseau (R-25). L'image du nœud reste en
   cache, partagée avec les autres benchmarks.
2. Commandes : celles de la section 4.2, identiques à chaque exécution.
   L'objet qui porte Postgres est appliqué en boucle, une fois par seconde,
   tant que l'API le refuse : CRD pas encore enregistrées (O3) ou webhook pas
   encore prêt (O2). Ce temps compte dans M1.
3. Fin de M1 : le premier de trois `SELECT 1` réussis de suite, lancés une fois
   par seconde par `kubectl exec` dans le pod client.
4. Repos (M2, M3) : le pod client est arrêté, puis trois échantillons à partir
   de 120 s après « prêt », espacés de 10 s, médiane des trois. Nœud par
   `docker stats --no-stream` sur le conteneur du nœud ; pods de la couche par
   l'API Summary du kubelet. Le nœud de base (M9) suit le même relevé, sans
   couche ni pod client.
5. Donnée gardée (M6) : une ligne écrite après « prêt », puis relue après
   chaque étape, (a), (b) et (c), qui se termine par une nouvelle attente de
   « prêt ». Pour (c), le script relève aussi le nombre de PVC et l'empreinte
   SHA-256 tronquée de la valeur du Secret, jamais la valeur elle-même.
6. Téléchargements : événements `Pulled` du nœud (M5) ; volumes lus au
   registre par `docker manifest inspect -v`, sans tirage (M4).
7. Trois exécutions par option, entrelacées dans l'ordre nœud de base, O1, O2,
   O3, avec 15 s de pause entre deux. Le script prend le verrou commun au
   démarrage et le rend à la fin, erreur comprise.

[BENCH] Pour refaire la mesure :

```bash
BENCH_LOCK=/chemin/vers/un/verrou tests/bench/bench-011-postgres.sh /chemin/vers/un/dossier/vide
```

[BENCH] Sans argument, le script crée un dossier temporaire ; un dossier
passé en argument doit être absent ou vide. `OPTIONS`, `RUNS`, `IDLE_WAIT`,
`BENCH_LOCK` et `NODE_RESTART` règlent l'essai. Le script refuse de démarrer
si le cluster `celian-bench-011` existe ; son `trap` n'est posé qu'après ce
contrôle et après le verrou, donc un refus ne supprime rien. Il passe
shellcheck et tourne sous le bash 3.2 de macOS. Aucun `curl`, aucun
`docker run`, `docker exec` ni `docker create` : tout contrôle passe par un pod
du cluster. `docker start` n'apparaît que derrière `NODE_RESTART=1`.

[BENCH] Redémarrage du nœud non mesuré. Le relancer demande `docker stop`
puis `docker start` sur le conteneur du nœud, comme dans BENCH-007, et
`docker start` attend l'accord de Lucas. Le script le prévoit derrière
`NODE_RESTART=1`, désactivé par défaut (section 8).

### 4.4 Résultats

[BENCH] Série retenue lancée le 2026-11-20 de 21:53 à 22:45 UTC, verrou
`bench-lock-s4` pris, dans l'ordre nœud de base, O1, O2, O3, trois fois
(dossier `series-1` du dossier de travail de [BENCH]). Aucun autre conteneur
ni cluster kind ne tournait au début de chaque exécution (`load.tsv`) ; la
charge moyenne de l'hôte était de 9,1 sur une minute au début de la première
exécution de O3, de 2,9 à 3,9 ailleurs. Un test de fumée a précédé, après
l'écriture des seuils (section 8).

| Mesure | Option | Exécution 1 | Exécution 2 | Exécution 3 | Médiane | Écart |
| --- | --- | --- | --- | --- | --- | --- |
| M1, installation jusqu'à « prêt » | O1. Sans opérateur | 10,1 s | 8,9 s | 7,8 s | 8,9 s | 2,3 s |
| M1 | O2. CloudNativePG | 33,8 s | 36,6 s | 33,8 s | 33,8 s | 2,8 s |
| M1 | O3. Opérateur de Zalando | 43,6 s | 44,4 s | 44,4 s | 44,4 s | 0,8 s |
| Nœud au repos | O1. Sans opérateur | 652,3 Mio | 594,3 Mio | 648,5 Mio | 648,5 Mio | 58,0 Mio |
| Nœud au repos | O2. CloudNativePG | 760,8 Mio | 759,5 Mio | 772,3 Mio | 760,8 Mio | 12,8 Mio |
| Nœud au repos | O3. Opérateur de Zalando | 792,6 Mio | 768,3 Mio | 797,3 Mio | 792,6 Mio | 29,0 Mio |
| M9, nœud de base | kind seul | 582,0 Mio | 618,3 Mio | 600,4 Mio | 600,4 Mio | 36,3 Mio |
| M2, couche au nœud | O1. Sans opérateur | | | | 48,1 Mio | |
| M2 | O2. CloudNativePG | | | | 160,4 Mio | |
| M2 | O3. Opérateur de Zalando | | | | 192,2 Mio | |
| Somme des pods de la couche (sensibilité) | O1. Sans opérateur | 26,4 Mio | 25,9 Mio | 26,6 Mio | 26,4 Mio | 0,7 Mio |
| Somme des pods | O2. CloudNativePG | 88,2 Mio | 100,5 Mio | 100,7 Mio | 100,5 Mio | 12,5 Mio |
| Somme des pods | O3. Opérateur de Zalando | 112,9 Mio | 104,6 Mio | 101,9 Mio | 104,6 Mio | 11,0 Mio |
| M3, CPU des pods au repos | O1. Sans opérateur | 1,4 % | 1,7 % | 1,8 % | 1,7 % | 0,4 % |
| M3 | O2. CloudNativePG | 1,0 % | 0,8 % | 1,1 % | 1,0 % | 0,3 % |
| M3 | O3. Opérateur de Zalando | 0,9 % | 0,6 % | 0,4 % | 0,6 % | 0,5 % |
| M7, retour à « prêt » après suppression du pod | O1. Sans opérateur | 3,3 s | 3,4 s | 3,3 s | 3,3 s | 0,1 s |
| M7 | O2. CloudNativePG | 12,3 s | 12,4 s | 12,3 s | 12,3 s | 0,1 s |
| M7 | O3. Opérateur de Zalando | 16,4 s | 15,3 s | 15,2 s | 15,3 s | 1,2 s |

[BENCH] M2 se lit en médianes : médiane du nœud de l'option moins médiane du
nœud de base (M9), soit 48,1 Mio pour O1 (648,5 moins 600,4), 160,4 pour O2
et 192,2 pour O3. Le nœud varie jusqu'à 58 Mio d'une exécution à l'autre
(O1), comme BENCH-005 l'avait relevé pour kind seul : la médiane de trois
exécutions peut tomber sur un niveau haut ou bas. La somme des pods de la
couche, lue par l'API Summary, va en sensibilité : 26,4 Mio pour O1 ; 100,5
pour O2, dont 34,6 pour l'opérateur en médiane des neuf échantillons ; 104,6
pour O3, dont 15,1 pour l'opérateur. L'écart entre
la somme des pods et le nœud vient du serveur d'API et d'etcd, que chargent
les CRD et les webhooks des opérateurs (troisième règle de la GATE 1).

[BENCH] Volume (M4) et images retéléchargées (M5), en Mo compressés de
10⁶ octets, lus au registre :

| Option | amd64 (noté) | arm64 | Détail amd64 | Cumul avec la plate-forme de base (505,8 Mo), amd64 | M5, à chaque création |
| --- | --- | --- | --- | --- | --- |
| O1. Sans opérateur | 168,5 | 167,1 | `postgres:18.7-trixie` 168,5 | 674,3 | Oui, l'image de Postgres, tirée en 4,7 à 6,3 s |
| O2. CloudNativePG | 127,0 | 126,9 | opérateur 39,1 ; opérande `minimal` 87,8 | 632,8 | Oui, les deux images, tirées en 2,9 à 4,1 s et 3,8 à 6,6 s |
| O3. Opérateur de Zalando | 679,5 | 661,6 | opérateur 50,8 ; Spilo 628,7 | 1 185,3 | Oui, les deux images, Spilo tirée en 27,2 à 28,1 s |

[BENCH] Variantes lues au registre, non tirées : `postgres:18.7-alpine`
120,3 Mo en amd64 ; opérande `standard` de CloudNativePG 224,8 Mo et
`system` 277,8 Mo, soit 264,0 et 316,9 Mo avec l'opérateur. À 10 Mbit/s, le
seuil de 112,5 Mo vaut 90 s ; O1 en demande 134,8 s, O2 101,6 s, O3 543,6 s.

[BENCH] Donnée gardée (M6), sur les trois exécutions. La classe de stockage
relevée à chaque exécution est `standard`, provisionneur `rancher.io/local-path`,
politique de récupération `Delete` : un PVC supprimé emporte sa donnée.

[BENCH] Résultats de M6 :

| Option | (a) pod supprimé | (b) couche réappliquée | (c) objet supprimé puis réappliqué | PVC après la suppression (c) | Secret après (c) |
| --- | --- | --- | --- | --- | --- |
| O1. Sans opérateur | Gardée 3 fois sur 3 | Gardée 3 fois sur 3, pod non redémarré | Gardée 3 fois sur 3 | 1, gardé (rétention `Retain` du StatefulSet) | Le Secret du script, inchangé |
| O2. CloudNativePG | Gardée 3 fois sur 3 | Gardée 3 fois sur 3, pod non redémarré | Perdue 3 fois sur 3 : le `Cluster` recréé repart d'un volume vide | 0, supprimé avec le `Cluster` | Le Secret du script, inchangé : l'opérateur ne le supprime pas |
| O3. Opérateur de Zalando | Gardée 3 fois sur 3 | Gardée 3 fois sur 3, pod non redémarré | Gardée 3 fois sur 3 | 1, gardé | Supprimé par l'opérateur avec l'objet, puis régénéré avec une valeur neuve, 3 fois sur 3 ; le mot de passe en base suit la nouvelle valeur |

[BENCH] Version servie (M8), identique aux trois exécutions : O1 et O2 servent
« 18.7 (Debian 18.7-1.pgdg13+5) », O3 « 18.3 (Ubuntu 18.3-1.pgdg22.04+1) ».
Cloud SQL sert 18.6 [S12].

[BENCH] Secret et redémarrages. Dans les trois options, le Secret créé par le
script avant l'installation garde sa valeur jusqu'à « prêt » : CloudNativePG
l'emploie par `bootstrap.initdb.secret`, et l'opérateur de Zalando adopte celui
qui porte le nom de son gabarit. Aucun conteneur de O1 ni de O2 n'a
redémarré avant le repos. Pour O3, l'opérateur s'arrête en erreur à son
premier démarrage sur chaque cluster neuf (M10, relevé ajouté après le test de
fumée) : « could not register Postgres CustomResourceDefinition: could not
update customResourceDefinition "": resource name may not be empty ». Il
réussit au redémarrage que Kubernetes relance, et ce délai compte dans M1. La
recherche de ce message dans les tickets du projet ne trouve aucun ticket
ouvert [S22].

[BENCH] Écart entre la documentation et la mesure pour Zalando : la page des
paramètres écrit que l'opérateur supprime les PVC avec l'objet
(`enable_persistent_volume_claim_deletion`, `true` par défaut) [S24], alors que
le PVC est resté et la donnée relue dans trois exécutions sur trois. La
cause n'a pas été cherchée ; la conclusion de M6 (c) pour O3 ne vaut que pour
ce délai entre suppression et réapplication.

## 5. Notation par critère

[BENCH] Chaque option retenue reçoit une note entière de 0 à 5 sur chaque critère.
Les points valent note × poids / 5. Un cran de note vaut donc 3 points sur un
critère de poids 15, 2 points sur un poids 10 et 1 point sur le coût. Les
poids sont ceux de la section 8 du brief et ne changent pas d'un rapport à
l'autre.

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

[BENCH] Chaque option est notée comme couche Postgres de la cible `local`,
seule, puisque la cible `gcp` garde Cloud SQL. PostgreSQL lui-même, ses CVE
et sa licence sont communs aux trois options : les notes portent sur ce que
chaque option ajoute autour, l'empaquetage, l'opérateur et l'image servie.

### 5.1 Licence et liberté d'usage, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. Sans opérateur | 5/5 | 15 | PostgreSQL License, approuvée par l'OSI ; empaquetage de l'image sous MIT ; les manifests sont écrits par CELIAN, sous Apache-2.0 comme le générateur | [S2], [S3], [S4], [S10] |
| O2. CloudNativePG | 5/5 | 15 | Apache-2.0 pour l'opérateur et pour les scripts des images d'opérande, construites sur les paquets du PGDG ; aucun changement de licence relevé | [S4], [S5], [S8] |
| O3. Opérateur de Zalando | 4/5 | 12 | MIT pour l'opérateur, Apache-2.0 pour Spilo. Réserve : Spilo embarque une vingtaine d'extensions sous leurs propres licences ; TimescaleDB y est construite en édition Apache par défaut, mais les options de construction de l'image publiée n'ont pas été lues | [S4], [S17], [S20] |

### 5.2 Gouvernance (fondation, multi-vendeurs), poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. Sans opérateur | 4/5 | 12 | Rien d'autre que PostgreSQL et Kubernetes. PostgreSQL : équipe principale de sept membres chez six organisations, 54 contributeurs majeurs dont Microsoft et AWS (dix chacun). Kubernetes : gradué à la CNCF le 2018-03-06. Réserve : l'image officielle est tenue par deux mainteneurs du programme d'images officielles de Docker | [S37], [S38], [S44] |
| O2. CloudNativePG | 4/5 | 12 | Projet de la CNCF, Incubating depuis le 2026-11-02. Réserve : comité de pilotage et mainteneurs du cœur, cinq personnes, toutes chez EDB ; 83 % des commits humains de l'année par les auteurs du top 10 qui déclarent EDB. Deux comités sur quatre comptent Verito Digital, GEICO et Upbound, et un vote équilibré par organisation reste à adopter (ticket #68) | [S13], [S14], [S23] |
| O3. Opérateur de Zalando | 2/5 | 6 | Éditeur unique, Zalando SE, sans fondation ; 7 mainteneurs, tous chez Zalando. 41 auteurs humains en 12 mois, dont 56 % des commits par les auteurs du top 10 qui déclarent Zalando. Le principe V demanderait un ADR pour justifier l'écart | [S21], [S23] |

### 5.3 Maturité et adoption, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. Sans opérateur | 5/5 | 15 | PostgreSQL publie une majeure par an et maintient chacune cinq ans ; l'image officielle existe depuis 2014. Supprimer un StatefulSet ne supprime pas ses volumes, et sa politique de rétention est stable depuis Kubernetes 1.32 | [S1], [S3], [S39] |
| O2. CloudNativePG | 4/5 | 12 | Dépôt créé en 2022, accepté à la CNCF le 2025-01-21, Incubating par vote du TOC. 56 organisations dans `ADOPTERS.md`, dont EDB pour son service de base de données ; l'annonce de la CNCF, écrite par les mainteneurs, cite IBM, Google Cloud, Microsoft Azure et Tesla parmi plus de 50 adoptants en production. Réserve : le niveau Incubating date de dix-huit jours, et la liste d'adoptants est déclarative | [S5], [S13], [S29], [S46] |
| O3. Opérateur de Zalando | 4/5 | 12 | Dépôt créé en 2017, « used in production for over five years » chez Zalando, déclaré par le projet. Réserve : aucune liste d'adoptants ; la 2.0.0 de juillet 2026 a dû être republiée en 2.0.1 pour une CRD qui cassait les chaînes GitOps | [S17], [S18] |

### 5.4 Activité et maintenance, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. Sans opérateur | 5/5 | 10 | PostgreSQL sort une mineure au moins tous les trois mois ; 18.7 est du 2026-11-12, et l'image `18.7-trixie` la sert au jour de la mesure, le 2026-11-20 (M8). Dépôt de l'image : 52 commits en 12 mois, dont 38 du bot de reconstruction | [S1], [S3], [S11], [M8] |
| O2. CloudNativePG | 5/5 | 10 | 16 releases stables en 12 mois, de 1.26.3 à 1.30.2, jusqu'à trois mineures corrigées le même jour (1.30.0, 1.29.2 et 1.28.4 le 2026-06-29) ; 597 commits humains par 77 auteurs ; dernier commit le 2026-11-20. Images d'opérande reconstruites chaque semaine | [S8], [S9], [S23] |
| O3. Opérateur de Zalando | 3/5 | 6 | 5 releases stables en 12 mois, 115 commits humains par 41 auteurs. La réserve demande une action : l'image Spilo par défaut de 2.0.3 vient d'un tag du 2026-04-13 et sert PostgreSQL 18.3 (M8), publiée le 2026-02-26, quatre mineures derrière 18.7 ; aucune image Spilo plus récente n'est publiée sous un tag 4.1-p3 ou 4.2-p1 | [S18], [S20], [S22], [S23], [S43], [S48], [M8] |

### 5.5 Sécurité (CVE, réactivité), poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. Sans opérateur | 4/5 | 8 | Rien d'autre que le serveur : ni opérateur, ni webhook, ni droit sur les Secrets du cluster. L'image sert 18.7, qui corrige 52 vulnérabilités, et tourne ici sans root, capacités retirées, mot de passe lu dans un fichier du Secret, authentification `scram-sha-256` par défaut. Réserve : ce durcissement est écrit et tenu par CELIAN ; Docker retire Docker Content Trust pour ses images officielles sans remplaçant documenté, donc aucune signature vérifiable n'a été trouvée (ENF-03), comme pour les images que `task up` construit (ADR-006) | [S2], [S11], [S45], [M1], [M8] |
| O2. CloudNativePG | 3/5 | 6 | Quatre avis en 12 mois, dont deux critiques (élévation vers le superutilisateur par l'exportateur de métriques, puis par des opérateurs SQL), un élevé et un moyen, tous corrigés le jour de leur publication sur chaque mineure maintenue. Images signées par cosign, conteneurs en `runAsNonRoot` et `readOnlyRootFilesystem`, politique de signalement avec délais. La réserve demande une action : l'opérateur crée, lit, modifie et supprime les Secrets de tout le cluster, et trois des quatre avis manquent à la base mondiale de GitHub : veille au dépôt | [S15], [S16], [S42] |
| O3. Opérateur de Zalando | 2/5 | 4 | L'image par défaut sert 18.3 (M8), sans les correctifs de 18.4, 18.6 et 18.7, dont 52 vulnérabilités pour 18.7 seule. Spilo tourne en root par défaut, élévation de privilèges permise ; l'opérateur crée et modifie les CRD et les Secrets du cluster. Aucun avis publié ; signalement par courriel, sans délai annoncé. Contourner demande de construire sa propre image Spilo | [S11], [S21], [S24], [S25], [S36], [M8] |

[BENCH] Les CVE de PostgreSQL lui-même ne départagent pas : la page de
sécurité du projet en liste pour la 18 dans les mineures 18.2, 18.4, 18.6 et
18.7 [S36], et une option qui sert la dernière mineure les a toutes. Elles
pèsent sur O3, dont l'image par défaut reste en 18.3.

[BENCH] Images, constat commun : tout ce que les trois options exécutent est
désigné par condensat dans le script, y compris la variable
`OPERATOR_IMAGE_NAME` de CloudNativePG et les images que la configuration de
Zalando n'active pas (pgbouncer, sauvegarde logique) [S42], [S25]. Les cinq
images portent des attestations de construction (provenance, SBOM) au
registre [S43]. Seule CloudNativePG documente une signature cosign [S15].

### 5.6 Empreinte sur PC (RAM, CPU, démarrage), poids 10

[BENCH] Règle de `TEMPLATE.md` (section 5.6), seuils écrits en 4.1 avant toute
mesure : chaque option part de 5 et perd un cran par seuil dépassé. Volume lu
sur l'amd64, mémoire au nœud moins le nœud de base.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. Sans opérateur | 3/5 | 6 | Deux seuils dépassés : 168,5 Mo en amd64 (seuil 1, 112,5 Mo), retéléchargés à chaque création (seuil 2). Prête en 8,9 s et 48,1 Mio au nœud, sous leurs seuils | [M1], [M2], [M4], [M5] |
| O2. CloudNativePG | 3/5 | 6 | Deux seuils dépassés : 127,0 Mo en amd64 (seuil 1), retéléchargés à chaque création (seuil 2). Prête en 33,8 s et 160,4 Mio au nœud, sous leurs seuils | [M1], [M2], [M4], [M5] |
| O3. Opérateur de Zalando | 3/5 | 6 | Deux seuils dépassés : 679,5 Mo en amd64 (seuil 1), six fois le seuil, retéléchargés à chaque création (seuil 2). Prête en 44,4 s et 192,2 Mio au nœud, sous leurs seuils | [M1], [M2], [M4], [M5] |

[BENCH] Le critère ne départage pas : les trois options perdent les deux
mêmes crans. Les écarts restent réels et la note ne les voit pas, faute de
seuil entre 112,5 Mo et 679,5 Mo, ni entre 0 et 512 Mio. O1 tient en 48,1 Mio au
nœud, contre 160,4 pour CloudNativePG et 192,2 pour Zalando, et devient prête
en 8,9 s, contre 33,8 et 44,4. En volume, CloudNativePG est la plus légère,
127,0 Mo contre 168,5 pour O1, et O3 pèse six fois le seuil, 543,6 s à
10 Mbit/s. Aucune option n'est à moins de 10 % d'un seuil : CloudNativePG
dépasse celui du volume de 12,9 %.

### 5.7 Portabilité multi-cloud, poids 10

[BENCH] La couche ne tourne que sur `local` ; sur `gcp`, l'application parle à
Cloud SQL. La note mesure donc deux choses : la couche tourne-t-elle sur tout
cluster conforme, et respecte-t-elle le contrat que la couche `gcp` partage,
un Secret de nom et de clés fixés (condition 5 de l'ADR-007) et la même
version majeure que Cloud SQL (ENF-02).

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. Sans opérateur | 5/5 | 10 | Objets du cœur de Kubernetes seulement ; images publiées pour huit architectures. Lit le Secret `db-auth` créé par le script, de nom et de clés choisis par CELIAN ; sert 18.7, même majeure que Cloud SQL, qui sert 18.6. Secret et donnée gardés dans les trois cas de M6 | [M6], [M8], [S12], [S38] |
| O2. CloudNativePG | 5/5 | 10 | Tourne sur tout Kubernetes de 1.34 à 1.36, dont la mineure de l'ADR-004 ; images amd64 et arm64. Accepte le même Secret `db-auth` par `bootstrap.initdb.secret`, sans le modifier ; sert 18.7. Ses CRD ne sortent pas de la couche `local`, comme le groupe `gateway.envoyproxy.io` de l'ADR-005 | [M6], [M8], [S7], [S8], [S27] |
| O3. Opérateur de Zalando | 3/5 | 6 | Tourne sur Kubernetes 1.27 et plus. La réserve demande une action : le nom du Secret vient du gabarit de l'opérateur, et l'opérateur supprime puis régénère ce Secret avec l'objet (M6 c), même quand il ne l'a pas créé ; il sert 18.3, en retard sur la 18.6 de Cloud SQL. Il faudrait changer le gabarit, `enable_secrets_deletion` et l'image | [M6], [M8], [S17], [S24], [S25] |

### 5.8 Expérience dev et documentation, poids 10

[BENCH] Note de jugement. L'essai qui la fonde : installation par la voie
documentée sans Helm, puis les trois cas de M6, trois fois par option, sans
intervention.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. Sans opérateur | 4/5 | 8 | Prête du premier coup à chaque exécution, sans boucle d'attente sur l'API, donnée gardée dans les trois cas. De retour en 3,3 s après la suppression du pod. Rien à apprendre hors de Kubernetes et de la documentation de l'image. Réserve : une soixantaine de lignes de manifest à écrire et à tenir ; les variables `POSTGRES_*` ne servent qu'à l'initialisation, si bien qu'un Secret recréé sur un volume existant ne change pas le mot de passe ; ni sauvegarde ni montée de majeure outillées | [M1], [M6], [M7], [S2] |
| O2. CloudNativePG | 4/5 | 8 | Prête sans intervention à chaque exécution ; de retour en 12,3 s après la suppression du pod ; un `Cluster` d'une quinzaine de lignes ; 59 pages de documentation par version, greffon `kubectl cnpg`. Réserve : l'objet est refusé tant que le webhook n'est pas prêt, d'où une boucle d'attente dans `task up` ; supprimer le `Cluster` supprime son volume et la donnée (M6 c), ce que la commande d'arrêt devra prendre en compte (question 4 de l'ADR-006) | [M1], [M6], [M7], [S26], [S27] |
| O3. Opérateur de Zalando | 3/5 | 6 | Prête sans intervention ; de retour en 15,3 s après la suppression du pod ; un objet `postgresql` court. La réserve demande une action : sur un cluster neuf, l'opérateur s'arrête en erreur à son premier démarrage en enregistrant ses CRD, et ne réussit qu'au redémarrage que Kubernetes relance (M10) ; l'objet est refusé d'ici là ; l'image Spilo, Patroni compris, est la plus lourde à comprendre et à télécharger ; le Secret est régénéré avec l'objet ; la documentation et les notes de version supposent souvent AWS (S3, EBS, IRSA) | [M1], [M6], [M7], [M10], [S19], [S24] |

### 5.9 Coût (managé ou opérationnel), poids 5

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. Sans opérateur | 4/5 | 4 | Gratuit, rien de facturé : la couche ne tourne que sur le PC. Coût en temps : CELIAN tient les manifests et leur durcissement | [S2], [S12] |
| O2. CloudNativePG | 4/5 | 4 | Gratuit, rien de facturé. Coût en temps : une mineure environ tous les deux mois, maintenue trois mois après la suivante, donc une montée d'opérateur au moins deux fois par an | [S7] |
| O3. Opérateur de Zalando | 4/5 | 4 | Gratuit, rien de facturé. Coût en temps : suivre l'opérateur et, faute d'image Spilo à jour, construire la sienne | [S20], [M8] |

[BENCH] Le critère ne départage pas : aucune des trois options ne coûte de
l'argent, et chacune a son coût en temps.

## 6. Grille pondérée

| Critère | Poids | O1. Sans opérateur | O2. CloudNativePG | O3. Opérateur de Zalando |
| --- | --- | --- | --- | --- |
| Critères éliminatoires (section 3) | éliminatoire | passe | passe | passe |
| Licence et liberté d'usage | 15 | 5/5, 15 pts | 5/5, 15 pts | 4/5, 12 pts |
| Gouvernance (fondation, multi-vendeurs) | 15 | 4/5, 12 pts | 4/5, 12 pts | 2/5, 6 pts |
| Maturité et adoption | 15 | 5/5, 15 pts | 4/5, 12 pts | 4/5, 12 pts |
| Activité et maintenance | 10 | 5/5, 10 pts | 5/5, 10 pts | 3/5, 6 pts |
| Sécurité (CVE, réactivité) | 10 | 4/5, 8 pts | 3/5, 6 pts | 2/5, 4 pts |
| Empreinte sur PC (RAM, CPU, démarrage) | 10 | 3/5, 6 pts | 3/5, 6 pts | 3/5, 6 pts |
| Portabilité multi-cloud | 10 | 5/5, 10 pts | 5/5, 10 pts | 3/5, 6 pts |
| Expérience dev et documentation | 10 | 4/5, 8 pts | 4/5, 8 pts | 3/5, 6 pts |
| Coût (managé ou opérationnel) | 5 | 4/5, 4 pts | 4/5, 4 pts | 4/5, 4 pts |
| Total | 100 | 88 / 100 | 83 / 100 | 62 / 100 |

## 7. Verdict proposé

[BENCH] Option proposée : O1, Postgres sans opérateur, un StatefulSet et un
Service écrits à la main autour de l'image officielle, à 88 sur 100. Elle
devance CloudNativePG, l'option pressentie par le PRD, de 5 points (83), et
l'opérateur de Zalando de 26 points (62).

[BENCH] Pourquoi. Les 5 points d'écart viennent de deux critères : la
maturité (3 points, PostgreSQL et un StatefulSet éprouvé contre un niveau
Incubating de dix-huit jours [S13], [S39]), la sécurité (2 points, aucun
composant qui détienne des droits sur les Secrets du cluster, face à deux avis
critiques en douze mois et à un opérateur qui crée et supprime tous les
Secrets [S16], [S42]). L'empreinte ne départage rien en note, mais elle va
dans le même sens pour la mémoire et le temps : 112,3 Mio de moins au nœud que
CloudNativePG (48,1 contre 160,4) et « prêt » en 8,9 s contre 33,8 (M1, M2).
CloudNativePG télécharge en revanche 41,5 Mo de moins (127,0 contre 168,5).
Hors grille, deux faits mesurés pèsent aussi pour O1 : supprimer l'objet qui
porte Postgres garde la donnée avec O1 et la perd avec CloudNativePG (M6 c),
et O1 ne demande aucune boucle d'attente sur l'API dans `task up`.

[BENCH] Ce que CloudNativePG apporte et que la grille du profil lite ne
compte pas : la haute disponibilité, les sauvegardes, les montées de version
et la gestion déclarative des rôles. Aucune n'est demandée par le golden repo
de la phase 2, qui tourne une instance jetable sur un poste. Elles pèseraient
pour une cible on-prem serveurs, hors MVP, qui aurait son propre benchmark.
CloudNativePG reste aussi le seul des trois à signer ses images par cosign
[S15], ce que Kyverno exigera dans les profils qui l'embarquent (ENF-03).

[BENCH] Sensibilité. Le verdict repose sur des notes de jugement, et l'écart
tient en deux crans. Un seul cran rendu à CloudNativePG laisse O1 devant, de
2 ou 3 points. Deux crans changent l'issue : gouvernance à 5, au titre de la
fondation, et maturité à 5, au vu des adoptants cités par la CNCF, mettent
CloudNativePG devant, 89 contre 88 ; gouvernance à 5 et sécurité à 4 donnent
l'égalité, 88 partout. Dans l'autre sens, si [SECU] tient l'absence de
signature de l'image officielle pour une action (réserve de 5.5), O1 passe à
3 en sécurité, soit 86, encore devant.
Les lectures de l'empreinte qui contredisent les règles de la GATE 1 ne
changent pas l'ordre :

| Lecture | O1 | O2 | O3 | En tête | Règle |
| --- | --- | --- | --- | --- | --- |
| Grille | 88 | 83 | 62 | O1 | Sans objet |
| Gouvernance de O2 à 5 (fondation) | 88 | 86 | 62 | O1 | Aucune contredite : jugement sur la part d'EDB |
| Maturité de O2 à 5 (adoptants cités par la CNCF) | 88 | 86 | 62 | O1 | Aucune contredite : jugement sur un niveau Incubating de dix-huit jours |
| Gouvernance et maturité de O2 à 5 | 88 | 89 | 62 | O2 | Aucune contredite : deux jugements |
| Gouvernance à 5 et sécurité à 4 pour O2 | 88 | 88 | 62 | Égalité | Aucune contredite : deux jugements de [SECU] et du DSI |
| Absence de signature de l'image officielle tenue pour une action : O1 à 3 en sécurité | 86 | 83 | 62 | O1 | Aucune contredite : jugement de [SECU] |
| O1 en variante Alpine, 120,3 Mo en amd64 | 88 | 83 | 62 | O1 | Aucune : toujours au-dessus de 112,5 Mo, à 6,9 % du seuil |
| O2 avec l'image `standard` (264,0 Mo) ou `system` (316,9 Mo) | 88 | 83 | 62 | O1 | Aucune : même cran perdu |
| Volume cumulé avec la plate-forme de base (505,8 Mo) contre 500 Mo | 88 | 83 | 62 | O1 | Contredit la deuxième règle de la GATE 1 ; les trois perdent le même cran |
| Mémoire en somme des pods au lieu du nœud | 88 | 83 | 62 | O1 | Contredit la troisième règle ; les trois restent sous 512 Mio |

[BENCH] Réserves. L'image officielle est tenue par deux personnes [S38] : si
son rythme ralentissait, les paquets du PGDG restent disponibles, et
CloudNativePG les emploie déjà [S8]. Le durcissement du StatefulSet devient du
code de CELIAN, copié dans chaque projet généré (risque R-35 proposé
ci-dessous). Prochaine vérification : à la sortie de CloudNativePG 1.31, vers
décembre 2026 [S7], ou au plus tard le 2027-05-20.

[BENCH] Conditions proposées pour l'ADR-012, chacune vérifiable par la
matrice (principe I) :

1. Manifests dans la couche `local` seulement : un Service et un StatefulSet,
   sans objet `Secret` (condition 1 de l'ADR-006). Image officielle par
   condensat (FR-008), variante Debian, sous l'UID 999 sans privilège,
   capacités retirées, comme dans le script. Contrôle : la matrice échoue sur
   une image sans condensat, un conteneur root, ou
   `POSTGRES_HOST_AUTH_METHOD=trust` (R-20).
2. Mot de passe par fichier : `POSTGRES_USER_FILE` et `POSTGRES_PASSWORD_FILE`
   pointent sur le Secret monté, jamais une valeur en variable.
3. Secret et volume vivent ensemble. Les variables de l'image ne servent qu'à
   l'initialisation d'un volume vide [S2] : `task up` ne recrée jamais le
   Secret tant que le volume existe, et la commande d'arrêt supprime les deux
   ou aucun. Contrôle : deux `task up` sur le même cluster gardent la même
   empreinte du Secret et la donnée lisible (US-2, scénario 3), comme M6 (b).
4. Donnée gardée au rechargement et à la suppression du pod (US-1,
   scénario 3 ; FR-007), testée comme M6 (a) et (b). Le redémarrage du nœud
   reste à mesurer, avec l'accord de Lucas (section 8).
5. Parité de majeure avec Cloud SQL (ENF-02) : la majeure locale est la
   majeure par défaut de Cloud SQL, relevée à chaque release du blueprint et
   tenue en une seule valeur pour les deux couches, comme la mineure de
   Kubernetes dans l'ADR-004. Contrôle : la matrice compare `server_version`
   à cette valeur. Un écart de mineure est admis et listé au README (18.7 en
   local, 18.6 sur Cloud SQL le 2026-11-20 [S12]).
6. « Prêt » veut dire une requête authentifiée par le Service, comme M1, et
   non un pod `Ready`.
7. Signature : aucune signature vérifiable de l'image officielle n'a été
   trouvée, Docker retirant Docker Content Trust sans remplaçant documenté
   [S45]. Avant que Kyverno entre dans un profil (ENF-03), l'ADR-012 dit
   comment ce profil admet l'image, avec la même règle que pour les images
   que `task up` construit (ADR-006), et [SECU] la relit.

[BENCH] Réversibilité. Passer à CloudNativePG ne toucherait que la couche
`local` : l'application garde le Secret `db-auth`, que CloudNativePG accepte
tel quel (M6), et un nom d'hôte venu de la configuration de la couche. Ce qui
rouvrirait la décision : un besoin local de sauvegarde ou de plusieurs
instances, l'ouverture d'une cible on-prem serveurs, ou un constat de [SECU]
sur l'image officielle.

[BENCH] Si l'ADR-012 retient CloudNativePG, les conditions changent ainsi :
manifest de release versionné avec son SHA-256 et appliqué par
`kubectl apply --server-side` ; image de l'opérateur figée par condensat dans
`image` et dans `OPERATOR_IMAGE_NAME`, opérande `minimal` figée elle aussi ;
Secret de `task up` passé par `bootstrap.initdb.secret` ; boucle d'attente
bornée tant que le webhook refuse le `Cluster` ; une commande d'arrêt qui ne
supprime pas le `Cluster` si la donnée doit rester ; veille des avis au dépôt,
la base mondiale n'en ayant qu'un sur quatre ; montée de mineure au moins deux
fois par an.

[BENCH] Suites. L'ADR-012, écrit par [ARCHI]. Une entrée `postgres` au
catalogue (ADR-009) : ligne `local` en `oss`, « image officielle PostgreSQL
dans un StatefulSet de la couche `local` », PostgreSQL License, gouvernance
« communauté PostgreSQL (PGDG), sans fondation ; image tenue par le programme
d'images officielles de Docker », statut actif, vérifiée le 2026-11-20, sources
[S1], [S2], [S10] ; ligne `gcp` en `managed`, Cloud SQL for PostgreSQL [S12].
Standard exposé : `postgresql-protocol`, déjà dans la liste fermée du
catalogue. Pour le DSI : le risque R-35 ci-dessous.

[BENCH] R-35 proposé, porteur [DEV] et [SECU], probabilité moyenne, impact
moyen. « Postgres local écrit à la main dans chaque projet généré. Le
StatefulSet, son durcissement et ses règles d'initialisation deviennent du
code de CELIAN, copié dans chaque projet. Quatre dérives possibles : un
Secret recréé sur un volume existant, qui laisse l'ancien mot de passe en
base et coupe l'application ; un volume monté ailleurs que sous
`/var/lib/postgresql`, qui loge la donnée hors du PVC ; une méthode `trust`
glissée pour déboguer ; une image qui ne suit plus les mineures, alors que
18.7 corrige 52 vulnérabilités. Mitigation : conditions 1 à 6 de l'ADR-012,
testées par la matrice ; Renovate sur le condensat de l'image, avec
l'exception de sécurité du principe VI. »

## 8. Limites et biais

| Limite | Effet possible sur le verdict | Ce qui la lèverait |
| --- | --- | --- |
| Une seule machine (macOS, OrbStack, arm64), moteur non libre (R-26) | Temps et mémoire propres à ce poste ; les volumes, eux, sont lus au registre pour l'amd64 | Relancer le script sur Linux amd64 avec Docker Engine |
| Redémarrage du nœud non mesuré : `docker start` attend l'accord de Lucas | La donnée gardée après un redémarrage du poste n'est pas prouvée pour les trois options | `NODE_RESTART=1`, après accord, qui lance `docker stop celian-bench-011-control-plane` puis `docker start celian-bench-011-control-plane` dans chaque exécution |
| Images tirées sur le réseau à chaque exécution | M1 dépend du débit du moment : 27,2 à 28,1 s pour tirer Spilo, 2,9 à 6,6 s pour les autres images | Remesurer après la solution de R-25 (BENCH-010), cache du nœud plein |
| Un test de fumée a tourné après l'écriture des seuils (2026-11-20, de 20:13 à 20:22 UTC, une exécution par option) | Aucun : les seuils étaient déjà posés et hachés ; le test a conduit à relever les redémarrages au repos plutôt qu'en fin d'exécution | Sans objet |
| M6 (c) supprime l'objet qui porte Postgres, pas le namespace | La lecture de la commande d'arrêt reste ouverte (question 4 de l'ADR-006) ; supprimer le namespace emporterait le volume dans les trois options | Refaire M6 avec la commande d'arrêt retenue |
| Une instance, ni sauvegarde ni haute disponibilité | Les forces de CloudNativePG hors du profil lite ne sont pas mesurées | Benchmark propre à une cible on-prem, hors MVP |
| Durcissement d'O1 essayé en partie : `readOnlyRootFilesystem` non essayé | La condition 1 pourrait demander un réglage de plus | Essai sur le golden repo |
| Comptes de commits relevés par l'API de GitHub, employeurs déclarés sur les profils | Gouvernance de O2 et de O3 lue sur des déclarations | Statistiques de LFX pour CloudNativePG |
| Percona non mesuré, écarté sur sources | Un autre troisième aurait pu finir devant Zalando, pas devant O1 : Percona tire au moins 540 Mo d'images (opérateur et Postgres) en amd64 | Mesurer Percona avec le même script |
| Aucune signature vérifiable de l'image officielle, sans remplaçant documenté par Docker [S45] | O1 perdrait un cran de sécurité (86), toujours devant | Relecture [SECU] ; guide de migration de Docker |
| Option pressentie par le PRD : CloudNativePG | Aucune note ne lui donne d'avantage ; elle finit deuxième | Sans objet |

## 9. Sources

[BENCH] Toutes lues le 2026-11-20. Les fichiers de dépôt GitHub ont été lus
par l'API de GitHub (`gh api`), au tag ou au commit indiqué ; les comptes de
commits sont ceux de la branche par défaut, du 2025-11-20 au 2026-11-20, bots
exclus (comptes en `[bot]` et `cnpg-bot`).

| ID | URL | Lue le | Ce que la source établit | Officielle |
| --- | --- | --- | --- | --- |
| S1 | <https://www.postgresql.org/support/versioning/> | 2026-11-20 | 18.7 mineure courante de la 18, maintenue jusqu'au 2030-11-14 ; 19.0 sortie le 2026-11-19 ; cinq ans de support par majeure, une mineure au moins tous les trois mois | Oui |
| S2 | <https://github.com/docker-library/docs/blob/master/postgres/README.md> | 2026-11-20 | Tags `18.7-trixie`, `18.7-bookworm`, `18.7-alpine` ; `PGDATA` en `/var/lib/postgresql/18/docker` et volume en `/var/lib/postgresql` à partir de 18 ; variables `_FILE` ; locales des variantes Alpine (musl) ; image « maintained by the PostgreSQL Docker Community » | Oui |
| S3 | <https://github.com/docker-library/postgres> | 2026-11-20 | Licence MIT de l'empaquetage, dépôt non archivé, créé le 2014-05-22, dernier commit le 2026-11-19 ; 52 commits en 12 mois, dont 38 du bot | Oui |
| S4 | <https://opensource.org/licenses> | 2026-11-20 | Apache-2.0, MIT et PostgreSQL License approuvées par l'OSI | Oui |
| S5 | <https://github.com/cloudnative-pg/cloudnative-pg> | 2026-11-20 | Licence Apache-2.0, dépôt créé le 2022-03-10, non archivé, dernier commit le 2026-11-20 | Oui |
| S6 | <https://github.com/cloudnative-pg/cloudnative-pg/releases/tag/v1.30.2> | 2026-11-20 | 1.30.2 publiée le 2026-11-17 ; opérande par défaut `18.7-system-trixie` ; correctifs Go GO-2026-6617 et suivants ; SHA-256 de `cnpg-1.30.2.yaml` publié par GitHub, `ea4cc355…c68c` ; release non immuable, signature sigstore du manifest jointe | Oui |
| S7 | <https://github.com/cloudnative-pg/cloudnative-pg/blob/main/docs/src/supported_releases.md> | 2026-11-20 | 1.30.x seule maintenue, sortie le 2026-06-29, fin vers mars 2027, Kubernetes 1.34 à 1.36, PostgreSQL 15 à 18 ; une mineure environ tous les deux mois, maintenue trois mois après la suivante ; 1.31 vers décembre 2026 | Oui |
| S8 | <https://github.com/cloudnative-pg/postgres-containers> | 2026-11-20 | Images d'opérande sous Apache-2.0, sur Debian et paquets PGDG, reconstruites chaque semaine ; types `minimal`, `standard`, `system` (déprécié) ; amd64 et arm64 ; SBOM et provenance | Oui |
| S9 | <https://github.com/cloudnative-pg/cloudnative-pg/releases> | 2026-11-20 | 16 releases stables en 12 mois, de 1.26.3 à 1.30.2 ; 1.30.1 le 2026-09-23 | Oui |
| S10 | <https://www.postgresql.org/about/licence/> | 2026-11-20 | PostgreSQL publié sous la PostgreSQL License, « similar to the BSD or MIT licenses » | Oui |
| S11 | <https://www.postgresql.org/about/news/postgresql-187-1712-1616-1520-1425-and-19-rc-2-released-3442/> | 2026-11-20 | 18.7 publiée le 2026-11-12, 52 vulnérabilités corrigées ; fin de PostgreSQL 14 | Oui |
| S12 | <https://docs.cloud.google.com/sql/docs/postgres/db-versions> | 2026-11-20 | Cloud SQL propose 9.6 à 18, 18 par défaut, mineure courante 18.6 | Oui |
| S13 | <https://www.cncf.io/projects/cloudnativepg/> | 2026-11-20 | Acceptée à la CNCF le 2025-01-21, au niveau Incubating depuis le 2026-11-02 | Oui |
| S14 | <https://github.com/cloudnative-pg/governance> (`MAINTAINERS.md`, `GOVERNANCE.md`) | 2026-11-20 | Comité de pilotage et mainteneurs du cœur : cinq personnes, toutes chez EDB ; comités chaîne d'approvisionnement et communauté ouverts à Verito Digital, GEICO et Upbound ; vote équilibré par organisation encore à venir (ticket #68) | Oui |
| S15 | <https://github.com/cloudnative-pg/cloudnative-pg/blob/v1.30.2/docs/src/security.md>, <https://github.com/cloudnative-pg/cloudnative-pg/blob/main/SECURITY.md> | 2026-11-20 | Images de l'opérateur et des opérandes signées par cosign ; conteneurs Postgres en `runAsNonRoot`, `readOnlyRootFilesystem`, capacités retirées, seccomp `RuntimeDefault` ; signalement privé, accusé sous 10 jours ouvrés, correctif sous 6 mois | Oui |
| S16 | <https://github.com/cloudnative-pg/cloudnative-pg/security/advisories> | 2026-11-20 | 4 avis en 12 mois : GHSA-423p-g724-fr39 (critique, 2026-05-08), GHSA-x8c2-3p4r-v9r6 (critique), GHSA-w3gf-xc94-wvmj (élevé, CVSS 8,5), GHSA-7qwx-x8ff-3px9 (moyen, CVSS 5,4), tous trois le 2026-06-29 ; versions corrigées publiées le même jour ; seul le premier figure dans la base mondiale de GitHub | Oui |
| S17 | <https://github.com/zalando/postgres-operator/blob/v2.0.3/README.md>, `LICENSE` | 2026-11-20 | Licence MIT ; dépôt créé le 2017-05-12, non archivé, dernier commit le 2026-11-19 ; 2.0.3 pour PostgreSQL 14 à 18 et Kubernetes 1.27 et plus ; « used in production for over five years » chez Zalando | Oui |
| S18 | <https://github.com/zalando/postgres-operator/releases/tag/v2.0.3> | 2026-11-20 | 2.0.3 publiée le 2026-10-02 ; images de l'opérateur ; la 2.0.0 republiée en 2.0.1 pour une CRD qui cassait les chaînes GitOps | Oui |
| S19 | <https://github.com/zalando/postgres-operator/blob/v2.0.3/docs/quickstart.md> | 2026-11-20 | minikube, kind et k3d cités ; installation par `kubectl apply -k` du dossier `manifests` | Oui |
| S20 | <https://github.com/zalando/spilo> | 2026-11-20 | Licence Apache-2.0 ; `PGVERSION=18` sur `master` ; tag 4.1-p2 sur un commit du 2026-04-13 ; TimescaleDB construite en édition Apache par défaut (`TIMESCALEDB_APACHE_ONLY`) | Oui |
| S21 | <https://github.com/zalando/postgres-operator/blob/master/MAINTAINERS>, `SECURITY.md` | 2026-11-20 | 7 mainteneurs, tous en `@zalando.de` ; signalement par courriel à `tech-security@zalando.de`, sans délai annoncé | Oui |
| S22 | <https://github.com/zalando/postgres-operator/releases> | 2026-11-20 | 5 releases stables en 12 mois : 1.15.1, 2.0.0 à 2.0.3 ; aucun avis de sécurité publié par le dépôt ni dans la base mondiale ; aucun ticket ouvert sur le message d'erreur de M10 | Oui |
| S23 | API de GitHub : commits de `cloudnative-pg/cloudnative-pg`, `zalando/postgres-operator`, `percona/percona-postgresql-operator`, et profils de leurs dix premiers auteurs | 2026-11-20 | CloudNativePG 597 commits humains, 77 auteurs, 83 % par les auteurs du top 10 qui déclarent EDB ; Zalando 115 et 41, 56 % Zalando ; Percona 407 et 19, 78 % Percona. Employeurs déclarés par les intéressés | Oui, employeurs déclarés |
| S24 | <https://github.com/zalando/postgres-operator/blob/v2.0.3/docs/administrator.md>, `docs/reference/operator_parameters.md` | 2026-11-20 | CRD enregistrées par l'opérateur au démarrage ; Spilo tourne en root par défaut (`spilo_runasuser`) ; `spilo_allow_privilege_escalation` à `true` par défaut ; Secrets et PVC supprimés avec l'objet par défaut (`enable_secrets_deletion`, `enable_persistent_volume_claim_deletion`) | Oui |
| S25 | <https://github.com/zalando/postgres-operator/tree/v2.0.3/manifests> | 2026-11-20 | `docker_image: ghcr.io/zalando/spilo-18:4.1-p2` ; `secret_name_template` ; ClusterRole qui crée, modifie et supprime les Secrets et les CRD du cluster ; SHA-256 des quatre fichiers, figés dans le script | Oui |
| S26 | <https://github.com/cloudnative-pg/cloudnative-pg/blob/v1.30.2/docs/src/installation_upgrade.md> | 2026-11-20 | Installation par `kubectl apply --server-side -f` du manifest de release ; opérateur dans `cnpg-system` | Oui |
| S27 | <https://github.com/cloudnative-pg/cloudnative-pg/blob/v1.30.2/docs/src/bootstrap.md> | 2026-11-20 | `bootstrap.initdb.secret` : Secret `kubernetes.io/basic-auth` fourni par l'utilisateur, ou mot de passe aléatoire généré par l'opérateur | Oui |
| S28 | <https://github.com/cloudnative-pg/cloudnative-pg/blob/v1.30.2/docs/src/container_images.md> | 2026-11-20 | Majeure détectée depuis le tag de `imageName`, ou par un catalogue d'images | Oui |
| S29 | <https://github.com/cloudnative-pg/cloudnative-pg/blob/main/ADOPTERS.md> | 2026-11-20 | 56 organisations déclarées, liste tenue par le projet | Oui, déclarative |
| S30 | <https://github.com/percona/percona-postgresql-operator/blob/v3.1.0/LICENSE.md> | 2026-11-20 | Apache-2.0, copyright Crunchy Data puis Percona | Oui |
| S31 | <https://docs.percona.com/percona-operator-for-postgresql/latest/System-Requirements.html>, <https://github.com/percona/percona-postgresql-operator/releases> | 2026-11-20 | 3.1.0 testée sur GKE 1.34 à 1.35, minikube 1.38.1, sans kind ; dépôt créé le 2021-03-04 ; 5 releases stables en 12 mois, 3.1.0 le 2026-09-09 | Oui |
| S32 | <https://github.com/CrunchyData/postgres-operator/blob/main/README.md> | 2026-11-20 | Code sous Apache-2.0 ; images de l'installation documentée soumises aux « Crunchy Data Developer Program terms » | Oui |
| S33 | <https://github.com/CrunchyData/postgres-operator/releases> | 2026-11-20 | 6.0.4 et 5.8.10 le 2026-11-16 | Oui |
| S34 | <https://github.com/ongres/stackgres> | 2026-11-20 | AGPL-3.0 ; miroir de GitLab ; aucune release sur GitHub ; installation par une commande en une ligne du site | Oui |
| S35 | <https://github.com/reactive-tech/kubegres> | 2026-11-20 | Apache-2.0 ; dernière release v1.19 le 2025-01-04 | Oui |
| S36 | <https://www.postgresql.org/support/security/> | 2026-11-20 | CVE de PostgreSQL 18 corrigées en 18.2, 18.4, 18.6 et 18.7 ; signalement à `security@postgresql.org` | Oui |
| S37 | <https://www.postgresql.org/community/contributors/> | 2026-11-20 | Équipe principale de sept membres chez six organisations (EDB deux fois, Microsoft, Redpill Linpro, Databricks, Snowflake, pgEdge) ; 54 contributeurs majeurs, Microsoft et AWS en tête avec dix chacun | Oui |
| S38 | <https://github.com/docker-library/official-images/blob/master/library/postgres> | 2026-11-20 | Image officielle tenue par deux mainteneurs, Tianon Gravi et Joseph Ferguson ; huit architectures | Oui |
| S39 | <https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/> | 2026-11-20 | Supprimer un StatefulSet ne supprime pas ses volumes ; `persistentVolumeClaimRetentionPolicy` à `Retain` par défaut, stable depuis Kubernetes 1.32 | Oui |
| S40 | `specs/001-golden-repo-saas-b2b/spec.md`, branche `docs/spec-golden-repo`, commit `a7cf613d` | 2026-11-20 | US-1 scénario 3, US-2 scénario 3, FR-004, FR-007, FR-008, FR-017, SC-008 | Oui, interne |
| S41 | [docs/prd-mvp.md](../prd-mvp.md) | 2026-11-20 | US-004 (CloudNativePG en exemple), US-005, ENF-01, ENF-02 | Oui, interne |
| S42 | `cnpg-1.30.2.yaml`, asset de la release v1.30.2 | 2026-11-20 | 11 CRD, deux webhooks ; ClusterRole `cnpg-manager` qui crée, lit, modifie et supprime les Secrets de tout le cluster ; image de l'opérateur nommée dans `image` et dans `OPERATOR_IMAGE_NAME` | Oui |
| S43 | Registres `docker.io` et `ghcr.io`, manifests lus par `docker manifest inspect -v` et `docker buildx imagetools inspect` | 2026-11-20 | Condensats d'index figés dans le script ; volumes compressés par architecture (M4) | Oui |
| S44 | [ADR-007](../adr/ADR-007-secrets.md), section « Entrée au catalogue » | 2026-11-20 | Kubernetes gradué à la CNCF le 2018-03-06, relevé pour la ligne `local` de la brique `secrets` | Oui, interne |
| S45 | <https://docs.docker.com/docker-hub/repos/manage/trusted-content/official-images/> | 2026-11-20 | Docker retire Docker Content Trust pour ses images officielles, cite Sigstore ou Notation comme pistes, sans date ni guide de migration publiés | Oui |
| S46 | <https://www.cncf.io/blog/2026/11/10/cloudnativepg-becomes-a-cncf-incubating-project/> | 2026-11-20 | Billet du 2026-11-10, signé des mainteneurs : vote du TOC pour l'incubation ; plus de 50 adoptants en production, dont IBM, Google Cloud, Microsoft Azure, GEICO Tech et Tesla ; demande de graduation prévue en 2027 | Oui, écrit par le projet |
| S47 | <https://cloudnative-pg.io/releases/cloudnative-pg-1-30.2-released/> | 2026-11-20 | 1.30.2 du 2026-11-17, avancée « given the security relevance of the PostgreSQL 18.7 release » | Oui |
| S48 | <https://www.postgresql.org/docs/18/release-18-3.html> | 2026-11-20 | PostgreSQL 18.3 publiée le 2026-02-26 | Oui |

## 10. Relectures

| Relecteur | Porte sur | Date | Avis |
| --- | --- | --- | --- |
| [SECU] | Licences, critères éliminatoires, sécurité | à venir | à venir |
| [FINOPS] | Coût | à venir | à venir |

[SECU] À venir. Points à relire en priorité : signature de l'image officielle
(condition 7), droits de l'opérateur de CloudNativePG sur les Secrets, image
Spilo en 18.3.

[FINOPS] À venir. Point à relire : volume de la couche dans le budget
d'ENF-01, au débit visé qui reste à fixer (R-04).
