# Contrat : API de l'exemple

L'API du golden repo, servie sous `/api` par la gateway, à la même origine que le front ([layers.md](layers.md)). Le code se limite à ces routes (FR-009) ; le contrôle S20 échoue sur toute autre route. Le format de description machine (OpenAPI ou autre) et sa version sont à choisir et à vérifier à l'étape 3.

Règles communes :

- JSON en UTF-8, noms de champs en camelCase ;
- chaque entrée est validée côté serveur ; une erreur de validation nomme le champ et la règle ;
- les réponses ne portent que les champs listés ici ;
- les erreurs suivent le format standard d'ASP.NET Core pour les détails de problème, à vérifier ; jamais de trace de pile ni de message de la base ;
- aucune authentification en local : l'exemple n'a pas d'utilisateur. Elle arrive avec l'ADR-013, et aucun déploiement réel sur GCP ne se fait sans elle (décision du DSI du 2026-11-21, research RS-25).

## `GET /api/healthz`

Processus vivant. Ne touche ni la base ni le cache. Sert à la sonde de vivacité.

| Code | Corps |
| --- | --- |
| 200 | `{"status": "ok"}` |

## `GET /api/readyz`

Base et cache joignables avec les identifiants de la cible. Sert à la sonde de disponibilité et à l'attente de `task up`.

| Code | Corps |
| --- | --- |
| 200 | `{"status": "ready", "database": "ok", "cache": "ok"}` |
| 503 | `{"status": "unavailable", "database": "ok" ou "error", "cache": "ok" ou "error"}`, sans détail de l'erreur |

## `POST /api/notes`

Écrit une note en base. Ne touche pas le cache.

Corps de la requête : `{"body": "<texte>"}`. `body` obligatoire, de 1 à 500 caractères après suppression des blancs de début et de fin. Tout autre champ est refusé.

| Code | Corps |
| --- | --- |
| 201 | `{"id": "<uuid>", "body": "<texte>", "createdAt": "<horodatage ISO 8601>"}`, en-tête d'emplacement vers la note |
| 400 | détail de problème qui nomme `body` et la règle enfreinte |
| 413 | corps de plus de 16 Kio, refusé avant toute lecture (décision du DSI du 2026-11-24) |
| 415 | corps qui n'est pas du JSON (décision du DSI du 2026-11-24) |

## `GET /api/notes/{id}`

Lit une note, par le cache d'abord.

| Code | Corps |
| --- | --- |
| 200 | `{"id": "<uuid>", "body": "<texte>", "createdAt": "<horodatage>", "servedFrom": "cache" ou "database"}` |
| 400 | identifiant qui n'est pas un UUID |
| 404 | note absente ; rien n'entre au cache |

La première lecture d'une note neuve répond `servedFrom: "database"`, la suivante `"cache"` tant que la clé vit. E02 s'appuie sur ce champ.

## `GET /api/notes?limit=<n>`

Liste les notes les plus récentes, depuis la base, sans cache.

`limit` : entier de 1 à 50, 20 par défaut ; hors bornes, 400.

| Code | Corps |
| --- | --- |
| 200 | `{"items": [{"id": "...", "body": "...", "createdAt": "..."}]}`, du plus récent au plus ancien |
| 400 | détail de problème qui nomme `limit` |

## Ce que le front attend

Le front appelle ces routes par des chemins relatifs, sans configuration d'adresse. Il affiche la liste au chargement, un formulaire d'ajout avec son état de chargement et ses erreurs par champ, et la provenance de la dernière lecture.
