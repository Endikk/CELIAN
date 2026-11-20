# ADR-011. Le cluster local tire ses images par un miroir zot que lance `task up`, dans tous les profils, sous conditions

| Champ | Valeur |
| --- | --- |
| Statut | proposé |
| Date | 2026-11-21 |
| Auteur | [ARCHI] |
| Décideur | Lucas, en attente ; arbitrage du DSI du 2026-11-20 sur BENCH-010 |
| BENCH lié | [BENCH-010](../benchmarks/BENCH-010-demarrage-hors-reseau.md) |
| Remplace | aucun |

## Contexte et problème

Chaque `task up` crée un nœud kind neuf, dont le containerd ne voit pas le cache Docker du poste ([ADR-006](ADR-006-orchestration-locale.md), condition 4). Toute image que la stack ne construit pas repasse donc par son registre public à chaque création : Postgres et Valkey, soit 139,1 Mo en amd64 par lancement, les deux images d'Envoy Gateway, puis celles de Flux dans le profil standard. Le 2026-11-19, ces tirages sont restés bloqués 15 minutes et une série entière a échoué. Docker Hub limite les tirages anonymes à 100 par adresse IPv4 sur 6 heures (R-25).

Trois décisions acceptées attendent une réponse. La condition 7 de l'[ADR-004](ADR-004-cluster-local.md) veut qu'un test de la matrice recrée le cluster hors réseau, et ce critère hors grille a fait pencher le choix de kind. La condition 4 de l'[ADR-005](ADR-005-gateway.md) et celle de l'ADR-006 demandent de traiter R-25 avant le golden repo, sans revenir aux tags ni à `imagePullPolicy: Never`. La spec du golden repo attend la solution : son récit P3 (« Redémarrer sans réseau après un premier lancement ») et FR-016 renvoient à BENCH-010, et FR-008 refuse toute référence par tag.

Les autres exigences viennent du PRD. US-005 veut une commande documentée qui « arrête et supprime l'environnement », et des profils lite et standard ; le profil standard sert de mesure au critère des 15 minutes. ENF-01 fixe ce critère au débit visé que [FINOPS] écrira après le golden repo. ENF-03 demande des dépendances figées. Côté constitution, les principes I à IX ; le X est sans objet, rien ne touche au cloud. Côté risques, R-04, R-20, R-25, R-26, R-30 et R-34, ouvert à la suite de BENCH-010.

BENCH-010 a jugé chaque mécanisme par deux tests éliminatoires, avant toute note. T1 relance `task up` hors réseau, cluster gardé. T2 le relance après suppression du cluster : c'est le test de la condition 7 de l'ADR-004. L'absence de réseau y est simulée dans le nœud seulement. Chaque registre public pointe vers un point mort, alors que le poste garde son réseau, et `docker build` avec lui (BENCH-010, sections 4.3 et 8).

Le DSI a arbitré le 2026-11-20, après les relectures de [SECU] et de [FINOPS] (BENCH-010, section 7). Cet ADR écrit cette décision et ses conditions. Il tranche aussi ce que le rapport laissait à [ARCHI] : où tourne le miroir et qui le lance, ce que fait `task down`, quels registres passent par le miroir, la commande qui garde le cluster et la place du miroir au catalogue.

## Options considérées

| Option | Score BENCH (sur 100) | Verdict | Raison principale |
| --- | --- | --- | --- |
| O2, miroir zot 2.1.23 | 83 | retenue | Seul mécanisme qui passe T2 : trois recréations hors réseau sur trois, prêtes en 34,7 s de médiane, avec un miroir démarré à froid sans amont. Empreinte sous tous les seuils, et seul mécanisme qui tient `imagePullPolicy: Always` hors réseau |
| O1, garder le cluster | pas de total, empreinte seule (4/5) | écartée comme comportement par défaut, gardée en commande explicite | Passe T1 en 12,8 s, mais ne recrée rien, et tient au moins 664,5 Mio entre deux sessions |
| O2, miroir Distribution 3.1.2 | éliminée, non notée | éliminée | T2 : en mode proxy, le démarrage interroge l'amont et lève un `panic` s'il ne répond pas. Le miroir ne redémarre pas sur un poste sans réseau |
| O3, archives `docker save` chargées par `kind load image-archive` | éliminée, non notée | éliminée | T2 échoue trois fois sur trois : containerd range l'image sous le condensat de l'archive, et le kubelet repart au registre |
| O4, magasin containerd du moteur | non mesurée | documentée | L'essai ne touche pas au moteur du poste |

Aucune option ne touche les critères éliminatoires du brief (BENCH-010, section 3).

Sensibilité, reprise du rapport. Le verdict repose sur T2 plus que sur la grille. Avec la gouvernance de zot à 3, que [SECU] juge défendable puisque deux mainteneurs seulement sur cinq sont actifs, zot fait 80 sans que rien ne change. Distribution obtiendrait de 84 à 87 s'il démarrait sans amont, et ce cas rouvre la décision (« Condition de révision »). Aucune note de zot n'est à moins de 10 % d'un seuil.

Grille, mesures et sources : [BENCH-010](../benchmarks/BENCH-010-demarrage-hors-reseau.md).

## Décision

Sur la cible `local`, le cluster kind tire ses images par un miroir zot 2.1.23, dans tous les profils, lite compris. Le miroir tourne hors du cluster, dans un conteneur du moteur relié au réseau `kind`, et `task up` le lance par la CLI `docker`. Il synchronise à la demande les images que le nœud réclame, les garde sur un stockage qui survit au cluster, et les sert ensuite sans amont. `task down` supprime le cluster. Garder le cluster entre deux sessions devient une commande explicite et documentée, jamais le comportement par défaut.

Le miroir sert dans tous les profils, sur l'avis de [FINOPS]. Ses 77,68 Mo en amd64 au premier `task up` sont regagnés dès le deuxième, puisque sans lui chaque création retélécharge Postgres et Valkey, 139,1 Mo en amd64. Sa mémoire ne fait pas changer le profil lite de palier. En option, les retéléchargements resteraient le cas par défaut, et l'option devrait être activée avant le premier `task up` pour remplir le cache.

