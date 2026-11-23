# Contrat : commandes du Taskfile

Seul `task up` a un nom fixé (principe VII). Les autres noms sont provisoires, comme dans les ADR-006 et ADR-011 : le PRD renvoie à la phase 5 les noms des commandes autres que `task up`. La syntaxe interne de Task est à vérifier (research RS-09) ; ce contrat ne décrit que ce que voit l'utilisateur.

Règles communes à toutes les commandes :

- chaque commande vise le kubeconfig du projet et le contexte du cluster local, jamais le kubeconfig par défaut de l'utilisateur (FR-019) ;
- une tâche qui manipule un secret n'affiche ni ses commandes ni ses valeurs ;
- une erreur s'affiche en une phrase qui dit ce qui manque et quoi faire, et la commande sort avec un code non nul ;
- rien ne contacte un cluster cloud ni un service payant.

## `task up`

Démarre ou reprend l'environnement local.

Entrée facultative : `PROFILE=lite` ou `PROFILE=standard`, qui force le profil.

Préconditions vérifiées avant toute création, dans cet ordre :

| Contrôle | Échec |
| --- | --- |
| Moteur de conteneurs joignable | message qui nomme le moteur attendu ; rien de créé |
| Version exacte de kind, mineure de kubectl dans la plage, Docker Engine 28.0.0 au moins sous Linux | message avec la version trouvée, la version attendue et le renvoi au README |
| Mémoire déclarée par le moteur | profil choisi et annoncé ; sous le lite, refus avec la mémoire qui manque |
| Ports de l'hôte libres en 127.0.0.1 | arrêt qui nomme le port pris ; rien de créé |
| Configuration du miroir présente | refus de lancer le miroir |

Effets, dans l'ordre du [plan](../plan.md) (section « Ce que fait `task up` ») : cluster, miroir, plate-forme, images, namespace et Secrets, application, attente de « prêt ».

Sortie en cas de succès :

- le profil retenu ;
- l'adresse du front et celle de l'API, en `http://127.0.0.1:<port>/` et `http://127.0.0.1:<port>/api/` ;
- la durée de chaque étape et la durée totale (FR-015) ;
- la taille du volume du miroir.

Comportements attendus :

| Situation | Comportement |
| --- | --- |
| Environnement existant | repris : rien de recréé, Secrets et données gardés |
| Volume de la base présent sans ses Secrets | arrêt ; le message propose de supprimer les deux |
| Registre public lent ou qui limite | échec dans un délai borné, qui nomme le registre |
| Premier démarrage sans réseau | échec qui dit que le premier démarrage demande le réseau |
| Redémarrage sans réseau après un premier démarrage | succès par le miroir (FR-016) |

## `task reload`

Reconstruit les images de l'API et du front dont les sources ont changé, les charge et réapplique les manifests. Mêmes étapes que `task up`, définies une seule fois. Ne redémarre pas la base et ne touche pas ses données. Sans modification, laisse les mêmes objets, étiquettes d'image mises à part.

## `task down`

Retire le conteneur du miroir, après contrôle de son nom, de son étiquette et de son image, puis supprime le cluster. Garde le volume du miroir. Affiche ce qui reste sur le poste : le volume du miroir et sa taille, les images du cache du moteur (image de nœud, image du miroir, images de base des constructions), et la commande qui retire le miroir.

## `task app:down`

Garde le cluster. En profil standard, suspend d'abord la liaison de Flux, si elle ne l'est pas déjà : elle est livrée suspendue tant que la question 1 de l'ADR-010 reste ouverte. Retire le conteneur du miroir comme `task down`, puis supprime le namespace de l'application, avec la base, son volume et ses Secrets. Le `task up` suivant réutilise le cluster sans tirer d'image et tire de nouveaux Secrets. Affiche la mémoire que garde le cluster.

## `task mirror:purge`

Dit d'abord que le `task up` suivant demandera le réseau, puis supprime le volume du miroir. Ne touche à aucun autre volume.

## Commandes de vérification

| Commande | Contenu | Cluster | Contrôles |
| --- | --- | --- | --- |
| `task test` | tests unitaires de l'API et du front, tests de la décision du scan | non | U01 à U03 |
| `task check` | contrôles statiques, rendus et parité, contrôles préalables simulés, inventaire, politique et exceptions du scan | non | S01 à S23, S25 à S28, P01 à P06 |
| `task test:e2e` | tests sur kind du profil courant | oui, créé et supprimé | E01 à E09, E11 à E24 selon le profil |
| `task test:offline` | T2 du profil courant | oui | E10 |
| `task test:images` | relevé des images en marche, SBOM des images construites, scan de l'inventaire du profil courant ; demande le réseau pour la base de vulnérabilités | oui, déjà démarré | E25 à E27 |
| `task gcp:validate` | init en lecture seule du verrou, puis validation | non | S14 |
| `task gcp:policy` | politiques conftest sur le HCL et les manifests `gcp` | non | S15, S16 |
| `task gcp:scan` | Trivy sur le HCL | non | S15 |

Aucune commande `gcp:plan`, `gcp:apply` ni `gcp:destroy` n'est livrée en phase 2. La destruction en deux temps de l'ADR-008 (condition 10) est décrite au README pour plus tard, et reste une action de l'utilisateur.
