# ADR-013. Le fournisseur d'identité du projet généré est Keycloak sur `local` et Identity Platform sur `gcp`, l'API vérifiant elle-même les jetons des deux, sous conditions et avec une dérogation datée à ENF-03

| Champ | Valeur |
| --- | --- |
| Statut | accepté |
| Date | 2026-11-24 |
| Auteur | [ARCHI] |
| Décideur | Lucas, décisions et acceptation du 2026-11-24 sur BENCH-012 |
| BENCH lié | [BENCH-012](../benchmarks/BENCH-012-fournisseur-identite.md) |
| Remplace | aucun |

## Contexte et problème

Le profil standard du projet généré ajoute au profil lite Flux, un fournisseur d'identité et un serveur de mails de test (décision de Lucas du 2026-11-20, US-005, FR-006 de la spec 001). C'est lui qui sert de mesure au critère des 15 minutes (ENF-01, section 7 du PRD), si bien que le volume et la mémoire du fournisseur comptent directement dans R-04. FR-006 veut que Keycloak entre dans le golden repo après son benchmark : c'est BENCH-012, ouvert le 2026-11-20.

L'exemple applicatif n'a pas d'authentification aujourd'hui. Le DSI l'a décidé le 2026-11-21 (research RS-25 de la spec 001) avec une règle : aucun déploiement réel sur GCP sans authentification, puisque la Gateway de GKE publierait l'API à tous. Le même point note que brancher l'API sur un fournisseur d'identité ajoute du code au-delà de FR-009 (contrôle de santé, exemple, front), et qu'il faudra un amendement de la spec. Cet ADR dit ce qui doit changer ; il ne modifie pas la spec.

Les exigences viennent du PRD et de la spec. ENF-02 veut que chaque brique existe sur les deux cibles et que seule la couche de cible change, les écarts listés au README. ENF-03 veut que Kyverno refuse les images non signées. FR-004 et FR-005 veulent des secrets locaux aléatoires d'au moins 32 caractères, jamais dans un fichier, une variable affichée ou un argument, et un test sur une liste de valeurs connues. FR-008 fige chaque image par condensat, FR-021 fait scanner toute image en marche.

Les décisions acceptées posent leurs contraintes. [ADR-005](ADR-005-gateway.md) : exposition en boucle locale par Envoy Gateway sur `local`, par le contrôleur de GKE sur `gcp` ; sa condition 2 interdit de porter un contrôle de sécurité, une authentification par exemple, par une politique du groupe `gateway.envoyproxy.io` sans un ADR qui nomme son équivalent sur `gcp` ; sa condition 5 compare les Gateway et HTTPRoute des deux cibles. [ADR-006](ADR-006-orchestration-locale.md) : ni Helm ni outil de boucle, aucun objet `Secret` sous `k8s/` (condition 1). [ADR-007](ADR-007-secrets.md) : Secrets créés par `task up` par un tube, liste des valeurs connues (condition 1), même nom et mêmes clés sur les deux cibles (condition 5). [ADR-008](ADR-008-modules-opentofu-gcp.md) : couche OpenTofu de GCP, GKE Autopilot à nœuds privés, `requests` explicites (condition 9). [ADR-009](ADR-009-catalogue.md) : le principe III fixe les candidats d'une cible et le principe V les départage ; une cible `gcp` en `oss` exige un `managed_gap`. [ADR-011](ADR-011-miroir-registres.md) : toute image tirée par le nœud passe par le miroir zot, sous une liste unique de registres (condition 10). [ADR-012](ADR-012-postgres-local.md) : Postgres partagé dans le namespace de l'application, Secret et volume vivent ensemble (condition 3), rôle sans superutilisateur (condition 8), et une dérogation à ENF-03 limitée à `docker.io/library/`. Côté risques : R-04, R-05, R-20, R-25, R-28, et R-36, ouvert avec BENCH-012.

BENCH-012 a mesuré Keycloak et Zitadel avec le même script, trois exécutions chacune, le 2026-11-23. [SECU] et [FINOPS] l'ont relu le même jour, le DSI a arbitré le 2026-11-24, et Lucas a tranché trois points le même jour (BENCH-012, section 7). Le rapport signale un fait qui pèse plus sur cet ADR que sur la grille : le pendant managé sur GCP ne parle pas le même protocole à l'application. Identity Platform connecte les utilisateurs par les SDK et les bibliothèques d'interface de Google, et ne décrit aucun rôle de serveur d'autorisation pour une application cliente (BENCH-012, section 2, S47). Cet ADR tranche donc aussi ce que le rapport laissait à [ARCHI] : comment l'API vérifie les jetons des deux fournisseurs, ce que fait le front sur chaque cible, ce que le golden repo teste, et ce qui change ailleurs.

## Options considérées

Sur `local`, la grille réconciliée par le DSI le 2026-11-24 :

| Option | Score BENCH (sur 100) | Verdict | Raison principale |
| --- | --- | --- | --- |
| Keycloak 26.8.2, mode `start`, manifest de démarrage rapide adapté | 81 | retenue | Apache-2.0, comme le générateur ; CNCF au niveau Incubating, onze mainteneurs de quatre employeurs ; jeton vérifié et valeurs connues refusées à chaque exécution (M6, M8). Empreinte mémoire la plus lourde : 843,2 Mio de couche |
| Zitadel v4.20.5, chart 10.5.0 rendu | 62 | écartée | AGPL-3.0 depuis 2025, éditeur unique, six avis critiques en douze mois dont trois prises de compte sans authentification ; une image tierce qui écrit les Secrets. Ne reprend l'avantage que sur la mémoire, 262,9 Mio |
| Authentik 2026.8.6 | éliminée, non notée | éliminée | Critère de licence : l'image officielle charge au démarrage `authentik/enterprise/`, sous une licence non approuvée par l'OSI, même sans clé. Décision du DSI du 2026-11-21, preuve revérifiée par [SECU], confirmée par Lucas le 2026-11-24 |

Sensibilité, reprise du rapport : un cran vaut au plus 3 points, et il faudrait sept crans dans le sens de Zitadel pour combler l'écart. Avec 0/5 en empreinte pour Keycloak et 5/5 pour Zitadel, Keycloak garde 11 points d'avance. Le verdict ne repose sur aucun critère isolé. Si Lucas revenait sur Authentik, ses notes de lecture le placeraient derrière Keycloak.

Sur `gcp`, deux voies que la grille ne départage pas (BENCH-012, section 5.7) :

| Voie | Score | Verdict | Raison principale |
| --- | --- | --- | --- |
| Identity Platform, service managé de Google | non noté | retenue, décision de Lucas du 2026-11-24 (principe III) | Service managé qui couvre l'authentification des utilisateurs de l'exemple ; sans frais jusqu'à 50 000 utilisateurs actifs par mois, et jusqu'à 50 sur la ligne SAML/OIDC. Prix au-delà non lus (R-05). Prix : un parcours de connexion du front propre à la cible |
| Keycloak sur GKE, avec `managed_gap` | non noté | écartée | Garderait la parité, au prix d'un composant à exploiter et facturé : 500m et 1700Mi par réplique dans la référence, environ 22,2 USD par réplique et par mois aux prix d'exemple de us-central1, plus une base dans Cloud SQL. Le `managed_gap` devrait dire pourquoi Identity Platform ne couvre pas le besoin, alors qu'il couvre celui de l'exemple |

Grille, mesures et sources : [BENCH-012](../benchmarks/BENCH-012-fournisseur-identite.md).

## Décision

Sur la cible `local`, le projet généré fait tourner Keycloak 26.8.2 en mode `start` dans le profil standard, image `quay.io/keycloak/keycloak` figée par condensat, avec sa propre base et son propre rôle dans le Postgres partagé de l'ADR-012. Sur la cible `gcp`, il s'appuie sur Identity Platform. L'API vérifie elle-même les jetons des deux fournisseurs, par un contrat commun que la couche de cible paramètre. Le parcours de connexion du front appartient à la couche de cible.

