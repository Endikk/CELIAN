# Secret db-auth in Secret Manager (ADR-007), one secret per key of the
# Kubernetes Secret (contracts/secrets.md): the sync of GKE maps each secret
# to one key. Values written through write-only attributes only, never in the
# state nor in a plan (ADR-008, condition 3). Attributes: research RS-16.

# 40 alphanumeric characters, as on the local layer (contracts/secrets.md).
# Ephemeral: drawn at each run, kept nowhere. Only the runs that raise a
# *_wo_version send it.
ephemeral "random_password" "db_auth" {
  length  = 40
  special = false
}

locals {
  # Key of the Kubernetes Secret db-auth => secret of Secret Manager.
  db_auth_secrets = {
    username = "${var.name}-db-auth-username"
    password = "${var.name}-db-auth-password"
  }
}

# The sync of GKE wants "the secret version in the same region as the
# cluster" (ADR-007, question 3): one replica, in the region of the cluster.
# The test of ADR-007, condition 3, tells whether that is enough.
resource "google_secret_manager_secret" "db_auth" {
  for_each  = local.db_auth_secrets
  project   = var.project_id
  secret_id = each.value
  labels    = local.labels

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "db_auth_username" {
  secret                 = google_secret_manager_secret.db_auth["username"].id
  secret_data_wo         = google_sql_user.app.name
  secret_data_wo_version = 1
}

resource "google_secret_manager_secret_version" "db_auth_password" {
  secret         = google_secret_manager_secret.db_auth["password"].id
  secret_data_wo = ephemeral.random_password.db_auth.result
  # Raise it together with password_wo_version of google_sql_user.app.
  secret_data_wo_version = 1
}

data "google_project" "main" {
  project_id = var.project_id
}

# ADR-007, condition 2: read access secret by secret, for the Kubernetes
# service account of the application only, through its Workload Identity
# principal; never a binding at the project level.
resource "google_secret_manager_secret_iam_member" "db_auth" {
  for_each  = google_secret_manager_secret.db_auth
  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "principal://iam.googleapis.com/projects/${data.google_project.main.number}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/subject/ns/${var.app_namespace}/sa/${var.app_service_account}"
}
