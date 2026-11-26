# Inputs of the budget root. No default for what depends on the project, the
# billing account or the amount: `tofu validate` needs no value, and no amount
# is chosen here before [FINOPS] validates one (R-05). S15 refuses a default on
# the variables of the amount.

variable "project_id" {
  description = "Existing GCP project that the budget watches. It is also the quota project of the provider, where the Billing Budgets API is enabled."
  type        = string
}

variable "project_number" {
  description = "Number of that project, digits only. The budget filter takes projects/<number>, not the project id (provider page of google_billing_budget, v8.12.0)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.project_number))
    error_message = "project_number: digits only, the number of the project and not its id."
  }
}

variable "name" {
  description = "Short name of the project, the same as in gcp/tofu/. The budget is named <name>-budget."
  type        = string

  # The display name takes 60 characters at most; <name>-budget stays under it.
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,18}[a-z0-9]$", var.name))
    error_message = "name: 4 to 20 characters, lower-case letters, digits and hyphens, starting with a letter."
  }
}

variable "billing_account_id" {
  description = "Cloud Billing account that holds the budget, as XXXXXX-XXXXXX-XXXXXX. Whoever applies this root holds roles/billing.costsManager on it."
  type        = string

  # Google: an 18-character alphanumeric value; the three groups of six come
  # from its example 010101-F0FFF0-10XX01 (docs.cloud.google.com/billing/docs/
  # how-to/find-billing-account-id, read on 2026-11-26).
  validation {
    condition     = can(regex("^[0-9A-Z]{6}-[0-9A-Z]{6}-[0-9A-Z]{6}$", var.billing_account_id))
    error_message = "billing_account_id: three groups of six upper-case letters or digits, separated by hyphens."
  }
}

variable "budget_amount" {
  description = "Monthly amount of the budget, in whole units of budget_currency, chosen with [FINOPS] (R-05). The alert caps nothing: it only warns."
  type        = number

  validation {
    condition     = var.budget_amount == floor(var.budget_amount) && var.budget_amount > 0
    error_message = "budget_amount: a whole number above 0."
  }
}

variable "budget_currency" {
  description = "ISO 4217 code of the currency of the billing account, for example EUR. The API refuses a code that differs from the account's."
  type        = string

  validation {
    condition     = can(regex("^[A-Z]{3}$", var.budget_currency))
    error_message = "budget_currency: three upper-case letters (ISO 4217)."
  }
}

variable "state_encryption_key" {
  description = "Cloud KMS key that encrypts the state and the plans, the same as for gcp/tofu/ (ADR-008, condition 2), as projects/<project>/locations/<location>/keyRings/<ring>/cryptoKeys/<key>. It exists before the first init."
  type        = string

  validation {
    condition     = can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.state_encryption_key))
    error_message = "state_encryption_key: projects/<project>/locations/<location>/keyRings/<ring>/cryptoKeys/<key>."
  }
}
