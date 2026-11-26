# Failing case of S15: a cache without encryption in transit. The setting is
# immutable: it cannot be fixed after the creation.
# package: tofu_memorystore
# expect: transit_encryption_mode is 'TRANSIT_ENCRYPTION_DISABLED'; it must be written SERVER_AUTHENTICATION

resource "google_memorystore_instance" "cache" {
  instance_id             = "demo-cache"
  location                = "europe-west1"
  authorization_mode      = "TOKEN_AUTH"
  transit_encryption_mode = "TRANSIT_ENCRYPTION_DISABLED"
}
