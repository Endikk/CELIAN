# BENCH-006. Langage de la CLI

| Champ | Valeur |
| --- | --- |
| Identifiant | BENCH-006 |
| Sujet | Langage de la CLI qui valide la spec, appelle le moteur de templates et lance les vérifications |
| Statut | relu |
| Ouvert le | 2026-11-19 |
| Mis à jour le | 2026-11-19 |
| Auteur | [BENCH] |
| Relecteurs | [SECU] pour les licences et les CVE, [FINOPS] pour les coûts |
| Périmètre | Générateur seul : la CLI sur le PC de l'utilisateur et dans la CI du générateur. Les projets générés ne dépendent pas de CELIAN (ENF-07) |
| Choix du PRD | « Langage de la CLI : Python, retenu dans la forme du produit », tranché par BENCH-006, en version courte (Q10) |
| ADR lié | À écrire par [ARCHI], numéro à attribuer |
| Verdict proposé | Python, 94/100, contre 76/100 pour TypeScript |

## 1. Contexte

[BENCH] La question : dans quel langage écrire la CLI de CELIAN, et comment l'utilisateur l'installe.

[BENCH] La CLI porte la partie déterministe du produit : validation de la spec, traduction par le catalogue, génération et vérifications (PRD, section 1). Le plugin Claude Code la pilote. Ce qui dépend du choix :

- US-001 : la commande d'entrée vérifie les prérequis, et chaque runtime exigé par la CLI en ajoute un à la liste ;
- US-003 et US-004 : la validation et la génération tournent avec la CLI seule, sans modèle de langage, dans la matrice de validation (principe I) ;
- US-011 : la mise à jour passe par `copier update` si BENCH-002 confirme Copier ;
- ENF-01 : chaque étape compte dans les 15 minutes ;
- les principes V (gouvernance ouverte) et VI (récent mais éprouvé) ;
- BENCH-002, en cours : Copier, pressenti, est une bibliothèque et une CLI écrites pour Python [S21]. BENCH-001 fixera le format de spec que la CLI valide.

[BENCH] Option pressentie : Python. Le brief l'inscrit dans la forme du produit, « Copier est écrit en Python » (section 4), et la constitution la reprend. Elle passe la même grille que TypeScript, sans avantage.

[BENCH] La grille vise des technos déployées. Pour un langage de CLI, elle se lit ainsi. La licence porte sur le compilateur ou l'interpréteur et sur le runtime. La gouvernance porte sur qui tient le langage et son runtime : la PSF pour Python, Microsoft pour TypeScript, l'OpenJS Foundation pour Node.js. L'empreinte sur PC devient ce qu'il faut installer pour lancer la CLI, plus le temps de démarrage d'une commande. La portabilité devient macOS et Linux, les systèmes retenus en Q5, Windows restant à évaluer. Le coût couvre le prix et le temps de maintenance.

[BENCH] Hors champ : le moteur de templates (BENCH-002), le format de la spec (BENCH-001), le cadriciel de ligne de commande et l'outillage de test de la CLI (choix de [DEV] en phase 5), le nom des commandes (phase 5) et Windows (Q5). Le langage des projets générés reste .NET et React.

## 2. Options étudiées

| Option | En une phrase | Version examinée | Publiée le | Sources |
| --- | --- | --- | --- | --- |
| Python (CPython) | Le langage de Copier : la CLI l'appellerait dans le même processus | 3.15.2 | 2026-10-25 | [S1] |
| TypeScript sur Node.js | Langage typé exécuté par Node.js : la CLI appellerait la commande `copier` en sous-processus | TypeScript 7.0.2, Node.js 26.13.1 LTS | 2026-08-20 et 2026-11-11 | [S10], [S17] |

[BENCH] Copier 9.19.1, publié le 2026-10-13 sous licence MIT, demande Python 3.10 ou plus et Git 2.27 ou plus [S21]. Tant que BENCH-002 le retient, il fait partie des deux options, et il n'est pas noté ici.

[BENCH] Le dépôt microsoft/typescript-go a servi au portage natif de TypeScript 7. Il passe en lecture seule, et le développement continue dans microsoft/TypeScript [S12]. Ce n'est pas une option distincte.

[BENCH] Options repérées mais non étudiées : Go et Rust. Le brief limite ce benchmark à deux options (section 8). Tout langage autre que Python appellerait Copier en sous-processus, avec Python installé à côté, comme TypeScript (section 5.6).

