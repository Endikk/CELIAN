# ADR-010. Le projet généré se synchronise par Config Sync sur GKE et par Flux sur le PC, sous conditions

| Champ | Valeur |
| --- | --- |
| Statut | proposé |
| Date | 2026-11-20 |
| Auteur | [ARCHI] |
| Décideur | Lucas, en attente de la GATE 1 |
| BENCH lié | [BENCH-009](../benchmarks/BENCH-009-gitops.md) |
| Remplace | aucun |

## Contexte et problème

Le projet généré se déploie par GitOps : un outil lit son dépôt et synchronise le cluster. Sur la cible `local`, ce cluster est le cluster kind de l'[ADR-004](ADR-004-cluster-local.md) ; sur `gcp`, le cluster GKE Autopilot de l'[ADR-008](ADR-008-modules-opentofu-gcp.md) (proposé). L'outil de chaque cible doit être choisi avant le golden repo de la phase 2. Le brief prévoit Argo CD, avec des ApplicationSets par environnement (section 6), et la réponse à Q6 du PRD parle d'une « structure Argo CD prête pour staging et prod » (section 8). Cet ADR répond aussi à la question 3 de l'[ADR-009](ADR-009-catalogue.md) (proposé) : Config Sync, que Google décrit comme « a GitOps service included with Google Kubernetes Engine (GKE) », couvre-t-il le besoin du blueprint sur `gcp` ?

