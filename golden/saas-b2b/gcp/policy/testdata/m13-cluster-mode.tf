# Failing case of S15: the cluster mode, which the demo profile does not budget.
# package: tofu_memorystore
# expect: mode is 'CLUSTER'; it must be written CLUSTER_DISABLED

resource "google_memorystore_instance" "cache" {
  instance_id = "demo-cache"
  location    = "europe-west1"
  mode        = "CLUSTER"
  shard_count = 3
}
