# ADR-004. kind crée le cluster local du projet généré, sous conditions

| Champ | Valeur |
| --- | --- |
| Statut | proposé |
| Date | 2026-11-19 |
| Auteur | [ARCHI] |
| Décideur | Lucas, en attente de la GATE 1 ; kind retenu par Lucas le 2026-11-19 |
| BENCH lié | [BENCH-003](../benchmarks/BENCH-003-cluster-local.md) |
| Remplace | aucun |

## Contexte et problème

Sur la cible `local`, `task up` démarre l'API, le front, Postgres et le cache du projet généré dans un cluster Kubernetes créé sur le poste. L'outil qui crée ce cluster doit être choisi avant le golden repo de la phase 2, et avant BENCH-004, BENCH-005 et BENCH-007, qui se mesurent dessus. Le PRD pressentait k3d, repris du brief (section 1 du PRD).

Les exigences viennent du PRD. US-005 veut que `task up` démarre toute la stack sans autre étape (principe VII), affiche les adresses locales et choisisse un profil lite, standard ou full selon la RAM. ENF-01 fixe le parcours à moins de 15 minutes, premier téléchargement des images compris. ENF-02 veut que seule la couche de cible change entre le PC et GCP (principe II), que le README liste les écarts restants, et que l'empreinte de chaque profil soit mesurée. Côté constitution, les principes III, V, VI et VIII. Côté risques, R-04 (15 minutes hors d'atteinte), R-20 (ports publiés sur toutes les interfaces), R-25 (démarrage tributaire des registres publics) et R-26 (moteur de conteneurs du poste sous licence payante).

La cible `gcp` passe par GKE et ne voit pas l'outil. Elle pèse en revanche sur la version de Kubernetes, qui ne se règle pas de la même façon des deux côtés : kind 0.33.0 crée par défaut un cluster v1.37.0, BENCH-003 a mesuré v1.36.4, et la version d'un cluster GKE suit son canal de release. Cet ADR fixe donc aussi la règle de version.

Le classement de tête de BENCH-003 dépendait de la règle de notation de l'empreinte, et les deux règles en présence avaient été posées après lecture des chiffres. Lucas a tranché le 2026-11-19 (voir « Tranché par Lucas le 2026-11-19 »).

## Options considérées

| Option | Score BENCH (sur 100) | Verdict | Raison principale |
| --- | --- | --- | --- |
| kind 0.33.0 | 90 | retenue | Rien n'est retéléchargé à la création une fois l'image de nœud en cache, le nœud est figé par condensat, la première création pèse 351,7 Mo, et seule l'API est exposée, en boucle locale |
| minikube 1.39.0 | 87 | écartée | 853,3 Mo à la première création, au-delà du seuil de 500 Mo, et CNI `kindnetd` retéléchargé par tag à chaque création, avec `NET_ADMIN` sur le réseau de l'hôte : 3/5 en empreinte comme en sécurité |
| k3d 5.9.0 | 64 | écartée | Organisation communautaire sans fondation, une seule release en 12 mois, API et registre sans authentification publiés sur toutes les interfaces par défaut, CRD Gateway API v1.5.1 préinstallées en conflit avec la v1.7.0 |

Ces totaux appliquent la règle d'empreinte de [FINOPS], validée par Lucas. Avec l'ancienne règle de [BENCH] et le tirage de kindnetd compté une seule fois, en empreinte et non en sécurité, minikube passerait à 91 contre 90 pour kind. Avec la règle retenue, un cran de gouvernance rendu à minikube donne l'égalité à 90, et un cran de sécurité en plus le met à 92. kind monterait à 93 avec une version 1.0. k3d reste dernier dans tous les cas, à 26 points au moins.

L'écart entre kind et minikube tient donc dans un ou deux crans, et la grille seule ne les départage pas. Les critères que BENCH-003 a écrits hors grille vont tous dans le sens de kind :

- aucun tirage à chaud dans M6, donc un cluster qui devrait se recréer sans réseau une fois l'image de nœud en cache, ce qui reste à essayer (condition 7) ;
- un nœud entièrement figé par condensat ;
- une première création 2,4 fois plus légère, 351,7 Mo contre 853,3 en arm64 ;
- une configuration déclarative, en YAML versionnable dans le projet généré ;
- l'API seule exposée, en boucle locale ;
- Podman documenté, voie possible vers un moteur libre (R-26).

