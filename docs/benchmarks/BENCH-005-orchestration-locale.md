# BENCH-005. Orchestration locale

| Champ | Valeur |
| --- | --- |
| Identifiant | BENCH-005 |
| Sujet | Outil derrière `task up` : il construit, démarre et recharge la stack du projet généré sur le PC |
| Statut | relu |
| Ouvert le | 2026-11-19 |
| Mis à jour le | 2026-11-20 |
| Auteur | [BENCH] |
| Relecteurs | [SECU] pour les licences, les CVE et les adresses d'écoute, [FINOPS] pour les coûts et les seuils des profils |
| Périmètre | Projet généré sur PC (macOS et Linux, Q5), dans le cluster kind retenu par Lucas (ADR-004 en cours). La cible GCP ne voit que les manifests |
| Choix du PRD | Orchestration dev locale, option pressentie Aspire (`docs/prd-mvp.md`, section 1) |
| ADR lié | ADR-006, à écrire par [ARCHI] |
| Verdict proposé | O4, sans outil de boucle (`docker build`, `kind load`, `kubectl apply`), 88/100, devant Tilt (74) et Aspire sur kind (63). Docker Compose et la boucle locale d'Aspire éliminés par US-005, décision du DSI du 2026-11-19, à confirmer par Lucas à la GATE 1 |

## 1. Contexte

[BENCH] Question posée : quel outil se cache derrière `task up` pour
construire l'API et le front du projet généré, démarrer toute la stack sur le
PC, et la recharger quand le développeur modifie le code.

[BENCH] Ce qui en dépend. US-005 demande que `task up` démarre l'API, le
front, Postgres et le cache « dans le cluster local », sans autre étape
(principe VII), affiche les adresses locales, et choisisse un profil lite,
standard ou full selon la RAM, avec des seuils à mesurer par BENCH-003 et
BENCH-005. Le cluster local est kind, retenu par Lucas le 2026-11-19
(BENCH-003, ADR-004 en cours). ENF-02 demande la parité entre PC et GCP :
seule la couche de cible change (principe II). ENF-01 fixe le parcours à
moins de 15 minutes, premier téléchargement des images compris (PRD,
section 7). Côté constitution : principes II, III (open source sur le PC), V
(fondation et plusieurs entreprises), VI (récent mais éprouvé), VII (une
commande) et VIII (aucun fait de mémoire). Côté risques : R-04 (15 minutes),
R-20 (identifiants par défaut et adresses d'écoute), R-25 (registres
publics) et R-26 (moteur de conteneurs payant).

[BENCH] Ce qui est jugé. Chaque option est jugée sur deux capacités : faire
tourner la stack dans kind avec les mêmes manifests que sur GKE, et la boucle
de développement (reconstruction et rechargement après une modification).
Docker Compose ne passe pas par Kubernetes : il est mesuré et noté comme les
autres, et sa note de portabilité dit ce que ce choix coûte.

[BENCH] La première version de ce rapport proposait au DSI d'éliminer, au
titre de US-005, les options qui ne démarrent pas la stack dans kind. Le DSI
l'a décidé par écrit le 2026-11-19 : la décision et sa raison sont en
section 3.

[BENCH] Option pressentie par le PRD : Aspire, reprise du brief (sections 6
et 8). Elle est notée comme les autres, avec le même script et les mêmes
sources.

[BENCH] Hors champ : le cluster lui-même (BENCH-003), la gateway
([BENCH-004](BENCH-004-gateway.md), [ADR-005](../adr/ADR-005-gateway.md)),
les secrets (BENCH-007), le contenu des profils standard et full, la
construction réelle du front (Vite) et le code de l'API, qui viendront du
golden repo de la phase 2.

## 2. Options étudiées

| Option | En une phrase | Version examinée | Publiée le | Sources |
| --- | --- | --- | --- | --- |
| Tilt | CLI qui construit les images, les charge dans le cluster et applique les manifests Kubernetes, puis resynchronise ou reconstruit à chaque modification | 0.37.9 | 2026-11-14 | [S1], [S2], [S5], [S6] |
| Aspire | AppHost écrit en code (C#, TypeScript ou Go) qui lance les projets .NET sur l'hôte et les dépendances en conteneurs, avec un tableau de bord ; `aspire publish` produit un chart Helm | 17.0.0 (CLI et paquets) | 2026-11-18 | [S11], [S12], [S14], [S18] |
| Docker Compose | Fichier `compose.yaml` qui décrit les services en conteneurs Docker, sans Kubernetes ; `up --watch` resynchronise ou reconstruit | 5.8.0, mesuré en 5.5.0 (section 4.2) | 2026-11-17 | [S27], [S28], [S31] |
| O4, sans outil de boucle | `task up` fait `docker build`, `kind load docker-image` et `kubectl apply -k` sur les mêmes manifests que Tilt ; une modification se recharge en relançant ces trois étapes | kubectl 1.37.1 (Kubernetes 1.37.2, dernière release) | 2026-10-28 | [S45], [S46], [S51] |

[BENCH] O4 est ajoutée le 2026-11-19, après la première série, par décision
du DSI. Deux raisons : le principe V coûte deux crans de gouvernance à Tilt
(Docker, un auteur à 53 %, version 0.x), et seule une base sans outil dit si
une boucle de rechargement vaut ce coût. O4 est le repli que la première
version du rapport citait déjà.

[BENCH] Aspire est mesuré par deux chemins. La boucle locale (`aspire
start`) a été mesurée la première ; elle est éliminée en section 3 et ses
mesures passent en annexe. Le chemin Kubernetes, seul retenu, enchaîne
`aspire publish` sur un AppHost doté d'un environnement Kubernetes
(`stack/aspire-k8s/apphost.cs`), la construction des images de l'API et du
front, `kind load`, puis l'installation du chart par Helm 4.3.2.

[BENCH] Aspire 17.0.0 a un jour au moment de la lecture. Le principe VI fait
attendre 7 jours avant toute mise à jour automatique : un projet généré
resterait en 13.6.5 jusqu'au 2026-11-25. Les avis de sécurité de la section
5.5 sont corrigés dans les deux.

[BENCH] Options repérées mais non étudiées : Skaffold, Garden, DevSpace,
Okteto et l'intégration kind de la boîte à outils communautaire d'Aspire
[S19]. Aucune ne figure dans la section 8 du brief, et aucune n'a été
vérifiée ici, sauf la page de l'intégration kind, citée en 5.7.

## 3. Critères éliminatoires

[BENCH] Seuil de release : 2025-11-19, douze mois avant la vérification.

| Option | Licence open source | Ni archivé ni en maintenance | Release de moins de 12 mois | Vérifié le | Résultat |
| --- | --- | --- | --- | --- | --- |
| Tilt | Oui, Apache-2.0 [S1], approuvée OSI [S35] | Oui, dépôt non archivé, dernier commit le 2026-11-14 [S1], [S3] | Oui, 0.37.9 le 2026-11-14, 12 releases stables en 12 mois [S2] | 2026-11-19 | Retenue |
| Aspire | Oui, MIT [S11], approuvée OSI [S35] | Oui, dépôt non archivé, dernier commit le 2026-11-18 [S11], [S13] | Oui, 17.0.0 le 2026-11-18, 36 releases stables en 12 mois [S12] | 2026-11-19 | Retenue |
| Docker Compose | Oui, Apache-2.0 [S27], approuvée OSI [S35] | Oui, dépôt non archivé, dernier commit le 2026-11-18 [S27], [S29] | Oui, 5.8.0 le 2026-11-17, 20 releases stables en 12 mois [S28] | 2026-11-19 | Passe les trois critères ; éliminé par US-005, voir plus bas |
| O4, sans outil de boucle | Oui, kubectl sous Apache-2.0 [S45], approuvée OSI [S35] | Oui, dépôt non archivé ; Kubernetes, environ 9 800 commits en 12 mois [S45], [S47] | Oui, Kubernetes 1.37.2 le 2026-10-28, 42 releases stables en 12 mois [S46] | 2026-11-19 | Retenue |

[BENCH] Aucune option n'est éliminée par les trois critères du brief.

[BENCH] Élimination par une exigence du PRD, décision du DSI datée du
2026-11-19, à confirmer par Lucas à la GATE 1 (`TEMPLATE.md`, section 3).
Raison : US-005 est un critère d'acceptation du PRD, écrit et validé avant ce
benchmark : « l'API, le front, Postgres et le cache démarrent dans le
cluster local ». Le critère s'applique à toutes les options de la même
façon.

- Docker Compose est éliminé : il ne démarre rien dans kind. Ses mesures
  restent dans l'annexe A, hors grille et sans note.
- La boucle locale d'Aspire (`aspire run`, `aspire start`) est éliminée pour
  la même raison : l'API tourne sur l'hôte et le reste dans Docker [S20],
  [S25]. Ses mesures passent aussi en annexe A, et les notes d'empreinte et
  d'expérience dev de la première version, qui portaient sur elle, sont
  retirées.
- Aspire reste candidat par le seul chemin qui place la stack dans kind :
  `aspire publish` vers Kubernetes, puis le chart installé dans kind [S18].
  Ce chemin a fonctionné au premier essai, le 2026-11-19 à 21:54 UTC ; il est
  mesuré avec le même script et les mêmes seuils.
- Aspire étant l'option pressentie par le brief, sa note et son classement
  restent une proposition que Lucas tranche.

[DSI] Trace de la première version, avant cette décision. Sa grille notait
les trois options du brief, le volume lu sur l'arm64 du poste : Docker
Compose 79, Tilt 76, Aspire 74, la boucle locale d'Aspire étant celle qui
était notée. Lu sur l'amd64, Tilt passe à 74 (relecture [FINOPS]). Ces
totaux ne servent plus au verdict ; ils restent ici pour que la décision
reste lisible.

## 4. Mesures

### 4.1 Ce qui est mesuré

[BENCH] Seuils et méthode des profils écrits le 2026-11-19 à 05:46 UTC, avant
la première mesure de ce benchmark. L'heure de chaque exécution est dans
`runs.tsv`. Git ne prouve ni cette heure ni la stabilité du texte : aucun
commit ne fige la section avant les mesures (relecture [FINOPS]). Ce qui se
vérifie : la seule révision déclarée est la lecture en amd64, plus bas, et
aucun réglage des seuils ne pouvait séparer O4 et Tilt, qui ont le même
volume et les mêmes tirages. Pour les benchmarks suivants, committer la
section 4.1 avant la première mesure.

| ID | Mesure | Unité | Critère alimenté | Script |
| --- | --- | --- | --- | --- |
| M1 | `task up` à chaud : de la première commande à la première ligne de la sonde qui voit l'API et le front répondre avec les marqueurs de l'exécution, Postgres et Valkey accepter une connexion | s | Empreinte sur PC | `tests/bench/bench-005-orchestration.sh` |
| M2 | `task up` à froid, images de la stack retirées, cache NuGet vide pour Aspire | s | Empreinte sur PC (ENF-01, R-04) | idem |
| M3 | Volume compressé du premier `task up` : images du registre, paquets NuGet, image de nœud kind | Mo | Empreinte sur PC (ENF-01, R-04) | idem, [S39], BENCH-003 |
| M4 | Images retéléchargées à chaque `task up` à chaud | nombre | Empreinte sur PC (R-25) | idem |
| M5 | Mémoire au repos de l'environnement complet, 2 minutes après « prêt » : conteneurs et processus de l'outil sur l'hôte | Mio | Empreinte sur PC, profils | idem |
| M6 | CPU au repos, au même moment | % d'un cœur | Empreinte sur PC | idem |
| M7 | Pic de mémoire pendant `task up` | Mio | Profils de US-005 | idem |
| M8 | `task down`, jusqu'à disparition des conteneurs | s | Expérience dev | idem |
| M9 | Boucle de développement : modification du fichier statique du front, puis du code de l'API, jusqu'à ce que la sonde voie le changement | s | Expérience dev | idem |
| M10 | Cluster kind seul au repos, même configuration | Mio | Profils de US-005 | idem |
| M11 | Adresses d'écoute des ports publiés et des processus de l'outil | adresse | Sécurité (R-20) | idem |
| M12 | Contenu du chart Helm que produit `aspire publish` avec un environnement Kubernetes | constat | Portabilité, sécurité | Essai manuel consigné en 4.4 |

#### Seuils de la note d'empreinte (section 5.6)

[BENCH] Règle de `TEMPLATE.md`, section 5.6, validée par Lucas le
2026-11-19 : seuils absolus, valeurs rondes tirées du PRD (budget de 900 s
d'ENF-01, portable de 8 Gio) ou d'un débit bas pris comme hypothèse
(10 Mbit/s). Chaque option part de 5 et perd un cran par condition remplie.
Le sujet change par rapport à BENCH-003 : on ne mesure plus le cluster seul,
mais tout ce que `task up` démarre avec l'option, cluster compris quand
l'option en utilise un. Les seuils sont adaptés en conséquence.

1. Le volume compressé téléchargé par le premier `task up`, caches vides,
   dépasse 500 Mo : image de nœud du cluster si l'option en crée un, images
   de la stack, images de base des constructions, paquets restaurés par
   l'outil. Repris de BENCH-003 : 400 s à 10 Mbit/s, soit 44 % du budget.
2. Ce même volume dépasse 1 000 Mo : 800 s à 10 Mbit/s, soit 89 % du budget.
   Ajouté parce que le volume porte maintenant sur toute la stack : au-delà,
   le téléchargement seul empêche de tenir ENF-01 sur une ligne lente.
3. Au moins une image ou un paquet se retélécharge à chaque `task up`, caches
   pleins, après un `task down`. Repris de BENCH-003.
4. Le `task up` à chaud (médiane, caches pleins, depuis un environnement
   supprimé) dépasse 90 s, soit 10 % du budget. Repris de BENCH-003, appliqué
   à toute la stack.
5. La mémoire au repos de l'environnement complet dépasse 2 Gio, un quart
   d'un portable de 8 Gio. Elle compte les conteneurs (nœud du cluster
   compris) et les processus que l'outil laisse tourner sur l'hôte. BENCH-003
   prenait un huitième pour le cluster seul ; le quart couvre le cluster et la
   stack lite.

[BENCH] Révision du 2026-11-19, décision du DSI prise après la première
série : le volume des conditions 1 et 2 se lit sur linux_amd64, pire cas des
systèmes de Q5, comme dans BENCH-004 et BENCH-008. Les seuils et leur texte
ne changent pas ; la lecture arm64 passe en sensibilité. Règle provisoire du
DSI jusqu'à la GATE 1 : la plate-forme de base (cluster kind, CRD Gateway
API, gateway) se compte contre les 500 Mo de BENCH-003 et BENCH-004, et
chaque couche suivante contre les seuils de sa propre section 4.1. Les
seuils ci-dessus comprennent le nœud kind et restent tels quels ; l'écart
entre les 500 Mo de BENCH-004 et les 1 000 Mo de la condition 2 est un point
de la GATE 1.

