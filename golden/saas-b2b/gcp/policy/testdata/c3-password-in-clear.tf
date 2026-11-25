# Failing case of S15: a database password in clear, hence in the state.
# package: tofu_adr008
# expect: ADR-008, condition 3): gcp/policy/testdata/c3-password-in-clear.tf: google_sql_user.app: password is written in clear

resource "google_sql_user" "app" {
  name     = "app"
  instance = "main"
  password = var.database_password
}
