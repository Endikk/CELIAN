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

# BENCH-013. Serveur de mails de test du profil standard

| Champ | Valeur |
| --- | --- |
| Identifiant | BENCH-013 |
| Sujet | Serveur de mails de test du profil standard sur le PC, et ce qui le remplace sur GCP |
| Statut | brouillon |
| Ouvert le | 2026-11-20 |
| Mis à jour le | 2026-11-20 |
| Auteur | [BENCH] |
| Relecteurs | [SECU] pour les licences et les CVE, [FINOPS] pour les coûts |
| Périmètre | Projet généré sur PC (cluster local), et projet généré sur GCP pour la parité |
| Choix du PRD | Aucune ligne du tableau des choix ouverts : composition du profil standard, décision de Lucas du 2026-11-20 (US-005) |
| ADR lié | ADR-014, à écrire par [ARCHI] |
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
Mailpit, et Mailpit passe par un benchmark avant d'entrer dans le golden repo.
Les paragraphes [DSI] cadrent la question ; [BENCH] les reprend ou les corrige
sous son tag.

[DSI] Question posée : quel serveur de mails de test le profil standard du
projet généré démarre dans le cluster local, pour capter les mails que
l'application envoie sans qu'aucun ne quitte le poste.

[DSI] Ce qui en dépend. US-005 et la spec du golden repo (FR-006) : le profil
standard sert de mesure au critère des 15 minutes (section 7 du PRD), donc le
volume et le temps de démarrage de cette brique comptent dans ENF-01 et R-04.
ADR-006 : pas d'outil de boucle derrière `task up`. ADR-005 et R-20 : son
interface web et son port SMTP restent en boucle locale. ADR-007 : s'il prend
un identifiant, `task up` le crée. Principes III, V, VI et VIII.

[DSI] Une question de parité à instruire, sans la trancher : ENF-02 veut que
chaque brique existe sur les deux cibles. Sur GCP, un serveur de test n'a pas
de pendant direct. [BENCH] dit ce que la documentation de GCP propose pour
l'envoi de mails, ou s'il n'y a rien, et [ARCHI] tranche dans l'ADR ce que la
couche `gcp` met à la place, ou l'écart à lister dans le README.

[DSI] Option pressentie : Mailpit, proposé pour le profil standard par
BENCH-005 et retenu dans la composition du profil par Lucas. Elle est notée
comme les autres. Les autres options sont à établir par [BENCH], sources à
l'appui, critères éliminatoires compris.

[DSI] Règles de notation de la GATE 1 (`TEMPLATE.md`) : volume noté sur
linux_amd64 ; la brique est une couche, comptée contre ses propres seuils ;
mémoire lue au nœud, moins kind seul ; seuils écrits avec leur heure UTC
avant la première mesure. Mesures sous le verrou de mesure partagé, après
BENCH-010 et BENCH-011.

[DSI] Hors champ : l'usage des mails par l'application d'exemple, qui se
décide dans le plan de la spec 001 (Q7) ; le choix d'un fournisseur d'envoi
réel pour un client en production.

[BENCH] Lecture retenue de la question, à confirmer par le DSI. Le serveur
capte en SMTP les mails envoyés depuis le cluster, les montre au développeur
dans une interface web et les rend lisibles par une API HTTP pour les tests.
Il tourne sur un nœud linux amd64 comme arm64 (Q5), sans port publié hors de
la boucle locale (R-20), et ne relaie rien vers l'extérieur. L'interface web
est une hypothèse de [BENCH], tirée de l'usage que vise le brief (« Mail de
dev », section 6) : sans elle, une option portée par une fondation entrerait
dans la liste (section 2).

## 2. Options étudiées

<!--
Deux ou trois options : celles de la section 8 du brief, sauf raison écrite
sous le tableau. Version examinée : la dernière release stable à la date de
lecture de sa source.
-->

| Option | En une phrase | Version examinée | Publiée le | Sources |
| --- | --- | --- | --- | --- |
| Mailpit | Serveur SMTP de test en Go, binaire unique, avec interface web, API REST et POP3 ; option pressentie | v1.34.0, image `axllent/mailpit` (linux/amd64, linux/arm64, linux/386) | 2026-11-17 | [S1], [S2], [S8], [S16] |
| maildev | Serveur SMTP de test en Node.js, avec interface web et API REST, entièrement reconstruit en 3.0 | 3.0.0, image `maildev/maildev` (linux/amd64, linux/arm64) | 2026-09-23 | [S22], [S23], [S29], [S31] |
| smtp4dev | Serveur SMTP, IMAP et POP3 de test en .NET, avec interface web et API décrite en OpenAPI | 3.16.1, image `rnwood/smtp4dev` (linux/amd64, linux/arm64, Windows) | 2026-11-06 | [S33], [S34], [S42], [S44] |

[BENCH] Choix des options. La section 8 du brief ne prévoit pas ce
benchmark : sa liste s'arrête à BENCH-007. Le brief nomme Mailpit dans la
stack du blueprint (« Mail de dev : Mailpit », section 6) et range MailHog
parmi les pièges connus (section 5). Les options sont donc établies par
[BENCH], avec une règle écrite avant toute note : parmi les serveurs de mails
de test repérés qui passent les trois critères éliminatoires et offrent une
interface web, une API HTTP et une image linux pour amd64 et arm64 (Q5), les
trois plus suivis sur GitHub le 2026-11-20. Ce sont Mailpit (10 990 étoiles),
maildev (6 163) et smtp4dev (4 032) [S1], [S22], [S33]. Le nombre d'étoiles
est un indicateur faible, gardé parce qu'il est daté et vérifiable ; il sert
à la sélection et n'entre dans aucune note.

[BENCH] Versions. Mailpit v1.34.0 a trois jours à la date de lecture, et le
principe VI fait attendre 7 jours aux mises à jour : le blueprint pourrait la
figer à partir du 2026-11-24. Elle corrige toutefois l'avis
GHSA-v887-64wg-qqc9 [S21], si bien que l'exception de sécurité de la
constitution 1.2.0 s'applique dès que sa PR passe la matrice. maildev 3.0.0
est une « Complete project re-build » [S23] ; la ligne précédente, 2.2.1 du
2024-12-12, a plus de douze mois. smtp4dev publie des préversions
d'intégration continue presque chaque jour : la version examinée est la
dernière qui n'en est pas une [S34].

[BENCH] Options repérées mais non étudiées :

- MailHog, piège connu du brief : dernière release v1.0.1 le 2020-08-11
  [S48]. Il serait éliminé sur le critère de release.
- MailCatcher : dernière release v0.10.0 le 2024-05-25 [S49], même critère.
- Inbucket (MIT, v3.2.0 le 2026-10-10, 2 314 étoiles) [S50] et MailCrab
  (Apache-2.0, v1.9.0 le 2026-08-02, 1 004 étoiles) [S51] passent les
  critères, mais viennent après les trois retenues dans la règle de sélection.
