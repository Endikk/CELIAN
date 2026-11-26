# Golden repo SaaS B2B

Projet de référence du blueprint SaaS B2B de CELIAN, construit à la main avant toute mise en template. Il contient une API .NET réduite à deux contrôles de santé et à un exemple de notes, un front React, Postgres et un cache Valkey, pour deux cibles : un cluster kind sur le poste et GCP. Une seule commande, `task up`, démarre tout sur un poste.

## État

Le profil lite démarre de bout en bout. `task up` crée le cluster kind, le miroir de registres, la plate-forme Envoy Gateway, la base, le cache, l'API et le front, puis attend que tout réponde. `task reload`, `task down`, `task app:down` et `task mirror:purge` sont livrés. La cible GCP est du code OpenTofu vérifié sans identifiant cloud, et rien ne la déploie.

Ce qui manque encore est signalé dans le texte, avec l'étape de la [spécification](../../specs/001-golden-repo-saas-b2b/spec.md) qui le livre.

## Prérequis de `task up`

Le dépôt demande un moteur de conteneurs local et quatre autres outils. `task up` vérifie les points du second tableau avant de créer quoi que ce soit, dans l'ordre du tableau, et s'arrête au premier qui manque en donnant ce qu'il a trouvé et ce qu'il attend. La section « Dépannage » reprend chaque refus.

### Outils

| Outil | Version | Licence | Lu le | Source |
| --- | --- | --- | --- | --- |
| Docker Engine | 28.0.0 ou plus, sous Linux | Apache-2.0 | 2026-11-26 | <https://docs.docker.com/engine/> |
| kind | 0.33.0 exactement | Apache-2.0 | 2026-11-26 | <https://github.com/kubernetes-sigs/kind> |
| kubectl | 1.35 à 1.37 | Apache-2.0 | 2026-11-26 | <https://kubernetes.io/releases/version-skew-policy/> |
| Task | 3.54.0 | MIT | 2026-11-26 | <https://github.com/go-task/task> |
| Git | aucune version exigée | GPL-2.0 | 2026-11-26 | <https://git-scm.com/about> |

Docker Engine passe en premier parce que c'est le moteur libre. Les versions viennent des fichiers du dépôt : `local/scripts/lib/preflight-checks.sh` pour kind et Docker Engine, `platform.yaml` pour la mineure de kubectl (celle du cluster, 1.36, à une mineure près), `tests/tools/install.sh` pour Task. La CI de CELIAN installe kubectl v1.36.6. Le poste de mesure fait tourner Docker 29.8.2 et kubectl v1.37.1 (relevé du 2026-11-24).

Sous macOS, le moteur tourne dans une machine virtuelle, et aucun moteur libre n'est validé sous macOS pour l'instant : le risque R-26 reste ouvert, et un benchmark de Colima et de Podman est prévu avant la phase 6. Le poste de mesure utilise OrbStack, qui n'est pas libre. Docker Desktop est payant pour une entreprise de plus de 250 salariés ou de plus de 10 millions de dollars de chiffre d'affaires annuel (page de Docker lue le 2026-11-26). Podman est documenté par kind, mais personne ne l'a évalué ici, et sous Linux la règle des 28.0.0 le refuserait : il répond derrière `docker` avec sa propre version.

Les licences viennent des pages citées et des dépôts officiels, lus à la date du tableau. L'API de GitHub ne tranche pas la licence de Git (réponse NOASSERTION) : la page de Git fait foi.

kubectl s'installe par la page officielle (<https://kubernetes.io/docs/tasks/tools/>) ; le fichier `.sha256` publié à côté du binaire sert à vérifier la somme.

### Contrôles de `task up`

| Contrôle | Attendu |
| --- | --- |
| Moteur de conteneurs | local, joint par la commande `docker` à travers un socket unix (un contexte `tcp://` ou `ssh://`, ou `DOCKER_HOST` vers une autre machine, est refusé) ; `docker info` répond en moins de 10 s |
| kind | 0.33.0 exactement (ADR-004) |
| kubectl | 1.35 à 1.37, une mineure autour de celle du cluster, 1.36 dans `platform.yaml` (ADR-006) |
| Docker Engine, sous Linux seulement | 28.0.0 ou plus (ADR-011) |
| Mémoire déclarée par le moteur | 2048 Mio pour le profil lite, 2560 Mio pour le standard. Sous macOS, elle désigne la mémoire de la machine virtuelle du moteur (ADR-004) |
| Ports de l'hôte | libres en 127.0.0.1 : 18080 pour HTTP, 18443 pour HTTPS |

