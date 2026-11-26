# Failing case of S15: an output that carries the token of Memorystore. An
# output sits in the state and prints on screen.
# package: tofu_memorystore
# expect: output.cache_token carries the token of Memorystore

output "cache_token" {
  value     = google_memorystore_auth_token.cache.token
  sensitive = true
}