- GreenMail (Apache-2.0, 2.1.15 le 2026-10-25, 756 étoiles) se présente
  comme un serveur à embarquer dans un test unitaire ou à lancer en
  conteneur ; la lecture par un client web passe par un projet séparé [S52].
- Mailtrap Local (MIT) : dépôt créé le 2026-05-05, en v0.5.1 [S53], trop
  jeune pour le principe VI. Laravel Sail le propose à côté de Mailpit
  [S17].
- mock-smtp-server d'Apache James [S54], seul candidat porté par une
  fondation que [BENCH] a trouvé (principe V). Son interface HTTP règle le
  comportement du serveur et liste les mails reçus, sans interface de
  lecture. Son image se construit depuis les sources avec Jib, et l'exemple
  du README lance `linagora/mock-smtp-server`, image d'une entreprise. Écarté
  faute d'interface : si Lucas juge l'interface inutile au profil standard,
  il redevient candidat, et le principe V pèse pour lui (question ouverte).

### Parité sur GCP

[BENCH] Question de la section 1, instruite sans être tranchée. Faits lus le
2026-11-20 dans la documentation de Google Cloud :

1. La page de Compute Engine sur l'envoi de mails ne cite aucun service
   d'envoi managé par Google. Elle recommande des fournisseurs tiers
   (SendGrid, Mailgun, Mailjet) ou, pour les clients de Google Workspace, son
   relais SMTP, qui n'accepte que les ports 465 et 587 [S56].
2. Google Cloud bloque la sortie vers le port TCP 25 d'une adresse externe,
   sauf dans les projets qu'il juge à faible risque. SMTP en TLS sur 465 et
   587 est exclu du blocage, et le trafic vers une adresse interne n'est pas
   touché [S57]. La page décrit ce blocage au niveau du réseau, hors règles
   de pare-feu, sans nommer GKE.
3. Google qualifie d'ancien (« legacy ») le service Mail d'App Engine : son
   guide de migration renvoie vers les trois mêmes fournisseurs SMTP tiers
   [S59].
4. Identity Platform, que le brief met en face de Keycloak sur GCP, envoie
   lui-même les mails de ses parcours, soit « on behalf of developer »
   (méthode `DEFAULT`), soit par un relais SMTP que fournit le développeur
   (méthode `CUSTOM_SMTP`) [S58]. Ce qui remplace Keycloak sur GCP relève de
   BENCH-012.

[BENCH] Ce que ces faits impliquent pour l'ADR-014, sans préférence de
[BENCH]. Aucun service managé de Google ne joue le rôle d'un serveur de test :
lu comme le fait l'ADR-009, le principe III ne désigne aucun candidat
`managed` sur `gcp`. Or le schéma du catalogue exige une entrée `gcp` de type
`managed`, ou `oss` avec un `managed_gap` (`schema/catalog-entry.schema.json`,
`catalog/README.md`). Il n'a pas de type pour un fournisseur tiers comme
SendGrid, ni de moyen d'écrire « pas d'équivalent sur cette cible », et sa
liste `standards` ne contient pas SMTP. Trois voies restent ouvertes, à
[ARCHI] de choisir :

- rien sur `gcp` : l'application lit l'hôte SMTP dans sa configuration, et
  le README généré liste l'écart (ENF-02). Le schéma doit alors accepter
  l'absence d'équivalent ;
- le même serveur de test dans un environnement non productif sur GKE, en
  `oss` avec `managed_gap` : un outil qui garde des mails tournerait sur le
  cloud, ce que [SECU] doit relire ;
- un relais réel, fournisseur tiers ou Workspace, sur 465 ou 587 : hors champ
  de ce benchmark (section 1), et hors du schéma actuel.

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
| Mailpit | Oui, MIT [S1], approuvée OSI [S46] | Oui, dépôt non archivé, dernier commit le 2026-11-19 [S1], [S3] | Oui, v1.34.0 le 2026-11-17 [S2] | 2026-11-20 | Retenue |
| maildev | Oui, MIT [S22], approuvée OSI [S46] | Oui, dépôt non archivé, dernier commit le 2026-09-24 [S22], [S24] | Oui, 3.0.0 le 2026-09-23 [S23] | 2026-11-20 | Retenue |
| smtp4dev | Oui, BSD-3-Clause [S33], approuvée OSI [S47] | Oui, dépôt non archivé, dernier commit le 2026-11-06 [S33], [S35] | Oui, 3.16.1 le 2026-11-06 [S34] | 2026-11-20 | Retenue |

[BENCH] Réserve sur maildev, sans élimination. Entre 2.2.1 (2024-12-12) et
3.0.0-rc.1 (2026-07-06), le projet est resté 19 mois sans release [S23] : une
vérification faite entre le 2025-12-12 et le 2026-07-06 l'aurait éliminé. La
réserve se note en maturité (5.3) et en activité (5.4).

[BENCH] Options éliminées : aucune des trois. MailHog et MailCatcher,
repérés, l'auraient été sur le critère de release (section 2).

## 4. Mesures

<!--
Une mesure réelle pour chaque critère où elle a un sens, en général
l'empreinte sur PC (ENF-02). Si aucune n'en a, le dire en une phrase et
retirer les sous-sections.
-->

### 4.1 Ce qui est mesuré

[BENCH] Seuils d'empreinte écrits le 2026-11-20 à 20:14 UTC, avant toute
mesure et avant tout test de fumée. Le SHA-256 de cette section, du titre
« 4.1 » jusqu'à la ligne qui précède le titre « 4.2 », est relevé au même
moment dans le dossier de travail de [BENCH]. Chaque option part de 5 et perd
un cran par seuil dépassé (règle de `TEMPLATE.md`, section 5.6). Le serveur
de mails de test est une couche du profil standard : d'après la deuxième
règle de la GATE 1, il se note contre ses propres seuils, et son cumul avec
la plate-forme de base et les autres couches du profil standard va dans la
sensibilité. Les quatre seuils reprennent ceux des dernières couches notées,
l'outil GitOps de BENCH-009 et Postgres local de BENCH-011, sans adaptation,
pour que l'ordre des benchmarks ne décide pas des notes :

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

[BENCH] Ce qui a été lu avant ces seuils : les métadonnées GitHub des dépôts
candidats (licence, releases, commits), relevées de 20:10 à 20:12 UTC. Aucune
taille d'image, aucune mémoire et aucun temps de démarrage d'une option n'ont
été lus. Les parts elles-mêmes (10 % du budget, un seizième de 8 Gio) restent
un choix de [BENCH] : le budget par étape d'ENF-01 n'est pas fixé (R-04). Si
aucune option ne dépasse de seuil, le critère ne départage pas, et chaque
option reçoit la même note avec cette raison (section 5).

