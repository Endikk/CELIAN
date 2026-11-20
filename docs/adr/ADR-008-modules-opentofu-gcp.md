# ADR-008. CELIAN écrit lui-même le code OpenTofu de la cible GCP, sous conditions

| Champ | Valeur |
| --- | --- |
| Statut | accepté |
| Date | 2026-11-19 |
| Auteur | [ARCHI] |
| Décideur | DSI, sur délégation de Lucas à la GATE 1 du 2026-11-20 |
| BENCH lié | [BENCH-008](../benchmarks/BENCH-008-modules-opentofu-gcp.md) |
| Remplace | aucun |

## Contexte et problème

Quand la cible `gcp` est choisie, le projet généré contient le code OpenTofu qui crée sa couche GCP (US-004). Reste à décider d'où vient ce code : des ressources du provider `google` écrites par CELIAN, les modules de Cloud Foundation Fabric, ou ceux de terraform-google-modules. Le choix doit précéder le golden repo de la phase 2, qui construira cette couche à la main. Le PRD ne pressentait aucune option (section 1).

Les exigences viennent du PRD. US-006 et US-007 veulent un `tofu validate` et des politiques conftest qui passent avant la livraison, puis un plan sans erreur avec les identifiants de l'utilisateur, l'agent ne lançant jamais `tofu apply`. Le plan valide compte dans les 15 minutes (section 7, Q1), donc `tofu init` et `tofu validate` aussi. ENF-02 veut que seule la couche de cible change d'une cible à l'autre (principe II), ENF-05 un dimensionnement minimal et une alerte budget déclarée dans le code. Q5 vise macOS et Linux pour le poste, Q6 un seul environnement déployé sur GCP. Côté constitution, les principes II, III, IV, V, VI, VIII, IX et X. Côté risques, R-05 et R-17 (dépense et tailles par défaut), R-15 (ressources qui survivent à `tofu destroy`), R-19 (identité de la CI et état OpenTofu) et R-27 (modules tirés sans contrôle d'intégrité).

Le mode du cluster GKE se tranche ici aussi. L'ADR-004 laissait la ligne `gcp` de son entrée de catalogue en attente du mode (Autopilot ou Standard) et du canal. BENCH-008 a construit ses trois socles sur Autopilot. Le canal reste régi par la règle de version de l'ADR-004.

Le classement de BENCH-008 a changé pendant sa relecture. La première version proposait Fabric, à 83 contre 82. Les relectures de [SECU] et de [FINOPS], puis l'arbitrage du DSI du 2026-11-19, ont corrigé cinq notes : la gouvernance de Fabric et celle de terraform-google-modules de 3 à 2, comme Pkl et CUE dans BENCH-001 et k3d dans BENCH-003 ; la sécurité de Fabric de 4 à 3, pour ses modules tirés par tag ; le coût de l'option écrite à la main de 4 à 5, le temps de maintenance étant déjà compté en expérience dev ; le coût de terraform-google-modules de 4 à 3. La grille recalculée en entier donne 83, 78 et 64.

## Options considérées

| Option | Score BENCH (sur 100) | Verdict | Raison principale |
| --- | --- | --- | --- |
| Écrits à la main, provider `hashicorp/google` 8.12.0 | 83 | retenue | Aucun module tiré à l'init, tout le code lisible par les politiques sur HCL, 42,4 Mo à la première init en amd64 sans rien retélécharger ensuite, aucun projet à éditeur unique ajouté |
| Cloud Foundation Fabric v60.0.0, tiré par tag Git | 78 | écartée | Éditeur unique sans fondation (gouvernance 2/5) ; modules tirés par tag et reclonés à chaque init sans somme de contrôle (sécurité 3/5) ; 99,6 Mo à la première init en amd64, à 0,4 % du seuil de 100 Mo |
| terraform-google-modules, neuf modules dont deux sous GoogleCloudPlatform | 64 | écartée | Valeurs par défaut à contourner (IP publique de Cloud SQL, point d'accès GKE public, Memorystore sans AUTH) ; provider bloqué en `google` 7.46.2 par le module secret-manager ; 134,8 Mo à la première init et neuf clones Git à chaque init |

La sensibilité de BENCH-008 (section 7) éprouve ces totaux :

- Fabric copié dans le blueprint, dossiers `modules/<nom>` seuls : sécurité à 4, empreinte à 5 (plus aucun clone, 92,7 Mo de providers en amd64), expérience dev à 3 (9 484 lignes de code tiers dans chaque projet généré, fusionnées par `copier update`, R-11). Total 80, trois points derrière. À 7,3 % sous le seuil de volume, ce 5 tomberait à 4 en une quinzaine de versions de `google` et `google-beta` au rythme observé : 78 ;
- Fabric figé par SHA complet : sécurité à 4, mais un clone complet de 88,1 Mo d'objets Git porte la première init à 180,8 Mo en amd64, et l'empreinte tombe à 3. Total inchangé, 78 ;
- Fabric tel que mesuré n'a que 0,42 Mo de marge sous le seuil de 100 Mo, 1,35 Mo avec le seul `.pack`, soit une à trois versions des providers. Seuil franchi, ou seuil abaissé à 5 % du budget (56 Mo) : 76 ;
- l'option écrite à la main sans verrou versionné : 81. Sa gouvernance ramenée à 3 : 80, à égalité avec Fabric copié. Sa maturité portée à 4 une fois la matrice en place : 86 ;
- pour que Fabric passe devant, il faut à la fois le copier (80) et retirer deux crans à l'option écrite à la main, par exemple sa gouvernance et le verrou (78) ;
- terraform-google-modules reste dernier dans tous les cas, à 12 points au moins.

Face à Fabric copié, l'écart tient donc à trois points et à des notes de jugement, que la section 8 de BENCH-008 renvoie à l'avis de Lucas. Les critères écrits hors grille penchent vers l'option écrite à la main, sauf le dernier :

- sur ce socle, Fabric n'économise que 34 lignes (169 contre 203) et charge 9 484 lignes de modules ;
- Fabric n'a pas de module Memorystore : le projet généré mêlerait de toute façon modules et ressources écrites à la main ;
- Fabric a publié 11 versions majeures en 12 mois, sans garantie de compatibilité : chaque montée serait une PR à relire ;
- un module tiré par tag échappe au verrou d'OpenTofu, qui ne suit que les providers. Rien ne vérifie alors le code qui crée l'infrastructure, et au plan une source de données `external` lance un programme qui reçoit l'environnement du processus, identifiants de la CI compris (R-27) ;
- une politique sur le HCL, conftest ou Trivy, ne voit tout que dans du code écrit à la main ou copié. Avec des modules tirés à l'init, elle doit lire le JSON d'un plan, donc attendre des identifiants ;
- en faveur de Fabric : ses valeurs par défaut servent de référence relue par Google, et sa CI teste chaque module sous OpenTofu, ce que CELIAN devra faire lui-même.

Grille, mesures et sources : [BENCH-008](../benchmarks/BENCH-008-modules-opentofu-gcp.md).

## Décision

Le blueprint SaaS B2B décrit sa couche `gcp` avec des ressources du provider `hashicorp/google`, écrites et maintenues par CELIAN dans le blueprint, sans aucun module tiers. Le cluster Kubernetes de cette couche est un cluster GKE Autopilot.

Cette option n'ajoute aucun projet à éditeur unique : sa seule dépendance tierce, le provider `google`, est commune aux trois options (principe V). La validation d'ensemble se fait à la GATE 1. Deux points y demandent l'avis explicite de Lucas : le mode Autopilot, que la grille n'a pas noté (voir « Mode du cluster : GKE Autopilot »), et les notes de jugement dont dépend le classement de tête, à savoir la gouvernance, la maturité et l'expérience dev de l'option écrite à la main (BENCH-008, section 8).

### Conditions

Elles reprennent les conditions de la section 7 de BENCH-008, issues des relectures de [SECU] et de [FINOPS]. La décision ne vaut qu'avec elles. Chaque contrôle cité entre dans la matrice de validation (principe I).

1. Fédération d'identité de la CI sur des identifiants. La condition d'attribut porte sur `assertion.repository_id`, `assertion.repository_owner_id` et `assertion.ref`, et le compte de service se lie à `attribute.repository_id/<id>`, jamais à un nom. Google écrit que les champs de nom favorisent le cybersquatting et le typosquatting, et recommande les champs `*_id`, que GitHub publie dans ses jetons. Les trois socles mesurés filtrent aujourd'hui sur des noms. Chaque variable interpolée dans la condition reçoit un bloc `validation`, sinon une apostrophe réécrit l'expression CEL. L'entretien relève les deux identifiants numériques du dépôt ([DEV]). Aucune clé de compte de service. Une politique conftest refuse une condition sans ces trois revendications, et un `principalSet` sur un nom.
2. État et plans chiffrés. OpenTofu chiffre l'état et les plans avec son chiffrement natif et le fournisseur de clé `gcp_kms`. Aucun fichier de plan n'est publié en artefact de CI. La raison : la chaîne AUTH de Memorystore est écrite en clair dans l'état des trois socles, et le compte qui lance `tofu plan` lit l'état. Ajout de [ARCHI] : un contrôle statique de la matrice échoue si la configuration ne déclare pas ce chiffrement, ou si un workflow du projet généré publie un plan.
3. Attributs `*_wo`. Partout où le provider en propose, le blueprint utilise l'attribut en écriture seule : `password_wo`, `root_password_wo` et `secret_data_wo` existent dans `google` 8.12.0. Un `random_password` éphémère du provider `random` les alimente, sans jamais être stocké dans l'état ni dans le plan. OpenTofu gère les uns et l'autre à partir de 1.11 : c'est la version minimale du projet généré, les mesures ayant été faites avec 1.13.9. La chaîne AUTH de Memorystore, générée par le serveur, n'a pas d'équivalent ; l'authentification IAM du cache revient au benchmark du moteur de cache. Une politique conftest refuse `password`, `root_password` et `secret_data` écrits en clair.
4. Compte de service dédié aux nœuds GKE, avec au moins `roles/container.defaultNodeServiceAccount`. Google le recommande, le compte par défaut de Compute Engine pouvant avoir plus de permissions que GKE n'en demande. Le socle mesuré gardait ce compte par défaut, oubli que Trivy a relevé au premier passage ; la matrice rejoue ce contrôle.
5. `dns_endpoint_config` écrit explicitement. Par défaut, le point d'accès DNS du plan de contrôle est joignable par les API publiques de Google Cloud, protégé par IAM, et Google recommande de n'utiliser que lui. Le socle mesuré n'écrivait pas le bloc. Le blueprint l'écrit, avec une valeur que fixent [OPS] et [SECU], pour que l'accès au plan de contrôle ne dépende d'aucun défaut implicite. Le point d'accès IP reste désactivé, les nœuds restent privés. Un contrôle statique refuse un cluster sans ce bloc.
6. Trivy et conftest sur le HCL, dans la matrice. Le code écrit à la main est le seul que Trivy lit en entier : sur les socles à modules, ses résultats n'étaient pas fiables. Les cinq échecs que Trivy 0.76.2 a relevés sur le socle mesuré, tous réels, sont corrigés ou justifiés par écrit avant que la matrice accepte la couche. Les politiques conftest suivent la liste des suites de BENCH-008 : elles refusent une IP publique sur Cloud SQL, un point d'accès IP public sur GKE sans réseau autorisé, une condition de fédération incomplète (condition 1), une clé de compte de service, un mot de passe ou un secret en clair (condition 3), et un tier Memorystore non écrit.
7. Verrou en lecture seule. Le projet généré versionne son fichier de verrouillage, comme le recommande OpenTofu. Sa CI lance `tofu init -lockfile=readonly`, qui vérifie les sommes du verrou sans le modifier, et met les providers en cache avec le verrou pour clé. Aucun provider n'entre sans un changement du verrou visible en PR.
8. Aucun module tiers tiré par tag. Si un module tiers entre plus tard, il est copié dans le blueprint, dossiers `modules/<nom>` seuls, jamais la racine du dépôt amont (celle de Fabric porte des fichiers d'instructions pour agents). La licence est jointe, les fichiers modifiés signalés et les mentions gardées, comme l'exige l'Apache-2.0 (4.a à 4.c). À défaut de copie, il est figé par SHA complet, sans `depth`. Toute montée de version d'un module copié passe par une relecture [SECU]. Ajout de [ARCHI] : un contrôle statique refuse toute `source` de module qui n'est ni un chemin local ni une source Git désignée par un SHA complet.
9. `requests` explicites sur chaque pod. Sans requête, Autopilot applique 0,5 vCPU et 2 Gio par pod, soit 23,4 USD par pod et par mois aux prix d'exemple de us-central1 relevés par [FINOPS]. Le blueprint fixe des `requests` sur chaque pod qu'il déploie, et une règle de validation côté Kubernetes refuse un pod sans requête.
10. Démontage en deux temps. La protection contre la suppression, active sur Cloud SQL et GKE, fait échouer `tofu destroy`. La commande documentée de destruction (US-006) commence par un apply qui lève les protections, puis lance le destroy. L'utilisateur lance les deux, jamais l'agent (principe X). Sinon le cluster et l'instance restent et facturent (R-15). [OPS] vérifie en phase 2 ce qu'un destroy partiel laisse derrière lui.

### Version du provider

Faits lus le 2026-11-19. BENCH-008 a mesuré le provider `hashicorp/google` 8.12.0, seul provider résolu par le socle écrit à la main. L'API des releases du dépôt le confirme : 8.12.0 est publiée le 2026-11-17 à 19:43 UTC et reste la dernière release à cette date, après 8.11.0 le 2026-11-10 et 8.10.0 le 2026-11-03. La dernière version majeure, 8.0.0, date du 2026-08-26.

Règle proposée par [ARCHI] :

1. Version figée par le verrou. Le fichier de verrouillage versionné porte la version retenue et ses sommes (condition 7), 8.12.0 aujourd'hui. Le provider `random`, qu'ajoute la condition 3, suit la même règle ; le socle mesuré ne le contenait pas.
2. Délai de 7 jours. La version qui entre dans le blueprint est publiée depuis au moins 7 jours (principe VI). 8.12.0 remplit ce délai à partir du 2026-11-24.
3. Mises à jour. Renovate propose chaque version mineure une fois publiée depuis 7 jours, et la PR passe toute la matrice. Au rythme observé, c'est une PR par semaine à relire. Une version majeure se monte à la main, dans une release du blueprint qui passe la matrice. La prise en charge du verrou d'OpenTofu par Renovate n'a pas été vérifiée dans sa documentation : [OPS] la vérifie. À défaut, chaque version donne lieu à une PR manuelle, avec le même délai.
4. Outil. OpenTofu 1.11 au moins (condition 3). La version exacte de l'outil dans la CI du projet généré se fixe avec [OPS].

### Mode du cluster : GKE Autopilot

BENCH-008 a retenu Autopilot pour ses trois socles, sur les sources de sa section 1, sans le noter dans la grille. Google le présente comme « the recommended way to use GKE ». Autopilot préconfigure la fédération d'identité de GKE, les nœuds Shielded et le démarrage sécurisé, que Standard laisse optionnels : moins de valeurs à régler et à vérifier par conftest. Il facture les demandes de ressources des pods généralistes, et l'offre gratuite couvre un cluster Autopilot par mois, pour les seuls frais de cluster.

Deux réserves. Un cluster Autopilot est toujours régional : le profil démo ne peut pas être zonal pour GKE (R-17). Selon [FINOPS], il ne coûte pas plus pour autant, puisque l'offre gratuite vise un cluster Autopilot et que la facture suit les demandes des pods, pas les nœuds. Ensuite, un nouveau cluster Autopilot a par défaut une adresse IP publique, que le socle désactive (condition 5).

Le canal du cluster suit la règle de version de l'ADR-004 : Regular comme canal de référence, fixé par [OPS].

### Portée

La spec ne nomme ni OpenTofu, ni le provider, ni GKE : ils vivent dans la couche `gcp` du blueprint et au catalogue (principe II). La décision couvre le socle de BENCH-008 : activation des API sur un projet existant, réseau VPC avec sous-réseau et plages secondaires, accès privé aux services, cluster GKE Autopilot à nœuds privés, Cloud SQL pour PostgreSQL en IP privée, Memorystore for Redis en tier basique, dépôt Artifact Registry Docker à tags immuables, secret Secret Manager, identité de la CI par fédération et sans clé. Elle vaut pour toute ressource que la phase 2 ajoutera à cette couche.

Restent hors de cette décision : le moteur du cache (Redis ou Valkey) et son authentification ; les versions de Postgres et de Kubernetes, la seconde suivant l'ADR-004 ; le backend de l'état, la clé KMS de la condition 2 et leur amorçage (R-19, [OPS] et [SECU]) ; Cloud NAT et la gateway (BENCH-004) ; le montant du budget (R-05) ; l'écriture des politiques conftest ; le découpage des racines OpenTofu par environnement, un seul environnement étant déployé sur GCP (Q6) ; le dimensionnement ([FINOPS], [OPS]) ; AWS, hors MVP.

## Conséquences

### Positives

- La première init télécharge 42,4 Mo en linux_amd64, pire cas retenu parce que Linux fait partie des systèmes visés (Q5), et 37,9 Mo en darwin_arm64. Avec le verrou, rien n'est retéléchargé. Init à froid en 12,36 s, validation en 1,07 s, 148,4 Mio de mémoire : loin des seuils de 100 Mo, 90 s et 1 Gio. Un seuil de volume abaissé à 56 Mo la laisserait dessous.
- Rien n'est tiré à l'init hormis le provider, signé. R-27 ne s'applique pas tant que la condition 8 tient.
- Chaque valeur sensible est choisie et lisible dans 203 lignes : IP privée, chiffrement en transit `ENCRYPTED_ONLY`, sauvegardes et protection contre la suppression pour Cloud SQL ; point d'accès IP désactivé et nœuds privés pour GKE ; tier basique avec AUTH, TLS et accès privé pour Memorystore ; tags immuables ; aucune clé de compte de service ; API gardées à la destruction.
- Trivy et conftest voient toute la couche sur le HCL, sans identifiant. La porte de politique reste dans la validation avant livraison (US-006, US-007), sans attendre un plan.
- Aucune valeur par défaut d'un module tiers à surveiller : le coût des services ne dépend que des valeurs que le blueprint écrit.
- Pas de `google-beta`, et aucun module ne bride la version du provider, comme secret-manager bride terraform-google-modules en 7.46.2.

### Négatives

- Code neuf, sans usage en production : maturité 3/5. Sa justesse repose sur ce que CELIAN écrit (matrice, Trivy, conftest), sans déploiement réel tant que le principe X l'interdit aux agents. Trivy a trouvé un oubli dès le premier passage, le compte des nœuds.
- 203 lignes à maintenir, le plus gros volume des trois socles, sans la communauté de Fabric ni sa CI qui teste chaque module sous OpenTofu. Tout repose sur l'équipe de CELIAN, ce que R-24 suit déjà pour les outils du générateur.
- Le provider publie chaque semaine : une PR à relire par semaine, et chaque version majeure à suivre seul.
- Sans la clé KMS, état et plans deviennent irrécupérables. La condition 2 fait de cette clé un point de défaillance, à protéger au même titre que l'état (R-19).
- La chaîne AUTH de Memorystore reste dans l'état, protégée par le seul chiffrement, tant que le cache n'a pas d'authentification IAM.
- Autopilot est toujours régional : pas de profil démo zonal pour GKE (R-17).
- Démontage en deux temps (condition 10) : un utilisateur qui lance seulement `tofu destroy` garde un cluster et une instance qui facturent (R-15).
- Le socle mesuré est minimal : ni Cloud NAT, ni gateway, ni budget, ni état distant, ni provider `random`. Lignes et empreinte se recomptent sur la couche complète du golden repo de la phase 2.
- Le coût reste inconnu. GKE seul coûte de 20 à 307 USD par mois aux prix d'exemple de us-central1, un minorant ; Cloud SQL, Memorystore et le réseau ne sont pas chiffrés (R-05).

### Effet sur les cibles hors MVP

La porte reste ouverte. La couche `gcp` est propre à GCP par construction, et rien de cette décision n'entre dans la spec ni dans la couche commune du blueprint. Une cible AWS ou Azure ajoutera sa couche, écrite selon la même méthode, ou avec un module tiers retenu par son propre benchmark et soumis à la condition 8. Les conditions 7 et 8 ne dépendent pas du fournisseur. Le fournisseur de clé de la condition 2 est propre à GCP : une autre cible devra vérifier qu'elle dispose d'un équivalent.

### Suites

- Entrée de catalogue pour le provider `google`, et mode Autopilot porté sur la ligne `gcp` de l'entrée du cluster de l'ADR-004 (section « Entrée au catalogue »).
- Politiques conftest de la cible GCP et règle Kubernetes sur les `requests` (conditions 6 et 9), pour [QA] et [SECU].
- Alerte budget de la section 5.9 de BENCH-008 dans le blueprint, après réponse à la question ouverte 1.
- R-27 ouvert et R-15, R-17 et R-19 amendés par le DSI dans la même PR que cet ADR, à partir des textes de la section 7 de BENCH-008. La mitigation de R-19 filtre désormais la fédération sur `repository_id`, `repository_owner_id` et `ref`, comme la condition 1.
- Phase 2 : couche complète construite à la main dans le golden repo, lignes et empreinte recomptées, premier plan sur un projet de Lucas avec son accord (principe X). Ce plan confirme l'état effectif du point d'accès DNS, et un vrai jeton répond à la question ouverte 4.

### Questions ouvertes

1. Alerte budget, pour [OPS] et [SECU] : racine OpenTofu séparée ou alias de provider. ENF-05 veut une alerte déclarée dans le code, et elle ne plafonne rien (R-05). [FINOPS] a relevé trois contraintes. Avec les identifiants de l'utilisateur, le provider doit porter `billing_project` et `user_project_override = true`, sinon l'API répond 403. Le budget appartient au compte de facturation, et un `tofu plan` en CI avec le seul `roles/viewer` sur le projet risque une erreur de droits ; c'est une déduction non vérifiée, qui mènerait à une racine séparée. Créer un budget demande un rôle sur le compte de facturation, rôle exact à lire.
2. Tarifs non lus, pour [FINOPS] : les grilles de Cloud SQL, de Memorystore et du réseau n'ont pas pu être lues le 2026-11-19. Elles se lisent pour la région retenue avant la GATE 2 (R-05). D'ici là, aucun budget de démo n'est validable.
3. Rôles de lecture de la CI, pour [OPS] : le socle donne `roles/viewer` au compte de `tofu plan`, rôle de base que Google déconseille en production. Il se remplace par des rôles de lecture par service, à définir.
4. À vérifier en phase 2 sur un vrai jeton : la restriction de l'événement et du workflow, puisqu'un workflow `pull_request_target` tourne sur la branche par défaut ; la longueur du nouveau `sub` de GitHub face aux 127 caractères de `google.subject`.
5. Ajout de [ARCHI], pour [OPS] : le verrou versionné doit couvrir les plateformes des postes de Q5 et des runners de CI. Ni la commande qui y inscrit les sommes de chaque plateforme, ni le comportement de `-lockfile=readonly` quand la plateforme courante y manque, n'ont été vérifiés.

### Réponses de la GATE 1 (2026-11-20)

- Le mode GKE Autopilot, que la grille ne notait pas, est accepté avec l'ADR,
  sur délégation de Lucas. Aucune ressource n'est créée avant la GATE 2 et un
  budget validé (principe X, R-05).
- Lucas lit lui-même les grilles tarifaires de GKE, Cloud SQL, Memorystore et
  du réseau avant la GATE 2, pour la région choisie : les agents ne peuvent
  pas les afficher.
- Aucun contexte ni identifiant GKE sur le poste avant la GATE 2.

## Conformité à la constitution

Vérifiée contre la [constitution](../../.specify/memory/constitution.md) en version 1.0.0.

| Principe | Effet | Justification |
| --- | --- | --- |
| I. Rien sans test automatique | respecté | `tofu validate`, Trivy et conftest tournent sur tout le HCL sans identifiant, et la matrice porte les contrôles des conditions 1 à 9 |
| II. Spec abstraite, catalogue concret | respecté | Le provider, GKE et les ressources concrètes ne vivent que dans la couche `gcp` du blueprint et au catalogue ; la spec ne les nomme pas |
| III. Managé sur le cloud, open source ailleurs | respecté | La couche crée des services managés de GCP : GKE Autopilot, Cloud SQL, Memorystore, Artifact Registry, Secret Manager |
| IV. Catalogue traçable | respecté | Les deux lignes de l'entrée portent licence, gouvernance, statut, date et source |
| V. Gouvernance ouverte d'abord | respecté | Aucun projet à éditeur unique ajouté : la seule dépendance tierce, le provider `google`, est commune aux trois options et maintenue par les équipes de Google et de HashiCorp d'après son README. Un module tiers futur demanderait la justification prévue par BENCH-008 (« Condition de révision ») |
| VI. Récent mais éprouvé | respecté | Aucun critère éliminatoire touché : MPL-2.0, dépôt non archivé, 8.12.0 du 2026-11-17 ; la version qui entre dans le blueprint attend 7 jours ; la réserve sur le code neuf de CELIAN est écrite (maturité 3/5) |
| VII. Une commande pour démarrer | sans objet | La couche `gcp` n'intervient pas dans `task up` |
| VIII. Aucun fait de mémoire | respecté | Les faits renvoient à BENCH-008 et aux pages du provider lues le 2026-11-19 ; sont signalés comme non vérifiés la prise en charge du verrou par Renovate, les plateformes du verrou, les droits de la CI sur le budget et les revendications du jeton |
| IX. Aucun secret dans le dépôt | respecté | Aucune clé de compte de service, attributs `*_wo`, état et plans chiffrés, aucun plan publié (conditions 1 à 3) |
| X. Aucune dépense cloud sans accord | respecté | Aucun plan ni apply pour cet ADR ni pour BENCH-008 ; l'agent ne lance jamais l'apply, et le démontage reste à l'utilisateur (condition 10) |

### Dérogations

Aucune.

## Entrée au catalogue

Brique abstraite : aucune. Le provider et le mode du cluster découlent de la cible `gcp`, sans brique déclarée par la spec, comme le cluster de l'ADR-004. Le nom des entrées et la structure de `catalog/` se fixent en phase 3.

| Cible | Service | Type | Licence | Gouvernance | Statut | Vérifié le | Source |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `gcp` | Provider OpenTofu `hashicorp/google` 8.12.0 | `oss` | MPL-2.0 | Sans fondation : « maintained by the Terraform team at Google and the Terraform team at HashiCorp » (README), dépôt de l'organisation `hashicorp` | actif | 2026-11-19 | <https://github.com/hashicorp/terraform-provider-google> |
| `gcp` | GKE en mode Autopilot, canal selon la règle de l'ADR-004 | `managed` | service propriétaire du fournisseur | Éditeur unique : Google | actif | 2026-11-19 | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview> |

Pas de ligne `local` : le provider ne sert qu'à la couche `gcp`, et le cluster local relève de l'ADR-004. La seconde ligne complète celle que l'ADR-004 laissait en attente du mode du cluster, dans la même entrée que kind.

## Condition de révision

Bascule par un nouvel ADR qui remplace celui-ci si le provider `google` touche un critère éliminatoire : dépôt archivé ou en maintenance, licence qui n'est plus open source, ou aucune release pendant 12 mois. Le décompte part de 8.12.0, publiée le 2026-11-17.

La décision se rouvre, sans basculer d'office, dans ces cas :

- un module tiers est proposé pour une partie de la couche. Il passe par la condition 8, une relecture [SECU] et un benchmark. S'il vient de Google, l'écart au principe V se justifie comme l'écrit BENCH-008 : sur GCP, l'éditeur des services managés est déjà Google (principe III), le code est sous Apache-2.0, et Fabric recommande lui-même de forker ;
- Fabric publie un module Memorystore ou passe en fondation, ou le module secret-manager de terraform-google-modules accepte `google` 8.x : ce sont les déclencheurs que liste BENCH-008 ;
- le décompte des lignes et de l'empreinte sur la couche complète de la phase 2 change le classement de la grille ;
- la lecture des grilles tarifaires avant la GATE 2 rend Autopilot incompatible avec le budget de démo que valide [FINOPS] : le mode du cluster, que la grille n'a pas noté, se rouvre alors.

Sans l'un de ces faits, prochaine vérification le 2027-05-19.

## Sources

Ce que BENCH-008 établit se cite par lui ; ses propres sources sont dans sa section 9.

| Source | Lue le | Ce qu'elle établit |
| --- | --- | --- |
| [BENCH-008](../benchmarks/BENCH-008-modules-opentofu-gcp.md), sections 1 à 3 | 2026-11-19 | Question posée et socle commun ; arguments et réserves d'Autopilot ; options et versions examinées ; critères éliminatoires |
| BENCH-008, section 4 | 2026-11-19 | Seuils d'empreinte et leur origine ; mesures M1 à M10 : temps, mémoire, volumes de la première init, retéléchargements, lignes, providers résolus |
| BENCH-008, sections 5 et 6 | 2026-11-19 | Notes et justifications ; valeurs par défaut des socles et des modules ; scan Trivy ; ordres de grandeur de [FINOPS] ; alerte budget et ses trois contraintes ; grille et totaux 83, 78 et 64 |
| BENCH-008, section 7 | 2026-11-19 | Verdict, sensibilité, critères hors grille, argument du principe V, conditions pour l'ADR, réserves, déclencheurs et date de prochaine vérification, suites |
| BENCH-008, sections 8 et 10 | 2026-11-19 | Limites, dont le socle minimal et les notes de jugement renvoyées à l'avis de Lucas ; avis de [SECU] et de [FINOPS] |
| <https://api.github.com/repos/hashicorp/terraform-provider-google/releases?per_page=5> | 2026-11-19 | v8.12.0 publiée le 2026-11-17T19:43:15Z, dernière release ; v8.11.0 le 2026-11-10 ; v8.10.0 le 2026-11-03 ; aucune préversion |
| <https://github.com/hashicorp/terraform-provider-google> | 2026-11-19 | README : « This provider is maintained by the Terraform team at Google and the Terraform team at HashiCorp » et « This repository is generated by magic-modules » ; licence MPL-2.0 |
| [ADR-004](ADR-004-cluster-local.md), sections « Version de Kubernetes » et « Entrée au catalogue » | 2026-11-19 | Règle de canal et de mineure ; ligne `gcp` en attente du mode du cluster |
| [docs/prd-mvp.md](../prd-mvp.md), sections 1 et 7, US-004, US-006, US-007, ENF-02, ENF-05, Q1, Q5, Q6 | 2026-11-19 | Aucune option pressentie ; code OpenTofu dans le dépôt généré ; validation, plan et apply laissé à l'utilisateur ; plan valide dans les 15 minutes ; parité ; alerte budget ; systèmes visés ; un seul environnement sur GCP |
| [docs/risques.md](../risques.md), R-05, R-11, R-15, R-17, R-19, R-24, R-27 | 2026-11-19 | Dépense GCP ; `copier update` ; démontage ; tailles par défaut ; identité de la CI et état ; outils portés par une équipe ; modules sans contrôle d'intégrité |
| [Constitution](../../.specify/memory/constitution.md), version 1.0.0 | 2026-11-19 | Principes I à X ; délai de 7 jours du principe VI |
