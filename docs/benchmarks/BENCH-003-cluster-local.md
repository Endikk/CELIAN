# BENCH-003. Cluster local

| Champ | Valeur |
| --- | --- |
| Identifiant | BENCH-003 |
| Sujet | Outil qui crée le cluster Kubernetes local sur lequel `task up` démarre le projet généré |
| Statut | relu |
| Ouvert le | 2026-11-19 |
| Mis à jour le | 2026-11-19 |
| Auteur | [BENCH] |
| Relecteurs | [SECU] pour les licences, les CVE et les adresses d'écoute, [FINOPS] pour les coûts |
| Périmètre | Projet généré sur PC (macOS et Linux, Q5). La cible GCP passe par GKE et ne voit pas ce choix |
| Choix du PRD | Cluster local, option pressentie k3d (`docs/prd-mvp.md`, section 1) |
| ADR lié | À écrire par [ARCHI], numéro à attribuer |
| Verdict proposé | kind, 90/100, devant minikube (87) et k3d (64), avec la règle d'empreinte proposée par [FINOPS], recommandée par le DSI, à valider par Lucas. Avec l'ancienne règle et le tirage de kindnetd compté une seule fois, minikube passerait à 91 (section 7) |

## 1. Contexte

[BENCH] Question posée : quel outil crée le cluster Kubernetes local dans
lequel `task up` démarre l'API, le front, Postgres et le cache du projet
généré.

[BENCH] Ce qui en dépend. US-005 demande que `task up` démarre toute la stack
dans le cluster local sans autre étape (principe VII), affiche les adresses
locales, et propose un profil lite, standard ou full selon la RAM, avec des
seuils à mesurer par BENCH-003 et BENCH-005. ENF-01 fixe le parcours à moins
de 15 minutes, et la section 7 du PRD y compte le premier téléchargement des
images, parce qu'une personne extérieure ne les aura pas en cache. ENF-02
demande la parité entre PC et GCP : seule la couche de cible change
(principe II), et l'empreinte de chaque profil est à mesurer. Côté
constitution : principes III (open source sur le PC), V (fondation et
plusieurs entreprises), VI (récent mais éprouvé), VIII (aucun fait de
mémoire). Côté risques : R-04 (15 minutes hors d'atteinte), R-20
(identifiants par défaut, et ports publiés sur toutes les interfaces), R-25
(démarrage local tributaire des registres publics) et R-26 (moteur de
conteneurs du poste sous licence payante). BENCH-004 (gateway) a besoin d'un
port publié vers l'hôte et des CRD Gateway API ; BENCH-005 (orchestration
locale) s'appuiera sur le chargement d'images locales.

[BENCH] Contrôles fonctionnels. Cinq contrôles servent le blueprint :
publication d'un port vers l'hôte pour une gateway, chargement d'une image
locale sans registre, registre local, plusieurs nœuds, installation des CRD
Gateway API du canal standard. Aucun n'est une exigence écrite du PRD : ils
alimentent l'expérience dev, la portabilité et la sécurité, et n'éliminent
aucune option.

[BENCH] Option pressentie par le PRD : k3d, reprise du brief (sections 6 et
8). Elle est notée comme les autres, avec le même script et les mêmes sources.

[BENCH] Hors champ : la gateway elle-même (BENCH-004), l'outil
d'orchestration locale (BENCH-005), Windows (Q5, à évaluer par [OPS]), le
choix du moteur de conteneurs du poste (OrbStack, Docker Desktop, Docker
Engine sous Linux), et le réglage fin du cluster dans le blueprint, qui
revient à [ARCHI] et [OPS].

## 2. Options étudiées

| Option | En une phrase | Version examinée | Publiée le | Sources |
| --- | --- | --- | --- | --- |
| k3d | CLI qui fait tourner k3s, la distribution Kubernetes allégée de la CNCF, dans des conteneurs Docker, derrière un load balancer nginx | 5.9.0, avec l'image `rancher/k3s:v1.36.4-k3s1` | 2026-06-02 | [S1], [S2], [S8] |
| kind | Kubernetes dans Docker : chaque nœud est un conteneur monté par kubeadm. Sous-projet de SIG Testing | 0.33.0, avec l'image `kindest/node:v1.36.4` épinglée par digest | 2026-08-26 | [S10], [S11], [S12] |
| minikube | Cluster local pour le développement d'applications, dans un conteneur ou une VM selon le pilote ; ici le pilote `docker`. Sous-projet de SIG Cluster Lifecycle | 1.39.0, avec `--kubernetes-version=v1.36.4` | 2026-09-02 | [S19], [S20], [S21] |

[BENCH] Version de Kubernetes alignée au correctif près : v1.36.4 pour les
trois. C'est la version par défaut de k3d 5.9.0 (relevée par `k3d version`),
une image publiée avec kind 0.33.0 [S12], et une version proposée par
minikube 1.39.0 (`minikube config defaults kubernetes-version`). kind et
minikube passent par défaut en v1.37.0 [S12], [S21]. Le dernier correctif de
la branche 1.36 est 1.36.5, maintenu jusqu'au 2027-06-28 [S45].

[BENCH] Options repérées mais non étudiées : le Kubernetes intégré à OrbStack
ou à Docker Desktop, Rancher Desktop et MicroK8s. Aucune ne figure dans la
section 8 du brief, et aucune n'a été vérifiée ici.

## 3. Critères éliminatoires

[BENCH] Seuil de release : 2025-11-19, douze mois avant la vérification.

| Option | Licence open source | Ni archivé ni en maintenance | Release de moins de 12 mois | Vérifié le | Résultat |
| --- | --- | --- | --- | --- | --- |
| k3d | Oui, MIT [S1], approuvée OSI [S33]. k3s sous Apache-2.0 [S8] | Oui, dépôt non archivé, dernier commit le 2026-10-18 [S1], [S3] | Oui, 5.9.0 le 2026-06-02 [S2] | 2026-11-19 | Retenue |
| kind | Oui, Apache-2.0 [S10], approuvée OSI [S33] | Oui, dépôt non archivé, dernier commit le 2026-11-18 [S10], [S13] | Oui, 0.33.0 le 2026-08-26 [S11] | 2026-11-19 | Retenue |
| minikube | Oui, Apache-2.0 [S19], approuvée OSI [S33] | Oui, dépôt non archivé, dernier commit le 2026-11-18 [S19], [S22] | Oui, 1.39.0 le 2026-09-02 [S20] | 2026-11-19 | Retenue |

[BENCH] Options éliminées : aucune. k3d passe le critère de release avec une
seule version en douze mois ; sans nouvelle release au 2027-06-02, il
tomberait.

## 4. Mesures

### 4.1 Ce qui est mesuré

| ID | Mesure | Unité | Critère alimenté | Script |
| --- | --- | --- | --- | --- |
| M1 | Temps de création jusqu'à « prêt », images en cache | s | Empreinte sur PC | `tests/bench/bench-003-clusters.sh` |
| M2 | Mémoire au repos des conteneurs du cluster, 2 minutes après « prêt » | Mio | Empreinte sur PC | `tests/bench/bench-003-clusters.sh` |
| M3 | CPU au repos des conteneurs du cluster, au même moment | % d'un cœur | Empreinte sur PC | `tests/bench/bench-003-clusters.sh` |
| M4 | Temps de suppression, jusqu'à disparition des conteneurs | s | Empreinte sur PC, expérience dev | `tests/bench/bench-003-clusters.sh` |
| M5 | Création à froid jusqu'à « prêt », images de l'option retirées | s | Empreinte sur PC (ENF-01, R-04) | `tests/bench/bench-003-clusters.sh` |
| M6 | Volume téléchargé à froid, et images tirées par le nœud à chaque création | Mo | Empreinte sur PC (ENF-01, R-04) | `tests/bench/bench-003-clusters.sh`, [S39], [S46], [S47] |
| M7 | Contrôles fonctionnels utiles au blueprint | oui ou non | Expérience dev, portabilité | `tests/bench/bench-003-clusters.sh` |
| M8 | Adresse d'écoute par défaut de l'API et des ports publiés | adresse | Sécurité (R-20) | `tests/bench/bench-003-clusters.sh` |

### 4.2 Machine de mesure

| Élément | Valeur |
| --- | --- |
| Modèle | Apple Mac16,7 |
| Processeur | Apple M4 Pro, 14 cœurs (10 performance, 4 efficacité) |
| Mémoire | 24 Gio |
| Système | macOS 27.2.1 (build 26B131) |
| Moteur de conteneurs | OrbStack 2.2.5 (moteur non libre, voir R-26), Docker Engine 29.8.2, cgroup v2, pilote de stockage overlay2 |
| Ressources allouées | Machine virtuelle d'OrbStack : 14 CPU, 11,73 Gio (12 598 894 592 octets, `docker info`) |
| Versions mesurées | k3d 5.9.0, kind 0.33.0, minikube 1.39.0, Kubernetes v1.36.4 pour les trois, figés et vérifiés au démarrage du script. kubectl 1.37.1. k3d et kind installés par Homebrew le 2026-11-19 pour ce benchmark ; minikube l'était déjà |
| Charge parasite | Applications de bureau ouvertes (navigateur, synchronisation de fichiers, sessions Claude Code). Charge moyenne sur une minute entre 3,30 et 5,78 au début de chaque exécution (`uptime`, `load.tsv`). Aucun autre conteneur ni cluster n'était actif pendant la série |

### 4.3 Protocole

1. État de départ : aucun conteneur du cluster `celian-bench-003`. Avant
   l'exécution à froid (exécution 0), le script retire par référence exacte
   les images épinglées de l'option : `rancher/k3s`, `k3d-proxy` et
   `k3d-tools` pour k3d, `kindest/node` pour kind, `kicbase` pour minikube,
   qui part aussi d'un `MINIKUBE_HOME` vide, donc sans son archive
   d'images préchargées. Les exécutions 1 à 3 gardent ces images dans le
   cache de Docker. Le kubeconfig et `MINIKUBE_HOME` vivent dans le dossier
   d'essai : `~/.kube/config` et `~/.minikube` ne servent pas, et la date
   de `~/.kube/config` est la même avant et après la série.
2. Commandes lancées, réglages par défaut pour le reste :
   `k3d cluster create celian-bench-003 --image rancher/k3s:v1.36.4-k3s1
   --timeout 600s` ; `kind create cluster --name celian-bench-003 --image
   kindest/node:v1.36.4@sha256:099e…faed --kubeconfig <essai>/kubeconfig` ;
   `minikube start -p celian-bench-003 --driver=docker --interactive=false
   --kubernetes-version=v1.36.4`. minikube choisit seul containerd, 2 CPU et
   une limite de mémoire ; aucune limite n'est demandée à kind ni à k3d.
3. Fin de la mesure : le premier de trois contrôles consécutifs, espacés
   d'une seconde, où tous les nœuds sont Ready et où chaque pod de
   `kube-system` est Ready ou Succeeded, avec Deployments disponibles,
   DaemonSets prêts et Jobs terminés. Pour k3d, chaque HelmChart de k3s doit
   aussi avoir son job terminé.
