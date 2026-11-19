# BENCH-008. Modules OpenTofu pour GCP

| Champ | Valeur |
| --- | --- |
| Identifiant | BENCH-008 |
| Sujet | Origine du code OpenTofu de la couche GCP du projet généré : modules écrits à la main, Cloud Foundation Fabric ou terraform-google-modules |
| Statut | relu |
| Ouvert le | 2026-11-19 |
| Mis à jour le | 2026-11-19 |
| Auteur | [BENCH] |
| Relecteurs | [SECU] pour les licences, les valeurs par défaut et la fédération d'identité, [FINOPS] pour les coûts |
| Périmètre | Projet généré sur GCP, et poste ou runner qui lance `tofu init` et `tofu validate` (validation de US-007, CI) |
| Choix du PRD | Modules OpenTofu pour GCP, sans option pressentie (`docs/prd-mvp.md`, section 1) |
| ADR lié | [ADR-008](../adr/ADR-008-modules-opentofu-gcp.md), écrit par [ARCHI] |
| Verdict proposé | Modules écrits à la main, 83/100, devant Cloud Foundation Fabric (78) et terraform-google-modules (64), après les relectures de [SECU] et [FINOPS] et l'arbitrage du DSI du 2026-11-19. La première version proposait Fabric à 83 contre 82 (section 7) |

## 1. Contexte

[BENCH] Question posée : d'où vient le code OpenTofu qui crée la couche GCP
du projet généré, entre des ressources du provider `google` écrites par
CELIAN, les modules de Cloud Foundation Fabric et ceux de
terraform-google-modules.

[BENCH] Ce qui en dépend. US-004 veut le code OpenTofu dans le dépôt généré
dès que la cible GCP est choisie. US-006 et US-007 exigent un `tofu validate`
et des politiques conftest qui passent avant la livraison, puis un plan sans
erreur avec les identifiants de l'utilisateur. Le plan valide compte dans les
15 minutes (PRD, section 7), donc `tofu init` et `tofu validate` aussi.
ENF-02 demande que seule la couche de cible change d'une cible à l'autre
(principe II), et ENF-05 un dimensionnement minimal. Côté constitution :
principes II et III (services managés de GCP), IV (catalogue traçable), V
(gouvernance), VI (récent mais éprouvé), VIII (aucun fait de mémoire) et X
(aucune dépense sans accord). Côté risques : R-05 et R-17 (dépense et tailles
par défaut), R-15 (ressources qui survivent à `tofu destroy`), R-18 (services
facturés au volume), R-19 (identité de la CI et état OpenTofu), R-21
(Application Design Center).

[BENCH] Socle commun. Les trois options écrivent le même socle minimal du
blueprint SaaS B2B, dans `tests/bench/bench-008/<option>/` : activation des
API sur un projet existant, un réseau VPC avec un sous-réseau et ses plages
secondaires, l'accès privé aux services (PSA), un cluster GKE Autopilot à
nœuds privés, une instance Cloud SQL pour PostgreSQL en IP privée, une
instance Memorystore for Redis en tier basique, un dépôt Artifact Registry
Docker à tags immuables, un secret Secret Manager sans version, et l'identité
de la CI : un pool de fédération d'identité limité à un dépôt et à une
référence Git (R-19), sur l'émetteur et les revendications `repository` et
`ref` des jetons de GitHub Actions [S36], un compte de service en lecture
seule pour `tofu plan`, aucune clé. Versions de moteur et tailles restent des variables sans valeur
par défaut : `tofu validate` n'en a pas besoin, et aucune n'est écrite de
mémoire. Ce socle n'a jamais été planifié ni appliqué (principe X).

[BENCH] GKE Autopilot plutôt que Standard, pour les trois options. Google
présente Autopilot comme « the recommended way to use GKE » [S33]. Autopilot
préconfigure la fédération d'identité de GKE, les nœuds Shielded et le
démarrage sécurisé, que Standard laisse optionnels ou par défaut [S34] : moins
de valeurs à régler et à vérifier par conftest. La facturation suit les
demandes des pods pour les pods généralistes [S33], et l'offre gratuite
couvre « One free Autopilot or zonal Standard cluster per month », pour les
frais de cluster seulement [S35]. Deux réserves pour [FINOPS] et [OPS] : un
cluster Autopilot est toujours régional [S34], ce qui interdit le profil démo
zonal envisagé par R-17 ; et un nouveau cluster Autopilot a par défaut une
adresse IP publique [S33], que le socle désactive. Les grilles tarifaires de
GKE, Cloud SQL, Memorystore et du réseau n'ont pas pu être lues le
2026-11-19 ; les ordres de grandeur relevés par [FINOPS] sont en section 5.9.

[BENCH] Option pressentie par le PRD : aucune.

[BENCH] Hors champ : le moteur du cache (Redis ou Valkey), les versions de
Postgres et de Kubernetes, le backend de l'état OpenTofu et son chiffrement
(R-19), Cloud NAT et la gateway (BENCH-004), le montant du budget (R-05), les
politiques conftest elles-mêmes, et la cible AWS, hors MVP.

## 2. Options étudiées

| Option | En une phrase | Version examinée | Publiée le | Sources |
| --- | --- | --- | --- | --- |
| Écrits à la main | Ressources du provider `google` écrites et maintenues par CELIAN dans le blueprint | Provider `hashicorp/google` 8.12.0 | 2026-11-17 | [S29] |
| Cloud Foundation Fabric | Monodépôt de Google (GoogleCloudPlatform) : modules légers versionnés ensemble, à consommer par Git avec un tag ou à forker | v60.0.0 | 2026-11-05 | [S3], [S4], [S6] |
| terraform-google-modules | Modules du Cloud Foundation Toolkit, un dépôt et une version par module, publiés sur les registres | network 18.3.1, kubernetes-engine 47.0.0, sql-db 28.3.1, memorystore 16.4.1, project-factory 18.4.0, service-accounts 5.1.0, github-actions-runners 6.0.0 ; artifact-registry 0.9.0 et secret-manager 0.10.0 sous GoogleCloudPlatform | 2026-09-22 à 2026-11-12 | [S16] à [S25] |

[BENCH] terraform-google-modules n'a pas de module Artifact Registry ni Secret
Manager : les deux dépôts répondent 404 dans l'organisation [S25]. Les modules
retenus pour ces deux briques sont publiés sous GoogleCloudPlatform, avec le
même préfixe `blueprints/terraform/` dans leur `provider_meta` que les modules
de l'organisation [S20], [S21]. Qu'ils relèvent du même toolkit est une
déduction, non vérifiée. Fabric n'a pas de module Memorystore à v60.0.0 :
l'option Fabric écrit donc l'instance Redis en ressource du provider.

[BENCH] Outil commun aux trois options : OpenTofu 1.13.9, publié le
2026-11-05 [S1], installé par Homebrew le 2026-11-19 [S2].

[BENCH] Options repérées mais non étudiées : aucune. Application Design
Center (R-21) produit du code pour GCP mais n'est pas une bibliothèque de
modules ; il sort du champ de ce choix.

## 3. Critères éliminatoires

[BENCH] Seuil de release : 2025-11-19, douze mois avant la vérification. Pour
l'option écrite à la main, le critère porte sur le provider `google`, seule
dépendance tierce. Pour terraform-google-modules, il porte sur chacun des neuf
modules du socle.

| Option | Licence open source | Ni archivé ni en maintenance | Release de moins de 12 mois | Vérifié le | Résultat |
| --- | --- | --- | --- | --- | --- |
| Écrits à la main | Oui : code de CELIAN sous Apache-2.0, provider sous MPL-2.0 [S29], [S38] | Oui, provider non archivé [S29] | Oui, 8.12.0 le 2026-11-17 [S29] | 2026-11-19 | Retenue |
| Cloud Foundation Fabric | Oui, Apache-2.0 [S3], [S38] | Oui, dépôt non archivé, dernier commit le 2026-11-18 [S3], [S5] | Oui, v60.0.0 le 2026-11-05, 30 releases en 12 mois [S4] | 2026-11-19 | Retenue |
| terraform-google-modules | Oui, Apache-2.0 pour les neuf dépôts [S16] à [S24], [S38] | Oui, aucun dépôt archivé [S16] à [S24] | Oui pour les neuf ; le moins actif, secret-manager, a une seule release en 12 mois, 0.10.0 le 2026-10-08 [S21] | 2026-11-19 | Retenue |

[BENCH] Options éliminées : aucune. La licence compte ici, même pour une cible
cloud : ces modules sont du code qui part dans le projet généré, pas un
service managé.

## 4. Mesures

### 4.1 Ce qui est mesuré

[BENCH] Seuils d'empreinte écrits le 2026-11-19 à 05:20 UTC, avant la
première exécution de `tofu init`. Avant de les écrire, [BENCH] avait lu la
taille du dépôt Fabric dans l'API GitHub (81 226 Kio) et aucune taille de
provider ni de module.

[BENCH] Adaptation de la règle de `TEMPLATE.md`. Ce choix ne fait tourner
aucun conteneur sur le PC : il n'y a ni mémoire au repos ni image. Ce qui pèse
sur le poste, c'est `tofu init` et `tofu validate`, lancés par la validation
avant livraison (US-007), dans la CI, et compris dans les 15 minutes (section 7
du PRD : « le plan OpenTofu GCP valide »). Les quatre seuils gardent les mêmes
origines : budget de 900 s d'ENF-01, portable de 8 Gio, débit bas de
10 Mbit/s. La couche GCP n'est qu'une étape du parcours parmi d'autres
(images, cluster, CI) : elle reçoit 10 % du budget au lieu des 44 % donnés aux
images de BENCH-003. Chaque option part de 5 et perd un cran par condition
remplie :

1. le volume compressé de la première initialisation dépasse 100 Mo,
   providers et modules compris (10 % du budget à 10 Mbit/s font 112,5 Mo,
   arrondis à 100) ;
2. au moins un élément se retélécharge à chaque `tofu init` dans un dossier
   neuf, même avec le cache des providers plein ;
3. la médiane de `tofu init` à froid plus celle de `tofu validate` dépasse
   90 s, soit 10 % du budget ;
4. la mémoire maximale d'un processus pendant `tofu validate` dépasse 1 Gio,
   un huitième d'un portable de 8 Gio.

[BENCH] Précision apportée après le test de fumée, donc après avoir vu un
premier résultat : « un dossier neuf » de la condition 2 désigne un clone neuf
du projet généré, qui versionne son fichier de verrouillage comme le dépôt de
CELIAN (`.gitignore`). Sans verrou, OpenTofu n'utilise pas le cache et
retélécharge tous les providers [S31] : la condition serait alors remplie par
les trois options et ne départagerait rien. L'effet de cette précision est
écrit dans la sensibilité (section 7).

[BENCH] Origine du seuil de volume, précisée après la relecture de [FINOPS].
Le seuil de 100 Mo est posé par [BENCH], dérivé du budget de 900 s d'ENF-01
et du débit bas de 10 Mbit/s du gabarit ; la part de 10 % donnée à la couche
GCP est aussi un choix de [BENCH]. Le PRD ne fixe aucun budget par étape :
ENF-01 les renvoie après les mesures de phase 1. À 5 % du budget, le seuil
tomberait à 56 Mo et Fabric perdrait un cran ; à 15 %, il monterait à 169 Mo
et aucune option ne perdrait de cran sur cette condition (calcul de
[FINOPS]).

