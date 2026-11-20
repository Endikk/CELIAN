# Vision de CELIAN

Statut : validée par Lucas à la GATE 0 le 15/11/2026. Section « Ce qui le
distingue » révisée le 19/11/2026, après l'analyse des outils existants.

Sources : brief v1.0 (sections 2, 3, 4 et 12), constitution 1.0.0 et
`CLAUDE.md`, lus le 15/11/2026. Le détail du MVP est dans le
[PRD](prd-mvp.md).

## Le problème

Démarrer un projet professionnel sur une architecture propre prend des
semaines. Il faut choisir les technos, écrire l'infrastructure as code, monter
Kubernetes et la CI/CD, traiter la sécurité, poser des conventions Git et
documenter. Chaque équipe refait ce socle de son côté, souvent à moitié faute
de temps. Ensuite il dérive. Personne n'est chargé de le tenir à jour, et une
brique peut changer de licence ou être archivée sans que l'équipe s'en
aperçoive.

## Pour qui

Le dev ou le tech lead d'une PME ou d'une ESN qui lance un nouveau projet et
veut un socle de niveau professionnel sans y passer des semaines. Il connaît
son métier de développeur. Il n'a pas forcément de platform engineer à côté de
lui pour l'infrastructure et la sécurité.

## Ce que fait CELIAN

CELIAN prend la forme d'un plugin Claude Code qui pilote une CLI Python.
L'utilisateur répond à un entretien guidé sur sa cible, son type de projet et
ses contraintes. Ses réponses deviennent une spec YAML abstraite, source de
vérité du projet. Des blueprints testés génèrent le dépôt de façon
déterministe, puis un agent écrit ce qui est propre au projet : les ADR et les
textes du projet. Le code applicatif se limite à l'exemple livré par le
blueprint, l'utilisateur écrit son métier. Une validation automatique tourne
avant la livraison et renvoie l'agent corriger quand elle échoue.

Le dépôt obtenu démarre en une commande sur un PC et se déploie sur la cible
choisie. Il continue ensuite de recevoir les correctifs de son blueprint.

## Ce qui le distingue

Aucune brique technique n'est neuve : Copier met à jour un projet généré, la
parité locale existe ailleurs. Mais aucun des douze outils
[analysés](benchmarks/analyse-outils-existants.md) ne couvre entièrement plus
de deux des six piliers de CELIAN. La différence tient à l'assemblage et à la
curation. Le catalogue est daté : la CI du générateur rejette toute entrée
incomplète. La règle « open source sur PC, managé sur GCP » vise une stack
.NET et React.
L'agent n'écrit que les ADR et les textes, et la validation le renvoie
corriger. Aucun des douze ne le fait ; c'est le point le moins éprouvé.

Le risque : une équipe outillée peut tout assembler elle-même. CELIAN ne vaut
que s'il lui épargne ce travail et sa maintenance.

## Ce que CELIAN ne fera pas

Le MVP se limite à un blueprint, SaaS B2B (.NET, React, Postgres, cache), et à
deux cibles : un PC, sous un cluster Kubernetes local (kind, ADR-004), et GCP.
AWS, Azure, les serveurs on-prem et le cloud souverain attendront la fin du
MVP, tout comme les blueprints data, IoT et mobile. Pendant le MVP, CELIAN n'aura ni interface web, ni application
autonome, ni version hébergée, ni agent comparateur intégré à l'entretien.

Certaines limites valent au-delà du MVP. CELIAN ne crée jamais de ressource
cloud payante sans accord explicite, et ne met jamais de secret dans un dépôt.
Il ne propose aucune combinaison de blueprint et de cible que sa matrice de
validation ne couvre pas. Une fois le dépôt livré, il n'exploite pas le projet
en production.

## Le succès du MVP

Le critère vient du brief. Une personne qui ne connaît pas le projet lance la
commande, répond à une dizaine de questions, et obtient en moins de 15 minutes
un dépôt qui démarre sur son PC et se déploie sur GCP, avec une CI qui passe.
Il se teste en phase 6, chronomètre en main, sans aide pendant la session. Le
PRD précise ce que couvrent les 15 minutes.

Aucun objectif d'adoption ou d'usage n'est chiffré. Rien n'est encore mesuré,
et un chiffre non mesuré ne s'écrit pas.

CELIAN est publié sous licence Apache-2.0, dans un dépôt public.
