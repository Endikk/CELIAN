# ADR-007. Les secrets du projet généré sont des Secrets Kubernetes : créés par `task up` sur le PC, synchronisés depuis Secret Manager par GKE sur GCP, sous conditions

| Champ | Valeur |
| --- | --- |
| Statut | proposé |
| Date | 2026-11-20 |
| Auteur | [ARCHI] |
| Décideur | Lucas, en attente de la GATE 1 |
| BENCH lié | [BENCH-007](../benchmarks/BENCH-007-secrets-locaux.md) |
| Remplace | aucun |

## Contexte et problème

Le projet généré a besoin de secrets : les mots de passe de Postgres et du cache, les clés de l'application. Ils doivent arriver aux pods du cluster kind de la cible `local` ([ADR-004](ADR-004-cluster-local.md)) comme à ceux du cluster GKE Autopilot de la cible `gcp` ([ADR-008](ADR-008-modules-opentofu-gcp.md), proposé), sans que les manifests de l'application changent d'une cible à l'autre. Le choix doit précéder le golden repo de la phase 2. Le PRD pressentait OpenBao (section 1), et la section 6 du brief le couple à External Secrets Operator, ESO dans la suite (BENCH-007, section 1).

Les exigences viennent du PRD. US-005 veut que `task up` démarre toute la stack sans autre étape (principe VII). US-012 veut qu'aucun scan ne trouve de secret dans le dépôt généré, historique compris, et que les secrets de l'application viennent du gestionnaire de secrets de la cible, « OpenBao en local si BENCH-007 le confirme, Secret Manager sur GCP ». ENF-02 veut que seule la couche de cible change (principe II), et que le README liste les écarts restants. ENF-03 veut des dépendances figées et le délai de publication du principe VI ; ENF-04 reprend le principe IX. Côté constitution, les principes II, III, V, VI, VIII, IX et X. Côté risques : R-05 (dépense GCP non maîtrisée), R-07 (agents capables de lire et d'exfiltrer des secrets), R-18 (services GCP facturés au volume), R-20 (« Identifiants par défaut dans le golden repo »), R-28 (secrets locaux en clair dans etcd) et R-29 (synchronisation des secrets de GKE lue, jamais exécutée).

BENCH-007 pose la question en deux couches : où vivent les valeurs sur le PC, et comment elles arrivent dans le pod de la même façon que sur GCP. Dans ses trois options, l'application lit un Secret Kubernetes de même nom et de mêmes clés. Seul change ce qui le produit.

Deux faits mesurés bornent ce que le choix peut apporter sur le PC. etcd y garde les Secrets en clair : l'API du cluster kind ne porte aucune option `--encryption-provider-config` (M8). Et le kubeconfig d'administration que kind écrit, dans `~/.kube/config` par défaut, lit tous les Secrets du cluster ; tout processus de l'utilisateur peut le lire, agent compris (R-07). La condition 9 de l'ADR-004 garde ce kubeconfig hors du dépôt, sans le soustraire à ces processus. Aucune des options étudiées ne protège donc mieux la valeur sur le PC (BENCH-007, section 5.5, confirmé par [SECU]).

Sur `gcp`, le choix suit la lecture des principes III et V que propose l'[ADR-009](ADR-009-catalogue.md) (proposé) : le principe III fixe les candidats d'une cible, le principe V les départage. La synchronisation de GKE est le service managé qui produit des Secrets Kubernetes depuis Secret Manager. ESO sur GKE serait un composant libre exploité par l'équipe du projet, qui demanderait un `managed_gap`. Lucas n'a pas encore validé cette lecture (question 1). BENCH-007 juge le côté GCP sur sa documentation, sans aucune ressource créée (principe X).

## Options considérées

| Option | Score BENCH (sur 100) | Verdict | Raison principale |
| --- | --- | --- | --- |
| O3. Secrets natifs : créés par `task up` sur le PC, synchronisés par GKE sur GCP | 82 | retenue, par arbitrage | Rien d'ajouté sur le PC, ni dans les pods de l'utilisateur sur GKE ; le service managé de la cible sur `gcp` |
| O2. ESO seul : fournisseur `kubernetes` sur le PC, `gcpsm` sur GCP | 82 | écartée, par arbitrage | La meilleure parité (la même chaîne tourne sur les deux cibles) et une gouvernance de fondation, mais trois pods d'ESO de plus sur chaque cible, et sur `gcp` un composant libre là où un service managé couvre le besoin |
| O1. OpenBao et ESO | 73 | écartée | Dernière dans toutes les lectures ; OpenBao ajoute un serveur HTTP en clair, un jeton racine et une clé de descellement rangée à côté de ce qu'elle protège, sans mieux protéger la valeur |

Aucune option ne touche de critère éliminatoire (BENCH-007, section 3). BENCH-007 a écarté sans les noter SOPS, qui répond à une autre question (versionner des secrets chiffrés), le module Secret Manager de GKE et le Secrets Store CSI Driver, qui montent des fichiers et ne synchronisent pas en Secret, l'injecteur d'OpenBao, qui demande des annotations propres à OpenBao dans les pods, le mode dev d'OpenBao, au jeton `root`, et les gestionnaires à éditeur unique (section 2).

### Ce que la grille tranche, et ce qu'elle laisse ouvert

La grille met O2 et O3 à égalité, 82 sur 100 chacun. O3 prend 2 points en sécurité, 2 en empreinte, 2 en expérience dev et 1 en coût ; O2 en prend 3 en gouvernance et 4 en portabilité. Les deux comptes s'annulent, et l'arbitrage du DSI du 2026-11-19 tranche pour O3, selon sa règle « en cas d'égalité ou d'écart d'un point, O3 » (BENCH-007, section 7). Ses raisons sont à la section « Décision ».

O1, l'option pressentie, finit à 73 et reste dernière dans toutes les lectures : BENCH-007 ne confirme pas OpenBao en local (US-012). Comparé à O2, OpenBao coûte en propre 80,1 Mo à télécharger en amd64, environ 24 Mio au repos et 1,4 s de plus au retour après redémarrage. Le reste du coût d'O1 est celui d'ESO (BENCH-007, section 7).

### Sensibilité

La sensibilité de BENCH-007 (section 7), reprise en entier. La dernière colonne est un ajout de [ARCHI] : elle dit si la lecture contredit une règle déjà posée.

| Lecture | O1 | O2 | O3 | En tête | Règle déjà posée |
| --- | --- | --- | --- | --- | --- |
| Grille | 73 | 82 | 82 | Égalité, O3 par arbitrage | Sans objet |
| Lucas rejette la lecture de l'ADR-009 et le principe V prime | 73 | 82 | 82 | O2 : la première raison de l'arbitrage tombe, et V préfère la fondation de la CNCF à une fonction de Google seul | Aucune contredite : c'est la question 1, ouverte |
| Seuils du gabarit (500 Mo, 90 s, 1 Gio) au lieu des seuils adaptés à la couche | 75 | 84 | 82 | O2 | Contredit la règle provisoire du DSI : chaque couche se note contre ses propres seuils (BENCH-007, section 4.1). Elle répond pourtant à un doute réel : l'heure d'écriture des seuils adaptés n'est pas prouvable par un tiers (BENCH-007, sections 4.1 et 8) |
| O2 noté sur l'arm64 seul (97,7 Mo) | 73 | 84 | 82 | O2 | Contredit la règle qui note le volume sur la plus lourde des deux architectures, l'amd64 ici (BENCH-007, section 4.1, condition 1 ; même règle dans BENCH-004 et BENCH-008, d'après l'ADR-005) |
| Gouvernance de la synchronisation de GKE à 3, ou d'ESO à 4 | 73 | 82 ou 85 | 85 ou 82 | Celui qui monte | La synchronisation à 3 s'écarte du précédent de BENCH-009, Config Sync noté 2, que [SECU] applique. ESO à 4 suppose de lever la réserve sur la pause de ses releases, un jugement sans règle écrite |
| Synchronisation de GKE facturée : O3 à 4 en coût | 73 | 82 | 81 | O2 | Aucune contredite : fait inconnu, grilles de prix illisibles le 2026-11-19 (R-05) |
| Installation à chaud retenue au-delà de 60 s (O1 82,3 s, O2 77,2 s, O1 115,4 s à froid au test de fumée) | 71 | 80 | 82 | O3 | Contredit la condition 3 de la section 4.1, qui se lit sur la médiane de M1 (29,2 s et 22,5 s). Les valeurs retenues sont des exécutions isolées, de cause non établie |
| Mémoire avec la part du plan de contrôle au-delà de 256 Mio pour O1 (254,8 Mio, à 0,5 % du seuil) | 71 | 82 | 82 | Égalité | Aucune contredite : lecture de M10, demandée par le DSI |
| Mémoire lue au nœud par `docker stats` à froid (lecture de [FINOPS]) | 71 | 82 ou 80 | 82 | Égalité ou O3 | Aucune contredite, mais mesure plus faible : un échantillon par exécution, cache de fichiers possible ; [FINOPS] ne change aucune note sur elle |
| Volume cumulé avec kind et Envoy Gateway contre 500 Mo, amd64 (lecture b de [FINOPS]) | 73 | 82 | 80 | O2 | Contredit la règle provisoire du DSI, qui réserve le cumul à la sensibilité (BENCH-007, section 4.1 ; ADR-005, question 2) |
| Même lecture en arm64 (O3 à 466,5 Mo, 6,7 % sous le seuil) | 73 | 82 | 82 ou 80 | Égalité ou O2 | Contredit la même règle, et celle de l'amd64 |

Lecture de [ARCHI]. Deux lectures mettent O2 devant sans contredire de règle posée : le refus de la lecture de l'ADR-009 au profit du principe V, qui revient à Lucas, et une facturation de la synchronisation, qui reste à établir. Aucune lecture compatible avec les règles ne met O3 devant. Celle des installations au-delà de 60 s contredit la règle de la médiane, et la mémoire lue au nœud repose sur une mesure que [FINOPS] juge trop faible pour changer une note. Les seuils du gabarit et le volume cumulé dépendent du périmètre que Lucas fixera à la GATE 1 (ADR-005, question 2) : s'il retient l'un ou l'autre, O2 passe devant.

Grille, mesures et sources : [BENCH-007](../benchmarks/BENCH-007-secrets-locaux.md).

## Décision

Le projet généré fournit ses secrets à l'application par des Secrets Kubernetes, de même nom et de mêmes clés sur les deux cibles. Sur `local`, `task up` crée lui-même ces Secrets avec des valeurs aléatoires, sans outil ajouté au cluster. Sur `gcp`, la synchronisation de GKE (`SecretProviderClass` et `SecretSync`) les produit depuis Secret Manager. L'application lit le même Secret sur les deux cibles et ne sait pas ce qui l'a produit.

La validation d'ensemble se fait à la GATE 1, et trois points y demandent l'avis explicite de Lucas : les questions 1 à 3.

### Arbitrage

Les raisons de l'arbitrage du DSI, dans son ordre (BENCH-007, section 7) :

1. Sur `gcp`, le principe III, dans la lecture de l'ADR-009 qui attend Lucas, fait de la synchronisation managée de GKE le candidat de la cible. ESO sur GKE serait un composant libre exploité par l'équipe du projet, qui demanderait un `managed_gap`.
2. Sur le PC, O3 n'ajoute aucun composant, et aucune option ne protège mieux le secret : etcd est en clair, et le kubeconfig d'administration que kind écrit dans `~/.kube/config` lit tous les Secrets.
3. [SECU] préfère O3 sur les deux cibles. Sur le PC, O3 n'ajoute ni port, ni compte, ni contrôleur aux droits de cluster. Sur GKE, la synchronisation est tenue et corrigée par Google, alors qu'ESO tournerait chez l'utilisateur avec un `ClusterRole` sur tous les Secrets du cluster, et a publié un avis critique en douze mois (BENCH-007, sections 5.5 et 10).
4. [FINOPS] : sur Autopilot, les trois pods d'ESO sont facturés, 0,5 vCPU et 2 Gio chacun tant que leurs requêtes restent vides. Sur le PC, la mesure M10, faite après sa relecture, montre qu'ESO ajoute environ 100 Mio au serveur d'API, avec ses 25 CRD : 232 Mio en moyenne avec O3, 332 à 339 Mio avec ESO.

Les raisons 2 et 4 recoupent en partie des notes de la grille (sécurité, empreinte, expérience dev, coût) : elles expliquent l'égalité plus qu'elles ne la rompent. Les raisons 1 et 3 viennent de hors de la grille, et ce sont elles qui tranchent.

Ajout de [ARCHI] sur la raison 1. Une fois la lecture de l'ADR-009 admise, l'avance d'O2 en portabilité ne tient que si ESO tourne aussi sur `gcp`. Or le `managed_gap` qu'il y faudrait doit dire pourquoi aucun service managé ne couvre le besoin, alors que la synchronisation produit le même Secret. Le mélange d'ESO sur le PC et de la synchronisation sur GKE garderait le coût d'O2 sur le PC et ferait tourner sur le poste une chaîne absente de la cible : il perdrait l'avantage qu'il était censé apporter.

### Répartition par couche

| Couche | Contenu |
| --- | --- |
| commune | Les manifests de l'application lisent chaque Secret par son nom et ses clés. Aucun objet Secret, aucune valeur |
| `local` | Les tâches de `task up` qui créent les Secrets selon la condition 1, silencieuses. Le README dit que les secrets locaux sont en clair dans le cluster (R-28) |
| `gcp` | Dans la couche OpenTofu de l'ADR-008 : les secrets de Secret Manager, écrits par des attributs en écriture seule (`secret_data_wo`, condition 3 de l'ADR-008) ; l'activation de la synchronisation sur le cluster ; les liaisons IAM secret par secret. Dans les manifests de la couche : `SecretProviderClass` (`secrets-store.csi.x-k8s.io/v1`, `provider: gke`) et `SecretSync` (`secret-sync.gke.io/v1`). La documentation active la synchronisation par l'option `--enable-secret-sync` de `gcloud` ; l'équivalent OpenTofu n'a pas été vérifié ([OPS]) |

