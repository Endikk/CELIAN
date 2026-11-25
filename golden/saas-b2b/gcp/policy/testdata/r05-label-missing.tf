# Failing case of S15: no input for the ttl label of R-05.
# package: tofu_finops
# expect: variable ttl is missing

variable "owner" {
  type = string

  validation {
    condition     = can(regex("^[a-z0-9_-]{1,63}$", var.owner))
    error_message = "owner: a GCP label value."
  }
}

variable "env" {
  type = string

  validation {
    condition     = can(regex("^[a-z0-9_-]{1,63}$", var.env))
    error_message = "env: a GCP label value."
  }
}

locals {
  labels = merge({ app = "demo" }, { owner = var.owner, env = var.env })
}
