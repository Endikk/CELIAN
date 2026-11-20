<!--
Gabarit des rapports de benchmark (brief, section 8).
Dupliquer ce fichier en docs/benchmarks/BENCH-XXX-sujet.md, sujet court en
minuscules et mots séparés par des tirets (ex. BENCH-003-cluster-local.md).
Remplir dans l'ordre des sections, le verdict en dernier.
Chaque paragraphe s'ouvre par le tag de son auteur : [BENCH] pour le corps,
[SECU] ou [FINOPS] dans les relectures.
Aucun fait de mémoire (principe VIII) : chaque version, licence, date ou
chiffre renvoie à une source [Sn] ou à une mesure [Mn].
Retirer tous les commentaires avant de passer le statut à « relu ».
-->

# BENCH-012. Fournisseur d'identité du profil standard

| Champ | Valeur |
| --- | --- |
| Identifiant | BENCH-012 |
| Sujet | Fournisseur d'identité (OIDC) du profil standard sur le PC, et son pendant sur GCP |
| Statut | brouillon |
| Ouvert le | 2026-11-20 |
| Mis à jour le | 2026-11-20 |
| Auteur | [BENCH] |
| Relecteurs | [SECU] pour les licences et les CVE, [FINOPS] pour les coûts |
| Périmètre | Projet généré sur PC (cluster local) et projet généré sur GCP |
| Choix du PRD | Aucune ligne du tableau des choix ouverts : composition du profil standard, décision de Lucas du 2026-11-20 (US-005) |
| ADR lié | ADR-013, à écrire par [ARCHI] |
| Verdict proposé | Option retenue et total sur 100, rempli en dernier |

<!--
Statut : « brouillon » pendant la rédaction. « relu » quand [SECU] et [FINOPS]
ont rendu leur avis et que leurs remarques sont traitées. « clos » quand l'ADR
lié a tranché : le rapport ne bouge plus, un fait nouveau ouvre un nouveau
benchmark.
Périmètre : garder seulement ce que le choix touche.
-->

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

<!--
Deux ou trois options : celles de la section 8 du brief, sauf raison écrite
sous le tableau. Version examinée : la dernière release stable à la date de
lecture de sa source.
-->

| Option | En une phrase | Version examinée | Publiée le | Sources |
| --- | --- | --- | --- | --- |
| Keycloak | Serveur d'identité et d'accès (OpenID Connect, OAuth 2.0, SAML), en Java sur Quarkus d'après son dépôt, en incubation à la CNCF ; image officielle sur quay.io, manifest de démarrage rapide pour Kubernetes et opérateur | 26.8.2 | 2026-11-05 | [S1], [S2], [S5], [S8], [S12] |
| Zitadel | Plate-forme d'identité multi-organisations (OpenID Connect, OAuth 2.0, SAML), en Go d'après son dépôt, éditée par la société ZITADEL ; une API et une interface de connexion en Next.js, installées par un chart Helm | v4.20.5 | 2026-11-18 | [S19], [S20], [S26], [S28] |
| Authentik | Fournisseur d'identité (OpenID Connect, OAuth 2.0, SAML, LDAP, proxy), en Python et en Go d'après son dépôt, édité par Authentik Security Inc. ; un serveur et un worker dans la même image, installés par un chart Helm | 2026.8.6 | 2026-11-20 | [S30], [S31], [S38], [S42] |

[BENCH] Âge des versions examinées au regard du principe VI (7 jours avant
toute mise à jour automatique). Keycloak 26.8.2 a 15 jours. Zitadel v4.20.5 en
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
principe II et ENF-02 demandent de contenir dans la couche de cible. L'autre voie est la même
option sur GKE, avec un `managed_gap` qui dit pourquoi Identity Platform ne
couvre pas le besoin. Ce choix revient à [ARCHI] ; la grille ne le tranche pas
(section 5.7).

[BENCH] Options repérées mais non étudiées : aucune hors du brief. Dex et la
suite Ory existent aussi ; le brief ne les nomme pas, et ils n'ont pas été lus
pour ce rapport.

## 3. Critères éliminatoires

<!--
Les trois critères du brief, vérifiés avant toute notation.
Licence : open source pour tout ce qui tourne sur le PC ou en on-prem, soit
une licence approuvée par l'OSI, vérifiée sur la liste de l'OSI à la date du
rapport [Sn]. Sans objet pour un service managé de la cible cloud
(principe III).
Statut : ni archivé, ni annoncé en maintenance par le dépôt, le site ou la
fondation.
Release : la dernière date de moins de 12 mois au jour de la vérification.
Pour une norme stable (JSON Schema, OpenAPI, OCI), le critère porte sur
l'outil maintenu qui la met en œuvre, pas sur le texte de la norme. Il ne
s'applique pas aux dépendances transitives, qui se signalent dans les limites.
Une exigence fonctionnelle du PRD peut éliminer une option ; elle s'écrit dans
le contexte avec sa référence (US-xxx), et le DSI l'accepte par écrit.
Une option éliminée n'est pas notée. S'il reste moins de deux options, le
signaler au DSI avant de continuer.
-->

[BENCH] Seuil de release : 2025-11-20, douze mois avant la vérification.

