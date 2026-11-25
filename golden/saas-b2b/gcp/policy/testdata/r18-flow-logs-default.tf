# Failing case of S15: VPC flow logs at the defaults of the provider, every 5
# seconds, half of the records, all metadata (R-18).
# package: tofu_finops
# expect: log_config.aggregation_interval is 'INTERVAL_5_SEC'

resource "google_compute_subnetwork" "main" {
  name          = "main"
  region        = "europe-west1"
  network       = "main"
  ip_cidr_range = "10.0.0.0/20"

  log_config {}
}
