# Tests of S15 for ADR-008 (tofu_adr008.rego), run by `conftest verify`.
# Each case changes one thing in a valid root, written as conftest parses HCL.
package tofu_adr008

encryption := {
	"key_provider": {"gcp_kms": {"state": [{"kms_encryption_key": "${var.state_encryption_key}", "key_length": 32}]}},
	"method": {"aes_gcm": {"state": [{"keys": "${key_provider.gcp_kms.state}"}]}},
	"state": [{"method": "${method.aes_gcm.state}", "enforced": true}],
	"plan": [{"method": "${method.aes_gcm.state}", "enforced": true}],
}

cluster := {
	"enable_autopilot": true,
	"private_cluster_config": [{"enable_private_nodes": true}],
	"control_plane_endpoints_config": [{
		"dns_endpoint_config": [{"allow_external_traffic": true}],
		"ip_endpoints_config": [{"enabled": false}],
	}],
	"cluster_autoscaling": [{"auto_provisioning_defaults": [{"service_account": "${google_service_account.nodes.email}"}]}],
}

validated := [{"validation": [{"condition": "${can(regex(\"^[0-9]+$\", var.x))}"}]}]

valid := {
	"terraform": [{"encryption": [encryption]}],
	"variable": {"repo_id": validated, "owner_id": validated, "ref": validated},
	"ephemeral": {"random_password": {"db": [{"length": 40}]}},
	"resource": {
		"google_iam_workload_identity_pool_provider": {"github": [{"attribute_condition": "assertion.repository_id == '${var.repo_id}' && assertion.repository_owner_id == '${var.owner_id}' && assertion.ref == '${var.ref}'"}]},
		"google_service_account_iam_member": {"ci": [{"role": "roles/iam.workloadIdentityUser", "member": "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.ci.name}/attribute.repository_id/${var.repo_id}"}]},
		"google_project_iam_member": {"nodes": [{"role": "roles/container.defaultNodeServiceAccount", "member": "serviceAccount:${google_service_account.nodes.email}"}]},
		"google_container_cluster": {"main": [cluster]},
		"google_sql_database_instance": {"main": [{"settings": [{"ip_configuration": [{"ipv4_enabled": false}]}]}]},
		"google_sql_user": {"app": [{"password_wo": "${ephemeral.random_password.db.result}", "password_wo_version": 1}]},
		"google_secret_manager_secret_version": {"password": [{"secret_data_wo": "${ephemeral.random_password.db.result}", "secret_data_wo_version": 1}]},
	},
	"module": {"local": [{"source": "./modules/network"}]},
}

files(contents) := [
	{"path": "gcp/tofu/main.tf", "contents": contents},
	{"path": "platform.yaml", "contents": {"kubernetes_minor": "1.36", "postgres_major": "18"}},
]

# The valid root after the JSON patch operations ops.
patched(ops) := files(json.patch(valid, ops))

set(path, value) := [{"op": "add", "path": path, "value": value}]

drop(path) := [{"op": "remove", "path": path}]

# "add" inserts into an array; "replace" overwrites the element.
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

provider_path := "/resource/google_iam_workload_identity_pool_provider/github/0/attribute_condition"

cluster_path := "/resource/google_container_cluster/main/0"

test_s15_accepts_a_valid_root if {
	accepted(files(valid))
}

test_s15_ignores_an_input_without_opentofu_file if {
	accepted([{"path": "platform.yaml", "contents": {"kubernetes_minor": "1.36"}}])
}

# Condition 1.

test_s15_rejects_a_condition_without_the_ref if {
	denied_with(patched(set(provider_path, "assertion.repository_id == '1' && assertion.repository_owner_id == '2'")), "does not check assertion.ref")
}

test_s15_does_not_take_ref_type_for_the_ref if {
	denied_with(patched(set(provider_path, "assertion.repository_id == '1' && assertion.repository_owner_id == '2' && assertion.ref_type == 'branch'")), "does not check assertion.ref")
}

test_s15_rejects_a_condition_without_the_owner_id if {
	denied_with(patched(set(provider_path, "assertion.repository_id == '1' && assertion.ref == 'refs/heads/main'")), "does not check assertion.repository_owner_id")
}