[BENCH] Une option à moins de 10 % d'un seuil voit ses deux notes possibles
écrites dans la sensibilité de la section 7. Le temps à froid et la boucle de
développement sont mesurés, mais ne retirent pas de cran ici : le temps à
froid dépend de la ligne, que le volume couvre déjà, et la boucle de
développement nourrit l'expérience dev (section 5.8).

#### Méthode des seuils des profils de US-005

[BENCH] Méthode proposée par [FINOPS] dans BENCH-003 (section 10) : cluster
au repos, plus stack du profil, plus une marge pour le système et les outils
du développeur. Le total doit tenir dans la mémoire de la machine virtuelle
du moteur, celle que lit `docker info` (sous macOS, ce n'est pas la RAM du
portable).

1. Plancher mesuré du profil : mémoire du cluster seul au repos, puis du
   cluster avec la stack du profil, au repos et au pic de démarrage, relevées
   par le script dans la même exécution. Le plancher retenu est le plus grand
   des deux, repos ou pic.
2. Mémoire minimale de la VM du moteur : plancher multiplié par 1,5, arrondi
   au demi-gibioctet supérieur. Le facteur 1,5 est une hypothèse de [BENCH],
   à confirmer par [OPS] : il couvre les constructions d'images, qui ne
   tournent pas dans un conteneur mesuré, et la dispersion entre postes.
3. RAM du portable conseillée : VM minimale plus 4 Gio pour le système, l'IDE
   et le navigateur. Autre hypothèse, à fixer avec [OPS].
4. `task up` lit la mémoire de la VM et retient le plus gros profil qui
   tient.

[BENCH] Seul le profil lite se mesure ici : sa stack est celle de US-005
(API, front, Postgres, cache). Le contenu des profils standard et full n'est
écrit nulle part ; la section 7 en propose une composition, à valider par
[ARCHI].

[BENCH] Écart à cette méthode, décidé en écrivant le script et avant toute
mesure : le cluster seul (M10) se relève dans une passe dédiée de la même
série, pas dans la même exécution que la stack, pour ne pas ajouter deux
minutes d'attente à M1.

### 4.2 Machine de mesure

| Élément | Valeur |
| --- | --- |
| Modèle | Apple Mac16,7 |
| Processeur | Apple M4 Pro, 14 cœurs |
| Mémoire | 24 Gio |
| Système | macOS 27.2.1 (build 26B131) |
| Moteur de conteneurs | OrbStack 2.2.5 (non libre, R-26), Docker Engine 29.8.2, cgroup v2, overlay2. Docker Compose 5.5.0, le greffon livré par OrbStack ; la dernière version est 5.8.0 [S28] |
| Ressources allouées | Machine virtuelle d'OrbStack : 14 CPU, 11,73 Gio (`docker info`) |
| Versions mesurées | Tilt 0.37.9 (Homebrew), kind 0.33.0 avec `kindest/node:v1.36.4` épinglée par condensat, kubectl 1.37.1 ; Aspire CLI 17.0.0 installée par `dotnet tool install --tool-path` dans un dossier dédié, paquets Aspire 17.0.0, SDK .NET 10.0.401 (Homebrew, alors que la dernière est 10.0.404 [S41]) ; vérifiées au démarrage du script |
| Charge parasite | Applications de bureau ouvertes, sessions Claude Code. D'autres benchmarks (BENCH-004, BENCH-007, BENCH-009) partagent le moteur : un verrou commun empêche deux séries de mesure simultanées, et le script relève leurs clusters et projets Compose dans `load.tsv` |

[BENCH] Stack d'essai, faute de golden repo (phase 2). Images figées par
condensat, lues le 2026-11-19 [S39] :

| Brique | Image ou source | Rôle |
| --- | --- | --- |
| API | Projet ASP.NET Core minimal, `/healthz` seulement, construit en deux étapes sur `mcr.microsoft.com/dotnet/sdk:10.0.404` et `aspnet:10.0.15` [S41] | Représente la compilation .NET et l'image d'exécution |
| Front | `nginx:1.30.7-alpine` [S38] et un fichier statique | Représente le front servi en statique ; la construction Vite viendra du golden repo |
| Postgres | `postgres:18.7-alpine` [S36] | Base de données ; mot de passe aléatoire écrit par le script dans un fichier en 600 du dossier d'essai, Secret créé par `kubectl create` ; le blueprint passera par un tube (BENCH-007) |
| Cache | `valkey/valkey:9.1.4-alpine` [S37], [S40] | Cache, sans mot de passe pour Tilt, O4 et Compose ; le blueprint devra en imposer un (R-20). Aspire l'impose par défaut |
| Sonde | `busybox:1.37.0` | Banc d'essai seulement : interroge les quatre briques depuis l'intérieur de l'environnement |

[BENCH] Mise en œuvre par option, chacune avec son mécanisme d'usage :

- Tilt : `kind create cluster`, création du Secret et de la ConfigMap de la
  sonde, puis `tilt up --host 127.0.0.1`. Les manifests de l'application
  (`k8s/app/`) sont ceux que GKE recevrait ; Postgres et Valkey sont dans la
  couche de cible (`k8s/local/`). Le front se resynchronise par
  `live_update`, l'API se reconstruit et entre dans kind par `kind load`,
  faute de registre local.
- Docker Compose : `docker compose up --build --watch`, ports publiés sur
  127.0.0.1. Le front se resynchronise (`sync`), l'API se reconstruit
  (`rebuild`).
- Aspire : `aspire start` sur un AppHost C# d'un seul fichier, profil de
  lancement `http`. L'API tourne en processus .NET sur l'hôte, le front est
  l'image nginx avec les fichiers montés, Postgres et Valkey passent par les
  intégrations officielles. Aspire ne surveille pas le code par défaut
  [S20] ; la commande documentée pour reconstruire un projet C# sans
  arrêter l'AppHost est `aspire resource api rebuild` [S25], lancée par le
  script juste après la modification. Option éliminée, mesures en annexe A.
- O4 : `kind create cluster`, Secret et ConfigMap, `docker build` de l'API
  et du front sous une étiquette neuve, `kind load docker-image`, puis
  `kubectl apply -k` sur `k8s/app/`, `k8s/local/` et la sonde, les
  étiquettes posées par kustomize. Après une modification, le script relance
  la construction de l'image touchée, `kind load` et `kubectl apply -k`, et
  ce temps compte dans M9.
- Aspire sur kind : `kind create cluster`, `aspire publish` de
  `stack/aspire-k8s/apphost.cs` (chart Helm), construction et `kind load`
  des images de l'API et du front avec les mêmes Dockerfile que O4, puis
  `helm upgrade --install` avec un fichier de valeurs qui porte les
  étiquettes et les mots de passe de l'essai. La boucle refait construction,
  `kind load` et `helm upgrade`. Le déploiement intégré, `aspire deploy`,
  aurait exigé un registre déclaré par une API en préversion [S18].

### 4.3 Protocole

1. État de départ : aucun conteneur, cluster ni projet Compose
   `celian-bench-005`. Avant l'exécution à froid (exécution 0) de chaque
   option, le script retire par référence exacte les images de la stack que
   l'option télécharge, et les images qu'il a construites ; pour Aspire, il
   part aussi d'un cache NuGet vide (`NUGET_PACKAGES` dans le dossier
   d'essai). Il ne retire jamais une image présente avant son lancement :
   l'image de nœud kind, partagée avec les autres benchmarks, reste en cache,
   et son volume vient de BENCH-003. Les exécutions 1 à 3 gardent tous les
   caches.
2. Commandes : celles de la section 4.2, identiques à chaque exécution.
   Chaque exécution écrit un marqueur neuf dans le code de l'API et dans la
   page du front : l'API est donc recompilée à chaque `task up`, comme
   après une journée de travail.
3. Fin de la mesure : la première ligne de la sonde, lue toutes les 0,5 s
   dans ses journaux, qui contient les deux marqueurs, `pg=[ok]` et une
   réponse de Valkey.
4. Relevé : chronomètre à la milliseconde (Perl `Time::HiRes`). Mémoire et
   CPU par `docker stats --no-stream` sur les conteneurs de l'option, et par
   `ps` (RSS, %CPU) sur les processus que l'outil laisse sur l'hôte :
   descendants du processus de l'outil, ou processus dont la ligne de
   commande désigne le dossier d'essai, la sortie de construction de
   l'AppHost ou le dossier de la CLI Aspire. Trois échantillons à partir de
   120 s après « prêt », espacés de 10 s, médiane des trois. Pic : un
   échantillon toutes les 1 à 3 s pendant `task up`. Téléchargements :
   événements `Pulled` du nœud kind et événements `pull` de Docker.
5. Boucle de développement (exécution 1) : trois modifications du fichier
   statique, puis trois du code de l'API, chacune chronométrée jusqu'à la
   ligne de la sonde qui montre le changement.
