# BENCH-007. Secrets locaux

| Champ | Valeur |
| --- | --- |
| Identifiant | BENCH-007 |
| Sujet | Comment le projet généré fournit ses secrets aux pods du cluster local, avec les mêmes manifests applicatifs que sur GCP |
| Statut | relu |
| Ouvert le | 2026-11-19 |
| Mis à jour le | 2026-11-19 |
| Auteur | [BENCH] |
| Relecteurs | [SECU] pour les licences, les CVE, les identifiants par défaut et les adresses d'écoute, [FINOPS] pour les coûts |
| Périmètre | Projet généré sur PC (cluster kind, ADR-004 en cours). La cible GCP est évaluée sur sa documentation, sans aucune ressource créée (principe X) |
| Choix du PRD | Secrets locaux, option pressentie OpenBao (`docs/prd-mvp.md`, section 1) |
| ADR lié | [ADR-007](../adr/ADR-007-secrets.md), écrit par [ARCHI] |
| Verdict proposé | O3, Secrets natifs créés par `task up` et synchronisés par GKE sur GCP, à égalité avec ESO seul (82 chacun), devant OpenBao avec ESO (73). Égalité tranchée pour O3 par l'arbitrage du DSI du 2026-11-19 (section 7). OpenBao en local n'est pas confirmé |

## 1. Contexte

