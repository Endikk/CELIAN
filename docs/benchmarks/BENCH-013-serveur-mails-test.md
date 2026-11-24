# BENCH-013. Serveur de mails de test du profil standard

| Champ | Valeur |
| --- | --- |
| Identifiant | BENCH-013 |
| Sujet | Serveur de mails de test du profil standard sur le PC, et ce qui le remplace sur GCP |
| Statut | relu |
| Ouvert le | 2026-11-20 |
| Mis à jour le | 2026-11-24 |
| Auteur | [BENCH] |
| Relecteurs | [SECU] pour les licences et les CVE, [FINOPS] pour les coûts |
| Périmètre | Projet généré sur PC (cluster local), et projet généré sur GCP pour la parité |
| Choix du PRD | Aucune ligne du tableau des choix ouverts : composition du profil standard, décision de Lucas du 2026-11-20 (US-005) |
| ADR lié | ADR-014, à écrire par [ARCHI] |
| Verdict proposé | Mailpit v1.34.0, 81/100, devant maildev 3.0.0 (70) et smtp4dev 3.16.1 (64). Écart de 11 points, au moins quatre crans (section 7). Retenu le 2026-11-24 ; rien sur `gcp` ; dérogation datée à ENF-03 (section 7) |

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

[BENCH] Décisions du DSI du 2026-11-20, que Lucas peut renverser. Un :
l'interface web est requise, parce que le développeur lit dans son navigateur
les mails de confirmation et de réinitialisation qu'envoie le fournisseur
d'identité, et que Lucas a nommé Mailpit dans le profil standard. Deux :
Mailpit se mesure en v1.34.0, sous l'exception de sécurité du principe VI
(section 2). Trois : la parité sur GCP revient à [ARCHI] dans l'ADR-014. Quatre :
l'écart au principe V se justifie dans l'ADR-014 (section 7).

## 2. Options étudiées

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

[BENCH] Règle d'interface, décidée par le DSI le 2026-11-20 et que Lucas
peut renverser (section 1) : une option sans interface web de lecture des
mails n'est pas retenue. Elle écarte le serveur d'Apache James (liste
ci-dessous) avant les critères éliminatoires.

[BENCH] Versions. Mailpit v1.34.0 a trois jours à la date de lecture, et le
principe VI fait attendre 7 jours aux mises à jour : le blueprint pourrait la
figer à partir du 2026-11-24. Elle corrige toutefois l'avis
GHSA-v887-64wg-qqc9, moyen : un message SMTP forgé, envoyé sans
authentification, fait tomber tout le processus : SMTP, interface et API
(CVSS 3.1 de 6,5, vecteur réseau adjacent, versions 1.33.1 à 1.34.0
exclue). L'avis est publié le 2026-11-17 avec la version qui le corrige ; il
n'a pas de CVE et ne figure ni dans la base mondiale de GitHub ni dans OSV le
2026-11-24 [S4], [S21], [S66], [S67]. Le DSI a donc décidé le 2026-11-20 de
mesurer la v1.34.0 sous l'exception de sécurité du principe VI (constitution
1.2.0) ; dans le blueprint, la même exception vaut dès que sa PR passe la
matrice ; la matrice n'existant pas encore, le golden repo la fige après le
délai, écoulé le 2026-11-24 à 06:57 UTC. maildev 3.0.0 est une « Complete project re-build » [S23] ; la ligne précédente, 2.2.1 du
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
  par la règle d'interface du DSI : si Lucas la renverse, il redevient
  candidat, et le principe V pèse pour lui.

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
[BENCH] : le DSI a confié la question à [ARCHI] le 2026-11-20, et ce rapport
ne la tranche pas. Aucun service managé de Google ne joue le rôle d'un serveur de test :
lu comme le fait l'ADR-009, le principe III ne désigne aucun candidat
`managed` sur `gcp`. Or le schéma du catalogue exige une entrée `gcp` de type
`managed`, ou `oss` avec un `managed_gap` (`schema/catalog-entry.schema.json`,
`catalog/README.md`). Il n'a pas de type pour un fournisseur tiers comme
SendGrid, ni de moyen d'écrire « pas d'équivalent sur cette cible », et sa
liste `standards` ne contient pas SMTP : c'est un point pour [ARCHI], quelle
que soit la voie. Trois voies restent ouvertes, à [ARCHI] de choisir :

- rien sur `gcp` : l'application lit l'hôte SMTP dans sa configuration, et
  le README généré liste l'écart (ENF-02). Le schéma doit alors accepter
  l'absence d'équivalent ;
- le même serveur de test dans un environnement non productif sur GKE, en
  `oss` avec `managed_gap` : un outil qui garde des mails tournerait sur le
  cloud, ce que [SECU] doit relire ;
- un relais réel, fournisseur tiers ou Workspace, sur 465 ou 587 : hors champ
  de ce benchmark (section 1), et hors du schéma actuel.

## 3. Critères éliminatoires

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

[BENCH] Machine relevée le 2026-11-20 par `sysctl` et `sw_vers`, puis par le
script au lancement de la série du 2026-11-23 (`versions.tsv`) : rien n'a
changé.

| Élément | Valeur |
| --- | --- |
| Modèle | Apple Mac16,7 |
| Processeur | Apple M4 Pro, 14 cœurs (10 performance, 4 efficacité), arm64 |
| Mémoire | 24 Gio (25 769 803 776 octets) |
| Système | macOS 27.2.1 (build 26B131) |
| Moteur de conteneurs | Docker Engine 29.8.2 sous OrbStack (`docker info` : « OrbStack aarch64 », cgroup v2), moteur non libre, voir R-26. La version d'OrbStack n'est pas relevée par le script ; BENCH-009 avait relevé la 2.2.5 le 2026-11-19 |
| Ressources allouées | Machine virtuelle d'OrbStack : 14 CPU, 11,73 Gio (12 598 894 592 octets, `docker info`) |
| Versions mesurées | kind 0.33.0, image de nœud `kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed` (ADR-004) ; Mailpit v1.34.0, maildev 3.0.0, smtp4dev 3.16.1, busybox 1.37.0 pour le client SMTP, chacune figée par condensat d'index dans le script ; kubectl 1.37.1 |
| Charge parasite | Applications de bureau ouvertes. Charge moyenne sur une minute de 1,91 à 3,37 au début des douze exécutions (`load.tsv`). Aucun autre conteneur actif, verrou `bench-lock-s4` tenu. Poste sur batterie, de 76 % de charge relevés à 21:48 UTC à 52 % à 23:44 UTC (`pmset -g log`), et non sur secteur comme prévu ; aucune mise en veille entre 20:35 UTC et la fin de la série de base |

### 4.3 Protocole

