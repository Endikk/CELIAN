# Failing case of S15: the default eviction of the service, which evicts only
# the keys that have a time to live (ADR-015, condition 15).
# package: tofu_memorystore
# expect: engine_configs.maxmemory-policy is 'volatile-lru'; it must be written allkeys-lru

resource "google_memorystore_instance" "cache" {
  instance_id = "demo-cache"
  location    = "europe-west1"

  engine_configs = {
    maxmemory-policy = "volatile-lru"
  }
}
