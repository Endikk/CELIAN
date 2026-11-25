# Failing case of S15 (scan): the legacy prefix, which Trivy also reads.
# expect: ignore comment outside the closed list

#tfsec:ignore:AVD-GCP-0061
resource "google_container_cluster" "main" {
  name = "main"
}
