# Cloud SQL for PostgreSQL, private IP only, at the major of platform.yaml
# (ADR-012, condition 5), with the database "app" and the user of the Secret
# db-auth (contracts/secrets.md). Attributes: research RS-16.

resource "google_sql_database_instance" "main" {
  project          = var.project_id
  name             = var.name
  region           = var.region
  database_version = "POSTGRES_${local.platform.postgres_major}"

  # ADR-008, condition 10: lifted by an apply before the documented teardown.
  deletion_protection = true

  settings {
    tier = var.database_tier
    # Explicit: from POSTGRES_16 the API defaults to ENTERPRISE_PLUS, which
    # refuses the shared-core and custom tiers. The tier is [FINOPS]'s.
    edition                     = "ENTERPRISE"
    availability_type           = "ZONAL"
    deletion_protection_enabled = true
    user_labels                 = local.labels

    # The disk grows by itself, up to a limit (R-17): the provider's default,
    # 0, means no limit.
    disk_autoresize       = true
    disk_autoresize_limit = var.database_disk_autoresize_limit_gb

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.main.id
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled = true
      # Demo profile, decided by the DSI: daily backups only, no point-in-time
      # recovery, so no transaction logs kept. Turning it on restarts the
      # instance (Cloud SQL, instance-settings page, read on 2026-11-25).
      point_in_time_recovery_enabled = false

      backup_retention_settings {
        retained_backups = var.database_retained_backups
        retention_unit   = "COUNT"
      }
    }
  }

  depends_on = [google_service_networking_connection.private_services]
}

resource "google_sql_database" "app" {
  project  = var.project_id
  name     = "app"
  instance = google_sql_database_instance.main.name
}

# User of the Secret db-auth, the one the API connects with (contracts/
# secrets.md). Its password is drawn by OpenTofu at apply and written only
# through write-only attributes, here and in Secret Manager (secrets.tf):
# never in the state nor in a plan (ADR-008, condition 3).
#
# Assumption of research RS-04 (review by [SECU] of step 3), to be read on
# GKE at the first apply agreed by Lucas, and an accepted gap until then:
# - google_sql_database has no owner argument, and no page read says who owns
#   a database created by the API. The console gives it to cloudsqlsuperuser;
#   the assumption is the same here.
# - this built-in user receives cloudsqlsuperuser, so it inherits the
#   implicit membership in pg_database_owner and may CREATE in the schema
#   public: the schema script of the API runs.
# - gap with local (ENF-02, R-39): locally the same user only owns its
#   database; here the API runs with cloudsqlsuperuser (CREATEROLE, CREATEDB,
#   event triggers, logical replication, pg_largeobject). Hardening after the
#   MVP, by an ADR: a custom role passed in database_roles, then
#   ALTER DATABASE app OWNER TO, by an administration step outside OpenTofu.
# Read at that first apply (research RS-16, checklist for E12): the owner of
# app (pg_database.datdba), has_schema_privilege('app', 'public', 'CREATE'),
# and the rows of pg_auth_members for the member app, with inherit_option.
resource "google_sql_user" "app" {
  project  = var.project_id
  name     = "app"
  instance = google_sql_database_instance.main.name

  password_wo = ephemeral.random_password.db_auth.result
  # Raise it to set a new password; raise db_auth_password's together.
  password_wo_version = 1
}
