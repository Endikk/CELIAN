# BENCH-002. Moteur de templates

| Champ | Valeur |
| --- | --- |
| Identifiant | BENCH-002 |
| Sujet | Moteur qui génère le dépôt depuis le blueprint et le met à jour ensuite |
| Statut | brouillon |
| Ouvert le | 2026-11-19 |
| Mis à jour le | 2026-11-19 |
| Auteur | [BENCH] |
| Relecteurs | [SECU] pour les licences et les CVE, [FINOPS] pour les coûts |
| Périmètre | Générateur (CLI Python) et mise à jour des projets générés. Le moteur tourne sur le poste qui génère : les cibles PC et GCP ne le voient pas |
| Choix du PRD | Moteur de templates, option pressentie Copier (`docs/prd-mvp.md`, section 1) |
| ADR lié | À écrire par [ARCHI], numéro à attribuer |
| Verdict proposé | Copier, 82/100. Seule option qui passe les critères éliminatoires et le prérequis du jour 2 |

## 1. Contexte

[BENCH] Question posée : quel moteur de templates la CLI de CELIAN utilise pour
générer un dépôt depuis le blueprint SaaS B2B, puis pour le mettre à jour quand
le blueprint évolue.

[BENCH] Ce qui en dépend. US-004 demande que deux générations depuis la même
spec et la même version du blueprint donnent une partie déterministe identique,
fichier par fichier. US-011 demande qu'un projet généré en version N reçoive la
version N+1 sans repasser par l'entretien, que les modifications de
l'utilisateur soient conservées hors conflit et que les conflits soient listés
fichier par fichier ; la matrice de la phase 4 couvre ce passage de N à N+1.
ENF-07 veut un projet généré qui fonctionne sans CELIAN, seule la mise à jour
demandant le moteur. ENF-06 veut que le dépôt enregistre la version du
blueprint qui l'a produit. Côté constitution : principes I (tout est testé),
V (gouvernance ouverte), VI (récent mais éprouvé) et VIII (aucun fait de
mémoire). Côté risques : R-11 (conflits de mise à jour) et R-22 (jour 2
dépendant d'un seul outil communautaire).

[BENCH] Prérequis du jour 2. La grille de la section 8 du brief ne contient
pas la mise à jour, qui est pourtant une exigence fonctionnelle du MVP
(US-011). Elle est traitée ici comme un prérequis : une option qui ne sait pas
mettre à jour un projet généré vers une nouvelle version du gabarit, en gardant
les modifications locales, est éliminée pour cette raison. Pour Cookiecutter,
la mise à jour passe par un outil tiers, cruft, auquel s'appliquent aussi les
critères éliminatoires. Le prérequis est vérifié par un essai pratique (M4),
lancé trois fois.

[BENCH] Option pressentie par le PRD : Copier. Elle est notée comme les
autres, avec les mêmes sources et le même essai.

[BENCH] Hors champ : la découpe du blueprint entre socle et code de l'équipe
(mitigation de R-11, phase 3), l'usage des tâches et migrations de Copier dans
le blueprint, le langage de la CLI (BENCH-006) et la matrice de la phase 4.

## 2. Options étudiées

| Option | En une phrase | Version examinée | Publiée le | Sources |
| --- | --- | --- | --- | --- |
| Copier | Bibliothèque et CLI Python de rendu de gabarits, avec `copier update` intégré | 9.19.1 | 2026-10-13 | [S1], [S2] |
| Cookiecutter | Générateur Python de projets depuis un gabarit, sans mise à jour ; cruft 2.16.0 (2024-12-25) apporte `cruft update` | 2.7.1 | 2026-03-04 | [S17], [S18], [S20], [S21] |
| Yeoman | Générateur Node.js : la CLI `yo` lance des générateurs écrits avec `yeoman-generator`. Demande Node.js, absent de la pile Python de la CLI | yo 7.0.1 ; yeoman-generator 10.3.1 | 2026-04-09 ; 2026-11-16 | [S22], [S23], [S24], [S27], [S28] |

[BENCH] Options repérées mais non étudiées. JHipster et les modèles
`dotnet new` ont été écartés par l'analyse des outils existants du 2026-11-15
(sections 4.8 et 4.9 de `analyse-outils-existants.md`) : le premier n'a plus de
blueprint .NET publié depuis plus de 12 mois, les seconds ne décrivent aucune
mise à jour. Le mécanisme de mise à jour de JHipster (une branche qui reçoit le
gabarit régénéré, puis une fusion Git) est le repli prévu par R-22. Il a été
essayé à titre de référence (M4), sans être noté.

## 3. Critères éliminatoires

[BENCH] Seuil de release : 2025-11-19, douze mois avant la vérification. La
dernière colonne applique le prérequis du jour 2 posé à la section 1.

| Option | Licence open source | Ni archivé ni en maintenance | Release de moins de 12 mois | Jour 2 (prérequis US-011) | Vérifié le | Résultat |
| --- | --- | --- | --- | --- | --- | --- |
| Copier | Oui, MIT [S1], approuvée OSI [S29] | Oui, dépôt non archivé, dernier commit le 2026-11-06 [S1], [S9] | Oui, 9.19.1 le 2026-10-13 [S2] | Oui : fusion propre, conflit signalé, 3 exécutions sur 3 [M4] | 2026-11-19 | Retenue |
| Cookiecutter seul | Oui, BSD-3-Clause [S17], approuvée OSI [S29] | Oui, dépôt non archivé [S17] | Oui, 2.7.1 le 2026-03-04 [S18] | Non : aucune commande de mise à jour [S19]. Régénérer avec `-f` écrase en silence, avec `-s` ignore en silence [M4] | 2026-11-19 | Éliminée (jour 2) |
| cruft, jour 2 de Cookiecutter | Oui, MIT [S20], approuvée OSI [S29] | Dépôt non archivé [S20], mais aucun commit depuis le 2024-12-25 [S21] | Non, 2.16.0 le 2024-12-25 [S21] | Oui sur le plan technique [M4] | 2026-11-19 | Éliminé (release) |
| Yeoman | Oui, BSD-2-Clause pour `yo` et `yeoman-generator` [S22], [S24], approuvée OSI [S29] | Oui, dépôts non archivés [S22], [S24] | Oui, yo 7.0.1 le 2026-04-09 [S23], yeoman-generator 10.3.1 le 2026-11-16 [S24] | Non : chaque fichier existant se garde ou s'écrase, sans fusion [S25], [S26]. `--force` écrase en silence, sans `--force` l'exécution échoue en mode non interactif [M4] | 2026-11-19 | Éliminée (jour 2) |

[BENCH] Cookiecutter est éliminé pour le jour 2. Seul, il ne sait pas mettre
à jour un projet [S19], et l'essai le confirme : sans option il refuse le
dossier existant, avec `--overwrite-if-exists` il écrase les deux
modifications locales sans rien signaler, avec `--skip-if-file-exists` il
garde tout et n'applique aucun changement du gabarit, même sur le fichier non
touché [M4]. Son outil de mise à jour, cruft, fusionne correctement [M4] mais
n'a publié aucune release depuis le 2024-12-25 [S21] : il tombe sous le
critère de release, et le jour 2 de Cookiecutter avec lui.

[BENCH] Yeoman est éliminé pour le jour 2. Sa documentation prévoit que chaque
écriture sur un fichier existant passe par une résolution de conflit que
l'utilisateur valide fichier par fichier [S25]. Les choix offerts sont écraser,
ne pas écraser, tout écraser, voir la différence, recharger, éditer, ignorer ou
abandonner [S26] : aucun ne fusionne. En mode non interactif, cas d'un agent ou d'une CI,
l'essai donne soit un échec (code 1, rien d'écrit), soit avec `--force` un
écrasement silencieux des modifications locales [M4].

