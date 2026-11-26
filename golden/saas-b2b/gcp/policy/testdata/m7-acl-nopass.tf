# Failing case of S15: an ACL rule that opens an account without any token, in
# any case (Valkey reads the flag without regard to case). If Memorystore
# honors it under TOKEN_AUTH, any pod of the VPC would connect without a token.
# package: tofu_memorystore
# expect: a rule holds 'nopass', an account without a token

resource "google_memorystore_acl_policy" "cache" {
  acl_policy_id = "demo-cache"
  location      = "europe-west1"

  rules {
    username = "default"
    rule     = "on NoPass ~* +@all"
  }
}
