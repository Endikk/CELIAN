# S15: Memorystore for Valkey of the gcp layer, as the HCL shows it without any
# cloud (spec 001, FR-011; ADR-015, conditions 7, 13, 15, 16 and 18; ADR-008,
# condition 10). What the instance may be is written once here: the mode, the
# node type and the replicas are those of the demo profile that [FINOPS]
# validates (principle X, R-05), and any other value goes through a reviewed
# change of this policy and of the budget.
#
# Input: the files given to `conftest test --combine`, a list of objects with
# a `path` and the parsed `contents` (research RS-18). Only the .tf files are
# read. Each refusal names its condition.
#
# Condition 18 rules (the token) apply to a resource that the pinned provider
# does not have yet: google_memorystore_auth_token is on the main branch of
# hashicorp/terraform-provider-google, in no release at 8.12.0 (research RS-11,
# 2026-11-26). They are written and tried now, and do nothing until the HCL
# uses that resource.
package tofu_memorystore

label(which) := sprintf("S15 (FR-011; %s)", [which])

tf_files contains file if {
	some file in input
	endswith(file.path, ".tf")
}

resources contains {"path": file.path, "type": type, "name": name, "body": body} if {
	some file in tf_files
	some type, named in object.get(file.contents, "resource", {})
	some name, bodies in named
	some body in bodies
}

blocks_of(type) := {block | some block in resources; block.type == type}

where(block) := sprintf("%s: %s.%s", [block.path, block.type, block.name])

# First body of nested block `key` of `body`, or an empty object.
first(body, key) := object.get(body, key, [{}])[0]

shown(value) := "not written" if value == null

shown(value) := sprintf("'%v'", [value]) if value != null

instances := blocks_of("google_memorystore_instance")

connection_policies := blocks_of("google_network_connectivity_service_connection_policy")

clusters := blocks_of("google_container_cluster")

# The instance: one, written out.

deny contains msg if {
	count(tf_files) > 0
	count(instances) == 0
	msg := sprintf("%s: no google_memorystore_instance; the cache of the gcp layer is missing", [label("ADR-015, condition 13")])
}

deny contains msg if {
	count(instances) > 1
	msg := sprintf("%s: %d google_memorystore_instance blocks; the demo profile has one node, so one instance", [label("ADR-015, condition 13"), count(instances)])
}

deny contains msg if {
	some instance in instances
	some meta in ["count", "for_each"]
	meta in object.keys(instance.body)
	msg := sprintf("%s: %s: %s multiplies the instance; every instance is billed by the node and by the hour", [label("ADR-015, condition 13"), where(instance), meta])
}

# What the instance must say, attribute by attribute: the value, and the
# condition that asks for it. A variable is not enough: the value is read here.
required := {
	"authorization_mode": {"value": "TOKEN_AUTH", "which": "ADR-015, condition 7"},
	"transit_encryption_mode": {"value": "SERVER_AUTHENTICATION", "which": "ADR-015, condition 7"},
	"server_ca_mode": {"value": "GOOGLE_MANAGED_PER_INSTANCE_CA", "which": "ADR-015, condition 7"},
	"mode": {"value": "CLUSTER_DISABLED", "which": "ADR-015, condition 13"},
	"node_type": {"value": "SHARED_CORE_NANO", "which": "ADR-015, condition 13"},
	"shard_count": {"value": 1, "which": "ADR-015, condition 13"},
	"replica_count": {"value": 0, "which": "ADR-015, condition 13"},
	"deletion_protection_enabled": {"value": true, "which": "ADR-008, condition 10"},
}

deny contains msg if {
	some instance in instances
	some attribute, want in required
	got := object.get(instance.body, attribute, null)
	got != want.value
	msg := sprintf("%s: %s: %s is %s; it must be written %v", [label(want.which), where(instance), attribute, shown(got), want.value])
}

# Persistence off and no backup, as on the local layer (condition 13).

deny contains msg if {
	some instance in instances
	mode := object.get(first(instance.body, "persistence_config"), "mode", null)
	mode != "DISABLED"
	msg := sprintf("%s: %s: persistence_config.mode is %s; it must be written DISABLED", [label("ADR-015, condition 13"), where(instance), shown(mode)])
}

# Blocks that start something billed beside the single node.
refused_blocks := ["automated_backup_config", "cross_instance_replication_config", "gcs_source", "managed_backup_source"]

deny contains msg if {
	some instance in instances
	some block in refused_blocks
	block in object.keys(instance.body)
	msg := sprintf("%s: %s: %s is written; the demo profile has no backup, no second instance and no import", [label("ADR-015, condition 13"), where(instance), block])
}

# Eviction: allkeys-lru on both targets (condition 15).

engine_configs(instance) := configs if {
	configs := object.get(instance.body, "engine_configs", {})
	is_object(configs)
} else := {}

