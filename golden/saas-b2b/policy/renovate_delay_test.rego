# Tests of S23, delay part (renovate_delay.rego), run by `conftest verify`.
package renovate_delay

celian_presets := ["config:recommended", "helpers:pinGitHubActionDigests", "customManagers:githubActionsVersions"]

# The entry of ADR-016, as both renovate.json files write it.
undated_rule := {
	"description": "Principle VI, ADR-016: these registries give Renovate no release date, so it cannot count the 7 days. Each update waits on the Dependency Dashboard.",
	"matchDatasources": ["docker"],
	"matchPackageNames": ["/^(ghcr\\.io|quay\\.io|mcr\\.microsoft\\.com)/.+$/"],
	"minimumReleaseAgeBehaviour": "timestamp-optional",
	"dependencyDashboardApproval": true,
}

# A configuration with exactly these packageRules.
config_with_rules(package_rules) := {
	"extends": celian_presets,
	"minimumReleaseAge": "7 days",
	"minimumReleaseAgeBehaviour": "timestamp-required",
	"internalChecksFilter": "strict",
	"vulnerabilityAlerts": {"minimumReleaseAge": null},
	"osvVulnerabilityAlerts": true,
	"packageRules": package_rules,
}

# A configuration with these packageRules, then the entry of ADR-016.
config_with(package_rules) := config_with_rules(array.concat(package_rules, [undated_rule]))

valid_config := config_with([])

with_value(obj, key, value) := object.union(object.remove(obj, {key}), {key: value})

without(obj, key) := object.remove(obj, {key})

checked(renovate) := [{"path": "renovate.json", "contents": renovate}]

accepted(files) if {
	msgs := deny with input as files
	count(msgs) == 0
}

denied_with(files, fragment) if {
	msgs := deny with input as files
	some msg in msgs
	contains(msg, fragment)
}

test_s23_accepts_the_delay_of_the_constitution if {
	accepted(checked(valid_config))
}

test_s23_accepts_a_renovate_json_under_a_folder if {
	accepted([{"path": "golden/saas-b2b/renovate.json", "contents": valid_config}])
}

# Shape of the input.

test_s23_rejects_an_input_without_renovate_json if {
	denied_with([{"path": "platform.yaml", "contents": {}}], "expected one renovate.json among the checked files, found 0")
}

test_s23_does_not_take_renovate_json5_for_renovate_json if {
	denied_with([{"path": "renovate.json5", "contents": valid_config}], "expected one renovate.json among the checked files, found 0")
}

test_s23_rejects_a_renovate_json_that_is_not_an_object if {
	denied_with(checked(["7 days"]), "renovate.json must hold a JSON object")
}

test_s23_rejects_package_rules_that_are_not_a_list if {
	renovate := with_value(valid_config, "packageRules", {"react": {"matchPackageNames": ["react"]}})
	denied_with(checked(renovate), "packageRules must be a list")
}

# Delay of 7 days.

test_s23_rejects_a_shorter_delay if {
	denied_with(checked(with_value(valid_config, "minimumReleaseAge", "3 days")), "minimumReleaseAge must be \"7 days\", found 3 days")
}

test_s23_rejects_a_missing_delay if {
	denied_with(checked(without(valid_config, "minimumReleaseAge")), "minimumReleaseAge must be \"7 days\", found null")
}

test_s23_rejects_a_rule_with_its_own_delay if {
	rule := {"matchPackageNames": ["react"], "minimumReleaseAge": "0 days"}
	denied_with(checked(config_with([rule])), "[\"packageRules\", 0, \"minimumReleaseAge\"] sets the delay again")
}

test_s23_rejects_a_release_without_a_date_taken_as_stable if {
	renovate := with_value(valid_config, "minimumReleaseAgeBehaviour", "timestamp-optional")
	denied_with(checked(renovate), "minimumReleaseAgeBehaviour must be written out as \"timestamp-required\"")
}

test_s23_rejects_a_rule_that_takes_a_release_without_a_date_as_stable if {
	rule := {"matchDatasources": ["docker"], "minimumReleaseAgeBehaviour": "timestamp-optional"}
	denied_with(checked(config_with([rule])), "[\"packageRules\", 0, \"minimumReleaseAgeBehaviour\"] sets the delay again")
}

test_s23_rejects_a_release_without_a_date_taken_as_stable_by_a_manager if {
	renovate := with_value(valid_config, "dockerfile", {"minimumReleaseAgeBehaviour": "timestamp-optional"})
	denied_with(checked(renovate), "[\"dockerfile\", \"minimumReleaseAgeBehaviour\"] sets the delay again")
}

