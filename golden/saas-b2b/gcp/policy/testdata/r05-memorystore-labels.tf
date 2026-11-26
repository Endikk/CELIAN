# Failing case of S15: a Memorystore instance without the labels of R-05, so
# that a forgotten demo would not show up in the bill.
# package: tofu_finops
# expect: google_memorystore_instance.cache: labels is not local.labels

resource "google_memorystore_instance" "cache" {
  instance_id = "demo-cache"
  location    = "europe-west1"
  labels      = { app = "demo" }
}
