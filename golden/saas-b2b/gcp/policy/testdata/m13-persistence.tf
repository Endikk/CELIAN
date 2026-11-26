# Failing case of S15: persistence by snapshots, which the cache does not need
# (research RS-11) and whose cost was not read.
# package: tofu_memorystore
# expect: persistence_config.mode is 'RDB'; it must be written DISABLED

resource "google_memorystore_instance" "cache" {
  instance_id = "demo-cache"
  location    = "europe-west1"

  persistence_config {
    mode = "RDB"
  }
}