## 3. Critères éliminatoires

| Option | Licence open source | Ni archivé ni en maintenance | Release de moins de 12 mois | Vérifié le | Résultat |
| --- | --- | --- | --- | --- | --- |
| Python | Oui : licence de Python (PSF License version 2, BeOpen, CNRI, CWI), approuvée par l'OSI sous Python-2.0, catégorie Superseded ; la PSF License seule (SPDX PSF-2.0) n'est pas sur la liste de l'OSI [S3, S4, S34] | Oui : 3.15 et 3.14 en phase de correctifs, support jusqu'en 2031-10 et 2030-10 [S1, S2] | Oui, 3.15.2 le 2026-10-25 [S1] | 2026-11-19 | Retenue |
| TypeScript sur Node.js | Oui : TypeScript sous Apache-2.0, Node.js sous MIT, deux licences approuvées par l'OSI [S4, S9, S14] | Oui : dépôts non archivés, TypeScript 7.1 bêta le 2026-10-20, Node.js 26 en LTS [S9, S10, S16] | Oui, TypeScript 7.0.2 le 2026-08-20, Node.js 26.13.1 le 2026-11-11 [S10, S17] | 2026-11-19 | Retenue |

[BENCH] Options éliminées : aucune.

## 4. Mesures

[BENCH] Aucune mesure n'a été lancée. Le plan de la version courte (Q10) écarte toute mesure qu'aucun critère n'exige, et aucun ne l'exige ici. Ce qui départage l'empreinte, le nombre de runtimes à installer, se lit dans la documentation (section 5.6). Le temps de démarrage d'une commande se paie quelques fois par session, face à un budget de 15 minutes qui inclut le premier téléchargement des images (PRD, section 7). L'hypothèse d'un écart faible entre les deux langages n'est pas vérifiée : la section 8 donne le script qui lèverait ce doute.

## 5. Notation par critère

[BENCH] Chaque option retenue reçoit une note entière de 0 à 5 sur chaque critère.
Les points valent note × poids / 5. Un cran de note vaut donc 3 points sur un
critère de poids 15, 2 points sur un poids 10 et 1 point sur le coût. Les
poids sont ceux de la section 8 du brief et ne changent pas d'un rapport à
l'autre.

| Note | Sens |
| --- | --- |
| 5 | Répond pleinement au critère, preuve directe |
| 4 | Répond, avec une réserve mineure écrite |
| 3 | Répond en partie, la réserve demande une action |
| 2 | Répond mal, il faut contourner |
| 1 | Répond à peine |
| 0 | Ne répond pas |

### 5.1 Licence et liberté d'usage, poids 15

[BENCH] Ce critère ne départage pas : les deux options ont des licences permissives approuvées par l'OSI.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Python | 5/5 | 15 | Licence de Python, approuvée par l'OSI (Python-2.0), propriété intellectuelle détenue par la PSF depuis 2001. La CLI requiert l'interpréteur sans l'embarquer. | [S3, S5] |
| TypeScript sur Node.js | 5/5 | 15 | TypeScript sous Apache-2.0, la licence du générateur, et Node.js sous MIT. Aucun changement de licence relevé dans les pages lues. | [S4, S9, S14] |

### 5.2 Gouvernance (fondation, multi-vendeurs), poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Python | 5/5 | 15 | La PSF, fondation à but non lucratif, détient la propriété intellectuelle. Les développeurs du noyau élisent un comité de pilotage de cinq membres après chaque version majeure, et deux membres au plus peuvent avoir le même employeur. | [S3, S6] |
| TypeScript sur Node.js | 3/5 | 9 | Node.js est un projet « Impact » de l'OpenJS Foundation, à gouvernance ouverte. Le compilateur TypeScript reste à Microsoft seule : dépôts de l'organisation microsoft, aucune fondation, absent de la liste de l'OpenJS. Il faudrait un ADR pour justifier l'écart au principe V. | [S9, S12, S14, S15] |

