# S15: the conditions of ADR-008 that the HCL of the gcp layer shows without
# any cloud (spec 001, FR-011, FR-012): 1 identity of the CI by federation on
# numeric ids, 2 state and plans encrypted, 3 write-only attributes, 4 node
# account, 5 DNS endpoint, 6 the suites that BENCH-008 gave conftest, 8 no
# third-party module by tag. Condition 7 is S14, condition 9 is S16 (step 14).
#
# Input: the files given to `conftest test --combine`, a list of objects with
# a `path` and the parsed `contents` (research RS-18). Only the .tf files are
# read. Each refusal names its condition.
package tofu_adr008

label(condition) := sprintf("S15 (FR-011, FR-012; ADR-008, condition %v)", [condition])

tf_files contains file if {
	some file in input
	endswith(file.path, ".tf")
}

# Every resource block, with its file, type and name.
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

# Condition 1: federation of the CI on numeric ids, never on names.

required_claims := ["assertion.repository_id", "assertion.repository_owner_id", "assertion.ref", "assertion.event_name"]

checks_claim(condition, claim) if {
	escaped := replace(claim, ".", `\.`)
	regex.match(sprintf(`(^|[^A-Za-z0-9_.])%s\s*==`, [escaped]), condition)
}

deny contains msg if {
	some provider in blocks_of("google_iam_workload_identity_pool_provider")
	condition := object.get(provider.body, "attribute_condition", "")
	some claim in required_claims
	not checks_claim(condition, claim)
	msg := sprintf("%s: %s: attribute_condition does not check %s", [label(1), where(provider), claim])
}

deny contains msg if {
	some provider in blocks_of("google_iam_workload_identity_pool_provider")
	condition := object.get(provider.body, "attribute_condition", "")
	regex.match(`assertion\.repository(_owner)?([^_A-Za-z0-9]|$)`, condition)
	msg := sprintf("%s: %s: attribute_condition filters on a name (repository or repository_owner); use the numeric *_id claims", [label(1), where(provider)])
}

# Only a push may get the token: a workflow run by pull_request_target,
# workflow_run, schedule or workflow_dispatch does not. The event name is
# compared with the literal 'push' (single or double quotes).
event_literals(condition) := [match[1] |
	some match in regex.find_all_string_submatch_n(`assertion\.event_name\s*==\s*['"]([^'"]*)['"]`, condition, -1)
]

deny contains msg if {
	some provider in blocks_of("google_iam_workload_identity_pool_provider")
	condition := object.get(provider.body, "attribute_condition", "")
	checks_claim(condition, "assertion.event_name")
	not "push" in event_literals(condition)
	msg := sprintf("%s: %s: assertion.event_name must be 'push' in attribute_condition", [label(1), where(provider)])
}

deny contains msg if {
	some provider in blocks_of("google_iam_workload_identity_pool_provider")
	condition := object.get(provider.body, "attribute_condition", "")
	some event in event_literals(condition)
	event != "push"
	msg := sprintf("%s: %s: assertion.event_name must be 'push' in attribute_condition, found '%s'", [label(1), where(provider), event])
}

variable_validated(name) if {
	some file in tf_files
	some body in object.get(file.contents, ["variable", name], [])
	count(object.get(body, "validation", [])) > 0
}

deny contains msg if {
	some provider in blocks_of("google_iam_workload_identity_pool_provider")
	condition := object.get(provider.body, "attribute_condition", "")
	some match in regex.find_all_string_submatch_n(`var\.([A-Za-z0-9_-]+)`, condition, -1)
	not variable_validated(match[1])
	msg := sprintf("%s: %s: variable %s, interpolated in attribute_condition, has no validation block", [label(1), where(provider), match[1]])
}

# Members of an IAM block, whether it writes member or members.
members(body) := {member |
	some member in array.concat([object.get(body, "member", "")], object.get(body, "members", []))
	is_string(member)
	member != ""
}

