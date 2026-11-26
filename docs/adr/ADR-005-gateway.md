# ADR-005. Le projet généré s'expose par Gateway API : Envoy Gateway sur le PC, le contrôleur de GKE sur GCP, sous conditions

| Champ | Valeur |
| --- | --- |
| Statut | accepté |
| Date | 2026-11-19 |
| Auteur | [ARCHI] |
| Décideur | DSI, sur délégation de Lucas à la GATE 1 du 2026-11-20 |
| BENCH lié | [BENCH-004](../benchmarks/BENCH-004-gateway.md) |
| Remplace | aucun |

## Contexte et problème

Le projet généré expose son API et son front par une gateway. Sur la cible `local`, elle tourne dans le cluster kind de l'ADR-004 ; sur `gcp`, dans le cluster GKE de l'[ADR-008](ADR-008-modules-opentofu-gcp.md) (proposé). Il faut choisir le contrôleur de chaque cible, la version des CRD Gateway API et la façon de les livrer au projet, avant le golden repo de la phase 2. Le PRD pressentait Envoy Gateway, repris du brief (section 1 du PRD).

Les exigences viennent du PRD. US-005 veut que `task up` démarre toute la stack sans autre étape (principe VII), affiche des adresses locales qui répondent et choisisse un profil selon la RAM. ENF-01 fixe le parcours à moins de 15 minutes, premier téléchargement des images compris. ENF-02 veut que seule la couche de cible change d'une cible à l'autre (principe II), et que le README liste les écarts restants. ENF-03 veut des dépendances figées et le délai de publication du principe VI. Côté constitution, les principes II, III, V, VI et VIII. Côté risques, R-04 (critère des 15 minutes hors d'atteinte), R-05 (dépense GCP non maîtrisée), R-15 (ressources GCP qui survivent à `tofu destroy`), R-20 (« Identifiants par défaut dans le golden repo »), R-25 (démarrage local tributaire des registres publics) et R-26 (moteur de conteneurs du poste sous licence payante).

Sur `gcp`, le choix suit la lecture des principes III et V que propose l'[ADR-009](ADR-009-catalogue.md) (proposé) : le principe III fixe les candidats d'une cible, le principe V les départage. Le contrôleur Gateway de GKE est le service managé qui implémente Gateway API. L'option de BENCH-004 vaut donc pour `local`, et ne vaudrait pour `gcp` qu'avec un `managed_gap`. Lucas n'a pas encore validé cette lecture. BENCH-004 ne note que les options de la cible `local`, et juge le côté GKE sur sa documentation et son rapport de conformité, sans cluster réel (principe X).

Deux décisions du DSI du 2026-11-19 pèsent sur ce choix, confirmées par Lucas à la GATE 1 le 2026-11-20. R-04 passe en probabilité forte : son déclencheur se lit désormais sur le premier `task up` complet et sur le pire cas des systèmes de Q5, et la plate-forme de base le franchit avec Envoy Gateway en amd64. R-25 passe aussi en probabilité forte : une image désignée par condensat et préchargée par `kind load` repasse par le registre à chaque création, ce qui touche chaque `task up` avec kind.

Le total d'Envoy Gateway a changé pendant la relecture. BENCH-004 notait d'abord le volume sur l'arm64 du poste de mesure, d'où 88. La relecture de [FINOPS] et la décision du DSI le notent sur linux_amd64, pire cas des systèmes de Q5, comme BENCH-008 : l'empreinte d'Envoy Gateway passe de 4 à 3, et son total à 86.

## Options considérées

| Option | Score BENCH (sur 100) | Verdict | Raison principale |
| --- | --- | --- | --- |
| Envoy Gateway 1.10.0 | 86 | retenue pour `local` | Gouvernance ouverte (CNCF au titre d'Envoy), même manifest qu'avec GKE à `gatewayClassName` près sans rien changer au cluster kind, privilèges les plus bas des trois |
| Cilium 1.20.5 | 81 | écartée | Il faut lui céder le CNI et kube-proxy du cluster, ce qui éloigne kind d'un Kubernetes amont ; 764,3 Mo à la première création en amd64, 146,9 s à froid, et l'agent le plus privilégié |
| Traefik 3.7.19 | 78 | écartée | Le plus léger, mais porté par un seul éditeur sans fondation (gouvernance 2/5), avec 70 avis de sécurité en douze mois, dont 41 élevés |

Aucune option ne touche de critère éliminatoire. Le contrôleur Gateway de GKE n'entre pas dans la grille : sur `gcp`, le principe III l'impose dans la lecture de l'ADR-009.

La sensibilité de BENCH-004 (section 7) éprouve ces totaux. Aucun changement d'un seul cran ne renverse le classement, un cran valant au plus 3 points. Avec le volume noté en arm64, Envoy Gateway monte à 88. Avec sa mémoire au-dessus du seuil, comme à son exécution 1, il tombe à 84 et reste premier. L'égalité à 84 avec Cilium demande deux changements à la fois : cette mémoire au-dessus du seuil, et un cran de gouvernance rendu à Cilium.

Grille, mesures et sources : [BENCH-004](../benchmarks/BENCH-004-gateway.md).

## Décision

Sur la cible `local`, le projet généré expose son API et son front par Envoy Gateway 1.10.0. Sur la cible `gcp`, il les expose par le contrôleur Gateway de GKE, service managé, sans `managed_gap`. La couche commune du blueprint ne contient que des objets Gateway API du cœur, et le cluster local reçoit les CRD Gateway API v1.7.0 du canal standard, comme dans BENCH-004.

Le blueprint déclare une seule Gateway, à deux écouteurs (HTTP 80 et HTTPS 443), pour l'API et le front, et des HTTPRoute. C'est la forme du manifest que BENCH-004 a mesuré, et la recommandation de [FINOPS] (voir « Réserves de [FINOPS] »).

La validation d'ensemble se fait à la GATE 1. Trois points y demandent l'avis explicite de Lucas : les questions ouvertes 1 à 3.

### Répartition par couche

| Couche | Contenu |
| --- | --- |
| commune | La Gateway et les HTTPRoute, en `gateway.networking.k8s.io/v1`, avec les seuls champs du cœur présents dans les versions que sert GKE. `gatewayClassName` vient de la couche de cible ; le mécanisme (variable de Copier ou correctif de la couche) se fixe en phase 3 |
| `local` | Les CRD Gateway API v1.7.0 du canal standard, versionnées avec leur SHA-256 et appliquées depuis le fichier (condition 4 de l'ADR-004). Les CRD propres à Envoy Gateway, par le chart `gateway-crds-helm`. Le contrôleur, par le chart `gateway-helm`. Une GatewayClass liée par `parametersRef` à un objet EnvoyProxy, qui publie le proxy en Service NodePort à ports fixes. Deux `extraPortMappings` vers ces ports, en `listenAddress: "127.0.0.1"` (condition 1 de l'ADR-004) |
| `gcp` | Le nom d'une classe fournie par GKE : `gke-l7-global-external-managed` dans BENCH-004, choix final par [OPS] avec [FINOPS]. GKE installe et tient lui-même les CRD, canal standard seul. Leur activation s'écrit dans la couche OpenTofu de l'ADR-008 : BENCH-004 cite l'option `--gateway-api=standard` de `gcloud`, et l'équivalent OpenTofu n'a pas été vérifié |

### Versions et condensats

Valeurs vérifiées par BENCH-004 le 2026-11-19. Le rapport les abrège ; les valeurs complètes sont celles de son script, `tests/bench/bench-004-gateway.sh`, qui vérifie chacune avant usage.

| Élément | Référence | Condensat |
| --- | --- | --- |
| CRD Gateway API, canal standard | `standard-install.yaml` de la release v1.7.0 de `kubernetes-sigs/gateway-api`, publiée le 2026-10-29, release immuable, attestation de release vérifiée par [SECU] | SHA-256 `4e2602c4cbe1afbc394d86f4ac6522e1a5263b01133bba1e40a6d1a549e753a1` |
| Chart du contrôleur | `oci://docker.io/envoyproxy/gateway-helm` v1.10.0 | SHA-256 `0f72c9050c33dbaab39b865e8cb5ed77f263720b22368eda4ce687077649e659` |
| Chart des CRD d'Envoy Gateway | `oci://docker.io/envoyproxy/gateway-crds-helm` v1.10.0 | SHA-256 `cc213d9059d0391d69d70bef7c041fb1c1e45270c84a65988229bd88639d0aa5` |
| Contrôleur | `docker.io/envoyproxy/gateway:v1.10.0` | `sha256:c2243d43518bed91d3ed8c2db849a4b7a14ac9b96eb019f2ab104bb1ca8572b1` |
| Proxy | `docker.io/envoyproxy/envoy:distroless-v1.40.2`, valeur par défaut compilée dans le binaire 1.10.0 | `sha256:09ca6f2140a61ad8df11779a4a30d52b48433d444466328494f9188c9c35eded` |

Réglages mesurés, repris tels quels. `gateway-crds-helm` reçoit `crds.envoyGateway.enabled=true` et `crds.gatewayAPI.enabled=false`, pour ne pas installer sa copie v1.6.1 du canal expérimental. `gateway-helm` reçoit `crds.enabled=false`, et `global.images.envoyGateway.image` égal à la référence par condensat du contrôleur.

Envoy Gateway 1.10.0 est publiée depuis le 2026-11-06 et Gateway API v1.7.0 depuis le 2026-10-29 : toutes deux passent le délai de 7 jours du principe VI. La date de publication du proxy 1.40.2 n'a pas été lue ; il entre avec le binaire du contrôleur, qui le fixe.

Écart de version des CRD. Le cluster local reçoit v1.7.0. GKE sert v1.5.0 à partir de 1.35.2-gke.1842000, et son rapport de conformité porte sur v1.6.0 avec 1.36.2-gke.2154000. La matrice d'Envoy Gateway 1.10 annonce v1.6.1, et v1.7.0 a fonctionné dans M7. La couche commune n'emploie donc que des champs que GKE sert (condition 5), et le README du projet généré liste cet écart (ENF-02).

### Conditions

Les quatre premières sont celles de [SECU] (BENCH-004, section 7). La décision ne vaut qu'avec elles. Chaque contrôle cité entre dans la matrice de validation (principe I).

1. Images et CRD figées. Le blueprint force le condensat du contrôleur, met `crds.enabled=false`, et fige aussi l'image `ratelimit` s'il active la limitation de débit : les valeurs du chart la désignent par tag, `docker.io/envoyproxy/ratelimit:5ae0682e`. La configuration mesurée ne l'active pas, et cet ADR non plus. Contrôle : la matrice rend les deux charts avec les valeurs du blueprint, comme [SECU] l'a fait en relecture, et échoue sur toute image sans condensat et sur toute CRD du groupe `gateway.networking.k8s.io` qui ne vient pas du `standard-install.yaml` vérifié. Les deux charts sont vérifiés par leur SHA-256 avant usage, comme les manifests tiers de la condition 4 de l'ADR-004.
2. Groupe `gateway.envoyproxy.io` cantonné à la couche `local`. Ses objets (EnvoyProxy, politiques de sécurité et de trafic) n'existent pas sur GKE. La couche commune ne contient que des objets Gateway API du cœur, et une politique conftest ou Kyverno refuse ce groupe hors de la couche `local`. Sinon, un contrôle posé en local disparaîtrait sans bruit en production. Ajout de [ARCHI] : dans la couche `local`, ce groupe ne sert qu'à configurer la cible, comme l'EnvoyProxy des ports fixes. Un contrôle de sécurité porté par une politique de ce groupe, par exemple une authentification, une liste d'adresses ou une limite de débit, demande un nouvel ADR qui nomme son équivalent sur `gcp`. Le contrôle porte sur la couche d'où vient l'objet, ce qui se lit dans le blueprint avant tout cluster : [ARCHI] penche pour conftest, et le choix de l'outil revient à [SECU] et [QA].
3. Signature du contrôleur. La CI vérifie la signature cosign de l'image du contrôleur avec l'identité du workflow de release d'`envoyproxy/gateway` (`.github/workflows/release.yaml`, qui lance `cosign sign` sur le condensat de l'index), et échoue si la vérification échoue. La commande s'écrit une fois cosign installé et vérifiée sur sa documentation. Le 2026-11-19, [SECU] n'a trouvé aucun tag `.sig` au registre et n'a pas pu trancher où la signature est rangée, faute de cosign sur le poste. Le proxy n'est pas couvert : sa signature n'est pas établie, et son condensat vient du binaire du contrôleur.
4. R-25 traité avant le golden repo. Sans préchargement sous le condensat du registre, la condition 7 de l'ADR-004 (recréation hors ligne) échoue, quelle que soit la gateway. [OPS] essaie les pistes de R-25 : un registre miroir local en boucle locale, une archive OCI qui garde l'index du registre, le magasin containerd du moteur. Revenir à des références par tag ou à `imagePullPolicy: Never` reste refusé. La condition est remplie quand le test de la condition 7 de l'ADR-004 passe avec la gateway installée.
5. Parité du manifest. Ajout de [ARCHI], qui reprend le contrôle de M7. La matrice rend la Gateway et les HTTPRoute pour `local` et pour `gcp`, et échoue si leur différence porte sur autre chose que `gatewayClassName`, ou si le rendu compte plus d'une Gateway. Elle valide aussi la couche commune contre le schéma de la version de Gateway API que sert GKE ; l'outil se fixe avec [QA]. Un écart voulu entre cibles passe par un ADR et se liste au README (ENF-02).

### Réserves de [FINOPS]

1. Une seule Gateway sur GKE pour l'API et le front. Le contrôleur de GKE est sans surcoût dans la tarification de GKE, mais chaque Gateway y a sa propre adresse IP et son propre équilibreur de charge, facturé. Le montant n'est pas chiffré : la grille réseau de Google n'a rendu que son titre le 2026-11-19 (R-05). Cet équilibreur naît de Kubernetes, hors de l'état OpenTofu, et `tofu destroy` ne le voit pas : la Gateway se supprime avant (R-15). La condition 5 compte les Gateway.
2. Plancher mémoire. Au repos, la plate-forme de base passe de 591,6 Mio avec kind seul à 948,8 Mio avec Envoy Gateway, soit de 7,2 % à 11,6 % d'un portable de 8 Gio. C'est le nouveau plancher du profil lite de US-005, avant la stack que mesurera BENCH-005. La marge sous le seuil de 1 Gio, 75 Mio, est plus petite que l'écart entre les exécutions, 144,2 Mio : deux exécutions à chaud de plus, sans action payante, trancheraient.

### Correctif attendu : CVE-2026-97054

Le scan Trivy de [SECU] trouve une CVE élevée dans le contrôleur 1.10.0 : CVE-2026-97054, dans la bibliothèque standard de Go 1.27.3, corrigée en Go 1.27.4. Elle touche les serveurs HTTP/1 du contrôleur, joignables seulement depuis le cluster. [SECU] la suit jusqu'à une release 1.10.x recompilée avec un Go corrigé, que le blueprint prend selon la règle de mise à jour ci-dessous. Le 2026-11-19, l'API des releases ne montre aucune release 1.10.x après 1.10.0 ; la plus récente du projet est 1.9.4, du 2026-11-17.

### Mises à jour

1. Mineure maintenue. D'après la matrice d'Envoy Gateway, 1.10 est maintenue jusqu'au 2027-05-05 et couvre Kubernetes 1.34 à 1.37, dont la mineure 1.36 de la règle de version de l'ADR-004. Le passage à la mineure suivante se fait à la main, avant cette date, dans une release du blueprint qui passe toute la matrice.
2. Correctifs. Renovate propose dans une seule PR le chart et le condensat du contrôleur d'une même release, une fois celle-ci publiée depuis 7 jours (principe VI). La configuration de Renovate qui tient cette paire n'a pas été vérifiée dans sa documentation : [OPS] la vérifie. À défaut, chaque release donne lieu à une PR manuelle, avec le même délai. Lucas a tranché le cas des correctifs de sécurité à la GATE 1 : amendement du principe VI (question 1).
3. CRD Gateway API. Leur version change à la main, dans une release du blueprint qui passe la matrice, après lecture de la matrice d'Envoy Gateway et de la version que sert GKE.

### Portée

La spec ne nomme ni Envoy Gateway ni le contrôleur de GKE : ils vivent dans les couches `local` et `gcp` du blueprint et au catalogue (principe II). Brique abstraite : `gateway`. Que la spec la déclare ou qu'elle découle de la cible (`declared_by` de l'ADR-009) se fixe en phase 3, avec le schéma de spec.

