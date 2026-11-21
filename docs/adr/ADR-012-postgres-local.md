# ADR-012. Sur la cible `local`, Postgres tourne sans opérateur, dans un StatefulSet écrit par CELIAN autour de l'image officielle, sous conditions et avec une dérogation datée à ENF-03

| Champ | Valeur |
| --- | --- |
| Statut | accepté |
| Date | 2026-11-21 |
| Auteur | [ARCHI] |
| Décideur | Lucas, décisions et acceptation du 2026-11-21 sur BENCH-011 |
| BENCH lié | [BENCH-011](../benchmarks/BENCH-011-postgres-local.md) |
| Remplace | aucun |

## Contexte et problème

Le projet généré a besoin de Postgres sur ses deux cibles. Sur `gcp`, c'est Cloud SQL, service managé imposé par le principe III et créé par la couche OpenTofu de l'[ADR-008](ADR-008-modules-opentofu-gcp.md). Sur `local`, Postgres tourne dans le cluster kind de l'[ADR-004](ADR-004-cluster-local.md), et sa forme restait ouverte : l'[ADR-006](ADR-006-orchestration-locale.md) a laissé hors de sa décision « la forme de Postgres et du cache dans la couche `local`, manifest simple comme dans l'essai ou opérateur ». La spec du golden repo bloque la couche locale de la base sur ce choix : « La base de données locale MUST suivre le verdict de BENCH-011 » (FR-017). Le PRD pressentait un opérateur, CloudNativePG, exemple du brief repris par US-004 « à confirmer en phase 1 ».

Les exigences viennent du PRD et de la spec. US-005 veut que `task up` démarre Postgres dans le cluster local sans autre étape (principe VII), et qu'une commande documentée arrête et supprime l'environnement. La spec ajoute que le rechargement ne redémarre pas la base et ne perd pas ses données (récit 1, scénario 3 ; FR-007), qu'une relance garde les secrets « et les données restent lisibles » (récit 2, scénario 3), que les secrets locaux sont aléatoires, d'au moins 32 caractères, jamais dans un fichier, une variable affichée ou un argument (FR-004), et que toute image tirée est figée par condensat (FR-008). ENF-01 fixe le budget de 15 minutes. ENF-02 veut la parité : seule la couche de cible change, et le README liste les écarts. ENF-03 veut que Kyverno refuse les images non signées. Le DSI a ajouté pour BENCH-011 une exigence : la même version majeure que Cloud SQL.

Les décisions acceptées posent leurs contraintes. ADR-006 : aucun outil de boucle, `task up` enchaîne `docker build`, `kind load` et `kubectl apply -k`, Helm reste hors des prérequis, et aucun objet `Secret` ne figure sous `k8s/` (condition 1). [ADR-007](ADR-007-secrets.md) : `task up` crée chaque Secret par un tube avec une valeur aléatoire, seulement s'il n'existe pas, et le nom et les clés de chaque Secret sont les mêmes sur les deux cibles (conditions 1 et 5). ADR-004 : images figées par condensat (condition 3). L'[ADR-011](ADR-011-miroir-registres.md), accepté le 2026-11-21, fait passer les tirages du nœud par un miroir zot, et propose deux commandes d'arrêt : `task down`, qui supprime le cluster, et `task app:down`, qui le garde. Il renvoie à BENCH-011 le sort des données de Postgres. Côté constitution, les principes I à IX ; le X est sans objet sur `local`. Côté risques, R-04, R-20, R-25, R-28, et R-35, ouvert avec BENCH-011.

BENCH-011 a mesuré trois options avec le même script, trois exécutions chacune, le 2026-11-20. [SECU] et [FINOPS] l'ont relu le 2026-11-21, et Lucas a tranché le même jour (BENCH-011, section 7). Cet ADR écrit ses décisions et les conditions de [SECU]. Il tranche aussi ce que le rapport laissait à [ARCHI] : la répartition par couche, ce qui change pour l'ADR-007, la parité avec Cloud SQL, le passage par le miroir et l'entrée au catalogue.

## Options considérées

| Option | Score BENCH (sur 100) | Verdict | Raison principale |
| --- | --- | --- | --- |
| O1, sans opérateur : StatefulSet et Service écrits par CELIAN, image `postgres:18.7-trixie` | 87 | retenue | Ni opérateur ni droit sur l'API ; prête en 8,9 s, 48,1 Mio au nœud ; donnée gardée dans les trois cas de M6, y compris quand l'objet qui porte Postgres est supprimé puis réappliqué |
| O2, CloudNativePG 1.30.2, opérande `18.7-minimal-trixie` | 83 | écartée | Option pressentie par le PRD. Projet de la CNCF qui signe ses images et sépare les rôles, mais son opérateur détient tous les droits sur les Secrets du cluster, la donnée part avec le `Cluster` supprimé (M6 c), et `task up` doit attendre son webhook |
| O3, opérateur de Zalando 2.0.3, Spilo `spilo-18:4.1-p2` | 61 | écartée | Éditeur unique ; image par défaut en 18.3, quatre mineures en retard, 628,7 Mo et en root ; Secret supprimé puis régénéré avec l'objet |
| Kubegres | éliminée, non notée | éliminée | Aucune release depuis 12 mois : v1.19 du 2025-01-04 |
| Percona, Crunchy Data (PGO), StackGres | non notées | non étudiées | Écartées sur sources avant la mesure : Percona moins bien gouverné que Zalando, images de PGO non libres, StackGres sous AGPL-3.0 sans manifest de release |

Les trois options étudiées passent les critères éliminatoires (BENCH-011, section 3).

Dans la grille réconciliée par le DSI le 2026-11-21, l'écart entre O1 et CloudNativePG, 4 points, tient à la maturité (3 points) et au coût (1 point). D'un côté, PostgreSQL, son image officielle et un objet du cœur de Kubernetes. De l'autre, un projet Incubating qui ne demandera la graduation qu'en 2027, et des montées d'opérateur au moins deux fois par an. La sécurité ne départage pas : 3 de chaque côté, pour des raisons opposées. L'empreinte ne départage pas en note, 3/5 pour les trois, mais elle va dans le sens d'O1 pour la mémoire et le temps : 48,1 Mio au nœud contre 160,4, prête en 8,9 s contre 33,8. CloudNativePG télécharge en revanche 41,6 Mo de moins, 127,0 Mo contre 168,5.

