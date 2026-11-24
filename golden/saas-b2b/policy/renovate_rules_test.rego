# Tests of S23, rules that follow platform.yaml (renovate_rules.rego), run by
# `conftest verify`. The delay has its tests in renovate_delay_test.rego.
package renovate_rules

import data.renovate_delay

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

# Both renovate.json files, the one of CELIAN and the one of the golden repo,
# write these entries, then the entry of ADR-016. The two packages accept
# that layout, and no image is caught both by the entry of ADR-016 and by an
# entry of this package, so their order does not change what Renovate does.

test_s23_accepts_the_rules_before_the_entry_of_adr_016_in_both_packages if {
    rules := array.concat(valid_rules, [renovate_delay.undated_registries_rule])
    files := checked(config_with(rules), valid_platform)
    accepted(files)
    count(renovate_delay.deny) == 0 with input as files
}

test_s23_the_entry_of_adr_016_catches_no_watched_image if {
    every name in watched_names {
        not catches(renovate_delay.undated_registries_rule, name)
    }
}

test_s23_the_watched_entries_catch_no_image_of_adr_016 if {
    undated_images := {"ghcr.io/gitleaks/gitleaks", "ghcr.io/project-zot/zot", "quay.io/keycloak/keycloak", "mcr.microsoft.com/dotnet/aspnet"}
    every rule in valid_rules {
        not catches_any(rule, undated_images)
    }
}

test_s23_accepts_exact_names_and_case_insensitive_regexes if {
	rule := with_value(postgres_rule, "matchPackageNames", ["postgres", "library/postgres", "/^DOCKER\\.IO/library/postgres$/i"])
	accepted(checked(config_with([rule, node_rule, kind_group, envoy_group]), valid_platform))
}

# Shape of the input.

test_s23_rejects_an_input_without_platform_yaml if {
	denied_with([{"path": "renovate.json", "contents": valid_config}], "expected one platform.yaml among the checked files, found 0")
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
	count(msgs) == 4
	every msg in msgs {
		startswith(msg, "S23 (FR-013")
	}
}
