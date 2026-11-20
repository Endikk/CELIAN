# ADR-003. CLI de CELIAN écrite en Python

| Champ | Valeur |
| --- | --- |
| Statut | accepté |
| Date | 2026-11-19 |
| Auteur | [ARCHI] |
| Décideur | DSI, sur délégation de Lucas à la GATE 1 du 2026-11-20 |
| BENCH lié | [BENCH-006](../benchmarks/BENCH-006-langage-cli.md) |
| Remplace | aucun |

## Contexte et problème

La CLI porte la partie déterministe du produit : validation de la spec, traduction par le catalogue, génération et vérifications. Le plugin Claude Code la pilote, et elle doit fonctionner seule pour que le plugin reste une couche fine (R-13). Le brief et la constitution inscrivent déjà une CLI Python dans la forme du produit. La question Q10 du PRD a gardé BENCH-006, en version courte, pour tracer le pourquoi dans un ADR.

Plusieurs exigences dépendent du langage. US-001 vérifie les prérequis au lancement, et chaque runtime exigé par la CLI en ajoute un. US-003 et US-004 font tourner la validation et la génération par la CLI seule, sans modèle de langage, dans la matrice de validation. US-011 passe par le moteur de templates, et ENF-01 compte chaque étape dans les 15 minutes. Côté constitution, les principes V et VI.

Le moteur proposé par [ADR-002](ADR-002-moteur-templates.md), Copier, est une bibliothèque Python qui demande Python 3.10 ou plus et Git 2.27 ou plus (BENCH-006, section 2).

## Options considérées

| Option | Score BENCH (sur 100) | Verdict | Raison principale |
| --- | --- | --- | --- |
| Python (CPython) | 94 | retenue | Langage de Copier, appelé dans le même processus ; un seul runtime à installer ; langage porté par une fondation |
| TypeScript sur Node.js | 76 | écartée | Ajoute Node.js sans retirer Python, que Copier exige : deux runtimes et deux registres de paquets, Copier appelé en sous-processus, compilateur tenu par Microsoft seule |

Go et Rust ont été repérés sans être étudiés : le brief limite ce benchmark à deux options, et tout langage autre que Python appellerait Copier en sous-processus, avec Python installé à côté.

Grille, mesures et sources : [BENCH-006](../benchmarks/BENCH-006-langage-cli.md).

## Décision

La CLI de CELIAN s'écrit en Python (CPython) et appelle Copier comme bibliothèque, dans son propre processus. Elle se distribue comme un paquet Python standard.

Ce choix dépend d'ADR-002. Il repose sur un moteur de templates écrit en Python : si ADR-002 était remplacé par un moteur distribué par npm, cet ADR se rouvre. Avec Yeoman, BENCH-006 calcule une égalité à 85 entre les deux langages.

### Conditions

1. Paquet standard, sans dépendance à uv. La CLI se publie comme un paquet Python standard, installable par pipx comme par uv. Elle ne dépend pas d'uv : aucun import, aucun appel, aucune fonction qui suppose sa présence (R-24). La documentation d'installation décrit les deux voies, dont une avec un Python hors uv (python.org ou celui de la distribution), et l'option `--no-python-downloads` pour qui garde uv. Raison : uv est tenu par un éditeur unique, Astral, qui a annoncé le 2026-03-19 rejoindre OpenAI, et uv fournit aussi l'interpréteur par le projet python-build-standalone d'Astral. pipx appartient à l'organisation PyPA. [DEV] fixe en phase 5 le prérequis de US-001 : uv seul, ou Python et pipx.
2. Version minimale de Python. Valeur proposée : 3.12, à confirmer par [DEV], qui la déclare dans la configuration du paquet. Copier accepte encore 3.10, en fin de vie depuis le 2026-10-01 : la CLI doit exiger une version supportée. 3.11 sort du support en 2027-10, onze mois après cet ADR, et 3.12 en 2028-10. La CI de Copier couvre 3.11 à 3.15, et l'image Ubuntu 24.04 des runners GitHub a 3.11 à 3.15.2 en cache. Avant de confirmer, [DEV] vérifie la version de Python que livrent macOS et les distributions Linux visées (Q5) : ni le BENCH ni cet ADR ne l'ont lue. Le plancher monte quand sa version sort du support.
3. Options d'installation à évaluer par [DEV]. `uv tool run --exclude-newer "7 days"` applique à l'installation de la CLI la règle des 7 jours du principe VI. En contrepartie, un correctif publié depuis moins de 7 jours n'est pas pris, et `--exclude-newer-package` permet une exception par paquet. `--no-build` refuse les distributions sources, dont la construction peut exécuter du code arbitraire. Point d'attention : la version minimale de Copier suit le dernier avis de sécurité (ADR-002, condition 2), et la règle des 7 jours retarderait d'autant l'arrivée d'un correctif chez l'utilisateur. L'exception par paquet est la piste à évaluer pour Copier.
4. Binaire autonome. Si [DEV] choisit un jour un binaire qui embarque CPython, il y joint les avis de licence de Python et de ses composants tiers, et [SECU] relit à nouveau avant toute publication.

### Portée

La décision porte sur le générateur seul : la CLI sur le PC de l'utilisateur et dans la CI du générateur. Elle ne touche aucune brique de la spec ni aucune cible. Les projets générés restent en .NET et React, et ne dépendent pas de CELIAN (ENF-07). La CLI n'entre pas dans `catalog/`, faute d'être une brique des projets générés.

Restent hors de cette décision : le cadriciel de ligne de commande, l'outillage de test et le vérificateur de types (phase 5, [DEV]), les noms des commandes (phase 5) et Windows (Q5).

## Conséquences

