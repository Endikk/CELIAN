# Failing case of S15: the token sent to Secret Manager by secret_data, not by
# secret_data_wo: the value would sit in the state of the secret version too.
# package: tofu_memorystore
# expect: secret_data reads the token; only secret_data_wo of a google_secret_manager_secret_version may

resource "google_secret_manager_secret_version" "cache_auth" {
  secret      = "demo-cache-auth"
  secret_data = google_memorystore_auth_token.cache.token
}
