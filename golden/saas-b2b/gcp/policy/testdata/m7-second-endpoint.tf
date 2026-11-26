# Failing case of S15: a second endpoint of the instance, created by the user
# in another network. The cache is reached through the endpoint of the
# network of GKE only.
# package: tofu_memorystore
# expect: google_memorystore_instance_desired_user_created_endpoints.extra: this resource type is not part of the layer

resource "google_memorystore_instance_desired_user_created_endpoints" "extra" {
  name     = "demo-cache"
  region   = "europe-west1"
  project  = "demo"
  instance = "demo-cache"
}