[BENCH] Protocole écrit le 2026-11-20 pendant la phase de lecture, puis
précisé le 2026-11-21 avec le script, avant toute mesure et avant tout test
de fumée. Le script `tests/bench/bench-013-test-mail.sh` et ses manifests,
sous `tests/bench/bench-013/`, reproduisent les gestes de `task up` : aucun
outil de boucle (ADR-006), Secret créé par tube avant l'application des
manifests (ADR-007), images et manifests figés par condensat (conditions 3 et
4 de l'ADR-004). Le script s'ouvre sur l'inventaire des commandes qui créent,
modifient ou suppriment un conteneur ou un réseau (règle [SECU] du
2026-11-20) : `kind create cluster`, qui lance lui-même le nœud par
`docker run --privileged` (BENCH-011, S60), et `kind delete cluster`, rien
d'autre sur le moteur. Les autres commandes Docker ne font que lire :
`version`, `info`, `ps -q`, `stats --no-stream`, `network inspect`,
`manifest inspect`. Il n'emploie ni `docker run`, `start`, `restart`, `exec` ou
`cp`, ni `kubectl exec`, ni curl, wget, python, node ou perl.

1. Contrôles, une fois par série. Le script vérifie le SHA-256 de chacun des
   14 fichiers de `tests/bench/bench-013/` contre la valeur qu'il fige, et
   s'arrête si un fichier n'est pas figé ou si une image n'a pas de
   condensat. Aucun des trois projets ne publie de manifest Kubernetes ni de
   chart dans les pages lues [S9], [S29], [S40] : ces manifests sont écrits
   par [BENCH]. Les images sont désignées par leur condensat d'index, relevé
   le 2026-11-20 dans l'API de Docker Hub : `axllent/mailpit:v1.34.0`,
   `maildev/maildev:3.0.0`, `rnwood/smtp4dev:3.16.1`, et `busybox:1.37.0`,
   celle de BENCH-009, pour la sonde. Sous le verrou, avant la première
   exécution, `docker manifest inspect` vérifie dans le registre, sans
   télécharger de couche, que l'index figé et le tag pointent sur les mêmes
   manifests amd64 et arm64 que ceux relevés, puis relève les tailles
   compressées de ces deux manifests (M4). Le script lit chaque index en une
   requête et ne demande que ces deux manifests de plate-forme : Docker Hub
   compte un tirage par architecture demandée, dans une limite de 100 par
   tranche de 6 heures pour une adresse anonyme [S65]. La forme `-v`, qui
   les demande toutes, est la cause probable, non prouvée, de l'échec du
   premier test de fumée (section 4.4).
2. Profil « Restricted ». Le namespace `mail-test` porte les étiquettes
   `pod-security.kubernetes.io/enforce: restricted` et `warn: restricted`, à
   la version v1.36 du nœud [S61], [S64] : le serveur d'API refuse tout pod
   qui sort du profil. Chaque conteneur porte `allowPrivilegeEscalation:
   false`, `runAsNonRoot: true`, `runAsUser: 65534`, le profil seccomp
   `RuntimeDefault` et les capacités `ALL` retirées. Le même utilisateur
   numérique sert aux trois options : Mailpit et smtp4dev n'en déclarent pas
   [S7], [S37], et maildev déclare `node`, un nom que le kubelet ne peut pas
   confronter à `runAsNonRoot`. Configuration propre à chaque option, sur sa
   voie documentée : Mailpit reçoit `MP_DISABLE_VERSION_CHECK=true`, sans
   quoi il interroge GitHub [S11] (R-25) ; smtp4dev passe ses ports SMTP,
   HTTP, IMAP et POP3 au-dessus de 1024, verrouille ses réglages
   (`LockSettings`), écrit ses données dans un `emptyDir` et prend `HOME=/tmp`
   [S37], [S38]. Aucun port n'est publié vers l'hôte, aucun relais n'est
   configuré, aucune demande de ressources n'est posée.
3. État de départ de chaque exécution : aucun cluster `celian-bench-013`. Le
   script crée un cluster kind neuf avec l'image de nœud de l'ADR-004,
   kubeconfig dans le dossier d'essai, et attend qu'il soit prêt. Les images
   des options ne sont pas préchargées : le nœud les tire à chaque
   exécution, comme au premier `task up` d'un poste.
4. Secret (M8) : 32 caractères tirés de `/dev/urandom` par `tr` et `head`,
   mis en forme par `awk` et passés par un tube à `kubectl create -f -`
   (condition 1 de l'ADR-007). La valeur ne passe ni par une variable, ni par
   un fichier, ni par un argument, et n'entre jamais dans le dossier d'essai :
   le script n'en relève que la longueur et l'absence d'annotation
   `last-applied-configuration`. Chaque option la lit en variable
   d'environnement tirée du Secret : `MP_UI_AUTH` pour Mailpit [S12],
   `ServerOptions__WebAuthenticationRequired`,
   `ServerOptions__Users__0__Username` et
   `ServerOptions__Users__0__Password` pour smtp4dev [S38], [S39],
   `MAILDEV_WEB_USER` et `MAILDEV_WEB_PASS` pour maildev [S29].
5. Installation (M1) : `kubectl apply -k` du dossier vérifié de l'option.
   Fin de la mesure : le premier de trois contrôles consécutifs, espacés
   d'une seconde, où le Deployment est prêt et le pod Running et Ready. La
   sonde de disponibilité vise `/readyz` pour Mailpit [S15] et `/api/healthz`
   pour maildev [S30], deux routes servies hors de l'authentification, et le
   port HTTP en TCP pour smtp4dev, faute de route de santé dans les pages
   lues. Une option qui ne devient pas prête en 300 s est consignée avec la
   raison (événements, journal du pod), et ses exécutions suivantes sont
   sautées : c'est le relevé du démarrage sous le profil « Restricted » que
   demande le DSI.
6. Sonde (M5, M8), un Job busybox lancé dans le namespace, sous le même
   profil, avec l'identifiant en variables d'environnement tirées du Secret.
   Elle interroge d'abord l'API de l'option sans identifiant, puis avec, et
   relève les deux codes HTTP. Elle envoie ensuite un mail au sujet propre à
   l'exécution par `sendmail -S <service>:<port>` [S60], et relit l'API
   jusqu'à y trouver ce sujet : `/api/v1/messages` pour Mailpit [S14],
   `/api/email` pour maildev [S30], `/api/messages` pour smtp4dev [S42]. Les
   requêtes HTTP partent de `nc`, faute de curl et de wget. M5 se chronomètre
   dans le pod, sur `/proc/uptime`, de l'envoi à la lecture. La sonde n'écrit
   que des paires clé et valeur : jamais d'identifiant, jamais de corps de
   réponse.
7. Contrôle statique (M8) sur le pod vivant : aucune `command` ni `args`
   dans la spécification, donc la ligne de commande est le point d'entrée de
   l'image, sans valeur secrète ; le Secret n'arrive que par `secretKeyRef`.
   Ce contrôle remplace la lecture de `/proc/1/cmdline` prévue le
   2026-11-20, qui aurait demandé d'entrer dans le conteneur.
8. Repos (M2, M3) : 120 s après la sonde, trois échantillons espacés de 10 s
   de l'API Summary du kubelet (mémoire de travail et CPU du pod de l'option),
   et du conteneur du nœud par `docker stats` au même moment ; médiane des
   trois. La mémoire de la couche est celle du nœud moins celle du nœud de
   base (M7), en médianes (troisième règle de la GATE 1).
9. Architecture (M6) : le script relève l'architecture du nœud et les
   entrées de l'index de chaque image (étape 1). Un nœud arm64 qui démarre
   l'option alors que l'index publie une entrée arm64 la tire en natif ;
   containerd ne se rabat pas sur une autre architecture.
10. Fin : suppression du cluster, 15 s de pause. Trois exécutions par option,
    options alternées (Mailpit, maildev, smtp4dev, puis on recommence) pour
    répartir les variations du réseau et de la charge. Les événements
    `Pulled` du nœud donnent les images tirées (M4).
11. Nœud de base (M7), série de référence à part : l'option `none` suit les
    mêmes étapes, namespace, Secret et Job de sonde compris, sans serveur de
    mails ; la sonde s'arrête aussitôt. Trois exécutions.

[BENCH] Quand `BENCH_LOCK` est défini, le script ne lance aucune commande
docker, kind ou kubectl avant d'avoir pris le verrou de mesure partagé, qu'il
crée par `mkdir` et dont il ne retire que son propre fichier `owner`. Il ne
sort du poste que par `docker manifest inspect` et les tirages du nœud, vers
Docker Hub. Il refuse de
démarrer si le verrou est pris (code 75) ou si le cluster existe déjà. Il
passe shellcheck, tourne sous le bash 3.2 de macOS, en `umask 077`, avec
`KUBECONFIG` dans le dossier d'essai : `~/.kube` n'est ni lu ni écrit. L'heure
à la milliseconde vient de `zsh`, faute de perl et de python. Un test de
fumée (une exécution par option, repos de 30 s) précède la série ; il ne peut
rien changer aux seuils, figés et hachés depuis le 2026-11-20.

Pour refaire la mesure :

```bash
BENCH_LOCK=/chemin/vers/un/verrou tests/bench/bench-013-test-mail.sh /chemin/vers/un/dossier/vide
OPTIONS=none BENCH_LOCK=/chemin/vers/un/verrou tests/bench/bench-013-test-mail.sh /chemin/vers/un/autre/dossier   # nœud de base, M7
```

### 4.4 Résultats

[BENCH] Premier test de fumée, lancé le 2026-11-21 à 23:27 UTC sous le
verrou, après la série de BENCH-012. Le script n'a rien écrit pendant onze
heures, entre son lancement et la fin des contrôles de démarrage (10:23 UTC
le 2026-11-22) : veille du poste ou moteur indisponible, la cause n'est pas
établie. La vérification des images a ensuite confirmé les manifests amd64
et arm64 figés des trois options et relevé leurs tailles, puis échoué sur
l'index de busybox après 15 minutes sans réponse du registre. Aucun cluster
n'a été créé, aucune mesure prise. Corrections avant la reprise : requêtes
au registre réduites (section 4.3, étape 1), erreurs du registre gardées
dans `logs/registry.log`, et exécution sous `caffeinate -i`, qui empêche la
mise en veille du poste pendant la série.

[BENCH] Trois autres tests de fumée ont suivi, tous après l'écriture et le
hachage des seuils, sous le verrou et après la série de BENCH-012. Le
deuxième (2026-11-23, 21:31 à 21:42 UTC) a validé Mailpit et maildev de bout
en bout. smtp4dev n'est pas devenu prêt : il écoutait sur le port 80, parce
que la variable `SERVEROPTIONS__URLS` de son image l'emportait sur la
variable `ServerOptions__Urls` du manifest, écrite avec une autre casse. Le
troisième (21:52 à 21:55 UTC), manifest corrigé, a vu smtp4dev prêt et le
mail accepté en SMTP, mais l'API n'a rien répondu : nc fermait son côté de la
connexion juste après la requête, ce que Mailpit et maildev toléraient et
pas le serveur Kestrel de smtp4dev. La sonde garde depuis la connexion
ouverte (section 4.3, étape 6). Le quatrième (22:20 à 22:27 UTC) a passé
tous les contrôles pour les trois options.

[BENCH] Série retenue lancée le 2026-11-23 de 22:42 à 23:16 UTC, verrou
`bench-lock-s4` tenu, trois exécutions par option, options alternées
(dossier `series-1` du dossier de travail de [BENCH]) ; nœud de base de
23:31 à 23:41 UTC (dossier `base-1`). Aucun redémarrage de conteneur, aucun
autre conteneur actif au début des exécutions. Le SHA-256 de la section 4.1
vaut `2d22574e54d5f817d73e5efdb069b794d66c935bc29f59d8b2cc68538f540346`, le
même qu'au relevé du 2026-11-20 à 20:14:05 UTC ; il a été revérifié avant
chaque lancement. `pmset -g log` ne montre aucune mise en veille ni aucun
réveil entre 20:35 UTC et la fin de la série de base : aucune exécution
n'est écartée à ce titre. Le poste tournait sur batterie (section 4.2).

| Mesure | Option | Exécution 1 | Exécution 2 | Exécution 3 | Médiane | Écart |
| --- | --- | --- | --- | --- | --- | --- |
| M1, installation jusqu'à « prêt » | Mailpit | 3,4 s | 4,4 s | 3,4 s | 3,4 s | 1,0 s |
| M1 | maildev | 6,6 s | 5,5 s | 6,5 s | 6,5 s | 1,1 s |
| M1 | smtp4dev | 7,6 s | 8,6 s | 8,7 s | 8,6 s | 1,1 s |
| Nœud au repos | Mailpit | 604,7 Mio | 631,1 Mio | 592,8 Mio | 604,7 Mio | 38,3 Mio |
| Nœud au repos | maildev | 617,8 Mio | 653,8 Mio | 620,1 Mio | 620,1 Mio | 36,0 Mio |
| Nœud au repos | smtp4dev | 691,2 Mio | 702,2 Mio | 679,4 Mio | 691,2 Mio | 22,8 Mio |
| M7, nœud de base | kind seul, namespace, Secret, sonde | 540,9 Mio | 617,2 Mio | 629,6 Mio | 617,2 Mio | 88,7 Mio |
| M2, couche au nœud | Mailpit | | | | -12,5 Mio | |
| M2 | maildev | | | | 2,9 Mio | |
| M2 | smtp4dev | | | | 74,0 Mio | |
| Pod de l'option au repos (sensibilité) | Mailpit | 16,3 Mio | 14,3 Mio | 15,3 Mio | 15,3 Mio | 2,0 Mio |
| Pod de l'option | maildev | 59,2 Mio | 74,4 Mio | 58,5 Mio | 59,2 Mio | 15,9 Mio |
| Pod de l'option | smtp4dev | 118,7 Mio | 129,1 Mio | 118,9 Mio | 118,9 Mio | 10,4 Mio |
| M3, CPU du pod au repos | Mailpit | 0,17 % | 0,15 % | 0,30 % | 0,17 % | 0,15 % |
| M3 | maildev | 0,22 % | 0,25 % | 0,21 % | 0,22 % | 0,04 % |
| M3 | smtp4dev | 0,21 % | 0,27 % | 0,17 % | 0,21 % | 0,10 % |
| CPU du nœud au repos (sensibilité) | Mailpit | 13,7 % | 11,6 % | 13,5 % | 13,5 % | 2,1 % |
| CPU du nœud | maildev | 12,1 % | 12,4 % | 9,5 % | 12,1 % | 2,9 % |
| CPU du nœud | smtp4dev | 12,3 % | 14,6 % | 15,9 % | 14,6 % | 3,6 % |
| CPU du nœud | kind seul | 14,6 % | 12,5 % | 13,4 % | 13,4 % | 2,0 % |
| M5, envoi puis lecture par l'API, maintien de 5 s retiré | Mailpit | 0,03 s | 0,04 s | 0,03 s | 0,03 s | 0,01 s |
| M5 | maildev | 0,17 s | 0,15 s | 0,16 s | 0,16 s | 0,02 s |
| M5 | smtp4dev | 0,17 s | 0,16 s | 0,17 s | 0,17 s | 0,01 s |

[BENCH] Lecture de M2. La mémoire d'une couche se lit au nœud moins le nœud
de base, en médianes (troisième règle de la GATE 1) : -12,5 Mio pour
Mailpit (604,7 moins 617,2), 2,9 pour maildev et 74,0 pour smtp4dev. Le
nœud de base varie de 88,7 Mio d'une exécution à l'autre, plus que chacune
des trois couches. Pour Mailpit et maildev, dont les exécutions recouvrent
celles du nœud de base, la méthode ne distingue pas la couche du bruit, et
le chiffre négatif de Mailpit ne veut rien dire d'autre. Les trois
exécutions de smtp4dev (679,4 à 702,2 Mio) restent au-dessus de la plus
haute du nœud de base (629,6) : sa couche tient entre 49,8 et 161,3 Mio. Lue
au plus défavorable, nœud de l'option le plus haut moins nœud de base le
plus bas, la couche vaut au plus 90,2 Mio pour Mailpit, 112,9 pour maildev
et 161,3 pour smtp4dev : la note ne dépend pas du bruit (relecture
[FINOPS]). La dispersion vient de la première exécution du nœud de base
(540,9 Mio, cluster créé en 35,2 s) ; sans elle, l'écart tombe à 12,4 Mio.
La mémoire de travail du pod, lue par l'API Summary, donne l'ordre de
grandeur : 15,3 Mio pour Mailpit, 59,2 pour maildev, 118,9 pour smtp4dev.
Sous l'une ou l'autre lecture, aucune option n'approche le seuil de
512 Mio : smtp4dev en est à 25 % au plus haut de ses pods (129,1 Mio), et à
23 % en médiane (118,9).

[BENCH] Lecture de M5. La sonde garde la connexion ouverte 5 s pour que
smtp4dev réponde, et nc n'a rendu la main qu'à la fin de ce délai, même
quand le serveur avait déjà répondu : les valeurs brutes valent de 5,03 à
5,17 s. Le sujet a été trouvé dès la première lecture de l'API dans les neuf
exécutions ; le tableau retire donc les 5 s du maintien. Le deuxième test de
fumée, sans maintien, donnait 0,02 s pour Mailpit et 0,13 s pour maildev,
du même ordre. M5 sert de contrôle fonctionnel à l'expérience dev et
n'alimente aucun seuil.

[BENCH] Volume (M4) et images retéléchargées, en Mo compressés (10^6
octets), relevés dans le registre par les manifests de plate-forme
(`images.tsv`), et dans les événements `Pulled` du nœud (`node-images.tsv`).

| Option | amd64 | arm64 | À 10 Mbit/s, amd64 | Retéléchargée à chaque création | Tirage par le nœud (médiane) |
| --- | --- | --- | --- | --- | --- |
| Mailpit | 15,1 Mo | 14,5 Mo | 12,1 s | Oui, 3 exécutions sur 3 | 2,6 s |
| maildev | 74,9 Mo | 75,2 Mo | 59,9 s | Oui, 3 sur 3 | 4,8 s |
| smtp4dev | 176,9 Mo | 175,9 Mo | 141,5 s | Oui, 3 sur 3 | 5,9 s |

[BENCH] Le nœud tire aussi busybox, l'image de la sonde, à chaque exécution,
nœud de base compris : elle appartient au banc de mesure, pas à la couche,
et n'entre pas dans ces volumes.

[BENCH] Contrôles fonctionnels, identiques dans les neuf exécutions des
options (`functional.tsv`) :

| Contrôle | Mailpit | maildev | smtp4dev |
| --- | --- | --- | --- |
| M6, nœud arm64, entrée arm64 de l'index tirée, pod prêt | Oui | Oui | Oui |
| Démarrage sous le profil « Restricted » imposé au namespace, `runAsUser: 65534` | Oui, sans autre changement | Oui, avec un utilisateur numérique à la place de `node` | Oui, après déplacement des ports et surcharge de `SERVEROPTIONS__URLS` |
| M8, API sans identifiant | 401 | 401 | 401 |
| M8, API avec l'identifiant du Secret | 200 | 200 | 200 |
| M8, `command` et `args` absents de la spécification du pod | Oui | Oui | Oui |
| M8, identifiant reçu par `secretKeyRef` | `MP_UI_AUTH` | `MAILDEV_WEB_USER`, `MAILDEV_WEB_PASS` | `ServerOptions__Users__0__Username`, `ServerOptions__Users__0__Password` |
| Secret de 32 caractères, sans annotation `last-applied-configuration` | Oui | Oui | Oui |
| Mail envoyé en SMTP, relu par l'API | Oui | Oui | Oui |

[BENCH] Aucune valeur secrète n'est écrite dans les dossiers d'essai : les
journaux ne gardent que « secret/mail-ui-auth created », et une recherche
des clés du Secret (`password:`, `mp-ui-auth:`, `stringData`) dans les
dossiers des tests de fumée 2 à 4, de la série et du nœud de base ne trouve
rien.

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

[BENCH] Notes écrites le 2026-11-20 pendant la phase de lecture, puis
revues le 2026-11-24 après la série du 2026-11-23. L'essai a confirmé les
notes de sécurité et de portabilité sans les changer, a fondé celle de
l'expérience dev, et a donné l'empreinte (5.6). Les métadonnées GitHub sont
relevées par `gh api` le 2026-11-20 ; les commits humains excluent les
fusions et les auteurs de type Bot (Renovate, Dependabot, agent Copilot).

### 5.1 Licence et liberté d'usage, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Mailpit | 5/5 | 15 | MIT, approuvée OSI, dans le fichier `LICENSE` depuis le premier commit du 2022-07-29, sans accord de contribution. Le projet généré tire l'image et n'en redistribue rien | [S1], [S46] |
| maildev | 5/5 | 15 | MIT, approuvée OSI, depuis la première release de 2013 ; le texte a été corrigé le 2026-01-09 sans changer de licence | [S22], [S46] |
| smtp4dev | 4/5 | 12 | BSD-3-Clause, approuvée OSI. Réserve : l'accord de contribution donne au projet le droit de « sublicense, and/or sell » les contributions, ce qui permettrait de publier les versions futures sous d'autres termes ; les versions publiées restent sous BSD-3-Clause | [S33], [S43], [S47] |

### 5.2 Gouvernance (fondation, multi-vendeurs), poids 15

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

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Mailpit | 4/5 | 12 | Dépôt créé le 2022-07-29, version 1.0.0 le 2022-09-03, 248 160 030 tirages de l'image sur Docker Hub. Adoption attestée par la documentation des adoptants eux-mêmes : Mailpit est le service de mails du fichier Compose par défaut de Laravel Sail, et le capteur de mails de DDEV. Réserve : aucune fondation ni liste d'adoptants tenue par le projet ; adoption lue chez Laravel et DDEV | [S1], [S16], [S17], [S18] |
| maildev | 3/5 | 9 | Projet de 2013, 60 228 176 tirages de l'image. Réserve qui demande une action : la version examinée, 3.0.0, est une reconstruction complète publiée le 2026-09-23, soit 58 jours de recul, après 19 mois sans release (section 3). Le README conseille lui-même de revenir à la v2 « if you run into any issues ». Ce code n'a pas l'ancienneté du projet (principe VI) | [S22], [S23], [S29], [S31] |
| smtp4dev | 4/5 | 12 | Dépôt créé le 2012-01-13, version majeure 3, 19 396 844 tirages de l'image, binaires et outil .NET publiés à chaque release. Réserve : aucune liste d'adoptants ni adoption tierce trouvée dans les pages lues | [S33], [S34], [S44] |

[BENCH] Les tirages de Docker Hub comptent aussi les exécutions de CI, et ne
mesurent pas le nombre d'équipes : ils servent d'ordre de grandeur, jamais de
preuve seule. Relecture [SECU] : 4/5, comme k3d (BENCH-003), Traefik
(BENCH-004) et Config Sync (BENCH-009), sans liste tenue par le projet ;
Keycloak, Incubating à la CNCF avec 59 adoptants, a 4/5 dans BENCH-012.
Compter Laravel et DDEV en preuve directe donnerait 5/5.

### 5.4 Activité et maintenance, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Mailpit | 5/5 | 10 | 32 releases stables en 12 mois, de v1.28.0 (2025-11-26) à v1.34.0 (2026-11-17), à peu près une tous les 11 jours. 471 commits humains, dernier commit le 2026-11-19 | [S2], [S3] |
| maildev | 3/5 | 6 | Une seule release stable en 12 mois, 3.0.0, après deux préversions ; 21 mois entre 2.2.1 et 3.0.0. 97 commits humains de 7 auteurs, aucun depuis le 2026-09-24. Réserve qui demande une action : vérifier que le rythme repris en 2026 se maintient | [S23], [S24] |
| smtp4dev | 3/5 | 6 | 6 releases stables en 12 mois, mais aucune entre 3.15.0 (2026-03-03) et 3.16.0 (2026-11-06). 12 commits humains seulement, le reste vient de Renovate et de l'agent Copilot ; les notes de release listent les fichiers publiés, pas les changements. Réserve qui demande une action : lire les commits pour savoir ce qu'apporte une version | [S34], [S35] |

### 5.5 Sécurité (CVE, réactivité), poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Mailpit | 3/5 | 6 | 18 avis publiés par le dépôt du 2026-01-06 au 2026-11-17, aucun critique, 1 élevé selon le dépôt ; 15 sont dans la base mondiale, qui en classe 3 en élevé. Les trois plus récents, sans CVE, dont le seul élevé du dépôt (GHSA-379p-g4f4-hq5h) et celui que corrige la v1.34.0, n'y sont pas : Trivy, qui lit cette base pour les modules Go, ne les voit pas. Chacun sort avec sa version corrigée : SSRF des fonctions de vérification de liens et de HTML, dénis de service par SMTP ou par l'API, détournement de WebSocket. Signalement privé ouvert, accusé de réception visé sous 24 h. La réserve demande une action : 13 versions correctives à suivre en dix mois et demi, image sans signature ni attestation, bâtie sur `alpine:latest` sans condensat, sans utilisateur déclaré, donc en root sans `securityContext`, appel à GitHub par défaut à couper | [S4], [S5], [S6], [S7], [S11], [S15], [S66], [S67], [S68], [S69] |
| maildev | 2/5 | 4 | Aucun avis en 12 mois. Le seul avis connu, CVE-2024-27448 (critique, exécution de code à distance par un en-tête Content-ID, versions 2.0.0-beta1 à 2.1.0), a été signalé publiquement le 2023-08-25 et corrigé en 2.2.1 le 2024-12-12, quinze mois et demi plus tard. Politique de sécurité écrite, signalement privé ouvert, image en utilisateur `node`. Dans le code de la 3.0.0, socket.io, attaché au serveur HTTP, échappe au crochet d'authentification et diffuse à tout client le résumé de chaque mail (sujet, adresses, 140 premiers caractères) ; le CORS de l'API renvoie toute origine avec `credentials` (lecture du code, non essayé). La version 3.0.0, reconstruite, n'a pas encore d'historique | [S25], [S26], [S27], [S28], [S32], [S70] |
| smtp4dev | 2/5 | 4 | Aucun avis, ni au dépôt ni dans la base mondiale ; aucune politique de sécurité, seul le signalement privé de GitHub est ouvert, et les notes de release ne disent pas ce qu'une version corrige. Image en root, ports 80 et 25 privilégiés par défaut, `curl` installé. `AuthenticationRequired` à `false` : IMAP n'exige aucun identifiant, et IMAP et POP3 restent à l'écoute dans la configuration mesurée (lecture des réglages, non essayé). `LockSettings` vaut `false` par défaut : les réglages se modifient depuis l'interface web, et le même fichier porte des expressions JavaScript de validation. Il faut contourner : surveiller les images par scan faute d'avis | [S34], [S36], [S37], [S38], [S71] |

[BENCH] Aucune des trois n'a de signature d'image ni d'attestation de
provenance dans ses workflows publics (GitHub Actions pour Mailpit et
maildev, Azure Pipelines pour smtp4dev) ; Mailpit fige ses actions par SHA
[S45], [S62], [S63]. Le critère ne départage donc pas sur ce point, et
aucune note n'en tient compte. Relecture [SECU] pour Mailpit : ni cosign ni
`actions/attest` dans le flux de la v1.34.0, aucune attestation à l'API de
GitHub, aucun tag `sha256-*` sur Docker Hub [S68], [S69]. Les trois images
sont sur docker.io hors de `library/` : l'ADR-014 porte sa propre dérogation
à ENF-03.

[BENCH] Sensibilité. Compter le nombre d'avis contre Mailpit, au lieu de la
réactivité qu'ils montrent, le ferait tomber à 2/5 ; à l'inverse, lire la
politique de sécurité de maildev 3.x comme une rupture avec la réaction
lente de 2024 le ferait monter à 3/5. [SECU] garde les deux notes : la
réactivité compte plus que le nombre d'avis, comme pour Keycloak dans
BENCH-012, et le code de maildev 3.0.0 laisse socket.io hors de
l'authentification, ce qui ne montre aucune rupture.

[BENCH] Essai (M8, section 4.4). Les trois options refusent l'API sans
identifiant (401), l'acceptent avec celui du Secret (200), le reçoivent par
`secretKeyRef` sans argument de commande, et démarrent sous le profil
« Restricted » imposé au namespace, en utilisateur 65534. M8 ne mesure que
l'API REST : maildev diffuse les nouveaux mails par socket.io hors de
l'authentification, et smtp4dev laisse IMAP et POP3 sans identifiant
(relecture [SECU], lecture du code et des réglages, non essayé). Les notes
restent celles de la lecture.
Mailpit et smtp4dev, sans utilisateur déclaré dans leur image, tourneraient
en root dans un manifest qui n'impose rien : le blueprint impose le profil.

### 5.6 Empreinte sur PC (RAM, CPU, démarrage), poids 10

[BENCH] Règle de `TEMPLATE.md` (section 5.6), seuils écrits et hachés en
4.1 avant toute mesure : chaque option part de 5 et perd un cran par seuil
dépassé. Volume lu sur l'amd64, mémoire au nœud moins le nœud de base.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Mailpit | 4/5 | 8 | Un seuil dépassé : image retéléchargée à chaque création (seuil 2). 15,1 Mo en amd64, prête en 3,4 s, couche au nœud dans le bruit de la mesure (pod de 15,3 Mio), sous leurs seuils | [M1], [M2], [M4], [M7] |
| maildev | 4/5 | 8 | Un seuil dépassé : image retéléchargée à chaque création (seuil 2). 74,9 Mo en amd64, prête en 6,5 s, couche au nœud dans le bruit de la mesure, 2,9 Mio (pod de 59,2 Mio), sous leurs seuils | [M1], [M2], [M4], [M7] |
| smtp4dev | 3/5 | 6 | Deux seuils dépassés : 176,9 Mo en amd64 (seuil 1, 112,5 Mo), retéléchargés à chaque création (seuil 2). Prête en 8,6 s et 74,0 Mio de couche au nœud (pod de 118,9 Mio), sous leurs seuils | [M1], [M2], [M4], [M7] |

[BENCH] Aucune option n'est à moins de 10 % d'un seuil : maildev pèse 66,6 %
du seuil de volume, smtp4dev le dépasse de 57,2 %. Les écarts que la note
ne voit pas restent réels : Mailpit tire cinq fois moins que maildev et
douze fois moins que smtp4dev, et son pod pèse le quart de celui de maildev
et le huitième de celui de smtp4dev.

[BENCH] Sensibilité. Avec le miroir de l'ADR-011, accepté depuis l'écriture
des seuils, le nœud retire l'image du miroir local à chaque création, et
plus d'Internet. Si le DSI lit le seuil 2 comme un retéléchargement depuis
Internet, les trois options regagnent un cran (Mailpit et maildev 5/5,
smtp4dev 4/5) : le classement ne change pas. La somme des pods à la place du
nœud ne fait franchir le seuil 4 à aucune option. Cumul avec le reste du
profil standard, en sensibilité (deuxième règle de la GATE 1, relecture
[FINOPS]). Le premier `task up` télécharge 1 787,0 Mo en amd64 avant ce
benchmark, miroir zot de l'ADR-011, Postgres de l'ADR-012 et Keycloak de
l'ADR-013 compris (R-04). Avec Mailpit : 1 802,1 Mo, soit 1 441,7 s à
10 Mbit/s, 160,2 % du budget de 900 s, et 16,0 Mbit/s au minimum. Avec
maildev, 1 861,9 Mo (165,5 %) ; avec smtp4dev, 1 963,9 Mo (174,6 %). En
mémoire, Mailpit laisse le profil standard à 3,5 Gio de VM et 7,5 Gio de
portable ; smtp4dev le ferait passer à 4,0 Gio de VM, maildev non.

### 5.7 Portabilité multi-cloud, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Mailpit | 5/5 | 10 | Image publiée pour linux/amd64, linux/arm64 et linux/386, binaire statique pour Linux, macOS et Windows : tourne sur tout cluster conforme, kind comme GKE ou un autre cloud. Démarrée en natif sur un nœud arm64 dans les trois exécutions | [M6], [S9], [S16] |
| maildev | 5/5 | 10 | Image publiée pour linux/amd64 et linux/arm64, paquet npm : tourne sur tout cluster conforme. Démarrée en natif sur un nœud arm64 dans les trois exécutions | [M6], [S29], [S31] |
| smtp4dev | 4/5 | 8 | Images linux/amd64, linux/arm64 et Windows, binaires et outil .NET. Réserve : la chaîne du projet construit l'image arm64 mais y a désactivé les tests de bout en bout, faute d'émulation fiable. L'image arm64 a démarré dans les trois exécutions (M6) ; la réserve porte sur les versions suivantes, que le projet ne teste pas sur cette architecture | [M6], [S40], [S44], [S45] |

[BENCH] La parité sur GCP ne départage pas : aucune des trois n'a de
service managé en face chez Google, et aucune n'est plus ou moins déployable
sur GKE que les autres. Le principe III et le schéma du catalogue relèvent de
l'ADR-014 (section 2, « Parité sur GCP »), pas de cette note.

### 5.8 Expérience dev et documentation, poids 10

[BENCH] Note de jugement. L'essai qui la fonde : installation par les
manifests du script sous le profil « Restricted », envoi et lecture d'un
mail (M5), contrôles d'accès (M8), trois fois par option dans la série,
après quatre tests de fumée (section 4.4). Ce qui a demandé une
intervention de [BENCH] est écrit ci-dessous.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Mailpit | 5/5 | 10 | Passé du premier coup au deuxième test de fumée, puis dans les trois exécutions, avec un seul ajout aux valeurs documentées : l'utilisateur numérique du profil « Restricted ». Site de documentation dédié, installation par Docker décrite. Chaque option a sa variable d'environnement, identifiants compris (`MP_UI_AUTH`, refusé en argument « for security reasons », ou un fichier de mots de passe hachés en bcrypt) ; `/readyz` servi hors de l'authentification a fait la sonde de disponibilité sans réglage ; API décrite en Swagger. Les ruptures de la v1.34.0 sont annoncées dans ses notes de release | [M1], [M5], [M8], [S10], [S11], [S12], [S13], [S14], [S15], [S21] |
| maildev | 4/5 | 8 | Passé du premier coup au deuxième test de fumée, puis dans les trois exécutions, avec le même ajout que Mailpit, rendu nécessaire par l'utilisateur nommé `node` de l'image. Variables documentées dans le README, `/api/healthz` hors de l'authentification, API REST documentée. Réserve : la 3.0.0 corrige encore la sonde de santé de son image et la prise en compte de `MAILDEV_HTTPS`, signes d'une réécriture jeune | [M1], [M5], [M8], [S23], [S29], [S30] |
| smtp4dev | 3/5 | 6 | Deux tests de fumée ratés avant le premier passage. La variable `SERVEROPTIONS__URLS` de l'image l'emporte sur la même variable écrite avec une autre casse, celle que suggère la documentation (`ServerOptions__…`), sans erreur affichée : le serveur écoute ailleurs que demandé. Son serveur web ne répond pas à une requête dont le client a fermé son côté de la connexion. La documentation consacre une page à la publication des ports en boucle locale, sous Docker seulement dans les pages lues. Les valeurs par défaut (ports 80 et 25, root, `LockSettings` à `false`) sont à surcharger, aucune route de santé n'a été trouvée, et les notes de release ne décrivent pas les changements. La réserve demande une action | [M1], [M5], [M8], [S34], [S37], [S38], [S39], [S41], [S42] |

### 5.9 Coût (managé ou opérationnel), poids 5

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Mailpit | 4/5 | 4 | Gratuit sous MIT, sans licence ni support payant requis ; mémoire et volume comptés en 5.6. Sur GCP, le coût dépend de la voie de l'ADR-014 : 0 USD si rien ne tourne sur `gcp` ; sur GKE Autopilot, de 1,8 USD par mois (50m et 52 MiB, avec la rafale) à 23,4 USD (demandes par défaut), aux prix d'exemple de us-central1, hors stockage éphémère ; relais réel non chiffré, facture hors de GCP. Réserve : coût sur GCP à trancher | [S1], [S20], [S73], [S74], [S75] |
| maildev | 4/5 | 4 | Gratuit sous MIT, même règle. Même réserve, mêmes minimums d'Autopilot | [S22], [S73], [S74] |
| smtp4dev | 4/5 | 4 | Gratuit sous BSD-3-Clause, dons facultatifs, même règle. Même réserve | [S33], [S73], [S74] |

[BENCH] Le coût ne départage pas. Sur le PC, il se réduit à la mémoire et au
volume, notés en 5.6. Sur GCP, il dépend de la voie de l'ADR-014
(section 2) : si rien ne tourne sur `gcp`, 0 USD ; pour un serveur de test
sur GKE Autopilot, environ 1,8 USD par mois avec la rafale au minimum de
demande, 9,9 USD sans rafale et 23,4 USD sans demande, aux prix d'exemple de
us-central1 et non à la grille, illisible le 2026-11-24 ; pour un relais
réel, prix non lus, facture hors de Cloud Billing, et une sortie vers
Internet depuis des nœuds privés qui demande Cloud NAT. La région n'est pas
choisie (R-05) (relecture [FINOPS]).

## 6. Grille pondérée

| Critère | Poids | Mailpit | maildev | smtp4dev |
| --- | --- | --- | --- | --- |
| Critères éliminatoires (section 3) | éliminatoire | passe | passe | passe |
| Licence et liberté d'usage | 15 | 5/5, 15 pts | 5/5, 15 pts | 4/5, 12 pts |
| Gouvernance (fondation, multi-vendeurs) | 15 | 2/5, 6 pts | 2/5, 6 pts | 2/5, 6 pts |
| Maturité et adoption | 15 | 4/5, 12 pts | 3/5, 9 pts | 4/5, 12 pts |
| Activité et maintenance | 10 | 5/5, 10 pts | 3/5, 6 pts | 3/5, 6 pts |
| Sécurité (CVE, réactivité) | 10 | 3/5, 6 pts | 2/5, 4 pts | 2/5, 4 pts |
| Empreinte sur PC (RAM, CPU, démarrage) | 10 | 4/5, 8 pts | 4/5, 8 pts | 3/5, 6 pts |
| Portabilité multi-cloud | 10 | 5/5, 10 pts | 5/5, 10 pts | 4/5, 8 pts |
| Expérience dev et documentation | 10 | 5/5, 10 pts | 4/5, 8 pts | 3/5, 6 pts |
| Coût (managé ou opérationnel) | 5 | 4/5, 4 pts | 4/5, 4 pts | 4/5, 4 pts |
| Total | 100 | 81 / 100 | 70 / 100 | 64 / 100 |

## 7. Verdict proposé

[BENCH] Option proposée : Mailpit v1.34.0, 81/100, 11 points devant
maildev 3.0.0 (70) et 17 devant smtp4dev 3.16.1 (64), dans la grille
réconciliée par le DSI le 2026-11-24 après les relectures de [SECU] et de
[FINOPS]. L'ADR-014, écrit par [ARCHI], tranche, et Lucas valide.

[BENCH] Pourquoi. Quatre critères font les 11 points d'écart avec maildev. La maturité
(12 contre 9) : Mailpit est en version 1 depuis le 2022-09-03 et sert de
capteur de mails par défaut à Laravel Sail et à DDEV [S2], [S17], [S18],
quand maildev 3.0.0 est une réécriture de 58 jours dont le README conseille
de revenir à la v2 en cas de problème [S23], [S29]. L'activité (10 contre
6) : 32 releases stables en 12 mois contre une [S2], [S23]. La réactivité de
sécurité (6 contre 4) : 18 avis publiés chacun avec sa version corrigée,
contre quinze mois et demi pour corriger la seule faille critique connue de
maildev [S4], [S26], [S27]. L'expérience dev ajoute 2 points, l'essai étant
passé sans autre réglage que l'utilisateur numérique [M5], [M8]. En
empreinte, les deux options ont la même note, mais l'image de Mailpit fait 15,1 Mo
contre 74,9 et son pod pèse 15,3 Mio contre 59,2 [M2], [M4]. smtp4dev perd
en plus un cran de volume (176,9 Mo, au-delà de 112,5) et un de licence.

