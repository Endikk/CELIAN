# Failing case of S15: an automated backup, whose cost was not read.
# package: tofu_memorystore
# expect: automated_backup_config is written; the demo profile has no backup

resource "google_memorystore_instance" "cache" {
  instance_id = "demo-cache"
  location    = "europe-west1"

  automated_backup_config {
    retention = "86400s"

    fixed_frequency_schedule {
      start_time {
        hours = 2
      }
    }
  }
}
