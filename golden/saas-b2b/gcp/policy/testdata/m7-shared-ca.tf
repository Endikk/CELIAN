# Failing case of S15: the shared regional CA. Any instance of the region that
# uses it presents a certificate that a client trusting it accepts as the cache
# (review by [SECU] at step 19, S63). The setting is immutable.
# package: tofu_memorystore
# expect: server_ca_mode is 'GOOGLE_MANAGED_SHARED_CA'; it must be written GOOGLE_MANAGED_PER_INSTANCE_CA

resource "google_memorystore_instance" "cache" {
  instance_id             = "demo-cache"
  location                = "europe-west1"
  authorization_mode      = "TOKEN_AUTH"
  transit_encryption_mode = "SERVER_AUTHENTICATION"
  server_ca_mode          = "GOOGLE_MANAGED_SHARED_CA"
}
