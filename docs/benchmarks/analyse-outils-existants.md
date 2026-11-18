# Analyse des outils existants

| Champ | Valeur |
| --- | --- |
| Statut | brouillon |
| Date | 2026-11-15 |
| Auteur | [BENCH] |
| Demandé par | [DSI], phase 1, étape 2 |
| Origine | Question Q12 du [PRD](../prd-mvp.md), section 8, tableau des questions tranchées |
| Suite | Options pour BENCH-001, BENCH-002 et BENCH-005, proposition d'un benchmark sur les modules OpenTofu GCP |

## 1. Objet et méthode

[BENCH] La question : un outil existant couvre-t-il déjà l'essentiel de la promesse de CELIAN, au point qu'il vaudrait mieux l'adopter ou l'adapter ? Le PRD notait qu'aucune analyse concurrentielle n'avait été faite (section 8, hypothèses).

[BENCH] Chaque outil est confronté aux six piliers de CELIAN :

1. un entretien guidé qui produit une spec abstraite (`database: postgres`), source de vérité ;
2. un catalogue qui traduit la spec en service concret selon la cible, avec licence, gouvernance, statut et date ;
3. une génération déterministe depuis des blueprints testés ;
4. un agent limité aux ADR et aux textes du projet, sous une validation qui le renvoie corriger ;
5. le jour 2 : le projet généré reçoit les correctifs du blueprint ;
6. la parité locale : une commande sur un PC (k3d), et un déploiement sur GCP.

[BENCH] « Couvert » : l'outil fait ce que demande le pilier, sans développement. « Partiel » : il en fait une partie, ou le fait hors du périmètre du MVP (autre cloud, autre langage). « Absent » : rien dans les pages lues. Les cases viennent de la documentation officielle lue le 15/11/2026, sans essai sur machine. Aucun chiffre d'adoption n'est repris.

## 2. Couverture des piliers

| Outil | 1. Spec abstraite | 2. Catalogue par cible | 3. Génération | 4. Agent et validation | 5. Jour 2 | 6. PC et GCP |
| --- | --- | --- | --- | --- | --- | --- |
| Backstage Software Templates | partiel | absent | partiel | absent | absent | absent |
| Score | partiel | partiel | partiel | absent | absent | partiel |
| Radius | partiel | partiel | absent | absent | absent | partiel |
| Crossplane | partiel | partiel | absent | absent | absent | partiel |
| Kratix | partiel | partiel | absent | absent | absent | absent |
| Copier | partiel | absent | couvert | absent | couvert | absent |
| Cookiecutter et cruft | partiel | absent | couvert | absent | partiel | absent |
| JHipster | partiel | absent | couvert | absent | couvert | partiel |
| Aspire et modèles `dotnet new` | partiel | partiel | partiel | absent | absent | partiel |
| Cloud Foundation Fabric et modules Google | absent | partiel | partiel | absent | absent | partiel |
| Encore | partiel | partiel | absent | absent | absent | partiel |
| Application Design Center | partiel | partiel | partiel | partiel | partiel | absent |

[BENCH] Aucun outil ne couvre plus de deux piliers. Aucun ne couvre le pilier 4.

## 3. Licence, gouvernance, activité

[BENCH] Le seuil de release est le 15/11/2025, douze mois avant la lecture (principe VI).

