# Tests of S23, delay part (renovate_delay.rego), run by `conftest verify`.
package renovate_delay

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
	denied_with(checked(config_with({"react": {"matchPackageNames": ["react"]}})), "packageRules must be a list")
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
	count(msgs) == 6
	every msg in msgs {
		startswith(msg, "S23 (FR-013")
	}
}
