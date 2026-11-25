# Failing case of S15: the access to the control plane left to its defaults.
# package: tofu_adr008
# expect: ADR-008, condition 5): gcp/policy/testdata/c5-no-dns-endpoint.tf: google_container_cluster.main: control_plane_endpoints_config.dns_endpoint_config.allow_external_traffic is not written out

resource "google_container_cluster" "main" {
  name             = "main"
  location         = "europe-west1"
  enable_autopilot = true

  private_cluster_config {
    enable_private_nodes = true
  }
}
