# BENCH-004. Gateway

| Champ | Valeur |
| --- | --- |
| Identifiant | BENCH-004 |
| Sujet | Contrôleur Gateway API qui expose l'API et le front du projet généré dans le cluster local |
| Statut | relu |
| Ouvert le | 2026-11-19 |
| Mis à jour le | 2026-11-19 |
| Auteur | [BENCH] |
| Relecteurs | [SECU] pour les licences, les CVE et les adresses d'écoute, [FINOPS] pour les coûts |
| Périmètre | Projet généré sur PC (cluster kind de l'ADR-004). Sur GCP, le contrôleur Gateway de GKE (principe III) : le choix n'y touche que la portabilité des manifests |
| Choix du PRD | Gateway, option pressentie Envoy Gateway (`docs/prd-mvp.md`, section 1) |
| ADR lié | ADR-005, à écrire par [ARCHI] |
| Verdict proposé | Envoy Gateway pour la cible `local`, 86/100, devant Cilium (81) et Traefik (78). Avance de 5 points, qu'aucun changement d'un seul cran ne renverse (section 7). Volume noté sur linux_amd64 après relecture, par décision du DSI ; 88 avec la lecture arm64 d'origine |

## 1. Contexte

[BENCH] Question posée : quel contrôleur Gateway API expose, dans le cluster
kind du PC, l'API et le front du projet généré, avec les mêmes manifests
Gateway et HTTPRoute que sur GKE.

[BENCH] Ce qui en dépend. US-005 demande que `task up` démarre toute la stack
dans le cluster local sans autre étape (principe VII) et affiche des adresses
locales qui répondent. ENF-01 fixe le parcours à moins de 15 minutes, premier
téléchargement des images compris. ENF-02 demande que seule la couche de
cible change d'une cible à l'autre (principe II) : sur GCP, le principe III
impose le service managé, le contrôleur Gateway de GKE ; l'ADR-009 en fait le
service de la cible `gcp`, avec une lecture des principes III et V qu'il
propose et que Lucas n'a pas encore validée. La portabilité se
juge donc sur une question précise : les mêmes Gateway et HTTPRoute tournent-
ils en local et sur GKE en ne changeant que `gatewayClassName` ? Côté
constitution : principes III, V (fondation et plusieurs entreprises), VI
(récent mais éprouvé) et VIII (aucun fait de mémoire). Côté risques : R-04
(15 minutes hors d'atteinte), R-20 (« Identifiants par défaut dans le golden
repo », dont le texte traite aussi les ports publiés), R-25 (démarrage tributaire des
registres publics), R-26 (moteur de conteneurs sous licence payante). Le
cluster local est kind 0.33.0, retenu par Lucas le 2026-11-19 (BENCH-003,
ADR-004 en cours) ; Cilium oblige à changer sa configuration, et cet effet
est mesuré.

[BENCH] Option pressentie par le PRD : Envoy Gateway, reprise du brief
(sections 6 et 8). Elle est notée comme les autres, avec le même script, le
même manifest et les mêmes seuils.

[BENCH] Hors champ : le cluster local (BENCH-003), l'orchestration locale
(BENCH-005), les certificats réels du projet (cert-manager ou équivalent, à
traiter avec [SECU]), le maillage de services, la répartition sur plusieurs
nœuds, et le réglage fin du contrôleur dans le blueprint, qui revient à
[ARCHI] et [OPS]. Aucune ressource GCP n'a été créée (principe X) : le côté
GKE est jugé sur sa documentation et son rapport de conformité.

## 2. Options étudiées

| Option | En une phrase | Version examinée | Publiée le | Sources |
| --- | --- | --- | --- | --- |
| Envoy Gateway | Contrôleur Gateway API de la famille Envoy, qui crée un déploiement Envoy par Gateway | 1.10.0 (chart `gateway-helm` v1.10.0), proxy `envoyproxy/envoy:distroless-v1.40.2` | 2026-11-06 | [S1], [S2], [S6] |
| Cilium | CNI fondé sur eBPF, dont l'Envoy intégré sert aussi de contrôleur Gateway API ; il remplace le CNI et kube-proxy du cluster | 1.20.5 (chart `cilium` 1.20.5) | 2026-11-17 | [S16], [S17] |
| Traefik | Proxy inverse qui lit, entre autres sources, les objets Gateway API par son fournisseur `kubernetesGateway` | 3.7.19 (chart `traefik` 42.4.1) | 2026-11-13 | [S30], [S31], [S37] |

[BENCH] Options repérées mais non étudiées : NGINX Gateway Fabric, Istio,
kgateway, agentgateway, et les autres implémentations des rapports de
conformité [S41]. Aucune ne figure dans la section 8 du brief.

[BENCH] Versions de Gateway API d'après les rapports de conformité officiels
[S41]. Aucune des trois n'a encore publié de rapport pour la v1.7 : le dossier
`reports/v1.7` ne contient que agentgateway, Airlock, Cloud Service Mesh et
kgateway. Leurs derniers rapports portent sur la v1.6.1.

| Option | Version testée | Canal du rapport | Profils réussis | Réserve |
| --- | --- | --- | --- | --- |
| Envoy Gateway | 1.9.0, Gateway API v1.6.1 | expérimental | GATEWAY-HTTP (37 tests du cœur, 55 étendus), GATEWAY-TLS, GATEWAY-GRPC : cœur et étendu réussis | Rapport fait sur 1.9.0, pas sur 1.10.0. La matrice du projet donne Gateway API v1.6.1 pour 1.10 [S6] |
| Cilium | 1.20.0, Gateway API v1.6.1 | standard et expérimental | GATEWAY-HTTP, -TLS, -GRPC, -TCP, -UDP, MESH-HTTP, MESH-GRPC : tous réussis | La documentation de 1.20 annonce Gateway API v1.6.3 [S22] |
| Traefik | 3.7.10, Gateway API v1.6.1 | expérimental | GATEWAY-GRPC et GATEWAY-TLS réussis ; GATEWAY-HTTP « partial » : 36 tests du cœur réussis, 1 sauté (`HTTPRouteMultipleGateways`) | La documentation de 3.7 annonce le canal standard v1.6.3 [S35] |
| GKE (cible GCP) | 1.36.2-gke.2154000, Gateway API v1.6.0 | standard | GATEWAY-HTTP : 37 tests du cœur, 19 étendus | Les CRD sont installées et tenues par GKE, canal standard seul [S43] |

[BENCH] La v1.7.0 du canal standard a été mesurée sur les trois options (M7) :
c'est la version imposée par le DSI, et la dernière publiée [S40]. Aucune
option n'a exigé un autre canal ni une autre version.

## 3. Critères éliminatoires

[BENCH] Seuil de release : 2025-11-19, douze mois avant la vérification.

| Option | Licence open source | Ni archivé ni en maintenance | Release de moins de 12 mois | Vérifié le | Résultat |
| --- | --- | --- | --- | --- | --- |
| Envoy Gateway | Oui, Apache-2.0 [S1], approuvée OSI [S46] | Oui, dépôt non archivé, dernier commit le 2026-11-19 [S1], [S3] | Oui, 1.10.0 le 2026-11-06, 1.9.4 le 2026-11-17 [S2] | 2026-11-19 | Retenue |
| Cilium | Oui, Apache-2.0 ; gabarits BPF sous GPL-2.0 seule ou BSD-2-Clause au choix [S16], toutes approuvées OSI [S46] | Oui, dépôt non archivé, dernier commit le 2026-11-18 [S16], [S18] | Oui, 1.20.5 le 2026-11-17 [S17] | 2026-11-19 | Retenue |
| Traefik | Oui, MIT [S30], approuvée OSI [S46] | Oui, dépôt non archivé, dernier commit le 2026-11-18 [S30], [S32] | Oui, 3.7.19 le 2026-11-13 [S31] | 2026-11-19 | Retenue |

[BENCH] Options éliminées : aucune.

## 4. Mesures

### 4.1 Ce qui est mesuré

[BENCH] Seuils d'empreinte écrits le 2026-11-19 à 05:45 UTC, avant la
première mesure, selon la règle de `TEMPLATE.md` (section 5.6) validée par
Lucas le 2026-11-19. Ils portent sur la plate-forme de base, c'est-à-dire le
cluster kind et la gateway mesurés ensemble, et reprennent tels quels les
quatre seuils de BENCH-003. Deux raisons. Cilium remplace le CNI de kind : sa
part ne se sépare pas de celle du cluster, et seule la plate-forme entière se
compare d'une option à l'autre. Et `task up` doit amener cette plate-forme
avant la moindre ligne de l'application : les seuils que BENCH-003 a posés
pour la base valent pour elle, gateway comprise. kind seul en consommait
déjà une partie (BENCH-003 : 351,7 Mo à télécharger en arm64, 26,8 s à
chaud, 602,5 Mio au repos) ; la gateway dispose du reste.

Chaque option part de 5 et perd un cran par condition remplie :

1. le volume compressé de la première création de la plate-forme dépasse
   500 Mo : image de nœud kind (351,7 Mo en arm64, 384,8 Mo en amd64,
   BENCH-003) plus les images que la gateway fait tirer au nœud. C'est 400 s
   à 10 Mbit/s, 44 % du budget de 900 s d'ENF-01. La note se donne sur
   l'arm64 du poste de mesure ; l'amd64 s'écrit à côté, et si elle change la
   note, les deux vont dans la sensibilité de la section 7. Révisé le
   2026-11-19 après relecture [FINOPS], par décision du DSI : volume noté
   sur linux_amd64, pire cas des systèmes de Q5, comme BENCH-008 ; la
   lecture arm64 d'origine passe en sensibilité ;
2. au moins une image de la gateway se retélécharge à chaque création du
   cluster, alors qu'elle est déjà dans le cache Docker du poste et chargée
   dans le nœud par `kind load docker-image`, le préchargement que `task up`
   ferait ;
3. le démarrage à chaud de la plate-forme dépasse 90 s, 10 % du budget :
   médiane de M1, de `kind create cluster` à la première réponse HTTP de
   l'application de test à travers la gateway, sur `127.0.0.1` ;
4. la mémoire au repos de la plate-forme dépasse 1 Gio, un huitième d'un
   portable de 8 Gio : médiane de M2, conteneurs du cluster.

[BENCH] Une option à moins de 10 % d'un seuil voit ses deux notes possibles
écrites dans la sensibilité de la section 7.

[BENCH] Périmètre, ajouté le 2026-11-19 sur proposition de [FINOPS] :
plate-forme de base : cluster kind, CRD Gateway API et gateway ; les images
de la stack relèvent du budget par étape d'ENF-01 que R-04 prévoit après
BENCH-005. Les benchmarks suivants ne comptent donc pas leurs images contre
les mêmes 500 Mo. La reprise de ce périmètre et de la règle d'architecture
dans `TEMPLATE.md` attend la GATE 1.

| ID | Mesure | Unité | Critère alimenté | Script |
| --- | --- | --- | --- | --- |
| M0 | Référence : kind sans gateway, création jusqu'à « prêt », mémoire et CPU au repos | s, Mio, % d'un cœur | Empreinte (écart dû à la gateway, effet de Cilium sur la création) | `tests/bench/bench-004-gateway.sh` |
| M1 | Démarrage de la plate-forme : de `kind create cluster` à la première réponse HTTP de l'application de test par la gateway, sur `127.0.0.1` | s | Empreinte (seuil 3) | idem |
| M2 | Mémoire au repos des conteneurs du cluster, 120 s après la première réponse | Mio | Empreinte (seuil 4) | idem |
| M3 | CPU au repos des conteneurs du cluster, au même moment | % d'un cœur | Empreinte | idem |
| M4 | Mémoire et CPU de chaque pod de la gateway, lus par l'API de statistiques du kubelet | Mio, millicœurs | Empreinte, détail | idem |
| M5 | Première création, images de la gateway absentes du nœud | s | Empreinte (ENF-01, R-04) | idem |
| M6 | Volume compressé des images de la gateway, et images retirées du registre à chaque création, avec et sans préchargement | Mo, nombre | Empreinte (seuils 1 et 2), R-25 | idem, `docker manifest inspect -v` |
| M7 | Contrôles fonctionnels : CRD Gateway API v1.7.0 du canal standard sans conflit, même manifest Gateway et HTTPRoute à la GatewayClass près, réponse HTTP et terminaison TLS sur `127.0.0.1`, état des conditions | oui ou non | Portabilité, expérience dev | idem |
| M8 | Adresses d'écoute côté poste et dans le nœud | adresse | Sécurité (R-20) | idem |

### 4.2 Machine de mesure

| Élément | Valeur |
| --- | --- |
| Modèle | Apple Mac16,7 |
| Processeur | Apple M4 Pro, 14 cœurs (10 performance, 4 efficacité) |
| Mémoire | 24 Gio |
| Système | macOS 27.2.1 (build 26B131) |
| Moteur de conteneurs | OrbStack (moteur non libre, voir R-26), Docker Engine 29.8.2, cgroup v2, pilote de stockage overlay2 sur btrfs, noyau de la machine virtuelle 7.2.12-orbstack |
| Ressources allouées | Machine virtuelle d'OrbStack : 14 CPU, 11,73 Gio (12 598 894 592 octets, `docker info`) |
| Versions mesurées | kind 0.33.0 et image `kindest/node:v1.36.4` par condensat (comme BENCH-003), kubectl 1.37.1, Helm 4.3.2 installé par Homebrew le 2026-11-19 pour ce benchmark, OpenSSL 4.0.3. Charts, CRD et images figés dans le script, vérifiés par SHA-256 ou condensat |
| Charge parasite | Applications de bureau ouvertes, sessions Claude Code. Charge moyenne sur une minute entre 2,31 et 4,29 au début de chaque exécution (`load.tsv`). Aucun autre conteneur actif pendant la série : BENCH-005, BENCH-007 et BENCH-009 ont mesuré avant, sous le même verrou, et la série a attendu leur fin de 12:33 à 13:04 UTC |

### 4.3 Protocole

1. État de départ : aucun conteneur du cluster `celian-bench-004`, ports
   18080 et 18443 libres. Le script prend le verrou commun aux benchmarks
   (`BENCH_LOCK_DIR`) avant toute création, et le rend à la fin, erreur
   comprise ; BENCH-005 et BENCH-007 ne mesurent donc pas en même temps. Le
   kubeconfig et les dossiers de Helm vivent dans le dossier d'essai.
2. Chaque exécution crée un cluster neuf par `kind create cluster`, avec la
   configuration de l'option (section 7, changements de la configuration
   kind), applique les CRD Gateway API v1.7.0 du canal standard,
   téléchargées par `gh` et vérifiées par SHA-256, installe l'option par son
   chart Helm figé, puis applique la même application de test : un
   `busybox httpd` figé par condensat, un Secret TLS auto-signé pour
   `celian.test`, une Gateway à deux écouteurs (HTTP 80, HTTPS 443 avec
   `certificateRefs`) et une HTTPRoute. Seul `gatewayClassName` change d'une
   option à l'autre ; le script le vérifie par `diff`.