[BENCH] Il ne reste qu'une option. Le gabarit des benchmarks demande de le
signaler au DSI avant de continuer : c'est fait dans le compte rendu de ce
rapport. La notation qui suit porte sur Copier seul, et le résultat principal
de ce benchmark tient dans les éliminations.

## 4. Mesures

### 4.1 Ce qui est mesuré

| ID | Mesure | Unité | Critère alimenté | Script |
| --- | --- | --- | --- | --- |
| M1 | Deux générations depuis les mêmes entrées donnent des fichiers identiques | oui ou non | Prérequis US-004, expérience dev | `tests/bench/bench-002-day2.sh` |
| M2 | Temps d'une génération du gabarit jouet, lanceur `uvx` ou `npx` compris | s | Empreinte sur PC | `tests/bench/bench-002-day2.sh` |
| M3 | Mémoire résidente maximale pendant cette génération | Mio | Empreinte sur PC | `tests/bench/bench-002-day2.sh` |
| M4 | Sort de chaque fichier après une mise à jour de v1 vers v2, sur un projet modifié localement | catégorie | Prérequis US-011, expérience dev | `tests/bench/bench-002-day2.sh` |

### 4.2 Machine de mesure

| Élément | Valeur |
| --- | --- |
| Modèle | Apple Mac16,7 |
| Processeur | Apple M4 Pro, 14 cœurs |
| Mémoire | 24 Gio |
| Système | macOS 27.2.1 (build 26B131) |
| Moteur de conteneurs | Sans objet : aucun conteneur |
| Ressources allouées | Sans objet |
| Versions mesurées | Copier 9.19.1, Cookiecutter 2.7.1, cruft 2.16.0, yo 7.0.1 (qui résout yeoman-environment 6.3.0), yeoman-generator 10.3.1, figées dans le script. Outils : uv 0.12.23, Python 3.13.15, Node.js 25.2.1, npm 11.12.1, Git 2.54.0 |
| Charge parasite | D'autres agents travaillaient en parallèle dans d'autres worktrees. Charge moyenne relevée par `uptime` entre 4,6 et 5,2 pendant les mesures |