test_s23_rejects_a_delay_set_for_an_update_type if {
	renovate := with_value(valid_config, "digest", {"minimumReleaseAge": null})
	denied_with(checked(renovate), "[\"digest\", \"minimumReleaseAge\"] sets the delay again")
}

test_s23_rejects_internal_checks_that_open_a_pr_during_the_delay if {
	renovate := with_value(valid_config, "internalChecksFilter", "none")
	denied_with(checked(renovate), "internalChecksFilter must be written out as \"strict\"")
}

test_s23_rejects_a_release_age_behaviour_left_to_the_default if {
	renovate := without(valid_config, "minimumReleaseAgeBehaviour")
	denied_with(checked(renovate), "minimumReleaseAgeBehaviour must be written out as \"timestamp-required\"")
}

test_s23_rejects_a_preset_added_to_extends if {
	renovate := with_value(valid_config, "extends", array.concat(celian_presets, ["github>example/presets"]))
	denied_with(checked(renovate), "extends must hold exactly the three presets of CELIAN")
}

test_s23_rejects_a_preset_extended_inside_a_rule if {
	rule := {"matchPackageNames": ["react"], "extends": ["github>example/presets"]}
	denied_with(checked(config_with([rule])), "[\"packageRules\", 0, \"extends\"] extends a preset")
}

# Registries without a release date (ADR-016): one entry, the block of the
# ADR to the letter, description aside.

test_s23_accepts_the_entry_of_adr_016_alone if {
	accepted(checked(config_with_rules([undated_rule])))
}

test_s23_accepts_the_entry_of_adr_016_with_its_own_description if {
	rule := with_value(undated_rule, "description", "Updates of these registries wait on the Dependency Dashboard.")
	accepted(checked(config_with_rules([rule])))
}

test_s23_accepts_the_entry_of_adr_016_without_a_description if {
	accepted(checked(config_with_rules([without(undated_rule, "description")])))
}

test_s23_accepts_the_entry_of_adr_016_after_other_rules if {
	accepted(checked(config_with([{"matchPackageNames": ["react"], "groupName": "react"}])))
}

test_s23_rejects_a_config_without_the_entry_of_adr_016 if {
	denied_with(checked(config_with_rules([])), "no packageRules entry is the entry of ADR-016")
}

test_s23_rejects_the_entry_of_adr_016_without_approval if {
	rule := without(undated_rule, "dependencyDashboardApproval")
	renovate := config_with_rules([rule])
	denied_with(checked(renovate), "[\"packageRules\", 0, \"minimumReleaseAgeBehaviour\"] sets the delay again")
	denied_with(checked(renovate), "no packageRules entry is the entry of ADR-016")
}

test_s23_rejects_the_entry_of_adr_016_with_the_approval_turned_off if {
	rule := with_value(undated_rule, "dependencyDashboardApproval", false)
	renovate := config_with_rules([rule])
	denied_with(checked(renovate), "[\"packageRules\", 0, \"minimumReleaseAgeBehaviour\"] sets the delay again")
	denied_with(checked(renovate), "[\"packageRules\", 0, \"dependencyDashboardApproval\"] sets dependencyDashboardApproval")
}

test_s23_rejects_the_entry_of_adr_016_with_docker_hub_added_to_its_pattern if {
	rule := with_value(undated_rule, "matchPackageNames", ["/^(docker\\.io|ghcr\\.io|quay\\.io|mcr\\.microsoft\\.com)/.+$/"])
	renovate := config_with_rules([rule])
	denied_with(checked(renovate), "[\"packageRules\", 0, \"minimumReleaseAgeBehaviour\"] sets the delay again")
	denied_with(checked(renovate), "[\"packageRules\", 0, \"dependencyDashboardApproval\"] sets dependencyDashboardApproval")
}

test_s23_rejects_the_entry_of_adr_016_with_docker_hub_as_a_second_pattern if {
	rule := with_value(undated_rule, "matchPackageNames", array.concat(undated_rule.matchPackageNames, ["/^(docker\\.io/)?library/.+$/"]))
	denied_with(checked(config_with_rules([rule])), "[\"packageRules\", 0, \"minimumReleaseAgeBehaviour\"] sets the delay again")
}

test_s23_rejects_the_entry_of_adr_016_with_one_more_criterion if {
	rule := with_value(undated_rule, "matchUpdateTypes", ["digest"])
	renovate := config_with_rules([rule])
	denied_with(checked(renovate), "[\"packageRules\", 0, \"minimumReleaseAgeBehaviour\"] sets the delay again")
	denied_with(checked(renovate), "[\"packageRules\", 0, \"dependencyDashboardApproval\"] sets dependencyDashboardApproval")
}