4. Relevé : chronomètre à la milliseconde (Perl `Time::HiRes`). Mémoire et
   CPU par `docker stats --no-stream` sur les conteneurs portant l'étiquette
   du cluster, trois échantillons à partir de 120 s après « prêt », espacés
   de 10 s, médiane des trois. Suppression par la commande de l'outil, chronométrée jusqu'à la
   disparition des conteneurs. Adresses par `docker ps` et `lsof` côté macOS.
5. Une exécution à froid puis trois à chaud par option, 15 s de pause entre
   deux, options enchaînées dans l'ordre k3d, kind, minikube, puis les
   contrôles fonctionnels sur un cluster dédié par option.

Pour refaire la mesure :

```bash
tests/bench/bench-003-clusters.sh /chemin/vers/un/dossier/vide
```

[BENCH] Sans argument, le script crée un dossier temporaire. Un dossier passé
en argument doit être absent ou vide. `OPTIONS`, `RUNS`, `COLD`, `FUNCTIONAL`
et `IDLE_WAIT` règlent l'essai. Le script refuse de démarrer si un cluster
`celian-bench-003` existe déjà. Son `trap` n'est posé qu'après les contrôles
de départ, si bien qu'un refus ne supprime rien ; ensuite, il ne supprime que
ce nom, avec la commande de suppression de chaque outil. Il relève dans
`leftovers.tsv` les réseaux et volumes qu'un outil laisse derrière lui sous ce
nom, puis les retire. Il passe shellcheck et tourne sous le bash 3.2 de macOS.

[BENCH] Après la relecture de [SECU] et [FINOPS], le script a changé sur six
points, sans effet sur le code de mesure : `trap` posé après les contrôles de
départ ; `umask 077` ; registre k3d visé par son nom exact ; `load.tsv` ne
nomme plus que les conteneurs du cluster ; CRD Gateway API téléchargées par
`gh` et vérifiées par SHA-256 avant application ; références des images
tirées par le nœud (`node-images.tsv`) et taille compressée des images
épinglées (`images.tsv`) relevées. Ces changements ont été vérifiés le
2026-11-19 par un test du refus et par une courte exécution sur kind, hors
série ; les mesures du rapport viennent de la version d'avant. Cette
vérification a aussi trouvé et corrigé une régression : avec `umask 077`, la
page de test devenait illisible pour le serveur de l'image.

### 4.4 Résultats

[BENCH] Mesures lancées le 2026-11-19 de 02:52:22 à 03:44:24 UTC, sur la
machine de la section 4.2. Les trois exécutions à chaud servent à la
notation ; l'exécution à froid est en M5.

[BENCH] Un test de fumée a précédé la série, le même jour de 02:13 à 02:33
UTC : une exécution à froid et une à chaud par option, 5 s d'attente avant
les échantillons. Le code de chronométrage n'a pas changé depuis ; les
contrôles fonctionnels de k3d et le relevé des restes ont été ajoutés après.
Ses valeurs à froid sont citées en complément de M5.

| Mesure | Option | Exécution 1 | Exécution 2 | Exécution 3 | Médiane | Écart |
| --- | --- | --- | --- | --- | --- | --- |
| M1 | k3d | 52,9 s | 57,0 s | 67,6 s | 57,0 s | 14,7 s |
| M1 | kind | 26,8 s | 26,5 s | 27,0 s | 26,8 s | 0,5 s |
| M1 | minikube | 35,3 s | 34,1 s | 82,0 s | 35,3 s | 47,9 s |
| M2 | k3d | 681,7 Mio | 697,9 Mio | 662,8 Mio | 681,7 Mio | 35,1 Mio |
| M2 | kind | 627,4 Mio | 599,0 Mio | 602,5 Mio | 602,5 Mio | 28,4 Mio |
| M2 | minikube | 527,9 Mio | 497,2 Mio | 544,6 Mio | 527,9 Mio | 47,4 Mio |
| M3 | k3d | 11,1 % | 12,7 % | 10,6 % | 11,1 % | 2,1 % |
| M3 | kind | 18,4 % | 13,2 % | 14,8 % | 14,8 % | 5,2 % |
| M3 | minikube | 12,1 % | 16,8 % | 14,8 % | 14,8 % | 4,7 % |
| M4 | k3d | 0,6 s | 0,7 s | 0,6 s | 0,6 s | 0,1 s |
| M4 | kind | 0,4 s | 0,4 s | 0,5 s | 0,4 s | 0,1 s |
| M4 | minikube | 2,0 s | 7,0 s | 2,0 s | 2,0 s | 5,0 s |

[BENCH] Exécution à froid (M5) et volume à télécharger (M6), en Mo
compressés. Les tailles viennent du registre : API de Docker Hub [S39],
[S46], [S47], [S65], et pour `k3d-proxy` et `k3d-tools` la somme des couches
et de la configuration lue par `docker manifest inspect -v` le 2026-11-19. La
taille décompressée vient de `docker image inspect`. Les images tirées par le
nœud de k3d n'ont pas de taille compressée relevée : leur borne est la somme
des tailles que le kubelet déclare pour les 9 images du nœud, dont 2 déjà
présentes, soit 170 Mio au plus, c'est-à-dire 179,3 Mo au plus.

| Option | M5, création à froid | Première création, arm64 (poste de mesure) | Première création, amd64 (Linux x86, runners GitHub) | Taille décompressée en cache | Retéléchargé à chaque création, même cache plein |
| --- | --- | --- | --- | --- | --- |
| k3d | 81,0 s (78,5 s au test de fumée) | Entre 121,4 et 300,7 : `rancher/k3s` 81,5, `k3d-proxy` 28,8, `k3d-tools` 11,2, plus les 7 images du nœud, 179,3 au plus | 129,3 (89,3 + 28,9 + 11,2), plus les images du nœud, non relevées | 344,5 (248,1 + 71,9 + 24,5) | 7 images, 179,3 au plus |
| kind | 73,7 s (73,7 s au test de fumée) | 351,7 : `kindest/node` | 384,8 | 908,8 | Aucune |
| minikube | 145,5 s (161,8 s au test de fumée) | 853,3 : `kicbase` 493,4, archive préchargée 324,2, CNI `kindnetd` 35,6 | Au moins 572,0 : `kicbase` 532,3, CNI 39,7, archive amd64 non relevée | 1 312,6, plus l'archive de 324,2 dans `MINIKUBE_HOME` | 1 image, `kindest/kindnetd` par tag, 35,6 |

[BENCH] Le constat qui compte pour R-04 et R-25 : un cache Docker plein ne
suffit pas à k3d ni à minikube. Les événements `Pulled` du cluster, relevés à
chaque exécution, montrent que k3s retélécharge 7 images système dans le nœud
à chaque création, même quand l'image `rancher/k3s` est en cache ; leur
magasin disparaît sans doute avec le conteneur du nœud, explication déduite et
non vérifiée dans la documentation. Ce sont probablement les images de la
liste hors ligne de k3s, toutes désignées par tag, moins busybox [S64] : autre
déduction, puisque la série n'a gardé que leur nombre. Le script relève
désormais leurs références dans `node-images.tsv`. minikube retélécharge une
image à chaque création, `docker.io/kindest/kindnetd:v20260820-69b56db7`, le
CNI qu'il associe à containerd, désigné par tag et absent de son archive
préchargée [S59] ; ce tirage a pris 55,3 s à l'exécution 3, d'où son écart en
M1. kind trouve toutes ses images déjà présentes dans le nœud : aucun
téléchargement à chaud.

[BENCH] Dimensionnement. Relevé à la main pendant l'exécution à froid de
minikube, `docker inspect` donne au conteneur du nœud une limite de
6 396 313 600 octets (6 100 Mio) et de 2 CPU. Pour le cluster fonctionnel à
deux nœuds, `lastStart.txt` (ligne 36) donne `Memory:3072 CPUs:2` par nœud.
minikube calcule lui-même cette limite de mémoire, sans valeur par défaut
écrite [S25]. Aucune limite n'est demandée à kind ni à k3d. Sous macOS, le
plafond réel reste la machine virtuelle du moteur : 11,73 Gio ici, sur 24 Gio
physiques.

[BENCH] Contrôles fonctionnels (M7), sur un cluster à un nœud créé avec des
ports publiés, puis sur un cluster à deux nœuds.

| Contrôle | k3d | kind | minikube |
| --- | --- | --- | --- |
| Port publié vers l'hôte, pour une gateway | Oui par `-p "127.0.0.1:18080:30080@server:0:direct"`. Non par le chemin par défaut, `-p "127.0.0.1:18082:30080@server:0"` : le load balancer nginx de k3d accepte la connexion, aucune réponse en 60 s. Reproduit au test de fumée, et à la main par Traefik sur le port 80 ; le NodePort répond depuis un pod du cluster | Oui, `extraPortMappings` du port 18080 de l'hôte vers le NodePort 30080, avec `listenAddress: "127.0.0.1"` | Oui, `--ports=127.0.0.1:18080:30080` |
| Image locale chargée sans registre | Oui, `k3d image import`, 3,7 s | Oui, `kind load docker-image`, 0,7 s | Oui, `minikube image load`, 2,2 s |
| Registre local | Oui, `--registry-create celian-bench-003-registry` : image poussée par `docker push 127.0.0.1:<port>/…` sans authentification, tirée par un pod. Le registre, `registry:2` désigné par tag [S57], écoute sur toutes les interfaces | Non intégré. Le script de la documentation lance `registry:3` par `docker run`, non exécuté ici (règle du benchmark) [S16] | Oui, `minikube addons enable registry`, prêt en 16,6 s : image poussée sur le port 127.0.0.1 publié par minikube, tirée par un pod sous `localhost:5000/…` |
| Plusieurs nœuds | Oui, `--agents 1`, 2 nœuds prêts en 50,8 s | Oui, configuration control-plane plus worker, 27,2 s | Oui, `--nodes=2`, 44,2 s |
| CRD Gateway API v1.7.0, canal standard | Non sans forcer. k3s préinstalle 8 CRD Gateway API v1.5.1 par Helm, et `kubectl apply --server-side` échoue sur 3 conflits avec le gestionnaire `helm`. Oui avec `--force-conflicts` | Oui, `kubectl apply --server-side -f …/v1.7.0/standard-install.yaml` [S38], CRD Established | Oui, même commande |

[BENCH] Méthode des CRD. Pendant la série, le script appliquait
`standard-install.yaml` depuis l'URL de la release, sans contrôle
d'empreinte, et vérifiait seulement l'annotation de version. Depuis la
relecture de [SECU], il télécharge le fichier par `gh release download` dans le
dossier d'essai, vérifie son SHA-256 (`4e2602c4…53a1`, release immuable avec
attestation [S66]), puis applique la copie locale ; sans `gh` ou si le
condensat diffère, le contrôle passe à « skipped ». Ce chemin a été validé le
2026-11-19 sur kind, hors série.