### Stade de la synchronisation de GKE

Faits relevés par [SECU] le 2026-11-19 et relus par [ARCHI] le 2026-11-20 sur les pages officielles (section « Sources »). Les notes de version de Secret Manager datent la preview du 2025-10-13 (« Integrated secret synchronization feature is now available in preview ») et la GA du 2026-04-16 (« The integrated secret synchronization feature is generally available »). La page de la fonction écrit « This feature requires GKE version 1.33 and later » et « This feature is available on both Standard and Autopilot clusters ». Elle exige Workload Identity Federation for GKE pour l'authentification, que GKE Autopilot préconfigure (ADR-008). Les notes de version de GKE pour la synchronisation, datées du 2026-06-25, ajoutent la recréation automatique d'un Secret synchronisé supprimé à partir de 1.35.5-gke.1163012, et un correctif de CVE à partir de 1.36.0-gke.4447000.

La même page laisse des points ouverts. « The secret version must be in the same region as the cluster », alors que son exemple désigne le secret sans région (question 3). Elle ne dit rien du prix, ni du comportement face à un Secret existant de même nom ; les notes de GKE mentionnent seulement une meilleure détection des conflits de « server-side apply ». Selon [FINOPS], elle ne dit pas non plus si le Secret suit une nouvelle version du secret quand la rotation n'est pas activée. Enfin, Google y recommande son module complémentaire « whenever your application supports it », comme « a more secure method » : voir « Négatives ».

