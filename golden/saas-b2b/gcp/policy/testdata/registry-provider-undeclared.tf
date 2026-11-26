# Failing case of S15: a provider configured but not declared, so with the implicit source hashicorp/google.
# package: tofu_registry
# expect: provider google is configured but not declared in required_providers

terraform {
  required_providers {
    random = {
      source  = "registry.opentofu.org/hashicorp/random"
      version = "3.9.1"
    }
  }
}

provider "google" {
  project = "example"
}
