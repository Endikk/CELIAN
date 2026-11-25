# Tests of S15 for ADR-007, condition 2 (tofu_secret_sync.rego), run by
# `conftest verify`. Each case changes one thing in a valid root.
package tofu_secret_sync

principal := "principal://iam.googleapis.com/projects/1/locations/global/workloadIdentityPools/p.svc.id.goog/subject/ns/app/sa/api"

valid := {"resource": {
	"google_container_cluster": {"main": [{
		"min_master_version": "${local.platform.kubernetes_minor}",
		"secret_sync_config": [{"enabled": true}],
	}]},
	"google_secret_manager_secret": {"db_auth": [{"for_each": "${local.db_auth_secrets}"}]},
	"google_secret_manager_secret_iam_member": {"db_auth": [{"role": "roles/secretmanager.secretAccessor", "member": principal}]},
	"google_project_iam_member": {"nodes": [{"role": "roles/container.defaultNodeServiceAccount", "member": "serviceAccount:n"}]},
}}

files_with(contents, minor) := [
	{"path": "gcp/tofu/main.tf", "contents": contents},
	{"path": "platform.yaml", "contents": {"kubernetes_minor": minor, "postgres_major": "18"}},
]

files(contents) := files_with(contents, "1.36")

patched(ops) := files(json.patch(valid, ops))

set(path, value) := [{"op": "add", "path": path, "value": value}]

drop(path) := [{"op": "remove", "path": path}]

accepted(input_files) if {
	msgs := deny with input as input_files
	count(msgs) == 0
}

denied_with(input_files, fragment) if {
	msgs := deny with input as input_files
	some msg in msgs
	contains(msg, fragment)
}

cluster := "/resource/google_container_cluster/main/0"

version_path := sprintf("%s/min_master_version", [cluster])

with_rotation(interval) := set(sprintf("%s/secret_sync_config/0/rotation_config", [cluster]), [{"enabled": true, "rotation_interval": interval}])

# Three secrets written one by one, without for_each.
three_secrets := set("/resource/google_secret_manager_secret", {"a": [{}], "b": [{}], "c": [{}]})

test_s15_accepts_a_valid_root if {
	accepted(files(valid))
}

# Access to the secrets.

test_s15_rejects_the_accessor_role_on_the_project if {
	grant := {"role": "roles/secretmanager.secretAccessor", "member": principal}
	denied_with(patched(set("/resource/google_project_iam_member/reader", [grant])), "granted at the project level")
}

test_s15_rejects_the_accessor_role_in_a_project_binding if {
	grant := {"role": "roles/secretmanager.secretAccessor", "members": [principal]}
	denied_with(patched(set("/resource/google_project_iam_binding", {"reader": [grant]})), "granted at the project level")
}

test_s15_rejects_a_service_account_as_reader if {
	path := "/resource/google_secret_manager_secret_iam_member/db_auth/0/member"
	denied_with(patched(set(path, "serviceAccount:app@p.iam.gserviceaccount.com")), "goes to serviceAccount:app@p.iam.gserviceaccount.com")
}

test_s15_rejects_a_principal_set_as_reader if {
	path := "/resource/google_secret_manager_secret_iam_member/db_auth/0/member"
	denied_with(patched(set(path, "principalSet://iam.googleapis.com/projects/1/locations/global/workloadIdentityPools/p.svc.id.goog/namespace/app")), "only the Workload Identity principal")
}

test_s15_rejects_one_wrong_member_of_a_binding if {
	grant := {"role": "roles/secretmanager.secretAccessor", "members": [principal, "allAuthenticatedUsers"]}
	denied_with(patched(set("/resource/google_secret_manager_secret_iam_binding", {"db": [grant]})), "goes to allAuthenticatedUsers")
}

# The sync.

test_s15_rejects_a_cluster_without_the_sync if {
	denied_with(patched(drop(sprintf("%s/secret_sync_config", [cluster]))), "the secret sync of GKE is not on")
}

test_s15_rejects_the_sync_turned_off if {
	denied_with(patched(set(sprintf("%s/secret_sync_config/0/enabled", [cluster]), false)), "the secret sync of GKE is not on")
}

test_s15_rejects_the_default_rotation_interval if {
	ops := array.concat(three_secrets, with_rotation("120s"))
	denied_with(patched(ops), "rotation_interval '120s' is under 900s")
}

test_s15_rejects_an_interval_not_in_seconds if {
	ops := array.concat(three_secrets, with_rotation("15m"))
	denied_with(patched(ops), "rotation_interval '15m'")
}

test_s15_rejects_a_rotation_without_interval if {
	ops := array.concat(three_secrets, set(sprintf("%s/secret_sync_config/0/rotation_config", [cluster]), [{"enabled": true}]))
	denied_with(patched(ops), "rotation_interval ''")
}

test_s15_accepts_fifteen_minutes_for_three_secrets if {
	accepted(patched(array.concat(three_secrets, with_rotation("900s"))))
}

test_s15_rejects_a_rotation_over_secrets_counted_by_for_each if {
	denied_with(patched(with_rotation("900s")), "counts its secrets with for_each")
}

test_s15_rejects_a_rotation_over_four_secrets if {
	four := set("/resource/google_secret_manager_secret", {"a": [{}], "b": [{}], "c": [{}], "d": [{}]})
	denied_with(patched(array.concat(four, with_rotation("900s"))), "rotation is on with 4 secret blocks")
}

# Version of the cluster.

test_s15_rejects_a_cluster_without_version if {
	denied_with(patched(drop(version_path)), "no min_master_version")
}

test_s15_rejects_latest if {
	denied_with(patched(set(version_path, "latest")), "version 'latest' may resolve under")
}

test_s15_rejects_a_variable_as_version if {
	denied_with(patched(set(version_path, "${var.version}")), "it cannot be checked")
}

test_s15_rejects_a_bare_minor_1_35 if {
	denied_with(patched(set(version_path, "1.35")), "version '1.35' may resolve under")
}

test_s15_rejects_the_bare_patch_of_the_minimum if {
	denied_with(patched(set(version_path, "1.35.5")), "version '1.35.5' may resolve under")
}

test_s15_rejects_one_build_under_the_minimum if {
	denied_with(patched(set(version_path, "1.35.5-gke.1163011")), "may resolve under")
}

test_s15_accepts_the_minimum if {
	accepted(patched(set(version_path, "1.35.5-gke.1163012")))
}

test_s15_accepts_the_next_patch if {
	accepted(patched(set(version_path, "1.35.6")))
}

test_s15_accepts_a_later_minor if {
	accepted(patched(set(version_path, "1.37")))
}

test_s15_rejects_a_platform_minor_under_the_minimum if {
	denied_with(files_with(valid, "1.35"), "version '1.35' may resolve under")
}

test_s15_reads_the_minor_from_any_local_name if {
	accepted(patched(set(version_path, "${local.shared.kubernetes_minor}")))
}

test_s15_names_the_condition_in_each_message if {
	msgs := deny with input as patched(drop(sprintf("%s/secret_sync_config", [cluster])))
	count(msgs) > 0
	every msg in msgs {
		startswith(msg, "S15 (FR-011, FR-012; ADR-007, condition 2)")
	}
}
