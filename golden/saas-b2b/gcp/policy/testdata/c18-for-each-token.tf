# Failing case of S15: the token read through an index (for_each) and given to
# another attribute than secret_data_wo of a secret version.
# package: tofu_memorystore
# expect: password_wo reads the token

resource "google_sql_user" "app" {
  name                = "app"
  instance            = "main"
  password_wo         = google_memorystore_auth_token.cache["a"].token
  password_wo_version = 1
}