À venir (étape 7, seconde PR) : `openssl` et `awk` rejoignent les prérequis, pour fabriquer et lire le certificat de la gateway. Le contrôle préalable les cherche et les nomme s'ils manquent, avant toute création.

### Outils de `task check`

`task check` demande Task, conftest, OpenTofu et Trivy. `tests/tools/install.sh <dossier>` les installe dans le dossier donné, après avoir vérifié le SHA-256 de chaque archive contre `tests/tools/SHA256SUMS`. Le dossier se met ensuite dans le `PATH`. `task test` demande Docker : les tests de l'API et du front tournent dans leurs images de construction, sans SDK .NET ni Node.js sur le poste.

| Outil | Version | Licence | Lu le | Source |
| --- | --- | --- | --- | --- |
| conftest | 0.71.1 | Apache-2.0 | 2026-11-23 | <https://github.com/open-policy-agent/conftest/blob/v0.71.1/LICENSE> |
| OpenTofu | 1.13.9 | MPL-2.0 | 2026-11-26 | <https://github.com/opentofu/opentofu> |
| Trivy | 0.76.2 | Apache-2.0 | 2026-11-23 | <https://github.com/aquasecurity/trivy> |

### Installer kind

Installez kind 0.33.0 depuis la page officielle (<https://kind.sigs.k8s.io/docs/user/quick-start/>, lue le 2026-11-26), puis comparez la somme SHA-256 du binaire à ce tableau avant de le lancer. Les sommes sont celles du catalogue de CELIAN (`catalog/kubernetes-cluster.yaml`, relevées le 2026-11-19). La somme que kind publie dans la même release ne protège que de la corruption : qui remplace le binaire remplace aussi cette somme. Le tableau, versionné ici, garde l'autre copie.

| Plateforme | SHA-256 |
| --- | --- |
| darwin-arm64 | `0c8c7dbe5e23594a198b786c4bc13dacc101fa6196b0cb0b23a1ca44e61f4b4f` |
| darwin-amd64 | `5a99f26f57246dc9319dd294803313197a0f34d33c525b3ea8b655db5916ece0` |
| linux-amd64 | `aee6151561422756b764a4ae28e7f44cda5af5a9eead3cc9985112b1de8d8e0d` |
| linux-arm64 | `20022bee6cfcd5086cb7234d218e3454e6090022f2a8f55d1fa7fcf42c3867a2` |

```text
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.33.0/kind-darwin-arm64
shasum -a 256 ./kind
```

Remplacez `darwin-arm64` par votre plateforme, et `shasum -a 256` par `sha256sum` sous Linux. Si la somme affichée diffère de celle du tableau, supprimez le fichier. Sinon, `chmod +x ./kind`, puis déplacez-le dans un dossier du `PATH`. `task up` compare ensuite la version de `kind version`, et s'arrête sur tout autre numéro que 0.33.0.

### Profil et mémoire

Le profil se choisit sur la mémoire que déclare le moteur, lue par `docker info`. La mémoire physique du poste ne compte pas. `PROFILE=lite task up`, ou `task up PROFILE=lite`, force un profil sous les mêmes contrôles. kind n'a aucun réglage de mémoire par nœud : les deux seuils sont des planchers de contrôle, le cluster n'est pas bridé. Ce que déclare une machine virtuelle réglée à 2,0 Gio n'est pas mesuré : si elle déclare moins de 2048 Mio, `task up` la refuse.

## Démarrer

```text
task up
```

Depuis la racine du dépôt, `task up` enchaîne : contrôles préalables, cluster, miroir de registres, namespace et Secrets, plate-forme, images de l'API et du front, application, base, cache, attente de « prêt ». Chaque étape imprime `Step <nom>: <n> s.`, la dernière ligne de durée est `Total: <n> s.`, et la taille du volume du miroir suit. Relancé, il reprend l'environnement : rien n'est recréé, les Secrets et les données sont gardés.

Le premier démarrage demande le réseau : il tire les images, que le miroir sert ensuite. Sur le poste de mesure (Mac arm64, OrbStack, Docker 29.8.2, kind 0.33.0, mesure du 2026-11-26), un premier `task up` avec le cache de construction du moteur et l'image de nœud déjà présents a duré 85 s, un démarrage à chaud 25 s, et le volume du miroir pesait 301,2 MB. Un poste sans cache de construction n'est pas mesuré. Les durées ne sont pas une promesse : elles dépendent du poste, du réseau et des registres.

À venir (étape 10) : le test du redémarrage sans réseau après un premier démarrage, et le message qui nomme le registre quand un tirage échoue ou se voit limité.

## Ce que vous voyez, et où

`task up` finit par deux lignes :

```text
Front: http://localhost:18080/
API: http://localhost:18080/api/
```

Le port est publié sur 127.0.0.1 seulement, et rien n'écoute ailleurs que sur la boucle locale. Les routes de la gateway nomment l'hôte `localhost`, parce que Gateway API refuse une adresse IP dans `hostnames`. Une requête qui porte un autre `Host` reçoit 404, ce qui ferme la voie du rebinding DNS. Le port n'est pas publié en IPv6 : le navigateur doit résoudre `localhost` vers 127.0.0.1, ou y retomber. Cela a été essayé en bash, pas dans un navigateur.

Le front affiche l'écran Notes : un formulaire d'ajout avec son état de chargement et ses erreurs par champ, la dernière note lue avec sa provenance (« Served from the cache » ou « Served from the database »), et la liste des notes les plus récentes. Les textes de l'écran sont en anglais, comme ceux des erreurs de l'API.

| Route | Rôle |
| --- | --- |
| `GET /api/healthz` | processus vivant ; ne touche ni la base ni le cache |
| `GET /api/readyz` | 200 si la base et le cache répondent, 503 sinon, sans détail de l'erreur |
| `POST /api/notes` | écrit une note de 1 à 500 caractères ; 201, 400, 413 au-delà de 16 Kio, 415 hors JSON |
| `GET /api/notes/{id}` | lit une note par le cache d'abord ; `servedFrom` vaut `cache` ou `database` |
| `GET /api/notes?limit=<n>` | liste de 1 à 50 notes, de la plus récente à la plus ancienne, depuis la base |

Le cluster a son propre kubeconfig, `$HOME/.kube/kind-saas-b2b`, contexte `kind-saas-b2b`, namespace `saas-b2b`. Les commandes du dépôt les nomment toujours, et ne touchent jamais le kubeconfig par défaut de l'utilisateur :

```text
kubectl --kubeconfig "$HOME/.kube/kind-saas-b2b" --context kind-saas-b2b --namespace saas-b2b get pods
```

## Commandes

Une tâche qui manipule un secret n'affiche ni ses commandes ni ses valeurs. Une erreur tient en une phrase qui dit ce qui manque et quoi faire, avec un code de sortie non nul. Aucune commande ne contacte un cluster cloud ni un service payant.

| Commande | Effet |
| --- | --- |
| `task up` | démarre ou reprend l'environnement local |
| `task reload` | reconstruit et recharge l'API et le front dont les sources ont changé ; la base et ses données ne sont pas touchées |
| `task down` | retire le conteneur du miroir, puis le cluster ; garde le volume du miroir et dit ce qui reste sur le poste |
| `task app:down` | garde le cluster ; retire le miroir, puis le namespace de l'application avec la base, son volume et ses Secrets |
| `task mirror:purge` | retire le volume du miroir ; le `task up` suivant demande le réseau |
| `task check` | contrôles statiques de toutes les couches, OpenTofu compris, et contrôles préalables joués contre des binaires simulés ; ni cluster ni identifiant cloud |
| `task test` | tests unitaires de l'API, du front et de la décision du scan ; demande Docker |
| `task test:e2e` | tests sur kind du profil courant ; le cluster est créé, puis supprimé |
| `task gcp:validate` | formate, initialise contre le verrou et valide la racine OpenTofu de `gcp/tofu/`, sans backend ni identifiant |
| `task gcp:policy` | politiques conftest sur le HCL et les manifests de la couche `gcp` |
| `task gcp:scan` | Trivy sur le HCL |

`task test:e2e` refuse de démarrer, en nommant ce qui existe, si le cluster `saas-b2b`, le conteneur `saas-b2b-mirror` ou le volume `saas-b2b-mirror` sont déjà là : il ne retire jamais ce qu'il n'a pas créé. Mesure du 2026-11-26 sur le poste de mesure : 18 tests en 715 s.

À venir (étape 10) : `task test:offline`, le test du redémarrage sans réseau. À venir (étape 18) : `task test:images`, le relevé des images en marche, le SBOM des images construites et le scan de l'inventaire du profil courant.

## Profils lite et standard

| Profil | Mémoire déclarée par le moteur | Contenu |
| --- | --- | --- |
| lite | 2048 Mio | kind, miroir de registres, Envoy Gateway, Postgres, cache, API, front |
| standard | 2560 Mio | le lite, plus Keycloak, Mailpit et Flux |

À venir (étape 12) : le profil standard. Il est reconnu puis refusé : sur un moteur qui déclare 2560 Mio ou plus, `task up` sans `PROFILE` s'arrête en le disant, et `PROFILE=lite task up` permet d'avancer.

À venir (étape 17) : la mesure du nœud avec toute la pile, qui peut changer les deux seuils.

Les données de la base survivent à `task reload` et au retrait d'un pod. Ce dépôt ne promet rien sur les données après un redémarrage du nœud, quand le poste ou le moteur redémarre, que le cluster est gardé et que `task up` le reprend. `task down` et `task app:down` les suppriment avec le volume.

## Couches et cibles

Une couche de cible tient dans un seul dossier. Tout ce qui est hors de `local/` et de `gcp/` appartient à la couche commune, identique sur les deux cibles. Le détail est dans le [contrat des couches](../../specs/001-golden-repo-saas-b2b/contracts/layers.md).

| Chemin | Couche | Contenu |
| --- | --- | --- |
| `local/` | `local` | kind, miroir de registres, plate-forme, données, tâches de démarrage |
| `gcp/` | `gcp` | OpenTofu, manifests de liaison et de secrets de GKE |
| tout le reste | commune | code de l'application, base et overlays Kustomize, conventions Git, README, tests et politiques communs |

La couche commune ne nomme aucun outil ni aucun fournisseur. Seule `local/` nomme kind, Envoy Gateway, zot ou Flux, et seule `gcp/` nomme un service de Google. Le contrôle S07 rend la couche commune, puis chaque cible, et refuse tout écart hors de la couche de cible, sauf `gatewayClassName` et `hostnames`.

Sur un cloud, la constitution de CELIAN laisse l'entretien choisir le mode d'hébergement de chaque brique : service managé, composant libre auto-hébergé, ou un mélange. Le golden repo construit une seule variante sur `gcp`, la variante managée : GKE Autopilot, Cloud SQL, Memorystore for Valkey et Secret Manager. Les variantes auto-hébergées n'y sont pas construites.

## Écarts entre les cibles

Liste tenue au fil des étapes (ENF-02). Seule la couche de cible change entre le poste et GCP, et ce tableau dit ce qui reste différent.

| Écart | Sur le poste | Sur GCP | Suivi |
| --- | --- | --- | --- |
| Privilèges de l'utilisateur de `db-auth` | propriétaire de la base `app`, sans autre attribut | membre de `cloudsqlsuperuser` : `CREATEROLE`, `CREATEDB`, triggers d'événement, réplication logique | R-39 ; vérifié au premier déploiement, durci après le MVP par un ADR |
| Secret `db-superuser` | existe, lu par le conteneur Postgres seulement, jamais par l'application | aucun : Cloud SQL ne donne pas de superutilisateur | ADR-012 ; Secret de couche, hors de la comparaison de parité |
| Mode de connexion à la base, `DATABASE_SSL_MODE` | `Disable` : le serveur local n'a pas TLS | `VerifyCA`, avec l'autorité de l'instance | À venir (étape 14) : le contrôle qui refuse `Disable`, `Allow`, `Prefer` et `Require` sur `gcp` |
| Version de Postgres | majeure 18 des deux côtés (`platform.yaml`) ; mineure 18.7 | mineure 18.6 sur Cloud SQL le 2026-11-20 | écart de mineure admis (ADR-012) |
| Sauvegarde, haute disponibilité, montée de majeure | aucune | sauvegardes de Cloud SQL activées | ADR-012, ADR-008 |
| Version de Kubernetes | mineure 1.36 (`platform.yaml`), image de nœud v1.36.4 | mineure 1.36, canal Regular | écart de correctif admis : GKE avance dans son canal (ADR-004) |
| Gateway | Envoy Gateway, CRD Gateway API v1.7.0 | GKE sert v1.5.0 à v1.6.0 selon sa version (ADR-005, relevé du 2026-11-19) | la couche commune n'emploie que des champs que GKE sert (ADR-005) ; À venir (étape 14) : la classe de GKE |
| Hôte des routes | `localhost` | domaine de la spécification | À venir (étape 14) |
| Certificat de `gateway-tls` | auto-signé, fabriqué par `task up` | à trancher avec la classe de GKE | À venir (étape 7, seconde PR) ; l'autorité de ce certificat n'entre jamais dans le magasin de confiance du poste |
| Secrets de l'application | créés par `task up` à partir de `/dev/urandom` | synchronisés depuis Secret Manager par GKE | ADR-007 |
| Cache : moteur | Valkey 9.1.4 dans le cluster, sans persistance | Memorystore for Valkey, ligne 9.1, un nœud sans réplica | le correctif servi par Memorystore n'est pas publié (ADR-015) |
| Cache : chiffrement, commandes, mémoire | pas de TLS, ACL plus stricte, `maxmemory 64mb` | TLS, liste de commandes bloquées de Memorystore, mémoire du type de nœud | le poste est plus strict, jamais moins (ADR-015) |
| GitOps | Flux, en profil standard | Config Sync | À venir (étape 12) |

Le cache ne persiste rien sur les deux cibles : ses données se perdent au redémarrage du pod sur le poste, et Memorystore n'a ni persistance ni sauvegarde. L'API n'a pas d'authentification : elle arrive avec l'ADR-013, et aucun déploiement réel sur GCP ne se fait sans elle.

## Couche GCP

`gcp/tofu/` décrit la cible GCP en OpenTofu : réseau privé, GKE Autopilot, Cloud SQL, Memorystore for Valkey, Artifact Registry, Secret Manager, Config Sync et identité de la CI par fédération. `gcp/budget/` est une racine à part qui porte l'alerte budget du projet. Elle prévient, elle ne plafonne rien, et les coûts arrivent en retard à la facturation. Son README dit comment l'appliquer : à la main, avant la racine principale, par une identité distincte, et la détruire en dernier.

Rien dans ce dépôt ne déploie la cible GCP. Aucune tâche et aucun workflow ne lance de plan, d'apply ni de destroy, et S17 le vérifie. `task gcp:validate`, `task gcp:policy` et `task gcp:scan` tournent sans identifiant cloud, et `task check` les lance aussi. Une action payante, création de ressources comprise, attend l'accord explicite de Lucas et un budget validé.

À venir (étape 20, seconde PR) : le jeton d'authentification de Memorystore et son secret dans Secret Manager. La ressource qui le crée n'est dans aucune release du provider figé, `google` 8.12.0 le 2026-11-26. La procédure de rotation s'écrit avec la seconde PR ; l'ordre prévu, que [SECU] doit relire, est de déclarer le second jeton, de basculer les clients, puis de retirer l'ancien.

### Démontage en deux temps

Trois protections empêchent un `tofu destroy` direct : `deletion_protection` du cluster GKE, `deletion_protection` et `deletion_protection_enabled` de l'instance Cloud SQL, `deletion_protection_enabled` de l'instance Memorystore. Sans démontage, le cluster et les instances restent et facturent (R-15).

Une personne lance chaque temps, jamais la CI ni un agent, et aucune tâche du dépôt ne les contient. Premier temps : elle lève les protections, en passant ces réglages à `false` dans le code, puis un `tofu apply` de la racine principale. À venir (étape 17) : une variable de protection, vraie par défaut, remplacera cette édition du code. Second temps : elle lance `tofu destroy` sur la racine principale, puis sur `gcp/budget/`.

Le lendemain, elle relit le rapport de facturation filtré sur le projet, parce que les coûts arrivent en retard : c'est ce contrôle qui montre ce qui a survécu. Certaines ressources n'ont pas d'étiquette, donc le filtre par projet les voit et le filtre par étiquette les manque : les activations d'API (`google_project_service`), le réseau, le sous-réseau, et le point de terminaison Private Service Connect que le service crée lui-même, dont l'héritage des étiquettes n'est pas vérifié.

## Sécurité

### Secrets

Les Secrets du cluster local sont en clair dans etcd : kind ne chiffre rien au repos, et leurs valeurs survivent au redémarrage du nœud (R-28, mesures du 2026-11-19). Le kubeconfig du projet donne l'administration du cluster à tout processus du poste qui peut le lire. N'y mettez jamais une valeur réelle, copie d'un secret de GCP ou clé d'un service tiers. Une clé de test d'un service tiers se saisit par l'entrée standard, jamais dans un fichier du dépôt.

Ce qui limite le risque : `task up` tire chaque mot de passe au hasard, 40 caractères alphanumériques de `/dev/urandom`, une fois par environnement neuf. Il passe chaque Secret par un tube vers `kubectl create`, seulement s'il manque, sans valeur dans un fichier, une variable de Task ni un argument. Aucun Secret n'est versionné.

| Secret | Clés | Lu par |
| --- | --- | --- |
| `db-auth` | `username` (`app`), `password` | l'API, par fichiers montés sous `/run/secrets/db-auth` |
| `cache-auth` | `password` | l'API, sous `/run/secrets/cache-auth` ; le conteneur d'initialisation du cache |
| `db-superuser` | `username`, `password` | le conteneur Postgres seulement |

À venir (étape 7, seconde PR) : le Secret `gateway-tls`, certificat auto-signé de la gateway. Ne l'installez jamais dans le magasin de confiance du poste : un navigateur qui ferait confiance à cette autorité la ferait pour tout le poste.

### Recherche de secrets et scan

gitleaks tourne en pre-commit et dans `secrets.yml` sur tout l'historique Git, avec `detect-private-key`. Trivy scanne le HCL (`task gcp:scan`). Dans CELIAN, le job `scan-images` scanne les images du profil lite au seuil HIGH. Les images construites par le projet et celles de `gcp` bloquent ; les images tierces du cluster local sont signalées dans le résumé du job sans le faire échouer. La classe de chaque image est dans `security/scan-policy.yaml`, les exceptions datées dans `security/scan-exceptions.yaml`.

À venir (étape 18) : le SBOM de chaque image construite, lisible par machine, gardé comme artefact de la CI.

### Mises à jour

Renovate propose les mises à jour d'une version publiée depuis 7 jours au moins ; un correctif de sécurité passe sans ce délai si sa PR passe toute la matrice. Les images de ghcr.io, quay.io et mcr.microsoft.com n'ont pas de date de publication que Renovate sait lire (ADR-016) : leurs mises à jour attendent que la personne qui maintient le projet coche l'approbation sur le tableau de bord de Renovate, après avoir lu la date de publication amont. Jamais un agent. Les actions et les hooks sont figés par SHA, avec le tag en commentaire.

## Intégration continue

Les workflows du projet généré sont dans `.github/workflows/`.

| Workflow | Rôle |
| --- | --- |
| `checks.yml` | `task check` et `task test`, sur chaque PR et sur `main` |
| `ci.yml` | tous les hooks pre-commit sur tous les fichiers, le validateur de configuration de Renovate, commitlint sur le titre de la PR |
| `secrets.yml` | gitleaks sur tout l'historique |
| `release-please.yml` | versions et `CHANGELOG.md`, sur `main` |

Le dépôt porte ses propres conventions Git : Conventional Commits vérifiés par commitlint, hooks pre-commit, Renovate, release-please. Dans une copie autonome du dossier, `pre-commit install` pose les hooks ; dans CELIAN, ce sont ceux de CELIAN qui s'appliquent, et le contrôle X01 exerce ceux-ci dans une copie.

Dans CELIAN, le workflow `golden-saas-b2b.yml` lance en plus `e2e-lite`, qui joue `task test:e2e` sur un runner, `scan-images`, `envoy-render` et `export`. Les workflows du projet généré ne les lancent pas encore : ils n'installent ni kind avec une somme vérifiée ni le scan. Sur un projet privé, un job qui crée un cluster le crée à froid et consomme des minutes de CI.

## Démonter l'environnement local

`task down` retire le conteneur du miroir, après contrôle de son nom, de son étiquette et de son image, puis supprime le cluster. Il garde le volume du miroir et affiche ce qui reste sur le poste : le volume et sa taille, les images du cache du moteur (nœud, miroir, images de base des constructions) et la commande qui les retire (`docker image rm`). `task app:down` garde le cluster et supprime l'application avec sa base. `task mirror:purge` retire le volume du miroir, et le `task up` suivant demande le réseau.

## Dépannage

Chaque refus de `task up` dit ce qu'il a trouvé et rien n'est créé avant lui. Les messages sont en anglais, comme le code.

| Le message contient | Cause | Remède |
| --- | --- | --- |
| `no container engine found` | la commande `docker` n'est pas dans le `PATH` | installer un moteur de conteneurs qui la fournit |
| `the container engine does not answer` ou `gave no answer` | le moteur est arrêté, ou ne répond pas en 10 s | le démarrer ou le redémarrer, puis relancer `task up` |
| `DOCKER_HOST points docker at` | `DOCKER_HOST` désigne un autre moteur que le socket local | `unset DOCKER_HOST` |
| `DOCKER_CONTEXT selects the docker context` ou `the docker context ... points at` | le contexte courant n'est pas un socket unix local | `unset DOCKER_CONTEXT`, ou `docker context use default` |
| `KIND_EXPERIMENTAL_PROVIDER=...` | kind créerait le cluster avec un autre moteur que docker | `unset KIND_EXPERIMENTAL_PROVIDER` |
| `KIND_EXPERIMENTAL_DOCKER_NETWORK=...` | les nœuds iraient sur un autre réseau que `kind`, où tourne le miroir | `unset KIND_EXPERIMENTAL_DOCKER_NETWORK` |
| `kind is not installed` ou `kind ... found, 0.33.0 expected` | kind absent ou d'une autre version | installer kind 0.33.0 (section « Installer kind ») |
| `kubectl is not installed` ou `kubectl ... found` | kubectl absent ou hors de la plage 1.35 à 1.37 | installer un kubectl de cette plage |
| `Docker Engine ... found, 28.0.0 or later expected on Linux` | un moteur plus ancien laisse le réseau local joindre des ports non publiés | mettre Docker Engine à jour |
| `the container engine declares ... MiB of memory` | la mémoire déclarée est sous le seuil du profil | donner plus de mémoire à la machine virtuelle du moteur, du nombre de Mio que dit le message |
| `the standard profile is not delivered yet` | le profil standard arrive à l'étape 12 | `PROFILE=lite task up` |
| `host port ... is already in use on 127.0.0.1` | un autre programme tient le port | libérer le port, puis relancer |
| `host port ... cannot be checked` | le bash de la machine n'a pas `/dev/tcp`, ou un filtre coupe 127.0.0.1 | utiliser un bash qui le prend en charge |
| `the cluster saas-b2b exists, but does not publish host port` | le cluster date d'avant ces ports | `task down`, puis `task up` |
| `the volume of the database ... exists without the Secret` | un nouveau mot de passe n'ouvrirait pas les données du volume | retirer ensemble le volume et les Secrets de la base : `task down` retire le cluster, donc les deux |
| `the container saas-b2b-mirror is not the mirror of this project` | un conteneur de ce nom existe sans l'étiquette du projet | il est laissé en place : le retirer ou le renommer soi-même |

Un refus d'un autre ordre, un déploiement qui n'est pas prêt dans son délai par exemple, nomme la commande `kubectl` à lancer, avec le kubeconfig du projet, pour lire les pods ou le journal.

## Pour aller plus loin

La [spécification](../../specs/001-golden-repo-saas-b2b/spec.md), le plan et les tâches sont dans `specs/001-golden-repo-saas-b2b/` de CELIAN, avec les contrats de [commandes](../../specs/001-golden-repo-saas-b2b/contracts/task-cli.md), de [couches](../../specs/001-golden-repo-saas-b2b/contracts/layers.md), de [Secrets](../../specs/001-golden-repo-saas-b2b/contracts/secrets.md) et d'[API](../../specs/001-golden-repo-saas-b2b/contracts/http-api.md). Les décisions sont dans les ADR de CELIAN, `docs/adr/`.
