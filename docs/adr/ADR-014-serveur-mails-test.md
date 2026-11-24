# ADR-014. Le serveur de mails de test du profil standard est Mailpit sur `local`, et rien ne le remplace sur `gcp`, sous conditions et avec une dérogation datée à ENF-03

| Champ | Valeur |
| --- | --- |
| Statut | accepté |
| Date | 2026-11-24 |
| Auteur | [ARCHI] |
| Décideur | Lucas, décisions et acceptation du 2026-11-24 sur BENCH-013 |
| BENCH lié | [BENCH-013](../benchmarks/BENCH-013-serveur-mails-test.md) |
| Remplace | aucun |

## Contexte et problème

Le profil standard du projet généré ajoute au profil lite Flux, un fournisseur d'identité et un serveur de mails de test (décision de Lucas du 2026-11-20, US-005, FR-006 de la spec 001). C'est lui qui sert de mesure au critère des 15 minutes (ENF-01, section 7 du PRD) : le volume et la mémoire du serveur de mails comptent dans R-04. FR-006 veut que Mailpit entre dans le golden repo après son benchmark : c'est BENCH-013, ouvert le 2026-11-20 et fusionné par la PR #47.

Le serveur capte en SMTP les mails envoyés depuis le cluster local, les montre au développeur dans une interface web et les rend lisibles par une API HTTP pour les tests, sans qu'aucun ne quitte le poste (BENCH-013, section 1). L'interface web est requise par décision du DSI du 2026-11-20 : le développeur lit dans son navigateur les mails de confirmation et de réinitialisation du fournisseur d'identité. Dans le MVP, l'exemple applicatif n'envoie aucun mail (Q7, FR-009). Le seul émetteur sur `local` sera Keycloak, dont l'ADR-013 renvoie l'envoi de mails à cet ADR, avec une inscription ouverte et aucun utilisateur créé d'avance (réponse de Lucas à sa question 5).

Les exigences viennent du PRD et de la spec. ENF-02 veut que chaque brique de la spec existe sur les deux cibles et que le README liste les écarts ; FR-018 le reprend. ENF-03 veut que Kyverno refuse les images non signées, ce qui arrive en phase 4 d'après les hypothèses de la spec. FR-003 garde tout en boucle locale, FR-004 et FR-005 règlent les secrets locaux, FR-008 fige chaque image par condensat, FR-016 veut un redémarrage sans registre public dans chaque profil livré, FR-021 scanne toute image en marche.

Les décisions acceptées posent leurs contraintes. [ADR-005](ADR-005-gateway.md) : interfaces exposées par la gateway en boucle locale ; sa condition 5 admet un écart voulu entre les rendus par un ADR et une ligne du README. [ADR-006](ADR-006-orchestration-locale.md) : ni Helm ni outil de boucle, aucun objet `Secret` sous `k8s/`. [ADR-007](ADR-007-secrets.md) : Secrets créés par `task up` par un tube et liste des valeurs connues (condition 1), même nom et mêmes clés sur les deux cibles (condition 5) ; sa question 2, les identifiants de services tiers sur le PC, reste ouverte. [ADR-009](ADR-009-catalogue.md) : le principe III fixe les candidats d'une cible et le principe V les départage ; une cible `gcp` est `managed`, ou `oss` avec un `managed_gap`. [ADR-011](ADR-011-miroir-registres.md) : toute image tirée par le nœud passe par zot, sous une liste unique de registres (condition 10), où docker.io figure déjà. [ADR-012](ADR-012-postgres-local.md) : profil `restricted` dans le namespace de l'application, dérogation à ENF-03 limitée à `docker.io/library/`. [ADR-013](ADR-013-fournisseur-identite.md) : Keycloak sur `local`, Identity Platform sur `gcp`, une dérogation à ENF-03 pour la seule image de Keycloak, et une limite mémoire de Keycloak qui attendait BENCH-013 (condition 11). Côté risques : R-04, R-20, R-25 et R-36.

BENCH-013 a mesuré Mailpit, maildev et smtp4dev avec le même script, trois exécutions chacune, le 2026-11-23. [SECU] et [FINOPS] l'ont relu le 2026-11-24, le DSI a arbitré le même jour, et Lucas a tranché deux points (BENCH-013, section 7). Le rapport laisse deux sujets à [ARCHI]. D'abord la parité sur `gcp` : la documentation de Google Cloud ne cite aucun service d'envoi managé par Google, le service Mail d'App Engine est qualifié d'ancien, et Identity Platform envoie lui-même les mails de ses parcours, par la méthode `DEFAULT` ou par un relais que fournit le développeur, `CUSTOM_SMTP` (BENCH-013, section 2, S56 à S59). [ARCHI] a relu S56 le 2026-11-24, comme le demande la section 8 du rapport : rien n'a changé. Le schéma du catalogue ne sait pas écrire cette absence. Ensuite l'écart au principe V : les trois options reposent chacune sur une personne.

## Options considérées

Sur `local`, la grille réconciliée par le DSI le 2026-11-24 :

| Option | Score BENCH (sur 100) | Verdict | Raison principale |
| --- | --- | --- | --- |
| Mailpit v1.34.0 | 81 | retenue | MIT ; 32 releases stables en 12 mois ; 18 avis publiés chacun avec sa version corrigée ; capteur par défaut de Laravel Sail et de DDEV ; passé sous le profil `restricted` avec le seul ajout d'un utilisateur numérique. La plus légère : 15,1 Mo en amd64, pod de 15,3 Mio |
| maildev 3.0.0 | 70 | écartée | Réécriture complète de 58 jours, après 19 mois sans release ; quinze mois et demi pour corriger sa seule faille critique connue ; socket.io diffuse le résumé de chaque mail hors de l'authentification (lecture du code par [SECU], non essayée) |
| smtp4dev 3.16.1 | 64 | écartée | 176,9 Mo en amd64, au-delà du seuil de volume ; IMAP sans identifiant par défaut (lecture des réglages, non essayée) ; la configuration la plus fragile, deux tests de fumée ratés ; aucune politique de sécurité |

Sensibilité, reprise du rapport : un cran vaut au plus 3 points, et il en faudrait au moins quatre contre Mailpit pour que maildev passe devant. Le cas le plus défavorable discuté, 79 contre 72, garde Mailpit devant ; avec le miroir de l'ADR-011, les trois options regagnent le même cran (83, 72 et 66). La gouvernance ne départage pas : 2/5 pour les trois. Le seul candidat porté par une fondation, mock-smtp-server d'Apache James, n'a pas d'interface de lecture et sort par la règle d'interface du DSI (question 1).

Sur `gcp`, trois voies, que la grille ne note pas (BENCH-013, section 2) :

| Voie | Score | Verdict | Raison principale |
| --- | --- | --- | --- |
| Rien sur `gcp` | non noté | retenue, décision de Lucas du 2026-11-24 | L'exemple n'envoie pas de mail ; Identity Platform envoie les mails des parcours de connexion ; 0 USD, aucune ressource ; la voie la moins exposée pour [SECU] |
| Mailpit sur GKE, `oss` avec `managed_gap` | non noté | écartée | De 1,8 à 23,4 USD par mois selon les demandes, aux prix d'exemple de us-central1 ; un outil qui garde des liens de confirmation et de réinitialisation sur un cluster joignable ; ne recevrait rien dans le MVP, et rien de ce qui a été lu ne dit qu'Identity Platform joint un hôte privé en `CUSTOM_SMTP` |
| Relais réel, fournisseur tiers ou Google Workspace, ports 465 ou 587 | non noté | écartée, hors champ du rapport | Fait entrer un vrai identifiant d'envoi (question 2 de l'ADR-007, hors MVP) ; facture hors de Cloud Billing ; sortie vers Internet depuis des nœuds privés sans Cloud NAT ; hors du schéma du catalogue |

