# Failing case of S15: k8s certs on the DNS endpoint left to the provider default.
# package: tofu_adr008
# expect: ADR-008, condition 5): gcp/policy/testdata/c5-dns-certs-unwritten.tf: google_container_cluster.main: control_plane_endpoints_config.dns_endpoint_config.enable_k8s_certs_via_dns must be written false

resource "google_container_cluster" "main" {
  name             = "main"
  location         = "europe-west1"
  enable_autopilot = true

  private_cluster_config {
    enable_private_nodes = true
  }

  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic    = true
      enable_k8s_tokens_via_dns = false
    }

    ip_endpoints_config {
      enabled = false
    }
  }
}