[BENCH] Sensibilité, recalculée sur la grille réconciliée (81, 70, 64).
L'écart de 11 points ne tient pas dans un cran : un cran vaut 3 points au
plus, sur un critère de poids 15, et il en faudrait au moins quatre contre
Mailpit pour que maildev passe devant. Aucune des lectures discutées plus
haut n'y suffit. Avec l'adoption lue chez Laravel et DDEV comptée en preuve
directe, Mailpit monterait à 84 (maturité 5/5). En comptant ses avis au lieu
de sa réactivité, il tomberait à 79 (sécurité 2/5) : ce 79 cumule les deux
lectures défavorables, maturité à 4/5 et sécurité à 2/5. maildev monterait à
72 si sa politique 3.x se lisait comme une rupture, lecture que [SECU]
écarte. Le cas le plus défavorable, 79 contre 72, garde Mailpit devant. Avec
le miroir de l'ADR-011, les trois options regagnent le même cran d'empreinte
(section 5.6), soit 83, 72 et 66 : le classement ne change pas. Le coût à
5/5 de la lecture d'origine rendrait un point à chacune, sans toucher aux
écarts. Aucune option n'est à moins de 10 % d'un seuil.

[BENCH] Gouvernance. Mailpit dépend d'une personne : 93,6 % des commits
humains de l'année, dépôt d'un compte personnel, soutien affiché de
Mailtrap sans termes publiés [S3], [S19], [S20]. Les deux autres options sont
dans le même cas (section 5.2), et le seul candidat porté par une fondation,
mock-smtp-server d'Apache James, n'a pas d'interface de lecture, que le DSI
a rendue obligatoire (section 2). Décision du DSI du 2026-11-20 : l'écart au
principe V se justifie dans l'ADR-014. Éléments que [BENCH] propose pour
cette justification : l'outil ne sert que sur le PC, hors du chemin de
production ; l'application ne lui parle qu'en SMTP, un standard, si bien
que changer de serveur de test ne touche que la couche `local` ; la relecture
du catalogue tous les six mois (ADR-009) verrait un abandon avant qu'il ne
dure.

