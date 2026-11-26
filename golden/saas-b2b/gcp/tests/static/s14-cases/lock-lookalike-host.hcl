# expect: provider "registry.opentofu.org.example.com/hashicorp/random" is locked on another host
# Failing case of S14: a good block, then a block on a host that starts like the OpenTofu one.

provider "registry.opentofu.org/hashicorp/google" {
  version     = "8.12.0"
  constraints = "8.12.0"
  hashes = [
    "h1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
  ]
}

provider "registry.opentofu.org.example.com/hashicorp/random" {
  version     = "3.9.1"
  constraints = "3.9.1"
  hashes = [
    "h1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
  ]
}
