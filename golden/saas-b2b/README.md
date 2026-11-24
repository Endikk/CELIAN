# Golden repo SaaS B2B

Projet de référence du blueprint SaaS B2B de CELIAN, construit à la main avant toute mise en template. Il portera une API .NET réduite à un contrôle de santé et à un exemple de notes, un front React, Postgres et un cache, pour deux cibles : un cluster kind sur le poste et GCP.

## État

En construction. Le dépôt ne démarre pas encore : `task up`, `task down`, `task reload` et `task test` répondent qu'ils ne sont pas livrés, et disent à quelle étape ils arrivent. Seul `task check` tourne, avec les contrôles statiques des étapes 1 et 2.

Pour lancer `task check` sur son poste, il faut Task et conftest. `tests/tools/install.sh <dossier>` les installe dans le dossier donné, après avoir vérifié le SHA-256 de chaque archive, puis ce dossier se met dans le `PATH`.

Le dépôt porte ses propres conventions Git : hooks pre-commit, commitlint, Renovate, release-please et workflows dans `.github/`. Elles prennent effet dans une copie autonome du dossier, où `pre-commit install` pose les hooks ; dans CELIAN, ce sont celles de CELIAN qui s'appliquent, et le contrôle X01 exerce celles-ci dans une copie.

La spécification, le plan et les tâches sont dans [`specs/001-golden-repo-saas-b2b/`](../../specs/001-golden-repo-saas-b2b/spec.md) de CELIAN. Le README complet, avec les prérequis datés, arrive à l'étape 11.

## Carte des couches

Une couche de cible tient dans un seul dossier. Tout ce qui est hors de `local/` et de `gcp/` appartient à la couche commune, identique sur les deux cibles. Le détail est dans le [contrat des couches](../../specs/001-golden-repo-saas-b2b/contracts/layers.md).

| Chemin | Couche | Contenu |
| --- | --- | --- |
| `local/` | `local` | kind, miroir de registres, plate-forme, données, tâches de démarrage |
| `gcp/` | `gcp` | OpenTofu, manifests de liaison et de secrets de GKE |
| tout le reste | commune | code de l'application, base et overlays Kustomize, conventions Git, README, tests et politiques communs |

La couche commune ne nomme aucun outil ni aucun fournisseur. Seule `local/` nomme kind, Envoy Gateway, zot ou Flux, et seule `gcp/` nomme un service de Google.