6. Une exécution 0 puis trois à chaud par option, 15 s de pause entre
   deux. Première série dans l'ordre Compose, boucle locale d'Aspire, Tilt,
   puis le cluster kind seul (M10) ; deuxième série pour O4 et Aspire sur
   kind, avec `COLD_REMOVE=0` : l'exécution 0 garde les images et sert de
   mise en route. Le script prend le verrou commun avant chaque série et le
   rend à la fin, erreur comprise.

Pour refaire la mesure :

```bash
ASPIRE_BIN=/chemin/vers/aspire tests/bench/bench-005-orchestration.sh /chemin/vers/un/dossier/vide
```

[BENCH] Sans argument, le script crée un dossier temporaire ; un dossier
passé en argument doit être absent ou vide. `OPTIONS`, `RUNS`, `COLD`,
`IDLE_WAIT`, `LOOP_ITER`, `CLUSTER_IDLE`, `TILT_PORT` et `BENCH_LOCK`
règlent l'essai. Le script refuse de démarrer si un conteneur, un cluster ou
un projet Compose `celian-bench-005` existe, ou si un de ses ports est
occupé. Son `trap` n'est posé qu'après ces contrôles et après le verrou :
un refus ne supprime rien. Il passe shellcheck et tourne sous le bash 3.2
de macOS. Aucun `curl`, aucun `docker run` ni `docker exec` : la sonde teste
le HTTP depuis l'intérieur de l'environnement.

### 4.4 Résultats

[BENCH] Série retenue lancée le 2026-11-19 de 20:06 à 20:50 UTC, verrou
pris, dans l'ordre Compose, Aspire, Tilt (dossier `b005-run2`). Aucun autre
cluster ni projet Compose de benchmark actif pendant la série (`load.tsv`).
Un test de fumée a précédé (12:40 à 13:01 UTC, une exécution par option).
Une première série, à 13:59 UTC, a échoué : dans le nœud kind neuf, les
tirages de Postgres, Valkey et busybox depuis Docker Hub sont restés bloqués
15 minutes, sans erreur, et `task up` a dépassé son délai. C'est le scénario
de R-25, constaté une fois ; la série suivante a tiré les mêmes images en
quelques secondes.

[BENCH] Deuxième série, pour O4 et Aspire sur kind, le même jour de 22:13 à
22:46 UTC (dossier `b005-run3`), verrou pris. L'exécution 0 y sert de mise
en route, hors médiane, sans retirer d'image (consigne du DSI : pas de
nouvelle tentative à froid). Le chemin Kubernetes d'Aspire a fonctionné au
premier essai, à 21:54 UTC, lors d'un test de fumée.

| Mesure | Option | Exécution 1 | Exécution 2 | Exécution 3 | Médiane | Écart |
| --- | --- | --- | --- | --- | --- | --- |
| M1, `task up` à chaud | Tilt | 39,8 s | 43,9 s | 36,8 s | 39,8 s | 7,1 s |
| M1 | O4 | 42,1 s | 38,5 s | 41,5 s | 41,5 s | 3,6 s |
| M1 | Aspire sur kind | 41,4 s | 38,0 s | 40,5 s | 40,5 s | 3,4 s |
| M5, mémoire au repos | Tilt | 896,2 Mio | 833,2 Mio | 896,5 Mio | 896,2 Mio | 63,3 Mio |
| M5 | O4 | 686,8 Mio | 689,3 Mio | 766,5 Mio | 689,3 Mio | 79,7 Mio |
| M5 | Aspire sur kind | 860,2 Mio | 831,2 Mio | 775,3 Mio | 831,2 Mio | 84,9 Mio |
| M6, CPU au repos | Tilt | 27,6 % | 26,4 % | 25,8 % | 26,4 % | 1,8 % |
| M6 | O4 | 19,7 % | 20,4 % | 19,0 % | 19,7 % | 1,4 % |
| M6 | Aspire sur kind | 20,8 % | 19,1 % | 20,8 % | 20,8 % | 1,7 % |
| M7, pic pendant `task up` | Tilt | 834,2 Mio | 772,0 Mio | 790,9 Mio | 790,9 Mio | 62,2 Mio |
| M7 | O4 | 788,4 Mio | 664,6 Mio | 697,6 Mio | 697,6 Mio | 123,8 Mio |
| M7 | Aspire sur kind | 787,2 Mio | 721,6 Mio | 727,4 Mio | 727,4 Mio | 65,6 Mio |
| M8, `task down` | Tilt | 0,6 s | 0,6 s | 0,6 s | 0,6 s | 0,0 s |
| M8 | O4 | 0,5 s | 0,6 s | 0,6 s | 0,6 s | 0,1 s |
| M8 | Aspire sur kind | 0,6 s | 0,6 s | 0,6 s | 0,6 s | 0,0 s |
| M9, front modifié | Tilt | 0,7 s | 0,6 s | 0,6 s | 0,6 s | 0,1 s |
| M9 | O4 | 5,7 s | 5,1 s | 3,8 s | 5,1 s | 1,9 s |
| M9 | Aspire sur kind | 4,8 s | 5,0 s | 5,1 s | 5,0 s | 0,3 s |
| M9, API modifiée | Tilt | 9,2 s | 6,2 s | 13,2 s | 9,2 s | 7,0 s |
| M9 | O4 | 6,6 s | 8,5 s | 6,1 s | 6,6 s | 2,4 s |
| M9 | Aspire sur kind | 8,5 s | 8,2 s | 7,5 s | 8,2 s | 1,0 s |
| M10, kind seul au repos | commun | 560,9 Mio | 563,5 Mio | 562,7 Mio | 562,7 Mio | 2,6 Mio |

[BENCH] Répartition de M5 (relecture [FINOPS]). Tilt, exécution médiane :
nœud kind 764,7 Mio, processus `tilt` 131,5 Mio ; les médianes par colonne,
764,7 et 130,3, ne s'additionnent pas en 896,2. O4 et Aspire sur kind : le
nœud kind seul, aucun processus sur l'hôte. Le nœud oscille, dans les trois
options et les deux séries, entre deux niveaux distants de 60 à 80 Mio,
parfois à 10 s d'écart dans une même exécution ; cause non attribuée. Avec
trois exécutions, la médiane tombe au niveau haut pour Tilt et au niveau bas
pour O4. À niveau égal, le nœud de Tilt pèse au plus 15 Mio de plus : sur les
207 Mio d'écart entre les deux, seuls les 130 Mio du processus `tilt` sont
établis. Ce processus tourne sous macOS hors de la VM du moteur, et porte les
redirections qui exposent l'API et le front, ce que la stack d'O4 ne fait
pas : la comparaison n'est pas à périmètre égal. Pour O4 et Aspire sur kind, M9 compte la construction de
l'image, `kind load` et `kubectl apply -k` ou `helm upgrade`, lancés par le
script comme le développeur les lancerait.

[BENCH] À froid (M2), mesure non obtenue proprement : au début des séries,
les images de Postgres, Valkey, nginx et busybox étaient déjà en cache,
tirées par un autre programme, et le script ne retire jamais une image qu'il
n'a pas créée. Le test de fumée, aux caches partiels, donne une indication
pour Tilt : 108,0 s.

[BENCH] Volume du premier `task up` (M3), en Mo compressés lus au registre
[S39], sonde exclue, noté sur linux_amd64 depuis la révision de 4.1. Images
retéléchargées à chaque `task up` à chaud (M4), d'après les événements du
nœud.

| Option | amd64 (noté) | arm64 | « Couche seule », sans le nœud kind, amd64 | Cumul avec Envoy Gateway (121,0, BENCH-004), amd64 | M4, à chaque `task up` |
| --- | --- | --- | --- | --- | --- |
| Tilt | 1 016,7 | 968,4 | 632,0 | 1 137,7 | Postgres et Valkey (et la sonde), tirés par le nœud |
| O4 | 1 016,7 | 968,4 | 632,0 | 1 137,7 | Postgres et Valkey (et la sonde), tirés par le nœud |
| Aspire sur kind | 1 204,5 | 1 153,1 | 819,8 | 1 325,5 | Postgres, Valkey et le tableau de bord `mcr.microsoft.com/aspire/nightly/dashboard:17.0`, par tag |

[BENCH] Détail amd64 : nœud kind 384,8 ; SDK .NET 362,8 ; runtime ASP.NET
104,0 ; nginx 26,1 ; Postgres 120,3 ; Valkey 18,8. Aspire sur kind y ajoute
le tableau de bord de son chart (71,5) et 105 paquets NuGet (116,4). Les
images de l'API et du front y sont construites par les mêmes Dockerfile que
pour O4 ; le déploiement intégré d'Aspire compilerait l'API avec le SDK du
poste et économiserait l'image du SDK (362,8), non mesuré.

[BENCH] Cause des tirages de M4, corrigée après la relecture de [SECU] :
chaque `task up` crée un nœud neuf, dont le containerd ne voit pas le cache
Docker du poste ; la stack d'essai ne précharge que les images qu'elle
construit. Postgres, Valkey et la sonde sont donc tirés à chaque fois,
figés par condensat ou non. La cause vérifiée pour
[BENCH-004](BENCH-004-gateway.md) n'explique pas ces tirages ; elle dit
pourquoi les précharger par `kind load docker-image` ne suffirait pas.

[BENCH] Adresses d'écoute (M11) : tout écoute en boucle locale. Tilt :
interface sur 127.0.0.1:10355, redirections sur 127.0.0.1:18580 et 18581,
un quatrième port 127.0.0.1:56467 au rôle non établi, API de kind sur
127.0.0.1. O4 et Aspire sur kind : rien n'est publié sur le poste hors de
l'API de kind, en 127.0.0.1 ; la stack d'essai n'expose ni l'API ni le
front, que la sonde interroge depuis le cluster. US-005 demande d'afficher
les adresses locales : avec O4, elles viendront de la gateway de
l'[ADR-005](../adr/ADR-005-gateway.md), publiée en 127.0.0.1, ou de
`kubectl port-forward`, en `localhost` par défaut [S68]. Une fois cet accès
en place, O4 et Tilt exposent la même chose, plus l'interface de Tilt.

[BENCH] Chart Helm d'Aspire (M12), essai du 2026-11-19 avec
`tests/bench/bench-005/aspire-k8s/apphost.cs` : `aspire publish` produit en
quelques secondes un chart `apphost` 0.1.0. L'API y garde une image à
fournir (`api:latest`), Postgres et Valkey deviennent des StatefulSets
figés par condensat, mots de passe vides dans `values.yaml`, et le chart
ajoute un tableau de bord tiré par tag :
`mcr.microsoft.com/aspire/nightly/dashboard:17.0`.

## 5. Notation par critère

Chaque option retenue reçoit une note entière de 0 à 5 sur chaque critère.
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

[BENCH] Dans cette section, Aspire désigne son chemin Kubernetes (Aspire sur
kind) : licence, gouvernance, maturité et activité sont celles du projet, les
autres critères portent sur ce chemin. Docker Compose, éliminé, n'est pas
noté ; ses mesures sont en annexe A.

### 5.1 Licence et liberté d'usage, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Tilt | 5/5 | 15 | Apache-2.0, approuvée par l'OSI. Le projet généré ne l'embarque pas : il le demande en prérequis | [S1], [S35] |
| Aspire | 5/5 | 15 | MIT pour la CLI, les paquets NuGet (licence lue dans leurs `.nuspec`) et le Developer Control Plane, dont le source est public depuis le 2026-01-08 | [S11], [S43], [S35] |
| O4 | 5/5 | 15 | kubectl sous Apache-2.0 ; kind et Task sont communs aux options | [S45], [S35] |

[BENCH] Aspire sur kind ajoute Helm en prérequis [S14], [S52]. Le critère
ne départage pas : trois licences permissives,
compatibles avec l'Apache-2.0 du générateur. Le seul coût de licence
possible reste le moteur de conteneurs du poste (R-26) : Aspire recommande
Docker Desktop et accepte Podman [S15].