Sensibilité, reprise du rapport : le verdict est fragile. Un seul cran de jugement rendu à CloudNativePG, la gouvernance ou la maturité à 5, la laisse derrière à 86 ; un cran de sécurité seul, à 85. Deux crans la mettent devant, 89 contre 87, et un cran de gouvernance ou de maturité plus un cran de sécurité aussi, 88 contre 87. Aucune lecture de l'empreinte, même contraire aux règles de la GATE 1, ne change l'ordre. Lucas a retenu O1 en connaissant cette fragilité.

Grille, mesures et sources : [BENCH-011](../benchmarks/BENCH-011-postgres-local.md).

## Décision

Sur la cible `local`, Postgres tourne sans opérateur : un StatefulSet d'une réplique et un Service, écrits par CELIAN dans la couche `local` du blueprint, autour de l'image officielle `postgres:18.7-trixie`, figée par condensat (FR-008). La cible `gcp` garde Cloud SQL (ADR-008). L'application lit le même Secret `db-auth` sur les deux cibles et ne sait pas ce qui sert la base.

Le condensat d'index mesuré est celui du script de BENCH-011 : `docker.io/library/postgres:18.7-trixie@sha256:eb63372c1e05c755f55fa30cbd07aecc443676fc6c0fa90b9002d01537841e1a` (`tests/bench/bench-011-postgres.sh`, ligne 85, branche de la PR #35). Renovate le suit ensuite, sous la condition 5.

Lucas a pris trois décisions le 2026-11-21 : O1, la dérogation à ENF-03 de la section « Dérogations », et l'autorisation de mesurer le redémarrage du nœud. La validation de cet ADR lui revient, avec deux questions ouvertes.

### Pourquoi pas l'option pressentie

Le PRD pressentait CloudNativePG (US-004). Cet ADR ne le confirme pas, pour les trois faits qui ont fait pencher Lucas (BENCH-011, section 7). Aucun opérateur à monter, donc aucun contrôleur qui crée, lit, modifie et supprime tous les Secrets du cluster. Une image sur docker.io, que le miroir de l'ADR-011 sert déjà. Des données qui survivent à la suppression puis à la recréation de l'objet qui porte Postgres, quand CloudNativePG les perd trois fois sur trois (M6 c), parce que son PVC part avec le `Cluster`. S'y ajoute un fait hors grille : `task up` n'a aucune boucle d'attente sur l'API, alors que CloudNativePG refuse le `Cluster` tant que son webhook n'est pas prêt.

Le prix est du code tenu par CELIAN : le StatefulSet durci, un script d'initialisation, un rôle applicatif sans superutilisateur et un second Secret (conditions 1 à 8). Le rapport compte une soixantaine de lignes de manifest, copiées dans chaque projet généré (R-35).

CloudNativePG apporte ce que le profil lite ne demande pas : haute disponibilité, sauvegardes, montées de majeure, gestion déclarative des rôles. Ces forces pèseraient pour une cible on-prem serveurs, hors MVP, qui aurait son propre benchmark.

Revenir plus tard à CloudNativePG ne toucherait que la couche `local`. CloudNativePG accepte `db-auth` tel quel par `bootstrap.initdb.secret`, sans le modifier (M6), et l'application reçoit son nom d'hôte de la couche de cible. Le rapport liste ce que les conditions deviendraient (BENCH-011, section 7). S'y ajouterait un miroir de ghcr.io dans zot, sans quoi ses deux images, 127,0 Mo, repartiraient d'Internet à chaque création du cluster.

### Répartition par couche

| Couche | Contenu |
| --- | --- |
| commune | Les manifests de l'application lisent `db-auth` (type `kubernetes.io/basic-auth`, clés `username` et `password`) et un nom d'hôte fourni par la couche de cible. Aucun objet `Secret`, aucune référence au Secret du superutilisateur (condition 8) |
| `local` | Le Service `postgres` et le StatefulSet, image par condensat, volume par `volumeClaimTemplate` sur la classe de stockage par défaut de kind ; le script d'initialisation du rôle applicatif ; les tâches de `task up` qui créent `db-auth` et le Secret du superutilisateur ; l'attente de « prêt » (condition 6) ; la liste fermée de la dérogation, quand un profil embarque Kyverno |
| `gcp` | Cloud SQL, créé par la couche OpenTofu de l'ADR-008, à la majeure de la valeur unique (condition 5) ; `db-auth` produit depuis Secret Manager par la synchronisation de GKE (ADR-007). Rien de cet ADR ne tourne dans le cluster GKE |

Dans l'essai, `db-auth` porte `username: app` et un mot de passe de 40 caractères tiré de `/dev/urandom` (BENCH-011, section 4.2 ; script, lignes 252, 407 à 419 et 508). La classe relevée à chaque exécution est `standard`, provisionneur `rancher.io/local-path`, politique de récupération `Delete` : un PVC supprimé emporte sa donnée (BENCH-011, section 4.4). Les chemins sous `k8s/` et le nom du Secret du superutilisateur se fixent en phase 3, comme dans l'ADR-006.

### Conditions

Les conditions 1 à 8 sont celles du rapport, révisées par [SECU] et retenues par Lucas (BENCH-011, sections 7 et 10). Les conditions 9 à 11 sont des ajouts de [ARCHI]. La décision ne vaut qu'avec elles. Chaque contrôle cité entre dans la matrice de validation (principe I).