Grille, mesures et sources : [BENCH-003](../benchmarks/BENCH-003-cluster-local.md).

## Décision

Le projet généré crée son cluster local avec kind 0.33.0. L'image de nœud est désignée par son condensat, et la configuration du cluster est un fichier YAML déclaratif, versionné dans la couche `local` du blueprint, que `task up` passe à kind.

Lucas a retenu kind le 2026-11-19. La validation d'ensemble de cet ADR, conditions et règle de version comprises, reste à faire à la GATE 1.

### Conditions

Elles reprennent les exigences de [SECU] et les réserves de BENCH-003 (sections 7 et 10). La décision ne vaut qu'avec elles. Chaque test cité entre dans la matrice de validation (principe I).

1. Boucle locale partout (R-20). La configuration garde `networking.apiServerAddress` à 127.0.0.1, sa valeur par défaut, et chaque entrée de `extraPortMappings` porte `listenAddress: "127.0.0.1"`, dont la valeur par défaut est 0.0.0.0. Un test de la matrice relève les ports en écoute après `task up` et échoue sur toute adresse 0.0.0.0, `[::]` ou `*`. Ajout de [ARCHI] : un contrôle statique de la configuration refuse, avant toute création, une entrée de `extraPortMappings` sans `listenAddress`.
2. Version exacte de kind. `task up` lit la version du binaire et refuse de démarrer si elle diffère de celle que fixe le blueprint, 0.33.0 aujourd'hui. Le message donne la version attendue et renvoie à la procédure d'installation du README. La commande qui lit la version se fixe en phase 3 avec [OPS].
3. Aucune image tirée par tag à la création. L'image de chaque nœud figure dans la configuration avec son condensat, prise dans la liste publiée avec la version de kind figée (règle de version ci-dessous). Les images de la stack sont elles aussi désignées par condensat (ENF-03). Si BENCH-005 demande un registre local, son image suit la même règle : le script de la documentation de kind lance `registry:3` par tag.
4. Manifests tiers versionnés. Les manifests tiers, comme les CRD Gateway API, sont versionnés dans le projet généré avec leur SHA-256, vérifié avant application. `task up` n'applique jamais un manifest depuis une URL. Pour Gateway API v1.7.0, BENCH-003 a relevé le SHA-256 de `standard-install.yaml`, issu d'une release immuable avec attestation ; la version retenue revient à BENCH-004.
5. Binaire vérifié contre le catalogue. La procédure d'installation du README vérifie le SHA-256 du binaire de kind contre la valeur du catalogue de CELIAN. La somme publiée dans la même release ne suffit pas : kind ne signe pas ses binaires, ne publie pas d'attestation et ses releases ne sont pas immuables, si bien que cette somme protège de la corruption et pas de la substitution. [SECU] a relevé le condensat du binaire darwin-arm64 (section « Entrée au catalogue ») ; ceux des autres systèmes de Q5 restent à relever avant que le blueprint s'en serve.
6. Mémoire minimale par profil. La configuration documentée de kind n'a aucun réglage de CPU ni de mémoire par nœud : les profils lite, standard et full de US-005 ne peuvent pas brider le cluster. Le README du projet généré donne donc, pour chaque profil, la mémoire minimale de la machine virtuelle du moteur de conteneurs. Le choix du profil lit la mémoire que déclare le moteur (`docker info` sous Docker), et non la mémoire physique : 11,73 Gio sur 24 sur le poste de mesure. Les valeurs se mesurent en BENCH-005.
7. Recréation hors ligne (R-25). Un test de la matrice lance `task up`, supprime le cluster, coupe le réseau, puis relance `task up`, qui doit réussir depuis le cache. M6 montre que kind ne tire rien à chaud, mais la recréation sans réseau n'a jamais été essayée, alors qu'elle fait partie des critères hors grille qui ont fait pencher le choix.
8. Moteur libre (R-26). [OPS] évalue avec Podman, pour chaque système de Q5, un moteur de conteneurs libre sur lequel kind crée le cluster. Le README le cite en premier, et la matrice tourne sur au moins un moteur libre. kind documente Podman ; le niveau de prise en charge qu'il annonce n'a pas été lu pour cet ADR.
9. Kubeconfig hors du dépôt. Ajout de [ARCHI] : le kubeconfig que kind écrit permet de joindre l'API du cluster. `task up` l'écrit hors du dépôt ou dans un chemin ignoré par Git, par l'option `--kubeconfig` ou la variable `KUBECONFIG` (principe IX).

