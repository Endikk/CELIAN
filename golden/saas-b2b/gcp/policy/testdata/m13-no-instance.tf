# Failing case of S15: a root without the cache of the gcp layer. Any other
# file of the root stands for it here.
# package: tofu_memorystore
# expect: no google_memorystore_instance; the cache of the gcp layer is missing

variable "name" {
  type = string
}
