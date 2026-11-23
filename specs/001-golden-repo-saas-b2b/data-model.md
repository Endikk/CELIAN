# Data Model: golden repo SaaS B2B

Phase 1 du plan ([plan.md](plan.md)), mise à jour le 2026-11-23. Reprend les entités clés de la spec et leur ajoute ce que la conception fixe : champs, règles, états. Les noms provisoires sont signalés.

## Note (exemple de l'application)

La seule donnée métier du golden repo (Q7, FR-009). Écrite et relue dans la base, mise en cache, affichée par le front.

| Champ | Type | Règle |
| --- | --- | --- |
| `id` | UUID | Tiré par l'API à l'écriture ; jamais fourni par le client |
| `body` | texte | Obligatoire ; de 1 à 500 caractères après suppression des blancs de début et de fin ; validé côté serveur, refus avec le nom du champ |
| `created_at` | horodatage avec fuseau | Posé par la base à l'insertion |

Stockage : table `notes` de la base `app`, créée par le script idempotent de l'API (research RS-04). Accès par requêtes paramétrées seulement.

Cache : clé `note:<id>`, valeur JSON des trois champs, durée de vie fixe tenue en constante nommée (valeur fixée à l'étape 3). Ce schéma de clé ne dépend pas du moteur, que fixera l'ADR-015. Lecture paresseuse : à la lecture par identifiant, le cache répond s'il a la clé ; sinon la base répond et la valeur entre au cache. Une note absente n'est pas mise en cache. L'écriture ne touche pas le cache. La liste lit toujours la base.

Pas d'état ni de transition : une note est créée, puis lue. Ni modification ni suppression (Q7).

## Environnement local

Un cluster kind sur le poste, avec ses Secrets, ses données et son profil. Il naît au premier `task up` et disparaît par `task down`.

| Attribut | Valeur |
| --- | --- |
| Nom du cluster | `saas-b2b`, nom du projet, provisoire jusqu'à la phase 3 |
| Kubeconfig | fichier propre au projet, hors du dépôt (research RS-21) |
| Profil | `lite` ou `standard` |
| Namespace de l'application | `saas-b2b`, profil `restricted` des Pod Security Standards ; la base y vit aussi (ADR-012, condition 9) |
| Miroir | conteneur et volume, voir plus bas |

États et transitions :

| Depuis | Commande | Vers | Effet sur les données et les Secrets |
| --- | --- | --- | --- |
| absent | `task up` | démarré | Secrets tirés, base initialisée |
| démarré | `task up` | démarré | Rien de recréé ; Secrets et données gardés (récit 2, scénario 3) |
| démarré | `task reload` | démarré | Images reconstruites et réappliquées ; base ni redémarrée ni vidée |
| démarré | `task app:down` | cluster gardé | Namespace de l'application supprimé, avec la base et ses Secrets (réponse de Lucas du 2026-11-21 à la question 1 de l'ADR-012) ; plate-forme gardée ; en standard, liaison de Flux suspendue d'abord, si elle ne l'est pas déjà |
| cluster gardé | `task up` | démarré | Aucune image tirée (T1) ; Secrets tirés de nouveau, base neuve |
| démarré ou cluster gardé | `task down` | absent | Cluster supprimé, avec les données ; volume du miroir gardé |

Le cas d'un nœud redémarré avec le poste, cluster gardé, n'est pas mesuré (ADR-012) : le README ne promet rien sur les données dans ce cas.

## Profil

