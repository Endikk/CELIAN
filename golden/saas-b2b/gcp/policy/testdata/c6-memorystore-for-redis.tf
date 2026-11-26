# Failing case of S15: Memorystore for Redis, which the BENCH-008 base used and
# which ADR-015 replaces with Memorystore for Valkey.
# package: tofu_adr008
# expect: Memorystore for Redis is not the cache of the layer (ADR-015)

resource "google_redis_instance" "cache" {
  name           = "demo-cache"
  tier           = "BASIC"
  memory_size_gb = 1
}
