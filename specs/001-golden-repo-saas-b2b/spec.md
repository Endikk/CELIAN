# Feature Specification: Golden repo SaaS B2B

**Feature Branch**: `docs/spec-golden-repo`

**Created**: 2026-11-20

**Status**: Draft

**Input**: User description: "Golden repo SaaS B2B de la phase 2, construit à la main dans golden/saas-b2b/ avant toute mise en template Copier. C'est le projet de référence que le blueprint saas-b2b reproduira : une API .NET (contrôle de santé et un exemple qui utilise Postgres et le cache), un front React, Postgres et un cache Valkey. Cible PC : `task up` démarre tout dans le cluster kind (ADR-004) sans outil de boucle (ADR-006), expose l'API et le front en 127.0.0.1 par Envoy Gateway (ADR-005), crée les Secrets avec des valeurs aléatoires par un tube vers kubectl create (ADR-007), choisit un profil selon la RAM ; le profil lite n'embarque pas GitOps, le profil standard sert de mesure au critère des 15 minutes (décisions de Lucas du 2026-11-20). Cible GCP : code OpenTofu écrit à la main sur GKE Autopilot, Cloud SQL, Memorystore, synchronisation des secrets de GKE, Config Sync (ADR-007, 008, 010), validé par tofu validate, conftest et Trivy, sans plan ni apply. Le dépôt porte les conventions Git complètes (commitlint, pre-commit, release-please, Renovate) et une CI qui passe. Postgres local attend BENCH-011 ; le démarrage hors réseau attend BENCH-010. Gate de la phase : démo de `task up` sur un poste propre, temps et volume mesurés (R-04)."

Le golden repo est le projet de référence que CELIAN générera plus tard. Il se
construit à la main avant toute mise en template, pour que le blueprint reproduise
un dépôt qui a déjà fonctionné. Les choix de technos sont faits : les ADR-001 à
ADR-010, acceptés à la GATE 1 du 2026-11-20, puis les ADR-011 et ADR-012,
acceptés par Lucas le 2026-11-21, les fixent. Cette spécification dit
ce que le dépôt doit permettre et comment on le vérifie ; le plan dira comment le
construire.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Démarrer le projet sur son poste en une commande (Priority: P1)

Une développeuse clone le dépôt sur son portable, macOS ou Linux, avec les
prérequis listés dans le README. Elle lance une seule commande. L'API, le front,
la base de données et le cache démarrent dans le cluster local, et la commande
affiche les adresses où les joindre. Elle modifie le code de l'API ou du front,
relance la reconstruction, et voit son changement. Elle arrête tout par une
commande documentée.

**Why this priority**: c'est la promesse du produit (principe VII, US-005) et le
gate de la phase. Sans elle, le golden repo ne prouve rien.

**Independent Test**: sur un poste propre, cloner, lancer la commande de
démarrage, puis appeler le contrôle de santé de l'API et la page d'accueil du
front aux adresses affichées.

**Acceptance Scenarios**:

1. **Given** un poste aux prérequis du README, sans cluster existant, **When** la développeuse lance la commande de démarrage, **Then** l'API, le front, la base et le cache sont prêts sans autre étape, et la commande affiche les adresses locales de l'API et du front.
2. **Given** l'environnement démarré, **When** elle appelle le contrôle de santé de l'API et la page d'accueil du front, **Then** les deux répondent, et l'exemple de l'API lit et écrit dans la base et dans le cache.
3. **Given** une modification du code de l'API, **When** elle lance la commande de rechargement, **Then** la nouvelle version répond, sans redémarrer la base ni perdre ses données.
4. **Given** l'environnement démarré, **When** elle lance la commande d'arrêt, **Then** l'application est supprimée, et la commande dit ce qui reste sur le poste.
5. **Given** la commande de démarrage terminée, **When** on relève les adresses en écoute sur le poste, **Then** rien n'écoute ailleurs qu'en boucle locale.

---

### User Story 2 - Démarrer avec des secrets propres à chaque poste (Priority: P1)

Chaque environnement local reçoit ses propres mots de passe, tirés au hasard au
premier démarrage. Aucun n'est écrit dans le dépôt, dans un fichier du projet ni
dans une commande visible par les autres processus.