3. Fin de M1 : la première réponse de l'application de test à une requête
   HTTP/1.1 envoyée par `nc` sur `127.0.0.1:18080`, port publié par kind avec
   `listenAddress: "127.0.0.1"`. Le script attend ensuite la première
   réponse HTTPS par `openssl s_client` sur `127.0.0.1:18443`, avec SNI.
4. Relevé : chronomètre à la milliseconde (Perl `Time::HiRes`). Mémoire et
   CPU par `docker stats --no-stream` sur les conteneurs du cluster, trois
   échantillons à partir de 120 s après la première réponse, espacés de
   10 s, médiane des trois ; au deuxième échantillon, mémoire et CPU par pod
   lus par l'API de statistiques du kubelet. Images tirées ou déjà présentes
   lues dans les événements `Pulled`. Adresses par `docker ps`, `lsof` côté
   macOS et `netstat` dans un pod en `hostNetwork`.
5. Exécution 0 à froid : les images de la gateway ne sont pas dans le nœud,
   qui les tire de leur registre. Exécutions 1 à 3 à chaud, comme dans
   BENCH-003 : les images sont dans le cache Docker du poste (tirées par tag
   avant le chronomètre, condensat vérifié) et chargées dans le nœud par
   `kind load docker-image`, chronométré. La référence (M0) est un cluster
   kind sans gateway, trois exécutions. 15 s de pause entre deux exécutions,
   options enchaînées dans l'ordre référence, Envoy Gateway, Cilium,
   Traefik.

Pour refaire la mesure :

```bash
BENCH_LOCK_DIR=/chemin/du/verrou tests/bench/bench-004-gateway.sh /chemin/vers/un/dossier/vide
```

[BENCH] Sans argument, le script crée un dossier par `mktemp -d`. Un dossier
passé en argument doit être absent ou vide. `OPTIONS`, `RUNS`, `PRELOAD`,
`IDLE_WAIT` et `READY_TIMEOUT` règlent l'essai. Le script refuse de démarrer
si un cluster `celian-bench-004` existe ou si un port est pris, et sort en
code 3 sans rien toucher si le verrou est pris ; un verrou dont le fichier
`owner` a plus de 90 minutes est retiré et signalé. Son `trap` n'est posé
qu'après ces contrôles et la prise du verrou. Il ne supprime que ce cluster,
le réseau `kind` s'il l'a créé et qu'il est vide, et ce qu'un outil laisse
sous ce nom. Les images tirées restent en cache. Il passe shellcheck et
tourne sous le bash 3.2 de macOS.

[BENCH] Deux essais de fumée ont précédé la série. Le premier client HTTP
envoyait une requête HTTP/1.0 par `nc` et fermait son côté de la connexion
aussitôt : le port de l'hôte acceptait la connexion sans rien renvoyer, alors
que `wget` obtenait la page depuis un pod. Avec une requête HTTP/1.1 et une
entrée gardée ouverte une demi-seconde, les trois options répondent. La
cause exacte n'est pas établie ; seul le client a changé.

### 4.4 Résultats

