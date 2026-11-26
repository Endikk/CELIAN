# Research: golden repo SaaS B2B

Phase 0 du plan ([plan.md](plan.md)). Rédigé par [DEV] le 2026-11-21, mis à jour le 2026-11-23 après l'amendement de la spec (PR #39) et les décisions du 2026-11-21 et du 2026-11-23 (tableau « Décisions prises depuis la première version » du plan).

Pour RS-01 à RS-21, aucune recherche nouvelle sur Internet n'a été faite : chaque fait vient d'un ADR, d'un benchmark, du catalogue ou d'un script de benchmark versionné, avec sa date de lecture d'origine. RS-22 à RS-24 s'appuient en plus sur des pages officielles lues le 2026-11-23, citées avec leur adresse. Ce qui manque est écrit « à vérifier », avec son porteur et l'étape qu'il bloque. Les choix déjà faits par les ADR-004 à ADR-012 ne sont pas rouverts ; les points ci-dessous fixent ce que ces ADR laissaient au golden repo.

Format de chaque point : décision, pourquoi, alternatives écartées, sources.

## RS-01. Arborescence et carte des couches

Décision : une couche de cible tient dans un dossier, `golden/saas-b2b/local/` ou `golden/saas-b2b/gcp/`. Tout le reste est commun : code de l'application, base et overlays Kustomize, conventions Git, README, politiques et tests communs. Le détail est dans [contracts/layers.md](contracts/layers.md).

Pourquoi : le principe II veut qu'un service propre à une cible ne vive que dans sa couche, et la phase 3 devra rendre chaque couche selon les cibles choisies. Un dossier par couche rend ce rendu trivial (un dossier conditionnel) et rend la règle vérifiable par un test de chemins. Les ADR-006 et ADR-010 renvoient l'arborescence exacte à la phase 3 ; le golden repo doit pourtant en avoir une, et celle-ci garde leurs contenus par couche.

À vérifier avant l'étape 7 : les composants de Kustomize, qui portent la couche de cible au-dessus d'un overlay d'environnement, sur la documentation de Kustomize et dans la version qu'embarque kubectl. À défaut, une composition par ressources garde le même découpage. Porteur : [DEV].

Alternatives : `blueprints/saas-b2b/{common,local,gcp}` reproduit dans le golden repo, écarté parce qu'un projet qui marche n'a pas trois racines ; `k8s/app/` et `k8s/local/` de l'essai de BENCH-005, gardés dans l'esprit (`k8s/` commun, `local/k8s/` de cible) mais complétés par les overlays par environnement de l'ADR-010.

Sources : constitution 1.2.0, principe II ; ADR-006, « Répartition par couche » ; ADR-010, « Répartition par couche » et condition 1 ; CLAUDE.md, arborescence.

### Relevé du 2026-11-25 : composants de Kustomize (T052, étape 7)

Fait par [OPS]. Guide de Kustomize, code de son API et `go.mod` de Kubernetes lus par `gh api` ou WebFetch, puis un essai sur le poste.

Les composants tiennent, et la composition par ressources n'est pas nécessaire. Le guide des composants donne leur forme : un dossier dont le `kustomization.yaml` déclare `apiVersion: kustomize.config.k8s.io/v1alpha1` et `kind: Component`, cité par le champ `components:` d'un overlay ; « As of `v3.7.0` Kustomize supports a special type of kustomization ». Ses exemples montrent un composant qui génère des objets et corrige ceux de la base, ce que fera le composant de cible. Le code de l'API au tag `api/v0.21.1` fixe ces deux valeurs (`api/types/kustomization.go`, lignes 20 et 21), le champ `Components` (ligne 127), et refuse un autre `apiVersion` pour un composant (ligne 331).

Version embarquée : le `go.mod` de Kubernetes v1.36.6, le kubectl de la CI, comme celui de v1.37.1, le kubectl du poste, requiert `sigs.k8s.io/kustomize/kustomize/v5 v5.8.1` et `sigs.k8s.io/kustomize/api v0.21.1` ; `kubectl version --client` du poste affiche « Kustomize Version: v5.8.1 ».

Essai sur le poste, hors du dépôt, avec ce kubectl : une base qui déclare une Gateway et son `namespace`, un overlay qui la reprend, un composant qui remplace `spec.gatewayClassName` par un correctif JSON et génère un ConfigMap, et une composition `resources: [../overlay]` plus `components: [../component]`. `kubectl kustomize` rend la Gateway corrigée et le ConfigMap. Deux points pour l'étape 8 : le ConfigMap généré porte un suffixe de hachage, et il ne reçoit pas le `namespace` de la base, posé dans un autre dossier ; le composant ou la composition doit donc nommer le namespace, et `app-config` désactiver le suffixe s'il doit garder son nom.

Effet : l'étape 7 écrit `k8s/base/` et `k8s/overlays/local/`, sans composant. L'étape 8 écrit `local/k8s/component/` en composant et `local/k8s/lite/` en composition (T070).

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://kubectl.docs.kubernetes.io/guides/config_management/components/> | 2026-11-25 | Forme d'un composant, champ `components:`, prise en charge depuis Kustomize 3.7.0 |
| <https://github.com/kubernetes-sigs/kustomize/blob/api/v0.21.1/api/types/kustomization.go> | 2026-11-25 | Lignes 20, 21, 127 et 331 : `ComponentVersion`, `ComponentKind`, `Components`, `apiVersion` exigé |
| <https://github.com/kubernetes/kubernetes/blob/v1.36.6/go.mod> | 2026-11-25 | Kustomize v5.8.1 et son API v0.21.1, dans kubectl v1.36.6 |
| <https://github.com/kubernetes/kubernetes/blob/v1.37.1/go.mod> | 2026-11-25 | Les mêmes versions dans kubectl v1.37.1 |
| `kubectl kustomize`, kubectl v1.37.1 sur le poste | 2026-11-25 | Composant appliqué au-dessus d'un overlay ; suffixe et namespace du ConfigMap généré |

## RS-02. Routage sous une seule origine

Décision : une Gateway à deux écouteurs (HTTP et HTTPS) et deux HTTPRoute. Le préfixe `/api` va à l'API, `/` au front. L'API sert ses routes sous `/api` elle-même. Le front appelle des chemins relatifs.

Pourquoi : une seule origine supprime CORS et toute configuration d'adresse dans le front. L'absence de réécriture de chemin garde la couche commune dans les champs que GKE sert (ADR-005, condition 5). Le manifest mesuré par BENCH-004 n'avait qu'une règle sans correspondance de chemin : que la correspondance par préfixe de chemin fasse partie du cœur de Gateway API, et qu'elle soit servie par le contrôleur de GKE, est à vérifier sur la spécification de Gateway API v1.7.0 et sur la page de GKE avant l'étape 7.

Alternatives : deux noms d'hôte (`api.` et front), écarté parce que la résolution de noms locaux dépend du système du poste et n'a pas été relevée ; deux Gateway, refusé par l'ADR-005 (une seule Gateway, et chacune crée un équilibreur facturé sur GKE).

Sources : ADR-005, décision, condition 5 et réserves de [FINOPS] ; `tests/bench/bench-004-gateway.sh`, lignes 400 à 470.

### Relevé du 2026-11-25 : préfixe de chemin, chez Gateway API et chez GKE (T053, étape 7)

Fait par [OPS]. Code de Gateway API au tag v1.7.0, lu par `gh api`, et page des capacités des GatewayClass de GKE, lue par WebFetch.

Cœur de Gateway API. `apis/v1/httproute_types.go` au tag v1.7.0 range `PathPrefix` dans le cœur : « "Exact" - Core », « "PathPrefix" - Core », « "RegularExpression" - Implementation Specific » (lignes 504 à 506), et le champ `path` de la correspondance porte « Support: Core (Exact, PathPrefix) » (ligne 568), `PathPrefix` par défaut. La correspondance se fait élément par élément : « the paths `/abc`, `/abc/`, and `/abc/def` would all match the prefix `/abc`, but the path `/abcd` would not » (lignes 529 à 536). `/api` ne prend donc pas `/apiary`, et `/` prend tout le reste. Une règle dont toutes les `backendRefs` sont invalides, un Service absent par exemple, répond 500 (lignes 279 à 290) ; E03 s'en sert à l'étape 7, avant que les Services existent. `allowedRoutes` d'un écouteur est du cœur, et vaut par défaut `{namespaces: {from: Same}}` (`apis/v1/gateway_types.go`, lignes 480 et 481).

GKE. La page des capacités donne pour `gke-l7-global-external-managed`, champ `spec.rules` des HTTPRoute, `path.type` « Exact, PathPrefix, RegularExpression », et « Prefix, exact match or regular expression » pour le routage par hôte et chemin. Elle donne Gateway API 1.5.0 à partir de GKE 1.35.2-gke.1842000, comme l'ADR-005. La page n'affiche pas de date de mise à jour.

Conclusion : la HTTPRoute `api` sur le préfixe `/api` et la HTTPRoute `front` sur `/` n'emploient que des champs du cœur que GKE sert. S07 et S08 le reverront sur le rendu `gcp` (étapes 9 et 14).

Namespace de l'application (T060). La page de Pod Security Admission donne le gabarit `pod-security.kubernetes.io/<MODE>: <LEVEL>`, `<MODE>` parmi `enforce`, `audit` et `warn`, `<LEVEL>` parmi `privileged`, `baseline` et `restricted` ; l'étiquette `<MODE>-version` est facultative, et prend une mineure de Kubernetes ou `latest`. `k8s/base/namespace.yaml` pose `pod-security.kubernetes.io/enforce: restricted`, sans version.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://github.com/kubernetes-sigs/gateway-api/blob/v1.7.0/apis/v1/httproute_types.go> | 2026-11-25 | Lignes 504 à 506 et 568 : `PathPrefix` du cœur ; lignes 529 à 536 : élément par élément ; lignes 279 à 290 : 500 sur une `backendRef` invalide |
| <https://github.com/kubernetes-sigs/gateway-api/blob/v1.7.0/apis/v1/gateway_types.go> | 2026-11-25 | Lignes 480 et 481 : `allowedRoutes` du cœur, `Same` par défaut |
| <https://docs.cloud.google.com/kubernetes-engine/docs/how-to/gatewayclass-capabilities> | 2026-11-25 | `gke-l7-global-external-managed` : `Exact`, `PathPrefix`, `RegularExpression` ; Gateway API 1.5.0 à partir de 1.35.2-gke.1842000 |
| <https://kubernetes.io/docs/concepts/security/pod-security-admission/> | 2026-11-25 | Étiquettes `pod-security.kubernetes.io/<MODE>` et `<MODE>-version`, niveaux et modes |

### Relevé du 2026-11-25 : Gateway API et Envoy Gateway vendorés (T058, étape 7)

Fait par [OPS]. API des releases et code d'`envoyproxy/gateway` et de `kubernetes-sigs/gateway-api`, lus par `gh api` ; API de Docker Hub, lue par WebFetch ; `docker buildx imagetools inspect`, buildx 0.37.2, en lecture seule ; Helm v4.3.2 sur le poste, la version de BENCH-004.

Versions. Les valeurs du tableau « Versions et condensats » de l'ADR-005 tiennent. Envoy Gateway n'a publié aucune release 1.10.x après 1.10.0 (2026-11-06) ; la plus récente reste 1.9.4 (2026-11-17), d'une mineure antérieure. Gateway API v1.7.0 (2026-10-29, release immuable) reste la dernière. Sur Docker Hub, `tag_last_pushed` donne 2026-11-06 pour `envoyproxy/gateway:v1.10.0`, `envoyproxy/gateway-helm:v1.10.0` et `envoyproxy/gateway-crds-helm:v1.10.0`, et 2026-10-27 pour `envoyproxy/envoy:distroless-v1.40.2` : plus de 7 jours le 2026-11-25 (principe VI). CVE-2026-97054 reste sans release corrigée.

CVE-2026-97054, relevé de [SECU] du 2026-11-25 : la base de Trivy la classe désormais MEDIUM (Red Hat, CVSS 5,9), et non plus HIGH comme à la rédaction de l'ADR-005. Au seuil `HIGH` de RS-23, le scan ne la relève donc plus, et l'exception que l'ADR-005 attendait n'a plus lieu d'être tant que la classe ne remonte pas. Ni l'ADR-005 ni RS-23 ne sont modifiés ici : [SECU] relit la classe au premier passage du scan (T118).

Relecture [SECU] de la PR de l'étape 7, relevé du 2026-11-25 : l'étiquette `pod-security.kubernetes.io/enforce: restricted` sur `envoy-gateway-system` tient. `PROFILE=lite task test:e2e` sur kind (Docker 29.8.2, nœud v1.36.4) passe avec elle : le contrôleur, certgen et le proxy sont admis, la Gateway devient `Programmed` et E03 ne relève aucun événement `FailedCreate` « violates PodSecurity ». `baseline` n'est donc pas retenu. Les champs du réglage `watch` du contrôleur (écart 43) viennent de <https://raw.githubusercontent.com/envoyproxy/gateway/v1.10.0/api/v1alpha1/envoygateway_types.go>, lu le 2026-11-25.

Sommes et condensats, relus le 2026-11-25 :

| Élément | Lu | Égal à l'ADR-005 |
| --- | --- | --- |
| `standard-install.yaml` de v1.7.0, par `gh release download` | SHA-256 `4e2602c4cbe1afbc394d86f4ac6522e1a5263b01133bba1e40a6d1a549e753a1` | oui |
| `gateway-helm-v1.10.0.tgz`, par `helm pull oci://docker.io/envoyproxy/gateway-helm --version v1.10.0` | SHA-256 `0f72c9050c33dbaab39b865e8cb5ed77f263720b22368eda4ce687077649e659` ; manifeste OCI `sha256:dcb82a14c04b426615a71d97222c7edf9f5ff58b800d241e71ac5784ae6dc7b7`, le même que Docker Hub | oui |
| `gateway-crds-helm-v1.10.0.tgz`, de même | SHA-256 `cc213d9059d0391d69d70bef7c041fb1c1e45270c84a65988229bd88639d0aa5` ; manifeste OCI `sha256:475c39aad3a05e3974a29fb80cfefe882b743e45e2ec0f751790ff0cb83bfa5d`, le même que Docker Hub | oui |
| `docker.io/envoyproxy/gateway:v1.10.0` | index `sha256:c2243d43518bed91d3ed8c2db849a4b7a14ac9b96eb019f2ab104bb1ca8572b1`, linux/amd64 et linux/arm64 | oui |
| `docker.io/envoyproxy/envoy:distroless-v1.40.2` | index `sha256:09ca6f2140a61ad8df11779a4a30d52b48433d444466328494f9188c9c35eded`, linux/amd64 et linux/arm64 ; `DefaultEnvoyProxyImage` de `api/v1alpha1/shared_types.go` au tag v1.10.0 (ligne 30), par condensat | oui |

Rendu. Méthode de `tests/bench/bench-004-gateway.sh` (lignes 226 à 246 et 620 à 633), Helm dans des dossiers temporaires (`HELM_CACHE_HOME`, `HELM_CONFIG_HOME`, `HELM_DATA_HOME`), chaque archive vérifiée avant usage :

- `helm template eg-crds gateway-crds-helm-v1.10.0.tgz --set crds.envoyGateway.enabled=true --set crds.gatewayAPI.enabled=false` ;
- `helm template eg gateway-helm-v1.10.0.tgz -n envoy-gateway-system --set crds.enabled=false --set global.images.envoyGateway.image=<image du contrôleur par condensat>`. BENCH-004 installait ce chart par `helm install` ; le golden repo en garde le rendu, que `kubectl apply` applique.

Avec `--kube-version v1.36.4` ou sans, les deux rendus sont identiques octet pour octet. Le premier ne contient que 8 CRD du groupe `gateway.envoyproxy.io`, aucune de `gateway.networking.k8s.io`. Le second ne contient aucune CRD ; ses conteneurs (contrôleur, certgen) et le `shutdownManager` de sa configuration portent l'image du contrôleur par condensat. `standard-install.yaml` porte 10 CRD du groupe `gateway.networking.k8s.io`, chacune annotée `bundle-version: v1.7.0` et `channel: standard`, plus une `ValidatingAdmissionPolicy` et sa liaison.

Ce que le rendu change par rapport à `helm install` :

- Les objets marqués `helm.sh/hook` (comptes et droits de certgen, Job certgen, `MutatingWebhookConfiguration` de l'injecteur de topologie) sont appliqués avec les autres, dans l'ordre du fichier, où Helm les place après le reste. Le Job tourne sous un contexte du profil `restricted` et se supprime 30 s après sa fin (`ttlSecondsAfterFinished`) : chaque `task up` le recrée. `envoy-gateway certgen` ne remplace pas des certificats déjà présents sans `--overwrite`, absent par défaut (`internal/cmd/certgen.go`, lignes 60 et 117 à 137, au tag v1.10.0) : relancé, il ne change rien. Il écrit le `caBundle` de la `MutatingWebhookConfiguration`, que `kubectl apply --server-side` laisse à son gestionnaire. Le webhook a `failurePolicy: Ignore`.
- Aucun objet `Namespace` : la couche `local` déclare `envoy-gateway-system` à part, comme `--create-namespace` le faisait.
- La configuration du contrôleur (ConfigMap `envoy-gateway-config`) nomme `docker.io/envoyproxy/ratelimit:5ae0682e` par tag, sous `rateLimitDeployment`. Cette image ne tourne que si la limitation de débit est activée, par une clé `rateLimit` de cette configuration, absente du rendu. La condition 1 de l'ADR-005 demande de la figer « s'il active la limitation de débit » : S22 refuse le rendu si `rateLimit` apparaît sans image par condensat.

EnvoyProxy. `KubernetesServiceSpec` au tag v1.10.0 (`api/v1alpha1/shared_types.go`, lignes 329 à 400) accepte `type: NodePort` et un `patch` ; un `patch` sans `type` est une fusion stratégique (lignes 591 à 600). Aucun champ ne fixe un `nodePort` : le correctif de fusion le fait, comme dans BENCH-004. La fusion se fait sur la clé `port` de la liste des ports du Service (`patchMergeKey:"port"`), et un port absent du Service s'y ajouterait sans nom, alors qu'un Service à plusieurs ports doit les nommer tous (`staging/src/k8s.io/api/core/v1/types.go` de Kubernetes v1.36.6, lignes 5988 et 6231 à 6235). Tant que la Gateway n'a que l'écouteur HTTP, l'EnvoyProxy ne corrige donc que le port 80, et le port 443 entre avec l'écouteur HTTPS (seconde PR, T074). Le drapeau `EnvoyProxyPatch` qui applique ces correctifs est actif par défaut (`api/v1alpha1/envoygateway_types.go`, lignes 195 à 201) ; la documentation de `KubernetesPatchSpec` avertit que quiconque écrit l'EnvoyProxy peut poser n'importe quel champ sur une ressource que le contrôleur applique. La GatewayClass nomme `gateway.envoyproxy.io/gatewayclass-controller`, le `controllerName` de la configuration rendue.

Ce que les hooks du dépôt refusent. Le rendu des CRD fait 2,86 Mo et contient un tiret cadratin dans la description d'une CRD (`clienttrafficpolicies.gateway.envoyproxy.io`) ; `standard-install.yaml` a deux lignes qui finissent par une espace. Ce sont des octets de tiers, que `SHA256SUMS` vérifie : `local/vendor/` sort des hooks qui réécrivent, de `check-added-large-files` et de `no-em-dash`, à la racine de CELIAN et dans le golden repo (T057).

Suivi par Renovate. Renovate cherche les charts Helm d'un registre OCI par la source `docker` (`lib/modules/manager/helmv3/readme.md`, ligne 85, au tag 44.247.1). Les trois références, contrôleur et charts, sont écrites par tag et condensat dans `local/tasks/local.yml`, sous un commentaire `# renovate:` que lit le gestionnaire des images de la couche `local`, et entrent dans le groupe « Envoy Gateway » des deux `renovate.json`. Aucun gestionnaire nouveau, donc S23 ne change pas. Aucun Renovate n'a tourné sur ces lignes.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://api.github.com/repos/envoyproxy/gateway/releases?per_page=10> | 2026-11-25 | Aucune 1.10.x après 1.10.0 ; 1.9.4 la plus récente |
| <https://api.github.com/repos/kubernetes-sigs/gateway-api/releases?per_page=8> | 2026-11-25 | v1.7.0 dernière release, immuable |
| <https://hub.docker.com/v2/repositories/envoyproxy/gateway/tags/v1.10.0> | 2026-11-25 | Condensat `c2243d43`, poussé le 2026-11-06 |
| <https://hub.docker.com/v2/repositories/envoyproxy/gateway-helm/tags/v1.10.0> | 2026-11-25 | Condensat `dcb82a14`, poussé le 2026-11-06 |
| <https://hub.docker.com/v2/repositories/envoyproxy/gateway-crds-helm/tags/v1.10.0> | 2026-11-25 | Condensat `475c39aa`, poussé le 2026-11-06 |
| <https://hub.docker.com/v2/repositories/envoyproxy/envoy/tags/distroless-v1.40.2> | 2026-11-25 | Condensat `09ca6f21`, poussé le 2026-10-27 |
| `docker buildx imagetools inspect` sur les deux images | 2026-11-25 | Index et plateformes |
| <https://github.com/envoyproxy/gateway/blob/v1.10.0/api/v1alpha1/shared_types.go> | 2026-11-25 | Ligne 30 : image du proxy ; ligne 38 : `ratelimit` par condensat dans le binaire ; lignes 329 à 400 et 591 à 600 : Service et correctif |
| <https://github.com/envoyproxy/gateway/blob/v1.10.0/api/v1alpha1/envoyproxy_types.go> | 2026-11-25 | Ligne 676 : `envoyService` |
| <https://github.com/envoyproxy/gateway/blob/v1.10.0/api/v1alpha1/envoygateway_types.go> | 2026-11-25 | Lignes 195 à 201 : `EnvoyProxyPatch` actif par défaut |
| <https://github.com/envoyproxy/gateway/blob/v1.10.0/internal/cmd/certgen.go> | 2026-11-25 | Lignes 60 et 117 à 172 : pas de remplacement sans `--overwrite` ; `caBundle` du webhook |
| Archive `gateway-helm-v1.10.0.tgz`, `values.yaml` et `templates/` | 2026-11-25 | `global.images.ratelimit.image` par tag ; hooks ; webhook |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/modules/manager/helmv3/readme.md> | 2026-11-25 | Ligne 85 : charts OCI par la source `docker` |
| <https://github.com/kubernetes/kubernetes/blob/v1.36.6/staging/src/k8s.io/api/core/v1/types.go> | 2026-11-25 | Ligne 5988 : ports d'un Service fusionnés sur `port` ; lignes 6231 à 6235 : nom obligatoire au-delà d'un port |

### Relevé du 2026-11-25 : périmètre du contrôleur d'Envoy Gateway (écart 43, étape 8)

Fait par [OPS], avant que l'étape 8 dépose les identifiants de Postgres dans le namespace de l'application. Chart et code d'Envoy Gateway au tag v1.10.0 lus par `gh api` ; artefacts OCI des charts tirés par leur condensat ; rendu par Helm v4.3.2 ; essai sur kind (OrbStack, Docker 29.8.2, kind 0.33.0, nœud v1.36.4).

Le chart. `charts/gateway-helm/templates/envoy-gateway-rbac.yaml` (lignes 1 à 94) : quand `config.envoyGateway.provider.kubernetes.watch.namespaces` n'est pas vide, il rend, pour chaque namespace de la liste, un Role et un RoleBinding qui portent les droits de `eg.rbac.namespaced`, et ne laisse au ClusterRole que ceux de `eg.rbac.cluster` ; sans liste, un seul ClusterRole porte les deux. `_rbac.tpl` : `eg.rbac.namespaced` lit `configmaps`, `secrets` et `services` (lignes 31 à 42) et, si `topologyInjector.enabled`, vrai par défaut dans `values.yaml` (lignes 237 et 238), peut `patch` et `update` `pods` et `pods/binding` (lignes 44 à 56) ; `eg.rbac.cluster` ne porte que `nodes`, `namespaces`, `gatewayclasses` avec leur statut et `serviceimports` (lignes 159 à 203). `infra-manager-rbac.yaml` (lignes 36 à 50) ajoute au Role du namespace du contrôleur la lecture des Secrets et des EndpointSlices quand la liste existe.

Le code. `api/v1alpha1/envoygateway_types.go` (lignes 562 à 584) : `KubernetesWatchMode` porte `type` (`Namespaces` ou `NamespaceSelector`), `namespaces` et `namespaceSelector`, et « The namespace where Envoy Gateway runs is always included ». `api/v1alpha1/validation/envoygateway_validate.go` (lignes 90 à 109) refuse `Namespaces` sans liste. `internal/provider/kubernetes/kubernetes.go` (lignes 281 à 300) borne le cache par défaut aux namespaces de la liste, sans celui du contrôleur, pour tout informateur sans exception propre, ceux de Gateway API et de l'EnvoyProxy compris ; seuls les ConfigMaps, les Services, les EndpointSlices et les Secrets y ajoutent le namespace du contrôleur. `internal/provider/kubernetes/controller.go` (lignes 3326 à 3336) lit l'EnvoyProxy de la GatewayClass par ce cache, dans son namespace. L'EnvoyProxy de la couche `local` vit dans `envoy-gateway-system` : la liste nomme donc les deux namespaces du projet, `envoy-gateway-system` et `saas-b2b`, celui de l'application. `NamespaceSelector` est écarté : le chart garde alors le ClusterRole complet, lecture des Secrets de tout le cluster comprise.

Le rendu. Méthode de l'étape 7, avec les artefacts désignés par condensat (la page des registres de Helm, en version 4.3.1, donne la forme `oci://<registre>/<chart>@sha256:<condensat>`, et la page d'usage la forme `--set name={a, b}` des listes) : `HELM_CACHE_HOME`, `HELM_CONFIG_HOME`, `HELM_DATA_HOME` et `HELM_REGISTRY_CONFIG` dans un dossier temporaire ; `helm pull oci://docker.io/envoyproxy/gateway-helm@sha256:dcb82a14c04b426615a71d97222c7edf9f5ff58b800d241e71ac5784ae6dc7b7` et `helm pull oci://docker.io/envoyproxy/gateway-crds-helm@sha256:475c39aad3a05e3974a29fb80cfefe882b743e45e2ec0f751790ff0cb83bfa5d`, dont les archives ont les SHA-256 de l'ADR-005 (`0f72c905...`, `cc213d90...`). Les commandes de l'étape 7 refont d'abord les deux rendus vendus octet pour octet (`518143d8...` et `4270cb46...`). Puis :

- `helm template eg <archive de gateway-helm> -n envoy-gateway-system --set crds.enabled=false --set global.images.envoyGateway.image=<contrôleur par condensat> --set config.envoyGateway.provider.kubernetes.watch.type=Namespaces --set 'config.envoyGateway.provider.kubernetes.watch.namespaces={envoy-gateway-system,saas-b2b}'`.

Le rendu, identique avec `--kube-version v1.36.4`, a pour SHA-256 `3786ec420eb7aa2228f06313df4411da577778416939b3a355721394bbea1669`. Celui des CRD ne change pas. 21 objets au lieu de 17 : un Role `eg-gateway-helm-envoy-gateway-role` et son RoleBinding dans chacun des deux namespaces. Le ClusterRole du contrôleur perd tous les droits sur les Secrets et sur les pods. La configuration du contrôleur gagne `provider.kubernetes.watch`. Le Role `eg-gateway-helm-infra-manager` gagne la lecture des Secrets et des EndpointSlices de `envoy-gateway-system`. La `MutatingWebhookConfiguration` de l'injecteur de topologie ne vise toujours que les pods de `envoy-gateway-system` (`namespaceSelector` du rendu).

Essai sur kind, `PROFILE=lite task up` de l'étape 8 : GatewayClass `Accepted`, Gateway `Programmed`, aucune ligne `forbidden` ni de niveau `error` dans le journal du contrôleur. `kubectl auth can-i --as=system:serviceaccount:envoy-gateway-system:envoy-gateway` : `get` et `list` sur `secrets`, `patch` et `update` sur `pods` répondent `no` dans `kube-system` et `default`, `yes` dans `saas-b2b` et `envoy-gateway-system` ; `list secrets` et `patch pods` sur tout le cluster répondent `no`.

Ce qui reste. Dans `saas-b2b`, le contrôleur lit les Secrets, `db-auth` et `db-superuser` compris : la Gateway y lira `gateway-tls` avec l'écouteur HTTPS. Il peut aussi `patch` et `update` les pods, par la règle de l'injecteur de topologie, alors que l'injecteur n'agit que dans `envoy-gateway-system` (écart 94). Le Role de `saas-b2b` part avec ce namespace : `task up` le crée avec les Secrets, avant la plate-forme (écart 92), et `task app:down` le retirera à l'étape 9 (écart 93).

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://github.com/envoyproxy/gateway/blob/v1.10.0/charts/gateway-helm/templates/envoy-gateway-rbac.yaml> | 2026-11-25 | Lignes 1 à 94 : Role et RoleBinding par namespace surveillé, ClusterRole réduit |
| <https://github.com/envoyproxy/gateway/blob/v1.10.0/charts/gateway-helm/templates/_rbac.tpl> | 2026-11-25 | Lignes 31 à 56 et 159 à 203 : droits par namespace et du cluster |
| <https://github.com/envoyproxy/gateway/blob/v1.10.0/charts/gateway-helm/templates/infra-manager-rbac.yaml> | 2026-11-25 | Lignes 36 à 50 : lecture des Secrets du namespace du contrôleur |
| Archive `gateway-helm` v1.10.0, `values.yaml` | 2026-11-25 | Lignes 181 à 191 : configuration par défaut ; lignes 237 et 238 : injecteur de topologie actif |
| <https://github.com/envoyproxy/gateway/blob/v1.10.0/api/v1alpha1/envoygateway_types.go> | 2026-11-25 | Lignes 562 à 584 : `KubernetesWatchMode` |
| <https://github.com/envoyproxy/gateway/blob/v1.10.0/api/v1alpha1/validation/envoygateway_validate.go> | 2026-11-25 | Lignes 90 à 109 : `Namespaces` exige une liste |
| <https://github.com/envoyproxy/gateway/blob/v1.10.0/internal/provider/kubernetes/kubernetes.go> | 2026-11-25 | Lignes 281 à 300 : cache borné aux namespaces surveillés |
| <https://github.com/envoyproxy/gateway/blob/v1.10.0/internal/provider/kubernetes/controller.go> | 2026-11-25 | Lignes 3326 à 3336 : EnvoyProxy de la GatewayClass lu par le cache |
| <https://helm.sh/docs/topics/registries/> | 2026-11-25 | Chart désigné par condensat dans son adresse OCI |
| <https://helm.sh/docs/intro/using_helm/> | 2026-11-25 | Listes de `--set` |
| Essai sur kind du 2026-11-25 | 2026-11-25 | Classe acceptée, Gateway programmée, droits relus par `kubectl auth can-i` |

### Relevé du 2026-11-26 : image du proxy dans l'EnvoyProxy (PR #77, écarts 110 et 111)

Fait par [OPS]. Lectures du 2026-11-26, au tag v1.10.0 d'Envoy Gateway :

- `api/v1alpha1/envoyproxy_types.go`, ligne 663 : `EnvoyProxyKubernetesProvider.EnvoyDeployment *KubernetesDeploymentSpec` (clé `envoyDeployment`).
- `api/v1alpha1/shared_types.go`, ligne 126 : `KubernetesDeploymentSpec.Container *KubernetesContainerSpec` (clé `container`) ; ligne 270 : `KubernetesContainerSpec.Image *string` (clé `image`), « the EnvoyProxy container image to be used including a tag, instead of the default image », mutuellement exclusif avec `imageRepository`. La règle de validation accepte un condensat (`(@sha256:[a-z0-9]+)?`). Le champ est `spec.provider.kubernetes.envoyDeployment.container.image`, comme prévu.
- Même fichier, ligne 30 : `DefaultEnvoyProxyImage = "docker.io/envoyproxy/envoy:distroless-v1.40.2@sha256:09ca6f2140a61ad8df11779a4a30d52b48433d444466328494f9188c9c35eded"`, avec le commentaire « pin to sha256 to avoid issues with image tags being mutable and changing over time ». Le défaut compilé porte déjà le condensat de l'index que l'étape 7 a relevé : la référence écrite dans l'`EnvoyProxy` est la même, à l'octet près (écart 110).

Renovate 44.247.1. `lib/modules/versioning/docker/index.ts` : `versionPattern` exige un préfixe numérique, `distroless-v1.40.2` n'est pas une version pour lui. `lib/workers/repository/process/lookup/index.ts`, lignes 554 à 566 : une valeur non versionnée avec `currentDigest` n'est pas ignorée, et les lignes 592 à 601 ajoutent la mise à jour du condensat. Le gestionnaire de la couche `local` lit `local/platform/` en plus ; le commentaire `# renovate: datasource=docker depName=docker.io/envoyproxy/envoy` précède la ligne `image:` de l'`EnvoyProxy`. Aucun Renovate n'a tourné sur cette ligne.

Essai sur kind, même suite : l'`EnvoyProxy` du cluster porte `envoyDeployment.container.image` égal au fichier, et le conteneur `envoy` du pod du proxy, trouvé par l'étiquette `gateway.envoyproxy.io/owning-gateway-name=saas-b2b`, tourne avec cette référence (E03).

Garde de la relecture [SECU] (C1). Le champ `image` de l'`EnvoyProxy` prime sur le défaut compilé : un contrôleur monté seul laisserait l'ancien Envoy, et E03, qui compare le pod au fichier, passerait. Lecture du 2026-11-26 par `gh api`, au tag v1.10.0 : le fichier est `api/v1alpha1/shared_types.go`, la constante `DefaultEnvoyProxyImage` (ligne 30), seule ligne du fichier à porter ce nom suivi d'un `=` ; le commentaire qui la précède n'en porte pas. `scripts/ci/check-envoy-gateway-render.sh` (job `envoy-render`) lit ce fichier à l'adresse `https://raw.githubusercontent.com/envoyproxy/gateway/<tag>/api/v1alpha1/shared_types.go`, le tag étant celui de `ENVOY_GATEWAY_IMAGE` de `local/tasks/local.yml`, et échoue en nommant les deux valeurs si la référence de `envoy-proxy.yaml` diffère. Essai avec le fichier lu par `gh api` au tag v1.10.0 : les deux valeurs sont identiques. Son test (`tests/ci/check-envoy-gateway-render-test.sh`) lit un `shared_types.go` simulé : référence plus ancienne, même tag et autre condensat, fichier absent, fichier sans image, source sans constante, chacun refusé ; vu échouer avant la correction (7 cas).

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://github.com/envoyproxy/gateway/blob/v1.10.0/api/v1alpha1/envoyproxy_types.go> | 2026-11-26 | Ligne 663 : `envoyDeployment` |
| <https://github.com/envoyproxy/gateway/blob/v1.10.0/api/v1alpha1/shared_types.go> | 2026-11-26 | Lignes 30, 126 et 270 : image par défaut par condensat, `container`, `image` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/modules/versioning/docker/index.ts> | 2026-11-26 | `versionPattern` : un tag préfixé n'est pas ordonné |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/workers/repository/process/lookup/index.ts> | 2026-11-26 | Lignes 554 à 566 et 592 à 601 : mise à jour du condensat d'un tag non versionné |

## RS-03. Exemple applicatif

Décision : une ressource « note » (identifiant, texte de 1 à 500 caractères, date de création). Écriture en base, lecture par identifiant en lecture paresseuse par le cache, liste des plus récentes depuis la base, provenance de la lecture dans la réponse. Deux routes de santé : vivant et prêt. Accès à la base par Npgsql, requêtes paramétrées, sans ORM ; accès au cache derrière une interface, dont le client concret suit l'ADR-015 (RS-11).

Pourquoi : FR-009 et Q7 limitent le code à l'exemple. Une note relue après un rechargement prouve la conservation des données (récit 1, scénario 3) ; la provenance rend l'usage du cache testable sans regarder dans le cache. Sans ORM, il n'y a qu'une dépendance de base de données à suivre.

Alternatives : un compteur de visites, écarté parce qu'il ne prouve pas la relecture d'une donnée précise ; Entity Framework Core, écarté pour son poids face à une seule table ; aucune liste, écartée parce que le front n'aurait rien à afficher au chargement.

À vérifier avant l'étape 3 : version, licence et date de Npgsql ; celles du client .NET du cache à l'étape 19 ; format des réponses d'erreur d'ASP.NET Core (ProblemDetails) ; verrouillage des paquets NuGet par fichier de verrouillage. Porteur : [DEV].

Sources : spec, FR-009, récits 1 et 2 ; ADR-009, standards (Valkey parle RESP).

### Relevé du 2026-11-24 (T015)

Fait par [DEV]. Sources : la documentation d'ASP.NET Core 10, de Npgsql et de PostgreSQL 18, et le code source d'ASP.NET Core lu par `gh api`. Les versions et les dates des paquets sont au point RS-18.

Format des erreurs. ASP.NET Core produit des détails de problème quand l'application appelle `AddProblemDetails` : le middleware `UseExceptionHandler` en écrit un pour une exception non gérée, `UseStatusCodePages` pour une réponse d'erreur encore sans corps. La page cite la RFC 9457 pour le service des détails de problème. `TypedResults.ValidationProblem` répond 400 avec un `HttpValidationProblemDetails`, de type de contenu `application/problem+json`, titre par défaut « One or more validation errors occurred. », et un dictionnaire `errors` qui range les messages par nom de champ. La page des exceptions pour développeur s'active d'elle-même en environnement `Development` avec `WebApplication.CreateBuilder`, et elle montre la trace de pile ; hors `Development`, `ThrowOnBadRequest` vaut `false`. `WebApplicationFactory` démarre l'application en `Development` si rien ne fixe l'environnement : les tests U01 la démarrent donc en `Production`, l'environnement de l'image, pour vérifier qu'aucune erreur ne laisse passer de détail.

Validation intégrée de .NET 10 (`AddValidation`), écartée : elle ne refuse pas un champ inconnu sans `JsonUnmappedMemberHandling.Disallow`, et la règle « de 1 à 500 caractères après suppression des blancs » ne s'écrit pas en attribut `DataAnnotations`. L'API valide le corps elle-même et nomme chaque champ fautif, champ inconnu compris. Les caractères se comptent en points de code Unicode, comme `char_length` de PostgreSQL, pour que la contrainte de la table dise la même chose.

Description machine des routes : OpenAPI 3.1, la version par défaut d'ASP.NET Core 10 (3.2 à partir de .NET 11). Le paquet `Microsoft.AspNetCore.OpenApi` 10.0 expose `IOpenApiDocumentProvider`, enregistré comme service à clé sous le nom du document en minuscules, `v1` par défaut (`AddKeyedSingleton<IOpenApiDocumentProvider, OpenApiDocumentService>(documentName)`). Retenu : U01 génère le document en mémoire et le compare au fichier versionné `src/Api/openapi.json`, que S20 lit sans SDK. L'API n'appelle pas `MapOpenApi`, dont la route `/openapi/{documentName}.json` sortirait du contrat (S20). Le paquet n'entre que dans le projet de tests, et l'image de l'API ne l'embarque pas. Écartée : la génération au build par `Microsoft.Extensions.ApiDescription.Server`, qui lance le point d'entrée de l'application avec un serveur simulé à chaque `dotnet build` et demande d'écarter le code de la base derrière un test du nom d'assembly `GetDocument.Insider`.

Npgsql. `NpgsqlDataSource` est le point d'entrée recommandé depuis la version 7.0 ; il est sûr entre fils d'exécution, et une application en garde une seule instance. Les paramètres positionnels (`$1`) sont recommandés : le SQL part tel quel. Plusieurs instructions passent par `NpgsqlBatch` ; une transaction s'ouvre par `BeginTransactionAsync` et se passe à chaque commande. Paramètres de connexion : `Host`, `Port` (5432 par défaut), `Database`, `Username`, `Password`, `SSL Mode`, `Timeout` (15 s) et `Command Timeout` (30 s). `SSL Mode` vaut `Prefer` par défaut, « allows SSL but does not require it, and does not validate certificates », et accepte `Disable`, `Allow`, `Prefer`, `Require`, `VerifyCA` et `VerifyFull`. Le mode retenu face à Cloud SQL reste à T062 ; l'API lit la valeur dans `app-config`. Une colonne `timestamp with time zone` se lit en `DateTime` UTC par défaut, et en `DateTimeOffset` de décalage nul.

Effets : `src/Api/` (T020 à T024), `src/Api.Tests/` (T017), `tests/static/s20-api-routes.sh` (T018), clés d'`app-config` dans [contracts/layers.md](contracts/layers.md).

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://learn.microsoft.com/en-us/aspnet/core/fundamentals/error-handling-api?view=aspnetcore-10.0> | 2026-11-24 | `AddProblemDetails`, `UseExceptionHandler`, `UseStatusCodePages`, page des exceptions en `Development`, `ThrowOnBadRequest`, RFC 9457 |
| <https://learn.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.http.typedresults.validationproblem?view=aspnetcore-10.0> | 2026-11-24 | 400 avec `HttpValidationProblemDetails`, titre par défaut |
| <https://learn.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.http.httpresults.validationproblem?view=aspnetcore-10.0> | 2026-11-24 | Type de contenu `application/problem+json` |
| <https://learn.microsoft.com/en-us/aspnet/core/test/integration-tests?view=aspnetcore-10.0> | 2026-11-24 | Environnement `Development` par défaut, `UseEnvironment`, `ConfigureTestServices`, SDK `Microsoft.NET.Sdk.Web` pour le projet de tests |
| <https://learn.microsoft.com/en-us/aspnet/core/release-notes/aspnetcore-10.0?view=aspnetcore-10.0> | 2026-11-24 | `AddValidation` et champs non reconnus |
| <https://learn.microsoft.com/en-us/aspnet/core/fundamentals/openapi/aspnetcore-openapi?view=aspnetcore-10.0> | 2026-11-24 | OpenAPI 3.1 par défaut en .NET 10, document `v1`, génération au build et `GetDocument.Insider` |
| <https://learn.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.openapi.iopenapidocumentprovider?view=aspnetcore-10.0> | 2026-11-24 | `IOpenApiDocumentProvider`, paquet `Microsoft.AspNetCore.OpenApi` 10.0.0 |
| <https://github.com/dotnet/dotnet/blob/b0f34d51fccc69fd334253924abd8d6853fad7aa/src/aspnetcore/src/OpenApi/src/Extensions/OpenApiServiceCollectionExtensions.cs> | 2026-11-24 | Service à clé, nom du document en minuscules |
| <https://github.com/dotnet/dotnet/blob/b0f34d51fccc69fd334253924abd8d6853fad7aa/src/aspnetcore/src/OpenApi/src/Extensions/OpenApiEndpointRouteBuilderExtensions.cs> | 2026-11-24 | Écriture du document : `OpenApiJsonWriter` et `SerializeAsync` |
| <https://www.npgsql.org/doc/basic-usage.html> | 2026-11-24 | `NpgsqlDataSource`, paramètres positionnels, `NpgsqlBatch`, transactions |
| <https://www.npgsql.org/doc/connection-string-parameters.html> | 2026-11-24 | Paramètres de connexion et leurs défauts |
| <https://www.npgsql.org/doc/security.html> | 2026-11-24 | Valeurs de `SSL Mode`, défaut `Prefer` |
| <https://www.npgsql.org/doc/types/datetime.html> | 2026-11-24 | Lecture de `timestamp with time zone` |

## RS-04. Création du schéma

Décision : un script SQL idempotent, embarqué dans l'API et exécuté au démarrage sous le rôle de `db-auth`, propriétaire de la base `app`.

Pourquoi : le rôle de l'application n'est pas superutilisateur (ADR-012, condition 8), et Cloud SQL n'en donne jamais ; un script exécuté par l'application marche à l'identique sur les deux cibles. Un Job Kubernetes de migration ajouterait un objet et une attente à `task up` pour une seule table.

À vérifier avant l'étape 3 : les droits de création dans le schéma `public` pour le propriétaire d'une base sous PostgreSQL 18, et les privilèges de `cloudsqlsuperuser` (ADR-012, « Parité attendue avec Cloud SQL »). Porteur : [DEV] avec [SECU].

Alternatives : migrations d'Entity Framework Core (écarté avec RS-03) ; script dans `/docker-entrypoint-initdb.d`, réservé par l'ADR-012 à la création du rôle et inexistant sur Cloud SQL.

Sources : ADR-012, conditions 2 et 8.

### Relevé du 2026-11-24 (T016)

Fait par [DEV], à relire par [SECU], second porteur de T016. Sources : la documentation de PostgreSQL 18 et celle de Cloud SQL.

PostgreSQL 18, en local. Dans une base neuve, `PUBLIC` garde `USAGE` sur le schéma `public` mais n'y a plus `CREATE` depuis PostgreSQL 15 ; seule une base mise à niveau depuis la 14 ou avant le garde. Le rôle prédéfini `pg_database_owner` « always has exactly one implicit member: the current database owner » et « Initially, this role owns the `public` schema, so each database owner governs local use of that schema ». Le rôle de `db-auth`, propriétaire de la base `app` (ADR-012, condition 8), crée donc la table dans `public` sans `SUPERUSER`, sans `CREATEDB` et sans `CREATEROLE`. Le script de l'API n'emploie que `CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS` et `pg_advisory_xact_lock`, verrou de transaction « held until the current transaction ends ». La section des verrous consultatifs ne mentionne aucun privilège requis, quand d'autres sections du même chapitre réservent leurs fonctions aux superutilisateurs ; le droit d'exécution par défaut n'y est pas écrit. `IF NOT EXISTS` émet une notice et ne garantit pas que la table existante ressemble à celle du script : un changement de forme demandera une migration, hors de cette étape.

Cloud SQL. Le rôle `cloudsqlsuperuser` porte `CREATEROLE`, `CREATEDB` et `LOGIN`, « It does not have the `SUPERUSER` or `REPLICATION` attributes », et il est « granted automatically to new PostgreSQL users who use built-in authentication ». Un utilisateur IAM ne le reçoit que si on le lui donne. Ni la page des utilisateurs ni celle des bases ne disent qui possède une base créée par la console, `gcloud` ou l'API : seul l'exemple `psql` fixe un propriétaire (`CREATE DATABASE ... WITH OWNER ...`).

Conclusion pour la parité (R-35). En local, l'utilisateur de `db-auth` a moins d'attributs que sur Cloud SQL, et tient de sa seule qualité de propriétaire le droit de créer dans `public`. Sur Cloud SQL, ce droit n'est établi par aucune page lue : si la base `app` appartient à un autre rôle que l'utilisateur de `db-auth`, le script de démarrage échouera sur `CREATE TABLE`. À trancher par [OPS] et [SECU] en écrivant la couche `gcp` (T107) : base créée avec l'utilisateur de `db-auth` pour propriétaire, ou droit `CREATE` sur `public` donné par un rôle d'administration ; la vérification réelle attend le premier apply, avec l'accord de Lucas (principe X). L'écart restant se liste au README (ENF-02).

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://www.postgresql.org/docs/18/ddl-schemas.html> | 2026-11-24 | Sections 5.10.4 et 5.10.6 : `USAGE` et `CREATE` sur `public`, défaut depuis PostgreSQL 15 |
| <https://www.postgresql.org/docs/18/predefined-roles.html> | 2026-11-24 | Section 21.5 : `pg_database_owner`, membre implicite, propriétaire initial de `public` |
| <https://www.postgresql.org/docs/18/functions-admin.html> | 2026-11-24 | Section 9.28.10 : `pg_advisory_xact_lock`, aucune restriction écrite |
| <https://www.postgresql.org/docs/18/sql-createtable.html> | 2026-11-24 | `IF NOT EXISTS`, `CHECK`, `DEFAULT` |
| <https://docs.cloud.google.com/sql/docs/postgres/users> | 2026-11-24 | Attributs de `cloudsqlsuperuser`, rôle donné aux utilisateurs intégrés |
| <https://docs.cloud.google.com/sql/docs/postgres/create-manage-databases> | 2026-11-24 | Propriétaire d'une base créée par l'API non documenté |

### Relecture [SECU] du 2026-11-24 (T016, second porteur)

`CREATE TABLE` devrait passer sur Cloud SQL. Une base créée par la console appartient à `cloudsqlsuperuser` (page « Known issues ») ; rien n'est écrit pour l'API, `gcloud` ni `google_sql_database`, qui n'a pas d'argument `owner`. Une base se crée depuis `template1` par défaut, et le refus documenté sur `public` ne vise que `template0`. Sous PostgreSQL 18, l'appartenance implicite à `pg_database_owner` se propage aux membres du propriétaire (`roles_is_member_of`, `src/backend/utils/adt/acl.c`, REL_18_STABLE, commit `8efeedc7`) : un utilisateur intégré, qui hérite de `cloudsqlsuperuser`, a donc `CREATE` sur `public` si la base appartient à ce rôle. `pg_advisory_xact_lock` reste ouvert à `PUBLIC` (aucun `REVOKE` dans `system_functions.sql`).

Le vrai écart est le privilège. Sur GCP, l'API tourne avec `cloudsqlsuperuser` (`CREATEROLE`, `CREATEDB`, triggers d'événement, réplication logique, `pg_largeobject`) ; en local, le même utilisateur n'est que propriétaire de sa base. Une injection ou une exécution de code dans l'API permettrait sur GCP de créer des rôles ou de lire toute l'instance (R-39). Hypothèse et contrôles à écrire par T107 ; le propriétaire réel ne se lit qu'au premier apply, avec l'accord de Lucas (principe X). Durcissement après le MVP, par un ADR : rôle personnalisé passé dans `database_roles`, puis `ALTER DATABASE app OWNER TO`, étape SQL d'administration hors d'OpenTofu.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://docs.cloud.google.com/sql/docs/postgres/known-issues> | 2026-11-24 | Base créée par la console possédée par `cloudsqlsuperuser` ; refus sur `public` pour `template0` |
| <https://github.com/postgres/postgres/blob/REL_18_STABLE/src/backend/utils/adt/acl.c> | 2026-11-24 | `roles_is_member_of` ajoute `pg_database_owner` quand un rôle de la chaîne possède la base |
| <https://github.com/postgres/postgres/blob/REL_18_STABLE/src/backend/catalog/system_functions.sql> | 2026-11-24 | Aucun `REVOKE` sur `pg_advisory_xact_lock` |
| <https://github.com/hashicorp/terraform-provider-google/blob/main/website/docs/r/sql_database.html.markdown> | 2026-11-24 | Pas d'argument `owner` |

## RS-05. Front et image du front

Décision : React et TypeScript, construits par Vite dans une image multi-étapes ; fichiers statiques servis par nginx sur un port non privilégié, comme l'essai de BENCH-005.

Pourquoi : le brief et la spec fixent React ; nginx 1.30.7 est déjà figé par condensat dans l'essai.

À vérifier avant l'étape 4, avec la date de publication (principe VI) : versions de Node.js, React, Vite, TypeScript et du framework de test du front ; image de construction Node par condensat ; variante de nginx qui tourne sans root, exigée par le profil `restricted` que l'ADR-012 étend aux pods de l'application (condition 9). Porteur : [DEV].

Alternatives : servir le front depuis l'API .NET, écarté parce que la couche commune garde deux images indépendantes, comme l'essai mesuré.

Sources : spec, hypothèses ; BENCH-005, S38 et section 4.2 ; ADR-012, condition 9.

### Relevé du 2026-11-24 (T027)

Fait par [DEV]. Sources : la documentation de Vite, d'Oxc, de TypeScript, de Vitest, de Testing Library, de React, de npm, de nginx et de son image officielle, et le dépôt de l'image lu par `gh api`. Les versions, les dates et les condensats sont au point RS-18.

Construction. Vite 8 transpile le TypeScript par Oxc sans vérifier les types ; la page conseille `tsc --noEmit` en plus pour une construction de production, et demande `isolatedModules`. Les fichiers `.tsx` sont pris en charge sans extension : Oxc applique par défaut le runtime JSX `automatic`, avec `react` pour source des imports, et Vite reprend le champ `jsx` de `tsconfig.json`. Retenu : aucun `@vitejs/plugin-react`, dont l'apport, Fast Refresh, ne sert qu'au serveur de développement ; le golden repo n'en lance pas, `task reload` reconstruit l'image. `vite/client` dans `types` donne les types des imports de CSS. La page d'entrée est `index.html` à la racine du projet, la sortie va dans `dist/`, défaut de `build.outDir`. Le polyfill de préchargement des modules entre dans le module d'entrée de chaque page ; l'étape de contrôle de l'image vérifie que la page construite ne garde ni script ni style en ligne, que la politique de contenu de nginx bloquerait.

TypeScript 7.0 est le portage natif en Go, publié sous le paquet `typescript`, avec la commande `tsc`. Ses défauts changent : `strict` à `true`, `types` à `[]`, `module` à `esnext`. Il refuse `moduleResolution` `node`, `node10` et `classic`, `baseUrl` et `target: es5`. Il n'a pas d'API JavaScript, et aucun outil retenu n'en demande : Vite transpile par Oxc. Le paquet tire le binaire de la plate-forme par une dépendance optionnelle (`@typescript/typescript-linux-x64`, `@typescript/typescript-linux-arm64`), qui tourne sous l'Alpine de l'image de construction (essai du 2026-11-24 en arm64 ; amd64 par le job `unit`).

Tests : Vitest dans l'environnement `jsdom`, le défaut étant `node`, réglé sous la clé `test` de `vite.config.ts` avec la référence `vitest/config`. `globals` vaut `false` par défaut : les tests importent leurs fonctions, et appellent eux-mêmes `cleanup` de Testing Library dans `afterEach`, puisque la bibliothèque ne le fait seule que si le framework injecte un `afterEach` global. `vi.stubGlobal` remplace `fetch`, `vi.unstubAllGlobals` le rend. jsdom 31 déclare `@napi-rs/canvas` en pair optionnel, que npm n'installe pas.

npm. `npm ci` exige un `package-lock.json`, échoue si `package.json` demande un autre arbre, et n'écrit jamais le verrou. `ignore-scripts` coupe les scripts d'installation des paquets ; `npm run build` et `npm test` lancent encore leur propre script, sans les scripts `pre` et `post`. `audit` envoie à chaque installation un rapport des dépendances au registre : coupé, puisque le scan des images et Renovate tranchent sur les failles. `update-notifier`, qui interroge le registre sur la dernière version de npm, est coupé aussi. `min-release-age`, présent depuis npm 11.10.0, n'installe que des versions publiées depuis plus du nombre de jours donné : `tests/unit/u02-front.sh --update-locks` résout le verrou avec `--min-release-age=7`. Le réglage n'entre pas dans `.npmrc`, où il bloquerait aussi la mise à jour du verrou par Renovate pour un correctif de sécurité de moins de 7 jours, que le principe VI laisse passer.

Image de construction : variante Alpine de `node`. Elle est environ 25 % plus petite que `slim`. Le README de docker-node dit les builds musl « Experimental » ; le `BUILDING.md` de Node.js 26.13.1, qui fait foi, classe linux x64 musl en Tier 2, et arm64 musl n'y figure pas (relecture [SECU] du 2026-11-24). Les étiquettes Debian `slim` de 26.13.1 ont été repoussées le 2026-11-24, sous le délai de 7 jours. L'image ne sert qu'à construire et tester, et ne part sur aucune cible.

Service des fichiers : nginx en variante `alpine-slim`, sans les modules dynamiques de la variante `alpine` (njs, xslt, geoip, image-filter, acme). La documentation de l'image officielle décrit l'exécution sous un UID non root : `pid` et les chemins temporaires (`client_body_temp_path`, `proxy_temp_path`, `fastcgi_temp_path`, `uwsgi_temp_path`, `scgi_temp_path`) passent dans `/tmp`. L'image crée l'utilisateur et le groupe `nginx` sous l'identifiant 101. Son point d'entrée lance les scripts de `/docker-entrypoint.d/` (gabarits, écoute IPv6, résolveurs) seulement s'il en trouve : l'image du front les retire avec le site par défaut, et son `nginx.conf` porte toute la configuration. `USER 101:101` donne un UID numérique, que le profil `restricted` peut vérifier par `runAsNonRoot`. Écoute sur 8080. `nginx -t` passe sous cet utilisateur dans l'étape de contrôle de l'image ; le démarrage réel dans un pod `restricted` reste à E12, à l'étape 9. Écartée : l'image `nginxinc/nginx-unprivileged`, que cite la même page, un éditeur de plus pour cinq lignes de configuration.

En-têtes. `add_header` avec `always` les pose quel que soit le code de réponse ; une directive `add_header` d'un niveau masque celles du niveau parent, d'où leur seule place dans `server`. Politique de contenu restreinte à l'origine (`default-src 'self'`), page interdite dans un cadre (`frame-ancestors 'none'`), `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`. `absolute_redirect off` : une redirection garde l'hôte et le port de la gateway. HSTS revient à la gateway, qui termine TLS. Aucune tâche ne le pose encore, ni la redirection de HTTP vers HTTPS, ni `nosniff` sur `/api` : l'écart 51 de tasks.md les confie à l'étape 7 (relecture [SECU] du 2026-11-24).

Effets : `src/front/` (T028, T030, T031), `tests/static/s20-front-screens.sh` et `policy/front_screens.rego` (T029), `tests/unit/u02-front.sh` (T032).

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://vite.dev/guide/features> | 2026-11-24 | Transpilation sans vérification de types, `tsc --noEmit`, `isolatedModules`, `vite/client`, champs de `tsconfig.json` lus par Vite, JSX par Oxc (page de Vite 8.3.7) |
| <https://vite.dev/config/shared-options> | 2026-11-24 | Option `oxc`, `base` à `/`, `envPrefix` |
| <https://vite.dev/config/build-options> | 2026-11-24 | `build.outDir` à `dist`, polyfill de préchargement dans le module d'entrée |
| <https://vite.dev/guide/> | 2026-11-24 | `index.html` à la racine, `vite build`, Node.js 20.19 ou 22.12 au moins |
| <https://oxc.rs/docs/guide/usage/transformer/jsx.html> | 2026-11-24 | Runtime `automatic` par défaut, source `react`, transformations de développement coupées par défaut |
| <https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/> | 2026-11-24 | Paquet `typescript`, `tsc`, défauts changés, options retirées, aucune API |
| <https://vitest.dev/config/> | 2026-11-24 | Clé `test` de la configuration de Vite, référence `vitest/config` (page de Vitest 5.1.1) |
| <https://vitest.dev/config/environment> | 2026-11-24 | Défaut `node`, environnement `jsdom` |
| <https://vitest.dev/config/include> | 2026-11-24 | Motif par défaut des fichiers de test |
| <https://vitest.dev/config/globals> | 2026-11-24 | `globals` à `false` par défaut |
| <https://vitest.dev/api/vi> | 2026-11-24 | `vi.stubGlobal`, `vi.unstubAllGlobals`, `vi.fn` |
| <https://vitest.dev/api/mock> | 2026-11-24 | `mock.calls` |
| <https://testing-library.com/docs/react-testing-library/api/> | 2026-11-24 | `cleanup` automatique avec un `afterEach` global seulement |
| <https://react.dev/reference/react-dom/client/createRoot> | 2026-11-24 | `createRoot` de `react-dom/client`, `root.render` |
| <https://react.dev/learn/synchronizing-with-effects> | 2026-11-24 | Lecture dans un effet, résultat ignoré après le nettoyage, double effet en développement sous `StrictMode` |
| <https://github.com/npm/cli/blob/v11.20.0/docs/lib/content/commands/npm-ci.md> | 2026-11-24 | `npm ci` : verrou exigé, échec sur écart, verrou jamais écrit |
| <https://github.com/npm/cli/blob/v11.20.0/workspaces/config/lib/definitions/definitions.js> | 2026-11-24 | `ignore-scripts`, `audit`, `update-notifier`, `min-release-age` de npm 11.20.0 |
| <https://github.com/npm/cli/blob/v11.20.0/CHANGELOG.md> | 2026-11-24 | `min-release-age` ajouté en 11.10.0 (#8965) |
| <https://docs.npmjs.com/cli/v11/using-npm/config> | 2026-11-24 | `before`, `min-release-age`, `package-lock-only`, `omit` |
| <https://github.com/nodejs/docker-node/blob/main/README.md> | 2026-11-24 | Variante Alpine, musl « Experimental » selon ce README |
| <https://github.com/nodejs/node/blob/v26.13.1/BUILDING.md> | 2026-11-24 | linux x64 musl en Tier 2 ; arm64 musl absent de la liste des plates-formes |
| <https://github.com/docker-library/docs/blob/master/nginx/content.md> | 2026-11-24 | Exécution sous un UID non root : `pid` et chemins temporaires dans `/tmp` ; image `nginx-unprivileged` |
| <https://github.com/nginx/docker-nginx/tree/a2a986d19aac4a79a330e6e0b5171aae4e521926/stable/alpine-slim> | 2026-11-24 | `Dockerfile` (utilisateur 101, `ENTRYPOINT`, `CMD`, `EXPOSE 80`), `docker-entrypoint.sh`, `10-listen-on-ipv6-by-default.sh` ; commit de l'image 1.30.7 `alpine-slim` |
| <https://github.com/nginx/docker-nginx/blob/master/stable/alpine/Dockerfile> | 2026-11-24 | Modules ajoutés par la variante `alpine` à `alpine-slim` |
| <https://nginx.org/en/docs/ngx_core_module.html> | 2026-11-24 | `pid`, `error_log`, `events` |
| <https://nginx.org/en/docs/http/ngx_http_core_module.html> | 2026-11-24 | `listen`, `root`, `try_files` et code final, `server_tokens`, `client_body_temp_path`, `default_type`, `sendfile`, `absolute_redirect` |
| <https://nginx.org/en/docs/http/ngx_http_headers_module.html> | 2026-11-24 | `add_header`, `always`, héritage entre niveaux |
| <https://nginx.org/en/docs/http/ngx_http_log_module.html> | 2026-11-24 | `access_log`, format `combined` par défaut |
| <https://nginx.org/en/docs/http/ngx_http_proxy_module.html> | 2026-11-24 | `proxy_temp_path` |
| <https://nginx.org/en/docs/http/ngx_http_uwsgi_module.html> | 2026-11-24 | `uwsgi_temp_path` |
| <https://docs.docker.com/build/concepts/context/> | 2026-11-24 | `.dockerignore` à la racine du contexte, syntaxe des motifs |
| <https://docs.docker.com/reference/dockerfile/> | 2026-11-24 | `USER <UID>[:<GID>]` ; `CMD` de l'image de base gardé tant qu'on ne pose pas d'`ENTRYPOINT` |

## RS-06. Construction des images

Décision : construction multi-étapes dans le moteur, SDK .NET dans l'image de construction ; aucun SDK .NET ni Node.js dans les prérequis du poste.

Pourquoi : la construction est reproductible d'un poste à l'autre, et les prérequis restent ceux de l'ADR-006.

Coût : l'image du SDK pèse 362,8 Mo en amd64 au premier `task up`. Le levier de [FINOPS] (compiler sur le poste, ADR-006, question 3) reste ouvert ; il pose une question de reproductibilité que [DEV] et [SECU] tranchent, et la mesure D02 dira s'il faut le reprendre.

Sources : ADR-006, question 3 ; BENCH-005, détail amd64.

## RS-07. Nom des images construites

Décision : `saas-b2b.invalid/api` et `saas-b2b.invalid/front`, avec une étiquette neuve à chaque construction posée par Kustomize.

Pourquoi : sans hôte, Kubernetes suppose Docker Hub, et une image absente du nœud partirait vers le miroir puis vers un espace de noms qui n'appartient pas au projet (ADR-011, condition 4). Le domaine `.invalid` ne résout vers aucun registre.

Non essayé : que `kind load docker-image` et le kubelet acceptent ce nom. Porteur : [OPS], essai au début de l'étape 9. Repli si l'essai échoue : un autre hôte qui ne résout vers aucun registre public, retenu avec [SECU] et contrôlé par S01 et E11 de la même façon.

Sources : ADR-011, condition 4 ; ADR-006, condition 7.

### Essai du 2026-11-26 (T082)

Poste arm64, Docker 29.8.2 (pilote de stockage overlay2, lu par `docker info`), kind 0.33.0 (nœud v1.36.4), kubectl 1.37.1, cluster créé par `task up` en lite. Les images `saas-b2b.invalid/api` et `saas-b2b.invalid/front` sont construites depuis `src/Api/Dockerfile` et `src/front/Dockerfile`, cible `runtime`, avec une étiquette quelconque.

- `kind load docker-image` accepte les deux noms et les charge sur le nœud (« not yet present on node, loading », code 0).
- Un pod du front (UID 101) et un pod de l'API (UID 1654), profil `restricted`, `readOnlyRootFilesystem: true`, `emptyDir` sur `/tmp`, avec `imagePullPolicy: IfNotPresent`, passent à Running sans aucun tirage. L'API, sans `app-config`, journalise `app-config has no value for DATABASE_HOST` et reste en Production.
- Un pod avec `imagePullPolicy: Always` échoue en `ImagePullBackOff` : `failed to resolve reference "saas-b2b.invalid/front:t082": ... dial tcp: lookup saas-b2b.invalid on ...: no such host`. Le nœud ne cherche pas l'image au miroir ni sur un registre public : le nom ne résout nulle part.

Décision : `saas-b2b.invalid` est retenu, sans repli. Le manifest d'un pod construit ne doit jamais demander `Always` (le Deployment de base dit `IfNotPresent`). Non essayé : le magasin d'images containerd de Docker (le poste est en overlay2), qui change l'identifiant que `docker image inspect` rend et le comportement de `kind load` ; ni amd64. Le job `e2e-lite` de la CI (runner x64) rejoue le chargement à chaque exécution.

## RS-08. Profils et mémoire

Décision : profil choisi selon la mémoire que déclare le moteur ; variable `PROFILE` pour forcer, sous les mêmes contrôles. Seuils de départ : VM de 2,0 Gio pour le lite, 2,5 Gio pour la partie connue du standard. Seuils recalculés sur la première mesure, à l'entrée du cache retenu par l'ADR-015, et à celle de Keycloak et de Mailpit.

Pourquoi : ADR-004, condition 6 (mémoire déclarée par le moteur, pas mémoire physique) ; spec, cas limites. Les seuils sont des ordres de grandeur de [FINOPS] qui mêlent plusieurs séries.

À vérifier : la commande qui lit la mémoire déclarée, sous Docker Engine et sous le moteur libre que retiendra [OPS]. Porteur : [DEV], étape 5.

Sources : ADR-004, condition 6 ; ADR-006, conséquences ; ADR-011 et ADR-012, conséquences.

### Relevé du 2026-11-24 (T033)

Fait par [DEV]. Sources officielles : docs.docker.com, kubernetes.io, gnu.org, docs.podman.io et taskfile.dev, plus le code source de moby, de docker/cli, de kind et de Podman, lu par `gh api` au tag de chaque version citée. Lectures sur le poste de mesure, toutes en lecture seule : `docker info`, `kind version`, `kubectl version --client`.

Mémoire et version sous Docker Engine : une seule commande, `docker info --format '{{.ServerVersion}} {{.MemTotal}}'`. La spécification de l'API du moteur définit `MemTotal` comme « Total amount of physical memory available on the host, in bytes », un entier, et `ServerVersion` comme « Version string of the daemon ». Quand le moteur tourne dans une machine virtuelle, l'hôte de l'API est cette machine : c'est bien la mémoire que vise la condition 6 de l'ADR-004. Les deux noms sont des champs de la structure `system.Info` que rend `--format`. La page de `docker system info` ne montre que le modèle `{{json .}}` et renvoie aux modèles Go : le nom des champs vient du code source.

Moteur qui ne répond pas : le code de `docker info` (docker/cli v29.8.2) distingue deux cas. Un échec de connexion rend le modèle avec des valeurs vides, puis sort en erreur. Sur le poste, avec `DOCKER_HOST` pointé sur un socket absent, le modèle `{{.ServerVersion}}|{{.MemTotal}}` donne `|0`, le message `failed to connect to the docker API at unix://...` et le code 1. Toute autre erreur du moteur est écrite sur la sortie d'erreur, le modèle est rendu avec des valeurs vides, et la commande sort en 0. `preflight.sh` refuse donc aussi une sortie sans version ni mémoire, quel que soit le code de sortie.

Docker Engine 28.0.0 : publiée le 2025-02-19. Ses notes de version disent « Direct routed access to container ports that are not exposed using p/-publish is now blocked ». La dernière 28.x de la page est 28.5.2, du 2025-11-05. `preflight.sh` reconnaît Linux à `uname -s` et compare les trois premiers nombres de `ServerVersion`, si bien qu'un suffixe de paquet comme `+dfsg1` ne compte pas.

kind : `kind version` imprime `kind v<version> <go> <os>/<arch>` (fonction `DisplayVersion`), et `kind version --quiet` (`-q`) la version seule, `0.33.0` sur le poste (code de kind au tag v0.33.0, `pkg/cmd/kind/version/version.go` et `pkg/cmd/kind/root.go`). Une version de développement ajoute `-<pré-version>` ; la comparaison exacte la refuse.

kubectl : `kubectl version --client` « shows client version only (no server required) » ; `-o, --output` accepte `yaml` ou `json`. `preflight.sh` lit `clientVersion.gitVersion` dans la sortie JSON, `v1.37.1` sur le poste. La plage vient de la politique de décalage des versions de Kubernetes, « kubectl is supported within one minor version (older or newer) of kube-apiserver » : 1.35 à 1.37 autour de la mineure 1.36 de `platform.yaml`, que le script lit (ADR-006, condition 5).

Kubeconfig, pour P05 : la page kubeconfig de Kubernetes donne l'ordre `--kubeconfig`, puis `KUBECONFIG`, puis `$HOME/.kube/config`, et le contexte par `--context`, puis par `current-context`. La page de `kubectl version` ne dit pas si `--client` lit le kubeconfig. Sur le poste, `kubectl version --client -o json` sort en 0 avec un `KUBECONFIG` ou un `--kubeconfig` qui désigne un fichier absent ou illisible : il ne le lit pas. `preflight.sh` n'appelle kubectl que pour cette lecture.

Ports, pour P04 : bash ouvre lui-même `/dev/tcp/<hôte>/<port>` (manuel de bash, « Redirections »). Une connexion acceptée en 127.0.0.1 signale un port pris, quel que soit l'utilisateur du processus qui écoute, et sans autre outil. La page des options de compilation de bash n'a pas pu être lue (réponses 429 de gnu.org). La prise en charge est constatée sur `/bin/bash` 3.2.57 du poste, où les ports 7000 et 32222 sortent pris, 1 et 59999 libres, et sur bash 5.2.21 d'Ubuntu 24.04 (image `mcr.microsoft.com/playwright:v1.64.1-noble`, par condensat), où un port fermé répond « Connection refused ». Un bash compilé sans cette redirection verrait tous les ports libres, et la création du cluster échouerait plus tard sur le port pris ; corrigé le 2026-11-25, voir le relevé qui suit.

`PROFILE` dans Task : une variable passée en ligne de commande n'est pas exportée aux commandes, et « By default, a variable already present in the process environment takes precedence over Taskfile `env` values ». La tâche passe donc `PROFILE` par `env:`. Constaté avec Task 3.54.0 : `PROFILE=lite task up` et `task up PROFILE=lite` forcent tous deux le lite ; sans `env:`, la seconde forme était ignorée sans un mot ; avec les deux formes à la fois, l'environnement gagne.

Moteur libre, pas encore retenu par [OPS] (R-26) : Podman. `podman info` rend la mémoire sous `host.memTotal` en JSON, champ `Host.MemTotal` en modèle Go, lu dans `/proc/meminfo` de la machine où tourne le service, donc de la VM sous `podman machine` (code de Podman v6.2.1, `libpod/info.go` et `libpod/define/info.go`). La page de `podman info` montre `memTotal: 16401895424` sans donner l'unité ; celle de `podman machine init` donne `--memory` en Mio, sans valeur par défaut. L'API compatible de Podman, « Docker v1.40 API », répond à `docker info` avec un `MemTotal` de même source et un `ServerVersion` égal à la version de Podman (`pkg/api/handlers/compat/info.go`). Rien n'est câblé pour Podman. Écart : sous Linux, un `docker` branché sur Podman rendrait une version 6.x, que la règle des 28.0.0, écrite pour Docker Engine, refuserait. La règle se reprend quand [OPS] retiendra le moteur libre.

OrbStack, moteur du poste : `ServerVersion` 29.8.2, `MemTotal` 12598894592 octets (12015 Mio, soit 11,73 Gio pour 24 Gio physiques), `OperatingSystem` « OrbStack », `OSType` linux, nom de plate-forme du serveur « Docker Engine - Community ». La sortie de `docker info --format` a le même format que sous Docker Engine : même CLI, en 29.8.2, et même API. Deux différences : `OperatingSystem`, que `preflight.sh` ne lit pas, et la valeur de `MemTotal`, qui suit l'allocation d'OrbStack plutôt qu'un réglage fixe de VM. Docker Desktop, lui, se nomme « Docker Desktop » suivi de sa version (exemple de la page `docker version`).

Écart sur les seuils : les seuils de départ parlent d'une VM de 2,0 et de 2,5 Gio, et `preflight.sh` compare la mémoire déclarée à 2048 et à 2560 Mio. Ce que déclare une VM réglée à 2,0 Gio n'est pas mesuré ; si c'est moins de 2048 Mio, cette VM est refusée. À mesurer avec le recalcul de T081.

Effets : `golden/saas-b2b/local/scripts/preflight.sh` (T037), ses binaires simulés `golden/saas-b2b/local/tests/preflight/fakes/` et les contrôles P01 à P05 (T034 à T036), dont les sorties reproduisent celles relevées ici.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://docs.docker.com/reference/cli/docker/system/info/> | 2026-11-24 | `--format` avec un modèle Go ; seul exemple, `{{json .}}` |
| <https://docs.docker.com/reference/cli/docker/version/> | 2026-11-24 | Exemple `{{.Server.Version}}` ; serveur « Docker Desktop 4.19.0 » ou « Docker Engine - Community » |
| <https://github.com/moby/moby/blob/docker-v29.8.2/api/swagger.yaml> | 2026-11-24 | `MemTotal` en octets, mémoire de l'hôte ; `ServerVersion`, version du démon |
| <https://github.com/moby/moby/blob/docker-v29.8.2/api/types/system/info.go> | 2026-11-24 | Champs `MemTotal`, `ServerVersion`, `OperatingSystem`, `OSType` de `system.Info` |
| <https://github.com/docker/cli/blob/v29.8.2/cli/command/system/info.go> | 2026-11-24 | Échec de connexion : erreur ; autre erreur du moteur : message, modèle rendu, sortie en 0 |
| <https://docs.docker.com/engine/release-notes/28/> | 2026-11-24 | 28.0.0 du 2025-02-19 ; accès routé aux ports non publiés bloqué ; 28.5.2 du 2025-11-05 |
| <https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/cmd/kind/version/version.go> | 2026-11-24 | Format de `kind version` et de `kind version --quiet` |
| <https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/cmd/kind/root.go> | 2026-11-24 | Option globale `--quiet`, `-q` |
| <https://kubernetes.io/docs/reference/kubectl/generated/kubectl_version/> | 2026-11-24 | `--client` sans serveur ; `--output` en `yaml` ou `json` |
| <https://kubernetes.io/releases/version-skew-policy/> | 2026-11-24 | kubectl pris en charge à une mineure près du serveur d'API |
| <https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/> | 2026-11-24 | Ordre `--kubeconfig`, `KUBECONFIG`, `$HOME/.kube/config` ; choix du contexte |
| <https://www.gnu.org/software/bash/manual/html_node/Redirections.html> | 2026-11-24 | `/dev/tcp/host/port` ouvert par bash |
| <https://taskfile.dev/docs/guide/variables> | 2026-11-24 | Ordre de résolution des variables ; `vars` non exportées aux commandes (v3.54.0) |
| <https://taskfile.dev/docs/guide/environment> | 2026-11-24 | L'environnement du processus l'emporte sur `env` |
| <https://docs.podman.io/en/latest/markdown/podman-info.1.html> | 2026-11-24 | `--format` en JSON ou modèle Go ; `memTotal` dans l'exemple |
| <https://docs.podman.io/en/latest/markdown/podman-machine-init.1.html> | 2026-11-24 | `--memory` en Mio, sans valeur par défaut écrite |
| <https://docs.podman.io/en/latest/markdown/podman-system-service.1.html> | 2026-11-24 | Couche compatible « Docker v1.40 API » |
| <https://github.com/containers/podman/blob/v6.2.1/libpod/info.go> | 2026-11-24 | `MemTotal` lu dans `/proc/meminfo` ; compat : `pkg/api/handlers/compat/info.go`, `ServerVersion` égal à la version de Podman |

### Relevé du 2026-11-25 : contexte Docker et délai d'attente (relecture [SECU] de la PR #57)

Fait par [DEV]. Code source au tag de chaque version, lu par `gh api`, et lectures sur le poste de mesure, toutes en lecture seule : `docker context inspect`, `docker context ls`, `docker info`.

Où kind crée le cluster : le fournisseur docker de kind v0.33.0 lance la commande `docker` (`exec.Command("docker", ...)`, par exemple ligne 98 de `pkg/cluster/internal/providers/docker/provider.go`). kind suit donc le même contexte que `docker info`. Avec un `DOCKER_HOST` ou un contexte distant, le cluster serait créé sur une autre machine, et les contrôles de mémoire, de version et de ports liraient cette machine-là.

Contexte courant : `resolveContextName` (docker/cli v29.8.2, `cli/command/cli.go`, lignes 443 à 461) prend l'option `--context`, puis l'option `--host` ou un `DOCKER_HOST` non vide, qui imposent le contexte `default`, puis `DOCKER_CONTEXT`, puis `currentContext` du fichier de configuration, et à défaut `default`. Le commentaire de `CurrentContext` (lignes 406 à 432) range `DOCKER_HOST` parmi les replis ; le code le fait passer avant `DOCKER_CONTEXT`, et le poste le confirme : avec les deux variables posées, le contexte retenu est `default`. L'hôte du contexte `default` est `DOCKER_HOST` passé par `ParseHost` (`cli.go`, lignes 342 à 371 et 590 à 599 ; `opts/hosts.go`) : un `hôte:port` sans schéma devient `tcp://hôte:port`, une valeur vide donne `unix:///var/run/docker.sock` (`opts/hosts_unix.go`, ligne 6).

Commande et champ confirmés : `docker context inspect --format '{{.Name}} {{.Endpoints.docker.Host}}'`. Sans argument, la commande inspecte le contexte courant (`cli/command/context/inspect.go`, lignes 30 à 35). L'objet inspecté embarque `store.Metadata`, avec `Name` et la table `Endpoints` (`cli/context/store/store.go`, lignes 70 à 74). Son entrée `docker` (constante `DockerEndpoint`, `cli/context/docker/constants.go`) porte le champ `Host` (`cli/context/endpoint.go`, ligne 5). `runInspect` (lignes 47 à 64) ne lit que le magasin des contextes ; le client de l'API ne se crée qu'à la demande (`initialize`, `cli.go`, lignes 532 à 550). Un nom de contexte suit `^[a-zA-Z0-9][a-zA-Z0-9_.+-]+$` (`store.go`, ligne 232) : nom et hôte se lisent sur une seule ligne.

Sur le poste, avec docker 29.8.2 : `orbstack unix:///Users/<utilisateur>/.orbstack/run/docker.sock`. `DOCKER_HOST=tcp://127.0.0.1:1` donne `default tcp://127.0.0.1:1`, `DOCKER_HOST=127.0.0.1:2375` donne `default tcp://127.0.0.1:2375`, `DOCKER_CONTEXT=default` donne `default unix:///var/run/docker.sock`. Un contexte inconnu imprime une ligne vide et le message `context "<nom>": context not found: ...`, puis sort en 1. Un contexte sans entrée `docker` rendrait `<no value>` avec une sortie en 0 (constaté avec une entrée absente, `{{.Endpoints.nope.Host}}`) : la ligne n'a pas la forme attendue, `preflight.sh` refuse.

Règle appliquée : seul un hôte `unix://` est accepté, et annoncé. Tout autre schéma, `tcp://`, `ssh://`, `fd://` ou `npipe://`, est refusé avant `docker info`, en nommant le contexte et l'hôte, avec le retour en arrière qui convient : `unset DOCKER_HOST`, `unset DOCKER_CONTEXT` ou `docker context use default`.

Limites connues. Un socket unix relayé par `ssh -L` vers une autre machine passe le contrôle. Podman machine expose un socket unix local, donc accepté ; l'écart de la règle des 28.0.0 sous Linux, noté plus haut, reste entier. Enfin la CLI de kind lit `KIND_EXPERIMENTAL_PROVIDER` (`podman`, `nerdctl` ou `docker`) et ne détecte plus rien quand la variable est posée (`pkg/cluster/provider.go`, lignes 109 et 110) : avec `podman` ou `nerdctl`, kind ne passe pas par `docker`, et ce contrôle regarde un autre moteur. Rien ne le traite encore ; à trancher avec l'étape 6, qui lance `kind create cluster`.

Délai d'attente : la CLI docker ne borne que son initialisation, à 2 s (`defaultInitTimeout`, `cli.go`, ligne 32), appliquée au ping de `initializeFromClient` (lignes 380 à 399). Un ping en échec est ignoré, et la requête de `docker info` attend ensuite sans limite. Sur le poste, `docker info --format '{{.ServerVersion}} {{.MemTotal}}'` répond en 0,03 s sur trois essais, `docker context inspect` en 0,01 s. `preflight.sh` borne les deux appels à 10 s (`DOCKER_TIMEOUT_SECONDS`) : un moteur lent dans sa machine virtuelle a le temps de répondre, un moteur bloqué est signalé sans longue attente. Bash 3.2 n'a pas de `timeout`, macOS non plus. Une sentinelle lancée en arrière-plan surveille la commande par `kill -0` et `sleep 1`, l'arrête par TERM puis par KILL une seconde plus tard, et l'appel rend 124. Comme la sentinelle tourne à côté de la commande, un appel qui répond tout de suite ne paie aucune attente. Seule la commande est arrêtée : un enfant qu'elle laisserait vivant garderait sa sortie ouverte.

Sonde des ports, reprise : seul « Connection refused » vaut port libre. `LC_ALL=C`, posé en tête des contrôles, garde ce message de bash non traduit. Tout autre résultat est indécidable et refusé. Sur le poste, une connexion au port 0 donne « Can't assign requested address ». Un bash compilé sans cette redirection chercherait un vrai fichier sous `/dev/tcp`, absent : « No such file or directory », constaté avec un chemin voisin, refusé lui aussi. P04 joue la vraie sonde sur le port 1, fermé, sous chaque bash testé.

Effets : les contrôles passent dans `golden/saas-b2b/local/scripts/lib/preflight-checks.sh`, que `preflight.sh` source avant de lancer `main` sans condition ; le faux `docker` de `local/tests/preflight/fakes/` répond à `docker context inspect` selon l'ordre ci-dessus ; P02 et P04 couvrent le contexte, le délai et la sonde.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/cluster/internal/providers/docker/provider.go> | 2026-11-25 | Le fournisseur docker lance la commande `docker` (ligne 98) |
| <https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/cluster/provider.go> | 2026-11-25 | `KIND_EXPERIMENTAL_PROVIDER` lu par la CLI de kind, sans détection (lignes 109 et 110) |
| <https://github.com/docker/cli/blob/v29.8.2/cli/command/cli.go> | 2026-11-25 | Résolution du contexte (lignes 443 à 461) ; hôte du contexte `default` (lignes 342 à 371, 590 à 599) ; délai de 2 s de l'initialisation seule (lignes 32, 380 à 399) ; client créé à la demande (lignes 532 à 550) |
| <https://github.com/docker/cli/blob/v29.8.2/cli/command/context/inspect.go> | 2026-11-25 | Sans argument, le contexte courant (lignes 30 à 35) ; lecture du magasin seule (lignes 47 à 64) |
| <https://github.com/docker/cli/blob/v29.8.2/cli/context/store/store.go> | 2026-11-25 | `Metadata` : `Name`, `Endpoints` (lignes 70 à 74) ; forme d'un nom de contexte (ligne 232) |
| <https://github.com/docker/cli/blob/v29.8.2/cli/context/endpoint.go> | 2026-11-25 | Champ `Host` de l'entrée d'un contexte (ligne 5) |
| <https://github.com/docker/cli/blob/v29.8.2/cli/context/docker/constants.go> | 2026-11-25 | Nom de l'entrée : `docker` |
| <https://github.com/docker/cli/blob/v29.8.2/opts/hosts.go> | 2026-11-25 | `ParseHost` : hôte sans schéma en `tcp://` ; `opts/hosts_unix.go`, hôte par défaut `unix:///var/run/docker.sock` |

### Relevé du 2026-11-25 : variables expérimentales de kind (étape 6)

Fait par [OPS]. Code de kind au tag v0.33.0, lu par `gh api`.

`KIND_EXPERIMENTAL_PROVIDER` est lue par la CLI de kind dans `GetDefault` (`pkg/internal/runtime/runtime.go`, lignes 28 à 44). Une valeur vide vaut absence : kind détecte alors le moteur lui-même. `docker` force le fournisseur docker. `podman` force Podman, et `nerdctl`, `finch` et `nerdctl.lima` forcent nerdctl. Toute autre valeur est ignorée avec un avertissement, et kind détecte de nouveau.

Décision du DSI du 2026-11-25, appliquée dans `local/scripts/lib/preflight-checks.sh` : les contrôles préalables refusent `KIND_EXPERIMENTAL_PROVIDER` posée à une autre valeur que `docker`, en la nommant, avant tout appel à `docker`. Une valeur inconnue est refusée aussi, bien que kind l'ignore, parce qu'elle trahit une intention que la règle ne suit pas. La valeur vide passe, comme pour kind. P02 joue chacune de ces valeurs.

Ajout d'[OPS], à confirmer par le DSI : le fournisseur docker lit aussi `KIND_EXPERIMENTAL_DOCKER_NETWORK` (`pkg/cluster/internal/providers/docker/provider.go`, lignes 71 à 76), qui remplace le réseau `kind` (`network.go`, ligne 47) par un autre. Le miroir démarre sur le réseau `kind` (ADR-011, condition 2) : avec un autre réseau, les nœuds ne le joindraient plus. Les contrôles préalables refusent donc cette variable quand elle vaut autre chose que `kind`, sur le même modèle.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/internal/runtime/runtime.go> | 2026-11-25 | Lignes 28 à 44 : valeurs de `KIND_EXPERIMENTAL_PROVIDER`, vide ignorée, inconnue ignorée avec un avertissement |
| <https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/cluster/internal/providers/docker/provider.go> | 2026-11-25 | Lignes 71 à 76 : `KIND_EXPERIMENTAL_DOCKER_NETWORK` remplace le réseau des nœuds |
| <https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/cluster/internal/providers/docker/network.go> | 2026-11-25 | Ligne 47 : réseau `kind` par défaut |

## RS-09. Taskfile et scripts

Décision : `Taskfile.yml` à la racine expose les commandes publiques et délègue aux Taskfiles inclus de `local/tasks/` et `gcp/tasks/`. La logique vit dans des scripts bash de `local/scripts/`, compatibles avec bash 3.2, sans heredoc, passés à shellcheck. Le Taskfile porte en tête l'inventaire des commandes qui créent, modifient ou suppriment un conteneur, un réseau ou un volume. Construction, chargement et application sont définis une fois et réutilisés par `task up` et `task reload`.

Pourquoi : ADR-006, condition 6 ; ADR-007, condition 1 (bash 3.2 de macOS, heredoc) ; ADR-011, condition 11.

À vérifier avant l'étape 1 : version de Task, sa syntaxe d'inclusion, le mode silencieux et la détection de sources modifiées utile à `task reload`. Porteur : [DEV].

### Relevé du 2026-11-23 (T001)

Fait par [DEV]. Sources officielles seulement : l'API GitHub du dépôt `go-task/task`, lue par `gh api`, et la documentation de taskfile.dev, dont chaque page lue s'annonce en v3.54.0.

Version retenue : Task v3.54.0, publiée le 2026-10-01, dernière release stable (la release `nightly` est une pré-version, écartée). Elle a 53 jours au 2026-11-23 et passe le délai de 7 jours (principe VI). Licence MIT.

Gouvernance (ADR-006, question 5) : le dépôt appartient à l'organisation `go-task`, qui compte trois membres publics, `andreynering`, `pd93` et `vmaerten`. Aucune fondation n'est citée. Sur un an, du 2025-11-23 au 2026-11-23, le dépôt reçoit 401 commits, dont 326 d'auteurs humains (robots `renovate[bot]`, `dependabot[bot]` et `task-bot` exclus), venus de 50 auteurs. `vmaerten` en signe 158 (48,5 %), `andreynering` 76 (23,3 %) et `pd93` 26 (8,0 %) : 79,8 % pour les trois membres. Employeurs déclarés sur leur profil GitHub : « @charmbracelet » pour `andreynering`, « Senior Software Engineer @oneid » pour `pd93`, aucun pour `vmaerten`. Lecture : un projet communautaire, sans fondation, porté par trois personnes, sans entreprise dominante déclarée. Ce relevé donne les faits ; le classement au titre du principe V reste à Lucas, et la question 5 de l'ADR-006 n'est pas close par lui.

Intégrité : la release publie un fichier de sommes, `task_checksums.txt`. Elle n'est pas immuable (`immutable: false`) et l'API des attestations répond 404 pour le binaire linux amd64. Comme pour kind (ADR-004, condition 5), la somme publiée dans la même release protège de la corruption, pas d'une substitution. Les sommes ci-dessous sont lues dans `task_checksums.txt` (asset 604090275, lu par l'API) ; elles sont égales au champ `digest` que l'API des releases donne pour chaque archive.

| Archive | SHA-256 |
| --- | --- |
| `task_linux_amd64.tar.gz` | `680859dbb4d881a9c72d4d9a8f510825450849af8567deacd7302c01124416fb` |
| `task_linux_arm64.tar.gz` | `d7189d439d4a6058e39e1b2acd7c8b27acd4856691b408f23b242e4294e1df5b` |
| `task_darwin_amd64.tar.gz` | `0543b0844a725814c0412d3f4bed12873ce9ed0da207b15775f63a97d734aac0` |
| `task_darwin_arm64.tar.gz` | `12a69fcf37bb8d5bc9150c44f9a936775b73e59ff044c2c245232f198c135637` |

Inclusion des Taskfiles : clé `includes`, forme courte (`nom: chemin`) ou longue (`taskfile:` et `dir:`). Sans `dir`, une tâche incluse s'exécute dans le dossier d'exécution du Taskfile qui l'inclut, pas dans celui de son fichier. `optional: true` tolère un fichier absent ; `internal: true` cache toutes les tâches du fichier, qui ne servent plus qu'aux tâches publiques ; `flatten: true` les expose sans espace de noms. Une tâche incluse s'appelle `espace:tache`, en ligne de commande comme depuis les `cmds` d'une autre tâche. Les Taskfiles inclus portent la même version de schéma, `version: '3'`.

Mode silencieux : `silent: true` à la racine, sur une tâche ou sur une commande, ou l'option `--silent` (`-s`). Il cache le texte de la commande que Task affiche, pas la sortie de la commande, et la page le dit : « Silent mode is not a substitute for secret masking. » C'est ce que l'ADR-007 (condition 1, S53) relevait déjà : une valeur ne passe jamais par un argument ni une variable de Task.

Sources modifiées : `sources` et `generates` acceptent fichiers et motifs, relatifs au dossier de la tâche, avec des entrées `exclude:`. La méthode par défaut, `checksum`, compare le contenu des sources à une empreinte gardée dans `.task/`, sous le dossier du projet (à ignorer dans Git ; `TASK_TEMP_DIR` le déplace). `timestamp` et `none` sont les deux autres méthodes ; `status` saute la tâche quand chaque contrôle sort en 0 ; `--force` (`-f`) la relance. Pour `task reload`, `sources` sur `src/Api/` et `src/front/` avec la méthode `checksum` permettrait de ne reconstruire que l'image touchée ; le choix se fait à l'étape 9.

Exécution : Task lance les commandes par son interpréteur intégré, sans le shell de l'utilisateur ; chaque entrée de `cmds` a son propre contexte, et un script bash s'appelle explicitement par `bash`. Une commande en échec arrête sa tâche. Codes de sortie de la CLI : 201 pour une commande en échec, 200 pour une tâche inconnue, 202 pour l'appel direct d'une tâche interne.

Effets : `golden/saas-b2b/Taskfile.yml` (T009) inclut `local/tasks/` en `internal` et `gcp/tasks/` en `optional` ; `golden/saas-b2b/tests/tools/install.sh` et `SHA256SUMS` (T011) installent v3.54.0 par ces sommes.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://api.github.com/repos/go-task/task/releases> | 2026-11-23 | v3.54.0 publiée le 2026-10-01, dernière stable ; `nightly` en pré-version ; release non immuable |
| <https://github.com/go-task/task/releases/download/v3.54.0/task_checksums.txt> | 2026-11-23 | Les quatre SHA-256 du tableau, lus par l'API (asset 604090275) |
| <https://api.github.com/repos/go-task/task> | 2026-11-23 | Licence MIT, dépôt non archivé, organisation `go-task` |
| <https://api.github.com/orgs/go-task/public_members> | 2026-11-23 | Trois membres publics |
| <https://api.github.com/repos/go-task/task/commits?since=2025-11-23T00:00:00Z> | 2026-11-23 | Commits de l'année par auteur |
| <https://api.github.com/repos/go-task/task/attestations/sha256:680859dbb4d881a9c72d4d9a8f510825450849af8567deacd7302c01124416fb> | 2026-11-23 | 404 : aucune attestation |
| <https://taskfile.dev/docs/guide/includes> | 2026-11-23 | Syntaxe d'inclusion, `dir`, `optional`, `internal`, `flatten`, appel `espace:tache` |
| <https://taskfile.dev/docs/guide/output> | 2026-11-23 | Mode silencieux et sa limite |
| <https://taskfile.dev/docs/guide/up-to-date> | 2026-11-23 | `sources`, `generates`, `method`, `.task/`, `status`, `--force` |
| <https://taskfile.dev/docs/guide/defining-tasks> | 2026-11-23 | `version: '3'`, `desc`, `dir`, tâche `internal` |
| <https://taskfile.dev/docs/guide/errors-and-cleanup> | 2026-11-23 | Une commande en échec arrête sa tâche ; exemples en `exit 1` |
| <https://taskfile.dev/docs/guide/platforms> | 2026-11-23 | Interpréteur intégré, contexte par entrée de `cmds`, appel explicite de `bash` |
| <https://taskfile.dev/docs/reference/cli> | 2026-11-23 | Codes de sortie, `--silent`, `--dir`, `--taskfile`, `--list` |

### Relevé du 2026-11-25 : noms à deux-points et variables d'un Taskfile inclus (étape 6)

Fait par [OPS], avec Task v3.54.0 sur le poste de mesure, dans un Taskfile d'essai hors du dépôt.

Une tâche du Taskfile racine peut porter un deux-points dans son nom : `mirror:purge` et `test:e2e` s'appellent tels quels, et `task --list` les affiche. La page des inclusions présente déjà `espace:tache` comme le nom d'appel d'une tâche incluse ; la page de définition des tâches ne dit rien d'un deux-points dans un nom écrit à la racine. Le constat sur le poste fait foi pour v3.54.0, et le contrat task-cli garde ces noms provisoires.

Une variable posée sous `vars:` en tête d'un Taskfile inclus garde sa valeur face à la même variable passée par l'environnement (`MIRROR_IMAGE=... task show`) ou en ligne de commande (`task show MIRROR_IMAGE=...`) : les trois appels rendent la valeur du fichier. L'image du miroir vit donc sous `vars:` dans `local/tasks/local.yml`, où personne ne la remplace sans modifier le fichier, et y porte le commentaire `# renovate:` que demande l'ADR-016. `PROFILE`, à l'inverse, reste une entrée de l'utilisateur, passée par `env:` (relevé de RS-08 du 2026-11-24).

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://taskfile.dev/docs/guide/includes> | 2026-11-25 | Appel `espace:tache` d'une tâche incluse |
| Task v3.54.0 sur le poste, Taskfile d'essai | 2026-11-25 | Noms `mirror:purge` et `test:e2e` appelés et listés ; `vars:` d'un Taskfile inclus plus forte que l'environnement et que la ligne de commande |

### Relevé du 2026-11-26 : prérequis du README (T090)

Fait par [DEV], sans l'évaluation d'un moteur libre par [OPS], qui n'est pas rendue (R-26, ADR-004 condition 8). Sources officielles, lues le 2026-11-26 ; l'API de GitHub par `gh api`. Les versions du tableau sont celles des fichiers du dépôt, jamais celles d'une release lue ce jour ; S18 les compare à ces fichiers.

| Outil | Version écrite au README | Licence | Ce qui l'établit |
| --- | --- | --- | --- |
| Docker Engine | 28.0.0 ou plus sous Linux (règle de l'ADR-011, condition 3) | Apache-2.0 | La page de l'Engine donne « Apache License, Version 2.0 » ; l'API de `moby/moby` répond `Apache-2.0` |
| kind | 0.33.0 exactement (ADR-004, condition 2) | Apache-2.0 | L'API de `kubernetes-sigs/kind` répond `Apache-2.0` ; entrée du catalogue lue le 2026-11-19 ; la page de démarrage rapide donne v0.33.0 comme version courante |
| kubectl | 1.35 à 1.37, autour de la mineure 1.36 de `platform.yaml` (ADR-006, condition 5) | Apache-2.0 | L'API de `kubernetes/kubernetes` répond `Apache-2.0` ; la page de kubectl pour macOS exige une mineure d'écart au plus avec le cluster |
| Task | 3.54.0 | MIT | Relevé de T001 du 2026-11-23 ; l'API de `go-task/task` répond `MIT` le 2026-11-26 |
| Git | aucune version exigée | GPL-2.0 | La page de Git écrit « Git is released under the GNU General Public License version 2.0 » ; l'API de `git/git` répond `NOASSERTION` |
| conftest, OpenTofu, Trivy (`task check`) | 0.71.1, 1.13.9, 0.76.2 (`tests/tools/install.sh`) | Apache-2.0, MPL-2.0, Apache-2.0 | RS-18 et RS-22 pour conftest et Trivy ; l'API de `opentofu/opentofu` répond `MPL-2.0` |

Moteur libre cité d'abord : Docker Engine, le seul des moteurs lus ici qui soit libre et que les contrôles préalables couvrent. Sous macOS, le moteur tourne dans une machine virtuelle et aucun moteur libre n'est validé. Docker Desktop demande un abonnement payant à une « larger enterprise », définie par plus de 250 salariés ou plus de 10 millions de dollars de chiffre d'affaires annuel (page de l'Engine). OrbStack, moteur du poste de mesure, n'est pas libre (R-26). Podman répond `Apache-2.0` à l'API de `containers/podman` ; kind le documente, mais son évaluation et la règle des 28.0.0 qu'il enfreindrait sous Linux restent ouvertes (relevé du 2026-11-24, ci-dessus). La question reste à [OPS] et au DSI : valider un moteur libre sur macOS, ou écrire au README que la matrice ne tourne sous macOS que sur un moteur sous abonnement.

Dernières releases lues pour information, non retenues comme exigence : Docker Engine docker-v29.10.1 du 2026-11-24 ; kubectl v1.37.3, v1.36.7 et v1.35.11 du 2026-11-25 (v1.36.7 a moins de 7 jours, la CI garde v1.36.6, principe VI) ; Git v2.56.1.

Installation. Pour kind, la page de démarrage rapide donne `curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.33.0/kind-<système>-<architecture>`, `chmod +x ./kind`, puis le déplacement dans un dossier du `PATH`. Le README y ajoute la comparaison avec les quatre sommes du catalogue de CELIAN (ADR-004, condition 5), que S18 compare au fichier `catalog/kubernetes-cluster.yaml` quand le golden repo est dans CELIAN. Pour kubectl, la page officielle publie un fichier `.sha256` à côté du binaire, vérifié par `echo "$(cat kubectl.sha256)  kubectl" | shasum -a 256 --check` ; le README renvoie à cette page sans copier de somme, et la CI de CELIAN épingle sa somme dans `golden-saas-b2b.yml`.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://docs.docker.com/engine/> | 2026-11-26 | Licence Apache-2.0 de l'Engine ; conditions de Docker Desktop pour une grande entreprise |
| <https://api.github.com/repos/moby/moby> et `/releases` | 2026-11-26 | Licence `Apache-2.0` ; docker-v29.10.1 du 2026-11-24 |
| <https://api.github.com/repos/kubernetes-sigs/kind> | 2026-11-26 | Licence `Apache-2.0`, dépôt non archivé |
| <https://kind.sigs.k8s.io/docs/user/quick-start/> | 2026-11-26 | Commandes d'installation de v0.33.0 ; kind détecte docker, podman ou nerdctl |
| <https://api.github.com/repos/kubernetes/kubernetes> et `/releases` | 2026-11-26 | Licence `Apache-2.0` ; v1.37.3, v1.36.7, v1.35.11 du 2026-11-25 |
| <https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/> | 2026-11-26 | Téléchargement du binaire et de `kubectl.sha256`, vérification par `shasum -a 256 --check`, écart d'une mineure |
| <https://api.github.com/repos/go-task/task> | 2026-11-26 | Licence `MIT` |
| <https://git-scm.com/about> | 2026-11-26 | « Git is released under the GNU General Public License version 2.0 » |
| <https://api.github.com/repos/git/git> | 2026-11-26 | Licence `NOASSERTION` ; dernière étiquette v2.56.1 |
| <https://api.github.com/repos/opentofu/opentofu> | 2026-11-26 | Licence `MPL-2.0` |
| <https://api.github.com/repos/containers/podman> | 2026-11-26 | Licence `Apache-2.0` |

## RS-10. Secrets locaux

Décision : `db-auth`, `cache-auth`, `db-superuser` et `gateway-tls` en profil lite, `cache-auth` à partir de l'étape 19 (RS-11) ; valeurs de 40 caractères alphanumériques tirées de `/dev/urandom`, comme l'essai de BENCH-011, passées par un tube à `kubectl create -f -`, seulement si le Secret manque. Contrat : [contracts/secrets.md](contracts/secrets.md).

Pourquoi : ADR-007, condition 1 ; ADR-012, conditions 3, 8 et 10.

Sur `gcp`, la fabrication de `gateway-tls` est proposée à RS-16, « `gateway-tls` sur `gcp` » (étape 14, écart 177).

### Fabrication de `gateway-tls` (T071, décidée le 2026-11-26)

Porteurs : [SECU] et [DEV]. Décision de [SECU], à valider par le DSI. BENCH-004 écrivait la clé dans un fichier, ce que la condition 1 de l'ADR-007 interdit au projet généré. La clé et le certificat naissent d'un seul `openssl req`, qui les écrit tous deux sur sa sortie standard ; `awk` étiquette les deux blocs PEM au fil du flux, et le manifeste passe par un tube à `kubectl create -f -`. Aucun fichier, aucune variable, aucun argument porteur de secret, aucun heredoc, aucun `base64`.

Commande retenue, pour `create()` de `local/scripts/secrets.sh` (T073). Les noms de variables reprennent ceux du script existant :

```bash
{
  printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: gateway-tls\n  namespace: %s\ntype: kubernetes.io/tls\nstringData:\n' "$APP_NAMESPACE"
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
    -keyout /dev/stdout -out /dev/stdout -days 365 -subj '/CN=localhost' \
    -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1' \
    -addext 'basicConstraints=critical,CA:FALSE' \
    -addext 'keyUsage=critical,digitalSignature' \
    -addext 'extendedKeyUsage=serverAuth' 2>/dev/null |
    awk '/^-----BEGIN [A-Z ]*PRIVATE KEY-----$/ { print "  tls.key: |" }
         /^-----BEGIN CERTIFICATE-----$/ { print "  tls.crt: |" }
         { print "    " $0 }'
} | kube create -f - >/dev/null
```

Ce que chaque morceau décide :

- Courbe P-256 (`prime256v1`) : clé de 256 bits, certificat court. `-nodes` laisse la clé sans phrase de passe ; `-noenc`, son remplaçant dans OpenSSL 3, est refusé par le LibreSSL 3.3.6 de macOS (essai du 2026-11-26), et `-nodes` reste accepté par OpenSSL 4.1.0. La documentation d'OpenSSL le dit « deprecated since OpenSSL 3.0 » : un retrait futur ferait échouer l'essai de T073 avec un message d'option inconnue.
- `-keyout /dev/stdout -out /dev/stdout` est obligatoire. Sans `-keyout`, `req` écrit la clé dans le fichier de `default_keyfile` de la configuration : celle d'OpenSSL 4.1.0 installé par Homebrew sur ce poste porte `default_keyfile = privkey.pem` (ligne 155), donc un `privkey.pem` au dossier courant. La configuration de `/usr/bin/openssl` le garde en commentaire. La configuration d'Ubuntu n'a pas été lue : la règle ne dépend pas d'elle.
- Sujet `CN=localhost` et SAN `DNS:localhost,IP:127.0.0.1` : l'écouteur de l'étape 7 répond sur `127.0.0.1` (E03 parle à `127.0.0.1`, `Host: 127.0.0.1`), et un client qui écrit `localhost` doit aussi s'y retrouver. Pas de `::1` : le port de la gateway n'est publié que sur `127.0.0.1` (E03).
- `CA:FALSE`, `digitalSignature`, `serverAuth` : un certificat de serveur, pas une autorité. Sans ces trois `-addext`, `req -x509` ajoute `CA:TRUE` (relevé sur OpenSSL 4.1.0).
- Durée 365 jours, choix de [SECU]. La clé ne vit que dans le cluster local, que `task down` supprime avec ses Secrets : un an borne l'exposition sans imposer de renouvellement à un usage normal.
- `2>/dev/null` coupe deux bandeaux d'avancement (LibreSSL écrit « Generating a 2048 bit EC private key », trompeur : la clé fait 256 bits, relevé par `openssl pkey -text`). Une panne d'`openssl` est reprise par `pipefail` de `secrets.sh` ; si elle laisse un manifeste incomplet, l'API refuse le Secret `kubernetes.io/tls` auquel manque `tls.crt` ou `tls.key`. T073 relit ensuite les deux clés du Secret créé, comme `verify()` le fait pour les mots de passe, et supprime le Secret si l'une est vide.
- `stringData` reçoit le PEM tel quel : pas de `base64`, donc pas de différence entre le `base64` de macOS et celui de GNU. L'ordre des blocs dans le flux n'a pas d'importance, `awk` étiquette ce qui passe. `create`, et non `apply`, pour ne pas recopier la clé dans l'annotation `last-applied-configuration` (ADR-007, condition 1).

Pas de variable, parce que S04 refuse « valeur dans une variable » (plan, S04 ; contrat) et que `stringData` n'en a pas besoin. La première piste de T071 était des variables non exportées et du `base64`. Elle garde la clé en mémoire du shell, et S04 devrait alors faire une exception. La voie retenue n'en demande aucune.

Outil absent : `secrets.sh` s'arrête avec une phrase qui nomme `openssl` et `awk` si `command -v` ne les trouve pas, avant de créer quoi que ce soit. macOS fournit les deux ; les runners d'`ubuntu-latest` fournissent OpenSSL. `awk` n'est cité par aucun README de runner-images, et n'a pas été essayé sous Linux : T073 le fait tourner en CI, E04 le prouve.

Versions vérifiées le 2026-11-26. Sur le poste (macOS 27.2.1) : `/usr/bin/openssl`, LibreSSL 3.3.6, et `/opt/homebrew/bin/openssl`, OpenSSL 4.1.0 (23 oct. 2026), que `PATH` trouve en premier. La commande ci-dessus produit sur les deux un manifeste à deux blocs, `tls.key` puis `tls.crt`, contrôlé sans jamais afficher la clé ; le certificat, relu par `x509 -text`, porte `Subject: CN=localhost`, le SAN `DNS:localhost, IP Address:127.0.0.1`, `CA:FALSE`, `Digital Signature`, `TLS Web Server Authentication`, une clé de 256 bits, la signature `ecdsa-with-SHA256` et 365 jours de validité (du 2026-11-26 au 2027-11-26). Un nom de courbe inconnu fait sortir le groupe en erreur sous `pipefail` (bash 3.2.57). Aucun fichier écrit : ni clé, ni certificat, ni `privkey.pem` n'existent au dossier courant ni dans `/tmp` après les essais. `awk` du poste : version 20200816. Sur Linux, lecture seule : `ubuntu-latest` désigne Ubuntu 26.04 depuis novembre 2026 (README de runner-images), image 20261116.202.1, OpenSSL 3.5.5-1ubuntu3.7 ; le README de l'image 24.04 donne OpenSSL 3.0.13-0ubuntu3.16. La commande n'a pas été exécutée sous Linux : la CI de T073 est le premier essai, et E04 le prouve.

Refus pour S04 (T072), sur tout fichier de `local/tasks/` et `local/scripts/` :

- `openssl req` sans `-keyout /dev/stdout`, ou avec `-keyout` ou `-out` vers un autre chemin que `/dev/stdout` ; de même `openssl genpkey`, `genrsa`, `ecparam` ou `x509 -signkey` écrits vers un chemin ;
- `kubectl create secret tls`, qui exige `--cert` et `--key` comme chemins de fichiers, et `kubectl create secret generic --from-file` ou `--from-literal` ;
- une redirection `>` ou `>>`, `tee` ou `mktemp` sur la sortie d'`openssl` ;
- le PEM ou sa copie `base64` rangés dans une variable (`k=$(openssl ...)`), ou passés à `export`, à `env` ou en argument de commande ;
- `kubectl apply` d'un Secret, et un heredoc, déjà refusés par S04.

Ce que devient le certificat :

- Auto-signé, jamais installé dans le magasin de confiance du poste : aucune écriture système, aucun `sudo`, aucun trousseau. `mkcert` fait l'inverse : il installe une autorité locale dans le magasin système et écrit clé et certificat dans le dossier courant (README). Un navigateur affichera donc un avertissement sur l'écouteur HTTPS local ; le README du golden repo le dit.
- E03 (T072) ne s'appuie ni sur `-k` ni sur un magasin. Il lit le certificat servi avec `openssl s_client -connect 127.0.0.1:PORT -servername localhost` (BENCH-014 emploie déjà `s_client` avec SNI sur `127.0.0.1`), lit le certificat du Secret par `kubectl get secret gateway-tls --output 'jsonpath={.data.tls\.crt}'` suivi de `base64 -d`, et compare les deux empreintes SHA-256 de `openssl x509 -noout -fingerprint -sha256`, par tubes seulement. `base64 -d` marche sur macOS 27.2.1 (usage `-D, -d, --decode`) et sous GNU (`-d, --decode`). E03 ajoute `x509 -checkend 0` pour l'expiration. Le LibreSSL 3.3.6 n'a ni `-checkhost` ni `-checkip` sous `x509` (essai du 2026-11-26) : le SAN se contrôle par `x509 -text`, ou ne se contrôle pas au poste. Le montage de `s_client` (entrée fermée par `</dev/null`, délai) n'a pas été essayé, faute de cluster : T072 le met au point.
- Renouvellement : `task up` ne recrée `gateway-tls` que s'il manque (contrat). À l'expiration, l'écouteur sert un certificat périmé et les clients le refusent ; E03 échoue avec `-checkend`. Remède : supprimer le Secret, puis `task up`. Que la gateway recharge le nouveau certificat sans redémarrage n'a pas été vérifié : T074 l'essaie. Un avertissement de `task up` à moins de 30 jours de l'échéance est possible ; il est proposé au DSI, pas décidé.

Écartées :

| Option | Raison |
| --- | --- |
| `kubectl create secret tls` | Exige deux chemins de fichiers (`--cert`, `--key`) : la clé devrait toucher le disque |
| Variables du shell et `base64` | Marche, mais la clé vit en mémoire du shell, S04 refuse la valeur en variable, et les options de `base64` diffèrent entre macOS et GNU |
| Job dans le cluster qui crée le Secret | La clé ne passerait jamais par le poste, mais il faut une image d'`openssl` figée par condensat et scannée, un compte de service pouvant créer des Secrets, et une attente : plus de surface que le tube, pour un certificat de boucle locale. Non essayé |
| cert-manager, émetteur auto-signé | Un opérateur et ses CRD sur un profil lite (seuil de 2048 Mio de mémoire déclarée) pour un seul certificat. Non mesuré, non lu dans sa documentation |
| `mkcert` | Outil à installer, il écrit des fichiers et modifie le magasin de confiance du système (README du projet) |

Pourquoi : ADR-007, condition 1 ; ADR-006, condition 2 (aucun secret en argument). Aucune condition d'un ADR ne change : pas de complément d'ADR.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://docs.openssl.org/master/man1/openssl-req/> | 2026-11-26 | `-keyout` : fichier de la clé ; sans `-keyout` ni `-key`, le `default_keyfile` de la configuration s'applique ; `-out` : sortie standard par défaut ; `-nodes` déprécié depuis OpenSSL 3.0, `-noenc` le remplace ; `-addext`, `-days`, `-subj`, `-pkeyopt` |
| <https://docs.openssl.org/master/man1/openssl-x509/> | 2026-11-26 | `-fingerprint`, `-checkend`, `-checkhost`, `-checkip` |
| <https://man.openbsd.org/openssl.1> | 2026-11-26 | Options `req` de LibreSSL : `-addext`, `-pkeyopt`, `-nodes`, `-keyout` (« If this option is not specified, the filename present in the configuration file is used »). Page de la version courante d'OpenBSD : la présence des options dans le 3.3.6 du poste vient de `openssl req -help` et de l'essai |
| `/usr/bin/openssl version`, `openssl req -help`, `openssl x509 -help`, `/opt/homebrew/bin/openssl version` | 2026-11-26 | LibreSSL 3.3.6 : `-nodes` oui, `-noenc` non, `-addext` oui ; `x509` sans `-checkhost` ni `-checkip`. OpenSSL 4.1.0 : `-nodes` et `-noenc` oui |
| `/opt/homebrew/etc/openssl@4/openssl.cnf`, `/etc/ssl/openssl.cnf` | 2026-11-26 | `default_keyfile = privkey.pem` actif dans le premier (ligne 155), en commentaire dans le second (ligne 4) |
| <https://github.com/actions/runner-images/blob/main/README.md> | 2026-11-26 | `ubuntu-latest` désigne Ubuntu 26.04 |
| <https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2604-Readme.md> | 2026-11-26 | Image 20261116.202.1, Ubuntu 26.04.1 LTS, OpenSSL 3.5.5-1ubuntu3.7 |
| <https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md> | 2026-11-26 | Image 20261116.376.1, Ubuntu 24.04.5 LTS, OpenSSL 3.0.13-0ubuntu3.16 |
| <https://kubernetes.io/docs/concepts/configuration/secret/> | 2026-11-26 | Type `kubernetes.io/tls` : `tls.key` et `tls.crt` dans `data` ou `stringData`, l'API vérifie la présence des clés, pas leurs valeurs ; `stringData` fusionné dans `data` |
| <https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_secret_tls/> | 2026-11-26 | `kubectl create secret tls NAME --cert=path/to/cert/file --key=path/to/key/file` : deux chemins de fichiers |
| <https://man7.org/linux/man-pages/man1/base64.1.html> | 2026-11-26 | `-d, --decode` (GNU) |
| <https://github.com/FiloSottile/mkcert> | 2026-11-26 | Autorité locale installée dans le magasin système ; clé et certificat écrits dans le dossier courant ; licence BSD-3-Clause |
| `docs/benchmarks/BENCH-014-cache.md`, ligne 184 | 2026-11-26 | Précédent : réponse HTTPS lue par `openssl s_client` sur `127.0.0.1`, avec SNI |
| Essais sur le poste, `t071-trial.sh` (hors dépôt) | 2026-11-26 | Structure du manifeste, certificat relu par `x509 -text`, sortie en erreur sous `pipefail`, aucun fichier écrit |

## RS-11. Cache

Décision de Lucas (2026-11-21) : le moteur du cache passe par un benchmark court, BENCH-014, ouvert le 2026-11-21 (lectures en cours, mesures après BENCH-012 et BENCH-013), puis par son ADR, l'ADR-015, réservé. Le plan garde le cache comme une couche en attente : aucune image, aucune version ni aucune forme (Deployment, persistance) n'est figée avant l'ADR-015, sur `local` comme sur `gcp`. Le moteur de Memorystore et son authentification, que l'ADR-008 laissait ouverts (chaîne AUTH écrite en clair dans l'état), entrent dans le même benchmark.

Ce que le plan fixe sans attendre, parce que rien n'y dépend du moteur :

- le Secret `cache-auth`, son nom et sa lecture par fichier, communs aux deux cibles ([contracts/secrets.md](contracts/secrets.md)) ; ses clés exactes suivent l'ADR-015 ;
- le mot de passe jamais en argument de commande (ADR-006, condition 2), contrôlé par S11 ;
- les clés d'`app-config` pour l'hôte, le port et le mode TLS du cache ;
- l'accès au cache dans l'API derrière une interface, testée par U01 avec un double ; le client concret entre à l'étape 19.

Effet sur les étapes : la partie cache de l'étape 8 devient l'étape 19 (couche cache locale). La ressource Memorystore de l'étape 13 et le producteur `gcp` de `cache-auth` deviennent l'étape 20. L'étape 9, qui démarre le profil lite de bout en bout, dépend de l'étape 19 : sans cache, FR-001 n'est pas tenu.

Ce qui avance sans BENCH-014. L'étape 6 (cluster et miroir) ne contient aucun fichier du cache. Son seul lien avec lui est la liste des registres du miroir : docker.io y entre déjà pour Postgres. Si l'ADR-015 retient une image d'un autre registre, l'étape 19 l'ajoute à la liste et rejoue E10 (ADR-011, condition 10), après le réglage du montage à plusieurs amonts (RS-13). L'étape 6 de `task up`, qui crée les Secrets, avance aussi : elle crée `db-auth` et `db-superuser`, et l'étape 19 ajoute `cache-auth` à la même tâche. Avancent de même les étapes 1 à 5 et 7, l'étape 8 sans le cache, l'étape 13 sans Memorystore et la première PR de l'étape 18.

Repère, et non choix : l'essai de BENCH-005 utilisait `valkey/valkey:9.1.4-alpine`, 18,8 Mo en amd64, que l'estimation de volume de R-04 compte encore.

À vérifier à l'entrée de l'étape 19 (porteurs [DEV] et [SECU]) : la façon de passer le mot de passe au moteur retenu sans argument, sur sa documentation ; le mode TLS face à Memorystore ; le client .NET, avec sa version, sa licence et sa date. RESP est un protocole conçu pour Redis, que parlent les clients de Valkey (ADR-009, sources) ; que toutes les options de BENCH-014 le parlent, ce qui garderait l'interface de l'API telle quelle, est à confirmer par [BENCH].

Sources : décision de Lucas du 2026-11-21 ; BENCH-014, brouillon du 2026-11-21 ; ADR-006, condition 2 ; ADR-008, portée et condition 3 ; ADR-009, section 2 et sources ; BENCH-005, section 4.4 ; `tests/bench/bench-005-orchestration.sh`, ligne 108.

### Relevé du 2026-11-26 : Memorystore for Valkey et le provider `google` 8.12.0 (étape 20, T136)

Fait par [OPS], pour T136. Rien n'a contacté Google Cloud : aucun plan, aucun apply, aucun identifiant, aucun backend. Le provider se lit dans le dépôt officiel, au tag `v8.12.0` (commit `5d2ae61997230ec12262ca575657308dbcbfa70b`), par `gh api` : pages `website/docs/r/` et code `google/services/` du tag. Les pages de Google se lisent par WebFetch, c'est-à-dire résumées par un petit modèle : les citations sont celles qu'il a rendues, et chaque point décisif se relit sur la page avant la GATE 2.

Ce qui change la suite : `google_memorystore_auth_token` n'existe pas dans `google` 8.12.0. Le dossier `google/services/memorystore/` du tag ne contient que `acl_policy`, `instance` et `instance_desired_user_created_endpoints` (ressources) et `acl_policy` et `instance` (sources de données) ; `website/docs/r/` n'a aucune page `memorystore_auth_token`. Sur la branche `main` du dépôt (commit `4cadca0cf`, du 2026-11-25 à 21:30 UTC), la ressource et sa source de données existent, ainsi que `google_memorystore_token_auth_user` : commits `fb0c73b6e` (2026-11-18 à 22:08 UTC, « add google_memorystore_auth_token resource and data source », #30751) et `866b42eb7` (2026-11-18 à 20:28 UTC, #30746). Le `CHANGELOG.md` de `main` ouvre « 8.13.0 (Unreleased) » sans aucune ligne. La dernière release est `v8.12.0`, du 2026-11-17 à 19:43 UTC ; aucune `v8.13.0` n'existe le 2026-11-26. Les quatre releases précédentes datent du mardi (2026-10-27, 11-03, 11-10, 11-17) : ce rythme ne date pas la prochaine. C'est l'écart que l'ADR-015 (condition 18) prévoyait : le jeton et son secret de Secret Manager ne sont pas écrits, et la version figée ne change pas.

Suite proposée au DSI, qui tranche. Attendre la release qui apporte la ressource, puis 7 jours (principe VI) ; [SECU] lit alors sa page ; la seconde PR de l'étape 20 écrit le jeton et son secret. Renovate proposera la montée du provider une fois la release publiée depuis 7 jours (ADR-008, version du provider). À la publication, on vérifie que le tag contient bien la ressource (même lecture qu'ici). Aucune voie ne contourne l'attente avec le provider figé : le jeton ne se lit dans aucun attribut ni aucune source de données de 8.12.0 (liste des fichiers ci-dessus), et la condition 18 refuse `gcloud`, un script, un jeton recopié et un `output`. La voie IAM ouvre son propre ADR et du code propre à `gcp` dans l'API (condition 17). Aucune exception de sécurité n'est en jeu : le principe VI ne l'admet que pour un correctif d'avis.

Ce que dit la page de la ressource sur `main`, pour la seconde PR et pour [SECU]. Arguments : `instance` (identifiant ou nom), `user_id` (le compte, `default` ici), `location`, `token_id` facultatif. Avec `TOKEN_AUTH`, le service crée un premier jeton `version-1` ; `token_id = "version-1"` le reprend dans l'état, une erreur survient s'il n'existe pas ; sans `token_id`, un nouveau jeton `version-N` est créé. Un compte porte deux jetons actifs au plus et en garde un au moins : la rotation sans coupure déclare deux ressources, bascule les clients, puis retire l'ancienne. L'attribut `token` est calculé, sensible, et la page avertit qu'il est « stored in the raw state as plain text » : ce n'est pas un attribut en écriture seule. L'état chiffré de l'ADR-008 (condition 2) le couvre, comme le disait l'ADR-015 ; `secret_data_wo` l'envoie ensuite à Secret Manager sans le garder dans l'état de la version du secret. Supprimer le seul jeton restant est refusé par l'API (`deletion_policy = "ABANDON"` l'évite). La page est celle de `main`, pas d'une release : elle se relit à la publication.

Attributs de `google_memorystore_instance`, d'après la page et le code de `resource_memorystore_instance.go` au tag :

- Requis : `shard_count`, `location`, `instance_id` (4 à 63 caractères, minuscules, chiffres et tirets, sans tiret final).
- `mode` : `CLUSTER` ou `CLUSTER_DISABLED`, `ForceNew` dans le code ; l'API le dit immuable et ajoute que le passage d'un mode à l'autre est impossible après la création. `replica_count` : « If omitted the default is 0 replicas ». `node_type` : `SHARED_CORE_NANO` et neuf autres valeurs, dont `CUSTOM_PICO`.
- `authorization_mode` : `AUTH_DISABLED`, `IAM_AUTH`, `TOKEN_AUTH`, modifiable. `transit_encryption_mode` : `TRANSIT_ENCRYPTION_DISABLED` ou `SERVER_AUTHENTICATION`, « Immutable », `ForceNew`.
- `server_ca_mode` : `GOOGLE_MANAGED_PER_INSTANCE_CA` (valeur par défaut, d'après la page), `GOOGLE_MANAGED_SHARED_CA`, `CUSTOMER_MANAGED_CAS_CA` (avec `server_ca_pool`), `ForceNew` ; la référence REST de l'API dit « Immutable ». Sortie `managed_server_ca.ca_certs.certificates` : la chaîne de la CA en PEM, remplie seulement avec `SERVER_AUTHENTICATION`.
- `engine_configs` : table de chaînes ; l'exemple du provider écrit `maxmemory-policy`. `engine_version` : chaîne, valeur facultative et calculée. Les exemples et les tests du tag écrivent `VALKEY_7_2`, `VALKEY_8_0` et `VALKEY_9_0`, jamais `VALKEY_9_1`. La page de Google sur la création d'une instance liste pour `--engine-version` de gcloud `VALKEY_7_2`, `VALKEY_8_0`, `VALKEY_9_0` et `VALKEY_9_1`, et donne `VALKEY_9_1` pour défaut. La référence REST décrit `engineVersion` comme une chaîne libre, sans énumération : la valeur `VALKEY_9_1` repose donc sur la page de gcloud, pas sur le provider ni sur la référence de l'API (à vérifier au premier plan de l'utilisateur, avec son accord).
- `persistence_config.mode` : `DISABLED`, `RDB`, `AOF`. `automated_backup_config` : bloc facultatif, 35 jours de rétention par défaut s'il est écrit. Aucune sauvegarde n'est écrite.
- `deletion_protection_enabled`, `labels` (non autoritaire, `effective_labels` porte le reste), `desired_auto_created_endpoints` (`network` au format `projects/{project_id}/global/networks/{network_id}` et `project_id`, requis ; l'attribut est immuable ; `ip_version` est en bêta).
- `google_memorystore_acl_policy` : un bloc `rules` avec `rule` (l'exemple de la page est `on >password123 ~* +@all`) et `username`.

Politique de connexion de service, page de `google_network_connectivity_service_connection_policy` : requis `service_class`, `network`, `name`, `location` ; `psc_config.subnetworks` est requis ; `psc_config.limit` est une chaîne dans le schéma, un nombre écrit en HCL est converti ; `labels` existe. Aucun argument ne porte de port.

Ports (page de Google sur le réseau de Memorystore for Valkey, lue par WebFetch). Les clients se connectent « by using an IP address and the 6379 port » ; chaque nœud emploie un port de la plage 11000 à 13047 ; la page demande d'autoriser dans le pare-feu 6379 et tous les ports de cette plage, et ne les distingue pas par mode. Elle ne dit pas que le mode sans cluster n'emploie que 6379 : l'ADR-015 (condition 7) demandait « les seuls ports du mode sans cluster », et rien de lu ne l'établit. La politique de connexion n'a pas de port à régler : seul un pare-feu du VPC pourrait les limiter, et cette PR n'en écrit aucun. Ce que le pare-feu implicite du VPC fait de ces ports n'a pas été lu : à lire avant la GATE 2.

Politique de connexion, d'après la même page : une politique par réseau, région et classe de service ; la limite de connexions vaut le nombre d'instances de la région fois deux, et peut rester vide ; « Memorystore for Valkey doesn't support custom service instance scopes » et le gestionnaire du réseau « must leave the default settings for the policy » ; les API Network Connectivity et Service Consumer Management doivent être activées. La page n'indique ni la plage ni le sous-réseau que l'instance emploie pour son point de terminaison.

API à activer, d'après la page de création d'instance : Memorystore for Valkey, Network Connectivity et Service Consumer Management ; les noms de service `memorystore.googleapis.com`, `networkconnectivity.googleapis.com` et `serviceconsumermanagement.googleapis.com` viennent des liens de la page, que le modèle a recopiés, et non du texte.

Choix de la CA (S63), proposé par [OPS], relu par [SECU] : une CA par instance (`GOOGLE_MANAGED_PER_INSTANCE_CA`), écrite. Raisons. Le réglage est immuable : il se décide avant le premier apply. Avec la CA régionale, la page de Google dit qu'un seul bundle « is valid for all instances located in a region that you configure to use the shared CA » : un client qui fait confiance à cette CA n'a plus rien qui distingue le cache des autres instances de la région qui l'emploient. [SECU] l'a noté à l'étape 19 pour `VerifyCA` : le client ne contrôlerait que la chaîne, et toute instance de la région sous cette CA pourrait se faire passer pour le cache. Avec une CA par instance, la confiance s'arrête à cette instance. La CA gérée par le client demande Certificate Authority Service, un service de plus et un coût non lu, hors du MVP. Le prix de la CA par instance : le fichier PEM doit atteindre chaque pod, par le ConfigMap de la seconde PR, et la page de Google dit que chaque instance a ses propres certificats à installer sur chaque client. La même page décrit une rotation hebdomadaire des certificats serveur sans dire si le paquet de la CA change : si oui, un ConfigMap figé en dépôt se périme. Ce point reste à lever par [OPS] et [SECU] avant la seconde PR. Relevé de [SECU] du 2026-11-26 : le ConfigMap porte toutes les CA de `caCerts[]` et se rafraîchit à une échéance écrite au README ; recréer l'instance (`ForceNew` : mode TLS ou mode de CA) change la CA (écart 90 de `tasks.md`).

Ce qui n'est pas vérifié : la valeur `VALKEY_9_1` auprès de l'API ; les ports du mode sans cluster ; que la politique de connexion au sous-réseau de GKE suffise à créer le point de terminaison (la page ne dit pas où il se place) ; le comportement de `TOKEN_AUTH` sans `acl_policy` (le compte `default` reçoit-il toutes les commandes ?) ; le contenu de l'attribut `managed_server_ca` au premier apply ; la durée de vie du paquet de CA ; les noms des API, copiés d'un résumé. Chacun se lit au premier apply autorisé par Lucas (GATE 2).

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://github.com/hashicorp/terraform-provider-google>, arbre du tag `v8.12.0` (`gh api` sur `git/trees/v8.12.0?recursive=1`), commit `5d2ae61997230ec12262ca575657308dbcbfa70b` | 2026-11-26 | Aucune ressource ni source `memorystore_auth_token` ; fichiers de `google/services/memorystore/` |
| Même dépôt, arbre de `main` (commit `4cadca0cf`, 2026-11-25) et historique de `resource_memorystore_auth_token.go` | 2026-11-26 | Ressource et source `auth_token` présentes sur `main` ; commits `fb0c73b6e` et `866b42eb7` du 2026-11-18 |
| <https://github.com/hashicorp/terraform-provider-google/blob/main/website/docs/r/memorystore_auth_token.html.markdown> | 2026-11-26 | Arguments, `token_id`, deux jetons au plus, `token` en clair dans l'état ; page de `main`, pas d'une release |
| <https://github.com/hashicorp/terraform-provider-google/blob/main/CHANGELOG.md> et la liste des releases (`gh api repos/hashicorp/terraform-provider-google/releases`) | 2026-11-26 | « 8.13.0 (Unreleased) » vide ; `v8.12.0` du 2026-11-17 à 19:43 UTC, dernière ; releases du mardi depuis le 2026-10-27 |
| <https://github.com/hashicorp/terraform-provider-google/blob/v8.12.0/website/docs/r/memorystore_instance.html.markdown> et `google/services/memorystore/resource_memorystore_instance.go` au même tag | 2026-11-26 | Arguments, valeurs, `ForceNew`, `server_ca_mode`, `desired_auto_created_endpoints`, `managed_server_ca` |
| <https://github.com/hashicorp/terraform-provider-google/blob/v8.12.0/website/docs/r/memorystore_acl_policy.html.markdown> | 2026-11-26 | Bloc `rules`, `rule`, `username` |
| <https://github.com/hashicorp/terraform-provider-google/blob/v8.12.0/website/docs/r/network_connectivity_service_connection_policy.html.markdown> et le code du même tag | 2026-11-26 | Arguments requis, `psc_config`, `limit` en chaîne, aucun port |
| <https://docs.cloud.google.com/memorystore/docs/valkey/supported-versions> | 2026-11-26 | Versions 7.2, 8.0, 9.0, 9.1 ; défaut 9.1 ; dernière mise à jour de la 9.1 : 2026-07-27 |
| <https://docs.cloud.google.com/memorystore/docs/valkey/create-instances> | 2026-11-26 | Valeurs de `--engine-version`, défaut `VALKEY_9_1`, pas de retour en arrière ; mode sans cluster : un seul shard ; trois API à activer |
| <https://docs.cloud.google.com/memorystore/docs/valkey/networking> | 2026-11-26 | Ports 6379 et 11000 à 13047 ; politique de connexion de service, limite, réglages par défaut |
| <https://docs.cloud.google.com/memorystore/docs/valkey/about-in-transit-encryption> | 2026-11-26 | Modes de CA, bundle par région pour la CA partagée, rotation hebdomadaire, aucune recommandation |
| <https://docs.cloud.google.com/memorystore/docs/valkey/reference/rest/v1/projects.locations.instances> | 2026-11-26 | `serverCaMode`, `mode`, `transitEncryptionMode` « Immutable » ; `engineVersion` chaîne libre |
| `engine_version` dans `google/services/memorystore/resource_memorystore_instance.go` au tag `v8.12.0` | 2026-11-26 | `TypeString`, facultatif et calculé, sans `ValidateFunc` : le provider n'énumère aucune valeur |
| Pages lues par [SECU] : <https://docs.cloud.google.com/memorystore/docs/valkey/manage-in-transit-encryption>, <https://docs.cloud.google.com/memorystore/docs/valkey/about-in-transit-encryption>, <https://docs.cloud.google.com/memorystore/docs/valkey/networking>, <https://docs.cloud.google.com/memorystore/docs/valkey/create-instances> (section « Before you begin ») | 2026-11-26 | Récupération des CA (`caCerts[]`), rotation, ports 6379 et 11000 à 13047, politique de connexion ; les trois noms d'API de `apis.tf` confirmés. Relevé de [SECU], non relu par [OPS] |

### Relevé du 2026-11-25 (T075, étape 19)

Fait par [DEV] le 2026-11-25, après la fusion de l'ADR-015 (#67). [SECU], second porteur de T075, relit ce relevé avec la PR de l'étape 19.

Ce que l'ADR-015 fixe. Image `docker.io/valkey/valkey:9.1.4-alpine@sha256:56729e68bdda139cbd3f6a2538683dc3523325fc5711ea1a379938f1b37893f0`, condensat d'index, tag poussé le 2026-11-18 à 23:11:58 UTC : le délai de 7 jours s'achève le 2026-11-25 à 23:12 UTC, et la PR ne fusionne pas avant, sauf exception de sécurité (décision, condition 2). Un Deployment d'une réplique sans persistance dans la couche `local`, en lite comme en standard. Registre docker.io, déjà dans `local/mirror/registries` : rien n'est ajouté au miroir, et E10 n'a pas à être rejoué pour un amont neuf. Secret `cache-auth`, type `Opaque`, clé unique `password`, même nom et même clé sur `gcp`. Ligne 9.1, valeur unique des deux couches (condition 16) : elle entre dans `platform.yaml` sous la clé neutre `cache_engine_line`, puisque la couche commune ne nomme pas le moteur (condition 17).

Mot de passe sans argument. Le serveur ne reçoit que le chemin de son fichier de configuration. Le conteneur d'initialisation lit le fichier du Secret, en calcule l'empreinte SHA-256 par l'entrée standard, et écrit la ligne ACL du compte `default` avec `#<empreinte>`. Valkey 9.1.4 accepte après `#` exactement 64 caractères hexadécimaux minuscules, et compare l'empreinte SHA-256 du mot de passe présenté à celle qu'il garde (`src/acl.c`, lignes 214 à 256 et 1419 à 1431). Quand la configuration décrit `default`, le compte est d'abord remis à zéro (`reset`, lignes 2432 à 2452) : sans mot de passe, sans clé, sans commande, désactivé ; la ligne doit donc tout redonner (`on`, `~*`, `&*`, `+@all`). Les règles se lisent de gauche à droite (`valkey.conf`, ligne 1169) : les refus viennent après `+@all`. `requirepass` n'est qu'une couche de compatibilité sur le compte `default` (ligne 1228) et `rename-command` est déprécié (ligne 1249) : aucun des deux n'est écrit. `save ""` coupe les instantanés (ligne 566), `appendonly no` est le défaut (ligne 1583). `64mb` vaut 64 × 1024 × 1024 octets (lignes 8 à 18). `allkeys-lru` évince n'importe quelle clé selon un LRU approché (ligne 1323). `enable-protected-configs`, `enable-debug-command` et `enable-module-command` valent `no` par défaut (lignes 133 à 135) ; le conteneur d'initialisation les écrit quand même, pour que S11 les lise.

Commandes refusées. La page des commandes de Memorystore for Valkey, relue ce jour par un outil qui résume, renvoie `NOPERM` pour `ACL` (`DELUSER`, `DRYRUN`, `GETUSER`, `LIST`, `LOAD`, `LOG`, `SAVE`, `SETUSER`, `USERS`, `CAT`, `GENPASS`, `HELP`, `WHOAMI`), `BGREWRITEAOF`, `BGSAVE`, `CLIENT` (`NO-EVICT`, `PAUSE`, `UNBLOCK`, `UNPAUSE`), quatorze sous-commandes de `CLUSTER`, `CONFIG` (`GET`, `RESETSTAT`, `REWRITE`, `SET`), `DEBUG`, `FAILOVER`, `LASTSAVE`, `MIGRATE`, `MODULE` (`LIST`, `LOAD`, `LOADEX`, `UNLOAD`), `MOVE`, `PFDEBUG`, `PFSELFTEST`, `PSYNC`, `REPLCONF`, `REPLICAOF`, `RESTORE-ASKING`, `SAVE`, `SHUTDOWN`, `SLAVEOF`, `SLOWLOG` (`GET`, `LEN`, `RESET`), `SWAPDB`, `SYNC` et `XSETID`. Elle permet `EVAL`, `FUNCTION`, `MONITOR`, `KEYS`, `FLUSHALL`, `INFO`, et parmi les sous-commandes de `CLIENT` : `ID`, `INFO`, `KILL`, `LIST`, `SETNAME` entre autres. Les catégories de chaque commande se lisent dans `src/commands/<commande>.json` au tag 9.1.4. Toutes celles que Memorystore bloque sont dans `@admin`, sauf neuf : `ACL CAT`, `ACL GENPASS`, `ACL HELP` et `ACL WHOAMI` (`@slow` seulement), `MIGRATE` et `RESTORE-ASKING` (`@keyspace`, `@write`, `@dangerous`), `MOVE` et `SWAPDB` (`@keyspace`, `@write`), `XSETID` (`@stream`, `@write`). La ligne retenue refuse donc, après `-@admin`, la commande `ACL` entière et ces cinq commandes : `user default on #<empreinte> ~* &* +@all -@admin -@scripting -acl -migrate -move -restore-asking -swapdb -xsetid`. `INFO` est dans `@dangerous` et `@slow`, hors de `@admin` : elle passe (condition 16). `MONITOR`, `ROLE`, `CLIENT LIST` et `CLIENT KILL` sont dans `@admin` : le poste les refuse quand Memorystore en permet trois, ce qui rend `local` plus strict, comme le veut l'ADR.

Client .NET. Deux candidats parlent RESP et servent les deux cibles :

| Paquet | Version retenue ou lue | Publiée le (nuget.org) | Licence | Gouvernance | Adoption (nuget.org, 2026-11-25) | Code natif |
| --- | --- | --- | --- | --- | --- | --- |
| `StackExchange.Redis` | 3.4.35 | 2026-11-12 14:13 | MIT | trois mainteneurs, propriétaires à titre personnel selon le ticket #3326 (lu par [SECU] le 2026-11-26), de l'organisation `seredis` et de ses clés NuGet depuis son transfert du 2026-11-09 par un employé de Stack Overflow, employeurs non vérifiés, aucune fondation ; ligne 3 depuis 3.0.0 du 2026-06-12, ligne 2.13 encore corrigée (2.13.23 du 2026-11-02) | 1,4 milliard de téléchargements ; 703 563 pour 3.4.35 | aucun |
| `Valkey.Glide` | 1.2.0 | 2026-11-18 05:43 | Apache-2.0 | projet Valkey, LF Projects ; 1.0.0 du 2026-04-18 | 343 000 téléchargements | `libglide_rs` en Rust, un binaire par plate-forme (`runtimes/linux-x64`, `linux-arm64`, `osx-*`, `win-*`) |

Retenu : `StackExchange.Redis` 3.4.35, publié depuis 13 jours. Sa documentation dit ce que le client envoie et comment le restreindre (voir plus bas), et son code est entièrement managé : Trivy le voit par les `*.deps.json` de l'image, ce qu'il ne ferait pas du moteur Rust de GLIDE, qui rejouerait R-36 dans l'API. Le principe V préférerait GLIDE, porté par une fondation ; son adoption, environ un quatre-millième de celle de StackExchange.Redis, et son âge, sept mois de version stable, pèsent plus ici que la gouvernance de StackExchange.Redis, qui n'est pas celle d'une fondation : trois mainteneurs, propriétaires à titre personnel selon le ticket #3326, employeurs non vérifiés, aucune fondation. Le choix est une dérogation écrite au principe V, non une conformité (voir l'écart 121 de [tasks.md](tasks.md)). Décision de [DEV] dans le périmètre que l'ADR-015 lui laisse (« Portée ») ; le DSI peut la rouvrir, et l'ADR de l'authentification IAM la relira, GLIDE ayant un fournisseur IAM et StackExchange.Redis non (S61 de BENCH-014). Dépendances pour `net10.0` : `RESPite` 3.4.35 (2026-11-12 14:12, MIT, mêmes auteurs), `System.IO.Hashing` au moins 10.0.13 (10.0.13 du 2026-10-13, MIT, Microsoft) et `Microsoft.Extensions.Logging.Abstractions` au moins 10.0.13, fournie par le framework partagé d'ASP.NET Core. Aucun avis de sécurité publié sur le dépôt.

Ce que le client envoie. La section « Redis Server Permissions » (lignes 227 à 246 de `docs/Configuration.md` au tag 3.4.35) liste `AUTH`, `CLIENT` (nom de la connexion), `INFO`, `ECHO`, puis en option `SUBSCRIBE`, `CONFIG`, `CLUSTER`, `SENTINEL`, `GET` pour le départage et `SET` si `INFO` manque. Une commande refusée par l'ACL doit aussi être retirée par la `CommandMap`, sinon le client l'essaie et la poignée de main échoue (ligne 246). `HELLO` est toujours envoyé, en `@connection` (lignes 413 à 425). Retenu : `CONFIG`, dans `@admin` et bloquée par Memorystore, sort de la `CommandMap` ; `TieBreaker` et `ConfigurationChannel` valent `""` (ligne 278), si bien que ni `GET __Booksleeve_TieBreak` ni `SUBSCRIBE` ne partent. Aucune commande de `@scripting` n'est dans la liste : `-@scripting` est retenu (condition 4). E13 rejoue sous l'ACL, avec `valkey-cli`, chaque commande de cette liste ; E02 de l'étape 9 vérifie le client lui-même par une note relue depuis le cache. `AbortOnConnectFail` à `false` rend un client qui se reconnecte seul, au lieu d'une exception au démarrage. `BacklogPolicy.FailFast` ne met aucune commande en file pendant une coupure (`src/StackExchange.Redis/BacklogPolicy.cs`, lignes 15 à 18) : la lecture retombe sur la base et `/api/readyz` répond sans attendre. `ConfigurationOptions.ToString()` écrit le mot de passe en clair par défaut (`ConfigurationOptions.cs`, ligne 1257) ; la bibliothèque, elle, journalise avec `includePassword: false` (`LoggerExtensions.cs`, ligne 25). L'API n'imprime jamais ces options.

TLS face à Memorystore. Memorystore for Valkey parle TLS 1.2 et plus, refuse un client sans TLS, et propose une CA par instance, une CA régionale distribuée en paquet, ou une CA du client ; la page ne dit pas si le certificat du serveur nomme le point de terminaison de Private Service Connect. `TrustIssuer` de StackExchange.Redis ne charge qu'un certificat et refuse toute erreur autre qu'une erreur de chaîne, nom compris (`ConfigurationOptions.cs`, lignes 539 et 599 à 670). Retenu : `CACHE_TLS_MODE` à `Disable`, `VerifyCA` ou `VerifyFull`, et une clé de plus, `CACHE_TLS_CA_FILE`, chemin du paquet PEM de la CA monté par la couche de cible (condition 17 : la référence de la CA vient d'`app-config`). En `VerifyCA` et `VerifyFull`, l'API valide la chaîne contre tous les certificats du paquet, et seulement eux ; `VerifyFull` exige en plus que le nom corresponde. `local` écrit `Disable` ; l'étape 20 choisit entre les deux autres quand [OPS] aura lu le certificat servi.

Sonde et contrôles. `valkey-cli` lit le mot de passe dans `VALKEYCLI_AUTH`, puis dans `REDISCLI_AUTH` (`src/valkey-cli.c`, lignes 92, 93 et 2927 à 2929), ce que son aide présente comme le passage sûr (ligne 2987) : le pod de sonde de `task up` et de E13 le reçoit par `secretKeyRef`, jamais en argument. La condition 5 ne refuse l'environnement que sur le conteneur du cache. L'image démarre par `tini -- docker-entrypoint.sh`, dont la dernière ligne est `exec "$@" $VALKEY_EXTRA_FLAGS` ; elle ne déclare aucun `USER`, crée `valkey` en UID 999 et GID 1000, et travaille dans `/data` (`9.1/alpine/Dockerfile`, lignes 101, 102, 127 et 130, au commit `32d10db6`). Une NetworkPolicy laisse toujours passer ce qui vient du nœud du pod : la sonde TCP du kubelet atteint le serveur malgré l'isolement en entrée. Un pod isolé en sortie n'ouvre que ce que liste une règle `egress` : sans règle, rien.

Essai sur le golden repo, le 2026-11-26 (kind 0.33.0, arm64). Sous l'ACL retenue, `INFO server` passe et donne `valkey_version:9.1.4` ; `HELLO 2`, `CLIENT SETNAME`, `CLIENT SETINFO`, `CLIENT ID`, `ECHO`, `SELECT`, `CLUSTER NODES`, `SET`, `GET`, `EXPIRE` et `DEL` passent ; `CONFIG GET`, `CONFIG SET`, `SAVE`, `BGSAVE`, `ACL LIST`, `ACL WHOAMI`, `ACL CAT`, `MODULE LIST`, `SLOWLOG GET`, `CLIENT LIST`, `SWAPDB`, `MOVE`, `MIGRATE`, `XSETID`, `LASTSAVE`, `EVAL` et `FUNCTION LIST` reçoivent `NOPERM`. `DEBUG` est refusé avant l'ACL, comme commande protégée, tant que `enable-debug-command` vaut `no` (`src/server.c`, `processCommand`, au tag 9.1.4). Le `sha256sum` et le `grep -E` de BusyBox de l'image suffisent au conteneur d'initialisation. Détail : écart 126 de [tasks.md](tasks.md).

Effets : `platform.yaml` (`cache_engine_line`), `local/data/cache/`, `local/scripts/cache.sh`, `src/Api/Caching/`, clé `CACHE_TLS_CA_FILE` et valeurs de `CACHE_TLS_MODE` dans [contracts/layers.md](contracts/layers.md), S11, S21, S23, E13 et U01.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| [ADR-015](../../docs/adr/ADR-015-cache.md), décision, conditions 1 à 19 | 2026-11-25 | Image, condensat, date du tag, forme, persistance, registre, clés de `cache-auth`, ligne 9.1 |
| <https://github.com/valkey-io/valkey/blob/9.1.4/src/acl.c> | 2026-11-25 | Lignes 214 à 256 (empreinte SHA-256 en hexadécimal minuscule), 1419 à 1431 (`>` et `#`), 2432 à 2452 (`default` remis à zéro) |
| <https://github.com/valkey-io/valkey/blob/9.1.4/valkey.conf> | 2026-11-25 | Unités, `protected-mode`, `enable-*`, `save ""`, format `user`, ordre des règles, `requirepass`, `rename-command`, `maxmemory-policy`, `appendonly` |
| <https://github.com/valkey-io/valkey/tree/9.1.4/src/commands> | 2026-11-25 | `command_flags` et `acl_categories` des commandes bloquées par Memorystore, d'`INFO`, `MONITOR`, `ROLE`, `CLIENT *`, `HELLO`, `ECHO`, `EVAL`, `FUNCTION`, lus par `gh api` |
| <https://github.com/valkey-io/valkey/blob/9.1.4/src/valkey-cli.c> | 2026-11-25 | `VALKEYCLI_AUTH`, `REDISCLI_AUTH`, aide, option `-t` |
| <https://github.com/valkey-io/valkey/blob/9.1.4/src/server.c> | 2026-11-26 | `processCommand` : le refus des commandes protégées passe avant celui de l'ACL |
| <https://github.com/valkey-io/valkey-container/blob/32d10db6/9.1/alpine/docker-entrypoint.sh> et `9.1/alpine/Dockerfile` | 2026-11-25 | `exec "$@" $VALKEY_EXTRA_FLAGS`, utilisateur 999:1000, `WORKDIR /data`, `tini` |
| <https://docs.cloud.google.com/memorystore/docs/valkey/supported-commands> | 2026-11-25 | Commandes bloquées et permises ; aucune date de mise à jour visible ; lue par un outil qui résume |
| <https://docs.cloud.google.com/memorystore/docs/valkey/about-in-transit-encryption> | 2026-11-25 | TLS 1.2 et plus, trois modes de CA, rotation hebdomadaire, client sans TLS bloqué ; rien sur le nom du certificat ; lue par un outil qui résume |
| <https://api.nuget.org/v3/registration5-semver1/stackexchange.redis/3.4.35.json> et l'entrée de catalogue `2026.11.12.14.18.21` | 2026-11-25 | `published`, licence MIT, auteurs, dépendances de `net10.0` |
| <https://api.nuget.org/v3/registration5-semver1/respite/3.4.35.json>, idem `system.io.hashing/10.0.13.json`, et leurs entrées de catalogue | 2026-11-25 | Dates, licences, aucune dépendance pour `net10.0` |
| <https://api.nuget.org/v3/registration5-semver1/valkey.glide/1.2.0.json> et l'entrée de catalogue `2026.11.18.05.48.12` | 2026-11-25 | Date, Apache-2.0, binaires natifs par plate-forme, cible `net8.0` |
| <https://www.nuget.org/packages/StackExchange.Redis>, <https://www.nuget.org/packages/Valkey.Glide> | 2026-11-25 | Téléchargements ; lues par un outil qui résume |
| <https://github.com/seredis/StackExchange.Redis>, releases et `security-advisories` par `gh api` ; ticket #3326 | 2026-11-25 | 3.0.0 du 2026-06-12, 3.4.35 du 2026-11-12, aucun avis, transfert vers `seredis` |
| <https://github.com/StackExchange/StackExchange.Redis/issues/3326> | 2026-11-26 ([SECU]) | Propriété de l'organisation `seredis` et des clés NuGet par trois mainteneurs, transfert du 2026-11-09 ; employeurs non vérifiés, aucune fondation |
| <https://github.com/valkey-io/valkey-glide-csharp>, releases par `gh api` | 2026-11-25 | 1.0.0 du 2026-04-18, 1.2.0 du 2026-11-18, Apache-2.0 |
| <https://github.com/seredis/StackExchange.Redis/blob/3.4.35/docs/Configuration.md> et `docs/Authentication.md` | 2026-11-25 | Options, permissions du client, `CommandMap`, départage et canal de configuration, `HELLO`, TLS et `TrustIssuer` |
| <https://github.com/seredis/StackExchange.Redis/blob/3.4.35/src/StackExchange.Redis/ConfigurationOptions.cs>, `BacklogPolicy.cs`, `LoggerExtensions.cs` | 2026-11-25 | `TrustIssuer`, `ToString()` et le mot de passe, `FailFast` |
| <https://kubernetes.io/docs/concepts/services-networking/network-policies/> | 2026-11-25 | Trafic du nœud toujours admis en entrée ; isolement en sortie ; lue par un outil qui résume, jusqu'au caractère 100 000 sur 122 840 |

## RS-12. Postgres local

Décision : l'ADR-012 tel quel, accepté par Lucas le 2026-11-21. Namespace unique pour la base et l'application, comme le propose sa condition 9 : réponse de Lucas à la question 1, `task app:down` efface la donnée locale avec ses deux Secrets. La dérogation à ENF-03 se relit au plus tard le 2027-05-20, et par [SECU] à chaque montée de condensat (question 2) ; elle reste sans effet dans le golden repo, qui n'embarque pas Kyverno.

Restent à faire sur le golden repo, d'après les suites de l'ADR-012 : `readOnlyRootFilesystem`, l'effet de `pg_isready` sur les journaux, le script d'initialisation sous `scram-sha-256` local, l'état TLS du serveur.

### Relevé du 2026-11-25 : image, TLS, durcissement et sonde de Postgres (T062, étape 8)

Fait par [OPS], second porteur [DEV] et relecture [SECU] attendues sur la PR. Sources : l'API de Docker Hub, l'historique de `docker-library/repo-info` et le code de `docker-library/postgres` lus par `gh api` ou WebFetch, `docker buildx imagetools inspect` en lecture seule, la documentation de PostgreSQL 18, de Cloud SQL, de Npgsql et de Kubernetes ; puis un essai sur kind (OrbStack, Docker 29.8.2, kind 0.33.0, nœud v1.36.4), sous le verrou commun, sur secteur et capot ouvert.

Image. Le tag `18.7-trixie` désigne aujourd'hui l'index `sha256:c699303802144847d238196173655dbbecf7a96aeca1565f2b02eb671a1f0b6b`, poussé le 2026-11-24 à 13:09 UTC : moins de 7 jours. Le golden repo garde l'index que fige l'ADR-012, `sha256:eb63372c1e05c755f55fa30cbd07aecc443676fc6c0fa90b9002d01537841e1a`. Son manifeste linux/amd64 porte `org.opencontainers.image.created` à 2026-11-20T00:38:25Z, la révision `31f4af9d429410ba4ad1f6e394daecd9ae7edfa7` de `docker-library/postgres` et la base `debian:trixie-slim`. L'historique de `repos/postgres/remote/18.7-trixie.md` de `docker-library/repo-info` le montre sur le tag du 2026-11-20 à 10:01 UTC (commit `dd8893b2`) au 2026-11-24 à 03:01 UTC (commit `8f3d5557`). PostgreSQL 18.7 est sortie le 2026-11-12 (ADR-012) : la version passe le délai de 7 jours du principe VI, le condensat le passe le 2026-11-27 à 10:01 UTC au plus tard (écart 91).

Ce que lance l'image, à la révision `31f4af9d`. `18/trixie/Dockerfile` : utilisateur et groupe `postgres` en 999 (lignes 11 à 13) ; `/var/lib/postgresql` en 1777 et `/run/postgresql` en 3777 (lignes 17 et 19) ; `PGDATA` à `/var/lib/postgresql/18/docker` et `VOLUME /var/lib/postgresql` à partir de la 18 (lignes 197 à 200) ; `STOPSIGNAL SIGINT` (ligne 220). `docker-entrypoint.sh` : `file_env` lit `POSTGRES_USER_FILE` et `POSTGRES_PASSWORD_FILE` (lignes 9 à 25) ; `initdb` reçoit le mot de passe par `--pwfile=<(printf ...)`, une substitution de processus, sans fichier (ligne 92) ; `pg_setup_hba_conf` ajoute `host all all all <password_encryption>` (lignes 268 à 286) ; `PGPASSWORD` est exporté pendant l'initialisation pour l'authentification locale (lignes 357 à 359) ; un `.sh` sans bit d'exécution de `/docker-entrypoint-initdb.d` est sourcé (lignes 172 à 199), et `docker_process_sql` lance `psql --username "$POSTGRES_USER" --no-password` (lignes 206 à 213) ; le serveur temporaire de l'initialisation n'écoute que sur le socket, `listen_addresses=''` (lignes 290 à 306).

État TLS du serveur. La documentation de PostgreSQL 18 donne `ssl` à `off` par défaut, et l'image n'y touche pas : `SHOW ssl` répond `off` sur kind. En local, l'application parle donc en clair à la base, dans le cluster. Mode retenu pour `local` : `DATABASE_SSL_MODE` à `Disable`, que l'`app-config` local écrira à l'étape 9 (T087). Sur `gcp`, Cloud SQL en `ENCRYPTED_ONLY` « only allows connections encrypted with SSL/TLS. The client certificate isn't verified » ; « The per-instance CA hierarchy is the default server CA mode configuration » quand l'instance naît par gcloud, l'API d'administration ou Terraform, et avec une autorité par instance « Verifying the CA verifies the server identity ». Npgsql : `Prefer` « does not validate certificates » (RS-03), `Require` n'offre aucune protection contre l'interception d'après son tableau, `VerifyCA` répond à « I want to be sure that I connect to a server that I trust », et le certificat racine se donne par le paramètre `Root Certificate` ou par la variable `PGSSLROOTCERT`. Mode retenu pour `gcp` : `VerifyCA`, avec l'autorité de l'instance lue par `PGSSLROOTCERT`, sans code nouveau dans l'API. La couche `gcp` refuse `Disable`, `Allow` et `Prefer`, sauf derrière un proxy sur localhost (relecture [SECU] de l'étape 3) ; elle refuse aussi `Require`, qui chiffre sans vérifier le serveur (décision du DSI du 2026-11-26, écart 95). Deux points passent à l'étape 14 : `gcp/tofu/database.tf` ne fixe pas `server_ca_mode`, et repose donc sur le défaut, à écrire explicitement ; le certificat de l'autorité doit atteindre le pod (écart 95). L'écart entre les cibles, en clair dans le cluster local et chiffré et vérifié sur GCP, se liste au README (ENF-02, T092).

`readOnlyRootFilesystem`. Essayé et retenu : le conteneur tourne avec une racine en lecture seule, le volume de la base sur `/var/lib/postgresql`, et deux `emptyDir`, `/run/postgresql` pour le socket (`unix_socket_directories` vaut `/var/run/postgresql`, lien vers `/run` sous Debian) et `/tmp`. `touch /probe` répond « Read-only file system », l'initialisation et le démarrage se font sans erreur. Une seule ligne de plus dans le journal : `chmod: changing permissions of '/run/postgresql': Operation not permitted`, que l'entrypoint ignore (`|| :`, ligne 45), le dossier vide appartenant à root.

Effet de `pg_isready` sur les journaux. La page de `pg_isready` écrit : « if incorrect values are provided, the server will log a failed connection attempt ». Mesuré sous `scram-sha-256` : la sonde `pg_isready --host=127.0.0.1 --port=5432 --username=postgres --dbname=postgres`, toutes les 5 s, n'ajoute aucune ligne au journal, ni pendant les 100 premières secondes ni sur 30 s comptées (56 lignes avant et après). Une sonde avec un utilisateur et une base qui n'existent pas n'en ajoute pas non plus : `pg_isready` repart à la demande d'authentification, avant que le serveur vérifie l'utilisateur. La sonde vise 127.0.0.1 en TCP, où le serveur temporaire de l'initialisation n'écoute pas : le pod ne se dit pas prêt pendant l'initialisation.

Script d'initialisation sous `scram-sha-256` local. `local/data/init/10-app-role.sh`, sourcé par l'entrypoint, crée le rôle et la base par `docker_process_sql`, qui s'authentifie par `PGPASSWORD`. Le mot de passe de `db-auth` va de son fichier à `psql` par un tube ; la session pose `log_min_error_statement` à `PANIC`, que la documentation donne pour « effectively turn off logging of failing statements », réservé aux superutilisateurs. La page de `CREATE ROLE` prévient qu'un mot de passe en clair « might also be logged in the client's command history or the server log », et donne `NOSUPERUSER`, `NOCREATEDB`, `NOCREATEROLE`, `NOREPLICATION`, `NOBYPASSRLS` et `NOLOGIN` par défaut ; le script les écrit, avec `LOGIN`. Relevé sur kind : le journal montre `SET`, `CREATE ROLE` et `CREATE DATABASE` ; le rôle `app` se connecte sans aucun autre attribut et possède la base `app` ; les deux mots de passe sont rangés en `SCRAM-SHA-256` ; `pg_hba_file_rules` compte 7 règles, toutes en `scram-sha-256` (`local` et `host` sur 127.0.0.1 et ::1, pour `all` et `replication`, plus `host all all all`).

Champs de Kubernetes employés, lus dans `staging/src/k8s.io/api/core/v1/types.go` et `apps/v1/types.go` au tag v1.36.6 : `automountServiceAccountToken` de `PodSpec` (ligne 4230), `fsGroup` de `PodSecurityContext` (ligne 4930), `readOnlyRootFilesystem` de `SecurityContext` (ligne 8299), `defaultMode` de `SecretVolumeSource` (ligne 1453) et de `ConfigMapVolumeSource` (ligne 1899), `volumeClaimTemplates` et `serviceName` de `StatefulSetSpec` (lignes 218 et 226), le type `kubernetes.io/basic-auth` et ses clés `username` et `password` (lignes 8022 à 8027). Le profil `restricted` des Pod Security Standards admet les volumes `configMap`, `emptyDir`, `persistentVolumeClaim` et `secret`, demande `allowPrivilegeEscalation` à `false`, `runAsNonRoot`, un `runAsUser` non nul, `seccompProfile` en `RuntimeDefault` ou `Localhost`, et `ALL` dans les capacités retirées.

Mesures de l'essai. Premier `task up` sur un poste sans cluster, images du nœud et de zot dans le cache du moteur, volume du miroir neuf : 56 s jusqu'au `SELECT 1` authentifié par le Service. Second `task up` : 7 s, Secrets gardés, aucune annotation. Volume du miroir après les deux : 281,9 Mo, images d'Envoy Gateway et de Postgres comprises.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://hub.docker.com/v2/repositories/library/postgres/tags/18.7-trixie> | 2026-11-25 | Index `c6993038` poussé le 2026-11-24 |
| `docker buildx imagetools inspect` sur l'index `eb63372c`, buildx 0.37.2 | 2026-11-25 | `created` 2026-11-20T00:38:25Z, révision `31f4af9d`, base `debian:trixie-slim` |
| <https://github.com/docker-library/repo-info/commits/master/repos/postgres/remote/18.7-trixie.md> | 2026-11-25 | Index `eb63372c` sur le tag du 2026-11-20 au 2026-11-24 (commits `dd8893b2` et `8f3d5557`) |
| <https://github.com/docker-library/postgres/blob/31f4af9d429410ba4ad1f6e394daecd9ae7edfa7/18/trixie/Dockerfile> | 2026-11-25 | UID 999, dossiers, `PGDATA`, `VOLUME`, `STOPSIGNAL` |
| <https://github.com/docker-library/postgres/blob/31f4af9d429410ba4ad1f6e394daecd9ae7edfa7/18/trixie/docker-entrypoint.sh> | 2026-11-25 | `file_env`, `initdb --pwfile`, `pg_hba`, `PGPASSWORD`, scripts sourcés, serveur temporaire sur le socket |
| <https://www.postgresql.org/docs/18/runtime-config-connection.html> | 2026-11-25 | `ssl` à `off`, `password_encryption` à `scram-sha-256` par défaut |
| <https://www.postgresql.org/docs/18/app-pg-isready.html> | 2026-11-25 | Tentative échouée journalisée sur des valeurs fausses |
| <https://www.postgresql.org/docs/18/runtime-config-logging.html> | 2026-11-25 | `log_min_error_statement`, `PANIC` pour ne plus journaliser les instructions en échec |
| <https://www.postgresql.org/docs/18/sql-createrole.html> | 2026-11-25 | Attributs par défaut ; mot de passe en clair journalisable |
| <https://docs.cloud.google.com/sql/docs/postgres/configure-ssl-instance> | 2026-11-25 | `ENCRYPTED_ONLY` sans vérification du certificat client ; identité vérifiée par l'autorité de l'instance |
| <https://docs.cloud.google.com/sql/docs/postgres/authorize-ssl> | 2026-11-25 | Autorité par instance par défaut (gcloud, API, Terraform) |
| <https://www.npgsql.org/doc/security.html> | 2026-11-25 | `SSL Mode`, `Root Certificate`, `PGSSLROOTCERT` |
| <https://kubernetes.io/docs/concepts/security/pod-security-standards/> | 2026-11-25 | Contrôles du profil `restricted` |
| <https://github.com/kubernetes/kubernetes/blob/v1.36.6/staging/src/k8s.io/api/core/v1/types.go> | 2026-11-25 | Champs du pod, des volumes et du Secret `basic-auth` |
| <https://github.com/kubernetes/kubernetes/blob/v1.36.6/staging/src/k8s.io/api/apps/v1/types.go> | 2026-11-25 | `volumeClaimTemplates`, `serviceName` |
| Essai sur kind du 2026-11-25 | 2026-11-25 | `ssl` à `off`, racine en lecture seule, journal sous la sonde, rôle et règles de `pg_hba` |

## RS-13. Miroir

Décision : l'ADR-011 tel quel, accepté par Lucas le 2026-11-21 avec ses réponses. `task down` supprime le cluster et `task app:down` le garde, noms provisoires que [PO] confirme en phase 5 ; le conteneur du miroir est retiré à chaque `task down`, son volume reste ; la purge passe par une commande explicite, `task mirror:purge`, et la rétention de zot n'entre qu'après un essai en `dryRun` et une relecture [SECU] ; un volume par projet. La liste des registres vit dans `local/mirror/registries`. La configuration zot et les `hosts.toml` en sont dérivés et versionnés ; S13 vérifie qu'ils restent d'accord, ce qui évite de générer du JSON à l'exécution sans outil dédié.

Ouvert : les montages a et b pour plusieurs amonts, essayés à l'étape 12 avec ghcr.io, ou à l'étape 19 si le cache vient d'un autre registre que docker.io ; le temps de démarrage du miroir, mesuré par E17.

### Relevé du 2026-11-25 : miroir, registres du nœud et configuration de kind (étape 6)

Fait par [OPS]. Code de zot au tag v2.1.23, de kind au tag v0.33.0 et de l'API de moby au tag docker-v29.8.2, lus par `gh api` ; documentation de containerd, de kind et de Docker ; lectures sur le poste en lecture seule (`docker buildx imagetools inspect`, `docker system df -v`).

Image de zot. Le tag `v2.1.23` de `ghcr.io/project-zot/zot` désigne toujours l'index `sha256:9d3de83ac2099e6f4843045b4c9b65b7e8baf40f92d28f54906dee9d4d390fd7`, celui que fige la condition 8 de l'ADR-011 ; il porte linux/amd64 et linux/arm64. La page des versions du paquet le donne « Published 23 days ago », et la release v2.1.23 date du 2026-11-02 : plus de 7 jours (principe VI, ADR-016). Le condensat entre dans `local/tasks/local.yml` sous `MIRROR_IMAGE`, avec le commentaire `# renovate:` que lit le gestionnaire des images de la couche `local` ; ses mises à jour passent par l'approbation de l'ADR-016.

Ce que l'image lance. L'image publiée ne sort pas de `build/Dockerfile` : le workflow `publish.yaml` la construit par stacker depuis `build/stacker.yaml`, sur `gcr.io/distroless/base-nossl-debian13` pour Linux. Son entrée est `/usr/local/bin/zot-linux-<arch>`, sa commande `serve /etc/zot/config.json`, son utilisateur 0, et elle n'a aucun `HEALTHCHECK` (`docker image inspect` sur le poste : `Config.Healthcheck` à `null`). `build/Dockerfile`, qui en déclare un, n'est pas celui de la release. La sous-commande `zot healthcheck` existe dans le binaire 2.1.23 (`pkg/cli/server/healthcheck.go`), mais `--health-cmd` de la CLI docker la lancerait par un shell (`CMD-SHELL`, `cli/command/container/opts.go`, ligne 580, docker/cli v29.8.2), absent d'une base distroless ; et des options `--health-*` sans commande ne posent aucune sonde (essayé sur le poste : `State.Health` absent). Le projet monte sa configuration à `/etc/zot/config.json`, en lecture seule, et garde la commande de l'image.

Attente du miroir. Sans port publié, sans `docker exec` et sans sonde dans l'image, la réponse HTTP du miroir ne se demande pas depuis le poste. zot lit sa configuration et ouvre son port au démarrage, et s'arrête aussitôt si l'un des deux échoue (`pkg/api/controller.go`, fonction `Run`, et `pkg/cli/server/root.go`, commande `serve`). `local/scripts/mirror.sh` attend donc l'état `running`, au plus 30 s, puis vérifie qu'il tient encore 2 s plus tard. La réponse elle-même a été relevée une fois sur le poste, le 2026-11-25 : un pod sur `docker.io/library/busybox:1.37.0` par condensat, tiré par le nœud à travers le miroir en capacité `pull` seule, a démarré en 5 s, et le journal de zot montre le `HEAD` puis les `GET` du manifeste et des couches, en 200, avec `?ns=docker.io`. T2 hors réseau en `pull` seul reste à l'étape 10 (E10).

Configuration de zot. Celle de l'essai (`tests/bench/bench-010/zot/config-online.json`), reprise avec un journal en `info` : `sync` en `onDemand` avec `tlsVerify`, un seul amont, `https://index.docker.io`, `gc` à `false`, stockage sous `/var/lib/registry`. Les champs suivent l'exemple `examples/config-sync.json` du tag.

Registres du nœud. La page `hosts.md` de containerd v2.3.4 : un dossier par registre sous `config_path`, `certs.d/<registre>/hosts.toml` ; les hôtes déclarés sont essayés d'abord, dans l'ordre, puis `server` ; `server` omis, le registre lui-même sert d'amont ; un hôte en HTTP s'écrit avec son schéma, `[host."http://..."]` ; `capabilities` prend `pull`, `resolve` et `push`, et « A public mirror should never be trusted to do a resolve action » ; le dossier se relit sans redémarrer containerd. `local/mirror/certs.d/docker.io/hosts.toml` omet `server` et déclare le seul miroir, `http://saas-b2b-mirror:5000`, en `pull`.

Configuration de kind. Le correctif `containerdConfigPatches` qui pose `config_path` est celui de l'essai et de la page du registre local de kind, qui ajoute qu'il « is not necessary with images from kind v0.27.0+ ». Le golden repo le garde, comme le décrit l'ADR-011 : la configuration mesurée par T2 le portait. kind résout un `hostPath` relatif d'`extraMounts` par `filepath.Abs`, donc depuis le dossier où il tourne, pas depuis celui du fichier (`pkg/cluster/internal/providers/docker/provision.go`, lignes 89 à 97) : `local/scripts/cluster.sh` se place à la racine du golden repo avant d'appeler kind, et `local/kind/cluster.yaml` écrit `hostPath: local/mirror/certs.d`. Les champs `apiServerAddress`, `extraMounts` (`readOnly`) et `extraPortMappings` (`listenAddress`) sont ceux de `pkg/apis/config/v1alpha4/types.go`. kind étiquette chaque nœud `io.x-k8s.kind.cluster=<cluster>` (`constants.go`, ligne 21) : E03 s'en sert.

Lancement par Docker. Options de `docker run` lues dans sa référence : `--network`, `--mount`, `--label`, `--name`, `--detach`, `--cap-drop`, `--security-opt`, `--read-only`, `--restart` à `no` par défaut, `--pull` à `missing` par défaut. Un montage `--mount type=bind,...,readonly` échoue si la source manque, là où `-v` créerait un dossier vide : le fichier de configuration absent ne peut pas devenir un dossier. `docker volume create` est idempotent pour un même nom et un même pilote, et `--label` y pose une étiquette. La page des étiquettes demande un préfixe en DNS inversé d'un domaine que l'on détient : le domaine réservé `saas-b2b.invalid` (RS-07) donne `invalid.saas-b2b.role`. Champs d'inspection relus dans l'API du moteur : `HostConfig.PortBindings`, `HostConfig.PublishAllPorts`, `NetworkSettings.Ports`, `NetworkSettings.Networks`. `docker system df -v --format '{{range .Volumes}}{{.Name}}={{.Size}};{{end}}'` rend la taille de chaque volume avec docker 29.8.2 (constaté, la page de `docker system df` ne liste pas les champs) ; `task down` s'en sert pour afficher la taille du volume du miroir.

Essai sur le poste (OrbStack, docker 29.8.2), le 2026-11-25 : le conteneur garde l'utilisateur de l'image et tourne avec `--cap-drop ALL`, `--security-opt no-new-privileges=true` et `--read-only`, sans erreur dans son journal ; 66,8 Mio au repos d'après `docker stats`. La condition 6 de l'ADR-011 (UID non root) reste à essayer à l'étape 10 (E23).

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| `docker buildx imagetools inspect ghcr.io/project-zot/zot:v2.1.23`, buildx 0.37.2 | 2026-11-25 | Index `9d3de83a`, manifestes linux/amd64 et linux/arm64 |
| <https://github.com/project-zot/zot/pkgs/container/zot/versions?filters%5Bversion_type%5D=tagged> | 2026-11-25 | v2.1.23, condensat `9d3de83a`, « Published 23 days ago » |
| <https://api.github.com/repos/project-zot/zot/releases/tags/v2.1.23> | 2026-11-25 | Publiée le 2026-11-02, release non immuable |
| <https://github.com/project-zot/zot/blob/v2.1.23/build/stacker.yaml> | 2026-11-25 | Construction de l'image publiée : entrée, commande, aucun `HEALTHCHECK` |
| <https://github.com/project-zot/zot/blob/v2.1.23/.github/workflows/publish.yaml> | 2026-11-25 | Base `gcr.io/distroless/base-nossl-debian13` pour Linux |
| `docker image inspect` sur l'image par condensat, docker 29.8.2 | 2026-11-25 | `Config.Healthcheck` à `null`, entrée `/usr/local/bin/zot-linux-arm64`, utilisateur 0 |
| <https://github.com/docker/cli/blob/v29.8.2/cli/command/container/opts.go> | 2026-11-25 | Ligne 580 : `--health-cmd` devient `CMD-SHELL` |
| <https://github.com/project-zot/zot/blob/v2.1.23/pkg/api/controller.go> | 2026-11-25 | `Run` : port ouvert au démarrage, erreur rendue à `serve` si l'ouverture échoue |
| <https://github.com/project-zot/zot/blob/v2.1.23/pkg/cli/server/healthcheck.go> | 2026-11-25 | `zot healthcheck <config>` existe : `/readyz`, 0 sur 2xx ; inutilisable sans shell par `--health-cmd` |
| <https://github.com/project-zot/zot/blob/v2.1.23/pkg/cli/server/root.go> | 2026-11-25 | `serve <config>` |
| <https://github.com/project-zot/zot/blob/v2.1.23/examples/config-sync.json> | 2026-11-25 | Champs de `sync` |
| <https://github.com/containerd/containerd/blob/v2.3.4/docs/hosts.md> | 2026-11-25 | `server`, `host`, `capabilities`, ordre des hôtes, relecture sans redémarrage, hôte HTTP |
| <https://kind.sigs.k8s.io/docs/user/local-registry/> | 2026-11-25 | Correctif `config_path`, inutile pour les images de kind v0.27.0 et après ; réseau `kind` |
| <https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/apis/config/v1alpha4/types.go> | 2026-11-25 | `apiServerAddress` à 127.0.0.1 par défaut, `containerdConfigPatches`, `Mount.readOnly`, `listenAddress` |
| <https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/cluster/internal/providers/docker/provision.go> | 2026-11-25 | Lignes 89 à 97 : `hostPath` relatif résolu par `filepath.Abs` ; lignes 395 à 400 : `listenAddress` vide publiée sur 0.0.0.0 |
| <https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/cluster/internal/providers/docker/constants.go> | 2026-11-25 | Ligne 21 : étiquette `io.x-k8s.kind.cluster` |
| <https://docs.docker.com/reference/cli/docker/container/run/> | 2026-11-25 | Options de `docker run` citées plus haut |
| <https://docs.docker.com/engine/storage/bind-mounts/> | 2026-11-25 | `--mount type=bind,src=...,dst=...,readonly` ; erreur si la source manque ; fichier seul accepté |
| <https://docs.docker.com/reference/cli/docker/volume/create/> | 2026-11-25 | `--label` ; création idempotente pour un même nom |
| <https://docs.docker.com/engine/manage-resources/labels/> | 2026-11-25 | Préfixe en DNS inversé, espaces réservés à Docker |
| <https://docs.docker.com/reference/cli/docker/system/df/> | 2026-11-25 | `--verbose`, `--format` ; volumes avec leur taille |
| <https://github.com/moby/moby/blob/docker-v29.8.2/api/swagger.yaml> | 2026-11-25 | `PortBindings`, `PublishAllPorts`, `PortMap`, `Networks`, `State.Status` |

### Relevé du 2026-11-25 : ce qu'un pod joint du miroir (étape 8)

Fait par [OPS], sur kind (OrbStack, Docker 29.8.2, kind 0.33.0, nœud v1.36.4), depuis un pod d'un namespace à part, au profil `restricted`, sur l'image de Postgres de l'étape 8, qui porte bash (écarts 21 et 34). Le nom du conteneur du miroir, `saas-b2b-mirror`, se résout depuis le pod (adresse IPv6 du réseau `kind`) ; `GET /v2/_catalog` répond `HTTP/1.0 200 OK`, et le début d'un envoi, `POST /v2/e2e/probe/blobs/uploads/`, répond `HTTP/1.0 202 Accepted` : le journal de zot le montre, avec l'adresse du nœud pour client. Tout pod du cluster lit donc le miroir et peut y commencer un envoi, sans authentification (R-34). La capacité `pull` seule du nœud et les références par condensat empêchent qu'une image envoyée remplace une image de la stack, mais rien n'empêche un pod de remplir le volume du miroir, ni de déposer une image sous un tag. La politique anonyme en lecture seule de l'écart 29 fermerait l'envoi ; elle est prévue à l'étape 10. E03 relève désormais ces trois réponses à chaque exécution, sans les juger (écart 98).

### Relevé du 2026-11-26 : miroir en lecture seule (PR #77, écarts 29, 98, 106, 109 et 113)

Fait par [OPS]. Lectures du 2026-11-26 :

- `pkg/api/routes.go` au tag v2.1.23, lignes 127 à 144 : `accessControlConfig := rh.c.Config.CopyAccessControlConfig()` ; quand il existe, sans authentification (`IsBasicAuthnEnabled` faux), zot journalise « anonymous policy only access control is being enabled » et monte `BaseAuthzHandler` et `DistSpecAuthzHandler` sur les routes.
- `pkg/api/config/config.go` au même tag : `AccessControl *AccessControlConfig` est un champ de `HTTPConfig` (tag `accessControl`). La clé se range donc sous `http`, non à la racine (écart 109).
- `pkg/api/authz.go` : pour un client sans nom d'utilisateur, seule la liste `anonymousPolicy` du motif qui correspond compte (lignes 116 et 117, et 664 et 665) ; le motif `**` correspond à tout dépôt.
- Documentation de zot v2.1.23, page « authn-authz » : `anonymousPolicy` dit ce qu'un client non authentifié peut faire ; `**` est la politique par défaut, le motif le plus long l'emportant ; les actions sont read, create, update et delete, et create, update et delete ne s'emploient pas sans read.

Essai sur kind (OrbStack, Docker 29.8.2, kind 0.33.0, nœud v1.36.4), depuis un pod d'un namespace à part, au profil `restricted`. Ancienne configuration, volume du miroir neuf : un pod envoie un blob (`POST` 202 puis `PUT` 201), un manifeste d'image (`PUT` 201), le relit (`GET` 200), puis pousse un index dans `envoyproxy/envoy` (`PUT` 201, relu par son condensat) ; le catalogue liste alors `poison/test`. zot accepte donc l'écriture d'un manifeste : ce point, non vérifié à l'écart 98, l'est. Un `GET` du tag `distroless-v1.40.2` rend encore le condensat d'origine après l'index poussé dessus, sans qu'on sache si zot tient le tag ou le resynchronise (écart 113).

Nouvelle configuration, volume neuf : `GET /v2/_catalog` répond 200, `POST /v2/<nom>/blobs/uploads/`, `PUT` et `DELETE` d'un manifeste répondent 401. La synchronisation à la demande remplit le cache : sur le volume neuf du premier `task up` de la suite (E24), le nœud tire le proxy et Postgres, et le catalogue lu par E03 liste `envoyproxy/envoy` et `library/postgres`. `PROFILE=lite task test:e2e` passe en entier, dix tests, 281 s.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://github.com/project-zot/zot/blob/v2.1.23/pkg/api/routes.go> | 2026-11-26 | Lignes 127 à 144 : accès « anonymous policy only » dès que `accessControl` existe |
| <https://github.com/project-zot/zot/blob/v2.1.23/pkg/api/config/config.go> | 2026-11-26 | `HTTPConfig.AccessControl` : la clé est sous `http` |
| <https://github.com/project-zot/zot/blob/v2.1.23/pkg/api/authz.go> | 2026-11-26 | Lignes 116 et 117, 664 et 665 : `anonymousPolicy` pour un client sans nom |
| <https://github.com/project-zot/zot/blob/v2.1.23/examples/config-anonymous-authz.json> | 2026-11-26 | `accessControl` sous `http`, motif `**` avec `anonymousPolicy` |
| <https://zotregistry.dev/v2.1.23/articles/authn-authz/> | 2026-11-26 | Actions, motif `**`, `anonymousPolicy` |
| Essai sur kind du 2026-11-26 | 2026-11-26 | Écriture acceptée avant, refusée avec 401 après ; cache rempli |

## RS-14. Flux dans le profil standard

Décision de Lucas (2026-11-21) : Flux est livré dans le profil standard avec sa liaison suspendue (`spec.suspend`), et `task reload` reste seul maître des objets de l'application, jusqu'à ce que Lucas tranche ce que lit Flux sur le PC (ADR-010, question 1). `task up` installe Flux depuis son `install.yaml` vendoré, quatre contrôleurs, options de verrouillage de la condition 3 de l'ADR-010. Un seul acteur tient ainsi les objets de l'application, comme le demande la question 3 de l'ADR-010. S28 vérifie la suspension.

Pourquoi : la mesure du profil standard (SC-002) compte les images et la mémoire de Flux, qui ne dépendent pas de la source. Une source choisie sans Lucas engagerait soit un identifiant sur le poste, soit une image non mesurée.

Conséquence sur E15. Une liaison suspendue ne réconcilie rien : E15 ne peut pas regarder Flux écrire. Il interroge à la place les droits du compte de service de chaque liaison auprès de l'API du cluster, sans réactiver la liaison, et échoue si un environnement peut écrire dans le namespace d'un autre. La réconciliation réelle se testera quand la source sera choisie.

À vérifier à l'étape 12 (porteur [DEV]) : qu'une `Kustomization` suspendue dont l'objet source n'est pas livré soit admise et reste inerte, sur la documentation de Flux 2.10 ; le mécanisme qui interroge les droits d'un compte de service. Repli : livrer les contrôleurs seuls, sans objet de liaison ; S10 et S28 portent alors sur les contrôleurs, et E15 sur les rôles livrés.

Reste ouvert, sans bloquer aucune étape : la question 1 de l'ADR-010.

Alternatives : attendre la décision avant l'étape 12, écarté parce que D02 attendrait aussi ; un dépôt distant public, qui garde la dépendance au réseau contre l'ADR-011.

## RS-15. Keycloak et Mailpit

Décision : aucune image, version ni manifest avant les ADR-013 et ADR-014. Chaque couche entre par le même chemin : un dossier de `local/`, un ajout à la composition `local/k8s/standard`, ses Secrets créés selon l'ADR-007, son registre ajouté à la liste du miroir, ses images ajoutées à l'inventaire du scan (RS-24), E10 et E25 rejoués en standard, seuil de mémoire recalculé.

Keycloak tourne sans être appelé par l'API jusqu'à l'ADR-013 et à l'amendement de la spec qu'il demandera (RS-25). Une base pour Keycloak, si BENCH-012 en demande une, s'ajoute dans la même couche.

## RS-16. Couche GCP

Décision : racine OpenTofu unique dans `gcp/tofu/`, ressources du socle de l'ADR-008, Memorystore mis à part jusqu'à l'ADR-015 (étape 20, RS-11), provider `google` 8.12.0 et provider `random` dans un verrou versionné. Validation en CI par `tofu init -lockfile=readonly` puis `tofu validate`, sans backend distant ni identifiant.

À vérifier avant l'étape 13 (porteur [OPS], avec [DEV]) : l'option qui désactive le backend à l'init ; la validation d'une configuration de chiffrement `gcp_kms` sans accès à la clé ; la commande qui inscrit les sommes de chaque plateforme dans le verrou et le comportement de `-lockfile=readonly` sur une plateforme absente (ADR-008, question 5) ; la lecture de `platform.yaml` par une fonction de décodage YAML d'OpenTofu ; les attributs des activations (Gateway API, synchronisation des secrets, flotte, Config Sync) ; la version du provider `random`.

Contrainte de date : `google` 8.12.0 ne passe le délai de 7 jours que le 2026-11-24 (ADR-008, règle de version, point 2). Avant cette date, l'étape 13 prend la version précédente qui passe le délai, ou attend.

### Relevé du 2026-11-25 (T102)

Fait par [OPS]. Sources : l'API GitHub des releases, lue par `gh api` ; la documentation d'OpenTofu, dont chaque page lue s'annonce en v1.13.x ; la documentation du provider `hashicorp/google` au tag `v8.12.0` et celle de `hashicorp/random` au tag `v3.9.1`, lues dans leurs dépôts par `gh api` ; des pages de Google Cloud. Les essais ont tourné avec OpenTofu 1.13.9 (Homebrew, darwin_arm64) dans un environnement vidé (`env -i`, `HOME` et `CLOUDSDK_CONFIG` vers des dossiers vides) : aucun identifiant n'était joignable, et rien n'a contacté Google Cloud. Aucun `tofu plan`, aucun apply.

Versions retenues :

| Outil | Version | Publiée le | Délai de 7 jours | Note |
| --- | --- | --- | --- | --- |
| OpenTofu, en CI | 1.13.9 | 2026-11-05 | passé | 1.13.10 (2026-11-23) corrige GO-2026-6859, un crash de serveur HTTP/1 de Go, d'après sa note de version. L'exception de sécurité du principe VI la permettrait dès maintenant ; non retenue, rien ne montrant que `init` ou `validate` ouvrent un serveur HTTP/1. Elle passe le délai le 2026-11-30, et Renovate la proposera |
| Provider `google` | 8.12.0 | 2026-11-17 à 19:43:15 UTC | passé depuis le 2026-11-24 à 19:43 UTC | Dernière release au 2026-11-25 |
| Provider `random` | 3.9.1 | 2026-09-11 | passé | Dernière release ; ressource éphémère `random_password` |

SHA-256 d'OpenTofu 1.13.9, lus dans `tofu_1.13.9_SHA256SUMS` de la release et égaux au champ `digest` de l'API :

| Archive | SHA-256 |
| --- | --- |
| `tofu_1.13.9_linux_amd64.tar.gz` | `b34b327cc1ef07178207b6f2cd1f5276537d3e5b7be316500f6dac50d4c0a857` |
| `tofu_1.13.9_linux_arm64.tar.gz` | `5dc196dde75b667e4806d358310ec96742774cd0993c54c1237efee5644b69b8` |
| `tofu_1.13.9_darwin_amd64.tar.gz` | `347e2e5a2cfe2f368829572d308b2e7c1e0486b20a1779090ff06360f7551e4f` |
| `tofu_1.13.9_darwin_arm64.tar.gz` | `496f4c3064b5c3bff79174b3dae4faaf65a66774eb8e2bf074f895412c5f124f` |

Backend. `-backend=false` : « To skip backend configuration ». Un bloc `backend "gcs" {}` vide est une configuration partielle : le seau et le préfixe arrivent à l'init par `-backend-config`. Essai : `tofu init -backend=false -input=false` passe sur une racine qui déclare ce bloc, sans joindre autre chose que le registre.

Chiffrement `gcp_kms`. Fournisseur de clé `gcp_kms` (`kms_encryption_key`, `key_length`), méthode `aes_gcm`, blocs `state` et `plan` avec `method` et `enforced = true`. AES-GCM « needs 16, 24, or 32-byte keys » : `key_length = 32`. Variables et locaux sont admis dans cette configuration, s'ils se résolvent à l'init. Essai : `tofu validate` passe sans identifiant ni accès à la clé. `tofu console`, lui, construit la clé et s'arrête sur « Unable to build encryption key data [...] could not find default credentials ». Conséquence : une commande qui lit l'état appelle Cloud KMS avec les identifiants qu'elle trouve. Les scripts de la couche lancent donc OpenTofu dans un environnement vidé, pour qu'aucun identifiant du poste ne serve, même par accident.

Verrou multi-plateformes (ADR-008, question 5). `tofu providers lock -platform=<os>_<arch>`, option répétable. Essai : le registre d'OpenTofu publie les sommes de toutes les plateformes, et `tofu init` comme `tofu providers lock -platform=linux_amd64` ont écrit 15 sommes `h1:` et 15 sommes `zh:` par provider. Effet de `-lockfile=readonly` : sur un verrou privé des sommes `h1:` mais qui garde les `zh:`, l'init passe, affiche « Provider lock file not updated » et laisse le verrou intact ; sur un verrou dont aucune somme ne correspond, l'init échoue (« doesn't match any of the checksums previously recorded in the dependency lock file »). Commande retenue pour T108 : `tofu providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_amd64 -platform=darwin_arm64`. Le verrou ne suit que les providers, jamais les modules.

Lecture de `platform.yaml`. `yamldecode` lit un sous-ensemble de YAML 1.2, un seul document ; `!!map` donne un objet, `!!str` une chaîne. Essai : `yamldecode(file("${path.module}/../../platform.yaml"))` donne `{"kubernetes_minor" = "1.36", "postgres_major" = "18"}`, des chaînes, et `"POSTGRES_${...postgres_major}"` donne `"POSTGRES_18"`. `min_master_version` accepte la forme `1.X`, qui se résout en « The highest valid patch release in the specified minor version » ; c'est un minimum, que GKE dépasse en montant de version. Mise à jour du 2026-11-25 : `database_version` s'écrit en littéral `POSTGRES_18`, parce que Trivy ne résout pas cette lecture (RS-22) ; S21 le compare à `platform.yaml`.

Activations, attributs de `google_container_cluster` en 8.12.0 :

- Gateway API : `gateway_api_config { channel }`, valeurs `CHANNEL_DISABLED`, `CHANNEL_EXPERIMENTAL`, `CHANNEL_STANDARD` ;
- synchronisation des secrets : `secret_sync_config { enabled, rotation_config { enabled, rotation_interval } }`, intervalle par défaut de 2 minutes. La page de Google écrit l'intervalle `60s` ou `300s`, avec un minimum d'une minute, et « The secret version must be in the same region as the cluster » ; une entrée de `SecretSync` donne une clé du Secret, d'où un secret de Secret Manager par clé de `db-auth` ;
- flotte : `fleet { project }`, qui expose `fleet.0.membership_id` et `fleet.0.membership_location`. Google : « To install Config Sync, all clusters must be registered to a fleet », avec ce bloc dans ses exemples Terraform ;
- Config Sync : `google_gke_hub_feature` (`name = "configmanagement"`, `location = "global"`) et `google_gke_hub_feature_membership` avec `configmanagement { version, management, config_sync { enabled } }`. `config_sync.enabled` « needs to be set to `true` explicitly to install Config Sync » ; `MANAGEMENT_MANUAL` coupe les montées automatiques. Google documente l'installation sans source : « only set the `spec.configSync.enabled` field as `true` », puis les `RootSync` par `kubectl`.

Restent en `pending`, écrits en commentaire daté dans la racine : l'API de la fonction `configmanagement`, qu'aucune page lue ne nomme ; la coupure de l'export des métriques de Config Sync (ADR-010, condition 7), qu'aucun attribut de `config_sync` ne porte en 8.12.0 ; les rôles du compte de la CI (ADR-008, question 3).

Attributs en écriture seule. `password_wo` et `password_wo_version` (`google_sql_user`), `root_password_wo` (`google_sql_database_instance`), `secret_data_wo` et `secret_data_wo_version` (`google_secret_manager_secret_version`). OpenTofu écrit `null` à leur place dans l'état et dans le plan, à partir de 1.11, et ne voit pas seul un changement de valeur : l'attribut `*_wo_version` sert à le signaler. Les ressources éphémères existent à partir de 1.11 ; ni l'une ni l'autre page ne dit si deux ressources qui lisent la même ressource éphémère dans une exécution reçoivent la même valeur. La racine le suppose pour `db-auth` : le test de la condition 3 de l'ADR-007 le vérifie, l'API se connectant avec le mot de passe synchronisé.

Autres faits lus :

- API : la page de la flotte demande `container`, `gkeconnect`, `gkehub` et `cloudresourcemanager`, plus `iam` pour sa fédération d'identité ; `compute.googleapis.com` est le service de l'API Compute Engine ; les autres viennent du socle de BENCH-008 ;
- fédération de la CI : Google déconseille les champs de nom (`repository`, `repository_owner`) au profit des champs `*_id` ; format générique `principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL_ID/attribute.ATTRIBUTE_NAME/ATTRIBUTE_VALUE` ; émetteur de GitHub écrit `https://token.actions.githubusercontent.com/`. La longueur du `sub` face à `google.subject` reste ouverte (ADR-008, question 4) ;
- point d'accès DNS : « accessible from any network reachable by Google Cloud APIs », et « Best practice: Use only the DNS-based endpoint ». Valeur proposée par [OPS] pour la condition 5 de l'ADR-008 : `allow_external_traffic = true`, le point d'accès IP désactivé, pour que l'utilisateur applique les manifests de la couche depuis son poste. [SECU] la confirme ;
- Cloud SQL : à partir de `POSTGRES_16`, l'API prend `ENTERPRISE_PLUS` par défaut, qui refuse les tiers partagés et personnalisés ; `edition = "ENTERPRISE"` s'écrit donc ;
- Renovate : son gestionnaire `terraform` lit `**/*.tf` et `**/*.tofu` ; il tient `.terraform.lock.hcl` « without calling the underlying package manager ». Correction du 2026-11-26 (Renovate 44.247.1, publiée le 2026-11-16, lue par `gh api` ; aucun Renovate n'a tourné sur ces racines) : la phrase de la doc, registre par défaut `registry.terraform.io` pour un provider « without a registry definition », est exacte mais incomplète. Pour un `source` sans hôte, `lib/modules/manager/terraform/base.ts` cherche dans le verrou les blocs de ce nom ; s'il n'y en a qu'un et qu'il n'est pas sur `registry.terraform.io`, il prend son registre pour la recherche (renovate#41487, fusionnée le 2026-02-25, couverte par `required-provider.spec.ts`). Pour un `source` avec hôte, il prend cet hôte. Les verrous de `gcp/tofu/` et `gcp/budget/` n'ont chacun qu'un bloc par provider, sur `registry.opentofu.org` : Renovate cherchait déjà les versions sur ce registre, et la `packageRule` annoncée par l'étape 13 (PR #64) n'est pas nécessaire. Dates : pour `registry.opentofu.org`, le datasource interroge `api.opentofu.org` et lit `published` (`v8.12.0` : 2026-11-17T19:21:13Z, lu le 2026-11-26). `minimumReleaseAge` joue donc, et l'ADR-016 est sans objet pour ces providers. Durcissement du 2026-11-26 (décision du DSI) : le registre consulté ne doit pas tenir au seul verrou, qu'un `terraform init` régénérerait sur `registry.terraform.io` sans trace. Les `required_providers` des deux racines écrivent donc `source = "registry.opentofu.org/hashicorp/<nom>"` (même adresse pour OpenTofu, verrous inchangés), S15 refuse un source sans cet hôte et S14 un bloc de verrou sur un autre hôte. À confirmer à la première exécution de Renovate : il suit `required_version` (`>= 1.11.0`) sur les versions de `hashicorp/terraform` (GitHub releases, `terraform-version.ts`), pas sur celles d'OpenTofu ; la plage `>=` devrait rester satisfaite, donc sans PR, mais rien ne l'a été exécuté.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://api.github.com/repos/opentofu/opentofu/releases> | 2026-11-25 | Dates de 1.13.9 et 1.13.10, note de 1.13.10 |
| <https://github.com/opentofu/opentofu/releases/download/v1.13.9/tofu_1.13.9_SHA256SUMS> | 2026-11-25 | Les quatre SHA-256, lus par `gh release download` |
| <https://api.github.com/repos/hashicorp/terraform-provider-google/releases> | 2026-11-25 | 8.12.0 du 2026-11-17, dernière release |
| <https://api.github.com/repos/hashicorp/terraform-provider-random/releases> | 2026-11-25 | 3.9.1 du 2026-09-11, dernière release |
| <https://opentofu.org/docs/cli/commands/init/> | 2026-11-25 | `-backend=false`, `-lockfile=readonly`, `-backend-config` |
| <https://opentofu.org/docs/language/settings/backends/configuration/> | 2026-11-25 | Configuration partielle, bloc vide |
| <https://opentofu.org/docs/language/settings/backends/gcs/> | 2026-11-25 | Backend `gcs`, `bucket`, `prefix`, verrouillage |
| <https://opentofu.org/docs/cli/commands/providers/lock/> | 2026-11-25 | `-platform`, répétable |
| <https://opentofu.org/docs/language/files/dependency-lock/> | 2026-11-25 | `h1:` et `zh:`, modules hors du verrou |
| <https://opentofu.org/docs/language/state/encryption/> | 2026-11-25 | `gcp_kms`, `aes_gcm`, `state`, `plan`, `enforced`, variables admises |
| <https://opentofu.org/docs/language/functions/yamldecode/> | 2026-11-25 | Types, un seul document |
| <https://opentofu.org/docs/language/ephemerality/> et ses pages `ephemeral-resources` et `write-only-attributes` | 2026-11-25 | Ressources éphémères et attributs en écriture seule à partir de 1.11 |
| <https://opentofu.org/docs/cli/config/environment-variables/> | 2026-11-25 | `TF_DATA_DIR`, `TF_ENCRYPTION` |
| <https://github.com/hashicorp/terraform-provider-google/tree/v8.12.0/website/docs/r> | 2026-11-25 | Pages des ressources utilisées par la racine : cluster, flotte, Config Sync, Cloud SQL, Secret Manager, Artifact Registry, réseau, IAM, fédération ; `website/docs/guides/provider_reference.html.markdown` |
| <https://github.com/hashicorp/terraform-provider-random/blob/v3.9.1/docs/ephemeral-resources/password.md> | 2026-11-25 | `random_password` éphémère, `length`, `special`, `result` |
| <https://docs.cloud.google.com/kubernetes-engine/versioning> | 2026-11-25 | Formes de version `1.X`, `1.X.Y`, `1.X.Y-gke.N` |
| <https://docs.cloud.google.com/secret-manager/docs/sync-k8-secrets> | 2026-11-25 | Région du secret, une clé par entrée, rôle et principal, intervalle |
| <https://docs.cloud.google.com/kubernetes-engine/config-sync/docs/how-to/installing-config-sync> | 2026-11-25 | Flotte obligatoire, installation sans source, exemples Terraform |
| <https://docs.cloud.google.com/kubernetes-engine/fleet-management/docs/before-you-begin> | 2026-11-25 | API de la flotte |
| <https://docs.cloud.google.com/compute/docs/reference/rest/v1> | 2026-11-25 | `compute.googleapis.com` |
| <https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines> | 2026-11-25 | Champs `*_id`, `principalSet`, émetteur |
| <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/network-isolation> | 2026-11-25 | Point d'accès DNS |
| <https://docs.renovatebot.com/modules/manager/terraform/> | 2026-11-25 | Fichiers lus, registre par défaut, verrou |
| <https://docs.renovatebot.com/modules/manager/terraform/> | 2026-11-26 | Relue : « Renovate can not know if you want to use the Terraform or OpenTofu registry » ; rien sur le choix du registre par le verrou |
| <https://docs.renovatebot.com/modules/datasource/terraform-provider/> | 2026-11-26 | Date de publication disponible pour `registry.terraform.io` (API v2) et `registry.opentofu.org` (par `api.opentofu.org`) |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/modules/manager/terraform/base.ts> | 2026-11-26 | `analyzeTerraformProvider` : hôte du `source` pris comme registre ; sans hôte, registre du verrou s'il est seul et hors `registry.terraform.io` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/modules/manager/terraform/lockfile/util.ts> | 2026-11-26 | `extractLocks` : `packageName` et `registryUrl` lus sur la ligne `provider "hôte/espace/type"` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/modules/manager/terraform/extractors/terraform-block/required-provider.spec.ts> | 2026-11-26 | Cas `hashicorp/kubernetes` sans hôte et verrou OpenTofu : `registryUrls: ['https://registry.opentofu.org']` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/modules/manager/terraform/extractors/terraform-block/terraform-version.ts> | 2026-11-26 | `required_version` suivi sur `hashicorp/terraform`, source `github-releases` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/modules/datasource/terraform-provider/index.ts> | 2026-11-26 | `registry.opentofu.org` interrogé par `api.opentofu.org` ; `releaseTimestampSupport` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/modules/datasource/terraform-provider/schema.ts> | 2026-11-26 | `published` lu comme `releaseTimestamp` |
| <https://api.github.com/repos/renovatebot/renovate/commits?path=lib/modules/manager/terraform/base.ts> | 2026-11-26 | Commit « extract provider registry url from lockfile (#41487) » du 2026-02-25 |
| <https://api.opentofu.org/registry/docs/providers/hashicorp/google/index.json> | 2026-11-26 | Champ `published` par version ; `v8.12.0` le 2026-11-17T19:21:13Z |
| <https://kubernetes.io/docs/concepts/overview/working-with-objects/names/> | 2026-11-25 | Règles de nom des variables `app_namespace` et `app_service_account` |

### Utilisateur de `db-auth` sur Cloud SQL (T107, 2026-11-25)

Écrit par [OPS] d'après la relecture [SECU] de l'étape 3 (RS-04, PR #54), à relire par [SECU]. La racine crée la base `app` par `google_sql_database`, qui n'a pas d'argument `owner`, et l'utilisateur `app` par `google_sql_user`, en authentification intégrée, mot de passe par `password_wo`.

Hypothèse retenue, écrite aussi en tête de `google_sql_user.app` dans `gcp/tofu/database.tf` : la base `app` appartient à `cloudsqlsuperuser`, comme une base créée par la console ; l'utilisateur `app` reçoit `cloudsqlsuperuser`, hérite donc de l'appartenance implicite à `pg_database_owner`, et peut créer dans `public` : le script de schéma de l'API passe. Le prix est l'écart de privilèges : sur GCP, l'API tourne avec `cloudsqlsuperuser` (`CREATEROLE`, `CREATEDB`, triggers d'événement, réplication logique, `pg_largeobject`), quand en local le même utilisateur n'est que propriétaire de sa base. L'écart est listé au README du golden repo (ENF-02) et suivi par R-39. Le dépôt n'a pas encore de modèle de menaces : l'écart y entrera quand [SECU] l'ouvrira.

À lire au premier apply autorisé par Lucas, pour E12 (fonctions et catalogues lus dans la documentation de PostgreSQL 18, sources ci-dessous) :

```sql
SELECT pg_get_userbyid(datdba) AS owner FROM pg_database WHERE datname = 'app';
SELECT has_schema_privilege('app', 'public', 'CREATE');
SELECT roleid::regrole, admin_option, inherit_option, set_option
  FROM pg_auth_members WHERE member = 'app'::regrole;
```

Si le propriétaire n'est pas `cloudsqlsuperuser`, ou si `inherit_option` est faux, l'hypothèse tombe et le script de schéma échoue sur `CREATE TABLE` : la couche `gcp` passe alors au durcissement prévu par R-39 avant tout déploiement.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://www.postgresql.org/docs/18/catalog-pg-auth-members.html> | 2026-11-25 | Colonnes `roleid`, `member`, `admin_option`, `inherit_option`, `set_option` |
| <https://www.postgresql.org/docs/18/catalog-pg-database.html> | 2026-11-25 | `datdba`, propriétaire de la base |
| <https://www.postgresql.org/docs/18/functions-info.html> | 2026-11-25 | `has_schema_privilege` (`CREATE`, `USAGE`), `pg_get_userbyid` |
| <https://www.postgresql.org/docs/18/datatype-oid.html> | 2026-11-25 | Type `regrole` |

### Relevé du 2026-11-26 : couche Kubernetes de `gcp` (T129, étape 14)

Fait par [OPS], pour relecture de [SECU] et [QA]. Pages de Google lues par WebFetch, code des releases et des providers lu par `gh api`, essais hors ligne avec kubectl v1.37.1 (Kustomize v5.8.1), conftest 0.71.1 et kubeconform 0.8.0. Aucun cluster, aucun identifiant, aucun `tofu plan` ni `apply`. Les pages de Google n'affichent pas de date : la date est celle de la lecture.

Classe de la Gateway. La page des capacités des GatewayClass de GKE donne neuf classes. `gke-l7-global-external-managed` est l'équilibreur d'application externe global, avec les écouteurs HTTP et HTTPS (mode `Terminate`), `certificateRefs`, `allowedRoutes`, et pour les HTTPRoute les chemins `Exact`, `PathPrefix` et `RegularExpression` ; elle ne mentionne aucun sous-réseau proxy, que le réseau de `gcp/tofu/` ne crée pas. Retenue : c'est la classe de BENCH-004. Parmi les neuf, les classes `-mc` sont multi-clusters, `gke-l7-gxlb` est l'équilibreur classique, `gke-l7-regional-external-managed` et `gke-l7-rilb` sont régionales et la dernière interne : celle-ci est la globale externe non classique. Le montant de l'équilibreur n'est pas lisible (R-05) : [FINOPS] le valide avant le premier apply. Il naît de Kubernetes, hors de l'état d'OpenTofu : la Gateway se supprime avant `tofu destroy` (R-15).

Version de Gateway API et schéma. La même page donne Gateway API 1.5.0 à partir de GKE 1.35.2-gke.1842000, 1.4.0 à partir de 1.34.1-gke.1822000 ; la mineure 1.36 de `platform.yaml` est au-dessus. Le schéma est donc celui du canal standard v1.5.0 : release v1.5.0 de `kubernetes-sigs/gateway-api` (publiée le 2026-02-27, non immuable), `standard-install.yaml` de SHA-256 `510338cf6709f84410efcce5269268f4c7c5067efdc5d04c75aa2fd2f8380c96`, égal au champ `digest` de l'API et au fichier téléchargé. S08 valide la couche commune contre le `openAPIV3Schema` des CRD Gateway, GatewayClass et HTTPRoute de cette release, avec `additionalProperties: false` ajouté partout (une CRD laisse passer les champs inconnus, que le serveur d'API élague) : un champ de v1.7.0 que GKE ne sert pas fait échouer le contrôle. Essai : un champ inconnu sous `spec` de la Gateway et un port écrit en texte sont refusés, la couche commune de l'étape 7 passe. La couche commune n'emploie que des champs du cœur (RS-02).

Synchronisation des secrets. Page « Sync Secret Manager secrets to Kubernetes Secrets » : `SecretProviderClass` en `secrets-store.csi.x-k8s.io/v1` avec `provider: gke` et `parameters.secrets`, un bloc YAML de `resourceName` (`projects/<projet>/secrets/<nom>/versions/<version>`, sans région) et `path` ; `SecretSync` en `secret-sync.gke.io/v1` avec `serviceAccountName`, `secretProviderClassName`, `secretObject.type` et `secretObject.data` (`sourcePath`, `targetKey`), dans le même namespace que la classe. « The secret version must be in the same region as the cluster » ; la page ne dit ni que `latest` est une version (son exemple écrit `versions/2`), ni quels types de Secret sont admis (`Opaque`, `tls`, `docker-registry` en exemples), ni ce qui arrive si un Secret du même nom existe. Écarts 175 et 182.

Règle d'admission. `ValidatingAdmissionPolicy` est stable en `admissionregistration.k8s.io/v1` depuis Kubernetes 1.30 (page de Kubernetes). Sur Autopilot, d'après la page des mesures de sécurité, GKE exclut les namespaces gérés de la règle et refuse celles qui visent nœuds, volumes persistants, demandes de signature et revues de jeton, sans joker. La règle de la couche vise `pods` en `CREATE`, `failurePolicy: Fail`, et la liaison la limite à `saas-b2b` par l'étiquette `kubernetes.io/metadata.name`. L'expression CEL n'est pas compilée ici (écart 184).

`RootSync`. Types de GoogleContainerTools/kpt-config-sync au tag v1.25.2 (publié le 2026-11-03) et page des champs de Google : `sourceFormat` (`hierarchy` par défaut, `unstructured` voulu), `override.roleRefs` (« If unset, a binding to cluster-admin will be created » ; pour un `ClusterRole`, `namespace` décide entre `RoleBinding` et `ClusterRoleBinding`), `monitoring.enabled` (« controls whether the OpenTelemetry (otel-agent) sidecar is deployed ») que la page dit non pris en charge sur le `root-sync` de la console, de `gcloud` ou de Terraform, `git.auth` parmi `ssh`, `cookiefile`, `gcenode`, `token`, `none` dans le code, `githubapp` et `gcpserviceaccount` en plus sur la page. Écart 176.

Config Sync libre pour kind (T132, E16). La release v1.25.2 porte `config-sync-manifest.yaml` (307 385 octets), de SHA-256 `bb5cf3cafe4d8a04adbcd900cac709c26dad0d1856fdffdf4c599e4cd4058121`, égal au champ `digest` de l'API et au fichier téléchargé ; la release n'est pas immuable. Neuf images, relues au registre le 2026-11-26 par `docker buildx imagetools inspect` et égales aux condensats de BENCH-009 (lignes 94 à 102 de son script) : `gcr.io/config-management-release/` `reconciler-manager`, `reconciler`, `resource-group-controller`, `hydration-controller`, `oci-sync`, `helm-sync`, `gcenode-askpass-sidecar` en `v1.25.2`, `git-sync:v4.5.0-gke.3__linux_amd64` et `otelcontribcol:v0.159.0-gke.4`. Rien n'est vendoré : E16 n'est pas écrit (écart 181).

Cloud SQL. Le schéma du provider au tag v8.12.0 (`resource_sql_database_instance.go`) accepte `CA_MODE_UNSPECIFIED`, `GOOGLE_MANAGED_INTERNAL_CA`, `GOOGLE_MANAGED_CAS_CA` et `CUSTOMER_MANAGED_CAS_CA` pour `settings.ip_configuration.server_ca_mode`, optionnel et calculé ; `server_ca_cert` est `Sensitive: true`. La page d'autorisation SSL de Google : `GOOGLE_MANAGED_INTERNAL_CA` est la CA par instance, défaut à la création ; la CA partagée demande de vérifier aussi le nom d'hôte ; le SAN ne porte le nom d'hôte que pour les instances à Private Service Connect. Écart 173.

#### Hôte et CA des services managés

Question de l'écart 87 de `main`, qui se pose de même pour Cloud SQL : l'adresse du point de terminaison de Memorystore, l'adresse privée de Cloud SQL et les deux CA n'existent qu'après l'apply, alors que l'`app-config` de `gcp` est un manifest versionné que lit Config Sync. Proposition de [OPS], pour décision du DSI.

Voie proposée : trois manifests de `gcp/k8s/values/` que la personne qui applique écrit, à partir de sorties d'OpenTofu sans secret, dans une PR relue. `app-config.yaml` (hôtes), `app-ca.yaml` (paquets de CA, un ConfigMap) et `secret-provider-class.yaml` (projet de Secret Manager). Le dépôt les livre avec des valeurs d'attente qui échouent fermées : un hôte sous `.invalid` ne se résout jamais, un paquet vide arrête l'API au démarrage avec un message qui nomme le fichier (écart 174), un projet `PROJECT_ID` ne lit aucun secret. Le parcours : l'utilisateur applique la racine, lit `tofu output -raw database_private_ip` et `tofu output -raw database_server_ca_cert` avec ses identifiants (l'état est chiffré, ADR-008 condition 2), écrit les valeurs, ouvre la PR, puis applique `gcp/k8s/bootstrap/` une fois. Les valeurs sont dans Git avant le premier `RootSync`, donc les pods démarrent avec elles. Seule une rotation demande un redémarrage de l'API (écart 131).

Raisons. Ce ne sont pas des secrets : un hôte privé et un certificat public. Les passer par Secret Manager et la synchronisation de GKE les ferait arriver dans un Secret Kubernetes, alors que l'API les lit dans `app-config` (variables d'environnement) et que la règle de parité compare ces références (ADR-007 condition 5) ; la synchronisation ne produit que des Secrets. Elle ajouterait des secrets, des liaisons IAM et des accès à la franchise de 10 000 par mois (ADR-007, condition 2), pour des valeurs publiques. Un fichier relu en PR garde l'historique, le retour arrière et un seul chemin pour toute valeur propre au déploiement. Voie écartée : un nom DNS stable, par une zone privée de Cloud DNS créée par OpenTofu, qui supprimerait les hôtes mais pas les CA, et ajouterait une ressource et un nom que `VerifyFull` ne vérifierait pas (écart 173).

Ce que [SECU] relit. (1) Que la PR de valeurs soit relue par le propriétaire : `.github/CODEOWNERS` nomme `/gcp/k8s/values/` sur sa ligne, mais la relecture obligatoire des propriétaires est un réglage du dépôt généré, que la personne qui l'installe pose (écart 197) ; remplacer l'hôte ou la CA suffirait à détourner la connexion de l'API vers un serveur du réseau privé. (2) S31 : modes `VerifyCA` et `VerifyFull` seuls, hôtes, CA qui doivent être des autorités, clé privée refusée. (3) Que les sorties ne portent aucun secret : S15 refuse déjà les jetons ; le paquet de CA est sensible pour le provider seulement. (4) L'empreinte SHA-256 de chaque certificat de la PR, à comparer avec la sortie. (5) La rotation de la CA et le redémarrage de l'API. Ce que la proposition ne fait pas : aucune écriture automatique des valeurs, qui demanderait un script qui lit l'état et une décision du DSI sur qui l'exécute.

#### `gateway-tls` sur `gcp`

Question de T129, avec [SECU]. Page de GKE sur la sécurisation d'une Gateway : trois voies, un Secret Kubernetes de type TLS cité par `certificateRefs` (la page l'illustre avec un certificat auto-signé et dit que le client doit alors le connaître), un certificat de Compute Engine, ou Certificate Manager (annotation `networking.gke.io/certmap`, qui ne se combine pas avec `certificateRefs`). Un certificat géré par Google demande un nom de domaine et un enregistrement DNS. Le golden repo n'a pas de domaine : la proposition est le Secret, produit comme `db-auth` par la synchronisation de GKE (ADR-007). Le provider `tls` 4.4.2 (publié le 2026-10-21) a la ressource éphémère `tls_private_key`, et `tls_self_signed_cert` accepte `private_key_pem_wo`, écriture seule, « never persisted to Terraform state » : la clé ne passe pas dans l'état. Le certificat, public, et la clé vont dans deux secrets de Secret Manager par `secret_data_wo`, puis un `SecretSync` de type `tls`, qui reste à vérifier comme le type de `db-auth` (écart 175). Il faut donner la même clé à `tls_self_signed_cert` et à `secret_data_wo` : question ouverte comme pour `db-auth`. Le producteur s'écrit avec l'écouteur HTTPS de la PR #83. Avec un domaine, Certificate Manager serait préférable et demanderait un ADR (annotation de la Gateway propre à GKE). Écart 177.

#### Cache joignable de tout pod

Écart 84 de `main` (« sur `gcp`, tout pod du cluster peut atteindre le cache, à traiter à l'étape 14 »), repris à l'écart 178. Le point de terminaison est dans le sous-réseau de GKE ; la politique de connexion de service limite le sous-réseau, non les pods. Une NetworkPolicy de sortie limiterait les pods de `saas-b2b`, demanderait l'adresse du point de terminaison et des règles de DNS et de ports non lues ; elle ne couvrirait pas les autres namespaces. Non écrite, décision à la GATE 2.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://docs.cloud.google.com/kubernetes-engine/docs/how-to/gatewayclass-capabilities> | 2026-11-26 | Neuf classes, Gateway API 1.5.0 dès GKE 1.35.2-gke.1842000, capacités de `gke-l7-global-external-managed` |
| <https://docs.cloud.google.com/kubernetes-engine/docs/how-to/secure-gateway> | 2026-11-26 | Secret, certificat Compute Engine et Certificate Manager ; auto-signé admis avec un Secret |
| <https://docs.cloud.google.com/secret-manager/docs/sync-k8-secrets> | 2026-11-26 | `SecretProviderClass`, `SecretSync`, `resourceName`, `type`, région, namespace |
| <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-security> | 2026-11-26 | `ValidatingAdmissionPolicy` sur Autopilot : namespaces gérés exclus, kinds refusés |
| <https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/> | 2026-11-26 | Stable depuis Kubernetes 1.30, forme de la règle et de la liaison |
| <https://docs.cloud.google.com/kubernetes-engine/config-sync/docs/reference/rootsync-reposync-fields> | 2026-11-26 | Champs du `RootSync` |
| <https://github.com/GoogleContainerTools/kpt-config-sync/tree/v1.25.2/pkg/api/configsync/v1beta1> | 2026-11-26 | `roleRefs` (cluster-admin par défaut), `MonitoringSpec`, `GitConfig`, `sourceFormat` |
| <https://github.com/GoogleContainerTools/kpt-config-sync/releases/tag/v1.25.2> | 2026-11-26 | Publiée le 2026-11-03 ; `config-sync-manifest.yaml`, SHA-256 `bb5cf3ca…8121` |
| `docker buildx imagetools inspect gcr.io/config-management-release/<image>` (buildx 0.37.2) | 2026-11-26 | Neuf condensats égaux à BENCH-009 |
| <https://docs.cloud.google.com/sql/docs/postgres/authorize-ssl> | 2026-11-26 | Modes de CA du serveur, SAN et nom d'hôte, vérification de la CA |
| <https://github.com/hashicorp/terraform-provider-google/blob/v8.12.0/google/services/sql/resource_sql_database_instance.go> | 2026-11-26 | `server_ca_mode` (valeurs), `server_ca_cert` sensible |
| <https://github.com/hashicorp/terraform-provider-tls/tree/v4.4.2/docs> | 2026-11-26 | `tls_private_key` éphémère, `private_key_pem_wo` de `tls_self_signed_cert` ; v4.4.2 du 2026-10-21 |
| <https://www.rfc-editor.org/rfc/rfc6761.html> | 2026-11-26 | Section 6.4, `invalid.` : réponse négative immédiate demandée aux résolveurs, NXDOMAIN aux serveurs de cache (SHOULD) |
| <https://github.com/kubernetes-sigs/gateway-api/releases/tag/v1.5.0> | 2026-11-26 | v1.5.0 du 2026-02-27, `standard-install.yaml`, SHA-256 `510338cf…0c96` |

## RS-17. CI du golden repo dans CELIAN

Décision : un workflow racine de CELIAN, `golden-saas-b2b.yml`, appelle les tâches du golden repo ; les workflows du golden repo appellent les mêmes tâches. Le contrôle X01 copie le golden repo dans un dépôt Git neuf pour exercer ses propres hooks et sa configuration.

Pourquoi : la spec fait tourner la CI du golden repo dans le dépôt de CELIAN. Une logique écrite une fois, dans les tâches, ne peut pas diverger entre les deux workflows.

Décision du DSI (2026-11-21) : la CI du golden repo tourne dans CELIAN seulement, comme le dit la spec. Les workflows de `golden/saas-b2b/.github/`, jobs du SBOM et du scan compris, décrivent la CI du futur projet généré ; X01 les exerce dans une copie autonome, sans les lancer sur GitHub. Un dépôt miroir, où ils tourneraient tels quels, viendra avec le générateur, hors de ce plan.

Les jobs du workflow racine qui doivent bloquer la fusion (statique, tests unitaires, bout en bout et scan des images, FR-022) entrent dans les contrôles requis du ruleset de `main`, `.github/rulesets/main.json`, qui ne compte aujourd'hui que `pre-commit` et `secrets (full history)`. Le script qui applique le ruleset demande les droits admin : Lucas le lance.

À vérifier avant l'étape 1 (porteur [OPS]) : que GitHub ne lance pas de workflow depuis un sous-dossier, et que Renovate et release-please ne lisent pas une configuration placée dans `golden/saas-b2b/` ; le comportement d'un workflow filtré par chemin face aux contrôles requis du ruleset de `main` ; l'option de `check-yaml` pour les fichiers YAML à plusieurs documents ; ce qu'actionlint lit hors de `.github/workflows/` à la racine ; la présence et la version de Docker sur les runners `ubuntu-latest` (Docker Engine 28.0.0 au moins, ADR-011) ; la disponibilité de runners arm64 pour un dépôt public.

### Relevé du 2026-11-23 (T003)

Fait par [DEV] à la place d'[OPS], porteur désigné, qui relit. Il lève les cinq points que T003 attend avant l'étape 1. Docker sur `ubuntu-latest` reste à T040, les runners arm64 restent ouverts.

1. Workflows d'un sous-dossier. GitHub ne lit les workflows que dans `.github/workflows` à la racine du dépôt : « You must store workflow files in the `.github/workflows` directory of your repository. » Rien de `golden/saas-b2b/.github/` ne tourne dans CELIAN, et X01 reste le seul moyen d'exercer ces workflows.
2. Renovate et release-please. Renovate lit un seul fichier de configuration, le premier trouvé dans une liste fixe de chemins (`renovate.json`, `.github/renovate.json`, `.gitlab/renovate.json`, `.renovaterc` et leurs variantes, `package.json`) : `golden/saas-b2b/renovate.json` n'en fait pas partie et n'est jamais lu. En revanche, les gestionnaires de la configuration de CELIAN trouvent leurs fichiers dans tout le dépôt. Celui des actions GitHub lit `(^|/)(workflow-templates|\.(?:github|gitea|forgejo)/(?:workflows|actions))/.+\.ya?ml$` et `(^|/)action\.ya?ml$`, celui de pre-commit `(^|/)\.pre-commit-config\.ya?ml$` ; ce dernier est coupé par défaut, mais `renovate.json` de CELIAN l'active. Les PR de mise à jour des workflows et des hooks du golden repo viendront donc de la configuration de CELIAN, sous ses règles (7 jours, exception de sécurité). Conséquence pour S23 et T098 : `golden/saas-b2b/renovate.json` se contrôle de façon statique et ne s'exerce que dans X01 ou dans le futur dépôt miroir. Le gestionnaire maison de CELIAN pour les variables `_IMAGE` reste limité à `^\.github/workflows/`. release-please ne lit que les chemins que lui passe le workflow de CELIAN (`config-file`, « Path to the release-please config in the repository », et `manifest-file`) : les fichiers release-please du golden repo sont ignorés. Le paquet `.` de CELIAN couvre tout le dépôt, et un commit sur `golden/` compte dans le journal des versions de CELIAN.
3. Workflow filtré par chemin et contrôles requis. Un workflow sauté par un filtre de chemins, de branches ou par le message de commit laisse ses contrôles en attente (« Pending ») et bloque la fusion ; la page conseille : « Avoid requiring workflows that can be skipped. » Un job sauté par sa condition `if` rend « Success » ; un job qui dépend d'un job en échec est sauté et peut ne pas bloquer la fusion, d'où `always()` avec `needs` pour un contrôle requis. Seuls comptent les contrôles nés d'événements éligibles, dont `push` et `pull_request`. Décision : le workflow `golden-saas-b2b.yml` ne porte aucun filtre de chemins, et son job `static`, rapide, tourne à chaque PR de CELIAN. Un job coûteux (sur kind, à partir de T051) qui voudrait un filtre passera par une condition de job alimentée par un job de détection des changements, avec la garde `always()`, à trancher avec [OPS] à ce moment-là. Le ruleset de `main` nomme déjà ses contrôles par le `name` de leur job (`pre-commit`, `secrets (full history)`) ; le job s'appelle donc `static`, et T014 l'ajoute sous ce nom.
4. YAML à plusieurs documents. `check-yaml` de pre-commit-hooks v6.0.0 (le tag pointe sur le SHA figé dans `.pre-commit-config.yaml`) accepte `--allow-multiple-documents`. `--unsafe` l'implique mais ne fait plus qu'une analyse de syntaxe, « removes all guarantees of portability » : écarté. Décision : une seconde entrée de `check-yaml` avec `--allow-multiple-documents`, limitée à `golden/`, où vivront les manifests Kubernetes ; le reste de CELIAN garde la règle d'un document par fichier (T013).
5. actionlint hors de `.github/workflows/`. Le hook `actionlint` de v1.7.12 (tag égal au SHA figé) porte `files: ^\.github/workflows/` : il ne voit pas `golden/saas-b2b/.github/workflows/`. actionlint vérifie tout fichier passé en argument : « When paths to YAML workflow files are given as arguments, actionlint checks them. » Décision : T013 élargit `files` du hook aux workflows du golden repo, avant qu'ils arrivent à l'étape 2.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax> | 2026-11-23 | Emplacement des workflows ; contrôles en attente si le workflow est sauté par un filtre ; `permissions` (`id-token`, `contents`) |
| <https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/troubleshooting-required-status-checks> | 2026-11-23 | Contrôles requis sautés, job sauté qui rend « Success », dépendance en échec et `always()`, événements éligibles, rulesets |
| <https://docs.renovatebot.com/configuration-options/> | 2026-11-23 | Liste des fichiers de configuration, premier trouvé |
| <https://docs.renovatebot.com/modules/manager/github-actions/> | 2026-11-23 | Motifs de fichiers par défaut du gestionnaire des actions |
| <https://docs.renovatebot.com/modules/manager/pre-commit/> | 2026-11-23 | Motif par défaut, gestionnaire coupé par défaut |
| <https://github.com/googleapis/release-please-action/blob/45996ed1f6d02564a971a2fa1b5860e934307cf7/README.md> | 2026-11-23 | Entrées `config-file`, `manifest-file` et `path` de la version figée dans CELIAN |
| <https://github.com/googleapis/release-please/blob/main/docs/manifest-releaser.md> | 2026-11-23 | Paquet `.` à la racine du dépôt, chemins relatifs à la racine |
| <https://github.com/pre-commit/pre-commit-hooks/blob/3e8a8703264a2f4a69428a0aa4dcb512790b2c8c/README.md> | 2026-11-23 | Options `--allow-multiple-documents` et `--unsafe` de `check-yaml` ; tag v6.0.0 égal à ce SHA |
| <https://github.com/rhysd/actionlint/blob/914e7df21a07ef503a81201c76d2b11c789d3fca/.pre-commit-hooks.yaml> | 2026-11-23 | `files: ^\.github/workflows/` du hook ; tag v1.7.12 égal à ce SHA |
| <https://github.com/rhysd/actionlint/blob/914e7df21a07ef503a81201c76d2b11c789d3fca/docs/usage.md> | 2026-11-23 | Fichiers passés en argument vérifiés |

### Décision du DSI du 2026-11-24 : le Renovate de CELIAN couvre `golden/`

Le Renovate de CELIAN couvre aussi `golden/`, ses workflows et son `.pre-commit-config.yaml`. Les versions du golden repo montent donc par des PR de CELIAN, passées dans sa CI et sous ses règles (7 jours, exception de sécurité). `golden/saas-b2b/renovate.json` sert au projet généré : CELIAN ne le lit pas (point 2 du relevé du 2026-11-23), et seul S23 le contrôle, statiquement.

Ce que l'étape 2 (T093 à T101) en tire, d'après le relevé de RS-18 du 2026-11-24 :

1. Les motifs par défaut des gestionnaires `github-actions` et `pre-commit`, comme celui du preset `customManagers:githubActionsVersions`, commencent par `(^|/)` : ils trouvent déjà `golden/saas-b2b/.github/workflows/` et `golden/saas-b2b/.pre-commit-config.yaml`. Le gestionnaire maison des variables `_IMAGE` de CELIAN s'arrêtait à `^\.github/workflows/`. Il reçoit un second motif pour les workflows du golden repo, sans quoi l'image de gitleaks de leur `secrets.yml` échapperait à la décision.
2. Les règles propres au projet généré (majeure de `postgres`, paires kind et Envoy Gateway) vivent dans `golden/saas-b2b/renovate.json`. Elles ne s'appliquent donc pas au golden repo dans CELIAN. C'est sans effet aujourd'hui : le golden repo ne nomme encore aucune de ces images, et le gestionnaire `kubernetes`, sans motif par défaut, reste coupé dans CELIAN. À trancher par le DSI avant l'étape 3 : les Dockerfile du golden repo entreront dans le gestionnaire `dockerfile` de CELIAN, dont les motifs par défaut commencent aussi par `(^|/)`, sous les règles de CELIAN.
3. S23 lit les règles du fichier. Le validateur de Renovate le lit en plus dans X01, par un hook de la copie autonome au stade `manual`. Les deux contrôles sont statiques : aucun Renovate ne tourne sur ce fichier avant le dépôt miroir.

### Relevé du 2026-11-24 : règles du golden repo et outils de test dans le Renovate de CELIAN

Fait par [DEV], dans le code et la documentation de Renovate au tag 44.247.1, lus par `gh api`. Il remplace le point 2 de la décision ci-dessus : les règles propres au projet généré s'appliquent désormais aussi au golden repo dans CELIAN.

1. Le `renovate.json` racine porte les quatre entrées de `golden/saas-b2b/renovate.json` (majeure de `postgres`, image de nœud sur la mineure, paire kind, paire Envoy Gateway), avant l'entrée de l'ADR-016. Les quatre ne posent que `allowedVersions` ou `groupName`, l'entrée de l'ADR-016 que le comportement du délai et l'approbation : aucune clé n'est posée deux fois, et leur ordre ne change rien. Aucune image n'est prise des deux côtés non plus, deux tests de `renovate_rules` le vérifient. `scripts/renovate/check-renovate.sh`, qui remplace `check-delay.sh`, lance les deux paquets de S23 sur la racine, `renovate_rules` contre `golden/saas-b2b/platform.yaml`. Les deux fichiers suivent donc la même valeur, et un écart fait échouer le job `pre-commit`.
2. `golden/saas-b2b/tests/tools/install.sh` porte un commentaire `# renovate:` au-dessus de `TASK_VERSION` et de `CONFTEST_VERSION`. Un gestionnaire `regex` les lit, dans la racine pour `golden/`, et dans le fichier du golden repo pour le projet généré. La source `github-releases` donne sa date de publication à Renovate, qui compte donc les 7 jours ; `depName` s'écrit `owner/repo`. Les tags portent un `v` que les constantes n'ont pas, et `extractVersion` ne s'applique qu'aux versions de la source : d'où `extractVersionTemplate` `^v(?<version>.*)$`, l'exemple de la documentation. Les expressions ont été essayées sur le script par `regex.find_all_string_submatch_n` d'OPA 1.21.1, moteur RE2 comme celui de Renovate : elles rendent `go-task/task` 3.54.0 et `open-policy-agent/conftest` 0.71.1. Aucun Renovate n'a tourné, et le validateur de Renovate n'a pas été lancé.
3. `config:recommended` étend `:ignoreModulesAndTests`, qui met `**/tests/**` dans `ignorePaths` : sans autre réglage, le script échapperait à tout gestionnaire, dans CELIAN comme dans le projet généré. Une entrée de `customManagers` n'accepte pas `ignorePaths` (liste fermée de ses clés). L'objet `regex` en tête l'accepte (portée `manager`), et Renovate le fusionne dans la configuration de chaque gestionnaire `regex`, où `ignorePaths`, non fusionnable, remplace la liste héritée. Les deux fichiers y écrivent la liste du preset sans `**/tests/**`. Aucun fichier des autres gestionnaires `regex` n'est aujourd'hui sous un dossier de tests.
4. Aucun gestionnaire ne met à jour `SHA256SUMS`. La PR de Renovate échoue en CI tant que les sommes de la nouvelle version ne sont pas écrites à la main, depuis le fichier de sommes de la release, comme pour le rendu vendu d'Envoy Gateway (ADR-005).
5. `masterIssue` devient `dependencyDashboard`, puis un objet `{ enabled }`. Tant qu'une entrée demande l'approbation, Renovate garde le tableau de bord et lit ses cases : la clé ne peut pas retirer l'approbation de l'ADR-016. S23 la refuse quand même, avec les autres clés anciennes.
6. Après la relecture [SECU] de la PR #55, `renovate_rules` ne se laisse plus tromper par une entrée qui a l'air juste. Renovate n'applique une entrée que si tous ses critères correspondent, et un motif qui commence par `!` exclut les noms qu'il prend. Les quatre entrées n'ont donc droit qu'à `description`, `matchDatasources`, `matchPackageNames` et leur clé propre, sans motif négatif. Seules l'entrée Postgres et l'entrée du nœud kind posent `allowedVersions`, pour qu'une entrée plus loin ne reprenne pas une image par un glob ou par `matchDepNames`. Depuis le 2026-11-25, `enabled` ne vaut que `true` où qu'il soit écrit, parce qu'une entrée sans critère, un glob, une regex, une négation, `matchDepNames` ou `matchDatasources` seul coupaient sans que S23 le voie des mises à jour, correctifs de sécurité compris, et seuls les groupes de kind et d'Envoy Gateway posent une clé qui décide de la branche d'une mise à jour (`groupName`, `groupSlug`, `group`, préfixes, options `separate*` et leurs anciens noms), avec pour motifs des regex ou leurs propres noms, et chaque paire prise entière ou pas du tout. Les conteneurs anciens que Renovate verse dans `packageRules` (`pathRules`, `packages`, `packageFiles`, les clés de `depTypes`, les objets de langage comme `docker` ou `node`, un `packageRules` imbriqué) sont refusés partout, parce que les contrôles des entrées ne lisent que le haut de `packageRules`, et aucun gestionnaire ni aucune option actuelle ne porte ces noms. Sont refusées partout, enfin, les clés qui changent ce que Renovate lit ou l'endroit où il cherche un paquet (`overridePackageName`, `overrideDatasource`, `overrideDepName`, `registryUrls`, `defaultRegistryUrls`, `followTag`, `ignoreDeps`, `enabledManagers`, `includePaths`, `ignorePaths` hors de l'objet `regex`, l'ancien `ignoreNodeModules`), parce que chacune peut arrêter une mise à jour, correctifs de sécurité compris ; parmi les presets d'`extends`, seul `:ignoreModulesAndTests` en pose une, `ignorePaths`, que S23 ne lit pas puisqu'il ne lit que le fichier. S23 exige en outre le gestionnaire d'`install.sh` à la lettre, description mise à part, avec un chemin tiré de celui de `platform.yaml`, et l'objet `regex` réduit à la liste ci-dessus. `customManagers` ne contient que deux entrées, chacune à la lettre à sa description près, celle d'`install.sh` et celle des variables `_IMAGE` (motifs de fichiers tirés eux aussi de `platform.yaml`), parce que le gabarit d'une entrée l'emporte sur ce que capture l'expression et choisit `datasource`, `packageName` et `registryUrl`, donc de qui Renovate tient la date (`lib/modules/manager/custom/regex/utils.ts`, l. 55 à 74, et `custom/utils.ts`, l. 6 à 17 et 37 à 55, où `versioning`, `extractVersion` et les alias de registre entrent aussi). Sont refusées partout en plus `customDatasources`, dont les versions portent leur propre `releaseTimestamp` (`datasource/custom/schema.ts`, l. 4 à 31), `npmrc` et `npmrcMerge`, que `npmrc.ts` (l. 47 à 123) convertit en `hostRules` et en entrées `registryUrls`, `registryAliases`, `hostRules`, `extractVersion`, `versioning`, `updatePinnedDependencies`, `constraintsFiltering` et les quatre clés `replacement*` (`options/index.ts`, au tag 44.247.1), alors que `constraints` et `constraintsVersioning` gardent des valeurs en chaînes au premier niveau, usage que documente `configuration-options.md` (`"constraints": {"node": "^18.0.0 || >=20.0.0"}`) et que les noms `node` ou `docker` refusés comme objets de langage ne doivent pas casser. Enfin `tests/tools/check-renovate-comments.sh`, lancé par S23 et par `check-renovate.sh`, refuse une ligne `<NOM>_VERSION=` qui ne suit pas immédiatement son commentaire `# renovate:`, ou dont la valeur n'est pas entre guillemets.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/presets/internal/config.preset.ts> | 2026-11-24 | `config:recommended` étend `:ignoreModulesAndTests` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/presets/internal/default.preset.ts> | 2026-11-24 | `ignorePaths` de `:ignoreModulesAndTests`, dont `**/tests/**` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/workers/repository/extract/index.ts> | 2026-11-24 | Configuration de chaque gestionnaire, puis de chaque entrée de `customManagers`, avant le tri des fichiers |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/workers/repository/extract/file-match.ts> | 2026-11-24 | Fichiers écartés par `ignorePaths`, en sous-chaîne ou en glob |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/index.ts> | 2026-11-24 | `getManagerConfig` fusionne l'objet du gestionnaire, `regex` compris |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/utils.ts> | 2026-11-24 | `mergeChildConfig` : une option non fusionnable est remplacée |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/options/index.ts> | 2026-11-24 | `ignorePaths` : portées `repo` et `manager`, `mergeable: false` ; une option par gestionnaire ; `description` partout |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/options/scopes.ts> | 2026-11-24 | Portée `manager` : gestionnaires et gestionnaires maison |
| <https://github.com/renovatebot/renovate/blob/44.247.1/tools/generate-imports.mjs> | 2026-11-24 | Option par gestionnaire générée aussi pour `regex` et `jsonata` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/validation.ts> | 2026-11-24 | Clés permises dans une entrée de `customManagers` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/modules/manager/custom/regex/readme.md> | 2026-11-24 | Groupes nommés `datasource`, `depName`, `currentValue` ; RE2 ; correspondance sur le fichier entier |
| <https://github.com/renovatebot/renovate/blob/44.247.1/docs/usage/configuration-options.md> | 2026-11-24 | `extractVersion` et son exemple `^v(?<version>.*)$` ; `extractVersionTemplate`, `versioningTemplate` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/docs/usage/key-concepts/minimum-release-age.md> | 2026-11-24 | Date de publication prise en charge pour `github-releases` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/modules/datasource/github-releases/readme.md> | 2026-11-24 | `packageName` au format `owner/repo` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/migrations/migrations-service.ts> | 2026-11-25 | Ligne 109 : `masterIssue` devient `dependencyDashboard` ; lignes 103 à 105 : `managerBranchPrefix`, `multipleMajorPrs` et `separatePatchReleases` deviennent des clés de branche |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/migrations/custom/separate-major-release-migration.ts> | 2026-11-25 | `separateMajorReleases` devient `separateMajorMinor` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/migrations/custom/path-rules-migration.ts> | 2026-11-25 | Lignes 9 à 17 : les entrées de `pathRules` passent dans `packageRules` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/migrations/custom/packages-migration.ts> | 2026-11-25 | Lignes 9 à 17 : les entrées de `packages` passent dans `packageRules` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/migrations/custom/package-files-migration.ts> | 2026-11-25 | Lignes 8 à 41 : un objet de `packageFiles` avec d'autres clés devient une entrée |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/migrations/custom/dep-types-migration.ts> | 2026-11-25 | Lignes 12 à 40 : `dependencies`, `devDependencies`, `optionalDependencies`, `peerDependencies`, `engines` et `depTypes` deviennent des entrées |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/migration.ts> | 2026-11-25 | Lignes 140 à 166 : un objet sous `docker`, `dotnet`, `golang`, `java`, `js`, `node`, `php`, `python`, `ruby` ou `rust` devient une entrée placée en tête ; lignes 167 à 191 : un `packageRules` imbriqué est fusionné dans son parent |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/modules/manager/api.ts> | 2026-11-25 | Liste des gestionnaires : aucun ne porte le nom d'un conteneur ancien |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/migrations/custom/dependency-dashboard-migration.ts> | 2026-11-24 | Booléen changé en `{ enabled }` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/workers/repository/dependency-dashboard.ts> | 2026-11-24 | Tableau de bord gardé et cases lues tant qu'une entrée demande l'approbation |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/util/package-rules/index.ts> | 2026-11-25 | Lignes 28 à 46 : une entrée s'applique si tous ses critères correspondent, et à tout paquet sans critère ; lignes 69 à 74 : `groupSlug` suit le dernier `groupName` ; lignes 79 à 103 : `enabled` à `false` écarte la mise à jour, que seul un `enabled` ou un `force.enabled` vrai rétablit |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/util/string-match.ts> | 2026-11-25 | Lignes 48 à 57 : un motif en `!` exclut ; lignes 11 à 27 : glob lu par minimatch sans casse, `*` prend tout nom ; lignes 73 à 92 : `/` et `//` lus comme une regex vide |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/workers/repository/init/vulnerability.ts> | 2026-11-25 | Lignes 160 à 166 : l'entrée d'un avis de sécurité force les réglages de `vulnerabilityAlerts`, sans `enabled` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/workers/repository/updates/branch-name.ts> | 2026-11-25 | Lignes 59 à 159 : nom de branche tiré du groupe, du slug, des préfixes et des options `separate*` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/workers/repository/updates/branchify.ts> | 2026-11-25 | Lignes 47 à 49 : les mises à jour d'un même nom de branche forment une seule PR |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/options/index.ts> | 2026-11-25 | Lignes 1534 à 1570 : `enabledManagers`, `includePaths`, `ignorePaths` ; lignes 1636 à 1670 : `defaultRegistryUrls`, `registryUrls` ; lignes 2634 à 2660 : options `override*`, dans `packageRules` seulement |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/workers/repository/process/lookup/index.ts> | 2026-11-25 | Lignes 249 à 267 : `followTag` sans étiquette trouvée, aucune mise à jour |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/modules/datasource/docker/index.ts> | 2026-11-25 | Lignes 1282 à 1316 : le résultat d'une image ne porte pas d'étiquettes |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/workers/repository/process/fetch.ts> | 2026-11-25 | Ligne 127 : `ignoreDeps` écarte un nom exact |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/migrations/custom/ignore-node-modules-migration.ts> | 2026-11-25 | Ligne 8 : `ignoreNodeModules` devient `ignorePaths` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/presets/internal/helpers.preset.ts> | 2026-11-25 | `pinGitHubActionDigests` ne pose aucune des clés refusées ; `followTag` vient de presets hors d'`extends` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/presets/internal/custom-managers.preset.ts> | 2026-11-25 | `githubActionsVersions` ne pose aucune des clés refusées |

### Relevé du 2026-11-25 : Docker sur les runners et filtre du job sur kind (T040, étape 6)

Fait par [OPS], dans le dépôt `actions/runner-images`.

`ubuntu-latest` change d'image : la page d'accueil annonce Ubuntu 26.04 pour ce label en novembre 2026 et donne pour cette ligne « `ubuntu-latest` or `ubuntu-26.04` » ; la bascule d'un label `-latest` « is gradual and happens over 1-2 months ». Les deux images possibles portent Docker Engine 28.0.0 au moins (ADR-011, condition 3) : Docker Server 29.4.2 sur Ubuntu 26.04 (image 20261116.202.1), 28.0.4 sur Ubuntu 24.04 (image 20261116.376.1). Elles portent aussi kind 0.33.0 et kubectl 1.37.2 ; le job ne s'en sert pas, il installe les siens, vérifiés par leur SHA-256, devant le `PATH`. Le paquet `iproute2`, qui fournit `ss`, figure sur Ubuntu 26.04 : E03 lit les ports en écoute par `ss` sous Linux. Les contrôles préalables relisent la version du moteur à chaque exécution : une image sous 28.0.0 ferait échouer le job sans rien créer.

Le job reste sur `ubuntu-latest`, le label que nomme T051. Un job requis qui change d'image d'un jour à l'autre peut échouer sans changement du dépôt ; si cela arrive, le repli est `ubuntu-24.04`, à décider par le DSI.

Filtre de chemins (point 3 du relevé du 2026-11-23) : décision d'[OPS], `e2e-lite` tourne sans filtre à chaque PR, comme `static`. Le dépôt est public et les runners standard gratuits (R-16) ; un filtre demanderait un job de détection et la garde `always()` pour un gain de quelques minutes. À revoir si sa durée dépasse le quart d'heure.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://github.com/actions/runner-images/blob/main/README.md> | 2026-11-25 | `ubuntu-latest` vers Ubuntu 26.04 ; bascule sur un à deux mois |
| <https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2604-Readme.md> | 2026-11-25 | Image 20261116.202.1 : Docker Server 29.4.2, kind 0.33.0, kubectl 1.37.2, bash 5.3.9, iproute2 |
| <https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md> | 2026-11-25 | Image 20261116.376.1 : Docker Server 28.0.4, kind 0.33.0, kubectl 1.37.2, bash 5.2.21 ; annonce de la bascule |

### Décision du DSI du 2026-11-24 sur RS-17, point 2

Les Dockerfile du golden repo restent dans les motifs par défaut du gestionnaire `dockerfile` du Renovate de CELIAN. Leurs images montent par des PR de CELIAN, sous ses règles, comme les workflows et les hooks du golden repo.

## RS-18. Outils de test

Décision : scripts bash pour les tests sur kind et les contrôles préalables, comme les scripts de BENCH ; politiques en Rego exécutées par conftest, outil que nomment les ADR-005 à ADR-011 ; validation de schéma par kubeconform, nommé par US-007, outil à confirmer avec [QA] (ADR-005, condition 5) ; Trivy pour le HCL, le SBOM et le scan des images (RS-22) ; conftest aussi pour la décision du scan (RS-23).

À vérifier avant usage, avec version, licence, date et somme de contrôle du binaire : conftest, kubeconform, cosign (qui vérifie aussi la signature de Trivy à chaque montée, RS-22), le framework de test .NET, celui du front, le validateur de configuration de Renovate. Trivy : 0.76.2 lue le 2026-11-23 (RS-22), somme et signature à vérifier à l'installation. Porteur : [DEV], avec [QA] pour le choix final.

Alternatives : des tests en Python, écartés parce que le projet généré n'aurait pas Python dans ses prérequis d'exécution (ENF-07) ; Kyverno en CLI, réservé au profil full.

### Relevé du 2026-11-23 : conftest (T002)

Fait par [DEV]. Sources : l'API GitHub du dépôt `open-policy-agent/conftest`, lue par `gh api`, ses fichiers au tag v0.71.1, et les pages de conftest.dev et de la CNCF.

Version retenue : conftest v0.71.1, publiée le 2026-10-06, dernière release. Elle a 48 jours au 2026-11-23 et passe le délai de 7 jours (principe VI). Licence Apache-2.0, d'après le fichier `LICENSE` (« Licensed under the Apache License, Version 2.0 ») ; l'API GitHub, elle, répond `NOASSERTION`, parce que le fichier commence par un en-tête de copyright.

Gouvernance : le dépôt appartient à l'organisation `open-policy-agent`, celle d'OPA, projet gradué à la CNCF (accepté le 2018-03-29, gradué le 2021-01-29). La page de la CNCF ne nomme pas conftest. La gouvernance de l'organisation (`GOVERNANCE.md` d'OPA) vote par organisation, « so that no single organization can dominate an area of expertise ». `MAINTAINERS.md` d'OPA donne à conftest un seul mainteneur propre, James Alseth (`@jalseth`, « Independent », renouvelé le 2026-09-30), plus deux mainteneurs de tous les dépôts, employés d'Apple. Sur un an, du 2025-11-23 au 2026-11-23, 157 commits, dont 51 humains, de 23 auteurs ; `jalseth` en signe 24 (47 %). Lecture : porté par l'organisation d'un projet de fondation, avec un seul mainteneur actif déclaré pour conftest.

Intégrité : la release publie `checksums.txt` et un SBOM par archive ; elle n'est pas immuable. L'API des attestations en donne une pour l'archive linux amd64 ; elle n'est pas vérifiée ici, faute d'archive téléchargée, et pourra l'être par [SECU]. Les sommes ci-dessous sont lues dans `checksums.txt` (asset 614476987, lu par l'API) ; elles sont égales au champ `digest` de l'API des releases.

| Archive | SHA-256 |
| --- | --- |
| `conftest_0.71.1_Linux_x86_64.tar.gz` | `c3f6b2a753bd56e377a1e51a95ae3e057f926f2e9139f7d5b5dfbbaf810f7985` |
| `conftest_0.71.1_Linux_arm64.tar.gz` | `218c682e110ae7e826dc14a746a6f9b43eb782643dbe730b771fd305634e3f47` |
| `conftest_0.71.1_Darwin_x86_64.tar.gz` | `a309853b5763c18486768157442d440248ee683b20a2aa1f6b28214e818bd780` |
| `conftest_0.71.1_Darwin_arm64.tar.gz` | `e1cc50d2590b6c5e3da6912666a71264bae82d60bdd62d7ae2b99971ccc8eedd` |

Fonctions relevées :

- plusieurs fichiers en une seule entrée : `conftest test --combine`. L'entrée devient une liste dont chaque élément porte `path`, « the relative file path of the file being evaluated », et `contents`, le document lu. S21 s'en sert pour comparer `platform.yaml` aux fichiers qui répètent ses valeurs ;
- Dockerfile : analyseur `dockerfile`, choisi d'office pour un fichier nommé `Dockerfile`, `Dockerfile.*` ou `*.Dockerfile` (`parser/parser.go` au tag), forçable par `--parser` ;
- fichier de données : `--data` (`-d`), qui cherche récursivement les fichiers JSON et YAML des chemins donnés et les expose sous `data.` ;
- tests Rego : `conftest verify --policy <dossier>` lance les règles `test_` ; `--namespace` ne garde que les résultats des paquets nommés, et le code de sortie est non nul si un test échoue ;
- syntaxe : `--rego-version` vaut `v1` par défaut, pour `test` comme pour `verify` (règles en `deny contains msg if`). conftest v0.71.1 embarque OPA v1.21.1 (`go.mod`) ; `regex.match`, `is_string`, `object.get`, `sprintf` et `count` existent depuis OPA v0.23.0 au plus tard ;
- parcours d'un document (lu le 2026-11-24 dans OPA v1.21.1) : `walk(x, [path, value])` rend chaque document imbriqué de `x`, avec `path`, la liste des clés et des indices qui y mènent, vide pour `x` lui-même. Une liste passée à `sprintf` par `%v` s'écrit `["packageRules", 4, "minimumReleaseAge"]`, chaînes entre guillemets. S23 s'en sert pour trouver une clé du délai à toute profondeur de `renovate.json` ;
- `conftest test` lit le paquet `main` par défaut, `--namespace` en choisit un autre, et sort en 1 quand une politique échoue ;
- piège : un nom de paquet qui n'existe pas ne lève aucune erreur, ni pour `test` ni pour `verify` (`runner/test.go` et `runner/verify.go` au tag), et le contrôle passe sans rien vérifier. Le lanceur des contrôles statiques (T004) refuse donc une politique dont le paquet ne porte pas le nom du fichier, ou qui n'a pas son fichier de tests dans le même paquet.

Effets : les politiques de `golden/saas-b2b/policy/` sont en Rego v1, un paquet par fichier, nommé comme lui, avec ses tests dans le même paquet ; `golden/saas-b2b/tests/tools/install.sh` et `SHA256SUMS` (T011) installent v0.71.1 par ces sommes.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://api.github.com/repos/open-policy-agent/conftest/releases> | 2026-11-23 | v0.71.1 publiée le 2026-10-06, dernière release, non immuable |
| <https://github.com/open-policy-agent/conftest/releases/download/v0.71.1/checksums.txt> | 2026-11-23 | Les quatre SHA-256 du tableau, lus par l'API (asset 614476987) |
| <https://github.com/open-policy-agent/conftest/blob/v0.71.1/LICENSE> | 2026-11-23 | Apache-2.0 |
| <https://api.github.com/repos/open-policy-agent/conftest/attestations/sha256:c3f6b2a753bd56e377a1e51a95ae3e057f926f2e9139f7d5b5dfbbaf810f7985> | 2026-11-23 | Une attestation, non vérifiée |
| <https://github.com/open-policy-agent/opa/blob/main/GOVERNANCE.md> | 2026-11-23 | Vote par organisation |
| <https://github.com/open-policy-agent/opa/blob/main/MAINTAINERS.md> | 2026-11-23 | Mainteneur de conftest, mainteneurs de tous les dépôts |
| <https://www.cncf.io/projects/open-policy-agent-opa/> | 2026-11-23 | OPA gradué, dates ; conftest non nommé |
| <https://api.github.com/repos/open-policy-agent/conftest/commits?since=2025-11-23T00:00:00Z> | 2026-11-23 | Commits de l'année par auteur |
| <https://www.conftest.dev/options/> | 2026-11-23 | `--combine`, `--data`, `--parser`, `--policy`, sorties, code de sortie |
| <https://github.com/open-policy-agent/conftest/blob/v0.71.1/docs/options.md> | 2026-11-23 | Clés `path` et `contents` de l'entrée combinée |
| <https://github.com/open-policy-agent/conftest/blob/v0.71.1/docs/index.md> | 2026-11-23 | `conftest verify`, tests en `test_` avec `with input as`, syntaxe v1 des exemples |
| <https://github.com/open-policy-agent/conftest/blob/v0.71.1/parser/parser.go> | 2026-11-23 | Détection des Dockerfile, analyseurs disponibles |
| <https://github.com/open-policy-agent/conftest/blob/v0.71.1/internal/commands/test.go> | 2026-11-23 | Options de `test`, `--rego-version` à `v1`, paquet `main` par défaut |
| <https://github.com/open-policy-agent/conftest/blob/v0.71.1/internal/commands/verify.go> | 2026-11-23 | Options de `verify`, sortie non nulle sur échec |
| <https://github.com/open-policy-agent/conftest/blob/v0.71.1/runner/verify.go> | 2026-11-23 | Filtre de `--namespace` sur le paquet des tests ; aucun paquet trouvé, aucune erreur |
| <https://github.com/open-policy-agent/conftest/blob/v0.71.1/runner/test.go> | 2026-11-23 | Paquet nommé lu tel quel, sans contrôle d'existence |
| <https://github.com/open-policy-agent/conftest/blob/v0.71.1/go.mod> | 2026-11-23 | OPA v1.21.1 |
| <https://www.openpolicyagent.org/docs/policy-reference/builtins> | 2026-11-23 | Signatures et version d'apparition des fonctions citées |
| <https://github.com/open-policy-agent/opa/blob/v1.21.1/v1/topdown/walk.go> | 2026-11-24 | Chemins rendus par `walk` : clés d'objet, indices de liste, chemin vide à la racine |
| <https://github.com/open-policy-agent/opa/blob/v1.21.1/v1/ast/builtins.go> | 2026-11-24 | Déclaration de `walk`, relation qui rend `[path, value]` |
| <https://github.com/open-policy-agent/opa/blob/v1.21.1/v1/topdown/strings.go> | 2026-11-24 | `sprintf` : une liste passée par `%v` s'écrit par sa forme texte |
| <https://github.com/open-policy-agent/opa/blob/v1.21.1/v1/ast/term_appenders.go> | 2026-11-24 | Forme texte d'une liste : entre crochets, éléments séparés par une virgule et une espace, chaînes entre guillemets |

### Relevé du 2026-11-24 : validateur de Renovate et réglages repris de CELIAN (T093)

Fait par [DEV], lecture le 2026-11-23 à 23 h 44 UTC, soit le 2026-11-24 à 00 h 44 à Paris. Sources : l'API GitHub des dépôts `renovatebot/renovate` et `renovatebot/pre-commit-hooks`, lue par `gh api`, leurs fichiers au tag retenu, et le registre npm.

Version retenue : Renovate 44.247.1, publiée le 2026-11-16 à 20 h 46 UTC, release immuable (`immutable: true`). C'est la plus récente qui avait 7 jours au moment de la lecture (principe VI) : les suivantes, de 44.247.2 (2026-11-17 à 03 h 53 UTC) à 44.258.3 (2026-11-23), ne passaient pas encore le délai. Licence AGPL-3.0 (`"license": "AGPL-3.0-only"` dans `package.json` au tag, et au registre npm). Node.js demandé : `^24.11.0 || ^26.13.0`. Le validateur est le programme `renovate-config-validator` du paquet (`dist/config-validator.js`). La date de publication du paquet sur npm n'a pas été lue ; le registre donne son intégrité, `sha512-DPiKrkkg2vElh2ro+/MVOninY9v0mSgDmTNAfEhB0Zv6y0/fHLs+tfojZe+0lo0In8YcvKcCM9ZVPs1QbhojSA==`.

Moyen retenu : le hook `renovate-config-validator` du dépôt `renovatebot/pre-commit-hooks`, licence MIT, au tag 44.247.1. Ce tag léger pointe sur le commit `7197a54c83a2e365f19561f0cb00dbd1e58018da`, écrit par `renovate[bot]` le 2026-11-16 à 21 h 16 UTC. Au tag, `.pre-commit-hooks.yaml` déclare `language: node`, `language_version: lts`, `additional_dependencies: [renovate@44.247.1]`, `entry: renovate-config-validator`, `files: '(^|/).?renovate(?:rc)?(?:\.json[c5]?)?$'` et `minimum_pre_commit_version: 3.6.0`. Chaque tag du hook embarque la version de Renovate du même numéro : monter son `rev` monte le validateur, sous le même délai.

Comportement lu dans `lib/config-validator.ts` et `lib/config/validation.ts` au tag :

- un fichier passé en argument est validé comme configuration globale d'un Renovate auto-hébergé, sauf avec `--no-global`. pre-commit passe les noms de fichiers : le hook prend donc `--no-global` ;
- une erreur ou un avertissement fait sortir en 1 ; `--strict` fait échouer en plus une configuration qui demande une migration ;
- hors ligne : le validateur ne télécharge pas les presets du `extends` de premier niveau, il en vérifie la syntaxe (`parsePreset`). Il résout en revanche un `extends` placé dans une entrée de `packageRules` (`resolveConfigPresets`) ; la configuration du golden repo n'en a aucun. Une fois installé, il valide donc sans réseau. Son installation demande le réseau : pre-commit télécharge Node.js LTS et le paquet `renovate` depuis npm.

Où il tourne : dans `golden/saas-b2b/.pre-commit-config.yaml`, avec `--strict --no-global`, au stade `manual` depuis la relecture [SECU] de la PR #46. pre-commit installe un hook Node par `npm install -g`, sans `--ignore-scripts` (`pre_commit/languages/node.py`, v4.7.0), et le hook ne fige que `renovate@44.247.1`. Au tag, le dépôt de Renovate n'a pas de `npm-shrinkwrap.json` et son `package.json` ne publie que `dist` et `renovate-schema.json` : les dépendances transitives se résolvent par plages, sans verrou ni délai de 7 jours. Le contenu du paquet publié n'a pas été lu. Le hook ne tourne donc pas sur un poste de développement : pre-commit n'installe que les environnements des hooks du stade lancé (`pre_commit/commands/run.py`), et aucun hook Git n'appelle le stade `manual` (`pre_commit/clientlib.py`). Reste une porte : `pre-commit install-hooks`, ou `pre-commit install --install-hooks`, installe tous les hooks, celui-ci compris (`pre_commit/commands/install_uninstall.py`). Il tourne par `pre-commit run --hook-stage manual renovate-config-validator --all-files`, dans X01 sur la copie autonome, et dans le workflow `ci.yml` du projet généré. Il reste hors de `task check`, qui ne demande ni Node.js ni Python sur le poste (RS-06), et hors des hooks de CELIAN, qui ne lit pas ce fichier (RS-17). Les règles propres au projet généré relèvent de S23, une politique Rego lancée par conftest dans `task check`.

Options de Renovate lues pour `renovate.json` (T098), dans `docs/usage/` et `lib/` au tag 44.247.1 :

- `minimumReleaseAge` : l'attente se compte pour chaque version ; tant qu'elle court, la branche porte le contrôle en attente `renovate/stability-days`. Sans date de publication, `minimumReleaseAgeBehaviour`, à `timestamp-required` par défaut, retient la mise à jour ;
- `internalChecksFilter`, à `strict` par défaut, saute la PR tant qu'aucune version n'a fini son délai. À `none`, Renovate prend la version la plus haute même en attente ; à `flexible`, il ouvre une PR sur la plus haute version en attente quand toutes le sont. `minimumReleaseAge`, `minimumReleaseAgeBehaviour` et `internalChecksFilter` se lisent en tête, dans une entrée de `packageRules`, dans la configuration d'un gestionnaire, dans `vulnerabilityAlerts` et dans l'objet d'un type de mise à jour comme `digest` (`lib/config/options/scopes.ts`). Depuis la relecture [SECU] de la PR #46, `renovate.json` écrit les deux défauts en tête, et S23 refuse ces trois clés partout ailleurs, sauf `vulnerabilityAlerts.minimumReleaseAge`. S23 exige aussi que `extends` porte exactement les trois presets de CELIAN. Renovate lit `extends` partout (portée `any`) : S23 le refuse ailleurs qu'en tête ;
- source `docker` : la date de publication n'existe que pour Docker Hub (champ `tag_last_pushed`), et un condensat reçoit la date de son tag. Une image de `ghcr.io` ou de `mcr.microsoft.com` n'a pas de date : avec le délai et ce réglage par défaut, Renovate ne la propose jamais, hors correctif de sécurité. Sont touchées l'image de gitleaks, celle de zot (ADR-011, condition 8) et les images .NET de l'étape 3. Les sources `github-tags`, `github-digest`, `pypi` et `npm` ont leur date ;
- exception de sécurité : une mise à jour de sécurité attend le `minimumReleaseAge` de `vulnerabilityAlerts`, « null by default » (`key-concepts/minimum-release-age.md`), et le défaut de `vulnerabilityAlerts` le fixe à `null` (`lib/config/options/index.ts`). Les alertes de GitHub demandent le graphe de dépendances et les alertes Dependabot actifs dans les réglages du dépôt. `osvVulnerabilityAlerts` lit osv.dev pour les dépendances directes des sources `crate`, `go`, `hackage`, `hex`, `maven`, `npm`, `nuget`, `packagist`, `pypi` et `rubygems`, donc ni les images ni les actions ;
- `packageRules.allowedVersions` borne les versions proposées ; une expression régulière s'écrit entre deux `/`, et l'option ne se combine pas avec `matchUpdateTypes` dans une même règle ;
- `packageRules.matchPackageNames` accepte un nom exact, un motif glob insensible à la casse, ou une expression régulière re2 entre `/` (`string-pattern-matching.md`) ;
- `groupName` : les mises à jour d'un même groupe partagent une branche et une PR. `groupSingleUpdates` vaut `false` : un groupe qui ne reçoit qu'une mise à jour n'applique pas ses réglages. Renovate réunit donc les deux membres d'une paire quand les deux montent, mais ne refuse pas une PR qui n'en porte qu'un ;
- gestionnaires : `kubernetes` n'a aucun motif de fichier par défaut, et ne lit qu'un fichier qui contient `apiVersion:` et `kind:`. `pre-commit` est coupé par défaut, son motif est `(^|/)\.pre-commit-config\.ya?ml$`, et il garde le format `# frozen:`. `github-actions` et le preset `customManagers:githubActionsVersions`, qui suit les variables `_VERSION` précédées d'un commentaire `# renovate:`, lisent `(^|/)(workflow-templates|\.(?:github|gitea|forgejo)/(?:workflows|actions))/.+\.ya?ml$`. `dockerfile` lit `(^|/|\.)([Dd]ocker|[Cc]ontainer)file$` et `(^|/)([Dd]ocker|[Cc]ontainer)file[^/]*$` ;
- `config:recommended` étend `:ignoreModulesAndTests`, qui ignore entre autres `**/vendor/**` et `**/tests/**`.

Réglages repris de CELIAN, relevés dans `.pre-commit-config.yaml`, `.commitlintrc.yaml`, `renovate.json`, `release-please-config.json`, `.release-please-manifest.json` et `.github/workflows/`. Chaque SHA a été comparé au commit de son tag par `gh api` le 2026-11-24 : tous concordent.

| Élément | Tag | SHA figé |
| --- | --- | --- |
| `pre-commit/pre-commit-hooks` | v6.0.0 | `3e8a8703264a2f4a69428a0aa4dcb512790b2c8c` |
| `gitleaks/gitleaks` | v8.30.1 | `83d9cd684c87d95d656c1458ef04895a7f1cbd8e` |
| `DavidAnson/markdownlint-cli2` | v0.24.1 | `c01a1853c19b175aee6a09f24e2ad9b748c485ad` |
| `rhysd/actionlint` | v1.7.12 | `914e7df21a07ef503a81201c76d2b11c789d3fca` |
| `shellcheck-py/shellcheck-py` | v0.11.0.1 | `745eface02aef23e168a8afb6b5737818efbea95` |
| `alessandrojcm/commitlint-pre-commit-hook` | v9.27.0 | `1f1ac45c93d1c2ce36b71330252c489a5f4f2724` |
| `renovatebot/pre-commit-hooks` (nouveau) | 44.247.1 | `7197a54c83a2e365f19561f0cb00dbd1e58018da` |
| `actions/checkout` | v7.0.1 | `3d3c42e5aac5ba805825da76410c181273ba90b1` |
| `astral-sh/setup-uv` | v10.3.3 | `68559e99cc807c1eb7e9238fd43a15bba460eec2` |
| `actions/cache` | v6.1.0 | `55cc8345863c7cc4c66a329aec7e433d2d1c52a9` |
| `googleapis/release-please-action` | v5.0.0 | `45996ed1f6d02564a971a2fa1b5860e934307cf7` |

Repris tels quels : les hooks de `pre-commit-hooks` et leurs arguments, gitleaks, markdownlint-cli2 et sa configuration, actionlint, shellcheck, commitlint avec `@commitlint/config-conventional@21.2.4`, `no-em-dash` ; `default_install_hook_types: [pre-commit, commit-msg]` ; `PRE_COMMIT_VERSION` 4.7.0 et `UV_PYTHON` 3.12 ; l'image `ghcr.io/gitleaks/gitleaks:v8.30.1` par condensat ; les réglages de `renovate.json` (presets, 7 jours, exception de sécurité, gestionnaire pre-commit, variables `_IMAGE`) ; release-please en `simple`, `bump-minor-pre-major`, sans composant dans le tag, version initiale 0.1.0. Adaptés : `check-yaml` accepte partout plusieurs documents, comme CELIAN le fait pour `golden/` (RS-17, point 4), et actionlint garde son motif amont, puisque les workflows sont à la racine de la copie. Écartés : les hooks du catalogue et le workflow `catalog-freshness`, propres au générateur.

CODEOWNERS et modèle de PR : GitHub ne lit le premier que dans `.github/`, à la racine ou dans `docs/` du dépôt, et le second qu'aux mêmes endroits. Ceux de `golden/saas-b2b/.github/` restent sans effet dans CELIAN, comme ses workflows (RS-17, point 1).

Pour X01 : `pre-commit install` pose les types de hooks de `default_install_hook_types` quand `--hook-type` manque, et pre-commit télécharge Node.js si le poste n'en a pas. Le job `export` installe pre-commit par `uv tool install pre-commit==<version>`. uv place les exécutables dans un dossier qui doit être dans le `PATH` ; `UV_TOOL_BIN_DIR` (depuis uv 0.3.0) le fixe, et setup-uv ne l'ajoute au `PATH` que sous Windows : le job l'ajoute lui-même.

Effets : `golden/saas-b2b/.pre-commit-config.yaml` (T097), `golden/saas-b2b/renovate.json` (T098), la politique de S23 (T095).

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://api.github.com/repos/renovatebot/renovate/releases> | 2026-11-24 | 44.247.1 publiée le 2026-11-16 à 20 h 46 UTC, immuable ; versions suivantes de moins de 7 jours |
| <https://github.com/renovatebot/renovate/blob/44.247.1/package.json> | 2026-11-24 | `AGPL-3.0-only`, `engines`, programme `renovate-config-validator` ; `files` limité à `dist` et `renovate-schema.json` |
| <https://github.com/renovatebot/renovate/tree/44.247.1> | 2026-11-24 | Aucun `npm-shrinkwrap.json` à la racine du dépôt au tag |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config-validator.ts> | 2026-11-24 | `--no-global`, `--strict`, code de sortie |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/validation.ts> | 2026-11-24 | `extends` de premier niveau vérifié par `parsePreset`, presets des `packageRules` résolus |
| <https://registry.npmjs.org/renovate/44.247.1> | 2026-11-24 | Licence, `engines`, intégrité du paquet |
| <https://api.github.com/repos/renovatebot/pre-commit-hooks> | 2026-11-24 | Licence MIT, dépôt non archivé |
| <https://github.com/renovatebot/pre-commit-hooks/blob/7197a54c83a2e365f19561f0cb00dbd1e58018da/.pre-commit-hooks.yaml> | 2026-11-24 | Définition du hook ; tag 44.247.1 égal à ce SHA |
| <https://github.com/renovatebot/pre-commit-hooks/blob/7197a54c83a2e365f19561f0cb00dbd1e58018da/README.md> | 2026-11-24 | Usage, mode `--strict` |
| <https://docs.renovatebot.com/config-validation/> | 2026-11-24 | Commande, fichiers lus par défaut, `--strict`, `--no-global` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/docs/usage/configuration-options.md> | 2026-11-24 | `minimumReleaseAge`, `minimumReleaseAgeBehaviour`, `internalChecksFilter`, `vulnerabilityAlerts`, `osvVulnerabilityAlerts`, `allowedVersions`, `matchPackageNames`, `groupName`, `groupSingleUpdates` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/docs/usage/key-concepts/minimum-release-age.md> | 2026-11-24 | Attente d'une mise à jour de sécurité ; date fournie par la source |
| <https://github.com/renovatebot/renovate/blob/44.247.1/docs/usage/string-pattern-matching.md> | 2026-11-24 | Expressions régulières entre `/`, syntaxe re2, glob insensible à la casse |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/options/index.ts> | 2026-11-24 | Défauts de `vulnerabilityAlerts`, `minimumReleaseAgeBehaviour`, `internalChecksFilter` et `groupSingleUpdates` ; portées des clés du délai et de `extends` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/options/scopes.ts> | 2026-11-24 | Objets que couvre chaque portée : tête, `packageRules`, gestionnaires, `vulnerabilityAlerts`, types de mise à jour |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/modules/datasource/docker/index.ts> | 2026-11-24 | Date de publication sur Docker Hub seulement |
| <https://github.com/renovatebot/renovate/tree/44.247.1/lib/modules/manager> | 2026-11-24 | Motifs par défaut de `kubernetes`, `pre-commit`, `github-actions`, `dockerfile` ; lecture des fichiers Kubernetes ; format `# frozen:` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/presets/internal/custom-managers.preset.ts> | 2026-11-24 | Motif et expression du preset `githubActionsVersions` |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/presets/internal/default.preset.ts> | 2026-11-24 | Chemins ignorés par `:ignoreModulesAndTests` |
| <https://github.com/DavidAnson/markdownlint-cli2/blob/c01a1853c19b175aee6a09f24e2ad9b748c485ad/README.md> | 2026-11-24 | Un fichier `.markdownlint-cli2.yaml` dans un sous-dossier l'emporte sur celui de la racine |
| <https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners> | 2026-11-24 | CODEOWNERS lu dans `.github/`, à la racine ou dans `docs/`, le premier trouvé |
| <https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/creating-a-pull-request-template-for-your-repository> | 2026-11-24 | Modèle de PR lu à la racine, dans `docs/` ou dans `.github/` |
| <https://pre-commit.com/> | 2026-11-24 | `default_install_hook_types` lu par `pre-commit install` ; options `--hook-stage`, `--all-files`, `--files` ; Node.js téléchargé s'il manque |
| <https://github.com/pre-commit/pre-commit/blob/v4.7.0/pre_commit/commands/run.py> | 2026-11-24 | Environnements installés pour les seuls hooks du stade lancé |
| <https://github.com/pre-commit/pre-commit/blob/v4.7.0/pre_commit/clientlib.py> | 2026-11-24 | Stade `manual`, appelé par aucun hook Git |
| <https://github.com/pre-commit/pre-commit/blob/v4.7.0/pre_commit/commands/install_uninstall.py> | 2026-11-24 | `install-hooks` et `install --install-hooks` installent tous les hooks |
| <https://github.com/pre-commit/pre-commit/blob/v4.7.0/pre_commit/languages/node.py> | 2026-11-24 | Hook Node installé par `npm install -g`, sans `--ignore-scripts` |
| <https://docs.astral.sh/uv/concepts/tools/> | 2026-11-24 | `uv tool install ruff==0.5.0` ; dossier des exécutables à mettre dans le `PATH` |
| <https://docs.astral.sh/uv/reference/environment/> | 2026-11-24 | `UV_TOOL_BIN_DIR`, depuis uv 0.3.0 |
| <https://github.com/astral-sh/setup-uv/blob/68559e99cc807c1eb7e9238fd43a15bba460eec2/docs/environment-and-tools.md> | 2026-11-24 | Dossier des outils ajouté au `PATH` sous Windows seulement ; tag v10.3.3 égal à ce SHA |

### Relevé du 2026-11-25 : kind et kubectl de la CI (T040, étape 6)

Fait par [OPS]. API GitHub des dépôts `kubernetes/kubernetes` et `kubernetes-sigs/kind`, lue par `gh api`, et fichiers de sommes de `dl.k8s.io`.

kubectl : v1.36.6, publiée le 2026-10-28 (28 jours, principe VI), dernière correction de la mineure 1.36 de `platform.yaml`, donc dans la plage 1.35 à 1.37 des contrôles préalables. SHA-256 du binaire linux/amd64, lu dans `kubectl.sha256` de la release : `29818b6729dc9262b692307470d0558d027725e738be5dd47c760261868a2634`, relu deux fois. Le job `e2e-lite` le télécharge de `dl.k8s.io` et le vérifie avant usage. Sa version vit dans le workflow sous `KUBECTL_VERSION`, avec le commentaire `# renovate: datasource=github-releases depName=kubernetes/kubernetes` que lit le preset `customManagers:githubActionsVersions` (motif `[A-Za-z0-9_]+?_VERSION\s*:`, Renovate 44.247.1) ; aucun gestionnaire ne met à jour `KUBECTL_SHA256`, et la PR de Renovate échoue en CI tant que la somme n'est pas écrite à la main, comme pour `tests/tools/SHA256SUMS`. Une version hors de la plage fait échouer les contrôles préalables du job.

kind : 0.33.0 reste la dernière release (2026-08-26), et la release donne toujours `kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed`. Le job prend la version et le SHA-256 linux-amd64 dans `catalog/kubernetes-cluster.yaml` (ADR-004, condition 5), par `scripts/ci/install-kind-kubectl.sh`. Une PR de Renovate qui monte `KIND_VERSION` dans `local/scripts/lib/preflight-checks.sh` échoue donc en CI tant que le catalogue ne porte pas la nouvelle version et ses sommes.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://api.github.com/repos/kubernetes/kubernetes/releases> | 2026-11-25 | v1.36.6, v1.37.2 et v1.35.10 publiées le 2026-10-28 |
| <https://dl.k8s.io/release/v1.36.6/bin/linux/amd64/kubectl.sha256> | 2026-11-25 | SHA-256 du binaire linux/amd64 |
| <https://api.github.com/repos/kubernetes-sigs/kind/releases> | 2026-11-25 | v0.33.0 dernière release, du 2026-08-26 ; image de nœud v1.36.4 et son condensat |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/config/presets/internal/custom-managers.preset.ts> | 2026-11-25 | Lignes 63 à 78 : `githubActionsVersions`, motif des variables `_VERSION` des workflows |

### Relevé du 2026-11-24 : paquets NuGet et images de l'API (T015)

Fait par [DEV] le 2026-11-24. Sources : l'API d'enregistrement de nuget.org, les pages des paquets, l'API GitHub lue par `gh api`, l'API de catalogue de mcr.microsoft.com et la documentation de NuGet, de xUnit.net, de .NET et de Docker. Les choix d'usage (format des erreurs, OpenAPI, Npgsql) sont au point RS-03.

Paquets retenus, en référence directe. L'âge se compte au 2026-11-24 depuis le champ `published` de nuget.org.

| Paquet | Version | Publiée le (UTC) | Licence | Projet | Pourquoi |
| --- | --- | --- | --- | --- | --- |
| `Npgsql` | 10.0.3 | 2026-05-27 11:33 | PostgreSQL | API | Accès à la base, sans ORM (RS-03) |
| `xunit.v3.mtp-v2` | 4.0.3 | 2026-11-09 00:41 | Apache-2.0, « Copyright (C) .NET Foundation » | tests | Framework de test, sur Microsoft Testing Platform v2 |
| `Microsoft.AspNetCore.Mvc.Testing` | 10.0.15 | 2026-11-10 13:08 | MIT | tests | `WebApplicationFactory`, l'API en mémoire |
| `Microsoft.AspNetCore.OpenApi` | 10.0.15 | 2026-11-10 13:08 | MIT | tests | Génération du document OpenAPI, dans les tests seulement (RS-03) |

Npgsql : 11.0.0 et 10.0.4 sont sorties le 2026-11-20, à 4 jours de la lecture, sous le délai de 7 jours. Aucune ne corrige un avis publié : le seul avis du dépôt, GHSA-x9vc-6hfv-hg8c (CVE-2024-32655), date du 2024-05-09 et vise des versions antérieures à 8.0.3, et le jalon de 10.0.4 ne liste que des corrections de bogues. 11.0.0 dépend en plus des bibliothèques `Microsoft.Extensions.*` 11.0.0. 10.0.3 est retenue ; dépôt `npgsql/npgsql`, licence PostgreSQL, non archivé.

xUnit.net v3 : la page de démarrage n'utilise plus que `xunit.v3.mtp-v2`, un projet de tests est un exécutable, et `dotnet run` lance les tests. Le paquet `xunit.v3` 4.0.3 ne fait que dépendre de `xunit.v3.mtp-v2` 4.0.3. Ni `xunit.runner.visualstudio` ni `Microsoft.NET.Test.Sdk`, qui ne servent qu'avec VSTest. Le projet de tests prend le SDK `Microsoft.NET.Sdk.Web`, comme le demande la page des tests d'intégration.

Paquets transitifs du verrou, tous publiés depuis plus de 7 jours : `xunit.v3.assert`, `xunit.v3.common`, `xunit.v3.core.mtp-v2`, `xunit.v3.extensibility.core`, `xunit.v3.runner.common` et `xunit.v3.runner.inproc.console` 4.0.3 (2026-11-09) ; `xunit.analyzers` 2.3.0 (2026-11-09) ; `Microsoft.AspNetCore.TestHost` et `Microsoft.Extensions.DependencyModel` 10.0.15 (2026-11-10) ; `Microsoft.Testing.Platform`, `Microsoft.Testing.Platform.MSBuild`, `Microsoft.Testing.Extensions.Telemetry` et `Microsoft.Testing.Extensions.TrxReport.Abstractions` 2.5.2 (2026-10-27) ; `Microsoft.OpenApi` 2.13.0 (2026-10-19) ; `Microsoft.ApplicationInsights` 2.23.0 (2025-02-19) ; `System.Security.AccessControl` 6.0.1 (2024-04-09) ; `Microsoft.Bcl.AsyncInterfaces` 6.0.0 (2021-11-08) ; `Microsoft.Win32.Registry` 5.0.0 (2020-11-09). NuGet prend pour une dépendance transitive la plus basse version admise par sa contrainte (« lowest applicable version ») : `Microsoft.AspNetCore.OpenApi` 10.0.15 demande `Microsoft.OpenApi` dans `[2.13.0, 3.0.0)` et reçoit 2.13.0. Le SDK .NET 10 élague par défaut, pour `net10.0`, les paquets déjà fournis par le framework partagé (`PrunePackageReference`) : `Microsoft.Extensions.Hosting`, que demande `Microsoft.AspNetCore.Mvc.Testing`, n'apparaît pas dans le verrou.

Télémétrie : `Microsoft.Testing.Extensions.Telemetry` envoie par défaut des données d'usage à Microsoft, comme les commandes du SDK. `TESTINGPLATFORM_TELEMETRY_OPTOUT` ou `DOTNET_CLI_TELEMETRY_OPTOUT` à `1` coupe la première, `DOTNET_CLI_TELEMETRY_OPTOUT` à `1` ou `true` la seconde : l'image de construction pose `DOTNET_CLI_TELEMETRY_OPTOUT=1`.

Verrouillage : `RestorePackagesWithLockFile` à `true` fait écrire `packages.lock.json` à la racine de chaque projet, avec tout le graphe des paquets. `dotnet restore --locked-mode` restaure exactement ce graphe, ou échoue si les références ont changé depuis le verrou. La page conseille de versionner le verrou d'une application. L'image de construction restaure en mode verrouillé ; `tests/unit/u01-api.sh --update-locks` réécrit les verrous dans l'image, sans SDK sur le poste. `nuget.config` vide les sources héritées par `<clear />` et ne garde que `https://api.nuget.org/v3/index.json`. Le réglage `minPublishAgeHours`, qui appliquerait le délai à la restauration, demande NuGet 8.0 et le SDK .NET 11.0.100 : hors de portée du SDK 10.0.404.

Renovate de CELIAN : le gestionnaire `nuget` lit par défaut `\.(?:cs|fs|vb|sql)proj$`, `\.(?:props|targets)$`, `dotnet-tools.json` et `global.json`, et confie l'entretien de `packages.lock.json` à l'outil du gestionnaire. Les `.csproj` du golden repo montent donc par des PR de CELIAN, et nuget.org donne la date de chaque version au délai de 7 jours.

.NET : la dernière version de la branche 10.0 est 10.0.15, sortie le 2026-11-10, marquée `security: true`, avec le SDK 10.0.404 (`releases.json` de `dotnet/core`). Aucune version plus récente à la lecture.

Images de base. Règle de l'ADR-016 décidée par Lucas le 2026-11-24 : condensat de 7 jours au moins, daté par l'API de catalogue de mcr.microsoft.com, ou correctif d'un avis publié. L'API de catalogue ne donne que le condensat courant de chaque tag, avec la date de création du tag et celle de son dernier déplacement. Les deux tags ont bougé le 2026-11-23 :

| Tag | Condensat courant | `createdDate` du tag | `lastModifiedDate` |
| --- | --- | --- | --- |
| `dotnet/sdk:10.0.404` | `sha256:8c6edfb26c85153f236d26efebd9ad349aec403583f343f201ee67838b23658d` | 2026-11-10 18:46:19 | 2026-11-23 17:17:22 |
| `dotnet/aspnet:10.0.15` | `sha256:aac50ceef10391e78a899e3d2ccd00bbafa2dcb56ccf4586cbccf00edb84fc21` | 2026-11-10 18:43:57 | 2026-11-23 17:16:00 |

Le catalogue ne date donc plus les condensats de BENCH-005. L'historique de `build-info/docker/image-info.dotnet-dotnet-docker-main.json`, dans le dépôt `dotnet/versions` où Microsoft consigne chaque publication, donne leur entrée et leur sortie. Les images 10.0.404 et 10.0.15 ont connu trois condensats :

| Construction | `dotnet/sdk:10.0.404` | `dotnet/aspnet:10.0.15` | Inscrite dans `dotnet/versions` | 7 jours atteints le |
| --- | --- | --- | --- | --- |
| initiale | `sha256:fe0fd4e93bd2fbb47c883b7a6369e5c8d3db8bf01cdc5981f6ee35fbdf3ff4fb` | `sha256:bfd912c83295ce66d4b706ebb8541b9f14259b0e76fbb88b2751f58ce2399d2e` | 2026-11-10 20:12 (`7c46f54d`) | 2026-11-17 |
| BENCH-005 | `sha256:bef136a371963aaa46ec97882845ef6f54dec15728bb4b128b1c2a400ffbc9b4` | `sha256:12b1135f5f8b3c0a214f2a680ff2033dff4f684f445d6c697d9524ceeb303586` | 2026-11-18 17:45 (`55dceb8f`) | 2026-11-25 à 17 h 45 |
| courante | `sha256:8c6edfb26c85153f236d26efebd9ad349aec403583f343f201ee67838b23658d` | `sha256:aac50ceef10391e78a899e3d2ccd00bbafa2dcb56ccf4586cbccf00edb84fc21` | 2026-11-23 17:19 (`782fa161`) | 2026-11-30 à 17 h 17 |

Les trois constructions portent la même version de .NET. Entre elles change l'image de base Ubuntu `noble` de `runtime-deps` (`baseImageDigest`) : ce sont des reconstructions sur une base renouvelée. Aucun avis de sécurité qui les motive n'a été relevé, et les notices d'Ubuntu n'ont pas été lues.

Retenus pour `src/Api/Dockerfile`, comme le demande T025 : les condensats de BENCH-005, ligne « BENCH-005 » du tableau, sous les tags `sdk:10.0.404` et `aspnet:10.0.15`. Ils atteignent 7 jours le 2026-11-25 à 17 h 45 UTC, d'après `dotnet/versions` : la PR ne fusionne pas avant. Une reconstruction plus récente existe, celle du 2026-11-23 ; si [SECU] y trouve le correctif d'un avis publié, elle passe sans le délai, sinon elle se reprend à partir du 2026-11-30. Les condensats de la construction initiale passent le délai mais ont deux renouvellements de base de retard.

Décision du DSI (2026-11-24) : l'historique de `dotnet/versions` est admis comme source de la date d'un condensat de mcr.microsoft.com que l'API de catalogue ne montre plus. C'est le dépôt où Microsoft consigne chaque publication de ses images, et le commit qui fait entrer un condensat le date à la minute. L'API de catalogue reste la source pour le condensat courant d'un tag, celui que Renovate propose sous l'ADR-016.

Faits relevés sur les images : `runtime-deps` 10.0 `noble` pose `APP_UID=1654` et `ASPNETCORE_HTTP_PORTS=8080`, et crée l'utilisateur de cet UID (Dockerfile au commit `ebca79f4`, celui de la construction du 2026-11-18) : `USER $APP_UID` donne un UID numérique au profil `restricted`, et Kestrel écoute sur un port non privilégié. `docker build` est un alias de `docker buildx build` ; `--output type=local,dest=<dossier>` copie le système de fichiers de l'étape visée, et une étape `FROM scratch` qui ne copie qu'un fichier n'exporte que lui ; l'exporteur `cacheonly` construit sans rien garder que le cache ; `--progress plain` affiche la sortie des commandes.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://www.nuget.org/packages/Npgsql> | 2026-11-24 | Versions et dates, licence PostgreSQL, dépendances de 11.0.0 |
| <https://api.nuget.org/v3/registration5-semver1/npgsql/10.0.3.json> | 2026-11-24 | `published` de 10.0.3 |
| <https://api.github.com/repos/npgsql/npgsql/releases> | 2026-11-24 | Dates des releases 10.0.3, 10.0.4 et 11.0.0 |
| <https://api.github.com/repos/npgsql/npgsql/security-advisories> | 2026-11-24 | Seul avis : GHSA-x9vc-6hfv-hg8c, 2024 |
| <https://api.github.com/repos/npgsql/npgsql/issues?milestone=139&state=closed> | 2026-11-24 | Contenu de 10.0.4 : corrections de bogues |
| <https://www.nuget.org/packages/xunit.v3> | 2026-11-24 | Versions, licence Apache-2.0, copyright .NET Foundation, dépendance vers `xunit.v3.mtp-v2` |
| <https://xunit.net/docs/getting-started/v3/getting-started> | 2026-11-24 | Paquet, projet exécutable, `dotnet run` |
| <https://xunit.net/releases/v3/4.0.3> | 2026-11-24 | Release du 2026-11-08, sans correctif de sécurité |
| <https://api.nuget.org/v3/registration5-semver1/xunit.v3.mtp-v2/4.0.3.json> | 2026-11-24 | `published` ; idem pour chaque paquet transitif cité, à son adresse `registration5-semver1/<id>/<version>.json` |
| <https://api.nuget.org/v3/catalog0/data/2026.11.10.13.59.41/microsoft.aspnetcore.mvc.testing.10.0.15.json> | 2026-11-24 | Licence MIT, dépendances |
| <https://api.nuget.org/v3/catalog0/data/2026.11.10.13.40.01/microsoft.aspnetcore.openapi.10.0.15.json> | 2026-11-24 | Licence MIT, `Microsoft.OpenApi` dans `[2.13.0, 3.0.0)` |
| <https://learn.microsoft.com/en-us/nuget/consume-packages/package-references-in-project-files> | 2026-11-24 | Verrou, mode verrouillé, `PrunePackageReference` |
| <https://learn.microsoft.com/en-us/nuget/concepts/dependency-resolution> | 2026-11-24 | « Lowest applicable version » |
| <https://learn.microsoft.com/en-us/nuget/reference/nuget-config-file> | 2026-11-24 | `<clear />`, adresse de nuget.org, `minPublishAgeHours` réservé à NuGet 8.0 |
| <https://docs.renovatebot.com/modules/manager/nuget/> | 2026-11-24 | Motifs par défaut, entretien de `packages.lock.json` |
| <https://learn.microsoft.com/en-us/dotnet/core/testing/microsoft-testing-platform-telemetry> | 2026-11-24 | Télémétrie de MTP et variables qui la coupent |
| <https://learn.microsoft.com/en-us/dotnet/core/tools/telemetry> | 2026-11-24 | Télémétrie du SDK, `DOTNET_CLI_TELEMETRY_OPTOUT` |
| <https://github.com/dotnet/core/blob/main/release-notes/10.0/releases.json> | 2026-11-24 | 10.0.15 du 2026-11-10, `security: true`, SDK 10.0.404 |
| <https://mcr.microsoft.com/api/v1/catalog/dotnet/sdk/tags?reg=mar> | 2026-11-24 | Tag `10.0.404` : `digest`, `createdDate`, `lastModifiedDate` |
| <https://mcr.microsoft.com/api/v1/catalog/dotnet/aspnet/tags?reg=mar> | 2026-11-24 | Tag `10.0.15` : `digest`, `createdDate`, `lastModifiedDate` |
| <https://github.com/dotnet/versions/commits/main/build-info/docker/image-info.dotnet-dotnet-docker-main.json> | 2026-11-24 | Commits `7c46f54d`, `55dceb8f` et `782fa161` ; condensats et `baseImageDigest` à chacun |
| <https://github.com/dotnet/dotnet-docker/blob/ebca79f4aa976b9bce41672fce41e884e4fa1b8c/src/runtime-deps/10.0/noble/amd64/Dockerfile> | 2026-11-24 | `APP_UID=1654`, `ASPNETCORE_HTTP_PORTS=8080`, création de l'utilisateur |
| <https://docs.docker.com/reference/cli/docker/buildx/build/> | 2026-11-24 | Alias `docker build`, `--file`, `--target`, `--output`, `--progress` |
| <https://docs.docker.com/build/exporters/> | 2026-11-24 | Exporteurs `local` et `cacheonly` |
| <https://docs.docker.com/build/exporters/local-tar/> | 2026-11-24 | `type=local,dest=`, étape `FROM scratch` qui n'exporte que ce qu'elle copie |

### Relevé du 2026-11-24 : paquets npm et images du front (T027)

Fait par [DEV] le 2026-11-24. Sources : le calendrier et les releases de Node.js, le registre npm, la base d'avis de GitHub, l'API de Docker Hub, les pages de nginx.org et la documentation de Renovate. Les choix d'usage sont au point RS-05.

Node.js. La ligne 26 (« Lithium ») est passée en LTS active le 2026-10-28, en maintenance le 2027-10-20, fin de vie le 2029-04-30 ; la 24 est en maintenance depuis le 2026-10-20. 26.13.1, sortie le 2026-11-11, est une release de sécurité (sept CVE notées « High », dans `http2` et `tls`) et embarque npm 11.20.0. Retenue : la LTS active, dans sa dernière version.

Paquets retenus, en version exacte dans `package.json`. La date vient du champ `time` du registre npm, lu le 2026-11-24 par `npm view <paquet> time --json`, lancé dans l'image Node par `docker build` : Node.js n'est pas sur le poste (RS-06).

| Paquet | Version | Publiée le (UTC) | Licence | Rôle |
| --- | --- | --- | --- | --- |
| `react` | 19.3.1 | 2026-10-14 16:47 | MIT | exécution |
| `react-dom` | 19.3.1 | 2026-10-14 16:49 | MIT | exécution |
| `vite` | 8.3.8 | 2026-11-11 02:49 | MIT | construction |
| `typescript` | 7.0.2 | 2026-07-08 15:55 | Apache-2.0 | vérification des types |
| `@types/react` | 19.3.0 | 2026-09-09 18:08 | MIT | types de React |
| `@types/react-dom` | 19.3.0 | 2026-09-09 18:07 | MIT | types de React DOM |
| `vitest` | 5.1.0 | 2026-11-02 16:12 | MIT | tests |
| `jsdom` | 31.0.1 | 2026-11-13 06:36 | MIT | tests, DOM simulé |
| `@testing-library/react` | 16.3.3 | 2026-08-27 17:41 | MIT | tests |
| `@testing-library/dom` | 10.4.2 | 2026-09-13 18:08 | MIT | tests, pair de la précédente |

Écartées sous le délai : `@types/react` 19.3.1, publiée le 2026-11-24 à 19:05, et `vitest` 5.1.1, publiée le 2026-11-18 à 07:35. La base d'avis de GitHub, interrogée par `affects=<paquet>@<version>` pour les dix versions retenues, ne renvoie aucun avis ; les avis de Vitest visent des versions antérieures à 4.1.11 et les préversions de 5.0.0. `@vitejs/plugin-react` n'entre pas (RS-05). Compatibilités lues sur les métadonnées : `vitest` 5.1.0 demande `vite` `^6.4.0 || ^7.0.0 || ^8.0.0` et Node.js `^22.12.0 || ^24.0.0 || >=26.0.0` ; `jsdom` 31.0.1 demande Node.js `^22.22.2 || ^24.15.0 || >=26.0.0` ; `@testing-library/react` 16.3.3 demande React 18 ou 19 et `@testing-library/dom` 10.

Verrou. `package-lock.json` (format 3) compte 137 paquets, binaires de toutes les plates-formes compris ; `npm ci` en installe 86 sous Linux arm64 musl. Il a été résolu le 2026-11-24 vers 21:05 UTC avec `--min-release-age=7`. La date de chacun des 137 a été relue au registre : le plus récent, `csstype` 3.2.4, date du 2026-11-17 à 09:43 UTC.

Images de base, toutes deux sur Docker Hub, qui date les étiquettes (`tag_last_pushed`) : Renovate y compte les 7 jours, hors du bloc de l'ADR-016.

| Image | Condensat d'index | Poussée le (UTC) | 7 jours atteints le | Taille amd64 |
| --- | --- | --- | --- | --- |
| `node:26.13.1-alpine` | `sha256:6bd9ab43c0ec0190ca7b2d193906cb8b7edf6e7f4afa43ddeccd6452710bffb5` | 2026-11-11 20:41 | 2026-11-18 | 63,0 Mo |
| `nginx:1.30.7-alpine-slim` | `sha256:8c950211a641ec5b23f265450517001f6bcca533666120ebe36cb4cff3d00a55` | 2026-11-19 01:50 | 2026-11-26 à 01:50 | 5,7 Mo |

Les deux condensats ont été relus par `docker buildx imagetools inspect`. L'image Node s'appuie sur `alpine:3.24` (même condensat sous `26.13.1-alpine3.24`). nginx 1.30.7, stable du 2026-11-18, corrige neuf avis, dont CVE-2026-125283 (`try_files` avec `alias`). La PR du front ne fusionne pas avant le 2026-11-26 à 01:50 UTC. nginx 1.30.8, du 2026-11-23, corrige CVE-2026-132779, qui vise `ssl_early_data` : le nginx du front ne termine pas TLS et n'emploie pas cette directive, donc l'exception de sécurité ne s'impose pas ; Renovate proposera `1.30.8-alpine-slim`, poussée le 2026-11-24 à 07:52, après ses 7 jours. La variante `alpine` de 1.30.7 pèse 26,1 Mo en amd64, et son condensat courant date du 2026-11-20.

Volume pour [FINOPS] (R-04), mesuré le 2026-11-24 en arm64 : `npm ci` télécharge environ 28,5 Mio d'archives (taille du cache de npm après installation, `du -sk`) et écrit 103,0 Mio dans `node_modules`, dont 25,8 Mio pour le binaire de TypeScript et 18,1 Mio pour celui de Rolldown. S'y ajoutent l'image Node, 63,0 Mo en amd64 et 68,0 Mo en arm64 (`full_size` de Docker Hub), et l'image nginx, 5,7 Mo. L'essai de BENCH-005 ne tirait que nginx.

Renovate de CELIAN : le gestionnaire `npm` lit par défaut `(^|/)package\.json$`, et confie l'entretien de `package-lock.json` à npm. Les paquets du front montent donc par des PR de CELIAN, avec le délai de 7 jours ; les deux images aussi, par le gestionnaire `dockerfile` (RS-17).

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://github.com/nodejs/Release/blob/main/schedule.json> | 2026-11-24 | Dates de LTS, de maintenance et de fin des lignes 22 à 27 |
| <https://api.github.com/repos/nodejs/node/releases> | 2026-11-24 | 26.13.1 du 2026-11-11, release de sécurité ; 26.13.0, passage en LTS |
| <https://nodejs.org/dist/index.json> | 2026-11-24 | npm 11.20.0 dans 26.13.1, `security: true` |
| <https://registry.npmjs.org/react> | 2026-11-24 | Champs `time`, `dist-tags` et `license` ; idem pour chaque paquet cité, à `https://registry.npmjs.org/<paquet>`, et pour les 137 paquets du verrou |
| <https://api.github.com/advisories?ecosystem=npm&affects=vitest@5.1.0> | 2026-11-24 | Aucun avis ; idem pour chacune des dix versions retenues |
| <https://hub.docker.com/v2/repositories/library/node/tags/26.13.1-alpine> | 2026-11-24 | Condensat, `tag_last_pushed`, taille par architecture |
| <https://hub.docker.com/v2/repositories/library/node/tags?page_size=100&name=26.13.1> | 2026-11-24 | Étiquettes `slim` repoussées le 2026-11-24 |
| <https://nginx.org/en/download.html> | 2026-11-24 | Stable 1.30.8, principale 1.31.10 |
| <https://nginx.org/en/CHANGES-1.30> | 2026-11-24 | Avis corrigés par 1.30.7 et 1.30.8 |
| <https://hub.docker.com/v2/repositories/library/nginx/tags/1.30.7-alpine-slim> | 2026-11-24 | Condensat, `tag_last_pushed`, taille par architecture |
| <https://hub.docker.com/v2/repositories/library/nginx/tags/1.30.7-alpine> | 2026-11-24 | Condensat courant et taille de la variante `alpine` |
| <https://hub.docker.com/v2/repositories/library/nginx/tags?page_size=100&name=1.30> | 2026-11-24 | Étiquettes 1.30.8 poussées les 2026-11-23 et 2026-11-24 |
| <https://docs.renovatebot.com/modules/manager/npm/> | 2026-11-24 | Motifs par défaut, entretien de `package-lock.json` par npm |

### Relevé du 2026-11-26 : outils de `task check` au README (T090)

Le README du golden repo donne, pour conftest, OpenTofu et Trivy, la version de `tests/tools/install.sh`, la licence et la date : conftest 0.71.1, Apache-2.0, d'après son fichier `LICENSE` lu le 2026-11-23 (ci-dessus) ; Trivy 0.76.2, Apache-2.0 (RS-22, lu le 2026-11-23) ; OpenTofu 1.13.9, MPL-2.0 (API de `opentofu/opentofu`, lue le 2026-11-26). Le détail de ce relevé, avec Docker Engine, kind, kubectl, Task et Git, est au point RS-09. S18 (`tests/static/s18-readme.sh`) compare le tableau du README aux fichiers qui portent ces versions.

### Relevé du 2026-11-26 : kubeconform et schémas de S08 (T129, étape 14)

Fait par [OPS], choix à confirmer par [QA] : la consultation de [QA] est à faire par le DSI, l'agent n'a pas pu la mener. Sources lues par `gh api` et `gh release download`, essais hors ligne.

Outil. kubeconform valide des manifests contre des schémas JSON, hors ligne quand les schémas sont des fichiers. Il n'a besoin d'aucun cluster, contrairement à `kubectl apply --dry-run=server`, et lit des schémas de CRD, que `kubectl --dry-run=client` ne valide pas. conftest ne valide pas contre un schéma. Version 0.8.0, publiée le 2026-06-04 à 20:08:59 UTC (plus de 7 jours, principe VI), licence Apache-2.0 (API de GitHub), dépôt non archivé, dernier push le 2026-06-13, aucune release postérieure. La release n'est pas immuable et ne publie aucune signature parmi ses 8 fichiers, seulement `CHECKSUMS` : les SHA-256 de `CHECKSUMS` sont égaux au champ `digest` de l'API, et l'archive téléchargée a la somme attendue.

| Archive | SHA-256 |
| --- | --- |
| `kubeconform-linux-amd64.tar.gz` | `9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883` |
| `kubeconform-linux-arm64.tar.gz` | `1f53fc8e81258197a35e8603054162a5af1de8c5af13746c71ab680d9534ed87` |
| `kubeconform-darwin-amd64.tar.gz` | `71dbc87ac9f24099a62b93570e65aa06312ba6ac8aea63b7f86e9d999edf5a92` |
| `kubeconform-darwin-arm64.tar.gz` | `f84f4dfbebf4a6b0b230385fa065a39ea35e02608c2b50d025dcf64775a69d67` |

Emploi, lu dans le Readme au tag v0.8.0 et essayé : `-schema-location` accepte un gabarit qui finit par `.json` et les variables `ResourceKind`, `ResourceAPIVersion`, `Group`, `KindSuffix` ; plusieurs emplacements s'essaient dans l'ordre ; sans `-ignore-missing-schemas`, un kind sans schéma échoue ; `-skip` nomme des kinds. `-strict` est décrit « disallow additional properties not in schema or duplicated keys ». Essayé sur le schéma d'une CRD tel que Gateway API le publie, il laisse passer un champ inconnu sous `spec`, le schéma ne fermant pas ses objets (la lecture du code de kubeconform n'a pas été faite, seul l'essai le dit). `tests/schemas/regenerate.sh` ajoute donc `additionalProperties: false`, par `jq`, aux objets des trois CRD de Gateway API qui listent des propriétés ; avec lui, le même champ est refusé.

Schémas. Gateway API : le `openAPIV3Schema` de la version `v1` de Gateway, GatewayClass et HTTPRoute dans `standard-install.yaml` v1.5.0 (RS-16), converti par `conftest parse` et `jq`. Kubernetes : fichiers « standalone-strict » de `yannh/kubernetes-json-schema`, que kubeconform nomme sa source par défaut, au commit `e62c03bd5a52fd34ff6ac28d083e2a300e0ae7c1` (2026-11-25), dossier `v1.36.7-standalone-strict` (le dépôt liste de v1.34 à v1.37.3). Le défaut de kubeconform lit la branche `master` de ce dépôt à chaque exécution : S08 n'y va pas, il lit des fichiers versionnés, dont les sommes sont dans `tests/schemas/SHA256SUMS` et dont la licence est dans `tests/schemas/NOTICE`. Onze schémas de Kubernetes (Namespace, ConfigMap, ServiceAccount, Service, Deployment, NetworkPolicy, Role, RoleBinding, ClusterRole, ValidatingAdmissionPolicy et sa liaison) et trois de Gateway API pèsent 1,26 Mo, le Deployment 692 ko : au-dessus des 500 ko que `check-added-large-files` laisse passer, d'où l'exclusion du dossier (écart 186).

Essais. La couche commune de l'étape 7 (4 objets) passe `-strict`. Un champ inconnu sous `spec` de la Gateway est refusé, comme un port écrit `eighty` : S08 le rejoue à chaque exécution pour prouver ses schémas. Les 7 rendus de la PR (base, trois overlays, composition `gcp/k8s/prod`, `bootstrap`, `values`) passent, `SecretProviderClass`, `SecretSync` et `RootSync` sautés par leur nom (écart 180).

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://api.github.com/repos/yannh/kubeconform/releases/tags/v0.8.0> | 2026-11-26 | Date, 8 fichiers, `digest`, release non immuable ; licence par l'API du dépôt |
| <https://github.com/yannh/kubeconform/blob/v0.8.0/Readme.md> | 2026-11-26 | Options, gabarit de `-schema-location`, variables |
| <https://github.com/yannh/kubernetes-json-schema/tree/e62c03bd5a52fd34ff6ac28d083e2a300e0ae7c1> | 2026-11-26 | Dossiers `v1.34` à `v1.37.3`, `v1.36.7-standalone-strict`, notice Apache-2.0 |

## RS-19. Mesures de la gate

Décision : la démo de l'étape 17 reprend la méthode des scripts de BENCH pour le volume et le temps, sur un poste propre, en profil standard, et rapporte le volume au budget de 900 s et au débit qu'il exige.

À fixer : la méthode exacte de mesure du volume en démo, avec [BENCH] ; le poste et sa connexion, notés dans le rapport.

## RS-20. Ports de l'hôte

Décision : deux ports de l'hôte, HTTP et HTTPS, en `listenAddress: "127.0.0.1"`, valeurs fixées à l'étape 7 et vérifiées libres avant toute création (P04). Ils se fixent à la création du cluster : la configuration les déclare d'emblée.

Sources : ADR-004, condition 1 et conséquences ; ADR-005, portée ; spec, cas limites.

### Relevé du 2026-11-25 : valeurs des ports (T059, étape 7)

Fait par [OPS]. Code de kind au tag v0.33.0 lu par `gh api`, page des Services de Kubernetes lue par WebFetch.

Valeurs retenues par [OPS] : 18080 pour HTTP et 18443 pour HTTPS sur l'hôte, en 127.0.0.1 ; 30080 et 30443 pour les NodePort du proxy, dans le nœud. Ce sont les ports que BENCH-004 a mesurés (M7, M8), et ceux que P04 essaie déjà. Un port pris sur le poste arrête `task up` avant toute création (P04). Les valeurs vivent dans `local/kind/cluster.yaml` et sous `vars:` dans `local/tasks/local.yml` ; S05 les garde d'accord, et vérifie que chaque `nodePort` de l'EnvoyProxy est le `containerPort` d'un `extraPortMappings` (écart 10 de tasks.md).

Champs de kind v0.33.0 : `containerPort`, `hostPort`, `listenAddress` et `protocol` d'un `extraPortMappings` (`pkg/apis/config/v1alpha4/types.go`, lignes 278 à 291). NodePort : « the Kubernetes control plane allocates a port from a range specified by `--service-node-port-range` flag (default: 30000-32767) », et un `nodePort` demandé doit tenir dans cette plage ; deux Services ne peuvent pas le prendre ensemble (page des Services, « Choosing your own port »). Le cluster de kind garde la plage par défaut.

Un environnement repris tient lui-même ses ports : au second `task up`, les deux ports répondent, et la sonde de P04 les dirait pris. Les contrôles préalables lisent donc d'abord les nœuds du cluster du projet (`docker container ls --all --filter label=io.x-k8s.kind.cluster=saas-b2b`, étiquette relevée en RS-13), puis leurs `HostConfig.PortBindings`. Sans nœud, chaque port doit être libre ; avec un nœud, chaque port doit y être publié en 127.0.0.1, ou `task up` s'arrête et demande `task down` : un cluster créé avant l'étape 7 n'a pas ces ports, et `local/scripts/cluster.sh` ne fait que réutiliser un cluster existant.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/apis/config/v1alpha4/types.go> | 2026-11-25 | Lignes 278 à 291 : champs d'un `extraPortMappings` |
| <https://kubernetes.io/docs/concepts/services-networking/service/> | 2026-11-25 | Plage 30000-32767 par défaut ; `nodePort` choisi dans la plage, collisions à la charge de qui le choisit |
| `tests/bench/bench-004-gateway.sh`, lignes 108 à 111 | 2026-11-25 | 18080, 18443, 30080 et 30443 mesurés par BENCH-004 |

## RS-21. Kubeconfig et contexte

Décision : `task up` écrit le kubeconfig du cluster dans un fichier propre au projet, hors du dépôt, et passe ce fichier à chaque commande ; le kubeconfig par défaut de l'utilisateur n'est ni lu ni modifié.

Pourquoi : ADR-004, condition 9 ; FR-019 ; décision de la GATE 1 (aucun contexte GKE sur le poste avant la GATE 2). Un fichier dédié évite aussi qu'un contexte cloud courant reçoive une commande par erreur.

Tranché avec [SECU] à l'étape 6 (voir plus bas) : l'emplacement exact du fichier, au regard de R-07 (ce kubeconfig lit tous les Secrets du cluster).

### Relevé et proposition du 2026-11-25 (T039), tranchés par [SECU]

Fait par [OPS], dans le code de kind au tag v0.33.0, lu par `gh api`. T039 nomme [DEV] et [SECU] ; [OPS] écrit la proposition, et la décision reste à [SECU].

Ce que fait kind. `kind create cluster` prend `--name`, `--config`, `--kubeconfig` (« sets kubeconfig path instead of $KUBECONFIG or $HOME/.kube/config ») et `--wait` (`pkg/cmd/kind/create/cluster/createcluster.go`, lignes 57 à 92) ; `kind delete cluster` et `kind export kubeconfig` prennent `--name` et `--kubeconfig`. Avec `--kubeconfig`, kind ne lit et n'écrit que ce fichier, mais il y fusionne : `WriteMerged` (`merge.go`) ajoute ses entrées à celles que le fichier contient déjà, et `RemoveKIND` (`remove.go`) retire les siennes et laisse le reste. Le fichier du projet ne tient que l'entrée du cluster `saas-b2b`, et `task down` le supprime en entier après le cluster, parce qu'il est propre au projet ; sans `--kubeconfig`, il prend `KUBECONFIG`, puis `$HOME/.kube/config` (`pkg/cluster/internal/kubeconfig/internal/kubeconfig/paths.go`, lignes 30 à 57). Chaque appel de kind des scripts passe donc `--kubeconfig` et `--name`, et chaque appel de kubectl `--kubeconfig` et `--context` (S19) : un `KUBECONFIG` de l'utilisateur n'est ni lu ni modifié (E24).

Proposition : `$HOME/.kube/kind-saas-b2b`, fichier en mode 600 dans un dossier en 700, écrits sous `umask 077`. Le chemin vit dans `local/scripts/lib/local-env.sh`. Tranché par [SECU] à la relecture de la PR #65, le 2026-11-25 : cet emplacement est validé.

- Hors du dépôt : ce fichier lit tous les Secrets du cluster. Dans l'arborescence, il tomberait dans une copie du dépôt (X01), une archive ou un contexte de `docker build` trop large, et ne serait qu'à un `.gitignore` près d'entrer dans Git. `.gitignore` garde ses motifs `kubeconfig*` et `*.kubeconfig` pour une copie laissée par erreur.
- Sous `~/.kube/`, dossier des kubeconfigs de kubectl, que kubectl ne lit pas d'office à un autre nom que `config` : le fichier n'entre dans aucune fusion par défaut.
- Dans CELIAN, `.claude/settings.json` refuse aux agents la lecture de `~/.kube` (R-07, `CLAUDE.md`, « Garde-fous ») : le fichier tombe sous ce refus sans règle de plus. Ce refus filtre un motif ; un script qui ouvre le fichier lui-même y échappe, comme le dit `CLAUDE.md`.
- `task down` supprime le fichier après le cluster : il ne désignait plus rien.

Les tests sur kind tournent avec un `HOME` à eux (`local/tests/e2e/run.sh`) : ils n'écrivent jamais dans le `~/.kube` du poste. Une seule valeur par poste, comme le nom du cluster `saas-b2b`, que kind tient pour unique par moteur. Point pour [SECU] : un nom propre à chaque clone (dossier du dépôt haché) éviterait que deux clones partagent le fichier, au prix d'un nom moins lisible ; le cluster, lui, reste partagé.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/cmd/kind/create/cluster/createcluster.go> | 2026-11-25 | Options `--name`, `--config` (et `-` pour l'entrée standard), `--kubeconfig`, `--wait` |
| <https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/cmd/kind/delete/cluster/deletecluster.go> | 2026-11-25 | Options `--name`, `--kubeconfig` |
| <https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/cmd/kind/export/kubeconfig/kubeconfig.go> | 2026-11-25 | Options `--name`, `--kubeconfig` |
| <https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/cluster/internal/kubeconfig/internal/kubeconfig/merge.go> | 2026-11-25 | `WriteMerged` : fusion des entrées de kind dans le fichier cible |
| <https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/cluster/internal/kubeconfig/internal/kubeconfig/remove.go> | 2026-11-25 | `RemoveKIND` : retrait des seules entrées du cluster |
| <https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/cluster/internal/kubeconfig/internal/kubeconfig/paths.go> | 2026-11-25 | Lignes 30 à 57 : `--kubeconfig` seul fichier lu et écrit, sinon `KUBECONFIG`, sinon `$HOME/.kube/config` |

## RS-22. Outil du SBOM et du scan, format du SBOM

Décision : Trivy pour les deux, SBOM au format CycloneDX en JSON. Un seul binaire produit le SBOM de chaque image construite et scanne chaque image de l'inventaire (RS-24). C'est déjà l'outil du scan du HCL (ADR-008, condition 6), et l'ADR-011 (condition 8) comme R-34 parlent du « SBOM et [du] scan Trivy du projet généré ». Trivy ne figure pas encore dans la CI de CELIAN : ni `.github/workflows/` ni `.pre-commit-config.yaml` ne l'appellent au 2026-11-23. Il n'a tourné qu'à la main, chez [SECU], pour BENCH-004 et BENCH-008.

Pourquoi :

- un outil de moins à figer, vérifier et suivre. La chaîne de Trivy a elle-même été compromise en mars 2026 (plus bas) : chaque outil de CI est une porte d'entrée ;
- CycloneDX, parce que Dependency-Track, que le brief et le PRD prévoient pour plus tard (Q9), consomme des BOM CycloneDX. Trivy écrit CycloneDX en JSON seulement (`--format cyclonedx`, XML non pris en charge), et SPDX en texte ou en JSON.

Écart au PRD : le PRD (US-009) et le brief nomment Syft pour le SBOM. Le plan s'en écarte pour la raison ci-dessus, écart confirmé par Lucas le 2026-11-23 ; il s'écrira dans le PRD.

Installation : binaire de la release, SHA-256 écrit dans le dépôt et vérifié avant chaque usage, sur le modèle de kind (ADR-004, condition 5). À chaque montée de version, [SECU] vérifie par cosign la signature sigstore de la release avant d'écrire la somme. Jamais par les actions `aquasecurity/trivy-action` ni `aquasecurity/setup-trivy` (S26). Plancher : 0.71.1, qui corrige CVE-2026-55092. Candidate : 0.76.2, celle de BENCH-008, publiée le 2026-11-05 en release immuable avec son fichier de sommes et ses bundles sigstore ; elle passe le délai de 7 jours (principe VI). Licence Apache-2.0 ; projet d'Aqua Security, éditeur unique.

Base de vulnérabilités : téléchargée à chaque exécution depuis ses registres par défaut, `mirror.gcr.io/aquasec` puis `ghcr.io/aquasecurity`. Jamais mise en cache d'une exécution à l'autre, jamais sautée (`--skip-db-update` interdit, S26) : une base périmée tirée d'un cache passerait au vert sans avoir vu les avis du jour, ce que refuse le cas limite de la spec.

Conservation : les SBOM sont des artefacts de l'exécution, à la rétention par défaut de GitHub, 90 jours, le maximum permis pour un dépôt public.

Compromission de mars 2026 : CVE-2026-33634 (GHSA-69fq-xp46-6x23, critique, publiée le 2026-03-21). Une v0.69.4 malveillante est partie sur tous les canaux de distribution ; 76 des 77 tags de `trivy-action` et les 7 tags de `setup-trivy` ont été réécrits vers du code qui volait les secrets des pipelines. L'avis recommande d'épingler les actions par SHA complet et de vérifier les binaires par cosign ; les images désignées par condensat n'étaient pas touchées. S'y ajoute CVE-2026-55092 (GHSA-mcj4-mphf-j9ff, élevée, publiée le 2026-06-15) : un artefact OCI hostile, base de vulnérabilités comprise, fait écrire Trivy hors de son dossier, sur les versions antérieures à 0.71.1.

À vérifier avant l'étape 18 (porteur [DEV], avec [SECU]) :

- la documentation de la version retenue : la page des filtres lue le 2026-11-23 s'annonce comme une version antérieure à la dernière (ses liens visent v0.67.2) ;
- le code de sortie de Trivy quand aucun registre de la base ne répond : la page de la base décrit le repli d'un registre à l'autre sur erreur transitoire, pas l'échec total. E27 le joue ;
- la lecture d'une image construite dans le moteur du runner, ou par une archive ;
- la commande cosign qui vérifie le bundle sigstore, et la version de cosign.

Alternatives : Syft pour le SBOM, nommé par le PRD, écarté pour l'outil de plus ; SPDX, écarté parce que Dependency-Track lit CycloneDX ; l'image de Trivy par condensat, sur le modèle de gitleaks dans `.github/workflows/secrets.yml`, gardée en repli, parce que la lecture des images construites depuis un conteneur reste à vérifier.

Sources :

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://trivy.dev/latest/docs/supply-chain/sbom/> | 2026-11-23 | Formats CycloneDX (`--format cyclonedx`, JSON seulement) et SPDX ; scan d'un SBOM en entrée |
| <https://trivy.dev/latest/docs/configuration/db/> | 2026-11-23 | Registres de la base, `--skip-db-update`, repli entre registres sur erreur transitoire ; échec total non décrit |
| <https://github.com/aquasecurity/trivy/security/advisories/GHSA-69fq-xp46-6x23> | 2026-11-23 | CVE-2026-33634 : versions, fenêtres, actions réécrites, remède (SHA, cosign) |
| <https://github.com/aquasecurity/trivy/security/advisories/GHSA-mcj4-mphf-j9ff> | 2026-11-23 | CVE-2026-55092, corrigée en 0.71.1 |
| <https://api.github.com/repos/aquasecurity/trivy/releases/latest> | 2026-11-23 | v0.76.2, publiée le 2026-11-05, release immuable, fichier de sommes et bundles sigstore |
| <https://github.com/aquasecurity/trivy> | 2026-11-23 | Apache-2.0 ; « an Aqua Security open source project » ; dépôt non archivé |
| <https://docs.dependencytrack.org/usage/cicd/> | 2026-11-23 | Dependency-Track consomme des BOM CycloneDX |
| <https://docs.github.com/en/organizations/managing-organization-settings/configuring-the-retention-period-for-github-actions-artifacts-and-logs-in-your-organization> | 2026-11-23 | Rétention des artefacts : 90 jours par défaut, de 1 à 90 jours pour un dépôt public |

### Relevé du 2026-11-25 : Trivy figé (T103)

Fait par [OPS], second porteur [SECU], qui relit la vérification de signature avant la fusion. Trivy est figé dès l'étape 13, qui scanne le HCL (S15) ; la première PR de l'étape 18 reprend cette version (écart 6 de tasks.md).

Version : 0.76.2, publiée le 2026-11-05 à 12:50:25 UTC, release immuable (`immutable: true`), au-dessus du plancher de 0.71.1. Elle passe le délai de 7 jours.

Signature. La documentation de 0.76.2 (`docs/getting-started/signature-verification.md` au tag `v0.76.2`) : depuis 0.68.1, chaque fichier de la release a son bundle sigstore `.sigstore.json`, et les commandes « assume cosign v3.0.0+ ». cosign retenu : v3.1.4, publiée le 2026-10-20, release immuable ; v3.1.5 du 2026-11-24 ne passe pas le délai. Le binaire `cosign-darwin-arm64` a été tiré par `gh release download` dans un dossier vide, et son SHA-256 (`9f9b8cd557cf2e5b3df3373a00baa005a86b02391e3e06dd0ce37b3a1533d3a4`) comparé à `cosign_checksums.txt` de la même release avant tout usage. La somme protège de la corruption, pas d'une substitution : la signature de cosign lui-même reste à vérifier par [SECU], avec un cosign déjà de confiance. Commande lancée sur le fichier de sommes de Trivy :

```text
cosign verify-blob trivy_0.76.2_checksums.txt \
  --bundle trivy_0.76.2_checksums.txt.sigstore.json \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
  --certificate-identity 'https://github.com/aquasecurity/trivy/.github/workflows/reusable-release.yaml@refs/tags/v0.76.2'
```

Résultat : « Verified OK ». La même commande sur une copie du fichier modifiée d'un octet échoue (« invalid signature when validating ASN.1 encoded signature »). Le fichier de sommes signé porte les quatre sommes ci-dessous, égales au champ `digest` de l'API ; elles entrent dans `golden/saas-b2b/tests/tools/SHA256SUMS`, et `install.sh` les vérifie avant d'ouvrir l'archive. L'archive `macOS-ARM64` tirée pour l'essai contient le seul binaire `trivy`, avec `LICENSE`, `README.md` et `contrib/`.

| Archive | SHA-256 |
| --- | --- |
| `trivy_0.76.2_Linux-64bit.tar.gz` | `bc0fc726e017b8927a62b2d3531d7a84ee01769daf5c99ed866dced54089fdbf` |
| `trivy_0.76.2_Linux-ARM64.tar.gz` | `ab9d51f86e6a5fb936f605faff6b593ac51bc378fff4d3e8b9d58358b9c367c3` |
| `trivy_0.76.2_macOS-64bit.tar.gz` | `e08bb9ea449ecf66c6bfb03cbb8697c503ff33d35fc585c9747e3eaeb7ed4c7b` |
| `trivy_0.76.2_macOS-ARM64.tar.gz` | `ae7ea358326960406b703c77b2ac490190797d80b306b5b50c2a27221da0a5b8` |

Scan du HCL, d'après la documentation de 0.76.2 (`trivy config`, et la page de configuration des erreurs de configuration) :

- `--exit-code` fixe le code de sortie quand un problème est trouvé ; `--misconfig-scanners terraform` limite le scan au HCL ;
- `--ignorefile ''` désactive la lecture de `.trivyignore` (« empty string disables loading ») : chaque échec admis se justifie alors à côté de sa ressource, par le commentaire `#trivy:ignore:<ID>` placé juste au-dessus d'elle (« immediately adjacent to resource definitions ») ;
- `--disable-telemetry` coupe l'envoi de données d'usage à Aqua (« disable sending anonymous usage data to Aqua »), envoi actif par défaut ;
- les règles viennent d'un bundle tiré de `mirror.gcr.io/aquasec/trivy-checks:2` (`--checks-bundle-repository`) ; `--skip-check-update` n'est pas employé dans ce relevé du T103 ; la décision du DSI du 2026-11-25 (relevé ci-dessous) la remplace ;
- `--include-non-failures` liste aussi les règles passées.

Essai sur le socle écrit à la main de BENCH-008, avec cette version : les cinq échecs que relevait [SECU] reviennent, AVD-GCP-0029 et AVD-GCP-0076 (journaux de flux du sous-réseau), AVD-GCP-0050 (compte des nœuds), AVD-GCP-0051 (étiquettes du cluster), AVD-GCP-0061 (réseaux autorisés du plan de contrôle). La racine de l'étape 13 en corrige quatre et justifie le dernier par écrit (T109).

Résultat sur la racine de l'étape 13, le 2026-11-25 (T109) : 91 règles passées, aucun échec. AVD-GCP-0061 est justifié au-dessus de `google_container_cluster.main` : le point d'accès IP du plan de contrôle est désactivé, il n'y a donc aucune plage à restreindre, et l'accès passe par le point d'accès DNS, sous IAM. Sans ce commentaire, Trivy échoue sur cette seule règle. [SECU] relit la justification. Les journaux de flux du sous-réseau partent vers Cloud Logging, dont le prix n'a pas été lu : [FINOPS] en fixe l'échantillonnage avec le budget.

Sur le poste, Trivy 0.76.2 vient de Homebrew : même version, binaire non comparé à la release. La CI installe celui de la release, par sa somme.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://api.github.com/repos/aquasecurity/trivy/releases/tags/v0.76.2> | 2026-11-25 | Date, release immuable, sommes et bundles des archives |
| <https://github.com/aquasecurity/trivy/blob/v0.76.2/docs/getting-started/signature-verification.md> | 2026-11-25 | Bundles sigstore depuis 0.68.1, cosign v3, commande `verify-blob` |
| <https://github.com/aquasecurity/trivy/blob/v0.76.2/docs/guide/references/configuration/cli/trivy_config.md> | 2026-11-25 | Options de `trivy config` |
| <https://github.com/aquasecurity/trivy/blob/v0.76.2/docs/guide/scanner/misconfiguration/config/config.md> | 2026-11-25 | Commentaire `#trivy:ignore:<ID>` adjacent à la ressource |
| <https://api.github.com/repos/sigstore/cosign/releases> | 2026-11-25 | v3.1.4 du 2026-10-20, v3.1.5 du 2026-11-24, releases immuables |
| <https://github.com/sigstore/cosign/releases/download/v3.1.4/cosign_checksums.txt> | 2026-11-25 | SHA-256 de `cosign-darwin-arm64` |

### Relevé du 2026-11-25 : relecture [SECU] de la PR #64

Fait par [OPS]. Sources lues le 2026-11-25 : le code et la documentation de Trivy au tag `v0.76.2`, les règles du dépôt `aquasecurity/trivy-checks` au commit embarqué dans ce binaire (`ac85645895ed`, lu dans `go.mod` de Trivy), la page des options de Cloud SQL, la page de PostgreSQL 18 sur les journaux, la page OIDC de GitHub et celle de la fédération d'identité de Google. Aucun `tofu plan`, aucun apply, aucune commande `gcloud`.

Valeur calculée et Trivy. Trivy ne résout pas `yamldecode(file(...))` : avec `database_version = "POSTGRES_${local.platform.postgres_major}"`, il passait sans appliquer AVD-GCP-0014, 0016, 0020, 0022 et 0025, qui ne visent que les instances PostgreSQL. La version s'écrit donc en littéral (`POSTGRES_18`), et S21 compare ce littéral à `postgres_major` de `platform.yaml`. S15 garde la preuve : une copie de la racine dont les cinq options sont coupées doit échouer sur les cinq règles. L'essai sur la racine avant correction acceptait cette copie.

Les cinq règles, d'après leur source. Trivy lit l'option `database_flags` d'une instance PostgreSQL ; `log_connections`, `log_disconnections`, `log_checkpoints` et `log_lock_waits` valent « on » pour lui, `log_temp_files` doit valoir 0 (une valeur négative ou positive échoue), et une option absente vaut « off » (-1 pour `log_temp_files`). Les cinq sont activées, sans exception `#trivy:ignore`. Volume : un événement par ouverture et fermeture de session, par point de contrôle, par attente de verrou plus longue que `deadlock_timeout`, par fichier temporaire. Pour `log_temp_files`, la page de Cloud SQL donne 0 comme valeur par défaut : l'écrire ne change pas le volume, et la page de PostgreSQL 18 donne -1 par défaut pour le moteur nu. La page de Cloud SQL liste ces options en booléen « on » ou « off » ; elle ne porte pas de mention de version pour elles, et ne confirme pas non plus leur prise en charge sur PostgreSQL 18 : à lire au premier apply autorisé. PostgreSQL 18 remplace `log_connections` par une liste d'options mais accepte encore « on » (page de PostgreSQL 18).

Options de Trivy. `--skip-version-check` avec `--disable-telemetry` : le code de `pkg/notification/notice.go` ne fait aucune requête vers `check.trivy.dev` quand les deux sont vraies, et envoie la télémétrie quand seule la vérification de version est coupée. `--config ''` : « empty string disables loading » (page de `trivy config`), pour qu'un `trivy.yaml` du dépôt ne fasse pas taire le scan. Décision du DSI : `--skip-check-update`, pour utiliser les règles embarquées dans le binaire vérifié par `install.sh` ; le résultat est reproductible, et Renovate apporte les règles nouvelles avec chaque version de Trivy. La documentation de 0.76.2 dit que le bundle est embarqué à la compilation et sert de repli ; l'essai avec un cache vide le confirme (« Falling back to embedded checks ») et applique les cinq règles. Ce relevé remplace le choix du T103, qui laissait tirer le bundle à chaque exécution.

Commentaires d'exception. Trivy lit comme règle tout mot qui commence par `trivy:` ou `tfsec:` après `#`, `/` ou `*` (code de `pkg/iac/ignore`, `*` pour tout, suffixes `exp` et crochets compris). S15 refuse donc tout commentaire de ce genre qui n'est pas, ligne entière, `#trivy:ignore:AVD-GCP-0061` au-dessus de `google_container_cluster.main` ; la liste est `allowed_ignores` dans le script. Six cas d'échec : une règle de journalisation, le joker, la bonne règle sur une autre ressource, le préfixe `tfsec:`, un suffixe d'expiration, deux règles sur une ligne.

Fédération de la CI. `event_name` est une revendication du jeton GitHub (« The name of the event that triggered the workflow run », page OIDC). La page de Google dit que la condition d'attribut peut lire `assertion` et tout attribut du mappage, sans confirmer qu'une revendication non mappée passe ; `event_name` est donc mappé aussi (`attribute.event_name`), comme les trois autres. La condition exige `assertion.event_name == 'push'` : `pull_request_target`, `workflow_run`, `schedule` et `workflow_dispatch` n'obtiennent pas le jeton.

Point d'accès DNS. `enable_k8s_tokens_via_dns` et `enable_k8s_certs_via_dns` sont des arguments de `dns_endpoint_config` en 8.12.0 (« Controls whether the k8s token auth is allowed via Dns », idem pour les certificats). La page ne donne pas leur valeur par défaut : les deux sont écrits à `false`, et S15 (condition 5) refuse `true` comme l'absence.

Liste d'autorisations de S17. Dans le Taskfile et les scripts de `gcp/`, OpenTofu ne s'exécute qu'avec `fmt`, `init` (avec `-backend=false` sur la même ligne), `validate`, `version`, `providers` ; `gcloud` et `kubectl` sont refusés jusqu'à la GATE 2. Le contrôle lit le premier mot après les options, y compris dans un message : S14 écrit « OpenTofu » dans ses messages. Sept cas d'échec dans `gcp/tests/static/s17-cases/`.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://github.com/aquasecurity/trivy/blob/v0.76.2/pkg/notification/notice.go> | 2026-11-25 | Requête vers `check.trivy.dev`, conditions de `--skip-version-check` et `--disable-telemetry` |
| <https://github.com/aquasecurity/trivy/blob/v0.76.2/pkg/iac/ignore/parse.go> | 2026-11-25 | Mots `trivy:` et `tfsec:` lus comme règles |
| <https://github.com/aquasecurity/trivy/blob/v0.76.2/pkg/iac/adapters/terraform/google/sql/adapt.go> | 2026-11-25 | Lecture de `database_flags`, valeurs « on » et défauts |
| <https://github.com/aquasecurity/trivy/blob/v0.76.2/docs/guide/references/configuration/cli/trivy_config.md> | 2026-11-25 | `--config`, `--skip-check-update`, `--skip-version-check` |
| <https://github.com/aquasecurity/trivy/blob/v0.76.2/docs/guide/scanner/misconfiguration/check/builtin.md> | 2026-11-25 | Bundle embarqué à la compilation, repli |
| <https://github.com/aquasecurity/trivy-checks/tree/ac85645895ed/checks/cloud/google/sql> | 2026-11-25 | Règles AVD-GCP-0014, 0016, 0020, 0022, 0025 |
| <https://docs.cloud.google.com/sql/docs/postgres/flags> | 2026-11-25 | Les cinq options, types, défaut de `log_temp_files` |
| <https://www.postgresql.org/docs/18/runtime-config-logging.html> | 2026-11-25 | `log_connections` en liste, « on » accepté, défauts |
| <https://docs.github.com/en/actions/reference/security/oidc> | 2026-11-25 | Revendication `event_name` |
| <https://docs.cloud.google.com/iam/docs/workload-identity-federation> | 2026-11-25 | Condition d'attribut, mot `assertion`, attributs mappés |
| <https://github.com/hashicorp/terraform-provider-google/blob/v8.12.0/website/docs/r/container_cluster.html.markdown> | 2026-11-25 | `enable_k8s_tokens_via_dns`, `enable_k8s_certs_via_dns` |
| <https://github.com/hashicorp/terraform-provider-google/blob/v8.12.0/website/docs/r/sql_database_instance.html.markdown> | 2026-11-25 | `database_flags`, `name`, `value` |

### Relevé du 2026-11-25 : scan des images avec Trivy 0.76.2 (T111, étape 18)

Fait par [OPS] sur délégation du DSI, porteurs prévus [DEV] et [SECU] : [SECU] relit avant la fusion. Code et documentation de Trivy au tag `v0.76.2`, lus par `gh api` ; essais avec le binaire de la release (archive `macOS-ARM64`, SHA-256 égal à `tests/tools/SHA256SUMS`), sous `env -i`, cache dans un dossier temporaire.

Code de sortie quand aucun registre de la base ne répond. `DownloadDB` renvoie « failed to download vulnerability DB » (`pkg/commands/operation/operation.go`, lignes 24 à 50). Le client essaie les dépôts dans l'ordre et ne passe au suivant que sur une erreur de transport temporaire ou `BLOB_UNKNOWN` ; sinon, ou après le dernier, il échoue (`pkg/oci/artifact.go`, lignes 287 à 340). L'erreur remonte à `main`, qui appelle `log.Fatal` (`cmd/trivy/main.go`, ligne 28) ; `log.Fatal` écrit sur la sortie d'erreur même avec `--quiet`, puis sort en 1 (`pkg/log/logger.go`, lignes 86 à 95). Essai avec `--db-repository registry.invalid/aquasec/trivy-db:2` : code 1, « FATAL Fatal error [...] failed to download vulnerability DB [...] lookup registry.invalid: no such host », aucun rapport écrit. La base se télécharge avant l'image : rien n'est tiré du registre de l'image dans ce cas. E27 joue ce cas.

Options retenues pour `trivy image` (page `trivy_image.md` de 0.76.2) :

- `--config ''`, `--ignorefile ''`, `--disable-telemetry`, `--skip-version-check` : comme pour le HCL (relevé précédent). L'essai en mode `--debug` montre « Version check and telemetry are disabled, skipping request » ;
- `--scanners vuln` : la valeur par défaut est `vuln,secret` ; FR-021 ne demande que les vulnérabilités. Sans `misconfig`, aucun bundle de règles n'est tiré (aucune ligne « checks » dans l'essai) ;
- `--image-src remote` : la valeur par défaut, `docker,containerd,podman,remote`, lirait d'abord une image locale de même référence ; `remote` tire le condensat écrit dans l'inventaire, sur le poste comme en CI ;
- `--platform linux/amd64` : « set platform in the form os/arch if image is multi-platform capable ». Les images de l'inventaire sont des index amd64 et arm64 ; la CI tourne en amd64. La variante arm64 n'est pas scannée (écart 58 de tasks.md) ;
- `--offline-scan` : « do not issue API requests to identify dependencies ». La page Java de 0.76.2 précise qu'il coupe les requêtes vers les dépôts Maven, et que « The `--offline-scan` flag does not affect the Trivy database » ;
- `--exit-code 0` : `Exit` ne rend un code non nul que si `--exit-code` l'est (`operation.go`, lignes 122 à 133). Un code non nul de Trivy veut donc dire une erreur, jamais une faille ;
- `--timeout 10m` : la valeur par défaut est 5m0s ; l'image du nœud est la plus lourde de l'inventaire ;
- `--format json`, `--output <fichier>`.

Restent interdits par S26 : `--skip-db-update`, `--skip-java-db-update`, `--ignore-unfixed`, et toute source autre que les dépôts par défaut de `--db-repository` (`mirror.gcr.io/aquasec/trivy-db:2`, puis `ghcr.io/aquasecurity/trivy-db:2`) et de `--java-db-repository` (`mirror.gcr.io/aquasec/trivy-java-db:1`, puis `ghcr.io/aquasecurity/trivy-java-db:1`), hors du cas de E27 sous `.invalid`. La base Java ne se tire que si l'image porte des fichiers JAR ; aucune image de l'inventaire n'en a tiré dans l'essai. `--vex` et `--sbom-sources` sont vides par défaut : ni VEX Hub ni Rekor ne sont appelés (« VEX filtering is disabled » dans l'essai).

Requêtes sortantes constatées en mode `--debug`, cache vide : la base depuis `mirror.gcr.io/aquasec/trivy-db:2`, puis l'image depuis son registre (« Image found [...] source="remote" »). Rien d'autre. La seconde image d'une même exécution réutilise la base tirée par la première.

Filtrage au seuil. `--severity` garde les niveaux listés (valeur par défaut, les cinq niveaux), et une gravité vide devient `UNKNOWN` avant le filtre (`pkg/result/filter.go`, lignes 83 à 119). Le scan ne filtre pas dans Trivy : le rapport garde tous les niveaux, et la politique Rego applique le seuil qu'elle lit dans `security/scan-policy.yaml`. Le seuil n'est ainsi lu qu'à un endroit, les failles `UNKNOWN` restent listées, et le décompte par niveau sert à [SECU] pour revoir le seuil (RS-23). Écart 56 de tasks.md.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://github.com/aquasecurity/trivy/blob/v0.76.2/docs/guide/references/configuration/cli/trivy_image.md> | 2026-11-25 | Options de `trivy image`, valeurs par défaut des dépôts et des niveaux |
| <https://github.com/aquasecurity/trivy/blob/v0.76.2/pkg/commands/operation/operation.go> | 2026-11-25 | `DownloadDB`, `Exit` |
| <https://github.com/aquasecurity/trivy/blob/v0.76.2/pkg/oci/artifact.go> | 2026-11-25 | Repli d'un dépôt à l'autre, échec après le dernier |
| <https://github.com/aquasecurity/trivy/blob/v0.76.2/cmd/trivy/main.go> | 2026-11-25 | Erreur fatale |
| <https://github.com/aquasecurity/trivy/blob/v0.76.2/pkg/log/logger.go> | 2026-11-25 | `log.Fatal` : sortie d'erreur, code 1 |
| <https://github.com/aquasecurity/trivy/blob/v0.76.2/pkg/result/filter.go> | 2026-11-25 | Filtre `--severity`, gravité vide lue `UNKNOWN` |
| <https://github.com/aquasecurity/trivy/blob/v0.76.2/docs/guide/coverage/language/java.md> | 2026-11-25 | `--offline-scan` et dépôts Maven ; base non touchée |

## RS-23. Seuil de gravité et exceptions

Décision : seuil `HIGH`. Une vulnérabilité `HIGH` ou `CRITICAL` fait échouer le scan, sauf exception valide. Le seuil est écrit une seule fois, dans `security/scan-policy.yaml` (nom provisoire), et la tâche de scan le lit là (S26).

Pourquoi `HIGH` : la seule faille connue de la stack, CVE-2026-97054 dans le contrôleur d'Envoy Gateway 1.10.0, est élevée (ADR-005). Un seuil `CRITICAL` la laisserait passer en silence, ce que le récit 7 veut éviter. `MEDIUM` n'est pas retenu d'emblée : le nombre de failles moyennes sur les images de la stack n'est pas mesuré, et des exceptions en série finiraient signées sans être lues. La première PR de l'étape 18 donne ces nombres ; [SECU] pourra alors proposer d'abaisser le seuil. Niveaux relevés dans la documentation de Trivy : `UNKNOWN`, `LOW`, `MEDIUM`, `HIGH`, `CRITICAL`. Une faille `UNKNOWN` ne bloque pas et reste listée dans le rapport ; [SECU] relit ce choix.

Failles sans correctif : aucune option ne les écarte (`--ignore-unfixed` interdit, S26). FR-022 ne distingue pas une faille corrigée d'une faille qui ne l'est pas : au seuil, la seconde demande une exception, avec son échéance.

Exceptions : un fichier par couche, `security/scan-exceptions.yaml` pour les images construites et `local/security/scan-exceptions.yaml` pour les images de la couche `local` (noms provisoires), pour que la phase 3 rende chaque couche avec les siennes. Chaque entrée porte l'identifiant de la vulnérabilité, l'image visée, la justification, la date d'écriture et la date d'échéance. L'image se désigne par son dépôt, sans condensat, pour qu'une montée de condensat par Renovate ne fasse pas tomber l'exception avant son échéance. Proposé, à confirmer par [SECU] : une échéance à 90 jours au plus de la date d'écriture.

Décision du passage : Trivy écrit un rapport JSON par image, filtré au seuil, sans échouer. Une politique Rego, exécutée par conftest, reçoit ce rapport, les exceptions et la date du jour, que la tâche lui passe en donnée. Elle refuse chaque couple image et vulnérabilité au seuil sans exception valide, en les nommant (récit 7, scénario 3). Une exception échue, incomplète ou qui vise une autre image ne compte pas (scénarios 4 et 5). Passer la date en donnée rend la politique testable sur des rapports d'exemple (U03), sans réseau ni image vulnérable.

Première exception attendue : CVE-2026-97054, si aucune release 1.10.x corrigée n'est sortie à l'étape 18. [SECU] l'écrit, avec la justification de l'ADR-005 : les serveurs touchés ne sont joignables que depuis le cluster.

Alternatives : le fichier `.trivyignore.yaml` de Trivy, écarté. Son format est marqué expérimental, il n'a ni portée par image ni date d'écriture, une entrée incomplète n'y est pas refusée, et la page ne dit pas ce que devient une entrée échue. Seuils `CRITICAL` et `MEDIUM`, écartés plus haut.

À vérifier avant l'étape 18 (porteur [DEV]) : la structure du rapport JSON de Trivy dans la version retenue ; l'option de conftest qui charge un fichier de données ; le passage de la date en donnée.

Sources : <https://trivy.dev/latest/docs/configuration/filtering/>, lue le 2026-11-23 (`--severity`, niveaux de l'exemple, `--ignore-unfixed`, format expérimental de `.trivyignore.yaml` et ses champs `id`, `paths`, `purls`, `expired_at`, `statement`) ; ADR-005, CVE-2026-97054 ; spec, FR-022.

### Relevé du 2026-11-25 : rapport JSON, données de conftest et premier passage (T111, T118, étape 18)

Fait par [OPS] sur délégation du DSI ; [SECU] relit, et reste porteur de T118 pour les exceptions.

Rapport JSON de Trivy 0.76.2. `SchemaVersion` vaut 2 (`pkg/report/writer.go`, ligne 26). Le rapport porte `ArtifactName`, la référence passée à Trivy, `ArtifactType` (`container_image`), `Metadata` et `Results` (`pkg/types/report.go`, lignes 19 à 40). Chaque résultat a `Target`, `Class` (`os-pkgs`, `lang-pkgs`, ...) et `Vulnerabilities` (lignes 157 à 175). Chaque vulnérabilité a `VulnerabilityID`, `PkgName`, `InstalledVersion`, `FixedVersion` et `Severity` (`pkg/types/vulnerability.go`, lignes 8 à 35, et `pkg/types/types.go` de trivy-db au commit `cbebf2ecd6df` que nomme `go.mod`). `Severity` y est marqué « Deprecated », gardé jusqu'au schéma 3 de la base ; c'est le champ que filtre `--severity`. Les niveaux, dans l'ordre : `UNKNOWN`, `LOW`, `MEDIUM`, `HIGH`, `CRITICAL` (`SeverityNames`, même fichier). La politique refuse un rapport d'un autre schéma que 2, et lit une gravité absente comme `UNKNOWN`, comme Trivy. Une gravité hors de la liste bloque, faute de pouvoir la classer.

conftest 0.71.1, qui embarque OPA 1.21.1 (`go.mod` de conftest au tag ; `conftest --version`). `--data` (`-d`) : « The paths at the flag are recursively searched for JSON and YAML files », et chaque clé de tête devient `data.<clé>` (page `options.md`). L'essai confirme qu'un chemin de fichier convient et que l'option se répète : `security/scan-policy.yaml` donne `data.scan_policy`, et un fichier temporaire `{"scan_today": "AAAA-MM-JJ"}` donne la date du jour en donnée. `--combine` réunit les fichiers dans un tableau d'objets `path` et `contents` (même page) ; l'ordre ne se garantit pas, et la politique reconnaît chaque fichier à sa forme. Une date YAML écrite sans guillemets arrive comme la chaîne `2026-11-25`. Aucune règle ne s'appelle `exception` : conftest réserve ce nom à ses propres exceptions (page `exceptions.md`).

Dates en Rego. `time.parse_ns(layout, value)` et `time.add_date(ns, years, months, days)` existent dans OPA 1.21.1 (`builtin_metadata.json` au tag `v1.21.1`). La forme `2006-01-02` est `time.DateOnly` de Go (`src/time/format.go`, Go 1.25.0). Essai : une date impossible (`2026-13-45`) rend l'expression indéfinie sans erreur ; la politique en fait donc un motif de refus explicite.

Règles de la décision, écrites dans `policy/scan_decision.rego` et `policy/scan_exceptions.rego` : une exception vaut si ses cinq champs sont des chaînes non vides, si `image` est un dépôt sans étiquette ni condensat, si `written` et `expires` sont des dates valides, `written` au plus tard aujourd'hui, `expires` après `written` et au plus `max_exception_days` jours plus tard (90, proposé, valeur de `security/scan-policy.yaml`), et si aujourd'hui ne dépasse pas `expires`, dernier jour où elle vaut. S27 refuse toute entrée qui ne vaut pas, échue comprise, en la nommant : un passage de `task check` qui réussit ne montre rien (`tests/run-static.sh`), et une entrée échue doit se voir. La décision du scan l'ignore et la liste en avertissement.

Premier passage, le 2026-11-25. Trivy 0.76.2, `linux/amd64`, base du 2026-11-25 à 13:07 UTC (`UpdatedAt`). Les nombres comptent les lignes du rapport, une par vulnérabilité, paquet et cible ; « distinctes » compte les identifiants au seuil.

| Image | CRITICAL | HIGH | MEDIUM | LOW | UNKNOWN | Distinctes au seuil | Dont avec correctif |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `docker.io/kindest/node:v1.36.4` (Debian 13.6) | 5 | 331 | 481 | 239 | 36 | 99 | 79 |
| `ghcr.io/project-zot/zot:v2.1.23` | 0 | 2 | 21 | 10 | 3 | 2 | 2 |
| `docker.io/envoyproxy/gateway:v1.10.0` | 0 | 0 | 17 | 10 | 2 | 0 | 0 |
| `docker.io/envoyproxy/envoy:distroless-v1.40.2` | 0 | 0 | 16 | 10 | 2 | 0 | 0 |
| `docker.io/library/postgres:18.7-trixie`, entrée avec l'étape 8 | 2 | 156 | 214 | 168 | 29 | 64 | 42 |

Dans l'image du nœud, 160 lignes au seuil viennent des paquets Debian, le reste des binaires Go (kubelet, kubeadm, containerd, runc, crictl, greffons CNI), surtout la bibliothèque standard de Go (76) et `golang.org/x/net` (42). Les cinq critiques : `libbrotli1`, trois de `perl-base`, et `google.golang.org/grpc` dans `containerd-fuse-overlayfs-grpc`. Pour zot : CVE-2026-95839 (`github.com/containerd/containerd/v2` 2.4.1, corrigé en 2.4.2) et CVE-2026-78661 (`golang.org/x/net` 0.61.0, corrigé en 0.62.0). Pour Postgres : 132 lignes Debian, 26 dans `gosu` ; les deux critiques sont CVE-2026-6653 (`libxml2`, sans correctif) et CVE-2025-68121 (bibliothèque standard de Go 1.24.6 dans `gosu`).

CVE-2026-97054 sort en MEDIUM dans le contrôleur d'Envoy Gateway (`SeveritySource` vide, gravité des autres fournisseurs : Red Hat, Alma, Amazon, Oracle, Photon à 2 sur 4), comme le relevait [SECU] (RS-02). Au seuil `HIGH`, aucune exception ne la vise.

Conclusion. 101 identifiants au seuil sur les images de `main`, 165 avec Postgres : bien au-delà de ce qui se justifie une par une. T118 le prévoit : le seuil ou la spec se rediscutent avec Lucas, par le DSI. Aucune exception n'est écrite, et le job `scan-images` échoue sur l'image du nœud et sur zot tant que la décision n'est pas prise (écart 55 de tasks.md).

Suite, décision du DSI du 2026-11-25 (par délégation de Lucas, réversible, à confirmer par Lucas à la GATE 2). Le seuil `HIGH` reste. Le scan ne bloque que les images que le projet construit, toute image déployée sur `gcp` et toute image que l'inventaire ne classe pas ; les images tierces du cluster local (nœud, zot, Envoy Gateway et son proxy, Postgres local) sont signalées dans un tableau du résumé du job, sans bloquer. La classe de chaque image s'écrit dans `security/scan-policy.yaml`, sous `image_classes`, et la politique de décision la lit comme elle lit le seuil. Raison : seuls l'API et le front partent en production sur `gcp` (Cloud SQL et Memorystore sont managés), et bloquer sur l'outillage local figerait toutes les PR sans protéger ce qui est déployé. Amendement de FR-021 et FR-022 dans spec.md ; écarts 55 et 57 de tasks.md. Les exceptions de RS-23 ne servent donc qu'aux images bloquantes.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://github.com/aquasecurity/trivy/blob/v0.76.2/pkg/report/writer.go> | 2026-11-25 | `SchemaVersion = 2` |
| <https://github.com/aquasecurity/trivy/blob/v0.76.2/pkg/types/report.go> | 2026-11-25 | `Report`, `Metadata`, `Result` |
| <https://github.com/aquasecurity/trivy/blob/v0.76.2/pkg/types/vulnerability.go> | 2026-11-25 | `DetectedVulnerability` |
| <https://github.com/aquasecurity/trivy-db/blob/cbebf2ecd6df/pkg/types/types.go> | 2026-11-25 | `SeverityNames`, `Severity` déprécié |
| <https://github.com/open-policy-agent/conftest/blob/v0.71.1/docs/options.md> | 2026-11-25 | `--data`, `--combine` |
| <https://github.com/open-policy-agent/conftest/blob/v0.71.1/docs/exceptions.md> | 2026-11-25 | Règle `exception` réservée |
| <https://github.com/open-policy-agent/conftest/blob/v0.71.1/go.mod> | 2026-11-25 | OPA v1.21.1 |
| <https://github.com/open-policy-agent/opa/blob/v1.21.1/builtin_metadata.json> | 2026-11-25 | `time.parse_ns`, `time.add_date` |
| <https://github.com/golang/go/blob/go1.25.0/src/time/format.go> | 2026-11-25 | `DateOnly = "2006-01-02"` |

## RS-24. Inventaire des images

Décision : l'inventaire d'un profil se calcule à chaque exécution, sans recopier les condensats. Il réunit les images des rendus du profil, celles des fichiers vendorés (Envoy Gateway, Flux), l'image du nœud de la configuration kind, celle du miroir et les images construites sous `saas-b2b.invalid`. S'y ajoute une courte liste versionnée, `local/security/unlisted-images` (nom provisoire), des images qu'aucun fichier du projet ne nomme : celles que l'image du nœud précharge (plan de contrôle, réseau, DNS, provisionneur de volumes), et l'image du proxy, que le contrôleur d'Envoy Gateway porte figée par condensat dans son binaire (BENCH-004).

E25 relève, après `task up` dans chaque profil livré, l'image résolue (son condensat) de chaque conteneur en marche dans le cluster, conteneurs d'initialisation compris, et de chaque conteneur du moteur. Sur le runner de CI, le moteur ne porte que les conteneurs du projet ; sur un poste, seuls ceux du projet sont relevés. E25 échoue sur toute image absente de l'inventaire scanné. Une montée de l'image du nœud ou d'Envoy Gateway qui change ces images fait donc échouer E25 tant que la liste n'est pas à jour : c'est le contrôle que FR-021 demande.

Hors de l'inventaire : les images de construction (SDK .NET, Node.js), qui ne tournent ni dans le cluster ni sur le moteur une fois `task up` fini ; ce qu'elles laissent dans l'image finale figure dans le SBOM des images construites. Les images de Config Sync du test E16 ne tournent pas sur le poste : elles se scannent aussi, au titre de R-32, sans entrer dans l'inventaire.

Pourquoi : un inventaire tenu à la main en double des manifests ferait échouer chaque PR de Renovate ; une liste seulement calculée manquerait les images qu'aucun manifest ne nomme, celles que vise FR-021.

À vérifier avant la seconde PR de l'étape 18 (porteur [DEV], avec [OPS]) : le champ du statut des pods qui porte l'image résolue ; la référence des images préchargées dans le nœud (registre amont, condensat d'index ou de plate-forme) et leur scan par Trivy depuis ce registre ; à défaut, leur export depuis le nœud vers une archive scannée, commande à vérifier.

Sources : spec, FR-021 et entité « Inventaire des images » ; BENCH-004, image du proxy figée dans le binaire du contrôleur ; R-32.

### Relevé du 2026-11-25 : inventaire calculé de la première PR (T114, T116, étape 18)

Fait par [OPS]. `local/scripts/image-inventory.sh lite` réunit l'image du nœud (`local/kind/cluster.yaml`), celle du miroir (`MIRROR_IMAGE` de `local/tasks/local.yml`), les champs `image:` des fichiers vendorés, de `local/platform/` et de `local/data/`, le rendu de `local/k8s/<profil>` quand il existe, et `local/security/unlisted-images`. Le profil standard est refusé jusqu'à l'étape 12, comme dans les contrôles préalables.

Références écrites en entier. Une référence sans hôte se lit comme Docker la lit : `docker.io` quand le premier élément n'a ni point, ni deux-points, ni majuscule et n'est pas `localhost`, `library/` devant un nom d'un seul élément, `index.docker.io` ramené à `docker.io` (`normalize.go` de `distribution/reference` v0.6.0, la version que nomme `go.mod` de Trivy 0.76.2, lignes 126 à 168). L'inventaire écrit `docker.io/kindest/node:...` là où `cluster.yaml` écrit `kindest/node:...`, et une exception nomme toujours le dépôt complet.

Une référence sans condensat dans un fichier vendoré arrête l'inventaire, sauf celles d'une liste fermée du script : `docker.io/envoyproxy/ratelimit`, nommée par étiquette sous `rateLimitDeployment` et lancée seulement si `rateLimit` est posé, ce que S22 refuse sans condensat (ADR-005, condition 1 ; RS-02). Figée un jour par condensat, elle entre d'elle-même.

Rendu. `kubectl kustomize` ne construit aucun client et ne lit aucun kubeconfig : `NewCmdKustomize` ne reçoit que les flux d'entrée et de sortie, sans `Factory` (`staging/src/k8s.io/kubectl/pkg/cmd/kustomize/kustomize.go`, ligne 30, et `pkg/cmd/cmd.go`, ligne 318, de Kubernetes v1.36.6). S19 l'accepte donc sans `--kubeconfig` ni `--context`, à condition que la ligne ne lance aucun autre `kubectl`. Le rendu de `local/k8s/<profil>` n'existe pas sur `main` ; il arrive avec l'étape 8 (T070), et l'inventaire le lit alors, en plus des fichiers de `local/data/` (écart 8 de tasks.md).

Images construites. Une référence sous `saas-b2b.invalid` entre à l'inventaire, mais la première PR ne la scanne pas : elle se scanne dans le job qui la fait tourner, avec la seconde PR (plan, « SBOM et scan des images »).

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://github.com/distribution/reference/blob/v0.6.0/normalize.go> | 2026-11-25 | Domaine par défaut, `library/`, `index.docker.io` |
| <https://github.com/aquasecurity/trivy/blob/v0.76.2/go.mod> | 2026-11-25 | `distribution/reference` v0.6.0 |
| <https://github.com/kubernetes/kubernetes/blob/v1.36.6/staging/src/k8s.io/kubectl/pkg/cmd/kustomize/kustomize.go> | 2026-11-25 | `NewCmdKustomize(streams)`, sans `Factory` |
| <https://github.com/kubernetes/kubernetes/blob/v1.36.6/staging/src/k8s.io/kubectl/pkg/cmd/cmd.go> | 2026-11-25 | Ligne 318 : `kustomize.NewCmdKustomize(o.IOStreams)` |

## RS-25. Authentification de l'exemple

Décision du DSI (2026-11-21) : aucune authentification en local. Elle arrive avec l'ADR-013, qui choisira le fournisseur d'identité après BENCH-012, en cours. Règle : aucun déploiement réel sur GCP sans authentification. La phase 2 n'en fait aucun (décision de Lucas du 2026-11-20).

Pourquoi : l'exemple n'a pas d'utilisateur, et rien n'écoute hors de la boucle locale (FR-003). Sur GCP, la Gateway publierait l'API à tous.

Conséquence à suivre : brancher l'API sur le fournisseur d'identité ajoute du code au-delà de FR-009 (santé, exemple, front). L'ADR-013 demandera donc un amendement de la spec, ou une lecture de Q7 par [PO]. Jusque-là, Keycloak tourne sans être appelé par l'API (RS-15).

## RS-26. Alerte budget GCP (T110)

Décision du DSI du 2026-11-25 (ADR-008, question 1) : une racine OpenTofu séparée, `gcp/budget/`, appliquée à la main avant la racine principale, avec `roles/billing.costsManager` sur le compte de facturation, jamais par la CI, détruite en dernier. Écrit par [OPS] le 2026-11-26 ; [SECU] et [FINOPS] relisent (voir « Choix à relire »).

Sources : la documentation du provider `hashicorp/google` au tag `v8.12.0` (commit `5d2ae61997230ec12262ca575657308dbcbfa70b`), lue par `gh api` ; les pages de Google et d'OpenTofu ci-dessous, lues par WebFetch, c'est-à-dire résumées par un petit modèle à partir de la page : les citations entre guillemets sont celles qu'il a rendues, et chaque point décisif se relit sur la page avant la GATE 2. Rien n'a contacté Google Cloud : aucun plan, aucun apply, aucun identifiant.

### Attributs, d'après la page `google_billing_budget` en 8.12.0

- `billing_account` et `amount` sont requis. L'identifiant du compte s'écrit nu : l'`id` de la ressource est `billingAccounts/{{billing_account}}/budgets/{{name}}`, donc `billing_account` n'a pas le préfixe `billingAccounts/`.
- `amount.specified_amount` : `currency_code` (« If specified, it must match the currency of the billing account »), `units` (une chaîne, les unités entières), `nanos`. `amount.last_period_amount` suit 100 % de la dépense de la période précédente ; la politique le refuse (une dérive d'un mois relèverait son propre plafond).
- `budget_filter.projects` : « A set of projects of the form projects/{project_number} », le numéro et non l'identifiant. « If omitted, the report will include all usage for the billing account, regardless of which project the usage occurred on » : sans filtre, le budget compte tout le compte.
- `budget_filter.calendar_period` (`MONTH`, `QUARTER`, `YEAR`) ou `custom_period` : « Exactly one ... must be provided ». `credit_types_treatment` vaut `INCLUDE_ALL_CREDITS` par défaut.
- `threshold_rules.threshold_percent` : « a 1.0-based percentage, so 0.5 = 50% » ; `spend_basis` vaut `CURRENT_SPEND` par défaut, ou `FORECASTED_SPEND`. L'exemple du provider emploie les deux.
- `all_updates_rule.disable_default_iam_recipients` : « Default recipients are those with Billing Account Administrators and Billing Account Users IAM roles for the target account ». `enable_project_level_recipients` : propriétaires (Owner) du projet, seulement si le budget n'a qu'un projet ; non employé ici.
- Aucun argument `labels` sur le budget lui-même (`budget_filter.labels` filtre la consommation par étiquette, il n'étiquette rien) : les étiquettes `owner`, `env` et `ttl` de R-05 n'ont pas d'objet dans cette racine.
- Avertissement de la page : avec les identifiants d'un utilisateur, il faut `billing_project` et `user_project_override = true` dans le provider, « Otherwise the Billing Budgets API will return a 403 error », et `serviceusage.services.use` sur ce projet. Page du provider : `billing_project` « is ignored if `user_project_override` is set to false or unset ».
- Délais par défaut de 20 minutes pour create, update et delete ; `deletion_policy` vaut `DELETE` par défaut, donc `tofu destroy` du budget est permis.

### Faits de Google

- Rôles (page des rôles de facturation) : `roles/billing.costsManager`, « Manage budgets for a billing account, and view, analyze, and export cost information of a billing account », porte `billing.budgets.create`, `delete`, `get`, `list` et `update`. `roles/billing.admin` porte les mêmes et `billing.budgets.configureSpendCap`. `roles/billing.user` n'en porte aucune. `billing.resourcebudgets.write` est portée par `roles/admin`, `roles/owner`, `roles/writer` et `roles/editor`, et par un rôle d'agent de service. La relève de [SECU] se confirme pour Owner et Editor.
- Précision sur cette relève : la page des budgets rattache `billing.resourcebudgets.write` à la création d'un budget de portée projet (avec `resourcemanager.projects.get` et `billing.resourcebudgets.read`), et `billing.budgets.create` à celle d'un budget de portée compte de facturation, ce que crée `google_billing_budget` (ressource `billingAccounts/.../budgets`). Les pages lues ne disent pas quels rôles de base portent `billing.budgets.*`. La séparation tient sans cette réponse : la politique refuse les six rôles dans tout IAM du dépôt.
- Rôles de base : « The legacy basic roles are Owner (`roles/owner`), Editor (`roles/editor`), and Viewer (`roles/viewer`) » ; « In production environments, do not grant basic roles unless there is no alternative ».
- Budgets : seuils par défaut « 50%, 90%, and 100% of the budget amount », sur la dépense réelle. Alerte prévue : envoyée quand le coût prévu atteint le seuil à la fin de la période calendaire courante ; « Budgets configured for a custom time range cannot trigger alerts on » le coût prévu ; la page ne donne aucun historique minimal pour la prévision (inconnu). « The budget doesn't automatically set a hard cap on spending » ; « it may take several hours before receiving the first email or Pub/Sub notification ». Destinataires par défaut : les administrateurs et les utilisateurs du compte de facturation. Les périodes calendaires commencent à minuit, heure du Pacifique (UTC-8).
- API REST : `CreditTypesTreatment` `EXCLUDE_ALL_CREDITS` ajoute les crédits au coût net, donc compte le coût brut ; `FORECASTED_SPEND` « can only be set when the budget's time period is a » période calendaire, et pas avec `custom_period`.
- Service : `billingbudgets.googleapis.com`, à activer « in the project you are using to call the Cloud Billing Budget API », permission `serviceusage.services.enable` ; l'API est « free to use ».
- Identifiant du compte de facturation : « an 18-character alphanumeric value » ; les trois groupes de six viennent de l'exemple `010101-F0FFF0-10XX01`, pas d'une règle écrite. La validation de `billing_account_id` s'appuie sur cet exemple.

### OpenTofu

- Backend `gcs` : `prefix`, « GCS prefix inside the bucket. Named states for workspaces are stored in an object called `<prefix>/<name>.tfstate` » ; `bucket` est requis. La page ne dit pas où va l'espace de travail par défaut.
- Configuration partielle : « You do not need to specify every required argument in the backend configuration » ; si les réglages viennent de plusieurs endroits, ils sont fusionnés et « any command-line options override the settings in the main configuration ». Donc `bucket` à l'init, `prefix` écrit dans le bloc, et un `-backend-config` qui poserait `prefix` écraserait le bloc sans qu'aucun fichier le montre : le README de la racine l'interdit, S15 ne le voit pas.
- Essais, OpenTofu 1.13.9 (darwin_arm64), environnement vidé (`env -i`, `HOME` et `TF_DATA_DIR` temporaires) : `tofu fmt -check`, `tofu init -backend=false -lockfile=readonly` et `tofu validate` passent sur `gcp/budget/` ; `tofu validate` ne construit pas la clé KMS (RS-16). Le verrou de `gcp/budget/` reprend le bloc `google` de celui de `gcp/tofu/` ; `tofu providers lock` des quatre plateformes (linux et darwin, amd64 et arm64), lancé sur une copie, donne un fichier identique à octet près. Trivy 0.76.2, règles embarquées, mêmes options que S15 : aucune alerte sur `gcp/budget/`. conftest : 54 tests du paquet `tofu_budget` et ses 15 cas d'échec refusés, chacun par le message attendu ; les deux racines passent le paquet.

### Choix à relire

- Seuils : 50, 90 et 100 % de la dépense réelle, plus 100 % de la dépense prévue. Les trois premiers sont les seuils par défaut de la console. 50 % laisse du temps à mi-mois, 90 % est le dernier moment pour agir, 100 % constate le dépassement. Le quatrième est le seul qui prévient avant la dépense : les coûts arrivent en retard à la facturation et la première alerte peut venir des heures plus tard, donc une alerte sur la seule dépense réelle arrive après un emballement. Le provider le permet (`spend_basis = "FORECASTED_SPEND"`) à condition d'une période calendaire, d'où `calendar_period = "MONTH"`.
- Crédits : `credit_types_treatment = "EXCLUDE_ALL_CREDITS"`, écrit. Avec le défaut, un essai gratuit ou une promotion masque la dépense : un compte neuf ne sonnerait jamais. [FINOPS] peut préférer le net.
- Destinataires : par défaut, les administrateurs et utilisateurs du compte de facturation, aucun `all_updates_rule`. Qui s'y trouve n'est pas lisible ici.
- `google_project_service` pour `billingbudgets.googleapis.com`, `disable_on_destroy = false` comme dans `gcp/tofu/apis.tf` : sans l'API sur le projet qui appelle, le premier appel échoue.
- Préfixes d'état `budget` et `main`, écrits en littéral dans les deux racines : `gcp/tofu/versions.tf` gagne `prefix = "main"` (sa configuration partielle laissait le préfixe à l'init), pour que S15 puisse montrer la différence. Le seau reste à l'init.
- Politique `tofu_budget` : refuse `roles/owner`, `roles/editor`, `roles/admin`, `roles/writer`, `roles/billing.admin` et `roles/billing.costsManager` dans toute ressource ou source IAM des deux racines, ainsi qu'un rôle qui n'est pas écrit en clair. Elle ne voit pas un rôle personnalisé qui porterait `billing.budgets.*` ou `billing.resourcebudgets.write`, ni un rôle accordé hors du dépôt.

### Reste à lever au premier apply autorisé par Lucas

- Que l'alerte part bien aux destinataires par défaut sans `all_updates_rule` (la page de Google le décrit, rien ne l'a essayé).
- Que `projects/<numéro>` et la devise du compte sont acceptés par l'API.
- Que l'activation de l'API et l'appel du budget passent dans le même apply avec les identifiants de l'utilisateur.
- Le seuil de prévision sur un projet jeune : historique de prévision inconnu, la page ne donne pas d'historique minimal, à constater au premier apply autorisé, porteur [FINOPS]. D'ici là, seuls les trois seuils sur le réel sont fiables.
- Que `project_number` est celui du projet de `gcp/tofu/` : rien ne le recoupe hors ligne, et un numéro d'un autre projet ferait suivre au budget une autre dépense. À vérifier par la personne qui applique, avant le premier apply.
- Renovate : son gestionnaire `terraform` lit `**/*.tf` et le verrou (RS-16), donc suit `gcp/budget/` sans règle de plus ; la montée d'un provider présent dans les deux verrous devrait tenir en une seule PR. Aucun Renovate n'a tourné sur cette racine.

| Source | Lue le | Ce qu'on y prend |
| --- | --- | --- |
| <https://github.com/hashicorp/terraform-provider-google/blob/v8.12.0/website/docs/r/billing_budget.html.markdown> | 2026-11-26 | Arguments, valeurs, avertissement du quota project, exemples |
| <https://github.com/hashicorp/terraform-provider-google/blob/v8.12.0/website/docs/guides/provider_reference.html.markdown> | 2026-11-26 | `billing_project`, `user_project_override` |
| <https://docs.cloud.google.com/iam/docs/roles-permissions/billing> | 2026-11-26 | `roles/billing.costsManager`, `roles/billing.admin`, `roles/billing.user`, porteurs de `billing.resourcebudgets.write` |
| <https://docs.cloud.google.com/iam/docs/roles-overview> | 2026-11-26 | Rôles de base, mise en garde en production |
| <https://docs.cloud.google.com/billing/docs/how-to/budgets> | 2026-11-26 | Seuils, prévision, destinataires, absence de plafond, délai, permissions par portée |
| <https://docs.cloud.google.com/billing/docs/reference/budget/rest/v1/billingAccounts.budgets> | 2026-11-26 | `creditTypesTreatment`, `calendarPeriod`, `spendBasis` |
| <https://docs.cloud.google.com/billing/docs/reference/budget/rest> | 2026-11-26 | Nom du service `billingbudgets.googleapis.com` |
| <https://docs.cloud.google.com/billing/docs/how-to/budget-api-setup> | 2026-11-26 | Activation de l'API sur le projet appelant, gratuité |
| <https://docs.cloud.google.com/billing/docs/how-to/find-billing-account-id> | 2026-11-26 | Format de l'identifiant du compte de facturation |
| <https://opentofu.org/docs/language/settings/backends/gcs/> | 2026-11-26 | `prefix`, `bucket` requis |
| <https://opentofu.org/docs/language/settings/backends/configuration/> | 2026-11-26 | Configuration partielle, fusion, priorité de la ligne de commande |

## Synthèse des points à vérifier

| Point | Porteur | Étape bloquée |
| --- | --- | --- |
| Versions du front, des frameworks de test, de Task, conftest, kubeconform, cosign, provider `random`, Npgsql, client du cache | [DEV] | 1 à 19, chacun à son entrée |
| Correspondance par préfixe de chemin dans le cœur de Gateway API et chez GKE | [DEV] | 7 |
| Composants de Kustomize dans la version qu'embarque kubectl | [DEV] | 7 |
| TLS vers la base | [DEV], [SECU] | 8 |
| Moteur du cache, local et Memorystore, et son authentification : BENCH-014 puis ADR-015 | [BENCH], [ARCHI] | 19 et 20, donc 9 et la suite du profil lite |
| Mot de passe du cache sans argument ; TLS vers le cache ; RESP pour toutes les options de BENCH-014 | [DEV], [SECU], [BENCH] | 19 |
| Nom sous `.invalid` avec `kind load` | [OPS] | 9 |
| Lecture de la mémoire déclarée par le moteur | [DEV] | 5 |
| Comportement de GitHub, Renovate, release-please et actionlint face au sous-dossier ; contrôles requis d'un workflow filtré par chemin ; runners | [OPS] | 1, 2, 18 |
| Validation OpenTofu hors ligne, verrou multi-plateformes, attributs des activations | [OPS] | 13 |
| Emplacement du kubeconfig | [SECU] | 6 |
| Montages de zot à plusieurs amonts | [OPS] | 12, ou 19 selon le registre du cache |
| `Kustomization` suspendue sans objet source ; interrogation des droits d'un compte de service | [DEV] | 12 |
| Trivy : documentation de 0.76.2, code de sortie sans base, lecture des images construites, rapport JSON ; cosign pour son bundle | [DEV], [SECU] | 18 |
| conftest : fichier de données et date passée en donnée | [DEV] | 18 |
| Image résolue dans le statut des pods ; images préchargées du nœud et leur scan | [DEV], [OPS] | 18, seconde PR |
