# Tests of S15 for Memorystore (tofu_memorystore.rego), run by
# `conftest verify`. Each case changes one thing in a valid root, written as
# conftest parses HCL.
package tofu_memorystore

instance := {
	"instance_id": "${var.name}-cache",
	"location": "${var.region}",
	"labels": "${local.labels}",
	"mode": "CLUSTER_DISABLED",
	"shard_count": 1,
	"replica_count": 0,
	"node_type": "SHARED_CORE_NANO",
	"engine_version": "VALKEY_9_1",
	"authorization_mode": "TOKEN_AUTH",
	"transit_encryption_mode": "SERVER_AUTHENTICATION",
	"server_ca_mode": "GOOGLE_MANAGED_PER_INSTANCE_CA",
	"deletion_protection_enabled": true,
	"engine_configs": {"maxmemory-policy": "allkeys-lru"},
	"persistence_config": [{"mode": "DISABLED"}],
	"desired_auto_created_endpoints": [{
		"network": "${google_compute_network.main.id}",
		"project_id": "${var.project_id}",
	}],
}

connection_policy := {
	"service_class": "gcp-memorystore",
	"network": "${google_compute_network.main.id}",
	"psc_config": [{"subnetworks": ["${google_compute_subnetwork.main.id}"], "limit": 2}],
}

cluster := {
	"network": "${google_compute_network.main.id}",
	"subnetwork": "${google_compute_subnetwork.main.id}",
}

valid := {"resource": {
	"google_memorystore_instance": {"cache": [instance]},
	"google_network_connectivity_service_connection_policy": {"cache": [connection_policy]},
	"google_container_cluster": {"main": [cluster]},
}}

files(contents) := [{"path": "gcp/tofu/main.tf", "contents": contents}]

# The valid root after the JSON patch operations ops.
patched(ops) := files(json.patch(valid, ops))

set(path, value) := [{"op": "add", "path": path, "value": value}]

drop(path) := [{"op": "remove", "path": path}]

swap(path, value) := [{"op": "replace", "path": path, "value": value}]

accepted(input_files) if {
	msgs := deny with input as input_files
	count(msgs) == 0
}

denied_with(input_files, fragment) if {
	msgs := deny with input as input_files
	some msg in msgs
	contains(msg, fragment)
}

instance_path := "/resource/google_memorystore_instance/cache/0"

policy_path := "/resource/google_network_connectivity_service_connection_policy/cache/0"

test_s15_accepts_a_valid_root if {
	accepted(files(valid))
}

test_s15_ignores_an_input_without_opentofu_file if {
	accepted([{"path": "platform.yaml", "contents": {"kubernetes_minor": "1.36"}}])
}

# The instance: one, written out.

test_s15_rejects_a_root_without_instance if {
	denied_with(files({"variable": {"x": [{}]}}), "no google_memorystore_instance")
}

test_s15_rejects_two_instances if {
	denied_with(patched(set("/resource/google_memorystore_instance/second", [instance])), "2 google_memorystore_instance blocks")
}

test_s15_rejects_an_instance_with_for_each if {
	denied_with(patched(set(concat("/", [instance_path, "for_each"]), "${toset([\"a\", \"b\"])}")), "for_each multiplies the instance")
}

test_s15_rejects_an_instance_with_count if {
	denied_with(patched(set(concat("/", [instance_path, "count"]), 3)), "count multiplies the instance")
}

# Condition 7.

test_s15_rejects_auth_disabled if {
	denied_with(patched(swap(concat("/", [instance_path, "authorization_mode"]), "AUTH_DISABLED")), "authorization_mode is 'AUTH_DISABLED'")
}

test_s15_rejects_iam_auth if {
	denied_with(patched(swap(concat("/", [instance_path, "authorization_mode"]), "IAM_AUTH")), "it must be written TOKEN_AUTH")
}

test_s15_rejects_an_authorization_mode_left_to_its_default if {
	denied_with(patched(drop(concat("/", [instance_path, "authorization_mode"]))), "authorization_mode is not written")
}

test_s15_rejects_an_authorization_mode_from_a_variable if {
	denied_with(patched(swap(concat("/", [instance_path, "authorization_mode"]), "${var.mode}")), "authorization_mode is '${var.mode}'")
}

test_s15_rejects_transit_encryption_disabled if {
	denied_with(patched(swap(concat("/", [instance_path, "transit_encryption_mode"]), "TRANSIT_ENCRYPTION_DISABLED")), "transit_encryption_mode is 'TRANSIT_ENCRYPTION_DISABLED'")
}

test_s15_rejects_a_transit_encryption_left_to_its_default if {
	denied_with(patched(drop(concat("/", [instance_path, "transit_encryption_mode"]))), "transit_encryption_mode is not written")
}