### 4.3 Protocole

1. État de départ : chaque exécution supprime son dossier `run-N`, reconstruit
   les gabarits jouets v1 et v2 depuis `tests/bench/bench-002/` (dépôts Git
   étiquetés `v1` et `v2` pour Copier et Cookiecutter, un dossier de
   générateur par version pour Yeoman) et repart de projets vides. Git est
   isolé de la configuration de l'utilisateur. Les caches `uv` et `npm` sont
   chauds : le script lance chaque outil une fois avant de mesurer.
2. Génération (M1, M2, M3) : chaque outil génère le projet v1 deux fois dans
   deux dossiers. La première génération passe sous `/usr/bin/time -l -p`,
   puis `diff -r` compare les deux copies, dossier `.git` exclu.
3. Jour 2 (M4) : pour chaque variante, un projet v1 neuf est versionné dans
   Git, puis modifié et commité. `app.conf` change `port` de 8080 à 9090 ;
   `pipeline.yml` change `runner` de `small` à `large` ; `local-notes.txt` est
   ajouté. La version 2 du gabarit change `log_format` dans `app.conf` (cinq
   lignes plus bas que la modification locale), la ligne `runner` de
   `pipeline.yml` (même ligne), et `NOTICE.txt`, que l'utilisateur n'a pas
   touché. Puis la variante met le projet à jour vers v2.
4. Relevé : le script classe chaque fichier d'après son contenu (fusion
   propre, conflit signalé par marqueurs ou fichier `.rej`, écrasement
   silencieux, changement du gabarit ignoré), relève le code de sortie et la
   liste des fichiers que Git marque non fusionnés.
5. Trois exécutions complètes, enchaînées sans pause, le 2026-11-19 entre
   00:40:03 et 00:40:42 UTC.

[BENCH] Variantes de mise à jour essayées : `copier update --defaults
--vcs-ref v2 --conflict inline` ; `cruft update --checkout v2
--skip-apply-ask` ; Cookiecutter relancé sur le projet existant sans option,
avec `--overwrite-if-exists`, et avec `--overwrite-if-exists
--skip-if-file-exists` ; Yeoman relancé avec le générateur v2, entrée
standard lue dans `/dev/null`, sans option puis avec `--force` ; le repli R-22, hors
options : Cookiecutter régénère v2 sur une branche `template` partie du commit
de génération, puis `git merge` la fusionne dans `main`.

Pour refaire la mesure :

```bash
tests/bench/bench-002-day2.sh /chemin/vers/un/dossier/vide
```

### 4.4 Résultats

