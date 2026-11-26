# expect: provider "registry.terraform.io/hashicorp/google" is locked on another host
# Failing case of S14: a lock written by Terraform, on the host of its registry.

provider "registry.terraform.io/hashicorp/google" {
  version     = "8.12.0"
  constraints = "8.12.0"
  hashes = [
    "h1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
  ]
}
