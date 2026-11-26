# Failing case of S15: the values to copy into the manifests are not output.
# package: tofu_sql_tls
# expect: no output database_server_ca_cert that reads google_sql_database_instance.main.server_ca_cert

resource "google_sql_database_instance" "main" {
  name             = "main"
  database_version = "POSTGRES_18"

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      ipv4_enabled   = false
      server_ca_mode = "GOOGLE_MANAGED_INTERNAL_CA"
    }
  }
}

output "database_private_ip" {
  value = google_sql_database_instance.main.private_ip_address
}
