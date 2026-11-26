# Failing case of S15: an engine version that is not a literal of the form
# VALKEY_<major>_<minor>, which S21 compares with the local layer.
# package: tofu_memorystore
# expect: engine_version is 'latest'; the line is written as a literal such as VALKEY_9_1

resource "google_memorystore_instance" "cache" {
  instance_id    = "demo-cache"
  location       = "europe-west1"
  engine_version = "latest"
}