| ID | Mesure | Unité | Critère alimenté | Script |
| --- | --- | --- | --- | --- |
| M1 | `tofu init` à froid : cache de providers vide, aucun verrou | s | Empreinte | `tests/bench/bench-008-tofu-modules.sh` |
| M2 | `tofu init` à chaud : dossier neuf, verrou de l'exécution à froid, cache plein | s | Empreinte | idem |
| M3 | `tofu validate` après l'init à froid | s | Empreinte | idem |
| M4 | Mémoire maximale d'un processus pendant init et validate (`/usr/bin/time -l`) | Mio | Empreinte | idem |
| M5 | Volume compressé de la première init : archives des providers (`tofu providers mirror`, darwin_arm64 et linux_amd64) plus objets Git des modules clonés | Mo | Empreinte (ENF-01) | idem |
| M6 | Ce qui se retélécharge à chaque init à chaud : providers, paquets de modules, clones Git réels (`GIT_TRACE`) | nombre | Empreinte, sécurité | idem |
| M7 | Lignes écrites pour le socle, et lignes des modules chargés (sources distinctes), hors lignes vides et commentaires | lignes | Expérience dev, maturité | idem |
| M8 | Providers résolus (verrou), contraintes par module (`tofu providers`), et essai du socle terraform-google-modules avec `google` épinglé en 8.12.0 | version | Activité, portabilité | idem |
| M9 | Résultat de `tofu validate` sans identifiant, avertissements, `tofu fmt -check` | oui ou non | Expérience dev, portabilité | idem |
| M10 | Socle Fabric figé par SHA complet (`?ref=f706bc3b…7477`, sans `depth`) : init à froid, objets Git, validation. Mesure de [SECU], une exécution | s, Mo | Empreinte, sécurité (sensibilité) | Commandes de [SECU], dossier `scratchpad/secu-b008/fabric-sha/` |

### 4.2 Machine de mesure

| Élément | Valeur |
| --- | --- |
| Modèle | Apple Mac16,7 |
| Processeur | Apple M4 Pro, 14 cœurs |
| Mémoire | 24 Gio |
| Système | macOS 27.2.1 (build 26B131) |
| Moteur de conteneurs | Aucun : ce benchmark n'en utilise pas |
| Ressources allouées | Sans objet |
| Versions mesurées | OpenTofu 1.13.9 (Homebrew), git 2.54.0 (Apple Git-157), figés ou relevés par le script dans `versions.tsv` |
| Charge parasite | Applications de bureau ouvertes et autres sessions Claude Code ; charge moyenne sur une minute de 2,72 au lancement de la série (`uptime`) |

### 4.3 Protocole

1. État de départ : pour chaque exécution à froid, un dossier de travail neuf
   et un cache de providers vide ; pour l'exécution à chaud qui la suit, un
   autre dossier neuf qui reçoit le verrou de l'exécution à froid et le même
   cache. Les fichiers `.tf` de l'option sont recopiés dans le dossier
   d'essai : aucun `.terraform/` ni verrou n'arrive dans le dépôt, ce que le
   script contrôle à la fin, avec l'absence de tout fichier `.tfstate`.
2. Commandes, identiques pour les trois options : `tofu init -input=false
   -backend=false`, puis `tofu validate`. Le script refuse toute autre
   sous-commande que `version`, `init`, `validate`, `fmt` et `providers`. Il
   refuse de démarrer si une variable `GOOGLE_*`, `CLOUDSDK_*` ou `GCLOUD_*`
   existe, et lance `tofu` sous `env -i`, avec un `HOME` vide dans le dossier
   d'essai : aucun identifiant n'est lisible.
3. Fin de la mesure : la sortie de la commande.
4. Relevé : `/usr/bin/time -l` pour le temps réel et la mémoire maximale ;
   journaux de `tofu init` pour les providers installés et les paquets de
   modules ; `GIT_TRACE` pour les clones Git réels. Volumes : taille des
   archives écrites par `tofu providers mirror`, et taille de
   `.git/objects` dans chaque paquet de module, qui approche le volume Git
   reçu sans le mesurer sur le réseau.
5. Trois exécutions à froid et trois à chaud par option, 5 s de pause entre
   deux, options enchaînées dans l'ordre écrit à la main, Fabric,
   terraform-google-modules.

Pour refaire la mesure :

```bash
tests/bench/bench-008-tofu-modules.sh /chemin/vers/un/dossier/vide
```

[BENCH] Sans argument, le script crée un dossier temporaire ; un dossier
passé en argument doit être absent ou vide. `OPTIONS`, `RUNS` et `PAUSE`
règlent l'essai. Il passe shellcheck et tourne sous le bash 3.2 de macOS ;
sous Linux, il lit la mémoire par `/usr/bin/time -f` de GNU (branche écrite,
non essayée). Les deux refus ont été essayés le 2026-11-19 : dossier non
vide, variable `GOOGLE_PROJECT` présente.

[BENCH] Après la relecture de [SECU], le script a changé sur trois points,
sans effet sur le code de mesure. `tofu version` tourne lui aussi sous
`env -i`. Un dossier d'essai placé dans un arbre Git est refusé, pour que
verrous, journaux et TSV ne puissent pas être commités. Les traces Git, qui
contenaient le nom d'utilisateur et le nom d'hôte du poste, sont réduites aux
commandes `git clone`, avec `TRIAL_DIR` à la place du chemin absolu ; les
autres journaux gardent ce chemin, et l'aide du script le dit. Vérifié le
2026-11-19 : shellcheck et pre-commit passent ; les refus du dossier non
vide, de `GOOGLE_APPLICATION_CREDENTIALS` et d'un dossier dans le dépôt
s'arrêtent sans rien créer ; une exécution de contrôle sur Fabric, hors
série, produit des traces sans nom d'utilisateur ni nom d'hôte. Les mesures
du rapport viennent de la version d'avant.

[BENCH] Le test de fumée a corrigé trois défauts avant la série. Un `TMPDIR`
placé dans le dossier d'essai rendait le chemin de la socket du plugin trop
long, et le provider ne démarrait pas pendant `tofu validate`. Le décompte
des providers téléchargés comptait aussi les lignes « Using ». Les exécutions
à chaud partaient sans verrou, et OpenTofu retéléchargeait alors chaque
provider malgré le cache, comme sa documentation l'annonce [S31].

### 4.4 Résultats

[BENCH] Mesures lancées le 2026-11-19 de 10:55:49 à 11:05:36 UTC, sur la
machine de la section 4.2. Un test de fumée d'une exécution par option a
précédé la série le même jour ; ses chiffres ne servent pas à la notation.

| Mesure | Option | Exécution 1 | Exécution 2 | Exécution 3 | Médiane | Écart |
| --- | --- | --- | --- | --- | --- | --- |
| M1, init à froid | Écrits à la main | 12,83 s | 11,71 s | 12,36 s | 12,36 s | 1,12 s |
| M1, init à froid | Fabric | 29,70 s | 36,59 s | 20,50 s | 29,70 s | 16,09 s |
| M1, init à froid | terraform-google-modules | 38,46 s | 35,67 s | 31,61 s | 35,67 s | 6,85 s |
| M2, init à chaud | Écrits à la main | 0,08 s | 0,08 s | 0,07 s | 0,08 s | 0,01 s |
| M2, init à chaud | Fabric | 7,02 s | 4,32 s | 4,61 s | 4,61 s | 2,70 s |
| M2, init à chaud | terraform-google-modules | 12,41 s | 12,62 s | 13,77 s | 12,62 s | 1,36 s |
| M3, validate | Écrits à la main | 1,17 s | 1,02 s | 1,07 s | 1,07 s | 0,15 s |
| M3, validate | Fabric | 2,60 s | 2,56 s | 2,36 s | 2,56 s | 0,24 s |
| M3, validate | terraform-google-modules | 2,52 s | 2,59 s | 2,45 s | 2,52 s | 0,14 s |
| M4, mémoire pendant validate | Écrits à la main | 148,4 Mio | 149,7 Mio | 144,7 Mio | 148,4 Mio | 5,0 Mio |
| M4, mémoire pendant validate | Fabric | 192,2 Mio | 202,8 Mio | 204,2 Mio | 202,8 Mio | 12,0 Mio |
| M4, mémoire pendant validate | terraform-google-modules | 185,2 Mio | 166,2 Mio | 174,2 Mio | 174,2 Mio | 19,0 Mio |

[BENCH] Mémoire pendant `tofu init` : 72,1 Mio au plus pour l'option écrite à
la main, 97,1 pour Fabric, 91,6 pour terraform-google-modules. Le maximum de
toute la série, exécutions à chaud comprises, est de 204,5 Mio (Fabric).

[BENCH] Volume de la première init (M5) et ce qui revient à chaque init (M6).
Archives des providers mesurées par `tofu providers mirror` ; modules mesurés
par la taille de `.git/objects` de chaque clone, une approximation du volume
reçu.

| Option | Providers résolus (verrou) | Archives, darwin_arm64 | Archives, linux_amd64 | Objets Git des modules | Total arm64 | Total amd64 | À chaque init à chaud, verrou et cache pleins |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Écrits à la main | `google` 8.12.0 | 37,9 Mo | 42,4 Mo | 0 | 37,9 Mo | 42,4 Mo | Rien |
| Fabric | `google` et `google-beta` 8.12.0, `random` 3.9.1 | 83,4 Mo | 92,7 Mo | 6,8 Mo, un clone `--depth 1 --branch v60.0.0` | 90,3 Mo | 99,6 Mo | 1 clone Git du dépôt entier, 7 paquets de modules recopiés |
| terraform-google-modules | `google` et `google-beta` 7.46.2, `kubernetes` 3.5.0, `null` 3.3.2, `random` 3.9.1 | 104,0 Mo | 114,3 Mo | 20,5 Mo, 9 clones avec tout l'historique | 124,5 Mo | 134,8 Mo | 9 clones Git, 11 paquets de modules |

[BENCH] Totaux de Fabric corrigés à la relecture : la première version
additionnait des valeurs déjà arrondies (92,7 plus 6,8, soit 99,5). À l'octet,
92 730 479 plus 6 848 512 font 99 578 991 octets, soit 99,6 Mo en amd64 et
90,3 Mo en arm64.

[BENCH] `.git/objects` majore le volume reçu : il contient, en plus du paquet
reçu (`.pack`), l'index `.idx` et l'index inverse `.rev` que Git construit
sur le poste [S79]. Mesure directe faite après les relectures, sur les
dossiers de la série encore présents, sans relancer de mesure : le seul
fichier `.pack` de Fabric pèse 5 920 160 octets (5,9 Mo), identique à
quelques octets près sur les trois exécutions à froid ; ceux de
terraform-google-modules 18 112 020 octets (18,1 Mo) à la première. Totaux
avec le `.pack` : Fabric 89,4 Mo en arm64 et 98,7 Mo en amd64,
terraform-google-modules 122,1 et 132,4 Mo. Ni les réponses HTTP, ni les
sommes de contrôle et signatures des providers ne sont comptées.

[BENCH] M10, mesure de [SECU] : le socle Fabric figé par le SHA complet de
v60.0.0 [S42], sans `depth`, fait un clone complet. `.git/objects` pèse 88,1 Mo (le `.pack` seul,
83,8 Mo, mesuré par [BENCH] dans le même dossier), l'init à froid 32,32 s, la
mémoire 89,8 Mio, et `tofu validate` réussit. Le volume de première init
passe à 171,5 Mo en arm64 et 180,8 Mo en amd64.

[BENCH] Sur disque, les modules occupent 174,2 Mio pour Fabric (le dépôt
entier recopié pour chacun des 7 appels) et 37,2 Mio pour
terraform-google-modules. Aucun provider n'est retéléchargé à chaud, pour
aucune option, dès que le verrou est présent. Sans verrou, le test de fumée a
retéléchargé tous les providers à chaque init, cache plein, pour les trois
options [S31].

[BENCH] Lignes (M7) : 203 lignes écrites pour l'option à la main, 169 pour
Fabric, 171 pour terraform-google-modules, hors lignes vides et commentaires,
`variables.tf` identique compris (28 lignes). Lignes des modules chargés, par
source distincte et sans les fichiers `.tofu` : 9 484 pour Fabric, 4 896 pour
terraform-google-modules. Fabric n'économise donc que 34 lignes sur le socle
écrit à la main.

