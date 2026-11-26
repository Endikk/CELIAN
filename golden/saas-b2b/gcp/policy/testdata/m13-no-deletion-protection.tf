# Failing case of S15: an instance without the deletion protection that the
# two-step teardown of ADR-008 (condition 10) counts on.
# package: tofu_memorystore
# expect: ADR-008, condition 10): gcp/policy/testdata/m13-no-deletion-protection.tf: google_memorystore_instance.cache: deletion_protection_enabled is 'false'

resource "google_memorystore_instance" "cache" {
  instance_id                 = "demo-cache"
  location                    = "europe-west1"
  deletion_protection_enabled = false
}
