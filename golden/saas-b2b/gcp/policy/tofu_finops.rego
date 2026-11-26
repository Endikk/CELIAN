# S15: the demo profile of R-05 and R-17 that the HCL of the gcp layer shows
# without any cloud (spec 001, FR-011): the labels owner, env and ttl, the
# sizes of Cloud SQL chosen by the user and bounded, the volume of the VPC flow
# logs. Each size or label comes from a variable with no default, so that no
# value is chosen here before [FINOPS] validates a budget; each such variable
# carries a validation block, and this package tries sample values against its
# pattern, because `tofu validate` never runs a validation (no value is given).
#
# Input: the files given to `conftest test --combine`, a list of objects with
# a `path` and the parsed `contents` (research RS-18). Only the .tf files are
# read. The patterns are read as written in `regex("<pattern>", var.x)`: OpenTofu
# and Rego both use the RE2 syntax, and a pattern holds no backslash.
package tofu_finops

label(topic) := sprintf("S15 (R-05, R-17, R-18; %s)", [topic])

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

variables contains {"path": file.path, "name": name, "body": body} if {
	some file in tf_files
	some name, bodies in object.get(file.contents, "variable", {})
	some body in bodies
}

blocks_of(type) := {block | some block in resources; block.type == type}

variable_named(name) := {v | some v in variables; v.name == name}

where(block) := sprintf("%s: %s.%s", [block.path, block.type, block.name])

first(body, key) := object.get(body, key, [{}])[0]

# Name N of a value written exactly "${var.N}", nothing else.
var_ref(value) := name if {
	is_string(value)
	matches := regex.find_all_string_submatch_n(`^\$\{var\.([A-Za-z0-9_]+)\}$`, value, 1)
	name := matches[0][1]
}

# The patterns of the regex("<pattern>", ...) calls in the validation blocks.
patterns(body) := {pattern |
	some validation in object.get(body, "validation", [])
	some match in regex.find_all_string_submatch_n(`regex\("([^"]*)"`, object.get(validation, "condition", ""), -1)
	pattern := match[1]
}

repeat(char, n) := concat("", [c | some _ in numbers.range(1, n); c := char])

# Labels: R-05.

required_labels := ["owner", "env", "ttl"]

# GCP label values: lower-case letters, digits, hyphens, underscores, 63
# characters at most. A date such as 2026-12-31 must pass.
label_accepted := ["demo", "dev-1", "a_b-c", "2026-12-31", "x", repeat("a", 63)]

label_refused := ["", "Demo", "a b", "a.b", "2026/12/31", "a@b", repeat("a", 64)]

deny contains msg if {
	count(tf_files) > 0
	some name in required_labels
	count(variable_named(name)) == 0
	msg := sprintf("%s: variable %s is missing; the label %s of R-05 has no input", [label("labels"), name, name])
}

deny contains msg if {
	some name in required_labels
	some v in variable_named(name)
	some pattern in patterns(v.body)
	some sample in label_accepted
	not regex.match(pattern, sample)
	msg := sprintf("%s: %s: variable %s: its validation refuses '%v', a valid GCP label value", [label("labels"), v.path, name, sample])
}

deny contains msg if {
	some name in required_labels
	some v in variable_named(name)
	some pattern in patterns(v.body)
	some sample in label_refused
	regex.match(pattern, sample)
	msg := sprintf("%s: %s: variable %s: its validation accepts '%v', which is not a valid GCP label value", [label("labels"), v.path, name, sample])
}

deny contains msg if {
	some name in required_labels
	some v in variable_named(name)
	count(patterns(v.body)) == 0
	msg := sprintf("%s: %s: variable %s: no validation block with a regex(\"<pattern>\", var.%s) condition", [label("labels"), v.path, name, name])
}

# The three labels reach local.labels.
deny contains msg if {
	count(tf_files) > 0
	some name in required_labels
	not label_in_locals(name)
	msg := sprintf("%s: no locals block builds labels with var.%s", [label("labels"), name])
}

label_in_locals(name) if {
	some file in tf_files
	some block in object.get(file.contents, "locals", [])
	is_string(block.labels)
	regex.match(sprintf(`var\.%s([^A-Za-z0-9_]|$)`, [name]), block.labels)
}

# Each resource that takes labels takes local.labels.
labelled := {
	"google_container_cluster": "resource_labels",
	"google_artifact_registry_repository": "labels",
	"google_secret_manager_secret": "labels",
	"google_memorystore_instance": "labels",
	"google_network_connectivity_service_connection_policy": "labels",
}

deny contains msg if {
	some type, key in labelled
	some block in blocks_of(type)
	object.get(block.body, key, "") != "${local.labels}"
	msg := sprintf("%s: %s: %s is not local.labels", [label("labels"), where(block), key])
}

deny contains msg if {
	some block in blocks_of("google_sql_database_instance")
	object.get(first(block.body, "settings"), "user_labels", "") != "${local.labels}"
	msg := sprintf("%s: %s: settings.user_labels is not local.labels", [label("labels"), where(block)])
}

# Cloud SQL: R-05 and R-17, demo profile decided by the DSI (zonal, no high
# availability, ENTERPRISE edition, at most 2 vCPU).

tier_accepted := ["db-f1-micro", "db-g1-small", "db-custom-1-3840", "db-custom-2-7680"]

