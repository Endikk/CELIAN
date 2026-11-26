# Failing case of S15: a replica, billed like a second node, every hour (S48).
# package: tofu_memorystore
# expect: replica_count is '1'; it must be written 0

resource "google_memorystore_instance" "cache" {
  instance_id   = "demo-cache"
  location      = "europe-west1"
  replica_count = 1
}