| Outil | Licence | Gouvernance | Dernière release | Critère éliminatoire | Sources |
| --- | --- | --- | --- | --- | --- |
| Backstage | Apache-2.0 | CNCF Incubating depuis le 15/03/2022, créé par Spotify | v1.56.5, 12/11/2026 | aucun | S1 à S3 |
| Score | Apache-2.0 | CNCF Sandbox depuis le 08/07/2024 ; mainteneurs chez Oracle, Docker, Checkly, plus un indépendant | score-k8s 0.23.0, 14/11/2026 | aucun | S6 à S8, S10 |
| Radius | Apache-2.0 | CNCF Sandbox depuis le 16/04/2024, lancé par l'équipe Azure Incubations de Microsoft | v0.62.0, 27/10/2026 | aucun | S11 à S13, S15 |
| Crossplane | Apache-2.0 | CNCF Graduated depuis le 28/10/2025 | v2.4.3, 22/10/2026 | aucun | S16 à S18 |
| Kratix | Apache-2.0 | Syntasso, éditeur unique, aucune fondation citée | numérotée : v0.125.0, 08/07/2024 ; glissante « latest » : 14/11/2026 | à trancher (section 7) | S22, S23, S25 |
| Copier | MIT | organisation copier-org, aucune entreprise citée | v9.19.1, 13/10/2026 | aucun | S26, S27 |
| Cookiecutter, cruft | BSD-3-Clause ; MIT | organisations cookiecutter et cruft | Cookiecutter 2.7.1, 04/03/2026 ; cruft 2.16.0, 25/12/2024 | cruft : aucune release depuis 12 mois | S30 à S33 |
| JHipster | Apache-2.0 | organisation jhipster, financement Open Collective | v9.4.0, 18/09/2026 ; blueprint .NET v4.5.0, 07/04/2025 | blueprint .NET : aucune release depuis 12 mois | S34, S35, S39 |
| Aspire | MIT | Microsoft (dépôt microsoft/aspire, failles signalées au MSRC) | 13.6.5, 10/11/2026 | aucun | S40 à S42 |
| Cloud Foundation Fabric, modules Google | Apache-2.0 | organisations GoogleCloudPlatform et terraform-google-modules ; support officiel non indiqué | Fabric v60.0.0, 05/11/2026 ; terraform-google-sql-db v28.3.1, 09/11/2026 | aucun | S45, S46, S49, S50 |
| Encore | MPL-2.0 pour le cadriciel ; plateforme gérée commerciale | organisation encoredev, éditeur unique | v1.58.9, 12/11/2026 | aucun pour le cadriciel | S51, S52 |
| Application Design Center | service propriétaire de Google Cloud | Google | disponibilité générale le 09/12/2025 | sans objet sur la cible cloud, inutilisable sur PC | S54 |

## 4. Les outils retenus

### 4.1 Backstage Software Templates

[BENCH] Le module de gabarits du portail Backstage charge un squelette, y injecte les variables saisies dans un formulaire et publie le résultat sur GitHub ou GitLab [S4]. Il recouvre l'entretien, sous forme de formulaire, et la génération. La page lue ne décrit aucune mise à jour d'un projet déjà créé : « Start Over » relance une nouvelle exécution [S4]. Un module d'action Cookiecutter existe [S5]. Backstage suppose un portail web à héberger, ce que le MVP exclut.

### 4.2 Score

[BENCH] Une spécification de charge de travail indépendante de la plateforme, en YAML validé par un JSON Schema (`score-v1b1.json`). Une dépendance s'y déclare par un type abstrait : `type: postgres` dans l'exemple officiel [S6]. score-compose produit un fichier Docker Compose, score-k8s des manifestes Kubernetes [S6]. Dans score-k8s, chaque type passe par un provisionneur ; celui de `postgres` crée une base sur une instance PostgreSQL partagée du cluster, et l'on peut écrire ses propres provisionneurs en gabarit Go (`template://`) ou en commande externe (`cmd://`) [S9]. Par la forme, c'est le plus proche des piliers 1 et 2. Score ignore la notion de projet (cible, région, budget, propriétaires du code), aucun provisionneur par défaut ne vise un service managé de GCP [S9], et le schéma en est encore à `score.dev/v1b1` [S6].

### 4.3 Radius

[BENCH] Une plateforme d'application qui sépare le contrat du développeur de sa réalisation. Un Resource Type, une base PostgreSQL par exemple, est réalisé par une Recipe en Terraform ou en Bicep, et chaque environnement fournit la sienne : la définition de l'application ne change pas, la base tourne dans Kubernetes en local et en service managé sur AWS ou Azure [S14]. C'est le modèle du principe II. Deux limites pour CELIAN. GCP n'apparaît ni dans le dépôt ni dans la page des concepts [S11, S14]. La traduction se fait à l'exécution, par le plan de contrôle Radius installé dans le cluster, sans dépôt généré.

### 4.4 Crossplane

[BENCH] Un cadriciel de plan de contrôle bâti sur Kubernetes [S19]. L'équipe plateforme définit une API abstraite (composite resource) et une Composition qui la réalise en ressources concrètes [S20]. Un fournisseur GCP est maintenu dans crossplane-contrib, v3.1.0 du 08/10/2026 [S21]. Crossplane recouvre les piliers 1 et 2 à l'exécution, sans entretien, sans génération de dépôt ni mise à jour de projet. Il ajouterait un composant à opérer dans chaque cluster, celui du PC compris.