| ID | Mesure | Unité | Critère alimenté | Script |
| --- | --- | --- | --- | --- |
| M1 | Installation jusqu'à « prêt », images tirées par le nœud | s | Empreinte sur PC | `tests/bench/bench-013-test-mail.sh` |
| M2 | Mémoire de la couche au repos : nœud avec l'option moins nœud de base (M7) ; mémoire du pod de l'option en sensibilité | Mio | Empreinte sur PC | `tests/bench/bench-013-test-mail.sh` |
| M3 | CPU du pod de l'option au même moment | % d'un cœur | Empreinte sur PC | `tests/bench/bench-013-test-mail.sh` |
| M4 | Volume compressé des images, par architecture, et images retéléchargées à chaque création | Mo, nombre | Empreinte sur PC (ENF-01, R-04, R-25) | `tests/bench/bench-013-test-mail.sh` |
| M5 | Délai entre l'envoi d'un mail en SMTP depuis un pod du cluster et sa lecture par l'API HTTP de l'option | s | Expérience dev | `tests/bench/bench-013-test-mail.sh` |
| M6 | Démarrage natif sur un nœud arm64, sans émulation | oui ou non | Portabilité | `tests/bench/bench-013-test-mail.sh` |
| M7 | Mémoire du nœud de base, sans serveur de mails (option `none` du script) | Mio | Empreinte sur PC, base de M2 | `tests/bench/bench-013-test-mail.sh` |
| M8 | Interface et API refusées sans identifiant, identifiant lu dans un Secret créé par tube et absent des arguments du processus | oui ou non | Sécurité (R-20, ADR-007) | `tests/bench/bench-013-test-mail.sh` |

### 4.2 Machine de mesure

[BENCH] Machine prévue, relevée le 2026-11-20 par `sysctl` et `sw_vers`, sans
lancer le moteur de conteneurs. Le script relève de nouveau le moteur et ses
ressources au lancement de la série ; ce tableau se corrige s'ils ont changé.

| Élément | Valeur |
| --- | --- |
| Modèle | Apple Mac16,7 |
| Processeur | Apple M4 Pro, 14 cœurs (10 performance, 4 efficacité), arm64 |
| Mémoire | 24 Gio (25 769 803 776 octets) |
| Système | macOS 27.2.1 (build 26B131) |
| Moteur de conteneurs | À relever par le script (`docker info`). Pour mémoire, OrbStack 2.2.5 et Docker Engine 29.8.2 le 2026-11-19 (BENCH-009) ; moteur non libre, voir R-26 |
| Ressources allouées | À relever par le script. Pour mémoire, 14 CPU et 11,73 Gio pour la machine virtuelle d'OrbStack le 2026-11-19 (BENCH-009) |
| Versions mesurées | kind 0.33.0, image de nœud `kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed` (ADR-004) ; Mailpit v1.34.0, maildev 3.0.0, smtp4dev 3.16.1, busybox 1.37.0 pour le client SMTP, chacune figée par condensat d'index dans le script |
| Charge parasite | À relever par le script : charge moyenne sur une minute au début de chaque exécution. Aucun autre conteneur actif, verrou de mesure partagé tenu |

### 4.3 Protocole

<!--
Assez précis pour qu'un tiers refasse la mesure. Au moins trois exécutions
par option et par mesure. Dire si les images sont déjà en cache : le temps de
démarrage en dépend.
-->