[BENCH] Contraintes et validation (M8, M9). `tofu validate` réussit pour les
trois options sans aucun identifiant, et `tofu fmt -check` passe. Fabric et
terraform-google-modules renvoient chacun un avertissement de dépréciation
venu du provider (`remove_default_node_pool` côté Fabric, `numeric_id` côté
terraform-google-modules). Le socle terraform-google-modules résout `google`
en 7.46.2 : le module secret-manager exige `< 8.0.0` [S21]. Avec `google`
épinglé en 8.12.0, comme dans les deux autres options, `tofu init` échoue :
« Could not resolve provider hashicorp/google: no available releases match
the given constraints ».

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

### 5.1 Licence et liberté d'usage, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Écrits à la main | 5/5 | 15 | Code de CELIAN sous l'Apache-2.0 du générateur ; seule dépendance, le provider sous MPL-2.0, commune aux trois options | [S29], [S38] |
| Cloud Foundation Fabric | 5/5 | 15 | Apache-2.0. Copier des modules dans le blueprint, comme Fabric le recommande, impose de garder les en-têtes de licence, déjà présents dans chaque fichier | [S3], [S7], [S8], [S38] |
| terraform-google-modules | 5/5 | 15 | Apache-2.0 pour les neuf dépôts | [S16] à [S24], [S38] |

[BENCH] Le critère ne départage pas : trois licences permissives, compatibles
avec l'Apache-2.0 du générateur.

### 5.2 Gouvernance (fondation, multi-vendeurs), poids 15

[BENCH] Cas particulier du principe V : sur la cible GCP, le fournisseur des
services managés est Google quoi qu'il arrive (principe III). Cet argument
justifie l'écart au principe V si l'ADR retient un module de Google
(section 7) ; il ne relève pas la note. Arbitrage du DSI du 2026-11-19, sur
proposition de [SECU] : Fabric et terraform-google-modules, éditeur unique
sans fondation, reçoivent 2, comme Pkl et CUE dans BENCH-001 et k3d dans
BENCH-003. La première version leur donnait 3. Le provider `google` est
commun aux trois options et ne départage pas.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Écrits à la main | 4/5 | 12 | Aucune gouvernance tierce ajoutée au provider : les choix restent à CELIAN. Réserve : aucune communauté, tout repose sur l'équipe de CELIAN, ce que R-24 suit déjà pour les outils du générateur | [S29] |
| Cloud Foundation Fabric | 2/5 | 6 | Dépôt de GoogleCloudPlatform, éditeur unique sans fondation : il faut contourner, et Fabric le dit lui-même en recommandant « Fork the repository and own the fork ». 636 commits humains par 92 auteurs en 12 mois, dont 400 signés d'une adresse `google.com` (63 %) ; le premier auteur fait 34 % des commits humains, les trois premiers 54 %. Des adresses d'autres entreprises apparaissent (`ysys.hu`, `vizio.com`) ; les adresses personnelles (184 commits) ne disent rien de l'employeur. Base de contributeurs plus large que celle de Pkl ; licence et modèle « fork and own » permettent la reprise | [S5], [S7] |
| terraform-google-modules | 2/5 | 6 | Organisation tenue par Google, éditeur unique sans fondation ; `CODEOWNERS` donne l'équipe `cft-admins` et cinq personnes. Sur kubernetes-engine, 57 commits humains sur 113 en 12 mois, 35 auteurs, 16 commits d'une adresse `google.com` et 18 d'adresses masquées. Réserve propre : le socle dépend de deux organisations, dont GoogleCloudPlatform pour deux modules | [S17], [S20], [S21], [S37] |

### 5.3 Maturité et adoption, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Écrits à la main | 3/5 | 9 | Ressources d'un provider mûr, mais code neuf, sans aucun usage en production : sa justesse ne repose que sur les tests à écrire (matrice, conftest), action exigée par la note 3 | [S29], [M9] |
| Cloud Foundation Fabric | 4/5 | 12 | Créé le 2019-05-03, en v60. Réserve : « These modules are not necessarily backward compatible », et 30 releases en 12 mois dont 11 versions majeures (v50.0.0 à v60.0.0) | [S3], [S4], [S7] |
| terraform-google-modules | 4/5 | 12 | Dépôts créés entre 2017 et 2020 pour les modules de l'organisation, versions majeures élevées (network 18, kubernetes-engine 47). Réserve : artifact-registry et secret-manager restent en 0.x | [S16] à [S24] |

[BENCH] Aucune des trois options ne publie de liste d'adoptants vérifiable ;
ces notes reposent sur l'ancienneté et la cadence, comme dans BENCH-003.

[BENCH] Tests. Fabric teste chaque PR par un plan évalué avec tftest, sous
Terraform et sous OpenTofu [S9], [S10]. terraform-google-modules déploie
réellement chaque PR et lance des tests d'intégration [S10], avec un dossier
`test/integration` dans les dépôts vérifiés [S17], [S18], [S21]. L'option
écrite à la main n'a que ce que CELIAN écrira : `tofu validate`, conftest et
la matrice de la phase 4 (principe I), sans déploiement réel tant que le
principe X l'interdit aux agents.

### 5.4 Activité et maintenance, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Écrits à la main | 5/5 | 10 | La seule dépendance, le provider, publie chaque semaine : 8.10.0 le 2026-11-03, 8.11.0 le 2026-11-10, 8.12.0 le 2026-11-17. Le suivi de ces versions revient à CELIAN, compté en 5.8 | [S29] |
| Cloud Foundation Fabric | 5/5 | 10 | 30 releases en 12 mois, 654 commits, dernier commit le 2026-11-18. v60.0.0 exige déjà `google >= 8.10.0`, deux jours après la sortie de 8.10.0 | [S4], [S5], [S8], [S29] |
| terraform-google-modules | 3/5 | 6 | Cadence correcte pour la plupart des modules (network 18 releases, sql-db 10, kubernetes-engine et memorystore 9 en 12 mois), mais secret-manager n'a publié qu'une fois et exige encore `google < 8`, près de trois mois après 8.0.0 (2026-08-26) : tout le socle reste en 7.46.2 [M8]. Action : remplacer ce module ou attendre | [S16] à [S21], [S29], [M8] |

### 5.5 Sécurité (CVE, réactivité), poids 10

[BENCH] Valeurs par défaut lues dans le code des modules à la version
examinée, pour les points demandés par le DSI (R-15, R-17, R-19). Le socle de
chaque option fixe explicitement la valeur sûre ; le tableau dit ce qui
arrive si le blueprint oublie de le faire.

| Point | Écrits à la main | Fabric v60.0.0 | terraform-google-modules |
| --- | --- | --- | --- |
| IP publique de Cloud SQL | Choisie par CELIAN : désactivée dans le socle | `public_ipv4 = false` [S11] | `ipv4_enabled = true` [S26] |
| Protection contre la suppression, Cloud SQL | Choisie : OpenTofu et API activées | `terraform_deletion_protection` et `gcp_deletion_protection` à `true` [S11] | `deletion_protection = true`, mais `deletion_protection_enabled = false` au niveau de l'API [S26] |
| Utilisateur et mot de passe Cloud SQL | Aucun créé : rien dans l'état (R-19) | Aucun par défaut [S11] | `enable_default_user = true`, mot de passe aléatoire par `random_password`, donc dans l'état [S26] |
| Chiffrement en transit, Cloud SQL | Choisi : `ENCRYPTED_ONLY` | Non fixé (`ssl.mode` nul) [S11] | Non fixé (`ssl_mode` nul) [S26] |
| Sauvegardes Cloud SQL | Choisies : activées | Non gérées par défaut (`backup_configuration = null`) [S11] | `enabled = false` [S26] |
| Plan de contrôle GKE | Choisi : point d'accès IP désactivé | Point d'accès IP désactivé tant que `ip_access` est nul ; point d'accès DNS ouvert à l'extérieur (`allow_external_traffic = true`), authentifié par IAM [S12], [S13] | Point d'accès public, sans réseau autorisé (`enable_private_endpoint = false`, `master_authorized_networks = []`) [S27] |
| Nœuds GKE | Privés | Privés (`private_nodes = true`) [S12] | Privés (`enable_private_nodes = true`) [S27] |
| Protection contre la suppression, GKE | Choisie : activée | `true` [S12] | `true` [S27] |
| Memorystore | Choisi : tier basique, AUTH, TLS, PSA | Pas de module | Tier `STANDARD_HA`, `auth_enabled = false`, TLS serveur, réseau `default` si aucun n'est donné [S28] |
| Condition de la fédération d'identité | Choisie : dépôt et référence | Facultative ; l'exemple du README filtre sur `repository_owner`, le défaut que R-19 signale [S14], [S15] | Obligatoire (`attribute_condition` sans défaut) ; `sa_mapping` à `*` ouvre le compte à tout le pool [S22] |
| Clé de compte de service | Aucune | Aucune | `generate_keys = false` [S23] |
| API désactivées à la destruction | Non (`disable_on_destroy = false`) | Non (`disable_on_destroy = false`, module `project`) [S61] | `disable_services_on_destroy = true` [S24] |
| Compte de service des nœuds GKE | Compte par défaut de Compute Engine, oubli du socle relevé par Trivy (GCP-0050) [S62] | Compte par défaut (`node_config.service_account` nul) [S61] | Compte dédié créé par défaut, avec `roles/container.defaultNodeServiceAccount` [S27], [S61] |
| Point d'accès DNS de GKE | Bloc non écrit | Écrit : `allow_external_traffic = true` [S12] | Bloc non écrit [S61] |

[BENCH] Les deux dernières lignes viennent de [SECU]. Google recommande un
compte de service dédié aux nœuds, le compte par défaut de Compute Engine
pouvant avoir « more permissions than GKE needs » [S57]. Par défaut, le point
d'accès DNS est joignable par les API publiques de Google Cloud, protégé par
IAM [S56] ; l'état effectif quand le bloc est absent se confirmera au premier
plan de la phase 2. Ces écarts ne changent aucune note : ils deviennent des
conditions pour l'ADR (section 7).

[BENCH] Chaîne d'approvisionnement, constatée pendant les mesures et
précisée par [SECU]. Le verrou d'OpenTofu ne suit que les providers [S32] :
un module tiré par un tag Git n'est vérifié par aucune somme de contrôle, et
un tag peut être déplacé. Fabric est recloné par `git clone --depth 1
--branch v60.0.0` à chaque init [M6]. terraform-google-modules l'est moins :
le registre d'OpenTofu enregistre pour chaque version le SHA de commit qu'il
a découvert, et chaque module est extrait par `git checkout <sha>` [S41] ; la
confiance passe au registre, et ce qu'il fait si un tag amont bouge n'est
pas vérifié. L'option écrite à la main ne tire aucun module. Syntaxe vérifiée
par [SECU] : une source Git accepte un SHA complet dans `ref`, mais `depth`
exige une branche ou un tag [S40], d'où un clone complet (M10). Le seul vrai
contrôle d'intégrité d'un module, le `digest` d'un artefact OCI [S40],
supposerait que CELIAN publie les modules, hors MVP.