tier_refused := [
	"", "DB-F1-MICRO", "db-f1-micro-2", "db-n1-standard-1", "db-perf-optimized-N-2",
	"db-custom-0-1024", "db-custom-3-11520", "db-custom-4-15360", "db-custom-12-9216",
	"db-custom-16-61440", "db-custom-1-",
]

instances := blocks_of("google_sql_database_instance")

settings_of(instance) := first(instance.body, "settings")

backup_of(instance) := first(settings_of(instance), "backup_configuration")

# The variable that each size comes from, by the setting that reads it.
sized_ref(instance, "tier") := var_ref(object.get(settings_of(instance), "tier", ""))

sized_ref(instance, "disk_autoresize_limit") := var_ref(object.get(settings_of(instance), "disk_autoresize_limit", ""))

sized_ref(instance, "retained_backups") := var_ref(object.get(first(backup_of(instance), "backup_retention_settings"), "retained_backups", ""))

sized_settings := ["tier", "disk_autoresize_limit", "retained_backups"]

sized_names contains name if {
	some instance in instances
	some setting in sized_settings
	name := sized_ref(instance, setting)
}

deny contains msg if {
	some instance in instances
	some setting in sized_settings
	not sized_ref(instance, setting)
	msg := sprintf("%s: %s: %s does not come from a variable (\"${var.<name>}\"); the user chooses it, bounded by a validation", [label("cloud sql"), where(instance), setting])
}

# Required without default and validated: the labels and each size.
checked_names contains name if {
	some name in required_labels
}

checked_names contains name if {
	some name in sized_names
}

deny contains msg if {
	some name in checked_names
	some v in variable_named(name)
	"default" in object.keys(v.body)
	msg := sprintf("%s: %s: variable %s has a default; no value is chosen here before [FINOPS] validates a budget", [label("no default"), v.path, name])
}

deny contains msg if {
	some name in checked_names
	some v in variable_named(name)
	count(object.get(v.body, "validation", [])) == 0
	msg := sprintf("%s: %s: variable %s has no validation block", [label("validation"), v.path, name])
}

deny contains msg if {
	some instance in instances
	name := sized_ref(instance, "tier")
	some v in variable_named(name)
	count(patterns(v.body)) == 0
	msg := sprintf("%s: %s: variable %s: no validation block with a regex(\"<pattern>\", var.%s) condition", [label("cloud sql tier"), v.path, name, name])
}

deny contains msg if {
	some instance in instances
	name := sized_ref(instance, "tier")
	some v in variable_named(name)
	some pattern in patterns(v.body)
	some sample in tier_refused
	regex.match(pattern, sample)
	msg := sprintf("%s: %s: variable %s: its validation accepts the tier '%v', above the demo profile (2 vCPU at most)", [label("cloud sql tier"), v.path, name, sample])
}

deny contains msg if {
	some instance in instances
	name := sized_ref(instance, "tier")
	some v in variable_named(name)
	some pattern in patterns(v.body)
	some sample in tier_accepted
	not regex.match(pattern, sample)
	msg := sprintf("%s: %s: variable %s: its validation refuses the tier '%v' of the demo profile", [label("cloud sql tier"), v.path, name, sample])
}

deny contains msg if {
	some instance in instances
	edition := object.get(settings_of(instance), "edition", "")
	edition != "ENTERPRISE"
	msg := sprintf("%s: %s: edition is '%v'; the tiers of the demo profile need ENTERPRISE", [label("cloud sql"), where(instance), edition])
}

deny contains msg if {
	some instance in instances
	availability := object.get(settings_of(instance), "availability_type", "")
	availability != "ZONAL"
	msg := sprintf("%s: %s: availability_type is '%v'; the demo profile is ZONAL, without high availability", [label("cloud sql"), where(instance), availability])
}

deny contains msg if {
	some instance in instances
	not is_boolean(object.get(backup_of(instance), "point_in_time_recovery_enabled", null))
	msg := sprintf("%s: %s: backup_configuration.point_in_time_recovery_enabled is not written; the provider leaves it to the edition", [label("cloud sql"), where(instance)])
}

# VPC flow logs: on, at the lowest volume of the demo profile (R-18).

max_sampling := 0.1

deny contains msg if {
	some subnet in blocks_of("google_compute_subnetwork")
	interval := object.get(first(subnet.body, "log_config"), "aggregation_interval", "INTERVAL_5_SEC")
	interval != "INTERVAL_15_MIN"
	msg := sprintf("%s: %s: log_config.aggregation_interval is '%v'; the demo profile uses INTERVAL_15_MIN", [label("flow logs"), where(subnet), interval])
}

deny contains msg if {
	some subnet in blocks_of("google_compute_subnetwork")
	sampling := object.get(first(subnet.body, "log_config"), "flow_sampling", 0.5)
	not valid_sampling(sampling)
	msg := sprintf("%s: %s: log_config.flow_sampling is %v; the demo profile keeps it above 0 and at %v at most", [label("flow logs"), where(subnet), sampling, max_sampling])
}

valid_sampling(sampling) if {
	is_number(sampling)
	sampling > 0
	sampling <= max_sampling
}

deny contains msg if {
	some subnet in blocks_of("google_compute_subnetwork")
	metadata := object.get(first(subnet.body, "log_config"), "metadata", "INCLUDE_ALL_METADATA")
	metadata == "INCLUDE_ALL_METADATA"
	msg := sprintf("%s: %s: log_config.metadata is INCLUDE_ALL_METADATA; the demo profile reduces it", [label("flow logs"), where(subnet)])
}
