# Failing case of S15: the validation of database_tier takes 4 vCPU, above the
# demo profile (2 vCPU at most).
# package: tofu_finops
# expect: its validation accepts the tier 'db-custom-4-15360'

variable "database_tier" {
  type = string

  validation {
    condition     = can(regex("^(db-f1-micro|db-g1-small|db-custom-[0-9]+-[0-9]+)$", var.database_tier))
    error_message = "database_tier: a Cloud SQL tier."
  }
}

resource "google_sql_database_instance" "main" {
  name   = "main"
  region = "europe-west1"

  settings {
    tier = var.database_tier
  }
}