Restent hors de cette décision : les certificats réels du projet (cert-manager ou équivalent, avec [SECU]) ; la classe GKE, une adresse IP statique et le dimensionnement sur `gcp` ([OPS], [FINOPS]) ; les ports de l'hôte, fixés en phase 3 sous la condition 1 de l'ADR-004 ; la solution de R-25 ([OPS], BENCH-005) ; le maillage de services ; Windows (Q5).

### Complément du 2026-11-25 : le contrôleur ne surveille que les namespaces du projet

Décidé par le DSI sur la relecture [SECU] de l'étape 7 du golden repo (écart 43 de [specs/001-golden-repo-saas-b2b/tasks.md](../../specs/001-golden-repo-saas-b2b/tasks.md)). Rendu avec les seuls réglages de la section « Versions et condensats », le chart `gateway-helm` donne au contrôleur un ClusterRole qui lit les Secrets de tout le cluster et peut modifier tous ses pods. La couche `local` ajoute donc un troisième réglage : `config.envoyGateway.provider.kubernetes.watch`, de type `Namespaces`, avec pour liste le namespace du contrôleur et celui de l'application (`envoy-gateway-system` et `saas-b2b` dans le golden repo). Le chart rend alors un Role et un RoleBinding dans chacun des deux, et le ClusterRole ne garde que les nœuds, les namespaces, les GatewayClass et les `ServiceImport`. Le namespace du contrôleur est dans la liste parce que l'EnvoyProxy de la GatewayClass y vit, et que le contrôleur ne lit l'EnvoyProxy que dans les namespaces surveillés. Le type `NamespaceSelector` est écarté : le chart garde alors le ClusterRole complet.