[BENCH] Mesures lancées le 2026-11-19 de 13:04:58 à 13:58:19 UTC, sur la
machine de la section 4.2 (dossier d'essai `b004-series-16`). Les trois
exécutions à chaud servent à la notation ; l'exécution 0 est en M5.

| Mesure | Option | Exécution 1 | Exécution 2 | Exécution 3 | Médiane | Écart |
| --- | --- | --- | --- | --- | --- | --- |
| M0, création jusqu'à « prêt » | kind seul | 26,9 s | 26,8 s | 26,9 s | 26,9 s | 0,1 s |
| M0, mémoire au repos | kind seul | 595,2 Mio | 591,6 Mio | 563,9 Mio | 591,6 Mio | 31,3 Mio |
| M0, CPU au repos | kind seul | 16,0 % | 12,9 % | 14,4 % | 14,4 % | 3,1 % |
| M1 | Envoy Gateway | 46,5 s | 44,6 s | 44,1 s | 44,6 s | 2,4 s |
| M1 | Cilium | 73,4 s | 41,3 s | 55,8 s | 55,8 s | 32,1 s |
| M1 | Traefik | 37,7 s | 43,5 s | 43,5 s | 43,5 s | 5,8 s |
| M2 | Envoy Gateway | 1 078,3 Mio | 948,8 Mio | 934,1 Mio | 948,8 Mio | 144,2 Mio |
| M2 | Cilium | 948,7 Mio | 972,6 Mio | 926,7 Mio | 948,7 Mio | 45,9 Mio |
| M2 | Traefik | 839,1 Mio | 811,8 Mio | 769,8 Mio | 811,8 Mio | 69,3 Mio |
| M3 | Envoy Gateway | 18,8 % | 25,0 % | 24,7 % | 24,7 % | 6,2 % |
| M3 | Cilium | 21,6 % | 25,0 % | 22,0 % | 22,0 % | 3,4 % |
| M3 | Traefik | 14,6 % | 22,9 % | 18,9 % | 18,9 % | 8,3 % |

[BENCH] Détail de M1, médianes à chaud : `kind load` des images 4,2 s (Envoy
Gateway), 11,1 s (Cilium), 2,1 s (Traefik) ; première réponse HTTPS 0,5 à
0,7 s après la première réponse HTTP pour les trois. Avec Cilium, le nœud ne
devient prêt qu'une fois Cilium installé : 41,3 à 73,4 s à chaud, contre
26,9 s pour kind seul (M0). C'est l'effet du changement de CNI sur la
création du cluster, et la source de l'écart de 32,1 s.

[BENCH] Mémoire par pod (M4), API du kubelet, médiane des trois exécutions à
chaud : pods de la gateway 99,7 Mio pour Envoy Gateway (contrôleur 47,1,
proxy 53,3 à l'exécution 1), 201,4 Mio pour Cilium (agent 125,6, opérateur
56,2, cilium-envoy 28,6), qui retire en échange kindnet et kube-proxy
(34,6 Mio dans M0), et 33,7 Mio pour Traefik. Le serveur d'API grossit avec
les CRD installées. Médianes des trois exécutions à chaud : 231,5 Mio sans
gateway, 469,6 Mio avec Envoy Gateway (442,0 à 511,2), 380,6 avec Cilium,
355,7 avec Traefik. Les CRD d'Envoy Gateway pèsent ainsi plus que son
contrôleur et son proxy réunis : 238 Mio de plus au serveur d'API, sur les
357,2 Mio qui séparent sa plate-forme de kind seul (948,8 moins 591,6).

[BENCH] Exécution à froid (M5) et volume à télécharger (M6), en Mo
compressés lus par `docker manifest inspect -v` ; image de nœud kind d'après
BENCH-003. L'image `busybox` de l'application de test (1,9 Mo) n'est pas
comptée.

| Option | M5, première création jusqu'à la première réponse | Images de la gateway, arm64 | Plate-forme, arm64 (kind 351,7) | Images de la gateway, amd64 | Plate-forme, amd64 (kind 384,8) | Images contactées au registre à chaque création, préchargées comprises |
| --- | --- | --- | --- | --- | --- | --- |
| Envoy Gateway | 75,9 s | 114,8 (contrôleur 71,9, proxy 42,9) | 466,5 | 121,0 | 505,8 | 2, sur Docker Hub |
| Cilium | 146,9 s | 387,5 (agent 241,2, opérateur 66,0, cilium-envoy 80,2) | 739,2 | 379,5 | 764,3 | 3, sur quay.io |
| Traefik | 47,0 s | 50,0 | 401,7 | 55,3 | 440,1 | 1, sur Docker Hub |

[BENCH] Effet sur R-04. M5 part d'une image de nœud déjà en cache. En
ajoutant le froid de kind (BENCH-003, 73,7 s) moins sa création à chaud
(M0, 26,9 s), [FINOPS] estime la création à froid jusqu'à la première
réponse à 122,7 s avec Envoy Gateway, 193,7 s avec Cilium et 93,8 s avec
Traefik : un ordre de grandeur, qui combine deux séries. Le DSI passe R-04
en probabilité forte, avec un déclencheur lu sur le premier lancement
complet et sur le pire cas de Q5 : 505,8 Mo en amd64 avec Envoy Gateway,
avant les images de la stack. Décision à confirmer par Lucas à la GATE 1.

[BENCH] Le constat qui compte pour R-25. À chaud, les images sont dans le
cache Docker du poste et chargées dans le nœud par `kind load`, mais le
kubelet rapporte quand même « Successfully pulled » pour chaque image de la
gateway, à chaque création et pour les trois options. Le tirage dure 0,9 à
2,4 s et la taille rapportée est celle de l'image décompressée déjà
présente : les couches ne sont pas retéléchargées, mais le registre est
interrogé pour le manifest. Cause vérifiée par [SECU] sur l'archive produite
par `docker save`, que `kind load` appelle [S61] : avec le magasin classique
du moteur (overlay2), l'archive ne garde ni l'index ni le manifest du
registre, seulement un manifest nommé par tag [S63]. Le passage par
containerd reste déduit : une référence par condensat ne retrouve pas
l'image sous ce nom, et le runtime la tire [S58]. Docker Hub compte une
requête GET de manifest comme un tirage [S45]. Le registre reste donc
nécessaire à chaque `task up`, même cache plein, pour toute image désignée
par condensat, celles de l'application comprises : `busybox` est tirée de la
même façon.

[BENCH] Contrôles fonctionnels (M7), sur les quatre exécutions de chaque
option :

| Contrôle | Envoy Gateway | Cilium | Traefik |
| --- | --- | --- | --- |
| CRD Gateway API v1.7.0 standard appliquées, inchangées après installation | Oui, avec `crds.enabled=false` ; le chart par défaut apporte sa copie v1.6.1 expérimentale | Oui ; elles doivent exister avant l'installation de Cilium | Oui ; le chart n'embarque pas de CRD Gateway API |
| Même manifest Gateway et HTTPRoute, seule la ligne `gatewayClassName` change (`diff` : 2 lignes) | Oui | Oui | Oui |
| GatewayClass, Gateway, écouteurs et HTTPRoute `Accepted` et `Programmed` | Oui | Oui | Oui, GatewayClass `Accepted` avec la raison `Handled` |
| Réponse HTTP par `127.0.0.1:18080` | Oui | Oui | Oui |
| Terminaison TLS par `127.0.0.1:18443`, certificat `CN=celian.test` du Secret | Oui | Oui | Oui |
| Réglages nécessaires | EnvoyProxy : Service NodePort, ports 30080 et 30443 fixés par correctif | CNI et kube-proxy de kind désactivés, `kubeProxyReplacement`, `k8sServiceHost`, opérateur à 1 réplique, réseau de l'hôte, `NET_BIND_SERVICE` | Points d'entrée sur 80 et 443, sysctl des ports bas, Service NodePort à ports fixes, Gateway du chart désactivée |

[BENCH] Adresses d'écoute (M8). Côté poste, seuls l'API et les ports 18080 et
18443 sont publiés, tous sur `127.0.0.1`, pour les trois options. Dans le
nœud, Envoy Gateway et Traefik n'ajoutent aucun socket aux écoutes de
Kubernetes ; leurs NodePort 30080 et 30443 restent joignables sur l'adresse
du nœud depuis le réseau Docker `kind`, parce que kube-proxy en iptables les
sert sans socket ouvert [S59], [S60]. `netstat` ne les voit pas ; ce point
est déduit de la documentation, non essayé. Cilium ajoute `0.0.0.0:80` et
`0.0.0.0:443` (la gateway en réseau de l'hôte, l'équivalent de ces
NodePort), `:::4244` (Hubble, en TLS mutuel par défaut), et sans
authentification `0.0.0.0:9964` (métriques de cilium-envoy), `:::9963`
(métriques de l'opérateur) et `192.168.97.2:4240` (santé). Tous ne sont
joignables que depuis le réseau `kind`, pas depuis le réseau local du poste.

[BENCH] Restes : aucun. La liste des volumes Docker est identique avant et
après la série, et le réseau `kind`, créé par le script, a été retiré.

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
| Envoy Gateway | 5/5 | 15 | Apache-2.0, approuvée par l'OSI. Le projet généré ne redistribue pas le contrôleur : il référence ses images | [S1], [S46] |
| Cilium | 5/5 | 15 | Apache-2.0 pour l'espace utilisateur ; gabarits BPF sous GPL-2.0 seule ou BSD-2-Clause, au choix de l'utilisateur. Toutes approuvées par l'OSI, et le choix BSD reste permissif | [S16], [S46] |
| Traefik | 5/5 | 15 | MIT, approuvée par l'OSI. L'éditeur vend une offre commerciale à côté (Traefik Hub, dont le chart embarque les CRD) ; le proxy lui-même n'en dépend pas | [S30], [S37], [S46] |

[BENCH] Le critère ne départage pas : trois licences permissives, compatibles
avec l'Apache-2.0 du générateur.

### 5.2 Gouvernance (fondation, multi-vendeurs), poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Envoy Gateway | 4/5 | 12 | Sous-projet de l'organisation Envoy, couvert par la CNCF au titre d'Envoy (gradué le 2018-11-28), sans revue CNCF propre. Comité de pilotage à sièges d'entreprises (Envoy, Tetrate, SAP, Ambassador Labs, Tencent) ; 10 mainteneurs, au moins 6 employeurs déclarés (Tetrate 3, AMD, SAP, Huawei Cloud, Kubermatic, Salesforce). Réserves : les trois premiers auteurs, tous chez Tetrate, font 51 % des commits humains en 12 mois ; le fichier de gouvernance donne aux sièges une fin au 2025-12-30 et n'a pas changé depuis le 2025-03-04 | [S3], [S4], [S5], [S8], [S9] |
| Cilium | 4/5 | 12 | Projet gradué à la CNCF depuis le 2023-10-11. Contribution très large : 5 123 commits humains par 371 auteurs, le premier à 9,1 %, les deux premiers à 14,5 %. Réserve : 42 des 52 committers dont l'employeur est écrit sont chez Isovalent, soit 81 % | [S18], [S19], [S20] |
| Traefik | 2/5 | 6 | Aucune fondation : le projet appartient à Traefik Labs. 11 des 18 mainteneurs actifs déclarent Traefik Labs, 4 un autre employeur, 3 aucun ; les deux premiers auteurs, chez Traefik Labs, font 35,1 % des commits humains. L'écart au principe V demanderait un ADR | [S30], [S32], [S33] |

### 5.3 Maturité et adoption, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Envoy Gateway | 4/5 | 12 | Créé en avril 2022, version 1.0 le 2024-03-13, déclaré « Conformant » par Gateway API v1.7.0 ; 38 adoptants dans la liste tenue par le projet (dont OpenAI, SAP, Docker, Alibaba Cloud). Il s'appuie sur le proxy Envoy, gradué depuis 2018. Réserve : le plus jeune des trois, en version 1.x depuis vingt mois | [S1], [S2], [S9], [S10], [S40] |
| Cilium | 5/5 | 15 | Créé en 2015, gradué à la CNCF ; 179 entrées dans `USERS.md`, liste tenue par les adoptants eux-mêmes ; présent dans les rapports de conformité de Gateway API depuis la v0.7.1 | [S16], [S20], [S21], [S41] |
| Traefik | 4/5 | 12 | Créé en 2015, version 3.0 le 2024-04-29 ; fournisseur Gateway API sorti de l'expérimental en 3.1.0 (2024-07-15). Réserves : aucune liste d'adoptants tenue par le projet dans le dépôt, et cœur HTTP « partial » au dernier rapport de conformité | [S30], [S31], [S34], [S41] |

### 5.4 Activité et maintenance, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Envoy Gateway | 5/5 | 10 | 31 releases stables en 12 mois, 1 075 commits humains par 211 auteurs, dernier commit le 2026-11-19. Chaque mineure est maintenue environ neuf mois (fin de 1.10 le 2027-05-05) | [S2], [S3], [S6] |
| Cilium | 5/5 | 10 | 41 releases stables en 12 mois sur trois branches, 5 123 commits humains par 371 auteurs, dernier commit le 2026-11-18 | [S17], [S18] |
| Traefik | 5/5 | 10 | 70 releases stables en 12 mois sur les branches 2.11 et 3.x, 814 commits humains par 183 auteurs, dernier commit le 2026-11-18 | [S31], [S32] |

[BENCH] Le critère ne départage pas : trois projets très actifs.

### 5.5 Sécurité (CVE, réactivité), poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Envoy Gateway | 4/5 | 8 | Politique de sécurité et signalement privé GitHub activé ; 17 avis publiés en 12 mois (2 critiques, 5 élevés, 10 moyens), auxquels s'ajoutent ceux du proxy Envoy (1 critique, 16 élevés). Version corrigée publiée au plus tard le jour de chaque avis, aucun avis sur 1.10.0. Contrôleur cantonné à son namespace pour ce qu'il crée. Image du contrôleur signée par cosign selon le workflow de release, signature vérifiée par personne ; image du proxy figée par condensat dans le binaire. Trivy (relecture [SECU]) : 1 CVE élevée dans le contrôleur, CVE-2026-97054 de la bibliothèque standard Go 1.27.3, corrigée en 1.27.4, sur des serveurs joignables seulement depuis le cluster. Mesuré : aucun socket ajouté dans le nœud ; ses NodePort restent joignables depuis le réseau `kind`, comme ceux de Traefik ; côté poste, rien d'autre que `127.0.0.1`. Réserve : le chart désigne le contrôleur par tag ; le blueprint doit passer le condensat, comme le script | [S11], [S12], [S13], [S47], [S56], [S57], [S59], [M8] |
| Cilium | 3/5 | 6 | Politique de sécurité, signalement privé activé, 12 avis en 12 mois (1 critique, 4 élevés), dont un sur la Gateway API (CVE-2026-56742, HTTPRoute qui redirige vers un autre namespace), corrigée en 1.19.5 ; versions corrigées publiées au plus tard le jour de chaque avis. Images figées par condensat par défaut dans le chart, signées par cosign selon les workflows, signatures vérifiées par personne. Mais l'option est la plus privilégiée : agent en réseau de l'hôte avec `NET_ADMIN`, `SYS_ADMIN`, `SYS_MODULE` et d'autres capacités hors de Pod Security Baseline, conteneur d'initialisation `privileged`, et `NET_BIND_SERVICE` à ajouter à Envoy pour les ports 80 et 443. Une faille dans l'agent donne la main sur le nœud et sur le CNI du cluster, pas seulement sur l'entrée ; un Baseline imposé par Kyverno demanderait une exemption permanente sur `kube-system`. S'y ajoutent, sans authentification, les métriques (9963, 9964) et la santé (4240), joignables depuis le réseau `kind` seulement | [S22], [S27], [S28], [S29], [S56], [S57], [S64], [M8] |
| Traefik | 3/5 | 6 | Politique de sécurité et signalement privé activé. Pod non root, capacités retirées, système de fichiers en lecture seule par défaut. Mais 70 avis en 12 mois, dont 2 critiques et 41 élevés, plus qu'Envoy Gateway et Envoy réunis (21 élevés) ; 6 avis en novembre 2026, dont 4 élevés le 2026-11-12, corrigés en 3.7.18. Correctifs publiés au plus tard le jour de l'avis pour 69 avis sur 70. L'image `docker.io/traefik` est une Docker Official Image, construite par docker-library avec des attestations de provenance, vérifiées par personne | [S30], [S37], [S38], [S56], [S57], [M8] |

### 5.6 Empreinte sur PC (RAM, CPU, démarrage), poids 10

[BENCH] Règle et seuils de la section 4.1, écrits avant la première mesure.
La condition 2 est remplie par les trois options : le registre est interrogé
pour chaque image à chaque création, même préchargée (section 4.4). Si l'on
ne compte comme retéléchargement que le transfert des couches, les trois
gagnent un cran ensemble et le classement ne change pas.

[BENCH] Volume noté sur linux_amd64 depuis la relecture [FINOPS] (note
révisée de la section 4.1). Mémoire jugée sur la médiane de M2, comme le
gabarit le prévoit.

[BENCH] Options à moins de 10 % d'un seuil : Envoy Gateway, 1,2 % au-dessus
du seuil de volume en amd64 (505,8 Mo) mais 6,7 % sous lui en arm64
(466,5 Mo) ; Envoy Gateway et Cilium, 7,3 % sous le seuil de mémoire
(948,8 et 948,7 Mio). La marge d'Envoy Gateway en mémoire, 75 Mio, est plus
petite que l'écart entre ses exécutions, 144,2 Mio (exécution 1 à
1 078,3 Mio) : la mesure ne tranche pas ce seuil. Celle de Cilium couvre son
écart (45,9 Mio). Leurs notes possibles sont en section 7.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Envoy Gateway | 3/5 | 6 | Deux conditions remplies : 505,8 Mo à la première création en amd64 (466,5 en arm64), et le registre interrogé à chaque création pour 2 images. M1 à 44,6 s et M2 à 948,8 Mio, sous leurs seuils ; froid en 75,9 s | [M1], [M2], [M5], [M6] |
| Cilium | 3/5 | 6 | Deux conditions remplies : 764,3 Mo à la première création en amd64 (739,2 en arm64 ; 379,5 Mo pour Cilium seul en amd64) et le registre interrogé pour 3 images à chaque création. M1 à 55,8 s, le plus dispersé (41,3 à 73,4 s), M2 à 948,7 Mio ; froid en 146,9 s, le double d'Envoy Gateway | [M1], [M2], [M5], [M6] |
| Traefik | 4/5 | 8 | Une condition remplie : le registre interrogé pour 1 image à chaque création. La plus légère : 440,1 Mo en amd64 (401,7 en arm64), M1 à 43,5 s, M2 à 811,8 Mio, 33,7 Mio pour son pod ; froid en 47,0 s | [M1], [M2], [M4], [M5], [M6] |

### 5.7 Portabilité multi-cloud, poids 10

[BENCH] Mesuré pour les trois options (M7) : le même fichier Gateway et
HTTPRoute, à la ligne `gatewayClassName` près, est accepté et programmé, et
répond en HTTP et en HTTPS. Sur GKE, la classe `gke-l7-global-external-managed`
accepte des écouteurs HTTP et HTTPS, des `certificateRefs` vers des Secrets
Kubernetes et des HTTPRoute [S42] ; GKE tient lui-même les CRD du canal
standard [S43], en v1.5.0 à partir de GKE 1.35.2 [S42] et en v1.6.0 au
rapport de conformité de 1.36.2 [S41]. Le manifest n'emploie que des champs
v1 du cœur, présents dans toutes ces versions. Ce qui diffère porte donc sur
la couche de cible : la configuration de l'option et celle du cluster. La
portabilité se juge sur le seul couple kind et GKE : sur un cloud, le
principe III impose le service managé, et l'on-prem est hors MVP.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Envoy Gateway | 5/5 | 10 | Sur kind, la configuration de l'ADR-004 ne change que par les deux ports publiés. La configuration locale tient dans un objet EnvoyProxy (Service NodePort à ports fixes) référencé par la GatewayClass, propre à la cible PC ; le manifest reste celui de GKE | [M7], [S6], [S15] |
| Cilium | 3/5 | 6 | La gateway exige Cilium comme CNI, avec le remplacement de kube-proxy : sur kind, il faut `disableDefaultCNI` et `kubeProxyMode: "none"`, donc un cluster local plus éloigné de GKE et d'un Kubernetes amont. Exposition par le réseau de l'hôte, faute de port de nœud fixe | [M7], [S22], [S23], [S44] |
| Traefik | 4/5 | 8 | Sur kind, rien ne change au cluster hors les deux ports publiés. Réserve : les ports des écouteurs doivent égaler ceux des points d'entrée de Traefik (8000 et 8443 par défaut). Pour garder le manifest de GKE (80 et 443), il faut changer les points d'entrée et autoriser les ports bas par sysctl. Cœur HTTP « partial » au rapport de conformité | [M7], [S36], [S37], [S41] |

### 5.8 Expérience dev et documentation, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Envoy Gateway | 4/5 | 8 | Documentation à jour par version, matrice de compatibilité datée, état des objets clair (`Accepted`, `Programmed`, `ResolvedRefs`). Réserve : le chart installe par défaut ses propres CRD Gateway API v1.6.1 du canal expérimental ; avec la v1.7.0 standard déjà en place, il faut `crds.enabled=false` et le chart `gateway-crds-helm` pour les seules CRD d'Envoy Gateway. Les ports fixes passent par un correctif du Service dans l'EnvoyProxy | [M7], [S6], [S7], [S14] |
| Cilium | 3/5 | 6 | Fonctionne, mais demande le plus de réglages : CRD présentes avant l'installation, `kubeProxyReplacement`, adresse de l'API (`k8sServiceHost`), un seul opérateur sur un nœud, réseau de l'hôte et capacité pour les ports 80 et 443. La page kind de Cilium ne parle pas de Gateway API, et le cluster ne devient prêt qu'une fois Cilium installé | [M1], [M7], [S22], [S24], [S25], [S28] |
| Traefik | 4/5 | 8 | Un seul chart, qui crée aussi la GatewayClass ; conditions `Accepted` et `Programmed` claires. Réserve : correspondance entre points d'entrée et écouteurs à régler, et chart qui déploie par défaut sa propre Gateway (désactivée ici) | [M7], [S36], [S37] |

### 5.9 Coût (managé ou opérationnel), poids 5

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Envoy Gateway | 5/5 | 5 | Aucune licence ni service payant sur le PC | [S1] |
| Cilium | 5/5 | 5 | Aucune licence ni service payant sur le PC | [S16] |
| Traefik | 5/5 | 5 | Aucune licence ni service payant sur le PC | [S30] |

[BENCH] Le critère ne départage pas. Sur GCP, la gateway est le contrôleur
Gateway de GKE quel que soit le choix local : l'ADR-009 en fait le service
managé de la cible `gcp`, lecture des principes III et V proposée et en
attente de Lucas. Google l'offre sans surcoût dans la tarification de GKE et
facture les ressources Compute Engine qu'il crée [S66] : le choix local ne
change rien à la facture GCP. Le temps et la mémoire du poste sont comptés
en 5.6, rien n'est compté deux fois ([FINOPS], section 10).

## 6. Grille pondérée

| Critère | Poids | Envoy Gateway | Cilium | Traefik |
| --- | --- | --- | --- | --- |
| Critères éliminatoires (section 3) | éliminatoire | passe | passe | passe |
| Licence et liberté d'usage | 15 | 5/5, 15 pts | 5/5, 15 pts | 5/5, 15 pts |
| Gouvernance (fondation, multi-vendeurs) | 15 | 4/5, 12 pts | 4/5, 12 pts | 2/5, 6 pts |
| Maturité et adoption | 15 | 4/5, 12 pts | 5/5, 15 pts | 4/5, 12 pts |
| Activité et maintenance | 10 | 5/5, 10 pts | 5/5, 10 pts | 5/5, 10 pts |
| Sécurité (CVE, réactivité) | 10 | 4/5, 8 pts | 3/5, 6 pts | 3/5, 6 pts |
| Empreinte sur PC (RAM, CPU, démarrage) | 10 | 3/5, 6 pts | 3/5, 6 pts | 4/5, 8 pts |
| Portabilité multi-cloud | 10 | 5/5, 10 pts | 3/5, 6 pts | 4/5, 8 pts |
| Expérience dev et documentation | 10 | 4/5, 8 pts | 3/5, 6 pts | 4/5, 8 pts |
| Coût (managé ou opérationnel) | 5 | 5/5, 5 pts | 5/5, 5 pts | 5/5, 5 pts |
| Total | 100 | 86 / 100 | 81 / 100 | 78 / 100 |

## 7. Verdict proposé

[BENCH] Option proposée : Envoy Gateway pour la cible `local`, 86 sur 100.
Cilium suit à 81, 5 points derrière, et Traefik à 78. Envoy Gateway était
l'option pressentie par le PRD ; elle a été notée avec le même script, le
même manifest et les mêmes seuils que les deux autres, et la révision du
volume après relecture la pénalise. Sur `gcp`, la gateway reste le
contrôleur de GKE (ADR-009, en attente de Lucas).

[BENCH] Pourquoi. Envoy Gateway est la seule option qui cumule une
gouvernance ouverte (sous-projet de l'organisation Envoy, couvert par la
CNCF au titre d'Envoy, gradué le 2018-11-28, sans revue CNCF propre ; au
moins six employeurs parmi les mainteneurs) [S4], [S5], [S8], [S50], une
portabilité complète entre kind et GKE (même manifest à la classe près, rien
à changer au cluster) [M7], et les privilèges les plus bas : contrôleur
cantonné à son namespace pour ce qu'il crée, aucun socket ajouté dans le
nœud ; ses NodePort restent joignables depuis le réseau `kind`, comme pour
Traefik [M8], [S59]. Cilium gagne sur la maturité [S20],
[S21], mais perd sur la portabilité et l'expérience : il faut lui céder le
CNI et kube-proxy du cluster, ce qui éloigne kind d'un Kubernetes amont,
double le démarrage à froid (146,9 s contre 75,9), ajoute 379,5 Mo à
télécharger en amd64 [M1], [M5], [M6], et demande les privilèges les plus
larges [S64]. Traefik est le plus léger [M2], [M4], [M6],
mais il appartient à un seul éditeur, sans fondation [S33], et a publié
70 avis de sécurité en douze mois [S38].

[BENCH] Sensibilité. Aucun changement d'un seul cran ne renverse le
classement ; un cran vaut au plus 3 points.

- Empreinte d'Envoy Gateway notée sur l'amd64, pire cas des systèmes visés
  (Q5) : 505,8 Mo, 1,2 % au-dessus du seuil, 3/5 et 86. Sur l'arm64 du
  poste de mesure, 466,5 Mo, 4/5 et 88. Sa mémoire médiane, 948,8 Mio, est
  7,3 % sous le seuil, mais l'exécution 1 le dépasse (1 078,3 Mio) et
  l'écart entre exécutions (144,2 Mio) dépasse la marge (75 Mio). À 2/5,
  Envoy Gateway tombe à 84 et reste premier ; il faut en plus un cran de
  gouvernance pour Cilium pour une égalité.
- Cilium monte à 85 avec un cran de plus en sécurité et un en portabilité,
  et à 88 avec un cran de gouvernance en plus ; Traefik passe à 81 avec un cran de plus en gouvernance, à
  80 avec un cran de plus en sécurité.

| Sensibilité, à partir des totaux proposés | Envoy Gateway | Cilium | Traefik |
| --- | --- | --- | --- |
| Base : volume en amd64, mémoire à la médiane | 86 | 81 | 78 |
| Volume noté en arm64, méthode écrite en 4.1 | 88 | 81 | 78 |
| Mémoire d'Envoy Gateway au-dessus du seuil, comme à l'exécution 1 | 84 | 81 | 78 |
| Mémoire de Cilium au-dessus du seuil | 86 | 79 | 78 |
| Condition 2 lue comme le seul transfert des couches | 88 | 83 | 80 |
| Mémoire d'Envoy Gateway au-dessus et Cilium à 5 en gouvernance | 84 | 84 | 78 |

[BENCH] Le classement de tête tient donc dans tous les cas d'un seul cran ;
il ne devient une égalité qu'avec deux changements défavorables à Envoy
Gateway et favorables à Cilium.

[BENCH] Réserves à surveiller :

- les trois premiers auteurs d'Envoy Gateway, tous chez Tetrate, font 51 %
  des commits humains, et son fichier de gouvernance n'est plus à jour
  [S3], [S4] ;
- ses CRD font passer le serveur d'API de 231,5 à 469,6 Mio en médiane
  (511,2 Mio à l'exécution 1, la plus haute) [M4] : les deux tiers des
  357,2 Mio qui séparent sa plate-forme de kind seul. Le chart `gateway-crds-helm` installe toutes les
  CRD d'Envoy Gateway ; [ARCHI] et [OPS] peuvent vérifier si le blueprint
  en a besoin de toutes ;
- son chart désigne le contrôleur par tag et apporte des CRD Gateway API
  v1.6.1 expérimentales : le blueprint passe le condensat et
  `crds.enabled=false` [S7], [S14] ;
- Gateway API v1.7.0 standard dépasse la version testée par Envoy Gateway
  1.10 (v1.6.1) [S6] : la v1.7.0 a fonctionné ici, mais la version des CRD
  du projet généré reste à fixer par l'ADR, en tenant compte de GKE
  (v1.5.0 à v1.6.0) [S41], [S42] ;
- l'image `docker.io/envoyproxy/ratelimit:5ae0682e` reste désignée par tag
  dans les valeurs du chart. Elle ne tourne que si la limitation de débit
  est activée, ce qui n'est pas le cas ici : à figer par condensat si
  l'ADR l'active ([SECU], [S14]) ;
- la CVE élevée de Go 1.27.3 dans le contrôleur partira avec un correctif
  1.10.x recompilé, à suivre ([SECU], section 10) ;
- sur GKE, chaque Gateway a sa propre adresse IP et son propre équilibreur
  de charge facturé [S66]. Le coût de démo dépend du nombre de Gateway du
  blueprint : [FINOPS] recommande une seule Gateway pour l'API et le front,
  comme le manifest de test. Montant non chiffré, la grille réseau étant
  illisible le 2026-11-19 [S67] (R-05) ;
- prochaine vérification proposée : 2027-05-05, fin de maintenance
  d'Envoy Gateway 1.10 [S6].

[BENCH] Changements à la configuration kind de l'ADR-004 :

- avec Envoy Gateway ou Traefik : seulement deux `extraPortMappings` vers
  les ports de nœud fixés pour la gateway (30080 et 30443 ici), avec
  `listenAddress: "127.0.0.1"`. Le reste de la configuration de BENCH-003
  ne bouge pas. Côté Envoy Gateway, un objet EnvoyProxy (Service NodePort et
  correctif des ports) rattaché à la GatewayClass locale ;
- avec Cilium : `networking.disableDefaultCNI: true`, `kubeProxyMode:
  "none"`, `extraPortMappings` vers les ports 80 et 443 du nœud, et
  l'adresse de l'API passée au chart (`k8sServiceHost:
  <cluster>-control-plane`). Le cluster n'est prêt qu'une fois Cilium
  installé, et chaque création interroge quay.io pour trois images (R-25).

[BENCH] Conditions de [SECU] pour l'ADR-005, si Envoy Gateway est retenu :

1. le blueprint force le condensat du contrôleur, met `crds.enabled=false`,
   et fige aussi `ratelimit` s'il l'active ;
2. les objets `gateway.envoyproxy.io` (EnvoyProxy, politiques de sécurité et
   de trafic) n'existent pas sur GKE : ils restent dans la couche `local`,
   la couche commune ne contient que des objets Gateway API du cœur, et une
   politique conftest ou Kyverno refuse ce groupe hors de la couche
   `local`. Sinon, un contrôle posé en local disparaîtrait sans bruit en
   production ;
3. la CI vérifie les signatures cosign du contrôleur avec l'identité du
   workflow de release, une fois cosign installé et la commande vérifiée sur
   sa documentation ;
4. R-25 est traité avant le golden repo : sans préchargement sous le
   condensat du registre, la condition 7 de l'ADR-004 (recréation hors
   ligne) ne passe pas, quelle que soit la gateway.

[BENCH] Suites :

- l'ADR de la gateway, écrit par [ARCHI] (ADR-005), qui fixe aussi la
  version des CRD Gateway API et la façon de les livrer au projet ;
- une entrée de `catalog/` si l'ADR suit ce verdict, sous `targets.local`
  seulement, type `oss` : Envoy Gateway 1.10.0, Apache-2.0, sous-projet de
  l'organisation Envoy (CNCF au titre d'Envoy), actif, vérifié le
  2026-11-19, sources [S1], [S6], [S8], chart `gateway-helm` v1.10.0 en
  `0f72c905…e659`, contrôleur en `sha256:c2243d43…72b1`. La ligne `gcp`
  est le contrôleur Gateway de GKE, type `managed`, sans `managed_gap`
  (ADR-009) ;
