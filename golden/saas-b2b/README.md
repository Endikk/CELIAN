# Golden repo SaaS B2B

Projet de référence du blueprint SaaS B2B de CELIAN, construit à la main avant toute mise en template. Il portera une API .NET réduite à un contrôle de santé et à un exemple de notes, un front React, Postgres et un cache, pour deux cibles : un cluster kind sur le poste et GCP.

## État

En construction. Le dépôt ne démarre pas encore. `task up` passe ses contrôles préalables, puis s'arrête : le cluster, le miroir et l'application arrivent aux étapes 6 à 9. `task down` et `task reload` répondent qu'ils ne sont pas livrés, et disent à quelle étape ils arrivent. `task check` tourne en entier, avec les contrôles statiques des étapes 1 à 4 et les contrôles préalables de l'étape 5, joués contre des binaires simulés. `task test` lance les tests unitaires de l'API et du front, chacun dans son image de construction : il demande Docker, et ni SDK .NET ni Node.js.

Pour lancer `task check` sur son poste, il faut Task, conftest, OpenTofu et Trivy. `tests/tools/install.sh <dossier>` les installe dans le dossier donné, après avoir vérifié le SHA-256 de chaque archive, puis ce dossier se met dans le `PATH`.

Le dépôt porte ses propres conventions Git : hooks pre-commit, commitlint, Renovate, release-please et workflows dans `.github/`. Elles prennent effet dans une copie autonome du dossier, où `pre-commit install` pose les hooks ; dans CELIAN, ce sont celles de CELIAN qui s'appliquent, et le contrôle X01 exerce celles-ci dans une copie.

La spécification, le plan et les tâches sont dans [`specs/001-golden-repo-saas-b2b/`](../../specs/001-golden-repo-saas-b2b/spec.md) de CELIAN. Le README complet, avec les prérequis datés, arrive à l'étape 11.

## Prérequis de `task up`

`task up` vérifie ces points avant de créer quoi que ce soit, dans l'ordre du tableau, et s'arrête au premier qui manque en donnant ce qu'il a trouvé et ce qu'il attend. Le README complet de l'étape 11 donnera pour chaque outil sa licence, sa source datée et une installation vérifiée.

| Contrôle | Attendu |
| --- | --- |
| Moteur de conteneurs | local, joint par la commande `docker` à travers un socket unix (un contexte `tcp://` ou `ssh://`, ou `DOCKER_HOST` vers une autre machine, est refusé) ; `docker info` répond en moins de 10 s |
| kind | 0.33.0 exactement (ADR-004) |
| kubectl | 1.35 à 1.37, une mineure autour de celle du cluster, 1.36 dans `platform.yaml` (ADR-006) |
| `openssl` et `awk` | sur le `PATH`, seulement cherchés, jamais lancés par ces contrôles : `task up` fabrique avec eux la clé et le certificat du Secret `gateway-tls`, sans fichier (research RS-10). macOS fournit les deux ; sous Linux, `openssl` est le paquet de la distribution |
| Docker Engine, sous Linux seulement | 28.0.0 ou plus (ADR-011) |
| Mémoire déclarée par le moteur | 2048 Mio pour le profil lite, 2560 Mio pour le standard. Sous macOS, c'est la mémoire de la machine virtuelle du moteur, pas celle du poste (ADR-004) |
| Ports de l'hôte | libres en 127.0.0.1 ; leurs valeurs arrivent à l'étape 7 |

Le profil se choisit sur la mémoire. `PROFILE=lite task up`, ou `task up PROFILE=lite`, force un profil sous les mêmes contrôles de mémoire. Jusqu'à l'étape 12, le profil standard est reconnu puis refusé : sur un moteur qui déclare 2560 Mio ou plus, `task up` sans `PROFILE` s'arrête en le disant, et `PROFILE=lite` permet d'avancer.

L'écouteur HTTPS local (port 18443 de l'hôte, en 127.0.0.1) sert un certificat auto-signé, valable 365 jours, jamais installé dans le magasin de confiance du poste : un navigateur affichera un avertissement. `task up` ne recrée `gateway-tls` que s'il manque, et prévient, sans s'arrêter, quand le certificat expire dans moins de 30 jours. Pour en changer : `kubectl delete secret gateway-tls --namespace saas-b2b`, puis `task up`.

## Carte des couches

Une couche de cible tient dans un seul dossier. Tout ce qui est hors de `local/` et de `gcp/` appartient à la couche commune, identique sur les deux cibles. Le détail est dans le [contrat des couches](../../specs/001-golden-repo-saas-b2b/contracts/layers.md).

| Chemin | Couche | Contenu |
| --- | --- | --- |
| `local/` | `local` | kind, miroir de registres, plate-forme, données, tâches de démarrage |
| `gcp/` | `gcp` | OpenTofu, manifests de liaison et de secrets de GKE |
| tout le reste | commune | code de l'application, base et overlays Kustomize, conventions Git, README, tests et politiques communs |

La couche commune ne nomme aucun outil ni aucun fournisseur. Seule `local/` nomme kind, Envoy Gateway, zot ou Flux, et seule `gcp/` nomme un service de Google.

## Couche GCP

`gcp/tofu/` décrit la cible GCP en OpenTofu : réseau privé, GKE Autopilot, Cloud SQL, Artifact Registry, Secret Manager, Config Sync et identité de la CI par fédération. Rien dans ce dépôt ne la déploie. `task gcp:validate`, `task gcp:policy` et `task gcp:scan` la vérifient sans identifiant cloud, et `task check` les lance aussi. `gcp/budget/` porte l'alerte budget dans une racine à part, appliquée à la main avant la principale ([README](gcp/budget/README.md)). Le premier déploiement attend l'accord de Lucas et un budget validé.

## Écarts entre les cibles

Liste tenue au fil des étapes (ENF-02) ; le README complet de l'étape 11 la reprend.

| Écart | Sur le poste | Sur GCP | Suivi |
| --- | --- | --- | --- |
| Privilèges de l'utilisateur de `db-auth` | propriétaire de la base `app`, sans autre attribut | membre de `cloudsqlsuperuser` : `CREATEROLE`, `CREATEDB`, triggers d'événement, réplication logique | R-39 ; vérifié au premier déploiement, durci après le MVP par un ADR |