### Version de Kubernetes

Faits lus le 2026-11-19. kind 0.33.0 crée par défaut un cluster v1.37.0 et publie des images de nœud pour v1.37.0, v1.36.4, v1.35.8 et v1.34.11 ; ses notes de version exigent le condensat pour garantir une image construite pour cette release. Sur GKE, la documentation marque le canal Regular comme canal par défaut, « what we recommend for most users ». La version par défaut de Regular à la création d'un cluster est 1.36.4-gke.2377000 depuis l'entrée du 2026-11-10. La mineure 1.37 y est disponible depuis le 2026-10-22, et le calendrier de GKE en fait la cible de mise à jour automatique de Regular vers janvier 2027, date que la page donne comme estimation. Le canal Stable a pour défaut 1.35.8-gke.1796000 et propose 1.36 depuis le 2026-10-27. GKE numérote ses versions X.Y.Z-gke.N, où X.Y.Z est la version amont de Kubernetes, et peut publier plusieurs versions GKE pour un même correctif amont. En amont, la branche 1.36 a pour dernier correctif 1.36.5 et finit le 2027-06-28 ; GKE assure le support standard de 1.36 jusqu'au 2027-08-09.

Règle proposée par [ARCHI] :

1. Canal de référence : Regular. C'est le canal par défaut de GKE et celui qu'il recommande pour la plupart des usages, et sa version par défaut porte le même correctif amont, 1.36.4, que celle que BENCH-003 a mesurée. Le canal du cluster GKE généré se fixe avec la conception de la cible `gcp`, par [OPS]. S'il devient Stable, la règle s'applique à la version par défaut de Stable sans rouvrir cet ADR ; kind 0.33.0 publie une image v1.35.8.
2. Même mineure des deux côtés. La mineure du cluster local est celle de la version par défaut du canal de référence, relevée à chaque release du blueprint : 1.36 aujourd'hui, et non la v1.37.0 par défaut de kind 0.33.0. Le blueprint tient cette mineure en une seule valeur, lue par la couche `local` et par la couche `gcp` ; la façon dont la couche `gcp` l'applique revient à [OPS]. Un test de la matrice échoue si la mineure de l'image de nœud diffère de cette valeur.
3. Correctif fixé par condensat. L'image de nœud est la plus récente que la version de kind figée publie pour cette mineure. Elle est désignée par son condensat dans le champ `image` de chaque nœud, jamais laissée au défaut de kind. Aujourd'hui : `kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed`, même correctif amont que le défaut de Regular. CELIAN ne construit pas ses propres images de nœud : il faudrait les publier, et [SECU] demande de relire toute redistribution d'images avant (BENCH-003, section 7).
4. Écart de correctif admis. GKE ajoute des versions dans Regular au fil des semaines (1.36.5-gke.1982000 y est disponible depuis le 2026-11-13), alors que kind publie une image par mineure à chaque release. La parité visée porte sur la mineure : la politique de dépréciation de Kubernetes compte les délais de retrait des API bêta en versions mineures ou en mois (règle 4a). Un écart de correctif est admis, et le README du projet généré le liste, comme le demande ENF-02.
5. Mises à jour. Renovate propose dans une seule PR la paire formée par la version de kind et l'image de nœud de la même release, une fois cette release publiée depuis 7 jours (principe VI), parce que l'image doit avoir été construite pour cette version de kind. Il ne propose jamais seul un changement de mineure. La mineure change à la main, dans une release du blueprint qui passe toute la matrice, quand la version par défaut du canal de référence change de mineure, et au plus tard à la fin de vie amont de la mineure en cours (2027-06-28 pour 1.36). La configuration de Renovate qui tient ces deux contraintes n'a pas été vérifiée dans sa documentation : [OPS] la vérifie. À défaut, chaque release de kind donne lieu à une PR manuelle, avec le même délai de 7 jours.

### Portée

Le cluster local n'est pas une brique que la spec déclare : il découle de la cible `local`. La spec ne nomme pas kind, qui n'apparaît que dans la couche `local` du blueprint et au catalogue (principe II). La cible `gcp` garde GKE et ne reçoit de cette décision que la règle de version.

