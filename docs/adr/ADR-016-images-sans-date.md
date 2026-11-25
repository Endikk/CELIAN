# ADR-016. Les images de ghcr.io, quay.io et mcr.microsoft.com, que Renovate ne sait pas dater, attendent l'approbation de Lucas sur le tableau de bord, avec une dérogation datée au principe VI

| Champ | Valeur |
| --- | --- |
| Statut | accepté |
| Date | 2026-11-24 |
| Auteur | [ARCHI] |
| Décideur | Lucas : décision du 2026-11-24 sur la relecture [SECU] de la PR #46, puis réponses aux questions 1 à 4 le même jour ; acceptation par la fusion de la PR de cet ADR |
| BENCH lié | aucun : la décision règle un outil déjà en place, Renovate, et ses variantes se comparent sur sa documentation, sans mesure |
| Remplace | aucun |

## Contexte et problème

Le principe VI veut que les mises à jour automatiques attendent qu'une version soit publiée depuis au moins 7 jours, sauf celle qui corrige un avis de sécurité publié, à condition que sa PR passe toute la matrice. CELIAN confie cette règle à Renovate. Ses deux fichiers de configuration écrivent `minimumReleaseAge: "7 days"`, `vulnerabilityAlerts.minimumReleaseAge: null` et `osvVulnerabilityAlerts: true`. Celui du golden repo, `golden/saas-b2b/renovate.json`, écrit en plus `minimumReleaseAgeBehaviour: "timestamp-required"` et `internalChecksFilter: "strict"`, et S23 le contrôle (`golden/saas-b2b/policy/renovate_rules.rego`) : la politique refuse toute clé de délai ailleurs qu'en tête du fichier. Celui de CELIAN n'écrit ni l'une ni l'autre, et rien ne le contrôle (constat 4 de [SECU]). Depuis la décision du DSI du 2026-11-24 (research, RS-17), le Renovate de CELIAN couvre aussi `golden/` : les versions du golden repo montent par des PR de CELIAN, sous ses règles, et le fichier du golden repo sert au projet généré.

[ARCHI] a relu la documentation de Renovate le 2026-11-24, sans reprendre de confiance le résumé de [SECU]. Le site correspond à Renovate 44.261.0. Cinq faits en ressortent.

1. Pour la source `docker`, Renovate ne connaît la date de publication que sur Docker Hub, par le champ `tag_last_pushed`. Le tableau des registres de la page sur l'âge minimal marque non pris en charge les registres « (not Docker Hub) » (ticket 38656), ghcr.io (ticket 39064) et quay.io (ticket 38572). mcr.microsoft.com n'y a pas de ligne à lui : il tombe sous « (not Docker Hub) », et dans le fil du ticket 38656 un mainteneur montre que ce registre ne renvoie aucune date exploitable.
2. Depuis Renovate 42, une version sans date est traitée comme si elle n'avait pas encore passé le délai. `timestamp-required`, ajouté en 41.150.0, est la valeur par défaut. Les mises à jour de condensat de GHCR, de Quay ou d'ECR restent alors en attente, « held indefinitely ». Elles figurent parmi les « Pending Status Checks » du tableau de bord, à côté des mises à jour qui attendent normalement leurs 7 jours, et le tableau de bord permet de les forcer. Rien ne distingue celles qui viendront de celles qui ne viendront jamais.
3. Avec `timestamp-optional`, Renovate traite une version sans date comme stable, donc sans aucun délai, et affiche un avertissement sur le tableau de bord.
4. `dependencyDashboardApproval` se pose dans une entrée de `packageRules` : la mise à jour attend qu'une personne coche sa case dans le ticket du tableau de bord, et aucune PR ne s'ouvre avant. `config:recommended` active le tableau de bord depuis la version 26.
5. Aucune voie de sécurité ne couvre les images. `osvVulnerabilityAlerts` n'interroge OSV que pour dix sources, dont `docker` ne fait pas partie. `vulnerabilityAlerts` lit les alertes Dependabot de GitHub, et la base d'avis de GitHub ne compte aucun écosystème d'images parmi ses écosystèmes revus.

Les trois tickets sont ouverts le 2026-11-24. La PR 47353, qui ferait dater quay.io, est ouverte depuis le 2026-10-23 et attend une relecture. Aucun ticket propre à mcr.microsoft.com n'a été trouvé.

Cinq images, présentes ou prévues, viennent de ces registres :

| Image | Registre | Où | Ce qui la fixe |
| --- | --- | --- | --- |
| gitleaks v8.30.1 | ghcr.io | `.github/workflows/secrets.yml` de CELIAN et du golden repo | Scan de secrets en CI (principe IX) |
| zot 2.1.23 | ghcr.io | Lancée par `task up` du golden repo, tirée par le moteur du poste | [ADR-011](ADR-011-miroir-registres.md), condition 8 |
| Contrôleurs de Flux | ghcr.io | Profil standard sur `local` | [ADR-010](ADR-010-gitops.md), condition 6 ; tableau des registres de l'ADR-011 |
| Keycloak 26.8.2 | quay.io | Profil standard sur `local` | [ADR-013](ADR-013-fournisseur-identite.md), conditions 1 et 2 |
| Images de base de l'API .NET | mcr.microsoft.com | Dockerfile de l'API, étape 3 du plan ; l'image d'exécution de l'API part aussi sur GKE | BENCH-005, S41 ; tableau des registres de l'ADR-011 |

Sans règle, ces cinq images ne seraient jamais proposées, correctifs compris, et l'exception de sécurité du principe VI ne jouerait pas pour elles. Le risque reste latent pour l'instant : l'application Renovate n'est pas encore installée sur le dépôt, c'est une action de Lucas dans `ROADMAP.md`. Lucas a tranché le 2026-11-24, après la relecture [SECU] de la PR #46. Cet ADR écrit sa décision, et la dérogation qu'exige la section « Gouvernance » de la constitution.