### 4.5 Kratix

[BENCH] Le cadriciel de plateforme de Syntasso [S22]. Une Promise est un contrat entre la plateforme et les équipes : une API en libre-service, des workflows intégrés, la gestion d'une flotte de clusters [S24]. Kratix se place au même endroit que Crossplane, dans le cluster, avec un éditeur unique. Les versions numérotées s'arrêtent à v0.125.0 du 08/07/2024 ; depuis, l'installation rapide pointe vers une release glissante nommée « latest » [S23, S25].

### 4.6 Copier

[BENCH] Une bibliothèque et une CLI de rendu de gabarits de projet [S26]. Le questionnaire de `copier.yml` gère types, valeurs par défaut, validateurs et questions conditionnelles, et les réponses restent dans `.copier-answers.yml` [S28]. `copier update` régénère le projet depuis la nouvelle version du gabarit, calcule la différence et la réapplique ; les conflits s'écrivent en marqueurs dans le fichier ou dans des fichiers `.rej` [S29]. Les tâches lancent des commandes après génération ou mise à jour, les migrations seulement pendant une mise à jour [S28]. Copier couvre les piliers 3 et 5 en tant que moteur. Les tests des blueprints restent à écrire, et un questionnaire ne fait pas à lui seul une spec abstraite.

### 4.7 Cookiecutter et cruft

[BENCH] Cookiecutter génère, et la page de son dépôt ne parle pas de mise à jour [S30]. cruft ajoute un fichier `.cruft.json` (commit du gabarit et variables), `cruft update` pour appliquer les changements du gabarit et `cruft check` pour signaler en CI un projet en retard [S32]. Sa dernière release date du 25/12/2024 [S33] : le jour 2 de cette option repose sur un outil qui tombe sous le critère éliminatoire.

### 4.8 JHipster

[BENCH] Une plateforme de génération d'applications web et de microservices [S34]. Son langage JDL décrit dans un même fichier les applications, les déploiements, les entités et leurs relations [S36] ; les déploiements visent Docker Compose, Kubernetes ou OpenShift [S37]. La commande `upgrade` régénère le projet sur une branche dédiée, la fusionne et laisse les conflits à l'utilisateur [S38]. C'est l'outil le plus proche dans l'esprit : une spec, une génération, une mise à jour. Mais son socle natif est Java, et le blueprint .NET n'a publié aucune release depuis le 07/04/2025 [S39]. La page des déploiements ne cite aucun service managé de GCP, seulement une valeur `gke` pour l'ingress [S37].

### 4.9 Aspire et modèles `dotnet new`

[BENCH] Aspire décrit l'application dans un AppHost écrit en code, pour la composer, la déboguer et la déployer [S40]. `aspire publish` et `aspire deploy` visent Docker Compose, Kubernetes, AKS, Azure Container Apps et Azure App Service ; la page ne cite pas GCP [S43]. Le site donne des exemples de services managés Azure et AWS [S40]. Les modèles `dotnet new` génèrent projets et solutions à partir d'un `template.json`, et la documentation lue ne décrit aucune mise à jour d'un projet déjà créé [S44]. Aspire reste candidat de BENCH-005 pour la boucle de développement locale. Pour le déploiement sur GCP, il ne sert pas.

### 4.10 Cloud Foundation Fabric et modules Terraform de Google

[BENCH] Fabric fournit des blueprints de bout en bout et des modules Terraform pour Google Cloud, dont Cloud SQL, GKE et Cloud Run ; Memorystore, qu'il faudrait pour le cache, n'apparaît pas dans le README lu [S45]. Un fichier `default-versions.tofu` et le suffixe `-tofu` de ses métadonnées de fournisseur laissent penser qu'OpenTofu est visé, sans que le README le dise [S47]. La documentation Google présente Fabric comme des exemples avancés destinés au prototypage, à côté des modules de l'organisation terraform-google-modules [S48]. Le Cloud Foundation Toolkit se décrit comme « GCP best practices as code » [S49]. Ces modules recouvrent la couche GCP des blueprints, et rien d'autre.

### 4.11 Encore

