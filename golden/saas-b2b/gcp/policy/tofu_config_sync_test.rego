# Tests of S15 for Config Sync (tofu_config_sync.rego), run by
# `conftest verify`. Each case changes one thing in a valid root.
package tofu_config_sync

valid := {"resource": {
	"google_container_cluster": {"main": [{"fleet": [{"project": "${var.project_id}"}]}]},
	"google_gke_hub_feature": {"configmanagement": [{"name": "configmanagement", "location": "global"}]},
	"google_gke_hub_feature_membership": {"configmanagement": [{
		"feature": "${google_gke_hub_feature.configmanagement.name}",
		"configmanagement": [{
			"version": "1.25.2",
			"management": "MANAGEMENT_MANUAL",
			"config_sync": [{"enabled": true}],
		}],
	}]},
}}

files(contents) := [{"path": "gcp/tofu/main.tf", "contents": contents}]

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

cm_path := "/resource/google_gke_hub_feature_membership/configmanagement/0/configmanagement/0"

test_s15_accepts_a_valid_root if {
	accepted(files(valid))
}

test_s15_rejects_a_cluster_outside_any_fleet if {
	denied_with(patched(drop("/resource/google_container_cluster/main/0/fleet")), "the cluster joins no fleet")
}

test_s15_rejects_a_cluster_without_config_sync if {
	denied_with(patched(drop("/resource/google_gke_hub_feature_membership")), "no google_gke_hub_feature_membership turns Config Sync on")
}

test_s15_rejects_config_sync_turned_off if {
	denied_with(patched(set(sprintf("%s/config_sync/0/enabled", [cm_path]), false)), "turns Config Sync on")
}

test_s15_rejects_a_missing_version if {
	denied_with(patched(drop(sprintf("%s/version", [cm_path]))), "configmanagement.version '' is not a pinned version")
}

test_s15_rejects_a_minor_only if {
	denied_with(patched(set(sprintf("%s/version", [cm_path]), "1.25")), "configmanagement.version '1.25' is not a pinned version")
}

test_s15_rejects_a_version_from_a_variable if {
	denied_with(patched(set(sprintf("%s/version", [cm_path]), "${var.config_sync_version}")), "is not a pinned version")
}

test_s15_rejects_automatic_upgrades if {
	denied_with(patched(set(sprintf("%s/management", [cm_path]), "MANAGEMENT_AUTOMATIC")), "configmanagement.management is 'MANAGEMENT_AUTOMATIC'")
}

test_s15_rejects_an_unwritten_management if {
	denied_with(patched(drop(sprintf("%s/management", [cm_path]))), "configmanagement.management is ''")
}

test_s15_names_its_rule_in_each_message if {
	msgs := deny with input as patched(drop("/resource/google_container_cluster/main/0/fleet"))
	count(msgs) > 0
	every msg in msgs {
		startswith(msg, "S15 (FR-011, FR-012; ADR-010")
	}
}
