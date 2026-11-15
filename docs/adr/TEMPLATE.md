# ADR-XXX. Titre de la décision

<!--
Gabarit des décisions d'architecture de CELIAN.
Dupliquer vers docs/adr/ADR-XXX-sujet.md. XXX est le numéro suivant sur trois
chiffres, sujet tient en un ou deux mots en minuscules reliés par des tirets.
Titre : la décision prise, pas la question posée.
Un choix structurant passe d'abord par son BENCH, puis par cet ADR, que Lucas
valide (CLAUDE.md, section Méthode).
Une fois accepté, le fond ne change plus : une nouvelle décision fait l'objet
d'un nouvel ADR qui remplace celui-ci. Seuls le statut et les liens bougent.
Aucun fait technique de mémoire : chaque fait renvoie à la section Sources
(principe VIII). Supprimer chaque commentaire une fois sa section remplie.
-->

| Champ | Valeur |
| --- | --- |
| Statut | proposé |
| Date | AAAA-MM-JJ |
| Auteur | [ARCHI] |
| Décideur | Lucas, validation le AAAA-MM-JJ |
| BENCH lié | [BENCH-XXX](../benchmarks/BENCH-XXX-sujet.md) |
| Remplace | aucun |

<!--
Statut : proposé, accepté, remplacé par ADR-YYY, ou abandonné.
Date : jour de la proposition. Tant que Lucas n'a pas validé, le décideur
s'écrit "Lucas, en attente", et le statut reste proposé.
BENCH lié : obligatoire pour un choix structurant. Sinon, écrire aucun et
dire pourquoi en une phrase.
Remplace : l'ADR que celui-ci remplace. Passer l'ancien au statut
"remplacé par ADR-XXX" dans la même PR.
-->

## Contexte et problème

<!--
Le problème à trancher et pourquoi maintenant. Les contraintes qui pèsent :
principes de la constitution, périmètre du MVP, cibles local et gcp,
exigences du PRD (US-XXX, ENF-XX). Les faits renvoient aux Sources. Aucune
solution dans cette section.
-->

## Options considérées

<!--
Deux à trois options, celles du BENCH (brief, section 8). La grille complète
reste dans le BENCH, qui fait foi : ici, le score total et la raison
principale. Verdict : retenue, écartée, ou éliminée. Une option éliminée
nomme le critère éliminatoire qu'elle touche.
-->

| Option | Score BENCH (sur 100) | Verdict | Raison principale |
| --- | --- | --- | --- |
| Option A | XX | retenue | une phrase |
| Option B | XX | écartée | une phrase |
| Option C | éliminée, non notée | éliminée | critère éliminatoire touché |

Grille, mesures et sources : [BENCH-XXX](../benchmarks/BENCH-XXX-sujet.md).

## Décision

<!--
Ce qui est retenu, en une ou deux phrases à la voix active. Puis la portée :
brique abstraite de la spec concernée, cibles couvertes, ce qui reste hors de
la décision. La spec ne nomme jamais le service concret (principe II).
-->

## Conséquences

### Positives

<!-- Ce que la décision apporte, sous une forme vérifiable si possible. -->

### Négatives

<!--
Ce qu'elle coûte : dette, dépendance, empreinte sur PC, coût cloud,
apprentissage. Un risque durable se signale au DSI pour docs/risques.md et se
cite ici par son identifiant R-XX.
-->

### Effet sur les cibles hors MVP

<!--
La décision empêche-t-elle d'ajouter AWS, Azure ou l'on-prem plus tard ? Une
phrase suffit. Ne rien concevoir pour ces cibles : vérifier seulement que la
porte reste ouverte.
-->

## Conformité à la constitution

Vérifiée contre la [constitution](../../.specify/memory/constitution.md) en version X.Y.Z.

<!--
Une ligne par principe. Effet : respecté, dérogation, ou sans objet. La
justification tient en une phrase.
Principe V : un projet à éditeur unique est accepté si le BENCH justifie
l'écart. Le dire ici, avec le critère de la grille qui l'emporte. Un service
managé du fournisseur, imposé sur le cloud par le principe III, ne demande pas
cette justification.
Principe VI : dire que l'option retenue ne touche aucun critère éliminatoire.
-->

| Principe | Effet | Justification |
| --- | --- | --- |
| I. Rien sans test automatique | à qualifier | une phrase |
| II. Spec abstraite, catalogue concret | à qualifier | une phrase |
| III. Managé sur le cloud, open source ailleurs | à qualifier | une phrase |
| IV. Catalogue traçable | à qualifier | une phrase |
| V. Gouvernance ouverte d'abord | à qualifier | une phrase |
| VI. Récent mais éprouvé | à qualifier | une phrase |
| VII. Une commande pour démarrer | à qualifier | une phrase |
| VIII. Aucun fait de mémoire | à qualifier | une phrase |
| IX. Aucun secret dans le dépôt | à qualifier | une phrase |
| X. Aucune dépense cloud sans accord | à qualifier | une phrase |

### Dérogations

<!--
Une dérogation se justifie ici, avec sa durée et la condition qui la lèvera
(constitution, section Gouvernance). Elle se signale au DSI pour que sa levée
soit suivie. Sans dérogation, remplacer le tableau par : Aucune.
-->

| Principe | Écart | Justification | Durée | Condition de levée |
| --- | --- | --- | --- | --- |
| numéro et nom | ce qui n'est pas respecté | pourquoi c'est acceptable | jusqu'à quand | ce qui la lèvera |

## Entrée au catalogue

<!--
Seulement si la décision fait entrer une techno au catalogue ; sinon,
supprimer la section. Une entrée incomplète ne sert à aucun blueprint
(principe IV).
Une ligne par cible du MVP : local et gcp. Une cible hors MVP n'a pas de ligne
tant que Lucas ne l'a pas ouverte ; elle viendra comme une ligne de plus.
Les colonnes reprennent le format indicatif du brief (section 5) : service,
type, license, governance, status, verified_on, sources.
Type : managed ou oss. Licence : identifiant court, comme Apache-2.0 dans
l'exemple du brief ; pour un service managé, service propriétaire du
fournisseur. Gouvernance : fondation (laquelle) ou éditeur unique (lequel).
Statut : actif, maintenance ou archivé.
-->

Brique abstraite : `id-de-la-brique`, le nom employé par la spec et la clé de l'entrée dans `catalog/`.

| Cible | Service | Type | Licence | Gouvernance | Statut | Vérifié le | Source |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `local` | nom du service | `oss` | à vérifier | à vérifier | à vérifier | AAAA-MM-JJ | URL officielle |
| `gcp` | nom du service | `managed` | à vérifier | à vérifier | à vérifier | AAAA-MM-JJ | URL officielle |

## Condition de révision

<!--
Ce qui ferait rouvrir la décision, sous une forme vérifiable. Exemples tirés
des sources : changement de licence, passage en maintenance ou archivage,
aucune release depuis 12 mois (critères éliminatoires du brief, section 8),
seuil de mesure du BENCH dépassé, ouverture d'une cible hors MVP.
-->

## Sources

<!--
Chaque fait technique cité dans l'ADR, avec son URL officielle et sa date de
lecture (principe VIII). Une information non vérifiée se signale comme telle
dans le texte. Ce que le BENCH établit déjà se cite par le BENCH, sans
recopier ses sources.
-->

| Source | Lue le | Ce qu'elle établit |
| --- | --- | --- |
| URL officielle | AAAA-MM-JJ | le fait cité |