[BENCH] Question posée : comment le projet généré fournit ses secrets (mots
de passe de Postgres et du cache, clés de l'application) aux pods du cluster
local kind, de façon que les manifests de l'application restent identiques
sur GCP, où le principe III impose Secret Manager.

[BENCH] Ce qui en dépend. US-012 veut que les secrets de l'application
viennent du gestionnaire de secrets de la cible, « OpenBao en local si
BENCH-007 le confirme, Secret Manager sur GCP », et qu'aucun scan ne trouve
de secret dans le dépôt généré. US-005 et le principe VII demandent que
`task up` démarre tout en une commande, sans étape manuelle. ENF-01 fixe le
parcours à moins de 15 minutes. ENF-02 demande la parité entre PC et GCP :
seule la couche de cible change (principe II). ENF-04 et le principe IX
interdisent tout secret versionné. Côté constitution s'ajoutent les principes
III (open source sur le PC, managé sur le cloud), V (fondation et plusieurs
entreprises), VI (récent mais éprouvé) et VIII (aucun fait de mémoire). Côté
risques : R-20 (identifiants par défaut, où OpenBao en mode dev est cité),
R-25 (registres publics) et R-26 (moteur de conteneurs payant). Le cluster
local est kind 0.33.0, retenu par Lucas le 2026-11-19 (BENCH-003).

[BENCH] Option pressentie par le PRD : OpenBao. La section 6 du brief la
couple à External Secrets Operator (« External Secrets Operator + OpenBao
(local/on-prem) ou Secret Manager (GCP) »). Elle est notée comme les autres,
avec le même script et les mêmes sources.

[BENCH] Hors champ : le déploiement réel sur GCP (aucune commande `gcloud`
ni `tofu`), l'identité de la CI et l'état OpenTofu (R-19), les identifiants
GCP et GitHub de l'utilisateur (deuxième critère de US-012), la rotation des
secrets, le chiffrement d'etcd au repos, l'on-prem et le choix final du mode
d'authentification d'ESO sur GKE, qui revient à [OPS] et [SECU].

## 2. Options étudiées

[BENCH] Le choix porte sur deux couches : où vivent les valeurs sur le PC, et
comment elles arrivent dans le pod de la même façon que sur GCP. Les trois
options vont de la plus outillée à la plus nue. Dans les trois, l'application
lit un Secret Kubernetes de même nom et de mêmes clés ; ce qui change, c'est
ce qui le produit.

| Option | En une phrase | Version examinée | Publiée le | Sources |
| --- | --- | --- | --- | --- |
| O1. OpenBao et ESO | OpenBao tourne dans le cluster, autodescellé par une clé statique générée par `task up` ; External Secrets Operator (ESO) copie ses valeurs en Secrets Kubernetes. Sur GCP, le même ESO lit Secret Manager | OpenBao 2.7.2 (chart 0.30.7), ESO 2.15.0 (chart 2.15.0) | 2026-10-26, 2026-11-06, 2026-11-10 | [S1], [S2], [S7], [S15], [S16] |
| O2. ESO seul, magasin Kubernetes | ESO sans OpenBao : en local, son fournisseur `kubernetes` lit un namespace source que `task up` remplit de valeurs aléatoires. Sur GCP, le même ESO lit Secret Manager | ESO 2.15.0 (chart 2.15.0) | 2026-11-10 | [S15], [S16], [S22] |
| O3. Secrets natifs | `task up` crée lui-même les Secrets Kubernetes de l'application, sans outil ajouté. Sur GCP, la synchronisation managée de GKE (`SecretSync`), GA depuis le 2026-04-16, crée les mêmes Secrets depuis Secret Manager | Kubernetes v1.36.4 (kind 0.33.0) | 2026-08-26 (kind) | [S31], [S36], [S37], [S45] |

[BENCH] Pourquoi ces trois. Le brief propose « OpenBao / alternatives ».
O1 reprend son couple ESO et OpenBao. O2 retire OpenBao pour mesurer ce qu'il
coûte et ce qu'il apporte, puisque ESO reste de toute façon le pont vers
Secret Manager sur GCP. O3 retire aussi ESO : c'est le plancher, et il oblige
à dire ce que la parité y perd.

[BENCH] Options repérées mais non étudiées :

- SOPS, au bac à sable de la CNCF depuis le 2023-05-17 [S34]. Il répond à
  une autre question : versionner des secrets chiffrés. En local, rien n'a
  besoin d'être partagé par le dépôt, puisque chaque poste tire ses propres
  valeurs au premier lancement. SOPS ajouterait une clé `age` à tenir hors du
  dépôt par développeur, pour un fichier qu'aucune cible ne lit ;
- le Secrets Store CSI Driver et le module complémentaire Secret Manager de
  GKE, qui en dérive : ils montent des fichiers, et le module de GKE « doesn't
  support the Sync as Kubernetes Secret feature » [S35]. L'application devrait
  lire des fichiers sur les deux cibles, avec un fournisseur CSI de plus en
  local ;
- l'injecteur d'agent du chart OpenBao : il passe par des annotations propres
  à OpenBao dans les pods, donc des manifests applicatifs qui diffèrent de GCP
  (principe II), et son image par défaut est `hashicorp/vault-k8s:1.7.6`,
  désignée par tag [S8] ;
- le mode dev d'OpenBao : stockage en mémoire, « All data is lost on
  restart », jeton racine `root` par défaut dans le chart [S8]. C'est le cas
  que cite R-20, écarté d'office ;
- les gestionnaires à éditeur unique (Infisical, Bitwarden Secrets Manager) :
  le principe V demande d'abord une fondation, et deux options de fondation
  sont disponibles.

## 3. Critères éliminatoires

[BENCH] Seuil de release : 2025-11-19, douze mois avant la vérification. Le
côté GCP de chaque option est un service managé : le critère de licence ne
s'y applique pas (principe III).

| Option | Licence open source | Ni archivé ni en maintenance | Release de moins de 12 mois | Vérifié le | Résultat |
| --- | --- | --- | --- | --- | --- |
| O1. OpenBao et ESO | Oui. OpenBao et son chart en MPL-2.0 [S1], [S39], ESO en Apache-2.0 [S15], deux licences approuvées par l'OSI [S33] | Oui, dépôts non archivés, derniers commits le 2026-11-18 et le 2026-11-19 [S3], [S17]. ESO a suspendu ses releases du 2025-08-13 au 2025-09-12 [S19], [S20] | Oui, OpenBao 2.7.2 le 2026-10-26, ESO 2.15.0 le 2026-11-10 [S2], [S16] | 2026-11-19 | Retenue |
| O2. ESO seul | Oui, Apache-2.0 [S15], [S33] | Oui, mêmes preuves pour ESO [S17], [S19], [S20] | Oui, 2.15.0 le 2026-11-10 [S16] | 2026-11-19 | Retenue |
| O3. Secrets natifs | Oui, Kubernetes en Apache-2.0 [S33], [S40] | Oui, branche 1.36 maintenue jusqu'au 2027-06-28 [S38] | Oui, kind 0.33.0 et son image v1.36.4 le 2026-08-26 [S37] | 2026-11-19 | Retenue |

[BENCH] Options éliminées : aucune. La pause des releases d'ESO, levée depuis
quatorze mois, n'élimine pas : elle compte dans la gouvernance (5.2).

## 4. Mesures

### 4.1 Ce qui est mesuré

| ID | Mesure | Unité | Critère alimenté | Script |
| --- | --- | --- | --- | --- |
| M1 | Installation à chaud jusqu'à « prêt » : images déjà dans le nœud | s | Empreinte sur PC | `tests/bench/bench-007-secrets.sh` |
| M2 | Mémoire au repos des pods de l'option, 120 s après « prêt » | Mio | Empreinte sur PC | `tests/bench/bench-007-secrets.sh` |
| M3 | CPU au repos des pods de l'option, au même moment | % d'un cœur | Empreinte sur PC | `tests/bench/bench-007-secrets.sh` |
| M4 | Installation à froid jusqu'à « prêt » : nœud neuf, images tirées du registre | s | Empreinte sur PC (ENF-01, R-04) | `tests/bench/bench-007-secrets.sh` |
| M5 | Volume compressé des images de l'option, et images retéléchargées à chaque installation | Mo | Empreinte sur PC (ENF-01, R-25) | `tests/bench/bench-007-secrets.sh` |
| M6 | Injection d'un secret dans un pod de test : délai, et valeur reçue identique à la valeur écrite | s, oui ou non | Expérience dev, portabilité | `tests/bench/bench-007-secrets.sh` |
| M7 | Redémarrage du cluster (arrêt puis relance du conteneur du nœud) : délai jusqu'à « prêt », descellement, valeur conservée | s, oui ou non | Expérience dev, sécurité | `tests/bench/bench-007-secrets.sh` |
| M8 | Adresses d'écoute et exposition : Services, ports de l'hôte, accès sans jeton depuis un autre namespace, chiffrement d'etcd | adresse, oui ou non | Sécurité (R-20) | `tests/bench/bench-007-secrets.sh` |
| M9 | Contrôles de R-20 : identifiant par défaut, valeurs aléatoires générées sans fichier, variante OpenBao sans autodescellement, générateur de mots de passe d'ESO | oui ou non | Sécurité, expérience dev | `tests/bench/bench-007-secrets.sh` |
| M10 | Mémoire au repos des pods de `kube-system` (serveur d'API, etcd), sur un cluster neuf par exécution, ajoutée après les relectures à la demande du DSI | Mio | Empreinte sur PC | `tests/bench/bench-007-secrets.sh`, `FRESH=1` |

[BENCH] Périmètre, règle provisoire du DSI jusqu'à la GATE 1 : la
plate-forme de base (kind, CRD Gateway API, Envoy Gateway) se compte contre
les 500 Mo de BENCH-003, chaque couche contre ses propres seuils, et le
cumul va en sensibilité. M2 compte donc la couche de secrets seule, images et
pods de l'option ; il ne compte ni le serveur d'API ni etcd, que BENCH-004
comptait dans sa plate-forme. M10 mesure ce qui manque.

[BENCH] Règle d'empreinte (5.6), selon la règle validée par Lucas pour
BENCH-003 et reprise dans `TEMPLATE.md`. Chaque option part de 5 et perd un
cran par condition remplie. Les seuils sont posés par [BENCH], dérivés du
budget de 900 s d'ENF-01, du débit bas de 10 Mbit/s du gabarit et d'un
portable de 8 Gio ; les parts de budget sont un choix de [BENCH], pas une
valeur du PRD, qui renvoie les budgets par étape après les mesures de phase 1.
Ils sont plus bas que ceux du cluster entier (500 Mo, 90 s, 1 Gio), parce que
la couche de secrets n'est qu'une des briques que `task up` démarre dans le
même budget :

1. le volume compressé des images de l'option dépasse 100 Mo pour la plus
   lourde des deux architectures, arm64 ou amd64. 100 Mo font 80 s à
   10 Mbit/s, soit 9 % du budget. L'amd64 compte parce que Linux fait partie
   des systèmes visés (Q5), et qu'un poste Linux x86 tire l'amd64 ;
2. au moins une image se retélécharge à chaque installation alors qu'elle est
   déjà dans le nœud (règle 2 de BENCH-003) ;
3. l'installation à chaud jusqu'à « prêt » (médiane de M1) dépasse 60 s,
   soit 7 % du budget ;
4. la mémoire au repos (médiane de M2) dépasse 256 Mio, un trente-deuxième
   d'un portable de 8 Gio.

[BENCH] Heure d'écriture. D'après le journal de session de [BENCH], cette
règle a été écrite le 2026-11-19 entre 09:47 et 10:56 UTC, avant le premier
test de fumée (10:56 UTC). Rien de vérifiable par un tiers ne le prouve :
aucun commit, et le fichier a été modifié depuis. La section 7 donne donc
aussi la notation avec les seuils du gabarit (500 Mo, 90 s, 1 Gio).

[BENCH] Biais déclaré. La taille compressée des images d'OpenBao et d'ESO a
été lue sur les registres le 2026-11-19, pendant la recherche, avant
l'écriture de ces seuils : 74,6 Mo en arm64 et 80,1 Mo en amd64 pour OpenBao,
97,7 et 104,6 Mo pour ESO. ESO seul tombe à moins de 10 % du seuil de 100 Mo,
de part et d'autre ; ses deux notes possibles sont dans la sensibilité de la
section 7.

### 4.2 Machine de mesure

| Élément | Valeur |
| --- | --- |
| Modèle | Apple Mac16,7 |
| Processeur | Apple M4 Pro, 14 cœurs (10 performance, 4 efficacité) |
| Mémoire | 24 Gio |
| Système | macOS 27.2.1 (build 26B131) |
| Moteur de conteneurs | OrbStack 2.2.5 (moteur non libre, voir R-26), Docker Engine 29.8.2, cgroup v2, pilote de stockage overlay2 |
| Ressources allouées | Machine virtuelle d'OrbStack : 14 CPU, 11,73 Gio (12 598 894 592 octets, `docker info`) |
| Versions mesurées | kind 0.33.0 et Kubernetes v1.36.4 (image de nœud figée par condensat), OpenBao 2.7.2 et chart 0.30.7, ESO 2.15.0 et chart 2.15.0, figés et vérifiés par le script ; kubectl 1.37.1, Helm 4.3.2 |
| Charge parasite | Voir 4.4 : charge moyenne et autres clusters relevés au début de chaque exécution (`load.tsv`) |

### 4.3 Protocole

1. État de départ : aucun conteneur du cluster `celian-bench-007`. Le
   script télécharge les deux charts par `gh release download` et vérifie
   leur SHA-256 avant tout usage. Le kubeconfig et les dossiers de Helm
   vivent dans le dossier d'essai : `~/.kube/config` et la configuration de
   Helm du poste ne servent pas.
2. Pour chaque option, un cluster kind neuf à un nœud, puis un pod
   d'amorçage qui tire `busybox` par condensat, pour que l'image du pod de
   test ne pèse sur aucune mesure. L'exécution 0, à froid, est la première
   installation sur ce nœud neuf : le nœud tire les images de l'option du
   registre. Les exécutions 1 à 3, à chaud, réinstallent après une
   désinstallation complète (namespaces, CRD et volumes retirés) : les images
   restent dans le nœud.
3. Installation. O1 : Secret de la clé de descellement (32 octets
   aléatoires), chart OpenBao en mode autonome avec `seal "static"`,
   `bao operator init`, moteur KV v2, politique en lecture seule, jeton
   périodique pour ESO, valeur de test écrite, jeton racine révoqué, puis
   chart ESO et `SecretStore` du fournisseur `vault`. O2 : chart ESO, Secret
   source aléatoire, compte de service et rôle, `SecretStore` du fournisseur
   `kubernetes`. O3 : Secret aléatoire créé par le script. Images
   d'OpenBao et d'ESO désignées par tag et condensat. Chaque valeur
   aléatoire passe par l'entrée standard, jamais par la ligne de commande ;
   le script n'en garde que l'empreinte SHA-256. Correction après la
   relecture de [SECU] : pendant la série, le script passait le Secret par un
   heredoc, que bash 3.2 écrit dans un fichier temporaire, et par
   `kubectl apply`, qui recopie la valeur dans l'annotation
   `last-applied-configuration` [S49], [S51]. Il utilise désormais un tube
   depuis `printf` vers `kubectl create -f -` [S50] ; la mesure M10 a tourné
   avec cette version. Dans tous les cas, etcd garde la valeur dans le nœud.
4. Fin de la mesure (« prêt ») : pods de l'option prêts (pour OpenBao, prêt
   veut dire initialisé et descellé, `bao status`), et `SecretStore` à
   `Ready` ; pour O3, le Secret existe.
5. Injection (M6) : un `ExternalSecret` (O1, O2) et un pod `busybox` qui lit
   la valeur par variable d'environnement et écrit son empreinte SHA-256.
   Délai chronométré de l'application des manifests à la fin du pod, puis
   comparaison des empreintes.
6. Repos (M2, M3) : endpoint `stats/summary` du kubelet, lu par le proxy de
   l'API, somme des pods des namespaces de l'option ; trois échantillons à
   partir de 120 s après « prêt », espacés de 10 s, médiane des trois.
   `docker stats` du nœud est relevé à titre de contexte.
7. Redémarrage (M7) : après la dernière exécution à chaud, trois fois de
   suite, `docker stop` puis `docker start` du conteneur du nœud, délai
   jusqu'au nœud prêt puis jusqu'à l'option prête, état de scellement,
   empreinte de la valeur relue par un pod neuf.
8. Contrôles (M8, M9) : Services et ports de l'option, ports publiés par le
   nœud, accès sans jeton depuis le namespace de l'application, option du
   chiffrement d'etcd de l'API ; variante OpenBao à partage de Shamir
   redémarrée ; générateur `Password` d'ESO en `CreatedOnce`.
9. Chronomètre à la milliseconde (Perl `Time::HiRes`). Charge du poste
   (`uptime`) et autres clusters kind relevés au début de chaque exécution.

Pour refaire la mesure :

```bash
tests/bench/bench-007-secrets.sh /chemin/vers/un/dossier/vide
```

[BENCH] Sans argument, le script crée un dossier temporaire par
`mktemp -d`. Un dossier passé en argument doit être absent ou vide.
`OPTIONS`, `RUNS`, `RESTARTS`, `FUNCTIONAL`, `IDLE_WAIT`, `BENCH_LOCK` et
`FRESH` règlent l'essai. Le script refuse de démarrer si un cluster
`celian-bench-007` existe. Son `trap` n'est posé qu'après les contrôles de
départ et la prise du verrou, si bien qu'un refus ne supprime rien ; ensuite,
il ne supprime que ce cluster et ce qu'il a créé. Il passe shellcheck et
tourne sous le bash 3.2 de macOS.

### 4.4 Résultats

[BENCH] Série lancée le 2026-11-19 de 19:12:43 à 20:05:31 UTC, sur la
machine de la section 4.2, verrou partagé pris par le script. Pendant toute
la série, `load.tsv` ne relève aucun autre cluster `celian-bench-*` ni aucun
autre conteneur ; charge moyenne sur une minute entre 2,32 et 4,53. Deux
tests de fumée (une exécution à chaud par option) ont précédé, de 10:56 à
11:04 et de 12:31 à 12:40 UTC ; leurs valeurs sont citées en complément. Les
trois exécutions à chaud servent à la notation.

| Mesure | Option | Exécution 1 | Exécution 2 | Exécution 3 | Médiane | Écart |
| --- | --- | --- | --- | --- | --- | --- |
| M1 | O1. OpenBao et ESO | 82,3 s | 29,2 s | 29,0 s | 29,2 s | 53,3 s |
| M1 | O2. ESO seul | 22,7 s | 22,3 s | 22,5 s | 22,5 s | 0,4 s |
| M1 | O3. Secrets natifs | 0,1 s | 0,1 s | 0,1 s | 0,1 s | 0,0 s |
| M2 | O1. OpenBao et ESO | 139,0 Mio | 142,0 Mio | 140,7 Mio | 140,7 Mio | 3,0 Mio |
| M2 | O2. ESO seul | 130,8 Mio | 116,0 Mio | 122,7 Mio | 122,7 Mio | 14,8 Mio |
| M2 | O3. Secrets natifs | 0 | 0 | 0 | 0 | 0 |
| M3 | O1. OpenBao et ESO | 2,8 % | 3,1 % | 3,2 % | 3,1 % | 0,4 % |
| M3 | O2. ESO seul | 0,3 % | 0,4 % | 0,3 % | 0,3 % | 0,1 % |
| M3 | O3. Secrets natifs | 0 | 0 | 0 | 0 | 0 |
| M6 | O1. OpenBao et ESO | 2,5 s | 2,0 s | 2,0 s | 2,0 s | 0,5 s |
| M6 | O2. ESO seul | 3,1 s | 3,2 s | 2,0 s | 3,1 s | 1,2 s |
| M6 | O3. Secrets natifs | 2,5 s | 3,1 s | 3,1 s | 3,1 s | 0,6 s |
| M7, nœud prêt | O1. OpenBao et ESO | 41,3 s | 38,1 s | 43,9 s | 41,3 s | 5,8 s |
| M7, nœud prêt | O2. ESO seul | 40,2 s | 44,8 s | 44,6 s | 44,6 s | 4,6 s |
| M7, nœud prêt | O3. Secrets natifs | 43,1 s | 44,7 s | 40,5 s | 43,1 s | 4,2 s |
| M7, option prête | O1. OpenBao et ESO | 66,1 s | 69,7 s | 68,8 s | 68,8 s | 3,6 s |
| M7, option prête | O2. ESO seul | 66,3 s | 67,7 s | 67,4 s | 67,4 s | 1,4 s |
| M7, option prête | O3. Secrets natifs | 45,5 s | 47,1 s | 42,9 s | 45,5 s | 4,2 s |

[BENCH] Répartition de la mémoire au repos (moyenne des échantillons à
chaud) : OpenBao 24 Mio ; ESO 117 à 123 Mio en trois pods, dont 47 à 51 Mio
pour son contrôleur de certificats. Le CPU d'O1 vient d'OpenBao.

[BENCH] Mesure complémentaire M10, demandée par le DSI après les
relectures : mémoire de `kube-system`, trois clusters neufs par option, une
installation chacun, même protocole de repos (`FRESH=1`). Lancée le
2026-11-19 de 22:47 à 23:20 UTC sous le verrou partagé, sans autre cluster ni
conteneur relevé ; elle a tourné avec la version corrigée du script, et les
9 injections ont reçu la bonne valeur.

| Mesure | Option | Exécution 1 | Exécution 2 | Exécution 3 | Médiane | Écart |
| --- | --- | --- | --- | --- | --- | --- |
| M10, `kube-system` | O1. OpenBao et ESO | 547,1 Mio | 523,3 Mio | 566,0 Mio | 547,1 Mio | 42,7 Mio |
| M10, `kube-system` | O2. ESO seul | 549,0 Mio | 538,6 Mio | 542,4 Mio | 542,4 Mio | 10,4 Mio |
| M10, `kube-system` | O3. Secrets natifs | 455,7 Mio | 445,0 Mio | 446,9 Mio | 446,9 Mio | 10,7 Mio |
| M2, même exécution | O1. OpenBao et ESO | 161,2 Mio | 151,5 Mio | 154,6 Mio | 154,6 Mio | 9,7 Mio |
| M2, même exécution | O2. ESO seul | 119,5 Mio | 138,3 Mio | 126,1 Mio | 126,1 Mio | 18,8 Mio |

[BENCH] O3 sert de référence : il n'ajoute qu'un Secret. Par rapport à lui,
le plan de contrôle prend 100,2 Mio avec O1 et 95,5 Mio avec O2 (médianes),
surtout dans le serveur d'API (232 Mio en moyenne avec O3, 332 à 339 Mio avec
ESO, qui installe 25 CRD) et un peu dans etcd (42 contre 54 Mio). Option et
plan de contrôle ensemble, sur nœud neuf : 254,8 Mio pour O1, 221,6 Mio pour
O2.