Restent hors de cette décision : la gateway (BENCH-004), l'orchestration locale et un éventuel registre local (BENCH-005), les secrets locaux (BENCH-007), le moteur de conteneurs du poste (R-26, [OPS]), Windows (Q5), et le mode, le canal et le dimensionnement du cluster GKE ([OPS], [FINOPS]).

## Conséquences

### Positives

- La première création télécharge 351,7 Mo compressés en arm64 et 384,8 Mo en amd64, sous le seuil de 500 Mo au-delà duquel R-04 passerait en probabilité forte.
- Rien n'est retéléchargé à chaud. La création prend 26,8 s images en cache et 73,7 s à froid, soit 8 % du budget de 900 s d'ENF-01 ; la suppression, 0,4 s.
- Le nœud est figé par condensat et aucune image n'est tirée par tag à la création : côté cluster, R-25 se limite à la première création, et le défaut d'intégrité relevé chez minikube n'existe pas.
- L'API écoute sur 127.0.0.1 par défaut, et aucun autre port n'est publié.
- Les nœuds sont montés par kubeadm, sans CRD Gateway API préinstallée : l'installation standard de Gateway API v1.7.0 passe sans conflit, ce qui sert BENCH-004 et la parité avec GKE (ENF-02).
- kind est un sous-projet de SIG Testing, donc de Kubernetes, gradué à la CNCF : trois releases et 172 commits humains par 31 auteurs en 12 mois.

### Négatives

- kind est en 0.x et se dit « still a work in progress ». Il est conçu d'abord pour tester Kubernetes lui-même, le développement d'applications venant en second.
- Un mainteneur porte 56 % des commits humains de l'année, malgré trois approbateurs de deux employeurs déclarés.
- Aucune limite de ressources par nœud : le README doit donner la mémoire du moteur par profil (condition 6), et la tenue de la stack sur un portable de 8 Gio reste à mesurer en BENCH-005.
- Pas de registre intégré. Si BENCH-005 en a besoin, il faut le monter et le tenir en boucle locale et par condensat (conditions 1 et 3).
- Les ports publiés se fixent à la création : la configuration déclare d'emblée tous les ports dont la stack a besoin, et un port ajouté demande de recréer le cluster.
- L'image de nœud occupe 908,8 Mo une fois décompressée dans le cache du moteur.
- kind crée par défaut un cluster v1.37.0 : un champ `image` oublié change la mineure sans erreur, d'où le test de la règle de version.
- Le cluster local et le cluster GKE peuvent diverger de mineure : GKE met à jour seul les clusters d'un canal, mineure comprise, alors que le projet généré garde sa configuration jusqu'à sa mise à jour (question ouverte 1).
- Les mesures viennent d'un seul poste, sous macOS avec OrbStack, moteur non libre (R-26). Ni Linux avec Docker Engine ni un runner amd64 n'ont été mesurés.
- Sur un projet généré privé, chaque job de CI crée le cluster à froid : 123 minutes pour 100 jobs dans l'hypothèse de [FINOPS], 6 % de l'allocation gratuite de GitHub Free. R-16 ne couvre que le dépôt de CELIAN, donc le README du projet généré doit le dire.

### Effet sur les cibles hors MVP

La porte reste ouverte. kind ne vit que dans la couche `local`. Une cible AWS ou Azure ajoutera sa couche et sa ligne de catalogue, et la règle de version s'appliquera au canal de son service managé ; le jour où deux clouds coexisteront, le choix de la mineure commune demandera un nouvel ADR. kind se présente comme un outil de test, de développement local et de CI : une cible on-prem serveurs aurait sa propre ligne au catalogue, choisie par son benchmark.

### Suites