| Profil | Composition | Seuil de départ (mémoire déclarée par le moteur) |
| --- | --- | --- |
| `lite` | plate-forme de base (kind, CRD Gateway API, Envoy Gateway), miroir, API, front, Postgres, cache (moteur de l'ADR-015) ; aucun contrôleur GitOps | VM de 2,0 Gio, recalculé à l'entrée du cache |
| `standard` | `lite`, plus Flux avec sa liaison suspendue, puis Keycloak et Mailpit après les ADR-013 et ADR-014 | VM de 2,5 Gio hors Keycloak et Mailpit, recalculé à leur entrée |

Règle de choix : mémoire au-dessus du seuil du standard, standard ; entre les deux, lite, annoncé ; sous le seuil du lite, refus avec la mémoire qui manque. `PROFILE` force un profil, sous les mêmes contrôles. Seuils : ordres de grandeur de [FINOPS] (ADR-011, ADR-012), recalculés sur la première mesure du golden repo.

## Couche

| Couche | Dossier | Contenu | Invariant |
| --- | --- | --- | --- |
| commune | tout ce qui n'est pas sous `local/` ni `gcp/` | code, base et overlays Kustomize, conventions, README, tests et politiques communs | aucun objet, groupe, annotation ou étiquette propre à un outil ou à un fournisseur (S06) |
| `local` | `local/` | kind, miroir, plate-forme, données, GitOps du PC, tâches de démarrage | seule à nommer kind, Envoy Gateway, zot, Flux |
| `gcp` | `gcp/` | OpenTofu, manifests de liaison et de secrets de GKE | seule à nommer un service de Google |

Règle de parité : la couche commune rendue seule se retrouve à l'identique dans chaque rendu de cible, aux champs permis près ([contracts/layers.md](contracts/layers.md)).

## Secret local

Valeur aléatoire propre à un environnement, jamais versionnée. Le contrat par Secret est dans [contracts/secrets.md](contracts/secrets.md).

| Règle | Source |
| --- | --- |
| 40 caractères alphanumériques tirés de `/dev/urandom` pour chaque mot de passe ; au moins 32 exigés | ADR-007, condition 1 ; BENCH-011 |
| Créé par un tube vers `kubectl create -f -`, seulement s'il manque, dans une tâche silencieuse | ADR-007, condition 1 |
| Jamais dans un fichier, une variable de Task, un argument ni par `kubectl apply` | ADR-007, condition 1 |
| Les Secrets de la base vivent avec le volume : volume présent sans Secret, `task up` s'arrête | ADR-012, condition 3 |
| Aucune valeur de la liste connue : `root`, `admin`, `postgres`, `password`, `changeme`, `mysecretpassword`, chaîne vide | ADR-007, condition 1 ; ADR-012, condition 10 |

## Miroir

| Élément | Valeur |
| --- | --- |
| Conteneur | nom et étiquette fixes propres au projet, image zot par condensat, réseau `kind`, aucun port publié, configuration montée en lecture seule |
| Volume | volume nommé du moteur, propre au projet, hors de l'arborescence |
| Liste des registres | une seule valeur, `local/mirror/registries`, dont dérivent la configuration zot et les `hosts.toml` |

États du volume : absent, puis rempli au premier `task up` en ligne, gardé par `task down`, vidé par `task mirror:purge`. Le conteneur est recréé à chaque `task up` et retiré par `task down` et `task app:down` (ADR-011).

## Inventaire des images

Toutes les images qu'un profil livré fait tourner (FR-021). Calculé à chaque exécution, sauf la liste des images qu'aucun fichier ne nomme (research RS-24).

| Origine | Exemples | Source de l'inventaire |
| --- | --- | --- |
| Construites par `task up` | `saas-b2b.invalid/api`, `saas-b2b.invalid/front` | tâche de construction ; SBOM exigé (FR-020) |
| Tirées par le cluster, nommées par le projet | Postgres, cache, contrôleur d'Envoy Gateway, contrôleurs de Flux en standard | rendus du profil et fichiers vendorés |
| Lancées sur le moteur | image du nœud kind, zot | configuration kind, tâche du miroir |
| Nommées par aucun fichier | images préchargées par l'image du nœud, proxy d'Envoy Gateway | `local/security/unlisted-images`, versionné, par condensat |

Règle : toute image en marche après `task up`, dans le cluster ou sur le moteur, figure dans l'inventaire, et tout l'inventaire est scanné (E25, E27). Les images de construction (SDK .NET, Node.js) n'en font pas partie.

## Exception au scan

Une vulnérabilité admise malgré le seuil (FR-022). Un fichier par couche : `security/scan-exceptions.yaml` pour les images construites, `local/security/scan-exceptions.yaml` pour celles de la couche `local` (noms provisoires).

| Champ | Règle |
| --- | --- |
| Vulnérabilité | identifiant tel que le rapporte le scan (CVE ou avis) ; obligatoire |
| Image | dépôt de l'image, sans condensat ; obligatoire |
| Justification | texte qui dit pourquoi la faille est admise ; obligatoire |
| Date d'écriture | AAAA-MM-JJ ; obligatoire |
| Date d'échéance | AAAA-MM-JJ, postérieure à la date d'écriture ; 90 jours au plus proposés, à confirmer par [SECU] |

États : valide tant que tous les champs sont présents et que la date du jour ne dépasse pas l'échéance ; sinon ignorée par la décision du scan et listée en sortie (S27, U03). Le seuil, `HIGH`, vit dans `security/scan-policy.yaml` (nom provisoire).

## Valeurs partagées

Valeurs tenues une fois pour les deux couches (ADR-004, règle de version ; ADR-012, condition 5), dans `platform.yaml` à la racine :

| Clé | Valeur | Lue par |
| --- | --- | --- |
| `kubernetes_minor` | `"1.36"` | test S21 face à l'image de nœud de `local/kind/cluster.yaml` ; couche OpenTofu, selon ce qu'[OPS] retiendra |
| `postgres_major` | `"18"` | test S21 face à l'image Postgres de `local/data/` ; version de l'instance Cloud SQL |

En phase 3, ces valeurs deviendront des variables du blueprint. Dans le golden repo, le test S21 garde d'accord chaque endroit qui les répète.

## Configuration de l'application

Valeurs non secrètes fournies par la couche de cible dans le ConfigMap `app-config`, de même nom et de mêmes clés sur les deux cibles : nom d'hôte et port de la base, nom de la base, nom d'hôte et port du cache, mode TLS de chaque connexion (research RS-11 et RS-12). Les clés du cache existent avant l'ADR-015 ; leurs valeurs arrivent avec les étapes 19 et 20. Les noms exacts des clés se fixent à l'étape 3 et entrent dans [contracts/layers.md](contracts/layers.md).