test_s15_rejects_the_shared_regional_ca if {
	denied_with(patched(swap(concat("/", [instance_path, "server_ca_mode"]), "GOOGLE_MANAGED_SHARED_CA")), "server_ca_mode is 'GOOGLE_MANAGED_SHARED_CA'")
}

test_s15_rejects_a_ca_mode_left_to_its_default if {
	denied_with(patched(drop(concat("/", [instance_path, "server_ca_mode"]))), "server_ca_mode is not written")
}

test_s15_rejects_an_acl_rule_with_a_password if {
	acl := {"rules": [{"username": "default", "rule": "on >password123 ~* +@all"}]}
	denied_with(patched(set("/resource/google_memorystore_acl_policy", {"p": [acl]})), "a rule holds '>'")
}

test_s15_rejects_an_acl_rule_with_a_password_in_the_second_rule if {
	acl := {"rules": [{"username": "a", "rule": "on #abc ~* +@all"}, {"username": "b", "rule": "on >x"}]}
	denied_with(patched(set("/resource/google_memorystore_acl_policy", {"p": [acl]})), "a rule holds '>'")
}

test_s15_rejects_an_acl_rule_that_is_not_a_literal if {
	acl := {"rules": [{"username": "default", "rule": "${var.rule}"}]}
	denied_with(patched(set("/resource/google_memorystore_acl_policy", {"p": [acl]})), "a rule is not a literal")
}

test_s15_accepts_an_acl_rule_with_a_hash if {
	acl := {"rules": [{"username": "default", "rule": "on #0123abcd ~* +@all -@admin"}]}
	accepted(patched(set("/resource/google_memorystore_acl_policy", {"p": [acl]})))
}

test_s15_rejects_a_root_without_connection_policy if {
	denied_with(patched(drop("/resource/google_network_connectivity_service_connection_policy")), "no service connection policy for gcp-memorystore")
}

test_s15_rejects_a_policy_for_another_service if {
	denied_with(patched(swap(concat("/", [policy_path, "service_class"]), "google-cloud-sql")), "the layer holds the policy of Memorystore only")
}

test_s15_rejects_a_policy_on_another_subnetwork if {
	denied_with(patched(swap(concat("/", [policy_path, "psc_config/0/subnetworks"]), ["${google_compute_subnetwork.other.id}"])), "not the subnetwork of the cluster")
}

test_s15_rejects_a_policy_on_two_subnetworks if {
	subnetworks := ["${google_compute_subnetwork.main.id}", "${google_compute_subnetwork.other.id}"]
	denied_with(patched(swap(concat("/", [policy_path, "psc_config/0/subnetworks"]), subnetworks)), "holds 2 entries")
}

test_s15_rejects_a_policy_without_subnetwork if {
	denied_with(patched(swap(concat("/", [policy_path, "psc_config/0/subnetworks"]), [])), "holds 0 entries")
}

test_s15_rejects_a_policy_on_another_network if {
	denied_with(patched(swap(concat("/", [policy_path, "network"]), "${google_compute_network.other.id}")), "not the network of the cluster")
}

test_s15_rejects_an_endpoint_on_another_network if {
	path := concat("/", [instance_path, "desired_auto_created_endpoints/0/network"])
	denied_with(patched(swap(path, "${google_compute_network.other.id}")), "desired_auto_created_endpoints.network")
}

test_s15_rejects_a_policy_without_limit if {
	denied_with(patched(drop(concat("/", [policy_path, "psc_config/0/limit"]))), "psc_config.limit is not written")
}

test_s15_rejects_a_policy_with_a_limit_above_two_per_instance if {
	denied_with(patched(swap(concat("/", [policy_path, "psc_config/0/limit"]), 3)), "psc_config.limit is '3'")
}

# Condition 13.

test_s15_rejects_the_cluster_mode if {
	denied_with(patched(swap(concat("/", [instance_path, "mode"]), "CLUSTER")), "mode is 'CLUSTER'")
}

test_s15_rejects_a_mode_left_to_its_default if {
	denied_with(patched(drop(concat("/", [instance_path, "mode"]))), "mode is not written")
}

test_s15_rejects_a_replica if {
	denied_with(patched(swap(concat("/", [instance_path, "replica_count"]), 1)), "replica_count is '1'")
}

test_s15_rejects_replicas_left_to_their_default if {
	denied_with(patched(drop(concat("/", [instance_path, "replica_count"]))), "replica_count is not written")
}

test_s15_rejects_two_shards if {
	denied_with(patched(swap(concat("/", [instance_path, "shard_count"]), 2)), "shard_count is '2'")
}