[BENCH] Adresses d'écoute par défaut (M8), relevées par `docker ps` et, côté
macOS, par `lsof` sur le processus d'OrbStack.

| Élément | k3d | kind | minikube |
| --- | --- | --- | --- |
| API Kubernetes, par défaut | 0.0.0.0, port aléatoire ; côté macOS `*:port`, toutes les interfaces | 127.0.0.1, port aléatoire ; côté macOS `127.0.0.1:port` | 127.0.0.1, port aléatoire ; côté macOS `127.0.0.1:port` |
| Autres ports publiés par défaut | Aucun | Aucun | SSH (22), démon Docker du nœud (2376), registre (5000) et 32443, tous sur 127.0.0.1 |
| Port publié sans adresse | 0.0.0.0 et `[::]` ; côté macOS `*:18081` | 0.0.0.0 ; côté macOS `*:18081` | 0.0.0.0 et `[::]` ; côté macOS `*:18081` |
| Registre | 0.0.0.0, port aléatoire ; côté macOS `*:59292` | Pas de registre intégré | 127.0.0.1, port 5000 du nœud |
| Restriction essayée | `--api-port 127.0.0.1:16443` et `-p 127.0.0.1:…` : 127.0.0.1 constaté | `listenAddress: "127.0.0.1"` : 127.0.0.1 constaté | `--ports=127.0.0.1:…` : 127.0.0.1 constaté |
| Restriction documentée, non essayée | Registre : `--registry-create NOM:127.0.0.1:PORT`, d'après le format `NAME[:HOST][:HOSTPORT]` de l'aide | `networking.apiServerAddress`, déjà à 127.0.0.1 [S15] | `--listen-address` pour les ports internes [S25], [S30] |

[BENCH] Restes après suppression. minikube laisse son réseau Docker
`celian-bench-003` après la suppression du cluster à deux nœuds, au test de
fumée comme dans la série, alors que sa sortie annonce « Removed all traces ».
Le script l'a relevé dans `leftovers.tsv` puis retiré. Aucun autre reste : la
liste des volumes est identique avant et après la série.

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

### 5.1 Licence et liberté d'usage, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| k3d | 5/5 | 15 | MIT pour k3d, Apache-2.0 pour k3s, deux licences permissives approuvées par l'OSI. Le projet généré n'embarque pas l'outil : il le demande en prérequis | [S1], [S8], [S33] |
| kind | 5/5 | 15 | Apache-2.0, approuvée par l'OSI. Même remarque sur le projet généré | [S10], [S33] |
| minikube | 5/5 | 15 | Apache-2.0, approuvée par l'OSI. Même remarque sur le projet généré | [S19], [S33] |

[BENCH] Le critère ne départage pas : trois licences permissives, compatibles
avec l'Apache-2.0 du générateur.

### 5.2 Gouvernance (fondation, multi-vendeurs), poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| k3d | 2/5 | 6 | Organisation communautaire k3d-io, sans fondation, qui se dit « not an official Rancher (SUSE) product ». Un seul mainteneur crédité ; 11 commits humains par 6 auteurs en 12 mois. k3s est au bac à sable de la CNCF depuis 2020, mais k3d n'en fait pas partie | [S1], [S3], [S9], [S48] |
| kind | 4/5 | 12 | Sous-projet de SIG Testing, donc de Kubernetes, gradué à la CNCF. Trois approbateurs, de deux employeurs déclarés (Google, Lambda), tous actifs dans l'année. Réserve : le premier auteur fait 56 % des commits humains et les deux premiers 72 % ; sur les PR fusionnées, le premier pèse 34 % | [S10], [S13], [S18], [S32], [S48], [S52], [S54] |
| minikube | 4/5 | 12 | Sous-projet de SIG Cluster Lifecycle, donc de Kubernetes. Base plus large, 99 auteurs humains en 12 mois. Réserve : les deux premiers auteurs font 68 % des commits humains, et 396 des 557 commits de fusion sont faits à la main par deux personnes ; sur les PR fusionnées, le premier pèse 35 %. Quatre approbateurs, deux employeurs déclarés (IBM, Databricks), deux sans employeur, un sans commit ni PR en 12 mois | [S19], [S22], [S23], [S32], [S48], [S53], [S55], [S56] |

[BENCH] Note de minikube ramenée de 5 à 4 après la relecture de [SECU], qui a
appliqué la même mesure aux deux projets, commits de fusion compris : mesurés
ainsi, kind et minikube se valent (section 10).

### 5.3 Maturité et adoption, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| k3d | 4/5 | 12 | Créé en 2019, version majeure 5 depuis septembre 2021. Le plus installé des trois par Homebrew sur 365 jours (103 004). Réserve : aucune liste d'adoptants tenue par k3d, et des installations ne disent rien de l'usage réel | [S1], [S36] |
| kind | 4/5 | 12 | Créé en 2018, conçu d'abord pour tester Kubernetes lui-même ; 58 642 installations Homebrew sur 365 jours. Réserve : toujours en 0.x, « still a work in progress » selon son propre site, et l'usage en développement vient en second dans sa raison d'être | [S10], [S14], [S36] |
| minikube | 5/5 | 15 | Créé en 2016, le plus ancien des trois, en version 1.39 ; sous-projet dont l'objet déclaré est le développement d'applications ; 55 350 installations Homebrew sur 365 jours | [S19], [S23], [S36] |

### 5.4 Activité et maintenance, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| k3d | 2/5 | 4 | Une seule release en 12 mois (5.9.0, le 2026-06-02), 11 commits humains, dernier commit le 2026-10-18. Sans release au 2027-06-02, il tomberait sous le critère éliminatoire | [S2], [S3] |
| kind | 5/5 | 10 | Trois releases en 12 mois, 172 commits humains par 31 auteurs, dernier commit le 2026-11-18 | [S11], [S13] |
| minikube | 5/5 | 10 | Trois releases en 12 mois, 1 296 commits humains par 99 auteurs, dernier commit le 2026-11-18 | [S20], [S22] |

### 5.5 Sécurité (CVE, réactivité), poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| k3d | 2/5 | 4 | Par défaut, l'API écoute sur 0.0.0.0, et côté macOS sur toutes les interfaces (`*:port`) ; les ports publiés sans adresse aussi. Le registre, sur toutes les interfaces lui aussi, accepte un `docker push` sans authentification : une machine du même réseau peut y déposer une image que le cluster exécutera. Images d'appoint (`k3d-proxy`, `k3d-tools`, `registry:2`) et images système de k3s désignées par tag. Aucune politique de sécurité ni signalement privé pour k3d, aucun avis publié ; les failles de k3s (trois avis en base, le dernier en 2026) passent par k3s. Contournement : `--api-port 127.0.0.1:PORT`, `-p 127.0.0.1:…`, `--registry-create NOM:127.0.0.1:PORT` (aide de `k3d cluster create`), images remplaçables par `K3D_IMAGE_LOADBALANCER` et `K3D_IMAGE_TOOLS` | [M7], [M8], [S1], [S34], [S35], [S41], [S57], [S64] |
| kind | 4/5 | 8 | API sur 127.0.0.1 par défaut, avec un avertissement écrit contre toute autre exposition ; aucun autre port publié. Image de nœud exigée par condensat, rien de tiré à la création : tout le contenu du nœud est figé. Processus de sécurité de Kubernetes (accusé de réception sous 3 jours ouvrés), aucun avis publié pour kind. Réserve : un `extraPortMappings` sans `listenAddress` écoute sur 0.0.0.0, comme la documentation l'annonce | [M6], [M8], [S10], [S12], [S15], [S31], [S34] |
| minikube | 3/5 | 6 | API, SSH, port 2376 du démon Docker et registre en boucle locale par défaut ; processus de sécurité de Kubernetes ; un avis publié, CVE-2018-1002103 (élevé), qui date de 2018. Mais l'intégrité de ce qui s'exécute n'est pas garantie : kindnetd est tiré par tag à chaque création et tourne sur le réseau de l'hôte avec `NET_ADMIN` et `NET_RAW` ; la somme de contrôle de l'archive préchargée vient de la même origine que l'archive, et le téléchargement continue si elle manque ; la clé client du démon Docker du nœud est recopiée en mode 0777 dans `MINIKUBE_HOME`, sans usage sous containerd d'après le source. Réserve aussi : `--ports` sans adresse écoute sur 0.0.0.0 | [M8], [S19], [S29], [S30], [S31], [S34], [S58], [S59], [S60], [S61], [S62] |

[BENCH] Pourquoi le tirage de kindnetd compte en 5.5 comme en 5.6, selon
l'arbitrage du DSI : ce sont deux effets distincts du même choix. L'empreinte
(5.6) compte la disponibilité et le temps : il faut le réseau, et un registre
qui répond dans sa limite de débit. La sécurité (5.5) compte l'intégrité de
ce qui s'exécute : avec `NET_ADMIN` sur le réseau de l'hôte tourne ce que le
registre sert ce jour-là pour ce tag, sans condensat, et l'archive préchargée
se vérifie contre une somme prise à la même origine, avec une clé laissée en
0777 à côté. Ce n'est pas un double compte. Si Lucas juge le contraire,
minikube garde 4 en sécurité (section 7).

[BENCH] Aucun des trois outils ne signe ses binaires ni ne publie
d'attestation, et aucune de leurs releases n'est immuable : la somme de
contrôle publiée dans la même release protège contre la corruption, pas
contre la substitution [S66], [S67]. Ce point ne départage pas les options.

### 5.6 Empreinte sur PC (RAM, CPU, démarrage), poids 10

[BENCH] Règle appliquée : proposée par [FINOPS], recommandée par le DSI, à
valider par Lucas. Elle remplace la règle de la première version de ce
rapport, qui comparait chaque option à la meilleure ; celle-ci et ses notes
restent dans la section 7, au titre de la sensibilité. Les deux règles ont
été posées après lecture des chiffres, et ni [BENCH] ni [FINOPS] ne peut
prétendre le contraire. Pour limiter le biais, aucun seuil de la règle
retenue ne vient des options : chacun est une valeur ronde tirée du PRD
(budget de 900 s d'ENF-01, portable de 8 Gio) ou d'un débit bas pris comme
hypothèse, 10 Mbit/s. Chaque option part de 5 et perd un cran par condition
remplie :

1. le volume compressé de la première création dépasse 500 Mo, images de
   l'outil, archives et images tirées par le nœud comprises (400 s à
   10 Mbit/s, soit 44 % du budget) ;
2. au moins une image se retélécharge à chaque création, même avec le cache
   Docker plein ;
3. la création à chaud (médiane de M1) dépasse 90 s, soit 10 % du budget ;
4. la mémoire au repos (médiane de M2) dépasse 1 Gio, un huitième d'un
   portable de 8 Gio.