**Why this priority**: un identifiant par défaut partirait dans chaque projet
généré et pourrait atteindre la cible cloud (R-20). C'est une condition de
sécurité, au même rang que le démarrage.

**Independent Test**: démarrer deux environnements neufs et comparer leurs
valeurs secrètes ; chercher les valeurs dans le dépôt, les fichiers du projet et
l'historique des commandes.

**Acceptance Scenarios**:

1. **Given** deux environnements neufs, **When** chacun démarre, **Then** aucune valeur secrète n'est commune aux deux, et chacune fait au moins 32 caractères.
2. **Given** un environnement démarré, **When** on cherche ses valeurs secrètes dans le dépôt et dans les fichiers du projet, **Then** on ne les trouve pas.
3. **Given** un environnement déjà démarré, **When** la commande de démarrage est relancée, **Then** les secrets existants sont gardés, et les données restent lisibles.

---

### User Story 3 - Préparer la cible cloud sans rien dépenser (Priority: P2)

Un tech lead veut savoir si le code d'infrastructure de la cible cloud est prêt,
sans créer la moindre ressource payante. La CI le valide, contrôle les
politiques de sécurité et le scanne, sans identifiant cloud ni déploiement.

**Why this priority**: la cible cloud fait partie du critère d'acceptation du
MVP, mais son premier déploiement réel attend l'accord explicite de Lucas et un
budget (principe X, décision du 2026-11-20). La phase 2 livre un code vérifié,
pas un déploiement.

**Independent Test**: ouvrir une PR qui touche le code de la cible cloud et
constater que la validation, le contrôle des politiques et le scan passent, sans
qu'aucune commande ne contacte le fournisseur.

**Acceptance Scenarios**:

1. **Given** le code de la cible cloud, **When** la CI tourne, **Then** la validation, le contrôle des politiques et le scan passent.
2. **Given** une modification qui enfreint une condition de l'ADR-008 vérifiable sans cloud, par exemple un module tiré par tag, **When** la CI tourne, **Then** elle échoue en nommant la condition.
3. **Given** toute exécution de la CI de la phase, **When** on relit ses journaux, **Then** aucune commande de plan, de création ni de destruction de ressources n'a tourné, et aucun identifiant cloud n'était présent.

---

### User Story 4 - Contribuer selon les conventions du projet généré (Priority: P2)

Un contributeur ouvre une PR sur le golden repo. Les mêmes contrôles tournent sur
son poste et en CI : format des messages de commit, hooks, recherche de secrets,
tests. Les versions sont tenues automatiquement, et les mises à jour de
dépendances arrivent par PR.

**Why this priority**: le PRD veut des conventions Git complètes dans le projet
généré. Le golden repo est l'endroit où elles sont prouvées avant d'être mises en
template.

**Independent Test**: ouvrir une PR avec un message de commit non conforme, puis
une PR conforme, et comparer les résultats de la CI.

**Acceptance Scenarios**:

1. **Given** un message de commit non conforme, **When** le contributeur commite, **Then** le hook local refuse, et la CI refuse aussi le titre de PR non conforme.
2. **Given** une PR conforme, **When** la CI tourne, **Then** les hooks, la recherche de secrets, les tests unitaires de l'API et du front, et le test de démarrage de bout en bout passent.
3. **Given** une dépendance publiée depuis moins de 7 jours, **When** l'outil de mise à jour passe, **Then** il n'ouvre pas de PR, sauf pour un correctif de sécurité (principe VI, constitution 1.2.0).

---

### User Story 5 - Servir de modèle fidèle au blueprint (Priority: P3)

En phase 3, l'architecte transforme le golden repo en template. Il doit retrouver
une séparation nette entre ce qui est commun aux deux cibles et ce qui est propre
à chacune, et un code d'exemple réduit au minimum.

**Why this priority**: c'est la raison d'être d'un golden repo, mais sa valeur se
réalise à la phase suivante.

**Independent Test**: rendre les manifests de l'application pour le PC et pour la
cible cloud, et comparer.

**Acceptance Scenarios**:

1. **Given** les rendus des deux cibles, **When** on les compare, **Then** ils ne diffèrent que par la couche de cible, et la couche commune ne contient aucun objet propre à un fournisseur ou à un outil.
2. **Given** le code de l'application, **When** on l'inventorie, **Then** il se limite au contrôle de santé, à l'exemple qui utilise la base et le cache, et au front qui les affiche (Q7).

