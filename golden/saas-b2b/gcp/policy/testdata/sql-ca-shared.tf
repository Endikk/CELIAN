# Failing case of S15: Cloud SQL on the shared CA of a region.
# package: tofu_sql_tls
# expect: google_sql_database_instance.main: settings.ip_configuration.server_ca_mode is 'GOOGLE_MANAGED_CAS_CA'

resource "google_sql_database_instance" "main" {
  name             = "main"
  database_version = "POSTGRES_18"

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      ipv4_enabled   = false
      server_ca_mode = "GOOGLE_MANAGED_CAS_CA"
    }
  }
}

output "database_private_ip" {
  value = google_sql_database_instance.main.private_ip_address
}

output "database_server_ca_cert" {
  value     = google_sql_database_instance.main.server_ca_cert[0].cert
  sensitive = true
}
