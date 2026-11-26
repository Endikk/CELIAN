# Racine du budget

Cette racine OpenTofu déclare l'alerte budget du projet GCP (ENF-05). Elle est séparée de `gcp/tofu/` parce qu'un budget appartient au compte de facturation : il demande `roles/billing.costsManager` sur ce compte, un rôle que l'identité de la racine principale ne doit jamais porter. La politique `tofu_budget` (S15) refuse dans les deux racines tout rôle de base (`roles/owner`, `roles/editor`, `roles/admin`, `roles/writer`) et tout rôle de facturation qui écrit des budgets.

L'alerte ne plafonne rien : elle prévient. Les coûts arrivent en retard à la facturation, et la première alerte peut venir plusieurs heures après la création.

## Ce qu'elle crée

Un `google_billing_budget` limité au projet, au mois civil, sur le coût brut (crédits exclus), et l'activation de `billingbudgets.googleapis.com` sur le projet. Alertes à 50, 90 et 100 % de la dépense réelle, et à 100 % de la dépense prévue. Les destinataires sont ceux par défaut : les administrateurs et les utilisateurs du compte de facturation.

Trois réserves :

- La prévision n'a pas d'historique minimal documenté. La page des budgets ne fixe aucun historique minimal pour la prévision. Comportement sur projet jeune à constater au premier apply autorisé. D'ici là, seuls les trois seuils sur le réel sont fiables.
- Avec un filtre par projet, les charges non rattachées à un projet ne sont pas comptées.
- Les destinataires par défaut ne couvrent pas quelqu'un qui n'aurait que `costsManager` : ce rôle ne l'inscrit ni parmi les administrateurs ni parmi les utilisateurs du compte.

Le montant (`budget_amount`), sa devise, le compte de facturation et le numéro du projet n'ont aucune valeur par défaut : le montant se choisit avec [FINOPS] avant tout apply. Le montant se compare au coût brut, avant crédits.

Aucun montant n'est conseillé ici, parce que le dépôt n'a pas d'estimation exploitable. L'ADR-008 écrit « le coût reste inconnu » : GKE seul coûte de 20 à 307 USD par mois (us-central1, prix d'exemple, minorant), et Cloud SQL, Memorystore et le réseau ne sont pas chiffrés. Le détail est à la section 5.9 de BENCH-008 (tableau aux lignes 536 à 551, minorant aux lignes 553 à 562). Ces chiffres sont en USD, alors que la devise du budget est celle du compte de facturation, et l'API refuse une devise différente. Le montant se fixe depuis les grilles de la région retenue, avant la GATE 2.

## Comment elle s'applique

- À la main, par la personne qui a l'accord de Lucas, hors de toute session d'agent. Jamais par la CI : aucun workflow ni aucune tâche ne la planifie, ne l'applique ni ne la détruit (S17).
- Avant la racine principale `gcp/tofu/`.
- Avec `roles/billing.costsManager` sur le compte de facturation. Sur le projet, il faut aussi `serviceusage.services.use` (le provider envoie `billing_project`) et `serviceusage.services.enable` pour l'API.
- Par une identité distincte de celle qui applique la racine principale : un compte de service emprunté, ou une configuration `gcloud` à part. Sans cela, la séparation des rôles reste nominale, puisqu'une seule identité porterait `costsManager` et les droits de la racine principale.
- À l'init, le seul réglage passé par `-backend-config` est `bucket`, le même seau que la racine principale. Jamais `prefix` : le préfixe `budget` est écrit dans `versions.tf`, différent du préfixe `main` de `gcp/tofu/`, et une valeur de la ligne de commande l'écraserait sans qu'aucun contrôle le voie. Le préfixe sépare deux chemins, pas deux droits : l'IAM d'un seau GCS vaut pour tout le seau (sauf condition IAM sur le nom d'objet), et une identité qui a accès au seau et à la même clé KMS lit et écrit l'état du budget. Chemin distinct, pas isolation des droits.
- Après `tofu init`, relire `.terraform/terraform.tfstate` et vérifier `prefix = "budget"`. Le premier plan ne doit montrer que deux ajouts (le budget et l'API) et aucune destruction. Un `-backend-config` ou un `TF_CLI_ARGS_init` qui poserait `prefix` écraserait le bloc sans trace : avec la même clé KMS, la racine du budget pourrait alors viser l'état `main` et proposer de détruire l'infrastructure principale. Si le plan montre une destruction, ne pas appliquer.
- L'état et les plans sont chiffrés par la même clé Cloud KMS que la racine principale (`state_encryption_key`), et refusés en clair. Garder la même clé est une condition de T110. Une clé propre à la racine du budget est une option que Lucas tranchera à la GATE 2 : elle couperait la lecture de l'état `main` depuis la racine du budget, au prix d'une clé de plus à tenir.
- Détruite en dernier, après la racine principale.

Rien dans ce dépôt ne l'initialise avec un backend ni ne la planifie : S14 fait `tofu init -backend=false -lockfile=readonly` puis `tofu validate`, S15 lance la politique et Trivy, sans identifiant.