[BENCH] Aucune option n'est à moins de 10 % d'un seuil. kind est 30 % sous le
seuil de volume en arm64 (351,7 Mo) et 23 % en amd64 (384,8 Mo) ; minikube
est 71 % au-dessus en arm64 (853,3 Mo) et au moins 14 % en amd64 ; k3d reste
sous le seuil même avec son majorant (300,7 Mo en arm64), et 37 % sous le
seuil de M1.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| k3d | 4/5 | 8 | Une condition remplie : 7 images retéléchargées à chaque création, d'où un écart de 14,7 s entre exécutions. Volume de la première création entre 121,4 et 300,7 Mo, M1 à 57,0 s et M2 à 681,7 Mio, tous sous leurs seuils ; CPU au repos le plus bas (11,1 % d'un cœur) ; froid en 81,0 s | [M1], [M2], [M3], [M5], [M6], [S39] |
| kind | 5/5 | 10 | Aucune condition remplie : 351,7 Mo à la première création, rien de retéléchargé, 26,8 s à chaud, 602,5 Mio au repos. Le plus rapide à chaud et à froid (73,7 s) | [M1], [M2], [M3], [M5], [M6], [S46] |
| minikube | 3/5 | 6 | Deux conditions remplies : 853,3 Mo à la première création, CNI compris, et l'image du CNI retéléchargée à chaque création. M1 à 35,3 s et M2 à 527,9 Mio, la plus basse des trois, sous leurs seuils ; froid en 145,5 s | [M1], [M2], [M3], [M5], [M6], [S47], [S65] |

### 5.7 Portabilité multi-cloud, poids 10

[BENCH] Le cluster local ne tourne que sur le PC ; la cible GCP passe par
GKE. Le critère porte donc sur deux points : les systèmes du poste (Q5), et
l'écart entre le cluster local et un Kubernetes amont comme GKE, qui oblige
sinon le blueprint à porter du code propre au PC (principe II, ENF-02).

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| k3d | 3/5 | 6 | Linux, macOS et Windows, Docker exigé. k3s se dit conforme, mais embarque par défaut Traefik, Klipper-lb, local-path et sqlite, et installe déjà les CRD Gateway API v1.5.1, gérées par Helm : l'installation standard de v1.7.0 échoue sur trois conflits [M7]. Pour la parité avec GKE, le blueprint devra désactiver ces composants (`--disable=traefik`), effet sur les CRD à vérifier par [OPS] | [M7], [S4], [S8], [S44] |
| kind | 5/5 | 10 | Linux, macOS et Windows, avec Docker, Podman ou nerdctl. Nœuds montés par kubeadm, sans composant ajouté qui gêne le blueprint : aucune CRD Gateway API préinstallée, installation standard de v1.7.0 sans conflit | [M7], [S17], [S49] |
| minikube | 5/5 | 10 | Linux, macOS et Windows, avec Docker, Podman ou une VM (QEMU, Hyper-V, KVM, VirtualBox), ce qui laisse une voie sans Docker. Deux extensions actives par défaut (`storage-provisioner`, `default-storageclass`), aucune CRD Gateway API préinstallée, installation standard de v1.7.0 sans conflit | [M7], [S27] |

### 5.8 Expérience dev et documentation, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| k3d | 2/5 | 4 | Une commande crée cluster et registre ; `k3d image import` charge une image locale en 3,7 s. Mais le chemin de port par défaut, par le load balancer nginx de k3d, accepte la connexion TCP sans jamais répondre sur ce poste, même par Traefik sur le port 80 (essai manuel) ; seul le suffixe `:direct`, absent de la documentation, fonctionne. Pages de référence datées de 2023, mention de copyright arrêtée en 2023 | [M7], [S4], [S6], [S7], [S42] |
| kind | 4/5 | 8 | Configuration déclarative en YAML, image locale chargée en 0,7 s, port publié du premier coup, deux nœuds prêts en 27,2 s, suppression en 0,4 s. Réserve : pas de registre intégré, le script officiel lance un conteneur de plus par `docker run` ; ports fixés à la création | [M4], [M7], [S15], [S16], [S17] |
| minikube | 4/5 | 8 | Tous les contrôles passent, registre compris : l'extension `registry` reçoit l'image poussée sur le port 127.0.0.1 publié par minikube, sans le conteneur socat de la documentation. Réserves : suppression en 2,0 à 7,0 s ; limite de 2 CPU posée par défaut, à relever par profil ; `--ports` appliqué à chaque nœud, ce qui empêche en principe un port fixe sur plusieurs nœuds (lu dans le source, non essayé) | [M4], [M7], [S25], [S26], [S29] |

### 5.9 Coût (managé ou opérationnel), poids 5

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| k3d | 5/5 | 5 | Aucune licence ni service payant : un binaire sur le poste. Le coût réel est le temps et la mémoire du poste, notés en 5.6, plus au plus 170 Mio retéléchargés à chaque création : c'est la somme que le kubelet déclare pour les 9 images du nœud, dont 2 déjà présentes, un majorant ; le transfert réel n'est pas mesuré | [S1], [M6] |
| kind | 5/5 | 5 | Aucune licence ni service payant : un binaire sur le poste | [S10] |
| minikube | 5/5 | 5 | Aucune licence ni service payant : un binaire sur le poste | [S19] |

[BENCH] Le critère ne départage pas. [FINOPS] confirme 5/5 pour les trois : sur
une ligne illimitée, le trafic de chaque création ne coûte rien de plus, et
son effet en temps et en disponibilité est déjà compté en 5.6 (section 10).
Le seul coût de licence possible sur le PC est le moteur de conteneurs, hors
du champ de ce benchmark (R-26).

## 6. Grille pondérée

| Critère | Poids | k3d | kind | minikube |
| --- | --- | --- | --- | --- |
| Critères éliminatoires (section 3) | éliminatoire | passe | passe | passe |
| Licence et liberté d'usage | 15 | 5/5, 15 pts | 5/5, 15 pts | 5/5, 15 pts |
| Gouvernance (fondation, multi-vendeurs) | 15 | 2/5, 6 pts | 4/5, 12 pts | 4/5, 12 pts |
| Maturité et adoption | 15 | 4/5, 12 pts | 4/5, 12 pts | 5/5, 15 pts |
| Activité et maintenance | 10 | 2/5, 4 pts | 5/5, 10 pts | 5/5, 10 pts |
| Sécurité (CVE, réactivité) | 10 | 2/5, 4 pts | 4/5, 8 pts | 3/5, 6 pts |
| Empreinte sur PC (RAM, CPU, démarrage) | 10 | 4/5, 8 pts | 5/5, 10 pts | 3/5, 6 pts |
| Portabilité multi-cloud | 10 | 3/5, 6 pts | 5/5, 10 pts | 5/5, 10 pts |
| Expérience dev et documentation | 10 | 2/5, 4 pts | 4/5, 8 pts | 4/5, 8 pts |
| Coût (managé ou opérationnel) | 5 | 5/5, 5 pts | 5/5, 5 pts | 5/5, 5 pts |
| Total | 100 | 64 / 100 | 90 / 100 | 87 / 100 |

## 7. Verdict proposé

[BENCH] Option proposée : kind, 90 sur 100. minikube suit à 87, soit 3 points
derrière, et k3d, l'option pressentie, finit à 64. Ce classement suppose la
règle d'empreinte de [FINOPS], recommandée par le DSI et soumise à Lucas.

[BENCH] Pourquoi. kind et minikube partagent l'essentiel : sous-projets de
Kubernetes, gradué à la CNCF [S18], [S23], [S32], licence Apache-2.0, API en
boucle locale par défaut [M8], presque tous les contrôles réussis [M7], et la
même gouvernance une fois mesurés de la même façon [S13], [S22], [S52] à
[S56]. kind l'emporte sur l'empreinte : rien de retéléchargé à la création,
351,7 Mo à la première création contre 853,3 [M6]. Il l'emporte aussi sur la
sécurité : nœud figé par condensat, aucune image tirée par tag au démarrage
[S12], [M6]. minikube garde l'avantage sur la maturité, une version 1.x dont
l'objet déclaré est le développement d'applications [S23], et sur le registre
intégré [M7]. k3d perd sur la gouvernance et l'activité (une organisation
communautaire, une release en douze mois) [S1], [S2], [S3], sur la sécurité
(API et registre ouverts sur toutes les interfaces, registre sans
authentification) [M7], [M8], sur l'expérience (chemin de port par défaut sans
réponse sur ce poste) et sur la parité avec GKE (CRD Gateway API v1.5.1
préinstallées, en conflit avec la v1.7.0) [M7].

[BENCH] Sensibilité. Le classement de tête dépend de la règle d'empreinte et
de notes de jugement : la gouvernance et la sécurité de minikube, la maturité
de kind.

- Ancienne règle de [BENCH] (un cran par mesure au-delà du double de la
  meilleure option, un cran pour la dépendance au réseau) : empreinte de k3d
  à 3, de kind à 5, de minikube à 4. Totaux : k3d 62, kind 90, minikube 89.
- Si Lucas garde l'ancienne règle et qu'on compte le tirage de kindnetd une
  seule fois, en empreinte et non en sécurité (minikube à 4 en sécurité),
  minikube remonte à 91 contre 90 pour kind et repasse devant.
- Avec la règle de [FINOPS], minikube à 4 en sécurité seul donne 89 ; un
  cran de gouvernance pour minikube (retour à 5, la note de la première
  version) donne l'égalité à 90 ; les deux ensemble, 92 contre 90.
- kind à 5 en maturité, s'il sortait en 1.0, monterait à 93.
- k3d reste dernier dans tous les cas, à 26 points de kind au moins.

[BENCH] La grille ne suffit donc pas à départager kind et minikube : l'écart
tient dans un ou deux crans. Critères écrits hors grille, qui vont tous dans
le sens de kind, à reprendre dans l'ADR :

- rien n'est téléchargé à la création : aucun tirage à chaud dans M6, donc
  un cluster qui doit se recréer sans réseau une fois l'image de nœud en
  cache, ce qui reste à essayer hors ligne (R-25) [M6] ;
- le nœud est entièrement figé par condensat [S12] ;
- la première création est 2,4 fois plus légère (351,7 contre 853,3 Mo) [M6] ;
- la configuration est déclarative, en YAML versionnable dans le projet
  généré [S15] ;
- seule l'API est exposée, en boucle locale [M8] ;
- Podman est documenté, ce qui ouvre une voie sans moteur payant (R-26)
  [S17].

[BENCH] Réserves de kind, à écrire aussi dans l'ADR :

- version 0.x, « still a work in progress » selon son propre site [S14] ;
- aucune limite de ressources par nœud dans la configuration documentée
  [S15] : les profils lite, standard et full de US-005 ne peuvent pas brider
  le cluster, et le README du projet généré devra donner la mémoire minimale
  de la machine virtuelle du moteur pour chaque profil ;
- pas de registre intégré : si BENCH-005 en a besoin, il faudra le monter
  [S16] ;
- un mainteneur porte 56 % des commits humains [S13].

[BENCH] Réserves à surveiller, quel que soit l'outil :

