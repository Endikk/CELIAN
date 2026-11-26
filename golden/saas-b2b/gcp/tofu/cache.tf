# Memorystore for Valkey (ADR-015, decision and conditions 7, 13, 15, 16): no
# cluster mode, no replica, one node of the smallest type, no commitment. The
# values that make the bill are literals checked by gcp/policy/
# tofu_memorystore.rego (S15): any other value goes through a reviewed change
# of that policy and a budget validated by [FINOPS] (principle X, R-05).
# Attributes: provider page at v8.12.0, read on 2026-11-26 (research RS-11).
#
# Not here yet: the token of the `default` user and the secret of Secret
# Manager that receives it. google_memorystore_auth_token is not in google
# 8.12.0, the pinned version (research RS-11, ADR-015 condition 18). The token
# and the producer of the Secret cache-auth come with the second PR of step 20.

# Private Service Connect: Memorystore creates its endpoint in the network
# through a policy of the service class gcp-memorystore (Google, networking
# page of Memorystore for Valkey, read on 2026-11-26). The policy lists the
# subnet of GKE only, and no other: the endpoint takes its address there. It
# has no port setting: Google lists 6379 for clients and 11000 to 13047 for the
# nodes, and does not split them by mode (same page).
resource "google_network_connectivity_service_connection_policy" "cache" {
  project       = var.project_id
  name          = "${var.name}-cache"
  location      = var.region
  service_class = "gcp-memorystore"
  network       = google_compute_network.main.id
  description   = "Private Service Connect endpoint of the Memorystore cache of ${var.name}"
  labels        = local.labels

  psc_config {
    subnetworks = [google_compute_subnetwork.main.id]
    # Google: two connections for each instance of the region. One instance.
    limit = 2
  }

  depends_on = [google_project_service.apis]
}

resource "google_memorystore_instance" "cache" {
  project     = var.project_id
  instance_id = "${var.name}-cache"
  location    = var.region
  labels      = local.labels

  # Condition 13: no cluster mode, one shard, no replica, the smallest node
  # type. Written out even where the provider's default is the same, so that
  # nothing depends on a default. `mode` cannot change after the creation.
  mode          = "CLUSTER_DISABLED"
  shard_count   = 1
  replica_count = 0
  node_type     = "SHARED_CORE_NANO"

  # Condition 16: the line that Memorystore serves by default, 9.1 on
  # 2026-11-26. A literal, like database_version: S21 will compare it with
  # the line of the local layer. The enum value is the one of the gcloud flag
  # --engine-version (Google, create-instances page, read on 2026-11-26): the
  # provider page lists VALKEY_7_2 to VALKEY_9_0 in its examples and tests,
  # not VALKEY_9_1. An instance cannot go back to an earlier version.
  engine_version = "VALKEY_9_1"

  # Condition 7: token authentication and TLS from the creation, the second
  # being immutable. TOKEN_AUTH creates the first token of the `default` user.
  authorization_mode      = "TOKEN_AUTH"
  transit_encryption_mode = "SERVER_AUTHENTICATION"

  # The CA of the instance is its own: a client that trusts it accepts no other
  # instance. The shared regional CA would let every instance of the region
  # that uses it pass for this one. Immutable (API reference, provider:
  # ForceNew), so decided before the first apply (research RS-11, S63).
  server_ca_mode = "GOOGLE_MANAGED_PER_INSTANCE_CA"

  # Condition 15: allkeys-lru, as on the local layer. The default of the
  # service is volatile-lru.
  engine_configs = {
    maxmemory-policy = "allkeys-lru"
  }

  # Condition 13: no persistence and no automated backup, as on the local
  # layer. No automated_backup_config block.
  persistence_config {
    mode = "DISABLED"
  }

  # The endpoint of the instance, in the network of GKE, through the policy
  # above. Immutable.
  desired_auto_created_endpoints {
    network    = google_compute_network.main.id
    project_id = var.project_id
  }

  # ADR-008, condition 10: lifted by an apply before the documented teardown.
  deletion_protection_enabled = true

  depends_on = [
    google_network_connectivity_service_connection_policy.cache,
    google_project_service.apis,
  ]
}