[BENCH] Un cadriciel backend dans lequel les ressources (bases, Pub/Sub, caches, secrets) se déclarent dans le code [S51]. `encore run` démarre tout le système en local avec des équivalents : Postgres, Redis, NSQ [S51]. Le provisionnement automatique sur AWS et GCP passe par la plateforme gérée, commerciale ; en auto-hébergement, l'utilisateur fournit ses ressources dans un fichier de configuration [S51, S53]. Encore montre la parité locale et la traduction par cible appliquées à GCP, mais en TypeScript et en Go seulement [S51].

### 4.12 Application Design Center et Gemini Cloud Assist

[BENCH] Un service de Google Cloud, en disponibilité générale depuis le 09/12/2025 [S54]. Une équipe plateforme y publie un catalogue de gabarits adossés à Terraform. Un développeur décrit son besoin en langage naturel, Gemini propose une architecture, le gabarit s'exporte en Terraform vers un dépôt, et le service signale la dérive entre le design et ce qui est déployé [S54]. L'équipe plateforme peut pousser des mises à jour de gabarit que les développeurs appliquent [S55]. C'est l'outil qui touche le plus de piliers, chaque fois en partie. Les pages lues ne parlent que de Google Cloud, il n'a aucun équivalent local, et ses designs nomment des produits concrets plutôt que des besoins.

## 5. Pistes écartées

[BENCH] Yeoman, déjà option de BENCH-002, ne recouvre que la génération. Dernière release de `yo` : v7.0.1 le 09/04/2026 [S56]. Ce qu'il propose pour mettre à jour un projet n'a pas été vérifié ici et reste à instruire dans BENCH-002.

[BENCH] KubeVela, découvert pendant la recherche, est une plateforme de livraison d'applications fondée sur l'Open Application Model [S57], CNCF Incubating depuis le 27/02/2023 [S58], v1.11.1 le 06/11/2026 [S59]. Elle se place au même endroit que Radius et Crossplane, dans le cluster. Non retenue, pour rester sous douze outils.

[BENCH] Kusion (KusionStack) : dernière release v0.15.0 le 30/06/2025 [S60], plus de douze mois avant la lecture. Éliminé sans autre examen.

[BENCH] Les générateurs d'applications par IA généralistes ne recouvrent aucun pilier hormis l'écriture par un agent, sans validation. v0, pris en exemple, produit du code d'application et déploie sur l'infrastructure de Vercel ; sa documentation ne parle ni d'infrastructure en code, ni de Kubernetes, ni de choix du cloud [S61]. Le cas qui concerne CELIAN, une IA qui conçoit l'infrastructure, est traité avec Application Design Center.

## 6. Conclusion

### 6.1 Un outil couvre-t-il l'essentiel ?

[BENCH] Non. Aucun outil ne couvre plus de deux piliers, et aucun ne réunit spec abstraite, PC et GCP pour une stack .NET et React. Trois s'en approchent, chacun par un côté. Copier couvre la moitié déterministe (piliers 3 et 5) : on l'adopte, et c'est déjà l'option pressentie. JHipster a la forme la plus proche (spec JDL, génération, mise à jour par Git), mais il est Java d'abord et son blueprint .NET tombe sous le critère de release. Application Design Center touche cinq piliers sur six, mais il est propriétaire, limité à Google Cloud dans les pages lues et sans parité locale. Il sert une équipe plateforme installée sur GCP, pas le persona du PRD.

### 6.2 Ce qui distingue CELIAN

[BENCH] Aucune brique technique de CELIAN n'est neuve. La spec par types abstraits existe chez Score et Radius. La traduction par environnement existe dans les Recipes de Radius, les provisionneurs de Score et chez Encore. La mise à jour existe dans Copier, cruft et JHipster, la parité locale chez Score, Aspire et Encore.

[BENCH] Aucun outil lu ne propose un catalogue dont chaque entrée porte licence, gouvernance, statut et date, et qui fait échouer la CI quand l'une manque. Aucun n'applique la règle « open source sur PC, managé sur le cloud » à GCP pour une stack .NET et React : Radius traduit sans GCP, Encore traite le local et GCP mais en Go et TypeScript, avec une plateforme commerciale pour provisionner. Enfin, aucun ne cantonne un agent aux ADR et aux textes sous une boucle de validation. Ce dernier pilier est le plus neuf, donc le moins éprouvé.

