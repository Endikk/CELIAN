# Network: one VPC, one subnet with the secondary ranges of GKE, and private
# service access for Cloud SQL (ADR-008, scope). Ranges of the BENCH-008
# base. No Cloud NAT: the private nodes reach Google APIs and services through
# Private Google Access, and nothing else outside the VPC (ADR-008 leaves
# Cloud NAT out of its decision).

resource "google_compute_network" "main" {
  project                 = var.project_id
  name                    = var.name
  auto_create_subnetworks = false

  depends_on = [google_project_service.apis]
}

resource "google_compute_subnetwork" "main" {
  project                  = var.project_id
  name                     = "${var.name}-${var.region}"
  region                   = var.region
  network                  = google_compute_network.main.id
  ip_cidr_range            = "10.0.0.0/20"
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.16.0.0/14"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.20.0.0/20"
  }

  # VPC flow logs stay on (Trivy AVD-GCP-0029 and AVD-GCP-0076), at the lowest
  # volume of the demo profile (R-05, R-18): the longest interval the provider
  # offers, one record in ten, no metadata fields. They go to Cloud Logging,
  # whose price was not read.
  log_config {
    aggregation_interval = "INTERVAL_15_MIN"
    flow_sampling        = 0.1
    metadata             = "EXCLUDE_ALL_METADATA"
  }
}

resource "google_compute_global_address" "private_services" {
  project       = var.project_id
  name          = "${var.name}-private-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "private_services" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services.name]
}