### 5.3 Maturité et adoption, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Python | 5/5 | 15 | Créé au début des années 1990. Chaque version reçoit cinq ans de support, dont deux de correctifs complets. Copier est une CLI Python, et specify-cli, déjà utilisé pour CELIAN, s'installe comme paquet Python avec `uv tool install`. | [S2, S3, S21, S24, S31] |
| TypeScript sur Node.js | 4/5 | 12 | Une LTS de Node.js reçoit en général 30 mois de correctifs. Réserve : le compilateur 7.0, annoncé le 2026-07-08, est une réécriture en Go livrée sans API programmatique, et les outils qui embarquent TypeScript restent sur 6.0 pour l'instant. Une CLI n'a pas besoin de cette API, mais la chaîne de compilation est neuve (principe VI). | [S11, S16] |

### 5.4 Activité et maintenance, poids 10

[BENCH] Ce critère ne départage pas : les deux options publient plusieurs versions par trimestre.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Python | 5/5 | 10 | 3.15.0 le 2026-10-09, puis 3.15.1 et 3.15.2 en octobre. Des binaires sortent environ tous les deux mois. | [S1, S2] |
| TypeScript sur Node.js | 5/5 | 10 | TypeScript 6.0 en mars 2026, 7.0 en juillet, 7.1 bêta le 2026-10-20. Node.js 26.13.1 le 2026-11-11. | [S10, S17, S33] |

### 5.5 Sécurité (CVE, réactivité), poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Python | 4/5 | 8 | Une équipe de réponse dédiée (PSRT), la PSF autorité de numérotation CVE, des avis publiés sur une liste publique et au format OSV. Une seule chaîne de paquets, PyPI. Réserves : aucun délai de réponse publié ; l'installation depuis PyPI exécute aussi du code quand elle construit une distribution source (« build backends may run arbitrary Python code »). Parade à évaluer par [DEV] : `--no-build`, si toutes les dépendances publient des roues. | [S7, S36] |
| TypeScript sur Node.js | 3/5 | 6 | Réponse sous 24 h promise par le MSRC pour TypeScript, accusé de réception sous 5 jours pour Node.js. Mais l'option cumule deux runtimes et deux registres, npm pour la CLI et PyPI pour Copier. `npm install` lance les scripts d'installation des paquets, le vecteur du ver Shai-Hulud en septembre 2025. Un registre compromis menace aussi PyPI : l'écart vient du cumul. | [S13, S18, S21, S29, S30] |

### 5.6 Empreinte sur PC (RAM, CPU, démarrage), poids 10

[BENCH] Sans mesure (section 4), la note porte sur ce qu'il faut installer pour lancer la CLI.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Python | 4/5 | 8 | Un seul runtime, celui que Copier exige déjà, avec Git. uv télécharge l'interpréteur s'il manque, et `uvx` lance la CLI dans un environnement isolé, sans installation globale. Réserve : temps de démarrage non mesuré. | [S21, S24, S25] |
| TypeScript sur Node.js | 2/5 | 4 | Node.js s'ajoute à Python et Git, que Copier exige toujours. Claude Code s'installe sans l'un ni l'autre, donc US-001 aurait deux runtimes à faire installer et à diagnostiquer. | [S21, S23] |

### 5.7 Portabilité multi-cloud, poids 10

[BENCH] Un langage de CLI n'a pas de cible cloud : le critère se lit sur les systèmes de Q5. Il ne départage pas.

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Python | 5/5 | 10 | macOS Apple Silicon, Linux x64 et Linux arm64 au niveau 1 de support de CPython, macOS Intel au niveau 2. | [S8] |
| TypeScript sur Node.js | 5/5 | 10 | Node.js 26 : macOS arm64, Linux x64 et Linux arm64 au niveau 1, macOS x64 au niveau 2 jusqu'au début de 2028. | [S19] |

### 5.8 Expérience dev et documentation, poids 10

[BENCH] Note de jugement, fondée sur la documentation, sans essai sur machine : cette version courte exclut toute installation (section 8).

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Python | 4/5 | 8 | La CLI appelle Copier dans le même processus, par `run_copy` et `run_update`, et reçoit ses exceptions Python. Elle peut se lancer depuis une étiquette Git figée, avec `uvx --from git+<URL du dépôt>@<tag> <commande>`. Réserve : le typage reste optionnel, un vérificateur de types en CI est à choisir par [DEV]. | [S22, S24] |
| TypeScript sur Node.js | 3/5 | 6 | Typage natif, et Node.js exécute le TypeScript effaçable sans étape de build, fonction stable depuis 24.12.0 et 25.2.0, mais sans vérifier les types. Mais l'API de Copier est en Python : depuis Node.js, il reste la commande `copier` en sous-processus, avec une sortie texte et des codes de retour à interpréter. Le rôle [DEV] couvre déjà TypeScript pour le front généré. | [S20, S21, S22, S31] |

