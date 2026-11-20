# ADR-006. `task up` démarre et recharge la stack locale sans outil de boucle, par `docker build`, `kind load` et `kubectl apply -k`, sous conditions

| Champ | Valeur |
| --- | --- |
| Statut | accepté |
| Date | 2026-11-20 |
| Auteur | [ARCHI] |
| Décideur | DSI, sur délégation de Lucas à la GATE 1 du 2026-11-20 |
| BENCH lié | [BENCH-005](../benchmarks/BENCH-005-orchestration-locale.md) |
| Remplace | aucun |

## Contexte et problème

Sur la cible `local`, `task up` construit l'API et le front du projet généré, démarre toute la stack dans le cluster kind de l'[ADR-004](ADR-004-cluster-local.md), et la recharge quand le développeur modifie le code. Ce qui se cache derrière cette commande doit être choisi avant le golden repo de la phase 2. Le brief retenait Aspire (« polyglotte, déploiement K8s »), et le PRD l'a repris comme option pressentie, à trancher par BENCH-005 entre Aspire, Tilt et Docker Compose.

Les exigences viennent du PRD. US-005 veut que, sur un PC qui a les prérequis du README, `task up` démarre l'API, le front, Postgres et le cache « dans le cluster local » sans autre étape (principe VII), affiche les adresses locales, choisisse un profil lite, standard ou full selon la RAM, et qu'une commande documentée « arrête et supprime l'environnement ». ENF-01 fixe le parcours à moins de 15 minutes, premier téléchargement compris. ENF-02 veut que seule la couche de cible change entre le PC et GCP (principe II). US-001 fait vérifier les prérequis dès le lancement de CELIAN, et US-007 lui fait lancer le démarrage local avant la livraison. Côté constitution, les principes I, II, III, V, VI, VII et VIII. Côté risques, R-04 (critère des 15 minutes hors d'atteinte), R-20 (identifiants par défaut et adresses d'écoute), R-25 (démarrage tributaire des registres publics) et R-30 (boucle locale maison portée par le Taskfile).

Le benchmark a changé de forme en cours de route. Deux décisions du DSI, prises par écrit le 2026-11-19, pèsent sur le résultat, et Lucas les confirme ou non à la GATE 1.

La première série de mesures retenue (2026-11-19, de 20:06 à 20:50 UTC) portait sur les trois options du brief. La première version du rapport plaçait Docker Compose en tête, à 79, devant Tilt (76) et Aspire (74), le volume lu sur l'arm64 du poste. Le rapport relu garde ces totaux en trace, à la fin de sa section 3 ; la relecture de [FINOPS] explique le passage de Tilt de 76 à 74 par la lecture du volume en amd64.

Première décision : US-005 devient un critère éliminatoire, appliqué à toutes les options de la même façon. La raison, écrite dans le rapport : c'est un critère d'acceptation du PRD, écrit et validé avant le benchmark, et il demande que la stack démarre « dans le cluster local ». Docker Compose ne démarre rien dans kind et sort de la grille. La boucle locale d'Aspire (`aspire run`, `aspire start`) sort aussi, parce que l'API y tourne sur l'hôte et le reste dans Docker. Aspire reste candidat par le seul chemin qui place la stack dans kind : `aspire publish` vers Kubernetes, puis le chart installé par Helm. Le rapport garde en annexe A ce que ce critère coûte sur le poste de mesure. À chaud, Compose démarre en 3,9 s et tient en 175,5 Mio au repos, contre 41,5 s et 689,3 Mio pour l'option retenue.

Seconde décision : une quatrième option, O4, entre après la première série. `task up` y enchaîne `docker build`, `kind load docker-image` et `kubectl apply -k`, sans outil de boucle. Le rapport donne deux raisons. Le principe V coûte deux crans de gouvernance à Tilt (porté par Docker, Inc., un auteur à 53 % des commits humains de l'année, toujours en 0.x). Et seule une base sans outil pouvait dire si sa boucle de rechargement vaut ce prix. O4 était déjà le repli que citait la première version.

Une autre décision du DSI du même jour change la lecture des seuils, pas les options : le volume se note sur linux_amd64, pire cas des systèmes de Q5, comme dans BENCH-004. La règle provisoire qui l'accompagne compte la plate-forme de base contre 500 Mo, alors que le seuil de BENCH-005 monte à 1 000 Mo nœud kind compris. Cet écart est un point de la GATE 1 (question 6).

## Options considérées

| Option | Score BENCH (sur 100) | Verdict | Raison principale |
| --- | --- | --- | --- |
| O4, sans outil de boucle (kubectl 1.37.1) | 88 | retenue | N'ajoute aucun outil aux prérequis communs ; kubectl est un composant de Kubernetes, gradué à la CNCF ; mêmes manifests que GKE ; API rechargée en 6,6 s |
| Tilt 0.37.9 | 74 | écartée | Même empreinte et mêmes manifests qu'O4, front resynchronisé en 0,6 s au lieu de 5,1 s, mais éditeur unique (Docker, Inc.), un auteur à 53 % et une version 0.x |
| Aspire 17.0.0 par son chemin Kubernetes (« Aspire sur kind ») | 63 | écartée | Chart généré depuis un AppHost en C#, hors de la spec et du catalogue, sans cible GCP documentée ; tableau de bord tiré par le tag mobile `nightly`, sous avis critique ; rien ne se recharge seul |
| Docker Compose 5.8.0, mesuré en 5.5.0 | éliminée, non notée | éliminée | US-005 : ne démarre rien dans le cluster local (décision du DSI, à confirmer) |
| Boucle locale d'Aspire (`aspire run`, `aspire start`) | éliminée, non notée | éliminée | US-005 : l'API tourne sur l'hôte, le reste dans Docker (décision du DSI, à confirmer) |

Aucune option ne touche les trois critères éliminatoires du brief.

L'écart entre O4 et Tilt, 14 points, tient à la gouvernance (9), la maturité (3), l'activité (2) et la sécurité (2). Tilt n'en reprend que 2, sur l'expérience dev. Il faudrait cinq crans pour inverser le classement. O4 reste premier dans toutes les lectures de sensibilité du rapport (volume en arm64, couche seule, mémoire cumulée avec la plate-forme), avec 12 points d'avance au moins. L'empreinte ne départage rien : les trois options sont à 2/5, et leurs 1 016,7 Mo en amd64 sont communs, Aspire y ajoutant 187,9 Mo.

Grille, mesures et sources : [BENCH-005](../benchmarks/BENCH-005-orchestration-locale.md).

## Décision

Sur la cible `local`, le projet généré n'utilise aucun outil de boucle. `task up` construit les images de l'API et du front par `docker build`, les charge dans le cluster kind par `kind load docker-image`, puis applique par `kubectl apply -k` les manifests de l'application, `k8s/app/`, et ceux de la couche de cible, `k8s/local/`. `task reload` reconstruit l'image touchée, la recharge et réapplique les manifests après une modification. Ni Tilt, ni Aspire, ni Docker Compose n'entrent dans le projet généré.

Les chemins `k8s/app/` et `k8s/local/` sont ceux de la stack d'essai ; l'arborescence du projet généré se fixe en phase 3. Le nom `task reload` est provisoire, puisque le PRD renvoie à la phase 5 les noms des commandes autres que `task up`.

La validation d'ensemble se fait à la GATE 1. Six points y demandent l'avis explicite de Lucas : les questions ouvertes 1 à 6.

### Ce que fait `task up`

Ordre proposé par [ARCHI], d'après la mise en œuvre mesurée (rapport, section 4.2) et les ADR-004 et ADR-005 :

1. vérifier les prérequis et leurs versions : kind (condition 2 de l'ADR-004), kubectl (condition 5) ;
2. créer le cluster kind depuis sa configuration versionnée, ou réutiliser celui qui existe si la condition 4 retient cette piste ;
3. installer la plate-forme de base de l'ADR-005 : CRD Gateway API, Envoy Gateway, GatewayClass ;
4. construire l'API et le front, puis les charger dans le nœud ;
5. créer les Secrets locaux (condition 1) ;
6. appliquer `k8s/app/` et `k8s/local/` par `kubectl apply -k` ;
7. attendre que le contrôle de santé de l'API et la page d'accueil du front répondent par la gateway, puis afficher leurs adresses.

L'ordre exact entre la création du namespace et celle des Secrets, et la commande de chaque étape, se fixent en phase 3 avec [DEV] et [OPS].

### Répartition par couche

| Couche | Contenu |
| --- | --- |
| commune | `k8s/app/` : charges et Services de l'API et du front, HTTPRoute de l'ADR-005. Ce sont les manifests que GKE reçoit. Aucun objet `Secret`, aucun `secretGenerator` |
| `local` | `k8s/local/` : Postgres et Valkey, comme dans l'essai, avec un mot de passe lu dans un Secret que crée `task up`. S'y ajoutent la configuration kind (ADR-004), la plate-forme de la gateway (ADR-005) et les tâches du Taskfile qui démarrent, rechargent et arrêtent la stack |
| `gcp` | Rien de cette décision. GKE reçoit `k8s/app/` et sa propre couche ; Postgres et le cache y sont des services managés (principe III), choisis ailleurs |

### Conditions

Les cinq premières sont les exigences de [SECU] (rapport, section 7). La sixième applique le principe I, et la septième est un ajout de [ARCHI]. La décision ne vaut qu'avec elles. Chaque contrôle cité entre dans la matrice de validation.

1. Secrets hors de `k8s/`. `task up` crée chaque Secret local par `kubectl create -f -`, alimenté par un tube, avant `kubectl apply -k`. Aucun objet `Secret` ni `secretGenerator` ne figure sous `k8s/`. `secretGenerator` lit ses valeurs dans des fichiers ou des littéraux et les applique par `kubectl apply -k`, et un Secret appliqué ainsi recopie sa valeur dans l'annotation `last-applied-configuration` (R-30). Les tâches qui manipulent une valeur n'affichent pas leurs commandes (R-30). Contrôle : un test de la matrice, ou une politique conftest, échoue sur tout objet `Secret` et tout champ `secretGenerator` sous `k8s/` ; l'outil se fixe avec [SECU] et [QA]. Si le cluster est gardé entre deux lancements (condition 4), le Secret existe déjà au lancement suivant : la tâche traite ce cas sans faire passer la valeur par un argument, geste fixé par [DEV] et [SECU].
2. Mot de passe de Valkey. La couche `local` impose un mot de passe à Valkey, comme à Postgres. Il vient d'un Secret créé selon la condition 1 et ne passe jamais en argument de commande. Dans l'essai, Valkey tournait sans mot de passe pour O4 et Tilt : tout pod du cluster pouvait lire et écrire le cache. Le chart d'Aspire, lui, passait le mot de passe en argument de `valkey-server`, et sa lisibilité dans le processus n'a pas été vérifiée. La façon de transmettre le mot de passe à Valkey n'a pas été lue dans sa documentation : [DEV] la vérifie en phase 3. Contrôle : la matrice échoue si Valkey accepte une commande sans authentification, ou si un manifest porte le mot de passe dans `command` ou `args`.
3. Accès en boucle locale. Les adresses que `task up` affiche (US-005) passent par la gateway de l'ADR-005, publiée par des `extraPortMappings` en `listenAddress: "127.0.0.1"` (condition 1 de l'ADR-004). `kubectl port-forward` reste une voie d'appoint, par exemple pour joindre Postgres depuis un outil du poste, et toujours avec `--address 127.0.0.1` : sa valeur par défaut, `localhost`, lie 127.0.0.1 et ::1. Le test des ports en écoute de R-20 et de la condition 1 de l'ADR-004 s'applique après `task up`, et échoue sur toute adresse 0.0.0.0, `[::]` ou `*`. [ARCHI] préfère la gateway pour US-005 : l'API et le front y passent par les mêmes HTTPRoute que sur GKE (ENF-02), et sa mémoire est déjà comptée dans la plate-forme de base, alors que celle des redirections n'a pas été mesurée.
4. R-25 traité avant le golden repo, sur la cause corrigée. Chaque `task up` crée un nœud neuf, dont le containerd ne voit pas le cache Docker du poste. Postgres, Valkey et toute image que la stack ne construit pas repassent donc par le registre à chaque lancement, figées par condensat ou non. Les précharger par `kind load docker-image` ne suffirait pas, pour la cause vérifiée dans BENCH-004. [OPS] évalue les pistes dans cet ordre : garder le cluster entre deux `task up` ; un miroir local en boucle locale, alimenté par condensat ; une archive OCI qui garde l'index du registre, chargée par `kind load image-archive` ; le magasin containerd du moteur. Revenir à des références par tag ou à `imagePullPolicy: Never` reste refusé (R-25). La condition est remplie quand deux tests passent. Le premier : un `task up` sur un cluster existant ne tire aucune image, d'après les événements du nœud relevés comme dans M4. Le second : le test de recréation hors ligne de la condition 7 de l'ADR-004 passe avec la gateway et la stack lite, ce qui remplit aussi la condition 4 de l'ADR-005. Garder le cluster ne remplit que le premier test, puisque la première création et toute recréation tirent encore : les autres pistes restent nécessaires. Cette première piste dépend de la lecture de US-005 (question 4).
5. Prérequis déclarés. kubectl et Task entrent dans la liste des prérequis du README généré, à côté de kind et du moteur de conteneurs, avec leur licence, leur gouvernance, la date de vérification et une source (principe IV). CELIAN lance lui-même `task up` pendant la validation (US-007) : les deux entrent donc aussi dans la liste que CELIAN vérifie au lancement (US-001). kubectl n'est pris en charge qu'à une mineure près de celle du serveur d'API. Le README borne donc sa version d'après la mineure que fixe la règle de l'ADR-004, 1.36 aujourd'hui, soit kubectl 1.35 à 1.37 ; le kubectl 1.37.1 de l'essai, face à un nœud v1.36.4, est dans cette plage. [ARCHI] propose que `task up` vérifie la mineure de kubectl comme il vérifie la version de kind, avec une commande fixée en phase 3 par [OPS]. La licence de Task est MIT ; sa gouvernance n'est pas relevée (question 5), et sa ligne reste incomplète jusque-là.
6. `task up` et `task reload` couverts par la matrice (principe I). La matrice lance `task up` sur un poste sans cluster, puis `task reload` après une modification du front, puis de l'API, et vérifie que le contrôle de santé et la page d'accueil montrent le changement, comme M9. Pour que `task reload` ne s'écarte pas de `task up` (R-30), le Taskfile définit une seule fois la construction, le chargement et l'application, et les deux tâches les réutilisent. La matrice vérifie qu'un `task reload` sans modification laisse dans le cluster les mêmes objets que `task up`, étiquettes d'image mises à part.
7. Images construites par `task up`. L'API et le front ne viennent d'aucun registre. Ils sont construits sur le poste sous une étiquette neuve à chaque construction, posée par kustomize comme dans l'essai, puis chargés par `kind load docker-image`. Les images de base de leurs Dockerfile sont figées par condensat, comme toute image tirée (condition 3 de l'ADR-004) ; [SECU] a jugé ce schéma conforme dans sa relecture. Contrôle : la matrice échoue sur toute image de `k8s/` qui n'est ni désignée par condensat ni construite par `task up`, et sur toute image de base sans condensat.

Les conditions de l'ADR-004 et de l'ADR-005 restent en vigueur, en particulier la boucle locale, les images par condensat, la recréation hors ligne et le kubeconfig hors du dépôt (conditions 1, 3, 7 et 9 de l'ADR-004).

### Réintroduction d'un outil de boucle

Un outil de boucle peut s'ajouter plus tard au-dessus de `k8s/`, sans rien y changer : Tilt applique les mêmes manifests qu'O4 (rapport, section 7). Il reste facultatif, et `task up` comme `task reload` continuent de fonctionner sans lui. Il passe par une relecture [SECU] avant d'entrer dans le blueprint, et si le blueprint livre sa configuration, la matrice la couvre aussi (principe I).

Pour Tilt, la relecture part de ces exigences : version minimale 0.37.4, qui corrige les trois avis du 2026-06-16 dont un critique ; `--host` laissé à sa valeur par défaut, la boucle locale ; `TILT_DISABLE_HUD_AUTH` refusé par un test, puisque cette variable désactive l'authentification du HUD ; somme de contrôle du binaire vérifiée à l'installation, les releases n'étant pas immuables ; écart au principe V justifié dans un ADR (Docker, Inc., un auteur à 53 %, version 0.x).

Rendre un outil de boucle obligatoire, ou le substituer à `task reload`, rouvre cette décision.

### Portée

L'orchestration locale n'est pas une brique que la spec déclare : elle découle de la cible `local`, comme le cluster (ADR-004). La spec ne nomme ni kind, ni kubectl, ni Task (principe II).

Restent hors de cette décision :

- la composition des profils standard et full, que le rapport propose sans l'avoir mesurée (Keycloak et Mailpit pour standard ; observabilité, Argo CD et Kyverno pour full) ;
- la construction du front par Vite et le code de l'API, qui viennent du golden repo ;
- la forme de Postgres et du cache dans la couche `local`, manifest simple comme dans l'essai ou opérateur ;
- l'outil GitOps sur le PC (BENCH-009) ;
- les images construites localement face à Kyverno, qui refuse les images non signées (ENF-03) dans les profils qui l'embarquent : question de [SECU] pour [ARCHI] et [OPS] ;
- le moteur de conteneurs du poste (R-26) et Windows (Q5).

Position de [ARCHI] sur le profil lite : il garde la gateway de l'ADR-005, puisque c'est elle qui donne les adresses de US-005 avec O4. Les seuils du profil lite donnés plus bas supposent cette composition.

## Conséquences

### Positives

- kind reçoit `k8s/app/`, les manifests que GKE recevra, et seule la couche de cible change (portabilité 5/5). kubectl vise tout cluster.
- O4 n'ajoute rien à ce que toutes les options demandaient déjà : kind, Task, le moteur de conteneurs, et kubectl, que `task up` utilise de toute façon pour créer les Secrets. kubectl est un composant de Kubernetes, gradué à la CNCF le 2018-03-06 : gouvernance et maturité à 5/5.
- Avec le rendu versionné des charts que l'ADR-005 propose pour la gateway, `task up` n'appelle que kind, `docker` et kubectl. Helm reste hors des prérequis, alors qu'Aspire sur kind y ajoutait Helm et sa propre CLI.
- `task up` à chaud prend 41,5 s en médiane, sous le seuil de 90 s. Au repos, 689,3 Mio et aucun processus laissé sur l'hôte. L'arrêt prend 0,6 s. Le CPU au repos est plus bas qu'avec Tilt, 19,7 % d'un cœur contre 26,4 %, sans seuil ni cause attribuée.
- L'API se recharge en 6,6 s, plus vite que par la boucle de Tilt (9,2 s).
- Dans l'essai, rien n'est publié sur le poste hors de l'API de kind, en 127.0.0.1. Toutes les images tirées sont figées par condensat, aucune par tag. Le flux officiel de Kubernetes porte 15 CVE en douze mois, une seule sur kubectl (CVE-2026-19444, `kubectl cp` sous Windows, hors Q5), aucune sur kustomize.
- La décision se renverse sans réécrire `k8s/` : un outil de boucle s'ajoute au-dessus des mêmes manifests (section « Réintroduction »).

### Négatives

- Aucun rechargement à chaud ni aucune surveillance des fichiers : le développeur relance `task reload` lui-même, sans interface. Le front se recharge en 5,1 s, contre 0,6 s avec la resynchronisation de Tilt, et plus lentement avec un vrai build Vite, à remesurer sur le golden repo.
- Le Taskfile devient du code de CELIAN, copié dans chaque projet généré, et porte seul construction, chargement, Secrets et application (R-30). Il peut dériver : un Secret appliqué par `kubectl apply` ou `secretGenerator`, un `task reload` qui s'écarte de `task up`, un outil de boucle installé sans relecture. Les conditions 1 et 6 et la section « Réintroduction » y répondent.
- La dépendance à Task se renforce, alors qu'aucun benchmark n'a noté sa gouvernance (question 5).
- Empreinte à 2/5, comme Tilt et Aspire sur kind : 1 016,7 Mo au premier `task up` en amd64, nœud kind compris, au-dessus des seuils de 500 et de 1 000 Mo, et Postgres et Valkey retéléchargés à chaque lancement. Rien de cela ne tient à O4 : volume et tirages sont communs aux trois options.
- R-04. Avec kind et Envoy Gateway, les Secrets natifs, Flux réduit et la stack, le premier `task up` complet télécharge 1 395,9 Mo en amd64 : 1 117 s à 10 Mbit/s utiles (hypothèse), 124 % du budget de 900 s, avant l'entretien, la génération et la CI. Sans GitOps sur le PC, c'est encore 101 %. Il faut 12,4 Mbit/s pour le seul téléchargement (question 3).
- R-25. Tant que chaque `task up` crée un nœud neuf, chaque lancement suivant retire 139 Mo de Docker Hub, 111 s à 10 Mbit/s. Le 2026-11-19, ces tirages sont restés bloqués 15 minutes et une série entière a échoué (condition 4).
- Profils de US-005, méthode de [FINOPS] : avec la plate-forme de base, les Secrets natifs et la stack d'O4, le profil lite demande une VM du moteur d'au moins 2,0 Gio et un portable de 6,0 Gio. La VM monte à 2,5 Gio si ESO ou Flux entrent dans le profil lite et se lisent au nœud, et à 3,0 Gio dans le cumul le plus défavorable ; un portable de 8 Gio tient le profil lite dans toutes ces lectures. Ces chiffres mêlent trois séries et restent un ordre de grandeur ; les facteurs 1,5 et 4 Gio de la méthode sont des hypothèses que [OPS] confirme. Docker Desktop donne par défaut 50 % de la RAM du poste à sa VM, et la documentation de Podman n'écrit aucune valeur par défaut.
- kubectl ne suit qu'à une mineure près le serveur d'API : sa version se relève avec la mineure du cluster, à chaque changement de la règle de l'ADR-004 (condition 5).
- Le temps à froid n'a pas été mesuré, le cache ayant été rempli par un autre programme. Les mesures viennent d'un seul poste, sous macOS avec OrbStack, moteur non libre (R-26), sur une stack d'essai minimale : API sans dépendance ni accès à la base, front statique.

### Effet sur les cibles hors MVP

La porte reste ouverte. O4 ne demande que kubectl et un cluster qui accepte des images chargées depuis le poste ; seule l'étape `kind load` tient à kind. Une cible AWS ou Azure recevrait `k8s/app/` et sa propre couche, sans orchestration locale. Une cible on-prem serveurs aurait sa propre ligne au catalogue, choisie par son benchmark.

### Suites

- [BENCH] : remesurer O4 sur le golden repo (boucle du front avec Vite, temps à froid, Linux avec Docker Engine).
- [BENCH] : relever une fois la gouvernance de Task, pour le catalogue (question 5).
- [OPS] : pistes de R-25 avant le golden repo (condition 4) ; mémoire par défaut de la VM de Podman ; facteurs 1,5 et 4 Gio de la méthode des profils ; commande qui lit la mineure de kubectl (condition 5).
- [DEV] : un Taskfile où `task reload` réutilise les étapes de `task up` (condition 6) ; création des Secrets sur un cluster gardé (condition 1) ; transmission du mot de passe de Valkey (condition 2).
- [SECU] et [QA] : outil du contrôle de la condition 1, test des ports de la condition 3.
- [OPS] et [SECU] : images construites localement face à Kyverno, dans les profils qui l'embarquent (ENF-03).
- [PO] : lecture de « arrête et supprime l'environnement » (question 4).
- Registre : R-30 reste ouvert tant que les conditions 1 et 6 ne sont pas en place.

### Questions ouvertes

1. Les deux décisions du DSI du 2026-11-19, pour Lucas. L'élimination par US-005 écarte Docker Compose, en tête de la première version, et la boucle locale d'Aspire. L'ajout d'O4 après la première série fait entrer l'option retenue. Avis de [ARCHI] : favorable aux deux. US-005 était écrit et validé avant le benchmark, et seul un démarrage dans le cluster donne la parité d'ENF-02, avec les manifests que GKE recevra ; ce critère coûte 41,5 s à chaud contre 3,9 s pour Compose. O4 répond à une question que la grille posait sans pouvoir y répondre : ce que vaut la boucle de Tilt face à une base sans outil. Si Lucas refuse l'élimination, Compose revient dans la grille et cet ADR se rouvre.
2. Le sort d'Aspire, pressenti par le brief et le PRD, pour Lucas. Il finit dernier, à 63. Avis de [ARCHI] : l'écarter pour le MVP. Son chart vient d'un AppHost en C# et non de la spec ni du catalogue (principe II), et `aspire publish` ne documente aucune cible GCP. Le chart tire son tableau de bord par le tag mobile `nightly/dashboard:17.0`, alors que l'avis critique CVE-2026-118740 (CVSS 9,1, publié le 2026-11-11) demande de remplacer ces références `nightly` dans les manifests générés. Enfin la 17.0.0 avait un jour à la lecture : le principe VI ferait générer avec 13.6.5, dont le chart n'a pas été produit.
3. Débit visé ou réduction du volume (R-04), pour Lucas. Le constat des 124 % vaut pour les trois options. Leviers chiffrés par [FINOPS] : sortir Flux du profil lite (258,1 Mo de moins), et compiler l'API avec le SDK .NET du poste pour ne construire que l'image d'exécution (362,8 Mo de moins, le SDK passant dans les prérequis, hors du budget). Les deux ensemble ramènent le volume à 775,0 Mo, 68,9 % du budget à 10 Mbit/s. Avis de [ARCHI] : réduire le volume d'abord, puis écrire le débit visé dans le critère d'acceptation. Sortir Flux du profil lite va dans le sens d'O4, qui applique déjà les manifests par `kubectl apply -k`, mais la décision revient à l'ADR de BENCH-009. La compilation sur le poste pose une question de reproductibilité que [DEV] et [SECU] tranchent.
4. Lecture de US-005, pour [PO] puis Lucas. « Une commande documentée arrête et supprime l'environnement » peut se lire comme la suppression de l'application, le cluster restant. Cette lecture rend possible la première piste de R-25 (condition 4) et épargne 139 Mo, soit 111 s à 10 Mbit/s, à chaque `task up` suivant. Avis de [ARCHI] : deux commandes documentées, l'une qui supprime l'application et garde le cluster, l'autre qui supprime le cluster ; leurs noms se fixent en phase 5.
5. Gouvernance de Task, pour Lucas. Le brief retient Task, commun aux trois options, et aucun benchmark n'a noté sa gouvernance ; avec O4, il porte toute la boucle. Sa licence est MIT et son dépôt appartient à l'organisation `go-task`, lus le 2026-11-20 ; ses mainteneurs et leurs employeurs n'ont pas été relevés. Si sa gouvernance demandait une justification au titre du principe V, elle tiendrait en deux faits : Task vient du brief et sert toutes les options, et les étapes d'O4 restent trois commandes standard qu'un script reprendrait. Faut-il le faire relever par [BENCH] avant la GATE 1, ou en phase 3 avec le catalogue ?
6. Seuils de volume, pour Lucas. BENCH-005 compte le nœud kind dans ses seuils de 500 et 1 000 Mo, et la règle provisoire du DSI compte la plate-forme de base, nœud compris, contre 500 Mo : le nœud (384,8 Mo en amd64) est compté deux fois. Sur les notes, l'effet est d'un cran au plus, pour les trois options ensemble, jamais sur l'ordre. Sur le budget, [FINOPS] relève que les seuils de couche posés jusqu'ici somment à 1 327,7 Mo, 118 % des 900 s à 10 Mbit/s : une couche qui tient ses propres seuils peut rendre ENF-01 intenable. Choix attendu : couche seule ou plate-forme comprise, et des parts par étape dont la somme laisse de la place au reste du parcours. C'est la question 2 de l'ADR-005, vue depuis la stack.

### Réponses de la GATE 1 (2026-11-20)

- Les deux décisions du DSI, l'élimination par US-005 et l'ajout de l'option
  sans outil de boucle, sont confirmées par Lucas.
- Aspire, pressenti par le brief, n'est pas retenu : l'ADR est accepté.
- R-04 : un débit visé entre dans le critère d'acceptation, valeur proposée
  par [FINOPS] après le golden repo, et le profil lite n'embarque pas l'outil
  GitOps (PR #26).
- Seuils de volume : la règle de périmètre de la plate-forme de base entre
  dans le gabarit de benchmark (PR #25).
- Restent ouvertes : la lecture de « arrête et supprime l'environnement »
  (US-005), qui attend BENCH-010, et la gouvernance de Task.

## Conformité à la constitution

Vérifiée contre la [constitution](../../.specify/memory/constitution.md) en version 1.0.0.

| Principe | Effet | Justification |
| --- | --- | --- |
| I. Rien sans test automatique | respecté | La matrice couvre `task up` et `task reload` (condition 6), l'absence de Secret sous `k8s/`, les ports en écoute, les images et R-25 (conditions 1, 3, 4 et 7) |
| II. Spec abstraite, catalogue concret | respecté | La spec ne nomme aucun outil ; `kind load` et les tâches du Taskfile vivent dans la couche `local`, et `k8s/app/` est le même sur kind et sur GKE |
| III. Managé sur le cloud, open source ailleurs | respecté | Sur le PC, kubectl (Apache-2.0), Task (MIT) et kind (Apache-2.0) sont gratuits ; le moteur de conteneurs reste hors de cette décision (R-26) |
| IV. Catalogue traçable | respecté | Aucune entrée nouvelle ; les prérequis portent licence, gouvernance, date et source au README (condition 5), et la ligne de Task reste incomplète jusqu'au relevé de sa gouvernance (question 5) |
| V. Gouvernance ouverte d'abord | respecté | O4 n'ajoute que des commandes de kubectl, composant de Kubernetes, gradué à la CNCF ; les deux options à éditeur unique sont écartées ; Task, retenu par le brief et commun aux options, attend son relevé (question 5) |
| VI. Récent mais éprouvé | respecté | Aucun critère éliminatoire touché : Apache-2.0, dépôt actif, Kubernetes 1.37.2 du 2026-10-28 et 42 releases stables en douze mois |
| VII. Une commande pour démarrer | respecté | `task up` démarre toute la stack seul, les prérequis étant listés au README (condition 5) |
| VIII. Aucun fait de mémoire | respecté | Les faits renvoient au rapport, à ses relectures et aux pages lues le 2026-11-20 ; sont signalés comme non vérifiés la transmission du mot de passe à Valkey, la gouvernance de Task, le temps à froid, la mémoire des redirections et la mémoire par défaut de la VM de Podman |
| IX. Aucun secret dans le dépôt | respecté | Les Secrets locaux naissent à l'exécution par un tube et aucun n'est versionné sous `k8s/` (condition 1) ; le kubeconfig reste hors du dépôt (condition 9 de l'ADR-004) |
| X. Aucune dépense cloud sans accord | sans objet | Tout tourne sur le poste, et `task up` ne crée aucune ressource cloud |

### Dérogations

Aucune.

## Entrée au catalogue

Aucune brique nouvelle. L'orchestration locale découle de la cible `local`, et ses outils, kubectl et Task, sont des prérequis du poste, comme kind et le moteur de conteneurs.

Faut-il les inscrire au catalogue ? Le principe IV vise les entrées du catalogue, et la condition 5 demande déjà au README licence, gouvernance, date et source. Avis de [ARCHI] : les y inscrire, comme outils du poste pour la cible `local`, avec les champs des autres entrées et les condensats de leurs binaires dans le champ `artifacts` que propose l'ADR-009. Deux raisons. La CI du générateur refuserait alors une ligne incomplète (US-004), comme pour toute brique. Et le README du projet généré comme la liste de US-001 se produiraient depuis une seule source, au lieu d'être recopiés. La décision revient à la phase 3, avec le schéma du catalogue.

| Outil | Licence | Gouvernance | Vérifié le | Source |
| --- | --- | --- | --- | --- |
| kubectl | Apache-2.0 | Fondation : composant de Kubernetes, gradué à la CNCF | 2026-11-19 | <https://github.com/kubernetes/kubectl> |
| Task | MIT | à relever (question 5) | 2026-11-20 | <https://github.com/go-task/task> |

## Condition de révision

Bascule par un nouvel ADR qui remplace celui-ci si kubectl touche un critère éliminatoire : dépôt archivé ou en maintenance, licence qui n'est plus open source, ou aucune release de Kubernetes pendant 12 mois. Le décompte part de 1.37.2, publiée le 2026-10-28.

La décision se rouvre, sans basculer d'office, dans ces cas :

- Lucas ne confirme pas l'élimination par US-005 : Docker Compose et la boucle locale d'Aspire reviennent dans la grille (question 1) ;
- Lucas retient Aspire, ou un outil de boucle obligatoire : un nouvel ADR justifie l'écart au principe V ;
- aucune piste de R-25 ne remplit la condition 4 ; l'ADR-004 et l'ADR-005 se rouvrent alors aussi ;
- l'ADR-005 n'est pas validé : l'accès de US-005 passe par des redirections dont la mémoire reste à mesurer ;
- la gouvernance de Task, une fois relevée, demande une justification au titre du principe V que Lucas ne retient pas ;
- l'ADR-004 se rouvre et kind change : l'étape `kind load` se remplace et `task up` se revérifie ;
- une cible hors MVP est ouverte.

Ne rouvrent pas cet ADR : l'ajout facultatif d'un outil de boucle selon la section « Réintroduction », une boucle du front plus lente avec Vite, qui se remesure et se signale, et la lecture des seuils de volume (question 6), qui déplace les trois options ensemble d'un cran au plus. Sans l'un de ces faits, prochaine vérification le 2027-05-19, date proposée par BENCH-005.

## Sources

Ce que BENCH-005 établit se cite par lui ; ses propres sources sont dans sa section 9.

| Source | Lue le | Ce qu'elle établit |
| --- | --- | --- |
| [BENCH-005](../benchmarks/BENCH-005-orchestration-locale.md), sections 1 à 3 | 2026-11-20 | Question posée ; options et versions ; ajout d'O4, sa date et ses raisons ; élimination de Compose et de la boucle locale d'Aspire par US-005, sa date, sa raison, confirmée par Lucas à la GATE 1 ; critères éliminatoires |
| BENCH-005, section 4 | 2026-11-20 | Seuils écrits avant les mesures, révision amd64 et règle provisoire de la plate-forme de base ; mise en œuvre d'O4 ; série retenue du 2026-11-19 ; M1 à M11 ; volumes ; tirages à chaque `task up` et leur cause corrigée ; série bloquée 15 minutes ; adresses d'écoute |
| BENCH-005, sections 5 à 7 | 2026-11-20 | Notes, grille et totaux 88, 74 et 63 ; sensibilité ; affichage des adresses par la gateway ou `kubectl port-forward` ; seuils du profil lite ; exigences de [SECU] ; condition de réintroduction de Tilt ; suites ; prochaine vérification au 2027-05-19 |
| BENCH-005, section 8, section 10 et annexe A | 2026-11-20 | Limites, dont le temps à froid et le poste unique ; relectures de [SECU] et de [FINOPS] ; mesures de Docker Compose et de la boucle locale d'Aspire |
| Relectures [SECU] et [FINOPS] de BENCH-005, texte complet transmis au DSI, résumé en section 10 du rapport | 2026-11-20 | Tilt à 76 dans la première version, puis 74 par la lecture en amd64 ; mot de passe de Valkey en argument dans le chart d'Aspire ; images construites sous étiquette locale jugées conformes ; seuils de couche à 1 327,7 Mo, 118 % du budget ; leviers de volume et variante à 775,0 Mo ; mémoire par défaut des moteurs |
| <https://kubernetes.io/releases/version-skew-policy/> | 2026-11-20 | kubectl pris en charge à une mineure près, plus ancienne ou plus récente, de `kube-apiserver` ; page modifiée le 2026-04-14 |
| <https://kubernetes.io/docs/reference/kubectl/generated/kubectl_port-forward/> | 2026-11-20 | `--address` à `localhost` par défaut, qui lie 127.0.0.1 et ::1 ; n'accepte que des adresses IP ou `localhost` |
| <https://github.com/go-task/task> | 2026-11-20 | Licence MIT, dépôt de l'organisation `go-task`, public, sans mention d'archivage |
| [ADR-004](ADR-004-cluster-local.md), conditions 1, 2, 3, 7 et 9, règle de version | 2026-11-20 | Boucle locale et test des ports ; version exacte de kind ; images par condensat ; recréation hors ligne ; kubeconfig hors du dépôt ; mineure 1.36 |
| [ADR-005](ADR-005-gateway.md), décision, condition 4, suites, question 2 | 2026-11-20 | Gateway publiée en 127.0.0.1 ; plate-forme de base ; R-25 avant le golden repo ; rendu versionné des charts plutôt que Helm en prérequis ; périmètre de la plate-forme de base |
| [ADR-009](ADR-009-catalogue.md), proposé | 2026-11-20 | Champ `artifacts` : condensats de binaires facultatifs |
| [docs/prd-mvp.md](../prd-mvp.md), section 1, section 3, US-001, US-004, US-005, US-007, ENF-01, ENF-02, ENF-03, Q5 | 2026-11-20 | Aspire pressenti ; noms des commandes autres que `task up` en phase 5 ; prérequis ; entrée de catalogue incomplète refusée par la CI ; démarrage dans le cluster local, adresses, profils, arrêt ; démarrage local avant livraison ; budget de 15 minutes ; parité ; Kyverno et images non signées ; systèmes visés |
| [docs/brief-v1.0.md](../brief-v1.0.md), lignes 245, 262 et 348 | 2026-11-20 | Aspire retenu pour l'orchestration locale ; Taskfile et `task up` ; options de BENCH-005 |
| [docs/risques.md](../risques.md), R-04, R-20, R-25, R-26, R-30 | 2026-11-20 | Premier `task up` complet à 124 % du budget ; mot de passe de Valkey et aucun Secret sous `k8s/` ; nœud neuf à chaque `task up`, pistes et reculs refusés ; moteur payant ; boucle maison et ses mitigations |
| [Constitution](../../.specify/memory/constitution.md), version 1.0.0 | 2026-11-20 | Principes I à X ; dérogation justifiée dans un ADR |
