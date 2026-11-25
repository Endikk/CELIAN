# OpenTofu settings of the gcp layer (ADR-008): providers pinned by version
# and by .terraform.lock.hcl, a partial GCS backend, and the native encryption
# of the state and of the plans. Versions and syntax: research RS-16.
#
# Principle X: nothing in this repository plans, applies or destroys this
# root. The checks run `tofu init -backend=false -lockfile=readonly` and
# `tofu validate`, without any credential (gcp/tests/static/s14-tofu-validate.sh).

terraform {
  # Ephemeral resources and write-only attributes need OpenTofu 1.11 or later
  # (ADR-008, condition 3). The checks use the version of
  # tests/tools/install.sh.
  required_version = ">= 1.11.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "8.12.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
  }

  # Partial configuration: the bucket and the prefix come at `tofu init`, by
  # -backend-config, from whoever runs the first apply with the agreement of
  # Lucas. The bucket, the key below and their bootstrap stay with [OPS] and
  # [SECU] (ADR-008, scope; R-19).
  backend "gcs" {}

  # ADR-008, condition 2: the state and the plans are encrypted by OpenTofu
  # with a Cloud KMS key, and refused unencrypted. Without that key, state and
  # plans cannot be read back: it is guarded like the state itself (R-19).
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

provider "google" {
  project = var.project_id
  region  = var.region
}