- pour R-25 : le préchargement par `kind load` n'évite pas l'appel au
  registre pour toute image désignée par condensat, celles de
  l'application comprises (section 4.4). Il faut précharger sous le
  condensat du registre : [OPS] et BENCH-005 ont à essayer un registre
  miroir local en boucle locale, une archive OCI qui garde l'index du
  registre, ou le magasin d'images containerd du moteur [S63]. Revenir à
  des références par tag ou à `imagePullPolicy: Never` est à refuser [S58] ;
- pour R-04 : le DSI le passe en probabilité forte, avec un déclencheur lu
  sur le premier lancement complet et sur le pire cas de Q5 (505,8 Mo en
  amd64 avant les images de la stack). Décision à confirmer par Lucas à la
  GATE 1 ;
- pour R-20 (« Identifiants par défaut dans le golden repo ») : la
  configuration mesurée ne publie rien hors de `127.0.0.1` côté poste, avec
  les trois options. Les trois contrôleurs lisent tous les Secrets du
  cluster : un contrôleur compromis lirait les mots de passe locaux de la
  base et du cache ([SECU], section 10) ;
- pour [OPS] : laisser les mises à jour de sécurité passer sans le délai de
  7 jours de Renovate, syntaxe à vérifier sur sa documentation ([SECU]).