[BENCH] Protocole écrit le 2026-11-20 pendant la phase de lecture. Le script
n'existe pas encore ; il s'écrira avant la série, qui attend BENCH-010 et
BENCH-011. Il reproduit les gestes de `task up` : aucun outil de boucle
(ADR-006), Secrets créés par tube avant l'application des manifests
(ADR-007), images et manifests figés par condensat (conditions 3 et 4 de
l'ADR-004).

1. Préparation, une fois par série. Le script fige chaque image par son
   condensat d'index, relevé dans le registre à l'écriture du script :
   `axllent/mailpit:v1.34.0`, `maildev/maildev:3.0.0`,
   `rnwood/smtp4dev:3.16.1`, et `busybox:1.37.0` pour le client SMTP, comme
   dans BENCH-009. Aucun des trois projets ne publie de manifest Kubernetes
   ni de chart dans les pages lues [S9], [S29], [S40] : les manifests de
   chaque option (un Deployment, un Service, un fichier `kustomization.yaml`,
   aucun Secret) sont écrits par [BENCH] et versionnés sous
   `tests/bench/bench-013/`. Le script vérifie le SHA-256 de chaque fichier
   contre la valeur qu'il fige, et s'arrête si une image reste sans
   condensat. Il relève dans le registre les tailles compressées par
   architecture, sans rien tirer (M4).
2. Configuration commune, même intention pour les trois options : SMTP et
   HTTP sur des ports non privilégiés, aucune persistance hors du pod, aucun
   relais, aucun port publié vers l'hôte. Chaque conteneur suit le profil
   « Restricted » des Pod Security Standards : `allowPrivilegeEscalation:
   false`, `runAsNonRoot: true`, `runAsUser` non nul, profil seccomp
   `RuntimeDefault`, capacités `ALL` retirées [S61]. Les Dockerfile de
   Mailpit et de smtp4dev ne déclarent pas d'utilisateur [S7], [S37] : le
   manifest fixe `runAsUser`. smtp4dev écoute par défaut sur les ports 80 et
   25 [S37], [S38] : le manifest les déplace par variables d'environnement.
   Mailpit reçoit `MP_DISABLE_VERSION_CHECK=true`, sans quoi il interroge
   GitHub [S11] (R-25). Une option qui ne démarre pas sous ce profil est
   consignée, et l'écart se note en sécurité.
3. État de départ de chaque exécution : aucun cluster `celian-bench-013`. Le
   script crée un cluster kind neuf avec l'image de nœud de l'ADR-004,
   kubeconfig dans le dossier d'essai, et attend qu'il soit prêt. Les images
   des options ne sont pas préchargées : le nœud les tire à chaque
   exécution, comme au premier `task up` d'un poste.
4. Secret (M8) : le script tire un mot de passe de 32 caractères de
   `/dev/urandom` et crée le Secret par `printf` dans un tube vers
   `kubectl create -f -`, sans écho de commande, avant d'appliquer les
   manifests (condition 1 de l'ADR-007). Chaque option le lit par sa voie
   documentée, en variable d'environnement tirée du Secret, jamais en
   argument : `MP_UI_AUTH` pour Mailpit [S12],
   `ServerOptions__WebAuthenticationRequired`,
   `ServerOptions__Users__0__Username` et
   `ServerOptions__Users__0__Password` pour smtp4dev [S38], [S39],
   `MAILDEV_WEB_USER` et `MAILDEV_WEB_PASS` pour maildev [S29].
5. Installation (M1) : `kubectl apply -k` du dossier vérifié de l'option.
   Fin de la mesure : le premier de trois contrôles consécutifs, espacés
   d'une seconde, où le Deployment est prêt et le pod Running et Ready. La
   sonde de disponibilité vise `/readyz` pour Mailpit, route servie hors de
   l'authentification [S15], `/api/healthz` pour maildev [S30], et le port
   HTTP en TCP pour smtp4dev, faute de route de santé dans les pages lues.
6. Envoi (M5) : un Job busybox envoie un mail au sujet propre à l'exécution
   par `sendmail -S <service>:<port> -f <expéditeur>` [S60]. Dès que le Job
   est vu terminé, le script interroge l'API de l'option avec l'identifiant
   (`/api/v1/messages` pour Mailpit [S14], `/api/email` pour maildev [S30],
   `/api/messages` pour smtp4dev [S42]) jusqu'à y lire ce sujet. La présence
   de l'applet `sendmail` dans l'image busybox se vérifie au premier test de
   fumée.
7. Contrôles d'accès (M8), depuis un pod du cluster : la même requête sans
   identifiant doit être refusée, et avec l'identifiant acceptée. Un contrôle
   statique échoue si un manifest porte la valeur dans `command` ou `args`.
   Une commande lancée dans le conteneur vérifie que `/proc/1/cmdline` ne
   contient pas la valeur, lue dans sa propre variable d'environnement : la
   valeur ne sort jamais du pod et n'est jamais affichée.
8. Repos (M2, M3) : 120 s après M5, trois échantillons espacés de 10 s de
   l'API Summary du kubelet (mémoire de travail et CPU du pod de l'option),
   et du conteneur du nœud par `docker stats` au même moment ; médiane des
   trois. La mémoire de la couche est celle du nœud moins celle du nœud de
   base (M7), en médianes (troisième règle de la GATE 1).
9. Architecture (M6) : le script relève l'architecture du nœud et le
   condensat de plate-forme que le nœud a tiré, et vérifie qu'il s'agit de
   l'entrée arm64 de l'index, sans émulation.
10. Fin : suppression du cluster, 15 s de pause. Trois exécutions par option,
    options alternées (Mailpit, maildev, smtp4dev, puis on recommence) pour
    répartir les variations du réseau et de la charge. Les événements
    `Pulled` du nœud donnent les images tirées (M4).
11. Nœud de base (M7), série de référence à part : l'option `none` suit les
    mêmes étapes, Secret compris, sans serveur de mails ni Job d'envoi, trois
    exécutions.

[BENCH] Le script prendra le verrou de mesure partagé (`BENCH_LOCK`) et
refusera de démarrer s'il est pris ou si le cluster existe déjà, comme celui
de BENCH-009. Il passera shellcheck, tournera sous le bash 3.2 de macOS, en
`umask 077`, avec `KUBECONFIG` dans le dossier d'essai : `~/.kube` n'est ni
lu ni écrit.

Pour refaire la mesure, une fois le script écrit :

```bash
BENCH_LOCK=/chemin/vers/un/verrou tests/bench/bench-013-test-mail.sh /chemin/vers/un/dossier/vide
OPTIONS=none BENCH_LOCK=/chemin/vers/un/verrou tests/bench/bench-013-test-mail.sh /chemin/vers/un/autre/dossier   # nœud de base, M7
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

[BENCH] Notes de la phase de lecture, écrites le 2026-11-20 avant toute
mesure. Elles restent provisoires : l'essai de la section 4 peut changer la
sécurité (M8, profil « Restricted »), la portabilité (M6) et l'expérience
dev (M5), et la section 5.6 attend les mesures. Les métadonnées GitHub sont
relevées par `gh api` le 2026-11-20 ; les commits humains excluent les
fusions et les auteurs de type Bot (Renovate, Dependabot, agent Copilot).

### 5.1 Licence et liberté d'usage, poids 15

<!--
Licence exacte, ce qu'elle impose au générateur (Apache-2.0) et aux projets
générés, changement de licence passé. Preuves : fichier de licence du dépôt,
annonce officielle.
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Mailpit | 5/5 | 15 | MIT, approuvée OSI, dans le fichier `LICENSE` depuis le premier commit du 2022-07-29, sans accord de contribution. Le projet généré tire l'image et n'en redistribue rien | [S1], [S46] |
| maildev | 5/5 | 15 | MIT, approuvée OSI, depuis la première release de 2013 ; le texte a été corrigé le 2026-01-09 sans changer de licence | [S22], [S46] |
| smtp4dev | 4/5 | 12 | BSD-3-Clause, approuvée OSI. Réserve : l'accord de contribution donne au projet le droit de « sublicense, and/or sell » les contributions, ce qui permettrait de publier les versions futures sous d'autres termes ; les versions publiées restent sous BSD-3-Clause | [S33], [S43], [S47] |

### 5.2 Gouvernance (fondation, multi-vendeurs), poids 15

<!--
Fondation porteuse, éditeur unique ou communauté, nombre d'entreprises parmi
les mainteneurs (principe V). Preuves : page du projet chez la fondation,
fichier des mainteneurs, statistiques de contribution datées.
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Mailpit | 2/5 | 6 | Aucune fondation : dépôt d'un compte personnel, droit d'auteur à une personne. Sur 471 commits humains en 12 mois, 441 (93,6 %) viennent de ce mainteneur, 18 auteurs en tout. Soutien affiché de Mailtrap, sans termes publiés ; Mailtrap publie depuis le 2026-05-05 son propre outil local, Mailtrap Local | [S1], [S3], [S19], [S20], [S53] |
| maildev | 2/5 | 6 | Aucune fondation : organisation GitHub dont un seul membre est public, droit d'auteur à une personne. Sur 97 commits humains en 12 mois, 89 (91,8 %) viennent de cette personne, 7 auteurs en tout | [S22], [S24], [S55] |
| smtp4dev | 2/5 | 6 | Aucune fondation : dépôt d'un compte personnel, accord de contribution au profit du projet. Sur 166 commits en 12 mois, 154 ont un auteur de type Bot (114 Renovate, 40 l'agent Copilot) ; restent 12 commits humains de 8 auteurs, dont 5 du mainteneur | [S33], [S35], [S43] |

[BENCH] Le critère ne départage pas : les trois options reposent sur une
personne, sans fondation ni entreprise qui les porte, comme k3d dans
BENCH-003 (2/5). Une lecture plus stricte, 1/5 pour un projet tenu par une
seule personne, toucherait les trois de la même façon. Quelle que soit
l'option retenue, le principe V demande un ADR qui justifie l'écart ; le seul
candidat porté par une fondation trouvé, mock-smtp-server d'Apache James,
n'a pas d'interface de lecture (section 2).

### 5.3 Maturité et adoption, poids 15

<!--
Ancienneté, niveau de maturité dans la fondation, adoption en production
déclarée (principe VI : pas de projet qui vient de sortir). Preuves : page de
la fondation, liste d'adoptants en précisant qui la tient.
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Mailpit | 5/5 | 15 | Dépôt créé le 2022-07-29, version 1.0.0 le 2022-09-03, 248 160 030 tirages de l'image sur Docker Hub. Adoption attestée par la documentation des adoptants eux-mêmes : Mailpit est le service de mails du fichier Compose par défaut de Laravel Sail, et le capteur de mails de DDEV. Le projet ne tient pas de liste d'adoptants | [S1], [S16], [S17], [S18] |
| maildev | 3/5 | 9 | Projet de 2013, 60 228 176 tirages de l'image. Réserve qui demande une action : la version examinée, 3.0.0, est une reconstruction complète publiée le 2026-09-23, soit 58 jours de recul, après 19 mois sans release (section 3). Le README conseille lui-même de revenir à la v2 « if you run into any issues ». Ce code n'a pas l'ancienneté du projet (principe VI) | [S22], [S23], [S29], [S31] |
| smtp4dev | 4/5 | 12 | Dépôt créé le 2012-01-13, version majeure 3, 19 396 844 tirages de l'image, binaires et outil .NET publiés à chaque release. Réserve : aucune liste d'adoptants ni adoption tierce trouvée dans les pages lues | [S33], [S34], [S44] |

[BENCH] Les tirages de Docker Hub comptent aussi les exécutions de CI, et ne
mesurent pas le nombre d'équipes : ils servent d'ordre de grandeur, jamais de
preuve seule. La note de Mailpit tient sur la documentation de Laravel et de
DDEV, sources officielles de ces deux projets mais tierces pour Mailpit.
Sans elles, Mailpit tomberait à 4/5, comme smtp4dev.

### 5.4 Activité et maintenance, poids 10

<!--
Rythme des releases sur 12 mois, contributeurs actifs, délai de réponse aux
tickets. Preuves : page des releases, statistiques du dépôt, datées.
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Mailpit | 5/5 | 10 | 32 releases stables en 12 mois, de v1.28.0 (2025-11-26) à v1.34.0 (2026-11-17), à peu près une tous les 11 jours. 471 commits humains, dernier commit le 2026-11-19 | [S2], [S3] |
| maildev | 3/5 | 6 | Une seule release stable en 12 mois, 3.0.0, après deux préversions ; 21 mois entre 2.2.1 et 3.0.0. 97 commits humains de 7 auteurs, aucun depuis le 2026-09-24. Réserve qui demande une action : vérifier que le rythme repris en 2026 se maintient | [S23], [S24] |
| smtp4dev | 3/5 | 6 | 6 releases stables en 12 mois, mais aucune entre 3.15.0 (2026-03-03) et 3.16.0 (2026-11-06). 12 commits humains seulement, le reste vient de Renovate et de l'agent Copilot ; les notes de release listent les fichiers publiés, pas les changements. Réserve qui demande une action : lire les commits pour savoir ce qu'apporte une version | [S34], [S35] |

### 5.5 Sécurité (CVE, réactivité), poids 10

<!--
Politique de signalement, avis de sécurité publiés, délai entre signalement
et correctif, CVE encore ouvertes. Relu par [SECU]. Preuves : politique de
sécurité du projet, base de CVE, avis du projet.
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Mailpit | 3/5 | 6 | 18 avis publiés par le dépôt du 2026-01-06 au 2026-11-17, aucun critique, 1 élevé selon le dépôt ; 15 sont dans la base mondiale, qui en classe 3 en élevé. Chacun sort avec sa version corrigée : SSRF des fonctions de vérification de liens et de HTML, dénis de service par SMTP ou par l'API, détournement de WebSocket. Signalement privé ouvert, accusé de réception visé sous 24 h. La réserve demande une action : 13 versions correctives à suivre en dix mois et demi, image sans utilisateur déclaré, donc en root sans `securityContext`, appel à GitHub par défaut à couper | [S4], [S5], [S6], [S7], [S11] |
| maildev | 2/5 | 4 | Aucun avis en 12 mois. Le seul avis connu, CVE-2024-27448 (critique, exécution de code à distance par un en-tête Content-ID, versions 2.0.0-beta1 à 2.1.0), a été signalé publiquement le 2023-08-25 et corrigé en 2.2.1 le 2024-12-12, quinze mois et demi plus tard. Politique de sécurité écrite, signalement privé ouvert, image en utilisateur `node`. La version 3.0.0, reconstruite, n'a pas encore d'historique | [S25], [S26], [S27], [S28], [S32] |
| smtp4dev | 2/5 | 4 | Aucun avis, ni au dépôt ni dans la base mondiale ; aucune politique de sécurité, seul le signalement privé de GitHub est ouvert, et les notes de release ne disent pas ce qu'une version corrige. Image en root, ports 80 et 25 privilégiés par défaut, `curl` installé. `LockSettings` vaut `false` par défaut : les réglages se modifient depuis l'interface web, et le même fichier porte des expressions JavaScript de validation. Il faut contourner : surveiller les images par scan faute d'avis | [S34], [S36], [S37], [S38] |

[BENCH] Aucune des trois n'a de signature d'image ni d'attestation de
provenance dans ses workflows publics (GitHub Actions pour Mailpit et
maildev, Azure Pipelines pour smtp4dev) ; Mailpit fige ses actions par SHA
[S45], [S62], [S63]. Le critère ne départage donc pas sur ce point, et
aucune note n'en tient compte.

[BENCH] Sensibilité. Compter le nombre d'avis contre Mailpit, au lieu de la
réactivité qu'ils montrent, le ferait tomber à 2/5 ; à l'inverse, lire la
politique de sécurité de maildev 3.x comme une rupture avec la réaction
lente de 2024 le ferait monter à 3/5. [SECU] tranche ces deux lectures.

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
| Mailpit | 5/5 | 10 | Image publiée pour linux/amd64, linux/arm64 et linux/386, binaire statique pour Linux, macOS et Windows : tourne sur tout cluster conforme, kind comme GKE ou un autre cloud. Arm64 natif à confirmer par M6 | [S9], [S16] |
| maildev | 5/5 | 10 | Image publiée pour linux/amd64 et linux/arm64, paquet npm : tourne sur tout cluster conforme. Arm64 natif à confirmer par M6 | [S29], [S31] |
| smtp4dev | 4/5 | 8 | Images linux/amd64, linux/arm64 et Windows, binaires et outil .NET. Réserve : la chaîne du projet construit l'image arm64 mais y a désactivé les tests de bout en bout, faute d'émulation fiable ; seul M6 dira si elle démarre | [S40], [S44], [S45] |

[BENCH] La parité sur GCP ne départage pas : aucune des trois n'a de
service managé en face chez Google, et aucune n'est plus ou moins déployable
sur GKE que les autres. Le principe III et le schéma du catalogue relèvent de
l'ADR-014 (section 2, « Parité sur GCP »), pas de cette note.

### 5.8 Expérience dev et documentation, poids 10

<!--
Qualité et fraîcheur de la documentation officielle, clarté des erreurs,
temps pour faire tourner un exemple minimal. Note de jugement : décrire
l'essai qui la fonde. Preuves : documentation officielle, essai consigné.
-->

[BENCH] Note de jugement, provisoire. Elle repose pour l'instant sur la
documentation seule ; l'essai qui la confirmera ou la corrigera est celui de
la section 4 : installation par les manifests du script, envoi et lecture
d'un mail (M5), contrôles d'accès (M8), trois fois par option, sans
intervention.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Mailpit | 5/5 | 10 | Site de documentation dédié ; chaque option a sa variable d'environnement, identifiants compris (`MP_UI_AUTH`, refusé en argument « for security reasons », ou un fichier de mots de passe hachés en bcrypt). Routes `/livez` et `/readyz` servies hors de l'authentification, API décrite en Swagger. Les ruptures de la v1.34.0 sont annoncées dans ses notes de release | [S10], [S11], [S12], [S13], [S14], [S15], [S21] |
| maildev | 4/5 | 8 | Tableau des options et de leurs variables dans le README, API REST documentée avec route `/api/healthz`, serveur MCP en option. Réserve : la 3.0.0 corrige encore la sonde de santé de son image et la prise en compte de `MAILDEV_HTTPS`, signes d'une réécriture jeune | [S23], [S29], [S30] |
| smtp4dev | 3/5 | 6 | Documentation fournie dans le dépôt, page dédiée à la publication des ports en boucle locale sous Docker, API décrite en OpenAPI sous `/api`, réglages par variables imbriquées (`ServerOptions__…`). La réserve demande une action : les valeurs par défaut (ports 80 et 25, root, `LockSettings` à `false`) sont à surcharger pour tourner sous le profil « Restricted », aucune route de santé n'a été trouvée, et les notes de release ne décrivent pas les changements | [S34], [S37], [S38], [S39], [S41], [S42] |

### 5.9 Coût (managé ou opérationnel), poids 5

<!--
Coût du service managé sur GCP, ou coût d'exploitation sur le PC et en
on-prem (temps, licence, support). Relu par [FINOPS]. Preuves : page de tarifs
officielle datée, estimation de [FINOPS].
-->

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Mailpit | 5/5 | 5 | Gratuit sous MIT, sans licence ni support payant requis. Mailtrap propose une offre hébergée pour les équipes, dont le projet généré n'a pas besoin | [S1], [S20] |
| maildev | 5/5 | 5 | Gratuit sous MIT, sans licence ni support payant requis | [S22] |
| smtp4dev | 5/5 | 5 | Gratuit sous BSD-3-Clause, sans licence ni support payant requis ; dons facultatifs | [S33] |

[BENCH] Le critère ne départage pas. Sur le PC, le coût d'exploitation se
réduit à la mémoire et au volume, notés en 5.6. Sur GCP, aucune des trois ne
tourne dans les voies lues en section 2, sauf si l'ADR-014 retient un serveur
de test dans un environnement GKE : [FINOPS] chiffrerait alors son pod sur
Autopilot, comme pour Flux et ESO dans BENCH-009 et BENCH-007.

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

[BENCH] Limites connues à la fin de la phase de lecture, le 2026-11-20. Les
limites propres aux mesures s'ajouteront avec la série.

| Limite | Effet possible sur le verdict | Ce qui la lèverait |
| --- | --- | --- |
| Une seule machine de mesure, différente du PC de référence de la phase 6 (pas encore défini, ENF-02) | Empreinte propre à ce matériel, sous un moteur non libre (R-26) | Relancer le script sur une deuxième machine, dont un poste linux amd64 |
| Option pressentie par le PRD et par le brief | Mailpit part avec l'attention du brief | Même règle de sélection écrite avant les notes, mêmes sources, même script pour les trois |
| Sélection des options par le nombre d'étoiles GitHub | Inbucket ou MailCrab pourraient valoir mieux qu'une des options retenues | Les ajouter à la série de mesure si le DSI le demande |
| Interface web supposée nécessaire (section 1) | Écarte le seul candidat porté par une fondation | Décision du DSI ou de Lucas |
| Notes de sécurité et d'expérience dev posées avant l'essai | Un cran par option, dans un sens ou dans l'autre | Essai de la section 4 et relecture [SECU] |
| Absence d'avis prise comme un fait pour maildev 3.x et smtp4dev | Une faille non publiée ne se voit pas | Scanner les images figées (Trivy, ENF-03) au premier essai |
| Adoption de Mailpit lue chez des tiers (Laravel, DDEV) et par les tirages de Docker Hub | Maturité surévaluée si ces projets changent d'outil ; les tirages comptent aussi la CI | Revoir à la prochaine vérification |
| Pages de Google Cloud lues sans date de mise à jour visible | Un service d'envoi managé apparu depuis échapperait à la section 2 | Relire les pages avant l'ADR-014 |

## 9. Sources

<!--
Une ligne par source, citée [Sn] dans le rapport. Source officielle d'abord
(principe VIII) : dépôt, documentation, site du projet ou de la fondation.
Une source tierce se signale dans la dernière colonne et ne justifie pas seule
une note. URL entre chevrons, par exemple <https://example.org/page>.
-->

[BENCH] Les métadonnées des dépôts GitHub (licence, archivage, releases,
commits, avis, membres) sont lues par `gh api` en lecture le 2026-11-20 ;
les données brutes sont gardées dans le dossier de travail de [BENCH]. Les
pages web sont lues par WebFetch le même jour.

| ID | URL | Lue le | Ce que la source établit | Officielle |
| --- | --- | --- | --- | --- |
| S1 | <https://github.com/axllent/mailpit> | 2026-11-20 | Licence MIT (fichier `LICENSE` depuis le premier commit du 2022-07-29), dépôt non archivé d'un compte personnel, créé le 2022-07-29, 10 990 étoiles | Oui |
| S2 | <https://github.com/axllent/mailpit/releases> | 2026-11-20 | v1.34.0 le 2026-11-17 ; 32 releases stables depuis le 2025-11-20, de v1.28.0 (2025-11-26) à v1.34.0 ; 1.0.0 le 2022-09-03 | Oui |
| S3 | <https://github.com/axllent/mailpit/commits/develop> | 2026-11-20 | 565 commits du 2025-11-20 au 2026-11-20, 471 commits humains hors fusion, 18 auteurs, 441 du mainteneur (93,6 %) ; dernier commit le 2026-11-19 | Oui |
| S4 | <https://github.com/axllent/mailpit/security/advisories> | 2026-11-20 | 18 avis publiés du 2026-01-06 au 2026-11-17, 1 élevé et 17 moyens selon le dépôt, chacun avec sa version corrigée (13 versions de 1.28.1 à 1.34.0) | Oui |
| S5 | <https://github.com/advisories?query=github.com%2Faxllent%2Fmailpit> | 2026-11-20 | 15 avis dans la base mondiale pour le module Go, dont 3 classés élevés (CVE-2026-45713, CVE-2026-67446, CVE-2026-67445) | Oui |
| S6 | <https://github.com/axllent/mailpit/blob/develop/.github/SECURITY.md> | 2026-11-20 | Signalement par avis privé de GitHub ou par courriel, accusé de réception « within 24 hours in most cases » ; signalement privé activé | Oui |
| S7 | <https://github.com/axllent/mailpit/blob/develop/Dockerfile> | 2026-11-20 | Base `alpine:latest`, aucune instruction `USER`, ports 1025, 1110 et 8025, `HEALTHCHECK` par `mailpit readyz` | Oui |
| S8 | <https://mailpit.axllent.org/docs/> | 2026-11-20 | Fonctions : capture SMTP, interface web, API REST, POP3, vérification de HTML et de liens, relais ; images Docker multi-architectures | Oui |
| S9 | <https://mailpit.axllent.org/docs/install/> | 2026-11-20 | Images pour 386, amd64 et arm64, binaire statique ; aucune mention de Kubernetes ni de Helm ; badge « Supported by Mailtrap » | Oui |
| S10 | <https://mailpit.axllent.org/docs/install/docker/> | 2026-11-20 | Image `axllent/mailpit` sur Docker Hub, miroir sur ghcr.io ; interface sur 8025 et SMTP sur 1025 par défaut | Oui |
| S11 | <https://mailpit.axllent.org/docs/configuration/runtime-options/> | 2026-11-20 | `MP_UI_AUTH_FILE`, `MP_SMTP_AUTH_FILE`, écoute par défaut sur 0.0.0.0 ; `MP_DISABLE_VERSION_CHECK` à `false` par défaut, Mailpit interroge alors GitHub ; `MP_ALLOW_INTERNAL_HTTP_REQUESTS` à `false` | Oui |
| S12 | <https://mailpit.axllent.org/docs/configuration/http/> | 2026-11-20 | `MP_UI_AUTH` en variable d'environnement, « not available as a CLI flag » pour raison de sécurité ; l'authentification couvre l'interface et l'API | Oui |
| S13 | <https://mailpit.axllent.org/docs/configuration/passwords/> | 2026-11-20 | Fichiers de mots de passe en clair ou hachés (SSHA, MD5Crypt, APR1Crypt, SHA, bcrypt, crypt SHA-256 et SHA-512) | Oui |
| S14 | <https://mailpit.axllent.org/docs/api-v1/> | 2026-11-20 | API REST sous `/api/v1/`, fichier Swagger 2.0 publié ; route `/api/v1/messages` dans `server/ui/api/v1/swagger.json` du dépôt | Oui |
| S15 | <https://github.com/axllent/mailpit/blob/develop/server/server.go> | 2026-11-20 | Routes `livez` et `readyz` enregistrées sans le middleware d'authentification, à côté des routes protégées | Oui |
| S16 | <https://hub.docker.com/r/axllent/mailpit> | 2026-11-20 | 248 160 030 tirages, dépôt enregistré le 2022-08-04 ; tag v1.34.0 pour linux/amd64, linux/arm64 et linux/386 | Oui |
| S17 | <https://laravel.com/docs/sail> | 2026-11-20 | Documentation de Laravel 13.x : le fichier Compose par défaut de Sail contient Mailpit ; Mailtrap Local proposé en option | Tierce pour Mailpit, officielle pour Laravel |
| S18 | <https://docs.ddev.com/en/stable/users/usage/developer-tools/> | 2026-11-20 | DDEV décrit Mailpit comme son capteur de mails de développement | Tierce pour Mailpit, officielle pour DDEV |
| S19 | <https://github.com/axllent/mailpit/blob/develop/README.md> | 2026-11-20 | « originally inspired by MailHog which is no longer maintained » ; Mailtrap présenté comme « our friendly companion » | Oui |
| S20 | <https://mailpit.axllent.org/docs/mailtrap/> | 2026-11-20 | Mailtrap « complements Mailpit », badge « Supported by Mailtrap », sans termes ni montants publiés | Oui |
| S21 | <https://github.com/axllent/mailpit/releases/tag/v1.34.0> | 2026-11-20 | Corrige GHSA-v887-64wg-qqc9 ; retire des options dépréciées depuis plus de deux ans et valide certains réglages au démarrage | Oui |
| S22 | <https://github.com/maildev/maildev> | 2026-11-20 | Licence MIT (fichier `LICENSE` depuis 2013, texte corrigé le 2026-01-09), dépôt non archivé d'une organisation, créé le 2013-03-31, 6 163 étoiles, droit d'auteur à une personne | Oui |
| S23 | <https://github.com/maildev/maildev/releases> | 2026-11-20 | 3.0.0 le 2026-09-23, « Complete project re-build » ; préversions le 2026-07-06 et le 2026-08-28 ; 2.2.1 le 2024-12-12, qui corrige CVE-2024-27448 ; corrections de la sonde de santé et de `MAILDEV_HTTPS` en 3.0.0 | Oui |
| S24 | <https://github.com/maildev/maildev/commits/main> | 2026-11-20 | 97 commits du 2025-11-20 au 2026-11-20, tous humains hors fusion, 7 auteurs, 89 du premier (91,8 %) ; dernier commit le 2026-09-24 | Oui |
| S25 | <https://github.com/maildev/maildev/blob/main/SECURITY.md> | 2026-11-20 | Versions 2.x et 3.x suivies, signalement privé de GitHub ou courriel, accusé de réception visé sous 3 jours ouvrés | Oui |
| S26 | <https://github.com/advisories/GHSA-vc6q-ccj9-9r89> | 2026-11-20 | CVE-2024-27448, critique : exécution de code à distance par un en-tête Content-ID, MailDev 2.0.0-beta1 à 2.1.0, publié le 2024-04-05 | Oui |
| S27 | <https://github.com/maildev/maildev/issues/467> | 2026-11-20 | Faille signalée publiquement le 2023-08-25, close le 2024-12-10 par la PR #508 | Oui |
| S28 | <https://github.com/maildev/maildev/blob/main/Dockerfile> | 2026-11-20 | Base `node:22-alpine`, `USER node`, ports 1080 et 1025, `HEALTHCHECK` | Oui |
| S29 | <https://github.com/maildev/maildev/blob/main/README.md> | 2026-11-20 | Options et variables (`MAILDEV_WEB_USER`, `MAILDEV_WEB_PASS`, `MAILDEV_INCOMING_USER`), serveur MCP, API REST, image Docker, paquet npm ; conseil de revenir à la v2 « if you run into any issues » ; aucune mention de Kubernetes ni de Helm | Oui |
| S30 | <https://github.com/maildev/maildev/blob/main/docs/rest.md> | 2026-11-20 | Routes `/api/email`, `/api/email/summary` et `/api/healthz` | Oui |
| S31 | <https://hub.docker.com/r/maildev/maildev> | 2026-11-20 | 60 228 176 tirages, dépôt enregistré le 2020-03-19 ; tag 3.0.0 pour linux/amd64 et linux/arm64 | Oui |
| S32 | <https://github.com/maildev/maildev/security/advisories> | 2026-11-20 | Aucun avis publié par le dépôt ; signalement privé activé | Oui |
| S33 | <https://github.com/rnwood/smtp4dev> | 2026-11-20 | Licence BSD-3-Clause (`LICENSE.md`), dépôt non archivé d'un compte personnel, créé le 2012-01-13, 4 032 étoiles ; profil communautaire sans politique de sécurité | Oui |
| S34 | <https://github.com/rnwood/smtp4dev/releases> | 2026-11-20 | 3.16.1 le 2026-11-06 ; 6 releases stables depuis le 2025-11-20 (3.11.0, 3.12.0, 3.14.0, 3.15.0 le 2026-03-03, 3.16.0, 3.16.1) ; préversions d'intégration quasi quotidiennes ; notes limitées à la liste des fichiers | Oui |
| S35 | <https://github.com/rnwood/smtp4dev/commits/master> | 2026-11-20 | 166 commits du 2025-11-20 au 2026-11-20 : 114 de Renovate, 40 de l'agent Copilot (type Bot), 12 humains de 8 auteurs dont 5 du mainteneur ; dernier commit le 2026-11-06 | Oui |
| S36 | <https://github.com/rnwood/smtp4dev/security> | 2026-11-20 | Aucun avis publié par le dépôt, aucun dans la base mondiale pour le paquet NuGet `Rnwood.Smtp4dev` ; signalement privé activé | Oui |
| S37 | <https://github.com/rnwood/smtp4dev/blob/master/Dockerfile.linux> | 2026-11-20 | Base `mcr.microsoft.com/dotnet/aspnet:10.0.14`, `curl` installé, aucune instruction `USER`, ports 80, 25, 143 et 110 | Oui |
| S38 | <https://github.com/rnwood/smtp4dev/blob/master/Rnwood.Smtp4dev/appsettings.json> | 2026-11-20 | `LockSettings` à `false` (réglages modifiables depuis l'interface), `Port` 25, `WebAuthenticationRequired` à `false`, liste `Users` (`Username`, `Password`), expressions JavaScript de validation | Oui |
| S39 | <https://github.com/rnwood/smtp4dev/blob/master/docs/Configuration.md> | 2026-11-20 | Réglages par variables d'environnement au format `ServerOptions__Users__0__…` | Oui |
| S40 | <https://github.com/rnwood/smtp4dev/blob/master/docs/Installation.md> | 2026-11-20 | Images Docker Linux et Windows, binaires, outil .NET ; aucune mention de Kubernetes ni de Helm | Oui |
| S41 | <https://github.com/rnwood/smtp4dev/blob/master/docs/Docker-Security.md> | 2026-11-20 | Mise en garde contre la publication des ports sur toutes les interfaces, exemples en 127.0.0.1 | Oui |
| S42 | <https://github.com/rnwood/smtp4dev/blob/master/docs/API.md> | 2026-11-20 | API documentée sous `/api`, routes `/api/messages`, `/api/sessions`, `/api/mailboxes`, `/api/server` | Oui |
| S43 | <https://github.com/rnwood/smtp4dev/blob/master/CLA.md> | 2026-11-20 | Accord de contribution : licence au projet pour « use, copy, modify, merge, publish, distribute, sublicense, and/or sell » les contributions | Oui |
| S44 | <https://hub.docker.com/r/rnwood/smtp4dev> | 2026-11-20 | 19 396 844 tirages, dépôt enregistré le 2018-09-20 ; tag 3.16.1 pour linux/amd64, linux/arm64 et Windows | Oui |
| S45 | <https://github.com/rnwood/smtp4dev/blob/master/azure-pipelines.yml> | 2026-11-20 | Image arm64 construite, tests de bout en bout désactivés pour elle « due to QEMU emulation issues » ; aucune signature trouvée | Oui |
| S46 | <https://opensource.org/license/mit> | 2026-11-20 | MIT porte le badge « Open Source Initiative Approved License » | Oui |
| S47 | <https://opensource.org/license/bsd-3-clause> | 2026-11-20 | BSD-3-Clause porte le badge « Open Source Initiative Approved License » | Oui |
| S48 | <https://github.com/mailhog/MailHog/releases> | 2026-11-20 | Dernière release v1.0.1 le 2020-08-11 | Oui |
| S49 | <https://github.com/sj26/mailcatcher/releases> | 2026-11-20 | Dernière release v0.10.0 le 2024-05-25 | Oui |
| S50 | <https://github.com/inbucket/inbucket> | 2026-11-20 | MIT, v3.2.0 le 2026-10-10, 2 314 étoiles | Oui |
| S51 | <https://github.com/tweedegolf/mailcrab> | 2026-11-20 | Apache-2.0, v1.9.0 le 2026-08-02, 1 004 étoiles | Oui |
| S52 | <https://github.com/greenmail-mail-test/greenmail> | 2026-11-20 | Apache-2.0, release 2.1.15 le 2026-10-25, 756 étoiles ; à embarquer dans un test unitaire ou à lancer en conteneur, clients web dans un projet séparé | Oui |
| S53 | <https://github.com/mailtrap/mailtrap-local> | 2026-11-20 | MIT, dépôt créé le 2026-05-05, v0.5.1 le 2026-11-16 | Oui |
| S54 | <https://github.com/apache/james-project/blob/master/server/mailet/mock-smtp-server/README.adoc> | 2026-11-20 | Interface HTTP pour régler le comportement et lister les mails reçus ; image construite par Jib, exemple `linagora/mock-smtp-server` ; tag `james-project-3.9.1` du 2026-09-25 | Oui |
| S55 | <https://github.com/orgs/maildev/people> | 2026-11-20 | Un seul membre public dans l'organisation maildev | Oui |
| S56 | <https://docs.cloud.google.com/compute/docs/tutorials/sending-mail> | 2026-11-20 | Port 25 bloqué vers l'extérieur, 465 et 587 permis ; fournisseurs recommandés SendGrid, Mailgun, Mailjet, ou relais SMTP de Google Workspace sur 465 ou 587 ; aucun service d'envoi managé par Google cité | Oui |
| S57 | <https://docs.cloud.google.com/firewall/docs/firewalls> | 2026-11-20 | Blocage de la sortie vers le port TCP 25 d'une adresse externe, levé pour les projets à faible risque ; SMTP en TLS sur 465 et 587 exclu ; adresses internes non touchées | Oui |
| S58 | <https://docs.cloud.google.com/identity-platform/docs/reference/rest/v2/Config> | 2026-11-20 | `SendEmail.method` : `DEFAULT`, « Sending email on behalf of developer », ou `CUSTOM_SMTP` ; champs du relais SMTP | Oui |
| S59 | <https://docs.cloud.google.com/appengine/migration-center/standard/python/mail-to-smtp> | 2026-11-20 | Migration du service Mail ancien d'App Engine vers un fournisseur SMTP tiers (SendGrid, Mailgun, Mailjet) | Oui |
| S60 | <https://busybox.net/downloads/BusyBox.html> | 2026-11-20 | Applet `sendmail` : `-S server[:port]`, `-f sender` obligatoire | Oui |
| S61 | <https://kubernetes.io/docs/concepts/security/pod-security-standards/> | 2026-11-20 | Profil « Restricted » : `allowPrivilegeEscalation` à `false`, `runAsNonRoot` à `true`, `runAsUser` non nul, seccomp `RuntimeDefault` ou `Localhost`, capacités `ALL` retirées | Oui |
| S62 | <https://github.com/axllent/mailpit/tree/develop/.github/workflows> | 2026-11-20 | Actions figées par SHA ; images construites pour linux/386, amd64 et arm64 ; aucune signature ni attestation trouvée | Oui |
| S63 | <https://github.com/maildev/maildev/tree/main/.github/workflows> | 2026-11-20 | Deux workflows (`ci.yml`, `draft-release.yml`) ; aucune signature ni attestation trouvée | Oui |

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