1. Manifests dans la couche `local` seulement. Un Service et un StatefulSet, sans objet `Secret` (condition 1 de l'ADR-006). Image officielle par condensat (FR-008), variante Debian. Le conteneur tourne sous l'UID 999 avec `runAsNonRoot`, `allowPrivilegeEscalation: false`, capacités retirées et `seccompProfile` en `RuntimeDefault`, sans jeton de compte de service monté. Le namespace de la base applique le profil `restricted` des Pod Security Standards. `readOnlyRootFilesystem` s'essaie sur le golden repo. Contrôle : la matrice échoue sur une image sans condensat, sur un pod refusé par le profil `restricted`, ou sur `POSTGRES_HOST_AUTH_METHOD=trust` (R-20).
2. Mot de passe par fichier, aucune méthode `trust`. `POSTGRES_USER_FILE` et `POSTGRES_PASSWORD_FILE` pointent sur le Secret monté, jamais sur une valeur en variable. `POSTGRES_INITDB_ARGS` porte `--auth-local=scram-sha-256 --auth-host=scram-sha-256`, que l'entrypoint passe à `initdb` : aucune ligne `trust` n'existe, même dans le conteneur. La sonde `pg_isready` n'a pas besoin du mot de passe ; son effet sur les journaux se vérifie sur le golden repo. Contrôle : la matrice lit les règles de `pg_hba` et échoue sur toute méthode `trust`, et un pod d'un autre namespace qui se connecte sans mot de passe doit être refusé. Lecture de [ARCHI], avec la condition 8 : ces deux fichiers sont ceux du Secret du superutilisateur, et le script d'initialisation lit `db-auth`. L'entrypoint exporte `PGPASSWORD` pour une authentification locale par mot de passe (BENCH-011, S52) ; que le script crée le rôle sous `scram-sha-256` en local se vérifie sur le golden repo.
3. Secret et volume vivent ensemble. Les variables `POSTGRES_*` ne servent qu'à l'initialisation d'un volume vide, comme les scripts de `/docker-entrypoint-initdb.d` (page de l'image, lue le 2026-11-21). `task up` ne recrée donc jamais le Secret tant que le volume existe, et la commande d'arrêt supprime les deux ou aucun. Contrôle : deux `task up` sur le même cluster gardent la même empreinte du Secret et la donnée lisible (récit 2, scénario 3), comme M6 (b). Si le volume existe sans le Secret, `task up` s'arrête avec un message qui propose de supprimer les deux, au lieu de tirer une nouvelle valeur. Avec la condition 8, la règle vaut pour les deux Secrets de la base.
4. Donnée gardée au rechargement et à la suppression du pod (récit 1, scénario 3 ; FR-007), testée comme M6 (a) et (b). Le redémarrage du nœud reste à mesurer, avec l'accord que Lucas a donné le 2026-11-21 (section « Redémarrage du nœud : non mesuré »).
5. Parité de majeure avec Cloud SQL (ENF-02). La majeure locale est la majeure par défaut de Cloud SQL, relevée à chaque release du blueprint et tenue en une seule valeur pour les deux couches, comme la mineure de Kubernetes dans l'ADR-004. Contrôle : la matrice compare `server_version` à cette valeur. Un écart de mineure est admis et listé au README : 18.7 en local, 18.6 sur Cloud SQL le 2026-11-20. Renovate ne propose aucune autre majeure pour l'image `postgres`. Contrôle : la configuration de Renovate est relue par [SECU].
6. « Prêt » veut dire une requête authentifiée par le Service, comme M1, et non un pod `Ready`. Contrôle, ajout de [ARCHI] : l'attente de `task up` et le test de démarrage de la matrice passent par un `SELECT 1` authentifié avec `db-auth`, par le Service que l'application utilise.
7. Signature. L'image officielle n'a aucune signature vérifiable. Docker a retiré Docker Content Trust pour ses images officielles à partir du 2025-08-08 et annonce un remplaçant sans date. La chaîne de construction ne signe que le dépôt `notary`, et les attestations sont des déclarations in-toto non signées. FR-008 reste tenu par le condensat, qui garantit le contenu et non son auteur ; ENF-03 ne l'est pas. D'où la dérogation datée de la section « Dérogations ». Contrôle, ajout de [ARCHI] : dès qu'un profil embarque Kyverno, la matrice échoue si une image de `docker.io/library/` désignée par un manifest rendu ou par un pod en marche manque à la liste fermée, ou n'y figure pas à l'identique, condensat compris.
8. Rôle de l'application sans superutilisateur. `POSTGRES_USER` crée un superutilisateur, alors que Cloud SQL n'en donne jamais. Le superutilisateur garde son propre mot de passe, tiré par `task up` selon la condition 1 de l'ADR-007, dans un Secret de la couche `local` que l'application ne monte pas. Un script d'initialisation crée le rôle de `db-auth`, propriétaire de la base `app`, sans `SUPERUSER` ; `CREATEROLE` et `CREATEDB` ne s'ajoutent que sur un besoin écrit. Contrôle : la matrice échoue si l'utilisateur de `db-auth` est superutilisateur, ou si le Secret du superutilisateur figure dans un manifest de l'application.
9. Un seul namespace pour la base et l'application sur `local`, proposition soumise à Lucas (question 1). Un pod ne lit un Secret que dans son propre namespace : `secretKeyRef` « Selects a key of a secret in the pod's namespace », et `secretName` désigne « the name of the secret in the pod's namespace » (référence de l'API Pod, lue le 2026-11-21). Dans le namespace de l'application, `db-auth` n'existe qu'en un exemplaire. `task app:down`, qui supprime ce namespace (ADR-011), emporte alors ensemble le volume et les deux Secrets, comme le demande la condition 3 ; que la suppression du namespace emporte le volume est écrit par BENCH-011 (section 8) sans avoir été essayé. Le profil `restricted` de la condition 1 s'applique aussi aux pods de l'API et du front, ce que l'essai de BENCH-005 n'a pas vérifié. Contrôles : celui de la condition 1 sur tous les pods du namespace ; après `task app:down`, aucun PVC ni Secret de la base ne reste.
10. Test de la condition 1 de l'ADR-007 étendu. Le Secret du superutilisateur y passe comme `db-auth`. La liste des valeurs connues reçoit `mysecretpassword`, valeur d'exemple de la documentation de l'image (BENCH-011, S2 et relecture [SECU]). Le test vise les clés de mot de passe : `username` porte un identifiant fixe, `app` dans l'essai, qui se répète d'un cluster à l'autre par construction et ferait échouer le test.
11. L'image passe par le miroir. Le test T2 de la condition 10 de l'ADR-011 tourne avec `postgres:18.7-trixie`, pour chaque profil livré. Contrôle : T2 passe hors réseau avec cette image.

