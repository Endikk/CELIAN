# Failing case of S15: the whole token resource put in a local, which would
# carry the token to any place that reads the local.
# package: tofu_memorystore
# expect: local.t reads the token

locals {
  t = google_memorystore_auth_token.cache
}