### 5.9 Coût (managé ou opérationnel), poids 5

[BENCH] Ce critère compte le temps des mainteneurs de CELIAN, qu'aucun autre ne compte : la sécurité mesure la surface des registres, l'empreinte ce que l'utilisateur installe. Note de TypeScript corrigée de 5 à 4 après la relecture [FINOPS] (section 10).

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Python | 5/5 | 5 | Licence sans redevance. Une seule chaîne d'outils en CI, un fichier de verrouillage, un flux Renovate. L'image Ubuntu 24.04 des runners GitHub (20261111.370.1) a Python 3.15.2 en cache et pipx 1.16.7 installé. | [S5, S35] |
| TypeScript sur Node.js | 4/5 | 4 | Licences sans redevance, mais deux chaînes d'outils en CI, deux fichiers de verrouillage, deux flux Renovate et deux runtimes à suivre. La même image n'a pas Node.js 26, seulement 22.23.4 et 24.22.2. | [S4, S35] |

## 6. Grille pondérée

| Critère | Poids | Python | TypeScript sur Node.js |
| --- | --- | --- | --- |
| Critères éliminatoires (section 3) | éliminatoire | passe | passe |
| Licence et liberté d'usage | 15 | 5/5, 15 pts | 5/5, 15 pts |
| Gouvernance (fondation, multi-vendeurs) | 15 | 5/5, 15 pts | 3/5, 9 pts |
| Maturité et adoption | 15 | 5/5, 15 pts | 4/5, 12 pts |
| Activité et maintenance | 10 | 5/5, 10 pts | 5/5, 10 pts |
| Sécurité (CVE, réactivité) | 10 | 4/5, 8 pts | 3/5, 6 pts |
| Empreinte sur PC (RAM, CPU, démarrage) | 10 | 4/5, 8 pts | 2/5, 4 pts |
| Portabilité multi-cloud | 10 | 5/5, 10 pts | 5/5, 10 pts |
| Expérience dev et documentation | 10 | 4/5, 8 pts | 3/5, 6 pts |
| Coût (managé ou opérationnel) | 5 | 5/5, 5 pts | 4/5, 4 pts |
| Total | 100 | 94 / 100 | 76 / 100 |

## 7. Verdict proposé

[BENCH] Python, avec 94/100, devance TypeScript sur Node.js, à 76/100, de 18 points.

[BENCH] Pourquoi. Copier est une bibliothèque Python [S21, S22]. Choisir TypeScript ajoute Node.js sans retirer Python : deux runtimes en prérequis pour US-001, deux registres de paquets à surveiller, deux chaînes d'outils à maintenir, et Copier appelé par sa commande au lieu de son API (sections 5.5, 5.6, 5.8 et 5.9). La gouvernance creuse l'écart : une fondation et un comité élu, à employeurs plafonnés, pour Python [S3, S6], un compilateur tenu par Microsoft seule pour TypeScript [S9, S12]. Trois critères donnent la même note aux deux options.

[BENCH] Sensibilité. Aucun cran isolé ne renverse le classement : un cran vaut au plus 3 points, six crans ne feraient qu'égaliser, il en faudrait sept. Le verdict repose en revanche sur une hypothèse, celle d'un moteur de templates écrit en Python. Si BENCH-002 retenait Yeoman, qui s'installe par npm [S32], les notes d'empreinte, de sécurité, d'expérience dev et de coût s'échangeraient entre les deux options. Calcul fait sur cette hypothèse : égalité à 85, l'avance de Python en gouvernance et en maturité compensant tout juste ses pertes. Dans ce cas, BENCH-006 se rouvre.

[BENCH] Gouvernance du canal d'installation. Le langage est porté par une fondation, l'écart au principe V ne se pose donc pas pour lui. Il se pose pour uv, le chemin le plus court vers la CLI : un éditeur unique, Astral, qui a annoncé le 2026-03-19 rejoindre OpenAI et continuer à soutenir ses outils open source [S26, S27]. Avec uv, l'interpréteur vient aussi d'Astral, par son projet python-build-standalone [S25]. Parade proposée : publier la CLI comme un paquet Python standard, installable aussi par pipx, dont le dépôt appartient à l'organisation PyPA [S28], et ne jamais faire d'uv une dépendance de la CLI elle-même. La parade couvre l'interpréteur : Python de python.org ou de la distribution, et l'option `--no-python-downloads` pour qui garde uv [S25, S36].

