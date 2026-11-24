# Tests of S23 (renovate_rules.rego), run by `conftest verify`.
package renovate_rules

postgres_rule := {
	"matchDatasources": ["docker"],
	"matchPackageNames": ["/^(docker\\.io/)?(library/)?postgres$/"],
	"allowedVersions": "/^18\\./",
}

node_rule := {
	"matchDatasources": ["docker"],
	"matchPackageNames": ["/^(docker\\.io/)?kindest/node$/"],
	"allowedVersions": "/^v1\\.36\\./",
}

kind_group := {
	"matchPackageNames": ["kubernetes-sigs/kind", "/^(docker\\.io/)?kindest/node$/"],
	"groupName": "kind and its node image",
}

envoy_group := {
	"matchDatasources": ["docker"],
	"matchPackageNames": ["/^(docker\\.io/)?envoyproxy/gateway(-helm|-crds-helm)?$/"],
	"groupName": "Envoy Gateway",
}

valid_rules := [postgres_rule, node_rule, kind_group, envoy_group]

celian_presets := ["config:recommended", "helpers:pinGitHubActionDigests", "customManagers:githubActionsVersions"]

config_with(package_rules) := {
	"extends": celian_presets,
	"minimumReleaseAge": "7 days",
	"minimumReleaseAgeBehaviour": "timestamp-required",
	"internalChecksFilter": "strict",
	"vulnerabilityAlerts": {"minimumReleaseAge": null},
	"osvVulnerabilityAlerts": true,
	"packageRules": package_rules,
}

valid_config := config_with(valid_rules)

valid_platform := {"kubernetes_minor": "1.36", "postgres_major": "18"}

with_value(obj, key, value) := object.union(object.remove(obj, {key}), {key: value})

without(obj, key) := object.remove(obj, {key})

checked(renovate, values) := [
	{"path": "renovate.json", "contents": renovate},
	{"path": "platform.yaml", "contents": values},
]

accepted(files) if {
	msgs := deny with input as files
	count(msgs) == 0
}

denied_with(files, fragment) if {
	msgs := deny with input as files
	some msg in msgs
	contains(msg, fragment)
}

test_s23_accepts_the_rules_of_the_constitution_and_the_adrs if {
	accepted(checked(valid_config, valid_platform))
}

test_s23_accepts_files_under_a_folder if {
	accepted([
		{"path": "golden/saas-b2b/renovate.json", "contents": valid_config},
		{"path": "golden/saas-b2b/platform.yaml", "contents": valid_platform},
	])
}

test_s23_accepts_exact_names_and_case_insensitive_regexes if {
	rule := with_value(postgres_rule, "matchPackageNames", ["postgres", "library/postgres", "/^DOCKER\\.IO/library/postgres$/i"])
	accepted(checked(config_with([rule, node_rule, kind_group, envoy_group]), valid_platform))
}

# Shape of the input.

test_s23_rejects_an_input_without_renovate_json if {
	denied_with([{"path": "platform.yaml", "contents": valid_platform}], "expected one renovate.json among the checked files, found 0")
}

test_s23_does_not_take_renovate_json5_for_renovate_json if {
	files := [
		{"path": "renovate.json5", "contents": valid_config},
		{"path": "platform.yaml", "contents": valid_platform},
	]
	denied_with(files, "expected one renovate.json among the checked files, found 0")
}

test_s23_rejects_an_input_without_platform_yaml if {
	denied_with([{"path": "renovate.json", "contents": valid_config}], "expected one platform.yaml among the checked files, found 0")
}

test_s23_rejects_a_renovate_json_that_is_not_an_object if {
	denied_with(checked(["7 days"], valid_platform), "renovate.json must hold a JSON object")
}

test_s23_rejects_package_rules_that_are_not_a_list if {
	denied_with(checked(config_with({"postgres": postgres_rule}), valid_platform), "packageRules must be a list")
}

# Delay of 7 days.

test_s23_rejects_a_shorter_delay if {
	denied_with(checked(with_value(valid_config, "minimumReleaseAge", "3 days"), valid_platform), "minimumReleaseAge must be \"7 days\", found 3 days")
}

test_s23_rejects_a_missing_delay if {
	denied_with(checked(without(valid_config, "minimumReleaseAge"), valid_platform), "minimumReleaseAge must be \"7 days\", found null")
}

