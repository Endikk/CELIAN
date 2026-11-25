# Failing case of S15 (scan): every check of a resource silenced.
# expect: ignore comment outside the closed list

#trivy:ignore:*
resource "google_container_cluster" "main" {
  name = "main"
}