## 8. Limites et biais

| Limite | Effet possible sur le verdict | Ce qui la lèverait |
| --- | --- | --- |
| Une seule machine, sous macOS, avec OrbStack, moteur non libre (R-26) | Empreinte propre à ce poste ; le comportement du port publié et du préchargement peut dépendre du moteur | Relancer le script sous Linux avec Docker Engine, sous Docker Desktop, et avec Docker Engine 29 en installation neuve, dont le magasin d'images par défaut est containerd [S63] |
| Trois exécutions à chaud : la marge d'Envoy Gateway sous le seuil de mémoire (75 Mio) est plus petite que l'écart entre ses exécutions (144,2 Mio) | Note d'empreinte d'Envoy Gateway à 3 ou à 2 (86 ou 84), sans effet sur le rang | Deux exécutions à chaud de plus pour Envoy Gateway (`OPTIONS=envoy-gateway`, `RUNS`), sans action payante |
| Une seule exécution à froid par option, sur le réseau du poste, et deux registres : Docker Hub pour Envoy Gateway et Traefik, quay.io pour Cilium | M5 dépend du débit et du registre du moment ; le volume (M6), lui, n'en dépend pas | Plusieurs exécutions à froid, sur un autre réseau et sur un runner amd64 |
| Préchargement mesuré avec le magasin classique du moteur (overlay2) : l'archive de `docker save` ne garde pas le condensat du registre (vérifié par [SECU]), et le nœud interroge le registre pour chaque image désignée par condensat (passage par containerd déduit) | Condition 2 de l'empreinte remplie par les trois options ; avec le magasin d'images containerd du moteur ou un registre miroir local, elle pourrait ne plus l'être | Refaire le préchargement avec le magasin containerd, ou avec un registre local (BENCH-005), puis relancer M6 |
| Configuration par défaut des charts, hors réglages nécessaires : Traefik garde ses fournisseurs Ingress et CRD, Cilium garde Hubble | Empreinte un peu surestimée pour Traefik et Cilium | Mesurer la configuration que retiendra le blueprint |
| Cilium mesuré en mode réseau de l'hôte, parce que kind n'a pas de répartiteur de charge et que `CiliumGatewayClassConfig` ne fixe pas le port de nœud [S23] ; ni LB-IPAM de Cilium ni cloud-provider-kind n'ont été essayés | Sécurité et portabilité de Cilium jugées sur ce seul mode | Essayer une de ces deux voies avec [OPS] |
| Gateway API v1.7.0 du canal standard, au-delà des versions testées par les options (v1.6.1 dans les rapports, v1.6.3 dans les documentations) | Un champ nouveau de la v1.7.0 pourrait être ignoré ; le manifest de test n'en emploie aucun | Rapports de conformité v1.7 des options, ou CRD figées à la version que l'ADR retiendra |
| Versions publiées depuis moins de 7 jours au moment de la mesure : Cilium 1.20.5 (2 jours) et Traefik 3.7.19 (6 jours), contre le délai de Renovate (principe VI) | Le blueprint partirait de la version précédente, non mesurée | Relancer avec les versions que fixera l'ADR |
| GKE jugé sur sa documentation et son rapport de conformité, sans cluster réel (principe X) | La portabilité du manifest n'est pas prouvée par un essai sur GKE | Un test de la matrice sur GKE, après accord de Lucas |
| Mesure au repos, un nœud, une route, aucune charge | Ne dit rien de la tenue sous la charge du projet ni sur un portable de 8 Gio | Mesurer `task up` sur le golden repo et en BENCH-005 |
| Notes de jugement : gouvernance, sécurité de Cilium et de Traefik, expérience dev | Le classement de tête peut en dépendre (section 7) | Relectures de [SECU] et [FINOPS], avis de Lucas dans l'ADR |
| Gouvernance mesurée par les identifiants des commits ; employeurs déclaratifs | Un compte multiple ou un profil faux fausserait les parts | Relire la liste des auteurs à la main |
| Cause de l'absence de réponse au premier client HTTP/1.0 non établie (section 4.3) | Un autre client pourrait se comporter autrement | Essayer un client HTTP complet hors de la liste des commandes interdites |
| Images scannées une seule fois, par la relecture [SECU] (Trivy 0.76.2, base du 2026-11-19) ; signatures et attestations annoncées, vérifiées par personne (cosign absent du poste) | Des CVE publiées après le 2026-11-19 échappent à la note ; l'intégrité au-delà du condensat n'est pas prouvée | Scan en CI du projet généré ; vérification cosign du contrôleur (condition 3 de [SECU]) |
| Joignabilité des NodePort depuis le réseau `kind` déduite de la documentation de kube-proxy, non essayée | Comparaison des ports dans le nœud fondée sur une déduction | Une requête vers l'adresse du nœud depuis un autre conteneur du réseau `kind` |
| Effets de bord hors du dossier d'essai | Les images de la gateway restent dans le cache Docker ; Helm 4.3.2 a été installé par Homebrew | Retirer ces images par leur référence exacte après décision |