O1 n'est pas le défaut, parce qu'il immobilise au moins 664,5 Mio, soit 8,1 % d'un portable de 8 Gio, pour gagner 21,9 s par relance. Ce gain tombe hors du critère des 15 minutes, qui compte le premier `task up`, où O1 ne change rien : 35,4 s contre 36,8 s pour la base. Et O1 ne couvre pas la recréation, donc pas la condition 7 de l'ADR-004.

La validation revient à Lucas. Six points demandent son avis : les questions ouvertes 1 à 6.

### Où tourne le miroir, et qui le lance

Hors du cluster, parce qu'il doit survivre à sa suppression : un pod disparaîtrait avec le nœud, et T2 échouerait. Le miroir est un conteneur du moteur du poste, voisin du nœud sur le réseau `kind`, selon la recette de registre local de kind (BENCH-010, S2).

`task up` le lance par `docker run`, comme il lance déjà `docker build` et `kind load` (ADR-006). Aucun outil de boucle n'entre, ni Docker Compose, que l'ADR-006 a éliminé pour la stack et dont un seul conteneur n'a pas besoin. La politique de redémarrage reste à sa valeur par défaut, `no` : après un redémarrage du poste, le miroir ne revient pas seul, et c'est `task up` qui le relance.

Le stockage est un volume nommé du moteur, propre au projet, et jamais un dossier de l'arborescence du projet. Dans le projet, il tomberait dans le contexte de `docker build`, et un `COPY` large embarquerait des couches tierces dans une image du projet, ce que R-25 refuse de publier ; il serait aussi à un `.gitignore` près d'entrer dans Git. Un volume survit au conteneur qui l'utilise, et se retire à part, par `docker volume rm` (page des volumes de Docker).

Le containerd du nœud trouve le miroir par la configuration de l'essai (`tests/bench/bench-010/kind.yaml`) : un `containerdConfigPatches` qui pose `config_path`, et un `extraMounts` en lecture seule d'un dossier `certs.d` versionné dans la couche `local`. containerd relit les `hosts.toml` à chaque tirage, sans redémarrer (BENCH-010, S4) : changer la liste des registres servis ne demande pas de recréer le cluster. Pour chaque registre servi, `server` reste l'amont public, que containerd n'essaie qu'après les hôtes déclarés (page `hosts.md` de containerd), et un seul hôte est déclaré, le miroir, avec la capacité `pull` (condition 1). Le nœud joint le miroir en HTTP, par son nom sur le réseau `kind`, comme dans l'essai. L'intégrité tient au condensat, que containerd vérifie sur tout ce qu'il reçoit (BENCH-010, S34).

### Ce que font `task up`, `task down` et les deux commandes du miroir

Seul `task up` a un nom fixé. Les autres noms sont provisoires, comme ceux de l'ADR-006 : le PRD les renvoie à la phase 5.

`task up` reprend l'ordre de l'ADR-006 et y ajoute une étape, après la création du cluster :

1. vérifier les prérequis, dont la version de Docker Engine sur Linux (condition 3) ;
2. créer le cluster kind, ou réutiliser celui que `task app:down` a gardé ;
3. lancer le miroir : retirer un conteneur du miroir laissé par une session précédente, après contrôle (condition 11), puis `docker run -d` avec un nom et une étiquette fixes, `--network kind`, sans `-p`, l'image par condensat, la configuration du projet montée en lecture seule et le volume du projet ; attendre que le miroir réponde, et s'arrêter avec un message s'il ne répond pas ;
4. puis la suite de l'ADR-006 : plate-forme de base, construction et chargement de l'API et du front, Secrets, `kubectl apply -k`, attente des réponses par la gateway ;
5. afficher la taille du volume du miroir, à côté des durées de FR-015.

Le miroir peut démarrer après le cluster, parce que la création du cluster ne tire rien d'un registre : les images système de kind sont dans l'image de nœud (BENCH-010, section 4.4, O3). Le conteneur est recréé à chaque `task up`. Une mise à jour du blueprint qui change l'image ou la configuration de zot s'applique donc sans détection de dérive. Et ce démarrage à froid est celui que T2 a mesuré : la phase hors réseau de l'essai a lancé un conteneur neuf sur le stockage rempli en ligne. Le temps de démarrage du miroir, lui, n'a pas été mesuré.

`task down` retire le conteneur du miroir, après le même contrôle, puis supprime le cluster par `kind delete cluster`. L'ordre fait que rien ne reste relié au réseau `kind` quand le cluster disparaît ; ce que kind fait de ce réseau à la suppression n'a pas été lu. Le volume du miroir reste. La commande dit ensuite ce qui reste sur le poste, comme le demande le scénario 4 du récit 1 de la spec : le volume du miroir et sa taille, les images du cache du moteur (image de nœud, image de zot, images de base des builds), et la commande qui retire le miroir. Entre deux sessions, rien ne tourne. M8 mesurait 51,2 Mio pour un miroir gardé en marche ; ce choix les rend, et ne laisse aucun serveur sans authentification en marche quand le projet ne sert pas (R-34).

`task mirror:purge` supprime le volume du miroir. C'est la commande documentée qui retire le miroir du poste, et le mécanisme par défaut de la purge (condition 5). Le `task up` suivant remplit le volume de nouveau, réseau requis, et la commande le dit avant d'agir. L'image de zot reste dans le cache du moteur, comme l'image de nœud de kind.

`task app:down` est la commande explicite qui garde le cluster, l'option O1. Elle retire le miroir comme `task down`, puis supprime le ou les namespaces de l'application avec ce qu'ils contiennent, comme dans l'essai d'O1 ; le `task up` suivant recrée les Secrets absents (condition 1 de l'ADR-007). Elle garde le nœud en marche, la plate-forme de base, et Flux dans le profil standard. Dans ce profil, elle suspend d'abord la `Kustomization` de l'environnement `local` : sinon Flux recrée l'application à sa réconciliation suivante (ADR-010, question 3). Le `task up` suivant réutilise le cluster et ne tire aucune image, d'après T1, mesuré sans miroir. Son coût entre deux sessions vaut au moins 664,5 Mio, mesurés sur la stack d'essai sans gateway ni Flux. Le vrai chiffre des profils lite et standard n'est pas mesuré : BENCH-004 donne 948,8 Mio au repos pour kind et Envoy Gateway, BENCH-009 265,2 Mio pour la couche de Flux, des séries différentes qui ne s'additionnent pas telles quelles. S'y ajoutent 2,157 Go de volume du nœud, mesure douteuse, et une image de l'API et du front de plus à chaque `task up`, que rien ne retire (BENCH-010, section 8). Ce que deviennent les données de Postgres suit BENCH-011.