## Options considérées

| Option | Score | Verdict | Raison principale |
| --- | --- | --- | --- |
| Approbation sur le tableau de bord pour les trois registres, délai automatique partout ailleurs | non noté | retenue, décision de Lucas du 2026-11-24 | Aucune mise à jour automatique n'échappe aux 7 jours ; l'exception de sécurité redevient possible ; une image nouvelle de ces registres tombe dans l'approbation, jamais dans l'absence de délai |
| Statu quo, `timestamp-required` partout | non noté | écartée | Tient la lettre du principe en bloquant tout, correctifs compris. Les images se figent sans signal propre, leurs mises à jour noyées parmi celles qui attendent leurs 7 jours. Le forçage depuis le tableau de bord existe, mais rien ne le cadre ni ne le contrôle |
| `timestamp-optional` seul sur les trois registres | non noté | éliminée | Une version sans date passe pour stable : PR immédiate, aucun délai, contraire au principe VI. C'est pourtant le contournement que proposent les fils des trois tickets |
| `minimumReleaseAge: null` sur les trois registres | non noté | éliminée | Retire le délai à ces images, au même effet que l'option précédente ; S23 refuse déjà toute clé de délai dans `packageRules` |
| Tirer de Docker Hub les images que l'amont y publie aussi | non noté | écartée comme règle, gardée au cas par cas | Docker Hub date les tags, donc Renovate compterait les 7 jours. Mais la copie n'existe pas pour toutes les images, et changer de registre touche les ADR-011 et ADR-013 |

Ce que [ARCHI] a relevé sur Docker Hub le 2026-11-24, par son API publique :

- gitleaks : `zricethezav/gitleaks:v8.30.1` porte le même condensat d'index que l'image de ghcr.io, `sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f`, poussé le 2026-03-21. Le README de gitleaks donne les deux noms ;
- Keycloak : `keycloak/keycloak:26.8.2` porte le condensat que fige l'ADR-013, `sha256:7e66a96e4739239070aeaf72e4c5decf0f7f682cfc725b9f7ea2b336eaba38b3`, poussé le 2026-11-19 à 07:42:21 UTC. Ce nom n'a pas été rapproché du workflow de publication de Keycloak ;
- Flux : le dépôt `fluxcd/source-controller` existe ; ses condensats n'ont pas été comparés à ceux de ghcr.io ;
- zot : `project-zot/zot` répond 404 ;
- .NET : rien cherché.

Pour Keycloak, la copie demanderait de réécrire la dérogation à ENF-03 de l'ADR-013, qui nomme `quay.io/keycloak/keycloak`, et de revoir la liste des amonts du miroir (condition 10 de l'ADR-011). Elle ajouterait aussi des tirages à Docker Hub, que R-25 surveille. D'où un examen image par image (question 3), et pas une règle.

## Décision

Le délai automatique reste partout où Renovate a une date. Pour les images des trois registres sans date, ghcr.io, quay.io et mcr.microsoft.com, une mise à jour devient une demande sur le tableau de bord de Renovate (Dependency Dashboard). Seul Lucas la coche, jamais un agent, après avoir lu la date de publication amont : une fois le condensat proposé publié depuis 7 jours, ou tout de suite pour le correctif d'un avis publié, selon l'exception du principe VI.

Le bloc, identique dans le `renovate.json` de CELIAN et dans `golden/saas-b2b/renovate.json`, description mise à part :

```json
  "minimumReleaseAge": "7 days",
  "minimumReleaseAgeBehaviour": "timestamp-required",
  "internalChecksFilter": "strict",
  "packageRules": [
    {
      "description": "Principle VI, ADR-016: these registries give Renovate no release date, so it cannot count the 7 days. Each update waits on the Dependency Dashboard: tick it once the upstream release is 7 days old, or at once for the fix of a published advisory.",
      "matchDatasources": ["docker"],
      "matchPackageNames": ["/^(ghcr\\.io|quay\\.io|mcr\\.microsoft\\.com)/.+$/"],
      "minimumReleaseAgeBehaviour": "timestamp-optional",
      "dependencyDashboardApproval": true
    }
  ]
```

Pourquoi il tient. `timestamp-optional` ne vaut que pour une version sans date (page des options). Sans date, la mise à jour passe le contrôle d'âge, et c'est l'approbation qui la retient. Le jour où Renovate saura dater l'un des registres, le délai de 7 jours reviendra de lui-même et l'approbation s'y ajoutera : le bloc échoue du côté fermé. Le filtre porte sur la source `docker`, celle du gestionnaire `dockerfile` comme des variables `_IMAGE` des workflows, et sur le nom du paquet, qui commence par l'hôte du registre dans les fichiers de CELIAN (`depName=ghcr.io/gitleaks/gitleaks`).

### Ce qui reste automatique

- Le délai de 7 jours, compté par Renovate, pour tout ce qu'il sait dater : les images de Docker Hub (Postgres, Valkey, Envoy Gateway, Mailpit, l'image de nœud de kind) et les autres sources que la page de l'âge minimal marque prises en charge.
- L'exception de sécurité par `vulnerabilityAlerts` et `osvVulnerabilityAlerts`, pour les sources qu'elles couvrent.
- Pour les trois registres, la détection : Renovate inscrit chaque mise à jour au tableau de bord, avec l'avertissement de `timestamp-optional`. Une fois la case cochée, la branche, la PR et la CI suivent sans autre geste.
- La fusion, qui ne change pas : aucun des deux fichiers ne pose `automerge`, dont la valeur par défaut est `false`.