[BENCH] Mesures lancées le 2026-11-19, sur la machine de la section 4.2. Les
options éliminées sont mesurées à titre indicatif et ne sont pas notées.
L'écart de M3 est calculé sur les valeurs brutes en Kio.

| Mesure | Option | Exécution 1 | Exécution 2 | Exécution 3 | Médiane | Écart |
| --- | --- | --- | --- | --- | --- | --- |
| M1 | Copier | identique | identique | identique | identique | aucun |
| M1 | Cookiecutter | identique | identique | identique | identique | aucun |
| M1 | cruft | identique | identique | identique | identique | aucun |
| M1 | Yeoman | identique | identique | identique | identique | aucun |
| M2 | Copier | 0,48 s | 0,48 s | 0,48 s | 0,48 s | 0,00 s |
| M2 | Cookiecutter | 0,19 s | 0,20 s | 0,19 s | 0,19 s | 0,01 s |
| M2 | cruft | 0,27 s | 0,27 s | 0,27 s | 0,27 s | 0,00 s |
| M2 | Yeoman | 0,78 s | 0,74 s | 0,76 s | 0,76 s | 0,04 s |
| M3 | Copier | 54,8 Mio | 54,4 Mio | 54,4 Mio | 54,4 Mio | 0,4 Mio |
| M3 | Cookiecutter | 43,8 Mio | 43,8 Mio | 43,8 Mio | 43,8 Mio | 0,1 Mio |
| M3 | cruft | 48,5 Mio | 48,3 Mio | 48,7 Mio | 48,5 Mio | 0,3 Mio |
| M3 | Yeoman | 167,3 Mio | 167,0 Mio | 162,1 Mio | 167,0 Mio | 5,3 Mio |

[BENCH] M4, sort de chaque fichier après la mise à jour. Les trois exécutions
donnent exactement le même résultat pour chaque variante.

| Variante | Code de sortie | `app.conf` (touché loin du changement) | `pipeline.yml` (touché sur la même ligne) | `NOTICE.txt` (non touché) | `local-notes.txt` (ajouté) | Non fusionnés selon Git |
| --- | --- | --- | --- | --- | --- | --- |
| Copier | 0 | fusion propre | conflit signalé, marqueurs dans le fichier | changement appliqué | conservé | `pipeline.yml` |
| Cookiecutter, sans option | 1, dossier existant | rien d'appliqué | rien d'appliqué | non appliqué | conservé | aucun |
| Cookiecutter, `--overwrite-if-exists` | 0 | écrasement silencieux | écrasement silencieux | changement appliqué | conservé | aucun |
| Cookiecutter, `--overwrite-if-exists --skip-if-file-exists` | 0 | changement du gabarit ignoré | changement du gabarit ignoré | non appliqué | conservé | aucun |
| cruft | 0 | fusion propre | conflit signalé, marqueurs dans le fichier | changement appliqué | conservé | `pipeline.yml` |
| Yeoman, sans option | 1, invite interrompue | rien d'appliqué | rien d'appliqué | non appliqué | conservé | aucun |
| Yeoman, `--force` | 0 | écrasement silencieux | écrasement silencieux | changement appliqué | conservé | aucun |
| Repli R-22, hors options | 1, conflit de fusion | fusion propre | conflit signalé, marqueurs dans le fichier | changement appliqué | conservé | `pipeline.yml` |

[BENCH] Deux constats servent la suite. Copier et cruft rendent le code 0
alors qu'un conflit reste à résoudre : la CLI de CELIAN ne peut pas se fier au
code de sortie, elle doit lire la liste des fichiers non fusionnés
(`git diff --name-only --diff-filter=U`) et chercher les marqueurs. Et le repli
de R-22 donne le même résultat que Copier sur ce jouet : il tient, au prix
d'un mécanisme que CELIAN devrait écrire et maintenir.

## 5. Notation par critère

Chaque option retenue reçoit une note entière de 0 à 5 sur chaque critère.
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

- Chaque note cite au moins une source [Sn] ou une mesure [Mn]. Une note sans
  preuve n'entre pas dans la grille, et le rapport reste en brouillon tant
  qu'elle manque.
- Un critère qui ne départage pas les options reçoit la même note pour
  toutes, avec la raison écrite.
- Une option éliminée à la section 3 n'est pas notée.