[BENCH] La valeur de CELIAN tient donc dans l'assemblage et la curation : catalogue daté, blueprints testés, ADR. Le risque est réel. Une équipe outillée peut assembler elle-même Copier, Score et des modules Fabric. CELIAN n'a d'intérêt que s'il lui épargne ce travail et le tient à jour ensuite.

### 6.3 Ce qu'on peut réutiliser

[BENCH] Plutôt qu'écrire :

- Copier comme moteur, avec son questionnaire, son fichier de réponses, ses tâches pour lancer la validation et ses migrations pour le jour 2 [S28, S29] ;
- le modèle de Radius (Resource Type, Recipe, Environment) pour structurer `catalog/`, sans dépendre de Radius : une brique abstraite, une réalisation par cible [S14] ;
- les noms de types de Score (`postgres`, `redis`, `route`, `s3`) pour la spec, ce qui laisse ouverte la porte de score-compose et score-k8s [S9] ;
- les modules de Fabric ou de terraform-google-modules pour la couche GCP, à éprouver dans le golden repo de la phase 2 [S45, S50] ;
- le mécanisme de mise à jour de JHipster (branche dédiée, régénération, fusion Git) comme repli si `copier update` déçoit dans BENCH-002 [S38].

### 6.4 Options à ajouter ou à reconsidérer dans les BENCH

| Benchmark | Proposition | Raison |
| --- | --- | --- |
| BENCH-001, format de la spec | Ajouter Score `score.dev/v1b1` comme option, seul ou en section d'une spec projet maison | YAML et JSON Schema comme l'option pressentie, types abstraits déjà définis, projet CNCF. Ne couvre pas les champs de projet, schéma encore en bêta [S6, S7] |
| BENCH-002, moteur de templates | Mesurer le jour 2 de chaque option ; noter Cookiecutter avec cruft et appliquer à cruft le critère de release ; vérifier ce que Yeoman offre pour la mise à jour | US-011 dépend de ce parcours, et cruft n'a rien publié depuis le 25/12/2024 [S33] |
| BENCH-005, orchestration locale | Noter qu'Aspire ne liste pas GCP parmi ses cibles ; vérifier la maturité de ses sorties Kubernetes et Compose | Aspire ne servirait qu'à la boucle locale [S43] |
| Nouveau, à décider par le DSI | Modules OpenTofu pour GCP : écrits à la main, Cloud Foundation Fabric ou terraform-google-modules | Choix structurant absent de BENCH-001 à BENCH-007 ; prise en charge d'OpenTofu à vérifier [S47, S48] |

[BENCH] À ne pas ajouter aux options du MVP : Backstage, qui suppose un portail web, ni Crossplane, Kratix, Radius et KubeVela, qui traduisent à l'exécution dans un plan de contrôle à installer et à opérer sur le PC comme sur GCP. Radius reste la meilleure source d'inspiration pour la structure du catalogue.

### 6.5 Effets sur la vision et le PRD, signalés au DSI

[BENCH] Aucun de ces fichiers n'a été modifié. Points à arbitrer :

- PRD, section 8 : l'hypothèse « La différenciation n'a pas été confrontée aux outils existants » est levée, elle peut renvoyer vers ce document ;
- vision, « Ce qui le distingue » : le jour 2 (point 2) et la parité locale (point 3) existent ailleurs, et le jour 2 vient de Copier lui-même. Les distinctions propres sont le catalogue daté (point 4) et l'agent cantonné sous validation (point 1). Une reformulation en termes de combinaison serait plus juste ;
- registre des risques, deux candidats : Application Design Center avance sur le même besoin pour les équipes déjà sur GCP ; le jour 2 dépend d'un seul outil, Copier, porté par une organisation communautaire.

## 7. Limites