[BENCH] Parité sur GCP : rien n'est tranché ici. Les trois voies et le point
du schéma du catalogue sont en section 2 (« Parité sur GCP »), pour
[ARCHI] dans l'ADR-014.

[BENCH] Réserves, pour l'ADR-014 et le blueprint :

1. Version. v1.34.0 entre sous l'exception de sécurité du principe VI, au
   titre de GHSA-v887-64wg-qqc9 (section 2). Le délai de 7 jours prend fin
   de toute façon le 2026-11-24 à 06:57 UTC, avant toute PR du golden repo.
2. Rythme des correctifs. 13 versions correctives en dix mois et demi
   [S4] : l'exception de sécurité servira souvent, et chaque PR de Renovate
   doit passer la matrice.
3. Profil « Restricted » imposé par le manifest. L'image ne déclare pas
   d'utilisateur [S7] : sans `runAsNonRoot` et un `runAsUser` numérique, elle
   tourne en root. La configuration mesurée en donne un modèle
   (`tests/bench/bench-013/mailpit/`).
4. Aucun appel sortant. `MP_DISABLE_VERSION_CHECK=true`, sans quoi Mailpit
   interroge GitHub (R-25), et `MP_ALLOW_INTERNAL_HTTP_REQUESTS` laissé à
   `false`, sa valeur par défaut, contre les SSRF des fonctions de
   vérification de liens et de capture [S11], [S4].
5. Accès. Interface et API derrière un identifiant tiré par `task up` dans
   un Secret (ADR-007), lu par `MP_UI_AUTH`, et joignables en boucle locale
   seulement, par la gateway ou par `kubectl port-forward --address
   127.0.0.1` (R-20, ADR-005, ADR-006), ce que la mesure n'a pas couvert :
   aucun port n'y était publié.
6. Gouvernance. Surveiller le soutien de Mailtrap, qui publie depuis le
   2026-05-05 son propre outil local [S53].
7. Signature : dérogation à ENF-03 pour `docker.io/axllent/mailpit` dans
   l'ADR-014.
8. Aucun envoi hors du poste : aucune variable de relais, de transfert ni de
   webhook dans la couche, et une NetworkPolicy qui ferme la sortie du pod,
   que kind applique depuis la v0.24.0 [S72].
9. Angle mort des scanners : trois des 18 avis manquent à la base que lit
   Trivy (R-36) [S67].