### 5.2 Gouvernance (fondation, multi-vendeurs), poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Tilt | 2/5 | 6 | Éditeur unique : « Maintained by Docker, Inc. », copyright Docker, failles à signaler à Docker. Activité concentrée : un auteur, sans employeur déclaré, fait 53 % des 115 commits humains de l'année ; 32 auteurs en tout | [S1], [S3], [S4], [S34], [S56] |
| Aspire | 2/5 | 6 | Éditeur unique, sans fondation : dépôt de l'organisation Microsoft, failles au MSRC, aucune mention de fondation dans le README ; la page `.net-aspire` de la .NET Foundation répond 404 ; seule la boîte à outils communautaire est un projet de la .NET Foundation. Base large (146 auteurs, le premier à 17 %), sans effet sur la note, comme pour Copier et Traefik | [S11], [S13], [S34], [S44], [S62] |
| O4 | 5/5 | 15 | O4 n'ajoute aucun outil à ceux que toutes les options demandent déjà : kind, Task, le moteur de conteneurs, et kubectl, que `task up` utilise pour créer les Secrets locaux (BENCH-007). `kubectl apply -k` fait partie de kubectl, composant de Kubernetes, gradué à la CNCF | [S45], [S47], [S49], [S70] |

[BENCH] Note d'Aspire ramenée de 3 à 2 après la relecture de [SECU], par la
règle de cohérence : un éditeur unique sans fondation vaut 2 dans tous les
rapports. Si une source officielle de la .NET Foundation listait Aspire
lui-même, le 3 pourrait revenir. Seule O4 répond au principe V ; si Tilt ou
Aspire était retenu, l'ADR-006 devrait justifier l'écart.

[BENCH] kind, Task et le moteur de conteneurs sont communs aux trois options
et ne sont pas notés ici. Avec O4, la boucle vit dans le Taskfile : la
dépendance à Task est plus forte, sans effet sur la note, les commandes
restant portables. Aucun rapport n'a noté la gouvernance de Task (section 8).

### 5.3 Maturité et adoption, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Tilt | 4/5 | 12 | Créé en 2018, maintenu par Docker. Réserve : toujours en 0.x (0.37.9), aucune liste d'adoptants lue | [S1], [S2], [S4] |
| Aspire | 3/5 | 9 | Créé en 2023. La 17.0.0 a un jour, déprécie `AddProject` et le SDK d'AppHost d'avant, et relève le minimum à .NET 10 ; registres et AppHost Go encore en préversion ; l'intégration kind vient de la boîte à outils communautaire. Le principe VI demande d'attendre | [S11], [S12], [S14], [S18], [S19] |
| O4 | 5/5 | 15 | kubectl est l'outil de référence de Kubernetes, gradué à la CNCF depuis 2018 ; `kind load` et `kubectl apply -k` sont des commandes documentées et stables | [S45], [S49], [S51] |

### 5.4 Activité et maintenance, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Tilt | 4/5 | 8 | 12 releases stables en 12 mois, 115 commits humains par 32 auteurs, dernier commit le 2026-11-14. Réserve : le volume reste faible et repose sur un auteur | [S2], [S3] |
| Aspire | 5/5 | 10 | 36 releases stables en 12 mois, 3 005 commits humains par 146 auteurs, dernier commit le 2026-11-18 | [S12], [S13] |
| O4 | 5/5 | 10 | Kubernetes : 42 releases stables en 12 mois, environ 9 800 commits, dernière release le 2026-10-28 | [S46], [S47] |

### 5.5 Sécurité (CVE, réactivité), poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Tilt | 3/5 | 6 | HUD, redirections et API de kind sur 127.0.0.1, mesuré. Trois avis publiés le 2026-06-16, dont un critique (HUD sans authentification une fois exposé au réseau), corrigés le jour même en 0.37.4. Depuis cette version, jeton exigé sur les points du HUD qui modifient ou exposent l'état, contrôle d'`Origin`, pprof limité à la boucle locale, d'après la PR du correctif ; une variable `TILT_DISABLE_HUD_AUTH` désactive ces contrôles. Signalement privé chez Docker ; releases non immuables. Action : version minimale 0.37.4, `--host` laissé par défaut, `TILT_DISABLE_HUD_AUTH` refusé par un test, somme de contrôle du binaire vérifiée à l'installation | [M11], [S53], [S54], [S55], [S56] |
| Aspire sur kind | 2/5 | 4 | Quatre avis publiés les 10 et 11 novembre 2026, tous corrigés en 13.6.5 : trois élevés (hébergement et CLI) et un critique sur le tableau de bord, CVE-2026-118740, CVSS 9,1. Le chart livré déploie ce tableau de bord depuis le dépôt `aspire/nightly`, par le tag mobile `17.0`, écrit dans le modèle et tiré à chaque `task up` ; l'avis critique demande lui-même de remplacer les références `nightly` des manifests Kubernetes générés. OTLP du tableau de bord sans authentification par défaut. Mots de passe passés par les valeurs Helm, donc conservés dans les Secrets de release, celui de Valkey en argument de commande. MSRC, releases immuables ; télémétrie de la CLI active par défaut | [M4], [M12], [S11], [S21], [S57], [S58], [S59], [S60], [S61], [S63], [S69] |
| O4 | 4/5 | 8 | Rien n'est publié sur le poste hors de l'API de kind, en 127.0.0.1, mesuré ; la stack d'essai n'expose ni l'API ni le front, et l'accès de US-005 viendra de la gateway de l'ADR-005 ou de `kubectl port-forward`, en `localhost` par défaut, commun aux options. Toutes les images figées par condensat, rien de tiré par tag. Processus de sécurité de Kubernetes, accusé de réception sous 3 jours ouvrés ; flux officiel : 15 CVE en 12 mois, une seule sur kubectl (CVE-2026-19444, moyenne, `kubectl cp` sous Windows, hors Q5), aucune sur kustomize. Réserve : signature et immuabilité des binaires non vérifiées ici | [M11], [S50], [S64], [S65], [S68] |

[BENCH] Les trois exigences de [SECU] issues de BENCH-003 s'appliquent :
images figées par condensat, rien de tiré par tag au démarrage, 127.0.0.1
partout. Seul Aspire tire une image par tag de lui-même. Le
retéléchargement de Postgres et de Valkey par un nœud neuf, commun aux trois
options, est compté une seule fois, en 5.6 ; il ne figure plus ici (double
compte relevé par [FINOPS]). Le mot de passe de Valkey tient au manifest,
quel que soit l'outil : la couche locale du blueprint l'imposera pour O4
comme pour Tilt (exigences de la section 7).

### 5.6 Empreinte sur PC (RAM, CPU, démarrage), poids 10

[BENCH] Seuils de la section 4.1, écrits avant la première mesure.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Tilt | 2/5 | 4 | Trois conditions remplies : 1 016,7 Mo en amd64, au-dessus de 500 et de 1 000 Mo ; Postgres et Valkey retéléchargés par le nœud à chaque `task up`. M1 à 39,8 s et M5 à 896,2 Mio restent sous leurs seuils | [M1], [M3], [M4], [M5] |
| Aspire sur kind | 2/5 | 4 | Trois conditions remplies : 1 204,5 Mo en amd64 ; Postgres, Valkey et le tableau de bord retéléchargés à chaque `task up`. M1 à 40,5 s et M5 à 831,2 Mio sous leurs seuils | [M1], [M3], [M4], [M5] |
| O4 | 2/5 | 4 | Trois conditions remplies, comme Tilt : 1 016,7 Mo en amd64, Postgres et Valkey retéléchargés. M1 à 41,5 s, M5 à 689,3 Mio ; aucun processus sur l'hôte, et aucune adresse exposée à l'hôte dans l'essai | [M1], [M3], [M4], [M5] |

[BENCH] Sensibilité, sans changer les seuils, totaux dans l'ordre O4, Tilt,
Aspire. En arm64, Tilt et O4 sont à 3,2 % sous 1 000 Mo (968,4) et passent à
3/5 ; Aspire reste à 2/5 (1 153,1) : 90, 76, 63. En « couche seule », sans
le nœud kind, Tilt et O4 tombent à 632,0 Mo et Aspire à 819,8 Mo, tous à
3/5 : 90, 76, 65. Cumulés avec Envoy Gateway (BENCH-004), Tilt et O4 font
1 137,7 Mo et Aspire 1 325,5 Mo, sans changement de note. Aucune de ces
lectures ne départage Tilt et O4. Le nœud kind est compté deux fois, dans
les 500 Mo de la plate-forme de BENCH-004 et dans les seuils ci-dessus :
l'écart entre ces 500 Mo et les 1 000 Mo de la condition 2 est un point de
la GATE 1. Le CPU au repos, sans seuil, est plus haut avec Tilt (26,4 % d'un
cœur contre 19,7 %), dans le nœud et non dans le processus `tilt`.

### 5.7 Portabilité multi-cloud, poids 10

[BENCH] Le critère porte sur la parité demandée par ENF-02 et le principe
II : la stack tourne-t-elle dans kind avec les manifests que GKE recevra, la
couche de cible seule changeant ? Puis sur les systèmes du poste (Q5).

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Tilt | 5/5 | 10 | Applique à kind les manifests de l'application que GKE recevra (`k8s/app/`), la couche de cible (`k8s/local/`) restant à part ; vise tout contexte Kubernetes ; Linux, macOS et Windows | [M1], [S5], [S6] |
| Aspire sur kind | 3/5 | 6 | La stack tourne bien dans kind, par un chart que génère `aspire publish`. Mais ces manifests viennent d'un AppHost en C#, pas de la spec ni du catalogue (principe II) : Postgres et Valkey y sont des StatefulSets du cluster, et aucune cible GCP n'est documentée. Pour GKE, il faudrait une autre branche de l'AppHost | [M1], [M12], [S17], [S18] |
| O4 | 5/5 | 10 | Applique à kind les mêmes manifests que Tilt (`k8s/app/`, que GKE recevra), la couche de cible restant à part ; kubectl vise tout cluster ; Linux, macOS et Windows | [M1], [S45], [S51] |

### 5.8 Expérience dev et documentation, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Tilt | 4/5 | 8 | Une commande, interface web, documentation à jour. Front resynchronisé en 0,6 s ; API reconstruite et rechargée dans kind en 9,2 s, avec un écart de 7,0 s, par `kind load`, que la documentation dit lent face à un registre local. Réserve : un Tiltfile en Starlark à apprendre | [M9], [S5], [S6] |
| Aspire sur kind | 2/5 | 4 | Rien ne recharge seul : chaque modification demande construction, `kind load` et `helm upgrade` (front 5,0 s, API 8,2 s), et chaque `task up` refait `aspire publish`. Deux outils de plus (CLI Aspire, Helm). La documentation décrit `aspire deploy`, avec un registre en préversion, pas cette boucle sur kind | [M1], [M9], [S18], [S52] |
| O4 | 3/5 | 6 | Trois commandes standard, à envelopper dans une tâche ; aucune surveillance des fichiers : le développeur relance lui-même. API rechargée en 6,6 s, plus vite que Tilt ; front en 5,1 s, contre 0,6 s avec la resynchronisation de Tilt. Aucune interface | [M9], [S51] |

### 5.9 Coût (managé ou opérationnel), poids 5

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Tilt | 5/5 | 5 | Aucune licence ni service payant : un binaire sur le poste | [S1] |
| Aspire sur kind | 5/5 | 5 | Aucune licence ni service payant : une CLI, des paquets NuGet et Helm | [S11], [S16], [S52] |
| O4 | 5/5 | 5 | Aucune licence ni service payant : kubectl, déjà prérequis du projet généré pour les Secrets ; kind ne l'exige pas | [S45], [S67] |

[BENCH] Le critère ne départage pas. Le coût réel est le temps et la mémoire
du poste, notés en 5.6, et le moteur de conteneurs, hors du champ (R-26).
Aucune option ne tourne sur GKE : la cible GCP reçoit les manifests du
catalogue. Réserve de [FINOPS] pour Aspire : si son chart servait aussi sur
GKE, ses cinq charges sans requête y prendraient chacune 0,5 vCPU et 2 GiB
sous Autopilot [S77], et sa note passerait à 4/5.