- un port publié sans adresse écoute sur toutes les interfaces, avec les
  trois outils [M8] : le blueprint met 127.0.0.1 sur chaque port (R-20) ;
- dimensionnement : sous macOS, le plafond réel est la machine virtuelle du
  moteur (11,73 Gio ici), et le choix du profil lit la mémoire donnée par
  `docker info`. Si minikube était retenu, ses limites calculées (6 100 Mio
  pour un nœud, `Memory:3072` par nœud à deux nœuds, 2 CPU) imposent de
  passer `--cpus` et `--memory` explicitement dans chaque profil [S25] ;
- un passage de kind en 1.0, une nouvelle release de k3d ou un kindnetd figé
  par condensat dans minikube rouvriraient la comparaison. Prochaine
  vérification proposée : 2027-05-19.

[BENCH] Suites :

- l'ADR du cluster local, écrit par [ARCHI] : il tranche entre les deux règles
  d'empreinte, et la règle retenue par Lucas entre dans `TEMPLATE.md` avant
  BENCH-005, pour être fixée avant les chiffres la prochaine fois. Il fixe
  aussi la politique de version de Kubernetes (v1.36.4 alignée ici, v1.37.0
  par défaut dans kind 0.33.0 [S12]) ;
- une entrée de `catalog/` pour l'outil de la cible PC, si l'ADR suit ce
  verdict : kind 0.33.0, Apache-2.0, sous-projet de SIG Testing (Kubernetes,
  CNCF), actif, vérifié le 2026-11-19, sources [S10], [S11], [S18], avec le
  condensat du binaire darwin-arm64
  `0c8c7dbe5e23594a198b786c4bc13dacc101fa6196b0cb0b23a1ca44e61f4b4f` [S66] ;
- la constitution (périmètre du MVP, « PC sous k3d »), `CLAUDE.md`,
  `docs/vision.md`, `docs/prd-mvp.md` et les fiches des agents `bench`, `ops`
  et `qa` nomment k3d. Si l'ADR retient un autre outil, amender la
  constitution revient à Lucas ;
- exigences de [SECU] pour le blueprint : `task up` vérifie la version exacte
  de l'outil et refuse de démarrer si elle diffère ; l'image de nœud et les
  images du blueprint sont figées par condensat, Renovate les met à jour avec
  le délai de 7 jours ; aucune image n'est tirée par tag à la création du
  cluster (préchargement, archive hors ligne ou miroir) ; les manifests tiers,
  comme les CRD Gateway API, sont versionnés dans le projet avec leur
  SHA-256, jamais de `kubectl apply -f https://` dans `task up` ; 127.0.0.1
  sur l'API et sur chaque port publié, contrôlé par un test de la matrice
  (R-20) ; la procédure d'installation vérifie le SHA-256 de l'outil contre
  la valeur du catalogue de CELIAN, pas seulement contre le fichier publié
  dans la même release ;
- un miroir ou une archive d'images publiés par CELIAN, piste de R-04 et
  R-25, serait une redistribution : les licences du contenu des images sont à
  relire avant, selon [SECU] ;
- suite possible, qui revient à Lucas : signaler la clé client recopiée en
  0777 par minikube 1.39.0 [S58] au processus de sécurité de Kubernetes
  [S31], plutôt que par une issue publique. [BENCH] ne l'a pas fait ;
- côté risques, le DSI a déjà repris R-04, R-20, R-25 et R-26 dans
  `docs/risques.md`. Volumes de la première création : 352 à 853 Mo
  compressés en arm64. Pour un projet généré privé, la création du cluster
  consomme des minutes de CI à chaque job, toujours à froid [S73], [S76] : le
  README du projet généré doit le dire, puisque R-16 ne couvre que le dépôt
  de CELIAN.

## 8. Limites et biais

| Limite | Effet possible sur le verdict | Ce qui la lèverait |
| --- | --- | --- |
| Une seule machine, sous macOS, avec OrbStack, moteur non libre (R-26) | Empreinte propre à ce poste. Le défaut de port de k3d par son load balancer peut venir de la combinaison avec OrbStack : cause non établie | Relancer le script sous Linux avec Docker Engine, et sous Docker Desktop |
| Une seule exécution à froid par option dans la série officielle, sur le réseau du poste | M5 dépend du débit et de Docker Hub. Le test de fumée donne une seconde valeur (78,5, 73,7 et 161,8 s). Le volume (M6), lui, ne dépend ni de la ligne ni du moment | Plusieurs exécutions à froid, sur un autre réseau et sur un runner amd64 |
| Mémoire variable d'une session à l'autre : kind à 516,0 Mio au test de fumée, 602,5 Mio en série | Classement de M2 entre kind et minikube fragile ; sans effet sur les notes, toutes sous le seuil de 1 Gio | Répéter les séries à d'autres moments, en alternant les options |
| Charge du poste : applications de bureau ouvertes, charge moyenne entre 3,30 et 5,78 | Bruit sur M1 à M3 | Relancer sur un poste dédié |
| Limites de ressources différentes : minikube se borne à 2 CPU et 6 100 Mio pour un nœud (`Memory:3072` par nœud à deux nœuds), rien n'est demandé à kind ni à k3d | CPU et mémoire au repos pas tout à fait comparables, minikube pourrait ralentir sous charge | Mesurer avec des limites identiques, puis avec la stack du blueprint (BENCH-005) |
| Configuration par défaut de chaque outil : Traefik, servicelb et metrics-server pour k3d, rien de tel pour kind | L'empreinte de k3d baisserait sans ces composants, que le blueprint désactiverait | Mesurer la configuration retenue par le blueprint |
| Mesure au repos seulement, cluster seul | Ne dit rien de la tenue sous la charge du projet, ni de la tenue sur 8 Gio | Mesurer `task up` sur le golden repo de la phase 2 et en BENCH-005 |
| Deux règles de notation de l'empreinte, posées l'une et l'autre après lecture des chiffres | Le classement de tête change selon la règle retenue (section 7) | Décision de Lucas dans l'ADR ; la règle retenue entre dans `TEMPLATE.md` avant BENCH-005 |
| Option pressentie par le PRD | Biais possible en faveur de k3d ; le résultat va à l'inverse | Même script et mêmes sources pour les trois options |
| Notes de jugement : gouvernance et maturité de kind et de minikube, sécurité de minikube | Le verdict de tête repose sur elles (section 7) | Relectures de [SECU] et [FINOPS] faites ; avis de Lucas dans l'ADR |
| Gouvernance mesurée par les identifiants des commits, robots filtrés par leur nom ; employeurs déclaratifs | Un compte multiple ou un profil faux fausserait les parts | Relire la liste des auteurs à la main |
| Installations Homebrew comme indice d'adoption ; intégrité de l'installation par Homebrew non évaluée | Ne mesure pas l'usage réel ; binaires installés sans vérification contre le catalogue | Une liste d'adoptants tenue par chaque projet ; vérifier le SHA-256 des binaires contre [S66] |
| Aucune image de nœud scannée (`kicbase`, `kindest/node`, `rancher/k3s`) | Des CVE dans le contenu des nœuds échappent à la note de sécurité | Un scan Trivy de chaque image de nœud, à confier à [SECU] |
| Condensat de `rancher/k3s` vérifié après usage seulement ; ceux de `k3d-proxy`, `k3d-tools` et `registry:2` jamais vérifiés | L'intégrité de ce qui a tourné pour k3d n'est pas prouvée | Vérifier avant la création, ou figer ces images par `K3D_IMAGE_LOADBALANCER` et `K3D_IMAGE_TOOLS` [S57] |
| Exposition réseau pendant l'exécution : pendant quelques minutes, l'API de k3d, son registre ouvert en écriture et le port 18081 ont écouté sur toutes les interfaces du poste | Une machine du même réseau aurait pu joindre l'API ou pousser une image dans le registre | Lancer le script sur un réseau de confiance, consigne désormais écrite en tête du script |
| CRD Gateway API appliquées depuis l'URL de la release pendant la série, sans contrôle d'empreinte | Contenu vérifié par son annotation de version seulement | Fait depuis : téléchargement par `gh` et SHA-256 vérifié avant application, validé sur kind le 2026-11-19 |
| Références des images tirées par le nœud non gardées pendant la série | Les 7 images de k3s ne sont identifiées que par déduction [S64] | Fait depuis : le script les relève dans `node-images.tsv` ; relancer la série k3d |
| Kubernetes v1.36.4, ni le dernier correctif 1.36.5 ni la v1.37.0 par défaut de kind et minikube | Écarts de temps possibles avec les versions par défaut | Relancer avec la version que fixera l'ADR |
| Effets de bord hors du dossier d'essai | Les images épinglées restent dans le cache Docker (environ 2,6 Go, `registry:2` compris) ; la couche `busybox` reste dans le cache de construction. Les journaux bruts contiennent le chemin absolu du poste | Retirer ces images par leur référence exacte après décision ; nettoyer les journaux s'ils sont un jour versionnés |

## 9. Sources

[BENCH] Les dates de release, les comptes d'activité et les métadonnées des
dépôts viennent de l'API publique de GitHub, lue le 2026-11-19. Un commit est
compté humain quand son auteur n'est pas un robot (`bot`, `renovate`,
`dependabot`, `github-actions`, `k8s-ci-robot` filtrés par leur nom).

[BENCH] Les sources S50 à S72 viennent de la relecture de [SECU], F1 à F11
de celle de [FINOPS], toutes lues le 2026-11-19. Une URL garde un seul
identifiant : S50 et S51 de [SECU] reprenaient les URL de [S13] et [S22], qui
reçoivent leurs relevés, et ces deux numéros ne sont pas réattribués. Côté
[FINOPS], F5 devient [S70], F6 [S65], F7 [S46], F8 [S47], F9 [S39] et F10
[S25] ; F1 à F4 deviennent [S73] à [S76], et F11 [S77].