### Qui coche, et comment il juge la date

Lucas seul. Un agent, le DSI compris, peut préparer la lecture : relever les dates et les avis, les écrire dans un commentaire de PR ou dans son rapport. Il ne coche jamais une case et ne modifie jamais le ticket du tableau de bord.

La date qui compte est celle de la publication du condensat proposé, pas celle de la version. Un tag republié porte un condensat neuf, et c'est ce condensat qui entrerait dans le dépôt : Keycloak 26.8.2 en compte trois entre le 2026-11-09 et le 2026-11-19. Renovate raisonne de même sur Docker Hub, où un tag repoussé relance le délai.

Où la lire, d'après ce que [ARCHI] a relevé le 2026-11-24, sans jeton :

| Registre | Source | Ce qu'elle donne |
| --- | --- | --- |
| quay.io | API du registre : `https://quay.io/api/v1/repository/<dépôt>/tag/?specificTag=<tag>&onlyActiveTags=false` | Pour chaque condensat d'un tag, `start_ts` et `last_modified`. Exemple : le condensat `7e66a96e` de `keycloak/keycloak:26.8.2` est en place depuis le 2026-11-19 à 07:42:01 UTC |
| mcr.microsoft.com | API de catalogue du registre : `https://mcr.microsoft.com/api/v1/catalog/<dépôt>/tags?reg=mar` | Pour chaque tag, `digest`, `createdDate` et `lastModifiedDate`. Aucune page de documentation de cette API n'a été lue |
| ghcr.io | Page GitHub Packages de l'image, et page des releases du projet | Pour chaque version, son condensat et une date relative (« Published 8 months ago » pour gitleaks v8.30.1) ; la date de la version sur la page des releases |

Jamais le champ `created` de la configuration de l'image : c'est celui qui construit l'image qui le fixe, comme le relève la discussion du ticket 39064. Une date qui ne se lit pas, ou pas au jour près quand l'écart frôle les 7 jours, vaut refus : Lucas attend.

L'exception de sécurité. Si le condensat ou la version corrige un avis publié, CVE ou avis du projet, Lucas coche sans attendre. C'est le cas fréquent d'une image republiée sur une base corrigée, chez Keycloak comme chez .NET. Sans avis à citer, les 7 jours s'appliquent. La PR passe toute la matrice, comme le veut le principe VI.

### Conditions

La décision ne vaut qu'avec elles. Les conditions 1 et 2 reprennent les contrôles proposés par [SECU] ; les conditions 3 à 7 sont des ajouts de [ARCHI].

1. Bloc contrôlé dans le golden repo. S23 exige une entrée identique au bloc, description mise à part, et n'accepte `timestamp-optional` et `dependencyDashboardApproval` que dans cette entrée. `dependencyDashboardApproval` est refusé partout ailleurs : autre entrée, tête du fichier, gestionnaire, type de mise à jour, `vulnerabilityAlerts`, groupe, tous lus par Renovate (`lib/config/options/scopes.ts`, 44.247.1). Tests : une entrée sans approbation, une entrée qui ajoute docker.io, une entrée avec un critère de plus, une seconde entrée qui pose l'approbation, l'entrée conforme. Porteur : [DEV]. L'exigence de présence et le refus hors de `packageRules` vont plus loin que la proposition de [SECU] : sans l'entrée, le fichier retombe dans le statu quo écarté plus haut (arbitrage du DSI du 2026-11-24).
2. Le même contrôle pour CELIAN. Le `renovate.json` de CELIAN reçoit le bloc et les deux clés de tête qu'il n'écrivait pas. La partie « délai » de S23 s'applique aux deux fichiers, par un paquet commun ou une politique jumelle, lancée par un hook ou un job de la CI de CELIAN ; [DEV] choisit.
3. Avant l'application Renovate. Les conditions 1 et 2 sont fusionnées avant que Lucas installe l'application sur le dépôt. Sans elles, les cinq images se figent dès le premier passage. Deux préalables de plus, ajoutés par la relecture [SECU] de la PR de cet ADR : l'ancien jeton classique est révoqué et la bascule vers le jeton à grain fin terminée (R-07) ; Lucas essaie lui-même le jeton des agents sur un ticket de test, par un `PATCH` REST et par la mutation GraphQL `updateIssue`, et obtient un refus 403 aux deux. Sans ce refus, « Lucas seul » ne tient que par un filtre de motifs, et écrire dans le ticket du tableau de bord suffit à forcer une mise à jour avant ses 7 jours, pour toutes les dépendances : la condition de révision sur la barrière technique s'applique.
4. Trois registres, pas un de plus. Un registre de plus élargit la dérogation et passe par un ADR. Le contrôle de la condition 10 de l'ADR-011 vérifie que chaque hôte de registre, mis en minuscules, est docker.io ou l'un des trois, et le même contrôle lit les `depName` des variables `_IMAGE` des workflows. Un hôte inconnu fait échouer le contrôle, puisque Renovate ne daterait pas ses images. Premier cas à relever : les images de la forme libre de Config Sync, que le test de la condition 5 de l'ADR-010 fait tourner sur kind, et dont cet ADR n'a pas lu le registre.
5. Lucas seul, vérifié. [SECU] vérifie que le jeton des agents ne peut pas modifier le ticket du tableau de bord. La page des permissions de GitHub range la modification d'un ticket (`PATCH /repos/{owner}/{repo}/issues/{issue_number}`) en écriture sous « Issues » et sous « Pull requests », avec la marque des permissions multiples. Le jeton que décrit `docs/securite/jeton-github.md` n'a pas « Issues », mais il a « Pull requests » en écriture, et que cette seule permission suffise n'est pas vérifié. L'ancien jeton classique reste par ailleurs à révoquer (`ROADMAP.md`, R-07). Le DSI pose dans `.claude/settings.json`, dans la PR de cet ADR, des règles `deny` sur les formes courantes de `gh issue edit`, des appels `gh api` en `PATCH` et des mutations GraphQL. C'est un filtre de motifs qui ne remplace pas le jeton (`CLAUDE.md`, « Garde-fous ») : un appel en POST ou par `curl` avec le jeton exporté y échappe, et ne se filtre pas sans bloquer des lectures.
6. Trace. Chaque PR de Renovate sur ces registres porte en commentaire la date lue et sa source, ou l'avis corrigé. Un agent peut l'écrire ; Lucas la relit avant de fusionner. [SECU] relit ces traces à sa lecture mensuelle des avis.
7. Projet généré. `golden/saas-b2b/renovate.json` porte le même bloc. Dans le projet généré, c'est une personne qui maintient le projet qui coche, jamais un agent, et le README dit comment lire la date pour chaque registre (question 1).

