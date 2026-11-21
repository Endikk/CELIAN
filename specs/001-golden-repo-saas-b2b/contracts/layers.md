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
| composant de cible `local` | `local` | `gatewayClassName` d'Envoy Gateway, `app-config` local, Postgres et Valkey |
| composant de cible `gcp` | `gcp` | `gatewayClassName` de GKE, `app-config` de GCP, `SecretProviderClass` et `SecretSync`, règle d'admission sur les `requests` |
| `local/k8s/lite/`, `local/k8s/standard/` | `local` | overlay `local` et composant de cible local ; en standard, les couches entrées (Keycloak, Mailpit) |
| `gcp/k8s/prod/` | `gcp` | overlay `prod` et composant de cible `gcp` |

Le mécanisme proposé pour les composants de cible est celui des composants de Kustomize, à vérifier sur sa documentation et dans la version embarquée par kubectl (research RS-01). À défaut, une composition par ressources, qui garde le même découpage.

Objets appliqués hors de cette composition :

- la plate-forme locale (CRD Gateway API, Envoy Gateway, EnvoyProxy, GatewayClass), par fichiers vendorés vérifiés, avant l'application ;
- Flux et ses objets de liaison en profil standard (`local/gitops/`) ;
- le `RootSync` de Config Sync (`gcp/k8s/`), jamais appliqué en phase 2.

## Règle de parité

Rendus comparés : la couche commune seule (overlay d'un environnement), puis ce même overlay avec le composant de cible `local`, puis avec le composant de cible `gcp`.

1. Chaque objet de la couche commune se retrouve à l'identique dans les deux rendus de cible, à une exception près : `spec.gatewayClassName` de la Gateway.
2. Un objet présent dans un rendu de cible et absent de la couche commune vient d'un fichier de la couche de cette cible.
3. Une seule Gateway par rendu (ADR-005, condition 5).
4. Les références aux Secrets et à `app-config` (nom, clés, lecture par fichier ou par variable) sont identiques dans les deux rendus (ADR-007, condition 5).

Contrôle : S07. Un écart voulu passe par un ADR et se liste au README (ENF-02).

## Routage

| Élément | Valeur |
| --- | --- |
| Gateway | une, dans le namespace de l'application ; écouteurs HTTP et HTTPS ; routes admises du même namespace |
| HTTPRoute `api` | préfixe de chemin `/api` vers le Service de l'API |
| HTTPRoute `front` | préfixe `/` vers le Service du front |
| Réécriture de chemin | aucune : l'API sert ses routes sous `/api` |
| Écouteur HTTPS | certificat du Secret `gateway-tls` |

Sur `local`, le proxy d'Envoy Gateway est publié en NodePort à ports fixes par l'EnvoyProxy de la couche, et deux `extraPortMappings` en `listenAddress: "127.0.0.1"` y mènent (ADR-005).

## `app-config`

ConfigMap fourni par chaque couche de cible, de même nom et de mêmes clés : hôte et port de la base, nom de la base, hôte et port du cache, mode TLS de chaque connexion. Les noms des clés se fixent à l'étape 3 et s'ajoutent ici.
