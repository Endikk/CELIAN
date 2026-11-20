# Catalogue des services

Le catalogue est le seul endroit du générateur qui nomme un service concret (principe II). La spec du projet déclare une brique abstraite, `postgres` ou `redis` par exemple ; le catalogue dit quel service la porte sur chaque cible. Le format est fixé par [ADR-009](../docs/adr/ADR-009-catalogue.md), au statut proposé jusqu'à la GATE 1.

## Un fichier par brique

Chaque brique a son fichier `catalog/<id>.yaml`, où `<id>` est le nom abstrait de la brique. Le fichier est validé par le JSON Schema [`schema/catalog-entry.schema.json`](../schema/catalog-entry.schema.json) (JSON Schema 2020-12, comme la spec, [ADR-001](../docs/adr/ADR-001-format-spec.md)), puis par le contrôle du catalogue en CI, qui vérifie ce que le schéma ne sait pas exprimer : les dates par rapport au jour, le nom du fichier, les liens vers les ADR et les BENCH, la liste blanche des licences.

Exemple réel : [`kubernetes-cluster.yaml`](kubernetes-cluster.yaml). Exemple minimal fictif : [`tests/catalog/valid/minimal.yaml`](../tests/catalog/valid/minimal.yaml).

Les clés sont en anglais, les textes libres (`summary`, `detail`, `establishes`, `note`, `notes`, `managed_gap`) en français.

### Champs de la brique

| Clé | Obligatoire | Contenu |
| --- | --- | --- |
| `schema_version` | oui | `1`, la version du schéma suivie |
| `id` | oui | Nom abstrait, en minuscules et tirets, identique au nom du fichier |
| `summary` | oui | Ce que la brique apporte, en une ligne |
| `declared_by` | oui | `spec` si la spec déclare la brique, `target` si elle découle de la cible (le cluster Kubernetes, par exemple) |
| `targets` | oui | Une entrée par cible du MVP, `local` et `gcp`, les deux obligatoires (ENF-02) |

### Champs d'une cible

Une cible est de type `oss` (composant libre que le projet généré fait tourner) ou `managed` (service managé du fournisseur cloud). La cible `local` n'accepte que `oss` (principe III). La cible `gcp` accepte `managed`, ou `oss` avec le champ `managed_gap` qui dit pourquoi aucun service managé de Google ne couvre le besoin.

| Clé | `oss` | `managed` | Contenu |
| --- | --- | --- | --- |
| `type` | oui | oui | `oss` ou `managed` |
| `service` | oui | oui | Nom du service ou du projet |
| `version` | oui | facultatif | Version exacte, jamais une plage ni `latest`. Pour un service managé, la version du moteur quand le fournisseur en propose plusieurs |
| `license` | oui | interdit | Expression SPDX, `Apache-2.0` par exemple. Un service managé n'en a pas : il est propriétaire et tourne sous les conditions du fournisseur |
| `provider` | interdit | oui | Fournisseur : `google` dans le MVP |
| `governance.model` | oui | oui, `single-vendor` | `foundation`, `community` (organisation sans fondation) ou `single-vendor` |
| `governance.body` | oui | oui | La fondation, l'organisation ou l'entreprise : `CNCF`, `Google` |
| `governance.detail` | facultatif | facultatif | Où le projet se situe dans cette structure |
| `status` | oui | oui | `active`, `maintenance` ou `archived`. Le contrôle échoue sur tout sauf `active` |
| `last_release_on` | oui | interdit | Date de la dernière release amont |
| `verified_on` | oui | oui | Date de la dernière vérification complète, égale au `read_on` le plus récent des sources |
| `standards` | oui | oui | Standards ouverts exposés, voir plus bas. Une liste vide est permise et veut dire que la couche de cible porte toute la différence |
| `sources` | oui, au moins une | oui, au moins une | `url` en `https://`, `read_on`, et `establishes` (facultatif mais attendu) : ce que la source établit |
| `decisions.adr` | oui | oui | ADR qui a fait entrer le service, `ADR-004` par exemple |
| `decisions.bench` | facultatif | facultatif | BENCH qui fonde l'ADR. Un service managé imposé par le principe III peut ne pas en avoir |
| `artifacts` | facultatif | interdit | Condensat SHA-256 d'un binaire téléchargé, par plateforme (`darwin-arm64`, `darwin-amd64`, `linux-amd64`, `linux-arm64`), avec sa source et sa date |
| `pending` | facultatif | facultatif | Champs encore ouverts : `topic`, `owner` (tag de rôle ou `Lucas`), `note` |
| `notes` | facultatif | facultatif | Remarque libre, 500 caractères au plus |
| `managed_gap` | `gcp` seulement, alors obligatoire | interdit | Pourquoi aucun service managé du fournisseur ne couvre le besoin |

