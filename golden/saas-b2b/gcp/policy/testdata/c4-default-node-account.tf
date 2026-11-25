# Failing case of S15: Autopilot nodes under the default Compute Engine account.
# package: tofu_adr008
# expect: ADR-008, condition 4): gcp/policy/testdata/c4-default-node-account.tf: google_container_cluster.main: no node account

resource "google_container_cluster" "main" {
  name             = "main"
  location         = "europe-west1"
  enable_autopilot = true

  private_cluster_config {
    enable_private_nodes = true
  }

  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = false
    }

    ip_endpoints_config {
      enabled = false
    }
  }
}