Il reste au contrôleur, dans le namespace de l'application, la lecture des Secrets, dont la Gateway a besoin pour le certificat de l'écouteur HTTPS, et la modification des pods, par la règle de l'injecteur de topologie. Contrôle : S22 refuse un rendu sans ce réglage, avec une autre liste, ou dont un ClusterRole donne un droit sur les Secrets ou sur les pods. Les faits, la commande de rendu et l'essai sur kind du 2026-11-25 sont au point RS-02 de [research.md](../../specs/001-golden-repo-saas-b2b/research.md). Le blueprint reprend le réglage en phase 3, la liste suivant le nom du projet.

### Complément du 2026-11-26 : l'image du proxy est fixée dans l'EnvoyProxy

Décidé par le DSI sur la raison de [SECU] (écarts 98, 110 et 111 de [specs/001-golden-repo-saas-b2b/tasks.md](../../specs/001-golden-repo-saas-b2b/tasks.md)). Le tableau de la section « Versions et condensats » donne le proxy comme la valeur par défaut compilée dans le binaire 1.10.0. Cette valeur porte déjà son condensat (`DefaultEnvoyProxyImage`, `shared_types.go` au tag v1.10.0), et le proxy n'était donc pas tiré par tag. La couche `local` l'écrit malgré tout dans l'`EnvoyProxy`, au champ `spec.provider.kubernetes.envoyDeployment.container.image`, par tag et condensat de l'index : le dépôt nomme l'image qui tourne, l'inventaire du scan la lit dans ce fichier, et Renovate en suit le condensat. Le tag, qu'il ne sait pas ordonner, change à la main avec chaque version d'Envoy Gateway, dans la PR du contrôleur et des charts.

