# PRD du MVP de CELIAN

Statut : validé par Lucas à la GATE 0 le 15/11/2026, questions Q1 à Q12
comprises. Rédigé par [PO] le même jour.

Sources : brief v1.0 (sections 2 à 4, 6, 8, 9 et 12), constitution 1.0.0
(branche `chore/speckit`) et `CLAUDE.md`, lus le 15/11/2026. La vision tient en
une page dans [vision.md](vision.md).

Ce document dit ce que le MVP doit faire et comment vérifier qu'il le fait. Les
choix de technos reviennent à [ARCHI] et [BENCH] ; un choix encore ouvert est
signalé avec le benchmark de phase 1 qui le tranchera.

## 1. Contexte et problème

Démarrer un projet professionnel sur un socle propre prend des semaines (brief,
section 2). Chaque équipe refait le même travail, des choix de technos à la
documentation en passant par l'infrastructure, la CI/CD et la sécurité, et le
mène rarement jusqu'au bout. Le socle dérive ensuite, faute de quelqu'un pour
le maintenir.

Le persona du MVP a deux options aujourd'hui. Soit il consacre ces semaines au
socle avant la première fonctionnalité. Soit il démarre avec le minimum et paie
plus tard : environnement local différent de la production, infrastructure
créée à la main dans la console, pas de CI, sécurité ajoutée après coup.
CELIAN veut lui donner en quelques minutes un socle complet, qu'il comprend et
qui se maintient.

Le produit est un plugin Claude Code (skills et sous-agents) qui pilote une
petite CLI Python. Le plugin porte l'entretien et la partie écrite par l'agent.
La CLI porte le déterministe : validation de la spec, traduction par le
catalogue, génération et vérifications.
Cette répartition, à confirmer par [ARCHI], permet de tester toute la partie
déterministe sans modèle de langage, dans la matrice de validation.

```text
Entretien guidé (cible, type de projet, contraintes)
  |
  v
Spec projet YAML (source de vérité, versionnée, validée)
  |
  v
Blueprint SaaS B2B (IaC, Kubernetes, CI, Git, docs)   déterministe
  |
  v
Agent (ADR, textes du projet)                         IA
  |
  v
Validation automatique                                si échec, retour à l'agent
  |
  v
Dépôt livré, mis à jour ensuite depuis le blueprint
```

Les choix suivants restent ouverts. L'option pressentie vient du brief et ne
vaut décision qu'après le benchmark et son ADR. Le reste de la stack du
blueprint (brief, section 6) sert de point de départ, chaque version étant
vérifiée et datée en phase 1 (principe VIII).

| Choix | Option pressentie | Tranché par |
| --- | --- | --- |
| Format de la spec | YAML validé par un JSON Schema rangé dans `schema/` | BENCH-001 (YAML et JSON Schema, CUE, Pkl) |
| Moteur de templates | Copier | BENCH-002 (Copier, Cookiecutter, Yeoman) |
| Cluster local | k3d | BENCH-003 (k3d, kind, minikube) |
| Gateway | Envoy Gateway | BENCH-004 (Envoy Gateway, Cilium, Traefik) |
| Orchestration dev locale | Aspire | BENCH-005 (Aspire, Tilt, Docker Compose) |
| Langage de la CLI | Python, retenu dans la forme du produit | BENCH-006 (Python, TypeScript) |
| Secrets locaux | OpenBao | BENCH-007 (OpenBao et alternatives) |

## 2. Personas

Les deux personas sont des hypothèses de travail tirées du brief. Aucun
entretien utilisateur n'a été mené. Ils décrivent des rôles et des situations.

### Persona principal : le dev ou tech lead qui lance un projet

Dans une PME, il lance un nouveau produit avec une petite équipe, sans équipe
plateforme, et porte les choix d'infrastructure en plus du code. Dans une ESN,
il démarre un projet pour un client : il doit poser vite un socle qu'il saura
défendre, puis le transmettre à l'équipe qui le maintiendra.