[BENCH] Cookiecutter et Yeoman sont éliminés à la section 3 : seul Copier est
noté. Les notes se lisent donc dans l'absolu, sans comparaison.

### 5.1 Licence et liberté d'usage, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Copier | 5/5 | 15 | MIT, approuvée par l'OSI, compatible avec l'Apache-2.0 du générateur qui l'embarque comme dépendance. Le contenu généré vient du blueprint de CELIAN, Copier n'y ajoute que son fichier de réponses. Seul changement passé : BSD vers MIT le 2015-04-05, d'une licence permissive à une autre | [S1], [S8], [S29] |

### 5.2 Gouvernance (fondation, multi-vendeurs), poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Copier | 2/5 | 6 | Aucune fondation : organisation communautaire copier-org, deux membres publics, employés chez Siemens et Moduon selon leur profil. Sur 12 mois, 21 auteurs humains, mais 91 des 120 commits humains (76 %) viennent d'un seul mainteneur. Le contournement existe : le repli de R-22, essayé en M4 | [S1], [S9], [S10], [S11], [S12], [M4] |

### 5.3 Maturité et adoption, poids 15

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Copier | 4/5 | 12 | Dépôt créé le 2011-11-01, version majeure 9 stable depuis le 2023-10-22, classée « Production/Stable » sur PyPI. Adoption : environ 8 600 fichiers `.copier-answers.yml` dans les dépôts publics de GitHub, et 2,48 millions de téléchargements sur 30 jours selon une source tierce. Réserve : aucune liste d'adoptants en production tenue par le projet | [S1], [S2], [S6], [S15], [S16] |

### 5.4 Activité et maintenance, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Copier | 5/5 | 10 | 23 releases sur 12 mois, la dernière le 2026-10-13. 21 contributeurs humains sur la même période, dernier commit le 2026-11-06 | [S2], [S9] |

### 5.5 Sécurité (CVE, réactivité), poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Copier | 3/5 | 6 | Signalement privé activé. 15 avis publiés du 2025-08-18 au 2026-10-12 (8 élevés, 7 moyens), chacun avec une version corrigée sortie entre zéro et deux jours avant l'avis. Réserve : la même classe de faille revient, évasion du mode « gabarit sûr » et contournement de la confiance, cinq fois pour la seule confiance en 2026. Action : CELIAN ne rend que ses propres blueprints, depuis une adresse qu'il contrôle, et exige Copier 9.19.0 au minimum. Le délai entre signalement et correctif n'est pas public | [S2], [S7], [S14] |

### 5.6 Empreinte sur PC (RAM, CPU, démarrage), poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Copier | 5/5 | 10 | Médiane de 0,48 s et 54,4 Mio au maximum pour une génération, lanceur `uvx` compris. Rien ne reste en mémoire : Copier ne tourne qu'à la génération et à la mise à jour | [M2], [M3] |

### 5.7 Portabilité multi-cloud, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Copier | 5/5 | 10 | Demande Python 3.10 et Git 2.27 ou plus récents. La CI du projet tourne sous macOS, Ubuntu et Windows. Le moteur ignore la cible : GCP ou PC n'est que du contenu du blueprint (principe II). Le projet généré n'a besoin de Copier que pour se mettre à jour (ENF-07) | [S3], [S5], [S6], [S13] |

### 5.8 Expérience dev et documentation, poids 10

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Copier | 4/5 | 8 | Documentation à jour, avec une page dédiée à la mise à jour et au traitement des conflits. Le fichier de réponses enregistre la version du gabarit (`_commit`), ce que demande ENF-06. Essai : gabarit jouet et mise à jour écrits et passés du premier coup, générations identiques (M1). Réserve : code 0 malgré un conflit restant, et dépôt Git propre exigé avant la mise à jour ; la CLI doit vérifier les deux | [S3], [S4], [M1], [M4] |

### 5.9 Coût (managé ou opérationnel), poids 5

| Option | Note | Points | Justification | Sources |
| --- | --- | --- | --- | --- |
| Copier | 5/5 | 5 | Aucune licence payante, aucun service à opérer : une dépendance Python qui tourne sur le poste. Le coût réel, l'entretien du blueprint, serait le même avec tout moteur. À confirmer par [FINOPS] | [S1], [M2] |

