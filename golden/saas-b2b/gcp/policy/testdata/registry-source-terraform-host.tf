# Failing case of S15: a provider source on the host of the Terraform registry.
# package: tofu_registry
# expect: required_providers.google has source 'registry.terraform.io/hashicorp/google'

terraform {
  required_providers {
    google = {
      source  = "registry.terraform.io/hashicorp/google"
      version = "8.12.0"
    }
  }
}

provider "google" {
  project = "example"
}
