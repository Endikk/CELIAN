# Failing case of S15: ignore_changes on the instance would hide a drift of
# authorization_mode, which the service lets anyone with the role change.
# package: tofu_memorystore
# expect: lifecycle.ignore_changes is written; it would hide a drift of authorization_mode

resource "google_memorystore_instance" "cache" {
  instance_id        = "demo-cache"
  location           = "europe-west1"
  authorization_mode = "TOKEN_AUTH"

  lifecycle {
    ignore_changes = [authorization_mode]
  }
}