## 6. Grille pondérée

| Critère | Poids | Copier | Cookiecutter | Yeoman |
| --- | --- | --- | --- | --- |
| Critères éliminatoires (section 3) | éliminatoire | passe | éliminée (jour 2, cruft sans release depuis 12 mois) | éliminée (jour 2) |
| Licence et liberté d'usage | 15 | 5/5, 15 pts | éliminée | éliminée |
| Gouvernance (fondation, multi-vendeurs) | 15 | 2/5, 6 pts | éliminée | éliminée |
| Maturité et adoption | 15 | 4/5, 12 pts | éliminée | éliminée |
| Activité et maintenance | 10 | 5/5, 10 pts | éliminée | éliminée |
| Sécurité (CVE, réactivité) | 10 | 3/5, 6 pts | éliminée | éliminée |
| Empreinte sur PC (RAM, CPU, démarrage) | 10 | 5/5, 10 pts | éliminée | éliminée |
| Portabilité multi-cloud | 10 | 5/5, 10 pts | éliminée | éliminée |
| Expérience dev et documentation | 10 | 4/5, 8 pts | éliminée | éliminée |
| Coût (managé ou opérationnel) | 5 | 5/5, 5 pts | éliminée | éliminée |
| Total | 100 | 82 / 100 | éliminée | éliminée |

## 7. Verdict proposé

[BENCH] Option proposée : Copier, 82 sur 100. Aucun écart à mesurer avec une
suivante : Cookiecutter et Yeoman sont éliminés avant la notation.

[BENCH] Pourquoi. Copier est la seule option qui met à jour un projet modifié
localement comme le demande US-011 : fusion propre là où c'est possible,
conflit signalé fichier par fichier ailleurs, fichiers de l'équipe conservés,
trois exécutions sur trois [M4]. Il génère de façon reproductible (US-004)
[M1], publie souvent [S2] et ne pèse rien sur le poste [M2], [M3]. Ses
faiblesses sont la gouvernance, portée en pratique par une personne [S9], et
la répétition de failles dans son modèle de confiance [S7].

[BENCH] Sensibilité. Avec une seule option notée, aucun changement de note ne
peut inverser un classement. Le verdict basculerait sur un fait nouveau : une
release de cruft, qui rouvrirait Cookiecutter avec cruft, ou une fusion à
trois voies ajoutée à Yeoman. Une note de Copier plus basse ne changerait rien
non plus, faute de seuil minimal dans la grille du brief.

[BENCH] Gouvernance. Copier n'a pas d'éditeur unique mais n'a pas non plus de
fondation, et un seul mainteneur porte les trois quarts des commits humains
[S9]. L'écart au principe V se justifie ici par l'absence d'alternative : les
deux autres options ne remplissent pas le jour 2. L'ADR doit le dire, et
garder le repli de R-22, essayé avec succès en M4, comme sortie si Copier
ralentit.

[BENCH] Réserves à surveiller. Les avis de sécurité de Copier, tous corrigés
jusqu'ici par une version sortie au plus tard le jour de l'avis [S2], [S7] : la
version minimale exigée par la CLI suit le dernier avis. L'activité du dépôt, et la part du premier
mainteneur dans les commits. L'activité de cruft, qui pourrait rouvrir une
option. Prochaine vérification proposée : 2027-05-19, ou plus tôt si un avis
de sécurité touche Copier.

[BENCH] Suites. L'ADR du moteur de templates, écrit par [ARCHI]. Copier est
une dépendance de la CLI plutôt qu'un service du catalogue : [ARCHI] dira s'il
entre dans `catalog/` ; dans tous les cas, sa version se fige dans la CLI avec
licence, gouvernance, statut, date et source (principe IV), et Renovate la
suit. Trois propositions pour `docs/risques.md`, que tient le DSI : compléter
R-22 avec l'activité vérifiée de Copier et l'essai du repli ; compléter R-11
avec le code de sortie 0 en cas de conflit, que la CLI et la matrice de la
phase 4 doivent contrôler par Git ; créer un risque sur les failles
récurrentes du modèle de confiance de Copier, avec pour mitigation la version
minimale et des blueprints servis seulement depuis une source contrôlée.

## 8. Limites et biais