[BENCH] Scan de configuration par [SECU], Trivy 0.76.2 [S62] : 5 échecs sur
le socle écrit à la main, tous réels ; 2 sur Fabric et 3 sur
terraform-google-modules. Seul le résultat du socle écrit à la main est
fiable : sur les deux autres, Trivy ne résout pas les blocs dynamiques des
modules (faux positif sur les sauvegardes de Fabric), manque des écarts
réels (journaux de flux, compte des nœuds de Fabric) et n'a pas chargé le
module sql-db. Hors grille, pour l'ADR : une politique sur le HCL ne voit tout
que dans du code écrit à la main ou copié ; avec des modules tirés à l'init,
il faut évaluer le JSON d'un plan, donc des identifiants.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Écrits à la main | 4/5 | 8 | Chaque valeur sensible est choisie et lisible dans 203 lignes ; aucun module tiré à l'init, seul le provider, signé ; Trivy lit tout le socle. Réserve : la justesse de ces valeurs repose sur CELIAN, et Trivy a trouvé un oubli au premier passage (compte des nœuds) ; conftest doit les vérifier (US-006) | [M6], [M7], [M9], [S62] |
| Cloud Foundation Fabric | 3/5 | 6 | Valeurs par défaut prudentes pour l'IP et la suppression de Cloud SQL, et pour l'accès à GKE ; chiffrement en transit et sauvegardes de Cloud SQL non fixés. Signalement privé de GitHub activé, aucun avis publié, pas de `SECURITY.md`. La note perd un cran pour les modules tirés par tag et reclonés à chaque init, sans somme de contrôle, comme minikube pour kindnetd dans BENCH-003 (arbitrage du DSI). Autres réserves : condition de fédération facultative, exemple sur `repository_owner` ; fichiers d'instructions pour agents (`AGENTS.md`, `GEMINI.md`, `skills/`) à la racine du dépôt cloné | [S3], [S11] à [S15], [S32], [S40], [M6] |
| terraform-google-modules | 2/5 | 4 | Il faut contourner : IP publique de Cloud SQL, utilisateur créé avec son mot de passe dans l'état, point d'accès GKE public sans filtre, Memorystore sans AUTH. Neuf clones Git complets par tag à chaque init, cinq providers. Signalement privé activé sur les dépôts vérifiés, aucun avis publié | [S17], [S21], [S26] à [S28], [S32], [M6], [M8] |

### 5.6 Empreinte sur PC (RAM, CPU, démarrage), poids 10

[BENCH] Règle de la section 4.1. Une seule option est à moins de 10 % d'un
seuil : Fabric, avec 99,6 Mo en linux_amd64, 0,4 % sous le seuil de 100 Mo,
et 90,3 Mo en darwin_arm64, 9,7 % sous le seuil. Le pire cas retenu est
linux_amd64 parce que Linux fait partie des systèmes visés pour le poste
(Q5) et qu'un poste Linux amd64 télécharge ces archives ; la première version
invoquait à tort les runners de CI, alors que le débit de 10 Mbit/s vise le
poste de la personne. Les 99,6 Mo surestiment le volume reçu : `.git/objects`
compte l'index construit sur le poste. Avec le seul `.pack`, Fabric fait
98,7 Mo en amd64 [M5]. Ses deux notes possibles sont dans la section 7.
Aucune option n'approche les seuils de temps (38,2 s au plus contre 90) ni de
mémoire (204,5 Mio au plus contre 1 Gio).

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Écrits à la main | 5/5 | 10 | Aucune condition remplie : 37,9 Mo (arm64) et 42,4 Mo (amd64) à la première init, rien de retéléchargé avec le verrou, 12,36 s d'init à froid plus 1,07 s de validation, 148,4 Mio en validation | [M1] à [M6] |
| Cloud Foundation Fabric | 4/5 | 8 | Une condition remplie : le dépôt Fabric est recloné à chaque init, 5,9 Mo de paquet Git, même avec le verrou et le cache pleins. Volume de 90,3 Mo (arm64) et 99,6 Mo (amd64), 98,7 Mo avec le seul `.pack` : sous le seuil, de justesse et à la date de mesure ; 29,70 s plus 2,56 s ; 202,8 Mio | [M1] à [M6] |
| terraform-google-modules | 3/5 | 6 | Deux conditions remplies : 124,5 Mo (arm64) et 134,8 Mo (amd64) à la première init, dont 104,0 Mo de providers seuls ; neuf clones Git complets à chaque init. 35,67 s plus 2,52 s ; 174,2 Mio | [M1] à [M6] |

### 5.7 Portabilité multi-cloud, poids 10

[BENCH] La couche GCP est propre à GCP par construction (principe II) : aucune
option n'est réutilisable sur un autre cloud. Le critère porte donc sur deux
points : la compatibilité avec OpenTofu, déclarée ou seulement constatée, et
la possibilité de reprendre la même approche pour les cibles prévues après le
MVP.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Écrits à la main | 4/5 | 8 | HCL et provider seuls, validé par OpenTofu [M9] ; la même méthode se reprend pour AWS ou Azure après le MVP. Réserve : le code de la couche GCP n'est pas réutilisable ailleurs | [M9] |
| Cloud Foundation Fabric | 4/5 | 8 | Compatibilité OpenTofu déclarée et testée : un `versions.tofu` par module (`required_version >= 1.11.0`), que OpenTofu charge à la place du `versions.tf` [S30], et une matrice `terraform` et `tofu` dans la CI des modules [S8], [S9]. Réserve : propre à GCP, sans équivalent pour une autre cible | [S8], [S9], [S30], [M9] |
| terraform-google-modules | 3/5 | 6 | Fonctionne avec OpenTofu, constaté : modules servis par `registry.opentofu.org`, `tofu validate` réussi [M9]. Aucune déclaration ni test OpenTofu trouvé : la recherche de code GitHub ne renvoie aucune mention dans l'organisation [S39]. Une divergence future ne serait vue par personne en amont | [S39], [M9] |

### 5.8 Expérience dev et documentation, poids 10

[BENCH] Essai consigné : les trois socles ont été écrits le 2026-11-19 à
partir du code des modules et de leurs README, puis validés au premier essai,
sans identifiant ; seul un alignement du socle terraform-google-modules a dû
être corrigé pour `tofu fmt -check`.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Écrits à la main | 3/5 | 6 | Le plus de lignes écrites (203), toutes à maintenir ; documentation du provider complète. Action : suivre seul chaque version majeure du provider (8.0.0 le 2026-08-26) et écrire les tests que les modules auraient apportés | [M7], [S29] |
| Cloud Foundation Fabric | 4/5 | 8 | Le moins de lignes écrites (169), interfaces par objets homogènes d'un module à l'autre, exemples dans chaque README. Réserves : 11 versions majeures en 12 mois, chacune à relire ; pas de module Memorystore ; un avertissement de dépréciation à la validation | [M7], [M9], [S4], [S7] |
| terraform-google-modules | 3/5 | 6 | 171 lignes écrites, dont une part pour écraser des valeurs par défaut ; deux organisations, cinq providers, un provider bloqué en 7.x par un module ; un avertissement de dépréciation. Action : surveiller les contraintes de chaque module | [M7], [M8], [M9] |

### 5.9 Coût (managé ou opérationnel), poids 5

[BENCH] Les trois socles créent les mêmes ressources avec les mêmes tailles :
le coût des services managés ne départage pas. Reste le coût d'une valeur par
défaut oubliée. Le temps de maintenance du code est compté en 5.8 seulement :
la première version le comptait aussi ici pour l'option écrite à la main, ce
que [FINOPS] a relevé et que le DSI a corrigé le 2026-11-19.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Écrits à la main | 5/5 | 5 | Aucune licence ; tier, édition et disponibilité écrits dans le socle, aucune valeur par défaut coûteuse à surveiller | [M7] |
| Cloud Foundation Fabric | 5/5 | 5 | Aucune licence ; valeurs par défaut sans surcoût relevé : Cloud SQL zonal, édition ENTERPRISE, tier obligatoire | [S11] |
| terraform-google-modules | 3/5 | 3 | Aucune licence ; deux valeurs par défaut changent la facture et demandent une action : Memorystore en `STANDARD_HA`, avec réplication et basculement, et l'édition de Cloud SQL laissée à l'API, qui applique ENTERPRISE_PLUS à partir de PostgreSQL 16, édition sans cœur partagé, alors que le tier par défaut est `db-f1-micro` | [S26], [S28], [S70], [S71], [S73] |

[BENCH] Ordres de grandeur, relevés par [FINOPS] le 2026-11-19. Aucune grille
tarifaire officielle n'a pu être lue : celles de GKE, de Cloud SQL, de Cloud
NAT et du réseau du VPC ne renvoient que leur titre, celle de Memorystore
redirige vers une page en 404 [S63] à [S66]. Les montants ci-dessous viennent
d'un article du blog Google Cloud de 2024 et des prix d'exemple des pages de
remises sur engagement, en us-central1. Ils ne suffisent pas à valider un
budget.

| Poste | Ce qui est lisible | Par mois |
| --- | --- | --- |
| GKE, frais de cluster | 0,10 USD par cluster et par heure, tarif de 2024 [S67] ; un cluster Autopilot par mois offert, frais de cluster seulement [S35] | 0 USD pour le cluster couvert par l'offre gratuite, 73 USD sinon |
| GKE, pods généralistes | Facturation par pod [S33] ; exemple us-central1 : 0,0445 USD par vCPU-heure, 0,0049225 USD par Go-heure [S68] | Tableau suivant |
| GKE, stockage éphémère et pods système | Non trouvé | Non chiffré |
| Cloud SQL, instance | Prix du cœur partagé non trouvé ; cœur partagé hors SLA, « for test and development instances only » [S70], exclu des remises [S77] | Non chiffré |
| Cloud SQL, stockage et sauvegardes | Non trouvé ; SSD et agrandissement automatique sans limite par défaut [S70], [S73] | Non chiffré |
| Memorystore BASIC, 1 Go | Prix non trouvé ; M1 exclu des remises [S78] | Non chiffré |
| Cloud NAT, IP, load balancer | Absents du socle (BENCH-004) ; non trouvé | Non chiffré |
| Secret Manager, Artifact Registry, Cloud Logging | Franchises de l'offre gratuite [S35] | 0 dans la franchise |

| Demande de ressources par pod [S69] | vCPU | Mémoire | USD par mois |
| --- | --- | --- | --- |
| Défaut appliqué sans requête | 0,5 | 2 Gio | 23,4 |
| Minimum sans rafale | 0,25 | 512 Mio | 9,9 |
| Minimum avec rafale | 0,05 | 52 Mio | 1,8 |

[BENCH] Pour GKE seul, [FINOPS] obtient de 20 USD par mois (2 pods à requêtes
minimales, offre gratuite) à 307 USD par mois (10 pods sans requêtes, sans
offre gratuite), aux prix d'exemple de us-central1, sur 730 heures par mois.
Le nombre de pods sur GCP n'est fixé nulle part : il dépend de BENCH-004, de
l'ADR d'Argo CD, de Kyverno et d'External Secrets Operator. Cloud SQL,
Memorystore et le réseau n'étant pas chiffrés, ce montant n'est qu'un
minorant. Le levier principal est la demande de ressources : sans `requests`,
Autopilot applique 0,5 vCPU et 2 Gio par pod [S69], soit 23,4 USD par pod et
par mois à ces prix ; le blueprint doit fixer des `requests` explicites sur
chaque pod, et une règle de validation refuser un pod sans requête.

[BENCH] Alerte budget proposée par [FINOPS], que le code généré doit
déclarer (ENF-05). Elle ne plafonne rien (R-05). Syntaxe relue par [FINOPS]
sur la documentation du provider 8.12.0 [S72], [S74] ; la ressource n'est ni
ajoutée aux socles, ni planifiée, ni créée :

```hcl
variable "billing_account" {
  description = "Billing account ID that pays for the project."
  type        = string
}

variable "budget_amount" {
  description = "Monthly budget, in whole units of the billing account currency."
  type        = string
}

data "google_project" "this" {
  project_id = var.project_id
}

resource "google_billing_budget" "monthly" {
  billing_account = var.billing_account
  display_name    = "${var.name}-monthly"

  budget_filter {
    projects        = ["projects/${data.google_project.this.number}"]
    calendar_period = "MONTH"
  }

  amount {
    specified_amount {
      units = var.budget_amount
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }
  threshold_rules {
    threshold_percent = 0.9
  }
  threshold_rules {
    threshold_percent = 1.0
  }
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }
}
```

