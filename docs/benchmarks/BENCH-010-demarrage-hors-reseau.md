# BENCH-010. Démarrage hors réseau du cluster local

| Champ | Valeur |
| --- | --- |
| Identifiant | BENCH-010 |
| Sujet | Faire démarrer `task up` sur kind sans accès aux registres publics |
| Statut | brouillon |
| Ouvert le | 2026-11-20 |
| Mis à jour le | 2026-11-20 |
| Auteur | [OPS] |
| Relecteurs | [SECU] pour les licences et les CVE, [FINOPS] pour les coûts |
| Périmètre | Projet généré sur PC (cluster local) |
| Choix du PRD | Aucun choix ouvert : condition 7 de l'ADR-004, condition 4 de l'ADR-005 et de l'ADR-006, risque R-25 |
| ADR lié | ADR-011 à écrire par [ARCHI] |
| Verdict proposé | O2 avec zot 2.1.23, 83 sur 100, seul mécanisme qui passe la recréation hors réseau (T2) ; O1 en complément selon la lecture de US-005 |

## 1. Contexte

[OPS] Question : quel mécanisme fait atteindre « prêt » à `task up` sur kind
sans aucun accès aux registres publics, une fois qu'un premier `task up` a
tourné avec le réseau ? Deux cas sont jugés : la relance avec le cluster
gardé (T1) et la recréation après suppression du cluster (T2).

[OPS] Ce qui en dépend : la condition 7 de l'ADR-004 (recréation hors ligne,
soit T2), la condition 4 de l'ADR-005 et de l'ADR-006, qui demandent de
traiter R-25 avant le golden repo, et R-25 lui-même. ENF-01 fixe le budget de
900 s, US-005 la commande qui « arrête et supprime l'environnement ». ENF-03
et la condition 3 de l'ADR-004 imposent les références par condensat : R-25
refuse de revenir aux tags ou à `imagePullPolicy: Never`. Principe VII : une
seule commande, sans étape manuelle autre que les prérequis du README.

[OPS] Option pressentie : garder le cluster (O1), que la condition 4 de
l'ADR-006 place en tête de l'ordre d'essai. Elle est mesurée comme les autres.

[OPS] Hors champ : la construction de l'API et du front sur le poste, qui
garde son réseau pendant l'essai (section 8) ; les images de la plate-forme
de base (BENCH-004) et de l'outil GitOps (BENCH-009), auxquelles le mécanisme
retenu s'appliquera de la même façon ; le cache d'images de la CI ; GKE.

## 2. Options étudiées

| Option | En une phrase | Version examinée | Publiée le | Sources |
| --- | --- | --- | --- | --- |
| O1, garder le cluster | `task down` supprime le namespace de l'application et garde le cluster, que le `task up` suivant réutilise | kind 0.33.0, aucune brique ajoutée | sans objet | [S1] |
| O2, miroir Distribution | Registre en cache pull-through de Docker Hub, sur le réseau `kind`, sans port publié ; le containerd du nœud lui envoie docker.io | 3.1.2, image `registry:3.1.2` figée par condensat | 2026-09-24 | [S2], [S11], [S14] |
| O2, miroir zot | Même rôle, par la synchronisation à la demande de zot | 2.1.23, image figée par condensat | 2026-11-02 | [S15], [S18] |
| O3, archive OCI | Archives chargées dans chaque nœud neuf par `kind load image-archive` ; source mesurée : `docker save` du cache du poste | kind 0.33.0, Docker Engine 29.8.2 | sans objet | [S1], [S3], [S7] |
| O4, magasin containerd du moteur | Le moteur range les images avec leur index ; documenté, non mesuré, puisque l'essai ne touche pas au moteur du poste | Docker Engine 29.0 et plus | sans objet | [S5], [S6] |

[OPS] Repérées, non étudiées. Une archive O3 qui garde l'index du registre :
il faut la découper dans le stockage d'un miroir, donc dépendre d'O2, ou la
produire avec un outil de copie OCI absent du poste, qui deviendrait un
prérequis de plus du projet généré. Le script garde cette variante
(`ARCHIVE_SOURCE=zot`) pour un essai ultérieur. Ensuite, arrêter le nœud entre
deux sessions au lieu de le garder en marche : cette variante d'O1 libérerait
la mémoire de M8, mais elle demande `docker start`, interdit aux agents, et
n'a pas été mesurée.

## 3. Critères éliminatoires

| Option | Licence open source | Ni archivé ni en maintenance | Release de moins de 12 mois | Vérifié le | Résultat |
| --- | --- | --- | --- | --- | --- |
| O1, O3, O4 | Sans objet : aucune brique ajoutée. kind passe ces critères dans BENCH-003 ; Docker Engine est un prérequis (R-26) | Sans objet | Sans objet | 2026-11-20 | Retenues |
| Distribution | Oui, Apache-2.0 [S12], approuvée par l'OSI [S20] | Oui, dépôt non archivé [S21], projet Sandbox de la CNCF [S13] | Oui, 3.1.2 le 2026-09-24 [S11] | 2026-11-20 | Retenue |
| zot | Oui, Apache-2.0 [S16], [S20] | Oui, dépôt non archivé [S21], projet Sandbox de la CNCF [S17] | Oui, 2.1.23 le 2026-11-02 [S15] | 2026-11-20 | Retenue |

[OPS] Aucune option éliminée à ce stade. Les tests T1 et T2 de la section 4.1
écartent ensuite les mécanismes qui ne démarrent pas hors réseau.

## 4. Mesures

### 4.1 Ce qui est mesuré

