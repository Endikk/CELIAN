# Failing case of S15 (scan): the justified check, with a suffix the list does not hold.
# expect: ignore comment outside the closed list

#trivy:ignore:AVD-GCP-0061:exp:2099-01-01
resource "google_container_cluster" "main" {
  name = "main"
}