[BENCH] Trois contraintes relevées par [FINOPS], à trancher par [OPS] et
[SECU] avant de l'écrire dans le blueprint : avec les identifiants de
l'utilisateur, le provider doit porter `billing_project` et
`user_project_override = true`, sinon l'API répond 403 [S72] ; le budget
appartient au compte de facturation, et un `tofu plan` en CI avec le seul
`roles/viewer` sur le projet risque une erreur de droits (déduction non
vérifiée, qui mènerait à une racine OpenTofu séparée) ; créer un budget
demande un rôle sur le compte de facturation, rôle exact à lire. Les grilles
tarifaires de Cloud SQL, de Memorystore et du réseau sont à lire avant la
GATE 2 (R-05) ; aucun budget de démo n'est validable aujourd'hui.

## 6. Grille pondérée

| Critère | Poids | Écrits à la main | Cloud Foundation Fabric | terraform-google-modules |
| --- | --- | --- | --- | --- |
| Critères éliminatoires (section 3) | éliminatoire | passe | passe | passe |
| Licence et liberté d'usage | 15 | 5/5, 15 pts | 5/5, 15 pts | 5/5, 15 pts |
| Gouvernance (fondation, multi-vendeurs) | 15 | 4/5, 12 pts | 2/5, 6 pts | 2/5, 6 pts |
| Maturité et adoption | 15 | 3/5, 9 pts | 4/5, 12 pts | 4/5, 12 pts |
| Activité et maintenance | 10 | 5/5, 10 pts | 5/5, 10 pts | 3/5, 6 pts |
| Sécurité (CVE, réactivité) | 10 | 4/5, 8 pts | 3/5, 6 pts | 2/5, 4 pts |
| Empreinte sur PC (RAM, CPU, démarrage) | 10 | 5/5, 10 pts | 4/5, 8 pts | 3/5, 6 pts |
| Portabilité multi-cloud | 10 | 4/5, 8 pts | 4/5, 8 pts | 3/5, 6 pts |
| Expérience dev et documentation | 10 | 3/5, 6 pts | 4/5, 8 pts | 3/5, 6 pts |
| Coût (managé ou opérationnel) | 5 | 5/5, 5 pts | 5/5, 5 pts | 3/5, 3 pts |
| Total | 100 | 83 / 100 | 78 / 100 | 64 / 100 |

[BENCH] Notes changées après les relectures, par arbitrage du DSI du
2026-11-19 : gouvernance de Fabric et de terraform-google-modules de 3 à 2 ;
sécurité de Fabric de 4 à 3 ; coût de l'option écrite à la main de 4 à 5, de
terraform-google-modules de 4 à 3. Totaux recalculés par [BENCH] sur la
grille entière. La première version donnait 82, 83 et 68.

## 7. Verdict proposé

[BENCH] Option proposée : les modules écrits à la main, 83 sur 100, 5 points
devant Cloud Foundation Fabric (78) et 19 devant terraform-google-modules
(64). Ce classement sort du recalcul de la grille entière après les
relectures de [SECU] et [FINOPS] et l'arbitrage du DSI du 2026-11-19
(section 6). La première version de ce rapport proposait Fabric, à 83 contre
82 : un cran de gouvernance et un cran de sécurité pour Fabric, le double
compte du temps de maintenance pour l'option écrite à la main, ont inversé
l'ordre.

[BENCH] Pourquoi. L'option écrite à la main l'emporte sur la gouvernance,
aucun projet tiers à éditeur unique n'étant ajouté au provider [S3], [S5] ;
sur la sécurité, aucun module n'étant tiré à l'init et tout le code étant
lisible par les politiques sur HCL [M6], [S62] ; sur l'empreinte, 42,4 Mo
au lieu de 99,6 en amd64 et rien de retéléchargé [M5], [M6]. Fabric garde
l'avantage sur la maturité, avec des modules éprouvés et testés sous OpenTofu
à chaque PR [S3], [S9], et sur l'expérience dev (34 lignes de moins) [M7].
terraform-google-modules perd sur la sécurité, avec IP publique de Cloud SQL,
mot de passe dans l'état et point d'accès GKE public par défaut [S26], [S27] ;
sur l'activité, un module bloquant tout le socle en `google` 7.x [S21],
[M8] ; sur l'empreinte, 134,8 Mo et neuf clones à chaque init [M5], [M6] ; et
sur le coût, deux valeurs par défaut qui changent la facture [S26], [S28].

[BENCH] Sensibilité, à partir des totaux de la section 6.

- Fabric figé par SHA complet (`?ref=<SHA>`, sans `depth`) : la sécurité
  remonte à 4, mais le clone complet fait 88,1 Mo d'objets Git (M10) et le
  volume de première init 180,8 Mo en amd64 ; deux conditions d'empreinte
  remplies, empreinte à 3. Total inchangé, 78.
- Fabric copié dans le blueprint, dossiers `modules/<nom>` seuls, sans la
  racine du dépôt : note qu'en tire [SECU], sécurité à 4, empreinte à 5
  (plus aucun clone, 92,7 Mo de providers en amd64), expérience dev à 3
  (9 484 lignes de code tiers dans chaque projet généré, fusionnées par
  `copier update`, R-11). Total 80. À 7,3 % sous le seuil de volume, ce 5
  tomberait à 4 en une quinzaine de versions de `google` et `google-beta`
  au rythme observé, selon [FINOPS] : 78.
- Marge de Fabric sous le seuil de 100 Mo : 0,42 Mo avec la mesure par
  `.git/objects` (99,58 Mo ; [FINOPS] et le DSI écrivent 0,47 Mo, calculés
  sur les chiffres arrondis), soit une à deux versions de `google` et
  `google-beta`, qui ont pris 0,55 Mo entre 8.11.0 et 8.12.0 et 0,46 Mo par
  version en moyenne depuis 8.0.0 [S75], [S76]. Avec le seul `.pack`, la
  marge est de 1,35 Mo, deux à trois versions. Seuil franchi : empreinte à
  3, Fabric à 76.
- Seuil de volume à 5 % du budget (56 Mo) : Fabric perd un cran, 76 ;
  l'option écrite à la main reste dessous. À 15 % (169 Mo) : aucun
  changement.
- Sans verrou versionné dans le projet généré, l'option écrite à la main
  perd un cran d'empreinte : 81, toujours devant.
- Gouvernance de l'option écrite à la main ramenée à 3 : 80, à égalité avec
  Fabric copié. Sa maturité portée à 4 une fois la matrice de la phase 4 en
  place : 86.
- Pour que Fabric passe devant, il faut à la fois le copier dans le
  blueprint (80) et retirer deux crans à l'option écrite à la main, par
  exemple sa gouvernance et le verrou (78).
- terraform-google-modules reste dernier dans tous les cas, à 12 points au
  moins.

[BENCH] Critères hors grille, à reprendre dans l'ADR. Ils penchent eux aussi
vers l'option écrite à la main :

- sur ce socle, Fabric n'économise que 34 lignes (169 contre 203) et charge
  9 484 lignes de modules [M7] ;
- Fabric n'a pas de module Memorystore : le projet généré mêlerait de toute
  façon modules et ressources écrites à la main [S6] ;
- Fabric a publié 11 versions majeures en 12 mois, sans garantie de
  compatibilité [S4], [S7] : chaque montée est une PR Renovate à relire ;
- un module tiré par tag échappe au verrou [S32] : rien ne vérifie le code
  qui crée l'infrastructure, dans la CI de chaque projet généré. Au plan, une
  source de données `external` lance un programme qui reçoit l'environnement
  du processus, identifiants de la CI compris [S44], [S45] (risque proposé
  R-27) ;
- une politique sur le HCL (conftest, Trivy) ne voit tout que dans le code
  écrit à la main ou copié ; avec des modules tirés à l'init, elle doit lire
  le JSON d'un plan, donc attendre des identifiants [S62] ;
- en faveur de Fabric : ses valeurs par défaut et ses modules servent de
  référence relue par Google, et sa CI teste chaque module sous OpenTofu
  [S9], ce que CELIAN devra faire lui-même.

[BENCH] Gouvernance. L'option proposée n'ajoute aucun projet à éditeur
unique : sa seule dépendance tierce, le provider `google`, est commune aux
trois options. Si l'ADR retient malgré tout un module de Google, l'écart au
principe V se justifie ainsi : sur la cible GCP, l'éditeur des services
managés est déjà Google (principe III), le code est sous Apache-2.0, et
Fabric recommande lui-même de forker [S7]. Cet argument ne relève pas la
note (section 5.2).

[BENCH] Conditions pour l'ADR, issues de la relecture de [SECU], valables
quelle que soit l'option. Elles ne changent aucune note : les trois socles
sont égaux sur chacune, ou l'écart ne touche pas le classement.

- Fédération d'identité de la CI : filtrer sur `assertion.repository_id` et
  `assertion.repository_owner_id`, plus `assertion.ref`, et lier le compte de
  service à `attribute.repository_id/<id>`, jamais à un nom. Google écrit que
  les champs de nom comme `repository` et `repository_owner` « increases the
  chances of cybersquatting and typosquatting attacks » et recommande les
  champs `*_id` [S51] ; GitHub publie ces identifiants dans ses jetons
  [S54], et une condition reste obligatoire pour un fournisseur
  multi-locataire comme GitHub [S52]. Les trois socles filtrent aujourd'hui
  sur des noms. Chaque
  variable interpolée dans la condition reçoit un bloc `validation`, sinon
  une apostrophe réécrit l'expression CEL. L'entretien doit relever les deux
  identifiants numériques du dépôt ([DEV]). À vérifier sur un vrai jeton en
  phase 2 : la restriction de l'événement et du workflow, puisqu'un workflow
  `pull_request_target` tourne sur la branche par défaut [S55], et la
  longueur du nouveau `sub` face aux 127 caractères de `google.subject`
  [S53]. Le rôle de base `roles/viewer` de la CI, déconseillé en production
  [S58], est à remplacer par des rôles de lecture par service, à définir par
  [OPS].
- Secrets dans l'état : la chaîne AUTH de Memorystore (`auth_string`,
  `sensitive` mais écrite en clair) est dans l'état des trois socles [S46],
  [S47], et le compte de `tofu plan` lit l'état. L'état et les plans sont
  chiffrés par OpenTofu avec le fournisseur de clé `gcp_kms` [S50]. Les
  attributs `*_wo` servent partout où le provider les propose :
  `password_wo`, `root_password_wo` et `secret_data_wo` existent dans
  `google` 8.12.0, et OpenTofu les gère depuis 1.11 [S46], [S48], avec un
  `random_password` éphémère pour les alimenter [S46], [S49]. La chaîne
  AUTH, générée par le serveur, n'en a pas ; l'authentification IAM du cache
  relève du benchmark du moteur de cache. Aucun plan n'est publié en
  artefact de CI.
- Durcissement de GKE à aligner dans le socle retenu : un compte de service
  dédié aux nœuds, avec au moins `roles/container.defaultNodeServiceAccount`
  [S57], que seul terraform-google-modules crée ; un bloc
  `dns_endpoint_config` écrit explicitement [S56], que seul Fabric écrit.
- Scan : les résultats de Trivy ne sont fiables que pour le socle écrit à la
  main [S62]. Le socle retenu passe Trivy et conftest sur son HCL dans la
  matrice.
- Modules tiers, si l'ADR en retient : copiés dans le blueprint, dossiers
  `modules/<nom>` seuls, jamais la racine du dépôt Fabric et ses fichiers
  pour agents ; licence jointe, fichiers modifiés signalés, mentions gardées
  (Apache-2.0, 4.a à 4.c) [S59]. À défaut, figés par SHA complet sans
  `depth` [S40]. Jamais par tag.