Il maîtrise le développement applicatif et Git. Kubernetes, OpenTofu ou la
chaîne d'approvisionnement ne sont pas forcément son terrain. Il attend un
dépôt qui démarre du premier coup, des choix qu'il peut expliquer, une facture
cloud qu'il contrôle et un socle qui ne vieillit pas sans lui. Deux choses le
feraient abandonner : un premier lancement qui casse, ou une facture qu'il n'a
pas vue venir.

Prérequis supposés : Claude Code installé, un compte GitHub, un projet GCP avec
facturation active, un PC capable de faire tourner le cluster local. Les
ressources nécessaires sur ce PC sont à mesurer en phase 1.

### Persona secondaire : le développeur qui rejoint un projet généré

Il n'a pas répondu à l'entretien. Il clone le dépôt des semaines plus tard, sur
un poste où CELIAN n'est pas forcément installé, et tout ce qu'il reçoit passe
par ce dépôt. Il a besoin d'un README qui liste les prérequis, d'une commande
pour tout démarrer, et d'ADR qui expliquent les choix. D'où une exigence : le
projet généré fonctionne sans CELIAN (ENF-07).

## 3. Parcours utilisateur du MVP

Les noms de commandes autres que `task up` et `copier update` se fixent en
phase 5.

1. Installation. L'utilisateur installe le plugin et la CLI. Le mode de
   distribution, dépôt privé compris, se décide avec [DEV].
2. Lancement. Il lance la commande d'entrée. CELIAN vérifie les prérequis. Le
   chronomètre du critère d'acceptation part ici.
3. Entretien. Une dizaine de questions, chacune avec une valeur par défaut.
   Liste candidate, fixée en phase 5 : nom et description du projet, cible (PC
   seul, ou PC et GCP), projet et région GCP, compte GitHub, propriétaires du
   code, profil de ressources local, licence du projet, plafond de l'alerte
   budget GCP.
4. Spec. CELIAN écrit la spec, la valide contre le schéma de `schema/` et la
   montre. L'utilisateur peut la corriger.
5. Génération. La CLI génère le dépôt depuis le blueprint SaaS B2B et le
   catalogue. L'agent écrit ensuite les ADR et le contenu propre au projet.
6. Validation. Les vérifications tournent, démarrage local compris. En cas
   d'échec, l'agent corrige et relance.
7. Livraison. Le dépôt reçoit un premier commit conforme et part sur GitHub, où
   la CI tourne. `task up` relance la stack locale à tout moment.
8. Déploiement GCP. CELIAN montre le plan OpenTofu et signale les ressources
   payantes. L'utilisateur lance lui-même l'apply.
9. Jour 2. À chaque nouvelle version du blueprint, l'utilisateur met son projet
   à jour et relit les changements avant de les fusionner.

## 4. User stories

Les critères se testent automatiquement quand c'est possible, sinon pendant le
test de phase 6.

### US-001 Installer CELIAN et vérifier les prérequis

En tant que tech lead, je veux savoir dès le lancement s'il manque un outil sur
mon poste, afin de ne pas le découvrir au milieu de la génération.

- Étant donné un poste où un prérequis manque, quand l'utilisateur lance la
  commande d'entrée, alors CELIAN le nomme, renvoie vers sa documentation
  officielle d'installation et ne commence pas l'entretien.
- Étant donné un poste conforme, quand il lance la commande, alors l'entretien
  démarre sans autre action.
- La liste vérifiée reprend celle du README de CELIAN, et un test contrôle que
  les deux concordent.

### US-002 Répondre à l'entretien guidé

En tant que tech lead, je veux décrire mon projet en quelques questions, afin
d'obtenir un socle adapté sans connaître chaque techno.

- Le parcours par défaut tient en une dizaine de questions, comptées pendant le
  test de phase 6.
- Chaque question propose une valeur par défaut et dit en une phrase ce que la
  réponse change.
- Aucune question ne demande un secret (mot de passe, jeton, clé). La liste est
  relue sur ce point avant la GATE 5.
- L'utilisateur peut changer une réponse avant la génération sans recommencer
  l'entretien.
- Étant donné une demande hors MVP (AWS, Azure, on-prem, cloud souverain,
  blueprint data, IoT ou mobile), quand elle arrive pendant l'entretien, alors
  CELIAN répond que le MVP ne la couvre pas et propose ce qui est disponible.

