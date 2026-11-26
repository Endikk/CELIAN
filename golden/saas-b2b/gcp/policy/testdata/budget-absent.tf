# Failing case of S15 (T110): the root declares no budget.
# package: tofu_budget
# expect: no google_billing_budget in the budget root

terraform {
  backend "gcs" {
    prefix = "budget"
  }

  encryption {
    key_provider "gcp_kms" "state" {
      kms_encryption_key = var.state_encryption_key
      key_length         = 32
    }

    method "aes_gcm" "state" {
      keys = key_provider.gcp_kms.state
    }

    state {
      method   = method.aes_gcm.state
      enforced = true
    }

    plan {
      method   = method.aes_gcm.state
      enforced = true
    }
  }
}

provider "google" {
  project               = var.project_id
  billing_project       = var.project_id
  user_project_override = true
}

variable "project_number" {
  type = string

  validation {
    condition     = can(regex("^[0-9]+$", var.project_number))
    error_message = "project_number: digits only."
  }
}

variable "budget_amount" {
  type = number

  validation {
    condition     = var.budget_amount > 0
    error_message = "budget_amount: above 0."
  }
}