test_s23_rejects_the_entry_of_adr_016_without_its_datasource if {
	rule := without(undated_rule, "matchDatasources")
	denied_with(checked(config_with_rules([rule])), "[\"packageRules\", 0, \"minimumReleaseAgeBehaviour\"] sets the delay again")
}

test_s23_rejects_the_entry_of_adr_016_with_its_own_delay if {
	rule := with_value(undated_rule, "minimumReleaseAge", "0 days")
	renovate := config_with_rules([rule])
	denied_with(checked(renovate), "[\"packageRules\", 0, \"minimumReleaseAge\"] sets the delay again")
	denied_with(checked(renovate), "[\"packageRules\", 0, \"minimumReleaseAgeBehaviour\"] sets the delay again")
}

test_s23_rejects_the_entry_of_adr_016_with_its_own_internal_checks if {
	rule := with_value(undated_rule, "internalChecksFilter", "none")
	denied_with(checked(config_with_rules([rule])), "[\"packageRules\", 0, \"internalChecksFilter\"] sets the delay again")
}

test_s23_rejects_a_second_rule_that_sets_the_approval_alone if {
	rule := {"matchDatasources": ["docker"], "dependencyDashboardApproval": false}
	denied_with(checked(config_with([rule])), "[\"packageRules\", 0, \"dependencyDashboardApproval\"] sets dependencyDashboardApproval")
}

test_s23_rejects_the_approval_set_at_the_top if {
	renovate := with_value(valid_config, "dependencyDashboardApproval", true)
	denied_with(checked(renovate), "[\"dependencyDashboardApproval\"] sets dependencyDashboardApproval")
}

test_s23_rejects_the_approval_set_for_an_update_type if {
	renovate := with_value(valid_config, "digest", {"dependencyDashboardApproval": false})
	denied_with(checked(renovate), "[\"digest\", \"dependencyDashboardApproval\"] sets dependencyDashboardApproval")
}

# The pattern of the entry, read as Renovate reads a string between slashes:
# the leading slash and the trailing one go, the inner slash stays a plain
# character (lib/util/string-match.ts, Renovate 44.247.1).

undated_pattern_catches(name) if {
	some pattern in undated_registries_rule.matchPackageNames
	regex.match(substring(pattern, 1, count(pattern) - 2), name)
}

test_s23_the_pattern_of_adr_016_catches_the_images_of_the_three_registries if {
	every name in [
		"ghcr.io/gitleaks/gitleaks",
		"ghcr.io/project-zot/zot",
		"quay.io/keycloak/keycloak",
		"mcr.microsoft.com/dotnet/sdk",
		"mcr.microsoft.com/dotnet/aspnet",
	] {
		undated_pattern_catches(name)
	}
}

test_s23_the_pattern_of_adr_016_leaves_other_images_to_the_delay if {
	every name in [
		"postgres",
		"docker.io/library/postgres",
		"kindest/node",
		"zricethezav/gitleaks",
		"ghcr.io",
		"ghcr.io/",
		"ghcr.io.example.com/gitleaks/gitleaks",
		"example.com/ghcr.io/gitleaks/gitleaks",
	] {
		not undated_pattern_catches(name)
	}
}

# Security exception.

test_s23_rejects_a_missing_security_exception if {
	denied_with(checked(without(valid_config, "vulnerabilityAlerts")), "vulnerabilityAlerts.minimumReleaseAge must be written out as null")
}

test_s23_rejects_a_delay_on_security_fixes if {
	renovate := with_value(valid_config, "vulnerabilityAlerts", {"minimumReleaseAge": "7 days"})
	denied_with(checked(renovate), "vulnerabilityAlerts.minimumReleaseAge must be written out as null")
}

test_s23_rejects_vulnerability_alerts_turned_off if {
	renovate := with_value(valid_config, "vulnerabilityAlerts", {"minimumReleaseAge": null, "enabled": false})
	denied_with(checked(renovate), "vulnerabilityAlerts must stay enabled")
}

test_s23_rejects_osv_alerts_turned_off if {
	denied_with(checked(without(valid_config, "osvVulnerabilityAlerts")), "osvVulnerabilityAlerts must be true")
}

# Messages.

test_s23_names_the_delay_in_each_message if {
	msgs := deny with input as checked({})
	count(msgs) == 7
	every msg in msgs {
		startswith(msg, "S23 (FR-013")
	}
}