test_s15_rejects_a_condition_on_the_repository_name if {
	denied_with(patched(set(provider_path, "assertion.repository_id == '1' && assertion.repository_owner_id == '2' && assertion.ref == 'refs/heads/main' && assertion.repository == 'a/b'")), "filters on a name")
}

test_s15_rejects_a_condition_on_the_owner_name if {
	denied_with(patched(set(provider_path, "assertion.repository_owner=='org' && assertion.repository_id == '1' && assertion.repository_owner_id == '2' && assertion.ref == 'x'")), "filters on a name")
}

test_s15_rejects_a_variable_without_validation if {
	denied_with(patched(drop("/variable/ref/0/validation")), "variable ref, interpolated in attribute_condition, has no validation block")
}

test_s15_rejects_a_principal_set_on_the_repository_name if {
	member := "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.ci.name}/attribute.repository/org/repo"
	denied_with(patched(set("/resource/google_service_account_iam_member/ci/0/member", member)), "is not bound to attribute.repository_id")
}

test_s15_rejects_a_principal_set_in_a_members_list if {
	binding := {"role": "roles/iam.workloadIdentityUser", "members": ["principalSet://iam.googleapis.com/pools/p/attribute.repository_owner/org"]}
	denied_with(patched(set("/resource/google_service_account_iam_binding", {"ci": [binding]})), "is not bound to attribute.repository_id")
}

test_s15_rejects_a_service_account_key if {
	denied_with(patched(set("/resource/google_service_account_key", {"ci": [{"service_account_id": "x"}]})), "no service account key")
}

# Condition 2.

test_s15_rejects_a_root_without_encryption if {
	denied_with(patched(swap("/terraform/0", {})), "no terraform.encryption block")
}

test_s15_rejects_an_encryption_without_gcp_kms if {
	denied_with(patched(set("/terraform/0/encryption/0/key_provider", {"pbkdf2": {"state": [{"passphrase": "${var.p}"}]}})), "has no gcp_kms key provider")
}

test_s15_rejects_plans_not_enforced if {
	denied_with(patched(set("/terraform/0/encryption/0/plan/0/enforced", false)), "no plan section with a method and enforced = true")
}

test_s15_rejects_a_state_section_without_method if {
	denied_with(patched(drop("/terraform/0/encryption/0/state/0/method")), "no state section with a method and enforced = true")
}

test_s15_rejects_the_unencrypted_method if {
	denied_with(patched(set("/terraform/0/encryption/0/method/unencrypted", {"migrate": [{}]})), "the unencrypted method is declared")
}

# Condition 3.

test_s15_rejects_a_password_in_clear if {
	denied_with(patched(set("/resource/google_sql_user/app/0/password", "${var.db_password}")), "password is written in clear")
}

test_s15_rejects_a_root_password_in_clear if {
	denied_with(patched(set("/resource/google_sql_database_instance/main/0/root_password", "${var.root}")), "root_password is written in clear")
}

test_s15_rejects_secret_data_in_clear if {
	denied_with(patched(set("/resource/google_secret_manager_secret_version/password/0/secret_data", "${var.value}")), "secret_data is written in clear")
}

test_s15_rejects_a_managed_random_password if {
	denied_with(patched(set("/resource/random_password", {"db": [{"length": 40}]})), "a managed random_password lands in the state")
}

test_s15_rejects_a_write_only_attribute_without_its_version if {
	denied_with(patched(drop("/resource/google_sql_user/app/0/password_wo_version")), "password_wo has no password_wo_version")
}

test_s15_rejects_a_data_source_that_reads_a_secret if {
	denied_with(patched(set("/data", {"google_secret_manager_secret_version": {"db": [{"secret": "x"}]}})), "copies a secret value into the state")
}

# Decision and condition 4.

test_s15_rejects_a_standard_cluster if {
	denied_with(patched(drop(sprintf("%s/enable_autopilot", [cluster_path]))), "the cluster is not Autopilot")
}

