# Tests of S15 for the demo profile (tofu_finops.rego), run by
# `conftest verify`. Each case changes one thing in a valid root, written as
# conftest parses HCL.
package tofu_finops

label_var := {"validation": [{"condition": "${can(regex(\"^[a-z0-9_-]{1,63}$\", var.x))}"}]}

size_var(condition) := {"validation": [{"condition": condition}]}

tier_var := {"validation": [{"condition": "${can(regex(\"^(db-f1-micro|db-g1-small|db-custom-[12]-[0-9]+)$\", var.database_tier))}"}]}

instance := {"settings": [{
	"tier": "${var.database_tier}",
	"edition": "ENTERPRISE",
	"availability_type": "ZONAL",
	"disk_autoresize_limit": "${var.disk_limit}",
	"user_labels": "${local.labels}",
	"backup_configuration": [{
		"enabled": true,
		"point_in_time_recovery_enabled": false,
		"backup_retention_settings": [{"retained_backups": "${var.retained}", "retention_unit": "COUNT"}],
	}],
}]}

valid := {
	"variable": {
		"owner": [label_var],
		"env": [label_var],
		"ttl": [label_var],
		"database_tier": [tier_var],
		"disk_limit": [size_var("${var.disk_limit >= 10}")],
		"retained": [size_var("${var.retained >= 1}")],
	},
	"locals": [{"labels": "${merge({app = var.name}, {owner = var.owner, env = var.env, ttl = var.ttl})}"}],
	"resource": {
		"google_sql_database_instance": {"main": [instance]},
		"google_container_cluster": {"main": [{"resource_labels": "${local.labels}"}]},
		"google_artifact_registry_repository": {"images": [{"labels": "${local.labels}"}]},
		"google_secret_manager_secret": {"db_auth": [{"labels": "${local.labels}"}]},
		"google_memorystore_instance": {"cache": [{"labels": "${local.labels}"}]},
		"google_network_connectivity_service_connection_policy": {"cache": [{"labels": "${local.labels}"}]},
		"google_compute_subnetwork": {"main": [{"log_config": [{
			"aggregation_interval": "INTERVAL_15_MIN",
			"flow_sampling": 0.1,
			"metadata": "EXCLUDE_ALL_METADATA",
		}]}]},
	},
}

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

settings_path := "/resource/google_sql_database_instance/main/0/settings/0"

backup_path := sprintf("%s/backup_configuration/0", [settings_path])

log_path := "/resource/google_compute_subnetwork/main/0/log_config/0"

with_pattern(name, pattern) := swap(
	sprintf("/variable/%s/0/validation/0/condition", [name]),
	sprintf("${can(regex(\"%s\", var.%s))}", [pattern, name]),
)

test_s15_accepts_a_valid_root if {
	accepted(files(valid))
}

test_s15_ignores_an_input_without_opentofu_file if {
	accepted([{"path": "values.yaml", "contents": {"anything": true}}])
}

# Labels

test_s15_rejects_a_missing_ttl_variable if {
	denied_with(patched(drop("/variable/ttl")), "variable ttl is missing")
}

test_s15_rejects_a_missing_owner_variable if {
	denied_with(patched(drop("/variable/owner")), "variable owner is missing")
}

test_s15_rejects_a_missing_env_variable if {
	denied_with(patched(drop("/variable/env")), "variable env is missing")
}

test_s15_rejects_a_label_with_a_default if {
	denied_with(patched(set("/variable/env/0/default", "demo")), "variable env has a default")
}

test_s15_rejects_a_label_without_validation if {
	denied_with(patched(swap("/variable/owner/0", {"type": "${string}"})), "variable owner has no validation block")
}

test_s15_rejects_a_label_validation_without_pattern if {
	denied_with(patched(swap("/variable/owner/0/validation/0/condition", "${length(var.owner) > 0}")), "variable owner: no validation block with a regex")
}

test_s15_rejects_a_label_validation_that_takes_capitals if {
	denied_with(patched(with_pattern("owner", "^[A-Za-z0-9_-]{1,63}$")), "its validation accepts 'Demo'")
}