- `tofu init -lockfile=readonly` dans la CI du projet généré [S43], et un
  cache des providers indexé sur le verrou.

[BENCH] Réserves à surveiller, quelle que soit l'option :

- un cluster Autopilot est toujours régional [S34] : le profil démo ne peut
  pas être zonal pour GKE. Selon [FINOPS], il ne coûte pas plus pour
  autant : l'offre gratuite vise un cluster Autopilot [S35], et Autopilot
  facture les demandes des pods, pas les nœuds [S33] ;
- la protection contre la suppression, active sur Cloud SQL et GKE dans les
  trois socles, fait échouer `tofu destroy` [S73] : le démontage se fait en
  deux temps, un apply qui lève les protections puis le destroy, sinon le
  cluster et l'instance restent et facturent ;
- prochaine vérification proposée : 2027-05-19, ou plus tôt si
  secret-manager accepte `google` 8.x, si Fabric publie un module
  Memorystore ou si Fabric passe en fondation.

[BENCH] Suites :

- l'ADR des modules OpenTofu pour GCP, écrit par [ARCHI]. Il reprend les
  conditions ci-dessus et fixe la version de `google` ;
- une entrée de `catalog/` pour le provider `google` : 8.12.0, MPL-2.0, dépôt
  de l'organisation `hashicorp` (gouvernance à préciser), actif, vérifié le
  2026-11-19, source [S29]. Si l'ADR retient Fabric, une entrée Fabric :
  v60.0.0, Apache-2.0, Google sans fondation, actif, vérifié le 2026-11-19,
  sources [S3], [S4] ;
- conftest pour la cible GCP, quelle que soit l'option : refuser une IP
  publique sur Cloud SQL, un point d'accès IP public sur GKE sans réseau
  autorisé, une condition de fédération sans `assertion.repository_id`,
  `assertion.repository_owner_id` et `assertion.ref`, un `principalSet` sur
  un nom, une clé de compte de service, `password`, `root_password` ou
  `secret_data` en clair, un tier Memorystore non écrit. Côté Kubernetes,
  une règle de validation refuse un pod sans `requests` ;
- l'alerte budget de la section 5.9 dans le blueprint, après arbitrage de
  [OPS] et [SECU] sur ses trois contraintes.

[BENCH] Textes proposés au DSI pour `docs/risques.md`, repris des
relectures :

- R-27, nouveau, « Modules OpenTofu tirés sans contrôle d'intégrité »
  ([SECU]) : « Le verrou d'OpenTofu ne suit que les providers. Un module tiré
  par un tag Git est recloné à chaque `tofu init`, sans somme de contrôle :
  qui déplace le tag change le code qui crée l'infrastructure de chaque
  projet généré. Au plan, une source de données `external` exécute un
  programme qui reçoit l'environnement du processus, identifiants de la CI
  compris (relevé par [SECU] le 2026-11-19, BENCH-008). Les modules servis
  par le registre d'OpenTofu sont extraits par le SHA de commit qu'il a
  enregistré. Mitigation : aucun module tiré par tag. Modules tiers copiés
  dans le blueprint (dossiers `modules/<nom>` seuls, licence et en-têtes
  gardés, fichiers modifiés signalés), ou à défaut figés par SHA complet,
  sans `depth`. `tofu init -lockfile=readonly` dans la CI. Toute montée de
  version d'un module copié passe par une relecture [SECU]. »
- R-19, amendement ([SECU]) : « Vérifié le 2026-11-19 (BENCH-008) : la chaîne
  AUTH de Memorystore (`auth_string`) est écrite en clair dans l'état dès que
  AUTH est activé, et le compte de `tofu plan` lit l'état. Le provider
  `google` 8.12.0 offre `password_wo`, `root_password_wo` et
  `secret_data_wo`, et `random` 3.9.1 un `random_password` éphémère, gérés
  par OpenTofu à partir de 1.11. Mitigation complétée : état et plans
  chiffrés par OpenTofu avec `gcp_kms` ; attributs `*_wo` obligatoires ;
  condition de fédération sur `repository_id`, `repository_owner_id` et
  `ref`, `principalSet` sur `repository_id` ; aucun plan publié en
  artefact. »
- R-17, amendement ([FINOPS]), à la place de « à prévoir un profil démo
  zonal et minimal » : « GKE Autopilot est toujours régional (BENCH-008) :
  le profil démo ne peut pas être zonal pour GKE. Les frais de cluster
  restent couverts par l'offre gratuite, qui vise un cluster Autopilot par
  mois, et Autopilot facture les demandes de ressources des pods, pas des
  nœuds. Le profil démo repose sur des requêtes explicites et minimales pour
  chaque pod (sans requête, Autopilot applique 0,5 vCPU et 2 Gio), une
  réplique par Deployment, Cloud SQL zonal à cœur partagé en édition
  ENTERPRISE, Memorystore BASIC, une limite d'agrandissement du disque de
  Cloud SQL et une alerte budget déclarée dans le code. »
- R-15, amendement ([BENCH], d'après [FINOPS]) : « La protection contre la
  suppression, active par défaut sur Cloud SQL et GKE dans les trois socles
  de BENCH-008, fait échouer `tofu destroy`. La procédure de démontage
  commence par un apply qui la lève, lancé par l'utilisateur ; [OPS] vérifie
  en phase 2 ce qu'un destroy partiel laisse derrière lui. »

## 8. Limites et biais

| Limite | Effet possible sur le verdict | Ce qui la lèverait |
| --- | --- | --- |
| Une seule machine, sous macOS arm64, sur le réseau du poste | M1 et M2 dépendent du débit et de GitHub ; M5 non | Relancer le script sur un runner Linux amd64 |
| Volume Git approché par `.git/objects`, qui compte l'index construit sur le poste ; le `.pack`, mesuré après coup sur les dossiers de la série, ne compte ni les réponses HTTP ni les sommes de contrôle | Fabric est à moins de 10 % du seuil de volume en amd64 (99,6 Mo, 98,7 Mo avec le `.pack`) : sa note d'empreinte en dépend | Mesurer les octets reçus sur le réseau (`GIT_TRACE_PACKET` ou proxy) |
| Mesure qui dérive avec les versions : les archives de `google` et `google-beta` grossissent d'environ 0,46 Mo par version | Le cran d'empreinte de Fabric tombe en une à trois versions | Revérifier à chaque montée du provider ; précision proposée pour `TEMPLATE.md` (section 11) |
| M10 (Fabric figé par SHA) : une seule exécution, hors protocole | Sensibilité seulement, sans effet sur le classement | Refaire la mesure dans le protocole de la section 4.3 si l'ADR retient le SHA |
| Précision de la condition 2 de l'empreinte écrite après le test de fumée | Sans verrou versionné, l'option écrite à la main perd aussi un cran, sans changer le classement | Fixer la règle dans `TEMPLATE.md` avant le prochain benchmark |
| Valeurs par défaut lues dans le source, sans `plan` (principe X) | Une valeur calculée par l'API, non visible dans le code, échappe au tableau | Un `tofu plan` sur un projet de Lucas, avec son accord (phase 2) |
| Scan Trivy fait par [SECU] : fiable pour le socle écrit à la main seulement, les modules n'étant pas résolus (faux positif, faux négatifs, module sql-db non chargé) | La note de sécurité des socles à modules repose sur une lecture humaine | Scanner le JSON d'un plan en phase 2, ou des modules copiés |
| Gouvernance mesurée par les adresses des commits, robots filtrés par leur nom | Une adresse personnelle cache l'employeur : 184 commits de Fabric | Relire la liste des auteurs à la main |
| Notes de jugement : gouvernance de l'option écrite à la main, maturité, expérience dev | Le classement de tête change si deux d'entre elles et la copie de Fabric se combinent (section 7) | Avis de Lucas dans l'ADR |
| Socle minimal : ni Cloud NAT, ni gateway, ni budget, ni état distant | Les écarts de lignes et de défauts peuvent changer sur la couche complète | Refaire le décompte sur le golden repo de la phase 2 |
| Grilles tarifaires de GKE, Cloud SQL, Memorystore, Cloud NAT et du réseau illisibles par les outils des agents | Coûts limités à des ordres de grandeur pour GKE seul, minorant ; aucun budget de démo validable | Lecture des grilles pour la région retenue, avant la GATE 2 (R-05) |
| Fabric mesuré tiré par tag Git, pas copié dans le blueprint | La variante copiée est notée par déduction (section 7), sans mesure | Mesurer la variante copiée si l'ADR la retient |

## 9. Sources

[BENCH] Les dates de release, les comptes d'activité et les métadonnées des
dépôts viennent de l'API publique de GitHub, lue le 2026-11-19. Un commit est
compté humain quand son auteur n'est pas un robot (`bot`, `renovate`,
`dependabot`, `github-actions`, `release-please` filtrés par leur nom).