| Option | Licence open source | Ni archivé ni en maintenance | Release de moins de 12 mois | Vérifié le | Résultat |
| --- | --- | --- | --- | --- | --- |
| Keycloak | Oui, Apache-2.0 [S1], approuvée OSI [S45] | Oui, dépôt non archivé, dernier push le 2026-11-20 [S1] | Oui, 26.8.2 le 2026-11-05 [S2] | 2026-11-20 | Retenue |
| Zitadel | Oui, AGPL-3.0-only depuis la v3, avec des parties sous Apache-2.0 et MIT, dont l'interface de connexion sous MIT [S19], [S21] ; AGPL-3.0 approuvée OSI [S45] | Oui, dépôt non archivé, dernier push le 2026-11-20 [S19] | Oui, v4.20.5 le 2026-11-18 [S20] | 2026-11-20 | Retenue |
| Authentik | Non au sens strict. L'édition libre est sous MIT [S32], approuvée OSI [S45], mais l'image officielle contient `authentik/enterprise/` sous une licence propre, non approuvée par l'OSI [S33], [S35], [S57], et le serveur charge ce module quand il le trouve [S34] | Oui, dépôt non archivé, dernier push le 2026-11-20 [S30] | Oui, 2026.8.6 le 2026-11-20 [S31] | 2026-11-20 | Élimination proposée, accord écrit du DSI attendu |

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
principe III. Proposition de [BENCH] : éliminer Authentik, sur accord écrit du
DSI. En attendant cet accord, la section 5 le note à titre provisoire, pour que
le refus éventuel de l'élimination ne retarde pas le rapport.

[BENCH] Zitadel, licence. AGPL-3.0 est approuvée par l'OSI [S45] : le critère
passe. Le changement de licence de 2025 (Apache-2.0 vers AGPL) se note en
5.1.

[BENCH] Options éliminées : Authentik, proposée, critère de licence. Il reste
deux options, Keycloak et Zitadel.

## 4. Mesures

<!--
Une mesure réelle pour chaque critère où elle a un sens, en général
l'empreinte sur PC (ENF-02). Si aucune n'en a, le dire en une phrase et
retirer les sous-sections.
-->

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

[BENCH] Relevé le 2026-11-20 pour le matériel et le système. Les lignes du
moteur, des ressources allouées, des versions et de la charge se relèvent au
lancement de la série, aucune commande n'ayant été passée au moteur pendant
cette phase de lecture.

| Élément | Valeur |
| --- | --- |
| Modèle | Apple Mac16,7 (`sysctl hw.model`) |
| Processeur | Apple M4 Pro, 14 cœurs (10 performance, 4 efficacité), arm64 |
| Mémoire | 24 Gio (25 769 803 776 octets, `sysctl hw.memsize`) |
| Système | macOS 27.2.1 (build 26B131) |
| Moteur de conteneurs | À relever au lancement de la série (`docker version`, `docker info`) ; OrbStack 2.2.5 et Docker Engine 29.8.2 pour BENCH-009, moteur non libre (R-26) |
| Ressources allouées | À relever au lancement de la série : CPU et mémoire de la machine virtuelle du moteur (`docker info`) |
| Versions mesurées | kind 0.33.0 et image de nœud `kindest/node:v1.36.4@sha256:099e…faed` (ADR-004) ; kubectl 1.37.1 ; Helm 4.3.2, au seul rendu des charts ; version de chaque option et condensat de chaque image figés dans le script à sa préparation (étape 1) |
| Charge parasite | À relever : applications ouvertes, charge moyenne au début de chaque exécution (`load.tsv`), verrou partagé tenu pendant toute la série |

### 4.3 Protocole

[BENCH] Protocole écrit avant le script, que [DEV] ou [BENCH] écrira après
BENCH-010 et BENCH-011. Les choix que le script devra encore fixer sont
signalés comme tels.

1. Préparation, une fois par série. Versions : la dernière stable de chaque
   option au lancement de la série, avec son âge au regard du principe VI
   (section 2). Couche de Keycloak : un `kustomization.yaml` écrit par
   [BENCH] d'après `kubernetes/keycloak.yaml` des quickstarts, au commit
   `c598d34d` [S12], dont le script vérifie le SHA-256 (`b4de5e35b234c11400192e805d4cb551c51e358f655be2196a51c2f9171fb9af`,
   relevé le 2026-11-20) avant d'en tirer les patches. Couches de Zitadel et
   d'Authentik : rendu de leur chart par `helm template`, une fois, versionné
   dans `tests/bench/` avec son SHA-256 et les valeurs passées ; pour Zitadel,
   l'image de l'application est la dernière stable si le chart l'accepte,
   sinon son `appVersion`, l'écart allant en 4.2. Le script réécrit chaque
   `image:` en `référence@condensat`, avec les condensats d'index relevés à la
   préparation, et s'arrête si une image reste sans condensat (condition 3 de
   l'ADR-004). Aucun manifest n'est appliqué depuis une URL (condition 4).