### Registres servis par le miroir

Règle : passe par le miroir tout registre d'où le containerd du nœud tire une image, dans un profil livré. Les images que tire le moteur du poste n'y passent pas, parce que le moteur ne passe pas par le containerd du nœud. Leur présence hors réseau tient au cache du moteur.

| Registre | Images | Tirées par | Profil | Passage par le miroir |
| --- | --- | --- | --- | --- |
| docker.io | Postgres 18.7 et Valkey 9.1.4 de l'essai (`tests/bench/bench-005-orchestration.sh`, lignes 107 et 108) | containerd du nœud | lite et standard | mesuré : servies par zot, T2 trois fois sur trois |
| docker.io | Contrôleur et proxy d'Envoy Gateway (ADR-005) | containerd du nœud | lite et standard | non mesuré |
| ghcr.io | Flux : `source-controller`, `kustomize-controller`, `helm-controller`, `notification-controller` (`tests/bench/bench-009-gitops.sh`, lignes 87 à 93) | containerd du nœud | standard | non mesuré |
| docker.io | Postgres local sans opérateur, `postgres:18.7-trixie` (BENCH-011, option retenue par Lucas le 2026-11-21 ; rapport à fusionner) | containerd du nœud | lite et standard | non mesuré pour cette image ; la variante Alpine de l'essai est servie par zot |
| à relever | Keycloak (BENCH-012), Mailpit (BENCH-013) | containerd du nœud | standard | non mesuré, registres non relevés |
| docker.io | Image de nœud `kindest/node` (ADR-004) | moteur du poste | tous | hors miroir |
| ghcr.io | Image de zot | moteur du poste | tous | hors miroir |
| mcr.microsoft.com | Images de base de l'API .NET (BENCH-005, S41) | BuildKit du moteur | tous | hors miroir ; construction hors réseau non testée |

Avec ce que l'on sait aujourd'hui, le profil lite ne tire que de docker.io, Postgres retenu compris : une seule entrée de synchronisation, comme dans l'essai. Le profil standard en demande au moins deux, docker.io et ghcr.io.

Pour plusieurs amonts, le mécanisme n'est pas établi. L'essai n'a servi qu'un amont, par une seule entrée de `sync` (`tests/bench/bench-010/zot/config-online.json`). La page de zot décrit plusieurs entrées et un filtre `content` (`prefix`, `destination`, `stripPrefix`), sans dire comment la synchronisation à la demande choisit l'amont d'un dépôt quand plusieurs entrées existent. containerd accepte un hôte dont le chemin porte la racine de l'API (`override_path`), et ajoute le registre d'origine en paramètre `ns` à chaque requête vers un miroir (`hosts.md`). Deux montages candidats, à essayer par [OPS] dans cet ordre :

- a. un seul zot, une entrée de `sync` par amont, chacune rangée sous un préfixe (`destination`) que reprend l'hôte du `hosts.toml` du registre, par `override_path` : un conteneur, un volume, un cycle de vie ;
- b. un zot par amont, chacun dans la configuration mesurée : environ 51 Mio de plus au repos par instance, extrapolés de M7 sans mesure, et un volume par instance.

Le premier montage qui passe T2 avec la seule capacité `pull`, plate-forme de base et Flux compris, est retenu. Si c'est le montage b, [FINOPS] relit le palier du profil standard.

### Conditions

Les conditions 1 à 9 reprennent les réserves des relectures de [SECU] et de [FINOPS], retenues par le DSI (BENCH-010, sections 7 et 10 ; R-34). Les conditions 10 à 13 sont des ajouts de [ARCHI]. La décision ne vaut qu'avec elles. Chaque contrôle cité entre dans la matrice de validation (principe I).