[OPS] Mesures et seuils écrits le 2026-11-20 à 17:44 UTC, avant la première
mesure de ce benchmark. Aucun commit ne fige cette section (consigne du DSI :
aucun commit) ; son SHA-256 est relevé au même moment dans le dossier d'essai,
et rappelé en 4.4.

[OPS] Deux tests jugent chaque mécanisme, avant toute note. Ils sont
éliminatoires et ne retirent pas de cran.

- T1, relance hors réseau : un premier `task up` avec réseau, puis
  `task down`, puis un `task up` sans aucun accès aux registres publics, qui
  atteint « prêt ». C'est le test que le DSI a fixé pour BENCH-010.
- T2, recréation hors réseau : le même enchaînement, avec un `task down` qui
  supprime le cluster. C'est le test de la condition 7 de l'ADR-004.

« Prêt » reprend la sonde de BENCH-005 : l'API et le front répondent avec
les marqueurs de l'exécution, Postgres et Valkey acceptent une connexion.
L'absence de réseau se simule dans le nœud, sans toucher au poste : la
configuration des registres de containerd fait pointer chaque registre public
vers un point mort, sans repli vers l'amont. La preuve tient en deux relevés :
les événements `Pulled` du nœud, et l'échec attendu de tirages témoins.

| ID | Mesure | Unité | Critère alimenté | Script |
| --- | --- | --- | --- | --- |
| M1 | `task up` hors réseau, de la première commande à « prêt », cluster gardé (T1) ou recréé (T2) | s | Empreinte sur PC | `tests/bench/bench-010-offline.sh` |
| M2 | Premier `task up` avec réseau, mécanisme compris | s | Information, une exécution | idem |
| M3 | Images tirées pendant le `task up` hors réseau : événements `Pulled` du nœud, événements `pull` du moteur Docker | nombre | T1, T2 | idem |
| M4 | Tirages témoins hors réseau : une image absente par registre public (docker.io, quay.io, registry.k8s.io, ghcr.io, mcr.microsoft.com), attendus en échec ; une image de la stack en `imagePullPolicy: Always` | constat | T1, T2, sécurité | idem |
| M5 | Volume ajouté sur le disque du poste : registre (image et stockage), archives, couche inscriptible d'un nœud gardé | Mo | Information | idem |
| M6 | Volume supplémentaire téléchargé par le premier `task up` à cause du mécanisme, en linux_amd64 | Mo | Empreinte sur PC (ENF-01, R-04) | idem, tailles lues au registre |
| M7 | Mémoire ajoutée au repos, 120 s après « prêt » : nœud kind moins nœud de base, plus le conteneur du registre s'il y en a un, en médianes | Mio | Empreinte sur PC | idem |
| M8 | Mémoire tenue entre deux sessions, 120 s après `task down` : nœud gardé, registre | Mio | Empreinte sur PC | idem |
| M9 | Adresses d'écoute des ports publiés par les conteneurs du script | adresse | Sécurité (R-20) | idem |

[OPS] Le nœud de base est celui de l'option `base` du script : la stack de
BENCH-005 en O4, configuration de kind sans mécanisme, tirée sur le réseau du
poste à chaque création. La règle de mémoire est la règle provisoire du DSI,
reprise de BENCH-009 (section 4.1) : nœud avec le mécanisme moins nœud de
base, en médianes, relevés par `docker stats`.

#### Seuils de la note d'empreinte (section 5.6)

[OPS] Règle de `TEMPLATE.md`, section 5.6 : seuils absolus, tirés du PRD ou
d'un débit de 10 Mbit/s pris comme hypothèse. Chaque option part de 5 et perd
un cran par seuil dépassé. Les seuils notent les mécanismes qui passent T1 ou
T2, et l'empreinte des deux registres candidats de O2 (section 5.6).

1. M1, médiane, au-delà de 90 s : 10 % du budget de 900 s d'ENF-01. Repris
   de BENCH-003 et BENCH-005.
2. M6 au-delà de 112,5 Mo en linux_amd64 : 90 s à 10 Mbit/s, 10 % du budget.
   Repris du seuil de couche de BENCH-009 : le mécanisme est une couche de la
   plate-forme de base, au même titre que l'outil GitOps. Le volume se lit sur
   linux_amd64, pire cas des systèmes de Q5.
3. M7, médiane, au-delà de 512 Mio : un seizième d'un portable de 8 Gio.
   Repris du seuil de couche de BENCH-009.
4. M8 au-delà de 512 Mio : le même seuil, appliqué à ce qui reste en mémoire
   quand l'environnement est arrêté.

[OPS] Biais à déclarer : BENCH-005 a mesuré le cluster kind seul au repos à
562,7 Mio (M10), chiffre connu en écrivant le seuil 4. Le seuil n'en est pas
tiré : il reprend tel quel celui de BENCH-009. Les tailles des images des
registres candidats n'ont pas été lues avant cette section ; leurs
dernières releases et leurs avis de sécurité l'ont été.

[OPS] Une option à moins de 10 % d'un seuil voit ses deux notes possibles
écrites dans la sensibilité de la section 7. M2 et M5 sont relevés sans
seuil : le PRD ne fixe aucun budget de disque, et le premier `task up` est
déjà couvert par R-04.

### 4.2 Machine de mesure