Le fichier ne fixe que cette image : S05 refuse un autre champ sous `envoyDeployment`, un autre champ du conteneur, une image sans condensat ou hors de `docker.io/envoyproxy/envoy`. E03 relit l'`EnvoyProxy` du cluster et l'image du pod du proxy. La condition de mise à jour 2 s'étend : le tag de cette image se déplace avec le contrôleur, et le job `envoy-render` le garde. Le champ prime sur le défaut compilé : le job lit `DefaultEnvoyProxyImage` dans `shared_types.go` au tag du contrôleur vendu et échoue, en nommant les deux valeurs, si la référence de l'`EnvoyProxy` diffère ; il est un contrôle requis du ruleset de `main`. Les lectures du code d'Envoy Gateway et de Renovate sont au point RS-02 de [research.md](../../specs/001-golden-repo-saas-b2b/research.md).

## Conséquences

### Positives

- Le même manifest Gateway et HTTPRoute, à la ligne `gatewayClassName` près (`diff` de 2 lignes), est accepté, programmé, et répond en HTTP et en HTTPS sur `127.0.0.1` (M7). Sur GKE, la classe `gke-l7-global-external-managed` accepte des écouteurs HTTP et HTTPS, des `certificateRefs` vers des Secrets et des HTTPRoute.
- La configuration kind de l'ADR-004 ne change que par deux `extraPortMappings` en boucle locale. kind garde son CNI et kube-proxy, et reste proche d'un Kubernetes amont.
- La plate-forme démarre en 44,6 s à chaud, sous le seuil de 90 s, et en 75,9 s quand les images de la gateway manquent au nœud.
- Le contrôleur est cantonné à son namespace pour ce qu'il crée, et n'ajoute aucun socket dans le nœud. Côté poste, rien d'autre que `127.0.0.1` n'est publié (M8).
- Gouvernance ouverte : sous-projet de l'organisation Envoy, couvert par la CNCF au titre d'Envoy (gradué le 2018-11-28), 10 mainteneurs d'au moins six employeurs déclarés. 31 releases stables et 1 075 commits humains par 211 auteurs en douze mois.
- 17 avis de sécurité en douze mois, chacun avec sa version corrigée publiée au plus tard le jour de l'avis, et aucun sur 1.10.0. Contrôleur et proxy figés par condensat.
- Les notes de Gateway API v1.7.0 font passer Envoy Gateway en « Conformant ».
- Sur GCP, le choix local ne change rien à la facture : le contrôleur de GKE est sans surcoût, et seules les ressources Compute Engine qu'il crée sont facturées.