### Conditions

La décision ne vaut qu'avec elles. Chaque contrôle cité entre dans la matrice de validation (principe I).

1. Création des Secrets sur `local` (R-20, « Identifiants par défaut dans le golden repo »). `task up` tire chaque valeur de `/dev/urandom` et la passe par un tube, depuis `printf`, à `kubectl create -f -`, seulement si le Secret n'existe pas. `kubectl create` échoue sur un objet qui existe déjà, et n'écrit l'annotation `last-applied-configuration` qu'avec `--save-config` (BENCH-007, S50). Jamais de heredoc, qui passe par un fichier temporaire sous le bash 3.2 de macOS (S51) ; l'interpréteur embarqué de Task passe un heredoc par un tube (S52), mais une tâche qui appelle bash retomberait sur le fichier. Jamais de `kubectl apply` pour un Secret, qui recopie la valeur dans l'annotation (S49). Aucune valeur dans un fichier, une variable de Task ou un argument de commande : Task affiche chaque commande avant de la lancer, et son option `secret: true` ne couvre ni `ps` ni la sortie des commandes (S53). Les tâches qui manipulent un secret sont en `silent: true`. Aucune tâche ne lit Secret Manager vers le cluster local (R-28). Contrôles :
   - deux `task up` sur deux clusters neufs ; le test échoue si une valeur se répète, fait moins de 32 caractères ou figure dans une liste de valeurs connues (`root`, `admin`, `postgres`, `password`, `changeme`, chaîne vide) ;
   - ajout de [ARCHI] : après `task up`, le test échoue si un Secret de l'application porte l'annotation `kubectl.kubernetes.io/last-applied-configuration`, trace d'un `kubectl apply`. Un second `task up` sur le même cluster laisse inchangée l'empreinte SHA-256 de chaque valeur ;
   - ajout de [ARCHI] : un contrôle statique refuse tout objet `kind: Secret` versionné dans le projet généré, et toute tâche qui crée un Secret sans `silent: true`, avec un heredoc ou par `kubectl apply`. L'outil se fixe avec [SECU] et [QA].