| ID | URL | Lue le | Ce que la source établit | Officielle |
| --- | --- | --- | --- | --- |
| S1 | <https://github.com/k3d-io/k3d> | 2026-11-19 | Licence MIT, dépôt non archivé, créé le 2019-04-02 ; « community-driven project but it's not an official Rancher (SUSE) product » ; Thorsten Klein (`iwilltry42`) crédité pour la maintenance ; aucun fichier de politique de sécurité | Oui |
| S2 | <https://api.github.com/repos/k3d-io/k3d/releases> | 2026-11-19 | 5.9.0 le 2026-06-02, seule release stable depuis le 2025-11-19 ; 5.9.0-rc.0 le 2025-10-01 ; 5.8.3 le 2025-02-15 | Oui |
| S3 | <https://api.github.com/repos/k3d-io/k3d/commits?since=2025-11-19T00:00:00Z> | 2026-11-19 | 17 commits sur 12 mois, dont 11 humains, par 6 auteurs ; dernier commit le 2026-10-18 | Oui |
| S4 | <https://k3d.io/stable/> | 2026-11-19 | Docker 20.10.5 ou plus récent exigé ; installation sous Linux, macOS et Windows ; pied de page « Copyright © 2020-2023 k3d Authors » | Oui |
| S5 | <https://k3d.io/stable/usage/registries/> | 2026-11-19 | `--registry-create` crée le registre avec le cluster ; port publié sur un port aléatoire de l'hôte ; adresse d'écoute non documentée | Oui |
| S6 | <https://k3d.io/stable/usage/exposing_services/> | 2026-11-19 | Syntaxe `-p` par le load balancer ou vers un NodePort ; adresse d'écoute par défaut non documentée | Oui |
| S7 | <https://k3d.io/stable/usage/commands/k3d_cluster_create/> | 2026-11-19 | `--api-port [HOST:]HOSTPORT`, sans défaut documenté ; page datée du 2023-06-30 | Oui |
| S8 | <https://github.com/k3s-io/k3s> | 2026-11-19 | Apache-2.0 ; « fully conformant production-ready Kubernetes distribution » ; embarque containerd, Flannel, CoreDNS, Traefik, Klipper-lb, local-path-provisioner, sqlite3 par défaut | Oui |
| S9 | <https://www.cncf.io/projects/k3s/> | 2026-11-19 | k3s accepté à la CNCF le 2020-08-19, niveau Sandbox | Oui |
| S10 | <https://github.com/kubernetes-sigs/kind> | 2026-11-19 | Apache-2.0, dépôt non archivé, créé le 2018-09-12 ; fichier `OWNERS` : approbateurs `aojea`, `BenTheElder`, `stmcginnis` ; fichier `SECURITY_CONTACTS` | Oui |
| S11 | <https://api.github.com/repos/kubernetes-sigs/kind/releases> | 2026-11-19 | 0.33.0 le 2026-08-26, 0.32.0 le 2026-06-02, 0.31.0 le 2025-12-18 | Oui |
| S12 | <https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0> | 2026-11-19 | Kubernetes 1.37.0 par défaut ; image `kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed` ; le digest est obligatoire | Oui |
| S13 | <https://api.github.com/repos/kubernetes-sigs/kind/commits?since=2025-11-19T00:00:00Z> | 2026-11-19 | 283 commits sur 12 mois, dont 172 humains, par 31 auteurs ; 96 de `BenTheElder` ; dernier commit le 2026-11-18. Mesure de [SECU] : deux premiers auteurs à 72,1 % ; 104 commits de fusion, dont 92 par Prow ; sans eux, 160 commits, premier auteur à 55,6 %, deux premiers à 70,6 % | Oui |
| S14 | <https://kind.sigs.k8s.io/> | 2026-11-19 | « primarily designed for testing Kubernetes itself, but may be used for local development or CI » ; « still a work in progress, see the 1.0 roadmap » | Oui |
| S15 | <https://kind.sigs.k8s.io/docs/user/configuration/> | 2026-11-19 | API sur 127.0.0.1 par défaut, avec l'avertissement « We strongly discourage exposing kind to anything other than loopback » ; `listenAddress` de `extraPortMappings` à 0.0.0.0 par défaut ; cluster à plusieurs nœuds par configuration | Oui |
| S16 | <https://kind.sigs.k8s.io/docs/user/local-registry/> | 2026-11-19 | Pas de registre intégré : un script lance `registry:3` par `docker run`, publié sur 127.0.0.1 | Oui |
| S17 | <https://kind.sigs.k8s.io/docs/user/quick-start/> | 2026-11-19 | `kind load docker-image`, `--kubeconfig`, `KUBECONFIG` respecté ; installation sous Linux, macOS, Windows ; Docker, Podman et nerdctl | Oui |
| S18 | <https://github.com/kubernetes/community/blob/master/sig-testing/README.md> | 2026-11-19 | kind est un sous-projet de SIG Testing | Oui |
| S19 | <https://github.com/kubernetes/minikube> | 2026-11-19 | Apache-2.0, dépôt non archivé, créé le 2016-04-15 ; fichier `OWNERS` : approbateurs `medyagh`, `prezha`, `comradeprogrammer`, `nirs` ; `SECURITY.md` qui renvoie au processus de Kubernetes | Oui |
| S20 | <https://api.github.com/repos/kubernetes/minikube/releases> | 2026-11-19 | 1.39.0 le 2026-09-02, 1.38.1 le 2026-02-19, 1.38.0 le 2026-01-29 | Oui |
| S21 | <https://github.com/kubernetes/minikube/releases/tag/v1.39.0> | 2026-11-19 | Kubernetes v1.37.0 par défaut, prise en charge de 1.36 et 1.37, kicbase v0.0.51 | Oui |
| S22 | <https://api.github.com/repos/kubernetes/minikube/commits?since=2025-11-19T00:00:00Z> | 2026-11-19 | 2 160 commits sur 12 mois, dont 1 296 humains, par 99 auteurs ; 473 de `medyagh`, 413 de `nirs` ; dernier commit le 2026-11-18. Mesure de [SECU] : premier auteur à 36,6 %, deux premiers à 68,5 % ; 396 commits « Merge pull request » sur 557 commits de fusion, dont 246 de `nirs` et 150 de `medyagh` ; sans les commits de fusion, 890 commits, 35,8 % et 54,6 % ; 2 commits de `copilot-swe-agent[bot]` | Oui |
| S23 | <https://github.com/kubernetes/community/blob/master/sig-cluster-lifecycle/README.md> | 2026-11-19 | minikube est un sous-projet de SIG Cluster Lifecycle, « for application development on macOS, Linux, and Windows » | Oui |
| S24 | <https://minikube.sigs.k8s.io/docs/handbook/config/> | 2026-11-19 | `MINIKUBE_HOME` fixe le dossier d'état ; `--kubernetes-version` | Oui |
| S25 | <https://minikube.sigs.k8s.io/docs/commands/start/> | 2026-11-19 | Options `--listen-address`, `--ports`, `--nodes`, `--cpus` (2 par défaut), `--memory`, `--wait` ; `--cpus` accepte `max` et `no-limit` (Docker et Podman seulement), `--memory` n'a pas de valeur par défaut écrite | Oui |
| S26 | <https://minikube.sigs.k8s.io/docs/handbook/registry/> | 2026-11-19 | Extension `registry` ; sous macOS, la doc pousse par un conteneur socat lancé par `docker run` | Oui |
| S27 | <https://minikube.sigs.k8s.io/docs/start/> | 2026-11-19 | 2 CPU, 2 Go de mémoire libre, 20 Go de disque ; Linux, macOS, Windows ; pilotes Docker, Podman, QEMU, Hyper-V, KVM, VirtualBox, entre autres | Oui |
| S28 | <https://github.com/kubernetes/minikube/blob/v1.39.0/pkg/minikube/kubeconfig/kubeconfig.go> | 2026-11-19 | minikube écrit dans la première entrée de `KUBECONFIG` | Oui |
| S29 | <https://github.com/kubernetes/minikube/blob/v1.39.0/pkg/minikube/registry/drvs/docker/docker.go> | 2026-11-19 | Chaque valeur de `--ports` est passée telle quelle à `docker run -p`, pour chaque nœud | Oui |
| S30 | <https://github.com/kubernetes/minikube/blob/v1.39.0/pkg/drivers/kic/kic.go> | 2026-11-19 | Ports internes (API, SSH, Docker, registre) publiés sur l'adresse par défaut, sauf `--listen-address` | Oui |
| S31 | <https://kubernetes.io/docs/reference/issues-security/security/> | 2026-11-19 | Signalement par HackerOne ou par `security@kubernetes.io`, accusé de réception sous 3 jours ouvrés par le Security Response Committee | Oui |
| S32 | <https://www.cncf.io/projects/kubernetes/> | 2026-11-19 | Kubernetes accepté à la CNCF le 2016-03-10, gradué le 2018-03-06 | Oui |
| S33 | <https://opensource.org/licenses> | 2026-11-19 | MIT et Apache-2.0 approuvées par l'OSI | Oui |
| S34 | <https://api.github.com/advisories?ecosystem=go&affects=k8s.io/minikube> | 2026-11-19 | Base mondiale des avis de GitHub : un avis pour minikube (CVE-2018-1002103, élevé, publié en base le 2022-05-13) ; aucun pour `sigs.k8s.io/kind` ni `github.com/k3d-io/k3d/v5` ; trois pour `github.com/k3s-io/k3s`, le dernier CVE-2026-54250 (moyen, 2026-07-14) | Oui |
| S35 | <https://api.github.com/repos/k3d-io/k3d/private-vulnerability-reporting> | 2026-11-19 | Signalement privé GitHub désactivé pour k3d, kind et minikube (même requête sur les trois dépôts) | Oui |
| S36 | <https://formulae.brew.sh/formula/k3d> | 2026-11-19 | Installations Homebrew sur 365 jours : k3d 103 004, kind 58 642, minikube 55 350 (pages `kind` et `minikube` du même site, lues par `brew info`) | Non, statistiques Homebrew |
| S37 | <https://github.com/kubernetes-sigs/gateway-api/releases> | 2026-11-19 | Gateway API v1.7.0 publiée le 2026-10-29, fichier `standard-install.yaml` | Oui |
| S38 | <https://gateway-api.sigs.k8s.io/guides/getting-started/> | 2026-11-19 | Installation : `kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.7.0/standard-install.yaml` | Oui |
| S39 | <https://hub.docker.com/v2/repositories/rancher/k3s/tags/v1.36.4-k3s1> | 2026-11-19 | Digest `sha256:edad48e1…3657`, 81 486 118 octets compressés en arm64, 89 257 597 en amd64 | Oui |
| S40 | <https://hub.docker.com/v2/repositories/library/busybox/tags/1.37.0> | 2026-11-19 | Digest de l'image de base du test, `sha256:a7dbc319…89ec` | Oui |
| S41 | <https://github.com/k3d-io/k3d/blob/v5.9.0/pkg/types/defaults.go> | 2026-11-19 | `DefaultAPIHost = "0.0.0.0"`, appliqué quand l'adresse est omise (`cmd/util/ports.go`) | Oui |
| S42 | <https://github.com/k3d-io/k3d/blob/v5.9.0/pkg/client/ports.go> | 2026-11-19 | Suffixes de port `proxy` (par défaut, par le load balancer) et `direct` (sur un seul nœud) | Oui |
| S43 | <https://github.com/k3d-io/k3d/blob/v5.9.0/pkg/client/kubeconfig.go> | 2026-11-19 | k3d écrit dans le kubeconfig par défaut de client-go, qui suit `KUBECONFIG` | Oui |
| S44 | <https://docs.k3s.io/installation/packaged-components> | 2026-11-19 | Composants embarqués et `--disable=traefik` | Oui |
| S45 | <https://kubernetes.io/releases/> | 2026-11-19 | Branche 1.36 : dernier correctif 1.36.5, fin de maintenance le 2027-06-28 | Oui |
| S46 | <https://hub.docker.com/v2/repositories/kindest/node/tags/v1.36.4> | 2026-11-19 | 351 656 432 octets compressés en arm64, 384 769 599 en amd64, même digest que [S12] | Oui |
| S47 | <https://hub.docker.com/v2/repositories/kicbase/stable/tags/v0.0.51> | 2026-11-19 | Digest `sha256:4a1c825b…0b24`, identique à l'image `gcr.io/k8s-minikube/kicbase` de minikube 1.39.0 ; 493 381 645 octets compressés en arm64, 532 258 316 en amd64 | Oui |
| S48 | GitHub, profils publics de `iwilltry42`, `BenTheElder`, `aojea`, `stmcginnis`, `nirs`, `ComradeProgrammer`, `spowelljr`, `medyagh`, `prezha` | 2026-11-19 | Employeur déclaré : basepeak, Google, Google, Lambda Inc., IBM, Databricks, Google ; aucun pour `medyagh` et `prezha` | Oui, déclaratif |
| S49 | <https://github.com/kubernetes-sigs/kind/releases/tag/v0.32.0> | 2026-11-19 | kind passe au format de configuration kubeadm v1beta4 pour Kubernetes 1.36.0 et suivants : les nœuds sont montés par kubeadm | Oui |
| S52 | <https://api.github.com/search/issues?q=repo:kubernetes-sigs/kind+is:pr+is:merged+merged:%3E=2025-11-19> | 2026-11-19 | kind : 85 PR humaines fusionnées depuis le 2025-11-19, premier auteur à 34,1 %, deux premiers à 58,8 % (relevé de [SECU]) | Oui |
| S53 | <https://api.github.com/search/issues?q=repo:kubernetes/minikube+is:pr+is:merged+merged:%3E=2025-11-19> | 2026-11-19 | minikube : 410 PR sur 966, premier auteur à 35,1 %, deux premiers à 48,0 % ; `prezha` sans PR fusionnée en 12 mois (relevé de [SECU]) | Oui |
| S54 | <https://api.github.com/repos/kubernetes-sigs/kind/contents/OWNERS> | 2026-11-19 | Approbateurs de kind, et `SECURITY_CONTACTS` du même dépôt : `BenTheElder`, `munnerz` (approbateur émérite) | Oui |
| S55 | <https://api.github.com/repos/kubernetes/minikube/contents/OWNERS> | 2026-11-19 | Approbateurs de minikube, et dans le même dépôt `SECURITY_CONTACTS` (`medyagh`, `prezha`) et `SECURITY.md` | Oui |
| S56 | <https://api.github.com/users/BenTheElder> | 2026-11-19 | Même requête `users/{login}` pour les 8 approbateurs et relecteurs : employeurs déclarés repris en [S48], `medyagh` sans employeur (« ex-googler ») | Oui, déclaratif |
| S57 | <https://github.com/k3d-io/k3d/blob/v5.9.0/pkg/types/images.go> | 2026-11-19 | Images d'appoint de k3d désignées par le tag de la CLI, registre par `registry:2` ; remplaçables par `K3D_IMAGE_LOADBALANCER` et `K3D_IMAGE_TOOLS` (`pkg/types/env.go`) | Oui |
| S58 | <https://github.com/kubernetes/minikube/blob/v1.39.0/pkg/provision/provision.go> | 2026-11-19 | Ligne 157 : clé client du démon Docker du nœud recopiée en mode `"0777"` à chaque démarrage ; constaté sur le disque par [SECU] (`key.pem`, `cert.pem`, `ca.pem` en 0777) | Oui |
| S59 | <https://github.com/kubernetes/minikube/blob/v1.39.0/pkg/minikube/bootstrapper/images/images.go> | 2026-11-19 | Ligne 185 : `docker.io/kindest/kindnetd:v20260820-69b56db7`, par tag, sans condensat ; images préchargées d'appoint limitées à `storage-provisioner` | Oui |
| S60 | <https://github.com/kubernetes/minikube/blob/v1.39.0/pkg/minikube/cni/kindnet.go> | 2026-11-19 | kindnetd tourne avec `hostNetwork`, `NET_ADMIN`, `NET_RAW`, et écrit la configuration CNI du nœud par un `hostPath` ; ligne 178, dépôt d'image redirigeable | Oui |
| S61 | <https://github.com/kubernetes/minikube/blob/v1.39.0/pkg/minikube/download/preload.go> | 2026-11-19 | Somme de contrôle de l'archive préchargée prise à la même origine que l'archive ; téléchargement poursuivi si la somme manque | Oui |
| S62 | <https://github.com/kubernetes/minikube/blob/v1.39.0/pkg/minikube/cruntime/cruntime.go> | 2026-11-19 | Avec containerd, minikube désactive dockerd dans le nœud (lu dans le source par [SECU], non essayé) | Oui |
| S63 | <https://github.com/kubernetes/minikube/blob/v1.39.0/cmd/minikube/cmd/start_flags.go> | 2026-11-19 | Lignes 90 et 309 : `--image-repository`, qui redirige kindnetd avec toutes les autres images | Oui |
| S64 | <https://github.com/k3s-io/k3s/blob/v1.36.4+k3s1/scripts/airgap/image-list.txt> | 2026-11-19 | Liste hors ligne de k3s : 8 images, toutes par tag ; manifests du même tag (`coredns.yaml`, `local-storage.yaml`, `metrics-server-deployment.yaml`, `traefik.yaml`) par tag seul | Oui |
| S65 | <https://hub.docker.com/v2/repositories/kindest/kindnetd/tags/v20260820-69b56db7> | 2026-11-19 | Condensat servi `sha256:526969f0a1a7a788a7a96f53a4ad3b51607bde7bb2841edf52a02916e8d52650` (arm64 `sha256:aa67f22c…e372`), poussé le 2026-08-20 ; 35 648 452 octets en arm64, 39 740 316 en amd64 | Oui |
| S66 | <https://api.github.com/repos/kubernetes-sigs/kind/releases/tags/v0.33.0> | 2026-11-19 | Même requête, et `/attestations/{condensat}`, pour k3d 5.9.0, minikube 1.39.0 et Gateway API v1.7.0 : aucun des trois outils ne signe ses binaires ni ne publie d'attestation, aucune release immuable ; Gateway API v1.7.0 immuable avec attestation, `standard-install.yaml` en `sha256:4e2602c4cbe1afbc394d86f4ac6522e1a5263b01133bba1e40a6d1a549e753a1` ; condensats darwin-arm64 des binaires (kind `0c8c7dbe…4b4f`, k3d `fe106541…3e00`, minikube `78ad8f2f…9bcd`) | Oui |
| S67 | <https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/immutable-releases> | 2026-11-19 | Définition des releases immuables de GitHub, à laquelle renvoie la colonne « immuable » de [S66] | Oui |
| S68 | <https://docs.docker.com/engine/network/port-publishing/> | 2026-11-19 | Docker publie par défaut sur toutes les adresses de l'hôte (`0.0.0.0` et `[::]`) ; « Publishing container ports is insecure by default » | Oui |
| S69 | <https://docs.docker.com/engine/network/packet-filtering-firewalls/> | 2026-11-19 | Le trafic des ports publiés est détourné avant les règles d'ufw | Oui |
| S70 | <https://docs.docker.com/docker-hub/usage/pulls/> | 2026-11-19 | 100 tirages anonymes par 6 h et par adresse IPv4 ou sous-réseau IPv6 /64, 200 avec un compte Personal ; un tirage par architecture ; limites anti-abus sur les adresses partagées. Page voisine lue par [SECU] : <https://docs.docker.com/docker-hub/usage/> | Oui |
| S71 | <https://github.com/opencontainers/distribution-spec/blob/main/spec.md> | 2026-11-19 | Un tag n'est qu'un pointeur ; seul le condensat fixe le contenu | Oui |
| S72 | `man 3 mkdtemp`, page de manuel locale sous macOS 27.2.1 | 2026-11-19 | `mktemp -d` crée le dossier en mode 0700 | Oui |
| S73 | <https://docs.github.com/en/billing/concepts/product-billing/github-actions> | 2026-11-19 | Runners standard gratuits pour un dépôt public ; en privé, GitHub Free inclut 12 USD par mois, Pro et Team 18 USD ; Linux 2 cœurs à 0,006 USD la minute en x64 ; usage bloqué sans moyen de paiement ; cache de 10 Go par dépôt | Oui |
| S74 | <https://docs.github.com/en/billing/reference/actions-runner-pricing> | 2026-11-19 | Chaque job arrondi à la minute supérieure ; tarifs des runners Linux x64 et arm64 | Oui |
| S75 | <https://docs.github.com/en/actions/reference/runners/github-hosted-runners> | 2026-11-19 | Runner Linux standard : 4 CPU et 16 Go en public, 2 CPU et 8 Go en privé | Oui |
| S76 | <https://docs.github.com/en/actions/concepts/runners/github-hosted-runners> | 2026-11-19 | Chaque runner hébergé est une machine virtuelle neuve : en CI, chaque création de cluster se fait à froid | Oui |
| S77 | <https://docs.docker.com/subscription/desktop-license/> | 2026-11-19 | Docker Desktop gratuit pour les entreprises de moins de 250 salariés et de moins de 10 M USD de chiffre d'affaires, l'usage personnel, l'éducation et l'open source non commercial ; payant au-delà | Oui |