test_s23_rejects_a_rule_with_its_own_delay if {
	rule := {"matchPackageNames": ["react"], "minimumReleaseAge": "0 days"}
	renovate := config_with(array.concat(valid_rules, [rule]))
	denied_with(checked(renovate, valid_platform), "[\"packageRules\", 4, \"minimumReleaseAge\"] sets the delay again")
}

test_s23_rejects_a_release_without_a_date_taken_as_stable if {
	renovate := with_value(valid_config, "minimumReleaseAgeBehaviour", "timestamp-optional")
	denied_with(checked(renovate, valid_platform), "minimumReleaseAgeBehaviour must be written out as \"timestamp-required\"")
}

test_s23_rejects_a_rule_that_takes_a_release_without_a_date_as_stable if {
	rule := {"matchDatasources": ["docker"], "minimumReleaseAgeBehaviour": "timestamp-optional"}
	renovate := config_with(array.concat(valid_rules, [rule]))
	denied_with(checked(renovate, valid_platform), "[\"packageRules\", 4, \"minimumReleaseAgeBehaviour\"] sets the delay again")
}

test_s23_rejects_a_delay_set_for_an_update_type if {
	renovate := with_value(valid_config, "digest", {"minimumReleaseAge": null})
	denied_with(checked(renovate, valid_platform), "[\"digest\", \"minimumReleaseAge\"] sets the delay again")
}

test_s23_rejects_internal_checks_that_open_a_pr_during_the_delay if {
	renovate := with_value(valid_config, "internalChecksFilter", "none")
	denied_with(checked(renovate, valid_platform), "internalChecksFilter must be written out as \"strict\"")
}

test_s23_rejects_a_release_age_behaviour_left_to_the_default if {
	renovate := without(valid_config, "minimumReleaseAgeBehaviour")
	denied_with(checked(renovate, valid_platform), "minimumReleaseAgeBehaviour must be written out as \"timestamp-required\"")
}

test_s23_rejects_a_preset_added_to_extends if {
	renovate := with_value(valid_config, "extends", array.concat(celian_presets, ["github>example/presets"]))
	denied_with(checked(renovate, valid_platform), "extends must hold exactly the three presets of CELIAN")
}

# Security exception.

test_s23_rejects_a_missing_security_exception if {
	denied_with(checked(without(valid_config, "vulnerabilityAlerts"), valid_platform), "vulnerabilityAlerts.minimumReleaseAge must be written out as null")
}

test_s23_rejects_a_delay_on_security_fixes if {
	renovate := with_value(valid_config, "vulnerabilityAlerts", {"minimumReleaseAge": "7 days"})
	denied_with(checked(renovate, valid_platform), "vulnerabilityAlerts.minimumReleaseAge must be written out as null")
}

test_s23_rejects_vulnerability_alerts_turned_off if {
	renovate := with_value(valid_config, "vulnerabilityAlerts", {"minimumReleaseAge": null, "enabled": false})
	denied_with(checked(renovate, valid_platform), "vulnerabilityAlerts must stay enabled")
}

test_s23_rejects_osv_alerts_turned_off if {
	denied_with(checked(without(valid_config, "osvVulnerabilityAlerts"), valid_platform), "osvVulnerabilityAlerts must be true")
}

# Postgres.

test_s23_rejects_a_config_without_the_postgres_rule if {
	renovate := config_with([node_rule, kind_group, envoy_group])
	denied_with(checked(renovate, valid_platform), "no packageRules entry keeps the postgres image on allowedVersions /^18\\./")
}

test_s23_rejects_another_postgres_major if {
	rule := with_value(postgres_rule, "allowedVersions", "/^19\\./")
	renovate := config_with([rule, node_rule, kind_group, envoy_group])
	denied_with(checked(renovate, valid_platform), "packageRules[0] sets allowedVersions /^19\\./ for the postgres image")
}

test_s23_follows_the_postgres_major_of_platform_yaml if {
	rule := with_value(postgres_rule, "allowedVersions", "/^19\\./")
	renovate := config_with([rule, node_rule, kind_group, envoy_group])
	accepted(checked(renovate, with_value(valid_platform, "postgres_major", "19")))
}

test_s23_rejects_a_postgres_matcher_that_misses_the_registry_name if {
	rule := with_value(postgres_rule, "matchPackageNames", ["postgres"])
	renovate := config_with([rule, node_rule, kind_group, envoy_group])
	denied_with(checked(renovate, valid_platform), "no packageRules entry keeps the postgres image")
}