Le condensat mesuré est celui du script de BENCH-012 : `quay.io/keycloak/keycloak:26.8.2@sha256:7e66a96e4739239070aeaf72e4c5decf0f7f682cfc725b9f7ea2b336eaba38b3` (`tests/bench/bench-012-identity.sh`, ligne 89, branche de la PR #43). C'est la troisième publication du tag, celle du 2026-11-19 (S66) ; Renovate la suit ensuite sous la condition 2.

Lucas a pris trois décisions le 2026-11-24 : Identity Platform sur `gcp`, la dérogation datée à ENF-03 de la section « Dérogations », et le maintien de l'élimination d'Authentik. La base de Keycloak dans le Postgres partagé suit la décision du DSI du 2026-11-20 (BENCH-012, section 4.1), et le mode `start` celle du 2026-11-21 (section 4.3). La validation de cet ADR revient à Lucas, avec cinq questions ouvertes.

### Répartition par couche

| Couche | Contenu |
| --- | --- |
| commune | Le code de vérification des jetons de l'API (section suivante) et l'interface de connexion du front. Les manifests de l'application lisent l'émetteur, l'audience, l'adresse et le format des clés dans `app-config`. Aucun nom de service, aucune adresse de Keycloak ni de Google, aucun SDK propre à une cible |
| `local` | Keycloak : StatefulSet d'une réplique, Service sans le port 9000, NetworkPolicy, royaume de l'application importé au démarrage, HTTPRoute vers ses chemins publics ; les tâches de `task up` qui créent ses deux Secrets, puis son rôle et sa base dans le Postgres partagé ; l'implémentation de la connexion du front par code d'autorisation avec PKCE ; les valeurs de `app-config` qui désignent Keycloak |
| `gcp` | La configuration d'Identity Platform dans la couche OpenTofu de l'ADR-008 (ressources `google_identity_platform_*` du provider `google`, S52) ; l'implémentation de la connexion du front par le SDK de Google ; les valeurs de `app-config` qui désignent l'émetteur de Google. Rien de Keycloak ne tourne dans le cluster GKE |

Les noms des Secrets de Keycloak, des clés de `app-config` et des chemins sous `local/` se fixent à l'étape 15 du plan, comme dans l'ADR-006 ; l'essai les appelait `idp-admin` et `idp-db`. Ces deux Secrets sont des Secrets de couche, comme `db-superuser` : ils n'ont pas de pendant sur `gcp`, et l'écart se liste au README (ENF-02).

### Vérification des jetons par l'API

Un seul code, dans la couche commune, pour les deux cibles. La couche de cible ne lui fournit que quatre valeurs : l'émetteur, l'audience, l'adresse des clés publiques et leur format. Ce contrat tient la condition 2 de l'ADR-005 : l'authentification se vérifie dans l'API, jamais dans une politique de la gateway, et rien ne disparaît en passant d'une cible à l'autre. Il tient aussi la règle de Lucas qui veut une authentification vérifiée côté serveur.

| Contrôle | Règle | Source |
| --- | --- | --- |
| Algorithme | `RS256` seulement ; tout autre `alg`, `none` compris, est refusé | S51 ; M6 pour Keycloak |
| Signature | Par la clé que désigne `kid` parmi celles de l'émetteur ; un `kid` inconnu déclenche un rafraîchissement borné des clés, puis un refus | S51 ; rafraîchissement borné : choix de [ARCHI] |
| Émetteur | `iss` égal à la valeur de la cible, à l'octet près | S51 |
| Audience | `aud` contient la valeur de la cible | S51 ; condition 8 de [SECU] |
| Expiration | `exp` dans le futur, `iat` dans le passé, tolérance d'horloge fixée par [DEV] et [SECU] | S51 |
| Sujet | `sub` non vide ; il porte l'appartenance des notes (section « Ce que l'ADR change ailleurs ») | S51 |

Valeurs par cible :

| Valeur | `local` | `gcp` |
| --- | --- | --- |
| Émetteur | L'URL publique du royaume de l'application, sous l'adresse que fixe `KC_HOSTNAME` (condition 4) | `https://securetoken.google.com/<projectId>` |
| Audience | L'identifiant du client de l'API, que le mappeur `oidc-audience-mapper` ajoute aux jetons d'accès du client du front (condition 8) | L'identifiant du projet |
| Clés | Le `jwks_uri` du document de découverte, lu par l'URL interne du Service | `https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com`, rafraîchies selon le `max-age` de l'en-tête `Cache-Control` |
| Format des clés | Jeu de clés JWK | Certificats, d'après le chemin `x509` ; la page n'en nomme pas le format |
| Jeton présenté | Jeton d'accès | Jeton d'identité, conforme à OpenID Connect d'après Google |

Trois points restent à vérifier. D'abord le chemin interne sur `local` : depuis un pod, l'adresse publique en boucle locale ne mène pas à Keycloak. L'option `hostname-backchannel-dynamic` résout dynamiquement les URL du canal arrière quand `hostname` est une URL complète (page `hostname` de Keycloak, lue le 2026-11-24). Ce que le document de découverte, lu par l'URL interne sous cette option, annonce comme `issuer` et comme `jwks_uri` n'a pas été essayé ([OPS], condition 4 de [SECU]). Ensuite, sur `gcp`, deux pages de Google donnent deux adresses de clés : celle de la page de vérification, retenue ici parce que la page d'Identity Platform y renvoie, et `https://www.googleapis.com/service_accounts/v1/metadata/x509/securetoken@system.gserviceaccount.com` dans celle de Cloud Endpoints. [DEV] et [SECU] confirment la première. Enfin, que le pod de l'API joigne cette adresse depuis des nœuds privés n'a pas été vérifié ([OPS]).

L'API n'a besoin d'aucun identifiant pour vérifier : ni secret de client chez Keycloak, ni compte de service chez Google. Elle ne lit que des clés publiques.

### Parcours de connexion du front

Le front porte une interface de connexion commune : obtenir un jeton, le joindre aux appels de `/api`, se déconnecter. Chaque couche de cible en fournit l'implémentation, choisie au moment où `task up` ou la CI construit l'image de la cible.

- Sur `local`, flux par code d'autorisation avec PKCE vers Keycloak, depuis un client public, sans aucun secret dans le navigateur (condition 8 de [SECU]).
- Sur `gcp`, connexion par le SDK de Google, que la page des concepts d'Identity Platform décrit (S47). Les appels d'authentification portent une clé d'API du projet, qui l'identifie sans rien autoriser. Google la dit non secrète une fois restreinte, et demande de resserrer le quota des points `identitytoolkit.googleapis.com` contre la force brute (S77, relue le 2026-11-24). Elle vit dans `app-config`, pas dans un Secret, et ce n'est jamais une clé de compte de service.

Le SDK de Google ne vit que dans la couche `gcp` : le principe II interdit de coder un service propre à une cible ailleurs que dans sa couche. L'image du front diffère donc d'une cible à l'autre par cette seule implémentation, comme l'image de l'API diffère par son étiquette. Le mécanisme de composition au build se fixe en phase 3 avec le blueprint ; le golden repo le prouve d'abord.

Le fournisseur de connexion de l'exemple sur `gcp` reste à choisir par [PO] et [DEV] parmi ceux qu'Identity Platform documente. Un fournisseur fédéré par SAML ou OIDC compte sur la ligne gratuite limitée à 50 utilisateurs par mois (S82, S50).

### Ce que le golden repo teste sur chaque cible

Le parcours diffère entre les cibles ; le contrat de vérification, lui, est le même. D'où trois niveaux de test.