| Limite | Effet possible | Ce qui la lèverait |
| --- | --- | --- |
| Cases remplies d'après la documentation, sans essai | Une case « partiel » peut se révéler couverte ou absente | Essai court dans le benchmark concerné |
| Kratix publie une release glissante « latest » depuis la dernière version numérotée | Critère de release non tranché : récent si l'on compte « latest », éliminé sinon | Règle à fixer par [ARCHI] pour les releases glissantes, ou politique de version publiée par Syntasso |
| Prise en charge d'OpenTofu par Fabric déduite d'un nom de fichier | Fabric peut demander des adaptations | `tofu validate` sur un module dans le golden repo |
| Cibles d'Aspire lues sur une seule page | Une intégration GCP communautaire a pu échapper à la lecture | Lire le catalogue des intégrations d'Aspire |
| Application Design Center : tarif et limite à Google Cloud non écrits en clair | Le risque concurrentiel peut être surestimé ou sous-estimé | Page de tarifs et conditions du service |
| Années de release lues dans le flux Atom des pages GitHub quand la page ne les affichait pas | Aucun, si le flux est à jour | Sans objet |

## 8. Sources

[BENCH] Toutes lues le 15/11/2026. Les dates de release viennent de la page des releases GitHub ou de son flux Atom (`releases.atom`).