test_s15_rejects_a_bigger_node_type if {
	denied_with(patched(swap(concat("/", [instance_path, "node_type"]), "STANDARD_SMALL")), "node_type is 'STANDARD_SMALL'")
}

test_s15_rejects_custom_pico_without_a_budget if {
	denied_with(patched(swap(concat("/", [instance_path, "node_type"]), "CUSTOM_PICO")), "node_type is 'CUSTOM_PICO'")
}

test_s15_rejects_a_node_type_from_a_variable if {
	denied_with(patched(swap(concat("/", [instance_path, "node_type"]), "${var.node_type}")), "it must be written SHARED_CORE_NANO")
}

test_s15_rejects_persistence_by_snapshots if {
	denied_with(patched(swap(concat("/", [instance_path, "persistence_config/0/mode"]), "RDB")), "persistence_config.mode is 'RDB'")
}

test_s15_rejects_persistence_left_to_its_default if {
	denied_with(patched(drop(concat("/", [instance_path, "persistence_config"]))), "persistence_config.mode is not written")
}

test_s15_rejects_an_automated_backup if {
	backup := [{"retention": "86400s"}]
	denied_with(patched(set(concat("/", [instance_path, "automated_backup_config"]), backup)), "automated_backup_config is written")
}

test_s15_rejects_a_cross_instance_replication if {
	config := [{"instance_role": "PRIMARY"}]
	denied_with(patched(set(concat("/", [instance_path, "cross_instance_replication_config"]), config)), "cross_instance_replication_config is written")
}

test_s15_rejects_an_instance_without_deletion_protection if {
	denied_with(patched(swap(concat("/", [instance_path, "deletion_protection_enabled"]), false)), "ADR-008, condition 10")
}

# Condition 15.

test_s15_rejects_the_default_eviction_of_the_service if {
	path := concat("/", [instance_path, "engine_configs/maxmemory-policy"])
	denied_with(patched(swap(path, "volatile-lru")), "engine_configs.maxmemory-policy is 'volatile-lru'")
}

test_s15_rejects_an_eviction_left_to_its_default if {
	denied_with(patched(drop(concat("/", [instance_path, "engine_configs"]))), "engine_configs.maxmemory-policy is not written")
}

test_s15_rejects_engine_configs_that_is_not_a_map if {
	denied_with(patched(swap(concat("/", [instance_path, "engine_configs"]), "${var.configs}")), "engine_configs.maxmemory-policy is not written")
}

# Condition 16.

test_s15_rejects_an_engine_version_left_to_its_default if {
	denied_with(patched(drop(concat("/", [instance_path, "engine_version"]))), "engine_version is not written")
}

test_s15_rejects_an_engine_version_that_is_not_a_line if {
	denied_with(patched(swap(concat("/", [instance_path, "engine_version"]), "9.1")), "engine_version is '9.1'")
}

# Condition 18.

token := "${google_memorystore_auth_token.cache.token}"

test_s15_rejects_an_output_that_carries_the_token if {
	denied_with(patched(set("/output", {"t": [{"value": token, "sensitive": true}]})), "output.t carries the token")
}

test_s15_rejects_an_output_that_wraps_the_token if {
	value := "${nonsensitive(google_memorystore_auth_token.cache.token)}"
	denied_with(patched(set("/output", {"t": [{"value": value}]})), "output.t carries the token")
}

test_s15_accepts_an_output_that_does_not_carry_the_token if {
	accepted(patched(set("/output", {"ca": [{"value": "${google_memorystore_instance.cache.managed_server_ca}"}]})))
}

test_s15_rejects_a_data_source_of_the_token if {
	denied_with(patched(set("/data", {"google_memorystore_auth_token": {"t": [{}]}})), "copies the token into the state")
}

test_s15_rejects_a_local_that_reads_the_token if {
	denied_with(patched(set("/locals", [{"t": token}])), "local.t reads the token")
}

test_s15_accepts_the_token_in_secret_data_wo if {
	version := {"secret_data_wo": token, "secret_data_wo_version": 1}
	accepted(patched(set("/resource/google_secret_manager_secret_version", {"cache": [version]})))
}

test_s15_rejects_the_token_in_another_attribute if {
	version := {"secret_data": token}
	denied_with(patched(set("/resource/google_secret_manager_secret_version", {"cache": [version]})), "secret_data reads the token")
}

test_s15_rejects_the_token_in_another_resource if {
	user := {"password_wo": token, "password_wo_version": 1}
	denied_with(patched(set("/resource/google_sql_user", {"app": [user]})), "password_wo reads the token")
}

test_s15_rejects_the_token_in_a_nested_block if {
	connection := {"settings": [{"labels": token}]}
	denied_with(patched(set("/resource/google_sql_database_instance", {"main": [connection]})), "settings.0.labels reads the token")
}
