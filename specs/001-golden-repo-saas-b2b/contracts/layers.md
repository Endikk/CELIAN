# Contrat : couches, composition et parité

Ce contrat sert deux lecteurs : le golden repo, qui doit le tenir, et l'architecte de la phase 3, qui en fera des dossiers conditionnels du blueprint.

## Appartenance

| Chemin sous `golden/saas-b2b/` | Couche |
| --- | --- |
| `local/` | `local` |
| `gcp/` | `gcp` |
| tout le reste | commune |

Un test de chemins échoue si un fichier hors de `local/` nomme kind, Envoy Gateway, zot ou Flux dans un objet rendu, ou si un fichier hors de `gcp/` nomme un service de Google (S06). Les tâches publiques du `Taskfile.yml` racine délèguent aux Taskfiles des couches : en phase 3, le rendu n'inclura que ceux des cibles choisies.

Le test de parité, qui rend les deux cibles, n'a de sens que si les deux sont présentes ; en phase 3, il ne sera généré qu'avec elles.

## Composition Kustomize

| Élément | Couche | Contenu |
| --- | --- | --- |
| `k8s/base/` | commune | namespace, Deployments et Services de l'API et du front, Gateway et HTTPRoute ; références à `app-config` et aux Secrets du [contrat](secrets.md) |
| `k8s/overlays/{local,staging,prod}/` | commune | réglages par environnement, neutres vis-à-vis de l'outil et du fournisseur (ADR-010, condition 1) |
| composant de cible `local` | `local` | `gatewayClassName` d'Envoy Gateway, `app-config` local, Postgres, et le cache après l'ADR-015 |
| composant de cible `gcp` | `gcp` | `gatewayClassName` de GKE, `app-config` de GCP, `SecretProviderClass` et `SecretSync`, règle d'admission sur les `requests` |
| `local/k8s/lite/`, `local/k8s/standard/` | `local` | overlay `local` et composant de cible local ; en standard, les couches entrées (Keycloak, Mailpit) |
| `gcp/k8s/prod/` | `gcp` | overlay `prod` et composant de cible `gcp` |

Le mécanisme proposé pour les composants de cible est celui des composants de Kustomize, à vérifier sur sa documentation et dans la version embarquée par kubectl (research RS-01). À défaut, une composition par ressources, qui garde le même découpage.

Objets appliqués hors de cette composition :

- la plate-forme locale (CRD Gateway API, Envoy Gateway, EnvoyProxy, GatewayClass), par fichiers vendorés vérifiés, avant l'application ;
- Flux et ses objets de liaison en profil standard (`local/gitops/`), liaison suspendue tant que Lucas n'a pas tranché ce que lit Flux (décision du 2026-11-21) ;
- le `RootSync` de Config Sync (`gcp/k8s/`), jamais appliqué en phase 2.

## Fichiers du scan des images

| Fichier (noms provisoires) | Couche | Contenu |
| --- | --- | --- |
| `security/scan-policy.yaml` | commune | seuil de gravité, `HIGH` |
| `security/scan-exceptions.yaml` | commune | exceptions des images construites |
| `policy/` (Rego de décision) | commune | décision du scan sur le rapport, les exceptions et la date du jour |
| `local/security/scan-exceptions.yaml` | `local` | exceptions des images de la couche `local` |
| `local/security/unlisted-images` | `local` | images qu'aucun fichier ne nomme, par condensat |

Une exception qui vise une image de la couche `local` vit dans la couche `local` : la couche commune ne nomme ni zot, ni Envoy Gateway, ni Flux (S06). Détail : [data-model.md](../data-model.md), sections « Inventaire des images » et « Exception au scan ».

## Règle de parité

Rendus comparés : la couche commune seule (overlay d'un environnement), puis ce même overlay avec le composant de cible `local`, puis avec le composant de cible `gcp`.

1. Chaque objet de la couche commune se retrouve à l'identique dans les deux rendus de cible, à deux champs près, que chaque cible fixe : `spec.gatewayClassName` de la Gateway et `spec.hostnames` des HTTPRoute (écart 120). La couche commune ne nomme aucun hôte ; la couche `local` nomme `localhost`.
2. Un objet présent dans un rendu de cible et absent de la couche commune vient d'un fichier de la couche de cette cible.
3. Une seule Gateway par rendu (ADR-005, condition 5).
4. Les références aux Secrets et à `app-config` (nom, clés, lecture par fichier ou par variable) sont identiques dans les deux rendus (ADR-007, condition 5).

Contrôle : S07. Un écart voulu passe par un ADR et se liste au README (ENF-02).

## Routage

| Élément | Valeur |
| --- | --- |
| Gateway | une, dans le namespace de l'application ; écouteurs HTTP et HTTPS ; routes admises du même namespace |
| HTTPRoute `api` | préfixe de chemin `/api` vers le Service de l'API, port 80 ; hôte posé par la couche de cible |
| HTTPRoute `front` | préfixe `/` vers le Service du front, port 80 ; hôte posé par la couche de cible |
| Réécriture de chemin | aucune : l'API sert ses routes sous `/api` |
| Écouteur HTTPS | certificat du Secret `gateway-tls` |

Sur `local`, le proxy d'Envoy Gateway est publié en NodePort à ports fixes par l'EnvoyProxy de la couche, et deux `extraPortMappings` en `listenAddress: "127.0.0.1"` y mènent (ADR-005).

## `app-config`

ConfigMap fourni par chaque couche de cible, de même nom et de mêmes clés : hôte et port de la base, nom de la base, hôte et port du cache, mode TLS de chaque connexion, paquet de la CA du cache. L'API lit ses clés en variables d'environnement ; elles ne portent aucun secret, et l'utilisateur et le mot de passe de la base viennent des fichiers montés de `db-auth`, le mot de passe du cache du fichier monté de `cache-auth` ([contrat des Secrets](secrets.md)).

Clés fixées à l'étape 3 (T021) et à l'étape 19 (T080), gardées par U01 :

| Clé | Valeur | Lue par l'API |
| --- | --- | --- |
| `DATABASE_HOST` | nom d'hôte de la base | dès l'étape 3 |
| `DATABASE_PORT` | port de la base, de 1 à 65535 | dès l'étape 3 |
| `DATABASE_NAME` | nom de la base, `app` | dès l'étape 3 |
| `DATABASE_SSL_MODE` | `SSL Mode` de Npgsql : `Disable`, `Allow`, `Prefer`, `Require`, `VerifyCA` ou `VerifyFull` ; valeur de chaque cible fixée par T062 (research RS-03 et RS-12) | dès l'étape 3 |
| `CACHE_HOST` | nom d'hôte du cache | à l'étape 19 |
| `CACHE_PORT` | port du cache | à l'étape 19 |
| `CACHE_TLS_MODE` | `Disable`, `VerifyCA` ou `VerifyFull`, sans égard à la casse : `Disable` sur `local` ; sur `gcp`, l'un des deux autres, choisi à l'étape 20 (research RS-11) | à l'étape 19 |
| `CACHE_TLS_CA_FILE` | chemin du paquet PEM de la CA du cache, monté par la couche de cible ; lu sous `VerifyCA` et `VerifyFull` seulement, vide sur `local` (ADR-015, condition 17 ; research RS-11) | à l'étape 19 |