### US-003 Obtenir une spec abstraite et validée

En tant que tech lead, je veux que mes réponses deviennent une spec vérifiée,
afin d'avoir une source de vérité que je peux versionner et rejouer.

- La spec ne contient que des briques abstraites (`database: postgres`). Un
  test vérifie qu'aucun nom de service du catalogue n'y figure (principe II).
- La spec porte la version du schéma qu'elle suit.
- Étant donné une spec non conforme, quand la CLI la valide, alors elle refuse,
  nomme le champ fautif et la raison, et ne génère rien.
- Le schéma refuse toute cible absente de la matrice de validation : seules PC
  et GCP passent dans le MVP (principe I).
- La validation tourne avec la CLI seule. Les exemples de spec prévus en phase 3
  la passent dans la CI du générateur.

### US-004 Générer le dépôt depuis le blueprint SaaS B2B

En tant que tech lead, je veux un dépôt complet généré depuis ma spec, avec les
bons services pour chaque cible, afin de partir d'un socle testé.

- Étant donné une spec valide, quand la CLI génère, alors le dépôt contient
  l'API .NET, le front React, Postgres et le cache, les manifestes Kubernetes,
  la CI, les conventions Git, la documentation, et le code OpenTofu si la cible
  GCP est choisie.
- Pour chaque brique abstraite, le service généré est celui que le catalogue
  associe à la cible. Exemple du brief pour Postgres, à confirmer en phase 1 :
  CloudNativePG en local, Cloud SQL sur GCP.
- Une entrée de catalogue sans licence, gouvernance, statut, date de
  vérification ou source fait échouer la CI du générateur (principe IV).
- Deux générations depuis la même spec et la même version du blueprint donnent
  une partie déterministe identique, fichier par fichier. Les fichiers écrits
  par l'agent sont listés à part.
- Une spec modifiée à la main se régénère par la CLI sans repasser par
  l'entretien. Ajouter la cible GCP ne change pas le code applicatif.

### US-005 Démarrer le projet en local en une commande

En tant que développeur, je veux lancer tout le projet sur mon PC avec une
commande, afin de travailler dans un environnement proche de la cible.

- Étant donné un PC avec les prérequis du README du projet généré, quand le
  développeur lance `task up`, alors l'API, le front, Postgres et le cache
  démarrent dans le cluster local sans autre étape (principe VII).
- La commande affiche les adresses locales, et le contrôle de santé de l'API
  comme la page d'accueil du front répondent.
- Le profil lite, standard ou full suit la RAM disponible. Seuils à mesurer en
  phase 1 (BENCH-003, BENCH-005).
- Une commande documentée arrête et supprime l'environnement.

### US-006 Déployer sur GCP avec un accord explicite

En tant que tech lead, je veux un plan vérifié et rien de payant sans mon
accord, afin de ne jamais découvrir une facture après coup.

- Étant donné la cible GCP, quand la validation tourne, alors `tofu validate`
  et les politiques conftest passent, avec les services managés du fournisseur
  (principe III).
- Étant donné un projet GCP et les identifiants de l'utilisateur dans son
  environnement, quand il demande le plan, alors le plan s'exécute sans erreur.
  CELIAN le résume et signale les ressources payantes d'après la liste tenue
  par [FINOPS].
- L'agent ne lance jamais `tofu apply` ni aucune commande qui crée des
  ressources payantes. Une tentative est bloquée, et un test couvre ce blocage.
  L'utilisateur lance l'apply lui-même.
- Après l'apply, l'application répond à l'adresse donnée en sortie. Une
  commande documentée détruit les ressources créées.

### US-007 Valider avant la livraison et laisser l'agent corriger

En tant que tech lead, je veux un dépôt vérifié et corrigé avant qu'on me le
livre, afin de ne pas déboguer un code que je n'ai pas écrit.

- Avant la livraison, CELIAN exécute `tofu validate`, conftest, kubeconform,
  les linters, les tests et le démarrage local. Chaque vérification rend un
  résultat lisible.
