# Golden repo SaaS B2B

Projet de référence du blueprint SaaS B2B de CELIAN, construit à la main avant toute mise en template. Il portera une API .NET réduite à un contrôle de santé et à un exemple de notes, un front React, Postgres et un cache, pour deux cibles : un cluster kind sur le poste et GCP.

## État

En construction. Le dépôt ne démarre pas encore. `task up` passe ses contrôles préalables, puis s'arrête : le cluster, le miroir et l'application arrivent aux étapes 6 à 9. `task down`, `task reload` et `task test` répondent qu'ils ne sont pas livrés, et disent à quelle étape ils arrivent. Seul `task check` tourne en entier, avec les contrôles statiques des étapes 1 et 2 et les contrôles préalables de l'étape 5, joués contre des binaires simulés.

Pour lancer `task check` sur son poste, il faut Task et conftest. `tests/tools/install.sh <dossier>` les installe dans le dossier donné, après avoir vérifié le SHA-256 de chaque archive, puis ce dossier se met dans le `PATH`.

Le dépôt porte ses propres conventions Git : hooks pre-commit, commitlint, Renovate, release-please et workflows dans `.github/`. Elles prennent effet dans une copie autonome du dossier, où `pre-commit install` pose les hooks ; dans CELIAN, ce sont celles de CELIAN qui s'appliquent, et le contrôle X01 exerce celles-ci dans une copie.

La spécification, le plan et les tâches sont dans [`specs/001-golden-repo-saas-b2b/`](../../specs/001-golden-repo-saas-b2b/spec.md) de CELIAN. Le README complet, avec les prérequis datés, arrive à l'étape 11.

## Prérequis de `task up`

`task up` vérifie ces points avant de créer quoi que ce soit, dans l'ordre du tableau, et s'arrête au premier qui manque en donnant ce qu'il a trouvé et ce qu'il attend. Le README complet de l'étape 11 donnera pour chaque outil sa licence, sa source datée et une installation vérifiée.

| Contrôle | Attendu |
| --- | --- |
| Moteur de conteneurs | joignable par la commande `docker` : `docker info` répond |
| kind | 0.33.0 exactement (ADR-004) |
| kubectl | 1.35 à 1.37, une mineure autour de celle du cluster, 1.36 dans `platform.yaml` (ADR-006) |
| Docker Engine, sous Linux seulement | 28.0.0 ou plus (ADR-011) |
| Mémoire déclarée par le moteur | 2048 Mio pour le profil lite, 2560 Mio pour le standard. Sous macOS, c'est la mémoire de la machine virtuelle du moteur, pas celle du poste (ADR-004) |
| Ports de l'hôte | libres en 127.0.0.1 ; leurs valeurs arrivent à l'étape 7 |

Le profil se choisit sur la mémoire. `PROFILE=lite task up`, ou `task up PROFILE=lite`, force un profil sous les mêmes contrôles de mémoire. Jusqu'à l'étape 12, le profil standard est reconnu puis refusé : sur un moteur qui déclare 2560 Mio ou plus, `task up` sans `PROFILE` s'arrête en le disant, et `PROFILE=lite` permet d'avancer.

## Carte des couches

Une couche de cible tient dans un seul dossier. Tout ce qui est hors de `local/` et de `gcp/` appartient à la couche commune, identique sur les deux cibles. Le détail est dans le [contrat des couches](../../specs/001-golden-repo-saas-b2b/contracts/layers.md).

| Chemin | Couche | Contenu |
| --- | --- | --- |
| `local/` | `local` | kind, miroir de registres, plate-forme, données, tâches de démarrage |
| `gcp/` | `gcp` | OpenTofu, manifests de liaison et de secrets de GKE |
| tout le reste | commune | code de l'application, base et overlays Kustomize, conventions Git, README, tests et politiques communs |

La couche commune ne nomme aucun outil ni aucun fournisseur. Seule `local/` nomme kind, Envoy Gateway, zot ou Flux, et seule `gcp/` nomme un service de Google.
