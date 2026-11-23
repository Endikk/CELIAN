# BENCH-012. Fournisseur d'identité du profil standard

| Champ | Valeur |
| --- | --- |
| Identifiant | BENCH-012 |
| Sujet | Fournisseur d'identité (OIDC) du profil standard sur le PC, et son pendant sur GCP |
| Statut | relu |
| Ouvert le | 2026-11-20 |
| Mis à jour le | 2026-11-24 |
| Auteur | [BENCH] |
| Relecteurs | [SECU] pour les licences et les CVE, [FINOPS] pour les coûts |
| Périmètre | Projet généré sur PC (cluster local) et projet généré sur GCP |
| Choix du PRD | Aucune ligne du tableau des choix ouverts : composition du profil standard, décision de Lucas du 2026-11-20 (US-005) |
| ADR lié | ADR-013, à écrire par [ARCHI] |
| Verdict proposé | Keycloak, 81 sur 100, 19 points devant Zitadel (62) ; Authentik éliminé (section 3). Retenu le 2026-11-24 ; Identity Platform sur `gcp` ; dérogation datée à ENF-03 (section 7) |

## 1. Contexte

[DSI] Benchmark ouvert par le DSI le 2026-11-20, sur décision de Lucas : le
profil standard du golden repo ajoute au profil lite Flux, Keycloak et
Mailpit, et Keycloak passe par un benchmark avant d'entrer dans le golden
repo. Les paragraphes [DSI] cadrent la question ; [BENCH] les reprend ou les
corrige sous son tag.

[DSI] Question posée : quel fournisseur d'identité le profil standard du
projet généré démarre dans le cluster local, et quel service lui correspond
sur GCP au sens du principe III et de la lecture de l'ADR-009.

[DSI] Ce qui en dépend. US-005 et la spec du golden repo (FR-006) : le profil
standard est celui qui sert de mesure au critère des 15 minutes (section 7 du
PRD), donc le volume et le temps de démarrage de cette brique comptent
directement dans ENF-01 et R-04. ENF-02 : la brique existe sur les deux
cibles, seule la couche de cible change. ADR-006 : pas d'outil de boucle
derrière `task up`. ADR-007 : identifiants créés par `task up` avec des
valeurs aléatoires. R-20 : Keycloak y figure parmi les briques qui démarrent
avec un mot de passe connu. ADR-005 : exposition en boucle locale par la
gateway. Principes II, III, V, VI et VIII.

[DSI] Option pressentie : Keycloak, proposé pour le profil standard par
BENCH-005 et retenu dans la composition du profil par Lucas. Elle est notée
comme les autres. Les autres options et le service managé de GCP sont à
établir par [BENCH], sources à l'appui.

[DSI] Règles de notation de la GATE 1 (`TEMPLATE.md`) : volume noté sur
linux_amd64 ; la brique est une couche, comptée contre ses propres seuils ;
mémoire lue au nœud, moins kind seul ; seuils écrits avec leur heure UTC
avant la première mesure. Mesures sous le verrou de mesure partagé, après
BENCH-010 et BENCH-011.

[DSI] Hors champ : l'usage du fournisseur d'identité par l'application
d'exemple, qui se décide dans le plan de la spec 001 (Q7) ; la gestion des
utilisateurs d'un client réel ; la fédération avec un annuaire d'entreprise.

[BENCH] Reprise du cadrage, sans correction de fond. La section 8 du brief
range ce benchmark parmi ceux d'après le MVP et lui donne trois options,
Keycloak, Zitadel et Authentik (`docs/brief-v1.0.md`, section 8) ; la décision
de Lucas du 2026-11-20 le fait entrer dans le MVP, et ce rapport garde les
trois. La section 5 du brief donne Identity Platform comme pendant de Keycloak
sur GCP, ce que la section 2 examine.

[BENCH] Deux points du cadrage se précisent à la lecture des sources, et pèsent
sur l'ADR-013 plus que sur la grille. D'abord, le pendant managé sur GCP ne
parle pas le même protocole à l'application que les trois options : la
section 2 le détaille, et c'est la première question pour [ARCHI]. Ensuite,
R-20 se confirme pour chaque option, sous trois formes différentes : le
manifest de démarrage rapide de Keycloak écrit `admin`/`admin` et le mot de
passe de sa base en clair [S12], celui de Zitadel documente
`Password1!` [S26], et Authentik laisse fixer le mot de passe de `akadmin` au
premier visiteur de son flux d'installation, sauf variable d'amorçage [S38],
[S40]. La mesure M8 vérifie que le protocole s'en écarte.

## 2. Options étudiées

| Option | En une phrase | Version examinée | Publiée le | Sources |
| --- | --- | --- | --- | --- |
| Keycloak | Serveur d'identité et d'accès (OpenID Connect, OAuth 2.0, SAML), en Java sur Quarkus d'après son dépôt, en incubation à la CNCF ; image officielle sur quay.io, manifest de démarrage rapide pour Kubernetes et opérateur | 26.8.2 | 2026-11-05 | [S1], [S2], [S5], [S8], [S12] |
| Zitadel | Plate-forme d'identité multi-organisations (OpenID Connect, OAuth 2.0, SAML), en Go d'après son dépôt, éditée par la société ZITADEL ; une API et une interface de connexion en Next.js, installées par un chart Helm | v4.20.5 | 2026-11-18 | [S19], [S20], [S26], [S28] |
| Authentik | Fournisseur d'identité (OpenID Connect, OAuth 2.0, SAML, LDAP, proxy), en Python et en Go d'après son dépôt, édité par Authentik Security Inc. ; un serveur et un worker dans la même image, installés par un chart Helm | 2026.8.6 | 2026-11-20 | [S30], [S31], [S38], [S42] |

[BENCH] Âge des versions examinées au regard du principe VI (7 jours avant
toute mise à jour automatique). Keycloak 26.8.2 a 15 jours. L'image mesurée
est une republication du tag du 2026-11-19 : `26.8.2` a porté au moins trois
condensats entre le 2026-11-09 et le 2026-11-19, le projet reconstruisant
l'image dès qu'une base neuve résout des CVE [S65], [S66]. Zitadel v4.20.5 en
a 2 : la dernière version utilisable le 2026-11-20 est la v4.20.3 du
2026-11-13 [S20]. Authentik 2026.8.6 est sortie le jour de la lecture : la
2026.8.5 du 2026-10-21 est la dernière utilisable, et la 2026.8.6 le
deviendra le 2026-11-27 [S31]. Le chart de Zitadel suit l'application avec
retard : sa version 10.5.0 du 2026-11-05 porte l'`appVersion` v4.19.2 [S28].

[BENCH] Installations de référence. Keycloak : le manifest
`kubernetes/keycloak.yaml` du dépôt `keycloak-quickstarts`, au commit
`c598d34d` du 2026-11-05, que la page de démarrage sur Kubernetes applique par
`kubectl create -f` [S12], [S13]. Il crée un StatefulSet de deux répliques en
mode `start` (le commentaire du fichier propose une seule réplique pour
économiser les ressources), ses Services et une base Postgres 17 éphémère de
test. Zitadel et Authentik ne publient qu'un chart Helm [S26], [S38] : le
protocole en versionne le rendu, comme l'ADR-005 l'a fait pour la gateway, et
Helm n'entre pas dans les prérequis du projet généré. Zitadel tourne en deux
charges, l'API en Go et l'interface de connexion en Next.js, plus deux tâches
d'initialisation [S26]. Authentik n'a plus besoin de Redis depuis la
2025.10 : « authentik no longer uses Redis at all » [S39].

[BENCH] Pendant managé sur GCP, au sens du principe III et de la lecture de
l'ADR-009 : Identity Platform, le service de Google que nomme la section 5 du
brief. Il authentifie les utilisateurs d'une application [S47], fédère des
fournisseurs OpenID Connect et SAML, prend en charge plusieurs locataires et
annonce un SLA de 99,95 % [S46] ; il est en GA depuis le 2019-04-09, ses
locataires depuis le 2019-11-18, et sa dernière note de version date du
2024-12-03 [S48]. Le provider `google` qu'utilise l'ADR-008 a des ressources
`google_identity_platform_*` pour sa configuration, ses locataires et ses
fournisseurs fédérés [S52].

[BENCH] Ce pendant n'offre pas la même interface à l'application. La page des
concepts décrit une connexion par les SDK et les bibliothèques d'interface de
Google, et présente OpenID Connect et SAML comme des fournisseurs en amont ;
elle ne décrit aucun rôle de serveur d'autorisation pour une application
cliente, ni point d'autorisation ni enregistrement de client [S47]. Le jeton
reçu se vérifie par une bibliothèque JWT standard, émetteur
`https://securetoken.google.com/<projectId>` et clés publiées par
Google [S51]. Les trois options, elles, se présentent comme fournisseurs OpenID
Connect des applications [S28], [S42], [S44] ; M6 vérifiera leur document de
découverte et leur point de jeton. Conséquence pour l'ADR-013 : avec Identity
Platform sur GCP, la vérification du jeton par l'API peut rester commune aux
deux cibles, mais le parcours de connexion du front diffère, ce que le
principe II et ENF-02 demandent de contenir dans la couche de cible. L'autre
voie est la même option sur GKE, avec un `managed_gap` qui dit pourquoi
Identity Platform ne couvre pas le besoin. Le DSI pose la question à Lucas
pour l'ADR-013 (décision du 2026-11-21) : ce rapport présente les deux voies
sans les départager, et la grille ne les tranche pas (section 5.7).

[BENCH] Options repérées mais non étudiées : aucune hors du brief. Dex et la
suite Ory existent aussi ; le brief ne les nomme pas, et ils n'ont pas été lus
pour ce rapport.

## 3. Critères éliminatoires

[BENCH] Seuil de release : 2025-11-20, douze mois avant la vérification.

| Option | Licence open source | Ni archivé ni en maintenance | Release de moins de 12 mois | Vérifié le | Résultat |
| --- | --- | --- | --- | --- | --- |
| Keycloak | Oui, Apache-2.0 [S1], approuvée OSI [S45] | Oui, dépôt non archivé, dernier push le 2026-11-20 [S1] | Oui, 26.8.2 le 2026-11-05 [S2] | 2026-11-20 | Retenue |
| Zitadel | Oui, AGPL-3.0-only depuis la v3, avec des parties sous Apache-2.0 et MIT, dont l'interface de connexion sous MIT [S19], [S21] ; AGPL-3.0 approuvée OSI [S45] | Oui, dépôt non archivé, dernier push le 2026-11-20 [S19] | Oui, v4.20.5 le 2026-11-18 [S20] | 2026-11-20 | Retenue |
| Authentik | Non au sens strict. L'édition libre est sous MIT [S32], approuvée OSI [S45], mais l'image officielle contient `authentik/enterprise/` sous une licence propre, non approuvée par l'OSI [S33], [S35], [S57], et le serveur charge ce module quand il le trouve [S34] | Oui, dépôt non archivé, dernier push le 2026-11-20 [S30] | Oui, 2026.8.6 le 2026-11-20 [S31] | 2026-11-20 | Éliminée, décision du DSI du 2026-11-21 |

[BENCH] Authentik, critère de licence. Le gabarit demande une licence
approuvée par l'OSI « pour tout ce qui tourne sur le PC ». Le fichier de
licence du dépôt place `authentik/enterprise/` sous une licence à part [S32].
Celle-ci réserve l'usage en production aux titulaires d'un abonnement,
autorise la copie et la modification « for development and testing
purposes » sans abonnement, et interdit la redistribution [S33]. La page de
l'édition entreprise écrit qu'elle « uses the same container images » que
l'édition libre, ses fonctions s'activant par une clé de licence [S35] ; le
Dockerfile de la 2026.8.6 copie tout le dossier `authentik/` dans
l'image [S57]. Le fichier `settings.py` de la même version essaie d'importer
`authentik.enterprise.apps` et, s'il le trouve, l'ajoute aux applications
chargées en journalisant « Enabled authentik enterprise » [S34]. Du code
sous licence non libre s'exécute donc sur le PC avec l'image officielle,
même sans clé. Seule une image reconstruite sans ce dossier lèverait le
point : CELIAN la construirait et la tiendrait à jour, hors des images que
l'ADR-006 fait construire (l'API et le front). L'usage de développement reste
permis par la licence entreprise, ce qui pourrait suffire à une lecture moins
stricte pour la seule cible PC, pas pour l'on-prem que vise aussi le
principe III. [BENCH] a proposé l'élimination le 2026-11-20.

[BENCH] Décision du DSI du 2026-11-21, que Lucas peut renverser : Authentik
est éliminé sur le critère de licence. Le critère porte sur ce qui tourne sur
le PC, et l'image officielle charge au démarrage du code sous licence non
approuvée par l'OSI, même sans clé (Dockerfile, ligne 224 [S57] ;
`settings.py`, lignes 591 à 595 [S34]). Authentik n'est ni noté ni mesuré.
Si Lucas renverse la décision, ses notes de lecture se reprennent depuis les
faits de ce rapport (sections 2, 3, 8 et 9), et il faut une série de mesures à
part.

[BENCH] Zitadel, licence. AGPL-3.0 est approuvée par l'OSI [S45] : le critère
passe. Le changement de licence de 2025 (Apache-2.0 vers AGPL) se note en
5.1.

[BENCH] Options éliminées : Authentik, critère de licence, décision du DSI du
2026-11-21. Il reste deux options, Keycloak et Zitadel.

## 4. Mesures

### 4.1 Ce qui est mesuré

[BENCH] Seuils d'empreinte écrits le 2026-11-20 à 20:10 UTC, avant toute
mesure, avant tout test de fumée, et avant toute lecture de la documentation
des options ou de leurs registres. Le SHA-256 de cette section, du titre
« 4.1 » jusqu'à la ligne qui précède le titre « 4.2 », est relevé au même
moment dans le dossier de travail de [BENCH] (section 8). Chaque option part
de 5 et perd un cran par seuil dépassé (règle de `TEMPLATE.md`, section 5.6).
Le fournisseur d'identité est une couche de la stack : d'après la deuxième
règle de la GATE 1, il se note contre ses propres seuils, et son cumul avec la
plate-forme de base et les autres couches du profil standard va dans la
sensibilité. Les quatre seuils reprennent ceux des deux dernières couches,
l'outil GitOps de BENCH-009 et Postgres de BENCH-011, sans adaptation :

1. volume compressé des images de la couche au-delà de 112,5 Mo, lu sur
   linux_amd64 (première règle de la GATE 1) : 90 s à 10 Mbit/s, soit 10 % du
   budget de 900 s d'ENF-01 ;
2. au moins une image de la couche retéléchargée à chaque création du
   cluster, cache Docker de l'hôte plein : repris de BENCH-003 ;
3. installation jusqu'à « prêt » (médiane de M1) au-delà de 90 s, 10 % du
   budget, images tirées par le nœud sur le réseau du poste ;
4. mémoire de la couche au repos (médiane de M2) au-delà de 512 Mio, un
   seizième d'un portable de 8 Gio, lue au nœud moins le nœud de base
   (troisième règle de la GATE 1).

[BENCH] Périmètre de la couche. Elle comprend les images et les pods du
fournisseur d'identité et de tout ce qu'il exige en plus de Postgres. Postgres
n'en fait pas partie : le profil standard en fait déjà tourner un pour la
stack, dont la forme attend BENCH-011, et un fournisseur qui a besoin d'une
base y reçoit la sienne. Le nœud de base (M9) porte donc une instance
Postgres, la même pour toutes les options, si bien que la soustraction de M2
garde la charge que le fournisseur ajoute à la base, sans compter l'instance
elle-même. Si une option ne sait pas utiliser Postgres, son stockage entre
dans la couche.