Les dates s'écrivent `"AAAA-MM-JJ"`, entre guillemets. Sans guillemets, PyYAML les lit comme des dates Python et le schéma les refuse. Les condensats aussi s'écrivent entre guillemets.

### Champ inconnu

On n'invente jamais une valeur. Un champ obligatoire inconnu empêche l'entrée d'exister : on la crée quand on sait le remplir. Un choix encore ouvert qui n'est pas un champ du schéma (le mode du cluster GKE, un condensat pour une autre plateforme) va dans `pending`, avec le rôle qui le tranchera.

Une cible qui a des `pending` est une entrée valide du catalogue, mais aucun blueprint ne peut encore s'en servir (principe IV). Le contrôle du catalogue les liste sans échouer.

### Standards exposés

Le standard est ce que la cible `local` et la cible `gcp` ont en commun, donc ce qui tient le principe II. Les valeurs admises sont dans le schéma ; en ajouter une passe par une PR qui modifie le schéma et ce tableau, avec sa source.

| Valeur | Standard | Ce qui est vérifié | Source, lue le 2026-11-19 |
| --- | --- | --- | --- |
| `kubernetes-api` | API de Kubernetes | Kubernetes est gradué à la CNCF depuis le 2018-03-06 | <https://www.cncf.io/projects/kubernetes/> |
| `gateway-api` | Gateway API de Kubernetes | Fait partie de SIG Network, sous Apache-2.0 | <https://github.com/kubernetes-sigs/gateway-api> |
| `postgresql-protocol` | Protocole frontend/backend de PostgreSQL | Version 3.2, introduite avec PostgreSQL 18, rétrocompatible avec la 3.0. Gouvernance à vérifier à l'entrée de la brique `postgres` | <https://www.postgresql.org/docs/current/protocol.html> |
| `resp` | REdis Serialization Protocol | Protocole des clients de Valkey, conçu pour Redis | <https://valkey.io/topics/protocol/> |
| `otlp` | OpenTelemetry Protocol | OpenTelemetry est gradué à la CNCF depuis le 2026-05-11 | <https://www.cncf.io/projects/opentelemetry/> |

## Ce qui n'entre pas au catalogue

- Les outils du générateur : Copier, python-jsonschema, la CLI. Ils sont tracés dans leurs BENCH et figés dans le verrou de la CLI (ADR-001, ADR-002, ADR-003).
- Les condensats d'images de conteneurs : ils vivent dans le blueprint, que Renovate met à jour. Les écrire aussi ici ferait deux sources pour une même valeur.
- Une techno écartée ou piégée. Le catalogue ne tient que ce qu'un blueprint peut utiliser. Les pièges connus du brief (section 5) servent de liste de contrôle à l'entrée de la brique concernée ; ils ne sont pas une source et se revérifient comme tout autre fait.

## Ajouter une entrée

1. Le service a son ADR, et son BENCH si le choix est structurant. Sur `gcp`, un service managé imposé par le principe III n'a pas besoin de BENCH, mais le choix entre deux services managés passe par un ADR.
2. Créer `catalog/<id>.yaml` en partant de l'exemple minimal.
3. Remplir chaque champ depuis une source officielle, lue le jour même : dépôt ou site du projet, page de la fondation, documentation du fournisseur. Un blog, un guide tiers ou un résultat de recherche ne compte pas (principe VIII).
4. Vérifier les principes au passage :
   - sur `local`, une licence libre approuvée par l'OSI et présente dans [`scripts/catalog/accepted-licenses.yaml`](../scripts/catalog/accepted-licenses.yaml), la liste blanche écrite par CELIAN (principe III). Une licence absente s'y ajoute par une PR relue par [SECU], avec sa page sur opensource.org et sa date de lecture ;
   - à fonctionnalité comparable, un projet de fondation plutôt qu'un éditeur unique (principe V) ; sur `gcp`, entre deux variantes managées, celle dont le moteur ou l'interface est porté par une fondation (ADR-009) ;
   - aucun critère éliminatoire du principe VI : dépôt archivé ou en maintenance, aucune release depuis 12 mois.
