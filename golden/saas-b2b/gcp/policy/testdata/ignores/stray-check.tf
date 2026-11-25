# Failing case of S15 (scan): a check of the Cloud SQL logging silenced.
# expect: ignore comment outside the closed list

#trivy:ignore:AVD-GCP-0016
resource "google_sql_database_instance" "main" {
  name = "main"
}
