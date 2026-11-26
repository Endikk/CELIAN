# Failing case of S15: a service connection policy on a subnet that is not the
# one of GKE. Read together with the cluster of the root.
# package: tofu_memorystore
# with: gcp/tofu/cluster.tf
# expect: psc_config.subnetworks has '${google_compute_subnetwork.other.id}', which is not the subnetwork of the cluster

resource "google_network_connectivity_service_connection_policy" "cache" {
  name          = "demo-cache"
  location      = "europe-west1"
  service_class = "gcp-memorystore"
  network       = google_compute_network.main.id

  psc_config {
    subnetworks = [google_compute_subnetwork.other.id]
    limit       = 2
  }
}
