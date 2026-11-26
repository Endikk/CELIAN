# Contrat : Secrets de l'application

L'application lit le même Secret, de même nom et de mêmes clés, sur les deux cibles, et ne sait pas ce qui l'a produit (ADR-007, condition 5). Elle les lit par fichiers montés, de la même façon sur les deux cibles. Noms provisoires jusqu'au schéma de spec de la phase 3.

## Secrets

| Secret | Type | Clés | Producteur `local` | Producteur `gcp` | Lu par |
| --- | --- | --- | --- | --- | --- |
| `db-auth` | `kubernetes.io/basic-auth` | `username` (`app`), `password` | `task up` | synchronisation de GKE depuis Secret Manager (ADR-007) : `SecretSync` de type `Opaque`, écart 144 | API ; script d'initialisation de la base sur `local` |
| `cache-auth` | `Opaque` | `password` (ADR-015) | `task up`, à partir de l'étape 19 | selon l'authentification de Memorystore retenue par l'ADR-015, étape 20 (research RS-11) | API ; le cache sur `local` |
| `db-superuser` | `kubernetes.io/basic-auth` | `username`, `password` | `task up` | aucun : Cloud SQL ne donne pas de superutilisateur (ADR-012) | conteneur Postgres seulement ; jamais l'application |
| `gateway-tls` | `kubernetes.io/tls` | `tls.crt`, `tls.key` | `task up` : `openssl req -x509` écrit clé et certificat auto-signé (P-256, 365 jours, SAN `localhost` et `127.0.0.1`) sur sa sortie standard, `awk` les étiquette, un tube mène à `kubectl create -f -` ; ni fichier, ni variable, ni argument (research RS-10, 2026-11-26) | proposé : certificat auto-signé, clé en écriture seule dans Secret Manager, puis synchronisation de GKE, avec l'écouteur HTTPS (research RS-16, écart 146) | Gateway |

L'API lit `db-auth` dans les fichiers `username` et `password` du dossier `/run/secrets/db-auth`, où la couche commune monte le Secret (étape 3, T021 ; montage écrit à l'étape 9, T087). Un saut de ligne final est ignoré ; un fichier absent ou vide arrête l'accès à la base, et le message nomme le fichier sans jamais donner sa valeur.

L'API lit `cache-auth` dans le fichier `password` du dossier `/run/secrets/cache-auth`, de la même façon (étape 19, T080 ; montage écrit à l'étape 9, T087) : un fichier absent ou vide met le cache en erreur dans `/api/readyz`, et les lectures passent par la base. Sur `local`, seul le conteneur d'initialisation du cache monte aussi ce Secret ; le serveur du cache ne le monte pas (ADR-015, condition 4).

`db-superuser` est un Secret de couche : son écart entre cibles se liste au README (ENF-02, ADR-012). Keycloak et Mailpit ajouteront leurs Secrets après leurs ADR. Flux n'a aucun identifiant Git par défaut (ADR-010, condition 4).

## Création sur `local`

- Chaque mot de passe : 40 caractères alphanumériques tirés de `/dev/urandom`.
- `gateway-tls` ne porte pas de mot de passe : sa clé et son certificat naissent d'un même `openssl req`, jamais écrits (research RS-10). Auto-signé, 365 jours, non installé dans le magasin de confiance du poste. Pour E04, la clé et le certificat diffèrent d'un environnement à l'autre, et la règle des 32 caractères ne s'y applique pas.
- Chaque Secret passe par un tube vers `kubectl create -f -`, seulement s'il manque. Jamais `kubectl apply`, jamais de heredoc, jamais de valeur dans un fichier, une variable de Task ou un argument.
- Les tâches qui créent un Secret sont silencieuses.
- `db-auth` et `db-superuser` vivent avec le volume de la base : volume présent et Secret absent, `task up` s'arrête (ADR-012, condition 3). Un Secret présent sans volume reste valide.
- Aucun Secret n'est versionné, ni sous `k8s/`, ni ailleurs (S03).

## Ce que vérifient les tests

| Contrôle | Règle |
| --- | --- |
| E04 | Deux environnements neufs : aucune valeur de mot de passe commune, 32 caractères au moins, aucune valeur de la liste `root`, `admin`, `postgres`, `password`, `changeme`, `mysecretpassword`, chaîne vide. `username` est fixe par construction et n'entre pas dans la comparaison |
| E05 | Second `task up` : empreinte SHA-256 de chaque valeur inchangée ; aucune annotation `kubectl.kubernetes.io/last-applied-configuration` ; chaque Secret porte exactement les clés de ce contrat |
| E06 | Aucune valeur retrouvée dans l'arborescence ni dans l'historique Git |
| S07 | Les références aux Secrets dans les rendus `local` et `gcp` de l'application sont identiques : nom, clés, lecture par fichier |
| S03, S04 | Aucun Secret versionné ; tâches silencieuses, sans heredoc ni `apply` |