| ID | URL | Lue le | Ce que la source établit | Officielle |
| --- | --- | --- | --- | --- |
| S1 | <https://api.github.com/repos/opentofu/opentofu/releases> | 2026-11-19 | OpenTofu 1.13.9 publié le 2026-11-05 ; dépôt sous MPL-2.0, non archivé | Oui |
| S2 | <https://formulae.brew.sh/formula/opentofu> | 2026-11-19 | Formule Homebrew : stable 1.13.9, licence MPL-2.0 (lu par `brew info`) | Non, Homebrew |
| S3 | <https://github.com/GoogleCloudPlatform/cloud-foundation-fabric> | 2026-11-19 | Apache-2.0, non archivé, créé le 2019-05-03 ; signalement privé activé ; pas de `SECURITY.md` ; aucun avis de sécurité publié | Oui |
| S4 | <https://api.github.com/repos/GoogleCloudPlatform/cloud-foundation-fabric/releases> | 2026-11-19 | v60.0.0 le 2026-11-05 ; 30 releases stables depuis le 2025-11-19, de v49.1.0 à v60.0.0, dont 11 versions majeures (v50.0.0 à v60.0.0) | Oui |
| S5 | <https://api.github.com/repos/GoogleCloudPlatform/cloud-foundation-fabric/commits?since=2025-11-19T00:00:00Z> | 2026-11-19 | 654 commits, 636 humains, 92 auteurs ; 400 commits humains d'une adresse `google.com`, 110 `gmail.com`, 74 adresses masquées ; premier auteur 219 commits ; dernier commit le 2026-11-18 | Oui |
| S6 | <https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/blob/v60.0.0/README.md> | 2026-11-19 | Liste des modules ; aucun module Memorystore ; dépôt « meant to be cloned as a single unit, and then forked » | Oui |
| S7 | <https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/blob/v60.0.0/modules/README.md> | 2026-11-19 | « These modules are not necessarily backward compatible », ruptures marquées par une version majeure ; recommandation « Fork the repository and own the fork » et sources GitHub avec `ref` | Oui |
| S8 | <https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/blob/v60.0.0/default-versions.tofu> | 2026-11-19 | `required_version = ">= 1.11.0"`, `google` et `google-beta` en `>= 8.10.0, < 9.0.0`, `provider_meta` suffixé `-tofu` ; le `versions.tf` équivalent exige `>= 1.12.2` | Oui |
| S9 | <https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/blob/v60.0.0/.github/workflows/tests.yml> | 2026-11-19 | Tests des modules en matrice `terraform` et `tofu`, `DEFAULT_TOFU_VERSION: "1.11.0"`, par pytest et tftest | Oui |
| S10 | <https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/blob/v60.0.0/FABRIC-AND-CFT.md> | 2026-11-19 | Fabric : à forker, tests par plan à chaque PR ; CFT : modules « opinionated », déploiement de bout en bout à chaque PR | Oui |
| S11 | <https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/blob/v60.0.0/modules/cloudsql-instance/variables.tf> | 2026-11-19 | `public_ipv4 = false`, `terraform_deletion_protection` et `gcp_deletion_protection` à `true`, `availability_type = "ZONAL"`, `edition = "ENTERPRISE"`, `backup_configuration = null`, `ssl` sans mode | Oui |
| S12 | <https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/blob/v60.0.0/modules/gke-cluster-autopilot/variables.tf> | 2026-11-19 | `private_nodes = true`, `allow_external_traffic = true` pour le point d'accès DNS, `deletion_protection = true`, `release_channel = "REGULAR"` | Oui |
| S13 | <https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/blob/v60.0.0/modules/gke-cluster-autopilot/main.tf> | 2026-11-19 | `ip_endpoints_config { enabled = var.access_config.ip_access != null }` (ligne 133) | Oui |
| S14 | <https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/blob/v60.0.0/modules/project/README.md> | 2026-11-19 | Exemple de fédération d'identité GitHub avec `attribute_condition = "attribute.repository_owner=='my_org'"` | Oui |
| S15 | <https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/blob/v60.0.0/modules/project/variables-identity-providers.tf> | 2026-11-19 | `attribute_condition` facultatif ; modèles `github`, `gitlab`, `okta`, `terraform` | Oui |
| S16 | <https://github.com/terraform-google-modules/terraform-google-network> | 2026-11-19 | Apache-2.0, non archivé, créé le 2018-07-03 ; 18.3.1 le 2026-10-08, 18 releases en 12 mois ; 63 commits dont 28 humains par 13 auteurs | Oui |
| S17 | <https://github.com/terraform-google-modules/terraform-google-kubernetes-engine> | 2026-11-19 | Apache-2.0, créé le 2018-08-13 ; 47.0.0 le 2026-10-30, 9 releases en 12 mois ; 113 commits dont 57 humains par 35 auteurs, 16 d'une adresse `google.com` ; `CODEOWNERS` : `cft-admins` et cinq personnes ; dossier `test/integration` ; signalement privé activé ; aucun avis | Oui |
| S18 | <https://github.com/terraform-google-modules/terraform-google-sql-db> | 2026-11-19 | Apache-2.0, créé le 2017-09-15 ; 28.3.1 le 2026-11-09, 10 releases en 12 mois ; 41 commits dont 21 humains par 13 auteurs ; `test/integration` | Oui |
| S19 | <https://github.com/terraform-google-modules/terraform-google-memorystore> | 2026-11-19 | Apache-2.0, créé le 2018-09-13 ; 16.4.1 le 2026-09-22, 9 releases en 12 mois ; sous-modules `memcache`, `redis-cluster`, `valkey` | Oui |
| S20 | <https://github.com/GoogleCloudPlatform/terraform-google-artifact-registry> | 2026-11-19 | Apache-2.0, créé le 2023-11-10 ; 0.9.0 le 2026-11-12, 3 releases en 12 mois ; `provider_meta` `blueprints/terraform/…` | Oui |
| S21 | <https://github.com/GoogleCloudPlatform/terraform-google-secret-manager> | 2026-11-19 | Apache-2.0 ; 0.10.0 le 2026-10-08, seule release en 12 mois ; `versions.tf` : `google` et `google-beta` en `>= 4.83.0, < 8` ; `SECURITY.md` présent | Oui |
| S22 | <https://github.com/terraform-google-modules/terraform-google-github-actions-runners/tree/v6.0.0/modules/gh-oidc> | 2026-11-19 | 6.0.0 le 2026-11-06 ; `attribute_condition` obligatoire ; `sa_mapping` : « If attribute is set to `*` all identities in the pool are granted access to SAs » | Oui |
| S23 | <https://github.com/terraform-google-modules/terraform-google-service-accounts> | 2026-11-19 | 5.1.0 le 2026-09-28 ; `generate_keys = false`, `grant_xpn_roles = true` par défaut | Oui |
| S24 | <https://github.com/terraform-google-modules/terraform-google-project-factory> | 2026-11-19 | 18.4.0 le 2026-09-30 ; `project_services` : `disable_services_on_destroy = true` par défaut | Oui |
| S25 | <https://api.github.com/repos/terraform-google-modules/terraform-google-secret-manager> | 2026-11-19 | 404, comme `terraform-google-artifact-registry` dans la même organisation | Oui |
| S26 | <https://github.com/terraform-google-modules/terraform-google-sql-db/blob/v28.3.1/modules/postgresql/variables.tf> | 2026-11-19 | `ipv4_enabled = true`, `deletion_protection = true`, `deletion_protection_enabled = false`, `enable_default_user = true`, `tier = "db-f1-micro"`, sauvegardes à `false` ; `main.tf` crée le mot de passe par `random_password` | Oui |
| S27 | <https://github.com/terraform-google-modules/terraform-google-kubernetes-engine/tree/v47.0.0/modules/beta-autopilot-private-cluster> | 2026-11-19 | `enable_private_nodes = true`, `enable_private_endpoint = false`, `master_authorized_networks = []` (aucun bloc de filtrage alors), `deletion_protection = true`, `create_service_account = true` | Oui |
| S28 | <https://github.com/terraform-google-modules/terraform-google-memorystore/blob/v16.4.1/variables.tf> | 2026-11-19 | `tier = "STANDARD_HA"`, `auth_enabled = false`, `transit_encryption_mode = "SERVER_AUTHENTICATION"`, `connect_mode` nul (DIRECT_PEERING), réseau `default` si `authorized_network` est vide | Oui |
| S29 | <https://github.com/hashicorp/terraform-provider-google> | 2026-11-19 | MPL-2.0, non archivé ; 8.12.0 le 2026-11-17, 8.11.0 le 2026-11-10, 8.10.0 le 2026-11-03, 8.0.0 le 2026-08-26, 7.46.2 le 2026-10-23 (API des releases) | Oui |
| S30 | <https://opentofu.org/docs/language/files/> | 2026-11-19 | « If both `foo.tf` and `foo.tofu` exist in the same directory, OpenTofu will only load `foo.tofu` » | Oui |
| S31 | <https://opentofu.org/docs/cli/config/config-file/> | 2026-11-19 | Le cache n'est utilisé que si le paquet correspond à une somme du verrou ; sinon « OpenTofu will always install a provider from upstream the first time you use it with a particular configuration » | Oui |
| S32 | <https://opentofu.org/docs/language/files/dependency-lock/> | 2026-11-19 | « At present, the dependency lock file tracks only provider dependencies » | Oui |
| S33 | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview> | 2026-11-19 | « Autopilot clusters are the recommended way to use GKE » ; facturation par pod pour les pods généralistes ; « New Autopilot clusters are regional clusters that have a publicly accessible IP address » | Oui |
| S34 | <https://docs.cloud.google.com/kubernetes-engine/docs/resources/autopilot-standard-feature-comparison> | 2026-11-19 | Autopilot : fédération d'identité de GKE, nœuds Shielded et démarrage sécurisé préconfigurés, régional imposé ; Standard : régional ou zonal, fédération et démarrage sécurisé optionnels | Oui |
| S35 | <https://docs.cloud.google.com/free/docs/free-cloud-features> | 2026-11-19 | « One free Autopilot or zonal Standard cluster per month », crédit limité aux frais de cluster ; franchises de Secret Manager et d'Artifact Registry | Oui |
| S36 | <https://docs.github.com/en/actions/concepts/security/openid-connect> | 2026-11-19 | Émetteur `https://token.actions.githubusercontent.com` ; revendications `repository`, `ref`, `repository_owner` | Oui |
| S37 | <https://github.com/terraform-google-modules/terraform-google-kubernetes-engine/blob/v47.0.0/CODEOWNERS> | 2026-11-19 | `* @terraform-google-modules/cft-admins` et cinq comptes nommés | Oui |
| S38 | <https://opensource.org/licenses> | 2026-11-19 | Apache-2.0 approuvée par l'OSI (relevé de BENCH-003, même jour) | Oui |
| S39 | <https://api.github.com/search/code?q=opentofu+org:terraform-google-modules> | 2026-11-19 | Aucun résultat pour « opentofu » dans l'organisation | Oui |
| S40 | <https://opentofu.org/docs/language/modules/sources/> | 2026-11-19 | `ref` accepte un SHA complet ; `depth` exige une branche ou un tag ; modules en artefacts OCI avec `digest` (relevé de [SECU]) | Oui |
| S41 | <https://raw.githubusercontent.com/opentofu/registry/main/modules/t/terraform-google-modules/project-factory/google.json> | 2026-11-19 | Le registre d'OpenTofu enregistre `version`, `commit` et `discovered` par version de module (relevé de [SECU]) | Oui |
| S42 | `git ls-remote` sur <https://github.com/GoogleCloudPlatform/cloud-foundation-fabric> et <https://github.com/terraform-google-modules/terraform-google-project-factory> | 2026-11-19 | v60.0.0 de Fabric pointe sur `f706bc3b6166787df01402f73a96f1de57097477` ; v18.4.0 de project-factory sur `eeda8a6ece829ceab899fbb528279bb4cff52ff7` (relevé de [SECU]) | Oui |
| S43 | <https://opentofu.org/docs/cli/commands/init/> | 2026-11-19 | `-lockfile=readonly` vérifie les sommes du verrou sans le modifier (relevé de [SECU]) | Oui |
| S44 | <https://opentofu.org/docs/language/data-sources/> | 2026-11-19 | Les sources de données sont lues pendant le plan quand c'est possible (relevé de [SECU]) | Oui |
| S45 | <https://github.com/hashicorp/terraform-provider-external/blob/main/docs/data-sources/external.md> | 2026-11-19 | Le programme d'une source `external` reçoit toutes les variables d'environnement du processus (relevé de [SECU]) | Oui |
| S46 | Schéma des providers `google` 8.12.0 et 7.46.2 et `random` 3.9.1, lu par `tofu providers schema -json` ; <https://github.com/hashicorp/terraform-provider-google/blob/v8.12.0/website/docs/r/redis_instance.html.markdown> | 2026-11-19 | `auth_string` de `google_redis_instance` calculé et `sensitive` ; attributs `password_wo`, `root_password_wo`, `secret_data_wo` ; `random_password` éphémère ; `authorization_mode` IAM sur `google_redis_cluster` et `google_memorystore_instance` (relevé de [SECU]) | Oui |
| S47 | <https://opentofu.org/docs/language/ephemerality/> | 2026-11-19 | Les valeurs sensibles restent écrites en clair dans l'état et le plan (relevé de [SECU]) | Oui |
| S48 | <https://opentofu.org/docs/language/ephemerality/write-only-attributes/> | 2026-11-19 | Attributs « write-only » à partir d'OpenTofu 1.11, écrits nuls dans l'état (relevé de [SECU]) | Oui |
| S49 | <https://opentofu.org/docs/language/ephemerality/ephemeral-resources/> | 2026-11-19 | Ressources éphémères à partir d'OpenTofu 1.11, jamais stockées dans l'état ni le plan (relevé de [SECU]) | Oui |
| S50 | <https://opentofu.org/docs/language/state/encryption/> | 2026-11-19 | Chiffrement natif de l'état et des plans, fournisseur de clé `gcp_kms` ; sans la clé, état et plans « unrecoverable » (relevé de [SECU]) | Oui |
| S51 | <https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines> | 2026-11-19 | Les champs de nom favorisent le cybersquatting ; champs `*_id` recommandés (relevé de [SECU]) | Oui |
| S52 | <https://docs.cloud.google.com/iam/docs/reference/rest/v1/projects.locations.workloadIdentityPools.providers> | 2026-11-19 | Les fournisseurs multi-locataires comme GitHub exigent un `attributeCondition` (relevé de [SECU]) | Oui |
| S53 | <https://docs.cloud.google.com/iam/docs/workload-identity-federation> | 2026-11-19 | `google.subject` limité à 127 caractères (relevé de [SECU]) | Oui |
| S54 | <https://docs.github.com/en/actions/reference/security/oidc> | 2026-11-19 | Revendications `repository_id` et `repository_owner_id` ; nouveau format de `sub` pour les dépôts créés après le 2026-07-15 (relevé de [SECU]) | Oui |
| S55 | <https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows> | 2026-11-19 | `pull_request_target` : `GITHUB_REF` sur la branche par défaut, avertissement sur le code non fiable (relevé de [SECU]) | Oui |
| S56 | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/network-isolation> | 2026-11-19 | Point d'accès DNS joignable par les API publiques, protégé par IAM ; recommandation de n'utiliser que lui (relevé de [SECU]) | Oui |
| S57 | <https://docs.cloud.google.com/kubernetes-engine/docs/how-to/service-accounts> | 2026-11-19 | Compte de Compute Engine par défaut pour les nœuds, trop de permissions possibles ; compte dédié avec `roles/container.defaultNodeServiceAccount` (relevé de [SECU]) | Oui |
| S58 | <https://docs.cloud.google.com/iam/docs/roles-overview> | 2026-11-19 | Rôles de base déconseillés en production (relevé de [SECU]) | Oui |
| S59 | <https://www.apache.org/licenses/LICENSE-2.0> | 2026-11-19 | Obligations de redistribution, sections 4.a à 4.d (relevé de [SECU]) | Oui |
| S60 | <https://api.github.com/repos/GoogleCloudPlatform/cloud-foundation-fabric> et dépôts équivalents, avec `/private-vulnerability-reporting`, `/security-advisories` et `/contents/SECURITY.md` | 2026-11-19 | Aucun dépôt archivé ; signalement privé et avis de sécurité par dépôt (relevé de [SECU]) | Oui |
| S61 | <https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules> ; <https://github.com/terraform-google-modules/terraform-google-kubernetes-engine/tree/v47.0.0/modules/beta-autopilot-private-cluster> ; <https://github.com/terraform-google-modules/terraform-google-sql-db/tree/v28.3.1/modules/postgresql> | 2026-11-19 | Code des modules lu dans les clones de la série : `disable_on_destroy = false` chez Fabric ; compte des nœuds par défaut chez Fabric, dédié chez terraform-google-modules ; bloc DNS absent chez terraform-google-modules (relevé de [SECU]) | Oui |
| S62 | Trivy 0.76.2, `trivy config`, sorties JSON dans `scratchpad/secu-b008/` | 2026-11-19 | 5 échecs sur le socle écrit à la main, 2 sur Fabric, 3 sur terraform-google-modules ; modules mal résolus (relevé de [SECU]) | Outil |
| S63 | <https://cloud.google.com/kubernetes-engine/pricing> | 2026-11-19 | Illisible : 88 caractères, le titre seul (relevé de [FINOPS]) | Oui |
| S64 | <https://cloud.google.com/sql/pricing> | 2026-11-19 | Illisible : titre seul (relevé de [FINOPS]) | Oui |
| S65 | <https://cloud.google.com/memorystore/docs/redis/pricing> | 2026-11-19 | Redirige vers une page en 404 (relevé de [FINOPS]) | Oui |
| S66 | <https://cloud.google.com/nat/pricing>, <https://cloud.google.com/vpc/network-pricing> | 2026-11-19 | Illisibles : titre seul (relevé de [FINOPS]) | Oui |
| S67 | <https://cloud.google.com/blog/products/containers-kubernetes/announcing-gke-extended-support> | 2026-11-19 | Article du 2024-07-18 : « standard cluster management fee ($0.10 per cluster per hour) » (relevé de [FINOPS]) | Oui, blog de l'éditeur |
| S68 | <https://docs.cloud.google.com/kubernetes-engine/cud> | 2026-11-19 | Exemple us-central1 : 0,0445 USD par vCPU-heure, 0,0049225 USD par Go-heure ; exemple, pas la grille (relevé de [FINOPS]) | Oui |
| S69 | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests> | 2026-11-19 | Sans requête : 0,5 vCPU et 2 Gio ; minimums de 250m et 512 Mio sans rafale, 50m et 52 Mio avec (relevé de [FINOPS]) | Oui |
| S70 | <https://docs.cloud.google.com/sql/docs/postgres/instance-settings> | 2026-11-19 | Cœur partagé hors SLA, « for test and development instances only », en édition Enterprise seulement ; Enterprise Plus par défaut à partir de PostgreSQL 16 (relevé de [FINOPS]) | Oui |
| S71 | <https://docs.cloud.google.com/memorystore/docs/redis/redis-tiers> | 2026-11-19 | Basic : un nœud ; Standard : réplication et basculement (relevé de [FINOPS]) | Oui |
| S72 | <https://raw.githubusercontent.com/hashicorp/terraform-provider-google/v8.12.0/website/docs/r/billing_budget.html.markdown> | 2026-11-19 | Syntaxe de `google_billing_budget` ; `billing_project` et `user_project_override` avec les identifiants de l'utilisateur, sinon 403 (relevé de [FINOPS]) | Oui |
| S73 | <https://raw.githubusercontent.com/hashicorp/terraform-provider-google/v8.12.0/website/docs/r/sql_database_instance.html.markdown> | 2026-11-19 | Agrandissement du disque sans limite par défaut ; ENTERPRISE_PLUS par défaut à partir de `POSTGRES_16` ; la protection fait échouer apply et destroy (relevé de [FINOPS]) | Oui |
| S74 | <https://raw.githubusercontent.com/hashicorp/terraform-provider-google/v8.12.0/website/docs/d/project.html.markdown> | 2026-11-19 | Source de données `google_project`, attribut `number` (relevé de [FINOPS]) | Oui |
| S75 | <https://api.github.com/repos/opentofu/terraform-provider-google/releases/tags/v8.12.0>, idem `v8.11.0` et `v8.0.0` | 2026-11-19 | Archives linux_amd64 : 42 350 829, 41 974 919 et 39 520 349 octets (relevé de [FINOPS]) | Oui |
| S76 | <https://api.github.com/repos/opentofu/terraform-provider-google-beta/releases/tags/v8.12.0>, idem `v8.11.0` et `v8.0.0` | 2026-11-19 | Archives linux_amd64 : 43 850 775, 43 679 504 et 41 200 337 octets (relevé de [FINOPS]) | Oui |
| S77 | <https://docs.cloud.google.com/sql/cud> | 2026-11-19 | Remises sur engagement sauf cœur partagé (relevé de [FINOPS]) | Oui |
| S78 | <https://docs.cloud.google.com/memorystore/docs/redis/cuds> | 2026-11-19 | Niveau M1 (moins de 5 Go) exclu des remises (relevé de [FINOPS]) | Oui |
| S79 | <https://git-scm.com/docs/git-index-pack> | 2026-11-19 | Git construit l'index `.idx`, et parfois `.rev`, à partir du `.pack` reçu (relevé de [FINOPS]) | Oui |