## 9. Sources

[BENCH] Les dates de release, les comptes d'activité et les métadonnées des
dépôts viennent de l'API publique de GitHub, lue le 2026-11-19. Un commit est
compté humain quand son auteur n'est pas un robot (`bot`, `renovate`,
`dependabot`, `github-actions`, `copilot` filtrés par leur nom). Les
employeurs sont ceux que les profils GitHub déclarent.

[BENCH] S50 à S65 viennent de la relecture de [SECU], S66 et S67 de celle
de [FINOPS] (F1 et F2), toutes lues le 2026-11-19. S48 et S49 ne sont pas
attribués. Quand une source de relecture reprend une page déjà citée, sa
ligne le dit et ne garde que le relevé nouveau.

| ID | URL | Lue le | Ce que la source établit | Officielle |
| --- | --- | --- | --- | --- |
| S1 | <https://github.com/envoyproxy/gateway> | 2026-11-19 | Apache-2.0, dépôt non archivé, créé le 2022-04-11 ; `SECURITY.md` ; signalement privé GitHub activé (`/private-vulnerability-reporting`) | Oui |
| S2 | <https://api.github.com/repos/envoyproxy/gateway/releases> | 2026-11-19 | 1.10.0 le 2026-11-06, 1.9.4 le 2026-11-17, 1.0.0 le 2024-03-13 ; 31 releases stables depuis le 2025-11-19 ; aucune release immuable | Oui |
| S3 | <https://api.github.com/repos/envoyproxy/gateway/commits?since=2025-11-19T00:00:00Z> | 2026-11-19 | 1 348 commits sur 12 mois, dont 1 075 humains, par 211 auteurs ; `zirain` 280 (26,0 %), `zhaohuabing` 198, `kkk777-7` 73, tous trois chez Tetrate (51,3 % à eux trois) | Oui |
| S4 | <https://github.com/envoyproxy/gateway/blob/main/GOVERNANCE.md> | 2026-11-19 | Comité de pilotage : siège permanent des mainteneurs d'Envoy, sièges Tetrate, SAP, Ambassador Labs, Tencent, avec une fin au 2025-12-30 ; fichier modifié pour la dernière fois le 2025-03-04 | Oui |
| S5 | <https://github.com/envoyproxy/gateway/blob/main/OWNERS> | 2026-11-19 | 10 mainteneurs ; employeurs déclarés sur leurs profils GitHub (`users/{login}`) : Tetrate 3, AMD, SAP, Huawei Cloud, Kubermatic, Salesforce, 2 sans employeur | Oui, déclaratif |
| S6 | <https://gateway.envoyproxy.io/news/releases/matrix/> | 2026-11-19 | 1.10 : Envoy `distroless-v1.40.x`, Gateway API v1.6.1, Kubernetes 1.34 à 1.37, fin de vie le 2027-05-05 ; 1.9 : fin de vie le 2027-02-14 | Oui |
| S7 | <https://gateway.envoyproxy.io/docs/install/install-helm/> | 2026-11-19 | Chart `oci://docker.io/envoyproxy/gateway-helm` ; l'installation par défaut applique les CRD Gateway API du canal expérimental ; `crds.enabled=false` et chart `gateway-crds-helm` pour les gérer à part | Oui |
| S8 | <https://gateway.envoyproxy.io/about/> | 2026-11-19 | « A proud member of the Envoy Proxy family, backed by the Cloud Native Computing Foundation » | Oui |
| S9 | <https://www.cncf.io/projects/envoy/> | 2026-11-19 | Envoy accepté à la CNCF le 2017-09-13, gradué le 2018-11-28 | Oui |
| S10 | <https://github.com/envoyproxy/gateway/blob/main/site/data/adopters.yaml> | 2026-11-19 | 38 adoptants dans la liste tenue par le projet | Oui, liste du projet |
| S11 | <https://github.com/envoyproxy/gateway/blob/v1.10.0/api/v1alpha1/shared_types.go> | 2026-11-19 | Image du proxy par défaut `docker.io/envoyproxy/envoy:distroless-v1.40.2@sha256:09ca6f21…eded`, figée par condensat | Oui |
| S12 | <https://github.com/envoyproxy/gateway/blob/main/.github/workflows/release.yaml> | 2026-11-19 | `cosign sign` de l'image multi-architecture du contrôleur à chaque release | Oui |
| S13 | <https://api.github.com/repos/envoyproxy/gateway/security-advisories> | 2026-11-19 | 17 avis publiés depuis le 2025-11-19 : 2 critiques, 5 élevés, 10 moyens | Oui |
| S14 | Chart `oci://docker.io/envoyproxy/gateway-helm` v1.10.0, SHA-256 `0f72c905…e659`, et `gateway-crds-helm` v1.10.0, `cc213d90…0aa5` | 2026-11-19 | Contrôleur désigné par tag (`gateway:v1.10.0`) ; sous-chart de CRD avec Gateway API v1.6.1 du canal expérimental et politique `safe-upgrades` ; EnvoyProxy : `envoyService.type` (ClusterIP, LoadBalancer, NodePort), `externalTrafficPolicy` à `Local` par défaut, `patch` | Oui |
| S15 | <https://gateway.envoyproxy.io/docs/tasks/operations/customize-envoyproxy/> | 2026-11-19 | EnvoyProxy rattaché par `parametersRef` à la GatewayClass ou à la Gateway ; correctif `envoyService.patch` | Oui |
| S16 | <https://github.com/cilium/cilium> | 2026-11-19 | Apache-2.0 pour l'espace utilisateur, gabarits BPF sous GPL-2.0 seule ou BSD-2-Clause (`README.rst`, `bpf/COPYING`) ; créé le 2015-12-16, non archivé ; `SECURITY.md`, signalement privé activé | Oui |
| S17 | <https://api.github.com/repos/cilium/cilium/releases> | 2026-11-19 | 1.20.5 le 2026-11-17, 1.20.0 le 2026-07-29 ; 41 releases stables depuis le 2025-11-19, dont 28 immuables, toutes les plus récentes | Oui |
| S18 | <https://api.github.com/repos/cilium/cilium/commits?since=2025-11-19T00:00:00Z> | 2026-11-19 | 5 668 commits sur 12 mois, dont 5 123 humains, par 371 auteurs ; premier auteur à 9,1 %, deux premiers à 14,5 % | Oui |
| S19 | <https://github.com/cilium/cilium/blob/main/MAINTAINERS.md> | 2026-11-19 | 52 committers avec employeur : Isovalent 42, Google 2, Datadog 2, Palantir, Microsoft, Ledger, Hedgehog, AMD | Oui |
| S20 | <https://www.cncf.io/projects/cilium/> | 2026-11-19 | Cilium accepté à la CNCF le 2021-10-13 (incubation), gradué le 2023-10-11 | Oui |
| S21 | <https://github.com/cilium/cilium/blob/main/USERS.md> | 2026-11-19 | 179 entrées, liste tenue par les adoptants | Oui, déclaratif |
| S22 | <https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/> | 2026-11-19 | `kubeProxyReplacement=true` et `l7Proxy=true` exigés ; CRD v1.6.3 dont TLSRoute requises ; `gatewayAPI.enabled` ; Service LoadBalancer par défaut ; mode réseau de l'hôte (`gatewayAPI.hostNetwork.enabled`), ports sous 1024 avec `keepCapNetBindService` et `NET_BIND_SERVICE` | Oui |
| S23 | <https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/parameterized-gatewayclass/> | 2026-11-19 | `CiliumGatewayClassConfig` : type de Service LoadBalancer ou NodePort, aucun champ pour fixer le port de nœud | Oui |
| S24 | <https://docs.cilium.io/en/stable/installation/kind/> | 2026-11-19 | kind avec `disableDefaultCNI: true`, `helm install cilium … --version 1.20.5`, préchargement par `kind load docker-image` ; rien sur Gateway API | Oui |
| S25 | <https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/> | 2026-11-19 | Sans kube-proxy, `k8sServiceHost` et `k8sServicePort` doivent donner l'adresse de l'API | Oui |
| S26 | <https://docs.cilium.io/en/stable/network/kubernetes/compatibility/> | 2026-11-19 | Kubernetes 1.33 à 1.36 testés pour Cilium 1.20 | Oui |
| S27 | <https://api.github.com/repos/cilium/cilium/security-advisories> | 2026-11-19 | 12 avis depuis le 2025-11-19 : 1 critique, 4 élevés, 7 moyens, dont CVE-2026-56742 (HTTPRoute qui redirige vers un autre namespace) | Oui |
| S28 | Chart `cilium` 1.20.5 de <https://helm.cilium.io>, SHA-256 `0c7592eb…1a21` | 2026-11-19 | Images par condensat par défaut ; `operator.replicas: 2` ; capacités d'Envoy `NET_ADMIN`, `SYS_ADMIN` ; `gatewayAPI.enabled: false` par défaut ; Hubble sur `:4244`, métriques de cilium-envoy sur 9964 et de l'opérateur sur 9963 | Oui |
| S29 | <https://github.com/cilium/cilium/blob/main/.github/actions/cosign/action.yaml> | 2026-11-19 | Signature cosign des images dans les workflows de build et de release | Oui |
| S30 | <https://github.com/traefik/traefik> | 2026-11-19 | MIT, créé le 2015-09-13, non archivé ; `SECURITY.md`, signalement privé activé ; 65 594 étoiles | Oui |
| S31 | <https://api.github.com/repos/traefik/traefik/releases> | 2026-11-19 | 3.7.19 le 2026-11-13, 3.0.0 le 2024-04-29 ; 70 releases stables depuis le 2025-11-19 (branches 2.11 et 3.x), aucune immuable | Oui |
| S32 | <https://api.github.com/repos/traefik/traefik/commits?since=2025-11-19T00:00:00Z> | 2026-11-19 | 969 commits sur 12 mois, dont 814 humains, par 183 auteurs ; premier auteur à 20,9 %, deux premiers à 35,1 % | Oui |
| S33 | <https://github.com/traefik/traefik/blob/master/docs/content/contributing/maintainers.md> | 2026-11-19 | 18 mainteneurs actifs ; profils GitHub : 11 déclarent Traefik Labs, 4 un autre employeur, 3 aucun | Oui, déclaratif |
| S34 | <https://github.com/traefik/traefik/blob/master/CHANGELOG.md> | 2026-11-19 | « KubernetesGateway provider is no longer experimental », v3.1.0 du 2024-07-15 | Oui |
| S35 | <https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-gateway/> | 2026-11-19 | Traefik 3.7 prend en charge Gateway API v1.6.3 du canal standard ; TCPRoute du canal expérimental | Oui |
| S36 | <https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/gateway-api/> | 2026-11-19 | « Gateway listener ports must match the configured EntryPoint ports of the Traefik deployment » | Oui |
| S37 | Chart `traefik` 42.4.1 de <https://traefik.github.io/charts>, SHA-256 `80ea7246…acdb` | 2026-11-19 | Points d'entrée `web` 8000 et `websecure` 8443 ; `image.digest` ; pod non root, capacités retirées ; GatewayClass `traefik` créée par le chart ; CRD de Traefik Hub embarquées | Oui |
| S38 | <https://api.github.com/repos/traefik/traefik/security-advisories> | 2026-11-19 | 70 avis depuis le 2025-11-19 : 2 critiques, 41 élevés, 25 moyens, 2 faibles | Oui |
| S39 | <https://github.com/traefik/traefik/blob/v3.7.19/integration/fixtures/gateway-api-conformance/merged/02-traefik.yml> | 2026-11-19 | Pour la conformance, Traefik ouvre ses points d'entrée sur 80 et 443 | Oui |
| S40 | <https://github.com/kubernetes-sigs/gateway-api/releases/tag/v1.7.0> | 2026-11-19 | v1.7.0 publiée le 2026-10-29, release immuable ; `standard-install.yaml` en `sha256:4e2602c4…53a1`, avec la politique d'admission `safe-upgrades` ; « Envoy Gateway moved to Conformant » | Oui |
| S41 | <https://github.com/kubernetes-sigs/gateway-api/tree/main/conformance/reports> | 2026-11-19 | Rapports v1.6 : Envoy Gateway 1.9.0, Cilium 1.20.0, Traefik 3.7.10, GKE 1.36.2-gke.2154000 (détail en section 2) ; aucun rapport v1.7 pour les trois options ; Cilium présent dès les rapports v0.7.1 | Oui |
| S42 | <https://docs.cloud.google.com/kubernetes-engine/docs/how-to/gatewayclass-capabilities> | 2026-11-19 | `gke-l7-global-external-managed` : écouteurs HTTP et HTTPS, `certificateRefs` vers des Secrets, HTTPRoute ; Gateway API 1.5.0 à partir de GKE 1.35.2-gke.1842000 | Oui |
| S43 | <https://docs.cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways> | 2026-11-19 | `--gateway-api=standard` fait installer par GKE les CRD du canal standard ; « GKE Gateway only supports the Gateway API Standard release channel » | Oui |
| S44 | <https://kind.sigs.k8s.io/docs/user/configuration/> | 2026-11-19 | `disableDefaultCNI` (« power user feature with limited support »), `kubeProxyMode: "none"`, `listenAddress` à 0.0.0.0 par défaut, `containerPort` égal au `nodePort` | Oui |
| S45 | <https://docs.docker.com/docker-hub/usage/pulls/> | 2026-11-19 | Une requête GET de manifest compte comme un tirage, un HEAD non ; 100 tirages anonymes par 6 h et par adresse IPv4 | Oui |
| S46 | <https://opensource.org/licenses> | 2026-11-19 | Apache-2.0, MIT, BSD-2-Clause et GPL-2.0 approuvées par l'OSI | Oui |
| S47 | <https://api.github.com/repos/envoyproxy/envoy/security-advisories> | 2026-11-19 | Proxy Envoy : 41 avis depuis le 2025-11-19, dont 1 critique et 16 élevés | Oui |
| S50 | <https://www.cncf.io/projects/envoy/> | 2026-11-19 | Même page que [S9]. Relevé de [SECU] : Envoy Gateway n'y figure que dans des titres de webinaires, sans statut CNCF propre | Oui |
| S51 | <https://www.cncf.io/projects/cilium/> | 2026-11-19 | Même page que [S20], dates confirmées par [SECU] | Oui |
| S52 | <https://github.com/traefik/traefik/blob/master/LICENSE.md>, <https://api.github.com/orgs/traefik> | 2026-11-19 | « Copyright (c) 2016-2020 Containous SAS; 2020-2025 Traefik Labs » ; organisation GitHub nommée « Traefik Labs » | Oui |
| S53 | `gh release verify-asset` sur la release v1.7.0 de Gateway API | 2026-11-19 | Même release que [S40]. Relevé de [SECU] : vérification d'attestation de release réussie, aucune attestation SLSA | Oui |
| S54 | <https://github.com/envoyproxy/gateway/blob/main/.github/workflows/release.yaml> | 2026-11-19 | Même fichier que [S12]. Relevé de [SECU] : lignes 121 à 127, cosign-installer v4.1.3, `cosign sign --yes` sur le condensat de l'index | Oui |
| S55 | <https://github.com/cilium/cilium/blob/main/.github/actions/cosign/action.yaml> | 2026-11-19 | Même fichier que [S29]. Relevé de [SECU] : SBOM et signature des images | Oui |
| S56 | Registres `docker.io` et `quay.io`, lus par `docker buildx imagetools inspect` | 2026-11-19 | Aucun tag `.sig` pour les six images ; index de Traefik avec manifests d'attestation, constructeur `https://github.com/docker-library` | Oui |
| S57 | `https://api.github.com/repos/{envoyproxy/gateway, cilium/cilium, traefik/traefik, envoyproxy/envoy}/security-advisories` et `/releases` | 2026-11-19 | Comptes de [S13], [S27], [S38], [S47] confirmés ; version corrigée publiée au plus tard le jour de l'avis (17 sur 17, 12 sur 12, 69 sur 70) ; aucun avis sur les versions examinées | Oui |
| S58 | <https://github.com/kubernetes/website/blob/main/content/en/docs/concepts/containers/images.md> (commit `3136f09689ce`) | 2026-11-19 | `IfNotPresent` par défaut pour une image par condensat ; le kubelet délègue la présence au runtime ; `Never` échoue si l'image est absente | Oui |
| S59 | <https://github.com/kubernetes/website/blob/main/content/en/docs/concepts/services-networking/service.md> | 2026-11-19 | « Each node proxies that port » ; `nodePortAddresses` à `all` par défaut en iptables et ipvs | Oui |
| S60 | <https://github.com/kubernetes-sigs/kind/blob/main/site/content/docs/user/configuration.md> | 2026-11-19 | Source de la page [S44]. Relevé de [SECU] : kube-proxy de kind en iptables par défaut | Oui |
| S61 | <https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/cmd/kind/load/docker-image/docker-image.go> | 2026-11-19 | Lignes 208 à 210 : `kind load docker-image` appelle `docker save -o` | Oui |
| S62 | <https://kind.sigs.k8s.io/docs/user/quick-start/> | 2026-11-19 | Section de chargement d'images : note sur `IfNotPresent` et `:latest`, rien sur les condensats | Oui |
| S63 | <https://docs.docker.com/engine/storage/containerd/> | 2026-11-19 | Le magasin classique ne gère pas les index d'images ; magasin containerd par défaut sur les installations neuves de Docker Engine 29.0 et plus | Oui |
| S64 | <https://github.com/kubernetes/website/blob/main/content/en/docs/concepts/security/pod-security-standards.md> | 2026-11-19 | Baseline : `net.ipv4.ip_unprivileged_port_start` parmi les sysctls sûrs ; capacités autorisées sans `NET_ADMIN`, `SYS_ADMIN` ni `SYS_MODULE` | Oui |
| S65 | <https://github.com/envoyproxy/gateway/blob/v1.10.0/api/v1alpha1/shared_types.go> | 2026-11-19 | Même fichier que [S11]. Relevé de [SECU] : ligne 30, `DefaultEnvoyProxyImage` par condensat | Oui |
| S66 | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/gateway-api> | 2026-11-19 | Contrôleur mono-cluster « offered at no additional charge as a part of GKE Standard and Autopilot pricing » ; ressources Compute Engine facturées ; « each Gateway corresponds to its own unique IP address and load balancer » | Oui |
| S67 | <https://cloud.google.com/vpc/network-pricing> | 2026-11-19 | Grille réseau illisible : le titre seul, 71 caractères | Oui |

