# Racine du budget

Cette racine OpenTofu déclare l'alerte budget du projet GCP (ENF-05). Elle est séparée de `gcp/tofu/` parce qu'un budget appartient au compte de facturation : il demande `roles/billing.costsManager` sur ce compte, un rôle que l'identité de la racine principale ne doit jamais porter. La politique `tofu_budget` (S15) refuse dans les deux racines tout rôle de base (`roles/owner`, `roles/editor`, `roles/admin`, `roles/writer`) et tout rôle de facturation qui écrit des budgets.

L'alerte ne plafonne rien : elle prévient. Les coûts arrivent en retard à la facturation, et la première alerte peut venir plusieurs heures après la création.

## Ce qu'elle crée

Un `google_billing_budget` limité au projet, au mois civil, sur le coût brut (crédits exclus), et l'activation de `billingbudgets.googleapis.com` sur le projet. Alertes à 50, 90 et 100 % de la dépense réelle, et à 100 % de la dépense prévue. Les destinataires sont ceux par défaut : les administrateurs et les utilisateurs du compte de facturation.

Le montant (`budget_amount`), sa devise, le compte de facturation et le numéro du projet n'ont aucune valeur par défaut : le montant se choisit avec [FINOPS] avant tout apply.

## Comment elle s'applique

- À la main, par la personne qui a l'accord de Lucas, hors de toute session d'agent. Jamais par la CI : aucun workflow ni aucune tâche ne la planifie, ne l'applique ni ne la détruit (S17).
- Avant la racine principale `gcp/tofu/`.
- Avec `roles/billing.costsManager` sur le compte de facturation. Sur le projet, il faut aussi `serviceusage.services.use` (le provider envoie `billing_project`) et `serviceusage.services.enable` pour l'API.
- À l'init, le seul réglage passé par `-backend-config` est `bucket`, le même seau que la racine principale. Jamais `prefix` : le préfixe `budget` est écrit dans `versions.tf`, différent du préfixe `main` de `gcp/tofu/`, et une valeur de la ligne de commande l'écraserait sans qu'aucun contrôle le voie.
- L'état et les plans sont chiffrés par la même clé Cloud KMS que la racine principale (`state_encryption_key`), et refusés en clair.
- Détruite en dernier, après la racine principale.

Rien dans ce dépôt ne l'initialise avec un backend ni ne la planifie : S14 fait `tofu init -backend=false -lockfile=readonly` puis `tofu validate`, S15 lance la politique et Trivy, sans identifiant.