### Portée

La décision vaut pour les mises à jour de Renovate dans CELIAN, golden repo compris, et dans le projet généré. Elle ne touche ni la spec, ni le catalogue, ni les couches de cible : elle nomme des registres, pas des services (principe II).

Restent hors de cette décision :

- les listes fermées de Kyverno (ENF-03, dérogations des ADR-012 à ADR-014) ;
- le scan des images (FR-021, RS-22) ;
- la base de vulnérabilités de Trivy, téléchargée à chaque exécution sans passer par Renovate (RS-22) ;
- le choix du premier condensat d'une image, qui se fait dans la PR qui la fait entrer, sous la même règle de date (section suivante pour l'étape 3).

## Conséquences

### Positives

- Aucune mise à jour automatique n'échappe aux 7 jours, dans CELIAN comme dans le projet généré.
- L'exception de sécurité redevient possible pour les cinq images : une case cochée suffit, là où le statu quo bloquait le correctif comme le reste.
- Une image nouvelle de ces registres tombe dans l'approbation par le filtre, jamais dans l'absence de délai.
- Ces mises à jour attendent une case, au lieu de rester sans fin parmi les mises à jour qui attendent leurs 7 jours.
- Le bloc échoue du côté fermé quand Renovate apprend à dater un registre, et la levée se fait registre par registre, en retirant un hôte du filtre.
- Le `renovate.json` de CELIAN, que rien ne contrôle aujourd'hui, reçoit un contrôle.

### Négatives

- R-38, ouvert au registre le 2026-11-24 : la mise à jour des images sans date dépend d'une personne. Une absence retarde un correctif, une date mal lue fait entrer une version de moins de 7 jours. L'image la plus exposée est l'image d'exécution de l'API, bâtie sur une base de mcr.microsoft.com, la seule des cinq qui part sur GKE.
- Charge pour Lucas, non mesurée. Chaque condensat neuf demande une case : Keycloak republie ses tags (trois condensats en dix jours pour 26.8.2), mcr.microsoft.com modifie des tags après leur création (`10.0-alpine3.24-amd64` de `dotnet/sdk`, créé le 2026-07-01, modifié le 2026-11-10), et zot a publié treize releases en douze mois (ADR-011).
- Aucune alerte automatique pour ces images. Un correctif ne se voit que par la lecture des avis de [SECU] ou par le scan des images (FR-021), qui ne voit que ce qu'il sait associer à un paquet (R-36).
- « Lucas seul » ne tient aujourd'hui que par la règle. Le jeton des agents n'est pas vérifié (condition 5), et le ruleset de `main` demande zéro approbation (`required_approving_review_count: 0`) : rien ne réserve techniquement la fusion à Lucas.
- S23 se complique, et CELIAN reçoit un contrôle de plus à tenir.
- Le filtre contient une barre oblique entre ses délimiteurs. La page des motifs de Renovate ne dit pas si elle doit s'échapper. Vérifié par [DEV] le 2026-11-24 dans le code de Renovate 44.247.1, par lecture et sans essai : Renovate ne retire que la barre de tête et celle de fin, et la barre interne reste un caractère ordinaire du motif (`lib/util/string-match.ts`, lignes 73 à 92).
- La règle n'est vérifiée qu'à la lecture de la documentation : aucun Renovate n'a encore tourné avec elle.

### Effet sur les cibles hors MVP

La porte reste ouverte. La règle nomme des registres, pas une cible. La page de Renovate cite aussi ECR parmi les registres qu'il ne sait pas dater : une cible AWS qui tirerait des images d'ECR étendrait le filtre par son propre ADR.

### Ce que l'ADR change ailleurs

La PR de cet ADR modifie les deux `renovate.json`, S23 et ses tests, le contrôle de CELIAN ([DEV]), ainsi que `CLAUDE.md`, le registre des risques et `.claude/settings.json` (DSI). Les autres changements passent chacun par leur PR, chez leur porteur.