Les conditions des ADR-004, ADR-006, ADR-007 et ADR-011 restent en vigueur, en particulier les images par condensat (condition 3 de l'ADR-004), l'absence de Secret sous `k8s/` (condition 1 de l'ADR-006) et la création des Secrets par un tube (condition 1 de l'ADR-007).

### Ce qui change pour l'ADR-007

L'ADR-007 n'est pas remplacé. Cet ADR précise son application à la base, sans toucher son texte.

- Un second Secret sur `local`. Le Secret du superutilisateur (condition 8) appartient à la couche `local` et n'a pas de pendant sur `gcp`, où aucun utilisateur n'a l'attribut superutilisateur. La condition 5 de l'ADR-007 compare les références aux Secrets dans les manifests de l'application : elle reste tenue, puisque l'application ne lit que `db-auth`. Sa phrase « Le nom et les clés de chaque Secret sont fixés une fois, pour les deux cibles » ne couvre pas ce Secret de couche, et l'écart se liste au README (ENF-02).
- La création dépend du volume. La condition 1 de l'ADR-007 crée un Secret « seulement si le Secret n'existe pas ». Pour les deux Secrets de la base, la condition 3 ajoute un cas : volume présent et Secret absent, `task up` s'arrête au lieu de tirer une valeur. Un Secret présent sans volume reste valide, et le volume neuf s'initialise avec lui.
- La liste des valeurs connues s'étend à `mysecretpassword`, et le test vise les clés de mot de passe (condition 10).
- R-28 vaut pour les deux Secrets : en clair dans etcd, lisibles par le kubeconfig d'administration.

### Redémarrage du nœud : non mesuré

Ce que deviennent les données de Postgres quand le nœud kind redémarre n'est pas mesuré. Lucas a autorisé la mesure le 2026-11-21 : `NODE_RESTART=1`, soit `docker stop` puis `docker start` du seul nœud de mesure, sous le verrou commun. Elle tournera après les séries de BENCH-012 et BENCH-013, et son résultat complétera BENCH-011 dans une PR à part. Un seul fait voisin est mesuré : les Secrets survivent à un redémarrage du nœud (M7 de BENCH-007, repris par l'ADR-007).

Le lien avec les commandes d'arrêt. La question 4 de l'ADR-006 a ouvert la lecture de US-005 en deux commandes, l'une qui garde le cluster, l'autre qui le supprime. L'ADR-011, proposé, la tranche ainsi : `task down` supprime le cluster, et les données avec ; `task app:down` garde le nœud en marche et supprime le ou les namespaces de l'application, donc, sous la condition 9, le volume et les deux Secrets. Ni l'une ni l'autre ne dépend du redémarrage du nœud.

Le cas non couvert est celui d'un nœud qui redémarre avec le poste ou le moteur, cluster gardé, puis d'un `task up` qui le réutilise. La donnée peut être là ou non, et le README ne promet rien tant que la mesure n'a pas tourné. La variante « arrêter le nœud entre deux sessions au lieu de le supprimer », que l'ADR-011 laisse hors de sa décision, attend la même mesure. Si le volume revenait sans ses Secrets, la condition 3 arrêterait `task up` avec son message.

### Parité attendue avec Cloud SQL

