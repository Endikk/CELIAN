# Failing case of S15: a public IP on Cloud SQL.
# package: tofu_adr008
# expect: ADR-008, condition 6): gcp/policy/testdata/c6-cloud-sql-public-ip.tf: google_sql_database_instance.main: the instance has a public IP

resource "google_sql_database_instance" "main" {
  name             = "main"
  region           = "europe-west1"
  database_version = "POSTGRES_18"

  settings {
    tier = "db-custom-1-3840"

    ip_configuration {
      ipv4_enabled = true
    }
  }
}