| Élément | Valeur |
| --- | --- |
| Modèle | Apple Mac16,7 |
| Processeur | Apple M4 Pro, 14 cœurs (10 performance, 4 efficacité), arm64 |
| Mémoire | 24 Gio |
| Système | macOS 27.2.1 (build 26B131) |
| Moteur de conteneurs | OrbStack 2.2.5 (moteur non libre, voir R-26), Docker Engine 29.8.2, pilote overlay2 : magasin d'images classique |
| Ressources allouées | Machine virtuelle d'OrbStack : 14 CPU, 11,73 Gio (12 598 894 592 octets, `docker info`) |
| Versions mesurées | kind 0.33.0, image de nœud `kindest/node:v1.36.4@sha256:099e…faed` (ADR-004), containerd 2.3.4 dans le nœud ; kubectl 1.37.1 ; Distribution 3.1.2 et zot 2.1.23, images figées par condensat dans le script ; stack de BENCH-005, images figées par condensat |
| Charge parasite | Applications de bureau ouvertes. Charge moyenne sur une minute entre 3,54 et 14,64 au début des exécutions de la série 1 (`load.tsv`), aucun autre cluster kind. Pendant O2, le registre de l'autre candidat tournait à vide : les deux `docker run` de chaque phase ont été groupés pour limiter les confirmations demandées à Lucas |

### 4.3 Protocole

1. État de départ de chaque série : aucun cluster `celian-bench-010`, verrou
   partagé `bench-lock-s4` pris (code 75 sinon). Les images de la stack et
   l'image de nœud sont dans le cache Docker du poste ; le nœud, lui, n'y a
   pas accès.
