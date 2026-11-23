# Fichiers de BENCH-012

Couches que `tests/bench/bench-012-identity.sh` applique dans le cluster kind,
et client HTTP du pod de test. Le rapport est
[BENCH-012](../../../docs/benchmarks/BENCH-012-fournisseur-identite.md).

| Fichier | Rôle |
| --- | --- |
| `keycloak/statefulset.yaml`, `service.yaml`, `service-discovery.yaml` | Couche de Keycloak 26.8.2, tirée du manifest de démarrage rapide de `keycloak/keycloak-quickstarts` ; les écarts sont listés en tête de `statefulset.yaml` |
| `keycloak/realm-bench.json` | Royaume de test et son client, importés au démarrage ; le secret du client vient d'une variable d'environnement |
| `keycloak/kustomization.yaml` | Assemble la couche de Keycloak |
| `zitadel/values.yaml` | Valeurs passées au chart ZITADEL 10.5.0 |
| `zitadel/rendered/` | Rendu du chart, un objet par fichier, fait une fois et versionné : Helm n'est pas un prérequis de la mesure |
| `zitadel/kustomization.yaml` | Applique le rendu dans le namespace du fournisseur, dans l'ordre de `helm template` |
| `client/http.sh` | Client HTTP/1.0 du pod de test, par le `nc` de busybox |

Aucun de ces fichiers ne contient de secret : le script crée chaque Secret par
un tube avant d'appliquer une couche (condition 1 de l'ADR-007).

Le rendu de ZITADEL se refait ainsi, avec Helm 4.3.2 :

```bash
helm pull zitadel --repo https://charts.zitadel.com --version 10.5.0 -d /tmp/zitadel-chart
shasum -a 256 /tmp/zitadel-chart/zitadel-10.5.0.tgz   # e216ca1a9b19e9e2982e76a2cf49c446eeb3a02cdf167834977978acb880f019
helm template zitadel /tmp/zitadel-chart/zitadel-10.5.0.tgz --namespace bench-idp \
  --kube-version 1.36.4 -f zitadel/values.yaml > /tmp/zitadel-rendered.yaml
```

Le fichier rendu est ensuite découpé en un objet par fichier, dans l'ordre :
le `check-yaml` du dépôt refuse les fichiers à plusieurs documents. Les cinq
documents du rendu qui ne portent que des commentaires (modèles vides) ne sont
pas repris. Deux commentaires `# gitleaks:allow` marquent, dans
`rendered/04-deployment-zitadel.yaml`, les annotations
`checksum/secret-db-ssl-ca-crt` et `checksum/secret-zitadel-secrets` : ce sont
les SHA-256 d'un saut de ligne et d'une chaîne vide, que gitleaks prend pour
des clés.

La série de mesure du 2026-11-23 a appliqué le rendu en un seul fichier
(SHA-256 `86d9777b8a6e8a7d8c0b6070d458c98512b3da3bc9f4f31e22ce1d401d7e9f70`)
et la couche de Keycloak en un seul fichier (SHA-256
`7287c1f54f3ba6045cf07d434d8a04a4bbd507840f94bcf7ab8f647815f34557`). Le
découpage, fait après la série, ne change aucun objet : le contenu concaténé
est identique, commentaires mis à part. Un essai de contrôle l'a appliqué
après coup (rapport, section 4.4).