| Limite | Effet possible sur le verdict | Ce qui la lèverait |
| --- | --- | --- |
| Une seule machine de mesure, sous macOS, chargée par d'autres agents | Temps et mémoire propres à ce poste ; Linux et Windows non essayés | Relancer le script sur Linux, et sur Windows si [OPS] retient cette plateforme (Q5) |
| Gabarit jouet de quatre fichiers | Le blueprint réel produira d'autres conflits, en nombre et en forme | La matrice de la phase 4 rejoue la mise à jour sur le vrai blueprint (US-011) |
| Temps et mémoire incluent `uvx` ou `npx`, cache chaud | M2 et M3 surestiment le moteur seul, et la CLI l'embarquera comme bibliothèque | Mesurer depuis la CLI une fois écrite |
| Chemin interactif de Yeoman non joué | Un humain peut choisir fichier par fichier, mais sans fusion d'après la source | Aucun effet sur l'élimination : le choix offert ne fusionne pas [S26] |
| Gouvernance mesurée par les identifiants des commits, robots filtrés par leur nom | Un contributeur qui signe sous plusieurs comptes fausserait la part du premier mainteneur | Relire la liste des auteurs à la main |
| Compte GitHub de fichiers `.copier-answers.yml` approximatif, téléchargements de source tierce | La note de maturité repose en partie sur des ordres de grandeur | Une liste d'adoptants tenue par le projet, s'il en publie une |
| Option pressentie par le PRD | Biais de confirmation possible en faveur de Copier | Même essai et mêmes sources pour les trois options ; relecture de [SECU] |
| Une seule option notée | Le total de 82 ne se compare à rien dans ce rapport | Décision du DSI : verdict à une option, ou seconde option à instruire (repli R-22 avec Cookiecutter) |

## 9. Sources

[BENCH] Les dates de release et les comptes d'activité viennent de l'API
publique de GitHub, lue le même jour que la page citée.