deny contains msg if {
	some block in resources
	some member in members(block.body)
	contains(member, "principalSet://")
	not contains(member, "/attribute.repository_id/")
	msg := sprintf("%s: %s: principalSet %s is not bound to attribute.repository_id", [label(1), where(block), member])
}

deny contains msg if {
	some key in blocks_of("google_service_account_key")
	msg := sprintf("%s: %s: no service account key; the CI goes through the federation", [label(1), where(key)])
}

# Condition 2: state and plans encrypted by OpenTofu with a Cloud KMS key.

encryptions contains encryption if {
	some file in tf_files
	some settings in object.get(file.contents, "terraform", [])
	some encryption in object.get(settings, "encryption", [])
}

deny contains msg if {
	count(tf_files) > 0
	count(encryptions) == 0
	msg := sprintf("%s: no terraform.encryption block; the state and the plans must be encrypted", [label(2)])
}

deny contains msg if {
	count(encryptions) > 0
	not some_gcp_kms
	msg := sprintf("%s: the encryption has no gcp_kms key provider", [label(2)])
}

some_gcp_kms if {
	some encryption in encryptions
	count(object.get(encryption, ["key_provider", "gcp_kms"], {})) > 0
}

enforced(target) if {
	some encryption in encryptions
	some section in object.get(encryption, target, [])
	section.enforced == true
	startswith(object.get(section, "method", ""), "${method.")
}

deny contains msg if {
	count(encryptions) > 0
	some target in ["state", "plan"]
	not enforced(target)
	msg := sprintf("%s: the encryption block has no %s section with a method and enforced = true", [label(2), target])
}

deny contains msg if {
	some encryption in encryptions
	count(object.get(encryption, ["method", "unencrypted"], {})) > 0
	msg := sprintf("%s: the unencrypted method is declared; it only serves a migration, never the code of the layer", [label(2)])
}

# Condition 3: secrets through write-only attributes, never in the state.

clear_attributes := {"password", "root_password", "secret_data"}

deny contains msg if {
	some block in resources
	some attribute in clear_attributes
	object.get(block.body, attribute, null) != null
	msg := sprintf("%s: %s: %s is written in clear; use %s_wo", [label(3), where(block), attribute, attribute])
}

deny contains msg if {
	some block in blocks_of("random_password")
	msg := sprintf("%s: %s: a managed random_password lands in the state; use the ephemeral one", [label(3), where(block)])
}

deny contains msg if {
	some block in resources
	some attribute, _ in block.body
	endswith(attribute, "_wo")
	object.get(block.body, sprintf("%s_version", [attribute]), null) == null
	msg := sprintf("%s: %s: %s has no %s_version, so a new value would never be sent", [label(3), where(block), attribute, attribute])
}

secret_reading_sources := {"google_secret_manager_secret_version", "google_secret_manager_regional_secret_version"}

deny contains msg if {
	some file in tf_files
	some type in secret_reading_sources
	some name, _ in object.get(file.contents, ["data", type], {})
	msg := sprintf("%s: %s: data.%s.%s copies a secret value into the state", [label(3), file.path, type, name])
}

# Condition 4 and the decision: GKE Autopilot, nodes under a dedicated
# account that holds roles/container.defaultNodeServiceAccount.

clusters := blocks_of("google_container_cluster")

deny contains msg if {
	some cluster in clusters
	object.get(cluster.body, "enable_autopilot", false) != true
	msg := sprintf("S15 (FR-011, FR-012; ADR-008, decision): %s: the cluster is not Autopilot (enable_autopilot = true)", [where(cluster)])
}

node_account(cluster) := account if {
	defaults := first(first(cluster.body, "cluster_autoscaling"), "auto_provisioning_defaults")
	account := defaults.service_account
	is_string(account)
	account != ""
}

