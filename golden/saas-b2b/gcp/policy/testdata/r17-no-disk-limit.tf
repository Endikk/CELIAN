# Failing case of S15: Cloud SQL without a limit on the growth of its disk,
# which the provider reads as no limit (R-17).
# package: tofu_finops
# expect: disk_autoresize_limit does not come from a variable

resource "google_sql_database_instance" "main" {
  name   = "main"
  region = "europe-west1"

  settings {
    tier = "db-f1-micro"

    disk_autoresize = true
  }
}