deny contains msg if {
	some instance in instances
	policy := object.get(engine_configs(instance), "maxmemory-policy", null)
	policy != "allkeys-lru"
	msg := sprintf("%s: %s: engine_configs.maxmemory-policy is %s; it must be written allkeys-lru, on both targets", [label("ADR-015, condition 15"), where(instance), shown(policy)])
}

# The engine line is one literal, compared by S21 with the local layer
# (condition 16): VALKEY_<major>_<minor>.
deny contains msg if {
	some instance in instances
	version := object.get(instance.body, "engine_version", null)
	not is_string(version)
	msg := sprintf("%s: %s: engine_version is %s; the line is written as a literal such as VALKEY_9_1", [label("ADR-015, condition 16"), where(instance), shown(version)])
}

deny contains msg if {
	some instance in instances
	version := object.get(instance.body, "engine_version", null)
	is_string(version)
	not regex.match(`^VALKEY_[0-9]+_[0-9]+$`, version)
	msg := sprintf("%s: %s: engine_version is '%s'; the line is written as a literal such as VALKEY_9_1", [label("ADR-015, condition 16"), where(instance), version])
}

# ACL policy: a rule with `>` is a password in clear in the HCL (condition 7).
# A rule that is not a literal could hide one.

deny contains msg if {
	some acl in blocks_of("google_memorystore_acl_policy")
	not is_array(object.get(acl.body, "rules", null))
	msg := sprintf("%s: %s: rules is not written as blocks, so no rule can be read", [label("ADR-015, condition 7"), where(acl)])
}

deny contains msg if {
	some acl in blocks_of("google_memorystore_acl_policy")
	some rule in object.get(acl.body, "rules", [])
	contains(object.get(rule, "rule", ""), ">")
	msg := sprintf("%s: %s: a rule holds '>', a password in clear in the HCL; use '#<sha256>' or the token", [label("ADR-015, condition 7"), where(acl)])
}

deny contains msg if {
	some acl in blocks_of("google_memorystore_acl_policy")
	some rule in object.get(acl.body, "rules", [])
	contains(object.get(rule, "rule", ""), "${")
	msg := sprintf("%s: %s: a rule is not a literal; a computed rule could hide a password", [label("ADR-015, condition 7"), where(acl)])
}

# `nopass` opens an account without any token. If Memorystore honors it under
# TOKEN_AUTH, any pod of the VPC would connect. Valkey reads the flag without
# regard to case.
deny contains msg if {
	some acl in blocks_of("google_memorystore_acl_policy")
	some rule in object.get(acl.body, "rules", [])
	contains(lower(object.get(rule, "rule", "")), "nopass")
	msg := sprintf("%s: %s: a rule holds 'nopass', an account without a token", [label("ADR-015, condition 7"), where(acl)])
}

# Resource types that start a second endpoint or another cache service, which
# the demo profile does not budget (conditions 7 and 13).
refused_types := {
	"google_memorystore_instance_desired_user_created_endpoints",
	"google_redis_cluster",
}

deny contains msg if {
	some type in refused_types
	some block in blocks_of(type)
	msg := sprintf("%s: %s: this resource type is not part of the layer; the cache is reached through the endpoint of the network of GKE, and Memorystore for Valkey is the only cache service", [label("ADR-015, conditions 7 and 13"), where(block)])
}

# What hides a drift or a block: ignore_changes would hide a change of
# authorization_mode, which the service lets anyone with the role make; a
# dynamic block escapes the lists above.
deny contains msg if {
	some instance in instances
	some lifecycle in object.get(instance.body, "lifecycle", [])
	"ignore_changes" in object.keys(lifecycle)
	msg := sprintf("%s: %s: lifecycle.ignore_changes is written; it would hide a drift of authorization_mode", [label("ADR-015, condition 7"), where(instance)])
}

deny contains msg if {
	some instance in instances
	some name, _ in object.get(instance.body, "dynamic", {})
	msg := sprintf("%s: %s: dynamic \"%s\" is written; a dynamic block hides what the instance says", [label("ADR-015, condition 13"), where(instance), name])
}

# Private Service Connect: a policy for Memorystore, on the subnet of GKE and
# the network of GKE only, with a bounded number of connections (condition 7).
# The policy has no port setting: the ports are not written here.

deny contains msg if {
	count(instances) > 0
	count({p | some p in connection_policies; object.get(p.body, "service_class", "") == "gcp-memorystore"}) == 0
	msg := sprintf("%s: no service connection policy for gcp-memorystore; the instance cannot create its endpoint", [label("ADR-015, condition 7")])
}

deny contains msg if {
	some policy in connection_policies
	class := object.get(policy.body, "service_class", null)
	class != "gcp-memorystore"
	msg := sprintf("%s: %s: service_class is %s; the layer holds the policy of Memorystore only", [label("ADR-015, condition 7"), where(policy), shown(class)])
}