- Étant donné un échec, quand la boucle de correction tourne, alors l'agent
  reçoit la sortie, corrige et relance toutes les vérifications. Le nombre
  maximal de tentatives est à définir en phase 5.
- Au-delà de cette limite, CELIAN s'arrête, dit ce qui échoue et ce qui a été
  tenté. Aucun dépôt n'est annoncé comme livré avec une vérification en échec.
- L'agent ne désactive aucune vérification ni aucun test. Un test compare leur
  configuration avant et après la boucle.
- Un échec dans la partie issue du blueprint remonte comme défaut du blueprint,
  sans correction silencieuse : le projet divergerait de son blueprint et la
  mise à jour (US-011) casserait.

### US-008 Recevoir des conventions Git complètes

En tant que tech lead, je veux des conventions Git appliquées dès le premier
commit, afin que l'équipe ne les négocie pas à l'oral.

- Le dépôt généré contient Conventional Commits vérifiés par commitlint en
  local et en CI, pre-commit avec détection de secrets, un CODEOWNERS rempli
  depuis l'entretien, un modèle de PR, release-please, Renovate et une
  protection de branche décrite en code, dont le mécanisme est à définir par
  [OPS] (brief, section 6).
- Étant donné les hooks installés, quand un développeur commite avec un message
  non conforme, alors le hook refuse le commit.
- Le premier commit du dépôt généré respecte lui-même la convention.

### US-009 Obtenir une CI verte au premier push

En tant que tech lead, je veux une CI qui passe dès le premier push, afin de
partir d'un état sain.

- Étant donné le dépôt poussé sur GitHub, quand GitHub Actions tourne pour la
  première fois, alors la CI passe.
- Elle comprend au minimum les linters, les tests, la construction des images,
  le SBOM (Syft), le scan (Trivy) et la signature (cosign).
- Une étape qui suppose l'infrastructure GCP ne fait pas échouer la CI tant que
  cette infrastructure n'existe pas.

### US-010 Trouver un ADR pour chaque choix de l'entretien

En tant que tech lead d'ESN, je veux un ADR par choix, afin de défendre
l'architecture devant mon client et de la transmettre.

- Chaque réponse qui modifie l'architecture produit un ADR dans le dépôt
  généré. La liste de ces champs se fixe avec [ARCHI].
- Un ADR donne le contexte, la décision, les options écartées et les
  conséquences. Pour une techno du catalogue, il cite sa licence, sa
  gouvernance, sa date de vérification et sa source.
- Un test vérifie que chaque champ concerné de la spec renvoie vers un ADR, et
  inversement.
- Les choix imposés par le blueprint sont expliqués par des ADR livrés et
  maintenus avec lui.

### US-011 Mettre à jour un projet généré

En tant que tech lead, je veux recevoir les correctifs du blueprint, afin que
mon socle ne vieillisse pas sans moi.

- Étant donné un projet généré avec la version N du blueprint et une version
  N+1 publiée, quand l'utilisateur lance `copier update` (si BENCH-002 confirme
  Copier), alors les changements s'appliquent sans repasser par l'entretien.
- Les modifications de l'utilisateur sont conservées hors conflit, et les
  conflits sont listés fichier par fichier.
- Les vérifications de US-007 sont relancées après la mise à jour.
- La matrice de la phase 4 couvre une mise à jour de N à N+1. BENCH-002 doit
  vérifier ce parcours pour chaque option.

### US-012 Ne trouver aucun secret dans le dépôt généré

En tant que tech lead, je veux un dépôt sans aucun secret, afin de le pousser
et de le partager sans risque.

- Un scan de secrets sur le dépôt généré, historique compris, ne trouve rien.
- Les identifiants GCP et GitHub de l'utilisateur n'apparaissent ni dans la
  spec ni dans aucun fichier généré.
- Les secrets de l'application viennent du gestionnaire de secrets de la cible
  (OpenBao en local si BENCH-007 le confirme, Secret Manager sur GCP).
- Étant donné un développeur qui tente de committer une clé, quand le hook
  pre-commit tourne, alors il refuse le commit.

## 5. Exigences non fonctionnelles

### ENF-01 Délai