[BENCH] Biais à déclarer : aucune taille d'image, aucune exigence de mémoire
et aucun temps de démarrage des options n'ont été lus avant ces seuils, qui
sont d'ailleurs ceux de BENCH-009, posés le 2026-11-19. Ils découlent du
budget d'ENF-01, du débit de 10 Mbit/s et du portable de 8 Gio. Les parts elles-mêmes (10 % du budget, un seizième de
8 Gio) restent un choix de [BENCH] : le budget par étape d'ENF-01 n'est pas
fixé (R-04).

[BENCH] « Prêt » veut dire : le document de découverte OIDC de l'émetteur de
test (`/.well-known/openid-configuration`) répond 200 avec un champ `issuer`
non vide, par le Service que l'application utilisera, depuis un pod client du
cluster. Le contrôle tourne une fois par seconde ; l'instant retenu est le
premier de trois succès de suite, comme dans BENCH-009 et BENCH-011.

| ID | Mesure | Unité | Critère alimenté | Script |
| --- | --- | --- | --- | --- |
| M1 | Installation jusqu'à « prêt » : du premier `kubectl apply` de la couche à la première de trois réponses valides du document de découverte, Postgres de base déjà prêt, nœud neuf, images tirées par le nœud | s | Empreinte sur PC | `tests/bench/bench-012-identity.sh` |
| M2 | Mémoire de la couche au repos, 120 s après « prêt » : nœud avec la couche moins nœud de base (M9), médianes de trois échantillons espacés de 10 s ; somme des pods de la couche en sensibilité | Mio | Empreinte sur PC | idem |
| M3 | CPU des pods de la couche au même moment | % d'un cœur | Empreinte sur PC | idem |
| M4 | Volume compressé des images de la couche, par architecture, lu au registre | Mo | Empreinte sur PC (ENF-01, R-04) | idem |
| M5 | Images de la couche retéléchargées à chaque création du cluster, d'après les événements `Pulled` du nœud | oui ou non | Empreinte sur PC (R-25) | idem |
| M6 | Parcours OIDC minimal : un jeton obtenu pour un client de test déclaré dans la configuration versionnée, puis vérifié contre les clés publiées par l'émetteur | oui ou non, et comment | Expérience dev, portabilité | idem |
| M7 | Retour à « prêt » après suppression du pod du fournisseur, cluster gardé, client de test toujours présent | s | Expérience dev | idem |
| M8 | Aucun identifiant d'administration par défaut : le premier compte d'administration porte la valeur d'un Secret créé par tube (ADR-007), et une authentification avec chaque valeur connue de la condition 1 de l'ADR-007 échoue | oui ou non | Sécurité (R-20) | idem |
| M9 | Mémoire du nœud de base : kind et l'instance Postgres de base, même image et même configuration (option `none` du script) | Mio | Base de M2 | idem |

### 4.2 Machine de mesure

[BENCH] Matériel et système relevés le 2026-11-20 ; moteur, ressources et
versions relevés au lancement de la série du 2026-11-21, et de nouveau à
celui de la série de référence du 2026-11-23 (`versions.tsv` de `series-4`,
sur batterie).

| Élément | Valeur |
| --- | --- |
| Modèle | Apple Mac16,7 (`sysctl hw.model`) |
| Processeur | Apple M4 Pro, 14 cœurs (10 performance, 4 efficacité), arm64 |
| Mémoire | 24 Gio (25 769 803 776 octets, `sysctl hw.memsize`) |
| Système | macOS 27.2.1 (build 26B131) |
| Moteur de conteneurs | OrbStack 2.2.5 (moteur non libre, voir R-26), Docker Engine 29.8.2, noyau 7.2.12-orbstack, cgroup v2, pilote overlay2 |
| Ressources allouées | Machine virtuelle d'OrbStack : 14 CPU, 11,73 Gio (12 598 894 592 octets, `docker info`) |
| Versions mesurées | kind 0.33.0 et image de nœud `kindest/node:v1.36.4@sha256:099e…faed` (ADR-004) ; kubectl 1.37.1 ; Keycloak 26.8.2 et Zitadel v4.20.5 (chart 10.5.0), images figées par condensat ; Postgres partagé `postgres:18.7-trixie` et client `busybox:1.37.0`, par condensat ; OpenSSL 4.1.0 sur l'hôte ; Helm 4.3.2 au seul rendu du chart |
| Charge parasite | Applications de bureau ouvertes ; charge moyenne relevée au début de chaque exécution (`load.tsv`) ; aucun autre conteneur de mesure, verrou partagé tenu par BENCH-012 pendant toute la série |

### 4.3 Protocole

[BENCH] Protocole tel que l'exécute `tests/bench/bench-012-identity.sh`,
écrit le 2026-11-21 après les décisions du DSI (section 3, et Postgres
partagé). Les écarts avec le protocole écrit le 2026-11-20 sont listés à la
fin de cette section.