## 10. Relectures

| Relecteur | Porte sur | Date | Avis |
| --- | --- | --- | --- |
| [SECU] | Licences, critères éliminatoires, sécurité, adresses d'écoute | 2026-11-19 | Réservé |
| [FINOPS] | Coût, trafic réseau à chaque création, empreinte, CI | 2026-11-19 | Réservé |

[BENCH] Les textes des deux relecteurs sont repris tels quels, à deux
exceptions : leurs identifiants de sources suivent la renumérotation de la
section 9, et un nom de conteneur d'un autre projet est remplacé par sa
description, le dépôt étant public.

[SECU] Licences et critères éliminatoires confirmés le 2026-11-19 : MIT pour
k3d, Apache-2.0 pour k3s, kind, minikube et Gateway API, aucune licence AGPL,
aucun dépôt archivé, une release stable en moins de 12 mois pour chacun. Un
miroir ou une archive d'images publiés par CELIAN serait une redistribution, à
relire avant.

[SECU] Gouvernance de minikube ramenée à 4. Sur la même mesure, depuis le
2025-11-19, les deux premiers auteurs font 72 % des commits humains de kind et
68 % de ceux de minikube ; sur les PR fusionnées, le premier auteur pèse 34 %
chez kind et 35 % chez minikube. Chaque projet compte deux employeurs déclarés
parmi ses approbateurs. minikube a un approbateur sans commit ni PR en douze
mois, deux approbateurs sans employeur déclaré, et 396 de ses 557 commits de
fusion sont faits à la main par deux personnes [S13], [S22], [S52] à [S56].