- Amendement de la constitution. Sa section « Périmètre du MVP » écrit « PC sous k3d ». La PR #13 l'amende, comme le prévoit la section « Gouvernance » : la version 1.1.0 parle d'un cluster Kubernetes local et renvoie à cet ADR pour l'outil. Elle corrige aussi `CLAUDE.md`, `docs/vision.md`, `docs/prd-mvp.md` (tableau des choix ouverts) et les fiches des agents `bench`, `ops` et `qa`, qui nomment k3d. Proposition de [ARCHI] : valider l'amendement et cet ADR à la même gate, pour que le dépôt ne porte jamais deux règles contraires.
- BENCH-004, BENCH-005 et BENCH-007 se mesurent sur kind, avec la version de Kubernetes fixée ici.
- Entrée de catalogue pour kind, avec le condensat darwin-arm64 relevé par [SECU] (section « Entrée au catalogue »).
- La PR de l'étape 4, qui porte cet ADR, contient aussi BENCH-003, la règle d'empreinte de `docs/benchmarks/TEMPLATE.md` et les textes de R-04, R-20, R-25 et R-26.

### Questions ouvertes

1. Dérive de mineure avec GKE, pour [OPS] dans la conception de la cible `gcp`. GKE met à jour seul les clusters d'un canal, mineure comprise ; dans Regular, 1.37 deviendrait cible de mise à jour automatique vers janvier 2027, date estimée par GKE. Deux voies existent : une exclusion de maintenance « No minor upgrades », que GKE accepte jusqu'à la fin du support de la mineure, ou le suivi par la mise à jour du blueprint (US-011), qui suppose que l'équipe la lance à temps.
2. Configuration de Renovate pour la règle de version (point 5) : une PR par paire kind et image, aucun changement de mineure proposé seul. À vérifier par [OPS] dans la documentation officielle de Renovate.

### Tranché par Lucas le 2026-11-19

1. Règle d'empreinte. Lucas valide la règle proposée par [FINOPS] et recommandée par le DSI : des seuils absolus, tirés du PRD (budget de 900 s d'ENF-01, portable de 8 Gio) ou d'un débit bas pris comme hypothèse (10 Mbit/s), jamais un écart à la meilleure option. Une option part de 5 et perd un cran par seuil dépassé. La règle entre dans la section 5.6 de `docs/benchmarks/TEMPLATE.md`, pour être posée avant les chiffres dès BENCH-005. Contexte : les deux règles en présence avaient été écrites après lecture des chiffres de BENCH-003, et le classement de tête en dépendait, kind 90 contre minikube 87 avec celle-ci, minikube 91 contre kind 90 avec l'ancienne et le tirage de kindnetd compté une seule fois.
2. Outil de la cible PC. Lucas retient kind. Cet ADR en écrit les conditions et la règle de version, que la GATE 1 valide.
3. Clé de minikube en 0777. minikube 1.39.0 recopie à chaque démarrage la clé client du démon Docker du nœud en mode 0777 dans `MINIKUBE_HOME` (BENCH-003, section 5.5). Lucas décide de ne pas le signaler au projet minikube, qui n'est pas retenu. La consigne de R-20, `MINIKUBE_HOME` en 700, ne servirait que si minikube revenait.

## Conformité à la constitution

Vérifiée contre la [constitution](../../.specify/memory/constitution.md) en version 1.0.0.

| Principe | Effet | Justification |
| --- | --- | --- |
| I. Rien sans test automatique | respecté | La matrice teste les adresses d'écoute, la recréation hors ligne et la parité de mineure (conditions 1 et 7, règle de version), en plus du démarrage local |
| II. Spec abstraite, catalogue concret | respecté | kind et sa version n'apparaissent que dans la couche `local` du blueprint et au catalogue ; la spec ne les nomme pas |
| III. Managé sur le cloud, open source ailleurs | respecté | kind est sous Apache-2.0 et gratuit ; le moteur de conteneurs du poste reste hors de cette décision, suivi par R-26 et la condition 8 |
| IV. Catalogue traçable | respecté | L'entrée porte licence, gouvernance, statut, date et source ; les condensats des binaires s'y ajoutent (condition 5) |
| V. Gouvernance ouverte d'abord | respecté | Sous-projet de SIG Testing, donc de Kubernetes, gradué à la CNCF, avec des approbateurs de deux employeurs déclarés |
| VI. Récent mais éprouvé | respecté | Aucun critère éliminatoire touché : Apache-2.0, actif, 0.33.0 du 2026-08-26 ; en usage pour tester Kubernetes lui-même ; la réserve sur la 0.x est écrite |
| VII. Une commande pour démarrer | respecté | `task up` crée le cluster depuis la configuration versionnée ; kind et le moteur de conteneurs sont des prérequis du README |
| VIII. Aucun fait de mémoire | respecté | Les faits renvoient à BENCH-003 et aux pages officielles de kind, de GKE et de Kubernetes lues le 2026-11-19 ; la configuration de Renovate et la prise en charge de Podman sont signalées comme non vérifiées |
| IX. Aucun secret dans le dépôt | respecté | Le kubeconfig reste hors du dépôt (condition 9), et la configuration de kind ne porte aucun secret |
| X. Aucune dépense cloud sans accord | sans objet | Le cluster tourne sur le poste et ne crée aucune ressource cloud |