| ID | URL | Lue le | Ce que la source établit | Officielle |
| --- | --- | --- | --- | --- |
| S1 | <https://github.com/copier-org/copier> | 2026-11-19 | Licence MIT, organisation copier-org, dépôt non archivé, créé le 2011-11-01 | Oui |
| S2 | <https://github.com/copier-org/copier/releases> | 2026-11-19 | 9.19.1 le 2026-10-13 ; 23 releases depuis le 2025-11-19 ; 9.0.0 le 2023-10-22 ; dates des versions corrigées, de 9.9.1 (2025-08-18) à 9.19.0 (2026-10-12) | Oui |
| S3 | <https://copier.readthedocs.io/en/stable/updating/> | 2026-11-19 | Prérequis de `copier update` (fichier de réponses, gabarit et projet versionnés dans Git, dépôt propre), algorithme, conflits `inline` par défaut ou `rej` | Oui |
| S4 | <https://copier.readthedocs.io/en/stable/creating/> | 2026-11-19 | Gabarit du fichier de réponses `{{_copier_conf.answers_file}}.jinja` | Oui |
| S5 | <https://copier.readthedocs.io/en/stable/> | 2026-11-19 | Python 3.10 et Git 2.27 ou plus récents ; installation par pip, pipx, uv, conda, Homebrew | Oui |
| S6 | <https://pypi.org/pypi/copier/9.19.1/json> | 2026-11-19 | `requires_python >=3.10`, « Development Status :: 5 - Production/Stable », MIT, fichiers publiés le 2026-10-13 | Oui |
| S7 | <https://github.com/copier-org/copier/security/advisories> | 2026-11-19 | 15 avis publiés du 2025-08-18 au 2026-10-12, sévérité et version corrigée de chacun ; signalement privé activé | Oui |
| S8 | <https://github.com/copier-org/copier/commits/master/LICENSE> | 2026-11-19 | Passage de BSD à MIT le 2015-04-05, dernier changement du fichier le 2019-08-20 | Oui |
| S9 | <https://api.github.com/repos/copier-org/copier/commits?since=2025-11-19T00:00:00Z> | 2026-11-19 | 415 commits sur 12 mois dont 120 humains, 21 auteurs humains, 91 commits de `sisp`, dernier commit le 2026-11-06 | Oui |
| S10 | <https://github.com/orgs/copier-org/people> | 2026-11-19 | Membres publics : `sisp` et `yajo` | Oui |
| S11 | <https://github.com/sisp> | 2026-11-19 | Employeur déclaré : Siemens | Oui |
| S12 | <https://github.com/yajo> | 2026-11-19 | Employeur déclaré : Moduon | Oui |
| S13 | <https://github.com/copier-org/copier/blob/master/.github/workflows/ci.yml> | 2026-11-19 | CI sous macOS, Ubuntu et Windows, Python 3.11 à 3.15 | Oui |
| S14 | <https://copier.readthedocs.io/en/stable/configuring/> | 2026-11-19 | Extensions Jinja, migrations et tâches désactivées par défaut, autorisées par `--trust` | Oui |
| S15 | <https://github.com/search?q=filename%3A.copier-answers.yml&type=code> | 2026-11-19 | Environ 8 608 fichiers `.copier-answers.yml` publics, compte approximatif de GitHub | Non, plateforme d'hébergement |
| S16 | <https://pypistats.org/api/packages/copier/recent> | 2026-11-19 | 2 483 686 téléchargements de Copier sur 30 jours | Non, tierce |
| S17 | <https://github.com/cookiecutter/cookiecutter> | 2026-11-19 | Licence BSD-3-Clause, dépôt non archivé, dernière poussée le 2026-04-01 | Oui |
| S18 | <https://github.com/cookiecutter/cookiecutter/releases> | 2026-11-19 | 2.7.1 le 2026-03-04, précédente 2.6.0 le 2024-02-21 | Oui |
| S19 | <https://cookiecutter.readthedocs.io/en/stable/cli_options.html> | 2026-11-19 | Aucune commande ni option de mise à jour ; `--overwrite-if-exists` et `--skip-if-file-exists` | Oui |
| S20 | <https://github.com/cruft/cruft> | 2026-11-19 | Licence MIT, dépôt non archivé, `cruft update` applique les changements du gabarit | Oui |
| S21 | <https://github.com/cruft/cruft/releases> | 2026-11-19 | 2.16.0 le 2024-12-25, dernier commit le même jour | Oui |
| S22 | <https://github.com/yeoman/yo> | 2026-11-19 | Licence BSD-2-Clause, dépôt non archivé, `yo ./path/to/local/generator` | Oui |
| S23 | <https://github.com/yeoman/yo/releases> | 2026-11-19 | v7.0.1 le 2026-04-09 | Oui |
| S24 | <https://github.com/yeoman/generator/releases> | 2026-11-19 | v10.3.1 le 2026-11-16 ; dépôt sous BSD-2-Clause, non archivé | Oui |
| S25 | <https://yeoman.io/authoring/file-system.html> | 2026-11-19 | Toute écriture sur un fichier existant passe par une résolution de conflit validée par l'utilisateur ; aucune mise à jour décrite | Oui |
| S26 | <https://github.com/yeoman/yeoman-api/blob/main/workspaces/conflicter/src/conflicter.ts> | 2026-11-19 | Choix offerts en cas de conflit : écraser, ne pas écraser, tout écraser, différence, abandonner, recharger, éditer, ignorer | Oui |
| S27 | <https://registry.npmjs.org/yo/7.0.1> | 2026-11-19 | yo 7.0.1 demande Node.js `^20.17.0 \|\| >=22.9.0` et dépend de yeoman-environment `^6.0.1` | Oui |
| S28 | <https://registry.npmjs.org/yeoman-generator/10.3.1> | 2026-11-19 | yeoman-generator 10.3.1 demande Node.js `^22.18.0 \|\| >=24.11.0`, paquet ESM | Oui |
| S29 | <https://opensource.org/licenses> | 2026-11-19 | MIT, BSD-2-Clause et BSD-3-Clause approuvées par l'OSI | Oui |

## 10. Relectures

| Relecteur | Porte sur | Date | Avis |
| --- | --- | --- | --- |
| [SECU] | Licences, critères éliminatoires, sécurité | à venir | à venir |
| [FINOPS] | Coût | à venir | à venir |

[SECU] Remarques et suite donnée : à venir.

[FINOPS] Remarques et suite donnée : à venir.