- Majeure : 18 sur les deux cibles. Cloud SQL propose PostgreSQL 9.6 à 18, 18 par défaut, mineure courante 18.6 (BENCH-011, S12, lue le 2026-11-20). PostgreSQL 19 est sorti le 2026-11-19, et Cloud SQL ne le propose pas. La valeur unique de la condition 5 alimente la couche `local`, qui en tire le tag de l'image, et la couche `gcp`, qui fixe la version de l'instance. L'ADR-008 avait laissé les versions de Postgres hors de sa portée : cette règle les fixe. L'attribut OpenTofu qui porte la version n'a pas été vérifié ([OPS]). Sur `gcp`, le contrôle de la condition 5 est d'abord statique, la configuration devant lire la valeur unique ; `server_version` se lit au premier apply réel, avec l'accord de Lucas (principe X).
- Rôle : aucun superutilisateur sur les deux cibles. Cloud SQL écrit « customers cannot create or have access to users with superuser attributes », et donne le rôle `cloudsqlsuperuser` à ses utilisateurs intégrés (BENCH-011, S53). En local, le rôle de `db-auth` n'a pas `SUPERUSER`, et n'a `CREATEROLE` ou `CREATEDB` que sur un besoin écrit (condition 8). Les privilèges de `cloudsqlsuperuser` n'ont pas été lus pour cet ADR : [OPS] et [SECU] les comparent au rôle local en écrivant la couche `gcp`, et le README liste l'écart qui reste. Le but : qu'une migration qui passe en local ne demande rien que Cloud SQL refuse (R-35).
- Secret : `db-auth`, même nom et mêmes clés sur les deux cibles (condition 5 de l'ADR-007), pour la base `app`.
- Chiffrement en transit. Cloud SQL est configuré en `ENCRYPTED_ONLY` (ADR-008). L'état TLS du serveur local n'a été ni lu ni mesuré par BENCH-011. Le mode de connexion de l'application doit passer sur les deux cibles : [DEV] et [SECU] le fixent sur le golden repo, et le README liste l'écart s'il en reste un.
- Ce que `local` n'a pas : ni sauvegarde, ni haute disponibilité, ni montée de majeure outillée (BENCH-011, section 1, hors champ), quand la couche `gcp` active les sauvegardes de Cloud SQL (ADR-008). Le README le dit.

### Registre et miroir

L'image vient de docker.io, registre que le miroir zot de l'ADR-011 sert déjà dans tous les profils. Le profil lite ne tire donc toujours que de docker.io, avec une seule entrée de synchronisation. Ce passage n'est mesuré que pour la variante Alpine de l'essai, `postgres:18.7-alpine`, servie par zot trois fois sur trois au test T2. La variante `trixie` ne l'est pas, d'où la condition 11 ; l'ADR-011 la porte déjà dans son tableau des registres, « non mesuré pour cette image ».

Volume (R-04, relecture [FINOPS]). L'image pèse 168,5 Mo compressés en amd64. Elle remplace la `postgres:18.7-alpine` de 120,3 Mo déjà comptée dans les 1 395,9 Mo de R-04, soit 48,3 Mo de plus. Le premier `task up` du profil standard, hors Keycloak et Mailpit, passe à 1 521,9 Mo avec zot : 135,3 % du budget de 900 s à 10 Mbit/s, et un débit minimal de 13,5 Mbit/s au lieu de 13,1. Sans miroir, l'image repartirait d'Internet à chaque création du cluster (M5). Avec lui, elle ne devrait plus être tirée qu'au premier `task up`, ce que la condition 11 vérifiera.

### Portée

La spec déclare la brique `database`, de valeur `postgres` (principe II). Elle ne nomme ni le StatefulSet, ni l'image, ni Cloud SQL, qui vivent dans les couches de cible et au catalogue. La décision couvre la cible `local`, profils lite et standard, une instance.

Restent hors de cette décision :

- Cloud SQL et sa configuration, sauf la version majeure (ADR-008) ;
- le cache, qui suivra le benchmark de son moteur ;
- sauvegardes, haute disponibilité et montées de majeure en local ;
- les images de base des builds face à Kyverno, que l'ADR-006 laisse ouvertes : la dérogation ne vise que les images que le nœud tire ;
- la composition du profil full, où Kyverno entrerait ;
- Windows (Q5).

## Conséquences

### Positives

- Prête en 8,9 s de médiane, contre 33,8 s pour CloudNativePG et 44,4 s pour Zalando (M1), et de retour en 3,3 s après la suppression du pod (M7). 48,1 Mio de plus au nœud au repos (M2), sous le seuil de 512 Mio.
- Aucun opérateur, aucune CRD, aucun webhook : aucun composant n'obtient de droit sur l'API, et `task up` n'attend aucun webhook.
- Donnée gardée trois fois sur trois dans les trois cas de M6, y compris quand le StatefulSet est supprimé puis réappliqué : sa politique de rétention garde le PVC par défaut, stable depuis Kubernetes 1.32 (BENCH-011, S39).
- 18.7 servie dès le jour de sa sortie, le 2026-11-12, avec ses 52 correctifs de vulnérabilités ; même majeure que Cloud SQL.
- Rien à ajouter au miroir : docker.io y passe déjà, alors que les images des deux opérateurs viennent de ghcr.io.
- Ni le profil lite ni le standard ne changent de palier de mémoire dans le majorant de [FINOPS] : 1 186,6 Mio de plancher en lite (VM de 2,0 Gio, portable de 6,0 Gio), 1 451,8 Mio en standard (2,5 et 6,5 Gio). Ces chiffres mêlent cinq séries et donnent des ordres de grandeur.
- Licence PostgreSQL, déjà dans la liste blanche du catalogue ; aucun service payant.
- Le retour à CloudNativePG ne toucherait que la couche `local` (section « Pourquoi pas l'option pressentie »).

### Négatives

- Du code de CELIAN copié dans chaque projet généré : le StatefulSet, son durcissement, le script d'initialisation et deux Secrets. R-35 en liste six dérives, chacune à une ligne de manifest près.
- ENF-03 n'est pas tenu : aucune signature vérifiable, d'où une dérogation dont la fin dépend de Docker.
- L'image est tenue par deux mainteneurs du programme d'images officielles de Docker (BENCH-011, S38). Si son rythme ralentissait, les paquets du PGDG resteraient disponibles, et CloudNativePG les emploie déjà.
- Volume : 168,5 Mo en amd64, au-dessus du seuil de couche de 112,5 Mo, et 48,3 Mo de plus dans R-04. CloudNativePG en tirait 41,6 Mo de moins.
- Les variables `POSTGRES_*` ne servent qu'à l'initialisation : un Secret recréé sur un volume existant laisserait l'ancien mot de passe en base (condition 3).
- Entrer dans le pod de la base donne le superutilisateur, comme cela donne déjà le fichier du Secret ([SECU]) : le Secret du superutilisateur y est monté.
- Verdict fragile : deux crans de jugement l'inversent.
- Mesures d'un seul poste, arm64 sous OrbStack, moteur non libre (R-26). Restent non mesurés : le redémarrage du nœud, la variante `trixie` à travers zot, `readOnlyRootFilesystem`, et l'effet de la suppression du namespace sur le volume.

### Effet sur les cibles hors MVP

La porte reste ouverte. La couche `local` ne sert que le PC. Une cible AWS ou Azure aurait son service managé dans sa couche, et l'application lirait le même `db-auth`. La valeur unique de la majeure suivrait la logique de l'ADR-004 : le jour où deux clouds coexisteront, la majeure commune demandera un nouvel ADR. Une cible on-prem serveurs aurait son propre benchmark, où pèseraient les sauvegardes et la haute disponibilité de CloudNativePG (BENCH-011, section 7).

### Suites

- [DEV] et [OPS], golden repo de la phase 2 : le StatefulSet, le Service et le script d'initialisation sous les conditions 1 à 9 ; les tâches qui créent les deux Secrets ; l'essai de `readOnlyRootFilesystem` ; l'effet de `pg_isready` sur les journaux ; le profil `restricted` pour l'API et le front (condition 9) ; le mode TLS de la connexion ; les privilèges dont les migrations de l'exemple ont besoin (condition 8).
- [QA] et [SECU] : les contrôles des conditions 1 à 11 dans la matrice ; la règle de Renovate qui ne propose aucune autre majeure (condition 5) ; la relecture de la liste fermée à chaque montée de condensat.
- [OPS] : T2 avec l'image `trixie` (condition 11) ; l'attribut OpenTofu de la version de Cloud SQL, lu dans la valeur unique ; avec [SECU], les privilèges de `cloudsqlsuperuser` face au rôle local.
- [BENCH] : la série `NODE_RESTART=1` après BENCH-012 et BENCH-013, dans une PR à part ; une reprise sur Linux amd64.
- [PO] : dans une PR dédiée, l'exemple de US-004, qui nomme CloudNativePG en local, et les volumes d'ENF-01 que R-04 a mis à jour.
- DSI : R-35 entre au registre avec cette décision ; la liste des valeurs connues de R-20 reçoit `mysecretpassword` ; le suivi de la levée de la dérogation ; l'entrée `database` au catalogue dans la PR de schéma de la phase 3.

### Questions ouvertes

1. Namespace de la base, et données à travers `task app:down`, pour Lucas. La condition 9 met la base dans le namespace de l'application : `task app:down` (ADR-011) la supprime avec ses deux Secrets, et la donnée locale ne survit qu'aux `task up` et aux rechargements successifs. L'autre voie est un namespace à part, que `task app:down` garde. La donnée survivrait alors à cette commande, au prix de deux exemplaires de `db-auth`, un par namespace, que `task up` doit tenir ensemble, et d'une commande qui ne supprime plus toute l'application. Avis de [ARCHI] : un seul namespace. La donnée locale est jetable (R-35), et c'est l'état le plus simple à garder cohérent avec la condition 3.
2. Date de relecture de la dérogation, pour Lucas. Proposée au plus tard le 2027-05-20, date de la prochaine vérification de BENCH-011, en plus de la relecture de [SECU] à chaque montée de condensat. Avis de [ARCHI] : cette date suffit, sauf si Docker publie une date pour son remplaçant de Docker Content Trust ; la relecture se cale alors sur elle.

### Réponses de Lucas (2026-11-21)

Lucas accepte cet ADR le 2026-11-21, avec les avis du DSI et de [ARCHI] sur
les deux questions :

- La base vit dans le namespace de l'application : `task app:down` efface
  la donnée locale avec ses deux Secrets (question 1).
- La dérogation à ENF-03 est relue au plus tard le 2027-05-20, et par
  [SECU] à chaque montée de condensat (question 2).

## Conformité à la constitution

Vérifiée contre la [constitution](../../.specify/memory/constitution.md) en version 1.2.0.

| Principe | Effet | Justification |
| --- | --- | --- |
| I. Rien sans test automatique | respecté | La matrice porte les contrôles des conditions 1 à 11, dont la donnée gardée (M6 a et b), la parité de majeure et l'absence de superutilisateur |
| II. Spec abstraite, catalogue concret | respecté | La spec déclare `database: postgres` ; le StatefulSet vit dans la couche `local`, Cloud SQL dans la couche `gcp`, et l'application lit `db-auth` sur les deux |
| III. Managé sur le cloud, open source ailleurs | respecté | Sur `local`, PostgreSQL sous la PostgreSQL License, approuvée par l'OSI, et des manifests de CELIAN sous Apache-2.0 ; sur `gcp`, Cloud SQL (ADR-008) |
| IV. Catalogue traçable | respecté | L'entrée `database` porte licence, gouvernance, statut, dates et sources (section « Entrée au catalogue ») ; ses `pending` l'écartent des blueprints jusqu'aux vérifications du golden repo, qui n'est pas un blueprint |
| V. Gouvernance ouverte d'abord | respecté | PostgreSQL n'a pas d'éditeur unique : équipe principale de sept membres chez six organisations, sans fondation. CloudNativePG, porté par la CNCF mais dirigé par une seule entreprise, reçoit la même note de gouvernance, 4/5 : l'écart se joue sur d'autres critères |
| VI. Récent mais éprouvé | respecté | Aucun critère éliminatoire : PostgreSQL 18 maintenu jusqu'au 2030-11-14, 18.7 du 2026-11-12, publiée depuis plus de 7 jours, dépôt de l'image créé en 2014. Adoption en production : Cloud SQL sert lui-même PostgreSQL |
| VII. Une commande pour démarrer | respecté | `task up` crée les deux Secrets, applique la couche et attend une requête authentifiée, sans prérequis nouveau ni attente d'un opérateur |
| VIII. Aucun fait de mémoire | respecté | Les faits renvoient à BENCH-011, à ses relectures, à son script et aux pages lues le 2026-11-21. Sont signalés comme non vérifiés : le redémarrage du nœud, la variante `trixie` à travers zot, `readOnlyRootFilesystem`, l'effet de `pg_isready` sur les journaux, le script d'initialisation sous `scram-sha-256` local, le profil `restricted` pour l'API et le front, l'effet de la suppression du namespace, l'état TLS du serveur local, les privilèges de `cloudsqlsuperuser` et l'attribut OpenTofu de la version |
| IX. Aucun secret dans le dépôt | respecté | Aucun objet `Secret` sous `k8s/` ; les deux Secrets naissent à l'exécution par un tube (condition 1 de l'ADR-007), et `mysecretpassword` entre dans la liste des valeurs refusées |
| X. Aucune dépense cloud sans accord | sans objet | Rien n'est créé sur GCP ; la lecture de `server_version` sur Cloud SQL attend le premier apply réel et l'accord de Lucas |

### Dérogations

Une dérogation, décidée par Lucas le 2026-11-21. Elle ne vise aucun principe de la constitution : ENF-03 est une exigence du PRD, et aucun principe n'impose de signature. Elle s'écrit ici parce que la section « Gouvernance » de la constitution veut qu'une dérogation se justifie dans un ADR, avec sa durée et la condition qui la lèvera, et parce que la condition 7 de BENCH-011 la place dans cet ADR.

| Principe | Écart | Justification | Durée | Condition de levée |
| --- | --- | --- | --- | --- |
| Aucun : exigence ENF-03 du PRD, « Kyverno refuse les images non signées » | Les images officielles Docker de la stack n'ont aucune signature vérifiable. Kyverno les admet par leur référence exacte, condensat compris, inscrite dans une liste fermée | FR-008 reste tenu : le condensat fige le contenu, que containerd vérifie. Docker a retiré Docker Content Trust pour ces images, et son remplaçant n'a ni date ni guide le 2026-11-21. Les images signées qui existent ne conviennent pas : Docker Hardened Images demande un compte Docker et un Secret de tirage, qui heurtent le principe VII et R-28, et l'opérande de CloudNativePG n'a pas le script d'initialisation de l'image officielle. La documentation de Kyverno prévoit des exceptions pour des images listées. [SECU] recommande cette voie | Depuis le 2026-11-21, jusqu'à sa levée. Relecture au plus tard le 2027-05-20 (question 2), et par [SECU] à chaque montée de condensat | Docker publie pour ses images officielles une signature que Kyverno sait vérifier. La politique la vérifie alors, et la liste fermée disparaît |

Portée. Toute image du programme d'images officielles de Docker que le nœud tire dans un profil livré, pas seulement Postgres : celles que le dépôt `docker-library/official-images` liste sous `library/` (BENCH-011, S38), servies sous `docker.io/library/`. Dans la stack d'essai, `postgres` en relève ; l'image de Valkey de l'essai, `valkey/valkey`, n'en relève pas (`tests/bench/bench-005-orchestration.sh`, ligne 108). Les autres images se vérifient à l'entrée de Kyverno, par le contrôle de la condition 7. Une image tierce sans signature, hors de ce programme, n'entre pas dans la dérogation : son ADR porte la sienne. Les images de base des builds n'y entrent pas non plus, puisque Kyverno voit l'image construite (ADR-006, portée).

Tenue de la liste. Elle naît avec le premier profil qui embarque Kyverno ; d'ici là, la dérogation n'a pas d'effet. Elle change dans la même PR que le manifest qui change l'image, PR de Renovate comprise, et [SECU] la relit à chaque montée, puisque chaque condensat nouveau refait confiance à Docker Hub (BENCH-011, section 10). Le contrôle de la condition 7 refuse tout écart entre la liste et les images en marche. Le DSI suit la levée au registre des risques, avec R-35.

## Entrée au catalogue

Brique abstraite : `database`, déclarée par la spec (`declared_by: spec`), de valeur `postgres`. BENCH-011 et `catalog/README.md` la nomment `postgres` : le nom du fichier se fixe en phase 3 avec le schéma de spec, comme celui de `secrets` (ADR-007). L'entrée s'écrit au format de l'[ADR-009](ADR-009-catalogue.md), dans la PR de schéma de la phase 3 ; cet ADR ne crée pas le fichier.

| Cible | Service | Type | Licence | Gouvernance | Statut | Vérifié le | Source |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `local` | PostgreSQL, image officielle Docker `postgres` dans un StatefulSet de la couche `local` | `oss` | PostgreSQL | Communauté : PostgreSQL Global Development Group, sans fondation ; image tenue par le programme d'images officielles de Docker | actif | 2026-11-21 | <https://www.postgresql.org/support/versioning/>, <https://github.com/docker-library/docs/blob/master/postgres/README.md> |
| `gcp` | Cloud SQL for PostgreSQL | `managed` | service propriétaire du fournisseur | Éditeur unique : Google | actif | 2026-11-21 | <https://docs.cloud.google.com/sql/docs/postgres/db-versions>, <https://docs.cloud.google.com/sql/docs/postgres/users> |

Ce que porte la ligne `local`, d'après BENCH-011 :

| Champ | Valeur |
| --- | --- |
| `service` | PostgreSQL, image officielle Docker `postgres` dans un StatefulSet de la couche `local` |
| `version` | 18.7 |
| `license` | `PostgreSQL`, identifiant présent dans `scripts/catalog/accepted-licenses.yaml` ; l'empaquetage de l'image est sous MIT (S3) |
| `governance` | `community`, PostgreSQL Global Development Group : équipe principale de sept membres chez six organisations ; image tenue par deux mainteneurs du programme d'images officielles de Docker (S37, S38) |
| `status` | `active` : PostgreSQL 18 maintenu jusqu'au 2030-11-14, dépôt de l'image non archivé (S1, S3) |
| `last_release_on` | 2026-11-19, PostgreSQL 19.0, dernière release amont ; la version servie, 18.7, date du 2026-11-12 (S1, S11) |
| `verified_on` | 2026-11-21, le `read_on` le plus récent : S2, S3 et S38 relues ce jour par [SECU] |
| `standards` | `postgresql-protocol`, déjà dans la liste fermée ; sa gouvernance, « à vérifier à l'entrée de la brique » selon `catalog/README.md`, se relève dans la PR de l'entrée |
| `sources` | S1, S2, S3, S10, S11 et S38 de BENCH-011, avec leurs URL et leurs dates |
| `decisions` | ADR-012, BENCH-011 |
| `pending` | redémarrage du nœud ([BENCH]) ; variante `trixie` à travers zot ([OPS]) ; `readOnlyRootFilesystem` ([OPS]) |

La ligne `gcp` est de type `managed`, `provider: google`, gouvernance `single-vendor` Google, `version` 18, la majeure de la valeur unique (condition 5), standard `postgresql-protocol`, décisions ADR-008 et ADR-012 avec BENCH-008. Elle n'a pas de `managed_gap`. Ses sources sont S12, lue le 2026-11-20, et S53, lue le 2026-11-21.

Le condensat de l'image reste dans le blueprint, que Renovate met à jour, comme le veut l'ADR-009. Le contrôle de l'ADR-009 en tirerait ces échéances pour la ligne `local` : le critère des 12 mois tombe le 2027-11-19 sans nouvelle release, et `verified_on` expire le 2027-05-21.

## Condition de révision

Bascule par un nouvel ADR qui remplace celui-ci si PostgreSQL ou l'image officielle touche un critère éliminatoire : dépôt archivé ou en maintenance, licence qui n'est plus open source, ou aucune release pendant 12 mois, décompte parti du 2026-11-19. De même si Docker cesse de publier l'image officielle `postgres`.

La décision se rouvre, sans basculer d'office, dans ces cas (BENCH-011, section 7, et ajouts de [ARCHI]) :

- un besoin local de sauvegarde ou de plusieurs instances ;
- l'ouverture d'une cible on-prem serveurs ;
- un constat de [SECU] sur l'image officielle, ou un ralentissement de son rythme de reconstruction ;
- CloudNativePG est gradué à la CNCF : sa maturité à 5 la met à 86 contre 87. Si sa direction s'ouvre en plus à plusieurs organisations, sa gouvernance à 5 la met devant, 89 contre 87 ;
- la mesure du redémarrage du nœud montre une perte de données qu'aucune condition ne corrige ;
- le profil `restricted` ou le script d'initialisation sous `scram-sha-256` se révèlent impossibles avec l'image officielle ;
- T2 échoue avec l'image `trixie` (condition 11) ;
- Lucas retient un namespace à part (question 1) : la condition 9 se réécrit.

La levée de la dérogation ne rouvre pas la décision : la PR qui retire la liste fermée l'indique ici par un lien. Une montée de mineure de PostgreSQL ne la rouvre pas non plus : elle passe par Renovate et la matrice. Un changement de la majeure par défaut de Cloud SQL suit la règle de la condition 5, dans une release du blueprint. Sans l'un de ces faits, prochaine vérification à la sortie de CloudNativePG 1.31, attendue vers décembre 2026, ou au plus tard le 2027-05-20, dates proposées par BENCH-011.

## Sources

Ce que BENCH-011 établit se cite par lui ; ses propres sources sont dans sa section 9.

| Source | Lue le | Ce qu'elle établit |
| --- | --- | --- |
| [BENCH-011](../benchmarks/BENCH-011-postgres-local.md), sections 1 à 3 | 2026-11-21 | Question posée et ce qui en dépend ; option pressentie par le PRD ; options, versions et options non étudiées ; critères éliminatoires ; parité de version avec Cloud SQL |
| BENCH-011, section 4 | 2026-11-21 | Seuils écrits avant la mesure ; mise en œuvre d'O1, UID 999, `db-auth` lu par fichier ; protocole ; M1 à M9 ; classe `standard` en `Delete` ; M6 ; versions servies ; redémarrage du nœud non mesuré |
| BENCH-011, sections 5 et 6 | 2026-11-21 | Notes, justifications et grille réconciliée : 87, 83 et 61 |
| BENCH-011, section 7 | 2026-11-21 | Verdict et raisons ; sensibilité ; réserves ; conditions 1 à 8 ; réversibilité ; conditions en cas de CloudNativePG ; entrée au catalogue proposée ; R-35 ; arbitrage du DSI et décisions de Lucas du 2026-11-21 ; prochaine vérification |
| BENCH-011, sections 8 à 10 | 2026-11-21 | Limites, dont la suppression du namespace ; sources S1 à S3, S10 à S12, S37 à S39, S45, S49 à S53, S55 à S57 et S59 citées ici ; relectures de [SECU] (signature, rôle de l'application, `seccompProfile`, trois voies pour ENF-03, `mysecretpassword`) et de [FINOPS] (cumul avec le premier `task up`, mémoire des profils, zot) |
| `tests/bench/bench-011-postgres.sh`, lignes 84-85, 252, 401-419, 498 et 508, branche de la PR #35 | 2026-11-21 | Condensat de `postgres:18.7-trixie` ; Secret `db-auth`, type `kubernetes.io/basic-auth`, clés `username` (`app`) et `password` ; StatefulSet de l'essai |
| `tests/bench/bench-005-orchestration.sh`, lignes 107-108 | 2026-11-21 | Images de Postgres et de Valkey de la stack d'essai : `postgres:18.7-alpine`, `valkey/valkey:9.1.4-alpine` |
| <https://github.com/docker-library/docs/blob/master/postgres/README.md> | 2026-11-21 | « scripts in `/docker-entrypoint-initdb.d` are only run if you start the container with a data directory that is empty » ; `POSTGRES_USER` « will create the specified user with superuser power » ; suffixe `_FILE` pour `POSTGRES_INITDB_ARGS`, `POSTGRES_PASSWORD`, `POSTGRES_USER` et `POSTGRES_DB` |
| <https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/> | 2026-11-21 | `secretKeyRef` « Selects a key of a secret in the pod's namespace » ; `secretName` « is the name of the secret in the pod's namespace to use » |
| [docs/risques.md](../risques.md), R-04, R-20, R-25, R-28, R-35, dans la branche de la PR #35 | 2026-11-21 | Cumul du premier `task up` avec l'image retenue ; liste des valeurs connues ; registres publics ; secrets en clair dans etcd ; dérives du Postgres écrit à la main et leurs mitigations |
| [ADR-004](ADR-004-cluster-local.md), condition 3 et règle de version | 2026-11-21 | Images par condensat ; mineure tenue en une seule valeur pour les deux couches ; écart de correctif admis et listé au README |
| [ADR-006](ADR-006-orchestration-locale.md), décision, condition 1, portée, question 4 | 2026-11-21 | Étapes de `task up` ; aucun Secret sous `k8s/` ; forme de Postgres laissée ouverte ; images construites face à Kyverno ; lecture de US-005 en deux commandes |
| [ADR-007](ADR-007-secrets.md), conditions 1 et 5, conséquences, entrée au catalogue | 2026-11-21 | Secrets créés par un tube, seulement s'ils n'existent pas, liste des valeurs connues ; parité du nom et des clés ; Secrets gardés au redémarrage du nœud (M7 de BENCH-007) ; brique `secrets` au nom provisoire |
| [ADR-008](ADR-008-modules-opentofu-gcp.md), portée et conséquences | 2026-11-21 | Cloud SQL en IP privée, `ENCRYPTED_ONLY`, sauvegardes ; versions de Postgres hors de sa portée |
| [ADR-009](ADR-009-catalogue.md), [`catalog/README.md`](../../catalog/README.md), `schema/catalog-entry.schema.json`, `scripts/catalog/accepted-licenses.yaml` | 2026-11-21 | Format d'une entrée, gouvernance `community`, `pending` ; condensats hors du catalogue ; règles de fraîcheur ; `postgresql-protocol` dans la liste fermée ; `PostgreSQL` dans la liste blanche |
| [ADR-011](ADR-011-miroir-registres.md), proposé : décision, commandes, registres servis, condition 10, portée | 2026-11-21 | Miroir zot sur docker.io ; `task down` et `task app:down` ; Postgres Alpine servi par zot à T2, `trixie` non mesurée ; T2 par profil livré ; arrêt du nœud hors de sa décision |
| [specs/001-golden-repo-saas-b2b/spec.md](../../specs/001-golden-repo-saas-b2b/spec.md), récits 1 et 2, FR-004, FR-007, FR-008, FR-017 | 2026-11-21 | Rechargement sans perte de données ; secrets et données gardés à la relance ; secrets aléatoires ; condensats ; base locale selon BENCH-011 |
| [docs/prd-mvp.md](../prd-mvp.md), US-004, US-005, ENF-01, ENF-02, ENF-03 | 2026-11-21 | CloudNativePG en exemple, à confirmer ; démarrage et arrêt ; budget de 15 minutes ; parité et écarts au README ; Kyverno refuse les images non signées |
| [Constitution](../../.specify/memory/constitution.md), version 1.2.0 | 2026-11-21 | Principes I à X ; dérogation justifiée dans un ADR, avec sa durée et sa condition de levée ; exception de sécurité au délai de 7 jours |