[BENCH] Réserves. Copier accepte encore Python 3.10 [S21], en fin de vie depuis le 2026-10-01 [S1]. La CLI doit exiger une version supportée : 3.11 sort du support en 2027-10, 3.12 en 2028-10 [S1]. [DEV] et [ARCHI] fixent ce plancher. Le temps de démarrage reste à mesurer. L'issue de l'accord entre Astral et OpenAI est à suivre. Prochaine vérification : à la clôture de BENCH-002, puis au plus tard le 2027-05-19.

[BENCH] Suites. [ARCHI] écrit l'ADR, qui cite ce rapport et sa dépendance à BENCH-002. Aucune entrée de `catalog/` à créer : la CLI n'est pas une brique des projets générés. En phase 5, [DEV] fixe le mode d'installation de US-001 (uv seul en prérequis, ou Python et pipx) et le plancher de version dans la configuration du paquet. Il évalue aussi deux options de uv [S36]. `uv tool run --exclude-newer "7 days"` applique à l'installation de la CLI la règle des 7 jours du principe VI ; en contrepartie, un correctif publié depuis moins de 7 jours n'est pas pris, et `--exclude-newer-package` permet une exception par paquet. `--no-build` refuse les distributions sources (section 5.5). Si [DEV] choisit un jour un binaire autonome qui embarque CPython, il joint les avis de licence de Python et de ses composants tiers, et [SECU] relit à nouveau. Pour `docs/risques.md`, le DSI décide d'ouvrir ou non un risque « canal d'installation tenu par un éditeur unique (uv) », de probabilité faible.

## 8. Limites et biais

| Limite | Effet possible sur le verdict | Ce qui la lèverait |
| --- | --- | --- |
| Temps de démarrage non mesuré | Un import lent de Copier pèserait sur chaque commande. Python perdrait au plus un cran d'empreinte, soit 2 points, sans changer le classement | Un script `tests/bench/bench-006-startup.sh` qui chronomètre `--version` sur un prototype dans chaque langage, trois exécutions, quand [DEV] aura un squelette |
| Expérience dev notée sans essai, installation exclue de cette version courte | Les notes 4 et 3 peuvent bouger d'un cran | Un prototype minimal qui appelle Copier depuis chaque langage |
| Verdict conditionné à BENCH-002, en cours | Renversement possible avec un moteur pour Node.js (section 7) | Rouvrir BENCH-006 si BENCH-002 ne retient pas un moteur écrit en Python |
| Option pressentie par le brief et la constitution | Biais de confirmation | Même grille pour les deux options ; l'argument décisif, Copier écrit pour Python, est un fait sourcé [S21] ; relu par [SECU], avis favorable |
| Gouvernance de TypeScript lue sur les pages des dépôts, sans statistiques de contribution | La note 3 peut être sévère ou généreuse d'un cran | Lire le guide de contribution et les statistiques de contributeurs du dépôt |

## 9. Sources

[BENCH] Toutes lues le 2026-11-19.