### Négatives

- La plate-forme de base télécharge 505,8 Mo à la première création en amd64, 1,2 % au-dessus du seuil de 500 Mo, et 466,5 Mo en arm64. À 10 Mbit/s utiles, une hypothèse, c'est 45 % du budget de 900 s d'ENF-01, avant les images de la stack. La création à froid jusqu'à la première réponse prend environ 123 s, calcul de [FINOPS] qui combine BENCH-003 et BENCH-004. R-04 passe en probabilité forte, décision du DSI confirmée par Lucas à la GATE 1.
- La mémoire au repos monte à 948,8 Mio en médiane, et l'exécution 1 a dépassé le seuil (1 078,3 Mio). Les CRD d'Envoy Gateway pèsent plus que son contrôleur et son proxy réunis (99,7 Mio) : le serveur d'API passe de 231,5 à 469,6 Mio en médiane, les deux tiers des 357,2 Mio qui séparent la plate-forme de kind seul.
- Chaque création interroge Docker Hub pour les 2 images de la gateway, même préchargées, et Docker Hub compte un GET de manifest comme un tirage. R-25 passe en probabilité forte, décision du DSI confirmée par Lucas à la GATE 1.
- Par défaut, le chart désigne le contrôleur par tag et installe des CRD Gateway API v1.6.1 du canal expérimental. Une valeur oubliée dans le blueprint réintroduit l'un ou l'autre sans erreur, d'où le contrôle de la condition 1.
- Les trois premiers auteurs, tous chez Tetrate, font 51 % des commits humains de l'année. Le fichier de gouvernance donne aux sièges du comité de pilotage une fin au 2025-12-30, et n'a pas changé depuis le 2025-03-04.
- Le plus jeune des trois, en 1.x depuis le 2024-03-13. Chaque mineure n'est maintenue qu'environ neuf mois : une montée de mineure à la main au moins à ce rythme.
- Gateway API v1.7.0 dépasse la version testée par Envoy Gateway 1.10 (v1.6.1) et celles que sert GKE (v1.5.0 à v1.6.0). Le README liste l'écart, et la condition 5 garde la couche commune dans ce que GKE sert.
- Le contrôleur lit tous les Secrets du cluster, comme les deux autres options : compromis, il lirait les mots de passe locaux de la base et du cache (R-20, « Identifiants par défaut dans le golden repo »).
- Les NodePort de la gateway restent joignables sur l'adresse du nœud depuis le réseau Docker `kind`. Ce point est déduit de la documentation de kube-proxy, pas essayé.
- Une CVE élevée attend son correctif (CVE-2026-97054), et le délai de 7 jours laisse un projet généré exposé au moins une semaine après chaque avis (question 1).
- Les mesures viennent d'un seul poste, sous macOS avec OrbStack, moteur non libre (R-26), et le préchargement n'a été mesuré qu'avec le magasin d'images classique du moteur.

### Effet sur les cibles hors MVP