2. Synchronisation sur GKE (R-29). Version minimale 1.35.5-gke.1163012, qui recrée un Secret synchronisé supprimé. `roles/secretmanager.secretAccessor` donné secret par secret au compte de service Kubernetes de l'application, par un principal `principal://` de Workload Identity, jamais au niveau du projet. La rotation s'active par `--enable-secret-sync-rotation`, avec un intervalle de 2 minutes par défaut et de 1 minute au moins. Si le blueprint l'active, l'intervalle est d'au moins 15 minutes pour 3 secrets, pour rester dans la franchise de 10 000 accès par mois (BENCH-007, section 5.9 ; R-18). Au défaut de 2 minutes, un seul secret dépasse la franchise (R-29). Le seuil se recalcule quand le nombre de secrets change, et suppose que rien d'autre ne consomme la franchise du compte de facturation ([FINOPS]). Contrôle : une politique conftest sur la configuration OpenTofu refuse une liaison de ce rôle au niveau du projet, une version de cluster sous la minimale et un intervalle sous le seuil. Les attributs OpenTofu qui portent l'activation et l'intervalle n'ont pas été vérifiés ([OPS]). La version par défaut du canal Regular relevée par l'ADR-004, 1.36.4-gke.2377000, est au-dessus de la minimale en numéro ; que la recréation y figure se vérifie au test de la condition 3.
3. Test de la matrice sur GKE Autopilot (R-29, principe X). Il tourne avec l'accord de Lucas et un budget validé par [FINOPS], au premier apply réel, prévu en phase 2 (R-17), et avant la GATE 2. Il échoue si le Secret produit n'a pas le nom et les clés de la condition 5, si un pod ne le lit pas, ou si le compte de service de l'application lit un secret de Secret Manager qui ne lui est pas donné. Il tranche ce que la documentation laisse ouvert : un secret global face à la contrainte de région, un Secret existant de même nom, la recréation d'un Secret supprimé, le suivi d'une nouvelle version sans rotation. Tant qu'il n'a pas passé, la ligne `gcp` de l'entrée de catalogue garde ces points en `pending`, aucun blueprint ne s'en sert (principe IV), et la combinaison n'est pas proposée (principe I). Aucun budget n'est validable tant que les grilles de prix restent illisibles (R-05 ; BENCH-007, section 8).
4. Repli sur ESO, pour la seule cible `gcp`. Si le test de la condition 3 échoue sur un point que la couche `gcp` ne sait pas corriger, cette couche passe à ESO : un `SecretStore` du fournisseur `gcpsm`, authentifié par Workload Identity (BENCH-007, S25), et des `ExternalSecret` qui produisent les mêmes Secrets. Les manifests de l'application et la couche `local` ne changent pas, et le contrôle de la condition 5 passe sans modification. Le repli passe par un nouvel ADR, qui porte le `managed_gap` de l'ADR-009 avec ce que le test a montré. Il demande : `scopedNamespace` et `scopedRBAC` essayés avant usage, puisque le contrôleur reçoit par défaut tous les droits sur les Secrets du cluster (R-29 ; BENCH-007, S29) ; des `requests` explicites sur ses trois pods (condition 9 de l'ADR-008) ; ses images figées par condensat (ENF-03) ; un intervalle de relecture dans la franchise, `CreatedOnce` ou une heure pour 3 secrets d'après [FINOPS] (R-18) ; aucun exemple de la documentation d'ESO recopié avec son jeton `root` (R-20).
5. Parité du Secret. Ajout de [ARCHI], sur le modèle de la condition 5 de l'ADR-005. Le nom et les clés de chaque Secret sont fixés une fois, pour les deux cibles. La matrice rend les manifests de l'application pour `local` et pour `gcp`, et échoue si leurs références aux Secrets diffèrent : nom, clés, lecture par variable d'environnement ou par volume. Elle vérifie aussi que le Secret produit porte exactement ces clés, après `task up` sur `local` et au test de la condition 3 sur `gcp`. Un écart voulu passe par un ADR et se liste au README (ENF-02).

### Portée

La spec ne nomme ni Secret Manager, ni la synchronisation de GKE, ni la méthode de `task up` : ils vivent dans les couches de cible du blueprint et au catalogue (principe II). Brique abstraite : `secrets`, nom repris de BENCH-007 (section 7) et proposé par le DSI, à confirmer en phase 3 avec le schéma de spec, comme son `declared_by` (ADR-009). BENCH-007 place dans la spec le nom et les clés de chaque Secret ; la forme se fixe au même moment.

Restent hors de cette décision : la rotation des secrets ; le chiffrement d'etcd au repos sur le PC ; l'identité de la CI et l'état OpenTofu (R-19) ; les identifiants GCP et GitHub de l'utilisateur, deuxième critère de US-012 ; les identifiants de services tiers sur le PC (question 2) ; le chiffrement applicatif des Secrets sur GKE par Cloud KMS, question de [SECU] pour [OPS] et [FINOPS] ; la chaîne AUTH de Memorystore, générée par le serveur, que l'ADR-008 renvoie au benchmark du moteur de cache ; Windows (Q5) ; l'on-prem.

## Conséquences

### Positives

- Sur le PC, rien d'ajouté : aucune image à télécharger, aucun pod, des Secrets créés en 0,1 s (M1, M2, M5). Sur nœud neuf, `kube-system` occupe au repos 446,9 Mio, contre 542,4 avec ESO seul et 547,1 avec OpenBao et ESO (M10).
- Après un redémarrage du nœud, l'option est prête au rythme du nœud, 45,5 s, contre 67,4 s avec ESO seul et 68,8 s avec OpenBao et ESO, et les valeurs sont conservées (M7).
- Aucun port, aucun compte, aucun opérateur ajouté ; l'hôte ne publie que l'API, sur 127.0.0.1 (M8).
- Sur GKE, aucun pod ajouté dans le cluster de l'utilisateur, donc rien de facturé à ce titre sur Autopilot, où chaque pod d'ESO sans requête compterait 0,5 vCPU et 2 Gio, soit 23,4 USD par mois aux prix d'exemple de us-central1 (ADR-008, condition 9). La synchronisation est tenue et corrigée par Google.
- Ni amorçage d'OpenBao, ni jeton racine, ni clé de descellement à garder.
- Le contrat entre l'application et la cible tient en un Secret de nom et de clés fixés. Le repli sur ESO ne touche que la couche `gcp` (condition 4).

### Négatives

- Rien de la chaîne GCP ne s'exerce sur le PC. Une erreur dans `SecretProviderClass`, `SecretSync` ou les liaisons IAM ne se voit que sur GKE, d'où la portabilité à 3/5 et le test de la condition 3, qui demande une dépense (R-29).
- Sur `gcp`, dépendance à une fonction de Google seul, sans fondation : gouvernance à 2/5. Un autre cloud demandera un autre mécanisme.
- Sur le PC, les valeurs sont en clair dans etcd et lisibles par le kubeconfig d'administration (R-28). Les trois options partagent ce point, et les contrôleurs d'entrée de BENCH-004 lisent eux aussi tous les Secrets du cluster (ADR-005).
- Google recommande son module complémentaire, qui monte des fichiers, comme la méthode la plus sûre quand l'application le permet. La synchronisation comme ESO écrivent des Secrets Kubernetes : c'est le prix de la parité, commun aux options.
- `task up` porte la logique de création, avec ses pièges. Un `kubectl apply` ou une variable de Task glissés dans une tâche réintroduiraient la fuite sans erreur, d'où les contrôles de la condition 1.
- La facturation de la synchronisation n'est pas documentée, et les grilles de Secret Manager et de GKE étaient illisibles le 2026-11-19 (R-05).
- Les mesures viennent d'un seul poste, sous macOS avec OrbStack, moteur non libre (R-26). Côté GCP, rien n'a été exécuté.
- Le PRD (section 1 et US-012) nomme OpenBao, et la section 6 du brief le couple à ESO.

### Effet sur les cibles hors MVP

La porte reste ouverte. Toute cible capable de produire un Secret Kubernetes de nom et de clés fixés s'ajoute par sa couche, sans toucher l'application. Qu'AWS et Azure proposent un mécanisme managé équivalent à la synchronisation de GKE n'a pas été vérifié pour cet ADR ; sans lui, leur couche passerait par un composant libre avec `managed_gap`, ESO par exemple, dont les fournisseurs pour ces clouds n'ont pas été lus. Une cible on-prem serveurs aurait son propre benchmark, où OpenBao resterait candidat (BENCH-007, section 5.7).

### Suites

- Entrée de catalogue `secrets`, dans une PR qui suit la GATE 1 (section « Entrée au catalogue »).
- Pour [PO], si Lucas suit : une PR dédiée corrige la ligne « Secrets locaux » de la section 1 du PRD et le troisième critère de US-012, qui nomment OpenBao. BENCH-007 cite aussi la section 6 du brief.
- Pour le DSI : compléter R-18 avec l'intervalle de la condition 2, comme le demande [FINOPS] (BENCH-007, section 5.9).
- Pour [OPS] : les attributs OpenTofu de l'activation et de l'intervalle ; la version minimale de la condition 2 dans la règle de version de l'ADR-004 ; la préparation du test de la condition 3 et la question 3.
- Pour [SECU] et [QA] : les contrôles statiques des conditions 1 et 5, la politique conftest de la condition 2.
- Pour [DEV], en phase 2 : les tâches de création des Secrets du golden repo, sous la condition 1.

### Questions ouvertes

1. Lecture des principes III et V de l'ADR-009, pour Lucas. La ligne `gcp` en dépend. Si V prime, O2 passe devant et un nouvel ADR remplace celui-ci. Si Lucas retient la lecture littérale, où chaque service managé déroge à V, la ligne `gcp` devient une dérogation, justifiée au paragraphe « Écart au principe V ».
2. Identifiants de services tiers sur le PC, pour Lucas et [PO]. Le blueprint du MVP a-t-il besoin d'un vrai identifiant tiers en local, SMTP, paiement ou client OAuth d'un fournisseur ? La condition 1 ne couvre que les valeurs que le projet tire lui-même, et un identifiant tiers n'aurait pas d'autre chemin qu'un fichier ou une commande tapée à la main. Si oui, [SECU] propose une tâche `task secret:set NOM` qui lit l'entrée standard sans écho, et des clés de test seulement (R-28).
3. Contrainte « same region as the cluster », pour Lucas. La page ne dit pas si un secret global convient, et un cluster Autopilot est toujours régional (ADR-008). Deux voies : le trancher au test de la condition 3, la ligne `gcp` restant d'ici là en `pending` et inutilisable par un blueprint, ou demander à [OPS] de ranger d'emblée les secrets dans la région du cluster, si Secret Manager le permet, ce que cet ADR n'a pas vérifié.

## Conformité à la constitution

Vérifiée contre la [constitution](../../.specify/memory/constitution.md) en version 1.0.0. L'amendement 1.1.0 (PR #13) ne touche que la section « Périmètre du MVP ».

| Principe | Effet | Justification |
| --- | --- | --- |
| I. Rien sans test automatique | respecté | La matrice porte les contrôles des conditions 1, 2 et 5, et le test sur GKE de la condition 3 ; sans lui, la combinaison `gcp` n'est pas proposée |
| II. Spec abstraite, catalogue concret | respecté | La spec ne nomme que la brique `secrets` ; `task up` et la synchronisation vivent dans leurs couches de cible, et la condition 5 vérifie que les manifests de l'application ne changent pas |
| III. Managé sur le cloud, open source ailleurs | respecté | Sur `local`, l'API Secret de Kubernetes, sous Apache-2.0, sans rien d'ajouté ; sur `gcp`, Secret Manager et la synchronisation de GKE, services managés, dans la lecture de l'ADR-009 qui attend Lucas |
| IV. Catalogue traçable | respecté | Les deux lignes de l'entrée portent licence ou fournisseur, gouvernance, statut, date et sources ; la ligne `gcp` garde ses `pending` jusqu'au test de la condition 3 |
| V. Gouvernance ouverte d'abord | respecté dans la lecture de l'ADR-009 | Sur `local`, Kubernetes, gradué à la CNCF. Sur `gcp`, service managé imposé par III, sans justification à fournir (gabarit d'ADR, ADR-009) ; l'écart est tout de même écrit ci-dessous, pour le cas où Lucas retiendrait une autre lecture |
| VI. Récent mais éprouvé | respecté | Aucun critère éliminatoire touché (BENCH-007, section 3) ; la synchronisation est GA depuis le 2026-04-16, et la branche 1.36 de Kubernetes est maintenue jusqu'au 2027-06-28 |
| VII. Une commande pour démarrer | respecté | `task up` crée les Secrets lui-même, sans étape manuelle, et ne recrée pas un Secret existant |
| VIII. Aucun fait de mémoire | respecté | Les faits renvoient à BENCH-007, aux relectures et aux pages officielles relues le 2026-11-20 ; sont signalés comme non vérifiés les attributs OpenTofu, la conduite face à un Secret existant, la contrainte de région, la facturation et l'offre d'AWS et d'Azure |
| IX. Aucun secret dans le dépôt | respecté | Aucune valeur dans le dépôt ni dans un fichier du poste hors du cluster ; aucun `.env` (R-20) ; le contrôle statique de la condition 1 refuse un Secret versionné |
| X. Aucune dépense cloud sans accord | respecté | Aucune ressource GCP créée pour BENCH-007 ni pour cet ADR ; le test de la condition 3 attend l'accord de Lucas et un budget de [FINOPS] |

### Écart au principe V

Sur `gcp`, O3 dépend d'une fonction de Google seul, notée 2 en gouvernance, quand ESO, au bac à sable de la CNCF depuis le 2022-07-26, est noté 3 (BENCH-007, section 5.2). Dans la lecture de l'ADR-009, cet écart n'a pas à se justifier : le principe III impose le service managé du fournisseur sur une cible cloud, et le principe V ne départage que les candidats que III autorise. Le gabarit d'ADR le dit aussi. Ce paragraphe sert si Lucas retient la lecture littérale.

Aucun critère de la grille ne l'emporte seul : les 7 points qu'O2 prend en gouvernance et en portabilité, O3 les reprend en sécurité, en empreinte, en expérience dev et en coût. L'écart se justifie donc hors de la grille. D'abord par son coût de sortie : ce que les deux cibles partagent est l'objet Secret de l'API Kubernetes, et passer à ESO ne touche que la couche `gcp` (condition 4), sur un cluster qui dépend de toute façon de Google. Ensuite par la sécurité : la synchronisation est tenue par Google, alors qu'ESO tournerait chez l'utilisateur avec tous les droits sur les Secrets du cluster (BENCH-007, section 5.5). La fondation d'ESO protège d'ailleurs moins que le principe V ne le suppose : faute de mainteneurs, son équipe a suspendu toutes ses releases du 2025-08-13 au 2025-09-12 (section 5.2).

### Dérogations

Aucune dans la lecture de l'ADR-009. Si Lucas retient la lecture littérale, la ligne `gcp` devient la dérogation suivante :

| Principe | Écart | Justification | Durée | Condition de levée |
| --- | --- | --- | --- | --- |
| V. Gouvernance ouverte d'abord | Ligne `gcp` : fonction de Google seul, sans fondation | Coût de sortie limité à la couche `gcp`, et sécurité (paragraphe précédent) | Tant que la ligne `gcp` repose sur la synchronisation de GKE | Repli sur ESO (condition 4), ou validation de la lecture de l'ADR-009 |

Si V prime, l'écart ne se justifie plus : O2 passe devant, et un nouvel ADR remplace celui-ci.

## Entrée au catalogue

Brique abstraite : `secrets`, nom proposé par le DSI, à confirmer en phase 3 avec le schéma de spec. L'entrée s'écrit au format de l'ADR-009, dans une PR qui suit la GATE 1.

| Cible | Service | Type | Licence | Gouvernance | Statut | Vérifié le | Source |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `local` | API Secret de Kubernetes, portée par le cluster de la brique `kubernetes-cluster` ; valeurs créées par `task up` | `oss` | Apache-2.0 | Fondation : Kubernetes, gradué à la CNCF le 2018-03-06 | actif | 2026-11-20 | <https://kubernetes.io/docs/concepts/configuration/secret/>, <https://github.com/kubernetes/kubernetes>, <https://kubernetes.io/releases/> |
| `gcp` | Secret Manager, synchronisé en Secrets Kubernetes par GKE (`SecretProviderClass`, `SecretSync`) | `managed` | service propriétaire du fournisseur | Éditeur unique : Google | actif | 2026-11-20 | <https://docs.cloud.google.com/secret-manager/docs/sync-k8-secrets>, <https://docs.cloud.google.com/secret-manager/docs/release-notes> |

Les deux lignes exposent le standard `kubernetes-api`, présent dans la liste fermée du catalogue : l'application lit un objet Secret de cette API sur les deux cibles. La ligne `gcp` n'a pas de `managed_gap`.

Pour `local`, `version` vaut 1.36.4, la version de l'image de nœud fixée par la règle de version de l'ADR-004, qu'elle suit sans tenir sa propre valeur. `last_release_on` vaut 2026-09-15 : 1.37.1 et 1.36.5, dernières releases de Kubernetes, sont datées de ce jour sur la page des releases relue le 2026-11-20. `verified_on` suit cette lecture, la plus récente des sources de la ligne.

La ligne `gcp` garde en `pending`, jusqu'au test de la condition 3 : la contrainte de région ([OPS], question 3), la conduite face à un Secret existant ([OPS]), la facturation de la synchronisation ([FINOPS]) et les attributs OpenTofu de l'activation et de l'intervalle ([OPS]).

## Condition de révision

Bascule par un nouvel ADR qui remplace celui-ci pour la cible concernée dans ces cas :

- sur `gcp`, le test de la condition 3 échoue sur un point que la couche `gcp` ne corrige pas : repli sur ESO (condition 4) ;
- Google retire la synchronisation de GKE ou la sort de la GA ;
- sur `local`, Kubernetes touche un critère éliminatoire : dépôt archivé, licence qui n'est plus open source, ou aucune release pendant 12 mois, décompte parti du 2026-09-15.

La décision se rouvre, sans basculer d'office, dans ces cas :

- Lucas ne retient pas la lecture des principes III et V de l'ADR-009 (question 1) ;
- la synchronisation se révèle facturée : O3 tombe à 81 contre 82. Dans la lecture de l'ADR-009, un prix seul n'établit pas de `managed_gap` ; la comparaison porte alors sur ce prix et sur celui des trois pods d'ESO, requêtes explicites comprises ;
- à la GATE 1, Lucas note le volume cumulé de la plate-forme, applique à chaque couche les seuils du gabarit (ADR-005, question 2), ou revient sur le volume noté en amd64 : O2 passe devant ;
- ESO change de niveau à la CNCF : sa gouvernance à 4 mettrait O2 à 85 (BENCH-007, section 7) ;
- une cible hors MVP est ouverte.

Un changement de mineure de Kubernetes ne rouvre pas cet ADR : la règle de version de l'ADR-004 s'applique. Sans l'un de ces faits, prochaine vérification le 2027-05-19, date proposée par BENCH-007.

## Sources

Ce que BENCH-007 établit se cite par lui ; ses propres sources sont dans sa section 9.

| Source | Lue le | Ce qu'elle établit |
| --- | --- | --- |
| [BENCH-007](../benchmarks/BENCH-007-secrets-locaux.md), sections 1 à 3 | 2026-11-19 | Question posée et ce qui en dépend ; options, versions, options non étudiées ; critères éliminatoires |
| BENCH-007, section 4 | 2026-11-19 | Seuils et périmètre de la couche, règle provisoire du DSI ; protocole, dont la correction du script après [SECU] ; mesures M1 à M10 |
| BENCH-007, sections 5 et 6 | 2026-11-19 | Notes et justifications, dont la gouvernance de la synchronisation à 2 ; franchise de Secret Manager et intervalle de 15 minutes pour 3 secrets ; grille 73, 82, 82 |
| BENCH-007, section 7 | 2026-11-19 | Arbitrage du DSI du 2026-11-19 et ses quatre raisons ; paragraphe de gouvernance ; coût propre d'OpenBao ; sensibilité ; réserves ; exigences pour le blueprint ; brique `secrets` ; prochaine vérification au 2027-05-19 |
| BENCH-007, sections 8 à 10 | 2026-11-19 | Limites ; sources S1 à S61, dont S25, S29, S49 à S53 citées ici ; avis de [SECU] et de [FINOPS] |
| Relectures de BENCH-007 par [SECU] et par [FINOPS], résumées en section 10 du rapport | 2026-11-19 | Préférence de [SECU] pour O3 et ses motifs ; tâche `task secret:set` proposée pour des identifiants tiers ; silence de la documentation sur le suivi d'une nouvelle version sans rotation ; hypothèse d'une franchise que rien d'autre ne consomme |
| [docs/risques.md](../risques.md), R-05, R-07, R-17, R-18, R-19, R-20, R-26, R-28, R-29 | 2026-11-20 | Mitigations reprises dans les conditions 1 à 4 ; apply réels prévus aux phases 2 et 6 ; budget prêt avant la GATE 2 |
| [ADR-004](ADR-004-cluster-local.md), condition 9 et règle de version | 2026-11-20 | Kubeconfig hors du dépôt ; mineure 1.36, image v1.36.4 ; défaut de Regular à 1.36.4-gke.2377000 |
| [ADR-005](ADR-005-gateway.md), proposé : condition 5, conséquences, question 2 | 2026-11-20 | Modèle de la condition de parité ; contrôleurs d'entrée qui lisent tous les Secrets ; volume noté en amd64 ; règle provisoire du périmètre |
| [ADR-008](ADR-008-modules-opentofu-gcp.md), proposé : conditions 3 et 9, mode du cluster | 2026-11-20 | GKE Autopilot, toujours régional, fédération d'identité préconfigurée ; `secret_data_wo` ; requêtes explicites, 23,4 USD par pod sans requête ; chaîne AUTH de Memorystore hors de sa portée |
| [ADR-009](ADR-009-catalogue.md), proposé | 2026-11-20 | Lecture des principes III et V ; `managed_gap` ; format d'une entrée, types `oss` et `managed`, `pending`, standard `kubernetes-api` ; règles de fraîcheur |
| [docs/adr/TEMPLATE.md](TEMPLATE.md) | 2026-11-20 | Un service managé imposé par III ne demande pas la justification du principe V |
| [docs/prd-mvp.md](../prd-mvp.md), section 1, US-005, US-012, ENF-02, ENF-03, ENF-04 | 2026-11-20 | OpenBao pressenti ; démarrage en une commande ; aucun secret, gestionnaire de la cible ; parité ; dépendances figées |
| [Constitution](../../.specify/memory/constitution.md), version 1.0.0 | 2026-11-20 | Principes I à X ; dérogation par ADR |
| <https://docs.cloud.google.com/secret-manager/docs/sync-k8-secrets> (S36 de BENCH-007) | 2026-11-20, relevé de [SECU] le 2026-11-19 | GKE 1.33 ou plus ; Standard et Autopilot ; Workload Identity requise ; « The secret version must be in the same region as the cluster » ; `--enable-secret-sync-rotation`, défaut 2 minutes, minimum 1 minute, `--secret-sync-rotation-interval` ; apiVersion et kind de `SecretProviderClass` et `SecretSync`, `provider: gke` ; `roles/secretmanager.secretAccessor` par principal `principal://` ; module complémentaire « a more secure method » ; rien sur le prix ni sur un Secret existant |
| <https://docs.cloud.google.com/secret-manager/docs/release-notes> (S45 de BENCH-007) | 2026-11-20, relevé de [SECU] le 2026-11-19 | Preview le 2025-10-13 ; GA le 2026-04-16 |
| <https://docs.cloud.google.com/secret-manager/docs/gke-release-notes> (S43 de BENCH-007) | 2026-11-20, relevé de [SECU] le 2026-11-19 | Entrée du 2026-06-25 : recréation des Secrets supprimés à partir de 1.35.5-gke.1163012, détection des conflits de « server-side apply » ; correctif de CVE à partir de 1.36.0-gke.4447000 |
| <https://kubernetes.io/releases/> (S38 de BENCH-007) | 2026-11-20 | 1.37.1 et 1.36.5 publiées le 2026-09-15 ; fin de vie de 1.36 le 2027-06-28 |
