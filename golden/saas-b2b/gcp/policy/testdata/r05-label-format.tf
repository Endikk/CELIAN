# Failing case of S15: the validation of a label takes capitals, which GCP
# refuses in a label value.
# package: tofu_finops
# expect: variable owner: its validation accepts 'Demo'

variable "owner" {
  type = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,63}$", var.owner))
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

variable "ttl" {
  type = string

  validation {
    condition     = can(regex("^[a-z0-9_-]{1,63}$", var.ttl))
    error_message = "ttl: a GCP label value."
  }
}

locals {
  labels = merge({ app = "demo" }, { owner = var.owner, env = var.env, ttl = var.ttl })
}