[BENCH] Installation à froid (M4) et volume (M5). Le nœud neuf tire les
images de l'option du registre ; aux exécutions à chaud, les événements
`Pulled` ne montrent que des images « already present ».

| Option | M4, installation à froid | Tests de fumée, à froid | Volume compressé, arm64 | Volume compressé, amd64 | Retéléchargé à chaque installation |
| --- | --- | --- | --- | --- | --- |
| O1. OpenBao et ESO | 37,7 s | 115,4 s | 172,3 Mo (74,6 + 97,7) | 184,6 Mo (80,1 + 104,6) | Aucune image |
| O2. ESO seul | 32,6 s | 42,2 s | 97,7 Mo | 104,6 Mo | Aucune image |
| O3. Secrets natifs | 0,1 s | 0,1 s | 0 | 0 | Aucune image |

[BENCH] Répartition du temps d'O1 (`phases.tsv`) : OpenBao répond, est
initialisé, descellé et configuré en 5,7 à 9,1 s ; le reste est l'attente des
déploiements d'ESO. Le seul écart fort, 82,3 s à l'exécution 1, vient de là :
les sondes de disponibilité du webhook et du contrôleur de certificats d'ESO
ont échoué environ une minute (événements `Unhealthy`, relevés à la main
pendant la série). Même effet au test de fumée d'O2 (77,2 s contre 42,2 s à
froid). Cause non établie. Il a touché deux premières réinstallations sur
quatre (O1 en série, O2 au test de fumée). La première installation d'O1 sur
nœud neuf a pris 115,4 s au test de fumée, sans relevé de phases : on ne sait
pas si le registre ou le même retard d'ESO en est la cause.

[BENCH] Injection (M6) : les 12 pods de test de la série et les 9 relancés
après redémarrage ont reçu une valeur dont l'empreinte SHA-256 égale celle de
la valeur écrite.

[BENCH] Redémarrage (M7) : après chacun des trois arrêts et relances du nœud,
pour les trois options, la valeur est conservée et relue par un pod neuf. O1
revient descellé seul, grâce au scellement `static`. Le port de l'API sur
127.0.0.1 ne change pas. Le Secret produit par le générateur `Password`
d'ESO garde la même empreinte après les trois redémarrages.

[BENCH] Exposition (M8), relevée sur chaque option.

| Élément | O1. OpenBao et ESO | O2. ESO seul | O3. Secrets natifs |
| --- | --- | --- | --- |
| Ports publiés sur l'hôte | API seule, 127.0.0.1 | API seule, 127.0.0.1 | API seule, 127.0.0.1 |
| Services ajoutés | `openbao` et `openbao-internal` (8200, 8201), webhook d'ESO (443), tous ClusterIP | Webhook d'ESO (443), ClusterIP | Aucun |
| `hostNetwork` ou `hostPort` | Aucun | Aucun | Sans objet |
| Écoute d'OpenBao | `[::]:8200`, `tls_disable = 1` : HTTP en clair dans le cluster | Sans objet | Sans objet |
| Accès sans jeton depuis `celian-app` | `/v1/sys/health` répond ; lecture du secret refusée, HTTP 403 | Non essayé | Sans objet |
| Chiffrement d'etcd au repos | Absent : aucune option `--encryption-provider-config` sur l'API | Absent | Absent |