## 10. Relectures

| Relecteur | Porte sur | Date | Avis |
| --- | --- | --- | --- |
| [SECU] | Licences, critères éliminatoires, sécurité, chaîne d'approvisionnement, adresses d'écoute, script | 2026-11-19 | Favorable, avec corrections |
| [FINOPS] | Coût, empreinte, R-04 | 2026-11-19 | Favorable, avec corrections |

[SECU] Licences et statuts CNCF confirmés, aucune note changée. Le scan
Trivy 0.76.2 des six images (base du 2026-11-19) ne trouve aucune CVE
critique et une seule élevée, CVE-2026-97054 dans la bibliothèque standard
Go 1.27.3 du contrôleur Envoy Gateway, corrigée en 1.27.4 : contrôleur 0, 1,
15 (critiques, élevées, moyennes) ; proxy Envoy 0, 0, 15 ; agent Cilium 0,
0, 48 ; opérateur Cilium 0, 0, 0 ; cilium-envoy 0, 0, 18 ; Traefik 0, 0,
12. Corrections intégrées : libellé de gouvernance d'Envoy Gateway, NodePort
joignables depuis le réseau `kind`, note de Cilium recentrée sur ses
privilèges et le CNI, sysctl de Traefik retiré (sûr pour Pod Security
Baseline [S64]), provenance de l'image Traefik, signatures vérifiées par
personne, cause de R-25 vérifiée sur l'archive et portée élargie, quatre
conditions pour l'ADR-005. Le script appelle de nouveau `check_start`
après la prise du verrou.

[FINOPS] Volume noté sur linux_amd64, pire cas des systèmes de Q5, comme
BENCH-008 : Envoy Gateway passe à 3/5 en empreinte, total 86, avance de
5 points. Mémoire jugée sur la médiane, sous le seuil, avec une marge plus
petite que l'écart entre exécutions. Périmètre de la plate-forme de base
écrit en 4.1. Coût 5/5 confirmé pour les trois : le contrôleur de GKE est
sans surcoût, chaque Gateway crée un équilibreur facturé, non chiffré faute
de grille lisible (R-05). R-04 passe en probabilité forte par décision du
DSI, à confirmer par Lucas à la GATE 1.
