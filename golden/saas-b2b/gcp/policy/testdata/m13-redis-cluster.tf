# Failing case of S15: Memorystore for Redis Cluster, a second service billed
# by the shard that the demo profile does not budget.
# package: tofu_memorystore
# expect: google_redis_cluster.cache: this resource type is not part of the layer

resource "google_redis_cluster" "cache" {
  name        = "demo-cache"
  shard_count = 3
  region      = "europe-west1"
}