Commun, sans cluster (tests unitaires de l'API et du front) :

- l'API accepte un jeton valide signé par une clé générée pour le test, servie dans chacun des deux formats ;
- elle refuse un `alg` autre que `RS256` (`none` et `HS256` compris), un `iss` voisin, une `aud` absente ou étrangère, un jeton expiré, un `iat` futur, un `kid` inconnu, un `sub` vide ;
- les routes de santé répondent sans jeton, les routes des notes répondent 401 sans jeton valide ;
- une note créée par un sujet répond 404 à un autre sujet, par la base comme par le cache ;
- le front joint le jeton à chaque appel de `/api`, avec chaque implémentation simulée.

`local`, profil standard, sur kind (CI amd64 et poste) :

- un jeton émis par le vrai Keycloak passe l'API ; le même jeton altéré, ou émis pour un autre client, est refusé ;
- le client du front est public, exige PKCE, n'accepte aucun flux par mot de passe, et n'a que des URI de redirection exactes ; les noms de ces réglages se lisent dans la documentation de 26.8.2 ([DEV]) ;
- les contrôles des conditions 1 à 13 ci-dessous.

Le client qui obtient un jeton de test est créé par le test et supprimé à la fin, avec un secret qui ne sort pas du pod de test. Il n'entre jamais dans le royaume livré, qui ne contient ainsi aucun secret.

`gcp`, sans cloud en phase 2 :

- `tofu validate` et conftest sur la configuration d'Identity Platform ;
- le rendu `gcp` de `app-config` porte l'émetteur de Google pour la variable du projet, l'audience égale au projet et l'adresse de clés retenue ;
- aucun objet de Keycloak dans le rendu `gcp` ;
- les tests unitaires de l'implémentation `gcp` du front.

Le parcours réel sur `gcp`, connexion par le front puis appel accepté par l'API, et refus d'un jeton d'un autre projet, se teste au premier déploiement réel, avec l'accord de Lucas et un budget de [FINOPS] (principe X). C'est le modèle de la condition 3 de l'ADR-007. Tant qu'il n'a pas passé, la ligne `gcp` du catalogue garde ce point en `pending` et la combinaison n'est pas proposée (principe I).

### Conditions

Les conditions 1 à 10 sont celles de [SECU], les conditions 11 à 13 celles de [FINOPS], retenues par le DSI le 2026-11-24 (BENCH-012, sections 7 et 10). Elles sont transposées à la décision de Lucas : Keycloak ne tourne que sur `local`, et ce que [SECU] demandait « sur `gcp` » pour Keycloak passe à Identity Platform ou devient sans objet, ce que chaque condition dit. Les conditions 14 à 16 sont des ajouts de [ARCHI]. La décision ne vaut qu'avec elles. Chaque contrôle cité entre dans la matrice de validation (principe I) ; [QA] lui donne son identifiant dans le plan.

1. Image et dérogation à ENF-03. `quay.io/keycloak/keycloak` est désignée par condensat et tirée par zot, avec `quay.io` dans la liste unique de la condition 10 de l'ADR-011. La dérogation datée de la section « Dérogations » l'admet par sa référence exacte, condensat compris, dans une liste fermée. Contrôles : S01 (condensat) ; E11 (hôte de registre dans la liste) ; dès qu'un profil embarque Kyverno, le contrôle de la condition 7 de l'ADR-012 étendu à `quay.io/keycloak/`.
2. Suivi. Keycloak ne corrige que sa dernière mineure, qui change environ chaque trimestre (S2, S7, S8). Renovate suit la mineure et le condensat. Une republication ou une version qui corrige un avis passe par l'exception de sécurité du principe VI. [OPS] vérifie comment `minimumReleaseAge` date une montée de condensat. [SECU] lit chaque mois les avis et les tickets `kind/cve` du dépôt (R-36). Contrôle : S23 étendu à l'image de Keycloak, relu par [SECU].
3. Durcissement. Le namespace applique le profil `restricted`. Le pod a `runAsNonRoot`, `allowPrivilegeEscalation: false`, les capacités `ALL` retirées, `seccompProfile: RuntimeDefault` et `automountServiceAccountToken: false` ; l'image tourne déjà sous l'UID 1000 (S18). `readOnlyRootFilesystem` s'essaie avec un `emptyDir`. Le port 9000, celui de la santé, n'est dans aucun Service. Contrôles : la matrice échoue sur un pod refusé par le profil ; un contrôle statique échoue sur un Service qui expose 9000.
4. Nom d'hôte et proxy. `KC_HOSTNAME` porte l'URL complète de la gateway en boucle locale, et `hostname-strict` garde son défaut, que `hostname` rend sans effet (page `hostname`, lue le 2026-11-24). `KC_PROXY_HEADERS` ne s'emploie qu'avec `KC_PROXY_TRUSTED_ADDRESSES` limité à la gateway (S70, S71) ; la façon de désigner les pods du proxy d'Envoy, dont l'adresse change, reste à trouver ([OPS]). `hostname-backchannel-dynamic` sert au chemin interne de l'API (section « Vérification des jetons »). Une NetworkPolicy limite le port 8080 au proxy de la gateway et à l'API. [OPS] vérifie qu'elle s'applique sous le CNI de kind. Sur `gcp`, sans objet. Contrôle : un `X-Forwarded-Host` forgé ne change pas l'émetteur du document de découverte.
5. Chemins exposés. Sur `local`, l'HTTPRoute de la couche n'envoie à Keycloak que des chemins publics que liste sa documentation, `/realms/` et `/resources/` ; jamais `/metrics` ni `/health` (S70). `/.well-known/` n'y entre que si un test en montre le besoin, parce que cette route prendrait ce préfixe au front, servi à la racine. La console d'administration suit la question 2. Sur `gcp`, aucune route d'identité : Identity Platform est servi par Google. Contrôles : par la gateway, `/metrics` et `/health` répondent 404 ; aucune HTTPRoute de la couche `gcp` ne vise un service d'identité.
6. Identifiants (R-20). Les deux Secrets de Keycloak, compte d'administration d'amorçage et rôle de la base, sont créés par `task up` selon la condition 1 de l'ADR-007, avec la liste étendue (section « Ce que l'ADR change ailleurs ») appliquée à toutes les clés secrètes de la couche, pas seulement aux mots de passe. Le contrôle du type de M8 exige `invalid_grant` pour chaque valeur connue et l'acceptation de la valeur du Secret ; il reste sous le seuil de la détection de force brute de la condition 7, et ne passe aucun secret en argument. Le client HTTP de la mesure, qui passait un PAT et un en-tête `Basic` en argument, n'y est pas repris (BENCH-012, section 8). Sur `local`, le compte d'amorçage reste, temporaire par conception (S16), et le README le dit. Sur `gcp`, sans objet pour Keycloak. Contrôles : E04 et E05 étendus à la couche ; le contrôle du type de M8.
7. Force brute. La création d'un royaume, `master` compris, désactive la détection (S69). `bruteForceProtected` est activé sur `master` et sur le royaume de l'application ; le mécanisme pour `master`, créé au premier démarrage, se fixe à l'étape 15 ([DEV]). Contrôle : la matrice lit le réglage des deux royaumes.
8. Jetons. Les jetons de la mesure portaient `aud: account`. Le client du front reçoit donc un mappeur `oidc-audience-mapper`, dont le champ « Included Client Audience » désigne le client de l'API ; « Add to access token » vaut `true` par défaut (page des mappeurs de protocole, lue le 2026-11-24, nom que [SECU] demandait à [ARCHI] de vérifier). L'API vérifie `RS256`, l'émetteur, l'audience et l'expiration (section « Vérification des jetons »). Le front est un client public avec PKCE, sans aucun secret dans le navigateur. Avec Identity Platform, l'API exige `aud` égal au projet (S51), et la clé d'API est restreinte, quotas resserrés (S77) ; les ressources OpenTofu qui le portent ne sont pas vérifiées ([OPS]). Contrôles : les tests communs et `local` de la section précédente ; une politique conftest sur la restriction de la clé, une fois ses ressources lues.
9. Base et transport. Le rôle de Keycloak n'est pas superutilisateur, comme celui de l'application (condition 8 de l'ADR-012). Sur `local`, le HTTP de Keycloak et sa connexion à Postgres, dont l'état TLS n'est pas mesuré (ADR-012), sont des écarts listés au README. `http-max-queued-requests` est fixé (S72). Une seule réplique sur `local` : la NetworkPolicy des ports 7800 et 57800 devient obligatoire si une seconde entre. Sur `gcp`, sans objet pour Keycloak ; l'émetteur et les clés de Google sont servis en HTTPS. Contrôles : E12 étendu au rôle de Keycloak ; un contrôle statique sur `http-max-queued-requests`.
10. GKE et premier déploiement. Aucun déploiement en phase 2. Le premier, configuration d'Identity Platform comprise, attend l'accord de Lucas et un budget de [FINOPS]. L'import du royaume au démarrage, que la documentation juge surtout utile en mode dev (S14), ne sert que sur `local`. Contrôle : S17, qui refuse tout plan et tout apply en CI.
11. Limite mémoire, de [FINOPS]. La limite du conteneur de Keycloak est fixée et mesurée sur le golden repo, pour que le profil standard tienne sur un portable de 8 Gio avec Mailpit. Le tas de la JVM peut monter à 70 % de la limite (S14). Avec la limite de la référence, 2000Mi, le plancher du profil passerait à environ 3 475,1 Mio, soit 9,5 Gio de portable ; pour tenir sur 8 Gio avant Mailpit, la limite devrait rester sous 1 255 Mi environ, ordre de grandeur de [FINOPS]. La valeur finale attend BENCH-013. Demande et limite sont explicites : la référence demande 1700Mi, plus que la limite visée. Contrôles : un contrôle statique sur la présence de la demande et de la limite ; D02 et D03 étendus au profil standard, pic de démarrage et repos relevés avec la limite retenue.
12. Miroir, de [FINOPS]. `quay.io` entre dans la liste unique des registres (condition 10 de l'ADR-011). Sans lui, 265,1 Mo repartent d'Internet à chaque création du cluster (M5). Contrôle : E10 en profil standard, avec l'image de Keycloak.
13. Volumes, de [FINOPS]. R-04 passe à 1 787,0 Mo pour le premier `task up` du profil standard, Mailpit non compté : 158,8 % du budget de 900 s à 10 Mbit/s, 15,9 Mbit/s au minimum. ENF-01 se met à jour dans le PRD. Contrôle : D02.
14. Contrat commun et couche commune neutre, ajout de [ARCHI]. La vérification de l'API et l'interface du front sont communes ; l'émetteur, l'audience, l'adresse et le format des clés viennent de `app-config`. Contrôles : les tests communs de la section précédente ; S06 étendu : la couche commune et le code commun ne contiennent ni adresse de Keycloak ni de Google, ni SDK propre à une cible ; S07 compare les références à `app-config` des deux rendus.
15. Rôle et base de Keycloak dans le Postgres partagé, ajout de [ARCHI]. Les scripts d'initialisation de l'image officielle ne tournent que sur un volume vide (ADR-012, condition 3). Le rôle et la base de Keycloak se créent donc par une étape de `task up` propre au profil standard, idempotente, lancée avec le Secret du superutilisateur, le mot de passe passé par un tube. Un cluster né en profil lite puis relancé en standard reçoit ainsi sa base. Le Secret de la base de Keycloak suit la règle de la condition 3 de l'ADR-012 : volume présent et Secret absent, `task up` s'arrête. Contrôles : un passage du lite au standard sur le même cluster ; E21 étendu à ce Secret.
16. Réglages propres au PC, ajout de [ARCHI]. `KC_HTTP_ENABLED`, `KC_PROXY_HEADERS` et `hostname-backchannel-dynamic`, comme l'import au démarrage, ne valent que dans la couche `local`. Contrôle : aucun objet ni réglage de Keycloak dans le rendu `gcp` ni dans la couche commune.

Les conditions des ADR-004 à ADR-012 restent en vigueur, en particulier les images par condensat (condition 3 de l'ADR-004), l'absence de Secret sous `k8s/` (condition 1 de l'ADR-006), la création des Secrets par un tube (condition 1 de l'ADR-007), la liste unique des registres (condition 10 de l'ADR-011) et le rôle sans superutilisateur (condition 8 de l'ADR-012).

### Les réglages `start` qui ne passent pas sur GKE

[SECU] a relevé quatre réglages de la couche mesurée qui ne valent que pour un PC à un seul utilisateur : nom d'hôte non strict, en-têtes de proxy acceptés de partout, HTTP en clair, aucun `securityContext`. Les conditions 3 et 4 en retirent deux sur `local` même. Les deux autres, HTTP et en-têtes de proxy limités à la gateway, restent sur `local` et sont listés au README.

Avec Identity Platform sur `gcp`, aucun de ces réglages n'atteint GKE, et la condition 16 le vérifie. Si la décision se rouvrait vers Keycloak sur GKE, l'ADR qui la remplacerait reprendrait ce qu'en dit [SECU] (BENCH-012, section 10) : TLS jusqu'au pod ou à la gateway, administration sur un autre nom ou chemin, compte d'amorçage remplacé puis supprimé, NetworkPolicy des ports du cache, base dans Cloud SQL en TLS, `requests` explicites (condition 9 de l'ADR-008).

### Mémoire et profil standard

[FINOPS] place le profil standard avec Keycloak au repos à 2 295,0 Mio de plancher, soit 3,5 Gio de VM et 7,5 Gio de portable, avec 435,7 Mio de marge avant Mailpit sur un portable de 8 Gio. Ce cadre tient au repos, pas à la limite de la JVM, et le pic de démarrage n'est pas mesuré (BENCH-012, section 8). La spec ne demande que le profil lite sur 8 Gio (SC-008). Si aucune limite ne fait tenir le standard sur 8 Gio avec Mailpit, le standard demande plus de 8 Gio, le lite reste le profil des petits postes, et `task up` le dit : c'est la question 3.

### Registre et miroir

L'image vient de quay.io, troisième amont du miroir après docker.io et ghcr.io. Le mécanisme à plusieurs amonts n'est pas établi : l'ADR-011 laisse à [OPS] les montages a et b. Le montage b ajouterait une instance de zot, environ 51 Mio d'après une extrapolation non mesurée. [FINOPS] estime le stockage de zot à 831,6 Mo en amd64 pour le profil standard avec Keycloak, une estimation qu'aucune mesure ne confirme.

Le workflow de publication de Keycloak pousse aussi l'image sur Docker Hub (S65). Que le condensat y soit le même, et sous quel nom, n'a pas été vérifié. Si quay.io ne passait pas par zot, cette copie serait la piste à étudier, avec une dérogation réécrite et relue par [SECU].

### Ce que l'ADR change ailleurs

Aucun de ces fichiers n'est modifié par cet ADR. Chaque changement passe par sa PR, chez son porteur.

- Spec 001, pour [PO] puis Lucas. FR-009 s'amende : l'exemple vérifie un jeton sur les routes des notes, et les notes appartiennent au `sub` du jeton. Une note d'un autre sujet répond 404, par la base comme par le cache : un utilisateur ne lit pas la donnée d'un autre en changeant l'identifiant de l'adresse. Les routes de santé restent publiques. Le front reçoit l'interface de connexion et ses deux implémentations. Le contrat `contracts/http-api.md` perd sa ligne « aucune authentification en local » et reçoit le 401 ; `data-model.md` reçoit le propriétaire d'une note et le palier du profil standard, 3,5 Gio de VM avant Mailpit ; `contracts/secrets.md` reçoit les deux Secrets de couche. FR-006 et l'hypothèse de la spec sur Keycloak renvoient à cet ADR.
- RS-25 et RS-15 du plan, pour [DEV]. La règle « aucun déploiement réel sur GCP sans authentification » reste, et devient tenable : le premier déploiement réel attend que le parcours `gcp` soit branché et que les routes des notes refusent un appel anonyme. RS-15 tombe une fois FR-009 amendé : l'API vérifie les jetons sans appeler Keycloak à chaque requête, puisqu'elle ne lit que ses clés. L'étape 15 du plan reçoit les contrôles des conditions 1 à 16, et la tâche T149 perd sa mention « l'API n'appelle pas Keycloak ».
- ADR-007. Il n'est pas remplacé. La liste des valeurs connues de la condition 1 reçoit trois valeurs relevées par [SECU] : `keycloak`, mot de passe de base du manifest de démarrage rapide (S12) ; `change_me`, exemple de la page des conteneurs (S14), qui diffère de `changeme` ; `Password1!`, défaut de Zitadel (S59) et valeur du démarrage rapide de son chart (S74). Le test vise toutes les clés secrètes d'une couche, pas seulement les mots de passe. Deux Secrets de couche s'ajoutent sur `local`, sans pendant sur `gcp` : la condition 5 reste tenue, puisque l'application ne les lit pas. La clé d'API d'Identity Platform n'est pas un secret (S77) et n'entre pas dans Secret Manager.
- ADR-011. Il n'est pas remplacé. La ligne « à relever » de son tableau des registres devient, pour Keycloak : quay.io, `keycloak/keycloak`, containerd du nœud, profil standard, non mesuré. Le montage retenu pour plusieurs amonts doit servir trois amonts dans le profil standard.
- ADR-012. Il n'est pas remplacé. Le Postgres partagé reçoit le rôle et la base de Keycloak (condition 15), et sa dérogation reste limitée à `docker.io/library/`.
- ADR-005. Il n'est pas remplacé. La couche `local` ajoute une HTTPRoute vers Keycloak, sur la Gateway commune. C'est un écart voulu entre cibles, que sa condition 5 admet par un ADR et une ligne du README ; la couche commune reste identique sur les deux rendus (S07).
- ADR-008. La couche OpenTofu reçoit la configuration d'Identity Platform et l'activation de son API. Les attributs des ressources `google_identity_platform_*` ne sont pas vérifiés ([OPS]).
- Catalogue, pour la PR de schéma de la phase 3 : l'entrée `identity` (section « Entrée au catalogue ») et deux valeurs de standards.
- PRD, pour [PO] : ENF-01 à 1 787,0 Mo ; la dérogation à ENF-03 citée sous l'exigence.
- Registre des risques, pour le DSI : R-04 et R-36 sont déjà écrits dans la branche de BENCH-012 ; R-20 reçoit les trois valeurs connues ; un risque nouveau est proposé, R-37 « Parcours de connexion différent entre le PC et GCP » (section « Négatives »).

### Portée

La spec déclare une brique abstraite, `identity` (nom proposé par BENCH-012, `declared_by: spec`), sans nommer Keycloak ni Identity Platform, qui vivent dans les couches de cible et au catalogue (principe II). La décision couvre la cible `local` en profil standard, une réplique, et la cible `gcp` décrite en code, sans déploiement.

Restent hors de cette décision :

- la gestion des utilisateurs d'un client réel, la fédération avec un annuaire d'entreprise et les locataires d'Identity Platform (BENCH-012, section 1) ;
- les rôles et autorisations au-delà de l'appartenance d'une note à son sujet ;
- le profil lite, sans fournisseur d'identité, que traite la question 1 ;
- la construction d'une image optimisée de Keycloak par le projet, que la documentation recommande (S14) et qui toucherait l'ADR-006 ;
- l'envoi de mails par Keycloak, qui suivra l'ADR-014 de Mailpit ;
- l'on-prem et Windows (Q5).

## Conséquences

### Positives

- Sur `local`, une brique prête en 25,7 s de médiane (M1), de retour en 21,4 s après la suppression de son pod (M7), qui sert un jeton vérifié et refuse les valeurs connues à chaque exécution (M6, M8), sans redémarrage de pod pendant l'installation.
- Une seule image de 265,1 Mo en amd64, contre 463,8 Mo pour Zitadel ; le premier `task up` du profil standard reste 198,7 Mo sous ce qu'il serait avec Zitadel.
- Un projet de fondation sous Apache-2.0 : le principe V ne demande aucune justification.
- Sur `gcp`, aucun pod d'identité à exploiter ni à payer : une démo reste dans la franchise d'Identity Platform.
- Un contrat de vérification unique, testé sans cluster sur les deux formats de clés. L'API n'a aucun identifiant à garder pour vérifier un jeton.
- Le royaume livré ne contient aucun secret : client du front public, API sans client confidentiel, client de test créé et supprimé par le test.
- La règle de RS-25 devient tenable sans changer de principe.

### Négatives

- R-37, proposé au DSI : le parcours de connexion diffère entre le PC et GCP. Une erreur dans l'implémentation `gcp` du front ou dans la configuration d'Identity Platform ne se voit que sur GCP, au premier déploiement réel, qui demande une dépense. Mitigation : contrat commun testé sur les deux formats, tests unitaires de chaque implémentation, test du parcours réel avant toute proposition de la combinaison `gcp`, écart listé au README.
- Le front embarque deux implémentations, et l'image du front diffère d'une cible à l'autre. Le mécanisme de composition reste à écrire.
- La clé d'API d'Identity Platform part dans le navigateur. Google la dit publique, et c'est la seule clé autorisée côté client par la règle de Lucas ; elle doit rester restreinte et sous quotas (S77), sinon elle ouvre une force brute sur les points de connexion.
- Mémoire : 843,2 Mio de couche au repos, 64,7 % au-delà du seuil de 512 Mio, et deux paliers de VM de plus pour le profil standard. Le profil ne tient sur 8 Gio qu'au repos, et la limite de la JVM peut le faire sortir de ce cadre (condition 11).
- Volume : 265,1 Mo de plus, R-04 à 158,8 % du budget à 10 Mbit/s.
- ENF-03 n'est pas tenu : aucune signature, et un tag republié trois fois en dix jours (S66). Chaque condensat neuf refait confiance à quay.io, et la base `ubi9-micro` est tirée sans tag ni condensat par le Dockerfile de Keycloak (S18).
- R-36 : une partie des CVE de Keycloak n'a pas de paquet associé dans la base mondiale, 16 sur 20 dans l'échantillon de [SECU] ; le scan de FR-021 ne les voit pas. 228 tickets de CVE hors dépendances en douze mois, et des correctifs sur la seule dernière mineure : le blueprint suit chaque mineure.
- Gouvernance : IBM tient huit mainteneurs sur onze.
- L'import du royaume est sauté si le royaume existe (S15) : un royaume modifié par une mise à jour du blueprint n'atteint pas un cluster existant tant que sa base n'est pas recréée, comme les variables `POSTGRES_*` de l'ADR-012.
- Sur `gcp`, dépendance à un service de Google seul, sans fondation. Sa dernière note de version date du 2024-12-03 (S48). Au-delà de 50 utilisateurs fédérés par mois, le coût n'est pas connu (R-05).
- Mesures d'un seul poste, arm64 sous OrbStack, moteur non libre (R-26). Restent non mesurés : le pic de démarrage, une limite sous 1 255 Mi, le chemin interne de l'API, la NetworkPolicy sous kind, `readOnlyRootFilesystem` et quay.io à travers zot ; rien n'a tourné côté GCP.

### Effet sur les cibles hors MVP

La porte reste ouverte. Le contrat de vérification de l'API ne dépend que d'un émetteur, d'une audience et de clés publiques : une cible AWS ou Azure fournirait les siennes par sa couche, avec l'implémentation de connexion de son service managé, que cet ADR n'a pas étudié. Une cible on-prem serveurs reprendrait Keycloak, sous les réglages de production que la section sur GKE énumère, après son propre benchmark.

### Suites

- [DEV] et [OPS], étape 15 du golden repo : la couche Keycloak sous les conditions 1 à 16 ; l'étape idempotente du rôle et de la base ; le mécanisme pour `master` (condition 7) ; le chemin interne et `hostname-backchannel-dynamic` ; la NetworkPolicy sous kind ; la désignation de la gateway dans `KC_PROXY_TRUSTED_ADDRESSES` ; `readOnlyRootFilesystem` ; la limite mémoire, après BENCH-013.
- [DEV], après l'amendement de FR-009 : la vérification commune de l'API et ses tests sur les deux formats ; l'interface du front et ses deux implémentations ; l'appartenance des notes.
- [OPS] : quay.io comme troisième amont du miroir ; la date que `minimumReleaseAge` donne à une montée de condensat ; les ressources OpenTofu d'Identity Platform et de la restriction de la clé d'API ; l'accès des nœuds privés à l'adresse des clés de Google.
- [QA] et [SECU] : les identifiants et l'ordre des contrôles dans la matrice ; la relecture de la liste fermée à chaque montée de condensat ; la lecture mensuelle des avis et des tickets `kind/cve` (R-36).
- [FINOPS] : la limite mémoire et le palier du profil standard après BENCH-013 ; les prix d'Identity Platform au-delà de la franchise, avant la GATE 2 (R-05).
- [PO] : l'amendement de FR-009 et des contrats ; ENF-01 dans le PRD ; le fournisseur de connexion de l'exemple sur `gcp`.
- DSI : R-20 et R-37 au registre ; le suivi de la levée de la dérogation ; l'entrée `identity` dans la PR de schéma de la phase 3.

### Questions ouvertes

1. Profil lite sans fournisseur d'identité, pour Lucas. Le lite n'embarque pas Keycloak, et les routes des notes exigeraient un jeton qu'aucun fournisseur n'émet. Trois voies. Un mode sans vérification, cantonné au rendu `local` du profil lite ; un contrôle statique le refuse dans la couche commune, dans le rendu standard et dans le rendu `gcp`, et l'API l'annonce au démarrage. Keycloak dans le lite aussi, qui y ajouterait 843,2 Mio et 265,1 Mo. Ou un lite sans routes des notes, qui ne montre plus l'exemple. Avis de [ARCHI] : le mode sans vérification, en boucle locale seulement, parce que le lite reste celui des petits postes ; c'est le seul endroit où une API sans authentification serait admise, et le contrôle statique l'y enferme.
2. Console d'administration de Keycloak sur `local`, pour Lucas. Par la gateway, sous `/admin/`, en boucle locale comme le reste ; ou hors de la gateway, par un `kubectl port-forward --address 127.0.0.1` et l'option `hostname-admin` (page `hostname`, lue le 2026-11-24). Avis de [ARCHI] : par la gateway, route de la seule couche `local`. La gateway n'écoute qu'en 127.0.0.1 (FR-003), si bien que les deux voies n'ouvrent la console qu'aux processus du poste. `KC_HOSTNAME` suffit à la première, alors que la seconde ajoute une adresse, un port et un processus à tenir.
3. Profil standard sur 8 Gio, pour Lucas et [FINOPS]. Si aucune limite mémoire mesurée ne fait tenir le standard sur 8 Gio avec Mailpit (condition 11), le standard demande plus de 8 Gio. Avis de [ARCHI] : l'accepter, puisque SC-008 ne vise que le lite ; `task up` choisit alors le lite sur 8 Gio et le dit (FR-006). L'autre voie, Zitadel, garderait 580,3 Mio de moins au nœud mais rouvrirait la décision contre 19 points de grille.
4. Date de relecture de la dérogation, pour Lucas. Proposée au plus tard le 2027-05-23, date de la prochaine vérification de BENCH-012, en plus de la relecture de [SECU] à chaque montée. Avis de [ARCHI] : cette date, sauf si Keycloak annonce une signature avant.
5. Comptes de l'exemple sur `local`, pour [PO] et [SECU]. Pour se connecter au front, il faut un utilisateur. Le guide d'administration de Keycloak 26.8.2 a une section sur l'inscription d'un nouvel utilisateur (« Registering as a new user »), lue par son titre seulement. Avis de [ARCHI] : inscription ouverte dans le royaume de l'application sur `local`, sans utilisateur créé d'avance, donc aucun identifiant par défaut à tirer ni à afficher ; vérification par mail quand Mailpit sera entré (ADR-014). Le réglage exact se lit sur la documentation de 26.8.2 ([DEV]).

### Réponses de Lucas (2026-11-24)

Lucas accepte cet ADR le 2026-11-24, avec les avis du DSI et de [ARCHI] sur
les cinq questions :

- Le profil lite n'a pas de fournisseur d'identité : l'API y tourne dans un
  mode sans vérification, enfermé dans le rendu lite de la cible `local` par
  un contrôle statique (question 1).
- La console d'administration de Keycloak sur `local` passe par la gateway,
  qui n'écoute qu'en boucle locale (question 2).
- Si aucune limite mémoire ne fait tenir le profil standard sur un portable
  de 8 Gio avec Mailpit, l'écart est accepté : SC-008 ne vise que le profil
  lite (question 3).
- La dérogation à ENF-03 est relue au plus tard le 2027-05-23, et par [SECU]
  à chaque montée (question 4).
- En local, l'inscription est ouverte et aucun utilisateur n'est créé
  d'avance ; les tests créent les leurs (question 5).

## Conformité à la constitution

Vérifiée contre la [constitution](../../.specify/memory/constitution.md) en version 1.2.0.

| Principe | Effet | Justification |
| --- | --- | --- |
| I. Rien sans test automatique | respecté | La matrice porte les contrôles des conditions 1 à 16 et les tests des trois niveaux ; le parcours réel sur `gcp` attend le premier déploiement, et la combinaison n'est pas proposée avant |
| II. Spec abstraite, catalogue concret | respecté | La spec déclare `identity` ; Keycloak vit dans la couche `local`, Identity Platform et le SDK de Google dans la couche `gcp` ; le code commun ne lit que des valeurs de `app-config` (condition 14) |
| III. Managé sur le cloud, open source ailleurs | respecté | Sur `local`, Keycloak sous Apache-2.0, gratuit ; sur `gcp`, Identity Platform, service managé de Google, sans `managed_gap` |
| IV. Catalogue traçable | respecté | L'entrée `identity` porte licence, gouvernance, statut, dates et sources ; ses `pending` l'écartent des blueprints jusqu'aux vérifications du golden repo, qui n'en est pas un |
| V. Gouvernance ouverte d'abord | respecté | Keycloak est porté par la CNCF, au niveau Incubating, avec des mainteneurs de quatre employeurs ; Zitadel, à éditeur unique, finit derrière. Identity Platform est imposé par III, sans justification à fournir (ADR-009) |
| VI. Récent mais éprouvé | respecté | Aucun critère éliminatoire : Apache-2.0, dépôt actif, 26.8.2 du 2026-11-05, publiée depuis plus de 7 jours ; 59 adoptants en référence publique. Le condensat du 2026-11-19 est une republication qui corrige des CVE de la base (S65), sous l'exception de sécurité ; comment Renovate la date reste à vérifier (condition 2) |
| VII. Une commande pour démarrer | respecté | `task up` crée les Secrets, le rôle et la base de Keycloak, applique la couche et attend le document de découverte, sans prérequis nouveau |
| VIII. Aucun fait de mémoire | respecté | Les faits renvoient à BENCH-012, à ses relectures, à son script et aux pages lues le 2026-11-24. Sont signalés comme non vérifiés : le chemin interne et ce qu'annonce le document de découverte sous `hostname-backchannel-dynamic`, l'adresse des clés de Google entre deux pages, l'accès depuis des nœuds privés, la NetworkPolicy sous kind, la désignation de la gateway comme proxy de confiance, `readOnlyRootFilesystem`, le pic mémoire, quay.io à travers zot, la copie sur Docker Hub, les ressources OpenTofu d'Identity Platform et de la clé d'API, les noms des réglages du client du front et de l'inscription |
| IX. Aucun secret dans le dépôt | respecté | Aucun objet `Secret` versionné ; les deux Secrets de Keycloak naissent par un tube ; le royaume livré n'en contient aucun ; la clé d'API d'Identity Platform est publique et restreinte (S77) ; trois valeurs connues de plus refusées |
| X. Aucune dépense cloud sans accord | respecté | Rien n'est créé sur GCP ; la configuration d'Identity Platform est validée sans apply, et son premier déploiement attend l'accord de Lucas et un budget de [FINOPS] |

### Dérogations

Une dérogation, décidée par Lucas le 2026-11-24, sur le modèle de celle de l'ADR-012. Elle ne vise aucun principe de la constitution : ENF-03 est une exigence du PRD. Elle s'écrit ici parce que la section « Gouvernance » de la constitution veut qu'une dérogation se justifie dans un ADR, avec sa durée et la condition qui la lèvera, et parce que celle de l'ADR-012 ne couvre que `docker.io/library/`.

| Principe | Écart | Justification | Durée | Condition de levée |
| --- | --- | --- | --- | --- |
| Aucun : exigence ENF-03 du PRD, « Kyverno refuse les images non signées » | L'image `quay.io/keycloak/keycloak` n'a aucune signature vérifiable. Kyverno l'admet par sa référence exacte, condensat compris, inscrite dans une liste fermée | FR-008 reste tenu : le condensat fige le contenu, que containerd vérifie. Le workflow de publication construit et pousse l'image sans cosign ni attestation, et quay.io ne porte aucun tag de signature pour le condensat mesuré (S65, S66). Aucune des options mesurées n'a d'image signée. [SECU] recommande cette voie | Depuis le 2026-11-24, jusqu'à sa levée. Relecture au plus tard le 2027-05-23 (question 4), et par [SECU] à chaque montée, republications comprises | Keycloak signe ses images de façon vérifiable par Kyverno : la politique vérifie alors la signature, et la liste fermée disparaît pour cette image. [SECU] propose une seconde voie, une image optimisée construite et signée par le projet (S14), qui demanderait un ADR touchant l'ADR-006 |

Portée. La seule image `quay.io/keycloak/keycloak`, pas les autres dépôts de quay.io. Une autre image sans signature entre par son propre ADR.

Tenue de la liste. Elle naît avec le premier profil qui embarque Kyverno, en phase 4 ; d'ici là, la dérogation n'a pas d'effet. Elle change dans la même PR que le manifest qui change l'image, PR de Renovate comprise. [SECU] relit chaque condensat neuf, parce que le tag se republie à chaque base qui corrige des CVE : trois condensats entre le 2026-11-09 et le 2026-11-19 (S66). Le contrôle de la condition 1 refuse tout écart entre la liste et les images en marche. Le DSI suit la levée au registre des risques.

## Entrée au catalogue

Brique abstraite : `identity`, déclarée par la spec (`declared_by: spec`), nom proposé par BENCH-012. Le nom se confirme en phase 3 avec le schéma de spec, comme `secrets` (ADR-007). L'entrée s'écrit au format de l'[ADR-009](ADR-009-catalogue.md), dans la PR de schéma de la phase 3 ; cet ADR ne crée pas le fichier.

| Cible | Service | Type | Licence | Gouvernance | Statut | Vérifié le | Source |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `local` | Keycloak, image officielle `quay.io/keycloak/keycloak` dans un StatefulSet de la couche `local` | `oss` | Apache-2.0 | Fondation : CNCF, Incubating depuis le 2023-04-10 | actif | 2026-11-23 | <https://github.com/keycloak/keycloak>, <https://www.cncf.io/projects/keycloak/> |
| `gcp` | Identity Platform | `managed` | service propriétaire du fournisseur | Éditeur unique : Google | actif | 2026-11-23 | <https://docs.cloud.google.com/identity-platform/docs/concepts-authentication>, <https://firebase.google.com/pricing> |

Ce que porte la ligne `local`, d'après BENCH-012 :

| Champ | Valeur |
| --- | --- |
| `service` | Keycloak, image officielle `quay.io/keycloak/keycloak` dans un StatefulSet de la couche `local` |
| `version` | 26.8.2 |
| `license` | `Apache-2.0`, présent dans `scripts/catalog/accepted-licenses.yaml` ; image bâtie sur Red Hat UBI 9 micro, dont le contrat laisse chaque composant sous sa licence libre (S67) |
| `governance` | `foundation`, CNCF : Incubating depuis le 2023-04-10 ; onze mainteneurs actifs de quatre employeurs, dont huit chez IBM (S3, S5) |
| `status` | `active`, dépôt non archivé, dernier push le 2026-11-20 (S1) |
| `last_release_on` | 2026-11-05, 26.8.2 (S2) |
| `verified_on` | 2026-11-23, le `read_on` le plus récent des sources de la ligne : S66 relue ce jour par [SECU] |
| `standards` | `openid-connect` et `jwt`, deux valeurs à ajouter à la liste fermée du schéma, avec leurs sources dans `catalog/README.md` |
| `sources` | S1, S2, S3, S5, S7 et S66 de BENCH-012, avec leurs URL et leurs dates |
| `decisions` | ADR-013, BENCH-012 |
| `pending` | limite mémoire ([FINOPS], [OPS]) ; quay.io à travers zot ([OPS]) ; chemin interne de l'API ([OPS]) ; NetworkPolicy sous kind ([OPS]) ; `readOnlyRootFilesystem` ([OPS]) |

La ligne `gcp` est de type `managed`, `provider: google`, gouvernance `single-vendor` Google, standard `jwt`, décisions ADR-013 et BENCH-012. Elle n'a pas de `managed_gap`. Ses sources sont S46, S47, S48 et S51, lues le 2026-11-20, et S82, lue le 2026-11-23. Ses `pending` : parcours réel au premier déploiement ([QA], [OPS]) ; ressources OpenTofu de la configuration et de la restriction de la clé d'API ([OPS]) ; prix au-delà de la franchise ([FINOPS], R-05) ; accès des nœuds privés à l'adresse des clés ([OPS]).

Les standards. La liste fermée du schéma compte aujourd'hui `kubernetes-api`, `gateway-api`, `postgresql-protocol`, `resp` et `otlp` (`schema/catalog-entry.schema.json`), sans valeur pour l'identité. Ce que les deux cibles partagent est le jeton signé que l'API vérifie, d'où `jwt` sur les deux lignes. `openid-connect` ne va qu'à la ligne `local` : Google dit ses jetons d'identité conformes à OpenID Connect, mais Identity Platform ne joue pas le rôle de serveur d'autorisation pour l'application (S47). Les deux noms sont des propositions de [ARCHI], à sourcer dans la PR de schéma.

Le condensat de l'image reste dans le blueprint, que Renovate met à jour, comme le veut l'ADR-009. Le contrôle de l'ADR-009 en tirerait ces échéances pour la ligne `local` : le critère des 12 mois tombe le 2027-11-05 sans nouvelle release, et `verified_on` expire le 2027-05-23, date que BENCH-012 propose pour sa prochaine vérification.

## Condition de révision

Bascule par un nouvel ADR qui remplace celui-ci pour la cible concernée dans ces cas :

- sur `local`, Keycloak touche un critère éliminatoire : dépôt archivé ou en maintenance, licence qui n'est plus open source, ou aucune release pendant 12 mois, décompte parti du 2026-11-05 ;
- sur `gcp`, Google retire Identity Platform ou le sort de la GA ;
- sur `gcp`, le test du parcours réel au premier déploiement échoue sur un point que la couche `gcp` ne sait pas corriger : la voie de Keycloak sur GKE revient, avec un `managed_gap` qui dit ce que le test a montré.

La décision se rouvre, sans basculer d'office, dans ces cas :

- aucune limite mémoire ne laisse Keycloak démarrer et servir dans le cadre de la condition 11, et Lucas refuse un standard au-delà de 8 Gio (question 3) ;
- le besoin du blueprint passe au-delà de la franchise d'Identity Platform, en particulier au-delà de 50 utilisateurs fédérés par mois, et le prix lu change l'équilibre avec Keycloak sur GKE (R-05) ;
- ni le montage a ni le montage b de l'ADR-011 ne fait passer T2 pour quay.io ;
- un constat de [SECU] sur l'image ou sur le rythme des republications, qui rendrait la liste fermée intenable ;
- Lucas revient sur l'élimination d'Authentik : une série de mesures à part, et une troisième colonne ;
- Lucas retient une autre voie pour le profil lite (question 1) ou pour la console (question 2) : les conditions 5 et 14 se réécrivent.

La levée de la dérogation ne rouvre pas la décision : la PR qui retire la liste fermée l'indique ici par un lien. Une montée de mineure de Keycloak ne la rouvre pas non plus : elle passe par Renovate et la matrice (condition 2). Une graduation de Keycloak à la CNCF ne change pas l'ordre. Sans l'un de ces faits, prochaine vérification au plus tard le 2027-05-23, date proposée par BENCH-012.

## Sources

Ce que BENCH-012 établit se cite par lui ; ses propres sources, S1 à S84, sont dans sa section 9.

| Source | Lue le | Ce qu'elle établit |
| --- | --- | --- |
| [BENCH-012](../benchmarks/BENCH-012-fournisseur-identite.md), sections 1 à 3, branche de la PR #43 | 2026-11-24 | Question posée et ce qui en dépend ; options et versions ; pendant managé et différence d'interface (S47, S51) ; critères éliminatoires, élimination d'Authentik |
| BENCH-012, section 4 | 2026-11-24 | Seuils, protocole, Postgres partagé ; M1 à M9 : 25,7 s, 843,2 Mio, 265,1 Mo, retéléchargement, jeton vérifié 6 sur 6, valeurs connues refusées 7 sur 7 ; `aud` relevé sans être jugé |
| BENCH-012, sections 5 et 6 | 2026-11-24 | Notes et grille réconciliée : 81 et 62 ; franchise d'Identity Platform et coût de Keycloak sur GKE (S82, S83, S84) |
| BENCH-012, section 7 | 2026-11-24 | Verdict, sensibilité, réserves, suites ; arbitrage du DSI et décisions de Lucas du 2026-11-24 ; prochaine vérification au 2027-05-23 |
| BENCH-012, sections 8 à 10 | 2026-11-24 | Limites, dont le pic mémoire et le client HTTP de la mesure ; sources S1 à S3, S5 à S8, S11, S12, S14 à S16, S18, S22, S24, S34, S46 à S48, S50 à S52, S57, S59, S65 à S67, S69 à S74, S77, S82 à S84 citées ici ; relecture de [SECU] (conditions 1 à 10, valeurs connues, signature, réglages `start`) et de [FINOPS] (cumul, mémoire, limite sous 1 255 Mi, miroir, coût sur GCP, trois conditions) |
| `tests/bench/bench-012-identity.sh`, ligne 89 ; `tests/bench/bench-012/keycloak/statefulset.yaml`, branche de la PR #43 | 2026-11-24 | Condensat de l'image mesurée ; réglages `start` de l'essai ; demandes 500m et 1700Mi, limites 2000m et 2000Mi ; ports 7800, 57800 et 9000 ; noms `idp-admin` et `idp-db` |
| <https://www.keycloak.org/server/hostname> | 2026-11-24 | `hostname`, URL complète ou nom d'hôte ; `hostname-admin` pour une console sur une autre adresse, qui n'empêche pas d'atteindre l'API d'administration par l'URL publique ; `hostname-strict` sans effet quand `hostname` est fixé ; `hostname-backchannel-dynamic`, `false` par défaut, exige une URL complète ; sélecteur de version jusqu'à 26.8.2 |
| <https://www.keycloak.org/admin-api/protocol-mappers> | 2026-11-24 | Mappeur « Audience », `oidc-audience-mapper` : « Included Client Audience » (`included.client.audience`), « Included Custom Audience », « Add to access token » à `true` par défaut |
| <https://www.keycloak.org/docs/latest/server_admin/index.html> | 2026-11-24 | Guide en version 26.8.2 ; section « Registering as a new user » ; page trop longue pour l'outil, sections « Audience support » et « Brute force attacks » non lues |
| <https://firebase.google.com/docs/auth/admin/verify-id-tokens> (S51 de BENCH-012) | 2026-11-24 | `alg` `RS256`, `kid` parmi les clés publiées ; `exp`, `iat`, `aud` égal au projet, `iss` `https://securetoken.google.com/<projectId>`, `sub`, `auth_time` ; clés à `https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com`, rafraîchies selon `max-age` ; bibliothèques JWT tierces admises ; aucun document de découverte cité |
| <https://docs.cloud.google.com/identity-platform/docs/concepts-admin-auth-api> | 2026-11-24 | « ID tokens conform to the OpenID Connect spec » ; vérification par le SDK d'administration ou par des bibliothèques JWT tierces ; renvoi à la page de vérification de Firebase |
| <https://firebase.google.com/docs/projects/api-keys> (S77 de BENCH-012) | 2026-11-24 | Clés d'API non secrètes une fois restreintes, acceptables dans le code client ; elles identifient le projet auprès de `identitytoolkit.googleapis.com` ; restreindre chaque clé et resserrer le quota de ces points pour l'authentification par mot de passe |
| <https://docs.cloud.google.com/endpoints/docs/openapi/authenticating-users-firebase> | 2026-11-24 | Émetteur et audience identiques ; adresse de clés `https://www.googleapis.com/service_accounts/v1/metadata/x509/securetoken@system.gserviceaccount.com`, différente de celle de Firebase ; revendications `iss`, `sub`, `aud`, `iat`, `exp` |
| [docs/risques.md](../risques.md), R-04, R-05, R-20, R-25, R-28, R-32, R-36, branche de la PR #43 | 2026-11-24 | Volume du premier `task up` à 1 787,0 Mo ; dépense GCP ; liste des valeurs connues ; registres publics ; secrets en clair dans etcd ; failles sans paquet et leur mitigation |
| [ADR-005](ADR-005-gateway.md), décision, répartition, conditions 2 et 5 | 2026-11-24 | Gateway en boucle locale et contrôleur de GKE ; aucun contrôle de sécurité porté par le groupe `gateway.envoyproxy.io` sans équivalent sur `gcp` ; parité des Gateway et HTTPRoute, écart voulu par un ADR |
| [ADR-006](ADR-006-orchestration-locale.md), condition 1 et portée | 2026-11-24 | Aucun Secret sous `k8s/` ; ni Helm ni outil de boucle ; images construites par `task up` |
| [ADR-007](ADR-007-secrets.md), conditions 1, 3 et 5 | 2026-11-24 | Création par un tube et liste des valeurs connues ; test sur GKE au premier apply réel ; parité du nom et des clés |
| [ADR-008](ADR-008-modules-opentofu-gcp.md), conditions et portée | 2026-11-24 | GKE Autopilot à nœuds privés ; `requests` explicites (condition 9) ; aucun apply sans accord |
| [ADR-009](ADR-009-catalogue.md), [`catalog/README.md`](../../catalog/README.md), `schema/catalog-entry.schema.json`, `scripts/catalog/accepted-licenses.yaml` | 2026-11-24 | Lecture des principes III et V ; `managed_gap` ; format d'une entrée et `pending` ; liste fermée des standards sans valeur d'identité ; `Apache-2.0` dans la liste blanche |
| [ADR-011](ADR-011-miroir-registres.md), registres servis, montages a et b, condition 10 | 2026-11-24 | Liste unique des registres ; Keycloak « à relever » ; mécanisme à plusieurs amonts non établi |
| [ADR-012](ADR-012-postgres-local.md), conditions 3, 7, 8 et 9, dérogation | 2026-11-24 | Secret et volume ensemble ; rôle sans superutilisateur ; base dans le namespace de l'application ; dérogation limitée à `docker.io/library/`, modèle de celle-ci |
| [specs/001-golden-repo-saas-b2b/spec.md](../../specs/001-golden-repo-saas-b2b/spec.md), FR-004 à FR-009, FR-021, SC-008 | 2026-11-24 | Secrets aléatoires et liste connue ; profil standard avec Keycloak ; condensats ; code limité par Q7 ; scan des images ; lite sur 8 Gio |
| [plan.md](../../specs/001-golden-repo-saas-b2b/plan.md), étape 15, matrice ; [research.md](../../specs/001-golden-repo-saas-b2b/research.md), RS-15 et RS-25 ; [contracts/http-api.md](../../specs/001-golden-repo-saas-b2b/contracts/http-api.md) | 2026-11-24 | Contrôles S01, S06, S07, S17, S23, E04, E05, E10 à E12, E21, D02, D03 ; Keycloak non appelé par l'API ; aucune authentification en local, aucun déploiement GCP sans elle |
| [docs/prd-mvp.md](../prd-mvp.md), US-005, ENF-01, ENF-02, ENF-03 | 2026-11-24 | Profil standard de mesure ; volume du premier `task up` ; parité et écarts au README ; Kyverno refuse les images non signées |
| [Constitution](../../.specify/memory/constitution.md), version 1.2.0 | 2026-11-24 | Principes I à X ; dérogation justifiée dans un ADR ; exception de sécurité au délai de 7 jours |