## 6. Grille pondérée

| Critère | Poids | Tilt | Aspire sur kind | O4, sans outil de boucle | Docker Compose |
| --- | --- | --- | --- | --- | --- |
| Critères éliminatoires (section 3) | éliminatoire | passe | passe (boucle locale éliminée) | passe | éliminé par US-005 |
| Licence et liberté d'usage | 15 | 5/5, 15 pts | 5/5, 15 pts | 5/5, 15 pts | éliminé |
| Gouvernance (fondation, multi-vendeurs) | 15 | 2/5, 6 pts | 2/5, 6 pts | 5/5, 15 pts | éliminé |
| Maturité et adoption | 15 | 4/5, 12 pts | 3/5, 9 pts | 5/5, 15 pts | éliminé |
| Activité et maintenance | 10 | 4/5, 8 pts | 5/5, 10 pts | 5/5, 10 pts | éliminé |
| Sécurité (CVE, réactivité) | 10 | 3/5, 6 pts | 2/5, 4 pts | 4/5, 8 pts | éliminé |
| Empreinte sur PC (RAM, CPU, démarrage) | 10 | 2/5, 4 pts | 2/5, 4 pts | 2/5, 4 pts | éliminé |
| Portabilité multi-cloud | 10 | 5/5, 10 pts | 3/5, 6 pts | 5/5, 10 pts | éliminé |
| Expérience dev et documentation | 10 | 4/5, 8 pts | 2/5, 4 pts | 3/5, 6 pts | éliminé |
| Coût (managé ou opérationnel) | 5 | 5/5, 5 pts | 5/5, 5 pts | 5/5, 5 pts | éliminé |
| Total | 100 | 74 / 100 | 63 / 100 | 88 / 100 | éliminé |

## 7. Verdict proposé

[BENCH] Le verdict change par rapport à la première version. Option
proposée : O4, sans outil de boucle, 88 sur 100, devant Tilt (74) et Aspire
sur kind (63). Docker Compose et la boucle locale d'Aspire sont éliminés par
US-005 (section 3). Les relectures de [SECU] et [FINOPS] confirment le
verdict ; seule la gouvernance d'Aspire change, de 3 à 2.

[BENCH] Pourquoi. O4 et Tilt appliquent à kind les mêmes manifests, que GKE
recevra [M1], [S6], [S51], et ont la même empreinte : même volume, mêmes
tirages par le nœud, même temps de `task up` à 2 s près [M1], [M3], [M4].
Ce que Tilt ajoute, c'est sa boucle : le front se resynchronise en 0,6 s au
lieu de 5,1 s. Pour l'API, la boucle de Tilt (9,2 s) est plus lente que la
reconstruction à la main d'O4 (6,6 s) [M9]. Ce gain sur le front ne
compense pas le coût de gouvernance et de maturité : un éditeur unique, un
auteur à 53 %, une version 0.x [S2], [S3], [S4], contre kubectl, partie de
Kubernetes, gradué à la CNCF [S49]. La mémoire ne départage pas : sur les
207 Mio d'écart, seuls les 130 Mio du processus `tilt` sont établis, hors de
la VM sous macOS, et ce processus expose l'API et le front, ce que la stack
d'O4 ne fait pas encore (section 4.4). Aspire sur kind fonctionne, mais à
travers un chart généré depuis du C#, hors de la spec et du catalogue, sans
boucle de rechargement, et avec un tableau de bord tiré par le tag mobile
`nightly` dont le composant a reçu un avis critique le 2026-11-11
(CVE-2026-118740, CVSS 9,1) ; l'avis demande de remplacer ces références
`nightly` dans les manifests générés [M4], [M12], [S17], [S58].

[BENCH] Sensibilité, totaux dans l'ordre O4, Tilt, Aspire. Entre O4 et
Tilt, l'écart de 14 points tient à la gouvernance (9 points), la maturité
(3), l'activité (2) et la sécurité (2) ; Tilt ne reprend que 2 points sur
l'expérience dev. Il faudrait cinq crans pour inverser le classement.
Volume en arm64 : 90, 76, 63. Couche seule : 90, 76, 65. Mémoire cumulée
avec la plate-forme, lue contre le seuil d'1 Gio de la plate-forme seule :
86, 72, 61. Chart d'Aspire servi aussi sur GKE : 88, 74, 62. Tilt à 4 en
sécurité : 76. Aspire à 3 en gouvernance, si une source officielle le
rattachait à la .NET Foundation : 66. O4 reste premier dans toutes ces
lectures, avec 12 points d'avance au moins.

[BENCH] Ce qui reste ouvert : O4 est une base sans boucle. Si l'équipe
juge la resynchronisation du front indispensable, Tilt peut s'ajouter plus
tard au-dessus des mêmes manifests, sans rien changer à `k8s/` ; l'inverse
est vrai aussi. Avec un vrai front Vite, la reconstruction d'O4 sera plus
longue que les 5,1 s mesurées ici : à remesurer sur le golden repo.

[BENCH] Gouvernance : O4 répond au principe V. Si Lucas retenait Tilt ou
Aspire, l'ADR-006 devrait justifier l'écart.

[BENCH] Affichage des adresses de US-005 : la stack mesurée ne publie ni
l'API ni le front. O4 les affichera par la gateway de
l'[ADR-005](../adr/ADR-005-gateway.md), publiée en 127.0.0.1, ou par
`kubectl port-forward`, en `localhost` par défaut [S68]. Avec la gateway,
leur mémoire est déjà comptée dans la plate-forme de
[BENCH-004](BENCH-004-gateway.md) ; avec des redirections, elle reste à
mesurer. [ARCHI] et [PO] confirment que ce chemin satisfait US-005.

[BENCH] Aspire était l'option pressentie par le brief : sa note de 63 et
l'élimination de sa boucle locale sont des propositions que Lucas tranche à
la GATE 1.

[BENCH] Seuils proposés pour les profils de US-005, méthode de la section
4.1, lectures de [FINOPS]. M5 additionne la VM du moteur et l'hôte sous
macOS ; pour la VM, seul le nœud compte.

- Stack seule, sans gateway, avec O4 : plancher 697,6 Mio (le pic dépasse
  le repos), VM d'au moins 1,5 Gio, portable de 5,5 Gio. Même résultat pour
  Tilt (nœud 764,7 Mio, plus 130 Mio de `tilt` hors VM) et pour Aspire sur
  kind (831,2 Mio), le plus lourd sur le périmètre de la VM.
- Profil lite retenu, avec la plate-forme de base (kind et Envoy Gateway,
  948,8 Mio, BENCH-004), les Secrets natifs (BENCH-007) et la stack d'O4
  (134,9 Mio au-dessus de kind seul) : plancher 1 083,7 Mio, **VM d'au moins
  2,0 Gio, portable de 6,0 Gio**.
- Sensibilité : 2,5 Gio de VM et 6,5 Gio de portable si ESO ou Flux entrent
  dans le profil lite et se lisent au nœud ; 3,0 et 7,0 Gio dans le cumul le
  plus défavorable. Un portable de 8 Gio tient le profil lite dans toutes
  ces lectures. Docker Desktop donne par défaut 50 % de la RAM du poste à sa
  VM [S73], soit 4 Gio sur 8 ; OrbStack alloue à la demande sous une limite
  de 8 Go [S74], [S75] ; la page de `podman machine init` n'écrit aucune
  valeur par défaut [S76], à vérifier par [OPS].

[BENCH] Ces chiffres mêlent trois séries (BENCH-004, BENCH-005, BENCH-007) :
ordre de grandeur. Les facteurs 1,5 et 4 Gio restent des hypothèses que
[OPS] doit confirmer. Composition proposée à [ARCHI], non mesurée : standard
ajoute au lite Keycloak et Mailpit ; full ajoute l'observabilité, Argo CD et
Kyverno, avec le même calcul brique par brique.

[BENCH] Réserves à écrire dans l'ADR-006 : sur kind, chaque `task up` crée
un nœud neuf qui retélécharge Postgres et Valkey, quelle que soit l'option,
et ce tirage a bloqué une série entière le 2026-11-19 ; O4 n'a pas de boucle
de rechargement, et le front se recharge en 5,1 s au lieu de 0,6 s avec
Tilt. Prochaine vérification proposée : 2027-05-19.

[BENCH] Exigences de [SECU] pour l'ADR-006, si O4 est retenu :

1. Secrets locaux par `kubectl create -f -` alimenté par un tube, avant
   `kubectl apply -k` ; aucun objet `Secret` ni `secretGenerator` sous
   `k8s/`, contrôlé par un test.
2. Mot de passe imposé à Valkey dans la couche locale, transmis par un
   Secret, jamais en argument de commande ; syntaxe à vérifier sur la
   documentation de Valkey.
3. Accès de US-005 par la gateway de l'ADR-005 ou par
   `kubectl port-forward`, toujours en 127.0.0.1 ; le test des ports en
   écoute de R-20 s'applique.
4. R-25 traité avant le golden repo, avec la cause corrigée (section 4.4).
5. kubectl et Task inscrits aux prérequis du README généré, avec licence,
   gouvernance et date (principe IV).

[BENCH] Suites :

- l'ADR-006 de l'orchestration locale, écrit par [ARCHI] (l'ADR-005 est
  celui de la gateway), qui reprend l'élimination de Compose et de la boucle
  locale d'Aspire, à confirmer par Lucas à la GATE 1 ;