2. `task up`, identique pour toutes les options : cluster kind créé avec
   `tests/bench/bench-010/kind.yaml` (API en 127.0.0.1, `config_path` de
   containerd vers un dossier de l'essai monté en lecture seule), Secret
   Postgres passé par un tube, `docker build` et `kind load docker-image` de
   l'API et du front, `kubectl apply -k`. O1 réutilise le cluster s'il
   existe ; O3 charge ses trois archives par `kind load image-archive` juste
   après la création.
3. Hors réseau, dans le nœud seulement : le script écrit un `hosts.toml` par
   registre public (`_default`, docker.io, quay.io, registry.k8s.io, ghcr.io,
   mcr.microsoft.com, gcr.io, public.ecr.aws) dont le `server` est
   `https://127.0.0.1:9`, où rien n'écoute. containerd essaie les hôtes
   déclarés, puis `server` en dernier [S4]. Pour O2, docker.io passe d'abord
   par le miroir, puis par le même point mort. Le moteur du poste garde son
   réseau et sa configuration.
4. Fin de la mesure : la première ligne de la sonde de BENCH-005 qui porte
   les marqueurs de l'exécution. Un lancement hors réseau est noté « non
   prêt » dès qu'un pod de la stack reste 45 s en `ErrImagePull` ou
   `ImagePullBackOff`.
5. Relevés de chaque exécution : 120 s après « prêt », trois échantillons
   `docker stats` du nœud et du registre espacés de 10 s, médiane ;
   événements `Pulled` et `Failed` du nœud, événements `pull` du moteur,
   noms d'images du statut du nœud, requêtes servies par le miroir. Après
   chaque lancement hors réseau, les six tirages témoins de
   `tests/bench/bench-010/witness.yaml`. Pour O1 et O2, 120 s après chaque
   `task down`, trois échantillons de ce qui reste en mémoire (M8).
6. Séquence : exécution 0 avec le réseau (M2), `task down`, puis trois
   exécutions hors réseau, chacune suivie de `task down`, 15 s de pause.
   L'option `base` fait trois exécutions avec le réseau : c'est le nœud de
   base de M7.
7. O2 se joue en quatre étapes, parce que le script ne lance aucun
   conteneur : une commande lancée dans un script échappe aux règles de
   permission de Claude Code. La préparation écrit la configuration et
   imprime la commande `docker run` ; Lucas la confirme ; la phase en ligne
   fait l'exécution 0 ; le nettoyage retire le registre. Puis une nouvelle
   préparation écrit la configuration hors réseau, dont l'amont est le même
   point mort, et un nouveau conteneur démarre sur le même stockage pour les
   exécutions 1 à 3. C'est un démarrage à froid sans amont, comme après un
   redémarrage du poste hors réseau.

Pour refaire la mesure :

```bash
OPTIONS="base keep archive" BENCH_LOCK=/chemin/vers/un/verrou tests/bench/bench-010-offline.sh /chemin/vers/un/dossier/vide
# O2, pour REGISTRY=distribution puis REGISTRY=zot :
MIRROR_PHASE=prepare-online REGISTRY=zot REGISTRY_DIR=/chemin/du/registre tests/bench/bench-010-offline.sh
# lancer la commande docker run imprimée, puis :
OPTIONS=mirror MIRROR_PHASE=online REGISTRY=zot REGISTRY_DIR=/chemin/du/registre BENCH_LOCK=/chemin/vers/un/verrou tests/bench/bench-010-offline.sh /chemin/vers/un/autre/dossier
MIRROR_PHASE=prepare-offline REGISTRY=zot REGISTRY_DIR=/chemin/du/registre tests/bench/bench-010-offline.sh
# lancer la nouvelle commande docker run imprimée, puis :
OPTIONS=mirror MIRROR_PHASE=offline REGISTRY=zot REGISTRY_DIR=/chemin/du/registre BENCH_LOCK=/chemin/vers/un/verrou tests/bench/bench-010-offline.sh /chemin/vers/un/troisieme/dossier
```

[OPS] Le script refuse de démarrer si le cluster existe ou si le verrou est
pris (code 75), et son `trap` n'est posé qu'après ces contrôles. Il ne lance
ni `docker run`, ni `docker start`, ni `docker restart`, ni `docker exec`. Il
n'utilise un registre que si son label, son image et ses montages sont ceux
attendus, et le retire à la sortie ; le stockage reste. `umask 077`,
`KUBECONFIG` dans le dossier d'essai, mot de passe Postgres tiré par openssl
et passé par un tube (R-20).

### 4.4 Résultats

[OPS] Série 1 (base, O1, O3) le 2026-11-20 de 19:11:26 à 19:54:51 UTC, script
de SHA-256 `7bc15b06…3f35`. O2 en quatre phases de 21:11:56 à 21:47:49 UTC,
script de SHA-256 `ec6810b7…c6ff`, qui ajoute les phases d'O2 sans toucher
aux chemins de mesure des autres options. Trois exécutions par mesure. M2 est
relevé une fois par option, comme le prévoit la section 4.1 ; M5, M6 et M9
une fois par option, parce qu'ils ne varient pas d'un lancement à l'autre.
M8 est relevé après chaque `task down`, et non une seule fois en fin de
série comme dans le brouillon du script, pour en avoir trois exécutions ; les
seuils n'ont pas changé.

[OPS] La section 4.1 n'a pas changé : son SHA-256, relevé le 2026-11-20 à
17:46:24 UTC, vaut `2a07279a…7bb5d` et correspond au texte ci-dessus. Des
tests de fumée ont tourné après les seuils et avant les mesures, de 18:06 à
18:22 UTC. Une première série, de 18:45 à 18:56 UTC, a été interrompue par
la fermeture de la session qui la portait. Ses trois exécutions de base sont
écartées : elles venaient d'une version du script qui arrêtait la série au
premier lancement hors réseau non prêt, et la base a été refaite dans la
série 1, dans les mêmes conditions que les autres options.

| Mesure | Option | Exécution 1 | Exécution 2 | Exécution 3 | Médiane | Écart |
| --- | --- | --- | --- | --- | --- | --- |
| M1, relance hors réseau, cluster gardé (T1) | O1 | 15,6 s | 12,8 s | 10,2 s | 12,8 s | 5,4 s |
| M1, recréation hors réseau (T2) | O3, archives `docker save` | non prêt | non prêt | non prêt | non prêt | sans objet |
| M1, recréation hors réseau (T2) | O2, Distribution | non lancé | non lancé | non lancé | non prêt | sans objet |
| M1, recréation hors réseau (T2) | O2, zot | 34,7 s | 36,5 s | 33,5 s | 34,7 s | 3,0 s |
| Référence, avec réseau, cluster créé | base | 35,3 s | 36,9 s | 36,8 s | 36,8 s | 1,6 s |
| M3, images tirées hors réseau (`Pulled` / en échec / `pull` du moteur) | O1 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 |
| M3 | O3 | 0 / 3 / 0 | 0 / 3 / 0 | 0 / 3 / 0 | 0 / 3 / 0 | 0 |
| M3 | O2, zot (tirages servis par le miroir) | 3 / 0 / 0 | 3 / 0 / 0 | 3 / 0 / 0 | 3 / 0 / 0 | 0 |
| M7, mémoire du nœud au repos | base | 690,8 Mio | 713,6 Mio | 782,8 Mio | 713,6 Mio | 92,0 Mio |
| M7 | O1, hors réseau | 782,6 Mio | 782,4 Mio | 799,5 Mio | 782,6 Mio | 17,1 Mio |
| M7 | O2, zot, nœud | 717,5 Mio | 700,4 Mio | 778,8 Mio | 717,5 Mio | 78,4 Mio |
| M7 | O2, zot, registre | 50,2 Mio | 51,1 Mio | 50,9 Mio | 50,9 Mio | 0,9 Mio |
| M8, mémoire tenue 120 s après `task down` | O1, nœud gardé | 672,1 Mio | 661,8 Mio | 664,5 Mio | 664,5 Mio | 10,3 Mio |
| M8 | O2, zot, registre | 51,2 Mio | 50,7 Mio | 56,3 Mio | 51,2 Mio | 5,6 Mio |

[OPS] O1, T1 passé trois fois sur trois : aucun tirage, cinq images déjà
présentes (Postgres, Valkey, busybox, l'API et le front fraîchement chargés),
aucun tirage du moteur.

[OPS] O3, T2 échoué trois fois sur trois, et le dernier maillon de R-25 est
désormais observé. `kind load image-archive` accepte chaque archive (trois
chargements réussis par exécution). containerd range alors les images sous
le condensat de l'archive, par exemple
`docker.io/library/import-2026-11-20@sha256:1740008b…` pour Postgres, et non
sous celui du registre, `postgres@sha256:ff64c9e3…`. kind importe en effet
par `ctr images import --all-platforms --digests` [S3], et l'archive de
`docker save` n'a ni nom ni index du registre : le magasin classique ne garde
pas les index [S5], [S6]. Le kubelet demande l'image sous le condensat du
registre, ne la trouve pas, et part au registre, où il tombe sur le point
mort (« dial tcp 127.0.0.1:9: connect: connection refused »). Le cluster
lui-même se recrée sans réseau : les images système de kind sont dans
l'image de nœud. Ces trois exécutions servent donc aussi de témoin pour un
cluster recréé sans aucun mécanisme.

[OPS] O2, Distribution : T2 échoué, avant même le premier lancement. Le
conteneur démarré avec la configuration hors réseau s'était arrêté moins
d'une minute plus tard, quand la phase a commencé. La seule différence avec
la configuration en ligne est l'URL d'amont. Le code de la version 3.1.2
l'explique : en mode proxy, le démarrage interroge `/v2/` sur l'amont pour
y découvrir l'URL des jetons, et une erreur fait lever un `panic` à
l'application [S27]. Le nettoyage du script a retiré le conteneur avant
lecture de son journal : le code de sortie n'est pas relevé. Distribution
en cache pull-through ne redémarre donc pas sur un poste sans réseau, après
un redémarrage par exemple. Le cas d'un miroir resté en marche quand le
réseau tombe n'est pas testé (section 8).

[OPS] O2, zot : T2 passé trois fois sur trois, avec un registre démarré à
froid, sans amont, sur le stockage rempli par l'exécution 0. À chaque
exécution, le nœud neuf tire Postgres, Valkey et busybox depuis le miroir :
manifests et blobs servis en 200, aucune erreur d'amont dans le journal du
registre, aucun tirage du moteur. Les trois images de la stack sont des index
OCI : zot les garde sous leurs condensats, comme le fait sa synchronisation
depuis la version 2.1.22 [S18].

[OPS] M2, premier `task up` avec le réseau, une exécution : O1 35,4 s ; O3
38,2 s, plus 1,9 s pour écrire les archives après coup ; O2 Distribution
37,9 s ; O2 zot 39,0 s. La base, sans mécanisme, donne 36,8 s en médiane.

[OPS] M4, tirages témoins. Après chaque lancement hors réseau d'O1 et d'O3,
les cinq images absentes (docker.io, quay.io, registry.k8s.io, ghcr.io,
mcr.microsoft.com) échouent, et chaque erreur nomme le point mort
`https://127.0.0.1:9`. L'image `busybox` déjà présente, en
`imagePullPolicy: Always`, échoue aussi : le kubelet délègue alors au runtime,
qui interroge le registre même quand l'image est en cache [S8]. Avec zot, les
cinq images absentes échouent aussi : celle de docker.io sur une réponse 503
du miroir, qui ne joint pas son amont, les quatre autres sur le point mort.
Le pod en `imagePullPolicy: Always` démarre, trois fois sur trois : le miroir
répond à la résolution du condensat. C'est la seule option qui supporte ce
réglage hors réseau, celui de huit conteneurs d'Argo CD (BENCH-009).

[OPS] M5, disque. O1 garde le volume `/var` du nœud, 2,157 Go selon
`docker system df`, et une couche inscriptible de 3,66 Mo ; ce volume
disparaît avec le cluster dans les autres options. O3 écrit 352,5 Mo
d'archives (couches non compressées : Postgres 301,3 Mo, Valkey 46,1 Mo,
busybox 4,4 Mo). O2 : stockage de 134,2 Mo pour Distribution et 139,4 Mo
pour zot après l'exécution 0, en arm64, plus l'image du registre dans le
cache du poste (61,5 Mo et 242,7 Mo décompressés).

[OPS] M6, volume ajouté au premier `task up`, en linux_amd64, lu au registre
par `docker buildx imagetools inspect` (configuration et couches) : O1 0 Mo ;
O2 Distribution 20,45 Mo, O2 zot 77,67 Mo (19,15 et 70,53 Mo en arm64). O3
ajouterait sur un poste neuf le tirage des trois images par le moteur,
141,30 Mo, pour un mécanisme qui ne démarre pas hors réseau.

[OPS] M7, mémoire ajoutée au repos : O1 +69,0 Mio (782,6 moins 713,6), dans
l'écart de la base elle-même (92,0 Mio). O2 zot +54,8 Mio : nœud 717,5
moins 713,6, plus le registre, 50,9. Le registre Distribution tenait
16,8 Mio au repos pendant sa phase en ligne, chiffre donné pour information.

[OPS] M8, entre deux sessions : O1 garde le nœud en marche, 664,5 Mio en
médiane des trois exécutions hors réseau (626,9 Mio après l'exécution 0).
O2 zot ne garde que son registre, 51,2 Mio : le nœud est supprimé.

[OPS] M9 : seul l'API du nœud est publiée, en `127.0.0.1:<port>->6443/tcp`.
Les registres n'ont aucun port publié (`"5000/tcp": null` dans
`docker inspect`). Aucune adresse 0.0.0.0, `[::]` ou `*`.

## 5. Notation par critère

[OPS] La grille de la section 8 du brief note des technologies. O1, O3 et O4
n'en ajoutent aucune : ils se jugent par T1, T2 et l'empreinte (5.6). Les
huit autres critères ne s'appliquent qu'aux registres d'O2, seules briques
nouvelles. O3 et Distribution sont éliminés par T2 et ne sont pas notés ; O4
n'est pas mesuré. Ce cadrage est à valider par le DSI.

### 5.1 Licence et liberté d'usage, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1 | sans objet | sans objet | Aucune brique ajoutée | |
| O2, zot | 5/5 | 15 | Apache-2.0, comme le générateur ; un miroir alimenté sur le poste ne redistribue rien (R-25) | [S16], [S20] |

### 5.2 Gouvernance (fondation, multi-vendeurs), poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1 | sans objet | sans objet | Aucune brique ajoutée | |
| O2, zot | 4/5 | 12 | Projet Sandbox de la CNCF depuis le 2022-12-13, premier niveau de maturité de la fondation ; cinq mainteneurs de cinq organisations (Microsoft, Ciroos AI, Geico, Luxoft, AMD) | [S17], [S22] |

### 5.3 Maturité et adoption, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1 | sans objet | sans objet | Aucune brique ajoutée | |
| O2, zot | 3/5 | 9 | Sandbox depuis 2022. La documentation de la 2.1.23 ne cite qu'un adoptant, Cisco, aussi sponsor, et le dépôt n'a pas de liste d'adoptants. Réserve qui demande une action : relire l'adoption à la prochaine vérification | [S17], [S21], [S28] |

### 5.4 Activité et maintenance, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1 | sans objet | sans objet | Aucune brique ajoutée | |
| O2, zot | 5/5 | 10 | Treize releases en 12 mois, la dernière le 2026-11-02 ; 482 commits et 65 auteurs humains depuis le 2025-11-20 | [S15], [S21] |

### 5.5 Sécurité (CVE, réactivité), poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1 | sans objet | sans objet | Aucune brique ajoutée | |
| O2, zot | 3/5 | 6 | Politique de signalement publiée ; 21 avis en 12 mois (1 critique, 11 élevés, 9 moyens), tous corrigés au plus tard en 2.1.22, dont un sur la synchronisation à la demande, corrigé en 2.1.21. Réserve qui demande une action : suivre les avis chaque mois, n'activer que l'extension `sync`, ne publier aucun port | [S24], [S26] |

### 5.6 Empreinte sur PC (RAM, CPU, démarrage), poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1 | 4/5 | 8 | M1 12,8 s, M6 0 Mo et M7 +69,0 Mio sous leurs seuils ; M8 664,5 Mio au-dessus de 512 Mio, parce que le nœud reste en marche entre deux sessions | [M1], [M6], [M7], [M8] |
| O2, zot | 5/5 | 10 | M1 34,7 s, M6 77,67 Mo, M7 +54,8 Mio, M8 51,2 Mio : aucun seuil franchi, aucun à moins de 10 % | [M1], [M6], [M7], [M8] |

### 5.7 Portabilité multi-cloud, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1 | sans objet | sans objet | Aucune brique ajoutée | |
| O2, zot | 4/5 | 8 | Un conteneur sur le réseau `kind`, selon la recette de kind, sans code propre au système du poste. Réserve mineure : il ne sert que la couche `local`, GKE tire ses images sans lui (principe III) | [S2], [S18] |

### 5.8 Expérience dev et documentation, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1 | sans objet | sans objet | Aucune brique ajoutée | |
| O2, zot | 4/5 | 8 | Configuration JSON courte, synchronisation documentée pour la version mesurée ; l'essai a marché du premier coup, démarrage à froid compris. Réserve mineure : la documentation ne dit pas ce que sert le cache quand l'amont manque, seul l'essai le montre | [S18], [M1] |

### 5.9 Coût (managé ou opérationnel), poids 5

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1 | sans objet | sans objet | Aucune brique ajoutée | |
| O2, zot | 5/5 | 5 | Aucune licence ni service payant ; un conteneur de 50,9 Mio au repos, 77,67 Mo téléchargés une fois | [S16], [M6], [M7] |

## 6. Grille pondérée

| Critère | Poids | O1 | O2, Distribution | O2, zot | O3 | O4 |
| --- | --- | --- | --- | --- | --- | --- |
| Critères éliminatoires (section 3) | éliminatoire | passe | passe | passe | passe | passe |
| T1 et T2 (section 4.1) | éliminatoire | T1 passe, T2 hors de sa portée | T2 échoue | T1 et T2 passent | T1 et T2 échouent | non mesuré |
| Licence et liberté d'usage | 15 | sans objet | éliminée | 5/5, 15 pts | éliminée | non mesurée |
| Gouvernance (fondation, multi-vendeurs) | 15 | sans objet | éliminée | 4/5, 12 pts | éliminée | non mesurée |
| Maturité et adoption | 15 | sans objet | éliminée | 3/5, 9 pts | éliminée | non mesurée |
| Activité et maintenance | 10 | sans objet | éliminée | 5/5, 10 pts | éliminée | non mesurée |
| Sécurité (CVE, réactivité) | 10 | sans objet | éliminée | 3/5, 6 pts | éliminée | non mesurée |
| Empreinte sur PC (RAM, CPU, démarrage) | 10 | 4/5, 8 pts | éliminée | 5/5, 10 pts | éliminée | non mesurée |
| Portabilité multi-cloud | 10 | sans objet | éliminée | 4/5, 8 pts | éliminée | non mesurée |
| Expérience dev et documentation | 10 | sans objet | éliminée | 4/5, 8 pts | éliminée | non mesurée |
| Coût (managé ou opérationnel) | 5 | sans objet | éliminée | 5/5, 5 pts | éliminée | non mesurée |
| Total | 100 | pas de total, empreinte seule | éliminée | 83 / 100 | éliminée | non mesurée |

## 7. Verdict proposé

[OPS] Proposition : O2 avec zot 2.1.23, 83 sur 100. C'est le seul mécanisme
qui passe T2, donc la condition 7 de l'ADR-004 : trois recréations hors
réseau sur trois, prêtes en 34,7 s de médiane, avec un registre démarré à
froid sans amont. O1 ne recrée rien ; O3 et Distribution échouent.

[OPS] Pourquoi : T2 (M1, M3), une empreinte sous tous les seuils (5.6), et le
seul mécanisme qui tient `imagePullPolicy: Always` hors réseau (M4). Ses
points perdus viennent de l'adoption, un seul adoptant cité, et du rythme de
ses avis de sécurité.

[OPS] O1 en complément, si la lecture de US-005 le permet (point 4 de
l'ADR-006, pour [PO] puis Lucas). Garder le cluster relance en 12,8 s au lieu
de 34,7 s, mais tient 664,5 Mio entre deux sessions et ne couvre pas la
recréation. Les deux ensemble tiendraient 715,7 Mio (664,5 plus 51,2),
au-dessus du seuil de M8 : 4 sur 5 en empreinte pour l'ensemble.

[OPS] Sensibilité : le verdict repose sur T2 plus que sur la grille. Notée
pour information, Distribution obtiendrait de 84 à 87 points, devant zot,
selon deux notes de jugement : maturité à 4 ou 5 (Docker Hub, GitHub et
GitLab dans la liste d'adoptants que tient le projet [S25]), expérience dev à
3 à cause de l'arrêt au démarrage. Un Distribution capable de démarrer sans
amont, par un correctif du projet ou par un registre simple lancé sur le même
stockage quand le réseau manque, rouvrirait donc la question. Aucune note de
zot n'est à moins de 10 % d'un seuil.

[OPS] Réserves : le rythme des avis de zot ; la couverture des registres
autres que docker.io, non mesurée ; le comportement sur Linux amd64 et sur un
moteur à magasin containerd. Prochaine vérification : à la prochaine release
de zot, au plus tard le 2027-02-20.

[OPS] Suites : l'ADR-011, écrit par [ARCHI], qui fixe le cycle de vie du
registre (démarré par `task up`, gardé entre deux sessions, retiré par une
commande documentée) et les registres couverts ; une entrée de `catalog/`
pour le miroir local, avec licence, gouvernance, statut, date et source
(principe IV) ; un test de la matrice pour la condition 7, dont ce script
donne la forme ; la mise à jour de R-25 et un risque R-34 sur le miroir,
proposés au DSI.

## 8. Limites et biais

| Limite | Effet possible sur le verdict | Ce qui la lèverait |
| --- | --- | --- |
| Une seule machine : arm64, OrbStack, magasin d'images classique | Temps et mémoire propres à ce poste ; O3 et O4 se comporteraient autrement avec un magasin containerd | Relancer le script sur Linux amd64, et sur un moteur à magasin containerd |
| Hors réseau simulé dans le nœud seulement : le poste garde son réseau | La construction de l'API et du front n'est pas testée hors réseau. Le BuildKit du moteur prend l'image locale en mode par défaut [S10], mais une résolution de manifest au registre n'émet aucun événement `pull` : M3 ne la verrait pas | Rejouer T1 et T2 avec le poste réellement coupé du réseau, par Lucas |
| Distribution jugé sur un démarrage à froid | Un miroir Distribution resté en marche quand le réseau tombe servirait peut-être son cache : ce cas n'est pas testé, et le journal du conteneur arrêté n'a pas été relevé | Rejouer avec un conteneur gardé et une vraie coupure, une confirmation de `docker run` de plus |
| Seul docker.io passe par le miroir | La plate-forme de base, Flux (ghcr.io) et le tableau de bord d'Aspire (mcr.microsoft.com) tirent ailleurs : leur passage par zot n'est pas mesuré | Déclarer un miroir par registre dans `hosts.toml` et rejouer avec la plate-forme de base et l'outil GitOps |
| O4 non mesuré | Sur un moteur à magasin containerd, `docker save` pourrait garder l'index, et O3 marcher : non vérifié | Essai sur un poste où ce magasin est actif (Docker Engine 29 installé à neuf, Docker Desktop) |
| Variante d'O1 avec le nœud arrêté entre deux sessions non mesurée | Elle libérerait la mémoire de M8 | Essai par Lucas : `docker stop` puis `docker start` du nœud, interdits aux agents |
| Disque d'un cluster gardé mal mesuré | `docker system df` donne 2,157 Go avant et après trois lancements, valeur peut-être non rafraîchie. Le statut du nœud montre pourtant qu'il accumule une image de l'API et une du front à chaque `task up` (quatre de chaque après quatre lancements) | Mesurer dans le nœud (`crictl`, donc `docker exec`), par Lucas |
| Mémoire lue par `docker stats` sous OrbStack, base dispersée (92,0 Mio d'écart) | M7 d'O1 (+69,0 Mio) tient dans la dispersion de la base | Plus d'exécutions de base |
| Pendant O2, le registre de l'autre candidat tournait à vide | Charge parasite faible sur M1 et M7 | Un registre à la fois, au prix de deux confirmations de plus |

## 9. Sources

[OPS] Les dates de release, les comptes d'activité, les avis de sécurité, les
fichiers des dépôts et l'état « archivé » viennent de l'API publique de
GitHub, lue par `gh api` le 2026-11-20. Un auteur est compté humain quand
GitHub le déclare `User` et non `Bot`.

| ID | URL | Lue le | Ce que la source établit | Officielle |
| --- | --- | --- | --- | --- |
| S1 | <https://kind.sigs.k8s.io/docs/user/quick-start/> | 2026-11-20 | `kind load docker-image` et `kind load image-archive` ; politique `IfNotPresent` par défaut sauf `:latest` | Oui |
| S2 | <https://kind.sigs.k8s.io/docs/user/local-registry/> | 2026-11-20 | Recette du registre local : `config_path`, `docker network connect kind`, `hosts.toml` | Oui |
| S3 | <https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/cluster/nodeutils/util.go> | 2026-11-20 | `LoadImageArchive` : `ctr --namespace=k8s.io images import --all-platforms --digests` | Oui |
| S4 | <https://github.com/containerd/containerd/blob/v2.3.4/docs/hosts.md> | 2026-11-20 | `server` sert de repli une fois tous les hôtes essayés ; `_default` ; mise à jour sans redémarrage de containerd | Oui |
| S5 | <https://docs.docker.com/engine/storage/containerd/> | 2026-11-20 | Magasin containerd par défaut sur les installations neuves de Docker Engine 29.0 et plus ; une mise à jour garde overlay2 ; le magasin classique ne gère pas les index d'images | Oui |
| S6 | <https://docs.docker.com/desktop/features/containerd/> | 2026-11-20 | Docker Desktop : magasin containerd activé par défaut ; le magasin classique ne gère ni index ni listes de manifests | Oui |
| S7 | <https://docs.docker.com/reference/cli/docker/image/save/> | 2026-11-20 | `docker save` enregistre par défaut les variantes de plate-forme présentes dans le magasin du démon | Oui |
| S8 | <https://kubernetes.io/docs/concepts/containers/images/> | 2026-11-20 | `imagePullPolicy: Always` : le runtime contacte le registre et résout le condensat à chaque lancement | Oui |
| S9 | <https://github.com/moby/moby/releases/tag/docker-v29.8.2> | 2026-11-20 | Tag de Docker Engine 29.8.2, commit `8af9fe3` | Oui |
| S10 | <https://github.com/moby/moby/blob/docker-v29.8.2/daemon/internal/builder-next/adapters/containerimage/pull.go> | 2026-11-20 | BuildKit du moteur, magasin classique : mode par défaut « prefer local », repli au registre si l'image locale manque (lignes 236 à 253) | Oui |
| S11 | <https://github.com/distribution/distribution/releases> | 2026-11-20 | 3.1.2 le 2026-09-24, dernière release ; trois releases en 12 mois | Oui |
| S12 | <https://raw.githubusercontent.com/distribution/distribution/v3.1.2/LICENSE> | 2026-11-20 | Licence Apache 2.0 | Oui |
| S13 | <https://www.cncf.io/projects/distribution/> | 2026-11-20 | Projet Sandbox de la CNCF depuis le 2021-01-26 | Oui |
| S14 | <https://distribution.github.io/distribution/about/configuration/> | 2026-11-20 | Section `proxy` : `remoteurl`, `ttl` de 168 h par défaut, 0 désactive l'expiration | Oui |
| S15 | <https://github.com/project-zot/zot/releases> | 2026-11-20 | 2.1.23 le 2026-11-02, dernière release ; treize releases en 12 mois | Oui |
| S16 | <https://raw.githubusercontent.com/project-zot/zot/v2.1.23/LICENSE> | 2026-11-20 | Licence Apache 2.0 | Oui |
| S17 | <https://www.cncf.io/projects/zot/> | 2026-11-20 | Projet Sandbox de la CNCF depuis le 2022-12-13 | Oui |
| S18 | <https://zotregistry.dev/v2.1.23/articles/mirroring/> | 2026-11-20 | Synchronisation à la demande ; depuis 2.1.22, médias et condensats d'amont gardés, `preserveDigest` ignoré ; `http.compat: ["docker2s2"]` pour accepter le schéma 2 de Docker | Oui |
| S19 | <https://github.com/distribution/distribution/blob/v3.1.2/MAINTAINERS> | 2026-11-20 | Douze mainteneurs, adresses chez GitHub, Mirantis, GitLab, VMware, Docker, Microsoft et personnelles | Oui |
| S20 | <https://opensource.org/license/apache-2-0> | 2026-11-20 | Apache-2.0 approuvée par l'OSI | Oui |
| S21 | <https://api.github.com/repos/distribution/distribution>, <https://api.github.com/repos/project-zot/zot> | 2026-11-20 | Dépôts non archivés ; depuis le 2025-11-20, 369 commits et 49 auteurs humains pour Distribution, 482 commits et 65 auteurs humains pour zot ; aucun fichier d'adoptants dans le dépôt zot à 2.1.23 | Oui |
| S22 | <https://github.com/project-zot/zot/blob/v2.1.23/MAINTAINERS.md> | 2026-11-20 | Cinq mainteneurs : Microsoft, Ciroos AI, Geico, Luxoft, AMD | Oui |
| S23 | <https://github.com/distribution/distribution/security/advisories> | 2026-11-20 | Quatre avis en 12 mois (2 élevés, 2 moyens), tous corrigés au plus tard en 3.1.2, dont GHSA-3p65-76g6-3w7r sur le cache pull-through, corrigé en 3.1.0 | Oui |
| S24 | <https://github.com/project-zot/zot/security/advisories> | 2026-11-20 | 21 avis en 12 mois (1 critique, 11 élevés, 9 moyens), tous corrigés au plus tard en 2.1.22, dont GHSA-c45h-jrgv-35rc sur la synchronisation à la demande non authentifiée, corrigé en 2.1.21 | Oui |
| S25 | <https://github.com/distribution/distribution/blob/v3.1.2/ADOPTERS.md> | 2026-11-20 | Adoptants : Docker Hub, GitLab Container Registry, GitHub Container Registry, Harbor, DigitalOcean ; liste tenue par le projet | Oui |
| S26 | <https://github.com/distribution/distribution/blob/main/SECURITY.md>, <https://github.com/project-zot/zot/blob/main/SECURITY.md> | 2026-11-20 | Politique de signalement publiée par chaque projet | Oui |
| S27 | <https://github.com/distribution/distribution/blob/v3.1.2/registry/proxy/proxyauth.go>, <https://github.com/distribution/distribution/blob/v3.1.2/registry/handlers/app.go> | 2026-11-20 | En mode proxy, le démarrage appelle `getAuthURLs`, qui fait `http.Get(remoteURL + "/v2/")` ; l'erreur remonte jusqu'à un `panic` (`app.go`, lignes 359 à 364) | Oui |
| S28 | <https://zotregistry.dev/v2.1.23/> | 2026-11-20 | Section « Adopters » : Cisco seul, aussi sponsor | Oui |

## 10. Relectures

| Relecteur | Porte sur | Date | Avis |
| --- | --- | --- | --- |
| [SECU] | Licences, critères éliminatoires, sécurité | à venir | à venir |
| [FINOPS] | Coût | à venir | à venir |

[OPS] Points soumis à [SECU] : les deux registres tournent en root dans leur
image (`User` vide pour Distribution, `0` pour zot) ; zot écoute sur toutes
les adresses de son conteneur, sans port publié sur le poste ; le rythme des
avis de zot (5.5) ; un miroir local ne redistribue rien (R-25).

[OPS] Points soumis à [FINOPS] : aucun coût cloud, le mécanisme ne tourne
que sur le PC. Coût d'exploitation : la mémoire de M7 et M8, et le volume de
M6 au premier `task up`.