Le parcours défini à la section 7 tient en moins de 15 minutes. La durée de
chaque étape est mesurée et affichée à la fin. Les budgets de temps par étape
sont à définir après les mesures de phase 1.

### ENF-02 Parité locale et empreinte

Chaque brique de la spec existe sur les deux cibles : open source sur le PC
(principe III), managée sur GCP. Seule la couche de cible change d'une cible à
l'autre (principe II), et le README généré liste les écarts restants.
L'empreinte de chaque profil est à mesurer en phase 1, le PC de référence de
la phase 6 à définir.

### ENF-03 Chaîne d'approvisionnement

Le projet généré produit un SBOM, scanne et signe ses images, et Kyverno refuse
les images non signées (brief, section 6). Ses dépendances sont figées, ses
actions épinglées par SHA comme dans le générateur, et Renovate respecte le
délai de publication du principe VI.

### ENF-04 Aucun secret

Ni le générateur ni un projet généré ne versionnent de secret (principe IX). La
détection tourne en pre-commit et en CI, sur tout l'historique. Un secret
exposé se révoque d'abord, puis l'historique se réécrit.

### ENF-05 Coût maîtrisé

Aucune ressource payante sans accord explicite, et l'agent ne peut pas lancer
la commande (US-006). Le dimensionnement GCP par défaut est le plus petit qui
fait tourner le blueprint ; [FINOPS] le fixe avec [OPS]. Le code généré déclare
une alerte budget, selon un mécanisme à confirmer par eux. Le coût réel du
déploiement par défaut est à mesurer en phase 2 sur le golden repo, après
accord de Lucas.

### ENF-06 Traçabilité

Le dépôt généré enregistre les versions de la spec, du blueprint et du
catalogue qui l'ont produit. Chaque fait technique du catalogue et des ADR est
daté et sourcé (principe VIII).

### ENF-07 Indépendance du projet généré

Un projet généré démarre, se teste et se déploie sur un poste sans CELIAN.
Seule la mise à jour demande le moteur de templates. Les systèmes
d'exploitation supportés sont à définir (Q5).

## 6. Non-objectifs du MVP

Une demande hors périmètre se refuse, se note dans `ROADMAP.md` et ne se code
pas. L'ordre de reprise vient du brief, section 9.

| Hors MVP | Ce qui est exclu | Après le MVP |
| --- | --- | --- |
| AWS et Azure | Aucune cible ni entrée de catalogue pour ces clouds | AWS en premier, puis Azure |
| On-prem serveurs et cloud souverain | Talos, RKE2, OVHcloud, Scaleway | Troisième étape |
| Autres blueprints | Data platform, IoT, mobile, et tout SaaS B2B dans une autre stack que .NET et React | Data platform en quatrième étape |
| Agent comparateur intégré | Pendant l'entretien, les choix viennent des ADR de phase 1, sans comparaison ni mesure | Cinquième étape |
| Interface web, application autonome, version hébergée | CELIAN n'existe que comme plugin Claude Code et CLI | Non planifié |
| Autres CI | GitLab CI et Forgejo Actions : le projet généré vit sur GitHub | Plus tard (brief, section 6) |
| Idées de la section 12 du brief | Auditeur de projets existants, alertes catalogue, migration de cible, estimation des coûts avant génération, pack conformité, badge OpenSSF Scorecard, site de documentation | Gardées dans `ROADMAP.md` |
| Exploitation du projet | Ni supervision ni astreinte après la livraison | Non prévu |
| Code métier écrit par l'agent | L'agent écrit les ADR et les textes propres au projet. Le code applicatif se limite à l'exemple du blueprint, et l'utilisateur écrit son métier (Q7) | À rouvrir après le MVP |

## 7. Critère d'acceptation global

Le critère du MVP (brief, section 4) :

> Une personne qui ne connaît pas le projet lance la commande, répond à une
> dizaine de questions, et obtient en moins de 15 minutes un dépôt qui démarre
> sur son PC et se déploie sur GCP, avec une CI qui passe.

### Ce que couvrent les 15 minutes

