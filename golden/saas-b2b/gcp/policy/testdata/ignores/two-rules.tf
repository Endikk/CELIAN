# Failing case of S15 (scan): two rules on one line.
# expect: ignore comment outside the closed list

#trivy:ignore:AVD-GCP-0061 trivy:ignore:AVD-GCP-0016
resource "google_container_cluster" "main" {
  name = "main"
}
