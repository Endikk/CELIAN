# Failing case of S15: a cache with no authorization, open to any client of the network.
# package: tofu_memorystore
# expect: authorization_mode is 'AUTH_DISABLED'; it must be written TOKEN_AUTH

resource "google_memorystore_instance" "cache" {
  instance_id        = "demo-cache"
  location           = "europe-west1"
  authorization_mode = "AUTH_DISABLED"
}