Décision de Lucas du 15/11/2026 (Q1). Le chronomètre part au
lancement de la commande d'entrée, sur un PC où les prérequis du README et le
plugin sont installés. Il s'arrête quand l'entretien est terminé, le dépôt
validé avec un `task up` réussi, le plan OpenTofu GCP valide et la CI du
premier push verte.

L'apply réel a lieu dans la même session, après accord, mais sa durée se mesure
à part : CELIAN ne maîtrise pas le temps que GCP met à créer des ressources
managées. Le premier téléchargement des images compte dans les 15 minutes,
parce qu'une personne extérieure ne les aura pas en cache.

### Comment le tester en phase 6

[QA] écrit le protocole détaillé. Le PRD en fixe le cadre.

- La personne n'a jamais travaillé sur CELIAN. Le nombre de sessions est à
  définir avec [QA].
- Elle suit une consigne écrite, sans aide. Un observateur note les blocages
  sans intervenir.
- On mesure la durée totale et par étape, le nombre de questions, le résultat
  de chaque vérification, l'état de la CI et celui du déploiement.
- L'apply se fait sur un projet GCP de Lucas, avec son accord et un budget
  validé par [FINOPS]. Les ressources sont détruites en fin de session.
- Le critère est atteint quand toutes les conditions passent dans une même
  session. Le résultat va dans un rapport daté.

## 8. Dépendances, hypothèses et questions tranchées

### Dépendances

- Claude Code et son système de plugins : format et distribution à vérifier sur
  la documentation officielle avant la phase 5.
- Les phases 1 à 4 : ADR et catalogue daté, golden repo, blueprint et schéma,
  matrice de validation. Le plugin de la phase 5 s'appuie sur elles.
- Les comptes de l'utilisateur : GitHub pour le dépôt et la CI, GCP avec
  facturation pour le déploiement.
- Un accès réseau aux registres d'images et de paquets.

### Hypothèses

Aucune n'est validée à ce jour.

- Le persona utilise déjà Claude Code et lit du .NET et du React.
- Une dizaine de questions suffit pour le blueprint SaaS B2B sur deux cibles.
- GitHub convient comme forge au persona pendant le MVP.
- Un PC de développeur fait tourner au moins le profil lite.
- La différenciation n'a pas été confrontée aux outils existants : aucune
  analyse concurrentielle n'a été faite.

### Questions tranchées

Lucas a retenu les propositions du PO pour les douze questions, le 15/11/2026.

| # | Question | Décision |
| --- | --- | --- |
| Q1 | Que couvrent les 15 minutes ? | Section 7 : plan GCP et CI dedans, apply mesuré à part, images comprises |
| Q2 | Qui lance `tofu apply` dans le produit ? | L'utilisateur, jamais l'agent : principe X transposé aux utilisateurs |
| Q3 | Qui crée le dépôt GitHub distant et pousse ? | CELIAN, avec les droits de l'utilisateur et après confirmation |
| Q4 | Langue de la documentation générée ? | Question de l'entretien, français par défaut |
| Q5 | Systèmes d'exploitation du PC ? | macOS et Linux, Windows à évaluer par [OPS] |
| Q6 | Environnements déployés sur GCP ? | Un seul, structure Argo CD prête pour staging et prod |
| Q7 | Quel code métier écrit l'agent ? | Les ADR et les textes du projet. Le code métier se limite à l'exemple du blueprint |
| Q8 | Où publier et signer les images avant que GCP existe ? | À instruire par [OPS] et [SECU] avant la phase 2, arbitré par [ARCHI] |
| Q9 | Un serveur Dependency-Track dans le MVP ? | Non : SBOM archivé par la CI, serveur plus tard |
| Q10 | BENCH-006 reste-t-il utile, la CLI Python étant retenue ? | Oui, court, pour tracer le pourquoi dans un ADR |
| Q11 | Accès au plugin pour la phase 6, le dépôt étant privé ? | Un accès en lecture le temps du test |
| Q12 | Une analyse des outils existants avant la GATE 1 ? | Oui, courte, par [BENCH] |

Q7 resserre le brief, qui confiait le code métier à l'agent. Raison : ce code
ne serait pas déterministe, la matrice de validation ne le couvrirait donc pas,
et il agrandirait la surface de conflit de `copier update` (R-11).
