# Cloud SQL for PostgreSQL, private IP only, at the major of platform.yaml
# (ADR-012, condition 5, kept by S21), with the database "app" and the user
# of the Secret db-auth (contracts/secrets.md). Attributes: research RS-16.

resource "google_sql_database_instance" "main" {
  project = var.project_id
  name    = var.name
  region  = var.region

  # A literal, not computed from platform.yaml: Trivy does not resolve a
  # computed value and would skip its Cloud SQL checks. S21 compares it with
  # postgres_major of platform.yaml.
  database_version = "POSTGRES_18"

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

    # Logging flags that Trivy asks for (AVD-GCP-0014, 0016, 0020, 0022,
    # 0025). Values are strings: Cloud SQL lists "on" and "off" for the
    # booleans, and an integer in kilobytes for log_temp_files (page of
    # supported flags, read on 2026-11-25). Each writes a few lines: one per
    # session start and end, per checkpoint, per lock wait longer than
    # deadlock_timeout, per temporary file. log_temp_files at 0 is the default
    # that page lists, written out because Trivy wants it explicit.
    database_flags {
      name  = "log_connections"
      value = "on"
    }

    database_flags {
      name  = "log_disconnections"
      value = "on"
    }

    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }

    database_flags {
      name  = "log_lock_waits"
      value = "on"
    }

    database_flags {
      name  = "log_temp_files"
      value = "0"
    }

    # The disk grows by itself, up to a limit (R-17): the provider's default,
    # 0, means no limit.
    disk_autoresize       = true
    disk_autoresize_limit = var.database_disk_autoresize_limit_gb

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.main.id
      ssl_mode        = "ENCRYPTED_ONLY"

      # The CA of this instance alone, written out although it is the
      # default (Google, authorize-ssl page, read on 2026-11-26: the mode
      # "GOOGLE_MANAGED_INTERNAL_CA" is the per-instance hierarchy, the
      # default when nothing is written). With it "Verifying the CA verifies
      # the server identity", which is what VerifyCA does in app-config; the
      # shared CA of a region would also need the hostname checked, and a
      # private IP instance has no hostname in its certificate. Checked by
      # S15 (gcp/policy/tofu_sql_tls.rego). Tasks.md, gap 178.
      server_ca_mode = "GOOGLE_MANAGED_INTERNAL_CA"
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