[BENCH] Contrôles de R-20 (M9).

| Contrôle | Résultat |
| --- | --- |
| Valeurs aléatoires générées par le script, hors de la ligne de commande | Oui pour les trois options : 24 octets de `/dev/urandom` passés par l'entrée standard, seule l'empreinte gardée. Aucun jeton ni aucune clé dans les journaux (recherche de motifs sur `logs/`, confirmée par [SECU]). Pendant la série, la valeur passait par le fichier temporaire d'un heredoc et par l'annotation de `kubectl apply` (section 4.3) ; etcd la garde dans le nœud |
| Identifiant par défaut dans le chemin mesuré | Aucun. O1 : jeton racine produit par `bao operator init`, révoqué après la configuration ; clé de descellement de 32 octets aléatoires |
| OpenBao à partage de Shamir, redémarré | Scellé après le redémarrage (`sealed: true`) ; descellé 0,2 s après l'envoi de la clé. Sans autodescellement, `task up` devrait garder la clé de descellement quelque part |
| Générateur `Password` d'ESO, `CreatedOnce` | Oui : Secret de 32 caractères créé sans aucune valeur fournie, stable après redémarrage |

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

[BENCH] Une option faite de deux projets (O1) prend, critère par critère, la
note du plus faible des deux : le projet généré dépend des deux.

### 5.1 Licence et liberté d'usage, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. OpenBao et ESO | 5/5 | 15 | MPL-2.0 pour OpenBao et son chart, Apache-2.0 pour ESO, approuvées par l'OSI. Le projet généré tire l'image sans la redistribuer : aucune obligation (FAQ de la MPL, Q5). Un miroir d'images publié par CELIAN redistribuerait la forme exécutable (section 3.2) : condition reportée par le DSI dans R-25, pour toutes les images | [S1], [S15], [S33], [S39], [S46], [S47] |
| O2. ESO seul | 5/5 | 15 | Apache-2.0, approuvée par l'OSI, compatible avec l'Apache-2.0 du générateur | [S15], [S33] |
| O3. Secrets natifs | 5/5 | 15 | Rien d'ajouté : l'API Secret fait partie de Kubernetes, en Apache-2.0 | [S33], [S40] |

### 5.2 Gouvernance (fondation, multi-vendeurs), poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. OpenBao et ESO | 3/5 | 9 | Note d'ESO, le plus faible des deux. OpenBao seul vaudrait 4 : série de LF Projects, au bac à sable de l'OpenSSF (Linux Foundation) depuis mai 2025 après LF Edge, listé dans l'onglet « SANDBOX » de l'OpenSSF ; comité technique de six organisations (IOTech Systems, Wallix, Adfinis, GitLab, SAP, ControlPlane) ; 892 commits humains par 120 auteurs en douze mois, premier auteur à 25,3 %, deux premiers à 47,9 %. Le projet généré dépend en plus de deux gouvernances au lieu d'une | [S1], [S3], [S4], [S5], [S6], [S48] |
| O2. ESO seul | 3/5 | 9 | Bac à sable de la CNCF depuis le 2022-07-26 ; cinq mainteneurs, quatre employeurs déclarés (External Secrets Inc, Form3, IBM, Kubermatic) et un sans affiliation ; 505 commits humains par 165 auteurs en douze mois, premier auteur à 17,2 %, deux premiers à 34,5 %. Réserve qui demande une action : faute de mainteneurs, le projet a suspendu toutes ses releases du 2025-08-13 au 2025-09-12, « until we have at least five consistent, long-term community maintainers » ; seule la dernière version mineure est maintenue. Action : relire `MAINTAINERS.md` et le rythme des releases à chaque vérification du catalogue, et documenter le repli dans l'ADR. La pause ne compte qu'ici : finie avant la fenêtre de douze mois, elle ne pèse ni en activité ni en sécurité | [S15], [S17], [S18], [S19], [S20], [S21] |
| O3. Secrets natifs | 2/5 | 6 | Note de la pièce la plus faible, comme pour O1. Sur le PC, Kubernetes, gradué à la CNCF depuis le 2018-03-06, vaudrait 5. Sur GCP, le Secret est créé par la synchronisation de GKE, fonction de Google seul, sans fondation : 2, comme Config Sync dans BENCH-009. Le principe III en fait un choix conforme sur la cible cloud ; il ne relève pas la note. Contournement connu : ESO sur GCP (R-29) | [S32], [S36] |

### 5.3 Maturité et adoption, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. OpenBao et ESO | 3/5 | 9 | OpenBao est une fourche de Vault créée le 2023-11-09, en version 2.7, au bac à sable de l'OpenSSF ; son site cite des soutiens, sans liste d'adoptants. Le couple n'est documenté que par une page d'ESO testée avec ESO 0.16.1 et OpenBao 2.2.0, et le tableau de stabilité d'ESO classe son fournisseur OpenBao dédié en alpha ; le fournisseur `vault`, utilisé ici, est stable | [S1], [S6], [S21], [S24] |
| O2. ESO seul | 4/5 | 12 | Créé le 2020-11-17, version 2.x depuis le 2026-02-06, 38 adoptants déclarés par eux-mêmes (dont Cisco, Elastic, SAP). Réserve : bac à sable de la CNCF, et fournisseur `kubernetes` classé bêta | [S15], [S16], [S21], [S30] |
| O3. Secrets natifs | 4/5 | 12 | En local, l'API Secret de Kubernetes, stable de longue date. Sur GCP, la synchronisation de GKE est GA depuis le 2026-04-16, après une preview ouverte le 2025-10-13 ; GKE 1.33 ou plus, clusters Standard et Autopilot, Workload Identity requise. Réserve : jamais exécutée par nous | [S31], [S36], [S43], [S45] |

### 5.4 Activité et maintenance, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. OpenBao et ESO | 5/5 | 10 | OpenBao : 16 releases stables en douze mois, dernier commit le 2026-11-18 ; son chart : 53 releases. ESO : 25 releases en douze mois, dernier commit le 2026-11-19 | [S2], [S3], [S7], [S16], [S17] |
| O2. ESO seul | 5/5 | 10 | 25 releases en douze mois, environ une toutes les deux semaines, 165 auteurs humains, dernier commit le 2026-11-19 | [S16], [S17] |
| O3. Secrets natifs | 5/5 | 10 | Kubernetes : branche 1.36 maintenue jusqu'au 2027-06-28 ; kind publie l'image v1.36.4 le 2026-08-26 | [S37], [S38] |

### 5.5 Sécurité (CVE, réactivité), poids 10

[BENCH] Point commun aux trois options : la valeur finit dans un Secret
Kubernetes, en clair dans etcd faute de chiffrement au repos [M8], [S31],
[S54]. kind écrit par défaut dans `~/.kube/config` un kubeconfig
d'administration, qui lit tous les Secrets quelle que soit l'option, et tout
processus de l'utilisateur, agent compris (R-07), peut le lire [S55]. OpenBao
et ESO ne protègent donc pas mieux la valeur sur le PC ; la note compte ce
que chaque option ajoute.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. OpenBao et ESO | 2/5 | 4 | Ajoute un serveur de secrets en HTTP clair sur `[::]:8200`, dont l'état de santé répond sans jeton à tout le cluster [M8], un jeton racine et une clé de descellement à gérer ; la clé du scellement `static` vit dans un Secret, à côté de ce qu'elle protège, cas que la documentation réserve à une source de confiance déjà présente. 39 avis en douze mois, dont 5 critiques, tous publiés avec correctif ; sommes de contrôle signées. Le mode dev du chart est désactivé par défaut ; activé, il prend le jeton racine `root`. S'y ajoutent les droits d'ESO (ligne O2) | [M8], [M9], [S8], [S9], [S13], [S14], [S29] |
| O2. ESO seul | 3/5 | 6 | Aucun identifiant d'administration, aucun port hors du cluster [M8]. Mais le contrôleur reçoit par défaut tous les droits sur les Secrets de tout le cluster ; 9 avis en douze mois, dont 1 critique et 3 élevés qui touchent la lecture de secrets. Action : restreindre ESO par `scopedNamespace` et `scopedRBAC`, options du chart non essayées | [M8], [S28], [S29] |
| O3. Secrets natifs | 4/5 | 8 | Rien d'ajouté : ni port, ni compte, ni opérateur. La valeur passe par l'entrée standard de `kubectl` [M9]. Réserve commune aux trois : etcd en clair, et quiconque crée un pod dans le namespace lit ses Secrets | [M8], [M9], [S31], [S41] |

### 5.6 Empreinte sur PC (RAM, CPU, démarrage), poids 10