| ID | URL | Lue le | Ce que la source établit | Officielle |
| --- | --- | --- | --- | --- |
| S1 | <https://www.python.org/downloads/> | 2026-11-19 | Python 3.15.2 le 2026-10-25, 3.15.0 le 2026-10-09 ; fin de support de 3.10 (2026-10-01), 3.11 (2027-10), 3.12 (2028-10), 3.14 (2030-10), 3.15 (2031-10) | Oui |
| S2 | <https://devguide.python.org/versions/> | 2026-11-19 | Phases de support, binaires environ tous les deux mois, correctifs de sécurité seuls après deux ans, fin de support à cinq ans | Oui |
| S3 | <https://docs.python.org/3/license.html> | 2026-11-19 | PSF License version 2, PSF propriétaire de la propriété intellectuelle depuis 2001, création au début des années 1990 au CWI | Oui |
| S4 | <https://opensource.org/licenses> | 2026-11-19 | Python-2.0 (catégorie Superseded), Apache-2.0 et MIT approuvées par l'OSI ; aucune entrée PSF-2.0 | Oui |
| S5 | <https://opensource.org/license/python-2-0> | 2026-11-19 | Licence Python-2.0 approuvée par l'OSI, PSF comme gardienne | Oui |
| S6 | <https://peps.python.org/pep-0013/> | 2026-11-19 | Comité de pilotage de cinq membres, élu après chaque version majeure, deux membres au plus par employeur | Oui |
| S7 | <https://www.python.org/dev/security/> | 2026-11-19 | PSRT, PSF autorité de numérotation CVE, avis publiés sur liste publique et au format OSV, aucun délai de réponse annoncé | Oui |
| S8 | <https://peps.python.org/pep-0011/> | 2026-11-19 | Niveaux de support de CPython : aarch64-apple-darwin et Linux x86_64 et aarch64 au niveau 1, x86_64-apple-darwin au niveau 2 | Oui |
| S9 | <https://github.com/microsoft/TypeScript> | 2026-11-19 | Licence Apache-2.0, dépôt non archivé, organisation microsoft | Oui |
| S10 | <https://github.com/microsoft/TypeScript/releases> | 2026-11-19 | TypeScript 7.0.2 marqué Latest le 2026-08-20, 7.1 bêta le 2026-10-20, 6.0 en mars 2026 | Oui |
| S11 | <https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/> | 2026-11-19 | 7.0 annoncé le 2026-07-08, portage natif en Go, aucune API dans 7.0, outils embarqués restés sur 6.0 | Oui |
| S12 | <https://github.com/microsoft/typescript-go> | 2026-11-19 | Dépôt de préparation du portage, passé en lecture seule, Apache-2.0, organisation microsoft, aucune fondation citée | Oui |
| S13 | <https://github.com/microsoft/TypeScript/blob/main/SECURITY.md> | 2026-11-19 | Signalement au MSRC, réponse annoncée sous 24 h | Oui |
| S14 | <https://github.com/nodejs/node> | 2026-11-19 | Licence MIT, soutien de l'OpenJS Foundation, gouvernance ouverte avec un comité technique | Oui |
| S15 | <https://openjsf.org/projects> | 2026-11-19 | Node.js projet « Impact » de l'OpenJS Foundation, TypeScript absent de la liste | Oui |
| S16 | <https://nodejs.org/en/about/previous-releases> | 2026-11-19 | Node.js 26 en LTS, LTS de 30 mois, cycle annuel à partir de Node.js 27 | Oui |
| S17 | <https://github.com/nodejs/node/releases> | 2026-11-19 | Node.js 26.13.1 « Lithium » le 2026-11-11, version de sécurité | Oui |
| S18 | <https://github.com/nodejs/node/blob/main/SECURITY.md> | 2026-11-19 | Signalement par HackerOne, accusé de réception sous 5 jours, embargo puis avis public | Oui |
| S19 | <https://github.com/nodejs/node/blob/v26.x/BUILDING.md> | 2026-11-19 | Node.js 26 : macOS arm64, Linux x64 et arm64 au niveau 1, macOS x64 au niveau 2 jusqu'au début de 2028 | Oui |
| S20 | <https://nodejs.org/api/typescript.html> | 2026-11-19 | Exécution du TypeScript effaçable stable depuis 24.12.0 et 25.2.0, sans vérification de types, enums refusés | Oui |
| S21 | <https://pypi.org/project/copier/> | 2026-11-19 | Copier 9.19.1 le 2026-10-13, MIT, Python 3.10 ou plus, Git 2.27 ou plus, bibliothèque et CLI, installation par pipx ou `uv tool install` | Oui |
| S22 | <https://copier.readthedocs.io/en/stable/reference/api/> | 2026-11-19 | API Python : `run_copy`, `run_recopy`, `run_update`, qui rendent un `Worker` | Oui |
| S23 | <https://code.claude.com/docs/en/setup> | 2026-11-19 | Installateur natif de Claude Code sans Node.js ; le paquet npm demande Node.js 22, mais le binaire ne l'utilise pas ; Git optionnel | Oui |
| S24 | <https://docs.astral.sh/uv/guides/tools/> | 2026-11-19 | `uvx` lance un outil dans un environnement isolé, `uv tool install` l'installe, source Git figeable sur une étiquette ou un commit | Oui |
| S25 | <https://docs.astral.sh/uv/concepts/python-versions/> | 2026-11-19 | uv télécharge Python s'il est absent, sur macOS, Linux et Windows, depuis le projet python-build-standalone d'Astral ; `--no-python-downloads` et le réglage `python-downloads` limitent ces téléchargements | Oui |
| S26 | <https://github.com/astral-sh/uv> | 2026-11-19 | uv sous Apache-2.0 ou MIT, développé par Astral, macOS, Linux et Windows | Oui |
| S27 | <https://astral.sh/blog/openai> | 2026-11-19 | Annonce du 2026-03-19 : Astral rejoint OpenAI et continue de soutenir ses outils open source | Oui |
| S28 | <https://github.com/pypa/pipx> | 2026-11-19 | pipx installe des applications Python isolées, MIT, dépôt de l'organisation PyPA | Oui |
| S29 | <https://docs.npmjs.com/cli/v11/using-npm/scripts> | 2026-11-19 | `npm install`, y compris en global, lance les scripts `preinstall`, `install` et `postinstall` des paquets (npm 11.21.2) | Oui |
| S30 | <https://github.blog/security/supply-chain-security/our-plan-for-a-more-secure-npm-supply-chain/> | 2026-11-19 | Ver Shai-Hulud signalé le 2025-09-14, propagé par des scripts post-installation, plan de GitHub pour npm | Oui, GitHub gère npm |
| S31 | [docs/brief-v1.0.md](../brief-v1.0.md) | 2026-11-19 | Section 1 : le rôle [DEV] couvre la CLI et TypeScript ; section 4 : CLI Python ; section 7.1 : `uv tool install specify-cli` | Non, document interne |
| S32 | <https://github.com/yeoman/yo> | 2026-11-19 | `yo` s'installe par `npm install --global yo`, projet JavaScript pour Node.js | Oui |
| S33 | <https://devblogs.microsoft.com/typescript/> | 2026-11-19 | Annonces de TypeScript 6.0 le 2026-03-23, 7.0 le 2026-07-08, 7.1 bêta le 2026-10-20 | Oui |
| S34 | <https://spdx.org/licenses/> | 2026-11-19 | Liste SPDX 3.29.0 du 2026-09-16 : Python-2.0 marquée approuvée par l'OSI, PSF-2.0 sans cette mention | Oui |
| S35 | <https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md> | 2026-11-19 | Image Ubuntu 24.04 20261111.370.1 : Python 3.11 à 3.15.2 en cache, pipx 1.16.7, Node.js 22.23.4 et 24.22.2 en cache, pas de Node.js 26 | Oui |
| S36 | <https://docs.astral.sh/uv/reference/cli/> | 2026-11-19 | `uv tool run` : options `--exclude-newer`, qui accepte une durée comme « 30 days », `--exclude-newer-package`, `--no-build` et `--no-python-downloads` ; les backends de construction « may run arbitrary Python code » | Oui |

