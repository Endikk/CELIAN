# Failing case of S15: a dynamic block that writes automated_backup_config,
# which the list of refused blocks does not see.
# package: tofu_memorystore
# expect: dynamic "automated_backup_config" is written; a dynamic block hides what the instance says

resource "google_memorystore_instance" "cache" {
  instance_id = "demo-cache"
  location    = "europe-west1"

  dynamic "automated_backup_config" {
    for_each = [1]

    content {
      retention = "86400s"
    }
  }
}