Les exigences viennent du PRD. ENF-02 veut que chaque brique existe sur les deux cibles, libre sur le PC et managée sur GCP, que seule la couche de cible change (principe II), et que le README généré liste les écarts restants. US-005 veut que `task up` démarre la stack sans autre étape (principe VII). US-006 veut que l'agent ne lance jamais une commande qui crée des ressources payantes. Q6 ne déploie qu'un environnement sur GCP, avec une structure prête pour staging et prod. ENF-01 fixe le parcours à 15 minutes, et ENF-03 demande des dépendances figées. Côté constitution : les principes I, II, III, V, VI, VIII, IX et X. Côté risques : R-04 (critère des 15 minutes hors d'atteinte), R-05 (dépense GCP non maîtrisée), R-07 (agents capables de lire et d'exfiltrer des secrets), R-19 (identité GCP de la CI et état OpenTofu), R-25 (démarrage local tributaire des registres publics), R-26 (moteur de conteneurs du poste sous licence payante), R-28 (secrets locaux en clair dans etcd), et les trois risques ouverts à la suite de BENCH-009 : R-31 (moteur GitOps différent entre le PC et GCP), R-32 (failles des moteurs GitOps invisibles aux scanners) et R-33 (écrire sur la branche suivie, c'est administrer le cluster).

Sur `gcp`, le choix suit la lecture des principes III et V que propose l'ADR-009 : le principe III fixe les candidats d'une cible, le principe V les départage, et un composant libre sur `gcp` demande un `managed_gap` qui dit ce que le service managé ne couvre pas. Lucas n'a pas encore validé cette lecture (question 6). BENCH-009 juge le service managé sur la documentation de Google, sans aucune ressource créée (principe X). Il a mesuré la forme libre de Config Sync sur kind sous l'émulation x86 d'OrbStack, et ces mesures ne fondent aucun cran (BENCH-009, sections 3 et 4.4).

## Options considérées

| Option | Score BENCH (sur 100) | Verdict | Raison principale |
| --- | --- | --- | --- |
| Flux 2.10.0 | 88 | retenue pour `local` | Couche à 265,2 Mio au nœud, sous le seuil de 512 Mio ; Apache-2.0 pour chaque contrôleur ; demandes de ressources déjà posées par le manifest ; aucune API réseau qui détienne des droits sur tout le cluster |
| Argo CD 3.6.2 | 86 | écartée | Couche à 611,2 Mio au nœud, au-dessus du seuil ; interface web et API, Dex et Redis 8 dans l'installation de référence ; 11 avis de sécurité en douze mois, dont 5 critiques |
| Config Sync 1.25.2 | 62 | retenue pour `gcp`, au titre du principe III ; écartée pour `local` | Service managé inclus dans GKE, qui couvre le besoin de Q6. Dernier de la grille, éditeur unique, images publiées pour `linux/amd64` seulement |

Aucune option ne touche de critère éliminatoire (BENCH-009, section 3). Le principe III n'est pas un critère de la grille : il se traite hors grille, comme dans BENCH-009 (section 7). Argo CD 3.6.2 avait un jour au moment de la mesure, et le blueprint n'aurait pu la retenir qu'à partir du 2026-11-25 (principe VI).

### Ce que la grille tranche, et ce qu'elle laisse ouvert

Avant la règle de mémoire au nœud, Flux et Argo CD sont à égalité, 88 chacun. Un seul cran les sépare ensuite, celui de la mémoire en empreinte sur PC. Lue au nœud kind, moins le nœud de base sans outil, la couche d'Argo CD pèse 611,2 Mio et dépasse le seuil de 512 Mio de 19 % ; celle de Flux pèse 265,2 Mio, à 52 % du seuil. Argo CD perd un cran d'empreinte, soit 2 points, et finit à 86.

Deux règles fondent ce résultat, et le rapport dit d'où elles viennent (BENCH-009, sections 4.1 et 8). La règle de mémoire lit la mémoire d'une option au nœud (`docker stats` du conteneur du nœud, médiane de trois échantillons), moins celle du nœud de base, même configuration sans outil GitOps, médiane 648,3 Mio. La règle d'égalité garde, si Flux et Argo CD restent à égalité, l'option déjà nommée par le PRD, Argo CD. Le DSI les a posées le 2026-11-19 après l'indice de [FINOPS], environ 250 Mio au nœud qu'aucun pod d'Argo CD n'explique, stables sur trois exécutions. Le rapport les a écrites à 23:01 UTC, avant la série de référence lancée à 23:21:37 UTC. Toutes deux restent provisoires jusqu'à la GATE 1 (question 7).

La lecture au nœud vient de la cohérence avec deux benchmarks précédents, où le serveur d'API porte une part de la mémoire que la somme des pods ne voit pas. Dans BENCH-004, les CRD d'Envoy Gateway font passer le serveur d'API de 231,5 à 469,6 Mio en médiane (ADR-005). Dans BENCH-007, la mesure de `kube-system` montre qu'ESO ajoute environ 100 Mio au serveur d'API avec ses 25 CRD (ADR-007). La règle d'égalité tient à une idée simple : une égalité ne donne aucune raison de changer une décision écrite.

Le dépassement d'Argo CD ne dépend pas de la médiane retenue. Ses trois exécutions donnent 611,2, 679,8 et 562,1 Mio contre la base médiane, et la base la plus haute, 656,5 Mio, laisse encore 603,0 Mio. Flux reste sous le seuil avec la base la plus basse (309,2 Mio). En revanche, 343,8 Mio de la couche d'Argo CD ne s'expliquent par aucun pod, et cet ADR ne les attribue pas. L'hypothèse d'un serveur d'API chargé par ses CRD va dans le sens de BENCH-004 et de BENCH-007, mais `docker stats` ne distingue pas le serveur d'API, etcd et le cache, et le nœud de base a été mesuré dans une autre session que la série principale, vers 23 h UTC contre 21 h (BENCH-009, section 8).

### Sensibilité

La sensibilité de BENCH-009 (section 7), reprise pour les lectures qui rendent la main à Argo CD et pour celles qui gardent Flux en tête. Config Sync reste dernier dans toutes, à 24 points au moins. La dernière colonne est un ajout de [ARCHI] : elle dit si la lecture contredit une règle déjà posée.

| Lecture | Argo CD | Flux | En tête | Règle déjà posée |
| --- | --- | --- | --- | --- |
| Grille | 86 | 88 | Flux | Sans objet |
| Mémoire lue par la somme des pods de l'outil (267,4 Mio pour Argo CD) | 88 | 88 | Égalité, donc Argo CD | Contredit la règle de mémoire au nœud, provisoire jusqu'à la GATE 1 (question 7) |
| Veille des avis de Flux dépôt par dépôt tenue pour une action : sécurité de Flux à 3 | 86 | 86 | Égalité, donc Argo CD | Aucune contredite. [SECU] ne la retient pas : trois avis sans critique, tous corrigés avant publication, restent une réserve mineure (BENCH-009, section 5.5) |
| Images de Flux tirées par tag pour retrouver le cache de `kind load` : sécurité de Flux à 3 | 86 | 86 | Égalité, donc Argo CD | Contredit la condition 3 de l'ADR-004 et R-25 : refusé |
| Sécurité d'Argo CD à 4 | 88 | 88 | Égalité, donc Argo CD | Aucune contredite, mais contraire à l'avis de [SECU] : 11 avis dont 5 critiques, et une API réseau qui détient `get`, `patch` et `delete` sur toutes les ressources |
| Licence d'Argo CD à 5, Redis 8 remplacé | 89 | 88 | Argo CD | Aucune contredite ; configuration jamais mesurée |
| Cumul avec la plate-forme contre ses seuils seuls (lecture c de [FINOPS]) | 86 | 86 | Égalité, donc Argo CD | Contredit la règle provisoire du DSI, qui réserve le cumul à la sensibilité (ADR-005, question 2) |
| Expérience dev de Flux à 5 | 86 | 90 | Flux | Aucune contredite |
| Montage C : outil sur le PC seulement, coût à 5/5 pour les deux | 87 | 89 | Flux | Aucune contredite |
| Base de mémoire la plus haute (656,5 Mio) ou la plus basse (604,3 Mio) | 86 | 88 | Flux | Aucune contredite |

Lecture de [ARCHI]. L'avance de Flux tient dans un cran, et le choix sur le PC dépend de deux décisions de Lucas à la GATE 1 : la règle de mémoire au nœud (question 7) et le périmètre des seuils de couche (ADR-005, question 2). S'il revient à la somme des pods, ou s'il compte le cumul avec la plate-forme, l'égalité revient et la règle d'égalité donne Argo CD. Les autres lectures qui rendent la main à Argo CD contredisent une règle posée ou l'avis de [SECU], ou supposent une configuration que personne n'a mesurée. Si Lucas rejetait aussi la règle d'égalité, une égalité se départagerait hors grille. [SECU] y préfère Flux sur le PC : aucune API réseau qui détienne des droits sur tout le cluster, aucun compte, pas de Redis, trois avis sans critique. Argo CD garde deux avantages réels, son interface web et la gouvernance la plus large (5/5 contre 4/5).

Grille, mesures et sources : [BENCH-009](../benchmarks/BENCH-009-gitops.md).

## Décision

Le projet généré synchronise son dépôt vers son cluster par l'outil GitOps de sa cible. Sur `gcp`, c'est Config Sync, service managé de GKE, avec un `RootSync` par environnement déployé. Sur `local`, c'est Flux 2.10.0, installé par `task up` depuis un manifest versionné. Les manifests de l'application et la structure du dépôt, une base Kustomize et un overlay par environnement, sont communs aux deux cibles. Seuls les objets de liaison, qui disent à l'outil quoi synchroniser et où, vivent dans la couche de chaque cible.

C'est le montage C de BENCH-009 (section 7.1). La validation d'ensemble se fait à la GATE 1, et quatre points y demandent l'avis explicite de Lucas : les questions 1, 3, 6 et 7.

### Pourquoi le montage C

Trois montages sortent de la question de parité (BENCH-009, section 7.1) : A, le même outil libre sur les deux cibles ; B, Config Sync partout ; C, le service managé sur GCP et un outil libre sur le PC.

Le montage B est écarté. Config Sync finit dernier de la grille, à 62. Google écrit qu'il « can run only on x86-based nodes, not Arm nodes », et ses images ne sont publiées que pour `linux/amd64`. Sur un PC à processeur Apple, il ne tourne que par l'émulation du moteur de conteneurs, non libre (R-26), hors de ce que Google prend en charge, et [SECU] refuse d'y faire tourner un contrôleur lié à `cluster-admin`.

Entre A et C, le montage C tient par le principe III, dans la lecture de l'ADR-009 qui attend Lucas. Config Sync couvre le besoin de Q6 sur GKE : il lit Git, rend Kustomize, et Google documente un `RootSync` par environnement (BENCH-009, sections 7.1 et 7.2). Sa licence est incluse dans l'offre GKE, flotte comprise. Le montage A demanderait sur `gcp` un `managed_gap`, et la seule lacune de Config Sync que BENCH-009 a trouvée est de ne pas tourner sur un PC arm64. Cette lacune touche la cible `local` ; sur `gcp`, elle ne dit rien de ce que le service managé ne couvre pas. Le `managed_gap` reposerait sur la seule parité d'outil, que la lecture de l'ADR-009 ne compte pas comme un manque du service managé. C'est le raisonnement déjà tenu pour les secrets dans l'ADR-007.

Le montage C n'a aucun avantage de coût établi sur le montage A, et cet ADR ne lui en prête pas. Les pods de Config Sync tournent dans le cluster du client. En Autopilot, Google fixe à chaque réconciliateur des demandes d'environ 0,93 vCPU et 0,93 Gio par `RootSync`, aucune page lisible ne les exempte de facturation, et ses métriques partent vers Cloud Monitoring, facturé à l'échantillon (R-31). Sur un cluster à rafale, un `RootSync` et les composants communs demandent environ 1,29 vCPU et 1,76 Gio, contre 0,35 vCPU et environ 371 Mio pour Flux réduit à ses quatre contrôleurs par défaut : 3,7 fois le calcul et 4,9 fois la mémoire, et l'écart grandit à chaque environnement ajouté (relecture de [FINOPS]). Si ces pods sont facturés, Flux sur les deux cibles coûterait moins cher, et le montage C ne tient plus que par le principe III.

L'avantage d'exploitation se réduit lui aussi. Config Sync se monte de version à la main, même sur GKE, au moins tous les neuf mois selon Google (R-32). Ce que le service managé épargne à l'équipe, c'est l'installation et les composants hébergés, tenus par le service Fleet.

Repli connu : Flux sur `gcp`, le montage A, qui ne change que les objets de liaison de la couche `gcp`. Il devient la décision si Lucas fait primer le principe V sur le III (question 6), ou si l'essai sur GKE de la condition 7 échoue sur un point que la couche `gcp` ne corrige pas.

### Pourquoi Flux sur le PC

Par la grille seule : 88 contre 86, et 89 contre 87 si l'outil ne tourne que sur le PC. Les deux points viennent du cran de mémoire décrit plus haut, et d'aucun départage hors grille. À la demande de [FINOPS] et de [SECU], trois arguments ont été retirés du verdict de BENCH-009 : la mémoire et le temps d'installation sous leurs seuils, déjà notés en empreinte ; la recréation hors ligne, fausse tant que R-25 n'est pas résolu ; le nombre d'avis, déjà compté en sécurité. Restent comme faits : Flux pose déjà ses demandes de ressources, n'expose aucune API qui détienne des droits sur tout le cluster, et n'embarque pas Redis 8. Si la règle de mémoire tombe à la GATE 1, Argo CD revient par la règle d'égalité, et cet ADR se rouvre (section « Condition de révision »).

### Répartition par couche

| Couche | Contenu |
| --- | --- |
| commune | Les manifests de l'application en base Kustomize, et un overlay par environnement (`local`, `staging`, `prod`), comme le dépôt de test de BENCH-009. Aucun objet de liaison, aucun groupe, aucune annotation ni étiquette propre à un moteur, aucune chaîne `${` (condition 1). Les overlays restent neutres eux aussi ; l'arborescence exacte, la place des overlays et leur lien avec `k8s/app/` de l'[ADR-006](ADR-006-orchestration-locale.md) (proposé) se fixent en phase 3 |
| `local` | Le manifest `install.yaml` de la release 2.10.0 de Flux, versionné avec son SHA-256 et vérifié avant application (condition 4 de l'ADR-004), ses images figées par condensat (condition 6) et les options de verrouillage de la condition 3. Les objets de liaison : un `GitRepository` et une `Kustomization` pour l'environnement `local`, dans `flux-system`. Ce que lit le `GitRepository` attend la question 1, et la présence de Flux dans le profil lite la question 3 |
| `gcp` | Dans la couche OpenTofu de l'ADR-008 : l'inscription du cluster dans une flotte, que Config Sync exige, et son activation, dans une version figée (R-32). Les ressources OpenTofu qui les portent n'ont pas été vérifiées ([OPS]). Dans les manifests de la couche : un `RootSync` par environnement déployé, un seul au MVP (Q6), en `sourceFormat: unstructured`, avec `spec.override.roleRefs` (condition 3) et l'authentification de la condition 4. Sans `sourceFormat`, le format `hierarchy` s'applique et refuse le rendu Kustomize. Le premier `RootSync` et le Secret Git s'appliquent hors de Config Sync ; qui les applique, OpenTofu ou une commande de l'utilisateur, se fixe en phase 3 ([OPS]), sous la condition 4 et le principe X |

### Versions

Flux 2.10.0 est publiée depuis le 2026-10-26, Config Sync 1.25.2 depuis le 2026-11-03 sur GitHub et le 2026-11-09 dans les notes de Google : toutes deux passent le délai de 7 jours du principe VI. Le SHA-256 du manifest de Flux, abrégé en `a8c838cc…7f28` dans le rapport, figure en entier dans le script de BENCH-009 (`tests/bench/bench-009-gitops.sh`), comme les condensats des images. Sur GKE, Config Sync ne se met plus à jour seul depuis 1.21.0 (2025-05-01) : la version déployée se fige dans la couche `gcp` et monte par une PR qui passe la matrice, et la forme libre testée sur kind suit la même version (condition 5, R-32). Le mécanisme qui fige cette version n'a pas été lu ([OPS]). Les montées de Flux suivent la règle de Renovate et le délai de 7 jours, comme les autres briques.

### Conditions

Les six premières reprennent les conditions proposées par BENCH-009 (section 7.5), issues de [SECU]. La septième est un ajout de [ARCHI], tiré de R-31 ; la huitième vient de la relecture de [SECU]. Les précisions de [ARCHI] sont signalées. La décision ne vaut qu'avec elles. Chaque contrôle cité entre dans la matrice de validation (principe I).

1. Couche commune neutre vis-à-vis du moteur (R-31). Une politique conftest sur les fichiers du dépôt généré refuse, hors des objets de liaison de la couche de cible : les groupes `configsync.gke.io`, `*.toolkit.fluxcd.io` et `argoproj.io` ; toute annotation ou étiquette préfixée `configmanagement.gke.io/`, `configsync.gke.io/`, `kustomize.toolkit.fluxcd.io/` ou `argocd.argoproj.io/` ; toute chaîne `${`. Raison : une annotation de moteur fait diverger un contrôle de sécurité sur une seule cible (`configmanagement.gke.io/managed: disabled` fait cesser la gestion d'un objet par Config Sync), et Flux remplace un `${var}` non défini par une chaîne vide, quand Config Sync le laisse tel quel. C'est la règle déjà posée pour `gateway.envoyproxy.io` (ADR-005, condition 2). Précision de [ARCHI] : la politique porte sur tout ce que Kustomize rend, base et overlays d'environnement compris, et la couche de cible ne loge les objets propres à son moteur que dans le dossier de ses objets de liaison. Ajout de [SECU] : la prévention de dérive par webhook, option de Config Sync, ne compte pas comme contrôle de sécurité, puisqu'elle n'existe pas sur le PC.
2. Même rendu des deux côtés (R-31). Config Sync embarque la version de Kustomize liée à chaque release, Flux la sienne dans `kustomize-controller`. Un test de la matrice rend chaque overlay avec la version de Kustomize de chaque moteur, et échoue au moindre écart. Variante : la CI rend une fois, et les deux moteurs synchronisent la sortie rendue ; elle va avec la source OCI de la question 2. Avis de [ARCHI] : le test de comparaison par défaut, la variante seulement si Lucas retient la source OCI.
3. Droits restreints des deux côtés, sans `cluster-admin` par défaut (R-33). Sur `gcp`, chaque `RootSync` porte `spec.override.roleRefs` vers un rôle limité au namespace de son environnement ; sans ce champ, Config Sync lie le réconciliateur à `cluster-admin`. Sur `local`, les contrôleurs de Flux concernés reçoivent `--no-cross-namespace-refs`, `--no-remote-bases` et `--default-service-account`, et chaque `Kustomization` une `serviceAccountName` limitée à son namespace ; la liste des contrôleurs qui portent chaque option se relève sur la page de verrouillage multi-locataire de Flux ([OPS]). Contrôles : une politique conftest refuse un `RootSync` sans `roleRefs`, toute liaison à `cluster-admin` dans les objets de liaison, une `Kustomization` sans `serviceAccountName`, et un contrôleur concerné sans ses options ; un test de la matrice vérifie qu'un environnement ne peut pas écrire dans le namespace d'un autre, sur kind pour `local` et dans le test de la condition 5 pour `gcp`. Précision de [ARCHI] : ces réglages bornent ce que la réconciliation d'un environnement peut faire. Les contrôleurs gardent les droits de leur manifest, et lisent tous les Secrets du cluster (BENCH-009, section 7.3) ; réduire ces droits n'a pas été étudié.
4. Identifiants Git et source (R-33, R-28, R-07). Jamais le jeton GitHub de portée `repo` que conseille la documentation de Google, qui donne l'écriture sur tous les dépôts de l'utilisateur ; jamais le jeton de `gh`, qui porte les droits d'administration (R-07) ; jamais un jeton personnel. Sur `gcp` : une clé de déploiement en lecture seule limitée au dépôt, une GitHub App installée sur ce seul dépôt avec un droit de lecture du contenu, ou une source OCI dans Artifact Registry lue par Workload Identity (`k8sserviceaccount`), sans aucun secret (question 2). En SSH, `known_hosts` est obligatoire : Google le tient pour « Optional, but recommended », et la vérification de l'hôte saute sans lui. Le Secret ne vient jamais d'une ressource Kubernetes d'OpenTofu, dont la valeur finirait dans l'état (R-19). Sur `local` : aucun identifiant Git par défaut (question 1). Si un identifiant devient nécessaire, une clé de déploiement en lecture seule avec `known_hosts`, que Flux attend à côté de `identity`, saisie sans écho et créée par un tube (`kubectl create -f -`), jamais par `kubectl apply` (ADR-007, condition 1). Si un serveur Git tourne dans le cluster local, le push anonyme y est fermé, et une NetworkPolicy n'ouvre la lecture qu'au namespace du moteur. La branche suivie est protégée dans le dépôt généré (Q3). Contrôles : une politique conftest refuse `auth: token` dans un `RootSync` ; la tâche qui crée un Secret Git échoue sans `known_hosts`, et un test le vérifie ; un test de la matrice vérifie que le serveur Git local, s'il existe, refuse un push.
5. Couche `gcp` testée en x64 (R-31). La couche `gcp` est testée sur kind, sur un runner `ubuntu-latest` en x64, avec la forme libre de Config Sync dans la version déployée sur GKE. Ce test valide les objets de liaison, le rendu et les droits de la condition 3 ; le service géré par Fleet reste hors de sa portée (condition 7). L'essai natif en x64 reste à faire : BENCH-009 n'a vu la forme libre synchroniser la structure du projet que sous émulation. Sur GKE, Config Sync tourne sur des nœuds x86 ; la façon de le garantir en Autopilot n'a pas été vérifiée ([OPS]).
6. Images figées par condensat (R-25, ENF-03). Les images de Flux, et celles de la forme libre de Config Sync dans le test de la condition 5, modèles de réconciliateurs compris, sont désignées par condensat, par le champ `digest` du transformateur `images` de Kustomize. Les manifests sont versionnés et vérifiés par SHA-256 (ADR-004, conditions 3 et 4). Revenir aux tags pour faire marcher `kind load docker-image` reste refusé. Sur GKE, les images de Config Sync sont celles qu'installe le service Fleet. Contrôle : la matrice échoue sur toute image d'un moteur sans condensat. Tant que R-25 n'est pas résolu, ces images restent retéléchargées à chaque création du cluster kind (ADR-005, condition 4).
7. Essai sur GKE (R-31, principe X). Ajout de [ARCHI], sur le modèle de la condition 3 de l'ADR-007 : le service managé n'a jamais tourné, et le test de la condition 5 ne le couvre pas. L'essai tourne sur GKE Autopilot avec l'accord de Lucas et un budget validé par [FINOPS], au premier apply réel de la phase 2 (R-17), avant la GATE 2. Il échoue si l'inscription dans la flotte ou l'activation échouent depuis la couche OpenTofu, si le `RootSync` ne synchronise pas l'overlay de l'environnement, si `roleRefs` laisse l'environnement écrire hors de son namespace, ou si l'export des métriques reste actif alors que la couche le coupe. Il relève les demandes effectives des pods de Config Sync (question 5). Tant qu'il n'a pas passé, la ligne `gcp` de l'entrée de catalogue garde ces points en `pending`, aucun blueprint ne s'en sert (principe IV), et la combinaison n'est pas proposée (principe I). Aucun budget n'est validable tant que les grilles de GKE et de Cloud Monitoring restent illisibles (R-05).
8. Signature des images face à Kyverno. Ajout de [SECU], qui s'applique quand les politiques Kyverno d'ENF-03 entrent dans le blueprint. Elles vivent dans la couche commune, et un test de la matrice vérifie qu'une image non signée est refusée sur les deux cibles, la couche `gcp` tournant comme dans la condition 5. Aucune signature des images de Config Sync n'a été trouvée : `verifyImages` demandera d'exclure ses namespaces sur `gcp`, écart à lister au README. Pour Flux, la documentation annonce des images signées par cosign, et [SECU] n'a pas pu établir où la signature est rangée, faute de cosign sur le poste.

Le README généré liste les écarts entre cibles (ENF-02), d'après BENCH-009 (section 7.1) : moteur différent ; objets de liaison différents ; interrogation de Git toutes les 15 s par Config Sync, à l'intervalle choisi pour Flux ; aucune interface web locale avec Flux ; prévention de dérive par webhook, option de Config Sync sans équivalent vérifié côté Flux ; montée de version de Config Sync à la main, même sur GKE ; exclusion de `verifyImages` de la condition 8.

### Réserves de [FINOPS]

1. Pods de Config Sync comptés comme facturés jusqu'à preuve contraire (R-31). Un seul `RootSync` par cluster dans le profil démo, comme le veut Q6. Les demandes des composants communs sur GKE managé n'ont pas été lues ; les valeurs du manifest libre servent d'ordre de grandeur.
2. Export des métriques coupé ou filtré par défaut. `spec.monitoring.enabled: false` coupe la collecte et l'export pour un `RootSync`, et retire le conteneur `otel-agent`. Le réglage n'est pas pris en charge sur le `root-sync` créé par la console : le blueprint déclare ses propres `RootSync`.
3. Coût du test de la condition 5. Il tire 407,6 Mo par exécution sur une VM neuve. Les runners standard sont gratuits sur le dépôt public de CELIAN ; un projet généré privé qui embarquerait ce test dans sa CI en paierait les minutes.

### Portée

Brique abstraite : `gitops`. La spec ne la déclare pas : elle découle de la cible, comme `kubernetes-cluster` (`declared_by: target`, ADR-009). La spec ne nomme ni Flux ni Config Sync (principe II).

Restent hors de cette décision : la forge et le déclencheur de la CI, fixés par le brief ; le déploiement progressif ; la mise à jour automatique des images par l'outil GitOps ; la gestion des secrets (ADR-007) ; le mode et le canal du cluster GKE (ADR-008, règle de version de l'ADR-004) ; la boucle de développement locale (ADR-006) ; Windows (Q5).

## Conséquences

### Positives

- Les mêmes manifests d'application et la même structure de dépôt servent aux trois outils : chacun a synchronisé la même base et les mêmes overlays dans BENCH-009 (M4), Config Sync sous émulation.
- Flux sur le PC : couche à 265,2 Mio au nœud, à 52 % du seuil ; installation en 29,1 s en médiane, sous le seuil de 90 s ; synchronisation de trois environnements et prise en compte d'un commit au plancher de la méthode (2,3 s et 1,1 s). Demandes de ressources posées par le manifest, contrôleurs conformes au profil « restricted » des Pod Security Standards, SBOM et provenance SLSA Build Level 3.
- Gouvernance de fondation sur le PC : Flux est gradué à la CNCF depuis le 2022-11-30, sous Apache-2.0 pour la CLI et chacun des sept contrôleurs. Trois avis en douze mois, aucun critique, tous corrigés avant leur publication.
- Sur GKE, licence de Config Sync incluse dans l'offre GKE, flotte comprise, et aucun outil à installer par l'équipe.
- Coût de sortie borné : passer `gcp` à Flux ne change que ses objets de liaison (montage A), et les conditions 1 et 2 gardent la couche commune prête pour ce repli.

### Négatives

- Deux moteurs à connaître et à suivre : 30 versions par an (19 pour Flux, 11 pour Config Sync) au lieu de 19 avec Flux partout, deux jeux d'objets de liaison, deux tests GitOps dans la matrice (R-31).
- La couche `gcp` ne se teste nativement qu'en x64 : aucun poste à processeur Apple ni runner arm64 ne la teste, et un pool de nœuds Arm sur GKE ne porterait pas Config Sync (R-31).
- Le service managé n'a jamais tourné : inclusion, prise en charge d'Autopilot, format du dépôt et droits reposent sur la documentation de Google (R-31, condition 7).
- Pods de Config Sync dans le cluster du client, facturation non établie : environ 1,29 vCPU et 1,76 Gio sur un cluster à rafale pour un `RootSync`, puis environ 0,93 vCPU et 0,93 Gio par environnement ajouté ; métriques facturées par Cloud Monitoring (R-31, R-05).
- Config Sync : éditeur unique, 126 commits humains par 8 auteurs en douze mois, le premier à 47,6 % ; aucun avis publié, des CVE corrigées sans être nommées dans neuf releases de 2026 ; montée de version à la main ; signature des images non trouvée ; durcissement des pods partiel, avec `runAsNonRoot: true` posé 4 fois pour 12 `allowPrivilegeEscalation: false` (R-32).
- Flux repose pour l'essentiel sur deux mainteneurs de ControlPlane, qui font 62,0 % des commits humains de `flux2`. Sa politique de sécurité parle d'un traitement « on a best-effort basis », et il publie ses avis dans chaque dépôt : l'avis élevé GHSA-mwcp-qpcg-fr7c manque à la base mondiale de GitHub (R-32).
- Les trois moteurs appliquent par défaut avec `cluster-admin`, et leurs contrôleurs lisent tous les Secrets : écrire sur la branche suivie revient à administrer le cluster (R-33). Le récepteur de webhooks de Flux, sur le port 9292, est ouvert à tous les namespaces.
- Aucune interface web avec Flux : l'état se lit par la CLI `flux` ou par les conditions des objets.
- Empreinte sur le PC : 392,1 Mo d'images en amd64 pour les sept contrôleurs, 258,1 Mo pour les quatre par défaut, au-dessus du seuil de 112,5 Mo, et retéléchargés à chaque création du cluster tant que R-25 n'est pas résolu.
- R-04. Avec kind, Envoy Gateway, les Secrets natifs, Flux réduit et la stack, le premier `task up` complet télécharge 1 395,9 Mo en amd64 : 124 % du budget de 900 s à 10 Mbit/s utiles, une hypothèse. Sans GitOps sur le PC, c'est encore 101 % (R-04, ADR-006). Retirer Flux du profil lite ne suffit donc pas à tenir le critère (question 3).
- Q6 du PRD et la fiche de l'agent `ops` nomment Argo CD (section « Suites »).
- Les mesures viennent d'un seul poste, arm64 sous macOS avec OrbStack, moteur non libre (R-26) ; Flux n'a été mesuré ni sous Linux ni en amd64.

### Effet sur les cibles hors MVP

La porte reste ouverte. La couche commune ne porte rien de propre à un moteur (conditions 1 et 2), et la politique de la condition 1 refuse déjà le groupe `argoproj.io` hors des couches de cible. Hors MVP, AWS propose Argo CD en service managé sur EKS, et Microsoft Flux en extension managée d'AKS : sur ces cibles, le principe III les désignerait, et chaque couche apporterait ses objets de liaison (BENCH-009, section 5.7). Une cible on-prem serveurs aurait sa propre ligne au catalogue, choisie par son benchmark.

### Suites

- Entrée de catalogue `gitops`, dans une PR qui suit la GATE 1 (section « Entrée au catalogue »).
- Pour [PO], si Lucas suit : une PR dédiée reformule Q6 (section 8 du PRD). La structure prête devient une base Kustomize et un overlay par environnement, avec un `RootSync` par environnement sur GCP et les objets de Flux sur le PC. Le brief (section 6) reste la trace d'origine et ne se réécrit pas.
- Pour le DSI, si Lucas suit : une PR dédiée corrige `.claude/agents/ops.md`, qui nomme Argo CD à la ligne 3 (description de l'agent) et à la ligne 13 (« Argo CD et ApplicationSets par environnement »). BENCH-009 ne relève que la ligne 13. La composition des profils proposée par BENCH-005, qui place Argo CD dans le profil full (ADR-006), se revoit avec la question 3. Cet ADR ne modifie aucun de ces fichiers.
- Pour [OPS] : ressources OpenTofu de la flotte et de l'activation ; mécanisme qui fige la version de Config Sync ; nœuds x86 en Autopilot ; application du premier `RootSync` et du Secret Git ; options de la condition 3 par contrôleur ; préchargement des images sous le condensat du registre (R-25).
- Pour [SECU] et [QA] : politiques conftest des conditions 1, 3 et 4 ; tests des conditions 2, 3, 5 et 6 ; relecture mensuelle des notes de version de Config Sync et des avis des dépôts `fluxcd` (R-32).
- Pour [BENCH], sans dépense : attribuer la part d'Argo CD qu'aucun pod n'explique, par les pods de `kube-system` relevés avant et après l'installation ; remesurer les quatre configurations dans une même série alternée ; mesurer Flux et la forme libre de Config Sync sur un runner x64.
- Pour [FINOPS] : facturation des pods de Config Sync en Autopilot, et lecture des grilles de GKE et de Cloud Monitoring (R-05).

### Questions ouvertes

1. Que lit Flux sur le PC, pour Lucas. Un dépôt privé imposerait un vrai identifiant sur chaque poste, en clair dans etcd (R-28, ADR-007), lisible par tous les contrôleurs qui lisent les Secrets, et une synchronisation qui demande le réseau, contre la condition 7 de l'ADR-004 (recréation hors ligne). Un dépôt public évite l'identifiant, mais garde la dépendance au réseau. Avis de [ARCHI] : par défaut, une source servie dans le cluster depuis la copie de travail, sans identifiant ni réseau, sous les règles de la condition 4 ; le dépôt distant seulement s'il est public. Le serveur de test de BENCH-009 ne convient pas tel quel : ses paquets `git`, `git-daemon` et `lighttpd` sont installés sans version figée. Cette source ajoute une image au premier `task up`, que personne n'a mesurée.
2. Source OCI sur GKE, pour Lucas, [OPS] et [SECU]. Elle retire tout identifiant Git de la cible `gcp` (R-33), au prix d'une CI qui publie un artefact dans Artifact Registry et de l'identité de CI de R-19. Elle permet aussi la variante de la condition 2. Avis de [ARCHI] : favorable sur le principe, à trancher en phase 2 avec Q8 (où publier et signer les images avant que GCP existe), puisque les deux passent par le même registre et la même identité.
3. L'outil GitOps dans le profil lite de US-005, pour Lucas, [OPS] et [PO]. Sortir Flux du profil lite épargne 258,1 Mo en amd64, soit 206,5 s à 10 Mbit/s, mais le premier lancement reste à 101 % du budget (R-04, ADR-006, question 3). Un second fait pèse : sous sa politique par défaut, Flux corrige la dérive à chaque réconciliation, et sa documentation écrit que les modifications faites par `kubectl` « will be reverted ». S'il synchronise l'environnement `local`, il défait ce que `task reload` applique par `kubectl apply -k` (ADR-006). Avis de [ARCHI] : Flux hors du profil lite, où `task up` et `task reload` restent seuls maîtres des objets de l'application ; Flux dans le profil qui exerce la chaîne GitOps, full dans la composition proposée par BENCH-005, qui y plaçait Argo CD. Dans ce profil, un seul acteur tient les objets de l'application : soit Flux, et la boucle passe par la source qu'il lit, soit `task reload`, et la `Kustomization` est suspendue (`spec.suspend`). Le choix se fait en phase 3 avec [DEV] et [OPS], et la matrice couvre le profil qui porte Flux (principe I).
4. Flux réduit à ses quatre contrôleurs par défaut, pour [OPS] et Lucas. L'automatisation des images est hors champ de BENCH-009 : `image-reflector-controller`, `image-automation-controller` et `source-watcher` n'y servent pas. 134,0 Mo de moins en amd64, et trois pods de moins. Avis de [ARCHI] : favorable ; les chiffres de R-04 supposent déjà ce Flux réduit.
5. Facturation des pods de Config Sync en Autopilot, pour [FINOPS], [OPS] et Lucas. Seule la grille de GKE, une réponse de Google ou la facture d'un essai autorisé la tranchera (condition 7). Si elle est établie, cet ADR se rouvre sur la comparaison avec le montage A.
6. Lecture des principes III et V de l'ADR-009, pour Lucas. La ligne `gcp` en dépend. Si V prime, Flux passe devant Config Sync sur `gcp`, et un nouvel ADR remplace celui-ci par le montage A. Si Lucas retient la lecture littérale, la ligne `gcp` devient une dérogation, justifiée au paragraphe « Écart au principe V ».
7. Règle de mémoire au nœud et règle d'égalité, pour Lucas. Toutes deux sont provisoires jusqu'à la GATE 1, et le choix de Flux sur le PC repose sur la première (section « Sensibilité »). Avis de [ARCHI] : garder la lecture au nœud, par cohérence avec BENCH-004 et BENCH-007, et l'écrire dans le gabarit de benchmark avec la mesure de `kube-system` qui permet d'attribuer l'écart.

## Conformité à la constitution

Vérifiée contre la [constitution](../../.specify/memory/constitution.md) en version 1.0.0. L'amendement 1.1.0 (PR #13) ne touche que la section « Périmètre du MVP ».

| Principe | Effet | Justification |
| --- | --- | --- |
| I. Rien sans test automatique | respecté | La matrice porte les contrôles des conditions 1 à 6, et l'essai sur GKE de la condition 7 ; sans lui, la combinaison `gcp` n'est pas proposée |
| II. Spec abstraite, catalogue concret | respecté | La spec ne déclare pas la brique `gitops` ; Flux et Config Sync n'apparaissent que dans les couches de cible et au catalogue, et les conditions 1 et 2 gardent la couche commune neutre |
| III. Managé sur le cloud, open source ailleurs | respecté | Sur `local`, Flux, sous Apache-2.0 et gratuit ; sur `gcp`, Config Sync, service managé, dans la lecture de l'ADR-009 qui attend Lucas. La forme libre de Config Sync ne sert qu'au test de la condition 5 |
| IV. Catalogue traçable | respecté | Les deux lignes portent licence ou fournisseur, gouvernance, statut, date et sources ; la ligne `gcp` garde ses `pending` jusqu'à l'essai de la condition 7 |
| V. Gouvernance ouverte d'abord | respecté dans la lecture de l'ADR-009 | Sur `local`, Flux, gradué à la CNCF, neuf mainteneurs principaux de quatre employeurs et trois indépendants ; l'option à éditeur unique est écartée. Sur `gcp`, service managé imposé par III ; l'écart est écrit ci-dessous, pour le cas où Lucas retiendrait une autre lecture |
| VI. Récent mais éprouvé | respecté | Aucun critère éliminatoire touché (BENCH-009, section 3) ; Flux 2.10.0 du 2026-10-26 et Config Sync 1.25.2 du 2026-11-03 passent le délai de 7 jours |
| VII. Une commande pour démarrer | respecté | `task up` installe Flux depuis des fichiers versionnés, sans identifiant Git par défaut (condition 4, question 1) ; si Flux sort du profil lite, ce profil ne dépend plus de lui (question 3) |
| VIII. Aucun fait de mémoire | respecté | Les faits renvoient à BENCH-009, à ses relectures, au registre des risques et à la documentation de Flux relue le 2026-11-20. Sont signalés comme non vérifiés : les ressources OpenTofu de la flotte et de l'activation, le mécanisme qui fige la version de Config Sync, la garantie de nœuds x86 en Autopilot, la facturation de ses pods, l'emplacement des signatures d'images, et l'offre GitOps managée d'AWS et d'Azure au-delà de ce qu'en dit BENCH-009 |
| IX. Aucun secret dans le dépôt | respecté | Aucun identifiant Git dans le dépôt ni dans l'état OpenTofu (condition 4) ; aucun sur le PC par défaut |
| X. Aucune dépense cloud sans accord | respecté | Aucune ressource GCP créée pour BENCH-009 ni pour cet ADR. Activer Config Sync ou créer un `RootSync` sur GKE fait tourner des pods peut-être facturés : ces actions relèvent du principe X au même titre que `tofu apply`, et reviennent à l'utilisateur (US-006). L'essai de la condition 7 attend l'accord de Lucas et un budget de [FINOPS] |

### Écart au principe V

Sur `gcp`, Config Sync dépend de Google seul, sans fondation, et il est noté 2 en gouvernance, quand Flux, gradué à la CNCF, est noté 4 (BENCH-009, section 5.2). Dans la lecture de l'ADR-009, cet écart n'a pas à se justifier : le principe III impose le service managé du fournisseur sur une cible cloud, et le principe V ne départage que les candidats que III autorise. Le gabarit d'ADR le dit aussi. Ce paragraphe sert si Lucas retient la lecture littérale.

Aucun critère de la grille ne justifie l'écart : Config Sync est dernier dans toutes les lectures, à 24 points au moins de Flux. L'écart se justifie donc hors de la grille, par trois faits. Il ne crée aucune dépendance nouvelle : sur `gcp`, le cluster dépend déjà de Google, et Config Sync est inclus dans l'offre GKE. Son coût de sortie se limite à la couche `gcp` : ce que les deux cibles partagent est la base Kustomize et ses overlays, et passer à Flux ne change que les objets de liaison, tant que les conditions 1 et 2 tiennent. Enfin, ce qui tourne dans le cluster est libre : Google parle de « hosted components in Google Cloud and open source components on your Google Kubernetes Engine cluster », et ce code est publié sous Apache-2.0. La gouvernance d'éditeur unique pèse quand même : aucun avis publié, des CVE corrigées sans être nommées, et 75,4 % des commits humains de l'année portés par deux auteurs (R-32).

Si V prime, l'écart ne se justifie plus : Flux passe devant sur `gcp`, et un nouvel ADR remplace celui-ci par le montage A.

### Dérogations

Aucune dans la lecture de l'ADR-009. Si Lucas retient la lecture littérale, la ligne `gcp` devient la dérogation suivante :

| Principe | Écart | Justification | Durée | Condition de levée |
| --- | --- | --- | --- | --- |
| V. Gouvernance ouverte d'abord | Ligne `gcp` : Config Sync, de Google seul, sans fondation | Principe III, aucune dépendance nouvelle, coût de sortie limité à la couche `gcp` (paragraphe précédent) | Tant que la ligne `gcp` repose sur Config Sync | Repli sur Flux (montage A), ou validation de la lecture de l'ADR-009 |

## Entrée au catalogue

Brique abstraite : `gitops`, nom proposé par BENCH-009 (section 7.8), `declared_by: target` comme `kubernetes-cluster`, à confirmer en phase 3 avec le schéma de spec. L'entrée s'écrit au format de l'ADR-009, dans une PR qui suit la GATE 1.

| Cible | Service | Type | Licence | Gouvernance | Statut | Vérifié le | Source |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `local` | Flux 2.10.0, contrôleurs selon la question 4 | `oss` | Apache-2.0 | Fondation : CNCF (gradué le 2022-11-30) | actif | 2026-11-19 | <https://github.com/fluxcd/flux2>, <https://www.cncf.io/projects/flux/> |
| `gcp` | Config Sync, service de GKE, après inscription du cluster dans une flotte | `managed` | service propriétaire du fournisseur | Éditeur unique : Google | actif | 2026-11-19 | <https://docs.cloud.google.com/kubernetes-engine/config-sync/docs/overview>, <https://docs.cloud.google.com/kubernetes-engine/config-sync/docs/release-notes> |

Pour `local`, `last_release_on` vaut 2026-10-26, date de 2.10.0 sur l'API des releases de `fluxcd/flux2` lue le 2026-11-19 : sans nouvelle release, le critère des 12 mois tombe le 2027-10-26. Les contrôleurs ont leurs propres dépôts, tous sous Apache-2.0 et non archivés ; leurs dates de release n'ont pas été relevées une à une. `verified_on` suit la lecture la plus récente des sources de chaque ligne, le 2026-11-19 pour les deux.

Les deux lignes exposent le standard `kubernetes-api`, présent dans la liste fermée du catalogue : les deux moteurs appliquent des objets de l'API Kubernetes. Le format qu'ils partagent vraiment, une base Kustomize et ses overlays, n'est pas dans cette liste ; l'y ajouter passe par une PR sur le schéma, avec sa source, en phase 3. La ligne `gcp` n'a pas de `managed_gap`.

La ligne `gcp` garde en `pending`, jusqu'à l'essai de la condition 7 : l'inscription dans la flotte et l'activation en OpenTofu ([OPS]), le mécanisme qui fige la version ([OPS]), les nœuds x86 en Autopilot ([OPS]) et la facturation des pods ([FINOPS]). La ligne `local` garde en `pending` la source lue par Flux (question 1, Lucas) et la liste de ses contrôleurs (question 4, [OPS]).

## Condition de révision

Bascule par un nouvel ADR qui remplace celui-ci, pour la cible concernée, dans ces cas :

- sur `local`, Flux touche un critère éliminatoire : dépôt archivé ou en maintenance, licence qui n'est plus open source, ou aucune release pendant 12 mois, décompte parti du 2026-10-26 ;
- sur `gcp`, l'essai de la condition 7 échoue sur un point que la couche `gcp` ne corrige pas : repli sur Flux (montage A), avec le `managed_gap` de l'ADR-009 qui dit ce que l'essai a montré ;
- Google retire Config Sync de GKE.

La décision se rouvre, sans basculer d'office, dans ces cas :

- Lucas ne retient pas la lecture des principes III et V de l'ADR-009 (question 6) ;
- Lucas revient à la mémoire lue par la somme des pods, ou compte le cumul avec la plate-forme (question 7, ADR-005 question 2) : l'égalité revient, et la règle d'égalité donne Argo CD ;
- la part d'Argo CD qu'aucun pod n'explique se révèle un effet de la mesure, ou une série alternée qui remesure le nœud de base fait passer Argo CD sous 512 Mio ;
- la facturation des pods de Config Sync en Autopilot est établie (question 5). Dans la lecture de l'ADR-009, un prix seul n'établit pas de `managed_gap` ; la comparaison porte alors sur ce prix et sur celui de Flux sur GKE ;
- Google publie Config Sync pour arm64 ;
- Flux perd l'un de ses mainteneurs principaux ;
- AWS ou Azure entrent dans le périmètre.

Si Argo CD revenait, son compte `admin` et son mot de passe initial en clair dans `argocd-initial-admin-secret` s'ajouteraient aux identifiants de R-20, à supprimer comme le recommande sa documentation.

Une montée de version de Flux ou de Config Sync ne rouvre pas cet ADR : elle passe par une PR qui passe la matrice (R-32). Sans l'un de ces faits, prochaine vérification le 2027-05-19, date proposée par BENCH-009 (section 7.8).

## Sources

Ce que BENCH-009 établit se cite par lui ; ses propres sources sont dans sa section 9.

| Source | Lue le | Ce qu'elle établit |
| --- | --- | --- |
| [BENCH-009](../benchmarks/BENCH-009-gitops.md), sections 1 à 3 | 2026-11-19 | Question posée et ce qui en dépend ; options et versions ; deux formes de Config Sync ; critères éliminatoires ; réserve sur les nœuds x86 |
| BENCH-009, section 4 | 2026-11-19 | Seuils écrits avant la mesure ; règle de mémoire au nœud et règle d'égalité, leur origine et leur heure d'écriture ; nœud de base ; mesures M1 à M8 ; volumes par architecture ; tirages à chaque création |
| BENCH-009, sections 5 et 6 | 2026-11-19 | Notes et justifications : licences, gouvernance, avis de sécurité, empreinte, portabilité, expérience dev, coût sur Autopilot ; grille 88, 86 et 62 |
| BENCH-009, section 7 | 2026-11-19 | Sensibilité ; parité et montages A, B et C ; proposition et paragraphe de gouvernance ; droits des moteurs ; identifiants Git ; conditions proposées ; effet sur Q6 et sur la fiche de l'agent `ops` ; questions ; réserves, risques proposés, prochaine vérification au 2027-05-19 |
| BENCH-009, sections 8 à 10 | 2026-11-19 | Limites ; sources S1 à S97 ; avis de [SECU] et de [FINOPS], et arbitrage repris par le rapport |
| Relectures de BENCH-009 par [SECU] et par [FINOPS], résumées en section 10 du rapport | 2026-11-19 | Contrôles de [SECU] sur Kyverno et le webhook de dérive, serveur Git local, Secret créé hors de Config Sync, signatures introuvables au registre ; demandes effectives sur Autopilot et rapports de 3,7 et 4,9, `spec.monitoring.enabled`, 30 versions par an, test x64 à 407,6 Mo |
| <https://fluxcd.io/flux/components/kustomize/kustomizations/> (S24 de BENCH-009) | 2026-11-20 | Réconciliation à chaque `spec.interval`, « correcting any existing drift in the process » ; sous la politique `Override`, par défaut, les modifications faites par `kubectl` « will be reverted » ; `spec.suspend` suspend la réconciliation, et la détection et la correction de dérive |
| [docs/risques.md](../risques.md), R-05, R-07, R-17, R-19, R-20, R-25, R-26, R-31, R-32, R-33 | 2026-11-20 | Mitigations reprises dans les conditions ; apply réels prévus en phase 2 ; texte des trois risques ouverts à la suite de BENCH-009 |
| [docs/risques.md](../risques.md), R-04 et R-28 | 2026-11-20 | Premier `task up` complet à 1 395,9 Mo en amd64, 124 % du budget à 10 Mbit/s et 101 % sans GitOps sur le PC ; secrets locaux en clair dans etcd |
| [ADR-004](ADR-004-cluster-local.md), conditions 3, 4 et 7 | 2026-11-20 | Images par condensat ; manifests tiers versionnés avec leur SHA-256 ; recréation hors ligne |
| [ADR-005](ADR-005-gateway.md), proposé : condition 2, condition 4, question 2, conséquences | 2026-11-20 | Règle du groupe propre à un moteur hors de la couche commune ; R-25 avant le golden repo ; périmètre provisoire des seuils ; serveur d'API de 231,5 à 469,6 Mio avec les CRD d'Envoy Gateway |
| [ADR-006](ADR-006-orchestration-locale.md), proposé : répartition, conséquences, portée, question 3 | 2026-11-20 | `task up` et `task reload` par `kubectl apply -k` ; R-04 à 124 et 101 % ; composition des profils proposée par BENCH-005, Argo CD dans le profil full ; sortie de Flux du profil lite renvoyée à cet ADR |
| [ADR-007](ADR-007-secrets.md), proposé : conditions 1 et 3, arbitrage | 2026-11-20 | Création des Secrets par un tube ; modèle de l'essai sur GKE ; ESO ajoute environ 100 Mio au serveur d'API avec ses 25 CRD ; raisonnement sur le `managed_gap` |
| [ADR-008](ADR-008-modules-opentofu-gcp.md), proposé | 2026-11-20 | Cluster GKE Autopilot de la couche `gcp` ; demandes explicites sur chaque pod |
| [ADR-009](ADR-009-catalogue.md) et [`catalog/README.md`](../../catalog/README.md) | 2026-11-20 | Lecture des principes III et V ; `managed_gap` ; question 3 sur le GitOps ; `declared_by: target` ; types `oss` et `managed` ; `pending` ; liste fermée des standards, dont `kubernetes-api` ; règles de fraîcheur |
| [docs/prd-mvp.md](../prd-mvp.md), US-005, US-006, ENF-01, ENF-02, ENF-03, section 8 (Q3, Q5, Q6, Q8) | 2026-11-20 | Démarrage en une commande et profils ; aucune ressource payante lancée par l'agent ; budget de 15 minutes ; parité et écarts au README ; dépendances figées ; « structure Argo CD prête pour staging et prod » |
| `.claude/agents/ops.md`, lignes 3 et 13 | 2026-11-20 | Argo CD nommé dans la description et dans le domaine de l'agent |
| [Constitution](../../.specify/memory/constitution.md), version 1.0.0 | 2026-11-20 | Principes I à X ; dérogation par ADR, avec sa durée et sa condition de levée |
| [docs/adr/TEMPLATE.md](TEMPLATE.md) | 2026-11-20 | Un service managé imposé par III ne demande pas la justification du principe V |