test_s23_rejects_a_postgres_rule_for_another_datasource if {
	rule := with_value(postgres_rule, "matchDatasources", ["helm"])
	renovate := config_with([rule, node_rule, kind_group, envoy_group])
	denied_with(checked(renovate, valid_platform), "no packageRules entry keeps the postgres image")
}

test_s23_rejects_a_later_rule_that_widens_postgres if {
	rule := {"matchPackageNames": ["postgres"], "allowedVersions": "/.*/"}
	renovate := config_with(array.concat(valid_rules, [rule]))
	denied_with(checked(renovate, valid_platform), "packageRules[4] sets allowedVersions /.*/ for the postgres image")
}

test_s23_rejects_a_rule_that_turns_off_postgres if {
	rule := {"matchPackageNames": ["/postgres/"], "enabled": false}
	renovate := config_with(array.concat(valid_rules, [rule]))
	denied_with(checked(renovate, valid_platform), "packageRules[4] turns off the updates")
}

# kind and its node image.

test_s23_rejects_another_kubernetes_minor if {
	rule := with_value(node_rule, "allowedVersions", "/^v1\\.37\\./")
	renovate := config_with([postgres_rule, rule, kind_group, envoy_group])
	denied_with(checked(renovate, valid_platform), "no packageRules entry keeps the kind node image on allowedVersions /^v1\\.36\\./")
}

test_s23_follows_the_kubernetes_minor_of_platform_yaml if {
	rule := with_value(node_rule, "allowedVersions", "/^v1\\.37\\./")
	renovate := config_with([postgres_rule, rule, kind_group, envoy_group])
	accepted(checked(renovate, with_value(valid_platform, "kubernetes_minor", "1.37")))
}

test_s23_rejects_a_dot_that_matches_any_character if {
	rule := with_value(node_rule, "allowedVersions", "/^v1.36./")
	renovate := config_with([postgres_rule, rule, kind_group, envoy_group])
	denied_with(checked(renovate, valid_platform), "packageRules[1] sets allowedVersions /^v1.36./ for the kind node image")
}

test_s23_rejects_kind_without_a_group if {
	renovate := config_with([postgres_rule, node_rule, envoy_group])
	denied_with(checked(renovate, valid_platform), "so that kind and its node image move in one PR")
}

test_s23_rejects_a_kind_group_without_the_node_image if {
	group := with_value(kind_group, "matchPackageNames", ["kubernetes-sigs/kind"])
	renovate := config_with([postgres_rule, node_rule, group, envoy_group])
	denied_with(checked(renovate, valid_platform), "so that kind and its node image move in one PR")
}

test_s23_rejects_a_kind_group_limited_to_one_datasource if {
	group := with_value(kind_group, "matchDatasources", ["docker"])
	renovate := config_with([postgres_rule, node_rule, group, envoy_group])
	denied_with(checked(renovate, valid_platform), "so that kind and its node image move in one PR")
}

test_s23_rejects_an_empty_group_name if {
	group := with_value(kind_group, "groupName", "")
	renovate := config_with([postgres_rule, node_rule, group, envoy_group])
	denied_with(checked(renovate, valid_platform), "so that kind and its node image move in one PR")
}

# Envoy Gateway.

test_s23_rejects_an_envoy_group_without_the_controller_image if {
	group := with_value(envoy_group, "matchPackageNames", ["/^(docker\\.io/)?envoyproxy/gateway(-helm|-crds-helm)$/"])
	renovate := config_with([postgres_rule, node_rule, kind_group, group])
	denied_with(checked(renovate, valid_platform), "no packageRules entry puts the charts and the controller image of Envoy Gateway")
}

test_s23_rejects_envoy_gateway_without_a_group if {
	rule := without(envoy_group, "groupName")
	renovate := config_with([postgres_rule, node_rule, kind_group, rule])
	denied_with(checked(renovate, valid_platform), "no packageRules entry puts the charts and the controller image of Envoy Gateway")
}

# Messages.

test_s23_names_its_requirements_in_each_message if {
	msgs := deny with input as checked({}, valid_platform)
	count(msgs) == 10
	every msg in msgs {
		startswith(msg, "S23 (FR-013")
	}
}
