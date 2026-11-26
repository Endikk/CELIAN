# Failing case of S15: a provider source without the host of the OpenTofu registry.
# package: tofu_registry
# expect: required_providers.google has source 'hashicorp/google'

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "8.12.0"
    }
  }
}

provider "google" {
  project = "example"
}