---

### User Story 6 - Redémarrer sans réseau après un premier lancement (Priority: P3)

Après un premier démarrage avec réseau, la développeuse arrête puis relance
l'environnement sans accès aux registres publics, dans un train ou derrière un
réseau d'entreprise qui bloque Docker Hub.

**Why this priority**: les ADR-004, 005 et 006 en font une condition (R-25).
BENCH-010 a rendu son verdict, et l'ADR-011, accepté par Lucas le 2026-11-21,
fixe le mécanisme. Le récit reste en P3 : le critère des 15 minutes compte le
premier démarrage, qui demande le réseau de toute façon.

**Independent Test**: premier démarrage avec réseau, arrêt, puis démarrage sans
accès aux registres, jusqu'à l'état prêt.

**Acceptance Scenarios**:

1. **Given** un premier démarrage réussi avec réseau, **When** l'environnement est relancé sans accès aux registres publics, **Then** il atteint l'état prêt.
2. **Given** un premier démarrage réussi avec réseau, puis la suppression du cluster local, **When** la commande de démarrage est relancée sans accès aux registres publics, **Then** le cluster est recréé et l'environnement atteint l'état prêt.
3. **Given** un environnement déjà démarré une fois avec réseau, **When** la développeuse lance la commande documentée qui retire du poste ce que garde le démarrage pour le redémarrage hors réseau, **Then** la commande dit, avant d'agir, que le démarrage suivant demandera le réseau, puis ne laisse rien de ce stockage sur le poste.

---

### User Story 7 - Connaître le contenu des images et bloquer les failles connues (Priority: P2)

Un tech lead veut savoir de quoi sont faites les images de la stack, et refuser
qu'une faille connue d'une gravité donnée arrive sur la branche principale. La
CI produit le SBOM de chaque image qu'elle construit, c'est-à-dire la liste de
ses composants et de leurs versions. Elle scanne toutes les images que la stack
fait tourner, et bloque la fusion dès qu'une vulnérabilité atteint le seuil
écrit dans le dépôt, sauf exception datée et justifiée.

**Why this priority**: le PRD veut une CI qui produit un SBOM et scanne les
images (US-009, ENF-03), et l'ADR-011 fait entrer l'image du miroir de registres
dans ce scan (condition 8, R-34). Décision de Lucas du 2026-11-21. Le démarrage
passe avant, mais une faille connue qui passe en silence partirait dans chaque
projet généré.

**Independent Test**: ouvrir une PR qui ajoute une image porteuse d'une
vulnérabilité connue qui atteint le seuil et constater le refus ; ajouter une
exception justifiée et datée et constater le passage ; passer sa date
d'échéance et constater de nouveau le refus.

**Acceptance Scenarios**:

1. **Given** une PR conforme, **When** la CI construit les images, **Then** chaque image construite a son SBOM, gardé avec l'exécution de la CI.
2. **Given** l'environnement démarré dans chaque profil livré, **When** le contrôle relève les images en marche, dans le cluster et sur le moteur du poste, **Then** chacune figure parmi les images scannées, et le contrôle échoue sur toute image absente du scan.
3. **Given** une image porteuse d'une vulnérabilité qui atteint le seuil écrit dans le dépôt, sans exception, **When** la CI tourne, **Then** le scan échoue en nommant l'image et la vulnérabilité, et la PR ne peut pas fusionner.
4. **Given** la même vulnérabilité couverte par une exception complète et non échue, **When** la CI tourne, **Then** le scan passe.
5. **Given** une exception échue ou incomplète, **When** la CI tourne, **Then** le scan échoue de nouveau sur la vulnérabilité visée.

---

### Edge Cases