Écart de texte, sans dérogation : la section « Périmètre du MVP » de la constitution 1.0.0 nomme k3d pour la cible PC. Elle ne pose aucun principe, et son amendement suit la procédure de la section « Gouvernance » (voir « Suites »).

### Dérogations

Aucune.

## Entrée au catalogue

Brique abstraite : `kubernetes-cluster`, nom provisoire. La spec ne déclare pas cette brique, qui découle de la cible ; son nom et la structure de `catalog/` se fixent en phase 3.

| Cible | Service | Type | Licence | Gouvernance | Statut | Vérifié le | Source |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `local` | kind 0.33.0, image de nœud de la règle de version | `oss` | Apache-2.0 | Fondation : sous-projet de SIG Testing, Kubernetes, CNCF (gradué) | actif | 2026-11-19 | <https://github.com/kubernetes-sigs/kind> |
| `gcp` | GKE, mode et canal à fixer par [OPS] | `managed` | service propriétaire du fournisseur | Éditeur unique : Google | actif | 2026-11-19 | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/release-channels> |

Pour `local`, l'entrée porte aussi le condensat SHA-256 du binaire darwin-arm64 de kind 0.33.0, relevé par [SECU] : `0c8c7dbe5e23594a198b786c4bc13dacc101fa6196b0cb0b23a1ca44e61f4b4f`. Ceux des autres systèmes de Q5 restent à relever (condition 5). Pour `gcp`, la ligne attend le mode du cluster (Autopilot ou Standard) et son canal, que fixera la conception de la cible.

## Condition de révision

Bascule par un nouvel ADR qui remplace celui-ci si kind touche un critère éliminatoire : dépôt archivé ou en maintenance, licence qui n'est plus open source, ou aucune release pendant 12 mois. Le décompte part de 0.33.0, publiée le 2026-08-26 : sans release au 2027-08-26, kind tombe.

La décision se rouvre, sans basculer d'office, dans ces cas :

- kind publie sa 1.0 : sa maturité passerait à 5 et son total à 93, mais le format de configuration, `kind.x-k8s.io/v1alpha4` aujourd'hui, peut changer et le blueprint se revérifie. Même chose si la ligne 0.x s'arrête sans 1.0 ;
- k3d publie une nouvelle release ; sans elle, il tombe sous le critère éliminatoire le 2027-06-02 ;
- minikube fige kindnetd par condensat ou l'ajoute à son archive préchargée : sa sécurité ou son empreinte remonterait d'un cran, soit 89 contre 90, et 91 contre 90 avec les deux ;
- le test de recréation hors ligne (condition 7) échoue, ou l'évaluation de Podman par [OPS] (condition 8) échoue pour kind : un critère hors grille qui a fait pencher le choix tombe.

Un changement de mineure de Kubernetes ne rouvre pas cet ADR : la règle de version s'applique. Sans l'un de ces faits, prochaine vérification le 2027-05-19.

## Sources

Ce que BENCH-003 établit se cite par lui ; ses propres sources sont dans sa section 9.

