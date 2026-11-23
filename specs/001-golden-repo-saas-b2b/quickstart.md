# Quickstart : valider le golden repo

Guide de validation du golden repo, une fois construit. Il dit quoi lancer et ce qu'on doit observer ; le détail des commandes est dans [contracts/task-cli.md](contracts/task-cli.md), celui des contrôles dans la matrice du [plan](plan.md). Les syntaxes d'outils tiers n'y figurent pas : chaque vérification passe par une tâche du golden repo.

## Prérequis

| Outil | Version | Source |
| --- | --- | --- |
| Moteur de conteneurs | Docker Engine 28.0.0 au moins sous Linux ; moteur libre cité d'abord au README | ADR-011, condition 3 ; R-26 |
| kind | 0.33.0, SHA-256 du binaire vérifié contre `catalog/kubernetes-cluster.yaml` | ADR-004 |
| kubectl | 1.35 à 1.37 | ADR-006, condition 5 |
| Task | à vérifier | ADR-006, question 5 |
| Git | à vérifier | |

Pour contribuer, en plus : pre-commit et les outils de `task check` (conftest, kubeconform, OpenTofu 1.11 au moins), versions à vérifier (research RS-18), et Trivy, 0.71.1 au moins, binaire vérifié contre le SHA-256 du dépôt (research RS-22).

Le golden repo vit dans `golden/saas-b2b/` du dépôt de CELIAN. Les commandes se lancent depuis ce dossier.

## Scénario 1 : démarrer, utiliser, arrêter (récit 1)

1. Poste sans cluster du projet. Lancer `task up`.
   Attendu : profil annoncé, adresses du front et de l'API en 127.0.0.1, durée de chaque étape et durée totale, taille du volume du miroir. Rien d'autre à faire.
2. Ouvrir l'adresse du front, ajouter une note.
   Attendu : la note apparaît dans la liste ; relue deux fois, elle vient de la base puis du cache.
3. Modifier le texte de la réponse de santé de l'API, lancer `task reload`.
   Attendu : la nouvelle version répond ; la note de l'étape 2 est toujours là.
4. Lancer `task down`.
   Attendu : le cluster disparaît, la commande liste ce qui reste sur le poste (volume du miroir et sa taille, images du cache du moteur) et la commande qui retire le miroir.

Contrôles automatiques : E01, E02, E07, E08, E17 ; `task test:e2e`.

## Scénario 2 : secrets propres au poste (récit 2)

1. `task up`, puis `task up` de nouveau.
   Attendu : la seconde commande ne recrée aucun Secret, la note écrite avant est lisible.
2. `task test:e2e`, qui crée deux environnements neufs l'un après l'autre.
   Attendu : aucune valeur de mot de passe commune, chacune d'au moins 32 caractères, aucune de la liste connue, aucune retrouvée dans le dépôt ni dans son historique.

Contrôles : E04, E05, E06.

## Scénario 3 : boucle locale seulement (récit 1, scénario 5)

`task test:e2e` relève les adresses en écoute après le démarrage.
Attendu : rien sur 0.0.0.0, `[::]` ni `*` ; le miroir ne publie aucun port.

Contrôle : E03.

## Scénario 4 : redémarrer sans registre (récit 6)

1. Un premier `task up` avec réseau, puis `task down`.
2. `task test:offline`.
   Attendu : le cluster est recréé et prêt sans joindre aucun registre public, par le miroir en capacité `pull` seule.

Contrôle : E10, pour chaque profil livré. Sur un poste réellement coupé du réseau : D05.

## Scénario 5 : cible cloud sans dépense (récit 3)

1. `task gcp:validate`, `task gcp:policy`, `task gcp:scan`.
   Attendu : les trois passent, sans identifiant cloud et sans contacter Google, hormis le téléchargement des providers figés par le verrou.
2. Ajouter à la racine OpenTofu un module tiers tiré par tag, relancer `task gcp:policy`.
   Attendu : échec qui nomme la condition 8 de l'ADR-008.
3. Relire les journaux du job de CI.
   Attendu : aucune commande de plan, de création ni de destruction ; aucun identifiant cloud.

Contrôles : S14, S15, S17.

## Scénario 6 : conventions du projet (récit 4)

1. Dans une copie du golden repo initialisée comme dépôt Git neuf, commiter avec un message non conforme.
   Attendu : le hook refuse.
2. Ouvrir une PR conforme sur CELIAN qui touche `golden/saas-b2b/`.
   Attendu : hooks, recherche de secrets, tests unitaires et test de démarrage de bout en bout passent ; un titre non conforme est refusé.

Contrôles : X01, U01, U02, E01 ; contrôle du titre de PR de la CI de CELIAN.

## Scénario 7 : modèle fidèle (récit 5)

`task check`.
Attendu : la couche commune rendue seule se retrouve à l'identique dans les rendus `local` et `gcp`, sauf `gatewayClassName` ; aucun objet propre à un outil ou à un fournisseur dans la couche commune ; l'API n'expose que les routes du contrat.

Contrôles : S06, S07, S20.

## Scénario 8 : profils et cas limites

| Situation | Attendu | Contrôle |
| --- | --- | --- |
| Moteur qui déclare moins que le seuil du standard | profil lite, annoncé | P03 |
| Moins que le seuil du lite | refus avec la mémoire qui manque | P03 |
| Port de l'hôte pris | arrêt avant toute création, port nommé | P04 |
| Moteur arrêté | message clair, rien de créé | P02 |
| Mauvaise version de kind | refus avec la version attendue | P01 |
| Kubeconfig de l'utilisateur sur un autre contexte | ignoré, `task up` réussit sans le modifier | P05, E24 |
| Profil lite | aucun contrôleur de Flux dans le cluster | E14 |
| Profil standard | contrôleurs de Flux présents, chaque liaison suspendue | E14, S28 |

## Scénario 9 : contenu des images et failles connues (récit 7)

1. Environnement démarré par `task up`. Lancer `task test:images`.
   Attendu : chaque image en marche, dans le cluster et sur le moteur, figure dans l'inventaire scanné ; un SBOM CycloneDX par image construite ; le scan passe, ou échoue en nommant l'image et la vulnérabilité au seuil `HIGH` sans exception valide.
2. `task test`.
   Attendu : la décision du scan, jouée sur des rapports d'exemple à date fixée, refuse une faille au seuil sans exception, accepte une exception complète et non échue, refuse de nouveau une exception échue ou incomplète.
3. Relire l'exécution de CI d'une PR qui touche `golden/saas-b2b/`.
   Attendu : les SBOM des images construites en artefacts ; le job du scan parmi les contrôles requis ; avec une source de base qui ne résout pas, le scan échoue en le disant.

Contrôles : S25, S26, S27, U03, E25, E26, E27.

## Mesure de la gate (étape 17)

Sur un poste propre, en profil standard, une personne qui ne connaît pas le dépôt lance `task up`. On relève la durée totale et par étape, le volume téléchargé, et le débit de la connexion ; le rapport compare le volume au budget de 900 s et donne le débit qu'il exige (SC-001, SC-002, R-04). La mémoire du profil lite se relève face à un portable de 8 Gio (SC-008).