cluster_subnetworks := {subnetwork |
	some cluster in clusters
	subnetwork := object.get(cluster.body, "subnetwork", null)
	is_string(subnetwork)
}

cluster_networks := {network |
	some cluster in clusters
	network := object.get(cluster.body, "network", null)
	is_string(network)
}

policy_subnetworks(policy) := subnetworks if {
	subnetworks := object.get(first(policy.body, "psc_config"), "subnetworks", [])
	is_array(subnetworks)
} else := []

deny contains msg if {
	some policy in connection_policies
	subnetworks := policy_subnetworks(policy)
	count(subnetworks) != 1
	msg := sprintf("%s: %s: psc_config.subnetworks holds %d entries; it holds the subnet of GKE alone", [label("ADR-015, condition 7"), where(policy), count(subnetworks)])
}

deny contains msg if {
	some policy in connection_policies
	some subnetwork in policy_subnetworks(policy)
	not subnetwork in cluster_subnetworks
	msg := sprintf("%s: %s: psc_config.subnetworks has '%v', which is not the subnetwork of the cluster", [label("ADR-015, condition 7"), where(policy), subnetwork])
}

deny contains msg if {
	some policy in connection_policies
	network := object.get(policy.body, "network", null)
	not network in cluster_networks
	msg := sprintf("%s: %s: network is %s, which is not the network of the cluster", [label("ADR-015, condition 7"), where(policy), shown(network)])
}

deny contains msg if {
	some instance in instances
	network := object.get(first(instance.body, "desired_auto_created_endpoints"), "network", null)
	not network in cluster_networks
	msg := sprintf("%s: %s: desired_auto_created_endpoints.network is %s, which is not the network of the cluster", [label("ADR-015, condition 7"), where(instance), shown(network)])
}

# Two connections per instance (Google: "multiply the number of instances by
# two"), so the limit is written, and at most that.
deny contains msg if {
	some policy in connection_policies
	limit := object.get(first(policy.body, "psc_config"), "limit", null)
	not valid_limit(limit)
	msg := sprintf("%s: %s: psc_config.limit is %s; it is written, and at most 2 for each instance", [label("ADR-015, condition 7"), where(policy), shown(limit)])
}

valid_limit(limit) if {
	is_number(limit)
	limit >= 1
	limit <= 2 * count(instances)
}

# The token (condition 18): created by google_memorystore_auth_token, read by
# no output, no data source, no local, and sent to Secret Manager by
# secret_data_wo only. Its `token` attribute is in the state (the provider
# page says so), which the encryption of the state covers (ADR-008,
# condition 2).

token_type := "google_memorystore_auth_token"

# Any mention of the type: `.<name>.token`, the whole object, `["a"].token` with
# for_each, `values(...)`.
token_reference := `google_memorystore_auth_token`

# A bare dependency on the resource carries no value.
token_dependency := `^(\$\{)?google_memorystore_auth_token\.[A-Za-z0-9_-]+(\})?$`

deny contains msg if {
	some file in tf_files
	some name, bodies in object.get(file.contents, "output", {})
	some body in bodies
	regex.match(`google_memorystore_auth_token`, sprintf("%v", [object.get(body, "value", "")]))
	msg := sprintf("%s: %s: output.%s carries the token of Memorystore; no output holds it", [label("ADR-015, condition 18"), file.path, name])
}

deny contains msg if {
	some file in tf_files
	some name, _ in object.get(file.contents, ["data", token_type], {})
	msg := sprintf("%s: %s: data.%s.%s copies the token into the state", [label("ADR-015, condition 18"), file.path, token_type, name])
}

deny contains msg if {
	some file in tf_files
	some block in object.get(file.contents, "locals", [])
	some name, value in block
	regex.match(token_reference, sprintf("%v", [value]))
	msg := sprintf("%s: %s: local.%s reads the token; only secret_data_wo of a secret version may", [label("ADR-015, condition 18"), file.path, name])
}

token_use_allowed(block, path) if {
	block.type == "google_secret_manager_secret_version"
	path == ["secret_data_wo"]
}

token_use_allowed(_, path) if {
	path[0] == "depends_on"
	count(path) == 2
}

deny contains msg if {
	some file in tf_files
	some name, bodies in object.get(file.contents, "module", {})
	some body in bodies
	walk(body, [_, value])
	is_string(value)
	regex.match(token_reference, value)
	msg := sprintf("%s: %s: module.%s reads the token; only secret_data_wo of a secret version may", [label("ADR-015, condition 18"), file.path, name])
}

# Every string of every resource, at any depth, with the path that leads to it.
deny contains msg if {
	some block in resources
	walk(block.body, [path, value])
	is_string(value)
	regex.match(token_reference, value)
	not token_use_allowed(block, path)
	msg := sprintf("%s: %s: %s reads the token; only secret_data_wo of a google_secret_manager_secret_version may", [label("ADR-015, condition 18"), where(block), concat(".", [sprintf("%v", [p]) | some p in path])])
}
