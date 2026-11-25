# Failing case of S15 (scan): the justified check, on another resource.
# expect: ignore comment outside the closed list

#trivy:ignore:AVD-GCP-0061
resource "google_container_cluster" "second" {
  name = "main"
}
