# Failing case of S15: a node type above the one that [FINOPS] budgeted.
# package: tofu_memorystore
# expect: node_type is 'STANDARD_SMALL'; it must be written SHARED_CORE_NANO

resource "google_memorystore_instance" "cache" {
  instance_id = "demo-cache"
  location    = "europe-west1"
  node_type   = "STANDARD_SMALL"
}