1. Préparation, une fois par série. Le script télécharge par `gh` le manifest
   de référence de Keycloak au commit `c598d34d` [S12] et vérifie son SHA-256
   (`b4de5e35b234c11400192e805d4cb551c51e358f655be2196a51c2f9171fb9af`). La
   couche de Keycloak, `tests/bench/bench-012/keycloak/`, reprend ce manifest
   avec les seuls écarts listés en tête de `statefulset.yaml` : une réplique, comme le
   commentaire de la référence le permet ; l'image par condensat ; le
   Postgres partagé à la place de celui de la référence ; les identifiants lus
   dans des Secrets ; `start --import-realm` avec le royaume de test. La
   couche de Zitadel, `tests/bench/bench-012/zitadel/rendered/`, est le
   rendu, fait une fois le 2026-11-21 par `helm template` (Helm 4.3.2), du
   chart 10.5.0 (archive au SHA-256
   `e216ca1a9b19e9e2982e76a2cf49c446eeb3a02cdf167834977978acb880f019`) avec
   `values.yaml` : images v4.20.5 de l'API et de la connexion, `alpine/k8s`
   et `wait4x` du chart, toutes par condensat ; seule l'étape `init zitadel`
   du schéma, la base et le rôle existant déjà [S63] ; tâche de nettoyage
   retirée, parce que Helm ne la lance qu'à la désinstallation, alors
   qu'appliquée par kubectl elle tournerait à l'installation [S64]. Le rendu
   ne contient aucun Secret ; il est versionné un objet par fichier, le
   `check-yaml` du dépôt refusant les fichiers à plusieurs documents, découpage
   fait après la série et vérifié par un essai de contrôle (4.4). Le script
   relève le SHA-256 de chaque fichier de
   couche (`files.tsv`), refuse toute image sans condensat (condition 3 de
   l'ADR-004), et lit aux registres la taille compressée de chaque image par
   architecture, sans rien tirer (M4). Aucun manifest n'est appliqué depuis
   une URL (condition 4).
2. Départ de chaque exécution : aucun cluster `celian-bench-012`. Cluster kind
   neuf, image de nœud de l'ADR-004. Le script démarre le Postgres partagé,
   option « statefulset » de BENCH-011 inchangée (`postgres:18.7-trixie` par
   condensat), et attend `SELECT 1`. Pour une option, il crée le rôle et la
   base du fournisseur, puis ses Secrets : compte d'administration initial
   (36 caractères aléatoires suivis de `a.Z9`, la politique de mots de passe
   par défaut de Zitadel exigeant les quatre classes de caractères [S60]),
   secret du client de test (Keycloak), clé maître, DSN et paire de clés de la
   connexion V2 (Zitadel). Chaque valeur va de `/dev/urandom` au Secret par un
   tube (condition 1 de l'ADR-007) ; le mot de passe de la base passe du
   Secret à `psql` par un tube ; la paire de clés reste en mémoire, d'openssl
   au tube. Il démarre enfin un pod client busybox figé par condensat. Les
   images de la couche ne sont pas préchargées : le nœud les tire à chaque
   exécution.
3. M1 : chronomètre au `kubectl apply -k` de la couche, arrêt au premier de
   trois contrôles réussis du document de découverte, à une seconde
   d'intervalle, depuis le pod client par le Service. curl et wget étant
   exclus, le client HTTP est `tests/bench/bench-012/client/http.sh` : une
   requête HTTP/1.0 que le `nc` de busybox envoie par son option `-e`,
   bornée à 8 s. Chaque contrôle passe par `kubectl exec`.
4. M6, dès « prêt ». Keycloak : jeton par `client_credentials` pour le client
   du royaume importé, le secret étant lu dans l'environnement du pod client.
   Zitadel : faute de client déclaratif au démarrage, le pod crée par l'API de
   gestion un utilisateur machine à jetons JWT, lui génère un secret et
   demande un jeton, avec le PAT que la tâche de setup du chart range dans un
   Secret [S61], [S64] ; le secret du client ne sort pas du pod. Sur l'hôte,
   le script reconstruit avec openssl la clé publique RSA que désigne le `kid`
   dans le `jwks_uri`, vérifie la signature RS256, l'émetteur et l'expiration,
   relève `aud`, `azp` et `client_id` sans les juger, puis efface le jeton.
5. M8 : sept valeurs connues : les six de la condition 1 de l'ADR-007 et
   `Password1!`, défaut de l'administrateur humain dans `steps.yaml` de
   Zitadel [S59], puis la valeur du Secret. Keycloak : `grant_type=password`
   sur le royaume master avec le client `admin-cli`, pour l'utilisateur
   `admin` ; Zitadel : création de session (`POST /v2/sessions`) avec
   vérification de l'utilisateur et du mot de passe de l'administrateur
   humain [S62]. Le verrouillage après échecs est désactivé par défaut chez
   Zitadel [S60] ; chez Keycloak, la détection de force brute n'est pas
   activée par le protocole. La condition 10 de l'ADR-012 a ajouté
   `mysecretpassword`, que le script de la série ne testait pas ; sans effet
   sur M8, la valeur du Secret étant aléatoire. Le script versionné l'ajoute
   depuis la relecture de [SECU].
6. M2, M3 : pod client ramené à zéro, 120 s d'attente, trois échantillons à
   10 s de l'API Summary du kubelet pour les pods du namespace du
   fournisseur, et du nœud par `docker stats` ; médianes.
7. M7 : suppression du pod du fournisseur (pour Zitadel, celui de l'API, pas
   celui de la connexion), chronomètre jusqu'au premier de trois contrôles
   réussis, puis un nouveau jeton pour le même client.
8. M5 : événements `Pulled` du nœud. Fin : suppression du cluster, 15 s de
   pause. Trois exécutions par option, alternées avec le nœud de base
   (option `none`, M9) : même cluster, même Postgres partagé et même pod
   client, sans fournisseur.

[BENCH] Garde-fous du script : inventaire en tête des commandes qui créent,
modifient ou suppriment un conteneur ou un réseau (règle de [SECU] du
2026-11-20) ; `kind create cluster` lance lui-même le nœud par
`docker run --privileged` (BENCH-011, S60) ; aucun `docker run`, `start`,
`restart`, `exec`, `cp`, `build` ni `pull` ; ni curl, ni wget, ni python, ni
node, ni perl. Deux lectures sortent du poste : `gh api` vers GitHub, avec le
jeton de l'utilisateur, et `docker manifest inspect` vers les registres. Le
verrou n'est pris que si `BENCH_LOCK` est défini. Verrou partagé
(`BENCH_LOCK`, refus en code 75 s'il est pris), refus si le cluster existe
déjà, `trap` posé après ces contrôles, `umask 077`, `KUBECONFIG` dans le
dossier d'essai. Aucune valeur secrète, aucun jeton ni aucune clé dans les
données gardées. Une exécution est refusée si l'horloge saute pendant l'attente
au repos, ou si le journal d'alimentation (`pmset -g log`) montre une mise en
veille depuis son début ; `caffeinate` empêche la veille sur inactivité, pas
celle du capot fermé sur batterie. shellcheck, bash 3.2 de macOS.

[BENCH] Écarts avec le protocole du 2026-11-20. Le Postgres de base est celui
d'O1 de BENCH-011, décision du DSI du 2026-11-21. Keycloak tourne en mode
`start`, décision du même jour. La vérification du jeton se fait sur l'hôte
par openssl, aucun outil de vérification en image n'ayant été retenu. Le
contrôle d'audience prévu se réduit à un relevé : les deux fournisseurs ne
remplissent pas les mêmes revendications pour `client_credentials`. Les
valeurs connues de M8 s'enrichissent de `Password1!`.

Pour refaire la mesure :

```bash
caffeinate -i -s env BENCH_LOCK=/chemin/vers/un/verrou tests/bench/bench-012-identity.sh /chemin/vers/un/dossier/vide
```

[BENCH] Le nœud de base (M9) fait partie de la série par défaut
(`OPTIONS="none keycloak zitadel"`).

### 4.4 Résultats

[BENCH] Mesures de référence : la série lancée le 2026-11-23 à 20:39 UTC et
finie à 21:16 UTC, sur la machine de la section 4.2, trois exécutions par
option et trois du nœud de base, alternées, toutes complètes (série
`series-4`, code de sortie 0). Seuils revérifiés juste avant, empreinte
inchangée (section 8). Le journal d'alimentation de l'hôte ne montre aucune
mise en veille pendant la série.

[BENCH] Ce qui a tourné avant, et pourquoi ce n'est pas retenu. Quatre tests
de fumée, du 2026-11-20 à 23:33 UTC au 2026-11-21 à 00:08 UTC, tous après
l'écriture des seuils, ont servi à mettre au point le client HTTP du pod de
test : le `nc` de busybox s'arrête à la fin de son entrée sans attendre la
réponse, puis, entrée tenue ouverte, ne rend pas la main quand le serveur
ferme ; d'où `nc -e` et la borne de 8 s. Trois séries ont ensuite échoué,
toutes pour la même cause : l'ordinateur, sur batterie, s'est mis en veille
capot fermé (« Clamshell Sleep » dans `pmset -g log`), ce que `caffeinate` ne
peut empêcher. La série lancée le 2026-11-21 à 00:08 UTC a été arrêtée par
ces veilles et nettoyée à 20:01 UTC le même jour ; un défaut du script lui
avait aussi fait continuer une exécution dont l'échantillonnage avait échoué.
Les séries lancées le 2026-11-21 à 20:04 et à 21:44 UTC, script corrigé, ont
chacune refusé leur dernière exécution au moment de la veille. La première a
même démarré pendant une veille : l'ordinateur s'est mis en veille capot fermé
à 20:04:26 UTC, 19 s après le lancement, et ne s'est réveillé qu'à
21:18:04 UTC (`pmset -g log`, relu le 2026-11-24, réponse à la question de
[FINOPS]). Entre les deux, la préparation n'a avancé que pendant les réveils
de maintenance, et la lecture des tailles aux registres n'a rendu aucune
taille pour les deux images de base ; la première exécution commence au
réveil, à 21:18:04 UTC (`runs.tsv`, `load.tsv`). La seconde série commence la
sienne à 21:45:16 UTC. Les exécutions complètes de ces
deux séries (nœud de base 2 et 2, Keycloak 2 et 2, Zitadel 1 et 1), faites
hors veille, donnent des valeurs du même ordre que la série de référence ;
elles ne servent pas à la notation. Aucune exécution incomplète n'est
reprise.

| Mesure | Option | Exécution 1 | Exécution 2 | Exécution 3 | Médiane | Écart |
| --- | --- | --- | --- | --- | --- | --- |
| M1, installation jusqu'à « prêt » (s) | Keycloak | 25,7 | 25,5 | 27,8 | 25,7 | 2,3 |
| M1, installation jusqu'à « prêt » (s) | Zitadel | 19,7 | 43,8 | 21,6 | 21,6 | 24,1 |
| M2, mémoire du nœud au repos (Mio) | Keycloak | 1 503,2 | 1 184,8 | 1 517,6 | 1 503,2 | 332,8 |
| M2, mémoire du nœud au repos (Mio) | Zitadel | 882,4 | 940,0 | 922,9 | 922,9 | 57,6 |
| M9, mémoire du nœud de base (Mio) | aucune | 682,3 | 654,2 | 660,0 | 660,0 | 28,1 |
| M2, somme des pods de la couche (Mio) | Keycloak | 819,9 | 538,2 | 828,0 | 819,9 | 289,8 |
| M2, somme des pods de la couche (Mio) | Zitadel | 191,2 | 185,0 | 189,4 | 189,4 | 6,2 |
| M3, CPU des pods au repos (% d'un cœur) | Keycloak | 0,7 | 0,8 | 1,1 | 0,8 | 0,4 |
| M3, CPU des pods au repos (% d'un cœur) | Zitadel | 2,1 | 1,7 | 2,3 | 2,1 | 0,6 |
| M7, retour à « prêt » après suppression du pod (s) | Keycloak | 21,4 | 12,8 | 21,4 | 21,4 | 8,6 |
| M7, retour à « prêt » après suppression du pod (s) | Zitadel | 9,2 | 9,2 | 9,2 | 9,2 | 0,0 |

[BENCH] Mémoire de la couche, règle de la GATE 1 (nœud moins nœud de base, en
médianes) : Keycloak 1 503,2 moins 660,0 = 843,2 Mio ; Zitadel 922,9 moins 660,0 =
262,9 Mio. Pour Keycloak, la deuxième exécution reste basse, au nœud
(1 184,8 Mio) comme au pod (538,2 Mio), sans cause établie ; un tas de JVM
encore petit, sous la limite de 2000Mi du manifest, l'expliquerait, sans
vérification. Les quatre exécutions complètes de Keycloak des séries du
2026-11-21, non retenues, donnent de 838,8 à 841,2 Mio au pod : la valeur
basse reste isolée. Les pods de Zitadel sont l'API et la connexion V2 : dans
l'échantillon médian de chaque exécution, l'API tient de 85,2 à 93,0 Mio et la
connexion de 98,2 à 99,8 ; sur les neuf échantillons, de 85,0 à 122,7 et de
80,0 à 99,8.

| Mesure | Keycloak | Zitadel |
| --- | --- | --- |
| M4, volume compressé de la couche, linux_amd64 | 265,1 Mo, une image | 463,8 Mo, quatre images : `alpine/k8s` 316,7, `zitadel-login` 78,5, `zitadel` 54,1, `wait4x` 14,5 |
| M4, même volume, linux_arm64 | 263,5 Mo | 436,1 Mo |
| M5, images de la couche retéléchargées à chaque création du cluster | oui, aux trois exécutions | oui, aux trois exécutions |
| M6, jeton du client de test vérifié (signature RS256, émetteur, expiration) | oui, 6 sur 6 (après « prêt » et après M7) | oui, 6 sur 6 ; client créé par l'API, pas déclaré |
| M8, valeurs connues refusées ; valeur du Secret acceptée | 7 sur 7 refusées (HTTP 400), acceptée (200), aux trois exécutions | 7 sur 7 refusées (HTTP 400), acceptée (201), aux trois exécutions |
| Redémarrages des pods de la couche avant le repos | 0, 0, 0 | 2, 3, 2 : l'API redémarre tant que la tâche de setup n'a pas fini |

[BENCH] M1 de Zitadel à 43,8 s à la deuxième exécution : le pod de l'API a
redémarré trois fois au lieu de deux. Le temps de tirage de ses images est
resté du même ordre (`node-images.tsv`).

[BENCH] Essai de contrôle, le 2026-11-23 de 21:45 à 21:51 UTC, avec le script
et les fichiers tels que versionnés, couches découpées en un objet par fichier
(section 4.3) : une exécution par option, attente au repos réduite à 10 s.
Keycloak prêt en 30,1 s, Zitadel en 17,5 s ; jeton vérifié et valeurs
connues refusées pour les deux. Il ne sert pas à la notation.

[BENCH] Données brutes dans le dossier d'essai de [BENCH] : `runs.tsv`,
`idle-pods.tsv`, `oidc.tsv`, `admin.tsv`, `images.tsv`, `node-images.tsv`,
`load.tsv`, `files.tsv`, `versions.tsv`. Aucune valeur secrète, aucun jeton
ni aucune clé n'y figure : `oidc.tsv` ne garde que le résultat, l'algorithme,
l'identifiant de clé et les revendications d'audience.

## 5. Notation par critère

Chaque option retenue reçoit une note entière de 0 à 5 sur chaque critère.
Les points valent note × poids / 5. Un cran de note vaut donc 3 points sur un
critère de poids 15, 2 points sur un poids 10 et 1 point sur le coût. Les
poids sont ceux de la section 8 du brief et ne changent pas d'un rapport à
l'autre.

| Note | Sens |
| --- | --- |
| 5 | Répond pleinement au critère, preuve directe |
| 4 | Répond, avec une réserve mineure écrite |
| 3 | Répond en partie, la réserve demande une action |
| 2 | Répond mal, il faut contourner |
| 1 | Répond à peine |
| 0 | Ne répond pas |

- Chaque note cite au moins une source [Sn] ou une mesure [Mn]. Une note sans
  preuve n'entre pas dans la grille, et le rapport reste en brouillon tant
  qu'elle manque.
- Un critère qui ne départage pas les options reçoit la même note pour
  toutes, avec la raison écrite.
- Une option éliminée à la section 3 n'est pas notée.

[BENCH] Notes de lecture écrites le 2026-11-20, reprises après les mesures du
2026-11-21 : la note d'empreinte (5.6) vient des mesures, la note
d'expérience dev (5.8) s'appuie désormais sur l'essai, et la note de sécurité
(5.5) intègre M8. Authentik, éliminé à la section 3, n'est pas noté.

### 5.1 Licence et liberté d'usage, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Keycloak | 5/5 | 15 | Apache-2.0, la licence du générateur ; fichier de licence inchangé depuis son ajout le 2019-11-08. Le manifest de démarrage rapide vient d'un dépôt sous Apache-2.0. L'image repose sur Red Hat UBI 9 micro, dont le contrat laisse chaque composant sous sa licence libre, sans abonnement ni limite d'usage ; une image dérivée redistribuée joint ce contrat et ne se dit pas soutenue par Red Hat | [S1], [S12], [S18], [S45], [S67] |
| Zitadel | 3/5 | 9 | AGPL-3.0-only depuis la v3 : le passage d'Apache-2.0 à l'AGPL est fusionné dans `v3.x` le 2025-03-27 (PR #9597), puis dans `main` le 2025-04-02 avec la v3 (PR #9645). Les contributions ne sont acceptées que sous Apache-2.0 et l'éditeur vend une licence commerciale : un prochain changement ne dépend que de lui. L'AGPL ne pèse pas sur un projet généré qui tire l'image sans la modifier, et se signale si l'utilisateur la modifie et l'expose (pièges du brief, section 5). Chart sous Apache-2.0. Action : relire la licence à chaque vérification du catalogue | [S19], [S21], [S22], [S28], [S45], [S75] |

### 5.2 Gouvernance (fondation, multi-vendeurs), poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Keycloak | 4/5 | 12 | En incubation à la CNCF depuis le 2023-04-10. 11 mainteneurs actifs de quatre employeurs : 8 chez IBM, un chez Robert Bosch, un chez Hitachi, un chez Identity Tailor ; un nouveau mainteneur demande l'accord des deux tiers d'entre eux. 3 470 commits humains par 177 auteurs en 12 mois, le premier à 12,6 %, les trois premiers à 22,6 %. Réserve : IBM tient 8 mainteneurs sur 11, les six premiers auteurs humains se déclarent chez IBM ou Red Hat, et Red Hat vend une version supportée | [S3], [S4], [S5], [S7], [S53], [S56] |
| Zitadel | 2/5 | 6 | Éditeur unique, ZITADEL, sans fondation. 817 commits humains par 34 auteurs en 12 mois, le premier à 20,0 %, les trois premiers à 41,3 % ; les six premiers déclarent Zitadel pour employeur. Le principe V demanderait un ADR pour justifier l'écart | [S19], [S21], [S54], [S56] |

### 5.3 Maturité et adoption, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Keycloak | 4/5 | 12 | Premier commit le 2013-07-02, version majeure 26 depuis le 2024-10-04. 59 organisations en référence publique dans `ADOPTERS.md`, liste tirée de l'enquête communautaire. Red Hat en vend une version à support long. Réserve : Incubating à la CNCF depuis le 2023-04-10, sans demande de graduation trouvée ; certifications OpenID sur 18.0.0 et 15.0.2 seulement | [S2], [S5], [S6], [S7], [S44], [S81] |
| Zitadel | 3/5 | 9 | Dépôt créé le 2020-03-16, v1.0.0 le 2021-04-20. Trois versions majeures depuis, dont la v3 (2025-05-02) et la v4 (2025-07-31) à trois mois d'écart, avec des ruptures : retrait de CockroachDB, API migrées. 16 lignes, éditeur compris, dans une liste d'adoptants tenue par les adoptants eux-mêmes. Absent des implémentations certifiées OpenID lues. Action : prévoir les montées de version majeure dans `copier update` | [S20], [S22], [S25], [S44] |

### 5.4 Activité et maintenance, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Keycloak | 5/5 | 10 | 24 releases stables en 12 mois, de la 26.4.6 à la 26.8.2, environ quatre mineures par an selon `RELEASES.md`. 3 470 commits humains par 177 auteurs, dernier push le 2026-11-20 | [S1], [S2], [S8], [S53] |
| Zitadel | 5/5 | 10 | 58 releases stables en 12 mois : 47 de la v4.7.1 à la v4.20.5, et 11 sur la branche v3.4, jusqu'à la v3.4.15 du 2026-08-14. 817 commits humains par 34 auteurs, dernier push le 2026-11-20 | [S19], [S20], [S54] |

### 5.5 Sécurité (CVE, réactivité), poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Keycloak | 3/5 | 6 | Politique tirée du modèle de la CISA, accusé de réception sous 7 jours ouvrés, correctifs sur la dernière mineure seulement. 21 avis au dépôt en 12 mois ; dans la base mondiale, 74 CVE dédoublonnées sur quatre paquets Maven (1 critique, 24 élevées), dont CVE-2026-18963, prise de compte sans authentification corrigée en 26.7.2. Une partie des CVE des tickets n'a pas de paquet dans cette base, hors de portée des scanners. Image sans signature ; tag `26.8.2` republié trois fois du 2026-11-09 au 2026-11-19. Force brute désactivée par défaut. M8 refuse les sept valeurs connues et accepte celle du Secret à chaque exécution. La réserve demande une action : suivre chaque mineure, dérogation datée à ENF-03, royaumes durcis | [M8], [S7], [S9], [S10], [S12], [S18], [S65], [S66], [S68], [S69] |
| Zitadel | 2/5 | 4 | Signalement par un portail de l'éditeur. 55 avis publiés en 12 mois, dont 6 critiques : cinq prises de compte, dont trois sans authentification, et une SSRF sans authentification ; 31 élevés, dont six publiés entre le 2026-11-13 et le 2026-11-18. Aucune signature d'image dans le flux de publication lu. 31 des 55 avis, dont 4 des 6 critiques, ne sont associés à aucun module Go dans la base mondiale, que Trivy lit pour les modules Go. La tâche de setup tire `docker.io/alpine/k8s`, image tierce non signée, sous un compte de service qui écrit les Secrets du namespace ; le PAT d'`iam-admin` vaut jusqu'au 2029-01-01. Le démarrage rapide documente un mot de passe d'administration connu, `Password1!`, défaut de `steps.yaml` ; avec un mot de passe tiré au hasard, M8 refuse les sept valeurs connues et accepte celle du Secret, à chaque exécution | [M8], [S23], [S24], [S26], [S29], [S59], [S68], [S73], [S79] |

### 5.6 Empreinte sur PC (RAM, CPU, démarrage), poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Keycloak | 2/5 | 4 | Trois seuils dépassés sur quatre : volume de 265,1 Mo sur linux_amd64, au-delà de 112,5 Mo ; image retéléchargée à chaque création du cluster ; mémoire de la couche de 843,2 Mio, au-delà de 512 Mio. Installation en 25,7 s, sous 90 s | [M1], [M2], [M4], [M5], [M9] |
| Zitadel | 3/5 | 6 | Deux seuils dépassés sur quatre : volume de 463,8 Mo sur linux_amd64, dont 316,7 pour l'image `alpine/k8s` de la tâche de setup ; images retéléchargées à chaque création. Mémoire de la couche de 262,9 Mio, sous 512 Mio ; installation en 21,6 s, sous 90 s | [M1], [M2], [M4], [M5], [M9] |

[BENCH] Sensibilité. Aucune option n'est à moins de 10 % d'un seuil en
médiane. Sur la mémoire, la deuxième exécution de Keycloak donnerait
524,8 Mio, encore au-dessus de 512 ; la somme des pods, lecture de
sensibilité, donne 819,9 Mio pour Keycloak et 189,4 Mio pour Zitadel, sans
changer de côté. Sur le volume, Zitadel sans `alpine/k8s` pèserait 147,1 Mo,
toujours au-delà du seuil ; il faudrait retirer aussi la connexion V2 et
`wait4x` pour descendre à 54,1 Mo, ce qui changerait l'installation de
référence. Le deuxième seuil, dépassé par les deux options, ne le serait plus
avec le miroir zot de l'ADR-011, accepté après l'écriture de ces seuils, qui,
d'après cet ADR, garde les images au-delà de la recréation du cluster, à
condition que leurs registres passent par lui : quay.io pour Keycloak, que
l'ADR-011 ne liste pas encore, et docker.io et ghcr.io pour Zitadel, que le
profil standard demande déjà (condition 10 de l'ADR-011, mécanisme à plusieurs
amonts non établi) : les deux options regagneraient le même cran, Keycloak à
3/5 et Zitadel à 4/5, et l'écart resterait de 19 points. La mesure suit le
protocole écrit, sans miroir.

[BENCH] Cumul avec le reste du profil standard, en sensibilité (deuxième
règle de la GATE 1, relecture [FINOPS]). Le premier `task up` télécharge
1 521,9 Mo en amd64 avant ce benchmark, miroir zot de l'ADR-011 et Postgres
de l'ADR-012 compris, Mailpit non compté (R-04). Avec Keycloak : 1 787,0 Mo,
soit 1 429,6 s à 10 Mbit/s, 158,8 % du budget de 900 s, et 15,9 Mbit/s au
minimum. Avec Zitadel : 1 985,7 Mo, 1 588,5 s, 176,5 %, 17,7 Mbit/s.

### 5.7 Portabilité multi-cloud, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Keycloak | 5/5 | 10 | Image et manifest ordinaires (StatefulSet, Services) pour tout cluster conforme, donc kind comme GKE ; opérateur publié à part. PostgreSQL 14 à 18 pris en charge, dont la 18, défaut de Cloud SQL (ADR-009) : sur GKE, sa base pourrait rester managée. Architectures des images à relever en M4 | [S8], [S12], [S17] |
| Zitadel | 4/5 | 8 | Chart Helm pour tout cluster 1.30 ou plus ; PostgreSQL 14 à 18 ; images construites pour amd64 et arm64. Réserve : la console exige HTTP/2 de bout en bout, en h2c jusqu'aux pods, réglage à vérifier avec Envoy Gateway (ADR-005) | [S26], [S29] |

[BENCH] Le principe III n'entre pas dans cette note, qui mesure ce qui tourne
où, comme dans BENCH-009. Il ne départagerait pas les options : sur GCP, le
pendant managé est Identity Platform pour chacune, et son parcours de
connexion diffère de celui des trois serveurs OpenID Connect (section 2) ;
l'autre voie, la même option sur GKE avec un `managed_gap`, reste ouverte aux
trois. Ce choix revient à l'ADR-013.

### 5.8 Expérience dev et documentation, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Keycloak | 4/5 | 8 | Installé, prêt et servant un jeton vérifié à chaque exécution, avec le manifest de démarrage rapide et ses seuls écarts listés ; le client de test se déclare dans le royaume importé au démarrage, secret lu dans l'environnement. Documentation par guide, avec sélecteur de version (26.8.2) ; compte d'administration d'amorçage par variables, temporaire par conception. Réserve : le manifest de démarrage écrit ses identifiants en clair, la documentation juge l'import au démarrage surtout utile en mode dev, et la construction optimisée qu'elle recommande demande une image construite par le projet | [M1], [M6], [M7], [S12], [S13], [S14], [S15], [S16] |
| Zitadel | 3/5 | 6 | Installé, prêt et servant un jeton vérifié à chaque exécution, mais au prix de quatre gestes propres à l'option : rendre le chart et en retirer la tâche de nettoyage, qu'un `kubectl apply` lancerait à l'installation ; préparer la base et réduire l'initialisation à l'étape du schéma ; fournir la paire de clés de la connexion V2 ; créer le client de test par l'API après « prêt », aucun mécanisme déclaratif n'apparaissant dans les pages lues. Le pod de l'API redémarre pendant la tâche de setup. Documentation versionnée (v4.20) ; la clé maître ne change plus après l'initialisation, et HTTP/2 doit être tenu de bout en bout | [M1], [M6], [M7], [S26], [S27], [S63], [S64] |

[BENCH] Note de jugement. L'essai qui la fonde : installation par le
protocole de 4.3, parcours OIDC de M6 et redémarrage de M7, trois fois par
option, sans intervention, après quatre tests de fumée qui ont surtout servi
à mettre au point le client HTTP du pod de test (section 4.4).

### 5.9 Coût (managé ou opérationnel), poids 5

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Keycloak | 4/5 | 4 | Gratuit sur le PC : Apache-2.0, aucun service payant ; suivi des mineures compté en 5.5 et construction optimisée en 5.8 (règle de BENCH-008). Sur GCP, le coût dépend de la voie de l'ADR-013. Identity Platform est sans frais jusqu'à 50 000 utilisateurs actifs par mois, et jusqu'à 50 sur la ligne SAML/OIDC ; prix au-delà non lus. Sur GKE Autopilot, la référence demande 500m et 1700Mi par réplique : environ 22,2 USD par réplique et par mois aux prix d'exemple de us-central1, 44,4 USD pour les deux répliques par défaut, hors stockage éphémère et base. Réserve : coût sur GCP à trancher | [S12], [S50], [S82], [S83], [S84] |
| Zitadel | 4/5 | 4 | Gratuit sur le PC, même règle : montées de majeure comptées en 5.3, gestes d'installation en 5.8. Même pendant managé. Sur GKE, le chart 10.5.0 ne fixe aucune demande de ressources : Autopilot appliquerait 0,5 vCPU et 2 Gio à chacun des deux pods, environ 46,9 USD par mois aux mêmes prix, ou 19,8 USD au minimum sans rafale ; rien n'est mesuré sur GKE. Même réserve | [S50], [S64], [S82], [S83], [S84] |

[BENCH] Le coût ne départage pas les options : licence gratuite sur le PC,
temps d'exploitation compté en 5.3, 5.5 et 5.8, et même pendant managé sur
GCP. Une démo reste dans la franchise d'Identity Platform. Sur la voie de
l'option sur GKE, les pods se paient à l'heure, de 20 à 47 USD par mois
environ selon les demandes, aux prix d'exemple de us-central1 et non à la
grille, illisible le 2026-11-23 ; la région n'est pas choisie (R-05).

## 6. Grille pondérée

| Critère | Poids | Keycloak | Zitadel | Authentik |
| --- | --- | --- | --- | --- |
| Critères éliminatoires (section 3) | éliminatoire | passe | passe | éliminée (licence) |
| Licence et liberté d'usage | 15 | 5/5, 15 pts | 3/5, 9 pts | éliminée |
| Gouvernance (fondation, multi-vendeurs) | 15 | 4/5, 12 pts | 2/5, 6 pts | éliminée |
| Maturité et adoption | 15 | 4/5, 12 pts | 3/5, 9 pts | éliminée |
| Activité et maintenance | 10 | 5/5, 10 pts | 5/5, 10 pts | éliminée |
| Sécurité (CVE, réactivité) | 10 | 3/5, 6 pts | 2/5, 4 pts | éliminée |
| Empreinte sur PC (RAM, CPU, démarrage) | 10 | 2/5, 4 pts | 3/5, 6 pts | éliminée |
| Portabilité multi-cloud | 10 | 5/5, 10 pts | 4/5, 8 pts | éliminée |
| Expérience dev et documentation | 10 | 4/5, 8 pts | 3/5, 6 pts | éliminée |
| Coût (managé ou opérationnel) | 5 | 4/5, 4 pts | 4/5, 4 pts | éliminée |
| Total | 100 | 81 / 100 | 62 / 100 | éliminée |

## 7. Verdict proposé

[BENCH] Option proposée pour le cluster local : Keycloak, 81 sur 100, 19
points devant Zitadel (62). L'ADR-013, écrit par [ARCHI], tranche ; Lucas
valide.

[BENCH] Pourquoi. L'avance se fait sur les critères de lecture : licence
(Apache-2.0, comme le générateur, contre une AGPL adoptée en 2025 [S22]),
gouvernance (CNCF, mainteneurs de quatre employeurs [S3], [S5], contre un
éditeur unique), maturité (treize ans, version majeure stable depuis 2024,
contre trois majeures en quatre ans) et sécurité, où Zitadel a publié six
avis critiques en douze mois, dont trois prises de compte sans
authentification [S24]. Zitadel ne reprend l'avantage que sur l'empreinte,
d'un cran : 262,9 Mio de mémoire de couche contre 843,2 [M2], pour un volume
pourtant plus lourd (463,8 Mo contre 265,1 [M4]). Les deux options ont passé
tous les contrôles fonctionnels, à chaque exécution : jeton vérifié contre
les clés de l'émetteur [M6], aucune valeur connue acceptée pour
l'administrateur [M8].

[BENCH] Sensibilité. Un cran vaut au plus 3 points : il faudrait au moins
sept crans dans le sens de Zitadel pour combler l'écart. Les mesures ne le
peuvent pas : l'empreinte pèse 10 points, et Keycloak garderait 11 points
d'avance avec 0/5 contre 5/5 à Zitadel. Le verdict ne repose sur aucun
critère isolé. Si Lucas renversait l'élimination d'Authentik, ses notes de
lecture du 2026-11-20 (62 points sur 90 hors empreinte, avant suppression de
ses lignes) le placeraient derrière Keycloak en tout état de cause.

[BENCH] Gouvernance : Keycloak est porté par une fondation, la CNCF, au
niveau Incubating [S5] ; le principe V ne demande pas de justification. La
réserve porte sur le poids d'IBM, 8 mainteneurs sur 11 [S3].

[BENCH] Réserves. D'abord l'empreinte : 843,2 Mio au nœud, à compter dans la
mémoire minimale du profil standard (US-005, condition 6 de l'ADR-004), et
265,1 Mo de plus au premier `task up`, qui le portent à 1 787,0 Mo avec zot
et le Postgres de l'ADR-012, soit 158,8 % du budget à 10 Mbit/s avant Mailpit
(R-04). Le profil standard passe à 3,5 Gio de VM et 7,5 Gio de portable,
435,7 Mio sous la limite d'un portable de 8 Gio avant Mailpit (relecture
[FINOPS]) : la limite mémoire du pod reste à fixer et à mesurer sur le golden
repo. Ensuite la cadence des correctifs :
la dernière mineure seule est corrigée [S7], [S8], et 228 tickets de CVE hors
dépendances ont été ouverts en douze mois [S11] ; le blueprint doit suivre
chaque mineure. Enfin les identifiants : le manifest de démarrage écrit
`admin`/`admin` [S12] ; le golden repo garde les écarts de la couche de
mesure (Secrets créés par un tube, aucun identifiant en clair), et un contrôle
du type de M8 est à proposer pour la matrice de validation. Aucune image
n'est signée : l'ADR-013 porte une dérogation à ENF-03 pour
`quay.io/keycloak/keycloak`, celle de l'ADR-012 ne couvrant que
`docker.io/library`. Les réglages `start` du PC ne passent pas sur GKE, et la
force brute s'active sur chaque royaume (relecture [SECU]). Prochaine
vérification : 2027-05-23, six mois après les mesures (ADR-009).

[BENCH] Question ouverte pour Lucas, posée par le DSI pour l'ADR-013 et non
tranchée ici : sur GCP, Identity Platform (principe III), avec un parcours de
connexion du front propre à la couche `gcp` [S47], ou Keycloak sur GKE avec
un `managed_gap`, au prix de pods facturés (la référence demande 500m de CPU
et 1700Mi par réplique [S12], soit environ 22,2 USD par réplique et par mois
aux prix d'exemple de us-central1 [S83], hors stockage éphémère et base ;
Identity Platform reste sans frais jusqu'à 50 000 utilisateurs actifs par
mois, et jusqu'à 50 sur la ligne SAML/OIDC [S82]) et de la base dans Cloud
SQL, que Keycloak prend en charge en PostgreSQL 18 [S17]. La première voie
garde le principe III et coûte un écart d'interface entre les cibles ; la
seconde garde la parité et coûte un composant à exploiter sur la cible cloud.

[BENCH] Suites proposées. L'ADR-013 ([ARCHI]). Une entrée `identity` au
catalogue : cible `local` de type `oss`, Keycloak 26.8.2, `Apache-2.0`,
gouvernance `foundation` (CNCF), statut `active`, dernière release le
2026-11-05, sources [S1], [S2], [S5] ; cible `gcp` en `pending` jusqu'à la
réponse de Lucas. Pour `docs/risques.md`, à décider par le DSI : R-20
confirmé pour Keycloak et pour Zitadel, avec les défauts relevés ([S12],
[S59]) ; R-04 relevé de 265,1 Mo, à 1 787,0 Mo avec zot (158,8 % du budget,
15,9 Mbit/s au minimum) ; quay.io à ajouter à la liste unique des registres
du miroir (condition 10 de l'ADR-011) ; un risque nouveau si Identity
Platform est retenu, « parcours de connexion différent entre le PC et GCP ».

[DSI] Arbitrage du 2026-11-24, après les relectures de [SECU] et de
[FINOPS]. Keycloak 26.8.2 est retenu comme fournisseur d'identité sur la
cible `local`, à 81 sur 100 dans la grille réconciliée, devant Zitadel (62).
La maturité de Keycloak passe à 4, comme pour tout projet Incubating de la
CNCF dans BENCH-004 et BENCH-011. Lucas a tranché le même jour trois points.
Sur la cible `gcp`, le projet généré utilise Identity Platform, service managé
de Google, conformément au principe III : une démo reste dans sa franchise,
et le parcours de connexion du front devient propre à la cible, ce que le
golden repo devra tester. Keycloak reçoit sa propre dérogation datée à
ENF-03, sur le modèle de l'ADR-012 : `quay.io/keycloak/keycloak` est admise
par sa référence exacte, condensat compris, dans une liste fermée que [SECU]
relit à chaque montée, republications comprises ; elle tombe quand Keycloak
signe ses images de façon vérifiable par Kyverno. Authentik reste éliminé sur
le critère de licence, preuve revérifiée par [SECU]. L'ADR-013, à écrire par
[ARCHI], reprend les conditions 1 à 10 de [SECU] et les trois conditions de
[FINOPS] : une limite mémoire de Keycloak fixée et mesurée sur le golden repo,
pour que le profil standard tienne sur un portable de 8 Gio avec Mailpit ;
`quay.io` dans la liste unique des registres du miroir (condition 10 de
l'ADR-011) ; R-04 et ENF-01 mis à jour à 1 787,0 Mo. Les failles sans paquet
associé, invisibles aux scanners, touchent les deux options : elles ouvrent
le risque R-36.

## 8. Limites et biais

[BENCH] Empreinte des seuils. SHA-256 de la section 4.1, du titre « 4.1 »
jusqu'à la ligne qui précède le titre « 4.2 » :
`c502b917d962e33da0310c3ba4c39955f6e1cba4cd3d026e527f1da214eed13c`, relevé
le 2026-11-20 à 20:10:29 UTC, juste après l'écriture des seuils. Aucun test de
fumée n'a tourné avant. Empreinte revérifiée avant la série de référence, le
2026-11-23 à 20:39 UTC : inchangée. Toute modification de la section 4.1 change cette
empreinte et doit se justifier ici, avant la première mesure.

| Limite | Effet possible sur le verdict | Ce qui la lèverait |
| --- | --- | --- |
| Série de référence sur batterie, capot ouvert ; trois séries précédentes interrompues par la veille capot fermé | Aucun, la série de référence ne montre aucune veille et le script refuse toute exécution qui en contient une ; la machine reste un portable sur batterie | Mesurer sur secteur, ou sur un poste fixe |
| Une seule machine de mesure, sous macOS avec OrbStack, moteur non libre (R-26), nœud arm64 | Empreinte et temps propres à ce matériel ; le volume, lui, se lit au registre pour amd64 | Relancer le script sous Linux avec Docker Engine, sur un runner amd64 |
| Note d'expérience dev de jugement, fondée sur un essai de trois exécutions par option avec le protocole de 4.3 | Un cran au plus, sans effet sur le classement (section 7) | Un essai par une autre personne, sur le golden repo |
| Comptes de CVE asymétriques : Keycloak suit ses CVE en tickets en plus de ses avis, Zitadel et Authentik dans leurs avis GitHub seulement | Les volumes de la section 5.5 ne se comparent pas un pour un | Fait par [SECU] le 2026-11-23, voir 5.5 [S68] |
| Statistiques de contribution tirées de l'API de GitHub, limitée aux principaux contributeurs de la branche par défaut (500 comptes rendus pour Keycloak, 100 pour Zitadel, 498 pour Authentik) ; robots, comptes sans profil et agent `claude` écartés | Commits et parts sous-estimés pour Zitadel au plus | Relevé par l'API des commits, sur les mêmes 12 mois |
| Employeurs lus dans les profils GitHub, déclaratifs ; seul Keycloak tient un fichier des mainteneurs avec employeurs | Gouvernance de Zitadel et d'Authentik lue sur un échantillon | Fichiers de gouvernance des deux éditeurs, s'ils existent |
| Page des prix d'Identity Platform encore illisible par l'outil le 2026-11-23 [S49] ; franchise lue sur la page tarifaire de Firebase [S82], prix au-delà non lus | Coût au-delà de la franchise inconnu, surtout pour les utilisateurs fédérés par SAML ou OIDC, sans frais jusqu'à 50 par mois | Lecture de la page dans un navigateur par Lucas (R-05) |
| Conditions de Red Hat UBI 9 micro, base de l'image de Keycloak, non lues ; dépendance transitive, hors critère éliminatoire | Réserve possible sur la licence de Keycloak | Levée par [SECU] le 2026-11-23 [S67] |
| Option pressentie par le PRD et proposée par BENCH-005 : Keycloak | Biais de lecture en sa faveur | Mêmes sources et mêmes critères pour les trois options ; relecture de [SECU] |
| Élimination d'Authentik décidée par le DSI le 2026-11-21, réversible par Lucas | Une troisième colonne à ajouter, notes et mesures comprises | Décision de Lucas |
| Client de test de Zitadel créé par l'API après « prêt », alors que Keycloak le déclare dans le royaume importé au démarrage | M1 de Zitadel ne contient pas la création du client | M6 dit comment le client est créé ; écart écrit dans la sensibilité |
| Contrôles de « prêt » par `kubectl exec` et `nc`, chacun borné à 8 s : un contrôle qui tombe sur un serveur encore en démarrage peut attendre jusqu'à cette borne | M1 et M7 connus à quelques secondes près | Un client HTTP natif dans le pod, exclu ici avec curl et wget |
| Zitadel mesuré avec la connexion V2 et ses deux tâches d'initialisation, comme le chart les livre ; Keycloak sans opérateur | Comparaison de deux installations de référence, pas de deux minimums | Mesurer aussi Zitadel sans la connexion V2, ou Keycloak par son opérateur |
| Postgres partagé sans TLS (`sslmode=disable` pour Zitadel) dans le cluster local | Sans effet sur l'empreinte ; écart à la cible GCP, où la base serait managée | Rien à faire pour ce benchmark ; à traiter dans l'ADR-013 |
| Certifications OpenID et listes d'adoptants tenues par les éditeurs eux-mêmes | Maturité lue sur des sources non indépendantes | Aucune source indépendante trouvée |
| Pages de Zitadel lues en partie : le guide de configuration dépasse ce que l'outil lit d'un coup (167 431 caractères) | Une capacité déclarative peut avoir échappé à la lecture (5.8) | Relecture complète avant l'écriture du script |
| Client HTTP du pod de test : PAT et en-tête `Basic` en argument, corps des requêtes dans un fichier du pod | Aucun sur les mesures | Ne pas reprendre ce client dans la matrice (FR-004) |
| Pic de mémoire au démarrage non mesuré ; mémoire lue 120 s après « prêt » | Le plancher de BENCH-005, qui retient le pic s'il dépasse le repos, peut être sous-estimé pour Keycloak, dont le tas peut monter à 70 % de la limite de 2000Mi [S14] | Mesurer pic et repos sur le golden repo, avec la limite retenue |
| Prix de GKE : valeurs d'exemple de us-central1 [S83], grille illisible, région non choisie | Montants de la voie GKE en ordre de grandeur, pas un budget | Grille de la région retenue lue avant la GATE 2 (R-05) |

## 9. Sources

| ID | URL | Lue le | Ce que la source établit | Officielle |
| --- | --- | --- | --- | --- |
| S1 | <https://github.com/keycloak/keycloak> | 2026-11-20 | Licence Apache-2.0, dépôt non archivé, créé le 2013-07-02, dernier push le 2026-11-20 (`gh api repos/keycloak/keycloak`) ; `LICENSE.txt` inchangé depuis son ajout le 2019-11-08 | Oui |
| S2 | <https://github.com/keycloak/keycloak/releases> | 2026-11-20 | 26.8.2 le 2026-11-05 ; 24 releases stables depuis le 2025-11-20, de la 26.4.6 à la 26.8.2 ; 26.0.0 le 2024-10-04 | Oui |
| S3 | <https://github.com/keycloak/keycloak/blob/main/MAINTAINERS.md> | 2026-11-20 | 11 mainteneurs actifs : 8 IBM, Robert Bosch, Hitachi, Identity Tailor | Oui |
| S4 | <https://github.com/keycloak/keycloak/blob/main/GOVERNANCE.md> | 2026-11-20 | Nouveau mainteneur accepté par les deux tiers des mainteneurs ; enquête semestrielle | Oui |
| S5 | <https://www.cncf.io/projects/keycloak/> | 2026-11-20 | Accepté à la CNCF le 2023-04-10 au niveau Incubating ; premier commit le 2013-07-02 | Oui |
| S6 | <https://github.com/keycloak/keycloak/blob/main/ADOPTERS.md> | 2026-11-20 | 59 organisations en référence publique, tirées de l'enquête communautaire | Oui |
| S7 | <https://github.com/keycloak/keycloak/blob/main/SECURITY.md> | 2026-11-20 | Modèle de la CISA, liste privée, accusé de réception sous 7 jours ouvrés, correctifs sur la mineure en cours ; version supportée de Red Hat à support long | Oui |
| S8 | <https://github.com/keycloak/keycloak/blob/main/RELEASES.md> | 2026-11-20 | Environ quatre mineures par an, correctifs de sécurité sur la dernière mineure, CVE suivies en tickets ; image sur quay.io, opérateur et ressources Kubernetes publiés | Oui |
| S9 | <https://github.com/keycloak/keycloak/security/advisories> | 2026-11-20 | 21 avis depuis le 2025-11-20 : 1 critique, 12 élevés, 7 moyens, 1 faible (`gh api`) | Oui |
| S10 | <https://github.com/keycloak/keycloak/security/advisories/GHSA-6qm4-x97f-55fh> | 2026-11-20 | CVE-2026-18963, critique, publiée le 2026-11-19 ; versions corrigées 26.4.15, 26.6.6, 26.7.2 | Oui |
| S11 | <https://github.com/keycloak/keycloak/issues?q=is%3Aissue%20type%3ACVE%20created%3A%3E%3D2025-11-20> | 2026-11-20 | 330 tickets de type CVE en 12 mois, dont 228 hors dépendances (225 identifiants CVE) ; 10 de ces derniers encore ouverts, tous moyens ou faibles | Oui |
| S12 | <https://github.com/keycloak/keycloak-quickstarts/blob/c598d34d3b2dd85976ac96614176df351ee1a4d5/kubernetes/keycloak.yaml> | 2026-11-20 | StatefulSet de deux répliques, image 26.8.2, `start`, `admin`/`admin` et mot de passe de base en clair, Postgres 17 éphémère, demandes 500m et 1700Mi, limites 2000m et 2000Mi ; SHA-256 `b4de5e35b234c11400192e805d4cb551c51e358f655be2196a51c2f9171fb9af` ; dépôt sous Apache-2.0 | Oui |
| S13 | <https://www.keycloak.org/getting-started/getting-started-kube> | 2026-11-20 | Installation par `kubectl create -f` du manifest S12 ; compte initial `admin`/`admin` | Oui |
| S14 | <https://www.keycloak.org/server/containers> | 2026-11-20 | `start-dev` à éviter en production ; construction optimisée par `kc.sh build` ; import au démarrage ; amorçage par `KC_BOOTSTRAP_ADMIN_USERNAME` et `KC_BOOTSTRAP_ADMIN_PASSWORD`, exemple `KC_BOOTSTRAP_ADMIN_PASSWORD=change_me` ; tas à 70 % de la limite du conteneur ; santé sur le port 9000 | Oui |
| S15 | <https://www.keycloak.org/server/importExport> | 2026-11-20 | `--import-realm`, import sauté si le royaume existe, substitution de variables d'environnement | Oui |
| S16 | <https://www.keycloak.org/server/bootstrap-admin-recovery> | 2026-11-20 | Compte d'administration d'amorçage temporaire, créé au premier démarrage seulement, sans mot de passe par défaut | Oui |
| S17 | <https://www.keycloak.org/server/db> | 2026-11-20 | PostgreSQL 14 à 18 pris en charge ; `dev-file` inadapté à la production | Oui |
| S18 | <https://github.com/keycloak/keycloak/blob/26.8.2/quarkus/container/Dockerfile> | 2026-11-20 | Image construite sur `registry.access.redhat.com/ubi9-micro` ; ports 8080, 8443 et 9000 | Oui |
| S19 | <https://github.com/zitadel/zitadel> | 2026-11-20 | Licence AGPL-3.0, dépôt non archivé, créé le 2020-03-16, dernier push le 2026-11-20 | Oui |
| S20 | <https://github.com/zitadel/zitadel/releases> | 2026-11-20 | v4.20.5 le 2026-11-18, v4.20.3 le 2026-11-13 ; 58 releases stables depuis le 2025-11-20 (47 en v4, 11 en v3.4) ; v1.0.0 le 2021-04-20, v3.0.0 le 2025-05-02, v4.0.0 le 2025-07-31 | Oui |
| S21 | <https://github.com/zitadel/zitadel/blob/main/LICENSING.md> | 2026-11-20 | AGPL-3.0-only ; `proto/` et `apps/docs/` sous Apache-2.0, `apps/login/` et deux paquets sous MIT ; contributions sous Apache-2.0 ; licence commerciale proposée | Oui |
| S22 | <https://github.com/zitadel/zitadel/commit/07ce3b69055a> | 2026-11-20 | Commit de la v3 du 2025-04-02 : passage d'Apache à l'AGPL (PR #9597), retrait de CockroachDB, API migrées | Oui |
| S23 | <https://github.com/zitadel/zitadel/blob/main/SECURITY.md> | 2026-11-20 | Signalement par le portail de l'éditeur | Oui |
| S24 | <https://github.com/zitadel/zitadel/security/advisories> | 2026-11-20 | 55 avis depuis le 2025-11-20 : 6 critiques, 31 élevés, 13 moyens, 5 faibles (`gh api`) | Oui |
| S25 | <https://github.com/zitadel/zitadel/blob/main/ADOPTERS.md> | 2026-11-20 | 16 lignes d'adoptants, liste tenue par les adoptants | Oui |
| S26 | <https://zitadel.com/docs/self-hosting/deploy/kubernetes> | 2026-11-20 | Chart Helm, Kubernetes 1.30 ou plus, PostgreSQL 14 à 18, HTTP/2 de bout en bout pour la console, API en Go et connexion en Next.js, tâches d'initialisation, clé maître immuable, identifiants du démarrage rapide `Password1!` ; exemples `YourSecurePassword123!` et `your-secure-password`, relus le 2026-11-23 | Oui |
| S27 | <https://zitadel.com/docs/self-hosting/manage/configure/configure> | 2026-11-20 | Section `FirstInstance` : organisation, administrateur `IAM_OWNER`, compte de service ; page lue en partie (167 431 caractères) | Oui |
| S28 | <https://github.com/zitadel/zitadel-charts> | 2026-11-20 | Chart sous Apache-2.0 ; version 10.5.0 du 2026-11-05, `appVersion` v4.19.2 ; mots-clés `oidc` et `idp` | Oui |
| S29 | <https://github.com/zitadel/zitadel/blob/main/.github/workflows/pack.yml> | 2026-11-20 | Images construites pour `linux/amd64` et `linux/arm64` ; aucune signature dans ce flux | Oui |
| S30 | <https://github.com/goauthentik/authentik> | 2026-11-20 | Licence non reconnue par GitHub (`NOASSERTION`), dépôt non archivé, créé le 2019-12-30, dernier push le 2026-11-20 | Oui |
| S31 | <https://github.com/goauthentik/authentik/releases> | 2026-11-20 | 2026.8.6 le 2026-11-20, 2026.8.5 le 2026-10-21 ; 33 releases stables depuis le 2025-11-20 | Oui |
| S32 | <https://github.com/goauthentik/authentik/blob/main/LICENSE> | 2026-11-20 | MIT par défaut ; `authentik/enterprise/` sous sa propre licence ; `website/` sous CC BY-SA 4.0 | Oui |
| S33 | <https://github.com/goauthentik/authentik/blob/main/authentik/enterprise/LICENSE> | 2026-11-20 | Licence entreprise d'Authentik Security Inc. : production réservée aux abonnés, développement et test permis, redistribution interdite | Oui |
| S34 | <https://github.com/goauthentik/authentik/blob/version/2026.8.6/authentik/root/settings.py> | 2026-11-20 | Lignes 591 à 595 : import de `authentik.enterprise.apps` s'il existe, ajout aux applications, « Enabled authentik enterprise » | Oui |
| S35 | <https://docs.goauthentik.io/enterprise/> | 2026-11-20 | L'édition entreprise « uses the same container images » que l'édition libre ; activation par clé de licence | Oui |
| S36 | <https://github.com/goauthentik/authentik/blob/main/SECURITY.md> | 2026-11-20 | GitHub pour CNA, signalement privé, branches 2026.5.x et 2026.8.x suivies, fonctions tenues pour voulues (expressions Python, plans) | Oui |
| S37 | <https://github.com/goauthentik/authentik/security/advisories> | 2026-11-20 | 24 avis depuis le 2025-11-20 : 3 critiques, 17 élevés, 4 moyens (`gh api`) | Oui |
| S38 | <https://docs.goauthentik.io/install-config/install/kubernetes/> | 2026-11-20 | Chart `authentik/authentik` ; Postgres du chart réservé aux essais ; mot de passe de `akadmin` fixé au premier passage dans l'installation | Oui |
| S39 | <https://docs.goauthentik.io/releases/2025.10/> | 2026-11-20 | « authentik no longer uses Redis at all » | Oui |
| S40 | <https://docs.goauthentik.io/install-config/automated-install/> | 2026-11-20 | `AUTHENTIK_BOOTSTRAP_PASSWORD` lu au premier démarrage, « stores plaintext passwords in environment variables », variante par empreinte | Oui |
| S41 | <https://docs.goauthentik.io/customize/blueprints/> | 2026-11-20 | Plans YAML découverts dans `/blueprints`, appliqués à chaque modification et toutes les 60 minutes | Oui |
| S42 | <https://github.com/goauthentik/helm/tree/authentik-2026.8.6/charts> | 2026-11-20 | Chart sous GPL-3.0, version 2026.8.6, mots-clés `oidc` et `idp` ; `serviceAccount.create: true` par défaut ; Role en écriture sur Secrets, Services, ConfigMaps, Deployments, Ingress et HTTPRoute du namespace | Oui |
| S43 | <https://github.com/goauthentik/authentik/blob/main/.github/workflows/release-publish.yml> | 2026-11-20 | Attestations de provenance (`actions/attest-build-provenance`) ; images pour `linux/amd64` et `linux/arm64` | Oui |
| S44 | <https://openid.net/developers/certified-openid-connect-implementations/> | 2026-11-20 | Keycloak 18.0.0 (déconnexion) et 15.0.2 (FAPI) certifiés par Red Hat ; authentik 2026.8.0 par son éditeur ; aucune ligne pour le serveur Zitadel, seule `zitadel/oidc` de CAOS, v0.15.7, Basic RP et Config RP | Oui |
| S45 | <https://opensource.org/licenses> | 2026-11-20 | Apache-2.0, AGPL-3.0, MIT et GPL-3.0 approuvées ; aucune licence entreprise d'Authentik | Oui |
| S46 | <https://docs.cloud.google.com/identity-platform/docs/product-comparison> | 2026-11-20 | OpenID Connect et SAML, locataires multiples, fonctions bloquantes, SLA de 99,95 % | Oui |
| S47 | <https://docs.cloud.google.com/identity-platform/docs/concepts-authentication> | 2026-11-20 | Connexion par SDK et bibliothèques d'interface ; OpenID Connect et SAML en fournisseurs fédérés ; aucun rôle de serveur d'autorisation décrit | Oui |
| S48 | <https://docs.cloud.google.com/identity-platform/docs/release-notes> | 2026-11-20 | GA le 2019-04-09, locataires en GA le 2019-11-18, dernière note le 2024-12-03 | Oui |
| S49 | <https://cloud.google.com/identity-platform/pricing> | 2026-11-20 | Page illisible par l'outil ; extrait du moteur de recherche : premier palier gratuit de 0 à 50 000 utilisateurs actifs par mois ; relue le 2026-11-23 par [FINOPS], toujours illisible | Oui, lue par extrait |
| S50 | <https://docs.cloud.google.com/identity-platform/docs/multi-tenancy-billing> | 2026-11-20 | Le palier dépend du fournisseur qui authentifie, pas du protocole entre l'application et Identity Platform | Oui |
| S51 | <https://firebase.google.com/docs/auth/admin/verify-id-tokens> | 2026-11-20 | Jeton RS256, émetteur `https://securetoken.google.com/<projectId>`, clés publiques de Google, vérifiable par une bibliothèque JWT | Oui |
| S52 | <https://github.com/hashicorp/terraform-provider-google/tree/main/website/docs/r> | 2026-11-20 | Ressources `google_identity_platform_config`, `_tenant`, `_oauth_idp_config`, `_inbound_saml_config` et leurs variantes ; provider v8.12.0 du 2026-11-17 | Oui |
| S53 | <https://github.com/keycloak/keycloak/graphs/contributors> | 2026-11-20 | API `stats/contributors` : 3 470 commits humains par 177 auteurs depuis le 2025-11-20 ; premier 12,6 %, trois premiers 22,6 % | Oui |
| S54 | <https://github.com/zitadel/zitadel/graphs/contributors> | 2026-11-20 | Même API : 817 commits humains par 34 auteurs ; premier 20,0 %, trois premiers 41,3 % | Oui |
| S55 | <https://github.com/goauthentik/authentik/graphs/contributors> | 2026-11-20 | Même API : 3 712 commits humains par 153 auteurs, 2 046 de Dependabot écartés ; premier 19,8 %, trois premiers 49,2 % | Oui |
| S56 | <https://api.github.com/users/ahus1>, et de même pour les six premiers auteurs humains de chaque dépôt (`gh api users/<login>`) | 2026-11-20 | Employeurs déclarés : IBM ou Red Hat pour les six premiers de Keycloak, Zitadel pour les six premiers de Zitadel, goauthentik ou Authentik Security pour quatre des six premiers d'Authentik | Oui, déclaratif |
| S57 | <https://github.com/goauthentik/authentik/blob/version/2026.8.6/lifecycle/container/Dockerfile> | 2026-11-20 | Ligne 224 : `COPY ./authentik/ /authentik`, donc `authentik/enterprise/` dans l'image | Oui |
| S58 | <https://docs.goauthentik.io/install-config/configuration/> | 2026-11-20 | « authentik supports PostgreSQL 14 - 18 » | Oui |
| S59 | <https://github.com/zitadel/zitadel/blob/v4.20.5/cmd/setup/steps.yaml> | 2026-11-21 | `FirstInstance` : administrateur humain `zitadel-admin`, mot de passe par défaut `Password1!`, `PasswordChangeRequired: true` ; utilisateur machine facultatif | Oui |
| S60 | <https://github.com/zitadel/zitadel/blob/v4.20.5/cmd/defaults.yaml> | 2026-11-21 | Politique de mots de passe par défaut : 8 caractères, minuscule, majuscule, chiffre et symbole ; `MaxPasswordAttempts: 0` ; clés de signature RSA 2048, SHA-256 | Oui |
| S61 | <https://github.com/zitadel/zitadel/blob/v4.20.5/proto/zitadel/management.proto> | 2026-11-21 | API de gestion sous `/management/v1` : `POST /users/machine` (déprécié, champ `access_token_type`), `PUT /users/{user_id}/secret` qui rend `client_id` et `client_secret` | Oui |
| S62 | <https://github.com/zitadel/zitadel/blob/v4.20.5/proto/zitadel/session/v2/session_service.proto> | 2026-11-21 | `POST /v2/sessions` avec vérification de l'utilisateur (identifiant ou nom de connexion) puis du mot de passe | Oui |
| S63 | <https://zitadel.com/docs/self-hosting/manage/database> | 2026-11-21 | Base et rôle préparés à la main : seule l'étape `init schema` (alias `init zitadel`) reste à lancer, le propriétaire de la base suffit | Oui |
| S64 | <https://github.com/zitadel/zitadel-charts/tree/zitadel-10.5.0/charts/zitadel> | 2026-11-21 | Chart 10.5.0 : la tâche de setup range la clé et le PAT de `iam-admin` dans des Secrets par un conteneur `alpine/k8s` ; tâche de nettoyage en crochet `post-delete` ; options `masterkeySecretName`, `login.loginServiceKeySecretName`, `envVarsSecret` ; archive au SHA-256 `e216ca1a9b19e9e2982e76a2cf49c446eeb3a02cdf167834977978acb880f019` | Oui |
| S65 | <https://github.com/keycloak-rel/keycloak-rel/tree/main/.github/workflows> (`x-keycloak-container.yml`, `respin-containers-conditionally.yml`, `.github/scripts/check-cve-updates-for-keycloak-image.sh`) | 2026-11-23 | Image poussée sur quay.io et Docker Hub par `docker/build-push-action@v2.10.0`, sans signature ni attestation ; un workflow quotidien la reconstruit quand une base neuve résout des CVE moyennes ou plus | Oui |
| S66 | <https://quay.io/api/v1/repository/keycloak/keycloak/tag/?specificTag=26.8.2> | 2026-11-23 | Condensats `723b1d6e…` le 2026-11-09, `c68e286c…` le 2026-11-12 et `7e66a96e…` le 2026-11-19 (courant) ; aucun tag `sha256-7e66….sig` | Oui |
| S67 | <https://www.redhat.com/licenses/EULA_Red_Hat_Universal_Base_Image_English_20190422.pdf> | 2026-11-23 | Contrat UBI de mars 2019 : composants sous licences permettant d'exécuter, copier, modifier et redistribuer ; contrat joint et aucun soutien de Red Hat allégué pour une image dérivée distribuée | Oui |
| S68 | <https://api.github.com/advisories> (`ecosystem`, `affects`, `published>=2025-11-20`) ; <https://trivy.dev/latest/docs/coverage/language/golang/> | 2026-11-23 | Keycloak : 74 CVE (1 critique, 24 élevées) ; 16 des 20 CVE de tickets échantillonnées sans paquet. Zitadel : 24 avis revus sur 55 ; GHSA-g8gj, -pq2q, -45f2 et -738m sans module Go. Trivy lit la base de GitHub pour les modules Go | Oui |
| S69 | <https://github.com/keycloak/keycloak/blob/26.8.2/services/src/main/java/org/keycloak/services/managers/RealmManager.java> | 2026-11-23 | Ligne 308 : `setBruteForceProtected(false)` à la création d'un royaume | Oui |
| S70 | <https://www.keycloak.org/server/reverseproxy> | 2026-11-23 | En-têtes forgés par un client qui contourne le proxy ; toutes les adresses sont de confiance par défaut ; chemins à exposer : `/realms/`, `/resources/`, `/.well-known/` ; chemins à ne pas exposer : `/`, `/admin/`, `/metrics`, `/health` | Oui |
| S71 | <https://www.keycloak.org/server/hostname> | 2026-11-23 | `hostname-strict=false` : injection d'en-tête Host ; « should always be set to true in production, unless your reverse proxy overwrites the Host header » ; `start` exige `--hostname` ou `--hostname-strict false` | Oui |
| S72 | <https://www.keycloak.org/server/configuration-production>, <https://www.keycloak.org/server/caching> | 2026-11-23 | Canal sûr pour toute communication ; administration sur un autre nom ou chemin ; `http-max-queued-requests` sans limite par défaut ; `cache-embedded-mtls-enabled` à `true`, ports 7800 et 57800 | Oui |
| S73 | <https://github.com/alpine-docker/k8s> (`Dockerfile`, `build.sh`, `.circleci/config.yml`) | 2026-11-23 | MIT, organisation non vérifiée, 64 commits du premier contributeur ; `FROM alpine:edge`, `curl` sans somme de contrôle, `--verify=false` ; SBOM et provenance sans signature | Oui |
| S74 | <https://github.com/zitadel/zitadel-charts/tree/zitadel-10.5.0/examples> | 2026-11-23 | Clés maîtres `MasterkeyNeedsToHave32Characters` et `x123456789012345678901234567891y` ; base `zitadel` ; `Password1!` avec `PasswordChangeRequired: false` | Oui |
| S75 | <https://github.com/zitadel/zitadel/pull/9597>, <https://github.com/zitadel/zitadel/pull/9645> | 2026-11-23 | #9597 fusionnée dans `v3.x` le 2025-03-27 ; #9645 dans `main` le 2025-04-02 | Oui |
| S76 | <https://github.com/goauthentik/authentik/tree/version/2026.8.6> (`.dockerignore`, `authentik/enterprise/`, `.github/workflows/release-publish.yml`) | 2026-11-23 | `authentik/enterprise/` non exclu de l'image ; modèles et migrations propres ; `actions/attest` à la publication | Oui |
| S77 | <https://firebase.google.com/docs/projects/api-keys> | 2026-11-23 | Clés d'API non secrètes mais à restreindre ; quota des points `identitytoolkit` à resserrer contre la force brute | Oui |
| S78 | <https://busybox.net/downloads/BusyBox.html> | 2026-11-23 | `nc` : « -e PROG Run PROG after connect (must be last) », `-l` pour écouter | Oui |
| S79 | <https://github.com/zitadel/zitadel/tree/v4.20.5/.github/workflows> | 2026-11-23 | `pack.yml` et `release.yml` sans cosign ni attestation ; actions épinglées par tag | Oui |
| S80 | <https://github.com/wait4x/wait4x/blob/main/.github/workflows/ci.yaml> | 2026-11-23 | Apache-2.0 ; aucune étape de signature | Oui |
| S81 | <https://github.com/cncf/toc/issues?q=keycloak> | 2026-11-23 | Aucune demande de graduation de Keycloak | Oui |
| S82 | <https://firebase.google.com/pricing> | 2026-11-23 | Section « With Identity Platform » : « Monthly active users », sans frais jusqu'à 50K MAUs ; « Monthly active users - SAML/OIDC », sans frais jusqu'à 50 MAUs ; au-delà, renvoi à la page tarifaire d'Identity Platform (relevé de [FINOPS]) | Oui |
| S83 | <https://docs.cloud.google.com/kubernetes-engine/cud> | 2026-11-23 | Exemple us-central1 : 0,0445 USD par vCPU-heure et 0,0049225 USD par Go-heure pour les pods Autopilot ; valeurs d'exemple, pas la grille (relevé de [FINOPS]) | Oui |
| S84 | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests> | 2026-11-23 | Classe généraliste : rapport vCPU:Gio de 1:1 à 1:6,5 ; CPU arrondi à 0,25 vCPU sans rafale ; minimums 250m et 512 Mio sans rafale ; sans requête, 0,5 vCPU et 2 Gio ; stockage éphémère par défaut 1 Gio (relevé de [FINOPS]) | Oui |

## 10. Relectures

| Relecteur | Porte sur | Date | Avis |
| --- | --- | --- | --- |
| [SECU] | Licences, critères éliminatoires, sécurité | 2026-11-23 | Réservé, favorable à Keycloak sous conditions. Licences, gouvernance et élimination d'Authentik sont confirmées sur les sources, et la réserve sur UBI est levée. La maturité de Keycloak passe à 4, comme celle de tout projet Incubating de la CNCF dans BENCH-004 et BENCH-011 : 81 contre 62. Aucune image mesurée n'est signée, et la dérogation de l'ADR-012 ne couvre que `docker.io/library`, donc l'ADR-013 porte la sienne. Les réglages `start` mesurés restent sur le PC : nom d'hôte non strict, en-têtes de proxy acceptés de partout, HTTP, aucun `securityContext`, force brute désactivée. Conditions 1 à 10. |
| [FINOPS] | Coût | 2026-11-23 | Favorable, avec corrections. Les chiffres de 4.4, 5.6 et 5.9 se retrouvent dans les données brutes de `series-4`. Les seuils ont été appliqués tels qu'écrits, donc 2/5 et 3/5 tiennent. Le cumul doit partir des 1 521,9 Mo de R-04, zot et Postgres de l'ADR-012 compris : 1 787,0 Mo et 158,8 % du budget avec Keycloak, 1 985,7 Mo et 176,5 % avec Zitadel. Avec Keycloak, le profil standard passe à 3,5 Gio de VM et tient sur 8 Gio au repos, avec 435,7 Mio de marge avant Mailpit. 5.9 reste à 4/5 pour les deux, avec une réserve réécrite : la franchise d'Identity Platform est lue, et Keycloak sur GKE coûte environ 44,4 USD par mois aux prix d'exemple. |

[SECU] Licences (5.1). Je confirme Keycloak à 5 et Zitadel à 3. Keycloak est
sous Apache-2.0 [S1]. La réserve sur l'image tombe. Le contrat de Red Hat
Universal Base Image (mars 2019) laisse chaque composant sous une licence qui
permet d'exécuter, copier, modifier et redistribuer. Il n'impose ni
abonnement ni limite d'usage en production. Pour une image dérivée
redistribuée, il demande seulement de joindre le contrat et de ne pas laisser
croire à un soutien de Red Hat [S67]. CELIAN ne redistribue pas l'image. Pour
Zitadel, une date est à préciser : la PR #9597 « change from Apache to AGPL »
est fusionnée dans `v3.x` le 2025-03-27, puis arrive dans `main` le
2025-04-02 avec la v3 (PR #9645) [S75]. Les contributions entrent sous
Apache-2.0 et le projet sort sous AGPL, ce qui laisse à l'éditeur seul le
choix d'une future licence [S21]. L'AGPL ne pèse que sur une version modifiée
et exposée par le réseau. Le miroir zot ne transmet de copie à personne
(ADR-011, condition 9) et ne redistribue donc rien.

[SECU] Gouvernance (5.2). Je confirme 4 et 2. `MAINTAINERS.md` liste onze
mainteneurs actifs : huit chez IBM, un chez Robert Bosch, un chez Hitachi et
un chez Identity Tailor [S3]. Keycloak est dans le cas de CloudNativePG et de
Cilium : une fondation porte le projet, une entreprise le dirige. Zitadel a
un seul éditeur, comme Config Sync dans BENCH-009.

[SECU] Maturité (5.3). Je ramène Keycloak à 4. Le critère nomme « le niveau
de maturité dans la fondation ». Les rapports précédents donnent 5 à un
projet gradué à la CNCF et 4 à un projet Incubating : CloudNativePG dans
BENCH-011, Envoy Gateway dans BENCH-004. Keycloak est Incubating depuis son
entrée le 2023-04-10, et la page de la CNCF n'affiche aucune autre date [S5].
Les tickets de `cncf/toc` ne contiennent aucune demande de graduation [S81].
Ses certifications OpenID ne portent que sur les versions 18.0.0 et 15.0.2
[S44]. Le reste de la justification tient. Zitadel reste à 3 : la liste des
fournisseurs certifiés ne le contient pas, seule la bibliothèque cliente
`zitadel/oidc` de CAOS y figure, en v0.15.7 [S44]. Nouveau total : Keycloak
81, Zitadel 62.

[SECU] Sécurité de Keycloak (5.5). Je maintiens 3, mais la justification est
à refaire. Les 21 avis du dépôt sont exacts [S9], sans donner le volume réel.
Dans la base mondiale de GitHub, j'ai pris les avis revus publiés depuis le
2025-11-20 pour quatre paquets Maven de Keycloak, ajouté les avis du dépôt,
puis dédoublonné par CVE. Résultat : 74 CVE, dont 1 critique, 24 élevées, 35
moyennes et 14 faibles [S68]. La critique, CVE-2026-18963, y figure depuis le
2026-08-18, la veille de la 26.7.2 qui la corrige. Les tickets du projet
citent 225 identifiants hors dépendances, et 157 manquent à ce compte. Sur un
échantillon de 20 d'entre eux, 16 sont dans la base sans paquet associé : un
scanner qui associe par paquet ne les voit pas [S68]. Deux faits manquaient
au rapport. D'abord, l'image n'a aucune signature. Le workflow qui la pousse
construit avec `docker/build-push-action@v2.10.0`, sans cosign ni
attestation, et quay.io n'a aucun tag `sha256-7e66….sig` pour le condensat
mesuré [S65], [S66]. Ensuite, le tag `26.8.2` a porté trois condensats : le
2026-11-09, le 2026-11-12 et le 2026-11-19, celui de la mesure [S66]. Un
workflow quotidien reconstruit l'image dès qu'une base neuve résout des CVE,
et le Dockerfile tire cette base sans tag ni condensat [S18], [S65]. Enfin,
la création d'un royaume, `master` compris, désactive la détection de force
brute (`RealmManager.java`, ligne 308) [S69]. La réserve demande donc d'agir
: suivre chaque mineure, couvrir l'absence de signature par une dérogation,
et durcir les royaumes.

[SECU] Sécurité de Zitadel (5.5). Je maintiens 2. Les comptes sont exacts (55
avis, 6 critiques, 31 élevés) [S24], sauf un : entre le 2026-11-13 et le
2026-11-18, il y a six avis élevés et non quatre. La base mondiale n'a revu
que 24 des 55 avis, dont 2 des 6 critiques. Les quatre autres critiques,
parmi lesquels les trois prises de compte sans authentification, n'y sont
associés à aucun module Go. Or Trivy lit cette base pour les modules Go
[S68]. Les workflows de la v4.20.5 ne signent rien, et leurs actions sont
épinglées par tag [S29], [S79]. La tâche de setup lance deux conteneurs
`docker.io/alpine/k8s` sous le compte de service `zitadel`, qui lit, crée,
modifie et supprime tous les Secrets du namespace. Le pod de l'API tourne
sous ce même compte (rendu, fichiers `09`, `10`, `04`). L'image `alpine/k8s`
vient de l'organisation GitHub `alpine-docker`, non vérifiée et hors de
`docker.io/library`. Elle est construite `FROM alpine:edge`, avec des
binaires tirés par `curl` sans somme de contrôle et des greffons Helm en
`--verify=false`, et n'est pas signée [S73]. Le PAT et la clé machine
d'`iam-admin`, rôle `IAM_OWNER`, valent jusqu'au 2029-01-01 et restent dans
des Secrets marqués `helm.sh/resource-policy=keep` (fichiers `08`, `12`).
Enfin, rien ne verrouille un compte après des échecs [S60].

[SECU] Élimination d'Authentik. Elle tient, vérifiée sur la 2026.8.6. Le
Dockerfile copie tout `authentik/` à la ligne 224 [S57], et `.dockerignore`
n'exclut pas `authentik/enterprise/` [S76]. `settings.py` importe
`authentik.enterprise.apps` et l'insère dans `TENANT_APPS`, lignes 591 à 595
[S34]. Le dossier porte ses propres modèles et migrations [S76]. La licence
entreprise réserve la production aux abonnés et ne permet copie et
modification que « for development and testing purposes » [S33]. Sur le PC,
la lecture du DSI se défend. En on-prem, que vise aussi le principe III,
recopier l'image dans un registre de production sortirait de cet usage. Un
point pour Lucas s'il revient sur la décision : Authentik est la seule des
trois options dont le flux de publication produit des attestations de
provenance signées (`actions/attest`) [S76]. Je n'ai pas vérifié où elles
sont rangées.

[SECU] Secrets (R-20, ADR-007). Les couches versionnées ne laissent aucun
identifiant par défaut. Keycloak ne fixe que le nom `admin`. Le mot de passe,
les identifiants de base et le secret du client viennent de Secrets, ce
dernier par substitution dans le royaume. Le rendu de Zitadel ne contient ni
Secret ni valeur. Les deux annotations `gitleaks:allow` sont bien les SHA-256
d'un saut de ligne et d'une chaîne vide, recalculés avec `shasum`. Dans les
données gardées (`series-1` à `4`, `control-1`, `smoke-1` à `4`), je n'ai
trouvé ni jeton, ni clé privée, ni certificat, ni valeur de Secret. Les
seules chaînes à forte entropie sont des `kid`, qui sont publics. Les
journaux ne gardent que « secret/… created », et les neuf `kubeconfig` font
28 octets, sans clé. Deux écarts restent. M8 a testé les six valeurs de
l'ADR-007 et `Password1!`, mais pas `mysecretpassword`, ajouté par la
condition 10 de l'ADR-012. C'est sans effet sur le résultat, puisque la
valeur du Secret est aléatoire. Dans le pod client, le PAT et l'en-tête
`Basic` passent en argument de `sh /bench/http.sh`. Le corps des requêtes,
mots de passe compris, passe par un fichier temporaire du pod, effacé à la
sortie. C'est acceptable sur un cluster jetable, mais ce client ne doit pas
entrer tel quel dans la matrice (FR-004).

[SECU] Valeurs connues à ajouter à la condition 1 de l'ADR-007. Pour
Keycloak, trois valeurs : `keycloak`, mot de passe de base du manifest de
démarrage [S12] ; `change_me`, valeur d'exemple de la page des conteneurs
[S14], qui diffère de `changeme` ; `Password1!`, défaut de Zitadel [S59] et
valeur du démarrage rapide de son chart [S74]. Si Zitadel revenait, il
faudrait aussi `zitadel`, `YourSecurePassword123!`, `your-secure-password`
[S26], et les deux clés maîtres d'exemple du chart :
`MasterkeyNeedsToHave32Characters` et `x123456789012345678901234567891y`
[S74]. Ces deux clés font exactement 32 caractères et passeraient la règle de
longueur : seule la liste les arrête. Le test doit viser toutes les clés
secrètes de la couche, secret du client compris, et pas seulement les mots de
passe (spec 001, E04). Le suffixe `a.Z9` répond à la politique de Zitadel. Il
n'entre dans le golden repo que si une politique de mot de passe l'exige.

[SECU] Signature et provenance (ENF-03, ADR-011, ADR-012). Aucune image
mesurée n'est signée. Pour Keycloak, la base `ubi9-micro` est tirée sans tag
ni condensat [S18]. Quelle que soit la signature de cette base, Kyverno ne
voit que l'image dérivée. Côté Zitadel, `alpine/k8s` porte un SBOM et une
provenance BuildKit sans enveloppe signée [S73], et `wait4x` n'a rien [S80].
La dérogation de l'ADR-012 ne vise que `docker.io/library/`. Elle ne couvre
ni `quay.io/keycloak/keycloak`, ni `ghcr.io/zitadel/*`, ni
`docker.io/alpine/k8s`, ni `docker.io/wait4x/wait4x`. Keycloak demande donc
sa propre dérogation dans l'ADR-013. Les republications pèsent : trois
condensats en dix jours pour une même version, chacun à relire. Pour le
miroir, `quay.io` entre dans la liste unique des registres (ADR-011,
condition 10). Un tirage anonyme suffit (condition 13) et le condensat tient
la condition 1.

[SECU] Inventaire du script et client `nc`. L'inventaire est exact. La seule
commande Docker qui écrit est `docker network rm kind`, dans le `trap`, et
seulement si le script a créé ce réseau et qu'il est vide. Les autres ne font
que lire : `version`, `info`, `ps -q`, `stats --no-stream`, `network
inspect`, `manifest inspect -v`. Le script n'appelle ni curl, ni wget, ni
python, ni node, ni perl. Il manque une mention, présente dans l'inventaire
validé de BENCH-011 : `kind create cluster` lance le nœud par `docker run
--privileged`. Deux sorties réseau sont aussi à nommer : `gh api` vers
GitHub, avec le jeton de l'utilisateur, et `docker manifest inspect` vers les
registres. Le verrou n'est pris que si `BENCH_LOCK` est défini. Pour `nc -e`,
BusyBox documente « Run PROG after connect (must be last) » [S78]. `nc` agit
en client, sans `-l`, et n'ouvre aucun port d'écoute. Le programme lancé est
écrit par `http.sh` dans un dossier `mktemp -d` : il envoie la requête et
copie la réponse dans un fichier, qui n'est jamais exécuté. Le pod tourne
sous l'UID 65534, sans élévation ni capacité, et aucun Service ne le vise.
`timeout 8` et `-w 8` bornent chaque requête. Rien n'ouvre d'accès inattendu.

[SECU] Mode `start`, TLS et GCP. `start` est le mode de production [S14], et
le garder sur le PC rapproche les deux cibles. Quatre réglages de la couche
ne valent pourtant que pour un PC à un seul utilisateur.
`KC_HOSTNAME_STRICT=false` rend les URL dynamiques ; la documentation le
réserve au cas où le proxy réécrit l'en-tête Host, et signale le risque
d'injection d'en-tête Host [S71]. `KC_PROXY_HEADERS=xforwarded` sans
`proxy-trusted-addresses` fait confiance à toutes les adresses ; la
documentation prévient qu'un client qui contourne le proxy peut forger ces
en-têtes [S70], et tout pod du cluster joint `keycloak:8080`.
`KC_HTTP_ENABLED=true` sert en clair, alors que le guide de production veut
un canal sûr pour toute communication [S72]. Le pod n'a aucun
`securityContext`, et le profil `restricted` le refuserait, même si l'image
tourne déjà sous l'UID 1000 [S18]. D'autres points sont à traiter avant GKE.
La console et l'API d'administration partagent le port de `/realms/`, alors
que la documentation les garde internes [S70]. La force brute est désactivée
[S69]. Le compte d'amorçage est temporaire : il faut créer un compte
permanent, puis le supprimer [S16]. Le mTLS du cache entre répliques, lui,
est actif par défaut [S72]. Aucun déploiement sur GKE n'a lieu en phase 2. Le
premier attend l'accord de Lucas et un budget de [FINOPS] (principe X).

[SECU] Dépôt public. Le gitleaks du hook pre-commit, figé en v8.30.1, a
scanné `cf38f91..86053db` : trois commits, aucune fuite. Les lignes ajoutées
ne contiennent aucun chemin `/Users/`, `/private/tmp` ou `scratchpad`, et
aucun nom de compte. Auteur et committer utilisent l'adresse noreply.

[SECU] Conditions proposées pour l'ADR-013 (Keycloak) :

1. Image et dérogation à ENF-03. `quay.io/keycloak/keycloak` est désignée
   par condensat et tirée par zot, avec `quay.io` dans la liste de la
   condition 10 de l'ADR-011. La dérogation est datée, sur le modèle de la
   condition 7 de l'ADR-012 : référence exacte, condensat compris, dans une
   liste fermée tenue dans la PR du manifest. [SECU] la relit à chaque
   montée. Elle tombe quand Keycloak signe ses images de façon vérifiable par
   Kyverno, ou quand le projet signe sa propre image optimisée [S14], si
   l'ADR-006 l'accepte. Contrôle : celui de l'ADR-012, étendu à
   `quay.io/keycloak/`.
2. Suivi. Keycloak corrige seulement sa dernière mineure, qui change
   chaque trimestre [S2], [S7]. Renovate suit la mineure et le condensat. Une
   republication ou une version qui corrige un avis passe par l'exception de
   sécurité du principe VI. [OPS] vérifie comment `minimumReleaseAge` date
   une montée de condensat. [SECU] lit chaque mois les avis et les tickets
   `kind/cve` [S68].
3. Durcissement. Le namespace applique le profil `restricted`. Le pod a
   `runAsNonRoot`, `allowPrivilegeEscalation: false`, les capacités `ALL`
   retirées, `seccompProfile: RuntimeDefault` et
   `automountServiceAccountToken: false`. `readOnlyRootFilesystem` est à
   essayer avec un `emptyDir`. Le port 9000 n'est dans aucun Service.
   Contrôle : la matrice échoue sur un pod refusé par le profil.
4. Nom d'hôte et proxy. `KC_HOSTNAME` est fixé sur les deux cibles, et
   `hostname-strict` garde son défaut. `KC_PROXY_HEADERS` ne s'utilise
   qu'avec `KC_PROXY_TRUSTED_ADDRESSES` limité à la gateway [S70], [S71]. Une
   NetworkPolicy restreint le port 8080. [OPS] vérifie qu'elle s'applique
   sous le CNI de kind, ainsi que le chemin interne de l'API vers l'émetteur.
   Contrôle : un `X-Forwarded-Host` forgé ne change pas l'émetteur du
   document de découverte.
5. Chemins exposés. Sur `gcp`, la route n'expose que `/realms/`,
   `/resources/` et `/.well-known/` [S70]. Sur `local`, la console reste en
   boucle locale, écart listé au README. Contrôle : sur `gcp`, `/admin/`
   répond 404 par la gateway.
6. Identifiants (R-20). Les valeurs sont créées par `task up` selon la
   condition 1 de l'ADR-007, avec la liste étendue appliquée à toutes les
   clés secrètes. Le contrôle du type de M8 exige `invalid_grant`, reste sous
   le seuil de force brute et ne passe aucun secret en argument. Sur `gcp`,
   le compte d'amorçage est remplacé puis supprimé [S16].
7. Force brute. `bruteForceProtected` est activé sur `master` et sur le
   royaume de l'application [S69]. Contrôle : la matrice lit les deux
   royaumes.
8. Jetons. Les jetons de la mesure portent `aud: account`, d'où un mappeur
   d'audience pour l'API ([ARCHI] vérifie son nom). L'API vérifie RS256,
   l'émetteur, l'audience et l'expiration. Le front est un client public avec
   PKCE, sans aucun secret dans le navigateur. Avec Identity Platform, l'API
   exige `aud` égal au projet [S51], et la clé d'API est restreinte, avec
   quotas resserrés [S77].
9. Base et transport. Le rôle Keycloak n'est pas superutilisateur. Le HTTP
   local est un écart listé au README. Sur `gcp`, TLS à la gateway ; le
   tronçon jusqu'au pod et la connexion TLS à Cloud SQL se décident dans
   l'ADR [S72]. `http-max-queued-requests` est fixé. À plusieurs répliques,
   une NetworkPolicy limite les ports 7800 et 57800 aux pods de Keycloak.
10. GKE. Aucun déploiement en phase 2. Le premier attend l'accord de Lucas
    et un budget de [FINOPS]. L'import du royaume au démarrage, « may only
    make sense » en mode dev [S14], ne sert pas sur `gcp` sans décision de
    [ARCHI].

[SECU] D'accord avec réserves : Keycloak reste devant, 81 contre 62. L'écart
tient sur la licence, la gouvernance et la maturité. En sécurité, les deux
options ont des CVE en partie invisibles aux scanners, et aucune n'a d'image
signée. Zitadel y ajoute six avis critiques, une image tierce qui écrit les
Secrets et un PAT d'administration valable jusqu'en 2029. Ce qui pèse sur
Keycloak vient du déploiement que CELIAN écrit, et les conditions 3 à 9 le
couvrent. Authentik reste éliminé.

[SECU] Questions ouvertes : maturité de Keycloak à 4 (arbitrage du DSI) ;
dérogation à ENF-03 pour Keycloak (Lucas) ; CVE sans paquet qui touchent les
deux options : étendre R-32 ou ouvrir un risque. Non vérifié : référents OCI
sur quay.io (pas de cosign ni d'oras sur le poste) ; comportement de Renovate
sur les condensats ; NetworkPolicy sous kind ; noms des options de Keycloak
pour l'audience et l'URL interne de l'émetteur.

[FINOPS] Recalcul depuis la série du 2026-11-23 (`runs.tsv`, `summary.tsv`,
`idle-pods.tsv`, `images.tsv`, `node-images.tsv`, `load.tsv` et
`versions.tsv` de `series-4`). Le script prend la médiane de trois
échantillons par exécution, puis la médiane des trois exécutions ; la couche
est la médiane du nœud de l'option moins celle du nœud de base. M1, M2 au
nœud, M9, la somme des pods, M3 et M7 se retrouvent au dixième près, écarts
compris : 1 503,2 moins 660,0 font 843,2 Mio, et 922,9 moins 660,0 font
262,9. Refaite échantillon par échantillon, la somme des pods de Zitadel
donne 191,2, 185,0 et 189,4 Mio. M4 se retrouve aux octets : 265 083 135 pour
Keycloak, et 463 782 772 pour Zitadel (`alpine/k8s` 316 686 555, connexion 78
469 346, API 54 109 438, `wait4x` 14 517 433). Cela fait 212,1 et 371,0 s à
10 Mbit/s. M5 se retrouve aussi : chaque exécution porte un événement
`Pulled` pour chaque image de la couche, en 6,5 à 8,5 s pour Keycloak et en
7,7 à 9,4 s pour `alpine/k8s`. Deux écarts, sans effet sur les notes.
D'abord, les plages des pods de Zitadel écrites en 4.4 ne sont pas celles des
données. Dans l'échantillon médian de chaque exécution, l'API va de 85,2 à
93,0 Mio et la connexion de 98,2 à 99,8 ; sur les neuf échantillons, de 85,0
à 122,7 et de 80,0 à 99,8. Ensuite, la valeur basse de la deuxième exécution
de Keycloak (538,2 Mio au pod) reste isolée : les quatre exécutions complètes
de Keycloak des séries du 2026-11-21, non retenues, donnent de 838,8 à 841,2
Mio. Pour dimensionner, c'est donc la médiane de 843,2 Mio qu'il faut retenir.

[FINOPS] Les seuils ont été appliqués tels qu'écrits. J'ai comparé une à une
les lignes 231 à 290 du rapport à `section-4.1-2026-11-20.md` : les 60 lignes
sont identiques. Le condensat de référence,
`c502b917d962e33da0310c3ba4c39955f6e1cba4cd3d026e527f1da214eed13c`, a été
relevé le 2026-11-20 à 20:10:29 UTC. Le premier test de fumée commence à
23:33:44 UTC (`smoke-1/load.tsv`), la série de référence le 2026-11-23 à
20:40:11 UTC. Seuil 1 : franchi par les deux options (265,1 et 463,8 Mo, pour
112,5). Seuil 2 : franchi par les deux, avec un `Pulled` par image de la
couche à chaque exécution. Seuil 3 : non franchi (25,7 et 21,6 s de médiane,
43,8 s au pire). Seuil 4 : franchi par Keycloak seul (843,2 Mio pour 512 ;
Zitadel reste à 262,9). Keycloak perd donc trois crans et finit à 2/5,
Zitadel en perd deux et finit à 3/5. Aucune médiane n'est à moins de 10 %
d'un seuil. Lue exécution par exécution, la deuxième de Keycloak donne 530,6
Mio (1 184,8 moins 654,2), 3,6 % au-dessus du seuil : elle reste du même
côté, donc même note. L'heure d'écriture des seuils et l'absence de lecture
préalable des registres reposent sur la déclaration de [BENCH], faute de
commit.

[FINOPS] Cumul avec le premier `task up`. Depuis l'ADR-012, la base est celle
de R-04 : 1 521,9 Mo en amd64 pour le profil standard, avec zot et
`postgres:18.7-trixie`, hors Keycloak et Mailpit. Le rapport part encore des
1 395,9 Mo d'avant zot et d'avant le Postgres retenu, d'où ses 1 661,0 Mo et
ses 148 %. Aucune des deux options n'ajoute d'image Postgres, puisqu'elles
utilisent la base partagée. Avec Keycloak, le premier `task up` passe à 1
787,0 Mo : 1 429,6 s à 10 Mbit/s, 158,8 % du budget de 900 s, et un débit
minimal de 15,9 Mbit/s au lieu de 13,5. Avec Zitadel, il passe à 1 985,7 Mo :
1 588,5 s, 176,5 %, 17,7 Mbit/s. Sans miroir, la base vaut 1 444,2 Mo, et les
totaux 1 709,3 et 1 908,0 Mo. Sur ce poste, Keycloak est le moins cher des
deux, avec 198,7 Mo de moins, soit 159 s à 10 Mbit/s.

[FINOPS] Registres et miroir. Keycloak vient de quay.io, que l'ADR-011 ne
liste pas : le profil standard demanderait un troisième amont au miroir,
après docker.io et ghcr.io. Or le mécanisme à plusieurs amonts n'est pas
encore établi (montages a et b de l'ADR-011). Sans miroir pour quay.io, les
265,1 Mo de Keycloak repartent d'Internet à chaque création du cluster, comme
M5 le montre, soit 212 s à 10 Mbit/s. Le montage b ajouterait une instance de
zot, environ 51 Mio d'après l'extrapolation non mesurée de l'ADR-011.
Zitadel, lui, tire de docker.io et de ghcr.io, que le profil standard demande
déjà pour Flux. Le stockage de zot est estimé à 566,5 Mo en amd64 pour le
profil standard avec le Postgres retenu. Si toutes les images passent par le
miroir, il monterait à 831,6 Mo avec Keycloak et à 1 030,3 Mo avec Zitadel.
C'est une estimation pour le seuil d'avertissement de la condition 5 de
l'ADR-011, qu'aucune mesure ne confirme.

[FINOPS] Mémoire. J'applique la méthode de BENCH-005, reprise par BENCH-010
et BENCH-011 : plancher multiplié par 1,5, arrondi au demi-gibioctet
supérieur, plus 4 Gio pour le portable. Sur un portable de 16 Gio, je prends
une VM de 8 Gio, comme BENCH-010. Je pars du majorant de BENCH-011 pour la
partie connue du profil standard, Postgres retenu compris : 1 451,8 Mio, soit
2,5 Gio de VM et 6,5 Gio de portable. Avec Keycloak, le plancher passe à 2
295,0 Mio, la VM à 3,5 Gio et le portable à 7,5 Gio : deux paliers de plus.
Sur un portable de 8 Gio, il reste 435,7 Mio de plancher pour Mailpit et le
bruit de mesure. Il reste aussi 94,3 Mio avant le palier de 4,0 Gio, qui
tient encore sur 8 Gio avec l'hypothèse des 4 Gio pour le système. Avec
Zitadel, le plancher vaut 1 714,7 Mio, 8,0 Mio au-dessus du palier de 2,5 Gio
: 3,0 Gio de VM, 7,0 Gio de portable, et 1 016,0 Mio de reste sur 8 Gio. Sur
16 Gio, il reste 3 166,3 Mio avec Keycloak et 3 746,6 avec Zitadel. Les 580,3
Mio d'écart au nœud valent 7,1 % d'un portable de 8 Gio et un palier de VM.

[FINOPS] Le profil standard tient donc sur 8 Gio avec Keycloak au repos, de
justesse, et deux lectures le font sortir de ce cadre. La première est la
limite de la JVM : le manifest fixe 2000Mi, et le tas peut monter jusqu'à 70
% de cette limite [S14]. Keycloak à sa limite porterait le plancher à environ
3 475,1 Mio, soit 5,5 Gio de VM et 9,5 Gio de portable. Le profil ne
tiendrait plus sur 8 Gio, mais tiendrait encore sur 16 Gio, avec 1 986,2 Mio
de reste. La seconde est le pic de démarrage : la méthode de BENCH-005 le
retient s'il dépasse le repos, et BENCH-012 ne le mesure pas. Pour que
Keycloak à sa limite tienne sur 8 Gio avant Mailpit, la limite du pod devrait
rester sous 1 255 Mi environ : 2 730,7 moins 1 451,8, moins les 23,3 Mio que
le nœud compte en plus du pod. Aucune limite de ce niveau n'a été mesurée.
Ces chiffres mêlent six séries : ce sont des ordres de grandeur.

[FINOPS] Côté GCP, je n'ai lancé aucune action cloud, et aucun budget n'est
validable : la région n'est pas choisie (R-05). Le 2026-11-23, l'outil ne
rend que le titre de la grille de GKE comme de celle d'Identity Platform.
Voie Identity Platform : la page tarifaire de Firebase, section « With
Identity Platform », annonce un usage sans frais jusqu'à 50 000 utilisateurs
actifs par mois, et jusqu'à 50 sur la ligne SAML/OIDC [S82]. Le palier dépend
du fournisseur qui authentifie l'utilisateur [S50]. Une démo reste dans cette
franchise, donc 0 USD. Je n'ai pas lu les prix par utilisateur au-delà, et je
n'en écris aucun. Pour un SaaS B2B dont les clients fédèrent leur annuaire
par SAML ou OIDC, la franchise s'arrête au cinquantième utilisateur fédéré du
mois.

[FINOPS] Voie Keycloak sur GKE Autopilot. La référence demande 500m et 1700Mi
par réplique, avec deux répliques [S12]. Ce rapport reste dans la plage de
1:1 à 1:6,5 qu'Autopilot accepte, et 500m est un multiple de 0,25 vCPU,
l'arrondi qu'il impose sans rafale : la demande ne serait pas ajustée [S84].
Aux prix d'exemple de us-central1, 0,0445 USD par vCPU-heure et 0,0049225 USD
par Go-heure [S83], sur 730 heures, une réplique coûte environ 22,2 USD par
mois et les deux 44,4 USD. Je compte la mémoire en Gio, comme BENCH-008 ; si
l'unité de la page est le Go décimal, ces montants deviennent 22,6 et 45,3
USD. Hors chiffre : le stockage éphémère (1 Gio par conteneur par défaut
[S84]), la base dans Cloud SQL, un équilibreur si Keycloak ne passe pas par
la Gateway de l'application (ADR-005), et les journaux. Voie Zitadel sur GKE
: le chart 10.5.0 ne fixe aucune demande (`resources: {}`). Autopilot
appliquerait alors 0,5 vCPU et 2 Gio à chacun des deux pods, soit environ
46,9 USD par mois. Au minimum sans rafale, 250m et 512 Mio par pod, ce serait
19,8 USD. Ni l'une ni l'autre de ces valeurs n'a été mesurée sur GKE.

[FINOPS] Note de coût. 4/5 tient pour les deux options, avec une autre
justification. Sur le PC, il n'y a ni licence ni service payant, et le temps
d'exploitation est compté ailleurs : le suivi des mineures de Keycloak en
5.5, les montées de majeure de Zitadel en 5.3, les gestes d'installation en
5.8 (règle de BENCH-008). La réserve porte sur le cloud. Dans BENCH-011, la
cible `gcp` gardait Cloud SQL quelle que soit l'option. Ici, l'option
elle-même peut tourner sur GKE si l'ADR-013 prend la voie du `managed_gap`,
avec des pods facturés à l'heure. La page des prix illisible n'est plus la
réserve, puisque la franchise est lue sur une page officielle. Le coût ne
départage pas : le pendant managé est le même, et les montants sur GKE sont
du même ordre. Avec 5/5 aux deux, lecture de BENCH-011, les totaux
passeraient à 85 et 63, et l'écart resterait le même.

[FINOPS] Empreinte. La règle donne bien 2/5 et 3/5. Elle compte les seuils
franchis, pas la hauteur du dépassement : Keycloak dépasse le seuil de
mémoire de 64,7 %, Zitadel celui de volume de 312 %, et chacun perd un cran
pour ça. Sur le PC, le coût réel se partage. Keycloak coûte un palier de VM
et 580,3 Mio de plus, Zitadel 198,7 Mo de plus au premier `task up`. Pour le
critère des 15 minutes, Keycloak est le meilleur des deux ; pour le portable
de 8 Gio, c'est Zitadel.

[FINOPS] D'accord avec réserves. Le coût ne départage pas, et le verdict
tient sur les critères de lecture, avec 22 points d'écart. Sur le PC, chaque
option a son prix : Keycloak télécharge 198,7 Mo de moins, Zitadel garde
580,3 Mio de moins au nœud. Trois conditions pour l'ADR-013 : une limite
mémoire de Keycloak fixée et mesurée sur le golden repo, pour que le profil
standard tienne sur 8 Gio avec Mailpit ; quay.io dans la liste du miroir,
sans quoi 265,1 Mo repartent d'Internet à chaque création du cluster ; R-04
et ENF-01 mis à jour à 1 787,0 Mo. Si Lucas retient Keycloak sur GKE : une
réplique dans le profil démo (environ 22,2 USD par mois aux prix d'exemple)
et des requêtes explicites (condition 9 de l'ADR-008). Aucun apply avant un
budget validé à la GATE 2.

[FINOPS] Questions ouvertes : l'heure de `series-2` (correction 2) pour
[BENCH] ; Mailpit (BENCH-013) décide si le profil standard reste à 3,5 Gio de
VM ou passe à 4,0, la limite d'un portable de 8 Gio ; le pic de démarrage de
Keycloak n'est pas mesuré ; la page de GKE écrit « per GB » (Go ou Gio, 2 %
d'écart) ; les prix d'Identity Platform au-delà de la franchise restent non
lus.

[BENCH] Suite donnée. Les quatorze corrections de [SECU] et les seize de
[FINOPS] sont intégrées dans les sections 1 à 9, avec la grille réconciliée
par le DSI le 2026-11-24 : Keycloak 81, Zitadel 62 (section 6). L'écart de 22
points cité dans la sensibilité de 5.6 suit la grille et passe à 19. Deux
chiffres de [FINOPS] partent de la grille d'avant la relecture de [SECU], où
Keycloak avait 84 : l'écart de 22 points de son avis vaut 19 dans la grille
réconciliée, et la lecture à 5/5 en coût donnerait 82 et 63, et non 85 et 63.
Les sources de [SECU] gardent leurs numéros, S65 à S81 ; celles de [FINOPS],
qu'elle numérotait aussi S65 à S67, deviennent S82 à S84, renvois compris
dans ses paragraphes ci-dessus. S49 reste citée dans la limite sur la page
des prix (section 8). La question de [FINOPS] sur l'heure de `series-2` a sa
réponse en 4.4 : la série a démarré pendant une veille capot fermé, et sa
première exécution commence au réveil, à 21:18:04 UTC. La correction 14 de
[SECU] passe par un commit à part, après celui qui garde le script mesuré.
Avant la relecture, le script versionné a pour SHA-256
`6db513d1af0fc80ff36c1add957f3bc1a1176997a433b8418926f3705c14faa7`, celui que
l'essai de contrôle a relevé ; la série de référence, lancée avant le
découpage des couches, a relevé
`55535ce61b51f951815bbb0c6e1393c94ab707bde5deee94c2c1b9257be81b1b`. Après la
correction 14, il a pour SHA-256
`d9b986fa375a6eb910b7b0741a36ddbe1d7fe6967da1d455cf21d64281283fc8`. Les
numéros de ligne cités par les deux relectures renvoient au rapport d'avant
la relecture, dont les commentaires du gabarit sont retirés depuis. Les
questions de [SECU] sur la maturité, la dérogation à ENF-03 et les CVE sans
paquet sont tranchées par l'arbitrage de la section 7 et par R-36.