- Le poste déclare moins de mémoire que ce qu'exige le profil standard : le démarrage choisit le profil lite et le dit, ou refuse avec un message qui dit combien de mémoire manque.
- Un port local voulu est déjà pris : le démarrage s'arrête avant de créer quoi que ce soit, en nommant le port.
- Le moteur de conteneurs est absent, arrêté ou d'une version non prise en charge : message clair, rien de créé.
- Un registre public répond mal ou limite les tirages : le démarrage échoue en le disant, sans rester bloqué sans fin, et la durée d'attente est bornée.
- Un environnement existe déjà : le démarrage le reprend, garde ses secrets et ses données, ou refuse en expliquant.
- Le poste est en arm64 : même résultat qu'en amd64.
- Un contexte de cluster cloud est configuré sur le poste : aucune commande du dépôt ne s'y adresse ; le démarrage local cible explicitement le cluster local (décision de la GATE 1 : aucun contexte GKE sur le poste avant la GATE 2).
- La base de vulnérabilités du scan est injoignable : le scan échoue en le disant, sans passer au vert.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Le dépôt MUST démarrer l'API, le front, la base et le cache dans le cluster local par une seule commande, sans autre étape (principe VII, US-005, ADR-006).
- **FR-002**: La commande de démarrage MUST afficher les adresses locales de l'API et du front, joignables en boucle locale uniquement, au travers de la gateway (ADR-005).
- **FR-003**: Les composants du dépôt MUST écouter uniquement en boucle locale sur le poste ; un test le vérifie après chaque démarrage (R-20).
- **FR-004**: Le dépôt MUST créer les secrets locaux au premier démarrage, avec des valeurs aléatoires d'au moins 32 caractères, sans les écrire dans un fichier, dans une variable affichée ni dans un argument de commande, et les garder aux démarrages suivants (ADR-007, R-20).
- **FR-005**: Un test MUST démarrer deux environnements neufs et échouer si une valeur secrète se répète, fait moins de 32 caractères ou figure dans une liste de valeurs connues (ADR-007, condition 1).
- **FR-006**: Le dépôt MUST choisir un profil selon la mémoire que déclare le moteur de conteneurs. Le profil lite MUST NOT embarquer l'outil GitOps ; le profil standard sert de mesure au critère des 15 minutes. Le profil standard ajoute au profil lite l'outil GitOps (Flux, ADR-010), un fournisseur d'identité (Keycloak) et un serveur de mails de test (Mailpit) : décision de Lucas du 2026-11-20. Keycloak et Mailpit entrent dans le golden repo après leurs benchmarks.
- **FR-007**: Le dépôt MUST fournir une commande de rechargement, qui reconstruit et redéploie le composant modifié sans toucher aux données, et une commande d'arrêt documentée (US-005, ADR-006).
- **FR-008**: Chaque image et chaque dépendance tirées d'un registre MUST être figées par condensat ou par somme de contrôle ; un contrôle refuse toute référence par tag (ADR-004, condition 3).
- **FR-009**: Le code de l'application MUST se limiter au contrôle de santé, à un exemple qui lit et écrit dans la base et dans le cache, et au front qui l'affiche (Q7).
- **FR-010**: Le dépôt MUST séparer une couche commune, identique sur les deux cibles, d'une couche par cible ; un test compare les rendus des deux cibles et échoue si l'écart sort de la couche de cible ou si la couche commune contient un objet propre à un outil ou à un fournisseur (ADR-005, condition 5 ; ADR-010).
- **FR-011**: Le code de la cible cloud MUST passer la validation, le contrôle des politiques et le scan en CI, sans plan, sans création ni destruction de ressources, et sans identifiant cloud (principe X, ADR-008).
- **FR-012**: Les conditions de l'ADR-008, de l'ADR-007 et de l'ADR-010 vérifiables sans cloud MUST être contrôlées en CI, chacune par un contrôle qui la nomme en cas d'échec.
- **FR-013**: Le dépôt MUST porter les conventions Git du projet généré : messages de commit vérifiés en local et en CI, mêmes hooks en local et en CI, recherche de secrets sur tout l'historique, versions tenues automatiquement, mises à jour de dépendances par PR après 7 jours sauf correctif de sécurité, actions de CI figées par SHA.
- **FR-014**: La CI MUST faire tourner les tests unitaires de l'API et du front, et un test de bout en bout qui démarre l'environnement sur un runner amd64 et appelle l'API et le front au travers de la gateway.
- **FR-015**: La commande de démarrage MUST mesurer et afficher la durée de chaque étape et la durée totale ; la démo relève aussi le volume téléchargé au premier démarrage (R-04).
- **FR-016**: Après un premier démarrage avec réseau, un démarrage sans accès aux registres publics MUST atteindre l'état prêt dans chaque profil livré, y compris quand le cluster local a été supprimé entre-temps (ADR-004, condition 7 ; R-25). La commande de démarrage MUST mettre en place elle-même ce qui le permet, sans autre étape (principe VII). Ce qu'elle garde sur le poste pour ce redémarrage MUST rester hors de l'arborescence du projet, et n'être jamais versionné ni publié. Une commande documentée MUST le retirer du poste, en disant avant d'agir que le démarrage suivant demandera le réseau. Le mécanisme est celui de l'ADR-011 (décision de Lucas du 2026-11-21) ; ses conditions vérifiables automatiquement MUST être contrôlées en CI, chacune par un contrôle qui la nomme en cas d'échec, dont un test qui joue ce redémarrage, cluster recréé, dans chaque profil livré (ADR-011, conditions 1 et 10 ; R-34).
- **FR-017**: La base de données locale MUST tourner dans le cluster local sans aucun composant qui obtienne des droits sur l'API du cluster, sous la forme et les conditions de l'ADR-012 (décision de Lucas du 2026-11-21). Elle MUST avoir la même version majeure que la base de la cible cloud, et l'utilisateur de l'application MUST NOT y être superutilisateur, puisque la cible cloud n'en donne pas (ENF-02, R-35). Les conditions de l'ADR-012 vérifiables sans cloud MUST être contrôlées en CI, chacune par un contrôle qui la nomme en cas d'échec.
- **FR-018**: Le README MUST lister les prérequis avec leur version, licence et date, citer d'abord un moteur de conteneurs libre (R-26), lister les écarts entre le PC et la cible cloud (ENF-02), et dire que les secrets locaux sont en clair dans le cluster (R-28).
- **FR-019**: Les commandes du dépôt MUST cibler explicitement le cluster local ; aucune ne s'adresse à un cluster cloud pendant cette phase.
- **FR-020**: La CI MUST produire, pour chaque image qu'elle construit, un SBOM lisible par machine, qui liste les composants de l'image et leurs versions, et le garder comme artefact de son exécution (US-009, ENF-03, Q9 ; décision de Lucas du 2026-11-21).
- **FR-021**: La CI MUST rechercher les vulnérabilités connues dans chaque image de l'inventaire des images : celles qu'elle construit, celles que le cluster local tire d'un registre dans chaque profil livré, et celles que la commande de démarrage lance sur le moteur du poste, image du miroir de registres comprise (ADR-011, condition 8 ; R-34). Un contrôle MUST relever les images en marche après le démarrage de chaque profil livré, dans le cluster et sur le moteur du poste, y compris celles qu'aucun manifest du projet ne nomme, et échouer sur toute image absente du scan (décision de Lucas du 2026-11-21).
- **FR-022**: Une vulnérabilité dont la gravité atteint ou dépasse le seuil écrit dans le dépôt MUST faire échouer le scan et bloquer la fusion de la PR, sauf exception écrite dans le dépôt. Chaque exception MUST nommer la vulnérabilité et l'image visées, et porter sa justification, sa date d'écriture et sa date d'échéance ; une exception échue ou incomplète MUST NOT être prise en compte (décision de Lucas du 2026-11-21).