La porte reste ouverte. La couche commune ne contient que des objets Gateway API du cœur, et Envoy Gateway ne vit que dans la couche `local`. Une cible AWS ou Azure ajoutera sa couche, avec son service managé et le nom de sa classe. Qu'AWS et Azure proposent un service managé qui implémente Gateway API n'a pas été vérifié pour cet ADR ; sans lui, la couche commune ne suffirait plus et la décision se rouvrirait. Une cible on-prem serveurs aurait sa propre ligne au catalogue, choisie par son benchmark.

### Suites

- Entrée de catalogue `gateway`, à ajouter dans une PR qui suit la GATE 1 : `targets.local` de type `oss`, `targets.gcp` de type `managed` (section « Entrée au catalogue »). Les condensats du tableau « Versions et condensats » vivent dans le blueprint, pas dans l'entrée : l'ADR-009 exclut du catalogue les condensats d'images, et son champ `artifacts` ne vise que des binaires par plateforme. Les suites de BENCH-004 les plaçaient dans l'entrée ; l'ADR-009 l'emporte s'il est validé.
- Essais de R-25 par [OPS], avant le golden repo (condition 4).
- Politique conftest ou Kyverno sur le groupe `gateway.envoyproxy.io` (condition 2), et contrôles des conditions 1 et 5, pour [SECU] et [QA].
- Deux exécutions à chaud de plus pour Envoy Gateway (`OPTIONS=envoy-gateway`, `RUNS`), pour trancher le seuil de mémoire ([BENCH]).
- Pour [OPS] : vérifier si `gateway-crds-helm` peut n'installer que les CRD d'Envoy Gateway dont le blueprint se sert, et mesurer l'effet sur le serveur d'API. Écrire l'activation de Gateway API dans la couche OpenTofu de l'ADR-008.
- Pour [OPS], en phase 3 : livrer les charts rendus et versionnés dans le blueprint, ou faire de Helm un prérequis du poste. [ARCHI] penche pour le rendu versionné : Helm resterait hors des prérequis de US-001, et conftest verrait chaque objet. BENCH-004 a installé Helm 4.3.2 pour ses seules mesures.
- Pour [SECU] : sur GKE, appliquer la Gateway crée un équilibreur facturé. Le principe X et US-006 veulent que l'agent ne puisse pas lancer une telle action. `.claude/settings.json` du générateur ne filtre aucune commande `kubectl`, et le blocage de US-006 devra couvrir ce cas.

### Questions ouvertes