| Source | Lue le | Ce qu'elle établit |
| --- | --- | --- |
| [BENCH-003](../benchmarks/BENCH-003-cluster-local.md), sections 1 à 3 | 2026-11-19 | Ce qui dépend du cluster local ; options et versions examinées ; v1.36.4 alignée pour les trois outils ; critères éliminatoires et dernières releases |
| BENCH-003, section 4.4 | 2026-11-19 | Mesures M1 à M8 : temps, mémoire, volumes de la première création, tirages à chaud, contrôles fonctionnels, adresses d'écoute par défaut |
| BENCH-003, sections 5 à 7 | 2026-11-19 | Notes et totaux ; règle d'empreinte de [FINOPS] ; sensibilité ; critères hors grille ; réserves de kind ; suites, dont le condensat darwin-arm64 du binaire et la relecture d'une redistribution d'images |
| BENCH-003, sections 8 et 10 | 2026-11-19 | Limites, dont le poste unique sous OrbStack ; avis et exigences de [SECU] et de [FINOPS] ; minutes de CI d'un dépôt privé |
| <https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0> | 2026-11-19 | Image par défaut v1.37.0 ; images publiées pour v1.37.0, v1.36.4, v1.35.8 et v1.34.11, chacune avec son condensat ; « You must use the @sha256 digest to guarantee an image built for this release » |
| <https://kind.sigs.k8s.io/docs/user/configuration/> | 2026-11-19 | Champ `image` par nœud, `apiVersion: kind.x-k8s.io/v1alpha4` ; `apiServerAddress` à 127.0.0.1 par défaut ; `listenAddress` de `extraPortMappings` à 0.0.0.0 par défaut ; aucun réglage de CPU ni de mémoire par nœud |
| <https://kind.sigs.k8s.io/docs/user/quick-start/> | 2026-11-19 | Images à prendre dans les notes de la release de kind utilisée, par condensat ; la page ne parle pas de vérifier la somme du binaire |
| <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/release-channels> | 2026-11-19 | Regular marqué « (default) » et « what we recommend for most users » ; Stable conseillé pour la maturité ; mises à jour automatiques, mineure comprise ; exclusion « No minor upgrades » possible jusqu'à la fin du support |
| <https://docs.cloud.google.com/kubernetes-engine/docs/release-notes-regular> | 2026-11-19 | Entrée du 2026-11-10 : 1.36.4-gke.2377000 version par défaut de Regular ; entrée du 2026-11-13 : 1.36.5-gke.1982000 disponible |
| <https://docs.cloud.google.com/kubernetes-engine/docs/release-notes-stable> | 2026-11-19 | Entrée du 2026-11-10 : 1.35.8-gke.1796000 version par défaut de Stable |
| <https://docs.cloud.google.com/kubernetes-engine/docs/release-schedule> | 2026-11-19 | 1.36 dans Regular le 2026-06-09, dans Stable le 2026-10-27, fin du support standard le 2027-08-09 ; 1.37 dans Regular le 2026-10-22, cible de mise à jour automatique vers 2027-01 ; dates données comme « best-effort predictions » |
| <https://docs.cloud.google.com/kubernetes-engine/versioning> | 2026-11-19 | Format X.Y.Z-gke.N, X.Y.Z étant la version amont ; plusieurs versions GKE possibles par correctif amont |
| <https://kubernetes.io/releases/> | 2026-11-19 | 1.36.5 dernier correctif de 1.36, fin de vie le 2027-06-28 ; 1.37.1 dernier correctif de 1.37, fin de vie le 2027-10-28 |
| <https://kubernetes.io/docs/reference/using-api/deprecation-policy/> | 2026-11-19 | Règle 4a : délais de dépréciation et de retrait des API bêta comptés en mois ou en versions mineures (9 mois ou 3 mineures, le plus long des deux) |
| [docs/prd-mvp.md](../prd-mvp.md), section 1, US-005, ENF-01, ENF-02, ENF-03, Q5 | 2026-11-19 | k3d pressenti ; démarrage en une commande et profils ; budget de 15 minutes ; parité et écarts listés au README ; dépendances figées ; systèmes visés |
| [docs/risques.md](../risques.md), R-04, R-16, R-20, R-25, R-26 | 2026-11-19 | Seuil de 500 Mo de R-04 ; allocation GitHub Actions du dépôt de CELIAN ; adresses d'écoute ; registres publics ; moteur de conteneurs payant |
| [Constitution](../../.specify/memory/constitution.md), version 1.0.0 | 2026-11-19 | Périmètre du MVP « PC sous k3d » ; amendement par PR dédiée validée par Lucas |
| [docs/benchmarks/TEMPLATE.md](../benchmarks/TEMPLATE.md), section 5.6 | 2026-11-19 | Règle d'empreinte validée par Lucas le 2026-11-19 |
| Message du DSI à [ARCHI] | 2026-11-19 | Décisions de Lucas du 2026-11-19 : règle d'empreinte, choix de kind, clé 0777 non signalée |