5. Écrire chaque source avec la date de lecture, et `verified_on` égal à la plus récente.
6. Mettre dans `pending` ce qui reste ouvert, avec son porteur.

## Revérifier une entrée

Une entrée vérifiée il y a plus de six mois fait échouer la CI (ADR-009), comme une source lue il y a plus de six mois, même quand une autre source a été relue depuis. Le contrôle prévient pendant le dernier mois.

1. Relire chaque source de chaque cible. Mettre à jour `read_on` de chacune, puis `verified_on`.
2. Si rien n'a changé, la PR ne touche que les dates.
3. Si un fait a changé (licence, statut, gouvernance, dernière release, version), corriger le champ. Un changement de licence ou de statut, ou un critère éliminatoire touché, demande un nouvel ADR : on ne se contente pas de mettre la date à jour.
4. Ne jamais avancer `verified_on` sans avoir relu les sources. Le contrôle exige qu'il soit égal au `read_on` le plus récent, et fait expirer chaque source six mois après son propre `read_on`.

## Contrôles en CI

Le contrôle est [`scripts/catalog/check_catalog.py`](../scripts/catalog/check_catalog.py), lancé par le hook pre-commit `catalog-check`. Sur chaque PR et chaque push sur `main` (job `pre-commit` de `ci.yml`, obligatoire pour fusionner), et chaque lundi sur `main` (`catalog-freshness.yml`), toutes les entrées passent le contrôle, modifiées ou non. Il échoue si :

- le fichier n'est pas en UTF-8, porte une clé en double, un alias ou une clé de fusion `<<` ;
- le fichier ne passe pas le schéma ;
- une chaîne finit par un saut de ligne : un bloc `>` ou `|` sans `-` en garde un, et le `pattern` du schéma le laisse passer ;
- le nom du fichier diffère de `id`, ou deux fichiers portent le même `id` ;
- `catalog/` contient autre chose que des fichiers `<id>.yaml` et ce README, ou un lien symbolique, refusé sans être suivi ;
- une date est impossible ou postérieure au jour, compté en UTC ;
- `verified_on` ou le `read_on` d'une source date de six mois ou plus, ou `verified_on` diffère du `read_on` le plus récent ;
- une cible `oss` n'a pas eu de release depuis 12 mois (principe VI) ;
- `status` vaut autre chose que `active` ;
- un ADR ou un BENCH cité n'a pas de fichier `docs/adr/ADR-XXX-*.md` ou `docs/benchmarks/BENCH-XXX-*.md` ;
- une licence `oss` n'est pas dans `scripts/catalog/accepted-licenses.yaml` ou n'y est pas écrite à l'identique, quel que soit l'opérateur (`AND`, `OR`), ou une exception après `WITH` n'y est pas ;
- deux condensats portent la même plateforme.

Il avertit, sans échouer, quand `verified_on` ou une source entre dans son dernier mois, quand `local` et `gcp` n'ont aucun standard en commun, quand une cible a des `pending`, et quand une licence est marquée à copyleft réseau (AGPL) dans la liste blanche : l'ADR de la brique dit alors comment le projet généré s'y conforme.

Chaque message donne le fichier, le chemin JSON du champ et la règle, par exemple :

```text
error: catalog/x.yaml: targets/local/license: [license] 'BUSL-1.1' is not in the CELIAN license allowlist: adding one takes a PR reviewed by [SECU]
```

En local, `pre-commit run catalog-check --all-files` lance le contrôle à la date du jour, et `pre-commit run catalog-check-tests --all-files` ses tests. Le script accepte `--today AAAA-MM-JJ` pour voir l'état du catalogue à une autre date. La liste blanche des licences, `scripts/catalog/accepted-licenses.yaml`, porte pour chaque identifiant sa page sur opensource.org, sa date de lecture et l'attribution CC-BY-4.0 du contenu de ce site.