1. Capacité `pull` seule. Chaque `hosts.toml` déclare le miroir avec `capabilities = ["pull"]`, jamais `resolve` ni `push`. Dans containerd 2.3.4, une référence par condensat ne demande à l'hôte que `pull`, et `resolve` ne s'ajoute que pour un tag (BENCH-010, S34) ; la documentation écrit « A public mirror should never be trusted to do a resolve action ». L'essai donnait au miroir `pull` et `resolve` (`tests/bench/bench-010-offline.sh`, ligne 298) : T2 avec `pull` seul n'a pas tourné. Contrôles : le test de la condition 7 de l'ADR-004 joue T2 dans cette configuration, avec un pod en `imagePullPolicy: Always` comme M4 ; un contrôle statique refuse un `hosts.toml` qui donne au miroir une autre capacité. Si T2 échoue dans cette configuration, cet ADR se rouvre.
2. Réseau `kind` seul, sans port publié. Le miroir démarre par `--network kind`, sans `-p`. L'essai le reliait à `bridge` puis à `kind` (M9), et sur le réseau `bridge` par défaut, tout conteneur de ce réseau le joint par son adresse IP (BENCH-010, S38). Contrôles : après `task up`, le miroir n'est relié qu'au réseau `kind` et ne publie aucun port ; le test des ports de la condition 1 de l'ADR-004 s'applique ; un pod relève ce que le cluster joint du miroir, point que [SECU] n'a pas vérifié (R-34).
3. Docker Engine 28.0.0 au minimum sur Linux. Cette version, du 2025-02-19, bloque l'accès routé aux ports non publiés depuis le réseau local ; ils restent joignables depuis le poste par l'adresse du conteneur (BENCH-010, S31). `task up` lit la version du moteur et refuse de démarrer en dessous, comme il le fait pour kind (condition 2 de l'ADR-004). Le README et la liste de prérequis de US-001 la portent. Sur macOS, le moteur tourne dans une machine virtuelle, et ce qu'un processus du poste joint d'un port non publié n'a pas été relevé : le test de la condition 2 le relève.
4. Aucune référence par tag. Le miroir ne garantit l'intégrité que des références par condensat (R-34). Les images de l'API et du front, construites sur le poste, portent un nom sous un hôte qui ne résout vers aucun registre public. Sans hôte, Kubernetes suppose Docker Hub (BENCH-010, S8) : une image locale absente du nœud serait demandée au miroir puis à Docker Hub, dans un espace de noms qui n'appartient pas au projet. Proposition de [ARCHI] : un nom sous le domaine `.invalid`, réservé aux noms « sure to be invalid » (RFC 2606, citée par l'ADR-009), par exemple `<projet>.invalid/api`. Que `kind load docker-image` et le kubelet acceptent ce nom n'a pas été essayé ([OPS]). Le contrôle de FR-008 n'exempte que les images sous cet hôte, construites par `task up` (condition 7 de l'ADR-006). Il porte sur les manifests rendus et sur les images des pods en marche après `task up`, parce qu'un contrôleur lance des images qu'aucun manifest du projet ne nomme : le proxy qu'Envoy Gateway crée vient d'une valeur compilée dans son binaire, désignée par condensat (BENCH-004, S11).
5. Règle de purge du stockage, fixée avant la mise en template. Sa croissance à chaque version tirée n'est ni mesurée ni bornée ([FINOPS]). Règle proposée par [ARCHI] : le stockage ne garde que ce que la version courante du projet référence. Deux mécanismes, que [OPS] et [SECU] départagent :
   - a. par défaut, `task mirror:purge`, qui vide le volume. Rien ne s'ajoute à la configuration mesurée, où le ramasse-miettes est coupé (`"gc": false`). La procédure de mise à jour du projet (US-011) purge avant le `task up` en ligne qui remplit de nouveau le miroir ;
   - b. en option, la rétention de zot (`storage.retention`) : `deleteUntagged` avec `keepUntagged` sur une règle d'activité comme `pulledWithin`, que la page présente pour les entrées d'un cache tirées par condensat seul. Elle s'essaie d'abord en `dryRun`. La page la montre avec le ramasse-miettes activé, et prévient que celui-ci tourne même pendant la vérification ; or cette fonction figure parmi celles que visent les avis de zot ([SECU], BENCH-010, section 10). Elle passe donc par une relecture [SECU] avant d'être activée.

   `task up` affiche la taille du volume. [FINOPS] fixe un seuil d'avertissement sur la première mesure du golden repo ; son estimation pour le profil standard, hors Keycloak et Mailpit, vaut 518,2 Mo en amd64 (Envoy Gateway 121,0, Flux 258,1, Postgres et Valkey 139,1), une estimation qu'aucune mesure ne confirme encore. Contrôle : après une purge et un `task up` en ligne, T2 passe, et le volume ne contient que les condensats du projet.
6. UID non root, sans capacités ni élévation de privilèges, à essayer. L'image de release tourne en root, sur une base distroless `latest` sans directive d'utilisateur, alors que distroless publie une variante `nonroot` (BENCH-010, S35 et S36). Options candidates de `docker run` : `--user` avec un UID non root, `--cap-drop`, `--security-opt no-new-privileges=true`, `--read-only`. Un volume nommé neuf reçoit le contenu du dossier qu'il recouvre, mais la page des volumes ne dit rien des propriétaires : que zot écrive dans son volume sous un UID non root reste à essayer ([OPS]). Si l'essai échoue, [SECU] dit si l'exécution en root reste acceptable ; sa gravité est jugée faible, le nœud kind tournant déjà en `--privileged` (BENCH-010, S30).
7. Configuration du projet toujours montée, extension `sync` seule. La configuration par défaut de l'image active la recherche, l'interface et la gestion (BENCH-010, S35). Le projet monte toujours la sienne, en lecture seule, sur le modèle de `tests/bench/bench-010/zot/config-online.json` : `sync` en `onDemand` avec `tlsVerify`, `http.compat: ["docker2s2"]` (BENCH-010, S18), aucune autre extension. Contrôle statique : la configuration ne déclare que `sync`, et `task up` refuse de démarrer le miroir sans elle.
8. Image figée par condensat, suivie et scannée. Aujourd'hui `ghcr.io/project-zot/zot:v2.1.23@sha256:9d3de83ac2099e6f4843045b4c9b65b7e8baf40f92d28f54906dee9d4d390fd7` (`tests/bench/bench-010-offline.sh`, ligne 148), ce qui remplit aussi la condition 3 de l'ADR-004 pour un registre local. Renovate la suit, avec le délai de 7 jours et l'exception de sécurité du principe VI ; le SBOM et le scan Trivy du projet généré l'incluent. Les images de release ne sont pas signées : le condensat est le seul ancrage d'intégrité ([SECU]). [SECU] lit chaque mois les avis du dépôt (R-34).
9. Stockage jamais versionné ni publié (R-25). Un miroir alimenté sur le poste, par et pour son utilisateur, ne transmet de copie à personne ([SECU]). Le volume reste hors de l'arborescence du projet ; aucun workflow du blueprint ne le publie, ni en artefact ni en image, et le projet ne le copie pas d'un poste à l'autre. Le cache d'images de la CI sort du poste : il passe par sa propre relecture [SECU] avant d'être activé. Contrôle : un test échoue si le stockage du miroir se trouve sous l'arborescence du projet.
10. Une seule liste de registres. Le blueprint tient la liste des registres servis en une seule valeur, dont dérivent les `hosts.toml` et la configuration de zot. Un contrôle extrait l'hôte de registre de chaque image, dans les manifests rendus et dans les pods en marche après `task up` de chaque profil livré, et échoue sur un hôte absent de la liste, l'hôte réservé de la condition 4 mis à part. T2 tourne pour chaque profil livré, plate-forme de base et Flux compris : c'est ce qui lève la limite « seul docker.io passe par le miroir » de BENCH-010 (section 8).
11. Cycle de vie contrôlé. `task up`, `task down` et `task app:down` ne retirent un conteneur qu'après contrôle de son nom, de son étiquette et de son image, comme `check_registry` dans le script de BENCH-010 : jamais un conteneur qui n'est pas celui du projet. Le Taskfile porte en tête l'inventaire des commandes qui créent, modifient ou suppriment un conteneur, un réseau ou un volume, et [SECU] le relit. C'est la règle que [SECU] a posée pour les scripts de benchmark (BENCH-010, section 10), étendue au projet généré : une règle de permission porte sur le texte d'une commande, pas sur ce qu'une tâche lance (BENCH-010, S29 ; R-30). Contrôles : après `task down`, aucun conteneur du miroir et le volume présent ; après `task mirror:purge`, plus de volume.
12. Moteur libre (R-26). L'évaluation de Podman de la condition 8 de l'ADR-004 couvre aussi le conteneur du miroir, ses options et son volume.
13. Aucun identifiant dans le miroir (principe IX). La configuration de zot ne porte aucune donnée d'identification. Les tirages authentifiés que R-25 garde en option ne passent pas par elle sans une nouvelle relecture [SECU] : l'identifiant y serait en clair sur le poste.

Les conditions des ADR-004 à ADR-007 et de l'ADR-010 restent en vigueur, en particulier la boucle locale, les images par condensat et la recréation hors ligne (conditions 1, 3 et 7 de l'ADR-004), et les images des moteurs GitOps par condensat (condition 6 de l'ADR-010).

### Portée

Le miroir n'est pas une brique que la spec déclare : il découle de la cible `local`, comme le cluster (ADR-004). La spec ne nomme pas zot, qui vit dans la couche `local` du blueprint et au catalogue (principe II). La cible `gcp` ne reçoit rien : GKE tire ses images lui-même.

Restent hors de cette décision :

- le cache d'images de la CI, qui demande sa propre relecture [SECU] ;
- la construction de l'API et du front sur un poste réellement coupé du réseau, que T2 n'a pas couverte (BENCH-010, section 8) ;
- les images que tire le moteur du poste, et le moteur lui-même (R-26) ;
- les registres de Keycloak, de Mailpit et de Postgres local, qui suivront BENCH-011 à BENCH-013 sous la condition 10 ;
- l'arrêt du nœud entre deux sessions au lieu de sa suppression, variante d'O1 non mesurée ;
- Windows (Q5).

## Conséquences

### Positives

- T2 passe trois fois sur trois, prêt en 34,7 s de médiane, avec un miroir démarré à froid sans amont, aucun tirage du moteur et aucune erreur d'amont. Une fois le test de la condition 1 passé, la condition 7 de l'ADR-004 et les conditions 4 de l'ADR-005 et de l'ADR-006 sont remplies pour les registres servis.
- Les retéléchargements à chaque création disparaissent après le premier `task up` : 139,1 Mo en amd64 pour Postgres et Valkey, et, d'après l'estimation de [FINOPS], environ 518,2 Mo en amd64 pour le profil standard si tous ses registres passent par le miroir.
- Docker Hub ne devrait plus voir qu'un tirage par image et par version, contre un GET de manifest par image à chaque création aujourd'hui (R-25). Ce gain n'est pas mesuré : zot peut revérifier un manifest auprès de l'amont une fois passé `manifestCheckInterval` (page de zot), et ce trafic en ligne n'a pas été relevé.
- `imagePullPolicy: Always` tient hors réseau, ce qu'aucun autre mécanisme ne fait (M4).
- Mémoire : +54,8 Mio au repos pendant une session, dont 50,9 Mio pour le conteneur du miroir, et rien entre deux sessions, puisque `task down` retire le miroir.
- Intégrité des références par condensat : containerd refuse tout contenu dont le condensat diffère (BENCH-010, S34). Aucun port publié sur le poste (M9).
- Aucune licence ni aucun service payant, rien sur GKE.

### Négatives

- R-04. Le miroir ajoute 77,68 Mo en amd64 au premier `task up`, et jusqu'à autant à chaque mise à jour de son image (treize releases en douze mois). Cumulé avec la plate-forme de base, qui en tire déjà 505,8, il porte le total à 583,5 Mo, 116,7 % des 500 Mo. Le premier `task up` du profil standard, hors Keycloak et Mailpit, passe de 1 395,9 à 1 473,6 Mo : 1 179 s à 10 Mbit/s, 131 % du budget, et un débit minimal de 13,1 Mbit/s au lieu de 12,4. Noté comme une couche, le miroir reste sous son seuil de 112,5 Mo ; le cumul entre dans R-04, décision du DSI. Une variante `zot-minimal` 2.1.23 existe sur ghcr.io, puisqu'elle sert de témoin dans l'essai (`tests/bench/bench-010/witness.yaml`, ligne 60) ; personne n'a vérifié qu'elle porte l'extension `sync`, ni mesuré sa taille.
- Profils de US-005, méthode de [FINOPS]. Le profil lite passe de 1 083,7 à 1 138,5 Mio de plancher et reste à 2,0 Gio de VM et 6,0 Gio de portable. La partie connue du profil standard passe de 1 348,9 à 1 403,7 Mio, et franchit ainsi le palier de 2,0 Gio : 2,5 Gio de VM et 6,5 Gio de portable. Le montage b, un zot par amont, y ajouterait une instance. Ces chiffres mêlent quatre séries et donnent des ordres de grandeur.
- Un serveur sans authentification sur le réseau `kind`, en root dans son conteneur tant que la condition 6 n'est pas tenue (R-34). Sans authentification, zot accepte toute requête, écritures et suppressions comprises (BENCH-010, S33). Sur Linux, même avec Docker Engine 28.0.0, tout processus du poste le joint par l'adresse du conteneur. Rien de confidentiel n'y est gardé : l'enjeu est la disponibilité du démarrage hors réseau, et l'intégrité de toute image désignée par tag, que la condition 4 interdit.
- Rythme des avis de zot : 21 en douze mois, dont un critique et 11 élevés, et 19 parus entre le 2026-08-06 et le 2026-10-23, tous corrigés au plus tard en 2.1.22. Deux dénis de service touchent la configuration retenue, corrigés avant 2.1.23 (GHSA-c45h-jrgv-35rc, GHSA-vm27-w3jg-7wg9). Images de release non signées.
- Gouvernance et adoption minces. zot est au premier niveau de la CNCF, Sandbox, et tient à deux mainteneurs actifs de deux entreprises, qui signent 283 des 445 commits humains de l'année. Sa documentation ne cite qu'un adoptant, Cisco, aussi sponsor (question 5).
- Disque : 382,2 Mo sur le poste de mesure en arm64, image décompressée et stockage, et un stockage qui grandit jusqu'à ce que la condition 5 s'applique.
- Le Taskfile porte plus de code : lancement, contrôle et retrait d'un conteneur, attente de sa réponse, version du moteur (R-30, condition 11).
- Le passage par le miroir des registres autres que docker.io n'est pas mesuré, et le mécanisme à plusieurs amonts n'est pas établi. Les mesures viennent d'un seul poste, arm64 sous OrbStack, moteur non libre (R-26), au magasin d'images classique ; Linux amd64 et le magasin containerd n'ont pas été mesurés.
- Le premier `task up` demande toujours le réseau, et `task mirror:purge` fait perdre le démarrage hors réseau jusqu'au `task up` en ligne suivant.

### Effet sur les cibles hors MVP

La porte reste ouverte. Le miroir ne vit que dans la couche `local` ; une cible AWS ou Azure tirerait ses images depuis son cluster managé, sans lui. Une cible on-prem serveurs aurait sa propre ligne au catalogue, choisie par son benchmark.

### Suites

- [OPS] : les montages a et b pour plusieurs amonts ; l'essai du UID non root (condition 6) ; les deux mécanismes de purge (condition 5) ; le nom sous `.invalid` avec `kind load` et le kubelet (condition 4) ; le temps de démarrage du miroir ; le retrait des anciennes images de l'API et du front dans un cluster gardé par `task app:down`. Les commandes s'écrivent en phase 3 dans le Taskfile du golden repo.
- [QA] et [OPS] : le test de la condition 7 de l'ADR-004 dans la matrice, en `pull` seul, pour chaque profil livré (conditions 1 et 10), sur le modèle de `tests/bench/bench-010-offline.sh`. Il tourne sur un runner Linux amd64, ce qui couvre aussi la condition 3 et une partie de la limite du poste unique.
- [SECU] et [QA] : les contrôles statiques des conditions 1, 4, 7, 9 et 10 ; le pod de la condition 2 ; la relecture de l'inventaire du Taskfile (condition 11) ; la lecture mensuelle des avis de zot ; la relecture de la rétention, si elle est retenue.
- [FINOPS] : le seuil d'avertissement du volume (condition 5) ; le palier du profil standard si le montage b est retenu ; le cumul de 583,5 Mo dans le débit visé.
- [BENCH] : relancer le script sur Linux amd64 et sur un moteur à magasin containerd, ce qui dira aussi si O4 tient ; vérifier si `zot-minimal` porte `sync`, et sa taille.
- Lucas : rejouer T1 et T2 avec le poste réellement coupé du réseau, construction comprise (BENCH-010, section 8).
- [PO] : avec la lecture de US-005 (question 1), la formulation de FR-016 et de SC-009 de la spec, qui attendaient BENCH-010.
- DSI : R-25 et R-34 renvoient à cet ADR ; l'attribut du catalogue entre dans la PR de schéma de la phase 3 (section « Entrée au catalogue »).

### Questions ouvertes

1. Lecture de US-005, question 4 de l'ADR-006, pour [PO] puis Lucas. Cet ADR lit « arrête et supprime l'environnement » au pied de la lettre : `task down` supprime le cluster. `task app:down` garde le cluster pour qui veut relancer plus vite, en connaissant son coût. Avis de [ARCHI] : retenir cette lecture ; elle tient avec le scénario 4 du récit 1 de la spec, puisque la commande supprime l'application et dit ce qui reste. Les noms se fixent en phase 5.
2. Cycle de vie du miroir, pour Lucas. Cet ADR retire le conteneur à chaque `task down` et garde son volume ; les suites de BENCH-010 le gardaient en marche entre deux sessions, pour 51,2 Mio. Avis de [ARCHI] : le retirer. Aucun serveur sans authentification ne tourne quand le projet ne sert pas, la mémoire est rendue, une mise à jour de zot s'applique sans détection de dérive, et le démarrage à froid sans amont est celui que T2 a mesuré. Le prix : le démarrage du miroir à chaque `task up`, non mesuré.
3. Place du miroir au catalogue, pour Lucas. Un attribut `companions` sur la cible `local` de `kubernetes-cluster`, ou une brique à part qui demanderait une ligne `gcp`. Avis de [ARCHI] : l'attribut (section « Entrée au catalogue »).
4. Mécanisme de purge, pour Lucas, [OPS] et [SECU]. Avis de [ARCHI] : la commande explicite par défaut, parce qu'elle n'active rien de nouveau dans zot ; la rétention seulement si elle passe en `dryRun` et la relecture [SECU] (condition 5).
5. Adoption au sens du principe VI, pour Lucas. Le principe veut une techno « déjà adoptée en production », et zot n'a qu'un adoptant déclaré, Cisco, qui est aussi son sponsor (BENCH-010, section 5.3). Avis de [ARCHI] : l'accepter, puisque c'est le seul mécanisme qui passe T2, et relire l'adoption à la prochaine vérification, au plus tard le 2027-02-20.
6. Un stockage par projet ou partagé entre les projets du poste, pour Lucas et [FINOPS]. Le partage éviterait de tirer deux fois la même image, au prix d'une purge qui toucherait tous les projets. Avis de [ARCHI] : un volume par projet pour le MVP.

## Conformité à la constitution

Vérifiée contre la [constitution](../../.specify/memory/constitution.md) en version 1.2.0.

| Principe | Effet | Justification |
| --- | --- | --- |
| I. Rien sans test automatique | respecté | La matrice joue T2 en `pull` seul pour chaque profil livré, et porte les contrôles des conditions 2, 4, 5, 7, 9, 10 et 11 |
| II. Spec abstraite, catalogue concret | respecté | La spec ne déclare pas le miroir ; zot vit dans la couche `local` et au catalogue, et `gcp` ne change pas |
| III. Managé sur le cloud, open source ailleurs | respecté | Sur `local`, zot est sous Apache-2.0 et gratuit ; rien n'est déployé sur `gcp` |
| IV. Catalogue traçable | respecté | L'attribut porte licence, gouvernance, statut, dates et sources, et s'écrit avant la mise en template ; d'ici là, aucun blueprint ne s'en sert, et le golden repo n'en est pas un |
| V. Gouvernance ouverte d'abord | respecté | Projet Sandbox de la CNCF, cinq mainteneurs de cinq organisations, dont deux actifs ; l'autre projet de fondation, Distribution, est éliminé par T2 |
| VI. Récent mais éprouvé | respecté, avec réserve | Aucun critère éliminatoire touché : Apache-2.0, dépôt non archivé, 2.1.23 du 2026-11-02, publiée depuis plus de 7 jours. L'adoption en production repose sur un seul adoptant déclaré (question 5) |
| VII. Une commande pour démarrer | respecté | `task up` lance le miroir lui-même ; Docker Engine 28.0.0 sur Linux entre dans les prérequis du README (condition 3) |
| VIII. Aucun fait de mémoire | respecté | Les faits renvoient à BENCH-010, à ses scripts et aux pages officielles lues le 2026-11-21. Sont signalés comme non vérifiés : le mécanisme à plusieurs amonts, T2 en `pull` seul, le UID non root, le nom sous `.invalid`, le temps de démarrage du miroir, ce que kind fait du réseau `kind`, la joignabilité sous macOS, le trafic de revérification vers l'amont et le contenu de `zot-minimal` |
| IX. Aucun secret dans le dépôt | respecté | La configuration de zot ne porte aucun identifiant (condition 13), et le stockage n'est jamais versionné (condition 9) |
| X. Aucune dépense cloud sans accord | sans objet | Tout tourne sur le poste |

### Dérogations

Aucune.

## Entrée au catalogue

Aucune brique nouvelle. Le miroir découle de la cible `local`, et la spec ne le déclare pas (principe II). Il doit pourtant porter au catalogue licence, gouvernance, statut, dates et sources (principe IV), et passer la règle de fraîcheur de l'[ADR-009](ADR-009-catalogue.md) : 12 mois sans release, six mois sans vérification.

Le format actuel ne le permet pas sans écart. Une brique exige une ligne `local` et une ligne `gcp` (ADR-009, ENF-02), et `gcp` n'a pas de miroir. Une brique `registry-mirror` obligerait à écrire sur `gcp` un service managé que personne n'a étudié, un cache de registre facturé, ou une ligne de façade.

Proposition de [ARCHI] : un attribut facultatif `companions` sur une cible `oss`, soit la liste des composants que la cible fait tourner avec son service. Chacun porte les champs d'une cible `oss` (`service`, `version`, `license`, `governance`, `status`, `last_release_on`, `verified_on`, `sources`, `decisions`, `pending`) et passe les mêmes contrôles. zot y entre sous `kubernetes-cluster.targets.local`. C'est une PR sur le schéma, sur le contrôle et sur leurs tests, en phase 3, avec la question de l'ADR-006 sur kubectl et Task, qui pourraient prendre la même forme. Le condensat de l'image reste dans le blueprint, comme le veut l'ADR-009.

Contenu, relevé par BENCH-010 le 2026-11-20 :

| Champ | Valeur |
| --- | --- |
| `service` | zot |
| `version` | 2.1.23 |
| `license` | Apache-2.0, approuvée par l'OSI |
| `governance` | `foundation`, CNCF ; projet Sandbox depuis le 2022-12-13 ; cinq mainteneurs de cinq organisations, deux actifs sur douze mois |
| `status` | `active`, dépôt non archivé |
| `last_release_on` | 2026-11-02 |
| `verified_on` | 2026-11-20 |
| `sources` | <https://github.com/project-zot/zot/releases>, <https://raw.githubusercontent.com/project-zot/zot/v2.1.23/LICENSE>, <https://www.cncf.io/projects/zot/>, <https://github.com/project-zot/zot/blob/v2.1.23/MAINTAINERS.md>, <https://api.github.com/repos/project-zot/zot>, lues le 2026-11-20 (S15, S16, S17, S22, S21 de BENCH-010) |
| `decisions` | ADR-011, BENCH-010 |
| `pending` | mécanisme à plusieurs amonts ([OPS]) ; T2 en `pull` seul ([QA], [OPS]) ; UID non root ([OPS]) ; mécanisme de purge ([OPS], [SECU]) |

Le contrôle de l'ADR-009 en tirerait ces échéances : le critère des 12 mois tombe le 2027-11-02 sans nouvelle release, et `verified_on` expire le 2027-05-20. BENCH-010 avance la vérification à la prochaine release de zot, au plus tard le 2027-02-20, à cause du rythme de ses avis.

## Condition de révision

Bascule par un nouvel ADR qui remplace celui-ci si zot touche un critère éliminatoire : dépôt archivé ou en maintenance, licence qui n'est plus open source, ou aucune release pendant 12 mois. Le décompte part de 2.1.23, publiée le 2026-11-02.

La décision se rouvre, sans basculer d'office, dans ces cas :

- T2 échoue avec la seule capacité `pull` (condition 1) ;
- ni le montage a ni le montage b ne fait passer T2 pour un registre autre que docker.io (condition 10) ;
- Distribution, ou un autre registre de fondation, démarre sans amont : la sensibilité le place de 84 à 87 ;
- une mesure montre qu'O4 recrée le cluster hors réseau sur tous les moteurs de Q5 ;
- l'essai du UID non root échoue et [SECU] refuse l'exécution en root (condition 6) ;
- un avis de zot touche la configuration retenue sans correctif dans les 60 jours que vise sa politique ;
- Lucas retient O1 par défaut (question 1), garde le miroir en marche entre deux sessions (question 2) ou préfère une brique de catalogue avec une ligne `gcp` (question 3).

Une montée de version de zot ne rouvre pas cet ADR : elle passe par Renovate et la matrice (condition 8). Sans l'un de ces faits, prochaine vérification à la prochaine release de zot, au plus tard le 2027-02-20, date proposée par BENCH-010.

## Sources

Ce que BENCH-010 établit se cite par lui ; ses propres sources sont dans sa section 9.

| Source | Lue le | Ce qu'elle établit |
| --- | --- | --- |
| [BENCH-010](../benchmarks/BENCH-010-demarrage-hors-reseau.md), sections 1 à 3 | 2026-11-21 | Question posée et ce qui en dépend ; T1 et T2 ; options et versions ; critères éliminatoires, licences et niveau CNCF |
| BENCH-010, section 4 | 2026-11-21 | Seuils et protocole ; absence de réseau simulée dans le nœud ; M1 à M9 ; échecs d'O3 et de Distribution et leurs causes ; T2 de zot trois fois sur trois ; images système de kind dans l'image de nœud ; `imagePullPolicy: Always` (M4) ; écoute de zot et réseaux `bridge` et `kind` (M9) |
| BENCH-010, sections 5 à 7 | 2026-11-21 | Notes et total de 83 ; sensibilité ; cumul avec la plate-forme de base ; réserves ; suites ; arbitrage du DSI du 2026-11-20 ; prochaine vérification au 2027-02-20 |
| BENCH-010, sections 8 à 10 | 2026-11-21 | Limites ; sources S2, S4, S8, S15 à S18, S20 à S22, S29 à S31 et S33 à S38 citées ici ; relectures de [SECU] (intégrité, exposition, root, redistribution, inventaire des scripts) et de [FINOPS] (coût mémoire, profils, disque, 518,2 Mo estimés, avis sur tous les profils et sur O1) |
| `tests/bench/bench-010-offline.sh`, lignes 147-148, 187, 291-303, 342-351 et 386-403 | 2026-11-21 | Image de zot et son condensat ; URL du miroir sur le réseau `kind` ; `hosts.toml` de l'essai en `pull` et `resolve` ; commande `docker run` de l'essai, sur `bridge` ; contrôle du conteneur avant usage |
| `tests/bench/bench-010/zot/config-online.json`, `tests/bench/bench-010/kind.yaml`, `tests/bench/bench-010/witness.yaml` ligne 60 | 2026-11-21 | Configuration mesurée : `sync` seule, `onDemand`, `"gc": false` ; `config_path` et montage en lecture seule ; image `zot-minimal` 2.1.23 utilisée comme témoin |
| `tests/bench/bench-009-gitops.sh`, lignes 87 à 93 ; `tests/bench/bench-005-orchestration.sh`, lignes 106 à 108 | 2026-11-21 | Images de Flux sur ghcr.io ; Postgres, Valkey et busybox sur Docker Hub |
| [BENCH-004](../benchmarks/BENCH-004-gateway.md), S11 ; [BENCH-005](../benchmarks/BENCH-005-orchestration-locale.md), S41 | 2026-11-21 | Proxy d'Envoy Gateway désigné par condensat dans le binaire 1.10.0 ; images de base de l'API sur mcr.microsoft.com |
| <https://github.com/containerd/containerd/blob/v2.3.4/docs/hosts.md> | 2026-11-21 | `capabilities` ; « A public mirror should never be trusted to do a resolve action » ; hôtes essayés dans l'ordre, puis `server` en repli ; `override_path` ; paramètre `ns` ajouté aux requêtes vers un miroir |
| <https://zotregistry.dev/v2.1.23/articles/mirroring/> | 2026-11-21 | `content`, `prefix`, `destination`, `stripPrefix` ; repli entre les `urls` d'une même entrée ; `onDemand` ; `manifestCheckInterval` ; rien sur le choix entre plusieurs entrées ni sur un amont injoignable |
| <https://zotregistry.dev/v2.1.23/articles/retention/> | 2026-11-21 | `storage.retention`, `deleteUntagged`, `keepUntagged` pour les entrées tirées par condensat seul, `pulledWithin`, `dryRun` ; exemple avec `"gc": true` ; ramasse-miettes actif pendant la vérification |
| <https://docs.docker.com/engine/containers/start-containers-automatically/> | 2026-11-21 | Politique de redémarrage `no` par défaut |
| <https://docs.docker.com/reference/cli/docker/container/run/> | 2026-11-21 | `--user`, `--cap-drop`, `--security-opt no-new-privileges=true`, `--read-only`, `--network`, `-p` |
| <https://docs.docker.com/engine/storage/volumes/> | 2026-11-21 | Volume géré par Docker, gardé quand le conteneur est retiré, retiré par `docker volume rm` ; contenu recopié dans un volume neuf ; rien sur les propriétaires |
| [ADR-004](ADR-004-cluster-local.md), conditions 1, 2, 3, 7 et 8 | 2026-11-21 | Boucle locale et test des ports ; contrôle de version ; images par condensat, registre local compris ; recréation hors ligne ; moteur libre |
| [ADR-005](ADR-005-gateway.md), condition 4 et tableau des versions | 2026-11-21 | R-25 avant le golden repo ; images d'Envoy Gateway sur docker.io |
| [ADR-006](ADR-006-orchestration-locale.md), ordre de `task up`, conditions 4 et 7, question 4 | 2026-11-21 | Étapes de `task up` ; pistes de R-25 ; images construites par `task up` ; lecture de US-005 ; noms des commandes en phase 5 |
| [ADR-007](ADR-007-secrets.md), condition 1 | 2026-11-21 | Secrets créés par `task up` seulement s'ils n'existent pas |
| [ADR-009](ADR-009-catalogue.md) et [`catalog/README.md`](../../catalog/README.md) | 2026-11-21 | Lignes `local` et `gcp` obligatoires ; condensats d'images hors du catalogue ; règles de fraîcheur ; domaine `.invalid` (RFC 2606, lue le 2026-11-19 par l'ADR-009) |
| [ADR-010](ADR-010-gitops.md), condition 6, question 3 | 2026-11-21 | Images de Flux par condensat ; un seul acteur sur les objets de l'application, `spec.suspend` |
| [docs/risques.md](../risques.md), R-04, R-20, R-25, R-26, R-30, R-34 | 2026-11-21 | Volume du premier `task up` et cumul de BENCH-010 ; limite de Docker Hub ; mitigation retenue par le DSI ; mitigations de R-34 |
| [specs/001-golden-repo-saas-b2b/spec.md](../../specs/001-golden-repo-saas-b2b/spec.md), récits 1 et 6, FR-008, FR-015, FR-016, SC-009 | 2026-11-21 | Commande d'arrêt qui dit ce qui reste ; redémarrage sans réseau ; aucune référence par tag ; durées affichées ; solution de BENCH-010 attendue |
| [docs/prd-mvp.md](../prd-mvp.md), US-001, US-005, US-011, ENF-01, ENF-03, section 7, Q5 | 2026-11-21 | Prérequis ; démarrage, profils lite et standard, arrêt ; mise à jour du projet ; budget de 15 minutes et débit visé ; dépendances figées ; profil standard de mesure ; systèmes visés |
| [Constitution](../../.specify/memory/constitution.md), version 1.2.0 | 2026-11-21 | Principes I à X ; exception de sécurité au délai de 7 jours |