deny contains msg if {
	some cluster in clusters
	not node_account(cluster)
	msg := sprintf("%s: %s: no node account in cluster_autoscaling.auto_provisioning_defaults.service_account; the default account of Compute Engine would serve", [label(4), where(cluster)])
}

deny contains msg if {
	some cluster in clusters
	contains(node_account(cluster), "-compute@developer.gserviceaccount.com")
	msg := sprintf("%s: %s: the nodes run under the default account of Compute Engine", [label(4), where(cluster)])
}

deny contains msg if {
	count(clusters) > 0
	not node_role_granted
	msg := sprintf("%s: no google_project_iam_member grants roles/container.defaultNodeServiceAccount to the node account", [label(4)])
}

node_role_granted if {
	some grant in blocks_of("google_project_iam_member")
	grant.body.role == "roles/container.defaultNodeServiceAccount"
}

# Condition 5: DNS endpoint written out, IP endpoint off, private nodes.

deny contains msg if {
	some cluster in clusters
	dns := first(first(cluster.body, "control_plane_endpoints_config"), "dns_endpoint_config")
	not is_boolean(object.get(dns, "allow_external_traffic", null))
	msg := sprintf("%s: %s: control_plane_endpoints_config.dns_endpoint_config.allow_external_traffic is not written out", [label(5), where(cluster)])
}

deny contains msg if {
	some cluster in clusters
	ip := first(first(cluster.body, "control_plane_endpoints_config"), "ip_endpoints_config")
	object.get(ip, "enabled", true) != false
	msg := sprintf("%s: %s: the IP endpoint of the control plane is not disabled (ip_endpoints_config.enabled = false)", [label(5), where(cluster)])
}

deny contains msg if {
	some cluster in clusters
	object.get(first(cluster.body, "private_cluster_config"), "enable_private_nodes", false) != true
	msg := sprintf("%s: %s: the nodes are not private (private_cluster_config.enable_private_nodes = true)", [label(5), where(cluster)])
}

# Neither Kubernetes tokens nor certificates are accepted through the DNS
# endpoint: access goes through IAM. The provider's default is not read, so
# false is written out, and a variable is not enough.
dns_auth_flags := ["enable_k8s_tokens_via_dns", "enable_k8s_certs_via_dns"]

deny contains msg if {
	some cluster in clusters
	dns := first(first(cluster.body, "control_plane_endpoints_config"), "dns_endpoint_config")
	some flag in dns_auth_flags
	object.get(dns, flag, null) != false
	msg := sprintf("%s: %s: control_plane_endpoints_config.dns_endpoint_config.%s must be written false", [label(5), where(cluster), flag])
}

# Condition 6: the suites of BENCH-008 not covered above.

deny contains msg if {
	some instance in blocks_of("google_sql_database_instance")
	ip := first(first(instance.body, "settings"), "ip_configuration")
	object.get(ip, "ipv4_enabled", true) != false
	msg := sprintf("%s: %s: the instance has a public IP (settings.ip_configuration.ipv4_enabled = false)", [label(6), where(instance)])
}

deny contains msg if {
	some cache in blocks_of("google_redis_instance")
	object.get(cache.body, "tier", "") == ""
	msg := sprintf("%s: %s: the tier of Memorystore is not written out", [label(6), where(cache)])
}

# Condition 8: a module is a local path, or a Git source at a full SHA
# without depth.

allowed_source(source) if startswith(source, "./")

allowed_source(source) if startswith(source, "../")

allowed_source(source) if {
	startswith(source, "git::")
	regex.match(`[?&]ref=[0-9a-f]{40}(&|$)`, source)
	not regex.match(`[?&]depth=`, source)
}

deny contains msg if {
	some file in tf_files
	some name, bodies in object.get(file.contents, "module", {})
	some body in bodies
	source := object.get(body, "source", "")
	not allowed_source(source)
	msg := sprintf("%s: %s: module.%s comes from %s; a third-party module is copied under modules/<name>, or pinned by a full Git SHA", [label(8), file.path, name, source])
}
