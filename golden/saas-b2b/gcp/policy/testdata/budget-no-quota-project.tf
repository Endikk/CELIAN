# Failing case of S15 (T110): the provider names no quota project: the API answers 403 to the credentials of a user.
# package: tofu_budget
# expect: provider google has no billing_project

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

resource "google_billing_budget" "demo" {
  billing_account = var.billing_account_id
  display_name    = "demo-budget"

  budget_filter {
    projects               = ["projects/${var.project_number}"]
    calendar_period        = "MONTH"
    credit_types_treatment = "EXCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      currency_code = var.budget_currency
      units         = tostring(var.budget_amount)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }

  threshold_rules {
    threshold_percent = 0.9
  }

  threshold_rules {
    threshold_percent = 1.0
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }
}
