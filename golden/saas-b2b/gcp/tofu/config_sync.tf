# Config Sync on the cluster (ADR-010), installed by the fleet feature
# "configmanagement" without any source: the RootSync of the environment is a
# manifest of the layer (gcp/k8s/, step 14), never applied in phase 2.
# Attributes: research RS-16.

resource "google_gke_hub_feature" "configmanagement" {
  project  = var.project_id
  name     = "configmanagement"
  location = "global"

  depends_on = [google_project_service.apis]
}

resource "google_gke_hub_feature_membership" "configmanagement" {
  project             = var.project_id
  location            = "global"
  feature             = google_gke_hub_feature.configmanagement.name
  membership          = google_container_cluster.main.fleet[0].membership_id
  membership_location = google_container_cluster.main.fleet[0].membership_location

  configmanagement {
    # Pinned, and upgraded by hand in a PR that passes the matrix, together
    # with the free form of the E16 test (ADR-010, condition 5; R-32).
    # Renovate does not follow this value. MANAGEMENT_MANUAL turns the
    # automatic upgrades off.
    version    = "1.25.2"
    management = "MANAGEMENT_MANUAL"

    config_sync {
      enabled = true
    }
  }

  # pending (2026-11-25): the export of the Config Sync metrics to Cloud
  # Monitoring, which ADR-010 (condition 7) wants cut. No attribute of the
  # config_sync block of google 8.12.0 carries it; the test of that condition
  # reads it on GKE, at the first apply agreed by Lucas.
}
