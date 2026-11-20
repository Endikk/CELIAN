# No pin on the google provider here: the secret-manager module v0.10.0
# requires google < 8, while the other modules accept < 9. Pinning 8.12.0, as
# the two other options do, makes `tofu init` fail (BENCH-008, section 4).
terraform {
  required_version = ">= 1.11.0"
}
