# Failing case of S15: an instance without the service connection policy that
# lets Memorystore create its endpoint in the network.
# package: tofu_memorystore
# expect: no service connection policy for gcp-memorystore

resource "google_memorystore_instance" "cache" {
  instance_id        = "demo-cache"
  location           = "europe-west1"
  authorization_mode = "TOKEN_AUTH"
}