[SECU] Sécurité de minikube ramenée à 3, pour l'intégrité : kindnetd tiré par
tag à chaque création, avec `NET_ADMIN` sur le réseau de l'hôte ; somme de
contrôle du préchargement prise à la même origine, téléchargement poursuivi
sans elle ; clé client du démon Docker du nœud recopiée en 0777, sans usage
avec containerd d'après le source [S58] à [S61]. k3d reste à 2 : son registre,
publié sur toutes les interfaces, accepte un push sans authentification [M7],
[M8]. Aucun des trois outils ne signe ses binaires ni ne publie de release
immuable [S66].

[SECU] Effet : kind 90, minikube 89, k3d 62 (minikube 91 si le tirage de
kindnetd n'est compté qu'en empreinte). L'écart tient dans un cran : la grille
ne départage plus kind et minikube, et l'ADR devra trancher sur des critères
écrits. Côté sécurité, kind est préférable : aucun téléchargement à la
création, nœud entièrement figé par condensat, aucun port en plus de l'API. Ses
réserves : version 0.x, registre à monter soi-même si BENCH-005 en a besoin.

[SECU] Exigences pour le blueprint : version de l'outil vérifiée par `task up` ;
image de nœud et images du blueprint figées par condensat ; aucune image tirée
par tag à la création du cluster ; CRD et manifests tiers versionnés avec leur
SHA-256 ; 127.0.0.1 sur l'API et sur chaque port publié, contrôlé par un test
de la matrice (R-20) ; dépendance à Docker Hub suivie en R-25.

[SECU] Script : poser le `trap` après les contrôles de départ, viser le
registre k3d par son nom exact, `umask 077`, ne relever que les conteneurs du
cluster. Inscrire et vérifier le condensat des CRD Gateway API.

[SECU] Rapport : retirer de la section 4.2 les noms des conteneurs d'un autre
projet.
Ajouter en section 8 l'absence de scan des images de nœud (kicbase,
kindest/node, rancher/k3s) et l'exposition réseau pendant l'exécution.

[BENCH] Suite donnée à [SECU], point par point :

- licences : confirmées, aucune note ne change ; la réserve sur la
  redistribution d'images entre dans les suites de la section 7 ;
- gouvernance : minikube passe de 5 à 4, selon l'arbitrage du DSI. La
  section 5.2 reprend la mesure de [SECU], et [S13], [S22], [S52] à [S56]
  portent les relevés ;
- sécurité : minikube passe de 4 à 3, selon l'arbitrage du DSI, qui ne voit
  pas de double compte entre 5.5 (intégrité) et 5.6 (disponibilité et temps) ;
  la justification est écrite en 5.5. Le registre de k3d ouvert en écriture
  et les binaires non signés y sont ajoutés ;
- effet : avec la règle d'empreinte de [FINOPS], également arbitrée par le
  DSI, les totaux finaux sont kind 90, minikube 87, k3d 64, et le verdict
  proposé passe à kind. Les critères écrits hors grille et les réserves de
  kind sont dans la section 7 ;
- exigences pour le blueprint : reprises dans les suites de la section 7 ;
- script : `trap` posé après les contrôles de départ, vérifié par un test du
  refus le 2026-11-19 (cluster kind préexistant, script arrêté en code 1,
  cluster et réseau intacts) ; registre k3d visé par son nom exact ;
  `umask 077` ; `record_load` ne relève plus que les conteneurs du cluster,
  et le nombre des autres sans leur nom ; CRD téléchargées par `gh`, SHA-256
  vérifié, copie locale appliquée, chemin validé sur kind ;
- rapport : section 4.2 réduite à « aucun autre conteneur ni cluster » ;
  section 8 complétée (images de nœud non scannées, condensats de k3d,
  exposition réseau et consigne de réseau de confiance) ;
- signalement de la clé en 0777 : écrit comme suite possible pour Lucas en
  section 7, non fait par [BENCH] ;
- questions restées ouvertes, non vérifiées : arrêt réel de dockerd sous
  containerd, effet de `--image-repository` sur kindnetd, images de
  l'extension `registry` de minikube, image `tag@sha256` acceptée par k3d,
  accès anonyme à l'API de k3s, pare-feu de macOS face à `*:port`, limites de
  Docker Hub sur les runners GitHub, intégrité de l'installation par
  Homebrew, scan Trivy des images de nœud.

[FINOPS] Coût. La note de 5/5 est confirmée pour les trois options. Sur une
ligne illimitée, le trafic retéléchargé à chaque création ne coûte rien de
plus. Sur une ligne facturée au volume, son prix dépend de l'abonnement de
chacun et ne peut pas s'écrire. Son effet réel, en temps et en dépendance au
réseau, est déjà compté en 5.6 : le compter ici pèserait deux fois le même
fait. La justification de k3d est corrigée en « au plus 170 Mio ». C'est la
somme des tailles que le kubelet déclare pour les 9 images du nœud, dont 2
déjà présentes, et le transfert réel n'est pas mesuré. Docker Hub limite les
tirages anonymes à 100 par 6 heures et par adresse IPv4 [S70]. minikube en
consomme 1 par création, k3d 7 si ses images viennent de Docker Hub (registre
à relever).

[FINOPS] Empreinte. La règle du double de la meilleure valeur compare les
options entre elles, alors qu'un client pose la question pour son poste et sa
ligne. Elle bascule aussi au gré du bruit d'une exécution à froid unique :
minikube passe à 1,97 dans la série, mais échoue à 2,20 au test de fumée et à
2,43 sur le volume. Règle proposée, écrite elle aussi après lecture des
chiffres, avec des seuils tirés du PRD et d'un débit bas de 10 Mbit/s, aucun
tiré des options. Chaque option part de 5 et perd un cran par condition
remplie : volume compressé de la première création au-delà de 500 Mo (400 s à
10 Mbit/s), image téléchargée à chaque création même avec le cache plein,
création à chaud au-delà de 90 s, mémoire au repos au-delà de 1 Gio. Effet :
k3d 4/5 (total 64), kind 5/5 (90), minikube 3/5 (92). L'avance de minikube
tombe à un cran : avec 5 en gouvernance, kind passerait devant, 93 contre 92.
Lucas tranche entre les deux règles, et celle qu'il retient entre dans
`TEMPLATE.md` avant BENCH-005.

[FINOPS] Volumes et ENF-01. Volumes de la première création, en Mo compressés
arm64 : kind 351,7 ; minikube 853,3, dont 35,6 Mo de CNI [S65] ; k3d entre
81,5 et 357,2, car la taille compressée de `k3d-proxy`, de `k3d-tools` et des
images du nœud n'est pas relevée. En amd64 : kind 384,8 [S46], minikube au
moins 572,0 [S65], [S47], k3d au moins 89,3 [S39]. Le téléchargement seul
consomme, selon le débit utile supposé : à 10 Mbit/s, 31 % du budget de
15 minutes avec kind et 76 % avec minikube ; à 50 Mbit/s, 6 % et 15 % ; à
300 Mbit/s, 1 % et 3 %. Sur le poste de mesure, le débit effectif déduit de
M5 moins M1 tourne autour de 60 Mbit/s. Les images de la stack restent à
mesurer en BENCH-005.

[FINOPS] Dimensionnement. Au repos, le cluster occupe 6,4 à 8,3 % d'un
portable de 8 Gio et 3,2 à 4,2 % d'un portable de 16 Gio, quel que soit le
profil. Sous macOS, le plafond est la VM du moteur (ici, `docker info` voit
11,73 Gio sur 24 Gio physiques) : c'est cette valeur que le choix du profil
de US-005 doit lire. Avec minikube, chaque profil passe `--cpus` et
`--memory` explicitement, ou `no-limit` [S25]. Ses valeurs par défaut (2 CPU,
mémoire calculée selon la machine et le nombre de nœuds) feraient dépendre le
profil du poste. Avec kind et k3d, rien ne limite le cluster. Reste à mesurer
en BENCH-005 si la stack tient sur 8 Gio.

[FINOPS] CI. Les runners standard sont gratuits pour un dépôt public [S73].
Pour un dépôt privé, GitHub Free inclut 12 USD par mois, soit 2 000 minutes
Linux x64 à 0,006 USD [S73], [S74]. Chaque job est arrondi à la minute
supérieure [S74] et démarre sur une VM neuve, donc à froid [S76]. Avec M5
comme hypothèse pour le runner, la création du cluster coûte, pour 100 jobs
par mois, 123 minutes avec kind, 135 avec k3d et 243 avec minikube, soit 6 %,
7 % et 12 % de l'allocation gratuite. Pour un dépôt public, l'effet porte sur
le temps, qui compte dans les 15 minutes à travers la CI du premier push.

[FINOPS] Suite attendue de [BENCH] : corriger 5.9 et la section 7 (« 352 à
853 Mo ») ; ajouter au tableau M6 la taille du CNI de minikube et les tailles
amd64 ; faire relever par le script les références des images tirées par le
nœud et la taille compressée de `k3d-proxy` et `k3d-tools` ; ajouter [F1] à
[F11] aux sources. L'avis reste réservé jusqu'à la décision sur la règle
d'empreinte.

[BENCH] Suite donnée à [FINOPS], point par point :

- coût : 5/5 confirmé pour les trois ; justification de k3d corrigée en
  « au plus 170 Mio », avec la raison du majorant (section 5.9) ;
- règle d'empreinte : appliquée en 5.6 selon l'arbitrage du DSI, marquée
  « proposée par [FINOPS], recommandée par le DSI, à valider par Lucas » ;
  l'ancienne règle et ses notes restent dans la sensibilité de la section 7.
  Avec la gouvernance de minikube ramenée à 4 et sa sécurité à 3, le total de
  minikube est 87, et non 92 ; la mise dans `TEMPLATE.md` avant BENCH-005 est
  dans les suites de la section 7 ;
- volumes : tableau M6 complété avec le CNI de minikube (35,6 Mo, total
  853,3 Mo) et une colonne amd64 ; section 7 corrigée en « 352 à 853 Mo ».
  Pour k3d, la taille compressée de `k3d-proxy` (28,8 Mo en arm64, 28,9 en
  amd64) et de `k3d-tools` (11,2 Mo) a été relevée par
  `docker manifest inspect -v` : la fourchette arm64 se resserre à 121,4 à
  300,7 Mo, au lieu de 81,5 à 357,2 ;
- dimensionnement : 6 100 Mio pour un nœud, `Memory:3072` par nœud à deux
  nœuds, plafond réel à la VM du moteur, écrits en 4.4 et dans les réserves
  de la section 7, avec l'absence de limite par nœud chez kind ;
- CI : pas de changement de note ; le README d'un projet généré privé devra
  signaler les minutes de CI consommées, suite écrite en section 7 ;
- script : il relève désormais les références des images tirées par le nœud
  (`node-images.tsv`) et la taille compressée par architecture des images
  épinglées (`images.tsv`, colonne `compressed_bytes`), sans curl ni
  `docker run` ;
- sources : F1 à F11 renumérotées ou fusionnées, voir la section 9 ;
- R-04 : texte repris par le DSI dans `docs/risques.md`.