Grille, mesures et sources : [BENCH-013](../benchmarks/BENCH-013-serveur-mails-test.md).

## Décision

Sur la cible `local`, le projet généré fait tourner Mailpit v1.34.0 dans le profil standard, image `docker.io/axllent/mailpit` figée par condensat, dans un Deployment d'une réplique de la couche `local`. Sur la cible `gcp`, rien ne le remplace : aucun pod, aucune ressource, aucun relais. Les mails des parcours de connexion y partent d'Identity Platform, l'hôte SMTP reste un réglage du projet, et le README liste l'écart. Le catalogue écrit cette absence par un type de cible nouveau, `absent`, que la PR de schéma de la phase 3 ajoute (section « Entrée au catalogue »).

Le condensat retenu est celui de la mesure : `docker.io/axllent/mailpit:v1.34.0@sha256:23a2ef85bc50853ab3093645d1d64679afd8887e89da5e48a88940c172591a4e`. C'est un condensat d'index, qui pointe sur le manifest `sha256:5040a9c533087d25dcb8f2ac748f45c9be5f7bc1d9fe5b860afb9597a2471d57` en amd64 et `sha256:fbcdc3ae58bf9b84fab363f53cdccb40698cd88e185e910335e812045e78b54b` en arm64 (`tests/bench/bench-013-test-mail.sh`, ligne 93). Le tag n'a été poussé qu'une fois, le 2026-11-17 à 07:07:21 UTC (S69). La release date du 2026-11-17 à 06:57 UTC : le délai de 7 jours du principe VI s'est écoulé le 2026-11-24 à 06:57 UTC, avant toute PR du golden repo, et l'exception de sécurité n'est pas requise (condition 7). La page des releases, relue par [ARCHI] le 2026-11-24, ne montre aucune version plus récente. Renovate suit ensuite l'image sous la condition 2.

Le DSI a retenu Mailpit dans son arbitrage du 2026-11-24. Lucas a pris deux décisions le même jour : rien sur `gcp`, et la dérogation datée à ENF-03 de la section « Dérogations ». La règle d'interface suit la décision du DSI du 2026-11-20. La validation de cet ADR revient à Lucas, avec cinq questions ouvertes.

### Répartition par couche

| Couche | Contenu |
| --- | --- |
| commune | Rien de Mailpit : aucun nom, aucune adresse, aucun port. Aucune clé SMTP dans `app-config` tant que l'exemple n'envoie rien (question 4) |
| `local` | Mailpit dans `local/mail/`, nom du plan : Deployment d'une réplique, Service en `ClusterIP` pour le SMTP et le HTTP, NetworkPolicy, HTTPRoute sous un préfixe (condition 14) ; la tâche de `task up` qui crée son Secret ; son image dans l'inventaire du scan ; son entrée dans `local/k8s/standard/`. Dans la couche de Keycloak, le serveur SMTP du royaume de l'application, qui désigne le Service de Mailpit (condition 12) |
| `gcp` | Rien de Mailpit. Identity Platform garde sa méthode d'envoi `DEFAULT` (S58), sans relais `CUSTOM_SMTP`, donc sans identifiant SMTP (condition 13) |