| ID | URL | Ce que la source établit |
| --- | --- | --- |
| S1 | <https://github.com/backstage/backstage> | Licence Apache-2.0, créé par Spotify, projet CNCF Incubation |
| S2 | <https://www.cncf.io/projects/backstage/> | Incubating depuis le 15/03/2022 |
| S3 | <https://github.com/backstage/backstage/releases> | v1.56.5 le 12/11/2026 |
| S4 | <https://backstage.io/docs/features/software-templates/> | Squelette, variables, publication ; « Start Over » relance une exécution |
| S5 | <https://backstage.io/docs/features/software-templates/builtin-actions> | Module d'action Cookiecutter |
| S6 | <https://github.com/score-spec/spec> | Apache-2.0, `type: postgres`, `score.dev/v1b1`, score-compose et score-k8s |
| S7 | <https://www.cncf.io/projects/score/> | CNCF Sandbox depuis le 08/07/2024 |
| S8 | <https://github.com/score-spec/spec/blob/main/MAINTAINERS.md> | Mainteneurs et employeurs |
| S9 | <https://docs.score.dev/docs/score-implementation/score-k8s/resources-provisioners/> | Provisionneurs par défaut, `template://` et `cmd://` |
| S10 | <https://github.com/score-spec/score-k8s/releases> | score-k8s 0.23.0 le 14/11/2026 |
| S11 | <https://github.com/radius-project/radius> | Apache-2.0, CNCF Sandbox, cibles locale, Azure et AWS |
| S12 | <https://www.cncf.io/projects/radius/> | CNCF Sandbox depuis le 16/04/2024 |
| S13 | <https://github.com/radius-project/radius/releases> | v0.62.0 le 27/10/2026 |
| S14 | <https://docs.radapp.io/concepts/> | Resource Types, Recipes, Environments ; AWS, Azure, Kubernetes local |
| S15 | <https://opensource.microsoft.com/blog/2023/10/18/enabling-developer-collaboration-with-radius/> | Lancement par l'équipe Azure Incubations le 18/10/2023 |
| S16 | <https://github.com/crossplane/crossplane> | Licence Apache-2.0 |
| S17 | <https://www.cncf.io/projects/crossplane/> | CNCF Graduated depuis le 28/10/2025 |
| S18 | <https://github.com/crossplane/crossplane/releases> | v2.4.3 le 22/10/2026 |
| S19 | <https://docs.crossplane.io/latest/whats-crossplane/> | Cadriciel de plan de contrôle bâti sur Kubernetes |
| S20 | <https://docs.crossplane.io/latest/composition/compositions/> | Composite resources et Compositions, documentation v2.4 |
| S21 | <https://github.com/crossplane-contrib/provider-upjet-gcp/releases> | Fournisseur GCP v3.1.0 le 08/10/2026 |
| S22 | <https://github.com/syntasso/kratix> | Apache-2.0, créé par Syntasso |
| S23 | <https://github.com/syntasso/kratix/tags> | v0.125.0 le 08/07/2024, « latest » le 14/11/2026 |
| S24 | <https://docs.kratix.io/> | Définition d'une Promise |
| S25 | <https://docs.kratix.io/main/quick-start> | Installation depuis la release « latest » |
| S26 | <https://github.com/copier-org/copier> | Licence MIT, organisation copier-org |
| S27 | <https://github.com/copier-org/copier/releases> | v9.19.1 le 13/10/2026 |
| S28 | <https://copier.readthedocs.io/en/stable/configuring/> | Questionnaire, `.copier-answers.yml`, tâches, migrations |
| S29 | <https://copier.readthedocs.io/en/stable/updating/> | Fonctionnement de `copier update` et des conflits |
| S30 | <https://github.com/cookiecutter/cookiecutter> | Licence BSD-3-Clause, aucune mise à jour mentionnée |
| S31 | <https://github.com/cookiecutter/cookiecutter/releases> | 2.7.1 le 04/03/2026 |
| S32 | <https://github.com/cruft/cruft> | MIT, `.cruft.json`, `cruft update`, `cruft check` |
| S33 | <https://github.com/cruft/cruft/releases> | 2.16.0 le 25/12/2024 |
| S34 | <https://github.com/jhipster/generator-jhipster> | Apache-2.0, financement Open Collective |
| S35 | <https://github.com/jhipster/generator-jhipster/releases> | v9.4.0 le 18/09/2026 |
| S36 | <https://www.jhipster.tech/jdl/intro> | Ce que décrit le JDL |
| S37 | <https://www.jhipster.tech/jdl/deployments> | Types de déploiement, ingress `gke` |
| S38 | <https://www.jhipster.tech/upgrading-an-application/> | Mise à jour par branche dédiée et fusion |
| S39 | <https://github.com/jhipster/jhipster-dotnetcore/releases> | Blueprint .NET v4.5.0 le 07/04/2025 |
| S40 | <https://aspire.dev/> | MIT, Microsoft, AppHost, exemples Azure et AWS |
| S41 | <https://github.com/microsoft/aspire> | Licence MIT, signalement des failles au MSRC |
| S42 | <https://github.com/microsoft/aspire/releases> | 13.6.5 le 10/11/2026 |
| S43 | <https://aspire.dev/deployment/deploy-with-aspire/> | Cibles de `aspire publish` et `aspire deploy`, GCP absent |
| S44 | <https://learn.microsoft.com/en-us/dotnet/core/tools/templates> | Modèles `dotnet new`, `template.json`, aucune mise à jour décrite |
| S45 | <https://github.com/GoogleCloudPlatform/cloud-foundation-fabric> | Apache-2.0, modules Cloud SQL, GKE, Cloud Run |
| S46 | <https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/releases> | v60.0.0 le 05/11/2026 |
| S47 | <https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/blob/master/default-versions.tofu> | Fichier de versions pour OpenTofu, sans mention explicite |
| S48 | <https://docs.cloud.google.com/docs/terraform/blueprints/terraform-blueprints> | Fabric présenté comme exemples avancés pour le prototypage ; modules terraform-google-modules |
| S49 | <https://github.com/GoogleCloudPlatform/cloud-foundation-toolkit> | Cloud Foundation Toolkit, Apache-2.0 |
| S50 | <https://github.com/terraform-google-modules/terraform-google-sql-db/releases> | v28.3.1 le 09/11/2026 |
| S51 | <https://github.com/encoredev/encore> | MPL-2.0, TypeScript et Go, équivalents locaux, plateforme commerciale |
| S52 | <https://github.com/encoredev/encore/releases> | v1.58.9 le 12/11/2026 |
| S53 | <https://encore.dev/docs/ts/self-host/configure-infra> | En auto-hébergement, ressources fournies par l'utilisateur |
| S54 | <https://cloud.google.com/blog/products/application-development/application-design-center-now-ga/> | Disponibilité générale le 09/12/2025, Gemini, export Terraform, dérive |
| S55 | <https://docs.cloud.google.com/application-design-center/docs/overview> | Espaces, gabarits, catalogues, mises à jour poussées par la plateforme |
| S56 | <https://github.com/yeoman/yo/releases> | `yo` v7.0.1 le 09/04/2026 |
| S57 | <https://kubevela.io/> | Livraison d'applications fondée sur l'Open Application Model |
| S58 | <https://www.cncf.io/projects/kubevela/> | CNCF Incubating depuis le 27/02/2023 |
| S59 | <https://github.com/kubevela/kubevela/releases> | v1.11.1 le 06/11/2026 |
| S60 | <https://github.com/KusionStack/kusion/releases> | v0.15.0 le 30/06/2025 |
| S61 | <https://v0.app/docs> | Code d'application déployé sur l'infrastructure de Vercel |
