# Failing case of S15: the server CA mode of Cloud SQL left to its default.
# package: tofu_sql_tls
# expect: google_sql_database_instance.main: settings.ip_configuration.server_ca_mode is ''

resource "google_sql_database_instance" "main" {
  name             = "main"
  database_version = "POSTGRES_18"

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      ipv4_enabled = false
    }
  }
}

output "database_private_ip" {
  value = google_sql_database_instance.main.private_ip_address
}

output "database_server_ca_cert" {
  value = google_sql_database_instance.main.server_ca_cert[0].cert
}