10. Ressources, de [FINOPS]. Demande et limite mémoire de Mailpit explicites
    dans la couche `local`, et sur GKE si l'ADR-014 l'y place (condition 9
    de l'ADR-008) : la mesure n'en posait aucune. Avec Mailpit, la limite du
    conteneur de Keycloak doit rester sous 1 240 Mi environ pour que le
    profil standard tienne sur 8 Gio à cette limite (condition 11 de
    l'ADR-013).

[BENCH] Prochaine vérification proposée : 2027-05-24, six mois après la
mesure, comme le veut la règle de date de l'ADR-009.

[BENCH] Suites :

- l'ADR-014, par [ARCHI], qui tranche l'option, la parité sur GCP et l'écart
  au principe V ;
- l'entrée de catalogue de la brique (nom à fixer avec le schéma) : cible
  `local` en `oss`, Mailpit v1.34.0, MIT, statut `active`, sources de la
  section 9. Deux champs ne rentrent pas tels quels dans le schéma actuel :
  la cible `gcp` (section 2) et `governance.model`, qui n'a pas de valeur
  pour un projet tenu par une personne (`foundation`, `community`,
  `single-vendor`) ;
- deux risques proposés à `docs/risques.md`, numéros à attribuer par le
  DSI : serveur de mails de test tenu par une seule personne, soutenue par
  un éditeur qui publie un outil concurrent ; avis de sécurité fréquents du
  serveur de mails de test (18 en dix mois et demi) ;
- le volume de R-04 : 15,1 Mo de plus au premier `task up` du profil
  standard, soit 1 802,1 Mo avec Keycloak, 160,2 % du budget de 900 s à
  10 Mbit/s et 16,0 Mbit/s au minimum (section 5.6) ; dans le tableau des
  registres de l'ADR-011, la ligne « à relever » devient docker.io pour
  Mailpit, registre déjà dans la liste unique.

[BENCH] Questions ouvertes pour [ARCHI] et Lucas : confirmer ou renverser
les deux décisions du DSI qui ont pesé sur la liste (interface requise,
mesure de la v1.34.0) ; choisir la voie de parité sur GCP et l'évolution du
schéma qu'elle demande ; dire si, depuis l'acceptation de l'ADR-011, le
seuil 2 se lit comme un retéléchargement depuis Internet, pour ce rapport
et les suivants.

[DSI] Arbitrage du 2026-11-24, après les relectures de [SECU] et de
[FINOPS]. Mailpit v1.34.0 est retenu comme serveur de mails de test du
profil standard sur la cible `local`, à 81 sur 100 dans la grille
réconciliée, devant maildev (70) et smtp4dev (64). La maturité de Mailpit
passe à 4, faute de fondation et de liste d'adoptants tenue par le projet,
et le coût passe à 4/5 pour les trois options, par cohérence avec BENCH-012.
La lecture du code par [SECU] sépare les contrôles d'accès que M8 faisait
paraître égaux : maildev diffuse les nouveaux mails par socket.io hors de
l'authentification, smtp4dev laisse IMAP sans identifiant, Mailpit protège
l'interface, l'API et le WebSocket. Le seuil 2 garde sa lettre, comme dans
BENCH-011 : la mesure sans miroir compte comme un retéléchargement depuis
Internet ; la lecture avec le miroir reste en sensibilité. Lucas a tranché
le même jour deux points. Sur la cible `gcp`, rien ne tourne : l'exemple
n'envoie pas de mail dans le MVP, les mails des parcours de connexion
partent d'Identity Platform (ADR-013), l'hôte SMTP reste un réglage, et
l'écart est listé au README. Mailpit reçoit sa propre dérogation datée à
ENF-03, sur le modèle de l'ADR-013 : `docker.io/axllent/mailpit` est admise
par sa référence exacte, condensat compris, dans une liste fermée que [SECU]
relit à chaque montée ; elle tombe quand Mailpit signe ses images de façon
vérifiable par Kyverno. L'ADR-014, à écrire par [ARCHI], reprend les
conditions 1 à 8 de [SECU] et les trois conditions de [FINOPS] : R-04 et
ENF-01 à 1 802,1 Mo ; demandes et limites de Mailpit explicites ; limite de
Keycloak sous 1 240 Mi environ, mesurée sur le golden repo, pic de démarrage
compris. Il justifie l'écart au principe V : les trois options reposent
chacune sur une seule personne. Les avis de dépôt absents de la base
mondiale (trois des 18 avis de Mailpit) étendent le risque R-36.

## 8. Limites et biais

[BENCH] Limites connues à la fin de la phase de lecture, le 2026-11-20, puis
celles de la série du 2026-11-23 (sept lignes suivantes), puis celles des
relectures du 2026-11-24 (cinq dernières lignes).

| Limite | Effet possible sur le verdict | Ce qui la lèverait |
| --- | --- | --- |
| Une seule machine de mesure, différente du PC de référence de la phase 6 (pas encore défini, ENF-02) | Empreinte propre à ce matériel, sous un moteur non libre (R-26) | Relancer le script sur une deuxième machine, dont un poste linux amd64 |
| Option pressentie par le PRD et par le brief | Mailpit part avec l'attention du brief | Même règle de sélection écrite avant les notes, mêmes sources, même script pour les trois |
| Sélection des options par le nombre d'étoiles GitHub | Inbucket ou MailCrab pourraient valoir mieux qu'une des options retenues | Les ajouter à la série de mesure si le DSI le demande |
| Interface web requise, par décision du DSI du 2026-11-20 (section 1) | Écarte le seul candidat porté par une fondation | Lucas confirme ou renverse la décision |
| Notes de sécurité et d'expérience dev posées avant l'essai | Un cran par option, dans un sens ou dans l'autre | Essai, puis relecture [SECU] du 2026-11-24 : notes de sécurité maintenues |
| Absence d'avis prise comme un fait pour maildev 3.x et smtp4dev | Une faille non publiée ne se voit pas | Scanner les images figées (Trivy, ENF-03) au premier essai |
| Adoption de Mailpit lue chez des tiers (Laravel, DDEV) et par les tirages de Docker Hub | Maturité surévaluée si ces projets changent d'outil ; les tirages comptent aussi la CI | Revoir à la prochaine vérification |
| Pages de Google Cloud lues sans date de mise à jour visible | Un service d'envoi managé apparu depuis échapperait à la section 2 | Relire les pages avant l'ADR-014 |
| Mémoire de la couche plus petite que le bruit du nœud de base (88,7 Mio d'écart entre exécutions) | Couche de Mailpit et de maildev illisible au nœud, -12,5 et 2,9 Mio ; aucun effet sur les notes : au plus défavorable, 90,2, 112,9 et 161,3 Mio, tous sous 512 | Plus d'exécutions du nœud de base, entrelacées avec les options, ou une couche mesurée dans le même cluster avant et après installation |
| Poste sur batterie pendant la série, et non sur secteur | Temps et CPU possiblement plus lents ; aucune mise en veille relevée | Relancer la série sur secteur |
| Un seul poste, en arm64 : le volume amd64 vient du registre, pas d'un tirage mesuré | Démarrage sur amd64 non essayé ; volume noté exact, puisque lu dans les manifests | Relancer le script sur un poste ou un runner linux amd64 |
| M5 mesuré avec un maintien de 5 s de la connexion, retiré après coup | Précision de M5 limitée, sans effet sur les notes : M5 n'alimente aucun seuil | Un client HTTP qui rend la main à la fermeture par le serveur, sans curl ni wget |
| Mesure sans le miroir de l'ADR-011, accepté après l'écriture des seuils | Seuil 2 dépassé par les trois options au titre des tirages depuis Internet | Décision du DSI sur la lecture du seuil 2 (section 7) |
| Configuration de smtp4dev corrigée par [BENCH] pendant les tests de fumée | Une équipe qui suit la documentation retomberait sur les mêmes pièges ; la note d'expérience dev en tient compte | Aucune : ces pièges sont des faits de l'essai |
| Base mesurée 15 minutes après la série, et non entrelacée avec elle | Une dérive de l'hôte entre les deux séries fausserait M2 | Entrelacer le nœud de base avec les options |
| M8 limité à l'API REST | socket.io de maildev, IMAP et POP3 de smtp4dev hors de la mesure | Un contrôle par port et par canal dans la matrice, et une NetworkPolicy |
| Trois avis récents de Mailpit hors de la base mondiale ; version du binaire peut-être illisible par Trivy | Un scan de l'image figée ne verrait pas ces failles | Lire les avis du dépôt chaque mois ; au premier scan, vérifier que Trivy relève `github.com/axllent/mailpit` en v1.34.0 |
| `docker ps` lancé à la main hors du verrou le 2026-11-21, écart déclaré par [BENCH] | Aucun : lecture seule, et aucune mesure retenue ne date de ce jour | Aucune |
| Mémoire de Mailpit mesurée au repos avec un seul mail reçu, sans demande ni limite | Plancher du profil standard sous-estimé si Mailpit garde beaucoup de mails | Mesurer sur le golden repo, avec la demande et la limite retenues |
| Prix de GKE : valeurs d'exemple de us-central1 [S73] ; grilles de GKE et du réseau illisibles le 2026-11-24 (<https://cloud.google.com/kubernetes-engine/pricing>, <https://cloud.google.com/vpc/network-pricing>) ; région non choisie | Montants de la voie GKE en ordre de grandeur, pas un budget ; Cloud NAT et sortie de la voie du relais non chiffrés | Grilles de la région retenue lues avant la GATE 2 (R-05) |

## 9. Sources

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
| S11 | <https://mailpit.axllent.org/docs/configuration/runtime-options/> | 2026-11-20, 2026-11-24 | `MP_UI_AUTH_FILE`, `MP_SMTP_AUTH_FILE`, écoute par défaut sur 0.0.0.0 ; `MP_DISABLE_VERSION_CHECK` à `false` par défaut, Mailpit interroge alors GitHub ; `MP_ALLOW_INTERNAL_HTTP_REQUESTS` à `false` ; relais `MP_SMTP_RELAY_CONFIG`, `MP_SMTP_RELAY_ALL` à `false`, `MP_SMTP_FORWARD_CONFIG`, `MP_WEBHOOK_URL`, POP3 seulement avec identifiants, base temporaire par défaut, relus le 2026-11-24 | Oui |
| S12 | <https://mailpit.axllent.org/docs/configuration/http/> | 2026-11-20, 2026-11-24 | `MP_UI_AUTH` en variable d'environnement, « not available as a CLI flag » pour raison de sécurité ; l'authentification couvre l'interface et l'API ; exemple `user1:password1 user2:password2` ; l'API d'envoi retombe sur ces identifiants | Oui |
| S13 | <https://mailpit.axllent.org/docs/configuration/passwords/> | 2026-11-20 | Fichiers de mots de passe en clair ou hachés (SSHA, MD5Crypt, APR1Crypt, SHA, bcrypt, crypt SHA-256 et SHA-512) | Oui |
| S14 | <https://mailpit.axllent.org/docs/api-v1/> | 2026-11-20 | API REST sous `/api/v1/`, fichier Swagger 2.0 publié ; route `/api/v1/messages` dans `server/ui/api/v1/swagger.json` du dépôt | Oui |
| S15 | <https://github.com/axllent/mailpit/blob/develop/server/server.go> | 2026-11-20, 2026-11-24 | Routes `livez` et `readyz` enregistrées sans le middleware d'authentification, à côté des routes protégées ; relu à v1.34.0 le 2026-11-24 : `send`, `proxy`, `release` derrière l'authentification | Oui |
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
| S64 | <https://kubernetes.io/docs/concepts/security/pod-security-admission/> | 2026-11-21 | Étiquettes de namespace `pod-security.kubernetes.io/<MODE>: <LEVEL>` et `<MODE>-version: <VERSION>`, modes `enforce`, `audit`, `warn` | Oui |
| S65 | <https://docs.docker.com/docker-hub/usage/> et <https://docs.docker.com/docker-hub/usage/pulls/> | 2026-11-21, 2026-11-23 | 100 tirages par tranche de 6 heures pour une adresse IPv4 anonyme ; une requête GET de manifest compte, pas une requête HEAD ; un tirage d'image multi-architecture compte un tirage par architecture | Oui |
| S66 | <https://github.com/axllent/mailpit/security/advisories/GHSA-v887-64wg-qqc9> | 2026-11-24 | Publié le 2026-11-17 à 06:58 UTC, moyen, CVSS 3.1 6,5 (AV:A/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H), CWE-248, sans CVE ; versions >= 1.33.1 et < 1.34.0, corrigé en 1.34.0 ; « One anonymous SMTP message kills the whole process: SMTP, web UI and REST API together » | Oui |
| S67 | <https://api.github.com/advisories?affects=github.com/axllent/mailpit&ecosystem=go>, <https://api.osv.dev/v1/vulns/GHSA-v887-64wg-qqc9>, <https://trivy.dev/latest/docs/coverage/language/golang/> | 2026-11-24 | 15 avis dans la base mondiale ; GHSA-2vgv-6hcp-mf43, GHSA-379p-g4f4-hq5h et GHSA-v887-64wg-qqc9 absents ; OSV répond 404 ; Trivy lit la base de GitHub pour les modules Go hors bibliothèque standard, et lit la version d'un binaire dans ses informations de build, sinon « (devel) » puis les `-ldflags` | Oui |
| S68 | <https://github.com/axllent/mailpit/blob/v1.34.0/.github/workflows/build-docker.yml>, <https://github.com/axllent/mailpit/blob/v1.34.0/Dockerfile>, <https://github.com/axllent/mailpit/releases/tag/v1.34.0> | 2026-11-24 | Construction déclenchée par `release: created`, `docker/build-push-action` v7.4.0 figée par SHA, poussée vers docker.io et ghcr.io, sans cosign ni attestation ; `FROM golang:alpine` et `alpine:latest`, aucun `USER`, `go build -ldflags` ; release publiée le 2026-11-17 à 06:57:50 UTC, qui refuse au démarrage des identifiants vides | Oui |
| S69 | <https://api.github.com/repos/axllent/mailpit/attestations/sha256:23a2ef85bc50853ab3093645d1d64679afd8887e89da5e48a88940c172591a4e>, <https://hub.docker.com/v2/repositories/axllent/mailpit/tags/v1.34.0>, <https://hub.docker.com/v2/repositories/axllent/mailpit/tags?name=sha256>, <https://hub.docker.com/v2/repositories/maildev/maildev/tags/3.0.0>, <https://hub.docker.com/v2/repositories/rnwood/smtp4dev/tags/3.16.1> | 2026-11-24 | Aucune attestation (404) ; aucun tag `sha256-*` ; Mailpit v1.34.0 poussé une fois le 2026-11-17 à 07:07:21 UTC, maildev 3.0.0 le 2026-09-23 à 16:22:28 UTC, smtp4dev 3.16.1 le 2026-11-06 à 08:22:29 UTC ; condensats d'index égaux à ceux du script | Oui |
| S70 | <https://github.com/maildev/maildev/blob/maildev@3.0.0/packages/api/src/server.ts>, `packages/core/src/utils/summary.ts`, `packages/cli/src/server/orchestrator.ts` du même tag, <https://github.com/socketio/socket.io/blob/socket.io@4.8.3/packages/engine.io/lib/server.ts> | 2026-11-24 | Basic par crochet `onRequest` de Fastify, `/api/healthz` exclu ; CORS de l'API `origin: true`, `credentials: true`, non réglé par la CLI ; socket.io sur `/socket.io`, CORS `*`, émet `newMail` avec sujet, adresses et 140 caractères de texte ; `attach()` d'engine.io intercepte ce chemin avant les autres écouteurs (l. 917-944) | Oui |
| S71 | <https://github.com/rnwood/smtp4dev/blob/3.16.1/Rnwood.Smtp4dev/appsettings.json> | 2026-11-24 | `AuthenticationRequired` à `false`, « True if SMTP and IMAP will require authentication » ; `ImapPort` 143, `Pop3Port` 110, « Set to null to disable » ; `RelayOptions.SmtpServer` vide ; exemples `password` et `pass` | Oui |
| S72 | <https://github.com/kubernetes-sigs/kind/releases/tag/v0.24.0> | 2026-11-24 | Publiée le 2024-08-15 : « Out-of-the-box support for network policy via sigs.k8s.io/kube-network-policies » | Oui |
| S73 | <https://docs.cloud.google.com/kubernetes-engine/cud> | 2026-11-24 | Exemple de calcul pour us-central1 : 0,0445 USD par vCPU et 0,0049225 USD par « GB », par heure, pour les pods Autopilot ; tarifs avant la remise de 28 % de l'engagement flexible d'un an, pas la grille (relevé de [FINOPS]) | Oui |
| S74 | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests> | 2026-11-24 | Classe généraliste : minimums de 50m et 52 MiB avec rafale, 250m et 512 MiB sans ; sans demande, 0,5 vCPU et 2 GiB ; stockage éphémère de 1 GiB par défaut ; arrondi à 0,25 vCPU sans rafale ; rapport vCPU:Gio de 1:1 à 1:6,5 (relevé de [FINOPS]) | Oui |
| S75 | <https://docs.cloud.google.com/kubernetes-engine/docs/how-to/pod-bursting-gke> | 2026-11-24 | Rafale à partir de GKE 1.30.2-gke.1394000, cgroupv2 requis (défaut des clusters créés en 1.26 ou plus), après un redémarrage du plan de contrôle (relevé de [FINOPS]) | Oui |
| S76 | <https://firebase.google.com/docs/auth/limits> | 2026-11-24 | Quotas quotidiens d'envoi de mails : Spark 150, 1 000, 1 000 et 5 ; Blaze 10 000, 100 000, 10 000 et 25 000 (réinitialisation, vérification d'adresse, changement d'adresse, lien de connexion) ; « Limitations apply per customer and can change without notice » ; aucun quota propre à Identity Platform, rien sur la facturation de ces envois (relevé de [FINOPS]) | Oui |

## 10. Relectures

| Relecteur | Porte sur | Date | Avis |
| --- | --- | --- | --- |
| [SECU] | Licences, critères éliminatoires, sécurité | 2026-11-24 | Réservé, favorable à Mailpit v1.34.0 sous conditions. Licences, gouvernance et critères éliminatoires sont confirmés sur les sources. La maturité de Mailpit passe à 4 : il n'a ni fondation ni liste d'adoptants tenue par le projet. GHSA-v887-64wg-qqc9 existe, de gravité moyenne (CVSS 6,5), et l'exception du principe VI couvre la v1.34.0 ; le délai de 7 jours s'achève de toute façon le 2026-11-24. Les notes de sécurité tiennent, mais M8 ne voyait que l'API REST : maildev et smtp4dev laissent chacun lire les mails hors de l'authentification. Aucune image n'est signée, et une image de docker.io hors de `library/` demande sa propre dérogation dans l'ADR-014. Aucun secret dans les données ni dans les commits. Conditions 1 à 8. |
| [FINOPS] | Coût | 2026-11-24 | Favorable, avec corrections. Les chiffres de 4.4, 5.6 et 5.9 se retrouvent dans les données brutes de `series-1` et `base-1`, sauf deux phrases de la lecture de M2. Les seuils de 4.1 ont été appliqués tels qu'écrits : 4/5, 4/5 et 3/5 tiennent, et la note ne dépend pas du bruit du nœud de base. Avec Mailpit, le premier `task up` du profil standard passe de 1 787,0 à 1 802,1 Mo : 160,2 % du budget de 900 s à 10 Mbit/s, et 16,0 Mbit/s au minimum. Le profil standard reste à 3,5 Gio de VM et 7,5 Gio de portable. Il tient sur 8 Gio au repos avec Keycloak et Mailpit, avec 420,4 Mio de marge ; pour tenir aussi à la limite de Keycloak, cette limite doit rester sous 1 240 Mi environ. Sur GCP, ne rien déployer coûte 0 USD. Mailpit sur GKE Autopilot coûterait de 1,8 à 23,4 USD par mois selon ses demandes de ressources, aux prix d'exemple de us-central1. Le relais réel n'a aucun prix lu. Je propose 4/5 en coût pour les trois options, comme dans BENCH-012 : les écarts ne changent pas. |

[SECU] Licences (5.1). Je confirme 5, 5 et 4. D'après l'API des dépôts relue
le 2026-11-24, Mailpit et maildev sont sous MIT, smtp4dev sous BSD-3-Clause
[S1], [S22], [S33]. L'accord de contribution de smtp4dev donne au projet le
droit de « sublicense, and/or sell » les contributions [S43] : c'est la
réserve mineure de sa note. Aucune option n'est sous AGPL. L'image de Mailpit
embarque des paquets d'Alpine sous leurs propres licences. CELIAN ne
redistribue aucune image, puisque le miroir zot ne transmet de copie à
personne (ADR-011, condition 9).

[SECU] Gouvernance (5.2). Je confirme 2 pour les trois. Les statistiques de
contribution de GitHub, depuis la semaine du 2025-11-16, donnent au mainteneur
de Mailpit 443 commits sur 485, dont 12 de Dependabot. Celui de maildev en a
89 sur 106. Pour smtp4dev, l'API des commits compte 5 commits du mainteneur
entre le 2025-11-20 et le 2026-11-20, comme le rapport. Chacun des trois
projets repose sur une seule personne.

[SECU] Maturité (5.3). Je ramène Mailpit à 4. Les rapports précédents
réservent 5 aux projets gradués à la CNCF qui ont une liste d'adoptants
déclarée (Cilium, Argo CD, Flux), et à minikube, sous-projet de Kubernetes. Un
projet sans fondation, qui ne tient pas lui-même de liste d'adoptants, a reçu
4 : k3d dans BENCH-003, Traefik dans BENCH-004, Config Sync dans BENCH-009.
Keycloak a 4 dans BENCH-012, alors qu'il est Incubating à la CNCF et liste 59
adoptants. Mailpit est tenu par une personne et son adoption se lit chez
Laravel et DDEV : il ne peut pas passer devant. Le rapport le reconnaît
lui-même, puisque sans ces deux sources la note serait 4. maildev reste à 3 et
smtp4dev à 4.

[SECU] Avis corrigé par la v1.34.0, et principe VI. GHSA-v887-64wg-qqc9
existe. Le dépôt l'a publié le 2026-11-17 à 06:58:14 UTC, 24 secondes après la
release v1.34.0. Il est classé moyen, CVSS 3.1 de 6,5
(AV:A/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H), CWE-248, et touche les versions de
1.33.1 incluse à 1.34.0 exclue [S66]. Un seul message SMTP anonyme fait
paniquer le processus entier : SMTP, interface et API. La section 2 ne parle
que du serveur SMTP. L'avis n'a pas de CVE, n'est pas dans la base mondiale de
GitHub, et OSV répond 404 [S67]. Gravité réelle sur le PC : faible, puisqu'il
faut un pod du cluster pour arrêter un outil de développement, sans aucune
fuite. L'exception du principe VI (constitution 1.2.0) vise « une version qui
corrige un avis de sécurité publié (CVE ou avis du projet) », et la v1.34.0 en
relève. Sa condition, une PR qui passe toute la matrice, ne peut pas encore
être tenue, faute de matrice. Elle n'a pas à l'être : le délai de 7 jours
s'achève le 2026-11-24 à 06:57 UTC, avant toute PR du golden repo. Appliquer
l'exception à la mesure reste une lecture du DSI, et je la partage : on mesure
la version que le blueprint figera. Les notes de la v1.34.0 ajoutent un point
utile : Mailpit refuse désormais de démarrer avec des identifiants vides
[S68], ce qui sert la condition 1 de l'ADR-007.

[SECU] Sécurité de Mailpit (5.5). Je maintiens 3 et je complète la
justification. Avis : les comptes sont exacts, 18 avis du 2026-01-06 au
2026-11-17, 1 élevé et 17 moyens selon le dépôt ; la base mondiale en contient
15, dont 3 qu'elle classe élevés [S4], [S67]. Les trois absents sont les plus
récents, tous sans CVE : GHSA-2vgv-6hcp-mf43 (2026-09-19), GHSA-379p-g4f4-hq5h
(2026-10-22, le seul élevé du dépôt, à 7,5) et GHSA-v887-64wg-qqc9. Angle mort
des scanners : Trivy lit la base de GitHub pour les modules Go hors
bibliothèque standard [S67], donc un scan de l'image ne voit pas ces trois
avis, comme les CVE sans paquet de R-36. Le binaire est construit par `go
build`, avec la version passée en `-ldflags` [S68] ; je n'ai pas vérifié que
Trivy sait lire cette version ; s'il ne la lit pas, aucun des 18 avis ne
sortirait. Signature : le flux de publication de la v1.34.0 n'a ni cosign ni
`actions/attest` ; l'API d'attestations de GitHub répond 404 pour le condensat
mesuré, et Docker Hub n'a aucun tag `sha256-*` [S68], [S69]. Image : le tag
v1.34.0 n'a été poussé qu'une fois, le 2026-11-17 à 07:07 UTC, au condensat
que fige le script [S69] ; le Dockerfile part pourtant de `golang:alpine` et
d'`alpine:latest`, sans condensat, et ne déclare aucun utilisateur. Accès : la
v1.34.0 tient bien ce point ; l'interface, l'API, le WebSocket, le proxy et
`release` passent par la même authentification, l'API d'envoi y retombe quand
elle n'a pas d'identifiants propres, et seules `livez` et `readyz` restent
ouvertes [S15]. La réserve demande d'agir : suivre les versions correctives,
lire les avis du dépôt hors des scanners, imposer le profil `restricted`.

[SECU] Sécurité de maildev (5.5). Je maintiens 2. J'écarte la lecture de la
politique 3.x comme une rupture. Le calendrier de CVE-2024-27448 est exact :
ticket public le 2023-08-25, avis mondial le 2024-04-05, correctif fusionné le
2024-12-10, publié en 2.2.1 le 2024-12-12 [S26], [S27]. Le dépôt n'a jamais
publié d'avis. Le code de la 3.0.0 montre deux faits que M8 ne pouvait pas
voir. socket.io échappe à l'authentification : l'authentification Basic est un
crochet `onRequest` de Fastify, socket.io est attaché au même serveur HTTP,
sur `/socket.io`, et engine.io intercepte ce chemin avant de passer la main
aux autres écouteurs, donc le crochet ne s'exécute pas ; chaque nouveau mail
part alors en résumé vers tout client connecté : sujet, adresses et 140
premiers caractères du texte, et un code de confirmation placé en début de
texte y passerait [S70]. Le CORS est ouvert : celui de l'API renvoie toute
origine avec `credentials: true`, et la CLI ne le règle pas [S70]. Ces deux
faits viennent de la lecture du code, je ne les ai pas essayés.

[SECU] Sécurité de smtp4dev (5.5). Je maintiens 2. Le projet n'a ni avis ni
politique de sécurité [S36]. Le fichier de réglages de la 3.16.1 ajoute un
point : `AuthenticationRequired` vaut `false`, et son commentaire dit « True
if SMTP and IMAP will require authentication » [S71]. Le manifest a déplacé
IMAP et POP3 sur 1143 et 1110 au lieu de les couper, alors que `null` les
désactive. Le journal du deuxième test de fumée les montre à l'écoute. Hors du
Service, ils restent joignables par l'adresse du pod depuis n'importe quel pod
du cluster. M8 a mesuré le 401 de l'API, pas la lecture des mails par IMAP.
C'est une lecture des réglages, non essayée.

[SECU] Secrets (R-20, ADR-007). Les couches versionnées ne contiennent aucun
objet Secret ni aucune valeur ; les trois manifests lisent l'identifiant par
`secretKeyRef`, sans `command` ni `args`. Aucune des trois images ne livre de
mot de passe par défaut : par défaut, elles n'ont pas d'authentification du
tout, et les manifests en ajoutent une ; le risque pour le golden repo est
donc l'oubli de `MP_UI_AUTH` : l'interface resterait ouverte, sans aucune
erreur. Le script tire 32 caractères de `/dev/urandom` et les passe à `awk`
par l'entrée standard, puis à `kubectl create -f -` : la valeur ne passe par
aucune variable, aucun fichier, aucun argument, c'est la condition 1 de
l'ADR-007, avec `awk` à la place de `printf`. La sonde construit l'en-tête
`Basic` dans le pod et ne le passe qu'à des fonctions du shell et à `printf`,
vers une FIFO, jamais à `nc` ; elle n'écrit que des paires clé et valeur. Dans
`series-1`, `base-1`, `smoke-1` à `smoke4-1`, les fichiers `.out` et
`wait-*.log` : ni valeur de Secret, ni en-tête, ni clé ; les journaux ne
gardent que « secret/mail-ui-auth created » ; les `kubeconfig` font 28 octets,
et 0 pour `smoke-1` ; gitleaks n'y trouve rien. Les journaux de kind gardent
le chemin absolu du dossier de travail, nom du compte compris : ils ne doivent
pas entrer dans le dépôt.

[SECU] Valeurs connues à ajouter à la condition 1 de l'ADR-007. Pour Mailpit :
`password1` et `password2`, l'exemple de la page de configuration HTTP
(`MP_UI_AUTH="user1:password1 user2:password2"`), repris pour l'API d'envoi
[S12]. Si smtp4dev revenait : `pass`, l'exemple de
`CredentialsValidationExpression` [S71] ; son autre exemple, `password`, est
déjà dans la liste. Le README de maildev 3.0.0 n'a que `<pass>`, un gabarit.
Toutes ces valeurs font moins de 32 caractères et tombent déjà sous la règle
de longueur. Deux précisions comptent davantage. La clé `mp-ui-auth` contient
`utilisateur:mot de passe` : appliquée à la clé entière, la règle de longueur
laisserait passer un mot de passe faible derrière un nom d'utilisateur long,
donc le test vise la partie qui suit le premier `:`. Le tirage exclut l'espace
et le `:`, qui séparent les entrées dans le format de `MP_UI_AUTH` [S12]. Le
nom d'utilisateur est fixe : il sort du test de répétition, comme `username`
dans la condition 10 de l'ADR-012.

[SECU] Signature, registres et profil (ENF-03, ADR-011, ADR-012). Aucune image
mesurée n'est signée. J'ai vérifié Mailpit moi-même (5.5) ; pour maildev et
smtp4dev, je garde la lecture du rapport [S45], [S63] ; leurs tags n'ont été
poussés qu'une fois, au condensat du script [S69]. Les trois images sont sur
docker.io, hors de `library/` : la dérogation de l'ADR-012 ne les couvre pas,
et celle de l'ADR-013 ne vise que `quay.io/keycloak/keycloak` ; l'ADR-014
porte donc la sienne pour `docker.io/axllent/mailpit`. zot sert déjà docker.io
: aucun registre n'entre dans la liste de la condition 10 de l'ADR-011 ; le
miroir sur ghcr.io que publie Mailpit n'apporterait rien ; un tirage anonyme
suffit (condition 13). Profil `restricted` : l'image de Mailpit tourne en root
faute de `USER`, et il suffit de lui donner un utilisateur numérique ; maildev
demande le même ajout ; smtp4dev demande cinq réglages, dont une variable où
la casse décide du résultat : c'est la configuration la plus fragile.
`readOnlyRootFilesystem` n'a été essayé pour aucune option, et aucune limite
de ressources n'est posée ; par défaut, Mailpit écrit sa base dans un fichier
temporaire [S11].

[SECU] Ce que le serveur expose. SMTP : sans authentification et ouvert à tout
pod du cluster, ce qui est voulu ; dans l'essai, les Services sont en
`ClusterIP` et aucun port n'est publié vers l'hôte. Relais : aucun n'est
actif. Chez Mailpit, le relais demande `MP_SMTP_RELAY_CONFIG` ou ses
variables, le transfert `MP_SMTP_FORWARD_CONFIG`, le webhook `MP_WEBHOOK_URL`,
et l'API `release` dépend du relais ; POP3 reste coupé sans identifiants
[S11], [S15]. maildev ne relaie qu'avec `--outgoing-host` [S29]. smtp4dev ne
relaie qu'avec `RelayOptions.SmtpServer`, réglable depuis l'interface tant que
`LockSettings` vaut `false` [S71]. Sorties HTTP de Mailpit : la vérification
de version, que le manifest coupe, et, quand un utilisateur de l'interface le
demande, la vérification des liens, celle du HTML et le proxy des captures ;
les adresses internes y sont refusées par défaut [S11]. Sortie du poste : sur
le PC, rien ne bloque le port 587, contrairement à GCP ; la promesse « aucun
mail ne quitte le poste » ne tient donc que par la configuration, et la série
n'a pas essayé de sortie. kind applique les NetworkPolicy depuis la v0.24.0,
grâce à kube-network-policies [S72] : une politique qui ferme la sortie du pod
rend la promesse vérifiable. L'interface passe par la gateway en boucle locale
(R-20, ADR-005), ce que l'essai n'a pas couvert.

[SECU] Inventaire du script, et `docker ps`. L'inventaire nomme bien les
commandes qui écrivent : `kind create cluster`, `kind delete cluster`, et
`kubectl apply` et `create` contre le cluster de l'essai ; `kubectl delete`
est déclaré mais ne sert pas. Il manque deux mentions, que la version intégrée
de BENCH-012 contient : `kind create cluster` lance le nœud par `docker run
--privileged`, et `docker ps -q` (ligne 408) n'est pas dans la liste des
commandes qui lisent. Le script ne sort du poste que par `docker manifest
inspect` et par les tirages du nœud, tous vers Docker Hub. Il ne prend le
verrou que si `BENCH_LOCK` est défini, ce que la section 4.3 ne dit pas. Le
`docker ps` lancé hors du verrou le 2026-11-21 est sans conséquence : la
commande ne fait que lire et ne touche ni conteneur ni réseau, et aucune
mesure retenue ne date de ce jour ; BENCH-012 garde `series-4` du 2026-11-23,
BENCH-013 le 2026-11-23 entre 22:42 et 23:41 UTC. L'écart s'écrit en section
8, et la règle reste telle quelle.

[SECU] Dépôt public. Le gitleaks du hook pre-commit, figé en v8.30.1, a scanné
`55b53af..9329120` : sept commits, aucune fuite. Les lignes ajoutées ne
contiennent ni `/Users/`, ni `/private/tmp`, ni `scratchpad`, ni tiret
cadratin. Auteur et committer utilisent l'adresse noreply.

[SECU] Parité sur GCP, pour [ARCHI]. La première voie est la moins exposée :
rien sur `gcp`, et l'hôte SMTP dans la configuration. La deuxième ferait
tourner, sur un cluster joignable, un outil qui garde des liens de
confirmation et de réinitialisation : il faudrait alors une interface jamais
publique, une sortie fermée, une dérogation à ENF-03 et un budget de [FINOPS].
La troisième ferait entrer un vrai identifiant d'envoi : c'est le cas de la
question 2 de l'ADR-007, hors du MVP.

[SECU] Conditions proposées pour l'ADR-014 (Mailpit) :

1. Image et dérogation à ENF-03. `docker.io/axllent/mailpit` est désignée par
   condensat et tirée par zot ; docker.io est déjà dans la liste de la
   condition 10 de l'ADR-011. La dérogation est datée, sur le modèle de
   l'ADR-013 : référence exacte, condensat compris, dans une liste fermée, et
   [SECU] relit chaque condensat neuf. Elle tombe quand Mailpit signe ses
   images de façon vérifiable par Kyverno. Contrôles : S01, E11, et le
   contrôle de la condition 7 de l'ADR-012 étendu à
   `docker.io/axllent/mailpit`.
2. Suivi et scanners. Renovate suit les versions correctives. Une version qui
   corrige un avis du dépôt passe par l'exception du principe VI, matrice
   comprise. [SECU] lit chaque mois les avis du dépôt (R-36 étendu à Mailpit).
   Au premier scan de l'image figée, [SECU] vérifie que Trivy relève
   `github.com/axllent/mailpit` et sa version ; sinon, R-36 dit que le scan ne
   couvre pas Mailpit.
3. Durcissement. Le namespace applique le profil `restricted`. Le pod a
   `runAsNonRoot`, un `runAsUser` numérique, `allowPrivilegeEscalation:
   false`, les capacités `ALL` retirées, `seccompProfile: RuntimeDefault` et
   `automountServiceAccountToken: false`. `readOnlyRootFilesystem` s'essaie
   avec un `emptyDir` borné par `sizeLimit`, qui reçoit la base temporaire. Le
   pod a une limite mémoire. `MP_MAX_MESSAGES` et `MP_MAX_MESSAGE_SIZE` sont
   fixés par [DEV] avec [FINOPS]. Contrôle : la matrice échoue sur un pod
   refusé par le profil.
4. Aucun envoi hors du poste. La couche ne porte aucune variable
   `MP_SMTP_RELAY_*`, `MP_SMTP_FORWARD_*`, `MP_WEBHOOK_URL` ou
   `MP_SEND_API_AUTH_ACCEPT_ANY`, ni `MP_ALLOW_INTERNAL_HTTP_REQUESTS` à
   `true`. `MP_DISABLE_VERSION_CHECK` vaut `true`. Une NetworkPolicy refuse
   toute sortie au pod ; en entrée, elle n'admet que le SMTP depuis
   l'application et le HTTP depuis la gateway. [OPS] vérifie qu'elle
   s'applique sous kind 0.33.0 [S72], comme pour la condition 4 de l'ADR-013.
   Contrôles : un contrôle statique refuse ces variables dans le rendu ; un
   pod non admis n'atteint ni 1025 ni 8025.
5. Exposition. Le SMTP ne sort pas du cluster : Service en `ClusterIP`, sans
   `NodePort`, ni `LoadBalancer`, ni route TCP. L'interface passe par une
   HTTPRoute de la gateway en boucle locale. POP3 reste coupé. Contrôle : par
   la gateway, `/api/v1/messages` répond 401 sans identifiant.
6. Identifiants (R-20). Le Secret est créé par `task up` selon la condition 1
   de l'ADR-007, avec `password1` et `password2` ajoutés à la liste. Le test
   vise la partie mot de passe de `mp-ui-auth`, et le tirage exclut l'espace
   et le `:`. `MP_UI_AUTH` vient d'un `secretKeyRef`. Le contrôle du type de
   M8 (401 puis 200) entre dans la matrice, sans identifiant en argument. Le
   README dit comment lire le mot de passe sans l'écrire dans un fichier.
   Contrôles : E04 et E05 étendus à la couche ; un contrôle statique sur la
   source de `MP_UI_AUTH`.
7. Version. La v1.34.0 est figée par condensat après le 2026-11-24 à 06:57
   UTC. L'exception du principe VI n'est pas requise pour le golden repo.
8. GKE. Aucun déploiement en phase 2. Si [ARCHI] retient un serveur de test
   sur GKE, les conditions 1 à 6 s'appliquent, l'interface n'est jamais
   publique, et il faut l'accord de Lucas et un budget de [FINOPS]
   (principe X).

[SECU] D'accord, avec réserves : Mailpit reste devant. L'écart tient sur la
maturité, l'activité, la sécurité et l'expérience dev. M8 faisait paraître
égaux les contrôles d'accès des trois options ; la lecture du code les sépare.
maildev diffuse les nouveaux mails hors de l'authentification, et smtp4dev
laisse IMAP sans identifiant. Mailpit protège l'interface, l'API et le
WebSocket. Ses faiblesses viennent d'ailleurs : des avis fréquents, dont les
derniers échappent aux scanners, et une image qui tourne en root sans
signature. Les conditions 1 à 4 les couvrent.

[SECU] Non vérifié : que Trivy lise la version du binaire de Mailpit ; que les
NetworkPolicy s'appliquent sous kind 0.33.0 ; le contournement par socket.io
chez maildev et l'accès IMAP sans identifiant chez smtp4dev, lus dans le code
et les réglages sans être essayés ; que `printf` soit intégré au shell de
busybox ; les workflows de maildev et smtp4dev.

[FINOPS] Recalcul depuis la série du 2026-11-23. J'ai relu `runs.tsv`,
`idle.tsv`, `summary.tsv`, `images.tsv`, `node-images.tsv`, `load.tsv` et
`versions.tsv` de `series-1`, puis les mêmes fichiers de `base-1`. Le script
prend la médiane des trois échantillons de chaque exécution, puis la médiane
des trois exécutions. La couche est la médiane du nœud de l'option moins celle
du nœud de base. M1, le nœud au repos, M7, la mémoire du pod, M3, le CPU du
nœud et M5 se retrouvent au dixième près, écarts compris, échantillon par
échantillon. M4 se retrouve aux octets en amd64 : 15 109 173 pour Mailpit, 74
861 847 pour maildev, 176 881 932 pour smtp4dev, soit 12,1, 59,9 et 141,5 s à
10 Mbit/s. Le seuil 2 se lit dans `node-images.tsv` : un événement `Pulled`
pour l'image de l'option dans chacune des neuf exécutions. Le tirage prend de
2,5 à 2,7 s pour Mailpit, de 4,6 à 4,9 s pour maildev et de 5,8 à 6,3 s pour
smtp4dev. busybox est tirée aussi dans les trois exécutions de base et reste
hors couche. Deux écarts, tous deux en 4.4 et sans effet sur les notes.
D'abord, le nœud de base varie de 88,7 Mio, plus que chacune des trois
couches, smtp4dev compris (74,0), alors que le rapport écrit « plus que deux
des trois ». Ensuite, 129,1 Mio font 25,2 % du seuil de 512 Mio, et non 23 % ;
les 23 % correspondent à la médiane de 118,9 Mio.

[FINOPS] Lire une couche plus petite que le bruit. La troisième règle de la
GATE 1 fixe la méthode, mais ne dit pas quoi faire d'un résultat négatif. Je
propose deux lectures, que le DSI doit faire valider. Pour la note, on compare
toujours au seuil la valeur que donne la règle. Quand elle est plus petite que
l'écart du nœud de base, on écrit « dans le bruit » et on contrôle le seuil
sur un majorant : le nœud de l'option le plus haut moins le nœud de base le
plus bas, en médianes d'exécution. Si le majorant reste sous le seuil, la note
ne dépend pas du bruit ; s'il le franchit, on refait la mesure en entrelaçant
la base avec les options. Pour dimensionner, on compte la plus grande des deux
valeurs, couche au nœud ou mémoire de travail du pod, puisque le nœud doit au
moins loger le pod. Une valeur négative ne se retranche jamais d'un plancher.
Ici, les majorants valent 90,2 Mio pour Mailpit (631,1 moins 540,9), 112,9
pour maildev et 161,3 pour smtp4dev : 17,6 %, 22,1 % et 31,5 % du seuil de 512
Mio. Échantillon par échantillon, ils montent à 93,5, 199,2 et 207,2 Mio,
toujours sous le seuil, donc la note d'empreinte n'en dépend pas. La couche de
smtp4dev se distingue quand même du bruit : ses trois exécutions (679,4 à
702,2 Mio) dépassent la plus haute du nœud de base (629,6), si bien que sa
couche tient entre 49,8 et 161,3 Mio. La dispersion de la base vient de sa
première exécution : un échantillon à 623,2 Mio puis deux à 540,9 et 538,7, et
un cluster créé en 35,2 s contre 27,2 et 26,6 pour les deux autres. Sans cette
exécution, l'écart de la base tombe à 12,4 Mio. La cause n'est pas établie.

[FINOPS] Seuils de 4.1. J'ai comparé une à une les lignes 248 à 291 du rapport
à `section-4.1-2026-11-20T20:14:05Z.md` : les 44 lignes sont identiques. Le
condensat de référence,
`2d22574e54d5f817d73e5efdb069b794d66c935bc29f59d8b2cc68538f540346`, est daté
du 2026-11-20 à 20:14:05 UTC (`section-4.1.sha256`). Toutes les traces de
mesure sont postérieures. Les contrôles du premier test de fumée tournent à
10:23:07 (`smoke-1.out`, sans date, le 2026-11-22 d'après le rapport), sans
aucune exécution dans `smoke-1/load.tsv`. Le deuxième test de fumée démarre le
2026-11-23 à 21:32:32 UTC, la série à 22:43:28 UTC. Seuil 1 : franchi par
smtp4dev seul (176,9 Mo pour 112,5 ; Mailpit 15,1, maildev 74,9). Seuil 2 :
franchi par les trois options, avec un `Pulled` à chaque exécution. Seuil 3 :
non franchi (3,4, 6,5 et 8,6 s pour 90). Seuil 4 : non franchi, ni par la
valeur de la règle, ni par le majorant. Mailpit et maildev perdent donc un
cran et smtp4dev deux : 4/5, 4/5 et 3/5. Aucune médiane n'est à moins de 10 %
d'un seuil. Comme dans BENCH-012, l'heure d'écriture des seuils et l'absence
de lecture préalable des registres reposent sur la déclaration de [BENCH],
faute de commit.

[FINOPS] Lecture du seuil 2. Je suis d'accord avec la lecture à la lettre. La
série a tourné sans miroir, et chaque création a retéléchargé l'image depuis
Internet, ce que décrit le seuil. Avec le miroir de l'ADR-011, le nœud tire
toujours l'image à chaque création, mais depuis zot, sans réseau après le
premier remplissage. En sensibilité, les trois options regagnent un cran et le
classement ne bouge pas. Pour Mailpit, l'enjeu est faible : 15,1 Mo, soit 12,1
s à 10 Mbit/s par création sans miroir, contre 141,5 s pour smtp4dev. Mailpit
vient de docker.io, déjà dans la liste unique de la condition 10 de l'ADR-011
: contrairement à Keycloak avec quay.io, il n'ajoute aucun amont au miroir.
L'estimation du stockage de zot pour le profil standard passe de 831,6 à 846,7
Mo en amd64, sans mesure qui la confirme.

[FINOPS] Cumul avec le premier `task up`. Depuis BENCH-012 et l'ADR-013, la
base est celle de R-04 : 1 787,0 Mo en amd64, zot, Postgres de l'ADR-012 et
Keycloak compris. Le rapport part encore des 1 521,9 Mo d'avant Keycloak, d'où
ses 1 537,0 Mo et ses 136,6 %. Avec Mailpit, le premier `task up` du profil
standard passe à 1 802,1 Mo : 1 441,7 s à 10 Mbit/s, 160,2 % du budget de 900
s, et 16,0 Mbit/s au minimum pour le seul téléchargement. La part de Mailpit
est de 12,1 s, soit 1,3 % du budget. Sans miroir, le total vaut 1 724,4 Mo,
153,3 % du budget et 15,3 Mbit/s au minimum. Avec maildev, il serait de 1
861,9 Mo (165,5 %) ; avec smtp4dev, de 1 963,9 Mo (174,6 %).

[FINOPS] Mémoire. J'applique la méthode de BENCH-005, reprise de BENCH-010 à
BENCH-012 : plancher multiplié par 1,5, arrondi au demi-gibioctet supérieur,
plus 4 Gio pour le portable, et une VM de 8 Gio sur un portable de 16 Gio. Je
pars du plancher du profil standard avec Keycloak, 2 295,0 Mio (R-04,
ADR-013). Mailpit y entre pour 15,3 Mio, la médiane de son pod, puisque sa
couche au nœud est dans le bruit. Le plancher passe à 2 310,3 Mio : 3,5 Gio de
VM et 7,5 Gio de portable, sans palier de plus. Sur un portable de 8 Gio, il
reste 420,4 Mio de plancher avant la limite, et 79,0 Mio avant le palier de
4,0 Gio, qui tient encore sur 8 Gio. Sur 16 Gio, il reste 3 151,0 Mio. Avec le
majorant de 90,2 Mio, le plancher vaudrait 2 385,2 Mio : toujours 3,5 Gio de
VM, à 4,1 Mio du palier suivant, et 345,5 Mio de reste sur 8 Gio. Le profil
standard tient donc sur 8 Gio au repos avec Keycloak et Mailpit, dans les deux
lectures. smtp4dev, compté à son pod de 118,9 Mio, porterait le plancher à 2
413,9 Mio et la VM à 4,0 Gio ; maildev resterait à 3,5 Gio. Ces chiffres
mêlent des séries de plusieurs benchmarks prises à des jours différents : ce
sont des ordres de grandeur.

[FINOPS] La limite de Keycloak décide du reste (condition 11 de l'ADR-013). À
la limite de la référence, 2000Mi, le plancher monterait à environ 3 490,4 Mio
avec Mailpit : 5,5 Gio de VM et 9,5 Gio de portable, au-delà de 8 Gio, avec
encore 1 970,9 Mio de reste sur 16 Gio. Pour que Keycloak tienne sur 8 Gio à
sa limite avec Mailpit, cette limite doit rester sous 1 240 Mi environ. Le
calcul : 2 730,7 Mio moins 1 451,8, moins 15,3 pour Mailpit, moins les 23,3
Mio que le nœud comptait en plus du pod de Keycloak. Avec le majorant de
Mailpit, la limite tombe à 1 165 Mi. Rien ne prouve que Keycloak tient sous
cette limite : son pod pèse environ 820 Mio au repos, ce qui laisse environ
420 Mi pour le pic de démarrage, jamais mesuré. La demande de la référence,
1700Mi, dépasse cette limite et doit baisser avec elle. Mailpit tournait sans
demande ni limite pendant la mesure : le blueprint doit en poser, pour que son
poids reste celui compté ici.

[FINOPS] Côté GCP, je n'ai lancé aucune action cloud, et aucun budget n'est
validable tant que la région n'est pas choisie (R-05). Le 2026-11-24, l'outil
ne rend que le titre des grilles de prix de GKE et du réseau. Voici les trois
voies, chiffrées sans prix inventé.

[FINOPS] Rien sur `gcp`. Aucun pod, aucune ressource : 0 USD pour la brique.
L'exemple n'envoie pas de mail (Q7), et les mails des parcours de connexion
partent d'Identity Platform, qui les envoie lui-même avec la méthode `DEFAULT`
[S58]. La page des limites de Firebase Authentication donne des quotas
quotidiens d'envoi : en offre Blaze, par exemple, 10 000 réinitialisations et
100 000 vérifications d'adresse par jour [S76]. Elle ne dit pas si ces envois
sont facturés, et ne donne pas de quota propre à Identity Platform. Une démo
reste loin de ces quotas.

[FINOPS] Mailpit dans GKE Autopilot, en `oss` avec `managed_gap`. Autopilot
facture les demandes de ressources du pod. Avec la rafale, disponible à partir
de GKE 1.30.2-gke.1394000 sur un cluster en cgroupv2 [S75], le minimum de la
classe généraliste est de 50m et 52 MiB [S74]. Mailpit pèse 15,3 Mio et 0,17 %
d'un cœur au repos sur le PC, donc il y tient, sans mesure sur GKE. Les prix
d'exemple de us-central1 sont de 0,0445 USD par vCPU-heure et 0,0049225 USD
par Go-heure, avant remise d'engagement [S73]. Sur 730 heures allumées, cela
fait environ 1,8 USD par mois. Sans rafale, le minimum passe à 250m et 512 MiB
: 9,9 USD par mois, ou 10,1 si l'unité de la page est le Go décimal. Sans
demande, Autopilot applique 0,5 vCPU et 2 GiB : 23,4 USD par mois, ou 24,0.
Trois postes restent hors chiffre. Le stockage éphémère, 1 GiB par défaut
[S74], a un prix non lu. Ouvrir l'interface ne coûte rien par `kubectl
port-forward`, ni par une route sur la Gateway de l'application, qui n'ajoute
pas d'équilibreur, mais cette route est à relire par [SECU]. Les journaux sont
facturés au volume (R-18). Dans le MVP, ce pod ne recevrait rien : l'exemple
n'envoie pas de mail, et rien de ce qui a été lu ne dit qu'Identity Platform
joigne un hôte privé du cluster en `CUSTOM_SMTP`. S'il fallait publier le port
SMTP, un équilibreur public s'ajouterait, à un prix non lu.

[FINOPS] Relais réel, fournisseur tiers ou Google Workspace, sur le port 465
ou 587. Je n'ai lu aucun prix et je n'en écris aucun. Au-delà de l'abonnement,
cette voie ouvre deux coûts. Le premier est une facture hors de Cloud Billing
: le budget d'alerte du projet de démo ne la voit pas (R-05), il lui faut donc
son propre plafond. Le second est la sortie vers Internet. Les nœuds sont
privés (ADR-008), et le socle mesuré n'a pas de Cloud NAT : il faudrait
l'ajouter, ou une autre voie de sortie. Ce service et le trafic sortant sont
facturés, à des prix que la page du réseau ne rend pas. L'identifiant du
relais irait enfin dans Secret Manager, facturé à l'accès (R-18, R-29).

[FINOPS] Note de coût. Je propose 4/5 pour les trois options au lieu de 5/5,
par cohérence avec BENCH-012. Sur le PC, il n'y a ni licence ni service
payant, et la mémoire et le volume sont comptés en 5.6. La réserve porte sur
le cloud. Comme Keycloak dans BENCH-012, l'option elle-même peut tourner sur
GKE si l'ADR-014 retient la voie du `managed_gap`, avec un pod facturé à
l'heure, et la voie du relais ouvre une facture hors de GCP. Le coût ne
départage pas : sans rafale, les trois options tiennent dans le même minimum
d'Autopilot, et avec la rafale elles ne diffèrent que de quelques dizaines de
centimes par mois. Les totaux passeraient à 84, 70 et 64, avec les mêmes
écarts de 14 et 20 points.

[FINOPS] Empreinte. La règle donne bien 4/5, 4/5 et 3/5, mais elle ne voit pas
la hauteur des écarts. Sur le PC, Mailpit coûte 15,1 Mo et 15,3 Mio de pod,
maildev 74,9 Mo et 59,2 Mio, smtp4dev 176,9 Mo et 118,9 Mio. Pour le critère
des 15 minutes comme pour le portable de 8 Gio, Mailpit est le moins cher des
trois, et smtp4dev serait le seul à coûter un palier de VM.

[FINOPS] D'accord. Le coût ne départage pas, et le verdict tient sur la
maturité, l'activité, la sécurité et l'expérience dev, avec 14 points d'écart.
Sur le PC, Mailpit est en plus le moins cher. Trois conditions pour l'ADR-014
: R-04 et ENF-01 passent à 1 802,1 Mo ; les demandes et limites de Mailpit
sont explicites ; la limite de Keycloak est fixée sous 1 240 Mi environ et
mesurée sur le golden repo, pic de démarrage compris, sinon le profil standard
demande plus de 8 Gio (question 3 de l'ADR-013). Sur GCP, côté coût,
préférence pour ne rien déployer : 0 USD, aucune ressource nouvelle, aucun
mail applicatif à capter dans le MVP. Si [ARCHI] retient Mailpit sur GKE : une
réplique, des demandes explicites au minimum avec la rafale, aucune exposition
publique, un budget validé avant tout apply.

[FINOPS] Questions ouvertes : la lecture d'une couche dans le bruit (majorant
pour la note, pod pour le dimensionnement) est une proposition, à confirmer
par Lucas pour les rapports suivants ; « per GB » (Go ou Gio, 2 % d'écart) ;
facturation des mails d'Identity Platform et accès à un hôte SMTP privé
inconnus ; mémoire de Mailpit avec beaucoup de mails non mesurée.

[BENCH] Suite donnée. Les corrections 1 à 16 de [SECU] et 1 à 13 de [FINOPS]
sont intégrées dans les sections 1 à 9, avec la grille réconciliée par le DSI
le 2026-11-24 : Mailpit 81, maildev 70, smtp4dev 64 (section 6). Chaque
relecture a calculé ses totaux sans la correction de l'autre : 82, 71 et 65
pour [SECU], retirés de sa ligne par le DSI ; 84, 70 et 64 pour [FINOPS], dont
les écarts de 14 et 20 points valent 11 et 17 dans la grille réconciliée. La
sensibilité de la section 7 est recalculée sur cette grille : 84 avec
l'adoption de Mailpit comptée en preuve directe, 79 en comptant ses avis,
maildev à 72 avec une politique 3.x lue comme une rupture. Les sources de
[SECU] gardent leurs numéros, S66 à S72 ; celles de [FINOPS], qu'elle
numérotait S66 à S69, deviennent S73 à S76, renvois compris dans ses
paragraphes ci-dessus, en 5.9 et en section 8. La réserve de [FINOPS] sur les
ressources prend le numéro 10, après les réserves 7 à 9 de [SECU].

[BENCH] Script et seuils. La correction 17 de [SECU] passe par un commit à
part, après celui qui garde le script mesuré. Avant la relecture, le script
versionné a pour SHA-256
`30f6f4d7923442ca5551adce29c225aacd98349cf7bd98e2f269662c3ca23e09`. C'est le
contenu du commit en place pendant la série : le dernier changement du script
date du 2026-11-23 à 22:05:07 UTC, et la série a démarré à 22:42:38 UTC. La
série ne relève pas le condensat du script lui-même, seulement ceux des 14
fichiers de `tests/bench/bench-013/` (`manifests.tsv`), tous égaux à ceux du
dépôt. Après la correction 17, qui ne touche que des commentaires, le script a
pour SHA-256
`b895830cc052bf17645c12eb751b43e6490deb79d3d78d08f7882edaa53c884a`.
La section 4.1 n'a pas bougé : son SHA-256 vaut toujours
`2d22574e54d5f817d73e5efdb069b794d66c935bc29f59d8b2cc68538f540346`.

[BENCH] Les numéros de ligne cités par les deux relectures renvoient au
rapport d'avant la relecture, dont les commentaires du gabarit sont retirés
depuis ; la ligne 408 du script citée par [SECU] est devenue la 410. La plage
`55b53af..9329120` scannée par [SECU] date d'avant le rebase de la branche sur
`a341d35`, le 2026-11-24 : les sept commits y gardent les mêmes changements.
Les points que [SECU] n'a pas vérifiés restent ouverts ; les deux premiers
entrent dans ses conditions 2 et 4. Reste aussi la question de [FINOPS] sur la
lecture d'une couche plus petite que le bruit (majorant pour la note, pod pour
le dimensionnement), à confirmer par Lucas pour les rapports suivants.
