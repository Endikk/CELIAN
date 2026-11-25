# Failing case of S15: the state is encrypted, the plans are not enforced.
# package: tofu_adr008
# expect: ADR-008, condition 2): the encryption block has no plan section with a method and enforced = true

terraform {
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
  }
}