[BENCH] Correspondance avec les relectures : S40 à S62 gardent les numéros de
[SECU]. Côté [FINOPS], F1 à F8 deviennent [S63] à [S70], F9 [S77], F10
[S71], F11 [S78], F12 à F14 [S72] à [S74], F21 et F22 [S75] et [S76], F24
[S79]. F15, F17 et F18 reprennent les URL de [S11], [S26] et [S28], et F25
celle de [S32] : ces sources gardent leur numéro. F16, F19, F20, F23 et F26
à F28 ne sont pas citées dans ce rapport.

## 10. Relectures

| Relecteur | Porte sur | Date | Avis |
| --- | --- | --- | --- |
| [SECU] | Licences, critères éliminatoires, sécurité, fédération d'identité | 2026-11-19 | Défavorable au verdict de la première version |
| [FINOPS] | Coût, empreinte, Autopilot régional, alerte budget, CI | 2026-11-19 | Réservé |

[SECU] Licences et critères éliminatoires confirmés : Apache-2.0 pour Fabric
et les neuf dépôts de modules, MPL-2.0 pour le provider, aucune licence AGPL,
aucun dépôt archivé [S60]. Gouvernance de Fabric et de terraform-google-modules à
ramener à 2, comme Pkl, CUE et k3d. Sécurité de Fabric à ramener à 3, modules
tirés par tag. Effet calculé par [SECU] sur ses seules corrections : 82, 78 et
65. Exigences pour le blueprint : fédération sur les identifiants numériques,
état chiffré, attributs `*_wo`, compte dédié aux nœuds, point d'accès DNS
explicite, `-lockfile=readonly`.

[BENCH] Suite donnée à [SECU] : les deux notes sont corrigées par arbitrage
du DSI (sections 5.2 et 5.5) ; la nuance sur terraform-google-modules, extrait
par SHA, la syntaxe par SHA, la ligne « API désactivées » de Fabric et les
deux lignes de durcissement sont portées en 5.5 ; les constats sur la
fédération, les secrets dans l'état, le durcissement et Trivy deviennent des
conditions pour l'ADR (section 7) ; la variante par SHA (M10) et la variante
copiée entrent dans la sensibilité ; les trois défauts du script sont
corrigés et vérifiés (section 4.3) ; les textes de R-27 et de l'amendement de
R-19 sont repris en section 7.

[FINOPS] Règle d'empreinte appliquée comme le gabarit le demande. Le seuil de
100 Mo est posé par [BENCH] ; le pire cas amd64 se justifie par les postes
Linux (Q5), pas par les runners ; le volume mesuré majore le volume reçu et
Fabric garde 4/5 à la date de mesure, avec une marge d'une à deux versions des
providers. La note de coût de l'option écrite à la main comptait deux fois le
temps de maintenance : 5/5 pour elle comme pour Fabric ; 3/5 pour
terraform-google-modules (`STANDARD_HA`, édition laissée à l'API). Effet
calculé par [FINOPS] sur ses seules corrections : 83, 83 et 67. GKE seul
coûte de 20 à 307 USD par mois aux prix d'exemple de us-central1 ; le reste
n'est pas chiffré et aucun budget de démo n'est validable. L'avis reste
réservé tant que les grilles tarifaires ne sont pas lues.

[BENCH] Suite donnée à [FINOPS] : origine du seuil et raison de l'amd64
corrigées (sections 4.1 et 5.6) ; mesure directe du `.pack` faite sur les
dossiers de la série, sans relancer de mesure (section 4.4) ; notes de coût
corrigées par arbitrage du DSI (section 5.9) ; ordres de grandeur, alerte
budget et contraintes repris en 5.9 avec leurs « non trouvé » ; marge et
dérive des providers dans la sensibilité ; textes de R-17 et de R-15 repris
en section 7 ; les deux précisions du gabarit en section 11. Les totaux
partiels des deux relectures ne sont pas repris : la grille entière a été
recalculée (section 6), d'où 83, 78 et 64.

## 11. À trancher par Lucas

[BENCH] Deux précisions proposées par [FINOPS] pour la règle d'empreinte de
`TEMPLATE.md`. Le gabarit n'est pas modifié ; elles s'appliqueraient aux
benchmarks suivants.

1. Une mesure approchée à moins de 10 % d'un seuil se remplace par une
   mesure directe avant le passage en « relu », si celle-ci ne demande aucune
   action payante.
2. Une mesure qui dérive avec les versions (providers, images) se note à la
   date de mesure ; la sensibilité donne en plus le nombre de versions au
   bout duquel le seuil serait franchi au rythme observé.

[BENCH] [FINOPS] propose aussi d'inscrire dans le gabarit la précision de la
condition 2 écrite pendant ce benchmark : « un dossier neuf » désigne un
clone neuf du projet avec son fichier de verrouillage versionné, comme la
documentation d'OpenTofu le recommande [S32].
