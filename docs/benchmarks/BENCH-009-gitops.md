# BENCH-009. Outil GitOps du projet généré

| Champ | Valeur |
| --- | --- |
| Identifiant | BENCH-009 |
| Sujet | Outil GitOps qui synchronise le dépôt du projet généré vers son cluster, sur kind et sur GKE |
| Statut | relu |
| Ouvert le | 2026-11-19 |
| Mis à jour le | 2026-11-19 |
| Auteur | [BENCH] |
| Relecteurs | [SECU] pour les licences et les CVE, [FINOPS] pour les coûts |
| Périmètre | Projet généré sur PC (kind, ADR-004) et projet généré sur GCP (GKE) |
| Choix du PRD | Aucune ligne du tableau des choix ouverts : Argo CD vient du brief (section 6) et de la réponse à Q6 (`docs/prd-mvp.md`, section 8) |
| ADR lié | ADR-010, à écrire par [ARCHI] ; il répond aussi à la question 3 de l'ADR-009 (catalogue) |
| Verdict proposé | Montage C : Config Sync managé sur GKE (principe III, lecture de l'ADR-009 à valider), Flux sur le PC. Grille : Flux 88/100, Argo CD 86, Config Sync 62. L'avance de Flux tient dans un seul cran, la mémoire lue au nœud (section 7) |

## 1. Contexte

[BENCH] Question posée : quel outil GitOps synchronise le dépôt du projet
généré vers le cluster, sur le PC (kind) et sur GCP (GKE), avec des
environnements staging et prod prêts à servir (Q6).

[BENCH] Pourquoi maintenant. Le brief prévoit Argo CD, avec des
ApplicationSets par environnement (section 6), et la réponse à Q6 parle d'une
« structure Argo CD prête pour staging et prod ». En écrivant l'ADR-009,
[ARCHI] a relevé que Google décrit Config Sync comme « a GitOps service
included with Google Kubernetes Engine (GKE) » [S31], sans GKE Enterprise
depuis sa version 1.22.0 du 2025-09-02 [S32]. Le principe III impose sur une
cible cloud le service managé du fournisseur, et la lecture proposée par
l'ADR-009 en tire une règle : III fixe les candidats d'une cible, V les
départage, et un composant libre sur `gcp` demande un `managed_gap` qui dit ce
que le service managé ne couvre pas [S49]. Le choix doit être tranché avant le
golden repo de la phase 2.

[BENCH] Ce qui en dépend. ENF-02 : chaque brique existe sur les deux cibles,
libre sur le PC et managée sur GCP, seule la couche de cible change, et le
README liste les écarts restants. US-005 : `task up` démarre la stack sur le
PC sans autre étape (principe VII). Q5 : le PC visé tourne sous macOS ou
Linux. Q6 : un seul environnement déployé sur GCP, structure prête pour
staging et prod. ENF-03 : dépendances figées, images signées. Principes II,
III, V, VI et VIII. Risques : R-04 (15 minutes), R-17 (tailles par défaut sur
GCP), R-20 (exposition locale), R-25 (registres publics).

[BENCH] La question centrale est la parité d'ENF-02 : les mêmes manifests et
la même structure de dépôt doivent servir sur kind et sur GKE, en ne changeant
que la couche de cible. Elle se traite en section 7, après la grille, parce
qu'elle ne se réduit pas à un critère : elle croise la portabilité (5.7),
l'empreinte (5.6) et le principe III, qui n'est pas dans la grille.

[BENCH] Option pressentie : Argo CD, reprise du brief et de Q6. Elle est
notée comme les autres, avec le même script et les mêmes sources.

[BENCH] Hors champ : la forge et le déclencheur de la CI (GitHub Actions est
fixé par le brief), le déploiement progressif (Argo Rollouts, Flagger), la
mise à jour automatique des images par l'outil GitOps, la gestion des secrets
dans le dépôt (BENCH-007), le mode et le canal du cluster GKE ([OPS]), et
l'outil de la boucle de développement locale (BENCH-005).

## 2. Options étudiées

| Option | En une phrase | Version examinée | Publiée le | Sources |
| --- | --- | --- | --- | --- |
| Argo CD | Contrôleur GitOps avec interface web, API et ApplicationSets, projet Argo de la CNCF | 3.6.2, manifest `manifests/install.yaml` du commit `8e8268ef` (installation « Non-HA ») | 2026-11-18 | [S1], [S2], [S3] |
| Flux | Ensemble de contrôleurs GitOps sans interface (source, kustomize, helm, notification, image), projet de la CNCF | 2.10.0, fichier `install.yaml` de la release | 2026-10-26 | [S14], [S15], [S22] |
| Config Sync | Service GitOps de Google inclus dans GKE ; son code est publié sous licence libre et s'installe hors GKE par un manifest de release | 1.25.2, fichier `config-sync-manifest.yaml` de la release | 2026-11-03 sur GitHub, 2026-11-09 dans les notes de Google | [S26], [S27], [S31], [S32] |

[BENCH] Version d'Argo CD. La 3.6.2 a un jour au moment de la mesure, alors
que le principe VI fait attendre 7 jours aux mises à jour automatiques. Elle
est mesurée parce qu'elle est la dernière stable à la date de lecture, comme
le veut le gabarit ; le blueprint ne pourrait la retenir qu'à partir du
2026-11-25. La 3.6.0 date du 2026-11-03 [S2].

[BENCH] Périmètre des installations de référence. Celle d'Argo CD comprend
l'interface web et l'API, Dex, Redis, les notifications et les
ApplicationSets ; Argo CD Core en retire l'API, les notifications et l'OIDC
[S56]. Le fichier `install.yaml` de Flux contient sept contrôleurs : les
quatre installés par défaut (source, kustomize, helm, notification) et les
trois optionnels (`image-reflector-controller`,
`image-automation-controller`, `source-watcher`) [S57]. Les mesures par pod
permettent de recompter les sous-ensembles (section 4.4).

[BENCH] Config Sync a deux formes, qu'il faut distinguer partout dans ce
rapport. Sur GKE, c'est un service managé : le service Fleet installe et gère
ses composants, après l'inscription du cluster dans une flotte [S33], [S39].
Hors de Google, c'est le même code sous Apache-2.0, installé par
`kubectl apply` d'un manifest de release, sans support annoncé [S26], [S28].
Dans les deux cas, les composants qui tournent dans le cluster sont libres :
Google parle de « hosted components in Google Cloud and open source
components on your Google Kubernetes Engine cluster » [S39].

[BENCH] Options repérées mais non étudiées : Config Controller, qui embarque
Config Sync dans un plan de contrôle hébergé et vise l'infrastructure plus
que l'application ; le Flux Operator de ControlPlane, autre voie
d'installation de Flux [S22]. Aucune des deux n'est dans le brief.

## 3. Critères éliminatoires

[BENCH] Seuil de release : 2025-11-19, douze mois avant la vérification.

| Option | Licence open source | Ni archivé ni en maintenance | Release de moins de 12 mois | Vérifié le | Résultat |
| --- | --- | --- | --- | --- | --- |
| Argo CD | Oui, Apache-2.0 [S1], approuvée OSI [S47] | Oui, dépôt non archivé, dernier commit le 2026-11-19 [S1], [S4] | Oui, 3.6.2 le 2026-11-18 [S2] | 2026-11-19 | Retenue |
| Flux | Oui, Apache-2.0 [S14], approuvée OSI [S47] | Oui, dépôt non archivé, dernier commit le 2026-11-17 [S14], [S16] | Oui, 2.10.0 le 2026-10-26 [S15] | 2026-11-19 | Retenue |
| Config Sync | Oui pour la forme libre, Apache-2.0 [S26], approuvée OSI [S47] ; sans objet pour le service managé de GKE (principe III) | Oui, dépôt non archivé, dernier commit le 2026-11-18 [S26], [S29] | Oui, 1.25.2 le 2026-11-03 [S27] | 2026-11-19 | Retenue |

[BENCH] Réserve forte sur Config Sync pour la cible `local`, sans
élimination. Google écrit « Config Sync can run only on x86-based nodes, not
Arm nodes » [S33], et chacune des 9 images de son manifest n'est publiée que
pour `linux/amd64` [S44]. Sur le poste de mesure, à processeur Apple, le nœud
kind est arm64, et Config Sync y a pourtant démarré et synchronisé les trois
environnements à chaque exécution (section 4.4) : OrbStack exécute les images
x86 par Rosetta [S63]. Ce fonctionnement repose donc sur l'émulation du
moteur de conteneurs, non libre (R-26), et sort de ce que Google prend en
charge. Une élimination au titre d'US-005 et de Q5 aurait été proposée si
Config Sync n'avait pas démarré ; elle ne l'est pas, et la réserve est notée
en portabilité (5.7).

[BENCH] Options éliminées : aucune.

## 4. Mesures

### 4.1 Ce qui est mesuré

[BENCH] Seuils d'empreinte écrits le 2026-11-19 à 12:36 UTC, avant la
première mesure. Chaque option part de 5 et perd un cran par seuil dépassé
(règle de `TEMPLATE.md`, section 5.6). Les seuils de BENCH-003 portaient sur
le cluster entier ; ici l'outil GitOps n'est qu'une brique de la stack qui
tourne dans ce cluster, d'où trois adaptations :

1. volume compressé des images de l'installation de référence au-delà de
   112,5 Mo : 90 s à 10 Mbit/s, soit 10 % du budget de 900 s d'ENF-01, le
   même pourcentage que le seuil de démarrage à chaud de BENCH-003 ;
2. au moins une image retéléchargée à chaque création du cluster, cache
   Docker de l'hôte plein : repris tel quel de BENCH-003 ;
3. installation jusqu'à « prêt » (médiane) au-delà de 90 s, 10 % du budget,
   images tirées par le nœud sur le réseau du poste ;
4. mémoire au repos (médiane) au-delà de 512 Mio : un seizième d'un portable
   de 8 Gio, la moitié du seuil de 1 Gio que BENCH-003 donnait au cluster
   entier, parce que l'outil partage ce cluster avec le reste de la stack.

[BENCH] Biais à déclarer : les tailles compressées des images (seuil 1) ont
été lues dans les registres pendant la recherche, avant l'écriture de ces
seuils. Aucun seuil n'est tiré de ces tailles : 112,5 Mo découle du budget
d'ENF-01 et du débit de 10 Mbit/s déjà retenus pour BENCH-003. Les parts
elles-mêmes (10 % du budget, un seizième de 8 Gio) sont posées par [BENCH] :
le PRD renvoie les budgets par étape après les mesures de phase 1 (ENF-01).

[BENCH] Règle de mémoire d'une couche, posée par le DSI le 2026-11-19 après
les relectures, provisoire jusqu'à la GATE 1, et écrite ici le 2026-11-19 à
23:01 UTC, avant la série de référence. La mémoire d'une option se lit au
nœud kind (`docker stats` sur le conteneur du nœud, médiane de trois
échantillons), moins la mémoire du nœud de base, en médianes. Le nœud de base
a la même configuration sans outil GitOps : même image, même serveur Git de
test, mêmes trois overlays appliqués directement par `kubectl apply -k`,
relevé au même moment. Raison donnée par le DSI : la cohérence avec BENCH-004
et BENCH-007, où les CRD chargent le serveur d'API plus que les contrôleurs,
ce que la somme des pods ne voit pas. Le seuil 4 reste 512 Mio. La somme des
pods de l'outil (M2) passe en sensibilité.

[BENCH] Règle d'égalité, posée par le DSI et écrite au même moment : si Flux
et Argo CD restent à égalité après la règle de mémoire, le verdict garde
l'option déjà nommée par le PRD (Q6), Argo CD, puisqu'une égalité ne donne
aucune raison de changer une décision écrite. Le DSI pose cette règle après
avoir lu l'indice de [FINOPS] : environ 250 Mio au nœud qu'aucun pod d'Argo CD
n'explique, stable sur trois exécutions. Le choix de lire la mémoire au nœud
vient de la cohérence avec BENCH-004 et BENCH-007, pas du résultat attendu ;
mais le lecteur doit savoir que les deux règles sont écrites après cet indice.

| ID | Mesure | Unité | Critère alimenté | Script |
| --- | --- | --- | --- | --- |
| M1 | Installation jusqu'à « prêt », images tirées par le nœud | s | Empreinte sur PC | `tests/bench/bench-009-gitops.sh` |
| M2 | Mémoire de la couche au repos, trois environnements synchronisés : nœud avec l'outil moins nœud de base (M8) ; somme des pods de l'outil en sensibilité | Mio | Empreinte sur PC | `tests/bench/bench-009-gitops.sh` |
| M3 | CPU des pods de l'outil au même moment | % d'un cœur | Empreinte sur PC | `tests/bench/bench-009-gitops.sh` |
| M4 | Première synchronisation de trois environnements depuis un dépôt Git servi dans le cluster | s | Expérience dev, portabilité | `tests/bench/bench-009-gitops.sh` |
| M5 | Prise en compte d'un commit poussé depuis un pod, après demande de rafraîchissement | s | Expérience dev | `tests/bench/bench-009-gitops.sh` |
| M6 | Volume compressé des images, par architecture, et images retéléchargées | Mo | Empreinte sur PC (ENF-01, R-04, R-25) | `tests/bench/bench-009-gitops.sh`, [S44] |
| M7 | Démarrage sur un nœud arm64, et sous quelle condition | oui ou non | Portabilité | `tests/bench/bench-009-gitops.sh` |
| M8 | Mémoire du nœud de base, sans outil GitOps (option `none` du script) | Mio | Empreinte sur PC, base de M2 | `tests/bench/bench-009-gitops.sh` |

### 4.2 Machine de mesure

| Élément | Valeur |
| --- | --- |
| Modèle | Apple Mac16,7 |
| Processeur | Apple M4 Pro, 14 cœurs (10 performance, 4 efficacité), arm64 |
| Mémoire | 24 Gio |
| Système | macOS 27.2.1 (build 26B131) |
| Moteur de conteneurs | OrbStack 2.2.5 (moteur non libre, voir R-26), Docker Engine 29.8.2, noyau 7.2.12-orbstack, cgroup v2, pilote overlay2 |
| Ressources allouées | Machine virtuelle d'OrbStack : 14 CPU, 11,73 Gio (12 598 894 592 octets, `docker info`) |
| Versions mesurées | kind 0.33.0, image de nœud `kindest/node:v1.36.4@sha256:099e…faed` (ADR-004) ; Argo CD 3.6.2, Flux 2.10.0, Config Sync 1.25.2, manifests vérifiés par SHA-256 et images figées par condensat dans le script ; kubectl 1.37.1 |
| Charge parasite | Applications de bureau ouvertes. Charge moyenne sur une minute entre 2,86 et 5,80 au début de chaque exécution de la série principale, entre 2,65 et 5,60 pour la série de référence (`load.tsv`). Aucun autre conteneur actif pendant les séries (verrou partagé tenu par BENCH-009) |

### 4.3 Protocole

1. Préparation, une fois par série. Le script télécharge par `gh` le
   manifest de chaque option et vérifie son SHA-256 contre la valeur figée :
   `install.yaml` d'Argo CD au commit du tag v3.6.2, `install.yaml` de la
   release 2.10.0 de Flux, `config-sync-manifest.yaml` de la release 1.25.2.
   Il réécrit chaque `image:` en `référence@condensat`, avec les condensats
   d'index relevés le 2026-11-19, et s'arrête si une image reste sans
   condensat. Il relève les tailles compressées par architecture dans les
   registres, sans rien tirer (M6). Il construit deux images de test : un
   serveur Git (`git-http-backend` derrière lighttpd, sur Alpine 3.24 figée
   par condensat [S45], [S46]) qui contient le dépôt de test, et une page
   statique sur busybox 1.37.0.
2. État de départ de chaque exécution : aucun cluster `celian-bench-009`. Le
   script crée un cluster kind neuf, attend qu'il soit prêt, y charge les deux
   images de test par `kind load`, démarre le serveur Git et vérifie depuis un
   pod qu'il répond (`git ls-remote`). Les images de l'outil ne sont pas
   préchargées : le nœud les tire à chaque exécution, comme au premier
   `task up` d'un poste.
3. Installation (M1) : la commande documentée de chaque option,
   `kubectl create namespace argocd` puis `kubectl apply -n argocd
   --server-side --force-conflicts -f` pour Argo CD [S3], `kubectl apply -f`
   pour Flux [S22] et pour Config Sync [S28]. Fin de la mesure : le premier de
   trois contrôles consécutifs, espacés d'une seconde, où chaque Deployment et
   StatefulSet de l'outil est prêt et chaque pod Running et Ready.
4. Synchronisation (M4) : les objets de liaison de chaque outil pour les trois
   overlays (un ApplicationSet à générateur de liste pour Argo CD [S12], un
   `GitRepository` et trois `Kustomization` pour Flux [S23], [S24], trois
   `RootSync` pour Config Sync [S40]). Fin : le premier de trois contrôles
   consécutifs où, dans chacun des namespaces `demo-local`, `demo-staging` et
   `demo-prod`, la ConfigMap porte la révision 1 et le Deployment a un pod
   prêt.
5. Repos (M2, M3) : 120 s après la fin de M4, trois échantillons espacés de
   10 s de l'API Summary du kubelet (`/api/v1/nodes/<nœud>/proxy/stats/summary`),
   mémoire de travail et CPU de chaque pod des namespaces de l'outil ; médiane
   des trois. Le conteneur du nœud entier est relevé en même temps par
   `docker stats`, médiane des trois : c'est la valeur que la règle de
   mémoire de 4.1 retient, moins celle du nœud de base (M8).
6. Commit (M5) : un Job lancé dans le cluster clone le dépôt, change la
   révision de l'overlay `local` et pousse. Dès que le Job est vu terminé, le
   script demande un rafraîchissement par l'annotation documentée de l'outil
   [S13], [S23] (aucune pour Config Sync), et mesure jusqu'à voir la révision
   2 dans `demo-local`.
7. Fin : suppression du cluster, 15 s de pause. Trois exécutions par option,
   options alternées (Argo CD, Flux, Config Sync, puis on recommence) pour
   répartir les variations du réseau et de la charge. Les événements `Pulled`
   du nœud donnent les images tirées.
8. Nœud de base (M8), série de référence à part : l'option `none` suit les
   mêmes étapes sans outil GitOps. Les trois overlays sont appliqués par
   `kubectl apply -k`, le repos et les échantillons tombent au même moment,
   et la somme des pods du serveur Git et des démonstrations est relevée pour
   qui veut recompter sur « kind seul » au sens strict.

Pour refaire la mesure :

```bash
BENCH_LOCK=/chemin/vers/un/verrou tests/bench/bench-009-gitops.sh /chemin/vers/un/dossier/vide
OPTIONS=none BENCH_LOCK=/chemin/vers/un/verrou tests/bench/bench-009-gitops.sh /chemin/vers/un/autre/dossier   # nœud de base, M8
```

[BENCH] Sans argument, le script crée un dossier temporaire ; un dossier
passé en argument doit être absent ou vide. `OPTIONS`, `RUNS`, `IDLE_WAIT`,
`BENCH_LOCK` et `NODE_PLATFORM` règlent l'essai. Le script refuse de démarrer
si le cluster existe déjà ou si le verrou est pris (code 75). Son `trap`
n'est posé qu'après ces contrôles, si bien qu'un refus ne supprime rien ;
ensuite il ne supprime que ce cluster et les deux images qu'il a construites,
et libère le verrou. `umask 077`, `KUBECONFIG` dans le dossier d'essai :
`~/.kube` n'est ni lu ni écrit. Aucun port n'est publié vers l'hôte. Il passe
shellcheck et tourne sous le bash 3.2 de macOS.

### 4.4 Résultats

[BENCH] Mesures lancées le 2026-11-19 de 20:51:27 à 21:33:10 UTC, sur la
machine de la section 4.2, verrou partagé tenu, trois exécutions par option,
options alternées. Aucun redémarrage de conteneur dans aucune exécution. Deux
tests de fumée ont précédé la série : le premier a montré qu'un Job lancé
juste après le démarrage du serveur Git ne joint pas encore le Service (échec
en 1 ms), d'où une nouvelle tentative par seconde pendant 60 s au plus dans
les scripts du pod ; le second a validé installation et synchronisation pour
Argo CD avant d'être interrompu.

| Mesure | Option | Exécution 1 | Exécution 2 | Exécution 3 | Médiane | Écart |
| --- | --- | --- | --- | --- | --- | --- |
| M1, installation jusqu'à « prêt » | Argo CD | 31,2 s | 44,9 s | 43,6 s | 43,6 s | 13,7 s |
| M1 | Flux | 30,4 s | 29,1 s | 27,9 s | 29,1 s | 2,5 s |
| M1 | Config Sync, sous émulation | 43,2 s | 44,1 s | 43,1 s | 43,2 s | 1,0 s |
| M2, mémoire des pods de l'outil au repos | Argo CD | 267,4 Mio | 346,1 Mio | 238,3 Mio | 267,4 Mio | 107,8 Mio |
| M2 | Flux | 198,6 Mio | 191,3 Mio | 184,6 Mio | 191,3 Mio | 14,0 Mio |
| M2 | Config Sync, sous émulation | 1 282,6 Mio | 1 292,8 Mio | 1 282,6 Mio | 1 282,6 Mio | 10,2 Mio |
| M3, CPU des pods de l'outil au repos | Argo CD | 1,5 % | 1,6 % | 1,6 % | 1,6 % | 0,1 % |
| M3 | Flux | 1,3 % | 0,9 % | 1,0 % | 1,0 % | 0,4 % |
| M3 | Config Sync, sous émulation | 8,9 % | 9,6 % | 11,2 % | 9,6 % | 2,3 % |
| M4, synchronisation de trois environnements | Argo CD | 2,3 s | 2,3 s | 2,3 s | 2,3 s | 0,0 s |
| M4 | Flux | 2,3 s | 2,3 s | 2,3 s | 2,3 s | 0,0 s |
| M4 | Config Sync, sous émulation | 51,7 s | 53,9 s | 52,7 s | 52,7 s | 2,2 s |
| M5, commit appliqué | Argo CD | 1,1 s | 1,1 s | 1,1 s | 1,1 s | 0,0 s |
| M5 | Flux | 1,1 s | 1,1 s | 1,1 s | 1,1 s | 0,0 s |
| M5 | Config Sync, sous émulation, sans demande de rafraîchissement | 19,3 s | 18,2 s | 18,1 s | 18,2 s | 1,2 s |

[BENCH] Lecture. M4 et M5 d'Argo CD et de Flux sont au plancher de la
méthode : un tour de contrôle (six appels à l'API) dure environ 1,1 s, si
bien que 2,3 s veut dire « au deuxième tour » et 1,1 s « au premier ». Les
deux outils ne se départagent pas là-dessus. Pour Config Sync, M5 suit
l'interrogation de Git toutes les 15 s [S40], faute de demande de
rafraîchissement.

[BENCH] Mémoire par composant, médiane des trois exécutions. Argo CD :
`argocd-application-controller` de 81 à 194 Mio selon l'exécution, d'où
l'écart de M2, `argocd-server` 40 Mio, `argocd-repo-server` 30 Mio, Dex 25,
ApplicationSet 25, notifications 23, Redis 10. Flux : kustomize-controller 41
à 54 Mio, notification 29 à 35, source 25 à 29, helm 25 à 27, et 17 à 20 pour
chacun des trois contrôleurs optionnels ; les quatre contrôleurs par défaut
font 133,5 Mio en médiane des sommes par échantillon, la méthode de M2
(129,2 Mio en sommant les médianes par pod). Config Sync : un réconciliateur
par `RootSync`,
de 266 à 278 Mio chacun, plus 183 à 186 Mio pour `reconciler-manager` comme
pour `resource-group-controller-manager`, et 106 à 109 Mio pour le collecteur
OpenTelemetry. Le nœud entier, cluster compris, pèse en médiane 913,5 Mio
avec Flux, 1 259,5 Mio avec Argo CD et 2 124,8 Mio avec Config Sync.

[BENCH] Nœud de base (M8), série de référence lancée le 2026-11-19 de
23:21:37 à 23:31:37 UTC, même machine, verrou partagé tenu, charge moyenne
entre 2,65 et 5,60. Mêmes étapes que la série principale, sans outil
GitOps : 604,3, 648,3 et 656,5 Mio au nœud, médiane 648,3 Mio, écart
52,2 Mio. Le serveur Git et les trois démonstrations n'en pèsent que 2,1 Mio
(somme des pods, médiane) : la base vaut pratiquement « kind seul ».

[BENCH] Mémoire de la couche selon la règle de 4.1, nœud avec l'outil moins
nœud de base, en médianes :

| Option | Nœud avec l'outil | Nœud de base | Couche (M2) | Somme des pods de l'outil (sensibilité) | Écart non expliqué par les pods | Seuil de 512 Mio |
| --- | --- | --- | --- | --- | --- | --- |
| Argo CD | 1 259,5 Mio | 648,3 Mio | 611,2 Mio | 267,4 Mio | 343,8 Mio | Dépassé, de 19 % |
| Flux | 913,5 Mio | 648,3 Mio | 265,2 Mio | 191,3 Mio | 73,9 Mio | Sous le seuil, à 52 % |
| Config Sync, sous émulation | 2 124,8 Mio | 648,3 Mio | 1 476,5 Mio | 1 282,6 Mio | 193,9 Mio | Dépassé, indicatif |

[BENCH] Le dépassement d'Argo CD ne dépend pas du choix de la médiane : ses
trois exécutions donnent 611,2, 679,8 et 562,1 Mio contre la base médiane, et
même la base la plus haute (656,5 Mio) laisse 603,0 Mio. Flux reste sous le
seuil avec la base la plus basse (309,2 Mio). La part d'Argo CD qu'aucun pod
n'explique (343,8 Mio) va dans le sens de l'hypothèse de BENCH-004 et
BENCH-007, un serveur d'API chargé par les CRD ; rien ne l'attribue encore.

[BENCH] Config Sync sur arm64 (M7). Le nœud est `arm64` (relevé par l'API) et
les images de Config Sync n'existent qu'en `linux/amd64` [S44] ; elles ont été
tirées puis exécutées. OrbStack exécute les images x86 par Rosetta [S63] :
c'est cette émulation qui fait tourner Config Sync ici. Ses chiffres ne valent
donc ni pour un PC x86 natif, ni pour un moteur sans émulation x86, et Google
ne prend pas ce cas en charge [S33]. Un fait reste acquis : la forme libre de
Config Sync a synchronisé la même base et les mêmes overlays que les deux
autres outils, `../../base` compris, avec trois `RootSync` en format
`unstructured`. Ses mesures de M1 à M5 ne fondent aucun cran ; les constats
statiques (droits, images, valeurs par défaut de la CRD) restent valables.

[BENCH] Deux réserves de protocole. Le PC n'a besoin que de l'environnement
`local`, et Q6 n'en déploie qu'un sur GCP : synchroniser trois environnements
ne change presque rien pour Argo CD et Flux (un seul jeu de contrôleurs) mais
triple les réconciliateurs de Config Sync. Et M1 ne découpe pas Config Sync
comme les deux autres : ses images `reconciler`, `git-sync` et
`hydration-controller` sont tirées à la création des `RootSync`, donc pendant
M4, qui les contient, quand M1 les exclut.

[BENCH] Volume des images (M6), en Mo compressés (10^6 octets), somme des
couches et de la configuration lue dans les registres par
`docker manifest inspect -v`, sans rien tirer [S44]. Les images sont figées
par condensat d'index ; le nœud tire la variante de son architecture.

| Option | Images | arm64 (poste de mesure) | amd64 (PC x86, runners GitHub) | Sous-ensemble |
| --- | --- | --- | --- | --- |
| Argo CD | `argocd` (8 conteneurs), `dex`, `redis` | 304,5 : `argocd` 219,8, `dex` 46,0, `redis` 38,7 | 320,7 : 231,1, 50,6, 39,0 | Argo CD Core (`core-install.yaml`, `argocd` et `redis` seulement) : 258,5 en arm64, 270,1 en amd64 [S51], [S56] |
| Flux | 7 contrôleurs | 364,7 | 392,1 | Les 4 contrôleurs par défaut [S57] : 240,5 en arm64, 258,1 en amd64 |
| Config Sync | 9 images ; `helm-sync`, `oci-sync` et `gcenode-askpass-sidecar` ne servent qu'à certaines sources [S39] | Aucune image publiée | 495,9, dont le collecteur OpenTelemetry 200,0 | Images réellement tirées dans l'essai : 407,6 en amd64 |

[BENCH] Les trois options dépassent le seuil de 112,5 Mo, même réduites à
leur sous-ensemble ; la note se lit sur l'amd64, pire cas des systèmes de Q5.
kind crée à chaque fois un nœud neuf, dont le magasin d'images ne contient
que celles du cluster : les images de l'outil sont retéléchargées à chaque
création tant que le blueprint ne les précharge pas sous le condensat du
registre (seuil 2). `kind load docker-image` ne suffit pas : depuis un
magasin classique comme celui du poste, l'archive ne garde que le tag, et le
nœud, qui cherche `…@sha256:…`, repasse par le registre, même en
`IfNotPresent` (constat de [SECU] pour BENCH-004). Les événements `Pulled` le confirment : chaque
exécution retire toutes les images de l'outil. Pour Argo CD, l'image
`argocd` est « tirée » huit fois par exécution, une par conteneur, effet de
`imagePullPolicy: Always` [S51], [S62].

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

[BENCH] Chaque option est notée comme outil GitOps du projet généré sur ses
deux cibles. Pour Config Sync, cela veut dire le service managé sur GKE et la
forme libre sur le PC ; les notes qui ne valent que pour l'une des deux le
disent. Le principe III, qui impose le service managé sur `gcp`, n'est pas un
critère de la grille : il est traité en section 7.

### 5.1 Licence et liberté d'usage, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Argo CD | 4/5 | 12 | Apache-2.0 pour Argo CD et pour Dex. Réserve : l'installation de référence tire `redis:8.10.1-alpine`, et Redis 8 est sous triple licence RSALv2, SSPLv1 ou AGPLv3 ; il ne reste libre que par l'AGPLv3, que R-10 demande de suivre. Le projet généré n'embarque pas l'image, il la tire | [S1], [S47], [S51], [S53], [S54] |
| Flux | 5/5 | 15 | Apache-2.0 pour la CLI et pour chacun des sept contrôleurs de l'installation de référence | [S14], [S47], [S54] |
| Config Sync | 5/5 | 15 | Forme libre sous Apache-2.0, comme `git-sync` et le collecteur OpenTelemetry qu'elle embarque. Sur GKE, service managé : licence sans objet (principe III, ADR-009) | [S26], [S47], [S49], [S54] |

### 5.2 Gouvernance (fondation, multi-vendeurs), poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Argo CD | 5/5 | 15 | Projet Argo, gradué à la CNCF le 2022-12-06. 52 mainteneurs ont un rôle sur Argo CD, de 18 organisations déclarées, dont Red Hat (12), Akuity (11), Intuit (8) et Octopus Deploy (4) ; les deux responsables d'Argo CD viennent d'Intuit et d'Akuity. 1 447 commits humains hors fusion par 417 auteurs en 12 mois ; le premier en fait 7,7 %, les deux premiers 14,0 % | [S4], [S5], [S6], [S48] |
| Flux | 4/5 | 12 | Gradué à la CNCF le 2022-11-30. Neuf mainteneurs principaux : trois chez ControlPlane, un chez NexHealth, un chez Associmates, un chez SUSE, trois indépendants. Réserve : deux mainteneurs de ControlPlane font 62,0 % des commits humains hors fusion de `flux2`, et le premier seul de 53,7 à 70,2 % dans les contrôleurs source, kustomize et helm ; la politique de sécurité parle d'un projet « maintained by volunteers », traité « on a best-effort basis » | [S16], [S17], [S18], [S19], [S48] |
| Config Sync | 2/5 | 6 | Éditeur unique, Google, sans fondation. 126 commits humains par 8 auteurs en 12 mois, le premier à 47,6 %, les deux premiers à 75,4 %. Sur `gcp`, selon la lecture des principes III et V proposée par l'ADR-009, à valider par Lucas, ce n'est pas une dérogation ; sur le PC, le principe V demanderait un ADR pour justifier l'écart | [S26], [S29], [S49] |

### 5.3 Maturité et adoption, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Argo CD | 5/5 | 15 | Dépôt créé en 2018, version majeure 3, gradué à la CNCF. 451 organisations dans `USERS.md`, liste tenue par le projet et déclarative. AWS le propose en service managé sur EKS | [S1], [S6], [S10], [S42] |
| Flux | 5/5 | 15 | Flux v2 depuis 2020, gradué à la CNCF. 127 adoptants de Flux v2 sur le site du projet, liste déclarative. Microsoft le propose en extension managée d'AKS | [S14], [S18], [S25], [S43] |
| Config Sync | 4/5 | 12 | Notes de version depuis au moins la 1.3.3 du 2020-07-30 ; inclus dans GKE, Standard et Autopilot. Réserve : aucune liste d'adoptants, et la forme libre, publiée depuis 2022, n'annonce aucun support | [S27], [S28], [S32], [S35] |

### 5.4 Activité et maintenance, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Argo CD | 5/5 | 10 | 68 releases stables en 12 mois, de la 3.0 à la 3.6 ; trois mineures maintenues à la fois. 1 447 commits humains hors fusion, dernier commit le 2026-11-19 | [S2], [S4], [S7] |
| Flux | 5/5 | 10 | 19 releases stables en 12 mois, de la 2.7 à la 2.10. 213 commits humains hors fusion dans `flux2`, de 123 à 140 dans chacun des contrôleurs source, kustomize et helm ; dernier commit le 2026-11-17 | [S15], [S16] |
| Config Sync | 4/5 | 8 | 11 releases stables en 12 mois, de la 1.23 à la 1.25, à peu près une par mois. Réserve : 8 auteurs humains, et 173 des 299 commits de l'année viennent de Dependabot | [S27], [S29], [S32] |

### 5.5 Sécurité (CVE, réactivité), poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Argo CD | 3/5 | 6 | 11 avis publiés depuis le 2025-11-19 : 5 critiques, dont deux exécutions de commande dans le repo-server par Kustomize, une lecture de fichiers par Jsonnet, un contournement des AppProjects et une extraction de Secrets ; 3 élevés, 3 moyens. Correctifs livrés sur les trois mineures maintenues, signalement privé ouvert sur GitHub, images signées par cosign, provenance SLSA de niveau 3. La réserve demande une action : grande surface (serveur web et API, Dex, Redis), 8 conteneurs en `imagePullPolicy: Always`, aucune demande de ressources ; le blueprint doit suivre chaque correctif et ne pas exposer le serveur | [S3], [S7], [S8], [S9], [S51] |
| Flux | 4/5 | 8 | 3 avis depuis le 2025-11-19, aucun critique, tous corrigés avant leur publication : GHSA-mwcp-qpcg-fr7c (élevé, CVSS 7.1, NetworkPolicy `allow-webhooks` du manifest, sans CVE et absent de la base mondiale, corrigé en 2.9.4), CVE-2026-47680 (moyen, traversée de chemin dans source-controller) et CVE-2026-40109 (faible). Images de la CLI et des contrôleurs signées par cosign, SBOM, provenance SLSA Build Level 3, contrôleurs conformes au profil « restricted » des Pod Security Standards. Réserve : signalement par une liste de diffusion, traitement « on a best-effort basis », avis publiés dans chaque dépôt et pas tous dans la base mondiale, d'où une veille dépôt par dépôt | [S19], [S20], [S21], [S52], [S66], [S67], [S68] |
| Config Sync | 3/5 | 6 | Aucun avis publié, ni par le dépôt ni dans la base mondiale de GitHub. Neuf releases de 2026 corrigent des CVE sans les nommer : un scan des images voit les dépendances vulnérables, pas une faille du code de Config Sync lui-même. Mise à jour automatique retirée en 1.21.0 (2025-05-01) : montée de version à la main, même sur GKE, au moins tous les neuf mois selon Google. Signalement par le programme de Google, réponse sous 5 jours ouvrés ; signature des images non trouvée. La réserve demande une action : suivre les notes de version et monter de version à la main | [S30], [S32], [S39], [S55], [S75], [S90] |

[BENCH] Le troisième avis de Flux, que la méthode du premier jet (base
mondiale seule) ne pouvait pas voir, ne change pas sa note : trois avis sans
critique, tous corrigés avant publication, restent une réserve mineure, pas
une action au sens du 3, ce que [SECU] confirme. Sensibilité : si le DSI tient
la veille dépôt par dépôt pour une action, Flux passe à 3 et perd 2 points.
Méthode pour les benchmarks suivants : compter les avis au dépôt, puis
vérifier leur présence dans la base mondiale.

[BENCH] Images, constat de [SECU] : tout ce que les trois outils exécutent est
désigné par condensat dans le script, modèles de réconciliateurs de Config
Sync compris, donc aucun cran ne tombe au titre de la règle des tags.
Sensibilité : revenir aux tags pour retrouver le cache de `kind load`
violerait la condition 3 de l'ADR-004 et retirerait un cran de sécurité ;
Flux tomberait à 86.

### 5.6 Empreinte sur PC (RAM, CPU, démarrage), poids 10

[BENCH] Règle de `TEMPLATE.md` (section 5.6), seuils écrits en 4.1 avant la
première mesure : chaque option part de 5 et perd un cran par seuil dépassé.
Le volume se lit sur l'amd64, pire cas des systèmes de Q5 ; la mémoire selon
la règle du DSI, au nœud moins le nœud de base (4.1, 4.4).

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Argo CD | 2/5 | 4 | Trois seuils dépassés : 320,7 Mo d'images en amd64 (seuil 1), retéléchargées à chaque création (seuil 2), 611,2 Mio de couche au nœud (seuil 4). Installation en 43,6 s, sous son seuil | [M1], [M2], [M6], [M8] |
| Flux | 3/5 | 6 | Deux seuils dépassés : 392,1 Mo en amd64, 258,1 Mo pour les quatre contrôleurs par défaut (seuil 1), retéléchargés à chaque création (seuil 2). Installation en 29,1 s et 265,2 Mio de couche au nœud, sous leurs seuils | [M1], [M2], [M6], [M8], [S57] |
| Config Sync | 2/5 | 4 | Trois seuils dépassés : 495,9 Mo en amd64 (seuil 1), retéléchargés à chaque création (seuil 2), 1 476,5 Mio de couche au nœud pour trois environnements (seuil 4). Médiane mesurée sous émulation x86, marquée indicative ; la note est gardée par décision du DSI | [M1], [M2], [M6], [M7], [M8] |

[BENCH] Aucune option n'est à moins de 10 % d'un seuil : Argo CD dépasse
celui de la mémoire de 19 %, Flux en reste à 48 % de marge. Config Sync
dépasse le seuil dès un seul environnement : ses composants communs pèsent à
eux seuls 473 à 478 Mio, et avec le seul réconciliateur de `demo-local` la
somme des pods fait 750,4 Mio en médiane (relevé de [FINOPS], sous
émulation ; les composants communs pourraient peser moins avec un seul
`RootSync`).

[BENCH] Sensibilité : avec l'ancienne lecture de M2, la somme des pods de
l'outil (267,4 Mio pour Argo CD), Argo CD reste sous le seuil et garde 3/5,
soit 88 au total, à égalité avec Flux. C'est la règle de mémoire au nœud qui
retire ce cran.

### 5.7 Portabilité multi-cloud, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Argo CD | 5/5 | 10 | Mêmes objets et même dépôt sur kind (arm64, mesuré) et sur tout cluster conforme, donc sur GKE ; images publiées pour amd64 et arm64. Hors MVP, AWS le propose en service managé : sur une cible AWS, le principe III le désignerait | [M7], [S42], [S44] |
| Flux | 5/5 | 10 | Mêmes objets et même dépôt sur kind (arm64, mesuré) et sur tout cluster conforme ; images amd64 et arm64. Hors MVP, Microsoft le propose en extension managée d'AKS : sur une cible Azure, le principe III le désignerait | [M7], [S43], [S44] |
| Config Sync | 2/5 | 4 | Managé sur GKE seulement, après inscription du cluster dans une flotte. La forme libre tourne sur tout cluster x86 ; Google l'exclut des nœuds Arm, donc des PC à processeur Apple et des nœuds Arm de GKE. Sur le poste de mesure, elle ne tourne que par l'émulation x86 d'OrbStack, hors prise en charge. Aucune offre managée hors de Google trouvée | [M7], [S33], [S34], [S44], [S63] |

[BENCH] Le principe III n'entre pas dans cette note : elle mesure ce qui
tourne où. Qu'Argo CD et Flux tournent sur GKE ne dit pas qu'ils y ont leur
place ; c'est l'objet de la section 7.

### 5.8 Expérience dev et documentation, poids 10

[BENCH] Note de jugement. L'essai qui la fonde : installation par la commande
documentée, puis synchronisation des trois overlays et d'un commit, trois
fois par option, sans aucune intervention.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Argo CD | 5/5 | 10 | Installé et synchronisé du premier coup à chaque exécution, avec la commande des notes de version. Un seul ApplicationSet décrit les trois environnements, comme le prévoit le brief. Interface web et CLI pour voir l'état et l'écart avec Git ; demande de rafraîchissement documentée | [M1], [M4], [M5], [S3], [S12], [S13] |
| Flux | 4/5 | 8 | Installé et synchronisé du premier coup à chaque exécution, avec la commande documentée. Réserve : aucune interface dans le projet ; l'état se lit par la CLI `flux` ou par les conditions des objets, et chaque environnement demande sa `Kustomization` | [M1], [M4], [M5], [S22], [S23], [S24] |
| Config Sync | 2/5 | 4 | Synchronisé sans intervention, sur ce poste seulement par émulation (M7) ; sa durée de M4 contient le tirage des images des réconciliateurs et l'émulation, et ne sert pas d'argument. Documentation tournée vers GKE et la flotte (console, gcloud, Terraform) ; la forme libre tient en une page d'installation et une page d'usage. Piège documenté : sans `sourceFormat: unstructured`, le format `hierarchy` s'applique, qui refuse le rendu Kustomize. Aucune demande de rafraîchissement trouvée dans les pages lues, aucune interface locale | [M4], [M7], [S28], [S34], [S37], [S40] |

### 5.9 Coût (managé ou opérationnel), poids 5

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Argo CD | 4/5 | 4 | Gratuit sur le PC. Sur GKE, sept pods sans demande, qu'Autopilot porte à 0,5 vCPU et 2 Gio par conteneur, soit 3,5 vCPU et 14 Gio. Réserve : demandes explicites à fixer, règle de tout le blueprint (R-17), comme pour ESO dans BENCH-007 ; coût résiduel de sept pods | [S41], [S51] |
| Flux | 4/5 | 4 | Gratuit sur le PC. Sur GKE, demandes posées par le manifest ; demande effective de 0,35 vCPU et environ 371 Mio pour les quatre contrôleurs par défaut sur un cluster à rafale, 1 vCPU et 2 Gio sans rafale, une fois appliqués les minimums et le rapport d'Autopilot. Réserve : coût résiduel de quatre pods | [S41], [S52] |
| Config Sync | 3/5 | 3 | Service et flotte inclus sans surcoût. Ses pods tournent dans le cluster du client : leur facturation en Autopilot n'est pas établie, et Google y fixe environ 0,93 vCPU et 0,93 Gio par `RootSync`, plus les composants communs. Métriques exportées vers Cloud Monitoring et facturées à l'échantillon. Action propre à l'option : surcharger les demandes, couper ou filtrer l'export | [S36], [S39], [S40], [S41], [S77], [S94], [S95] |

[FINOPS] Les grilles de GKE et de Cloud Monitoring n'ont rendu que leur titre
le 2026-11-19 : aucun prix n'est écrit [S93], [S97]. Config Sync est inclus
dans l'offre GKE, flotte comprise [S36], [S61]. Ses pods tournent dans le
cluster du client, et aucune page lisible ne les exempte de la facturation
d'Autopilot ; la seule exemption trouvée vise le « system overhead » sans le
définir [S95]. Le budget les compte comme facturés jusqu'à preuve contraire.

## 6. Grille pondérée

| Critère | Poids | Argo CD | Flux | Config Sync |
| --- | --- | --- | --- | --- |
| Critères éliminatoires (section 3) | éliminatoire | passe | passe | passe |
| Licence et liberté d'usage | 15 | 4/5, 12 pts | 5/5, 15 pts | 5/5, 15 pts |
| Gouvernance (fondation, multi-vendeurs) | 15 | 5/5, 15 pts | 4/5, 12 pts | 2/5, 6 pts |
| Maturité et adoption | 15 | 5/5, 15 pts | 5/5, 15 pts | 4/5, 12 pts |
| Activité et maintenance | 10 | 5/5, 10 pts | 5/5, 10 pts | 4/5, 8 pts |
| Sécurité (CVE, réactivité) | 10 | 3/5, 6 pts | 4/5, 8 pts | 3/5, 6 pts |
| Empreinte sur PC (RAM, CPU, démarrage) | 10 | 2/5, 4 pts | 3/5, 6 pts | 2/5, 4 pts |
| Portabilité multi-cloud | 10 | 5/5, 10 pts | 5/5, 10 pts | 2/5, 4 pts |
| Expérience dev et documentation | 10 | 5/5, 10 pts | 4/5, 8 pts | 2/5, 4 pts |
| Coût (managé ou opérationnel) | 5 | 4/5, 4 pts | 4/5, 4 pts | 3/5, 3 pts |
| Total | 100 | 86 / 100 | 88 / 100 | 62 / 100 |

## 7. Verdict proposé

[BENCH] Classement de la grille, après l'arbitrage du DSI et la série de
référence : Flux 88, Argo CD 86, Config Sync 62. Totaux de départ, avant la
règle de mémoire au nœud : Flux 88, Argo CD 88, Config Sync 62. C'est la
règle de mémoire qui sépare Flux et Argo CD : lue au nœud, la couche d'Argo
CD pèse 611,2 Mio et dépasse le seuil de 512 Mio, celle de Flux 265,2 Mio
(4.4). Il n'y a donc pas d'égalité, et la règle d'égalité de 4.1 ne
s'applique pas. Sur `gcp`, le principe III impose le service managé qui
couvre le besoin, ce qui n'est pas un critère de la grille : Config Sync le
couvre (Git, Kustomize, un `RootSync` par environnement, M4) [S31], [S38].

[BENCH] Sensibilité, à lire franchement : l'avance de Flux tient dans un cran,
et chacun des changements suivants ramène l'égalité, que la règle d'égalité
tranche alors pour Argo CD.

| Changement | Argo CD | Flux | Config Sync | Effet |
| --- | --- | --- | --- | --- |
| Grille retenue | 86 | 88 | 62 | Flux |
| Mémoire lue par la somme des pods (ancienne lecture de M2) | 88 | 88 | 62 | Égalité, donc Argo CD |
| Veille des avis de Flux dépôt par dépôt tenue pour une action (sécurité à 3) | 86 | 86 | 62 | Égalité, donc Argo CD |
| Images de Flux tirées par tag pour retrouver le cache (condition 3 de l'ADR-004 violée, sécurité à 3) | 86 | 86 | 62 | Égalité, donc Argo CD |
| Sécurité d'Argo CD à 4 | 88 | 88 | 62 | Égalité, donc Argo CD |
| Licence d'Argo CD à 5 (Redis remplacé) | 89 | 88 | 62 | Argo CD |
| Expérience dev de Flux à 5 | 86 | 90 | 62 | Flux |
| Montage C : outil sur le PC seulement, coût à 5/5 pour les deux | 87 | 89 | sans objet | Flux |
| Base de mémoire la plus haute (656,5 Mio) ou la plus basse (604,3 Mio) | 86 | 88 | 62 | Flux, Argo CD restant au-dessus du seuil (603,0 et 655,2 Mio) |
| Cumul avec la plate-forme contre ses seuils seuls (lecture c de [FINOPS]) | 86 | 86 | 62 | Égalité, donc Argo CD |

[BENCH] Config Sync reste dernier dans tous les cas, à 24 points au moins.

### 7.1 La question de parité

[BENCH] Ce que les trois outils partagent. Tous trois lisent des manifests
Kubernetes ordinaires, rendus par Kustomize depuis un dossier par
environnement. Le dépôt de test de ce benchmark suit la structure de Q6 : une
base, et trois overlays `local`, `staging` et `prod`, chacun dans son
namespace. Les trois outils l'ont synchronisé tel quel sur kind (M4), Config
Sync sous émulation x86 (M7), avec ses règles documentées : format
`unstructured`, `kustomization.yaml` à la racine du dossier synchronisé, pas
de base distante privée, un `RootSync` par environnement [S37], [S38].

[BENCH] Ce qui diffère d'un outil à l'autre tient dans quelques objets de
liaison, qui disent à l'outil quoi synchroniser et où :

| Élément | Argo CD | Flux | Config Sync |
| --- | --- | --- | --- |
| Objets de liaison | `ApplicationSet` ou `Application`, dans `argocd` | `GitRepository` et `Kustomization`, dans `flux-system` | `RootSync` (ou `RepoSync`), dans `config-management-system` |
| Format du dossier synchronisé | Kustomize, chart Helm, image OCI, dossier de manifests YAML, JSON ou Jsonnet, ou greffon | Kustomize, ou manifests bruts pour lesquels un `kustomization.yaml` est généré | `unstructured` à déclarer, sinon `hierarchy` par défaut ; Kustomize et Helm rendus en place |
| Interrogation de Git par défaut | 120 s plus 60 s d'aléa | Intervalle obligatoire, choisi par l'auteur | 15 s |
| Demande de rafraîchissement | Annotation `argocd.argoproj.io/refresh` | Annotation `reconcile.fluxcd.io/requestedAt` | Aucune dans les pages lues |
| Sources | [S11], [S12], [S13], [S60] | [S23], [S24] | [S37], [S38], [S40] |

[BENCH] Réponse. Les mêmes manifests d'application et la même structure de
dépôt servent avec les trois outils : la base et les overlays sont du
Kustomize sans rien de propre à l'outil. Les objets de liaison, eux, sont
propres à chaque outil. Ils servent tels quels sur kind et sur GKE avec Argo
CD ou avec Flux, puisque l'outil tourne de la même façon sur les deux
clusters (5.7). Avec Config Sync, ils servent tels quels sur GKE et sur un PC
x86 ; sur un PC à processeur Apple, seulement par l'émulation x86 du moteur,
hors prise en charge de Google (M7, [S33], [S63]). La parité complète, même
outil et mêmes objets partout, n'est donc acquise qu'avec Argo CD ou Flux.

[BENCH] Trois montages possibles en découlent, jugés sur ENF-02, le principe
II et le principe III, sans élimination automatique :

| Montage | `local` (kind) | `gcp` (GKE) | ENF-02 et principe II | Principe III | Coût du montage |
| --- | --- | --- | --- | --- | --- |
| A. Même outil libre partout | Argo CD ou Flux | Le même, installé dans le cluster | Parité complète : seules l'adresse du cluster et les identifiants changent | Écart : un `managed_gap` est exigé sur `gcp` par la lecture de l'ADR-009, et la seule lacune de Config Sync trouvée ici est de ne pas tourner sur un PC arm64 | L'équipe installe, met à jour et corrige l'outil sur GKE ; ses pods tournent dans le cluster (Flux réduit : 0,35 vCPU et environ 371 Mio sur Autopilot à rafale, rien de plus par environnement) ; un seul test GitOps dans la matrice |
| B. Config Sync partout | Config Sync libre | Config Sync managé | Parité complète sur PC x86 ; sur PC arm64, par émulation seulement | Respecté ; sur le PC, éditeur unique (principe V, ADR à écrire) | 62/100 ; un contrôleur `cluster-admin` sous une émulation que Google ne prend pas en charge, inacceptable pour [SECU] |
| C. Managé sur GCP, libre sur le PC | Argo CD ou Flux | Config Sync managé | Manifests d'application et structure communs ; objets de liaison dans la couche de cible de chacun, ce que le principe II autorise ; écarts de comportement à lister dans le README, comme ENF-02 le prévoit | Respecté sur les deux cibles | Deux outils à connaître et à suivre ; pods de Config Sync dans le cluster du client, facturation non établie, environ 0,93 vCPU et 0,93 Gio par environnement sur Autopilot ; métriques facturées par Cloud Monitoring ; deux tests GitOps dans la matrice, la couche `gcp` en x64 seulement |

[BENCH] Le montage C est celui qu'ENF-02 décrit pour toutes les briques :
libre sur le PC, managé sur GCP, seule la couche de cible change, et le README
liste les écarts restants. C'est la règle que l'ADR-009 prend en exemple
pour le cache, avec Memorystore for Valkey sur GCP et Valkey sur le PC [S49].
Son vrai coût porte sur le test (principe I) : les `RootSync` de la couche
`gcp` ne tournent pas nativement sur un PC à processeur Apple. Ils peuvent
tourner sur kind dans la CI, sur les runners `ubuntu-latest` en x64 de
GitHub [S59], puisque la forme libre de Config Sync s'installe sur tout
cluster x86 [S28], [S33] ; l'essai de M4 sous émulation montre qu'elle
synchronise bien la structure du projet, l'essai natif sur x64 reste à faire.

[BENCH] Écarts que le README du projet généré devrait lister en montage C,
d'après les sources lues : moteur différent entre le PC et GCP ; objets de
liaison différents ; délai d'interrogation de Git différent (15 s pour Config
Sync, celui de l'outil local ailleurs) ; aucune interface web locale si Flux
est retenu ; prévention de dérive par webhook d'admission, option de Config
Sync [S39], sans équivalent vérifié dans les deux autres outils ; montée de
version de Config Sync à la main, même sur GKE [S39].

### 7.2 Proposition

[BENCH] Montage proposé : C. Config Sync managé sur `gcp`, Flux sur
`local`.

[BENCH] Pourquoi C plutôt que A. Config Sync couvre le besoin de Q6 sur GKE
(Git, Kustomize, un `RootSync` par environnement) [S31], [S38], et sa
licence est incluse dans l'offre GKE [S36], [S61]. L'exécution de ses pods en
Autopilot, elle, n'est pas établie comme gratuite (5.9), et elle demande plus
de ressources que Flux, d'autant plus qu'on ajoute des environnements. Si ces
pods sont facturés, Flux sur les deux cibles coûte moins cher, et le montage C
ne tient alors que par le principe III, dans la lecture de l'ADR-009 que
Lucas doit encore valider. Les deux montages font tourner des pods sur GKE ;
le montage A demande en plus de faire installer, monter de version et
corriger l'outil par l'équipe, et un `managed_gap` fondé sur la seule parité
d'outil. Le montage B est écarté : dernier de la grille (62), et
inacceptable pour [SECU], qui refuse un contrôleur `cluster-admin` sous une
émulation que Google ne prend pas en charge.

[BENCH] Gouvernance. Config Sync dépend de Google seul, sans fondation (2/5).
Sur `gcp`, le principe III désigne le service managé du fournisseur, et
Google est déjà ce fournisseur : l'éditeur unique ne crée pas de dépendance
nouvelle. Si Lucas valide la lecture des principes III et V de l'ADR-009, ce
n'est pas une dérogation ; sinon, l'ADR-010 porte l'écart au principe V. Repli
connu : Flux sur `gcp` (montage A), qui ne change que la couche de cible.

[BENCH] Pourquoi Flux plutôt qu'Argo CD sur le PC. Par la grille seule :
88 contre 86, et 89 contre 87 si l'outil ne tourne que sur le PC. Ces deux
points viennent d'un seul cran, celui de la mémoire lue au nœud, où Argo CD
dépasse le seuil de 512 Mio (611,2 Mio) et Flux non (265,2 Mio). Sans la
règle de mémoire du DSI, les deux outils seraient à égalité et la règle
d'égalité garderait Argo CD, l'option de Q6. Le verdict repose donc sur ce
cran, et sur aucun départage hors grille : la mémoire et le temps
d'installation sous leurs seuils, la recréation hors ligne (fausse tant que
R-25 n'est pas résolu) et le nombre d'avis (déjà compté en 5.5) ont été
retirés, selon l'arbitrage du DSI. Restent, comme faits et non comme
départage : Flux pose déjà ses demandes de ressources [S52], n'expose aucune
API qui détienne des droits sur tout le cluster (7.3), et n'embarque pas
Redis 8 [S53]. Argo CD garde deux avantages réels, son interface web et la
gouvernance la plus large (5.2).

### 7.3 Droits des moteurs

[BENCH] Relevé par [SECU] dans les trois manifests de la série, dont les
SHA-256 concordent avec ceux du script. Le moteur GitOps est le composant le
plus privilégié du cluster, quel que soit l'outil : qui le compromet, ou qui
écrit dans ce qu'il lit, administre le cluster.

| Droit | Argo CD 3.6.2 | Flux 2.10.0 | Config Sync 1.25.2 |
| --- | --- | --- | --- |
| Peut tout créer | `argocd-application-controller` : ClusterRole `*` sur `*`, plus `nonResourceURLs: *` | `kustomize-controller` et `helm-controller`, liés à `cluster-admin` | `reconciler-manager`, lié à `cluster-admin` ; chaque réconciliateur de `RootSync` reçoit `cluster-admin` tant que `spec.override.roleRefs` est absent |
| Lit tous les Secrets | Contrôleur, `argocd-server` (`get`, `patch`, `delete` sur toutes les ressources) et ApplicationSet | Les sept contrôleurs, par la ClusterRole `crd-controller` | Les mêmes, plus `resource-group-controller` (`get`, `list`, `watch` sur `*`) |
| Exposé sur le réseau | API et interface web, Dex, compte `admin` dont le mot de passe initial est en clair dans `argocd-initial-admin-secret` | Récepteur de webhooks (9292) ouvert à tous les namespaces, métriques ; trois NetworkPolicies | Aucune NetworkPolicy dans le manifest |
| Restreindre | AppProject dédié au lieu de `default` ; Argo CD Core retire l'API | `--no-cross-namespace-refs`, `--no-remote-bases`, `--default-service-account`, `serviceAccountName` par `Kustomization` | `spec.override.roleRefs`, depuis la 1.17.0 |
| Sources | [S51], [S87] | [S52], [S83] | [S40], [S39], [S77] |

[BENCH] Dans les trois séries, tout a été appliqué avec ces droits par
défaut : `project: default` pour Argo CD, aucune `serviceAccountName` pour
Flux, aucun `roleRefs` pour Config Sync. Sur un seul cluster GKE qui porte
plusieurs environnements (Q6), un `RootSync` de staging peut donc modifier
les objets de prod. Ces droits tiennent à la fonction et touchent les trois
options : aucune note ne change, les restrictions passent dans les
conditions de l'ADR-010. Le serveur de test de ce benchmark acceptait la
lecture et le push anonymes : acceptable pour un banc jetable, à ne jamais
reproduire dans le blueprint.

### 7.4 Identifiants Git

[BENCH] Sur GKE. Pour un jeton GitHub, la documentation de Google écrit
« Grant the token the `repo` scope so that it can read from private
repositories » [S78]. La portée `repo` donne l'écriture sur tous les dépôts
de l'utilisateur [S85] : à refuser. Le blueprint retient une clé de
déploiement en lecture seule, limitée au seul dépôt [S86], ou une GitHub App
installée sur ce dépôt avec un droit de lecture, ou une source OCI dans
Artifact Registry lue par Workload Identity (`k8sserviceaccount`), sans
aucun secret [S78]. Pour SSH, Google tient `known_hosts` pour « Optional, but
recommended », et la vérification de l'hôte saute sans lui [S78] : il est
obligatoire. Le Secret ne vient pas d'une ressource Kubernetes d'OpenTofu,
dont la valeur finirait dans l'état (R-19).

[BENCH] Sur le PC. Par défaut, aucun identifiant Git : source locale ou dépôt
public, à arbitrer par [ARCHI] (question 1 de 7.7). Si un identifiant est
nécessaire : clé de déploiement en lecture seule avec `known_hosts`, que Flux
attend à côté de `identity` [S23], saisie sans écho et créée par un tube,
jamais `kubectl apply`. Jamais le jeton de `gh`, qui porte les droits
d'administration sur les dépôts de l'utilisateur (R-07).

### 7.5 Conditions proposées pour l'ADR-010

[BENCH] Reprises de [SECU], pour que la couche commune reste neutre vis-à-vis
du moteur et que les droits soient les mêmes des deux côtés :

1. Une politique conftest sur les fichiers du dépôt généré refuse, hors de
   la couche de cible, les groupes `configsync.gke.io`, `*.toolkit.fluxcd.io`
   et `argoproj.io`, toute annotation ou étiquette préfixée
   `configmanagement.gke.io/`, `configsync.gke.io/`,
   `kustomize.toolkit.fluxcd.io/` ou `argocd.argoproj.io/`, et toute chaîne
   `${`. Raison : une annotation de moteur fait diverger un contrôle de
   sécurité sur une seule cible [S81], [S24], et Flux remplace un `${var}`
   non défini par une chaîne vide quand Config Sync le laisse tel quel [S24].
2. Un test de la matrice compare le rendu Kustomize de chaque overlay par la
   version de Kustomize de chaque moteur, et échoue au moindre écart ; ou la
   CI rend une fois, et les deux moteurs synchronisent la sortie rendue [S37].
3. Droits restreints des deux côtés : `spec.override.roleRefs` vers un rôle
   limité au namespace de chaque environnement sur `gcp` ; sur le PC,
   `--no-cross-namespace-refs`, `--no-remote-bases`,
   `--default-service-account` et une `serviceAccountName` par
   `Kustomization` [S83], [S77].
4. Identifiants Git selon 7.4, et protection de la branche suivie.
5. La couche `gcp` est testée sur kind en x64 (`ubuntu-latest`) avec la forme
   libre de Config Sync dans la version déployée sur GKE ; ce test valide les
   objets de liaison et le rendu, pas le service géré par Fleet.
6. Images des deux moteurs figées par condensat dans leur couche, par le champ
   `digest` du transformateur `images` de Kustomize [S89], manifests
   versionnés et vérifiés par SHA-256 (ADR-004, condition 4).

### 7.6 Effet sur Q6 et sur la stack du brief

[BENCH] Q6 garde sa décision : un seul environnement déployé sur GCP, et une
structure prête pour staging et prod. Ce qui change, c'est le mot « Argo
CD ». La structure prête devient une base Kustomize et un overlay par
environnement, que n'importe lequel des trois outils synchronise (M4). En
montage C, chaque environnement de GCP reçoit son `RootSync`, que Google
documente pour une organisation par environnement [S38], et le PC reçoit les
objets de l'outil local. La reformulation de Q6 revient à [PO], et sa
validation à Lucas.

[BENCH] La stack du brief (section 6) écrit « Argo CD (GitOps,
ApplicationSets par environnement dev / staging / prod) ». En montage C, la
ligne deviendrait « Config Sync sur GCP, Flux sur le PC, un overlay
Kustomize par environnement ». Le brief reste la trace d'origine et ne se
réécrit pas. Ni la constitution, ni `CLAUDE.md`, ni `docs/vision.md`, ni
`ROADMAP.md` ne nomment l'outil GitOps ; la fiche de l'agent `ops`
(`.claude/agents/ops.md`, ligne 13) écrit « Argo CD et ApplicationSets par
environnement » et serait à corriger avec Q6.

### 7.7 Questions ouvertes pour [ARCHI] et Lucas

1. Que lit l'outil GitOps sur le PC ? Un dépôt privé imposerait un vrai
   identifiant, en clair dans etcd (R-28), lisible par tous les contrôleurs
   qui lisent les Secrets (7.3).
2. Faut-il une source OCI sur GKE, sans aucun secret, au prix d'une CI qui
   publie un artefact et de l'identité de R-19 ?
3. Faut-il l'outil GitOps dans le profil lite d'US-005 ? Selon [FINOPS], avec
   kind et Envoy Gateway, le premier lancement télécharge alors 68 % (Flux
   réduit) à 74 % (Argo CD) du budget de 15 minutes à 10 Mbit/s, avant les
   images de la stack.
4. Faut-il réduire Flux à ses quatre contrôleurs par défaut, l'automatisation
   des images étant hors champ : 134,0 Mo de moins en amd64 et trois pods de
   moins ?
5. Facturation des pods de Config Sync en Autopilot, et lecture des grilles
   de GKE et de Cloud Monitoring, illisibles par les outils des agents (R-05).

### 7.8 Réserves, suites et risques proposés

[BENCH] Réserves : l'avance de Flux tient dans un cran, et plusieurs
changements d'un cran rendent la main à Argo CD (tableau de sensibilité) ;
la part de mémoire d'Argo CD qu'aucun pod n'explique reste à attribuer ; le
nœud de base a été mesuré dans une autre session que la série principale ;
Flux repose pour l'essentiel sur deux mainteneurs de ControlPlane (5.2) ; la
parité du montage C n'est démontrée que pour les manifests d'application, pas
pour le comportement des deux moteurs. Prochaine vérification proposée :
2027-05-19, ou plus tôt si Google publie Config Sync pour arm64, si la
facturation des pods de Config Sync en Autopilot est établie, si AWS ou Azure
entrent dans le périmètre, ou si Flux perd l'un de ses mainteneurs
principaux.

[BENCH] Suites :

- l'ADR-010, écrit par [ARCHI], qui répond aussi à la question 3 de
  l'ADR-009 : montage retenu, conditions de 7.5, et `managed_gap` écrit si le
  montage A l'emporte ;
- les entrées de `catalog/` : une brique `gitops`, `declared_by: target`
  comme `kubernetes-cluster`, avec pour `gcp` Config Sync (`managed`,
  `google`, `single-vendor`) et pour `local` l'outil retenu (`oss`,
  Apache-2.0, fondation CNCF), chacune avec sa date et ses sources ;
- [QA] : le test de la condition 5, si le montage C est retenu ;
- [OPS] : préchargement des images qui garde le condensat du registre
  (R-25), et version de Config Sync figée dans la couche `gcp` ;
- risques proposés pour `docs/risques.md`, que le DSI reprend lui-même :

```markdown
### R-31. Moteur GitOps différent entre le PC et GCP

En montage C (BENCH-009), l'outil libre synchronise le cluster local et
Config Sync, service managé de GKE, synchronise GCP. Les objets de liaison
diffèrent, et le service managé n'a jamais tourné (principe X) : ses faits
viennent de la documentation de Google. Config Sync ne tourne que sur des
nœuds x86 : aucun poste à processeur Apple ni runner arm64 ne teste
nativement la couche `gcp`, et un pool de nœuds Arm sur GKE ne le porterait
pas. Une annotation propre à un moteur, une variable `${…}` ou une autre
version de Kustomize peuvent faire diverger la couche commune sans bruit,
contrôles de sécurité compris. Ses pods tournent dans le cluster du client :
Google y fixe environ 0,93 vCPU et 0,93 Gio par `RootSync` en Autopilot,
aucune page lisible ne les exempte, et ses métriques sont facturées par
Cloud Monitoring ; s'ils sont facturés, Flux sur les deux cibles coûterait
moins cher.

Probabilité : moyenne. Impact : moyen, fort si un contrôle de sécurité
diverge. Porteur : OPS, SECU, QA, FINOPS.

Mitigation : conditions 1, 2 et 5 de l'ADR-010 ; nœuds x86 pour Config Sync
sur GKE ; un seul `RootSync` dans le profil démo et export des métriques
coupé ou filtré par défaut ; écarts listés au README ; essai sur GKE après
accord de Lucas et budget de [FINOPS].
```

```markdown
### R-32. Failles des moteurs GitOps invisibles aux scanners

Config Sync corrige des CVE sans les nommer (neuf releases en 2026) et ne
publie aucun avis : un scan des images voit ses dépendances vulnérables,
pas une faille de son propre code. Sa mise à jour automatique a été retirée
en 1.21.0 (2025-05-01) : sur GKE, la montée de version se fait à la main, au
moins tous les neuf mois selon Google. Côté Flux, l'avis élevé
GHSA-mwcp-qpcg-fr7c (2026-08-11) n'a pas de CVE et manque à la base mondiale
de GitHub : Flux publie ses avis dans chaque dépôt.

Probabilité : moyenne. Impact : moyen, fort pour un moteur qui a
`cluster-admin`. Porteur : SECU, OPS.

Mitigation : version de Config Sync figée dans la couche `gcp` et montée par
une PR qui passe la matrice ; relecture mensuelle des notes de version de
Config Sync et des avis des dépôts `fluxcd` par [SECU] ; scan Trivy des
images des deux moteurs à chaque montée ; procédure de montée de version
dans le runbook du projet généré.
```

```markdown
### R-33. Écrire sur la branche suivie, c'est administrer le cluster

Les trois moteurs étudiés par BENCH-009 appliquent par défaut avec
`cluster-admin`. Qui écrit sur la branche suivie, ou intercepte sa lecture,
administre donc le cluster, et un environnement peut écrire dans un autre
sur un même cluster GKE. La documentation de Google fait créer un jeton
GitHub de portée `repo` et désactive la vérification de l'hôte SSH quand
`known_hosts` manque. Sur le PC, la pente serait de reprendre le jeton de
`gh` (R-07).

Probabilité : moyenne. Impact : fort. Porteur : SECU, OPS.

Mitigation : condition 3 de l'ADR-010 ; protection de la branche suivie
dans le dépôt généré (Q3) ; identifiant en lecture seule limité au dépôt,
`known_hosts` obligatoire, jamais un jeton personnel ni celui de `gh` ;
Secret jamais créé par une ressource OpenTofu (R-19) ; aucun identifiant
Git sur le PC par défaut.
```

```markdown
Complément de R-25 (BENCH-009, relu par [SECU]) : les images de l'outil
GitOps sont retéléchargées à chaque création du cluster kind, quel que soit
l'outil. Les manifests amont les désignent par tag ; le blueprint les fige
par condensat (ADR-004, condition 3). `IfNotPresent` ne suffit pas :
préchargées par `kind load docker-image` depuis un magasin classique, elles
perdent le condensat du registre et repassent par lui. Argo CD demande en
plus un correctif en `IfNotPresent` (8 conteneurs en `Always`), sauf si la
mitigation retenue est un miroir local déclaré à containerd. Revenir aux
tags pour faire marcher `kind load` est refusé.
```

## 8. Limites et biais

| Limite | Effet possible sur le verdict | Ce qui la lèverait |
| --- | --- | --- |
| Une seule machine, arm64 sous macOS avec OrbStack, moteur non libre (R-26) | Empreinte propre à ce poste ; ni Linux ni amd64 mesurés pour Argo CD et Flux | Relancer le script sur un poste Linux x86 et sur un runner GitHub x64 |
| Config Sync mesuré sous émulation x86 (Rosetta, par OrbStack) sur un nœud arm64 | Temps, mémoire et CPU de Config Sync indicatifs ; sa note d'empreinte (2) pourrait monter d'un cran sur x86 natif si la mémoire y passait sous 512 Mio, ce qu'aucune mesure ne dit | Lancer le script sur un poste x86 ou un runner `ubuntu-latest` |
| Option `NODE_PLATFORM` du script jamais exécutée | Aucun effet sur les mesures du rapport | L'essayer avant de s'en servir |
| Service managé de GKE non essayé : aucune ressource cloud sans accord (principe X) | Inclusion sans surcoût, prise en charge d'Autopilot et format de dépôt établis sur la documentation de Google seulement | Un essai sur le projet GCP de démonstration, après accord de Lucas et budget de [FINOPS] |
| Installations de référence de périmètres différents : Argo CD avec interface, Dex, Redis, notifications et ApplicationSets ; Flux avec ses sept contrôleurs, automatisation d'images comprise | Empreinte comparée à fonctions inégales | Les mesures par pod permettent de recompter un sous-ensemble ; voir section 4.4 |
| Images tirées par le nœud à chaque exécution | M1 dépend du réseau du poste et des registres `quay.io`, `ghcr.io`, `public.ecr.aws` | Mesurer avec les images préchargées par `kind load`, et sur une ligne lente |
| Dépôt de test minimal : un Deployment et une ConfigMap par environnement | La mémoire au repos croît avec le nombre d'applications et de ressources suivies | Mesurer sur le golden repo de la phase 2 |
| M5 mesuré après une demande explicite de rafraîchissement | Sans elle, le délai suit l'interrogation : 120 à 180 s pour Argo CD [S11], l'intervalle choisi pour Flux (1 minute ici) [S23], 15 s par défaut pour Config Sync [S40] | Mesurer aussi sans demande, ou avec un webhook de la forge |
| Faits sur Config Sync tenus par Google seul | Inclusion, Autopilot, format et architecture reposent sur la documentation de l'éditeur | Essai sur GKE (ligne ci-dessus) |
| Page de tarifs de GKE illisible par l'outil de lecture | L'absence de surcoût repose sur deux autres pages de Google [S35], [S36] | Relecture de la page par [FINOPS] dans un navigateur |
| Option pressentie par le brief et par Q6 | Biais possible en faveur d'Argo CD | Même script et mêmes sources pour toutes les options |
| Notes de jugement : sécurité, expérience dev | Le classement entre Argo CD et Flux peut en dépendre (section 7) | Relectures de [SECU] et de [FINOPS] |
| Seuil de volume écrit après la lecture des tailles d'images | Biais possible sur le seuil 1 | Seuil tiré du budget d'ENF-01 et du débit de BENCH-003, sans valeur prise aux options |
| Règle de mémoire au nœud et règle d'égalité écrites après l'indice de [FINOPS] sur Argo CD | Biais possible en défaveur d'Argo CD (première règle) et en sa faveur (seconde) | Règles posées par le DSI pour la cohérence avec BENCH-004 et BENCH-007, écrites avant la série de référence, et dites telles quelles en 4.1 |
| Nœud de base (M8) mesuré dans une autre session que la série principale, le 2026-11-19 vers 23 h UTC contre 21 h | Bruit de l'état du poste sur la différence de M2 | Remesurer les quatre configurations dans une même série alternée |
| Mémoire au nœud par `docker stats`, qui ne distingue pas ce qui revient au serveur d'API, à etcd ou au cache | La part d'Argo CD qui n'apparaît dans aucun pod reste une hypothèse (serveur d'API chargé par ses CRD) | Relever les pods de `kube-system` par la même API Summary avant et après l'installation |
| Somme des seuils de couche : 112,5 Mo ici, 500 Mo pour la plate-forme, 100 Mo pour les secrets, soit 63 % du budget de volume avant la stack (calcul de [FINOPS]) | Les seuils de couche, posés un par un, ne bornent pas le total | Décision de Lucas sur le périmètre et les parts, à la GATE 1 |
| Serveur Git de test construit sur Alpine 3.24 figée par condensat, mais paquets `git`, `git-daemon` et `lighttpd` installés par `apk` sans version figée | Image de test non reproductible à l'octet près | Figer les versions des paquets, ou servir le dépôt par un outil déjà au catalogue |
| Gouvernance mesurée par les identifiants des commits, employeurs déclaratifs | Un compte multiple ou un profil faux fausserait les parts | Relire la liste des auteurs à la main |

## 9. Sources

[BENCH] Les dates de release, les comptes d'activité, les avis de sécurité et
les métadonnées des dépôts viennent de l'API publique de GitHub, lue le
2026-11-19. Un commit est compté humain quand son auteur n'est pas un robot
(`bot`, `renovate`, `dependabot`, `github-actions`, `copilot` filtrés par leur
nom) ; « hors fusion » écarte les commits à plusieurs parents.

[BENCH] Les sources des relectures, lues le 2026-11-19, gardent la
numérotation de [SECU] (S64 à S92) quand l'URL est nouvelle ; une URL déjà
citée garde son premier identifiant. Ainsi S64 devient [S8], S69 [S19], S70
[S18], S71 [S6], S72 [S17], S73 [S5], S74 [S32], S76 [S39], S79 [S33], S80
[S37], S82 [S23], S84 [S24], S88 [S62] et S91 [S63]. Côté [FINOPS], F1
devient [S93], F2 [S39], F3 [S94], F4 [S95], F6 [S97] et F7 [S77] ; F5, un
extrait de recherche que [FINOPS] n'a pas retenu comme preuve, n'est pas
repris. S92 n'est pas cité. Faits ajoutés à [S39] par [FINOPS] : en
Autopilot, demande et limite de `reconciler` à 700 m et 512 Mio,
`hydration-controller` 200 m et 256 Mio, `git-sync` 20 m et 32 Mio,
`otel-agent` 10 m et 64 Mio, par `RootSync`.

| ID | URL | Lue le | Ce que la source établit | Officielle |
| --- | --- | --- | --- | --- |
| S1 | <https://github.com/argoproj/argo-cd> | 2026-11-19 | Apache-2.0, dépôt non archivé, créé le 2018-02-09 | Oui |
| S2 | <https://api.github.com/repos/argoproj/argo-cd/releases> | 2026-11-19 | 3.6.2 le 2026-11-18, 3.6.0 le 2026-11-03 ; 68 releases stables depuis le 2025-11-19, mineures 3.0 à 3.6 | Oui |
| S3 | <https://github.com/argoproj/argo-cd/releases/tag/v3.6.2> | 2026-11-19 | Installation « Non-HA » : `kubectl create namespace argocd`, puis `kubectl apply -n argocd --server-side --force-conflicts -f …/v3.6.2/manifests/install.yaml` ; images signées par cosign, provenance SLSA de niveau 3 ; tag sur le commit `8e8268ef2f3df99ca95663f5080fa6056f156805` | Oui |
| S4 | <https://api.github.com/repos/argoproj/argo-cd/commits?since=2025-11-19T00:00:00Z> | 2026-11-19 | 2 417 commits, dont 1 447 humains hors fusion par 417 auteurs ; premier auteur 7,7 %, deux premiers 14,0 % ; dernier commit le 2026-11-19 | Oui |
| S5 | <https://github.com/argoproj/argoproj/blob/main/MAINTAINERS.md> | 2026-11-19 | Mainteneurs du projet Argo et leurs organisations : 52 avec un rôle sur Argo CD, 18 organisations, dont Red Hat 12, Akuity 11, Intuit 8, Octopus Deploy 4 ; responsables d'Argo CD chez Intuit et Akuity | Oui, déclaratif |
| S6 | <https://www.cncf.io/projects/argo/> | 2026-11-19 | Accepté le 2020-03-26, gradué le 2022-12-06 | Oui |
| S7 | <https://github.com/argoproj/argo-cd/blob/master/SECURITY.md> | 2026-11-19 | Version 1.7 du 2026-10-22 ; trois dernières mineures maintenues ; signalement privé GitHub activé (API `private-vulnerability-reporting`) | Oui |
| S8 | <https://api.github.com/repos/argoproj/argo-cd/security-advisories> | 2026-11-19 | 11 avis depuis le 2025-11-19 : CVE-2026-77459, CVE-2026-113708, CVE-2026-113709, CVE-2026-113672 et CVE-2026-42880 critiques ; CVE-2025-61560, CVE-2026-55797 et CVE-2026-45738 élevés ; GHSA-g3ff-q88g-chrj, GHSA-w996-f2wq-x9c6 et CVE-2026-45737 moyens | Oui |
| S9 | <https://argo-cd.readthedocs.io/en/stable/operator-manual/signed-release-assets/> | 2026-11-19 | Images signées par cosign sans clé, provenance SLSA de niveau 3, sommes de contrôle de la CLI ; rien sur les manifests d'installation | Oui |
| S10 | <https://github.com/argoproj/argo-cd/blob/master/USERS.md> | 2026-11-19 | 451 organisations déclarées | Oui, déclaratif |
| S11 | <https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/> | 2026-11-19 | Synchronisation automatique ; `timeout.reconciliation` à 120 s par défaut, plus 60 s d'aléa, soit 3 minutes au plus | Oui |
| S12 | <https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-List/> | 2026-11-19 | ApplicationSet à générateur de liste, `goTemplate: true` | Oui |
| S13 | <https://argo-cd.readthedocs.io/en/stable/user-guide/annotations-and-labels/> | 2026-11-19 | Annotation `argocd.argoproj.io/refresh`, valeurs `normal` et `hard` | Oui |
| S14 | <https://github.com/fluxcd/flux2> | 2026-11-19 | Apache-2.0, dépôt non archivé, créé le 2020-04-24 | Oui |
| S15 | <https://api.github.com/repos/fluxcd/flux2/releases> | 2026-11-19 | 2.10.0 le 2026-10-26 ; 19 releases stables depuis le 2025-11-19, mineures 2.7 à 2.10 ; `install.yaml` en `sha256:a8c838cc…7f28`, sommes de contrôle signées (`.sigstore.json`) | Oui |
| S16 | <https://api.github.com/repos/fluxcd/flux2/commits?since=2025-11-19T00:00:00Z> | 2026-11-19 | `flux2` : 213 commits humains hors fusion par 49 auteurs, premier 31,0 %, deux premiers 62,0 %. Même requête : source-controller 123 (53,7 %), kustomize-controller 124 (70,2 %), helm-controller 140 (68,6 %) ; dernier commit le 2026-11-17 | Oui |
| S17 | <https://github.com/fluxcd/community/blob/main/CORE-MAINTAINERS> | 2026-11-19 | Neuf mainteneurs principaux : ControlPlane (3), NexHealth, Associmates, SUSE, trois indépendants | Oui, déclaratif |
| S18 | <https://www.cncf.io/projects/flux/> | 2026-11-19 | Accepté le 2019-07-15, incubation le 2021-03-12, gradué le 2022-11-30 | Oui |
| S19 | <https://github.com/fluxcd/.github/blob/main/SECURITY.md> | 2026-11-19 | Signalement par `cncf-flux-security@lists.cncf.io`, équipe de quatre personnes, « best-effort basis » ; signalement privé GitHub désactivé sur `fluxcd/flux2` (API) | Oui |
| S20 | <https://api.github.com/advisories?ecosystem=go&affects=github.com/fluxcd/source-controller> | 2026-11-19 | Même requête pour `flux2` et chaque contrôleur : 10 avis depuis 2021, dont 2 depuis le 2025-11-19, CVE-2026-47680 (moyen, 2026-06-05) et CVE-2026-40109 (faible, 2026-04-10). Aucun avis pour `GoogleContainerTools/config-sync` ni `kpt.dev/configsync` | Oui |
| S21 | <https://fluxcd.io/flux/security/> | 2026-11-19 | Images signées par cosign, SBOM SPDX, SLSA Build Level 3, profil « restricted » des Pod Security Standards | Oui |
| S22 | <https://fluxcd.io/flux/installation/> | 2026-11-19 | Installation de développement par `kubectl apply -f …/install.yaml` ; chart Helm communautaire « best effort » ; Flux Operator | Oui |
| S23 | <https://fluxcd.io/flux/components/source/gitrepositories/> | 2026-11-19 | `spec.url` en HTTP/S ou SSH, `spec.interval` obligatoire, annotation `reconcile.fluxcd.io/requestedAt` | Oui |
| S24 | <https://fluxcd.io/flux/components/kustomize/kustomizations/> | 2026-11-19 | Champs obligatoires ; un changement de révision de la source est traité « instantly outside the interval window » ; sans `kustomization.yaml`, le fichier « is automatically generated » | Oui |
| S25 | <https://github.com/fluxcd/website/blob/main/data/adopters/1-flux-v2.yaml> | 2026-11-19 | 127 adoptants de Flux v2 | Oui, déclaratif |
| S26 | <https://github.com/GoogleContainerTools/config-sync> | 2026-11-19 | Apache-2.0, dépôt non archivé, créé le 2022-03-02 sous le nom `kpt-config-sync` ; le README renvoie à l'installation de « OSS Config Sync » | Oui |
| S27 | <https://api.github.com/repos/GoogleContainerTools/config-sync/releases> | 2026-11-19 | 1.25.2 le 2026-11-03 ; 11 releases stables depuis le 2025-11-19, mineures 1.23 à 1.25 ; première release « launch » le 2022-05-13 ; `config-sync-manifest.yaml` en `sha256:bb5cf3ca…8121` ; binaires `nomos` | Oui |
| S28 | <https://github.com/GoogleContainerTools/config-sync/blob/main/docs/installation.md> | 2026-11-19 | Installation libre par `kubectl apply -f …/config-sync-manifest.yaml` | Oui |
| S29 | <https://api.github.com/repos/GoogleContainerTools/config-sync/commits?since=2025-11-19T00:00:00Z> | 2026-11-19 | 299 commits, dont 173 de Dependabot et 126 humains par 8 auteurs ; premier 47,6 %, deux premiers 75,4 % ; dernier commit le 2026-11-18 | Oui |
| S30 | <https://github.com/GoogleContainerTools/config-sync/blob/main/SECURITY.md> | 2026-11-19 | Signalement par g.co/vulnz, réponse sous 5 jours ouvrés ; signalement privé GitHub activé ; aucun avis publié (API `security-advisories`) | Oui |
| S31 | <https://docs.cloud.google.com/kubernetes-engine/config-sync/docs/overview> | 2026-11-19 | « a GitOps service included with Google Kubernetes Engine (GKE) » ; sources Git, OCI et Helm | Oui |
| S32 | <https://docs.cloud.google.com/kubernetes-engine/config-sync/docs/release-notes> | 2026-11-19 | 1.22.0 du 2025-09-02 : « available as part of the standard GKE offering and no longer requires GKE Enterprise » ; 1.25.2 du 2026-11-09 ; CVE corrigées sans être nommées dans neuf releases de 2026 ; 1.3.3 du 2020-07-30 | Oui |
| S33 | <https://docs.cloud.google.com/kubernetes-engine/config-sync/docs/concepts/cluster-requirements> | 2026-11-19 | Autopilot et Standard pris en charge ; inscription dans une flotte exigée ; « Config Sync can run only on x86-based nodes, not Arm nodes » | Oui |
| S34 | <https://docs.cloud.google.com/kubernetes-engine/config-sync/docs/how-to/installing-config-sync> | 2026-11-19 | « all clusters must be registered to a fleet » ; source Helm non configurable par la console ni par gcloud | Oui |
| S35 | <https://docs.cloud.google.com/kubernetes-engine/enterprise/docs/deployment-options> | 2026-11-19 | Config Sync dans les fonctions incluses à l'activation de GKE, disponible en Standard et en Autopilot, pas sans appartenance à une flotte | Oui |
| S36 | <https://cloud.google.com/blog/products/containers-kubernetes/gke-gets-new-pricing-and-capabilities-on-10th-birthday> | 2026-11-19 | Billet du 2025-08-27 : niveau payant unique en septembre 2025, « Fleets, Teams, Config Management, and Policy Controller [...] all available with GKE Standard at no additional cost » | Oui |
| S37 | <https://docs.cloud.google.com/kubernetes-engine/config-sync/docs/concepts/kustomize> | 2026-11-19 | Rendu Kustomize : dépôt hiérarchique non pris en charge, bases distantes privées non prises en charge, `kustomization.yaml` à la racine du dossier synchronisé | Oui |
| S38 | <https://docs.cloud.google.com/kubernetes-engine/enterprise/config-sync/docs/how-to/unstructured-repo> | 2026-11-19 | Format `unstructured` recommandé ; organisation par environnement par plusieurs `RootSync` sur chaque cluster ; ClusterRoles intégrés non gérables | Oui |
| S39 | <https://docs.cloud.google.com/kubernetes-engine/config-sync/docs/concepts/architecture> | 2026-11-19 | « hosted components in Google Cloud and open source components on your Google Kubernetes Engine cluster » ; composants gérés par le service Fleet ; « You must manually upgrade Config Sync as needed » | Oui |
| S40 | `config-sync-manifest.yaml` de la release 1.25.2, CRD `rootsyncs.configsync.gke.io` | 2026-11-19 | `sourceFormat` à `hierarchy` si absent ; `git.auth` accepte `none` ; `git.period` à 15 s par défaut ; versions `v1alpha1` et `v1beta1` | Oui |
| S41 | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests> | 2026-11-19 | Demandes par défaut en Autopilot : 0,5 vCPU, 2 Gio, 1 Gio de stockage éphémère ; facture fondée sur la demande effective du pod | Oui |
| S42 | <https://docs.aws.amazon.com/eks/latest/userguide/argocd.html> | 2026-11-19 | « With EKS Capabilities, Argo CD is fully managed by AWS » ; le logiciel tourne dans le plan de contrôle d'AWS | Oui |
| S43 | <https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/tutorial-use-gitops-flux2> | 2026-11-19 | Extension `microsoft.flux` pour AKS et Azure Arc ; contrôleurs source, helm, kustomize et notification par défaut | Oui |
| S44 | Registres `quay.io`, `ghcr.io`, `public.ecr.aws`, `gcr.io`, lus par `docker manifest inspect -v` et `docker buildx imagetools inspect` | 2026-11-19 | Condensats d'index, architectures et tailles compressées des images des trois manifests ; images de Config Sync en `linux/amd64` seulement | Oui |
| S45 | <https://git-scm.com/docs/git-http-backend> | 2026-11-19 | Configuration lighttpd de `git-http-backend` ; `http.receivepack` à `true` pour un push anonyme | Oui |
| S46 | <https://pkgs.alpinelinux.org/contents?file=git-http-backend&branch=v3.22&repo=main&arch=aarch64> | 2026-11-19 | `git-http-backend` fourni par le paquet `git-daemon` | Oui |
| S47 | <https://opensource.org/licenses> | 2026-11-19 | Apache-2.0 et AGPLv3 approuvées par l'OSI (liste relue pour BENCH-003) | Oui |
| S48 | Profils GitHub de `crenshaw-dev`, `blakepettersson`, `ppapapetrou76`, `matheuscscp`, `stefanprodan` | 2026-11-19 | Employeurs déclarés : Intuit, Akuity, Octopus Deploy, ControlPlane, ControlPlane | Oui, déclaratif |
| S49 | ADR-009, section 2 et question 3 (worktree du catalogue, statut proposé) | 2026-11-19 | Lecture des principes III et V ; `managed_gap` pour un composant libre sur `gcp` ; question GitOps renvoyée à un arbitrage | Oui, interne |
| S50 | [ADR-004](../adr/ADR-004-cluster-local.md) | 2026-11-19 | kind 0.33.0, image de nœud `kindest/node:v1.36.4@sha256:099e…faed` | Oui, interne |
| S51 | `manifests/install.yaml` et `manifests/core-install.yaml` d'Argo CD au commit `8e8268ef` | 2026-11-19 | `install.yaml` : SHA-256 `c948064d…a2a2`, 8 conteneurs en `imagePullPolicy: Always`, aucune demande de ressources, images par tag `argocd:v3.6.2`, `dex:v2.46.0`, `redis:8.10.1-alpine`. `core-install.yaml` : `argocd` (5 conteneurs) et `redis` seulement | Oui |
| S52 | `install.yaml` de la release 2.10.0 de Flux | 2026-11-19 | Sept contrôleurs en `imagePullPolicy: IfNotPresent`, demandes de 50 ou 100 mCPU et 64 Mio, images par tag | Oui |
| S53 | <https://redis.io/legal/licenses/> | 2026-11-19 | Redis 8.0 et suivants sous RSALv2, SSPLv1 ou AGPLv3 ; 7.2 et avant sous BSD-3-Clause | Oui |
| S54 | <https://api.github.com/repos/fluxcd/source-controller> | 2026-11-19 | Même requête pour les sept contrôleurs de Flux, `dexidp/dex`, `kubernetes/git-sync` et `open-telemetry/opentelemetry-collector-contrib` : Apache-2.0, non archivés | Oui |
| S55 | Recherche sur `docs.cloud.google.com` et `cloud.google.com` (« Config Sync » security bulletin) | 2026-11-19 | Aucun bulletin de sécurité GKE propre à Config Sync trouvé ; dernière CVE nommée par ses notes de version en 2020 | Oui, recherche |
| S56 | <https://argo-cd.readthedocs.io/en/stable/operator-manual/core/> | 2026-11-19 | Argo CD Core, installation « headless » par `core-install.yaml` : sans API, sans RBAC propre, sans notifications ni OIDC ; Redis inclus | Oui |
| S57 | <https://fluxcd.io/flux/installation/configuration/optional-components/> | 2026-11-19 | Composants par défaut : source, kustomize, helm et notification ; `image-reflector-controller`, `image-automation-controller` et `source-watcher` en option par `--components-extra` | Oui |
| S58 | <https://docs.cloud.google.com/kubernetes-engine/config-sync/docs/how-to/nomos-command> | 2026-11-19 | `nomos vet` vérifie un dépôt, `--source-format=unstructured` obligatoire pour ce format, `--no-api-server-check` évite le cluster ; `nomos` s'installe par gcloud ou depuis la page de téléchargement | Oui |
| S59 | <https://docs.github.com/en/actions/reference/runners/github-hosted-runners> | 2026-11-19 | Runners Linux standard : `ubuntu-latest` en x64, et des runners arm64 sous `ubuntu-24.04-arm` ; 4 CPU et 16 Go en dépôt public, 2 CPU et 8 Go en privé | Oui |
| S60 | <https://argo-cd.readthedocs.io/en/stable/user-guide/application_sources/> | 2026-11-19 | Sources d'une Application : Kustomize, chart Helm, image OCI, dossier de manifests YAML, JSON ou Jsonnet, greffon de gestion de configuration | Oui |
| S61 | <https://docs.cloud.google.com/kubernetes-engine/docs/release-notes> | 2026-11-19 | Entrée du 2025-09-02 : Config Sync parmi les fonctions « included in the GKE offering at no additional cost » ; texte relevé par l'outil de recherche, la page entière n'ayant pas été lue | Oui, par extrait |
| S62 | <https://kubernetes.io/docs/concepts/containers/images/> | 2026-11-19 | Avec `imagePullPolicy: Always`, « The container runtime contacts the registry » à chaque lancement de conteneur, et réutilise les couches en cache ; `IfNotPresent` ne tire que si l'image manque ; un condensat fige le contenu | Oui |
| S63 | <https://docs.orbstack.dev/docker/> | 2026-11-19 | Sur processeur Apple, OrbStack exécute par Rosetta les images construites pour x86_64/amd64 ; page voisine <https://docs.orbstack.dev/settings> : réglage `rosetta` | Oui, éditeur d'OrbStack ; texte relevé par l'outil de recherche |
| S66 | <https://api.github.com/repos/fluxcd/flux2/security-advisories>, même requête pour chaque contrôleur et `pkg` | 2026-11-19 | 3 avis depuis le 2025-11-19 : GHSA-mwcp-qpcg-fr7c (élevé, 7.1, sans CVE, NetworkPolicy `allow-webhooks`, corrigé en 2.9.4), CVE-2026-47680 (moyen), CVE-2026-40109 (faible). Relevé de [SECU] | Oui |
| S67 | <https://api.github.com/advisories?ghsa_id=GHSA-mwcp-qpcg-fr7c> | 2026-11-19 | 0 résultat dans la base mondiale pour l'avis de 2026. Relevé de [SECU] | Oui |
| S68 | <https://api.github.com/repos/fluxcd/flux2/releases/tags/v2.9.4> et tags `v1.8.5` de `source-controller`, `v1.8.3` de `notification-controller` | 2026-11-19 | Correctifs publiés le 2026-08-07, le 2026-05-20 et le 2026-04-07, avant leurs avis. Relevé de [SECU] | Oui |
| S75 | <https://docs.cloud.google.com/kubernetes-engine/config-sync/docs/how-to/upgrade-config-sync> | 2026-11-19 | « Manually upgrade Config Sync » ; « upgrade at least every nine months » ; notes de version 1.21.0 (2025-05-01) : « auto-upgrades feature is now unavailable ». Relevé de [SECU] | Oui |
| S77 | <https://docs.cloud.google.com/kubernetes-engine/config-sync/docs/reference/rootsync-reposync-fields> | 2026-11-19 | `roleRefs`, ClusterRoleBinding vers `cluster-admin` si absent, depuis la 1.17.0 ; `spec.override.resources` et ses limites en Autopilot ; `spec.monitoring.enabled` à vrai par défaut. Relevé de [SECU] et de [FINOPS] | Oui |
| S78 | <https://docs.cloud.google.com/kubernetes-engine/enterprise/config-sync/docs/how-to/grant-access-git> | 2026-11-19 | Types d'authentification ; jeton GitHub de portée `repo` ; `known_hosts` « Optional, but recommended », vérification désactivée sans lui ; `k8sserviceaccount` pour Helm et OCI. Relevé de [SECU] | Oui |
| S81 | <https://cloud.google.com/anthos-config-management/docs/how-to/managing-objects> | 2026-11-19 | `configmanagement.gke.io/managed: disabled` fait cesser la gestion d'un objet. Relevé de [SECU] par l'outil de recherche | Oui, par extrait |
| S83 | <https://fluxcd.io/flux/installation/configuration/multitenancy/> | 2026-11-19 | Contrôleurs liés à `cluster-admin` par défaut ; `--no-cross-namespace-refs`, `--no-remote-bases`, `--default-service-account`. Relevé de [SECU] | Oui |
| S85 | <https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps> | 2026-11-19 | Portée `repo` : « full access to public and private repositories including read and write access to code ». Relevé de [SECU] | Oui |
| S86 | <https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys> | 2026-11-19 | Clé de déploiement en lecture seule par défaut, limitée à un dépôt. Relevé de [SECU] | Oui |
| S87 | <https://argo-cd.readthedocs.io/en/stable/getting_started/> | 2026-11-19 | Mot de passe initial `admin` en clair dans `argocd-initial-admin-secret`, à supprimer après changement. Relevé de [SECU] | Oui |
| S89 | <https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/images/> | 2026-11-19 | Champ `digest` du transformateur `images` de Kustomize. Relevé de [SECU] | Oui |
| S90 | <https://trivy.dev/latest/docs/coverage/language/golang/> | 2026-11-19 | Trivy lit les dépendances des binaires Go dans les images. Relevé de [SECU] | Oui |
| S93 | <https://cloud.google.com/kubernetes-engine/pricing> | 2026-11-19 | Illisible par les outils des agents : le titre seul. Relevé de [FINOPS] | Oui |
| S94 | <https://docs.cloud.google.com/kubernetes-engine/config-sync/docs/how-to/monitoring-config-sync> | 2026-11-19 | Métriques exportées vers Cloud Monitoring, « charges for the ingestion of these metrics are based on the number of samples ingested ». Relevé de [FINOPS] | Oui |
| S95 | <https://docs.cloud.google.com/kubernetes-engine/docs/how-to/extended-duration-pods> | 2026-11-19 | « Autopilot charges you for the resource requests of your running Pods. You're not charged for system overhead or for unused node capacity. » Relevé de [FINOPS] | Oui |
| S97 | <https://cloud.google.com/stackdriver/pricing> | 2026-11-19 | Illisible : le titre seul. Relevé de [FINOPS] | Oui |

## 10. Relectures

| Relecteur | Porte sur | Date | Avis |
| --- | --- | --- | --- |
| [SECU] | Licences, critères éliminatoires, sécurité, droits des moteurs, identifiants Git | 2026-11-19 | Favorable sous réserve |
| [FINOPS] | Coût sur GKE et Autopilot, empreinte, R-04 | 2026-11-19 | Réservé |

[SECU] Aucune note changée. Flux a publié 3 avis en douze mois, pas 2, dont
GHSA-mwcp-qpcg-fr7c, élevé, sans CVE et absent de la base mondiale : sa note
reste 4, avec une veille dépôt par dépôt. L'argument « `IfNotPresent`
permet de recréer hors ligne » est faux tant que R-25 n'est pas résolu par un
préchargement qui garde le condensat. Les droits des moteurs et les
identifiants Git manquaient : ils sont ajoutés (7.3, 7.4), avec les
conditions de l'ADR-010 (7.5). Les mesures de Config Sync sous Rosetta ne
fondent aucun cran ; ses constats statiques restent valables. Le montage C est
acceptable côté sécurité sous ces conditions ; le montage B ne l'est pas.
R-31, R-32 et R-33 sont proposés, R-25 complété.

[FINOPS] Le coût d'Argo CD passe à 4/5 (même règle que pour ESO dans
BENCH-007) et celui de Config Sync à 3/5 : sa licence est incluse, ses pods et
ses métriques ne le sont pas forcément, et ils demandent plus que Flux sur
GKE. Le volume se cite en amd64. Config Sync dépasse le seuil de mémoire dès
un environnement. Lue au nœud, la mémoire d'Argo CD dépasse ce que ses pods
expliquent d'environ 250 Mio : d'où la règle de mémoire du DSI et la
série de référence M8. Le montage C tient par le principe III, sans avantage
de coût établi sur le montage A. Aucun montant n'est écrit, les grilles
étant illisibles (R-05).

[BENCH] Suite donnée : toutes les corrections demandées sont intégrées. Le DSI
a arbitré le 2026-11-19 : coûts de [FINOPS] acceptés, aucune note changée par
[SECU], règle de mémoire au nœud et règle d'égalité écrites en 4.1 avant la
série de référence, trois arguments de départage retirés de 7.2 (mémoire et
temps d'installation, recréation hors ligne, nombre d'avis).
