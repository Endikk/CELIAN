# Failing case of S15: a provider declared by its version alone, so with no source.
# package: tofu_registry
# expect: required_providers.google has no source

terraform {
  required_providers {
    google = "8.12.0"
  }
}

provider "google" {
  project = "example"
}
