# Failing case of S15: an ACL rule that carries a password in clear (">" sets a
# password in Valkey ACL syntax), hence in the HCL and in the state. The value
# is the example of the provider page, a known value (ADR-015, condition 19).
# package: tofu_memorystore
# expect: a rule holds '>', a password in clear in the HCL

resource "google_memorystore_acl_policy" "cache" {
  acl_policy_id = "demo-cache"
  location      = "europe-west1"

  rules {
    username = "default"
    rule     = "on >password123 ~* +@all"
  }
}