[BENCH] Règle et seuils de la section 4.1. Aucune option n'a d'image
retéléchargée à chaud [M5]. M10, appliqué selon la demande du DSI, ne change
aucune note : avec la part du plan de contrôle, O1 atteint 254,8 Mio et O2
221,6 Mio, sous les 256 Mio. O1 est à moins de 10 % du seuil : ses deux notes
sont dans la sensibilité de la section 7.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. OpenBao et ESO | 4/5 | 8 | Une condition remplie : 184,6 Mo en amd64 (172,3 en arm64), au-delà de 100 Mo. M1 à 29,2 s et M2 à 140,7 Mio, sous leurs seuils, 254,8 Mio avec la part du plan de contrôle ; CPU au repos le plus haut (3,1 % d'un cœur) | [M1], [M2], [M3], [M5], [M10], [S42] |
| O2. ESO seul | 4/5 | 8 | Une condition remplie, de justesse : 104,6 Mo en amd64, 97,7 en arm64. M1 à 22,5 s, M2 à 122,7 Mio, 221,6 Mio avec la part du plan de contrôle | [M1], [M2], [M3], [M5], [M10], [S42] |
| O3. Secrets natifs | 5/5 | 10 | Aucune condition : rien à télécharger, 0,1 s, aucun pod ajouté | [M1], [M2], [M5] |

### 5.7 Portabilité multi-cloud, poids 10

[BENCH] Le critère porte sur la parité d'ENF-02 : ce que la couche de cible
doit porter, et ce qui, de la chaîne GCP, s'exerce déjà sur le PC.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. OpenBao et ESO | 4/5 | 8 | Même `ExternalSecret` sur les deux cibles, seul le `SecretStore` change (`vault` en local, `gcpsm` sur GCP), et le pont ESO tourne déjà sur le PC. Réserve : la couche PC porte en plus tout l'amorçage d'OpenBao (clé, init, moteur, politique, jeton), qui n'existe sur aucune cible cloud. OpenBao resterait utile à une cible on-prem, hors MVP | [M6], [S23], [S25] |
| O2. ESO seul | 5/5 | 10 | Même `ExternalSecret` sur les deux cibles, seul le `SecretStore` change (`kubernetes` en local, `gcpsm` sur GCP) ; la couche PC ne porte que le Secret source et un rôle en lecture. Le même ESO servirait OpenBao en on-prem sans toucher à l'application. Pour O1 comme pour O2, l'`ExternalSecret` n'est identique que si les clés ont la même forme des deux côtés, par exemple `dataFrom.extract` d'un secret JSON, montré avec `gcpsm` [S44] ; non vérifié pour les fournisseurs `kubernetes` et `vault` | [M6], [S22], [S25], [S44] |
| O3. Secrets natifs | 3/5 | 6 | L'application lit le même Secret, mais ce qui le produit diffère entièrement : `task up` sur le PC, `SecretProviderClass` et `SecretSync` propres à GKE sur GCP. Rien de la chaîne GCP ne s'exerce sur le PC, et un autre cloud demanderait un autre mécanisme. Action : la matrice doit tester la synchronisation sur GCP | [S36] |

### 5.8 Expérience dev et documentation, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. OpenBao et ESO | 3/5 | 6 | Neuf étapes d'amorçage, dont trois `kubectl exec` (init, configuration, jeton), écrites et validées ici ; retour à « prêt » le plus lent après redémarrage (68,8 s) ; première réinstallation à 82,3 s, par le même retard d'ESO qu'O2. Le scellement par défaut, Shamir, revient scellé et demande la clé à chaque redémarrage [M9] : le blueprint doit passer par `static`. Action : essayer l'auto-initialisation documentée, qui supprimerait les `exec` et le jeton racine | [M1], [M7], [M9], [S10], [S24] |
| O2. ESO seul | 4/5 | 8 | Un chart et trois manifests, 22,5 s ; redémarrage transparent ; le générateur `Password` fabrique la valeur sans script [M9]. Réserves : 67,4 s pour revenir prêt, et la première réinstallation dans un cluster existant a pris 77,2 s au test de fumée, cause non établie | [M1], [M7], [M9], [S22], [S26] |
| O3. Secrets natifs | 5/5 | 10 | Un `kubectl create -f -` par Secret, alimenté par un tube, 0,1 s ; redémarrage au rythme du nœud (45,5 s) ; rien à apprendre de plus que Kubernetes | [M1], [M6], [M7], [S31] |

### 5.9 Coût (managé ou opérationnel), poids 5

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| O1. OpenBao et ESO | 4/5 | 4 | Aucune licence payante sur le PC ; OpenBao ne tourne pas sur GCP. Sur GKE, ESO ajoute trois pods à `resources: {}`, qu'Autopilot facture à 0,5 vCPU et 2 Gio chacun. Réserve : requêtes explicites à fixer, coût résiduel de trois pods | [S59], [S60], [S61], [S25] |
| O2. ESO seul | 4/5 | 4 | Même constat sur GCP | [S59], [S60], [S61] |
| O3. Secrets natifs | 5/5 | 5 | Rien d'ajouté sur le PC ni dans les pods de l'utilisateur sur GKE. Réserve : facturation de la synchronisation non documentée, grille de GKE illisible le 2026-11-19 ; 4/5 si elle en montre une | [S36], [S57] |

[BENCH] Selon [FINOPS], les secrets eux-mêmes coûtent pareil dans les trois
options : mêmes secrets dans Secret Manager, même franchise de 6 versions
actives et 10 000 accès par mois [S58]. Le nombre d'accès dépend du réglage
de relecture, pas de l'option. Pour 3 secrets relus périodiquement,
l'intervalle de relecture doit être d'au moins 15 minutes pour rester dans
la franchise, à écrire dans R-18. La grille au-delà de la franchise n'a pas
pu être lue [S56].

## 6. Grille pondérée

| Critère | Poids | O1. OpenBao et ESO | O2. ESO seul | O3. Secrets natifs |
| --- | --- | --- | --- | --- |
| Critères éliminatoires (section 3) | éliminatoire | passe | passe | passe |
| Licence et liberté d'usage | 15 | 5/5, 15 pts | 5/5, 15 pts | 5/5, 15 pts |
| Gouvernance (fondation, multi-vendeurs) | 15 | 3/5, 9 pts | 3/5, 9 pts | 2/5, 6 pts |
| Maturité et adoption | 15 | 3/5, 9 pts | 4/5, 12 pts | 4/5, 12 pts |
| Activité et maintenance | 10 | 5/5, 10 pts | 5/5, 10 pts | 5/5, 10 pts |
| Sécurité (CVE, réactivité) | 10 | 2/5, 4 pts | 3/5, 6 pts | 4/5, 8 pts |
| Empreinte sur PC (RAM, CPU, démarrage) | 10 | 4/5, 8 pts | 4/5, 8 pts | 5/5, 10 pts |
| Portabilité multi-cloud | 10 | 4/5, 8 pts | 5/5, 10 pts | 3/5, 6 pts |
| Expérience dev et documentation | 10 | 3/5, 6 pts | 4/5, 8 pts | 5/5, 10 pts |
| Coût (managé ou opérationnel) | 5 | 4/5, 4 pts | 4/5, 4 pts | 5/5, 5 pts |
| Total | 100 | 73 / 100 | 82 / 100 | 82 / 100 |

## 7. Verdict proposé

[BENCH] Option proposée : O3, Secrets natifs créés par `task up` sur le PC,
synchronisés depuis Secret Manager par GKE sur GCP. La grille met O3 et O2
(ESO seul) à égalité, 82 sur 100 chacun. O1, OpenBao et ESO, l'option
pressentie, finit à 73 : BENCH-007 ne confirme pas OpenBao en local
(US-012). Le DSI a arbitré le 2026-11-19 : en cas d'égalité ou d'écart d'un
point, O3.

[BENCH] Raisons de l'arbitrage, dans l'ordre du DSI :

1. sur `gcp`, le principe III, dans la lecture de l'ADR-009 qui attend la
   décision de Lucas, fait de la synchronisation managée de GKE le candidat
   de la cible. ESO sur GKE serait un composant open source exploité par
   l'équipe, qui demanderait un `managed_gap` ;
2. sur le PC, O3 n'ajoute aucun composant, et aucune option ne protège mieux
   le secret : etcd est en clair [M8], [S54], et le kubeconfig
   d'administration que kind écrit dans `~/.kube/config` lit tous les Secrets
   [S55] ;
3. [SECU] préfère O3 sur les deux cibles (section 10) ;
4. [FINOPS] : sur Autopilot, les trois pods d'ESO sont facturés, 0,5 vCPU et
   2 Gio chacun tant que leurs requêtes restent vides [S59], [S60].

[BENCH] Gouvernance. O3 dépend sur GCP d'une fonction de Google seul,
notée 2 (5.2) : c'est un écart au principe V. Il se justifie par le
principe III, qui demande le service managé du fournisseur sur une cible
cloud, et par un coût de sortie faible : l'application lit un Secret de même
nom dans les trois options, et passer à ESO plus tard ne touche que la couche
de cible (un `SecretStore` et des `ExternalSecret`).

[BENCH] Ce que coûte OpenBao en propre, comparé à O2 : 80,1 Mo à
télécharger en amd64, environ 24 Mio au repos, 1,4 s de plus au retour après
redémarrage, plus un serveur HTTP en clair, un jeton racine et une clé de
descellement rangée à côté de ce qu'elle protège [M2], [M5], [M7], [M8],
[S9]. Le reste du coût d'O1 est celui d'ESO, qu'O2 paie aussi.

[BENCH] Sensibilité, à partir des totaux 73, 82 et 82. L'égalité tient à un
fil : chaque ligne ci-dessous la rompt.

| Lecture | O1 | O2 | O3 | En tête |
| --- | --- | --- | --- | --- |
| Grille | 73 | 82 | 82 | Égalité, O3 par arbitrage |
| Lucas rejette la lecture de l'ADR-009 et le principe V prime | 73 | 82 | 82 | O2 : la première raison tombe, et le principe V préfère la fondation de la CNCF à une fonction de Google seul |
| Seuils du gabarit (500 Mo, 90 s, 1 Gio) au lieu des seuils adaptés | 75 | 84 | 82 | O2 |
| O2 noté sur l'arm64 seul (97,7 Mo) | 73 | 84 | 82 | O2 |
| Gouvernance de la synchronisation de GKE à 3, ou d'ESO à 4 | 73 | 82 ou 85 | 85 ou 82 | Celui qui monte |
| Synchronisation de GKE facturée : O3 à 4 en coût | 73 | 82 | 81 | O2 |
| Installation à chaud retenue au-delà de 60 s (O1 82,3 s, O2 77,2 s, O1 115,4 s à froid au test de fumée) | 71 | 80 | 82 | O3 |
| Mémoire avec la part du plan de contrôle au-delà de 256 Mio pour O1 (254,8 Mio, à 0,5 % du seuil) | 71 | 82 | 82 | Égalité |
| Mémoire lue au nœud par `docker stats` à froid (lecture de [FINOPS]) | 71 | 82 ou 80 | 82 | Égalité ou O3 |
| Volume cumulé avec kind et Envoy Gateway contre 500 Mo, amd64 (lecture b de [FINOPS]) | 73 | 82 | 80 | O2 |
| Même lecture en arm64 (O3 à 466,5 Mo, 6,7 % sous le seuil) | 73 | 82 | 82 ou 80 | Égalité ou O2 |

[BENCH] O1 reste dernier dans toutes les lectures. Entre O3 et O2, le
verdict repose sur l'arbitrage du DSI, pas sur la grille : l'ADR-007 doit le
dire.

[BENCH] Réserves à écrire dans l'ADR :

- la synchronisation de GKE est GA depuis le 2026-04-16 et compatible
  Autopilot, mais jamais exécutée par nous ; la contrainte « same region as
  the cluster » et le câblage IAM restent à essayer (R-29) [S36], [S45] ;
- Google recommande son module complémentaire CSI quand l'application le
  permet ; ESO comme la synchronisation écrivent des Secrets Kubernetes :
  c'est le prix de la parité, commun aux options ;
- etcd en clair sur le PC (R-28) : les valeurs locales restent aléatoires et
  jetables, jamais une copie d'un secret de GCP ;
- prochaine vérification proposée : 2027-05-19, ou plus tôt si OpenBao ou ESO
  changent de niveau dans leur fondation.

[BENCH] Ce que le blueprint devra faire, si l'ADR suit ce verdict :

- `task up` tire chaque valeur de `/dev/urandom` et la passe par un tube
  depuis `printf` vers `kubectl create -f -`, ou à `kubectl create secret`
  lu sur l'entrée standard, seulement si le Secret n'existe pas. Jamais de
  heredoc (fichier temporaire sous bash 3.2) ni de `kubectl apply` pour un
  Secret (annotation `last-applied-configuration`) [S49], [S50], [S51]. Rien
  dans le dépôt, rien dans un fichier du poste hors du cluster ; etcd garde
  les valeurs, qui survivent aux redémarrages [M7] ;
- Task affiche chaque commande, et son `secret: true` ne couvre ni `ps` ni la
  sortie des commandes [S53] : génération et tube dans la même ligne, jamais
  par une variable de Task ni par un argument, tâche en `silent: true` ;
- la spec fixe le nom et les clés de chaque Secret ; la couche GCP les
  produit par `SecretProviderClass` et `SecretSync`, avec Workload Identity
  et `roles/secretmanager.secretAccessor` secret par secret, à écrire par
  [OPS] et à couvrir par la matrice dès que Lucas autorise un déploiement.
  Si la rotation est activée, intervalle d'au moins 15 minutes pour 3
  secrets (R-18) ;
- un test de la matrice lance deux `task up` sur deux clusters neufs et
  échoue si une valeur se répète, fait moins de 32 caractères ou figure parmi
  des valeurs connues (`root`, `admin`, `postgres`, `password`, `changeme`,
  chaîne vide) ;
- le README dit que les secrets locaux sont en clair dans le cluster.

[BENCH] Suites : l'ADR-007, écrit par [ARCHI] ; une entrée de `catalog/`
pour la brique `secrets` (PC : Secrets Kubernetes, Apache-2.0, CNCF gradué ;
GCP : Secret Manager et synchronisation de GKE, GA), vérifiée le 2026-11-19,
sources [S31], [S36], [S40], [S45] ; `docs/prd-mvp.md` (ligne « Secrets
locaux » et US-012) et la section 6 du brief nomment OpenBao et ESO, à
amender par une PR dédiée si Lucas suit ; risques repris par le DSI dans
`docs/risques.md` : R-20 complété, R-28 (secrets locaux en clair dans etcd),
R-29 (synchronisation de GKE jamais exécutée sur un vrai cluster), et la
condition d'un miroir d'images dans R-25.

## 8. Limites et biais

| Limite | Effet possible sur le verdict | Ce qui la lèverait |
| --- | --- | --- |
| Côté GCP lu, jamais exécuté (principe X) | Gouvernance, maturité et portabilité d'O3 notées sur la documentation de GKE ; la synchronisation est GA depuis le 2026-04-16, mais la contrainte « same region as the cluster » et le câblage IAM restent à essayer (R-29) | Un essai de `SecretSync` sur GKE Autopilot, avec l'accord de Lucas ; aucun budget validable tant que les grilles de prix restent illisibles (R-05) |
| Heure d'écriture des seuils de 4.1 non prouvable par un tiers | Seuils adaptés soupçonnables d'avoir suivi les tests de fumée | Notation avec les seuils du gabarit donnée en section 7 ; à l'avenir, commiter la règle avant la première mesure |
| Périmètre : couche seule contre ses propres seuils, plate-forme contre 500 Mo (règle provisoire du DSI jusqu'à la GATE 1) | Le volume et la mémoire changent selon la lecture ; l'ordre des benchmarks peut décider des notes | Budgets par étape d'ENF-01, décision de Lucas à la GATE 1 ; les deux lectures de [FINOPS] sont en section 7 |
| Une seule machine, macOS avec OrbStack, moteur non libre (R-26) | Empreinte et temps propres à ce poste | Relancer le script sous Linux avec Docker Engine |
| Autres benchmarks sur le même moteur | Aucun pendant la série : verrou partagé, aucun autre cluster ni conteneur relevé dans `load.tsv`. BENCH-005, BENCH-004 et BENCH-009 ont tenu le verrou avant ; les tests de fumée l'ont pris eux aussi, sans autre conteneur relevé | Sans objet |
| Installation à froid variable : 115,4 s au test de fumée d'O1, 37,7 s en série | M4 dépend du réseau et du registre ; le volume (M5) non | Plusieurs exécutions à froid, sur un autre réseau |
| Réinstallation à chaud dans un cluster existant, alors que `task up` part d'un cluster neuf | M1 ne reflète pas le préchargement des images dans un nœud neuf ; l'écart de 82,3 s d'O1 vient de cette réinstallation | Mesurer `task up` sur le golden repo, images préchargées (BENCH-005) |
| Redémarrage simulé par l'arrêt du conteneur du nœud | Ne couvre ni le redémarrage du moteur ni celui du poste | Refaire M7 après un redémarrage d'OrbStack et du poste |
| Un seul secret, une seule application | Délais de synchronisation d'ESO sous charge inconnus | Mesurer avec les secrets du golden repo |
| Non essayés : auto-initialisation d'OpenBao, `scopedRBAC` d'ESO, même `ExternalSecret` sur deux fournisseurs | Notes d'O1 et d'O2 en expérience dev, sécurité et portabilité | Un essai par point sur le golden repo |
| Cause du retard d'ESO à la réinstallation non établie (82,3 s et 77,2 s, deux fois sur quatre) | Notes d'O1 et d'O2 en empreinte (sensibilité) et en expérience dev | Deux exécutions de plus et la lecture des journaux du webhook et du contrôleur de certificats |
| Comptes de commits par identifiant, robots filtrés par leur nom ; employeurs déclaratifs | Gouvernance d'O1 et d'O2 | Relire les auteurs à la main |
| Option pressentie par le PRD | Biais possible en faveur d'OpenBao ; le résultat va à l'inverse | Même script et mêmes sources pour les trois options |
| Seuil de volume écrit en connaissant la taille des images | Note d'O2 en empreinte | Les deux notes sont dans la sensibilité de la section 7 |

## 9. Sources

[BENCH] Les dates de release, les comptes d'activité, les avis de sécurité et
les métadonnées des dépôts viennent de l'API publique de GitHub, lue le
2026-11-19. Un commit est compté humain quand son auteur n'est pas un robot
(`bot`, `renovate`, `dependabot`, `github-actions`, `copilot` filtrés par leur
nom). Les tailles d'images viennent des registres, lues par
`docker manifest inspect -v` sans tirer l'image.

[BENCH] Les sources S45 à S55 viennent de la relecture de [SECU] (ses S45,
S46, S47, S51, S54, S55, S56, S57, S58, S60, S61), S56 à S61 de celle de
[FINOPS] (ses F1 à F6), toutes lues le 2026-11-19. Les autres sources des
relectures doublent [S8], [S15], [S19] et [S20], ou ne sont pas citées ici.
S36 et S43 ont été relues par [SECU] : Standard et Autopilot, Workload
Identity requise, contrainte « same region as the cluster », Secret supprimé
recréé à partir de GKE 1.35.5-gke.1163012.

| ID | URL | Lue le | Ce que la source établit | Officielle |
| --- | --- | --- | --- | --- |
| S1 | <https://github.com/openbao/openbao> | 2026-11-19 | Licence MPL-2.0, dépôt non archivé, créé le 2023-11-09 ; `MAINTAINERS.md` ; signalement des failles à `openbao-security@lists.openssf.org` | Oui |
| S2 | <https://api.github.com/repos/openbao/openbao/releases> | 2026-11-19 | 2.7.2 le 2026-10-26, release immuable ; 16 releases stables depuis le 2025-11-19 | Oui |
| S3 | <https://api.github.com/repos/openbao/openbao/commits?since=2025-11-19T00:00:00Z> | 2026-11-19 | 1 354 commits, dont 892 humains, par 120 auteurs ; `cipherboy` 226 (25,3 %), `satoqz` 201 (deux premiers à 47,9 %) ; dernier commit le 2026-11-18 | Oui |
| S4 | <https://github.com/openbao/openbao/blob/main/CONTRIBUTING.md> | 2026-11-19 | Comité technique : IOTech Systems, Wallix, Adfinis (présidence), GitLab, SAP, ControlPlane | Oui |
| S5 | <https://github.com/openbao/openbao/blob/main/GOVERNANCE.md> | 2026-11-19 | Comité formé en juin 2024 ; passage de LF Edge à l'OpenSSF en mai 2025, « becoming a sandbox project there » ; `CHARTER.md` : « OpenBao a Series of LF Projects, LLC », passage à l'OpenSSF le 2025-06-05 | Oui |
| S6 | <https://openbao.org/> | 2026-11-19 | « managed by the Linux Foundation's OpenSSF », « OpenBao is a Sandbox project » ; soutiens cités (Fermilab, Adfinis, GitLab, ControlPlane, SAP, Proton, Blendbyte, Liquid Reply), aucun adoptant | Oui |
| S7 | <https://github.com/openbao/openbao-helm/releases/tag/openbao-0.30.7> | 2026-11-19 | Chart 0.30.7 le 2026-11-06, `appVersion` v2.7.2, `kubeVersion >= 1.30.0-0` ; archive `sha256:fa4e6f3c…980f` et fichier de provenance `.prov` ; 53 releases du chart depuis le 2025-11-19 | Oui |
| S8 | <https://github.com/openbao/openbao-helm/blob/openbao-0.30.7/charts/openbao/values.yaml> | 2026-11-19 | Injecteur par défaut `docker.io/hashicorp/vault-k8s:1.7.6` par tag ; mode dev « All data is lost on restart », `devRootToken: "root"` ; mode autonome par défaut, `tls_disable = 1`, `address = "[::]:8200"`, stockage `pebbledb` ; sonde de disponibilité `bao status` (code 0 seulement descellé) | Oui |
| S9 | <https://openbao.org/docs/configuration/seal/static/> | 2026-11-19 | Scellement `static` : clé de 32 octets (AES-256-GCM-96) par `file://` ou `env://` ; avertissement : à réserver au cas où « an existing source of trust, such as another third-party secrets manager, already exists » | Oui |
| S10 | <https://openbao.org/docs/configuration/self-init/> | 2026-11-19 | Auto-initialisation par blocs `initialize` (documentation 2.7.x) ; exige un autodescellement ; « The root token is not returned to the caller and is revoked after use » | Oui |
| S11 | <https://openbao.org/docs/commands/operator/init/> | 2026-11-19 | Options `-key-shares`, `-key-threshold`, `-recovery-shares`, `-recovery-threshold`, `-format` | Oui |
| S12 | <https://openbao.org/docs/commands/kv/put/> | 2026-11-19 | `bao kv put -mount=secret foo bar=-` lit la valeur sur l'entrée standard | Oui |
| S13 | <https://api.github.com/repos/openbao/openbao/security-advisories> | 2026-11-19 | 39 avis publiés depuis le 2025-11-19 : 5 critiques, 8 élevés, 10 moyens, 16 faibles | Oui |
| S14 | <https://api.github.com/repos/openbao/openbao/releases/tags/v2.7.2> | 2026-11-19 | Sommes de contrôle signées par GPG et par Sigstore, SBOM par archive | Oui |
| S15 | <https://github.com/external-secrets/external-secrets> | 2026-11-19 | Licence Apache-2.0, dépôt non archivé, créé le 2020-11-17 ; `MAINTAINERS.md` : cinq mainteneurs et leurs affiliations ; `SECURITY.md` : signalement par courriel à une liste de la CNCF ; parrains Roche, Container Solutions, Form3, Infisical | Oui |
| S16 | <https://api.github.com/repos/external-secrets/external-secrets/releases> | 2026-11-19 | v2.15.0 et `helm-chart-2.15.0` le 2026-11-10 ; archive du chart `sha256:ed94d41c…9e1d` ; provenance in-toto et SBOM ; 25 releases de l'opérateur et 24 du chart depuis le 2025-11-19 ; reprise des releases avec v0.20.0 le 2025-09-22 | Oui |
| S17 | <https://api.github.com/repos/external-secrets/external-secrets/commits?since=2025-11-19T00:00:00Z> | 2026-11-19 | 898 commits, dont 505 humains, par 165 auteurs ; `Skarlso` et `evrardj-roche` 87 chacun (17,2 %, deux premiers à 34,5 %) ; dernier commit le 2026-11-19 | Oui |
| S18 | <https://www.cncf.io/projects/external-secrets/> | 2026-11-19 | « accepted to CNCF on July 26, 2022 at the Sandbox maturity level » | Oui |
| S19 | <https://github.com/external-secrets/external-secrets/pull/5137> | 2026-11-19 | Fusionnée le 2025-08-13 : « Project Releases Paused Until Maintainer Team is Rebuilt », jusqu'à cinq mainteneurs durables | Oui |
| S20 | <https://github.com/external-secrets/external-secrets/pull/5309> | 2026-11-19 | Fusionnée le 2025-09-12 : retrait de l'avis de pause du README | Oui |
| S21 | <https://external-secrets.io/latest/introduction/stability-support/> | 2026-11-19 | Seule la dernière version mineure est maintenue ; 2.15 pour Kubernetes 1.37 ; fournisseurs `vault` et `gcpsm` stables, `kubernetes` bêta, `openbao` alpha | Oui |
| S22 | <https://external-secrets.io/latest/provider/kubernetes/> | 2026-11-19 | `SecretStore` du fournisseur `kubernetes`, rôle en lecture et `selfsubjectrulesreviews`, `url` par défaut `kubernetes.default` | Oui |
| S23 | <https://external-secrets.io/latest/provider/hashicorp-vault/> | 2026-11-19 | `SecretStore` du fournisseur `vault` par jeton ; l'exemple de la page stocke le jeton `root` (`cm9vdA==`) | Oui |
| S24 | <https://external-secrets.io/latest/provider/openbao/> | 2026-11-19 | OpenBao passe par le fournisseur `vault`, « tested with External Secrets Operator v0.16.1 and OpenBao v2.2.0 » | Oui |
| S25 | <https://external-secrets.io/latest/provider/google-secrets-manager/> | 2026-11-19 | Fournisseur `gcpsm`, authentification `workloadIdentity` sur GKE | Oui |
| S26 | <https://external-secrets.io/latest/api/generator/password/> | 2026-11-19 | Générateur `Password` (`generators.external-secrets.io/v1alpha1`) | Oui |
| S27 | <https://external-secrets.io/latest/api/externalsecret/> | 2026-11-19 | `refreshPolicy: CreatedOnce` ; `creationPolicy: Owner` par défaut | Oui |
| S28 | <https://api.github.com/repos/external-secrets/external-secrets/security-advisories> | 2026-11-19 | 9 avis publiés depuis le 2025-11-19 : 1 critique (CVE-2026-22822, lecture de secrets par la fonction de gabarit `getSecretKey`), 3 élevés, 3 moyens, 2 faibles | Oui |
| S29 | <https://github.com/external-secrets/external-secrets/tree/helm-chart-2.15.0/deploy/charts/external-secrets> | 2026-11-19 | Chart rendu par `helm template` : `ClusterRole` du contrôleur avec `get`, `list`, `watch`, `create`, `update`, `delete`, `patch` sur les Secrets de tout le cluster ; 25 CRD ; options `scopedNamespace` et `scopedRBAC` | Oui |
| S30 | <https://github.com/external-secrets/external-secrets/blob/main/ADOPTERS.md> | 2026-11-19 | 38 adoptants déclarés par eux-mêmes | Oui, déclaratif |
| S31 | <https://kubernetes.io/docs/concepts/configuration/secret/> | 2026-11-19 | « Kubernetes Secrets are, by default, stored unencrypted in the API server's underlying data store (etcd) » ; quiconque peut créer un pod dans un namespace peut lire ses Secrets | Oui |
| S32 | <https://www.cncf.io/projects/kubernetes/> | 2026-11-19 | Kubernetes accepté à la CNCF le 2016-03-10, gradué le 2018-03-06 (lu pour BENCH-003) | Oui |
| S33 | <https://opensource.org/license/mpl-2-0> | 2026-11-19 | MPL-2.0 approuvée par l'OSI ; Apache-2.0 approuvée (<https://opensource.org/licenses>, lue pour BENCH-003) | Oui |
| S34 | <https://www.cncf.io/projects/sops/> | 2026-11-19 | « SOPS was accepted to CNCF on May 17, 2023 at the Sandbox maturity level » ; dépôt `getsops/sops` en MPL-2.0, v3.13.3 le 2026-07-23 | Oui |
| S35 | <https://docs.cloud.google.com/secret-manager/docs/secret-manager-managed-csi-component> | 2026-11-19 | Module Secret Manager de GKE, dérivé du Secrets Store CSI Driver, montage en volume ; « doesn't support the Sync as Kubernetes Secret feature » | Oui |
| S36 | <https://docs.cloud.google.com/secret-manager/docs/sync-k8-secrets> | 2026-11-19 | Synchronisation vers des Secrets Kubernetes par `SecretSync` (`secret-sync.gke.io/v1`), GKE 1.33 ou plus, option `--enable-secret-sync` ; aucun stade de lancement affiché | Oui |
| S37 | <https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0> | 2026-11-19 | kind 0.33.0 le 2026-08-26, image `kindest/node:v1.36.4@sha256:099e…faed` (lue pour BENCH-003) | Oui |
| S38 | <https://kubernetes.io/releases/> | 2026-11-19 | Branche 1.36 maintenue jusqu'au 2027-06-28 (lue pour BENCH-003) | Oui |
| S39 | <https://github.com/openbao/openbao-helm> | 2026-11-19 | Licence MPL-2.0 ; 102 commits humains par 29 auteurs depuis le 2025-11-19 | Oui |
| S40 | <https://github.com/kubernetes/kubernetes> | 2026-11-19 | Licence Apache-2.0, dépôt non archivé | Oui |
| S41 | <https://kubernetes.io/docs/reference/issues-security/security/> | 2026-11-19 | Processus de sécurité de Kubernetes, accusé de réception sous 3 jours ouvrés (lu pour BENCH-003) | Oui |
| S42 | `docker manifest inspect -v` sur `quay.io/openbao/openbao@sha256:5046…561f`, `ghcr.io/external-secrets/external-secrets@sha256:6888…0e31` et `busybox@sha256:a7db…89ec` | 2026-11-19 | Tailles compressées : OpenBao 74 573 755 octets en arm64 et 80 091 339 en amd64 ; ESO 97 736 458 et 104 555 058 ; busybox 1 901 250 et 2 211 973. Même condensat pour OpenBao sur quay.io, docker.io et ghcr.io | Oui, registres |
| S43 | <https://docs.cloud.google.com/secret-manager/docs/gke-release-notes> | 2026-11-19 | Entrées « Kubernetes Secret Sync » datées du 2026-06-25, sans mention de stade de lancement | Oui |
| S44 | <https://external-secrets.io/latest/guides/all-keys-one-secret/> | 2026-11-19 | `dataFrom.extract` copie toutes les clés d'un secret JSON, exemple avec `gcpsm`, « should work with other providers in the same way » | Oui |
| S45 | <https://docs.cloud.google.com/secret-manager/docs/release-notes> | 2026-11-19 | Synchronisation intégrée en preview le 2025-10-13 ; « generally available » le 2026-04-16 (relevé de [SECU]) | Oui |
| S46 | <https://www.mozilla.org/en-US/MPL/2.0/> | 2026-11-19 | MPL-2.0, section 3.2 : distribuer la forme exécutable oblige à rendre le source disponible | Oui |
| S47 | <https://www.mozilla.org/en-US/MPL/2.0/FAQ/> | 2026-11-19 | Q5 : aucune obligation sans distribution hors de l'organisation ; Q11 : copyleft par fichier | Oui |
| S48 | <https://openssf.org/projects/> | 2026-11-19 | OpenBao dans l'onglet « SANDBOX » de l'OpenSSF | Oui |
| S49 | <https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/> | 2026-11-19 | L'annotation `last-applied-configuration` « contains the contents of the object configuration file » | Oui |
| S50 | <https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/> | 2026-11-19 | `kubectl create -f -` ; l'annotation n'est écrite qu'avec `--save-config` | Oui |
| S51 | <https://tiswww.case.edu/php/chet/bash/NEWS> | 2026-11-19 | bash 5.1 passe les heredocs courts par un tube ; avant, par un fichier temporaire (constaté sous bash 3.2.57 par [SECU]) | Oui |
| S52 | <https://taskfile.dev/docs/guide/platforms> | 2026-11-19 | Task exécute ses commandes dans son interpréteur embarqué (`mvdan.cc/sh`), qui passe un heredoc par un tube | Oui |
| S53 | <https://taskfile.dev/docs/guide/secret-variables> | 2026-11-19 | Task affiche chaque commande sauf `silent: true` ; `secret: true` masque une variable dans cet affichage, ni dans `ps`, ni dans la sortie des commandes (avec <https://taskfile.dev/docs/guide/output>) | Oui |
| S54 | <https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/> | 2026-11-19 | « By default, the API server stores plain-text representations of resources into etcd » ; chiffrement activé par `--encryption-provider-config` | Oui |
| S55 | <https://kind.sigs.k8s.io/docs/user/quick-start/> | 2026-11-19 | kind écrit son kubeconfig dans `${HOME}/.kube/config` par défaut | Oui |
| S56 | <https://cloud.google.com/secret-manager/pricing> | 2026-11-19 | Grille illisible par les outils des agents : titre seul (relevé de [FINOPS]) | Oui |
| S57 | <https://cloud.google.com/kubernetes-engine/pricing> | 2026-11-19 | Grille illisible : titre seul (relevé de [FINOPS]) | Oui |
| S58 | <https://docs.cloud.google.com/free/docs/free-cloud-features> | 2026-11-19 | Secret Manager : « 6 active secret versions per month », « 10,000 access operations per month » | Oui |
| S59 | <https://github.com/external-secrets/external-secrets/blob/helm-chart-2.15.0/deploy/charts/external-secrets/values.yaml> | 2026-11-19 | `resources: {}` et une réplique pour le contrôleur, le webhook et le contrôleur de certificats | Oui |
| S60 | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests> | 2026-11-19 | Pod sans requête : 0,5 vCPU et 2 Gio ; « Your bill is based on the effective resource request of the Pod » | Oui |
| S61 | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview> | 2026-11-19 | Pods généralistes facturés au pod (« Pod-based billing model ») | Oui |

## 10. Relectures

| Relecteur | Porte sur | Date | Avis |
| --- | --- | --- | --- |
| [SECU] | Licences, critères éliminatoires, sécurité, identifiants par défaut, adresses d'écoute | 2026-11-19 | Réservé : le classement dépend d'une question de méthode |
| [FINOPS] | Coût, empreinte, R-04 | 2026-11-19 | Favorable, avec corrections |

[SECU] Licences et critères éliminatoires confirmés. La MPL-2.0 d'OpenBao
n'impose rien au projet qui tire l'image : licence d'O1 portée à 5, la
condition d'un miroir va à R-25. Gouvernance d'O3 ramenée à 2, parce que la
synchronisation de GKE est une fonction de Google seul, notée comme Config
Sync (BENCH-009) ; si l'ADR garde O3, il justifie l'écart au principe V. La
synchronisation de GKE est GA depuis le 2026-04-16 et compatible Autopilot.
« Rien sur disque » était faux (etcd, heredoc sous bash 3.2, annotation de
`kubectl apply`) : script, rapport et exigences du blueprint corrigés, R-20
complété par le DSI, R-28 et R-29 ouverts. Côté sécurité, [SECU] préfère O3
sur les deux cibles. Suite donnée par [BENCH] : toutes les corrections
reprises, notes changées selon l'arbitrage du DSI.

[FINOPS] Seuils de 4.1 adaptés à la couche, ce que le gabarit permet ; parts
posées par [BENCH], heure d'écriture donnée, volume noté sur l'amd64 pour les
postes Linux (Q5), notation avec les seuils du gabarit en sensibilité. M2 ne
comptait pas le serveur d'API ni etcd : M10 les mesure. La marge d'O1 au
seuil de 60 s est plus petite que l'écart entre ses exécutions : sensibilité
écrite. Coût : grilles de Secret Manager et de GKE illisibles ; les secrets
coûtent pareil dans les trois options ; les trois pods d'ESO sur Autopilot
valent 4/5 à O1 et O2. Suite donnée par [BENCH] : toutes les corrections
reprises.