2. Écarts communs aux trois références, et à elles seules. Une réplique.
   Base de données : l'instance Postgres de base (4.1), à la place de la base
   que chaque référence apporte, avec un utilisateur et une base propres à
   l'option. Aucun identifiant en clair : mot de passe de la base, compte
   d'administration initial, clé maître de Zitadel, clé secrète d'Authentik et
   secret du client de test viennent de Secrets que le script crée avant
   `kubectl apply -k`, chaque valeur tirée de `/dev/urandom` et passée par un
   tube à `kubectl create -f -` (condition 1 de l'ADR-007), lue par
   `secretKeyRef`. Client de test déclaré par le mécanisme déclaratif de
   l'option quand il existe : import de royaume au démarrage pour Keycloak
   [S15], plan (`blueprint`) pour Authentik [S41]. Pour Zitadel, la création
   d'une application OpenID Connect au démarrage n'apparaît pas dans les pages
   lues [S27] : si elle exige un appel d'API après « prêt », le script le fait
   et M6 le dit. Ressources : celles de la référence, sans ajout ; le
   manifest de Keycloak fixe une limite de 2000Mi, dont la JVM prend 70 % en
   tas [S12], [S14]. Aucun port publié vers l'hôte, aucune gateway : la
   couche se joint par son Service.
3. État de départ de chaque exécution : aucun cluster `celian-bench-012`. Le
   script crée un cluster kind neuf avec l'image de nœud de l'ADR-004, attend
   qu'il soit prêt, démarre l'instance Postgres de base (le verdict de
   BENCH-011 s'il est rendu avant la série, sinon l'image officielle
   `postgres` en majeure 18, défaut de Cloud SQL selon l'ADR-009, figée par
   condensat) et un pod client, puis attend que Postgres réponde à
   `SELECT 1`. Les images de la couche ne sont pas préchargées : le nœud les
   tire à chaque exécution, comme au premier `task up` d'un poste. Le cache
   Docker de l'hôte ne sert qu'à l'image de nœud.
4. Installation (M1) : création des Secrets, puis `kubectl apply -k` de la
   couche ; le chronomètre part au premier `kubectl apply` et s'arrête selon
   la définition de « prêt » de 4.1, par le pod client.
5. Parcours OIDC (M6), dès « prêt » : jeton demandé au point de jeton du
   document de découverte pour le client de test, puis vérifié contre le
   `jwks_uri` du même document, émetteur et audience compris. L'outil de
   vérification, en image figée par condensat, se choisit à l'écriture du
   script et se cite avec sa documentation.
6. Identifiants (M8) : authentification du compte d'administration initial
   avec chaque valeur connue de la condition 1 de l'ADR-007, puis avec la
   valeur du Secret. La méthode d'authentification de chaque option se fixe à
   l'écriture du script, d'après sa documentation, et se cite.
7. Repos (M2, M3) : 120 s après « prêt », trois échantillons espacés de 10 s
   de l'API Summary du kubelet pour les pods de la couche, et du conteneur du
   nœud par `docker stats` ; médianes des trois, comme dans BENCH-009.
8. Redémarrage (M7) : suppression des pods du fournisseur, cluster gardé ;
   chronomètre jusqu'à « prêt », puis nouveau jeton pour le client de test.
9. Volume et tirages (M4, M5) : tailles compressées lues aux registres par
   architecture, sans rien tirer, comme dans BENCH-009 ; images tirées
   d'après les événements `Pulled` du nœud.
10. Fin : suppression du cluster, 15 s de pause. Trois exécutions par option
    retenue, options alternées pour répartir les variations du réseau et de
    la charge. Nœud de base (M9) en série à part, option `none` : mêmes
    étapes 3 et 7, sans fournisseur.

[BENCH] Garde-fous du script, repris de BENCH-009 et BENCH-011 : verrou
partagé (`BENCH_LOCK`, refus en code 75 s'il est pris, jamais forcé), refus si
le cluster existe déjà, `trap` posé après ces contrôles, `umask 077`,
`KUBECONFIG` dans le dossier d'essai (`~/.kube` ni lu ni écrit), aucune valeur
secrète en argument ni dans un fichier, shellcheck, bash 3.2 de macOS.

Pour refaire la mesure, une fois le script écrit :

```bash
BENCH_LOCK=/chemin/vers/un/verrou tests/bench/bench-012-identity.sh /chemin/vers/un/dossier/vide
OPTIONS=none BENCH_LOCK=/chemin/vers/un/verrou tests/bench/bench-012-identity.sh /chemin/vers/un/autre/dossier   # nœud de base, M9
```

### 4.4 Résultats

<!--
Une ligne par mesure et par option. La médiane sert à la notation, l'écart
(maximum moins minimum) montre la dispersion. Ajouter une colonne par
exécution au-delà de trois.
-->

[BENCH] Mesures lancées le AAAA-MM-JJ, sur la machine de la section 4.2.

| Mesure | Option | Exécution 1 | Exécution 2 | Exécution 3 | Médiane | Écart |
| --- | --- | --- | --- | --- | --- | --- |
| M1 | Option A | valeur | valeur | valeur | valeur | valeur |
| M1 | Option B | valeur | valeur | valeur | valeur | valeur |
| M1 | Option C | valeur | valeur | valeur | valeur | valeur |

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

[BENCH] Notes provisoires, écrites pendant la phase de lecture le 2026-11-20,
sans aucune mesure. La section 5.6 attend les mesures. La note d'expérience dev
(5.8) repose sur la seule documentation et se confirmera par l'essai de M6. Les
lignes d'Authentik sont marquées « provisoire » : elles disparaissent si le DSI
accepte l'élimination proposée à la section 3.

### 5.1 Licence et liberté d'usage, poids 15

<!--
Licence exacte, ce qu'elle impose au générateur (Apache-2.0) et aux projets
générés, changement de licence passé. Preuves : fichier de licence du dépôt,
annonce officielle.
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Keycloak | 5/5 | 15 | Apache-2.0, la licence du générateur ; fichier de licence inchangé depuis son ajout le 2019-11-08. Le manifest de démarrage rapide vient d'un dépôt sous Apache-2.0. L'image repose sur Red Hat UBI 9 micro, dont les conditions n'ont pas été lues (section 8) | [S1], [S12], [S18], [S45] |
| Zitadel | 3/5 | 9 | AGPL-3.0-only depuis la v3 : le passage d'Apache-2.0 à l'AGPL est fusionné le 2025-04-02 (PR #9597). Les contributions ne sont acceptées que sous Apache-2.0 et l'éditeur vend une licence commerciale : un prochain changement ne dépend que de lui. L'AGPL ne pèse pas sur un projet généré qui tire l'image sans la modifier, et se signale si l'utilisateur la modifie et l'expose (pièges du brief, section 5). Chart sous Apache-2.0. Action : relire la licence à chaque vérification du catalogue | [S19], [S21], [S22], [S28], [S45] |
| Authentik (provisoire) | 2/5 | 6 | MIT pour l'édition libre, mais l'image officielle charge du code sous licence entreprise non libre (section 3) : il faudrait reconstruire l'image. Chart sous GPL-3.0 : versionner son rendu dans le blueprint demande l'avis de [SECU] sur la licence des manifests rendus | [S32], [S33], [S34], [S42], [S57] |

### 5.2 Gouvernance (fondation, multi-vendeurs), poids 15

<!--
Fondation porteuse, éditeur unique ou communauté, nombre d'entreprises parmi
les mainteneurs (principe V). Preuves : page du projet chez la fondation,
fichier des mainteneurs, statistiques de contribution datées.
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Keycloak | 4/5 | 12 | En incubation à la CNCF depuis le 2023-04-10. 11 mainteneurs actifs de quatre employeurs : 8 chez IBM, un chez Robert Bosch, un chez Hitachi, un chez Identity Tailor ; un nouveau mainteneur demande l'accord des deux tiers d'entre eux. 3 470 commits humains par 177 auteurs en 12 mois, le premier à 12,6 %, les trois premiers à 22,6 %. Réserve : IBM tient 8 mainteneurs sur 11, les six premiers auteurs humains se déclarent chez IBM ou Red Hat, et Red Hat vend une version supportée | [S3], [S4], [S5], [S7], [S53], [S56] |
| Zitadel | 2/5 | 6 | Éditeur unique, ZITADEL, sans fondation. 817 commits humains par 34 auteurs en 12 mois, le premier à 20,0 %, les trois premiers à 41,3 % ; les six premiers déclarent Zitadel pour employeur. Le principe V demanderait un ADR pour justifier l'écart | [S19], [S21], [S54], [S56] |
| Authentik (provisoire) | 2/5 | 6 | Éditeur unique, Authentik Security Inc., titulaire de la licence entreprise, sans fondation. 3 712 commits humains par 153 auteurs en 12 mois (2 046 commits de Dependabot écartés), le premier à 19,8 %, les trois premiers à 49,2 % ; quatre des six premiers déclarent goauthentik ou Authentik Security | [S30], [S33], [S55], [S56] |

### 5.3 Maturité et adoption, poids 15

<!--
Ancienneté, niveau de maturité dans la fondation, adoption en production
déclarée (principe VI : pas de projet qui vient de sortir). Preuves : page de
la fondation, liste d'adoptants en précisant qui la tient.
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Keycloak | 5/5 | 15 | Premier commit le 2013-07-02, en incubation à la CNCF, version majeure 26 depuis le 2024-10-04. 59 organisations en référence publique dans `ADOPTERS.md`, liste tirée de l'enquête communautaire du projet. Certifié OpenID par Red Hat pour les profils de déconnexion (18.0.0) et FAPI (15.0.2). Red Hat en vend une version à support long | [S2], [S5], [S6], [S7], [S44] |
| Zitadel | 3/5 | 9 | Dépôt créé le 2020-03-16, v1.0.0 le 2021-04-20. Trois versions majeures depuis, dont la v3 (2025-05-02) et la v4 (2025-07-31) à trois mois d'écart, avec des ruptures : retrait de CockroachDB, API migrées. 16 lignes, éditeur compris, dans une liste d'adoptants tenue par les adoptants eux-mêmes. Absent des implémentations certifiées OpenID lues. Action : prévoir les montées de version majeure dans `copier update` | [S20], [S22], [S25], [S44] |
| Authentik (provisoire) | 4/5 | 12 | Dépôt créé le 2019-12-30, versions calendaires, une version de fonctionnalités environ tous les trois mois (2025.12, 2026.2, 2026.5, 2026.8). Certifié OpenID en 2026.8.0 par son éditeur (profils Basic, Config, Hybrid, Implicit, Form Post et déconnexion). Réserve : aucune liste d'adoptants dans le dépôt | [S30], [S31], [S44] |

### 5.4 Activité et maintenance, poids 10

<!--
Rythme des releases sur 12 mois, contributeurs actifs, délai de réponse aux
tickets. Preuves : page des releases, statistiques du dépôt, datées.
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Keycloak | 5/5 | 10 | 24 releases stables en 12 mois, de la 26.4.6 à la 26.8.2, environ quatre mineures par an selon `RELEASES.md`. 3 470 commits humains par 177 auteurs, dernier push le 2026-11-20 | [S1], [S2], [S8], [S53] |
| Zitadel | 5/5 | 10 | 58 releases stables en 12 mois : 47 de la v4.7.1 à la v4.20.5, et 11 sur la branche v3.4, jusqu'à la v3.4.15 du 2026-08-14. 817 commits humains par 34 auteurs, dernier push le 2026-11-20 | [S19], [S20], [S54] |
| Authentik (provisoire) | 5/5 | 10 | 33 releases stables en 12 mois, deux branches suivies (2026.5.x et 2026.8.x). 3 712 commits humains par 153 auteurs, dernier push le 2026-11-20 | [S30], [S31], [S36], [S55] |

### 5.5 Sécurité (CVE, réactivité), poids 10

<!--
Politique de signalement, avis de sécurité publiés, délai entre signalement
et correctif, CVE encore ouvertes. Relu par [SECU]. Preuves : politique de
sécurité du projet, base de CVE, avis du projet.
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Keycloak | 3/5 | 6 | Politique tirée du modèle de la CISA, signalement par une liste privée, accusé de réception sous 7 jours ouvrés, correctifs sur la dernière mineure seulement. 21 avis publiés en 12 mois, dont un critique, CVE-2026-18963 (prise de compte sans authentification par le flux de réinitialisation, corrigée en 26.7.2 le 2026-08-19, avis publié le 2026-11-19), et 12 élevés. Le projet suit aussi ses CVE en tickets : 228 tickets hors dépendances ouverts en 12 mois, 10 encore ouverts au 2026-11-20, tous moyens ou faibles. Signature des images non relevée. La réserve demande une action : suivre chaque mineure, environ tous les trois mois, et ne jamais reprendre les identifiants du manifest de démarrage | [S7], [S8], [S9], [S10], [S11], [S12] |
| Zitadel | 2/5 | 4 | Signalement par un portail de l'éditeur. 55 avis publiés en 12 mois, dont 6 critiques : cinq prises de compte, dont trois sans authentification, et une SSRF sans authentification ; 31 élevés, dont quatre publiés entre le 2026-11-13 et le 2026-11-18. Aucune signature d'image dans le flux de publication lu. Le démarrage rapide documente un mot de passe d'administration connu | [S23], [S24], [S26], [S29] |
| Authentik (provisoire) | 3/5 | 6 | Signalement privé par GitHub, qui attribue les CVE ; deux branches corrigées. 24 avis en 12 mois, dont 3 critiques (contournement de SourceStage, XSS réfléchi, exécution de code authentifiée par un point de test) et 17 élevés. Attestations de provenance publiées avec les images. La réserve demande une action : le chart crée par défaut un Role qui écrit Secrets, Deployments et HTTPRoute dans son namespace, pour les avant-postes gérés ; le mot de passe de `akadmin` se fixe au premier passage dans le flux d'installation, sauf variable d'amorçage, que la documentation dit stockée en clair | [S36], [S37], [S38], [S40], [S42], [S43] |

### 5.6 Empreinte sur PC (RAM, CPU, démarrage), poids 10

<!--
RAM au repos, CPU, temps de démarrage sur le PC (ENF-02). Preuve : la médiane
des mesures de la section 4.

Règle de notation, validée par Lucas le 2026-11-19 (BENCH-003) : des seuils
absolus, jamais un écart à la meilleure option. Chaque seuil est une valeur
ronde tirée du PRD (budget de 900 s d'ENF-01, portable de 8 Gio) ou d'un débit
bas pris comme hypothèse (10 Mbit/s). Les seuils s'écrivent dans la section
4.1 avant la première mesure, avec leur origine. Chaque option part de 5 et
perd un cran par seuil dépassé. Une option à moins de 10 % d'un seuil voit
ses deux notes possibles écrites dans la sensibilité de la section 7.

Seuils de BENCH-003, à reprendre ou à adapter au sujet, en disant pourquoi :
volume compressé à télécharger au premier lancement au-delà de 500 Mo (400 s
à 10 Mbit/s) ; au moins une image retéléchargée à chaque lancement, cache
plein ; démarrage à chaud au-delà de 90 s (10 % du budget) ; mémoire au repos
au-delà de 1 Gio (un huitième d'un portable de 8 Gio).

Trois règles validées par Lucas à la GATE 1, le 2026-11-20, après leur usage
dans BENCH-004, 005, 007 et 009 :

1. Le volume se note sur linux_amd64, pire cas des systèmes visés par Q5.
   Les autres architectures mesurées vont dans la sensibilité.
2. La plate-forme de base (cluster kind, CRD Gateway API, gateway) se compte
   contre les 500 Mo ci-dessus. Chaque couche suivante (stack, secrets,
   GitOps...) se note contre ses propres seuils, écrits dans sa section 4.1 ;
   son cumul avec la plate-forme va dans la sensibilité. Sans ce périmètre,
   l'ordre des benchmarks déciderait des notes.
3. La mémoire d'une couche se lit au nœud, moins la mémoire du nœud de base
   (kind seul, même configuration), en médianes : les CRD et les contrôleurs
   chargent aussi le serveur d'API, que la somme des pods ne voit pas. La
   somme des pods va dans la sensibilité.

Les seuils écrits avant la première mesure portent leur heure UTC, et le
rapport dit si des tests de fumée ont tourné avant. Les seuils de couche
additionnés dépassaient déjà le budget de 900 s à la GATE 1 : un budget par
étape d'ENF-01 reste à fixer (R-04).
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Option A | n/5 | p | Une ou deux phrases | [Mn] |
| Option B | n/5 | p | Une ou deux phrases | [Mn] |
| Option C | n/5 | p | Une ou deux phrases | [Mn] |

### 5.7 Portabilité multi-cloud, poids 10

<!--
Fonctionne sur les deux cibles du MVP sans code propre à l'une (principe II),
et resterait utilisable sur un autre cloud ou en on-prem. Preuves :
documentation officielle d'installation par plateforme.
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Keycloak | 5/5 | 10 | Image et manifest ordinaires (StatefulSet, Services) pour tout cluster conforme, donc kind comme GKE ; opérateur publié à part. PostgreSQL 14 à 18 pris en charge, dont la 18, défaut de Cloud SQL (ADR-009) : sur GKE, sa base pourrait rester managée. Architectures des images à relever en M4 | [S8], [S12], [S17] |
| Zitadel | 4/5 | 8 | Chart Helm pour tout cluster 1.30 ou plus ; PostgreSQL 14 à 18 ; images construites pour amd64 et arm64. Réserve : la console exige HTTP/2 de bout en bout, en h2c jusqu'aux pods, réglage à vérifier avec Envoy Gateway (ADR-005) | [S26], [S29] |
| Authentik (provisoire) | 5/5 | 10 | Chart Helm pour tout cluster ; images publiées pour amd64 et arm64 ; PostgreSQL 14 à 18, seule dépendance depuis la 2025.10 | [S38], [S39], [S43], [S58] |

[BENCH] Le principe III n'entre pas dans cette note, qui mesure ce qui tourne
où, comme dans BENCH-009. Il ne départagerait pas les options : sur GCP, le
pendant managé est Identity Platform pour chacune, et son parcours de
connexion diffère de celui des trois serveurs OpenID Connect (section 2) ;
l'autre voie, la même option sur GKE avec un `managed_gap`, reste ouverte aux
trois. Ce choix revient à l'ADR-013.

### 5.8 Expérience dev et documentation, poids 10

<!--
Qualité et fraîcheur de la documentation officielle, clarté des erreurs,
temps pour faire tourner un exemple minimal. Note de jugement : décrire
l'essai qui la fonde. Preuves : documentation officielle, essai consigné.
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Keycloak | 4/5 | 8 | Documentation par guide, avec sélecteur de version (26.8.2). Démarrage sur Kubernetes en une commande ; import d'un royaume au démarrage (`--import-realm`), sauté si le royaume existe, avec substitution de variables d'environnement ; compte d'administration d'amorçage par variables, temporaire par conception. Réserve : le manifest de démarrage écrit ses identifiants en clair, la documentation juge l'import au démarrage surtout utile en mode dev, et la construction optimisée qu'elle recommande demande une image construite par le projet | [S12], [S13], [S14], [S15], [S16] |
| Zitadel | 3/5 | 6 | Documentation versionnée (v4.20) ; chart Helm seul, à rendre et versionner ; section `FirstInstance` pour l'organisation, l'administrateur et un compte de service. Action : la création d'une application OpenID Connect au démarrage n'apparaît pas dans les pages lues, la clé maître ne change plus après l'initialisation, et HTTP/2 doit être tenu de bout en bout | [S26], [S27] |
| Authentik (provisoire) | 4/5 | 8 | Documentation versionnée (2026.8) ; plans YAML découverts dans `/blueprints`, appliqués à chaque modification et toutes les 60 minutes ; amorçage de `akadmin` par variable ou par empreinte du mot de passe. Réserve : chart Helm seul, à rendre et versionner, et la variable en clair que la documentation déconseille | [S38], [S40], [S41] |

[BENCH] Note de jugement, fondée pour l'instant sur la seule lecture des pages
citées. L'essai qui la confirmera : installation par le protocole de 4.3, puis
le parcours OIDC de M6 et le redémarrage de M7, trois fois par option, sans
intervention.

### 5.9 Coût (managé ou opérationnel), poids 5

<!--
Coût du service managé sur GCP, ou coût d'exploitation sur le PC et en
on-prem (temps, licence, support). Relu par [FINOPS]. Preuves : page de tarifs
officielle datée, estimation de [FINOPS].
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Keycloak | 4/5 | 4 | Gratuit sur le PC. Sur GCP, pendant managé identique pour toutes les options (Identity Platform) : d'après l'extrait que le moteur de recherche donne de la page officielle, les méthodes du premier palier sont gratuites jusqu'à 50 000 utilisateurs actifs par mois, et le palier dépend du fournisseur qui authentifie. Réserve : page des prix illisible par l'outil le 2026-11-20 (R-05). Sur GKE, avec un `managed_gap`, la référence demande 500m de CPU et 1700Mi par réplique, deux répliques par défaut | [S12], [S49], [S50] |
| Zitadel | 4/5 | 4 | Gratuit sur le PC. Même pendant managé, même réserve sur la page des prix. Demandes de ressources sur GKE non relevées | [S49], [S50] |
| Authentik (provisoire) | 4/5 | 4 | Gratuit sur le PC, édition entreprise non utilisée. Même pendant managé, même réserve. Demandes de ressources sur GKE non relevées | [S33], [S49], [S50] |

[BENCH] Le coût ne départage pas les options à ce stade : licence gratuite sur
le PC pour les trois, et même service managé sur GCP. Il ne bougerait que si
l'ADR-013 retenait l'option libre sur GKE, où les demandes de ressources de
chaque référence entreraient dans le budget de [FINOPS].

## 6. Grille pondérée

<!--
Reporter notes et points de la section 5. Total : somme des points, sur 100.
Une option éliminée garde sa colonne, avec « éliminée » dans chaque case.
-->

| Critère | Poids | Option A | Option B | Option C |
| --- | --- | --- | --- | --- |
| Critères éliminatoires (section 3) | éliminatoire | passe | passe | passe |
| Licence et liberté d'usage | 15 | n/5, p pts | n/5, p pts | n/5, p pts |
| Gouvernance (fondation, multi-vendeurs) | 15 | n/5, p pts | n/5, p pts | n/5, p pts |
| Maturité et adoption | 15 | n/5, p pts | n/5, p pts | n/5, p pts |
| Activité et maintenance | 10 | n/5, p pts | n/5, p pts | n/5, p pts |
| Sécurité (CVE, réactivité) | 10 | n/5, p pts | n/5, p pts | n/5, p pts |
| Empreinte sur PC (RAM, CPU, démarrage) | 10 | n/5, p pts | n/5, p pts | n/5, p pts |
| Portabilité multi-cloud | 10 | n/5, p pts | n/5, p pts | n/5, p pts |
| Expérience dev et documentation | 10 | n/5, p pts | n/5, p pts | n/5, p pts |
| Coût (managé ou opérationnel) | 5 | n/5, p pts | n/5, p pts | n/5, p pts |
| Total | 100 | p / 100 | p / 100 | p / 100 |

## 7. Verdict proposé

<!--
Une proposition. L'ADR lié, écrit par [ARCHI], tranche, et Lucas valide.
-->

[BENCH] Option proposée, son total, et son écart en points avec la suivante.

[BENCH] Pourquoi : les critères qui font la différence, avec leurs sources.

[BENCH] Sensibilité : les notes qui, changées d'un cran, inverseraient le
classement. Si l'écart tient dans un seul cran, le verdict repose sur ce
critère : le dire.

[BENCH] Gouvernance : si l'option proposée dépend d'un éditeur unique, ce qui
justifie l'écart au principe V. Sinon, retirer ce paragraphe.

[BENCH] Réserves : ce qu'il faut surveiller, et la date de la prochaine
vérification.

[BENCH] Suites : l'ADR lié, les entrées de `catalog/` à créer avec licence,
gouvernance, statut, date et source (principe IV), les risques à ajouter à
`docs/risques.md`.

## 8. Limites et biais

<!--
Ce qui peut fausser le verdict, dit une fois et précisément, avec ce qui
lèverait la limite. Pistes : une seule machine de mesure, machine différente
du PC de référence de la phase 6 (pas encore défini, ENF-02), images en
cache, source tenue par l'éditeur lui-même, note de jugement, option
pressentie par le PRD.
-->

[BENCH] Empreinte des seuils. SHA-256 de la section 4.1, du titre « 4.1 »
jusqu'à la ligne qui précède le titre « 4.2 » :
`c502b917d962e33da0310c3ba4c39955f6e1cba4cd3d026e527f1da214eed13c`, relevé
le 2026-11-20 à 20:10:29 UTC, juste après l'écriture des seuils. Aucun test de
fumée n'a tourné avant. Toute modification de la section 4.1 change cette
empreinte et doit se justifier ici, avant la première mesure.

| Limite | Effet possible sur le verdict | Ce qui la lèverait |
| --- | --- | --- |
| Une seule machine de mesure | Empreinte propre à ce matériel | Relancer le script sur une deuxième machine |
| Notes écrites avant toute mesure et tout essai ; 5.8 repose sur la lecture seule | Une note de jugement peut bouger d'un cran | L'essai de M6 et M7, trois fois par option |
| Comptes de CVE asymétriques : Keycloak suit ses CVE en tickets en plus de ses avis, Zitadel et Authentik dans leurs avis GitHub seulement | Les volumes de la section 5.5 ne se comparent pas un pour un | Relecture de [SECU], recoupement avec la base mondiale de GitHub comme dans BENCH-009 |
| Statistiques de contribution tirées de l'API de GitHub, limitée aux principaux contributeurs de la branche par défaut (500 comptes rendus pour Keycloak, 100 pour Zitadel, 498 pour Authentik) ; robots, comptes sans profil et agent `claude` écartés | Commits et parts sous-estimés pour Zitadel au plus | Relevé par l'API des commits, sur les mêmes 12 mois |
| Employeurs lus dans les profils GitHub, déclaratifs ; seul Keycloak tient un fichier des mainteneurs avec employeurs | Gouvernance de Zitadel et d'Authentik lue sur un échantillon | Fichiers de gouvernance des deux éditeurs, s'ils existent |
| Page des prix d'Identity Platform illisible par l'outil (81 caractères) ; le palier gratuit vient d'un extrait du moteur de recherche | Coût sur GCP non établi | Lecture par [FINOPS] de la page dans un navigateur (R-05) |
| Conditions de Red Hat UBI 9 micro, base de l'image de Keycloak, non lues ; dépendance transitive, hors critère éliminatoire | Réserve possible sur la licence de Keycloak | Lecture par [SECU] des conditions d'UBI |
| Option pressentie par le PRD et proposée par BENCH-005 : Keycloak | Biais de lecture en sa faveur | Mêmes sources et mêmes critères pour les trois options ; relecture de [SECU] |
| Élimination d'Authentik en attente de l'accord écrit du DSI | Grille à deux ou trois colonnes | Décision écrite du DSI |
| Client de test de Zitadel peut-être créé par l'API après « prêt », alors que Keycloak et Authentik le déclarent au démarrage | M1 de Zitadel plus court, à périmètre différent | M6 dit comment le client est créé ; écart écrit dans la sensibilité |
| Certifications OpenID et listes d'adoptants tenues par les éditeurs eux-mêmes | Maturité lue sur des sources non indépendantes | Aucune source indépendante trouvée |
| Pages de Zitadel lues en partie : le guide de configuration dépasse ce que l'outil lit d'un coup (167 431 caractères) | Une capacité déclarative peut avoir échappé à la lecture (5.8) | Relecture complète avant l'écriture du script |

## 9. Sources

<!--
Une ligne par source, citée [Sn] dans le rapport. Source officielle d'abord
(principe VIII) : dépôt, documentation, site du projet ou de la fondation.
Une source tierce se signale dans la dernière colonne et ne justifie pas seule
une note. URL entre chevrons, par exemple <https://example.org/page>.
-->

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
| S14 | <https://www.keycloak.org/server/containers> | 2026-11-20 | `start-dev` à éviter en production ; construction optimisée par `kc.sh build` ; import au démarrage ; amorçage par `KC_BOOTSTRAP_ADMIN_USERNAME` et `KC_BOOTSTRAP_ADMIN_PASSWORD` ; tas à 70 % de la limite du conteneur ; santé sur le port 9000 | Oui |
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
| S26 | <https://zitadel.com/docs/self-hosting/deploy/kubernetes> | 2026-11-20 | Chart Helm, Kubernetes 1.30 ou plus, PostgreSQL 14 à 18, HTTP/2 de bout en bout pour la console, API en Go et connexion en Next.js, tâches d'initialisation, clé maître immuable, identifiants du démarrage rapide `Password1!` | Oui |
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
| S44 | <https://openid.net/developers/certified-openid-connect-implementations/> | 2026-11-20 | Keycloak 18.0.0 (déconnexion) et 15.0.2 (FAPI) certifiés par Red Hat ; authentik 2026.8.0 par son éditeur ; aucune ligne Zitadel trouvée | Oui |
| S45 | <https://opensource.org/licenses> | 2026-11-20 | Apache-2.0, AGPL-3.0, MIT et GPL-3.0 approuvées ; aucune licence entreprise d'Authentik | Oui |
| S46 | <https://docs.cloud.google.com/identity-platform/docs/product-comparison> | 2026-11-20 | OpenID Connect et SAML, locataires multiples, fonctions bloquantes, SLA de 99,95 % | Oui |
| S47 | <https://docs.cloud.google.com/identity-platform/docs/concepts-authentication> | 2026-11-20 | Connexion par SDK et bibliothèques d'interface ; OpenID Connect et SAML en fournisseurs fédérés ; aucun rôle de serveur d'autorisation décrit | Oui |
| S48 | <https://docs.cloud.google.com/identity-platform/docs/release-notes> | 2026-11-20 | GA le 2019-04-09, locataires en GA le 2019-11-18, dernière note le 2024-12-03 | Oui |
| S49 | <https://cloud.google.com/identity-platform/pricing> | 2026-11-20 | Page illisible par l'outil ; extrait du moteur de recherche : premier palier gratuit de 0 à 50 000 utilisateurs actifs par mois | Oui, lue par extrait |
| S50 | <https://docs.cloud.google.com/identity-platform/docs/multi-tenancy-billing> | 2026-11-20 | Le palier dépend du fournisseur qui authentifie, pas du protocole entre l'application et Identity Platform | Oui |
| S51 | <https://firebase.google.com/docs/auth/admin/verify-id-tokens> | 2026-11-20 | Jeton RS256, émetteur `https://securetoken.google.com/<projectId>`, clés publiques de Google, vérifiable par une bibliothèque JWT | Oui |
| S52 | <https://github.com/hashicorp/terraform-provider-google/tree/main/website/docs/r> | 2026-11-20 | Ressources `google_identity_platform_config`, `_tenant`, `_oauth_idp_config`, `_inbound_saml_config` et leurs variantes ; provider v8.12.0 du 2026-11-17 | Oui |
| S53 | <https://github.com/keycloak/keycloak/graphs/contributors> | 2026-11-20 | API `stats/contributors` : 3 470 commits humains par 177 auteurs depuis le 2025-11-20 ; premier 12,6 %, trois premiers 22,6 % | Oui |
| S54 | <https://github.com/zitadel/zitadel/graphs/contributors> | 2026-11-20 | Même API : 817 commits humains par 34 auteurs ; premier 20,0 %, trois premiers 41,3 % | Oui |
| S55 | <https://github.com/goauthentik/authentik/graphs/contributors> | 2026-11-20 | Même API : 3 712 commits humains par 153 auteurs, 2 046 de Dependabot écartés ; premier 19,8 %, trois premiers 49,2 % | Oui |
| S56 | <https://api.github.com/users/ahus1>, et de même pour les six premiers auteurs humains de chaque dépôt (`gh api users/<login>`) | 2026-11-20 | Employeurs déclarés : IBM ou Red Hat pour les six premiers de Keycloak, Zitadel pour les six premiers de Zitadel, goauthentik ou Authentik Security pour quatre des six premiers d'Authentik | Oui, déclaratif |
| S57 | <https://github.com/goauthentik/authentik/blob/version/2026.8.6/lifecycle/container/Dockerfile> | 2026-11-20 | Ligne 224 : `COPY ./authentik/ /authentik`, donc `authentik/enterprise/` dans l'image | Oui |
| S58 | <https://docs.goauthentik.io/install-config/configuration/> | 2026-11-20 | « authentik supports PostgreSQL 14 - 18 » | Oui |

## 10. Relectures

<!--
[SECU] relit licences, critères éliminatoires et sécurité. [FINOPS] relit le
coût. Le statut passe à « relu » quand les deux avis sont rendus et leurs
remarques traitées.
-->

| Relecteur | Porte sur | Date | Avis |
| --- | --- | --- | --- |
| [SECU] | Licences, critères éliminatoires, sécurité | AAAA-MM-JJ | Favorable, réservé ou défavorable |
| [FINOPS] | Coût | AAAA-MM-JJ | Favorable, réservé ou défavorable |

[SECU] Remarques et suite donnée.

[FINOPS] Remarques et suite donnée.