test_s15_rejects_a_label_validation_without_length_limit if {
	denied_with(patched(with_pattern("env", "^[a-z0-9_-]+$")), "its validation accepts 'aaaaaaaa")
}

test_s15_rejects_a_label_validation_that_refuses_a_date if {
	denied_with(patched(with_pattern("ttl", "^[a-z_-]{1,63}$")), "its validation refuses '2026-12-31'")
}

test_s15_rejects_a_label_validation_that_takes_dots if {
	denied_with(patched(with_pattern("ttl", "^[a-z0-9._-]{1,63}$")), "its validation accepts 'a.b'")
}

test_s15_rejects_labels_that_miss_a_variable if {
	denied_with(patched(swap("/locals/0/labels", "${merge({app = var.name}, {owner = var.owner, env = var.env})}")), "no locals block builds labels with var.ttl")
}

test_s15_rejects_a_cluster_without_the_labels if {
	denied_with(patched(swap("/resource/google_container_cluster/main/0/resource_labels", {"app": "x"})), "resource_labels is not local.labels")
}

test_s15_rejects_a_registry_without_the_labels if {
	denied_with(patched(drop("/resource/google_artifact_registry_repository/images/0/labels")), "labels is not local.labels")
}

test_s15_rejects_a_secret_without_the_labels if {
	denied_with(patched(drop("/resource/google_secret_manager_secret/db_auth/0/labels")), "labels is not local.labels")
}

test_s15_rejects_a_cache_without_the_labels if {
	denied_with(patched(drop("/resource/google_memorystore_instance/cache/0/labels")), "google_memorystore_instance.cache: labels is not local.labels")
}

test_s15_rejects_a_connection_policy_without_the_labels if {
	denied_with(patched(swap("/resource/google_network_connectivity_service_connection_policy/cache/0/labels", {"app": "x"})), "service_connection_policy.cache: labels is not local.labels")
}

test_s15_rejects_a_database_without_the_labels if {
	denied_with(patched(drop(sprintf("%s/user_labels", [settings_path]))), "settings.user_labels is not local.labels")
}

# Cloud SQL sizes

test_s15_rejects_a_literal_tier if {
	denied_with(patched(swap(sprintf("%s/tier", [settings_path]), "db-f1-micro")), "tier does not come from a variable")
}

test_s15_rejects_a_tier_with_a_default if {
	denied_with(patched(set("/variable/database_tier/0/default", "db-f1-micro")), "variable database_tier has a default")
}

test_s15_rejects_a_tier_without_validation if {
	denied_with(patched(swap("/variable/database_tier/0", {"type": "${string}"})), "variable database_tier has no validation block")
}

test_s15_rejects_a_tier_validation_without_pattern if {
	denied_with(patched(swap("/variable/database_tier/0/validation/0/condition", "${startswith(var.database_tier, \"db-\")}")), "variable database_tier: no validation block with a regex")
}

test_s15_rejects_a_tier_above_two_vcpu if {
	denied_with(patched(with_pattern("database_tier", "^(db-f1-micro|db-g1-small|db-custom-[0-9]+-[0-9]+)$")), "accepts the tier 'db-custom-4-15360'")
}

test_s15_rejects_a_tier_validation_that_takes_any_tier if {
	denied_with(patched(with_pattern("database_tier", "^db-.*$")), "accepts the tier 'db-n1-standard-1'")
}

test_s15_rejects_a_tier_validation_that_takes_twelve_vcpu if {
	denied_with(patched(with_pattern("database_tier", "^(db-f1-micro|db-g1-small|db-custom-[12][0-9]*-[0-9]+)$")), "accepts the tier 'db-custom-12-9216'")
}

test_s15_rejects_a_tier_validation_that_refuses_shared_core if {
	denied_with(patched(with_pattern("database_tier", "^db-custom-[12]-[0-9]+$")), "refuses the tier 'db-f1-micro'")
}

test_s15_rejects_a_missing_disk_limit if {
	denied_with(patched(drop(sprintf("%s/disk_autoresize_limit", [settings_path]))), "disk_autoresize_limit does not come from a variable")
}