## 10. Relectures

| Relecteur | Porte sur | Date | Avis |
| --- | --- | --- | --- |
| [SECU] | Licences, critères éliminatoires, sécurité | 2026-11-19 | Favorable |
| [FINOPS] | Coût | 2026-11-19 | Réservé, levé par la correction de la note 5.9 |

[SECU] Aucune note à changer. Cinq remarques, toutes intégrées. La cellule licence de Python (section 3) précise la pile de licences, la catégorie Superseded de l'OSI et l'absence de PSF-2.0 sur sa liste ; la limite correspondante sort de la section 8. La section 5.5 note, pour l'équilibre, que l'installation depuis PyPI exécute aussi du code quand elle construit une distribution source, avec `--no-build` comme parade à évaluer. Le paragraphe sur le canal d'installation (section 7) étend la parade pipx à l'interpréteur, qu'uv tire de python-build-standalone. Les suites citent `--exclude-newer "7 days"` et son exception par paquet, et la règle des avis de licence pour un éventuel binaire autonome.

[FINOPS] Le temps des mainteneurs n'était compté dans aucun critère : la section 5.9 l'écartait comme déjà compté, alors que 5.5 et 5.6 portent sur autre chose. Avec TypeScript, il faudrait tenir deux chaînes d'outils en CI, deux fichiers de verrouillage, deux flux Renovate et deux runtimes, et l'image Ubuntu 24.04 des runners n'a pas Node.js 26 [S35]. Suite donnée : coût de TypeScript passé de 5/5 à 4/5, total de 77 à 76, écart de 17 à 18 points ; grille, verdict, sensibilité et en-tête mis à jour.