- `catalog/` : aucune entrée d'outil de boucle pour O4 ; kubectl, déjà
  prérequis du projet généré pour les Secrets (kind ne l'exige pas [S67]),
  et Task entrent aux prérequis du README avec licence, gouvernance et
  date ; la licence et la gouvernance de Task sont à relever une fois,
  quelle que soit l'option ;
- pour le blueprint : les trois étapes d'O4 dans une tâche `task reload` ;
  R-25 à traiter dans l'ordre de ses mitigations, la première étant de
  garder le cluster entre deux `task up` ;
- question pour [PO] et [ARCHI] : US-005 demande qu'une commande « arrête et
  supprime l'environnement ». Cela peut se lire comme supprimer
  l'application en gardant le cluster, ce qui supprimerait les
  retéléchargements de R-25 à chaque lancement ;
- condition de réintroduction d'un outil de boucle, à écrire dans
  l'ADR-006 : un outil ajouté plus tard au-dessus de `k8s/` reste facultatif
  et passe par une relecture [SECU]. Pour Tilt : version minimale 0.37.4,
  `--host` laissé par défaut, `TILT_DISABLE_HUD_AUTH` refusé par un test,
  somme de contrôle du binaire vérifiée, et écart au principe V justifié
  (Docker, Inc., un auteur à 53 %, version 0.x) ;
- risques : le DSI met à jour `docs/risques.md` lui-même, à partir des
  relectures de [SECU] et [FINOPS] :
  - R-25, cause corrigée : chaque `task up` crée un nœud neuf, dont le
    containerd ne voit pas le cache Docker du poste ; Postgres et Valkey
    sont retéléchargés à chaque lancement, et le tableau de bord d'Aspire
    par tag. Précharger par `kind load docker-image` ne suffirait pas
    (cause vérifiée pour BENCH-004). Mitigations à évaluer dans cet ordre :
    garder le cluster entre deux `task up` ; un miroir local en boucle
    locale, alimenté par condensat ; une archive OCI qui garde l'index du
    registre, chargée par `kind load image-archive` ; le magasin containerd
    du moteur ;
  - R-04, cumul de [FINOPS] : avec kind et Envoy Gateway, les Secrets
    natifs, Flux réduit et la stack d'O4 ou de Tilt, le premier `task up`
    télécharge 1 395,9 Mo en amd64, soit 124 % du budget d'ENF-01 à
    10 Mbit/s, avant l'entretien, la génération et la CI ; 101 % sans GitOps
    sur le PC ; il faut 12,4 Mbit/s pour le seul téléchargement. Tant que le
    cluster est recréé, chaque `task up` suivant retire 139 Mo (111 s à
    10 Mbit/s) ;
  - R-20, complément : mot de passe imposé à Valkey, transmis par un
    Secret ; aucun objet `Secret` ni `secretGenerator` sous `k8s/` ; des
    identifiants passés par un chart Helm resteraient dans ses Secrets de
    release, jusqu'à dix révisions par défaut [S69] ;
  - R-30, boucle locale maison portée par le Taskfile : avec O4, `task up`
    et `task reload` portent seuls construction, chargement, Secrets et
    application, dans un code copié dans chaque projet généré. Dérives
    possibles : un Secret appliqué par `kubectl apply` ou `secretGenerator`,
    un `task reload` qui s'écarte de `task up`, un outil de boucle installé
    sans relecture.

## 8. Limites et biais

| Limite | Effet possible sur le verdict | Ce qui la lèverait |
| --- | --- | --- |
| Stack d'essai minimale : API sans dépendance NuGet ni accès à la base, front statique sans construction Vite | Temps de construction et volume sous-estimés pour les trois options ; l'écart entre options sur la boucle de l'API peut changer avec un vrai projet | Refaire la série sur le golden repo de la phase 2 |
| Une seule machine, sous macOS, avec OrbStack, moteur non libre (R-26) | Empreinte propre à ce poste ; Aspire ne cite pas OrbStack parmi ses moteurs pris en charge [S15] | Relancer le script sous Linux avec Docker Engine, et avec Podman |
| Moteur partagé avec BENCH-004, BENCH-007 et BENCH-009 | Le verrou commun empêche deux séries simultanées, mais pas les créations et suppressions d'images des autres entre deux séries : des images de la stack ont disparu du cache après le test de fumée, retirées par un autre script. L'état réel du cache à chaque exécution est dans la colonne `cache` de `runs.tsv` | Une machine dédiée, ou un cache d'images propre à chaque benchmark |
| Cache de construction BuildKit jamais vidé | L'exécution à froid de Tilt et de Compose peut réutiliser des couches déjà construites ; le volume (M3), lu au registre, n'en dépend pas | Vider le cache de construction sur une machine dédiée |
| Une seule exécution à froid par option, sur la ligne du poste | M2 dépend du débit et des registres ; le volume (M3) n'en dépend pas | Plusieurs exécutions à froid, sur une ligne lente et sur un runner amd64 |
| Version de Compose mesurée (5.5.0) plus ancienne que la dernière (5.8.0) | Écarts de temps possibles sur `up --watch` | Installer Compose 5.8.0 et relancer l'option |
| SDK .NET 10.0.401 sur l'hôte, alors que la dernière est 10.0.404 | L'AppHost d'Aspire et l'API qu'il lance tournent sur le runtime 10.0.12, sans le correctif du 2026-11-10 ; la construction signale l'avis [S26] | Mettre à jour le SDK et relancer l'option Aspire |
| Aspire 17.0.0 mesuré, 13.6.5 non mesuré | Le principe VI ferait retenir 13.6.5 jusqu'au 2026-11-25 ; son chart et l'image de son tableau de bord ne sont pas vérifiés (le dépôt `nightly` n'a pas de tag 13.6.5 [S59]) | Produire le chart de 13.6.5 si Aspire revenait |
| Aspire sur kind monté par le script (images par nos Dockerfile, chart installé par Helm), pas par `aspire deploy`, qui exige un registre déclaré par une API en préversion | Le volume compte l'image du SDK (362,8 Mo en amd64). Sans elle, Aspire tomberait à 841,7 Mo, donc 3/5 ; le SDK .NET construit aussi l'image sans Dockerfile pour O4 et Tilt [S71], qui tomberaient à 653,9 Mo, 3/5. Classement inchangé | Essayer `aspire deploy` avec un registre local relié à kind, et la construction par le SDK pour toutes les options |
| Gouvernance de Task notée dans aucun rapport | Task est commun aux trois options, mais avec O4 il porte toute la boucle : une faiblesse de sa gouvernance pèserait plus sur O4. Sans effet mesuré sur la note, les étapes restant trois commandes standard | Relever la licence et la gouvernance de Task pour le catalogue |
| Valkey sans mot de passe dans la couche locale d'O4 et de Tilt | Tout pod du cluster lit et écrit le cache ; rien n'est publié sur le poste. La stack d'essai n'est pas le blueprint | Exigence 2 de la section 7 : mot de passe imposé, transmis par un Secret |
| Relevé des tirages Docker limité aux noms de la stack (`busybox`, `nginx`, `postgres`, `valkey`, `dotnet`, `kindest`) | Un tirage d'une image MCR d'Aspire par Docker échappe au relevé ; « aucune image retéléchargée » ne vaut pas preuve pour la boucle locale d'Aspire, éliminée. Les tirages du nœud kind, eux, sont tous relevés | Relever tous les événements `pull` de la série |
| Boucles d'O4 et d'Aspire sur kind lancées par le script juste après la modification | M9 ne compte pas le temps qu'un développeur met à taper la commande | Une tâche `task reload` mesurée en conditions réelles |
| Deux séries, à deux heures d'écart (Tilt à 20:32 UTC, O4 et Aspire sur kind à 22:13 UTC) | M3 et M4 n'en dépendent pas (volumes lus au registre, mêmes tirages). M1 contient environ 139 Mo tirés de Docker Hub à chaque exécution, donc le débit du registre, non journalisé ; l'écart entre Tilt et O4 (1,7 s) reste sous l'écart entre exécutions de Tilt (7,1 s). L'écart de M5 au nœud vient de ses deux niveaux de mémoire, pas de l'heure | Relancer les trois options dans une même série |
| Boucle d'Aspire mesurée avec `aspire resource api rebuild`, une commande que le développeur lance lui-même | Le mode `defaultWatchEnabled`, automatique, redémarre toute l'application [S25] : non mesuré | Ajouter une variante avec ce mode |
| Option pressentie par le PRD (Aspire) | Biais possible en sa faveur | Même script et mêmes sources pour les trois |
| Notes de jugement : gouvernance, maturité, sécurité, expérience dev | Le classement peut en dépendre (section 7) | Relectures de [SECU] et [FINOPS], avis de Lucas dans l'ADR |
| Effets de bord hors du dossier d'essai | Les images épinglées restent en cache ; Tilt garde son état dans `~/.tilt-dev`, la CLI Aspire le sien dans `~/.aspire` (journaux, cache, et un dossier `versions` de 372 Mio qui contient DCP et le tableau de bord, daté de 10:27 UTC, sans lien établi avec une exécution du script). Le script retire la sortie de construction de l'AppHost et les images qu'il a construites | Retirer ces images et dossiers après décision |

## 9. Sources

[BENCH] Les dates de release, les comptes d'activité et les métadonnées des
dépôts viennent de l'API publique de GitHub, lue le 2026-11-19 par `gh api`.
Un commit est compté humain quand son auteur n'est pas un robot (`bot`,
`renovate`, `dependabot`, `github-actions`, `copilot` filtrés par leur nom),
comme dans BENCH-003.

| ID | URL | Lue le | Ce que la source établit | Officielle |
| --- | --- | --- | --- | --- |
| S1 | <https://github.com/tilt-dev/tilt> | 2026-11-19 | Apache-2.0, dépôt non archivé, créé le 2018-08-07 ; `SECURITY.md` : signalement privé à `security@docker.com` | Oui |
| S2 | <https://api.github.com/repos/tilt-dev/tilt/releases> | 2026-11-19 | 0.37.9 le 2026-11-14, 0.37.4 le 2026-06-16 ; 12 releases stables depuis le 2025-11-19, toutes en 0.x ; aucune release immuable | Oui |
| S3 | <https://api.github.com/repos/tilt-dev/tilt/commits?since=2025-11-19T00:00:00Z> | 2026-11-19 | 161 commits sur 12 mois, dont 115 humains, par 32 auteurs ; 61 de `nicks` (53 %) ; dernier commit le 2026-11-14 | Oui |
| S4 | <https://tilt.dev/> | 2026-11-19 | Pied de page : « Maintained by Docker, Inc. » | Oui |
| S5 | <https://docs.tilt.dev/choosing_clusters.html> | 2026-11-19 | Avec kind, Tilt pousse vers un registre local monté par `ctlptl` ; sans lui, il se replie sur `kind load`, « much slower » | Oui |
| S6 | <https://docs.tilt.dev/api.html> | 2026-11-19 | `docker_build(..., live_update=[...])`, `k8s_yaml`, `k8s_resource(port_forwards=...)` ; un port forward écoute sur `localhost` par défaut ; contextes kind autorisés par défaut | Oui |
| S7 | <https://docs.tilt.dev/telemetry_faq.html> | 2026-11-19 | Choix des statistiques d'usage demandé à la première visite de l'interface ; refus par `tilt analytics opt out` ou `TILT_DISABLE_ANALYTICS` | Oui |
| S8 | <https://docs.tilt.dev/cli/tilt_ci.html> | 2026-11-19 | `tilt ci` sort en échec sur une construction ratée, en succès quand tout est sain ; interface sur `localhost:10350` par défaut | Oui |
| S9 | <https://api.github.com/advisories?ecosystem=go&affects=github.com/tilt-dev/tilt> | 2026-11-19 | Trois avis publiés le 2026-06-19, corrigés en 0.37.4 : CVE-2026-55884 (critique, serveur HUD sans authentification quand il est exposé au réseau), CVE-2026-55883 (élevé, détournement du WebSocket du HUD), CVE-2026-55882 (élevé, points `pprof` sans authentification) | Oui |
| S11 | <https://github.com/microsoft/aspire> | 2026-11-19 | MIT, dépôt de l'organisation Microsoft, non archivé, créé le 2023-09-25 ; `SECURITY.md` : signalement au MSRC, réponse sous 24 h ; le README ne cite pas la .NET Foundation | Oui |
| S12 | <https://api.github.com/repos/microsoft/aspire/releases> | 2026-11-19 | 17.0.0 le 2026-11-18, 13.6.5 le 2026-11-10 ; 36 releases stables depuis le 2025-11-19 ; releases immuables depuis 13.5.2 | Oui |
| S13 | <https://api.github.com/repos/microsoft/aspire/commits?since=2025-11-19T00:00:00Z> | 2026-11-19 | 3 703 commits sur 12 mois, dont 3 005 humains, par 146 auteurs ; 520 de `JamesNK` (17,3 %) ; 338 commits d'un agent Copilot ; dernier commit le 2026-11-18 | Oui |
| S14 | <https://github.com/microsoft/aspire/releases/tag/v17.0.0> | 2026-11-19 | .NET 10 minimum ; `AddProject` et `Aspire.AppHost.Sdk` dépréciés ; paquets Kubernetes passés en stable ; Helm 4.0.0 exigé pour le déploiement Kubernetes | Oui |
| S15 | <https://aspire.dev/get-started/prerequisites/> | 2026-11-19 | SDK .NET 10.0 pour un AppHost C# ; Docker Desktop recommandé, Podman pris en charge, Rancher Desktop non testé, OrbStack non cité ; page mise à jour le 2026-11-17 | Oui |
| S16 | <https://aspire.dev/get-started/install-cli/> | 2026-11-19 | Installation par Homebrew (`microsoft/aspire/aspire`), npm, outil .NET (`dotnet tool install -g Aspire.Cli`), WinGet, mise, Nix ou script | Oui |
| S17 | <https://aspire.dev/deployment/deploy-with-aspire/> | 2026-11-19 | Cibles de `aspire publish` et `aspire deploy` : Docker Compose, Kubernetes, AKS, Azure Container Apps, Azure App Service ; GCP et GKE absents | Oui |
| S18 | <https://aspire.dev/integrations/compute/kubernetes/> | 2026-11-19 | `Aspire.Hosting.Kubernetes` : `aspire publish` produit un chart Helm, `aspire deploy` l'installe dans le contexte `kubectl` courant par `helm upgrade --install` ; Helm 4 exigé ; registre à déclarer, API en préversion (`ASPIRECOMPUTE003`) | Oui |
| S19 | <https://aspire.dev/integrations/compute/kind/kind-host/> | 2026-11-19 | Intégration kind de la boîte à outils communautaire (`CommunityToolkit.Aspire.Hosting.Kind`) : à `aspire run`, le cluster est créé et reçoit manifests et charts, les projets ne tournent pas dedans ; seul `aspire deploy` construit et charge les images. Même lecture sur `kind-get-started` | Oui |
| S20 | <https://aspire.dev/reference/cli/commands/aspire-run/> | 2026-11-19 | `aspire run` ne surveille pas les sources par défaut ; option `features.defaultWatchEnabled` pour redémarrer après une modification ; `--detach`, `--isolated` | Oui |
| S21 | <https://aspire.dev/reference/cli/microsoft-collected-cli-telemetry/> | 2026-11-19 | La CLI envoie de la télémétrie ; refus par `ASPIRE_CLI_TELEMETRY_OPTOUT=true` ; rien sur le tableau de bord | Oui |
| S22 | <https://api.github.com/advisories?ecosystem=nuget&affects=Aspire.Cli> | 2026-11-19 | Même requête pour `Aspire.Hosting` : CVE-2026-120006 (élevé, élévation de privilèges, publié le 2026-11-10), CVE-2026-120792 (élevé, divulgation d'informations) et CVE-2026-120778 (élevé, élévation de privilèges), publiés le 2026-11-11 ; tous corrigés en 13.6.5 | Oui |
| S23 | <https://aspire.dev/whats-new/aspire-17/> | 2026-11-19 | `AddDotnetProject` remplace `AddProject` ; AppHost en `Microsoft.NET.Sdk` avec références explicites | Oui |
| S24 | <https://aspire.dev/diagnostics/aspire013/> | 2026-11-19 | Un AppHost C# exige le paquet de la CLI (« CLI bundle ») | Oui |
| S25 | <https://aspire.dev/app-host/hot-reload-and-watch/> | 2026-11-19 | Lue aussi par `aspire docs get hot-reload-and-watch`. `aspire run` et `aspire start` ne surveillent rien par défaut ; `features.defaultWatchEnabled` redémarre toute l'application après une modification d'un projet C# ; sans cela, `aspire resource <nom> rebuild` reconstruit un projet C# ; `dotnet watch` sur l'AppHost « has some quirks today » | Oui |
| S26 | <https://github.com/advisories/GHSA-p3jp-9v83-76w9> | 2026-11-19 | CVE-2026-111497 (élevé, publié le 2026-11-03) : `Microsoft.DotNet.ILCompiler` 10.0.x vulnérable avant 10.0.14 ; signalé à la construction de l'AppHost avec le SDK 10.0.401 | Oui |
| S27 | <https://github.com/docker/compose> | 2026-11-19 | Apache-2.0, dépôt de l'organisation Docker, non archivé, créé le 2013-12-09 ; pas de `SECURITY.md` propre, politique commune de l'organisation [S42] | Oui |
| S28 | <https://api.github.com/repos/docker/compose/releases> | 2026-11-19 | 5.8.0 le 2026-11-17, 5.5.0 le 2026-08-17 ; 20 releases stables depuis le 2025-11-19 ; aucune release immuable | Oui |
| S29 | <https://api.github.com/repos/docker/compose/commits?since=2025-11-19T00:00:00Z> | 2026-11-19 | 970 commits sur 12 mois, dont 841 humains, par 66 auteurs ; 441 de `ndeloof` (52,4 %), deux premiers à 69,8 % ; dernier commit le 2026-11-18 | Oui |
| S30 | <https://github.com/compose-spec/compose-spec> | 2026-11-19 | Spécification Compose sous Apache-2.0, Docker Compose en implémentation de référence ; `OWNERS.md` : `ndeloof`, `glours`, `aevesdocker` | Oui |
| S31 | <https://docs.docker.com/compose/how-tos/file-watch/> | 2026-11-19 | Actions `sync`, `rebuild`, `sync+restart` ; `docker compose up --watch` ou `docker compose watch` ; l'image doit contenir `stat`, `mkdir` et `rmdir` | Oui |
| S32 | <https://github.com/advisories/GHSA-gv8h-7v7w-r22q> | 2026-11-19 | CVE-2025-62725 (élevé, publié le 2025-10-27) : traversée de chemin par les annotations d'un artefact OCI, corrigée en 2.40.2 | Oui |
| S33 | <https://docs.docker.com/compose/bridge/> | 2026-11-19 | Compose Bridge convertit un fichier Compose en manifests Kubernetes et surcouche Kustomize ; licence et statut non écrits | Oui |
| S34 | GitHub, profils publics de `nicks`, `nicksieger`, `ndeloof`, `glours`, `Benehiko`, `JamesNK`, `davidfowl`, `sebastienros`, `mitchdenny`, `adamint` | 2026-11-19 | Employeur déclaré : aucun pour `nicks` ; Docker pour `nicksieger`, `ndeloof`, `glours`, `Benehiko` ; Microsoft pour les cinq premiers auteurs d'Aspire | Oui, déclaratif |
| S35 | <https://opensource.org/licenses> | 2026-11-19 | MIT et Apache-2.0 approuvées par l'OSI | Oui |
| S36 | <https://www.postgresql.org/support/versioning/> | 2026-11-19 | PostgreSQL 18.7, version mineure courante de la 18, maintenue jusqu'au 2030-11-14 | Oui |
| S37 | <https://github.com/valkey-io/valkey/releases> | 2026-11-19 | Valkey 9.1.4 publiée le 2026-11-18 | Oui |
| S38 | <https://nginx.org/en/download.html> | 2026-11-19 | nginx 1.30.7, branche stable | Oui |
| S39 | Registres Docker Hub et MCR, lus par `docker buildx imagetools inspect` | 2026-11-19 | Condensats des images de la stack, repris dans le script et la section 4.2 | Oui |
| S40 | <https://hub.docker.com/r/valkey/valkey> | 2026-11-19 | Image `valkey/valkey` « Maintained by: the Valkey Community », badge Sponsored OSS ; ce n'est pas une Docker Official Image | Oui |
| S41 | <https://dotnet.microsoft.com/en-us/download/dotnet/10.0> | 2026-11-19 | Dernière version : SDK 10.0.404, runtime 10.0.15, correctif de sécurité du 2026-11-10 | Oui |
| S42 | <https://github.com/docker/.github/blob/main/SECURITY.md> | 2026-11-19 | Politique de sécurité de l'organisation Docker : signalement privé à `security@docker.com`, accusé de réception sous 72 h | Oui |
| S43 | <https://github.com/microsoft/dcp> | 2026-11-19 | Developer Control Plane, l'orchestrateur local d'Aspire : MIT, dépôt public créé le 2026-01-08 ; même licence dans le `LICENSE` livré avec la CLI 17.0.0 | Oui |
| S44 | <https://dotnetfoundation.org/projects/project-detail/.net-aspire-community-toolkit> | 2026-11-19 | La boîte à outils communautaire d'Aspire figure parmi les projets de la .NET Foundation, sous MIT | Oui |

| S45 | <https://github.com/kubernetes/kubectl> | 2026-11-19 | kubectl : Apache-2.0, dépôt de l'organisation Kubernetes, non archivé, créé le 2017-03-30 | Oui |
| S46 | <https://api.github.com/repos/kubernetes/kubernetes/releases> | 2026-11-19 | Kubernetes 1.37.2, 1.36.6 et 1.35.10 publiées le 2026-10-28 ; 42 releases stables depuis le 2025-11-19 | Oui |
| S47 | <https://api.github.com/repos/kubernetes/kubernetes/commits?since=2025-11-19T00:00:00Z> | 2026-11-19 | Environ 9 800 commits en 12 mois, robots compris (nombre de pages à un commit par page) | Oui |
| S48 | <https://api.github.com/advisories?ecosystem=go&affects=k8s.io/kubectl> | 2026-11-19 | Aucun avis pour `k8s.io/kubectl` ; un seul pour `k8s.io/kubernetes` depuis le 2025-11-19 (même requête) | Oui |
| S49 | <https://www.cncf.io/projects/kubernetes/> | 2026-11-19 | Kubernetes accepté à la CNCF le 2016-03-10, gradué le 2018-03-06 (lue par BENCH-003) | Oui |
| S50 | <https://kubernetes.io/docs/reference/issues-security/security/> | 2026-11-19 | Processus de sécurité de Kubernetes : HackerOne ou `security@kubernetes.io`, accusé de réception sous 3 jours ouvrés (lue par BENCH-003) | Oui |
| S51 | <https://kind.sigs.k8s.io/docs/user/quick-start/> | 2026-11-19 | `kind load docker-image` charge une image locale dans les nœuds (lue par BENCH-003) | Oui |
| S52 | `brew info helm` et `helm version`, lus sur le poste | 2026-11-19 | Helm 4.3.2, version installée et dernière stable de Homebrew ; prérequis du chemin Kubernetes d'Aspire [S14] | Non, métadonnées Homebrew |

| S53 | <https://api.github.com/repos/tilt-dev/tilt/security-advisories> | 2026-11-20 | Lue par [SECU]. Trois avis publiés dans le dépôt le 2026-06-16, dans la base globale le 2026-06-19, corrigés en 0.37.4 ; « The default loopback-only bind is not reachable from the network » | Oui |
| S54 | <https://github.com/tilt-dev/tilt/pull/6776> | 2026-11-20 | Lue par [SECU], avec l'avis GHSA-c73q-8xxr-rgqm. Faille : aucun middleware d'authentification. Correctif : jeton exigé sur les URL qui modifient ou exposent l'état, contrôle d'`Origin`, pprof limité à la boucle locale, échappatoire `TILT_DISABLE_HUD_AUTH` (description et messages de commit, code non lu) | Oui |
| S55 | <https://api.github.com/repos/tilt-dev/tilt/releases?per_page=5> | 2026-11-20 | Lue par [SECU]. `"immutable": false` de 0.37.5 à 0.37.9 | Oui |
| S56 | <https://raw.githubusercontent.com/tilt-dev/tilt/master/SECURITY.md> | 2026-11-20 | Lue par [SECU]. Signalement à `security@docker.com` | Oui |
| S57 | <https://api.github.com/repos/microsoft/aspire/security-advisories> | 2026-11-20 | Lue par [SECU], remplace S22. Quatre avis : CVE-2026-120006, -120792, -120778 (élevés) et CVE-2026-118740 (critique), tous corrigés en 13.6.5 | Oui |
| S58 | <https://github.com/microsoft/aspire/security/advisories/GHSA-4g86-54fm-h9h8> | 2026-11-20 | Lue par [SECU]. Critique, CVSS 9,1 ; route `NotFound` du tableau de bord sans authentification ; demande de remplacer les références `nightly` des manifests générés, image fixée à `mcr.microsoft.com/aspire/dashboard:13.6.5` | Oui |
| S59 | <https://mcr.microsoft.com/v2/aspire/nightly/dashboard/tags/list> | 2026-11-20 | Lue par [SECU], avec le dépôt stable `aspire/dashboard`. Dépôt nocturne : `17.0`, `17.1`, `17.1.0`, pas de `13.6.5` ; dépôt stable : `13.6.5`, `17.0.0` | Oui |
| S60 | <https://aspire.dev/dashboard/configuration/> | 2026-11-20 | Lue par [SECU]. Interface en `BrowserToken`, OTLP en `Unsecured` par défaut | Oui |
| S61 | <https://aspire.dev/integrations/compute/kubernetes/> | 2026-11-20 | Relue par [SECU]. Tableau de bord inclus dans le chart, aucun moyen documenté de le retirer ni de changer son image | Oui |
| S62 | <https://dotnetfoundation.org/projects/project-detail/.net-aspire> | 2026-11-20 | Lue par [SECU], avec le README de `microsoft/aspire` et la liste des projets : page 404 ; README sans mention de fondation ; liste non lisible sans navigateur | Oui |
| S63 | <https://api.github.com/repos/microsoft/aspire/releases?per_page=8> | 2026-11-20 | Lue par [SECU]. Releases immuables de 13.6.3 à 17.0.0 ; 13.6.5 publiée le 2026-11-10 | Oui |
| S64 | <https://kubernetes.io/docs/reference/issues-security/official-cve-feed/index.json> | 2026-11-20 | Lue par [SECU], remplace S48. 15 CVE du 2025-11-19 au 2026-11-20, une seule sur kubectl, aucune sur kustomize | Oui |
| S65 | <https://github.com/kubernetes/kubernetes/issues/141294> | 2026-11-20 | Lue par [SECU]. CVE-2026-19444, moyenne (6,5), `kubectl cp`, Windows seulement, corrigée en 1.34.12, 1.35.9 et 1.36.5 | Oui |
| S66 | <https://api.github.com/advisories?ecosystem=go&affects=k8s.io/kubectl> | 2026-11-20 | Lue par [SECU]. Liste vide dans la base GitHub, qui ne suit pas le flux de Kubernetes | Oui |
| S67 | <https://kind.sigs.k8s.io/docs/user/quick-start/> | 2026-11-20 | Relue par [SECU]. « `kind` does not require `kubectl` » ; rien sur les condensats | Oui |
| S68 | <https://kubernetes.io/docs/reference/kubectl/generated/kubectl_port-forward/> | 2026-11-20 | Lue par [SECU]. `--address` à `localhost` par défaut, soit 127.0.0.1 et ::1 | Oui |
| S69 | <https://helm.sh/docs/topics/advanced/> | 2026-11-20 | Lue par [SECU], avec `helm upgrade`. Releases rangées dans des Secrets avec le contenu des valeurs ; `--history-max` à 10 ; page pas encore à jour pour Helm 4 | Oui |
| S70 | <https://kubernetes.io/docs/tasks/configmap-secret/managing-secret-using-kustomize/> | 2026-11-20 | Lue par [SECU]. `secretGenerator` lit fichiers, `.env` ou littéraux, appliqué par `kubectl apply -k` | Oui |
| S71 | <https://learn.microsoft.com/en-us/dotnet/core/containers/sdk-publish> | 2026-11-20 | Lue par [SECU]. « The .NET SDK creates container images without Docker » | Oui |
| S72 | <https://docs.docker.com/desktop/features/networking/> | 2026-11-20 | Lue par [SECU]. Ne dit pas si un conteneur joint un service lié au 127.0.0.1 de l'hôte | Oui |
| S73 | <https://docs.docker.com/desktop/settings-and-maintenance/settings/> | 2026-11-20 | Lue par [FINOPS] (F1). Mémoire de la VM de Docker Desktop : « Defaults to 50% of your host's memory » | Oui |
| S74 | <https://docs.orbstack.dev/settings> | 2026-11-20 | Lue par [FINOPS] (F2). Mémoire d'OrbStack : « no more than 8 GB by default » | Oui |
| S75 | <https://docs.orbstack.dev/efficiency> | 2026-11-20 | Lue par [FINOPS] (F3). Allocation à la demande, mémoire rendue à macOS | Oui |
| S76 | <https://docs.podman.io/en/latest/markdown/podman-machine-init.1.html> | 2026-11-20 | Lue par [FINOPS] (F4). `--memory` sans valeur par défaut écrite | Oui |
| S77 | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests> | 2026-11-20 | Lue par [FINOPS] (F5). Conteneur sans requête sous Autopilot : 0,5 vCPU et 2 GiB | Oui |

[BENCH] S22 et S48 restent pour l'historique : S57 et S64 les remplacent,
parce que la base GitHub des paquets ne voit ni l'avis critique du tableau
de bord d'Aspire ni le flux de Kubernetes.

[BENCH] S10 n'est pas attribué. Deux références internes complètent ces
sources : BENCH-003 pour le volume de l'image de nœud kind, et BENCH-004
pour le volume d'Envoy Gateway (121,0 Mo en amd64), la mémoire de la
plate-forme (948,8 Mio) et la cause, vérifiée par [SECU], de la perte du
condensat par `kind load docker-image` ; les relectures de BENCH-007 et
BENCH-009 par [FINOPS] pour ESO et Flux lus au nœud.

## 10. Relectures

| Relecteur | Porte sur | Date | Avis |
| --- | --- | --- | --- |
| [SECU] | Licences, critères éliminatoires, sécurité, adresses d'écoute, images tirées par tag | 2026-11-20 | Favorable, avec corrections |
| [FINOPS] | Coût, volumes, seuils des profils de US-005, R-04 | 2026-11-20 | Favorable, avec corrections |

[SECU] Licences et critères éliminatoires confirmés. Gouvernance d'Aspire
ramenée à 2 : aucune source officielle ne le rattache à une fondation.
Totaux : O4 88, Tilt 74, Aspire sur kind 63. Le tableau de bord que le chart
d'Aspire tire par tag depuis le dépôt `nightly` a reçu un avis critique le
2026-11-11 (CVE-2026-118740), qui demande de remplacer ces références dans
les manifests générés. Le HUD de Tilt exige un jeton depuis 0.37.4. kubectl
a une CVE en 12 mois, sous Windows seulement. Les retéléchargements de M4
viennent d'un nœud neuf à chaque `task up`, sans préchargement ; la cause de
BENCH-004 dit seulement pourquoi `kind load docker-image` ne suffirait pas à
les éviter. R-25 et R-20 complétés ; le texte sur Tilt passe en condition de
l'ADR-006 ; un risque ouvert pour la boucle maison d'O4.

[FINOPS] Empreinte. Les seuils de 4.1, datés de 05:46 UTC, précèdent toute
mesure ; Git ne le prouve pas, mais l'ajout d'O4 et du chemin Aspire ne
pouvait rien changer entre O4 et Tilt, qui ont le même volume et les mêmes
tirages. Les trois options à 2/5 appliquent la règle : leurs 1 016,7 Mo sont
communs. L'écart de mémoire entre O4 et Tilt tient au processus `tilt`
(130 Mio, hors de la VM sous macOS) et à deux niveaux du nœud ; O4 n'expose
aucune adresse à l'hôte dans l'essai. Profils : avec la plate-forme de base,
le profil lite demande une VM d'au moins 2,0 Gio et un portable de 6,0 Gio ;
8 Gio suffisent dans toutes les lectures. Coût : 5/5 confirmé, aucune option
ne tourne sur GKE. R-04 : à 10 Mbit/s, le premier `task up` complet dépasse
à lui seul le budget de 15 minutes, quelle que soit l'option.

[BENCH] Suite donnée, sans nouvelle mesure :

- gouvernance d'Aspire de 3 à 2, décision du DSI ; justification d'O4
  réécrite (aucun outil ajouté, kubectl déjà utilisé pour les Secrets) ;
  Task signalé en section 8 ;
- sécurité : quatre avis d'Aspire, dont le critique, et S57 à S63 ; HUD de
  Tilt décrit selon le correctif de 0.37.4 ; flux officiel de Kubernetes
  (S64, S65) ; retéléchargement retiré de 5.5, compté en 5.6 seulement ;
- R-25 : cause corrigée en 4.4 et en section 7 ; garder le cluster devient
  la première mitigation, avec la question à [PO] et [ARCHI] ;
- adresses : affichage par la gateway de l'ADR-005 ou `kubectl
  port-forward` ; comparaison de mémoire recadrée en 4.4 et en section 7 ;
- identifiants : Valkey sans mot de passe écrit en limite et en exigence ;
  Secrets de release de Helm cités pour Aspire ; interdiction de
  `secretGenerator` et de tout `Secret` sous `k8s/` ;
- [FINOPS] : trois arrondis corrigés ; note sur l'heure des seuils ; profils
  avec la plate-forme de base ; totaux de sensibilité ; ligne des deux séries
  réécrite ; R-04 cumulé dans les suites ;
- risques : textes repris dans les suites ; le DSI met `docs/risques.md` à
  jour lui-même (R-04, R-20, R-25, R-30), R-30 étant la boucle locale
  maison portée par le Taskfile ;
- script : inventaire de départ avant tout chemin qui nettoie, et verrou
  rafraîchi à chaque exécution ; `bash -n` et shellcheck passent, série non
  relancée.

## Annexe A. Mesures des options éliminées, pour information

[BENCH] Docker Compose et la boucle locale d'Aspire sont éliminés par
US-005 (section 3). Leurs mesures, prises avec le même script dans la série
du 2026-11-19 de 20:06 à 20:29 UTC (`b005-run2`), restent ici, hors grille et
sans note. Elles disent ce que coûte, sur ce poste, le passage par
Kubernetes qu'impose US-005.

| Mesure | Option | Exécution 1 | Exécution 2 | Exécution 3 | Médiane | Écart |
| --- | --- | --- | --- | --- | --- | --- |
| M1, `task up` à chaud | Compose | 3,9 s | 3,9 s | 3,9 s | 3,9 s | 0,0 s |
| M1 | Boucle locale d'Aspire | 11,1 s | 11,8 s | 7,9 s | 11,1 s | 3,9 s |
| M5, mémoire au repos | Compose | 174,4 Mio | 176,4 Mio | 175,5 Mio | 175,5 Mio | 2,0 Mio |
| M5 | Boucle locale d'Aspire | 1 266,2 Mio | 1 269,6 Mio | 1 276,0 Mio | 1 269,6 Mio | 9,8 Mio |
| M7, pic pendant `task up` | Compose | 159,7 Mio | 162,3 Mio | 163,8 Mio | 162,3 Mio | 4,1 Mio |
| M7 | Boucle locale d'Aspire | 1 234,9 Mio | 1 235,4 Mio | 1 222,2 Mio | 1 234,9 Mio | 13,2 Mio |
| M8, `task down` | Compose | 10,4 s | 10,5 s | 10,5 s | 10,5 s | 0,1 s |
| M8 | Boucle locale d'Aspire | 17,6 s | 17,4 s | 15,3 s | 17,4 s | 2,3 s |
| M9, front modifié | Compose | 1,2 s | 1,2 s | 1,2 s | 1,2 s | 0,0 s |
| M9 | Boucle locale d'Aspire | 0,6 s | 0,0 s | 0,6 s | 0,6 s | 0,6 s |
| M9, API modifiée | Compose | 3,4 s | 2,8 s | 3,4 s | 3,4 s | 0,6 s |
| M9 | Boucle locale d'Aspire, avec `aspire resource api rebuild` | 3,0 s | 2,8 s | 3,6 s | 3,0 s | 0,8 s |

[BENCH] Volume du premier lancement, en Mo compressés, amd64 : Compose
632,0, boucle locale d'Aspire 314,1 (dont 116,4 de paquets NuGet et 33,1
pour la base Azure Linux du tunnel de DCP, tirée par tag). Aucune image de
la stack retéléchargée à chaque lancement ; pour les images MCR d'Aspire, le
relevé ne prouve rien (section 8). Mémoire de la boucle locale d'Aspire :
72,2 Mio de conteneurs, dont le conteneur `tunnel-proxy` de DCP, et
1 195,3 Mio de processus sur l'hôte (une douzaine de processus `dcp`
d'environ 50 Mio, l'AppHost, le tableau de bord, la CLI et l'API). Adresses
d'écoute : tout en boucle locale ; Compose publie sur 127.0.0.1 parce que
le fichier le demande.

[BENCH] Boucle de l'API sous Aspire : au test de fumée, `aspire resource api
restart` relançait l'ancienne version, et la sonde ne voyait jamais le
changement en 600 s. La commande documentée est `rebuild` [S25] ; c'est elle
que mesure M9.