### Key Entities *(include if feature involves data)*

- **Environnement local**: un cluster sur le poste, avec ses secrets, ses données et son profil ; il naît au premier démarrage et disparaît à la suppression.
- **Profil**: l'ensemble des briques démarrées ; lite ou standard, choisi selon la mémoire déclarée.
- **Couche**: commune, locale ou cloud ; seule une couche de cible diffère d'une cible à l'autre.
- **Secret local**: une valeur aléatoire propre à un environnement, jamais versionnée.
- **Exemple de l'application**: une donnée écrite et relue dans la base, et mise en cache, que le front affiche.
- **Inventaire des images**: toutes les images qu'un profil livré fait tourner : celles que la CI construit, celles que le cluster local tire d'un registre, et celles que la commande de démarrage lance sur le moteur du poste, dont l'image du nœud du cluster et celle du miroir de registres.
- **Exception au scan**: une vulnérabilité admise malgré le seuil, écrite dans le dépôt avec l'image visée, sa justification, sa date d'écriture et sa date d'échéance.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Sur un poste propre aux prérequis du README, une personne qui ne connaît pas le dépôt obtient l'API et le front qui répondent avec une seule commande, sans autre intervention, dans 100 % des essais de la démo.
- **SC-002**: La durée et le volume du premier démarrage complet en profil standard sont mesurés, affichés et rapportés au budget de 15 minutes, au débit visé que fixera [FINOPS] (R-04).
- **SC-003**: Un démarrage à chaud, environnement existant, atteint l'état prêt en moins de 90 secondes.
- **SC-004**: Deux environnements neufs ne partagent aucune valeur secrète, dans 100 % des essais.
- **SC-005**: Aucun service n'est joignable depuis une autre machine du réseau local : 0 adresse en écoute hors boucle locale.
- **SC-006**: Chaque PR de la phase passe la CI, et la cible cloud passe ses trois contrôles sans qu'aucune ressource payante ne soit créée : 0 euro dépensé.
- **SC-007**: Les rendus des deux cibles ne diffèrent que dans la couche de cible : 0 écart dans la couche commune.
- **SC-008**: Le profil lite tient sur un portable de 8 Gio de mémoire.
- **SC-009**: Après un premier démarrage avec réseau, un redémarrage sans accès aux registres publics, cluster local supprimé puis recréé, atteint l'état prêt dans chaque profil livré : 100 % des passages du test de FR-016 (ADR-011).
- **SC-010**: Sur chaque exécution de la CI du golden repo : 0 image construite sans SBOM, 0 image en marche absente du scan, et 0 PR fusionnée avec une vulnérabilité qui atteint le seuil sans exception valide.