test_s15_rejects_a_cluster_without_node_account if {
	denied_with(patched(drop(sprintf("%s/cluster_autoscaling", [cluster_path]))), "no node account")
}

test_s15_rejects_the_default_compute_account if {
	path := sprintf("%s/cluster_autoscaling/0/auto_provisioning_defaults/0/service_account", [cluster_path])
	denied_with(patched(set(path, "123-compute@developer.gserviceaccount.com")), "default account of Compute Engine")
}

test_s15_rejects_a_node_account_without_its_role if {
	denied_with(patched(set("/resource/google_project_iam_member/nodes/0/role", "roles/viewer")), "grants roles/container.defaultNodeServiceAccount")
}

# Condition 5.

test_s15_rejects_a_cluster_without_dns_endpoint_config if {
	path := sprintf("%s/control_plane_endpoints_config/0/dns_endpoint_config", [cluster_path])
	denied_with(patched(drop(path)), "allow_external_traffic is not written out")
}

test_s15_rejects_an_unwritten_allow_external_traffic if {
	path := sprintf("%s/control_plane_endpoints_config/0/dns_endpoint_config/0/allow_external_traffic", [cluster_path])
	denied_with(patched(drop(path)), "allow_external_traffic is not written out")
}

test_s15_accepts_external_traffic_refused if {
	path := sprintf("%s/control_plane_endpoints_config/0/dns_endpoint_config/0/allow_external_traffic", [cluster_path])
	accepted(patched(set(path, false)))
}

test_s15_rejects_the_ip_endpoint_on if {
	path := sprintf("%s/control_plane_endpoints_config/0/ip_endpoints_config/0/enabled", [cluster_path])
	denied_with(patched(set(path, true)), "IP endpoint of the control plane is not disabled")
}

test_s15_rejects_an_ip_endpoint_left_to_its_default if {
	path := sprintf("%s/control_plane_endpoints_config/0/ip_endpoints_config", [cluster_path])
	denied_with(patched(drop(path)), "IP endpoint of the control plane is not disabled")
}

test_s15_rejects_public_nodes if {
	denied_with(patched(drop(sprintf("%s/private_cluster_config", [cluster_path]))), "the nodes are not private")
}

# Condition 6.

test_s15_rejects_a_public_ip_on_cloud_sql if {
	path := "/resource/google_sql_database_instance/main/0/settings/0/ip_configuration/0/ipv4_enabled"
	denied_with(patched(set(path, true)), "the instance has a public IP")
}

test_s15_rejects_a_public_ip_left_to_its_default if {
	path := "/resource/google_sql_database_instance/main/0/settings/0/ip_configuration"
	denied_with(patched(drop(path)), "the instance has a public IP")
}

test_s15_rejects_a_memorystore_without_tier if {
	denied_with(patched(set("/resource/google_redis_instance", {"cache": [{"memory_size_gb": 1}]})), "the tier of Memorystore is not written out")
}

# Condition 8.

test_s15_rejects_a_module_pulled_by_tag if {
	denied_with(patched(set("/module/net", [{"source": "git::https://github.com/org/modules.git//net?ref=v60.0.0"}])), "ADR-008, condition 8): gcp/tofu/main.tf: module.net")
}

test_s15_rejects_a_registry_module if {
	denied_with(patched(set("/module/sql", [{"source": "terraform-google-modules/sql-db/google", "version": "26.0.0"}])), "module.sql comes from")
}

test_s15_rejects_a_full_sha_with_depth if {
	denied_with(patched(set("/module/net", [{"source": "git::https://github.com/org/m.git?ref=0123456789abcdef0123456789abcdef01234567&depth=1"}])), "module.net comes from")
}

test_s15_accepts_a_module_at_a_full_sha if {
	accepted(patched(set("/module/net", [{"source": "git::https://github.com/org/m.git//net?ref=0123456789abcdef0123456789abcdef01234567"}])))
}

test_s15_names_the_condition_in_each_message if {
	msgs := deny with input as patched(swap("/terraform/0", {}))
	count(msgs) > 0
	every msg in msgs {
		startswith(msg, "S15 (FR-011, FR-012; ADR-008, ")
	}
}