- Les deux `renovate.json`, S23 et ses tests, le contrôle de CELIAN : [DEV], dans la PR de cet ADR.
- ADR-011, condition 8. Il n'est pas remplacé. L'image de zot y est « suivie par Renovate, avec le délai de 7 jours et l'exception de sécurité » : sur ghcr.io, le délai se compte désormais par la lecture de Lucas, sous cet ADR. Renovate doit aussi trouver le condensat de zot dans le Taskfile ; la tâche qui l'écrit lui en donne le moyen, comme le rappelle l'en-tête de S23.
- ADR-013, conditions 1 et 2. Il n'est pas remplacé. La vérification que la condition 2 confiait à [OPS], comment `minimumReleaseAge` date une montée de condensat, a sa réponse : sur quay.io, il ne la date pas, et sans cet ADR la montée attendrait sans fin. La liste fermée de la condition 1 change dans la PR que la case cochée fait ouvrir. Le paragraphe « Registre et miroir » laissait ouverte l'identité du condensat sur Docker Hub : elle est relevée pour 26.8.2 (section « Options considérées »).
- ADR-010. Les images de Flux sur ghcr.io passent sous approbation ; sa condition 6, images par condensat, ne change pas.
- Étape 3 du golden repo, images .NET. Les motifs par défaut du gestionnaire `dockerfile` font entrer les Dockerfile du golden repo dans le Renovate de CELIAN. Le DSI les y garde (décision du 2026-11-24, research, RS-17, point 2, écrite par la PR de l'étape 3) : leurs images montent par des PR de CELIAN, comme les workflows et les hooks du golden repo. Elles tombent sous le bloc, présent dans les deux fichiers. La PR de l'étape 3 choisit des condensats dont la date, lue dans l'API de catalogue de mcr.microsoft.com, a au moins 7 jours, ou qui corrigent un avis publié, et écrit la date et sa source dans sa description. Chaque `FROM` porte le tag et le condensat (FR-008).
- `CLAUDE.md`, sections « Conventions » et « Garde-fous », par le DSI dans la PR de cet ADR : la phrase sur Renovate et les 7 jours renvoie à cet ADR pour les trois registres ; les règles `deny` de la condition 5 y sont citées.
- Registre des risques, par le DSI dans la PR de cet ADR : R-38 ; la mitigation de R-34 qui dit l'image de zot « suivie par Renovate avec l'exception de sécurité » renvoie à cet ADR.
- README du projet généré, pour [DOC] : la case à cocher, qui la coche, comment lire la date.

### Suites

- [DEV] : les conditions 1 et 2, l'essai du filtre, la PR de l'étape 3 sous ces règles.
- [SECU] : la condition 5 ; la relecture des traces (condition 6) ; la lecture mensuelle des avis de gitleaks, de Flux et des images .NET, en plus de ceux de zot et de Keycloak déjà suivis (R-34, R-36).
- [OPS], avec [SECU] : la copie de Docker Hub au cas par cas (question 3).
- [DOC] : le README du projet généré.
- DSI : R-38 au registre, les règles `deny` de la condition 5 et la phrase de `CLAUDE.md`, faits dans la PR de cet ADR ; l'état des trois tickets à chaque relecture de la dérogation.
- Lucas : installer l'application Renovate une fois les conditions 1 et 2 fusionnées.

### Questions tranchées

Lucas a répondu le 2026-11-24 aux quatre questions qui lui revenaient. Il a suivi l'avis d'[ARCHI] sur chacune.

1. Qui coche dans le projet généré. Le même bloc, coché par une personne qui maintient le projet, jamais un agent. Le README du projet généré explique la lecture de la date registre par registre.
2. Date de relecture de la dérogation. Au plus tard le 2027-02-24, et à la fermeture de chacun des trois tickets : la PR 47353 est ouverte, et une levée partielle pour quay.io peut venir avant.
3. Docker Hub pour gitleaks. À essayer dans une PR à part, après vérification des condensats et du workflow de publication par [OPS] et [SECU]. Le condensat est le même sur les deux registres, et l'image ne sert qu'en CI sans passer par le miroir : la tirer de `zricethezav/gitleaks` la sortirait de l'approbation et rendrait les 7 jours à Renovate. Keycloak attend l'étape 15, parce que le changement réécrit la dérogation de l'ADR-013.

   Essayé le 2026-11-25 par [OPS], dans la PR #59. Condensat : les index de `docker.io/zricethezav/gitleaks:v8.30.1` et de `ghcr.io/gitleaks/gitleaks:v8.30.1` sont identiques octet pour octet, `sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f`, et listent les mêmes quatre manifestes : linux/amd64, linux/arm64 et leurs deux attestations. Publication : au tag v8.30.1, un seul job du workflow `release.yml` de gitleaks pousse les deux noms, après une connexion à Docker Hub sous le compte qui publie la release. L'exécution 23369935991, lancée le 2026-03-21 par la release de `zricethezav`, auteur de 671 des commits du dépôt, s'est terminée à 02:24:46 UTC ; Docker Hub date le tag de 02:24:33 UTC, avec `zricethezav` pour dernier auteur. Le workflow de `master` pousse toujours les deux registres. Limite : la page des limites de GitHub Actions écrit que la limite de tirage de Docker Hub ne s'applique pas aux runners hébergés par GitHub qui tirent une image publique ; un runner auto-hébergé la subit. Renovate ramène le préfixe `docker.io/` à `https://index.docker.io` et lit alors `tag_last_pushed` (code identique en 44.247.1 et 44.261.0, lu sans essai) : gitleaks sort de l'approbation, et Renovate compte ses 7 jours. La relecture [SECU] de la PR #59 a relevé que Docker Hub reçoit ses images par un mot de passe personnel, sans signature : une image poussée sur Docker Hub seul passerait la CI. Décision de Lucas du 2026-11-25 : le commentaire `# renovate:` des deux `secrets.yml` nomme `docker.io/zricethezav/gitleaks`, pour la date, et l'image se tire de `ghcr.io/gitleaks/gitleaks` par le même condensat ; un condensat absent de ghcr.io fait échouer le tirage. Exception de sécurité : Renovate ne connaît aucun avis pour les images (fait 5), donc un correctif de gitleaks attend ses 7 jours, sauf si Lucas seul le force depuis les mises à jour en attente du tableau de bord, sur alerte de [SECU].
4. Rythme de lecture du tableau de bord. Une fois par semaine, et sur alerte de [SECU] pour un avis publié.

### Question ouverte

Question 5. Une source de dates propre au projet, pour [DEV] après le golden repo. quay.io et mcr.microsoft.com donnent une date par condensat dans leurs API. Que Renovate accepte une source maison qui porte cette date n'a pas été vérifié. Si c'est le cas, la dérogation pourrait se lever pour ces deux registres sans attendre les tickets.

## Conformité à la constitution

Vérifiée contre la [constitution](../../.specify/memory/constitution.md) en version 1.2.0.

| Principe | Effet | Justification |
| --- | --- | --- |
| I. Rien sans test automatique | respecté | S23 et son pendant pour CELIAN refusent tout écart au bloc, avec leurs tests ; le contrôle des hôtes refuse un registre de plus (conditions 1, 2 et 4) |
| II. Spec abstraite, catalogue concret | sans objet | La règle nomme des registres dans les fichiers de Renovate ; ni la spec, ni le catalogue, ni une couche de cible ne changent |
| III. Managé sur le cloud, open source ailleurs | sans objet | Aucune brique n'entre ni ne sort |
| IV. Catalogue traçable | sans objet | Les condensats restent hors du catalogue (ADR-009) |
| V. Gouvernance ouverte d'abord | sans objet | Aucune techno nouvelle |
| VI. Récent mais éprouvé | dérogation | Pour les trois registres, Lucas compte les 7 jours à la place de Renovate (section « Dérogations ») ; ailleurs, Renovate les compte toujours |
| VII. Une commande pour démarrer | sans objet | `task up` ne change pas |
| VIII. Aucun fait de mémoire | respecté | Les faits renvoient aux pages lues le 2026-11-24. Sont signalés comme non vérifiés : la documentation de l'API de catalogue de mcr.microsoft.com, la suffisance de « Pull requests » pour modifier un ticket, le nom de Keycloak sur Docker Hub face à son workflow, les condensats de Flux sur Docker Hub, le registre des images de Config Sync du test de l'ADR-010, une source de dates maison |
| IX. Aucun secret dans le dépôt | respecté | La décision n'ajoute aucun identifiant ; les dates se lisent sur des API publiques, sans jeton |
| X. Aucune dépense cloud sans accord | sans objet | Rien ne touche au cloud |

### Dérogations

Une dérogation au principe VI, décidée par Lucas le 2026-11-24. La lettre du principe tient, puisque ces mises à jour cessent d'être automatiques. La garantie, elle, passe d'une machine à une personne, et c'est cet écart que la section « Gouvernance » demande de justifier, avec sa durée et la condition qui le lèvera.

| Principe | Écart | Justification | Durée | Condition de levée |
| --- | --- | --- | --- | --- |
| VI. Récent mais éprouvé | Pour les images de ghcr.io, quay.io et mcr.microsoft.com, Renovate ne compte pas les 7 jours. Lucas les compte, sur la date amont du condensat, avant de cocher la mise à jour sur le tableau de bord | Renovate ne date pas ces registres (page de l'âge minimal). Le statu quo bloque tout, correctifs compris ; les deux variantes sans approbation suppriment le délai. Contrôles : S23 et son pendant, liste fermée des trois registres, Lucas seul, trace dans chaque PR (conditions 1 à 6) | Depuis le 2026-11-24, jusqu'à sa levée. Relecture au plus tard le 2027-02-24 (question 2), et à la fermeture de chacun des tickets 38656, 39064 et 38572 | Registre par registre : la page de l'âge minimal de Renovate marque le registre pris en charge. L'hôte sort alors du filtre, et Renovate compte de nouveau les 7 jours. mcr.microsoft.com n'a pas de ticket propre ; 38656, qui daterait un condensat par les API du registre, est le plus proche. Le bloc disparaît avec le dernier hôte, et S23 refuse de nouveau `timestamp-optional` |

Portée. Les trois hôtes, pour la source `docker`. Un autre registre sans date n'entre que par un ADR (condition 4).

Suivi. Le DSI suit la levée au registre des risques, sous R-38.

## Condition de révision

La décision se rouvre dans ces cas :

- Renovate change le sens de `timestamp-optional` ou de `dependencyDashboardApproval`, vu à la relecture de la page des options à chaque relecture de la dérogation ;
- [SECU] montre qu'un agent peut cocher et qu'aucune barrière technique ne tient (condition 5) : la décision se rouvre vers une barrière technique ;
- une mise à jour de ces registres attend plus de 30 jours sur le tableau de bord, seuil proposé par [ARCHI] : la décision se rouvre vers la copie de Docker Hub ou une source de dates maison (questions 3 et 5) ;
- un registre sans date de plus entre dans la stack (condition 4) ;
- Lucas revient sur sa réponse à la question 1, pour le projet généré.

La levée, registre par registre, ne rouvre pas la décision : la PR qui retire un hôte du filtre l'indique ici par un lien. Sans l'un de ces faits, relecture au plus tard le 2027-02-24.

## Sources

| Source | Lue le | Ce qu'elle établit |
| --- | --- | --- |
| <https://docs.renovatebot.com/key-concepts/minimum-release-age/> | 2026-11-24 | Site à Renovate 44.261.0 ; date de la source `docker` sur Docker Hub seul (`tag_last_pushed`) ; tableau des registres : « (not Docker Hub) », ghcr.io et quay.io non pris en charge, tickets 38656, 39064 et 38572 ; GHCR, Quay et ECR « cannot be aged », condensats « held indefinitely » sous `timestamp-required` ; changement de Renovate 42, `timestamp-required` ajouté en 41.150.0 ; « Pending Status Checks » ; forçage depuis le tableau de bord sous `internalChecksFilter=strict` ; avertissement de `timestamp-optional` affiché sur le tableau de bord ; tag repoussé sur Docker Hub qui relance le délai ; mises à jour de sécurité qui passent outre le délai |
| <https://docs.renovatebot.com/configuration-options/> | 2026-11-24 | `minimumReleaseAgeBehaviour` : défaut `timestamp-required`, valeurs, `timestamp-optional` qui traite une version sans date comme stable, portée `packageRule` ; `internalChecksFilter` : défaut `strict` ; `dependencyDashboardApproval` : portées dont `packageRule`, approbation par la case du ticket ; `dependencyDashboard` activé par `config:recommended` depuis la version 26 ; `osvVulnerabilityAlerts` : dix sources, sans `docker` ; `vulnerabilityAlerts` : GitHub seul, alertes Dependabot, `minimumReleaseAge` à `null` par défaut ; `automerge` à `false` par défaut ; `matchPackageNames` |
| <https://docs.renovatebot.com/key-concepts/dashboard/> | 2026-11-24 | `dependencyDashboardApproval` dans une entrée de `packageRules` ; rien sur qui peut cocher |
| <https://docs.renovatebot.com/modules/datasource/docker/> | 2026-11-24 | Date sur Docker Hub seul ; condensat daté comme `tag_last_pushed` |
| <https://docs.renovatebot.com/modules/manager/dockerfile/> | 2026-11-24 | Le gestionnaire `dockerfile` produit la source `docker` ; ses motifs par défaut trouvent un Dockerfile dans tout dossier |
| <https://docs.renovatebot.com/string-pattern-matching/> | 2026-11-24 | Motif entre `/` ; casse respectée par défaut ; rien sur une barre oblique interne |
| <https://github.com/renovatebot/renovate/blob/44.247.1/lib/util/string-match.ts> | 2026-11-24 | Lu par [DEV]. `configValStart` (`/^!?\//`) et `configValEnd` (`/\/i?$/`), lignes 73 et 74 ; `parseRegexMatch` ne retire que ces deux barres avant de construire l'expression, lignes 82 à 92. Fichier identique aux tags 44.261.0 et 44.261.1. `matchPackageNames` passe par `matchRegexOrGlobList` (`lib/util/package-rules/package-names.ts`, ligne 21) |
| <https://github.com/renovatebot/renovate/issues/38656> | 2026-11-24 | Ouvert depuis le 2025-10-16 ; date d'un condensat par les API du registre ; mcr.microsoft.com sans date exploitable ; Renovate garde l'échec fermé ; contournement par `timestamp-optional` limité à un registre |
| <https://github.com/renovatebot/renovate/issues/39064> | 2026-11-24 | Ouvert depuis le 2025-11-04 ; date pour ghcr.io par l'API des paquets de GitHub, qui demande un jeton ; date d'image fixée par qui la construit |
| <https://github.com/renovatebot/renovate/issues/38572> | 2026-11-24 | Ouvert depuis le 2025-10-13 ; l'API de Quay renvoie la date de poussée d'un tag ; lié à la PR 47353 |
| <https://github.com/renovatebot/renovate/pull/47353> | 2026-11-24 | Ouverte le 2026-10-23, quay.io seul, relecture attendue |
| <https://docs.github.com/en/code-security/security-advisories/working-with-global-security-advisories-from-the-github-advisory-database/about-the-github-advisory-database> | 2026-11-24 | Écosystèmes des avis revus : Composer, Erlang, Go, GitHub Actions, Maven, npm, NuGet, pip, Pub, RubyGems, Rust, Swift ; aucun écosystème d'images |
| <https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens> | 2026-11-24 | `PATCH /repos/{owner}/{repo}/issues/{issue_number}` en écriture sous « Issues » et sous « Pull requests », avec la marque des permissions multiples |
| <https://docs.github.com/en/rest/issues/issues#update-an-issue> | 2026-11-24 | « Issue owners and users with push access or Triage role can edit an issue » |
| <https://quay.io/api/v1/repository/keycloak/keycloak/tag/?specificTag=26.8.2&onlyActiveTags=false> | 2026-11-24 | Champs `start_ts`, `end_ts`, `last_modified`, `manifest_digest` ; trois condensats pour 26.8.2, du 2026-11-09, du 2026-11-12 et du 2026-11-19, le dernier égal à celui de l'ADR-013 |
| <https://mcr.microsoft.com/api/v1/catalog/dotnet/sdk/tags?reg=mar> | 2026-11-24 | Champs `name`, `digest`, `createdDate`, `lastModifiedDate` par tag ; `10.0-alpine3.24-amd64` créé le 2026-07-01, modifié le 2026-11-10 |
| <https://github.com/gitleaks/gitleaks/pkgs/container/gitleaks> | 2026-11-24 | « Published 8 months ago » et condensat `c00b6bd0` pour v8.30.1 ; dates relatives seulement |
| <https://github.com/gitleaks/gitleaks/blob/master/README.md> | 2026-11-24 | Images `zricethezav/gitleaks` sur Docker Hub et `ghcr.io/gitleaks/gitleaks` |
| <https://hub.docker.com/v2/repositories/zricethezav/gitleaks/tags/v8.30.1> | 2026-11-24 | Condensat d'index `c00b6bd0`, égal à celui de ghcr.io ; `tag_last_pushed` 2026-03-21T02:24:33Z |
| `docker buildx imagetools inspect` et `--raw`, buildx 0.37.2, sur `docker.io/zricethezav/gitleaks:v8.30.1` et `ghcr.io/gitleaks/gitleaks:v8.30.1` | 2026-11-25 | Lu par [OPS]. Index OCI identiques octet pour octet, SHA-256 `c00b6bd0` ; manifestes `b109bc5f` (linux/amd64), `6b2d5224` (linux/arm64), `e4037a31` et `8af0bd93` (attestations) sur les deux registres (question 3) |
| <https://hub.docker.com/v2/repositories/zricethezav/gitleaks/tags/v8.30.1> | 2026-11-25 | Relu par [OPS]. Même condensat ; `last_updater_username` `zricethezav` ; manifestes poussés entre 02:24:32 et 02:24:33 UTC le 2026-03-21 |
| <https://github.com/gitleaks/gitleaks/blob/v8.30.1/.github/workflows/release.yml> ; même fichier sur `master` | 2026-11-25 | Lu par [OPS]. Sur `release: published`, un job `build-and-push-image` se connecte à Docker Hub avec `github.actor` et le secret `DOCKER_PASSWORD`, puis à ghcr.io, et pousse `zricethezav/gitleaks` et `ghcr.io/gitleaks/gitleaks` en linux/amd64 et linux/arm64 dans la même étape. `master` garde les deux registres |
| <https://github.com/gitleaks/gitleaks/actions/runs/23369935991> ; API des releases et des contributeurs du dépôt | 2026-11-25 | Lu par [OPS]. Événement `release`, commit `83d9cd68` du tag v8.30.1, lancé par `zricethezav`, job de 02:18:01 à 02:24:46 UTC, succès ; release publiée à 02:17:58 UTC par `zricethezav` (Zachary Rice), premier contributeur du dépôt avec 671 commits |
| <https://docs.github.com/en/actions/reference/limits>, « Docker Hub's rate limit for GitHub Actions » | 2026-11-25 | Lu par [OPS]. Runner hébergé par GitHub, image publique : limite non appliquée ; image privée ou runner auto-hébergé : limite appliquée |
| <https://docs.docker.com/docker-hub/usage/pulls/> | 2026-11-25 | Lu par [OPS]. Tirage anonyme : 100 par adresse IPv4 ou sous-réseau IPv6 /64 sur 6 heures ; un GET de manifest compte, un HEAD non ; une image multi-architecture compte un tirage pour chaque architecture différente |
| <https://github.com/renovatebot/renovate/blob/44.261.0/lib/modules/datasource/docker/common.ts>, lignes 340 à 363 ; `index.ts`, lignes 1243 à 1273 | 2026-11-25 | Lu par [OPS], sans essai. Un nom qui commence par `docker.io/` donne l'hôte `https://index.docker.io`, celui de Docker Hub ; pour cet hôte, Renovate lit les tags dans l'API de Docker Hub, avec `tag_last_pushed` |
| <https://hub.docker.com/v2/repositories/keycloak/keycloak/tags/26.8.2> | 2026-11-24 | Condensat d'index `7e66a96e`, égal à celui de quay.io ; `tag_last_pushed` 2026-11-19T07:42:21Z |
| <https://hub.docker.com/v2/repositories/fluxcd/source-controller/tags/?page_size=3> | 2026-11-24 | Le dépôt existe sur Docker Hub |
| <https://hub.docker.com/v2/repositories/project-zot/zot/tags/?page_size=5> | 2026-11-24 | Réponse 404 |
| `renovate.json`, `golden/saas-b2b/renovate.json`, `golden/saas-b2b/policy/renovate_rules.rego`, `main` à `b31363c` | 2026-11-24 | Clés de délai écrites ou absentes ; S23 refuse toute clé de délai hors de la tête et tout `extends` imbriqué ; gestionnaire des variables `_IMAGE` |
| `.github/workflows/secrets.yml` et `golden/saas-b2b/.github/workflows/secrets.yml` | 2026-11-24 | `GITLEAKS_IMAGE` sur ghcr.io, v8.30.1 par tag et condensat |
| `.github/rulesets/main.json` | 2026-11-24 | `required_approving_review_count: 0` ; contrôles requis `pre-commit`, `secrets (full history)`, `static` |
| [`docs/securite/jeton-github.md`](../securite/jeton-github.md) ; [`ROADMAP.md`](../../ROADMAP.md), actions de Lucas | 2026-11-24 | Permissions du jeton des agents, sans « Issues » ; jeton classique à révoquer ; application Renovate à installer |
| [research.md](../../specs/001-golden-repo-saas-b2b/research.md), RS-17 (décision du DSI du 2026-11-24), RS-18, RS-22 | 2026-11-24 | Renovate de CELIAN sur `golden/` ; Dockerfile du golden repo dans le gestionnaire `dockerfile`, à trancher avant l'étape 3 ; validateur de Renovate et conftest ; base de Trivy hors Renovate |
| [plan.md](../../specs/001-golden-repo-saas-b2b/plan.md), étape 3 et matrice | 2026-11-24 | Dockerfile de l'API par condensat ; S23, X01 |
| [ADR-010](ADR-010-gitops.md), conditions 5 et 6 ; [ADR-011](ADR-011-miroir-registres.md), tableau des registres, conditions 8 et 10 ; [ADR-013](ADR-013-fournisseur-identite.md), conditions 1 et 2, « Registre et miroir », dérogation | 2026-11-24 | Images des moteurs GitOps par condensat, Config Sync en forme libre dans un test sur kind ; registres de Flux, de zot et des images .NET ; image de zot suivie avec le délai ; liste unique des registres ; image de Keycloak, suivi du condensat, copie sur Docker Hub non vérifiée, dérogation qui nomme `quay.io/keycloak/keycloak` |
| [docs/risques.md](../risques.md), R-07, R-25, R-34, R-36 | 2026-11-24 | Jeton des agents ; limite de Docker Hub ; mitigation de zot ; failles sans paquet |
| [Constitution](../../.specify/memory/constitution.md), version 1.2.0 | 2026-11-24 | Principe VI et son exception ; dérogation justifiée dans un ADR, avec durée et condition de levée |