## Assumptions

- Les choix de technos sont ceux des ADR-001 à ADR-010, acceptés à la GATE 1 du 2026-11-20, et des ADR-011 et ADR-012, acceptés par Lucas le 2026-11-21 : cluster kind, Envoy Gateway, aucun outil de boucle, Secrets natifs, OpenTofu écrit à la main sur GKE Autopilot, Flux sur le PC et Config Sync sur GKE, miroir de registres local lancé par la commande de démarrage, Postgres local sans opérateur. Le plan les nomme ; cette spécification n'y revient pas.
- La stack applicative suit le brief (section 6) : une API .NET, un front React, Postgres et un cache Valkey. Chaque version est lue sur sa source officielle et datée avant usage (principe VIII).
- BENCH-010 et BENCH-011 sont rendus. Le redémarrage hors réseau suit l'ADR-011, la base locale l'ADR-012. Leurs points non mesurés se vérifient sur le golden repo, et un échec suit la condition de révision de l'ADR concerné.
- Comme dans BENCH-010, le test de FR-016 coupe les registres publics pour le seul cluster : le poste garde son réseau, et la construction de l'API et du front avec lui. Le redémarrage sur un poste réellement coupé du réseau, construction comprise, reste à vérifier ; l'ADR-011 confie cet essai à Lucas.
- Le SBOM et le scan des images entrent dans cette spécification par décision de Lucas du 2026-11-21 (US-009, ENF-03). La signature des images et le contrôle d'admission qui refuse les images non signées (Kyverno) en restent hors : ils arrivent en phase 4. D'ici là, la dérogation datée de l'ADR-012 pour les images officielles de Docker n'a pas d'effet.
- Le plan fixe l'outil de scan et celui du SBOM, le format du SBOM et la valeur du seuil de gravité. Le SBOM reste un artefact de la CI, sans serveur d'analyse (Q9). Q8, où publier et signer les images avant que GCP existe, n'est pas tranchée ; FR-020 n'en dépend pas.
- Le débit visé du critère d'acceptation sera fixé par [FINOPS] après le golden repo (décision de la GATE 1).
- Aucun déploiement réel sur la cible cloud pendant la phase 2 (décision de Lucas du 2026-11-20) ; le premier se fera avec son accord explicite et un budget, après sa lecture des grilles tarifaires.
- Systèmes visés : macOS et Linux (Q5) ; Windows reste hors périmètre.
- Le golden repo vit dans `golden/saas-b2b/` du dépôt de CELIAN, et sa CI tourne dans ce dépôt.
- Le profil standard comprend Keycloak et Mailpit (décision de Lucas du
  2026-11-20). Aucun benchmark ne les a encore traités : chacun passe par un
  benchmark avant d'entrer dans le golden repo, comme Postgres local
  (BENCH-011).