### Positives

- Un seul runtime en prérequis, celui que Copier exige déjà, avec Git. Claude Code s'installe sans Python ni Node.js, donc US-001 n'a qu'un runtime à faire installer et à diagnostiquer.
- La CLI appelle Copier par son API (`run_copy`, `run_update`) et reçoit ses exceptions Python, au lieu d'interpréter une sortie texte et des codes de retour.
- Le langage est porté par une fondation, la PSF, et piloté par un comité élu de cinq membres, deux au plus par employeur.
- Une seule chaîne d'outils en CI, un verrou, un flux Renovate. L'image Ubuntu 24.04 des runners a Python 3.15.2 en cache et pipx 1.16.7.
- macOS Apple Silicon, Linux x64 et Linux arm64 sont au niveau 1 de support de CPython, macOS Intel au niveau 2.

### Négatives

- Temps de démarrage non mesuré. Un import lent de Copier pèserait sur chaque commande ; au pire, Python perdrait 2 points sans changer le classement. Le script `tests/bench/bench-006-startup.sh` le mesurera quand [DEV] aura un squelette.
- Typage optionnel : un vérificateur de types en CI reste à choisir par [DEV].
- Une installation depuis PyPI exécute du code quand elle construit une distribution source (condition 3).
- Le chemin d'installation le plus court, uv, est tenu par un éditeur unique qui fournit aussi l'interpréteur (R-24). La voie pipx avec un Python hors uv borne ce risque.
- L'expérience dev est notée sans essai sur machine : ses notes peuvent bouger d'un cran.

### Effet sur les cibles hors MVP

La porte reste ouverte. Le langage de la CLI n'entre dans aucun projet généré et ne connaît aucune cible : AWS, Azure ou l'on-prem resteront des couches de blueprint et des lignes de catalogue.

## Conformité à la constitution

Vérifiée contre la [constitution](../../.specify/memory/constitution.md) en version 1.0.0.

| Principe | Effet | Justification |
| --- | --- | --- |
| I. Rien sans test automatique | respecté | Validation et génération tournent par la CLI seule, sans modèle de langage, donc dans la matrice de validation (US-003, US-004) |
| II. Spec abstraite, catalogue concret | sans objet | Le langage de la CLI ne change ni la spec ni le catalogue |
| III. Managé sur le cloud, open source ailleurs | sans objet | Outil du générateur, pas un service d'une cible |
| IV. Catalogue traçable | sans objet | Aucune entrée au catalogue : la CLI n'est pas une brique des projets générés |
| V. Gouvernance ouverte d'abord | respecté | Langage porté par la PSF, comité élu à employeurs plafonnés ; uv, éditeur unique, reste un canal d'installation et jamais une dépendance (condition 1) |
| VI. Récent mais éprouvé | respecté | Aucun critère éliminatoire touché ; le plancher de la condition 2 exclut les versions en fin de vie |
| VII. Une commande pour démarrer | sans objet | Le projet généré ne dépend pas de la CLI (ENF-07) |
| VIII. Aucun fait de mémoire | respecté | Chaque fait renvoie à BENCH-006, sources lues le 2026-11-19 |
| IX. Aucun secret dans le dépôt | sans objet | Le choix du langage ne touche aucun secret |
| X. Aucune dépense cloud sans accord | sans objet | La CLI ne lance pas l'apply : l'utilisateur le fait lui-même (US-006) |

### Dérogations

Aucune.

## Condition de révision

La décision se rouvre si l'un de ces faits se vérifie :

- ADR-002 est remplacé par un moteur qui n'est pas écrit en Python, en particulier un outil distribué par npm ; BENCH-006 se rouvre avec cet ADR ;
- la licence de Python change, ou le modèle de gouvernance de la PEP 13 cesse de s'appliquer.

Deux faits ne la rouvrent pas. La fin de support du plancher fait monter le plancher (condition 2). Un changement chez uv ne touche que la documentation d'installation (condition 1). Sans l'un des faits ci-dessus, prochaine vérification au plus tard le 2027-05-19.

## Sources

Ce que BENCH-006 établit se cite par lui ; ses propres sources sont dans sa section 9.

| Source | Lue le | Ce qu'elle établit |
| --- | --- | --- |
| [BENCH-006](../benchmarks/BENCH-006-langage-cli.md), sections 1 à 3 | 2026-11-19 | Ce qui dépend du langage ; options étudiées et écartées ; critères éliminatoires ; exigences de Copier en Python et en Git |
| BENCH-006, sections 5 et 6 | 2026-11-19 | Notes et totaux ; gouvernance de la PSF et PEP 13 ; niveaux de support de CPython ; image des runners ; API de Copier ; installation de Claude Code |
| BENCH-006, sections 7 et 8 | 2026-11-19 | Sensibilité au moteur (égalité à 85 avec Yeoman) ; canal d'installation et uv ; fins de support de Python ; options de uv ; binaire autonome ; script de démarrage à écrire |
| BENCH-006, section 10 | 2026-11-19 | Avis de [SECU] et de [FINOPS] |
| [BENCH-002](../benchmarks/BENCH-002-moteur-templates.md), section 5.7 | 2026-11-19 | CI de Copier sous Python 3.11 à 3.15 |
| [docs/prd-mvp.md](../prd-mvp.md), US-001, US-003, US-004, US-006, US-011, ENF-01, ENF-07, Q5, Q10 | 2026-11-19 | Exigences qui dépendent du langage de la CLI ; systèmes visés ; maintien d'un BENCH-006 court |
| [docs/risques.md](../risques.md), R-13, R-24 | 2026-11-19 | CLI qui fonctionne seule ; uv porté par un éditeur unique |
