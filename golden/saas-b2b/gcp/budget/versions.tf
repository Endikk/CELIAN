# OpenTofu settings of the budget root (T110; ADR-008, question 1): the same
# versions as gcp/tofu/, a partial GCS backend with a prefix of its own, and
# the same native encryption of the state and of the plans. Versions and
# syntax: research RS-16, RS-26.
#
# Principle X: nothing in this repository plans, applies or destroys this
# root. The checks run `tofu init -backend=false -lockfile=readonly` and
# `tofu validate`, without any credential (gcp/tests/static/s14-tofu-validate.sh).

terraform {
  # Same floor as gcp/tofu/. The checks use the version of tests/tools/install.sh.
  required_version = ">= 1.11.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "8.12.0"
    }
  }

  # Partial configuration: the bucket comes at `tofu init`, by
  # -backend-config, from whoever applies this root by hand with the agreement
  # of Lucas. The prefix is written here, and differs from the one of
  # gcp/tofu/ (S15, T110): the state of the budget is its own object. The
  # prefix separates two paths, not two sets of rights: the IAM of a GCS
  # bucket applies to the whole bucket (unless an IAM condition on the object
  # name narrows it), so an identity that reaches the bucket and the same KMS
  # key reads and writes this state too. Distinct path, not isolation of
  # rights. Never pass `prefix` to -backend-config: a command-line value
  # overrides this one, and S15 cannot see it.
  backend "gcs" {
    prefix = "budget"
  }

  # ADR-008, condition 2, applied to this root too (T110, condition of
  # [SECU]): the state and the plans are encrypted by OpenTofu with a Cloud
  # KMS key, and refused unencrypted. Same shape as gcp/tofu/versions.tf.
  encryption {
    key_provider "gcp_kms" "state" {
      kms_encryption_key = var.state_encryption_key
      # AES-GCM takes keys of 16, 24 or 32 bytes.
      key_length = 32
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

# With the credentials of the user, the Billing Budgets API answers 403 unless
# the provider names a quota project and sets user_project_override
# (provider page of google_billing_budget, v8.12.0; research RS-26). The
# caller needs serviceusage.services.use on that project.
provider "google" {
  project               = var.project_id
  billing_project       = var.project_id
  user_project_override = true
}