Proposition de [ARCHI] : Mailpit vit dans le namespace de l'application, comme la base. Le profil `restricted` s'y applique déjà à tous les pods (condition 9 de l'ADR-012), et `task app:down` emporte ensemble le pod et son Secret. Les mails n'ont rien à garder : la base de Mailpit est par défaut un fichier temporaire, supprimé à l'arrêt (page des options, lue le 2026-11-24).

Le Secret s'appelait `mail-ui-auth` dans l'essai, avec la clé `mp-ui-auth` ; le nom se fixe à l'étape 16 du plan, comme dans l'ADR-013. C'est un Secret de couche, comme `db-superuser` et les deux Secrets de Keycloak : il n'a pas de pendant sur `gcp`, l'application ne le lit pas, et la condition 5 de l'ADR-007 reste tenue. L'écart se liste au README.

### Qui envoie des mails, et où ils arrivent

| Émetteur | `local` | `gcp` |
| --- | --- | --- |
| Parcours de connexion | Keycloak, royaume de l'application, vers le Service de Mailpit sur le port 1025, sans authentification ni TLS, dans le cluster seulement | Identity Platform, méthode `DEFAULT` : des mails réels, vers des adresses réelles. La page des limites de Firebase donne des quotas quotidiens, sans dire s'ils valent pour Identity Platform ni si ces envois sont facturés (S76) |
| Exemple applicatif | Aucun dans le MVP (Q7). Quand l'utilisateur en ajoute un, l'hôte SMTP est un réglage du projet, qui désigne le Service de Mailpit | Aucun dans le MVP. Quand l'utilisateur en ajoute un, l'hôte est son relais, avec un identifiant que rien ne prévoit dans le MVP (question 2 de l'ADR-007) |
| Tests de la matrice | Un pod de test envoie en SMTP et relit l'API, comme la sonde de M5 et de M8 | Aucun |

Le SMTP sans authentification est un choix. Avec un identifiant, le royaume de Keycloak porterait un mot de passe, alors que l'ADR-013 livre un royaume sans aucun secret. La NetworkPolicy de la condition 4 garde la porte à sa place.

### Conditions

Les conditions 1 à 8 sont celles de [SECU], les conditions 9 à 11 celles de [FINOPS], retenues par le DSI le 2026-11-24 (BENCH-013, sections 7 et 10). Elles sont transposées à la décision de Lucas : rien ne tourne sur `gcp`. Les conditions 12 à 15 sont des ajouts de [ARCHI]. La décision ne vaut qu'avec elles. Chaque contrôle cité entre dans la matrice de validation (principe I) ; [QA] lui donne son identifiant dans le plan.

1. Image et dérogation à ENF-03. `docker.io/axllent/mailpit` est désignée par condensat et tirée par zot ; docker.io est déjà dans la liste unique de la condition 10 de l'ADR-011, et un tirage anonyme suffit (condition 13 de l'ADR-011). La dérogation datée de la section « Dérogations » admet l'image par sa référence exacte, condensat compris, dans une liste fermée ; [SECU] relit chaque condensat neuf. Contrôles : S01 ; E11 ; E10 en profil standard, image de Mailpit comprise ; dès qu'un profil embarque Kyverno, le contrôle de la condition 7 de l'ADR-012 étendu à `docker.io/axllent/mailpit`.
2. Suivi et scanners. Renovate suit les versions correctives. Une version qui corrige un avis du dépôt passe par l'exception de sécurité du principe VI, matrice comprise. [SECU] lit chaque mois les avis du dépôt (R-36, déjà étendu à Mailpit). Au premier scan de l'image figée, [SECU] vérifie que Trivy relève `github.com/axllent/mailpit` et sa version ; sinon, R-36 dit que le scan ne couvre pas Mailpit. Contrôles : S23 étendu à l'image de Mailpit ; E25 et E27 en profil standard.
3. Durcissement. Le namespace applique le profil `restricted`. Le pod a `runAsNonRoot`, un `runAsUser` numérique (65534 dans l'essai), `allowPrivilegeEscalation: false`, les capacités `ALL` retirées, `seccompProfile: RuntimeDefault` et `automountServiceAccountToken: false` : l'image ne déclare aucun utilisateur et tournerait en root sans eux (S7). `readOnlyRootFilesystem` s'essaie avec un `emptyDir` borné par `sizeLimit`, qui reçoit la base temporaire. Le pod a une limite mémoire (condition 10). `MP_MAX_MESSAGES` et `MP_MAX_MESSAGE_SIZE` sont fixés par [DEV] avec [FINOPS] : leurs défauts, 500 messages et 50 « MB » par message (page des options, lue le 2026-11-24), laissent la base grossir bien au-delà de ce que la mesure a vu, un seul mail. Contrôles : la matrice échoue sur un pod refusé par le profil ; un contrôle statique vérifie ces champs et ces deux variables.
4. Aucun envoi hors du poste. La couche ne porte aucune variable `MP_SMTP_RELAY_*`, `MP_SMTP_FORWARD_*`, `MP_WEBHOOK_URL` ou `MP_SEND_API_AUTH_ACCEPT_ANY`, ni `MP_ALLOW_INTERNAL_HTTP_REQUESTS` à `true`. `MP_DISABLE_VERSION_CHECK` vaut `true`. Une NetworkPolicy refuse toute sortie au pod. En entrée, elle n'admet que le SMTP depuis les pods qui envoient, Keycloak, l'API quand elle enverra, et le pod de test, et que le HTTP depuis le proxy de la gateway. [SECU] écrivait « depuis l'application » : la transposition tient compte de ce que Keycloak est le seul émetteur du MVP. [OPS] vérifie que la politique s'applique sous kind 0.33.0 (S72) et désigne les pods du proxy d'Envoy, comme pour la condition 4 de l'ADR-013. Sans sortie, la vérification des liens et la capture d'écran de Mailpit échouent, ce qui est voulu. Contrôles : un contrôle statique refuse ces variables dans le rendu ; un pod non admis n'atteint ni 1025 ni 8025 ; proposition de [ARCHI], un pod de test soumis à la même politique, sans être choisi par le Service, ne joint aucune adresse, ce qui évite d'entrer dans le conteneur de Mailpit.
5. Exposition. Le SMTP ne sort pas du cluster : Service en `ClusterIP`, sans `NodePort`, ni `LoadBalancer`, ni route TCP. L'interface passe par une HTTPRoute de la gateway en boucle locale (FR-003), sous le préfixe de la condition 14. POP3 reste coupé : il ne démarre qu'avec un fichier d'identifiants ou leur variable (page des options, lue le 2026-11-24), et la couche ne porte aucune variable `MP_POP3_*`. Contrôles : par la gateway, l'API de Mailpit sous son préfixe répond 401 sans identifiant ; E03 ; un contrôle statique sur le type du Service et l'absence de variable POP3.
6. Identifiants (R-20). Le Secret est créé par `task up` selon la condition 1 de l'ADR-007, avec `password1` et `password2`, l'exemple de la page de configuration HTTP (S12), ajoutés à la liste des valeurs connues. La clé contient `utilisateur:mot de passe` : le test de longueur et de liste vise la partie qui suit le premier `:`, le tirage exclut l'espace et le `:`, qui séparent les entrées de `MP_UI_AUTH` (S12), et le nom d'utilisateur, fixe, sort du test de répétition, comme `username` dans la condition 10 de l'ADR-012. `MP_UI_AUTH` vient d'un `secretKeyRef`, jamais d'une valeur écrite ni d'un argument ; Mailpit le refuse d'ailleurs en option de commande (S12), et la v1.34.0 refuse de démarrer avec des identifiants vides (S68). Le contrôle du type de M8, 401 sans identifiant puis 200 avec celui du Secret, entre dans la matrice, sans identifiant en argument. Le README dit comment lire le mot de passe sans l'écrire dans un fichier. Contrôles : E04 et E05 étendus à la couche ; un contrôle statique sur la source de `MP_UI_AUTH` et l'absence de `command` et d'`args`.
7. Version. La v1.34.0 est figée par le condensat de la section « Décision », après le 2026-11-24 à 06:57 UTC. L'exception du principe VI n'est pas requise pour le golden repo. Contrôles : S01 ; S23.
8. GKE. Aucun déploiement en phase 2 et, par décision de Lucas, rien de Mailpit sur `gcp`. Si la décision se rouvrait vers Mailpit sur GKE, un nouvel ADR porterait le `managed_gap`, les conditions 1 à 6 s'appliqueraient, l'interface ne serait jamais publique, les demandes seraient explicites (condition 9 de l'ADR-008), et il faudrait l'accord de Lucas et un budget de [FINOPS] (principe X). Contrôles : S17 ; celui de la condition 13.
9. Volume, de [FINOPS]. R-04 et ENF-01 passent à 1 802,1 Mo pour le premier `task up` du profil standard, Keycloak et Mailpit compris : 1 441,7 s à 10 Mbit/s, 160,2 % du budget de 900 s, 16,0 Mbit/s au minimum. La part de Mailpit est de 12,1 s, 1,3 % du budget. R-04 l'écrit déjà ; ENF-01 se met à jour dans le PRD. Contrôle : D02 en profil standard avec Mailpit.
10. Demandes et limites de Mailpit, de [FINOPS]. La couche `local` pose des demandes et des limites explicites, dont la demande et la limite mémoire : la mesure n'en posait aucune, et le plancher du profil compte Mailpit pour 15,3 Mio, la médiane de son pod, ou 90,2 Mio au majorant. Les valeurs se mesurent sur le golden repo, avec les réglages de la condition 3. Contrôles : un contrôle statique sur la présence des demandes et des limites ; D02 et D03 étendus au profil standard ; P03 avec le seuil recalculé.
11. Limite mémoire de Keycloak, de [FINOPS]. Avec Mailpit, la limite du conteneur de Keycloak doit rester sous 1 240 Mi environ pour que le profil standard tienne sur un portable de 8 Gio à cette limite, et sous 1 165 Mi au majorant de Mailpit. Cette valeur remplace l'ordre de grandeur de 1 255 Mi de la condition 11 de l'ADR-013. Rien ne prouve que Keycloak tient sous cette limite : son pod pèse environ 820 Mio au repos, ce qui laisse environ 420 Mi au pic de démarrage, jamais mesuré, et sa demande de référence, 1700Mi, doit baisser avec elle. Si aucune limite ne tient, le profil standard demande plus de 8 Gio, écart que Lucas a accepté (réponse à la question 3 de l'ADR-013). Contrôles : un contrôle statique sur la demande et la limite de Keycloak ; D02 et D03 en profil standard, pic de démarrage et repos relevés à la limite retenue.
12. Couche commune neutre et SMTP sans secret, ajout de [ARCHI]. Ni la couche commune ni le code commun ne nomment Mailpit, son Service ou ses ports. Le serveur SMTP du royaume de l'application vit dans la couche `local` et désigne le Service de Mailpit, port 1025, sans authentification ni TLS. L'adresse d'expéditeur et celles des utilisateurs de test sont sous le domaine réservé `.invalid` (RFC 2606, cité par la condition 4 de l'ADR-011), pour qu'un mail échappé par erreur n'atteigne personne. Les noms des réglages de Keycloak 26.8.2, et le fait qu'il accepte une adresse en `.invalid`, se lisent dans sa documentation ([DEV]). Contrôles : S06 étendu, ni nom ni port de Mailpit dans la couche commune ; un mail émis par Keycloak arrive dans Mailpit en profil standard, par un déclenchement que [DEV] fixe à l'étape 16.
13. Absence sur `gcp`, ajout de [ARCHI]. Le rendu `gcp` ne contient aucun objet de Mailpit, aucune HTTPRoute vers un service de mails, aucun réglage SMTP qui désigne un hôte du cluster. La configuration d'Identity Platform garde la méthode `DEFAULT` (S58) et ne porte aucun relais `CUSTOM_SMTP` : aucun identifiant SMTP n'entre dans Secret Manager. Le README du projet généré porte la ligne d'écart du catalogue. Contrôles : un contrôle statique sur le rendu `gcp` ; une politique conftest qui refuse `CUSTOM_SMTP`, une fois l'attribut OpenTofu lu ([OPS]) ; un contrôle statique qui cherche la ligne d'écart dans le README.
14. Interface sous un préfixe, ajout de [ARCHI]. L'API de l'exemple occupe `/api` et le front la racine, sur la même gateway ; l'API de Mailpit vit sous `/api/v1/`, et les deux se recouvriraient. Mailpit sert donc son interface et son API sous un préfixe, par `MP_WEBROOT`, que la page des options décrit pour l'interface et l'API : `mail` y donne `/mail/` (lue le 2026-11-24). L'HTTPRoute de ce préfixe n'existe que dans la couche `local` : c'est un écart voulu, que la condition 5 de l'ADR-005 admet par cet ADR et une ligne du README. Restent à vérifier : que `/readyz` suive ou non le préfixe ([DEV]), et que le WebSocket de l'interface passe la gateway ([OPS]). Contrôles : par la gateway, l'API de Mailpit sous le préfixe répond 401 sans identifiant, et `/api/` atteint toujours l'exemple ; S07 inchangé sur la couche commune.
15. Profil standard seulement, ajout de [ARCHI]. Le profil lite n'embarque ni Keycloak ni Mailpit : sans émetteur, le serveur n'aurait rien à capter. Contrôle : E14, aucun objet de Mailpit dans le rendu lite, Mailpit présent en standard.

Les conditions des ADR-004 à ADR-013 restent en vigueur, en particulier les images par condensat (condition 3 de l'ADR-004), l'absence de Secret sous `k8s/` (condition 1 de l'ADR-006), la création des Secrets par un tube (condition 1 de l'ADR-007), la liste unique des registres (condition 10 de l'ADR-011) et le profil `restricted` du namespace de l'application (conditions 1 et 9 de l'ADR-012).

### Mémoire et profil standard

[FINOPS] place le profil standard avec Keycloak et Mailpit au repos à 2 310,3 Mio de plancher : 3,5 Gio de VM et 7,5 Gio de portable, sans palier de plus, avec 420,4 Mio de marge sur un portable de 8 Gio. Au majorant de Mailpit, 2 385,2 Mio, le palier ne change pas, à 4,1 Mio du suivant. Ce cadre vaut au repos, avec un seul mail dans Mailpit, et pas à la limite de Keycloak : à sa limite de référence, 2000Mi, le plancher monterait à environ 3 490,4 Mio, soit 5,5 Gio de VM et 9,5 Gio de portable. Ces chiffres mêlent des séries de plusieurs benchmarks prises à des jours différents : ce sont des ordres de grandeur, que D02 et D03 remplaceront sur le golden repo.

### Ce que l'ADR change ailleurs

Aucun de ces fichiers n'est modifié par cet ADR. Chaque changement passe par sa PR, chez son porteur.

- ADR-007, pour [SECU] et [DEV]. Il n'est pas remplacé. La liste des valeurs connues de la condition 1 reçoit `password1` et `password2`. Le test vise la partie mot de passe de `mp-ui-auth`, celle qui suit le premier `:`, et le nom d'utilisateur fixe sort du test de répétition. Le tirage exclut l'espace et le `:`. Un Secret de couche s'ajoute sur `local`, sans pendant sur `gcp` ; la condition 5 reste tenue. La question 2 n'est pas tranchée : le MVP n'a besoin d'aucun identifiant SMTP, ni sur `local` ni sur `gcp`, et elle reviendra avec le premier relais réel.
- Registre des risques, pour le DSI. R-04 est déjà à 1 802,1 Mo et R-36 déjà étendu à Mailpit. R-20 reçoit `password1` et `password2`. R-37 peut s'étendre aux mails : sur `gcp`, les mails des parcours partent vers des adresses réelles et rien ne les capte. BENCH-013 propose deux risques, numéros à attribuer : un serveur de mails de test tenu par une seule personne, soutenue par un éditeur qui publie un outil concurrent ; des avis de sécurité fréquents, 18 en dix mois et demi.
- Catalogue et schéma, pour la PR de schéma de la phase 3 : l'entrée `test-mail`, le type de cible `absent`, la valeur de gouvernance `individual` et le standard `smtp` (section « Entrée au catalogue »).
- README du projet généré, pour [DOC] : la ligne d'écart sur `gcp` ; l'adresse de Mailpit par la gateway, sous son préfixe ; la lecture du mot de passe sans fichier ; les mails perdus au redémarrage du pod ; le SMTP sans TLS dans le cluster ; Mailpit dans le seul profil standard ; le Secret de couche sans pendant sur `gcp`.
- PRD, pour [PO] : ENF-01 à 1 802,1 Mo ; la dérogation à ENF-03 citée sous l'exigence, avec celles des ADR-012 et ADR-013.
- Spec 001, pour [PO] puis Lucas. FR-006 et l'hypothèse sur Mailpit renvoient à cet ADR ; `contracts/secrets.md` reçoit le Secret de Mailpit ; `data-model.md` reçoit le palier du profil standard, 3,5 Gio de VM avec Keycloak et Mailpit.
- Plan et tâches, pour [DEV]. L'étape 16 reçoit les contrôles des conditions 1 à 15 ; T151 et T152 portent un Secret, puisque la couche en a un ; RS-15 note l'image, le registre et le Secret.
- ADR-011. Il n'est pas remplacé. La ligne « à relever » de son tableau des registres devient, pour Mailpit : docker.io, `axllent/mailpit`, containerd du nœud, profil standard, non mesuré. Aucun amont ne s'ajoute ; l'estimation du stockage de zot passe de 831,6 à 846,7 Mo en amd64, sans mesure qui la confirme.
- ADR-012. Il n'est pas remplacé. Sa dérogation reste limitée à `docker.io/library/`, et le contrôle de sa condition 7 s'étend à `docker.io/axllent/mailpit`.
- ADR-013. Il n'est pas remplacé. La couche de Keycloak reçoit le serveur SMTP du royaume (condition 12), et sa condition 11 prend la limite de la condition 11 ci-dessus.
- ADR-005. Il n'est pas remplacé. La couche `local` ajoute une HTTPRoute vers Mailpit sur la Gateway commune, écart voulu que sa condition 5 admet.

### Portée

Brique abstraite proposée : `test-mail`, déclarée par la cible (`declared_by: target`). La spec du projet ne la nomme pas : elle découle de la cible `local` et du profil standard, et Mailpit ne vit que dans la couche `local` et au catalogue (principe II). La décision couvre la cible `local` en profil standard, une réplique, et l'absence sur `gcp`.

Restent hors de cette décision :

- l'envoi de mails par l'exemple applicatif (Q7), et le choix d'un fournisseur d'envoi réel pour un client en production (BENCH-013, section 1) ;
- une brique d'envoi déclarée par la spec, qui viendrait avec un besoin d'envoi du projet et passerait par son propre benchmark ;
- le profil lite, sans Mailpit (condition 15) ;
- POP3, le relais et le transfert de Mailpit ;
- l'on-prem et Windows (Q5).

## Conséquences

### Positives

- La plus légère des trois options : 15,1 Mo en amd64, cinq fois moins que maildev et douze fois moins que smtp4dev ; pod de 15,3 Mio au repos ; prête en 3,4 s de médiane (M1) ; mail relu par l'API en 0,03 s (M5). Le palier du profil standard ne bouge pas : 3,5 Gio de VM, 7,5 Gio de portable.
- Un seul contrôle d'accès pour l'interface, l'API, le WebSocket, le proxy et `release` ; seules `livez` et `readyz` restent ouvertes (S15). 401 sans identifiant et 200 avec celui du Secret dans les trois exécutions (M8).
- Aucun amont nouveau pour le miroir : docker.io est déjà servi par zot.
- Sur `gcp`, 0 USD, aucun pod, aucune exposition, aucun identifiant SMTP.
- Le royaume de Keycloak reste sans secret, puisque le SMTP du cluster n'a pas d'identifiant.
- Un coût de sortie limité à la couche `local` : Keycloak, et plus tard l'application, ne parlent au serveur qu'en SMTP, et les mails n'ont rien à migrer.
- Démarrage sous le profil `restricted` avec un seul ajout, l'utilisateur numérique.

### Négatives

- Gouvernance : une personne fait 93,6 % des commits humains de l'année, depuis un compte personnel ; Mailtrap affiche son soutien sans en publier les termes, et publie depuis le 2026-05-05 son propre outil local (S53). Écart au principe V, justifié plus bas.
- Rythme des correctifs : 18 avis en dix mois et demi, 13 versions correctives. Renovate ouvrira souvent des PR, chacune sous la matrice.
- R-36 : trois des 18 avis manquent à la base mondiale, dont le seul élevé du dépôt, et Trivy ne les voit pas. Que Trivy lise la version du binaire n'est pas vérifié ; s'il ne la lit pas, aucun des 18 avis ne sortirait.
- ENF-03 n'est pas tenu : aucune signature ni attestation, une image bâtie sur `golang:alpine` et `alpine:latest` sans condensat (S68). Chaque condensat neuf refait confiance à Docker Hub.
- Sans `securityContext`, l'image tourne en root (S7) : un manifest qui oublierait le profil le ferait sans erreur. La condition 3 et le profil du namespace couvrent ce point.
- Sur `gcp`, aucun mail n'est capté : les mails des parcours partent vers de vraies adresses, sous des quotas et une facturation mal connus (S76). Un défaut des mails de connexion sur `gcp` ne se voit qu'au premier déploiement réel (R-37).
- Les mails captés se perdent au redémarrage du pod, la base étant un fichier temporaire.
- La promesse « aucun mail ne quitte le poste » tient par la configuration et par la NetworkPolicy : sur le PC, rien ne bloque le port 587 ([SECU]), et l'application de la politique sous kind 0.33.0 n'est pas vérifiée.
- Volume : 15,1 Mo de plus, R-04 à 160,2 % du budget à 10 Mbit/s.
- Mesures d'un seul poste, arm64 sous OrbStack, sur batterie (R-26). Restent non mesurés : le démarrage sur amd64, `readOnlyRootFilesystem`, la NetworkPolicy, la route par la gateway et son WebSocket, la mémoire de Mailpit avec beaucoup de mails et sous sa limite.

### Effet sur les cibles hors MVP

La porte reste ouverte. Mailpit tourne sur tout cluster conforme (BENCH-013, section 5.7). Une cible AWS ou Azure recevrait une ligne `absent` de plus, avec ses propres sources, si sa documentation ne propose pas non plus de serveur de test managé, ce que cet ADR n'a pas vérifié. Une cible on-prem serveurs passerait par son propre ADR.

### Suites

- [DEV] et [OPS], étape 16 du golden repo : la couche Mailpit sous les conditions 1 à 15 ; la tâche du Secret ; le serveur SMTP du royaume de Keycloak ; `MP_WEBROOT` et `/readyz` ; la NetworkPolicy sous kind et la désignation du proxy de la gateway ; `readOnlyRootFilesystem` ; les demandes et limites ; la commande qui lit le mot de passe pour le README.
- [OPS] : l'attribut OpenTofu de la méthode d'envoi d'Identity Platform ; le WebSocket par la gateway.
- [QA] et [SECU] : les identifiants des contrôles ; la relecture de la liste fermée à chaque condensat ; la lecture mensuelle des avis ; la vérification de Trivy au premier scan.
- [FINOPS] : les valeurs de Mailpit et le palier après le golden repo ; la limite de Keycloak ; la facturation des mails d'Identity Platform avant la GATE 2 (R-05).
- [PO] : ENF-01 et ENF-03 dans le PRD ; FR-006 et les contrats ; la question 3.
- [DOC] : les lignes du README.
- DSI : R-20, R-37 et les deux risques proposés ; le suivi de la levée de la dérogation ; l'entrée `test-mail` et le schéma dans la PR de la phase 3.

### Questions ouvertes

1. Règle d'interface, pour Lucas. La décision du DSI du 2026-11-20 rend l'interface web obligatoire, et c'est elle qui écarte mock-smtp-server d'Apache James, seul candidat porté par une fondation. Avis de [ARCHI] : la confirmer. Le développeur lit les mails de Keycloak dans son navigateur ; sans interface, il les lirait par l'API depuis un terminal, et le README d'Apache James lance d'ailleurs l'image d'une entreprise (S54).
2. Forme du catalogue pour l'absence, pour Lucas. Trois ajouts au schéma : le type `absent`, réservé aux cibles cloud et aux briques déclarées par la cible ; la valeur `individual` de `governance.model` ; le standard `smtp`. Avis de [ARCHI] : les trois, pour les raisons de la section « Entrée au catalogue ». Les deux autres formes écrivent une absence muette ou un fait faux : rendre `gcp` facultatif, ou une ligne `oss` avec un `managed_gap` pour un service qui ne tourne pas.
3. Vérification d'adresse sur `local`, pour [PO] et [SECU]. L'inscription est ouverte (réponse de Lucas à la question 5 de l'ADR-013). Activer la vérification par mail dans le royaume ferait de Mailpit un outil utile dès le MVP et exercerait le chemin du mail ; sur `gcp`, le parcours équivalent passe par le SDK de Google, sous R-37. Avis de [ARCHI] : l'activer sur `local`, réglage exact à lire dans la documentation de 26.8.2 ([DEV]), et décider du pendant `gcp` avec le parcours de connexion.
4. Clé SMTP dans `app-config`, pour Lucas et [PO]. Lecture de [ARCHI] de la décision de Lucas : l'hôte SMTP est un réglage du projet, que CELIAN ne remplit pas sur `gcp`. Avis de [ARCHI] : aucune clé tant que l'exemple n'envoie rien (Q7). Une clé vide sur `gcp` inviterait à une configuration fausse ; le README dit où l'ajouter et quelle valeur prend la couche `local`.
5. Dates et seuils de suivi, pour Lucas et [SECU]. Relecture de la dérogation au plus tard le 2027-05-24, date de la prochaine vérification de BENCH-013, en plus de la relecture de [SECU] à chaque condensat. Signaux d'abandon qui rouvrent la décision (section « Condition de révision ») : aucune release stable pendant six mois, ou un avis du dépôt sans version corrective trente jours après sa publication. Avis de [ARCHI] : ces valeurs, à confirmer par [SECU].

### Réponses de Lucas (2026-11-24)

Lucas accepte cet ADR le 2026-11-24, avec les avis du DSI et de [ARCHI] :

- Il confirme la règle d'interface web du DSI du 2026-11-20 : le
  développeur lit dans son navigateur les mails de confirmation et de
  réinitialisation, et le serveur d'Apache James reste écarté (question 1).
- Il accepte les trois ajouts au schéma du catalogue : le type de cible
  `absent`, `governance.model: individual` et le standard `smtp`, posés dans
  la PR de schéma de la phase 3 (question 2).
- La vérification d'adresse par mail sur `local` revient à [PO] et à
  [SECU] (question 3).
- Aucune clé SMTP dans `app-config` tant que l'exemple n'envoie rien
  (question 4).
- La dérogation à ENF-03 est relue au plus tard le 2027-05-24, et plus tôt
  si un signal d'abandon apparaît : aucune release stable en six mois, ou
  un avis sans correctif au bout de trente jours (question 5).

## Conformité à la constitution

Vérifiée contre la [constitution](../../.specify/memory/constitution.md) en version 1.2.0.

| Principe | Effet | Justification |
| --- | --- | --- |
| I. Rien sans test automatique | respecté | La matrice porte les contrôles des conditions 1 à 15 ; l'absence sur `gcp` se vérifie sur le rendu (condition 13) |
| II. Spec abstraite, catalogue concret | respecté | La spec ne nomme pas la brique ; Mailpit et le serveur SMTP du royaume vivent dans la couche `local`, et la couche commune ne les nomme pas (condition 12) |
| III. Managé sur le cloud, open source ailleurs | respecté | Sur `local`, Mailpit sous MIT, gratuit ; sur `gcp`, aucun service managé de Google ne joue ce rôle (S56, relue le 2026-11-24 ; S59), et rien n'y tourne, donc aucun composant libre sans `managed_gap` |
| IV. Catalogue traçable | respecté sous réserve | L'entrée porte licence, gouvernance, statut, dates et sources ; deux de ses valeurs, `individual` et `absent`, attendent la PR de schéma, et l'entrée avec elles. Aucun blueprint ne s'en sert d'ici là ; le golden repo n'en est pas un |
| V. Gouvernance ouverte d'abord | écart justifié | Projet tenu par une personne ; le critère ne départage pas les trois options, et Mailpit l'emporte sur la maturité, l'activité, la sécurité et l'expérience dev (paragraphe suivant) |
| VI. Récent mais éprouvé | respecté | Aucun critère éliminatoire : MIT, dépôt actif, v1.34.0 du 2026-11-17, publiée depuis 7 jours le 2026-11-24 à 06:57 UTC ; adoptée par Laravel Sail et DDEV, 248 160 030 tirages de l'image |
| VII. Une commande pour démarrer | respecté | `task up` crée le Secret, applique la couche et attend que Mailpit soit prêt, sans prérequis nouveau |
| VIII. Aucun fait de mémoire | respecté | Les faits renvoient à BENCH-013, à ses relectures, à son script et aux pages lues le 2026-11-24. Sont signalés comme non vérifiés : la lecture de la version par Trivy, la NetworkPolicy sous kind 0.33.0, `readOnlyRootFilesystem`, `/readyz` sous le préfixe, le WebSocket par la gateway, les réglages SMTP de Keycloak et les adresses en `.invalid`, l'attribut OpenTofu de la méthode d'envoi, la facturation des mails d'Identity Platform, la mémoire de Mailpit avec beaucoup de mails, la limite de Keycloak |
| IX. Aucun secret dans le dépôt | respecté | Aucun objet `Secret` versionné ; le Secret de Mailpit naît par un tube ; le royaume reste sans secret ; aucun identifiant SMTP sur `gcp` ; `password1` et `password2` refusés |
| X. Aucune dépense cloud sans accord | respecté | Rien n'est créé sur GCP, et la voie retenue n'y crée rien |

### Écart au principe V

Le principe V accepte un projet à éditeur unique quand un benchmark justifie l'écart, avec un ADR. Mailpit n'a même pas d'éditeur : une personne, sans entreprise derrière elle. Le critère de gouvernance donne 2/5 aux trois options (BENCH-013, section 5.2). Chez Mailpit, le mainteneur fait 93,6 % des commits humains ; chez maildev, 91,8 % ; chez smtp4dev, il reste 12 commits humains en douze mois, dont 5 du mainteneur, le reste venant de Renovate et d'un agent. Le choix d'une option ne change donc rien à la gouvernance. Le seul projet de fondation repéré, mock-smtp-server d'Apache James, n'a pas d'interface de lecture (question 1).

Le critère qui l'emporte : la maturité, l'activité, la sécurité et l'expérience dev font les 11 points d'écart avec maildev (BENCH-013, section 7). L'écart se tient aussi hors de la grille. L'outil ne sert que sur le PC, hors du chemin de production, et rien ne tourne sur `gcp`. Keycloak, et plus tard l'application, ne lui parlent qu'en SMTP, standard de l'IETF (RFC 5321), si bien que changer de serveur ne touche que `local/mail/`, son Secret et sa route. Les mails n'ont pas de durée de vie : il n'y a rien à migrer. La relecture du catalogue tous les six mois (ADR-009) verrait un abandon, et les signaux de la condition de révision le verraient plus tôt.

### Dérogations

Une dérogation, décidée par Lucas le 2026-11-24, sur le modèle de celle de l'ADR-013. Elle ne vise aucun principe de la constitution : ENF-03 est une exigence du PRD. Elle s'écrit ici parce que la section « Gouvernance » de la constitution veut qu'une dérogation se justifie dans un ADR, avec sa durée et la condition qui la lèvera, et parce que les dérogations des ADR-012 et ADR-013 ne couvrent pas `docker.io/axllent/mailpit`.

| Principe | Écart | Justification | Durée | Condition de levée |
| --- | --- | --- | --- | --- |
| Aucun : exigence ENF-03 du PRD, « Kyverno refuse les images non signées » | L'image `docker.io/axllent/mailpit` n'a aucune signature vérifiable. Kyverno l'admet par sa référence exacte, condensat compris, inscrite dans une liste fermée | FR-008 reste tenu : le condensat fige le contenu, que containerd vérifie. Le flux de publication de la v1.34.0 n'a ni cosign ni attestation, l'API d'attestations de GitHub répond 404 pour le condensat mesuré, et Docker Hub ne porte aucun tag `sha256-*` (S68, S69). Aucune des trois options n'a d'image signée. Le tag n'a été poussé qu'une fois. [SECU] recommande cette voie | Depuis le 2026-11-24, jusqu'à sa levée. Relecture au plus tard le 2027-05-24 (question 5), et par [SECU] à chaque condensat neuf | Mailpit signe ses images de façon vérifiable par Kyverno : la politique vérifie alors la signature, et la liste fermée disparaît pour cette image |

Portée. La seule image `docker.io/axllent/mailpit`. Ni la copie que Mailpit publie sur ghcr.io, qui n'apporterait rien d'après [SECU], ni les autres dépôts de docker.io hors de `library/`. Une autre image sans signature entre par son propre ADR.

Tenue de la liste. Elle naît avec le premier profil qui embarque Kyverno, en phase 4 ; d'ici là, la dérogation n'a pas d'effet. Elle change dans la même PR que le manifest qui change l'image, PR de Renovate comprise. Au rythme de 13 versions correctives en dix mois et demi, la relecture de [SECU] reviendra souvent. Le contrôle de la condition 1 refuse tout écart entre la liste et les images en marche. Le DSI suit la levée au registre des risques.

## Entrée au catalogue

Brique abstraite proposée : `test-mail`, déclarée par la cible (`declared_by: target`), nom repris du script de BENCH-013. Le nom se confirme en phase 3 avec le schéma. L'entrée s'écrit au format de l'[ADR-009](ADR-009-catalogue.md), dans la PR de schéma de la phase 3 ; cet ADR ne crée pas le fichier. Elle demande trois ajouts au schéma, décrits plus bas.

| Cible | Service | Type | Licence | Gouvernance | Statut | Vérifié le | Source |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `local` | Mailpit, image `docker.io/axllent/mailpit` dans un Deployment de la couche `local` | `oss` | MIT | Personne seule : compte personnel `axllent`, soutien affiché de Mailtrap sans termes publiés | actif | 2026-11-24 | <https://github.com/axllent/mailpit>, <https://github.com/axllent/mailpit/releases> |
| `gcp` | aucun service | `absent`, type proposé | sans objet | sans objet | sans objet | 2026-11-24 | <https://docs.cloud.google.com/compute/docs/tutorials/sending-mail> |

Ce que porte la ligne `local`, d'après BENCH-013 :

| Champ | Valeur |
| --- | --- |
| `service` | Mailpit, image `docker.io/axllent/mailpit` dans un Deployment de la couche `local` |
| `version` | 1.34.0 |
| `license` | `MIT`, présent dans `scripts/catalog/accepted-licenses.yaml`, approuvée par l'OSI (S46). L'image embarque des paquets d'Alpine sous leurs propres licences, et CELIAN n'en redistribue rien (condition 9 de l'ADR-011) |
| `governance` | `individual`, valeur à ajouter ; `body` : `axllent` ; 441 des 471 commits humains de l'année au mainteneur, 18 auteurs (S3) |
| `status` | `active`, dépôt non archivé, dernier commit le 2026-11-19 (S1, S3) |
| `last_release_on` | 2026-11-17, v1.34.0 (S2, relue par [ARCHI] le 2026-11-24) |
| `verified_on` | 2026-11-24, le `read_on` le plus récent des sources de la ligne |
| `standards` | `smtp`, valeur à ajouter à la liste fermée |
| `sources` | S1 à S4, S11, S12 et S66 de BENCH-013, avec leurs URL et leurs dates |
| `decisions` | ADR-014, BENCH-013 |
| `pending` | lecture de la version par Trivy ([SECU]) ; NetworkPolicy sous kind ([OPS]) ; `readOnlyRootFilesystem` ([OPS]) ; demandes et limites ([DEV], [FINOPS]) ; `MP_WEBROOT` et WebSocket par la gateway ([DEV], [OPS]) |

La ligne `gcp` est de type `absent`. Elle porte la raison de l'absence, la ligne d'écart que le README liste, ses sources (S56 relue le 2026-11-24, S58 et S59 lues le 2026-11-20) et ses décisions, ADR-014 et BENCH-013. Elle n'a ni service, ni licence, ni gouvernance, ni standard.

Le condensat de l'image reste dans le blueprint, que Renovate met à jour, comme le veut l'ADR-009. Le contrôle de l'ADR-009 en tirerait ces échéances pour la ligne `local` : le critère des 12 mois tombe le 2027-11-17 sans nouvelle release, et `verified_on` expire le 2027-05-24, date que BENCH-013 propose pour sa prochaine vérification. La ligne `gcp` expire le même jour : l'absence se revérifie aussi.

### Trois ajouts au schéma

Le type `absent`. Le schéma actuel exige pour `gcp` une cible `managed`, ou `oss` avec `managed_gap` (`schema/catalog-entry.schema.json`). Aucune des deux n'est vraie ici : il n'y a pas de service managé, et rien ne tourne. Rendre `gcp` facultatif écrirait une absence muette, que ni la CI ni la relecture ne verraient. Écrire Mailpit en `oss` avec un `managed_gap` serait faux, et pousserait un blueprint à le déployer. D'où un troisième type, sous quatre règles :

1. `absent` n'est permis que sur une cible cloud, jamais sur `local` : le PC fait tourner toutes les briques de son profil (principe VII).
2. `absent` n'est permis que pour une brique `declared_by: target`. Une brique déclarée par la spec existe sur les deux cibles (ENF-02) ; le schéma refuse donc `absent` quand `declared_by` vaut `spec`.
3. Champs obligatoires : `type`, `reason` (pourquoi rien ne tourne, 500 caractères au plus), `readme_gap` (la ligne d'écart du README, sur une ligne), `verified_on`, `sources` (au moins une, qui établit l'absence de service managé) et `decisions.adr`. Facultatifs : `pending`, `notes`. Refusés : `service`, `version`, `license`, `provider`, `governance`, `status`, `last_release_on`, `standards`, `artifacts`, `managed_gap`.
4. Le contrôle du catalogue applique à cette ligne les mêmes échéances de six mois qu'aux autres : l'absence se revérifie, et c'est cette relecture qui verrait Google publier un service qui joue ce rôle. L'avertissement « aucun standard en commun » ne s'applique pas à une cible `absent`. En phase 3, le contrôle du blueprint vérifie que le README porte `readme_gap`.

La valeur `individual` de `governance.model`. Les valeurs actuelles sont `foundation`, `community` (organisation sans fondation) et `single-vendor` (une entreprise). Mailpit n'entre dans aucune, et lui en donner une fausserait la lecture du principe V que le catalogue rend visible.

Le standard `smtp`. C'est ce qu'expose la ligne `local` et ce que parlent ses clients : Simple Mail Transfer Protocol, RFC 5321, d'octobre 2008, Draft Standard sur la voie des standards de l'IETF (page de l'éditeur des RFC, lue le 2026-11-24). Il s'ajoute au tableau des standards de `catalog/README.md` avec cette source.

La PR de schéma dit si ces ajouts demandent `schema_version: 2` ; les entrées existantes restent valides sans changement. Forme proposée, que le schéma actuel refuse :

```yaml
schema_version: 1
id: test-mail
summary: Serveur de mails de test qui capte en SMTP les mails émis dans le cluster local
declared_by: target
targets:
  local:
    type: oss
    service: Mailpit, image docker.io/axllent/mailpit dans un Deployment de la couche local
    version: "1.34.0"
    license: MIT
    governance:
      model: individual
      body: axllent
      detail: Compte personnel GitHub, soutien affiché de Mailtrap sans termes publiés
    status: active
    last_release_on: "2026-11-17"
    verified_on: "2026-11-24"
    standards: [smtp]
    sources:
      - url: https://github.com/axllent/mailpit/releases
        read_on: "2026-11-24"
        establishes: v1.34.0 publiée le 2026-11-17, dernière release
    decisions:
      adr: [ADR-014]
      bench: [BENCH-013]
  gcp:
    type: absent
    reason: >-
      Aucun service managé de Google ne joue le rôle d'un serveur de mails
      de test. L'exemple n'envoie pas de mail dans le MVP, et Identity
      Platform envoie lui-même les mails des parcours de connexion.
    readme_gap: Aucun serveur de mails de test sur GCP ; l'hôte SMTP est un réglage du projet
    verified_on: "2026-11-24"
    sources:
      - url: https://docs.cloud.google.com/compute/docs/tutorials/sending-mail
        read_on: "2026-11-24"
        establishes: Aucun service d'envoi managé par Google cité ; fournisseurs tiers recommandés
    decisions:
      adr: [ADR-014]
      bench: [BENCH-013]
```

## Condition de révision

Bascule par un nouvel ADR qui remplace celui-ci pour la cible concernée dans ces cas :

- sur `local`, Mailpit touche un critère éliminatoire : dépôt archivé ou en maintenance, licence qui n'est plus open source, ou aucune release pendant 12 mois, décompte parti du 2026-11-17 ;
- sur `local`, un signal d'abandon de la question 5 : aucune release stable pendant six mois, ou un avis du dépôt sans version corrective trente jours après sa publication. maildev et smtp4dev se remesurent alors, avec Inbucket et MailCrab, repérés par BENCH-013 ;
- sur `gcp`, Google publie un service managé qui joue ce rôle, vu à la relecture de la ligne `absent` ;
- le projet généré reçoit un besoin d'envoi déclaré par la spec : une brique d'envoi, son benchmark et son ADR traitent alors le relais sur `gcp` et la question 2 de l'ADR-007.

La décision se rouvre, sans basculer d'office, dans ces cas :

- Lucas renverse la règle d'interface (question 1) : mock-smtp-server d'Apache James redevient candidat, et le principe V pèse pour lui ;
- Trivy ne lit pas la version de Mailpit (condition 2), et [SECU] juge la lecture mensuelle des avis insuffisante ;
- la NetworkPolicy ne s'applique pas sous kind, ou le profil `restricted` refuse le pod dans la configuration retenue ;
- Mailtrap retire son soutien, ou le projet change de licence ou de gouvernance, par un accord de contribution ou une cession ;
- Lucas retient une autre forme de catalogue (question 2).

La levée de la dérogation ne rouvre pas la décision : la PR qui retire la liste fermée l'indique ici par un lien. Une version corrective de Mailpit ne la rouvre pas non plus : elle passe par Renovate et la matrice (condition 2). Sans l'un de ces faits, prochaine vérification au plus tard le 2027-05-24, date proposée par BENCH-013.

## Sources

Ce que BENCH-013 établit se cite par lui ; ses propres sources, S1 à S76, sont dans sa section 9.

| Source | Lue le | Ce qu'elle établit |
| --- | --- | --- |
| [BENCH-013](../benchmarks/BENCH-013-serveur-mails-test.md), sections 1 à 3, `main` à `aa01fd5` | 2026-11-24 | Question posée, lecture retenue, décisions du DSI du 2026-11-20 ; options, versions, options repérées dont mock-smtp-server (S54) ; parité sur GCP (S56 à S59) et limite du schéma du catalogue ; critères éliminatoires |
| BENCH-013, section 4 | 2026-11-24 | Seuils, protocole, profil `restricted`, Secret par un tube ; M1 à M8 : 3,4 s, pod de 15,3 Mio, majorant de 90,2 Mio, 15,1 Mo en amd64, retéléchargement, 0,03 s, arm64 natif, 401 puis 200 |
| BENCH-013, sections 5 et 6 | 2026-11-24 | Notes et grille réconciliée : 81, 70 et 64 ; gouvernance à 2/5 pour les trois ; coûts sur GKE Autopilot (S73 à S75) |
| BENCH-013, section 7 | 2026-11-24 | Verdict, sensibilité, réserves 1 à 10, suites ; arbitrage du DSI et décisions de Lucas du 2026-11-24 ; prochaine vérification au 2027-05-24 |
| BENCH-013, sections 8 à 10 | 2026-11-24 | Limites ; sources S1 à S4, S7, S11, S12, S15 à S18, S46, S53, S54, S56 à S59, S66 à S69, S72 à S76 citées ici ; relecture de [SECU] (conditions 1 à 8, valeurs connues, signature, exposition, parité) et de [FINOPS] (cumul à 1 802,1 Mo, plancher à 2 310,3 Mio, limite de Keycloak sous 1 240 Mi, trois voies sur GCP, trois conditions) |
| `tests/bench/bench-013-test-mail.sh`, ligne 93 ; `tests/bench/bench-013/mailpit/deployment.yaml`, `main` à `aa01fd5` | 2026-11-24 | Condensat d'index et manifests amd64 et arm64 ; `MP_DISABLE_VERSION_CHECK` à `true`, `MP_UI_AUTH` par `secretKeyRef`, utilisateur 65534, noms `mail-ui-auth` et `mp-ui-auth` |
| <https://mailpit.axllent.org/docs/configuration/runtime-options/> | 2026-11-24 | `MP_MAX_MESSAGES` à 500 par défaut ; `MP_MAX_MESSAGE_SIZE` à 50 (« MB ») ; `MP_WEBROOT` à `/` pour l'interface et l'API, `mail` donnant `/mail/` ; POP3 activé seulement par un fichier d'identifiants ou leur variable ; `MP_SEND_API_AUTH_ACCEPT_ANY`, `MP_ALLOW_INTERNAL_HTTP_REQUESTS` et `MP_DISABLE_VERSION_CHECK` à `false` ; `MP_SMTP_RELAY_CONFIG`, `MP_SMTP_RELAY_ALL`, `MP_SMTP_FORWARD_CONFIG`, `MP_WEBHOOK_URL` ; écoute sur `0.0.0.0:1025` et `0.0.0.0:8025` ; base par défaut dans un fichier temporaire supprimé à l'arrêt |
| <https://github.com/axllent/mailpit/releases> | 2026-11-24 | v1.34.0 marquée « Latest », publiée le 17 novembre à 06:57 ; aucune release plus récente |
| <https://docs.cloud.google.com/compute/docs/tutorials/sending-mail> (S56 de BENCH-013) | 2026-11-24 | Aucun service d'envoi managé par Google Cloud cité ; SendGrid, Mailgun, Mailjet, relais SMTP de Google Workspace sur 465 et 587, serveur hébergé sur un port non bloqué ; port 25 bloqué vers l'extérieur ; aucune date de mise à jour visible |
| <https://www.rfc-editor.org/rfc/rfc5321> | 2026-11-24 | « Simple Mail Transfer Protocol », octobre 2008, Draft Standard sur la voie des standards ; remplace la RFC 2821, mise à jour par la RFC 7504 |
| [docs/risques.md](../risques.md), R-04, R-20, R-25, R-36, R-37 | 2026-11-24 | Premier `task up` du profil standard à 1 802,1 Mo ; liste des valeurs connues ; registres publics ; R-36 étendu aux avis de Mailpit absents de la base mondiale ; parcours de connexion différent entre le PC et GCP |
| [ADR-005](ADR-005-gateway.md), condition 5 | 2026-11-24 | Parité des Gateway et HTTPRoute ; écart voulu par un ADR et une ligne du README |
| [ADR-006](ADR-006-orchestration-locale.md), condition 1 | 2026-11-24 | Aucun Secret sous `k8s/` ; ni Helm ni outil de boucle |
| [ADR-007](ADR-007-secrets.md), conditions 1 et 5, question 2 | 2026-11-24 | Création par un tube et liste des valeurs connues ; parité du nom et des clés ; identifiants de services tiers non tranchés |
| [ADR-008](ADR-008-modules-opentofu-gcp.md), condition 9, citée par BENCH-013 et l'ADR-013 | 2026-11-24 | Demandes explicites sur GKE Autopilot |
| [ADR-009](ADR-009-catalogue.md), section 2 et règles de date | 2026-11-24 | III fixe les candidats, V les départage ; `managed_gap` ; six mois entre deux vérifications |
| [ADR-011](ADR-011-miroir-registres.md), tableau des registres, conditions 4, 9, 10 et 13 | 2026-11-24 | docker.io servi par zot ; ligne « à relever » pour Mailpit ; domaine `.invalid` (RFC 2606) ; aucune redistribution ; liste unique des registres ; tirage anonyme |
| [ADR-012](ADR-012-postgres-local.md), conditions 1, 7, 9 et 10, dérogation | 2026-11-24 | Profil `restricted` du namespace de l'application ; contrôle de la liste fermée ; nom d'utilisateur fixe hors du test de répétition ; dérogation limitée à `docker.io/library/` |
| [ADR-013](ADR-013-fournisseur-identite.md), conditions 4 et 11, portée, questions 3 et 5, dérogation | 2026-11-24 | Désignation du proxy de la gateway ; limite de Keycloak sous 1 255 Mi en attente de BENCH-013 ; envoi de mails par Keycloak renvoyé à cet ADR ; standard sur 8 Gio non exigé ; inscription ouverte ; royaume sans secret ; modèle de dérogation |
| [`catalog/README.md`](../../catalog/README.md), `schema/catalog-entry.schema.json`, `scripts/catalog/accepted-licenses.yaml` | 2026-11-24 | Types `managed` et `oss`, `managed_gap` ; valeurs de `governance.model` ; liste fermée des standards, sans SMTP ; contrôles de date et avertissement sans standard commun ; `MIT` dans la liste blanche |
| [specs/001-golden-repo-saas-b2b/spec.md](../../specs/001-golden-repo-saas-b2b/spec.md), FR-003 à FR-009, FR-016, FR-018, FR-021, SC-008, hypothèses | 2026-11-24 | Boucle locale ; secrets ; profil standard avec Mailpit ; condensats ; code limité par Q7 ; redémarrage hors réseau ; écarts au README ; scan ; lite sur 8 Gio ; Kyverno en phase 4 |
| [plan.md](../../specs/001-golden-repo-saas-b2b/plan.md), étape 16 et matrice ; [tasks.md](../../specs/001-golden-repo-saas-b2b/tasks.md), T150 à T152 ; [research.md](../../specs/001-golden-repo-saas-b2b/research.md), RS-15 ; `contracts/secrets.md`, `data-model.md` | 2026-11-24 | `local/mail/` ; contrôles S01, S06, S07, S17, S23, P03, E03 à E05, E10, E11, E14, E25 à E27, D02, D03 ; chemin d'entrée d'une couche du profil standard |
| [docs/prd-mvp.md](../prd-mvp.md), US-005, ENF-01 à ENF-03, Q7 | 2026-11-24 | Profil standard de mesure ; volume du premier `task up` ; parité et écarts au README ; Kyverno refuse les images non signées ; l'exemple limité au code du blueprint |
| [Constitution](../../.specify/memory/constitution.md), version 1.2.0 | 2026-11-24 | Principes I à X ; dérogation justifiée dans un ADR ; exception de sécurité au délai de 7 jours |