1. Correctifs de sécurité sans le délai de 7 jours, pour Lucas. [SECU] le propose : Traefik a publié 6 avis en novembre 2026, et le constat vaut pour les trois options en proportion de leurs avis ; avec le délai, un projet généré reste exposé au moins une semaine après chaque avis. Le délai vient du principe VI de la constitution (« Les mises à jour automatiques attendent qu'une version soit publiée depuis au moins 7 jours »), qu'ENF-03 applique au projet généré et que `CLAUDE.md` reprend. Une exception passe donc par un amendement de la constitution, ou par une dérogation écrite dans un ADR avec sa durée et sa condition de levée. Avis de [ARCHI] : favorable, par amendement, parce que la question se posera pour chaque brique, et à condition que la PR de sécurité passe toute la matrice. [OPS] vérifie la syntaxe sur la documentation de Renovate. Jusqu'à la décision, le délai s'applique.
2. Périmètre de la plate-forme de base dans `docs/benchmarks/TEMPLATE.md`, pour Lucas. Règle provisoire du DSI jusqu'à la GATE 1 : la plate-forme de base (kind, CRD Gateway API, gateway) se compte contre les 500 Mo, et chaque couche suivante contre ses propres seuils, avec le cumul en sensibilité. Sans périmètre fermé, chaque benchmark trouverait la barre plus proche, et l'ordre des benchmarks déciderait des notes ([FINOPS]). Lue sur la gateway seule, la condition de volume ne retirerait de cran à personne : 88, 83 et 78. La même reprise dans le gabarit porte sur l'architecture du volume, notée sur linux_amd64 par décision du DSI. Les seuils des couches suivantes s'écrivent avant les mesures de BENCH-005.
3. Dépendance à l'ADR-009, pour Lucas. La ligne `gcp` repose sur sa lecture des principes III et V. Lue à la lettre, chaque service managé dérogerait à V, et cet ADR devrait porter la justification du contrôleur de GKE. Si V primait, Envoy Gateway sur GKE passerait devant le service managé, contre le texte de III.

### Réponses de la GATE 1 (2026-11-20)

- Correctifs de sécurité (question 1) : Lucas amende le principe VI. Un
  correctif de sécurité passe sans le délai de 7 jours si sa PR passe toute la
  matrice (constitution 1.2.0, PR #24).
- Périmètre de la plate-forme de base (question 2) : la règle provisoire entre
  dans le gabarit de benchmark, avec la lecture du volume sur linux_amd64
  (PR #25).
- Lecture des principes III et V (question 3) : Lucas retient celle de
  l'ADR-009. III fixe les candidats d'une cible, V départage. La ligne `gcp`
  tient.

## Conformité à la constitution

Vérifiée contre la [constitution](../../.specify/memory/constitution.md) en version 1.0.0. L'amendement 1.1.0 (PR #13) ne touche que la section « Périmètre du MVP ».

| Principe | Effet | Justification |
| --- | --- | --- |
| I. Rien sans test automatique | respecté | La matrice porte les contrôles des conditions 1, 2, 4 et 5, la CI la vérification de signature de la condition 3, en plus du démarrage local |
| II. Spec abstraite, catalogue concret | respecté | Envoy Gateway n'apparaît que dans la couche `local` et au catalogue, la classe de GKE dans la couche `gcp` ; la couche commune ne porte que des objets Gateway API du cœur, et la condition 5 le vérifie |
| III. Managé sur le cloud, open source ailleurs | respecté | Sur `local`, Envoy Gateway est sous Apache-2.0 et gratuit ; sur `gcp`, le contrôleur de GKE est le service managé, dans la lecture de l'ADR-009 validée par Lucas à la GATE 1 |
| IV. Catalogue traçable | respecté | Les deux lignes de l'entrée portent licence, gouvernance, statut, date et source ; l'entrée s'écrit dans une PR qui suit la GATE 1 |
| V. Gouvernance ouverte d'abord | respecté | Sur `local`, projet couvert par la CNCF au titre d'Envoy, avec au moins six employeurs parmi les mainteneurs, et l'option à éditeur unique est écartée. Sur `gcp`, service managé imposé par III, sans justification à fournir (gabarit d'ADR, ADR-009) |
| VI. Récent mais éprouvé | respecté | Aucun critère éliminatoire touché : Apache-2.0, dépôt actif, 1.10.0 du 2026-11-06 publiée depuis plus de 7 jours ; la réserve sur la jeunesse du projet est écrite |
| VII. Une commande pour démarrer | respecté | `task up` installe CRD, charts et objets depuis des fichiers versionnés ; la dépendance au registre à chaque création est traitée par la condition 4 |
| VIII. Aucun fait de mémoire | respecté | Les faits renvoient à BENCH-004, à son script et à l'API des releases lue le 2026-11-19 ; sont signalés comme non vérifiés la commande cosign, la configuration de Renovate, l'activation de Gateway API en OpenTofu, la joignabilité des NodePort et l'offre Gateway API d'AWS et d'Azure |
| IX. Aucun secret dans le dépôt | respecté | La configuration de la gateway ne porte aucun secret ; les certificats du projet restent hors de cette décision et ne seront pas versionnés (US-012) |
| X. Aucune dépense cloud sans accord | respecté | Aucune ressource GCP créée pour BENCH-004 ni pour cet ADR. Sur GKE, appliquer la Gateway crée un équilibreur facturé : cette action relève du principe X au même titre que `tofu apply`, et revient à l'utilisateur (US-006) |

### Dérogations

Aucune.

## Entrée au catalogue

Brique abstraite : `gateway`, nom proposé par le DSI, à confirmer en phase 3 avec le schéma de spec. L'entrée s'écrit au format de l'ADR-009, dans une PR qui suit la GATE 1.

| Cible | Service | Type | Licence | Gouvernance | Statut | Vérifié le | Source |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `local` | Envoy Gateway 1.10.0, charts `gateway-helm` et `gateway-crds-helm` v1.10.0 | `oss` | Apache-2.0 | Fondation : CNCF au titre d'Envoy (gradué le 2018-11-28), sans revue CNCF propre ; organisation `envoyproxy` | actif | 2026-11-19 | <https://github.com/envoyproxy/gateway>, <https://gateway.envoyproxy.io/news/releases/matrix/> |
| `gcp` | Contrôleur Gateway de GKE, classe à fixer par [OPS] | `managed` | service propriétaire du fournisseur | Éditeur unique : Google | actif | 2026-11-19 | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/gateway-api> |

Les deux lignes exposent le standard `gateway-api`, présent dans la liste fermée de la PR #15. La ligne `gcp` n'a pas de `managed_gap`. Pour `last_release_on` de la ligne `local`, la dernière release du projet est 1.9.4, du 2026-11-17 ; la version retenue, 1.10.0, est du 2026-11-06. La ligne `gcp` garde en `pending` le choix de la classe et l'activation de Gateway API dans la couche OpenTofu ([OPS]).

## Condition de révision

Bascule par un nouvel ADR qui remplace celui-ci si Envoy Gateway touche un critère éliminatoire : dépôt archivé ou en maintenance, licence qui n'est plus open source, ou aucune release pendant 12 mois. Le décompte part de la dernière release du projet, 1.9.4 du 2026-11-17.

La décision se rouvre, sans basculer d'office, dans ces cas :

- Lucas ne retient pas la lecture des principes III et V de l'ADR-009 (question 3) ;
- les deux exécutions de plus placent la mémoire d'Envoy Gateway au-dessus du seuil, et un cran de gouvernance revient à Cilium : égalité à 84 ;
- aucune piste de R-25 ne fait passer le test de recréation hors ligne (condition 4) ; l'ADR-004 se rouvre alors aussi ;
- aucune signature du contrôleur n'est vérifiable (condition 3) ;
- un besoin de sécurité ne s'exprime qu'avec une politique du groupe `gateway.envoyproxy.io` (condition 2) ;
- Envoy Gateway quitte l'organisation Envoy ;
- une cible hors MVP est ouverte.

Une montée de mineure d'Envoy Gateway ou de version des CRD ne rouvre pas cet ADR : la règle de mise à jour s'applique. Sans l'un de ces faits, prochaine vérification le 2027-05-05, fin de maintenance d'Envoy Gateway 1.10, date proposée par BENCH-004.

## Sources

Ce que BENCH-004 établit se cite par lui ; ses propres sources sont dans sa section 9.

| Source | Lue le | Ce qu'elle établit |
| --- | --- | --- |
| [BENCH-004](../benchmarks/BENCH-004-gateway.md), sections 1 à 3 | 2026-11-19 | Question posée ; options et versions examinées ; versions de Gateway API d'après les rapports de conformité, GKE compris ; critères éliminatoires |
| BENCH-004, section 4 | 2026-11-19 | Seuils écrits avant la mesure et périmètre de la plate-forme de base ; mesures M0 à M8 : démarrage, mémoire, volumes, tirages à chaque création et leur cause, contrôles fonctionnels, adresses d'écoute |
| BENCH-004, sections 5 et 6 | 2026-11-19 | Notes et justifications ; gouvernance, avis de sécurité, signatures, compatibilité de 1.10 ; capacités de la classe GKE ; coût du contrôleur de GKE ; grille et totaux 86, 81 et 78 |
| BENCH-004, section 7 | 2026-11-19 | Verdict, sensibilité, réserves, changements à la configuration kind, conditions de [SECU], suites, prochaine vérification au 2027-05-05 |
| BENCH-004, sections 8 et 10 | 2026-11-19 | Limites ; avis de [SECU] (Trivy, CVE-2026-97054, lecture des Secrets, NodePort) et de [FINOPS] (volume en amd64, Gateway facturée sur GKE, plancher mémoire, R-04) |
| `tests/bench/bench-004-gateway.sh`, lignes 71 à 94, 315 à 348 et 620 à 633 | 2026-11-19 | Condensats complets ; EnvoyProxy et GatewayClass locales ; réglages `crds.envoyGateway.enabled`, `crds.gatewayAPI.enabled`, `crds.enabled` et `global.images.envoyGateway.image` |
| <https://api.github.com/repos/envoyproxy/gateway/releases?per_page=6> | 2026-11-19 | Releases les plus récentes : v1.9.4 le 2026-11-17, v1.10.0 le 2026-11-06 ; aucune release 1.10.x après 1.10.0 |
| [ADR-009](ADR-009-catalogue.md) et [`catalog/README.md`](../../catalog/README.md) | 2026-11-19 | Lecture proposée des principes III et V ; option de BENCH-004 valable pour `local`, et pour `gcp` seulement avec un `managed_gap` ; types `oss` et `managed` ; `declared_by` ; condensats d'images hors du catalogue ; `artifacts` réservé aux binaires par plateforme ; `last_release_on` ; standard `gateway-api` |
| [ADR-004](ADR-004-cluster-local.md), conditions 1, 3, 4 et 7, règle de version | 2026-11-19 | Boucle locale ; images par condensat ; manifests tiers versionnés avec leur SHA-256 ; recréation hors ligne ; mineure 1.36 |
| [ADR-008](ADR-008-modules-opentofu-gcp.md), proposé | 2026-11-19 | Cluster GKE Autopilot de la couche `gcp` ; gateway hors de sa portée |
| [docs/prd-mvp.md](../prd-mvp.md), section 1, US-001, US-005, US-006, US-012, ENF-01, ENF-02, ENF-03, Q5 | 2026-11-19 | Envoy Gateway pressenti ; prérequis ; démarrage en une commande et profils ; aucune ressource payante lancée par l'agent ; aucun secret ; budget de 15 minutes ; parité ; délai de publication ; systèmes visés |
| [docs/risques.md](../risques.md), R-04, R-05, R-15, R-20, R-25, R-26 | 2026-11-19 | Déclencheur de R-04 et probabilités forte de R-04 et R-25, à confirmer ; équilibreurs nés de Kubernetes hors de l'état OpenTofu ; pistes et reculs refusés de R-25 |
| [Constitution](../../.specify/memory/constitution.md), version 1.0.0 | 2026-11-19 | Principes I à X ; délai de 7 jours du principe VI ; amendement et dérogation |
| [docs/benchmarks/TEMPLATE.md](../benchmarks/TEMPLATE.md), section 5.6 | 2026-11-19 | Règle d'empreinte et seuils de BENCH-003 ; le gabarit ne fixe ni le périmètre ni l'architecture du volume |
| `.claude/settings.json` | 2026-11-19 | Aucune règle sur `kubectl` |
| Décisions du DSI du 2026-11-19, reprises dans `docs/risques.md` (R-04, R-25) et BENCH-004 (section 4.1) | 2026-11-19 | R-04 et R-25 en probabilité forte, confirmés à la GATE 1 ; règle provisoire de la plate-forme de base |
| Chart et code d'Envoy Gateway v1.10.0, rendu par condensat et essai sur kind, au point RS-02 de [research.md](../../specs/001-golden-repo-saas-b2b/research.md) | 2026-11-25 | Complément du 2026-11-25 : réglage `watch` du contrôleur, droits qui restent |