test_s15_rejects_a_literal_disk_limit if {
	denied_with(patched(swap(sprintf("%s/disk_autoresize_limit", [settings_path]), 100)), "disk_autoresize_limit does not come from a variable")
}

test_s15_rejects_a_disk_limit_with_a_default if {
	denied_with(patched(set("/variable/disk_limit/0/default", 100)), "variable disk_limit has a default")
}

test_s15_rejects_a_disk_limit_without_validation if {
	denied_with(patched(swap("/variable/disk_limit/0", {"type": "${number}"})), "variable disk_limit has no validation block")
}

test_s15_rejects_a_missing_retention if {
	denied_with(patched(drop(sprintf("%s/backup_retention_settings", [backup_path]))), "retained_backups does not come from a variable")
}

test_s15_rejects_a_retention_with_a_default if {
	denied_with(patched(set("/variable/retained/0/default", 7)), "variable retained has a default")
}

test_s15_rejects_a_retention_without_validation if {
	denied_with(patched(swap("/variable/retained/0", {"type": "${number}"})), "variable retained has no validation block")
}

test_s15_rejects_an_unwritten_point_in_time_recovery if {
	denied_with(patched(drop(sprintf("%s/point_in_time_recovery_enabled", [backup_path]))), "point_in_time_recovery_enabled is not written")
}

test_s15_accepts_point_in_time_recovery_written_on if {
	accepted(patched(swap(sprintf("%s/point_in_time_recovery_enabled", [backup_path]), true)))
}

test_s15_rejects_the_enterprise_plus_edition if {
	denied_with(patched(swap(sprintf("%s/edition", [settings_path]), "ENTERPRISE_PLUS")), "edition is 'ENTERPRISE_PLUS'")
}

test_s15_rejects_an_unwritten_edition if {
	denied_with(patched(drop(sprintf("%s/edition", [settings_path]))), "edition is ''")
}

test_s15_rejects_high_availability if {
	denied_with(patched(swap(sprintf("%s/availability_type", [settings_path]), "REGIONAL")), "availability_type is 'REGIONAL'")
}

# VPC flow logs

test_s15_rejects_the_default_aggregation_interval if {
	denied_with(patched(drop(sprintf("%s/aggregation_interval", [log_path]))), "aggregation_interval is 'INTERVAL_5_SEC'")
}

test_s15_rejects_a_ten_minute_interval if {
	denied_with(patched(swap(sprintf("%s/aggregation_interval", [log_path]), "INTERVAL_10_MIN")), "aggregation_interval is 'INTERVAL_10_MIN'")
}

test_s15_rejects_the_default_sampling if {
	denied_with(patched(drop(sprintf("%s/flow_sampling", [log_path]))), "flow_sampling is 0.5")
}

test_s15_rejects_a_high_sampling if {
	denied_with(patched(swap(sprintf("%s/flow_sampling", [log_path]), 0.5)), "flow_sampling is 0.5")
}

test_s15_rejects_a_sampling_of_zero if {
	denied_with(patched(swap(sprintf("%s/flow_sampling", [log_path]), 0)), "flow_sampling is 0")
}

test_s15_accepts_a_lower_sampling if {
	accepted(patched(swap(sprintf("%s/flow_sampling", [log_path]), 0.05)))
}

test_s15_rejects_all_metadata if {
	denied_with(patched(swap(sprintf("%s/metadata", [log_path]), "INCLUDE_ALL_METADATA")), "log_config.metadata is INCLUDE_ALL_METADATA")
}

test_s15_rejects_default_metadata if {
	denied_with(patched(drop(sprintf("%s/metadata", [log_path]))), "log_config.metadata is INCLUDE_ALL_METADATA")
}

test_s15_rejects_flow_logs_that_are_missing if {
	denied_with(patched(drop("/resource/google_compute_subnetwork/main/0/log_config")), "aggregation_interval is 'INTERVAL_5_SEC'")
}

test_s15_names_the_risk_in_each_message if {
	msgs := deny with input as patched(drop("/variable/ttl"))
	count(msgs) > 0
	every msg in msgs {
		startswith(msg, "S15 (R-05, R-17, R-18;")
	}
}
