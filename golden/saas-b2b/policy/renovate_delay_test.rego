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

# Legacy keys that Renovate migrates into a key of the delay, and
# experimental options of the delay.

test_s23_rejects_stability_days_in_a_rule if {
	rule := {"matchPackageNames": ["*"], "stabilityDays": 0}
	denied_with(checked(config_with([rule])), "[\"packageRules\", 0, \"stabilityDays\"] is a legacy key")
}

test_s23_rejects_master_issue_approval_after_the_entry_of_adr_016 if {
	rule := {"matchDatasources": ["docker"], "matchPackageNames": undated_rule.matchPackageNames, "masterIssueApproval": false}
	denied_with(checked(config_with_rules([undated_rule, rule])), "[\"packageRules\", 1, \"masterIssueApproval\"] is a legacy key")
}

test_s23_rejects_master_issue_at_the_top if {
	renovate := with_value(valid_config, "masterIssue", false)
	denied_with(checked(renovate), "[\"masterIssue\"] is a legacy key")
}

test_s23_rejects_unpublish_safe_at_the_top if {
	renovate := with_value(valid_config, "unpublishSafe", true)
	denied_with(checked(renovate), "[\"unpublishSafe\"] is a legacy key")
}

test_s23_rejects_the_package_manager_sync_of_the_delay if {
	renovate := with_value(valid_config, "minimumReleaseAgePackageManagerSync", true)
	denied_with(checked(renovate), "[\"minimumReleaseAgePackageManagerSync\"] is an experimental option")
}

test_s23_rejects_the_package_manager_delay_of_a_manager if {
	renovate := with_value(valid_config, "npm", {"minimumReleaseAgePackageManager": "0 days"})
	denied_with(checked(renovate), "[\"npm\", \"minimumReleaseAgePackageManager\"] is an experimental option")
}

# Legacy containers whose content Renovate moves into packageRules, out of
# reach of the checks of the entries (lib/config/migration.ts, lines 140 to
# 191; lib/config/migrations/custom/, Renovate 44.247.1). Each one carries
# here a setting that the entries of S23 reserve to themselves.

widened := {"allowedVersions": "/.*/"}

legacy_container(key) := sprintf("[\"%s\"] is a legacy key", [key])

test_s23_rejects_legacy_path_rules if {
	renovate := with_value(valid_config, "pathRules", [{"paths": ["**"], "allowedVersions": "/.*/"}])
	denied_with(checked(renovate), legacy_container("pathRules"))
}

test_s23_rejects_legacy_packages if {
	renovate := with_value(valid_config, "packages", [{"matchPackageNames": ["*"], "allowedVersions": "/.*/"}])
	denied_with(checked(renovate), legacy_container("packages"))
}

test_s23_rejects_legacy_package_files if {
	renovate := with_value(valid_config, "packageFiles", [{"packageFile": "Dockerfile", "allowedVersions": "/.*/"}])
	denied_with(checked(renovate), legacy_container("packageFiles"))
}

test_s23_rejects_legacy_dependencies if {
	denied_with(checked(with_value(valid_config, "dependencies", widened)), legacy_container("dependencies"))
}

test_s23_rejects_legacy_dev_dependencies if {
	denied_with(checked(with_value(valid_config, "devDependencies", widened)), legacy_container("devDependencies"))
}

test_s23_rejects_legacy_optional_dependencies if {
	denied_with(checked(with_value(valid_config, "optionalDependencies", widened)), legacy_container("optionalDependencies"))
}

test_s23_rejects_legacy_peer_dependencies if {
	denied_with(checked(with_value(valid_config, "peerDependencies", widened)), legacy_container("peerDependencies"))
}

test_s23_rejects_legacy_engines if {
	denied_with(checked(with_value(valid_config, "engines", widened)), legacy_container("engines"))
}

test_s23_rejects_legacy_dep_types if {
	renovate := with_value(valid_config, "depTypes", [{"depType": "dependencies", "groupName": "dependencies"}])
	denied_with(checked(renovate), legacy_container("depTypes"))
}

test_s23_rejects_the_legacy_docker_object if {
	denied_with(checked(with_value(valid_config, "docker", widened)), legacy_container("docker"))
}

test_s23_rejects_the_legacy_dotnet_object if {
	denied_with(checked(with_value(valid_config, "dotnet", widened)), legacy_container("dotnet"))
}

test_s23_rejects_the_legacy_golang_object if {
	denied_with(checked(with_value(valid_config, "golang", widened)), legacy_container("golang"))
}

test_s23_rejects_the_legacy_java_object if {
	denied_with(checked(with_value(valid_config, "java", widened)), legacy_container("java"))
}

test_s23_rejects_the_legacy_js_object if {
	denied_with(checked(with_value(valid_config, "js", widened)), legacy_container("js"))
}

test_s23_rejects_the_legacy_node_object if {
	denied_with(checked(with_value(valid_config, "node", widened)), legacy_container("node"))
}

test_s23_rejects_the_legacy_php_object if {
	denied_with(checked(with_value(valid_config, "php", widened)), legacy_container("php"))
}

test_s23_rejects_the_legacy_python_object if {
	denied_with(checked(with_value(valid_config, "python", widened)), legacy_container("python"))
}

test_s23_rejects_the_legacy_ruby_object if {
	denied_with(checked(with_value(valid_config, "ruby", widened)), legacy_container("ruby"))
}

test_s23_rejects_the_legacy_rust_object if {
	denied_with(checked(with_value(valid_config, "rust", widened)), legacy_container("rust"))
}

test_s23_rejects_a_legacy_container_inside_an_entry if {
	rule := {"matchDatasources": ["docker"], "docker": widened}
	denied_with(checked(config_with([rule])), "[\"packageRules\", 0, \"docker\"] is a legacy key")
}

test_s23_rejects_package_rules_nested_in_an_entry if {
	rule := {"matchDatasources": ["docker"], "packageRules": [{"matchPackageNames": ["*"], "allowedVersions": "/.*/"}]}
	denied_with(checked(config_with([rule])), "[\"packageRules\", 0, \"packageRules\"] nests packageRules")
}

# Keys that change what Renovate reads, or where it looks a package up: each
# can stop an update, security fixes included, through any entry, manager or
# the top.

changes_lookup(path) := sprintf("%s changes what Renovate reads", [path])

test_s23_rejects_override_package_name if {
	rule := {"matchPackageNames": ["kindest/node"], "overridePackageName": "example/node"}
	denied_with(checked(config_with([rule])), changes_lookup("[\"packageRules\", 0, \"overridePackageName\"]"))
}

test_s23_rejects_override_datasource if {
	rule := {"matchPackageNames": ["postgres"], "overrideDatasource": "github-tags"}
	denied_with(checked(config_with([rule])), changes_lookup("[\"packageRules\", 0, \"overrideDatasource\"]"))
}

test_s23_rejects_override_dep_name if {
	rule := {"matchPackageNames": ["postgres"], "overrideDepName": "example/postgres"}
	denied_with(checked(config_with([rule])), changes_lookup("[\"packageRules\", 0, \"overrideDepName\"]"))
}

test_s23_rejects_registry_urls if {
	rule := {"matchPackageNames": ["postgres"], "registryUrls": ["https://registry.example.com"]}
	denied_with(checked(config_with([rule])), changes_lookup("[\"packageRules\", 0, \"registryUrls\"]"))
}

test_s23_rejects_default_registry_urls if {
	renovate := with_value(valid_config, "dockerfile", {"defaultRegistryUrls": ["https://registry.example.com"]})
	denied_with(checked(renovate), changes_lookup("[\"dockerfile\", \"defaultRegistryUrls\"]"))
}

test_s23_rejects_follow_tag if {
	rule := {"matchPackageNames": ["*"], "followTag": "next"}
	denied_with(checked(config_with([rule])), changes_lookup("[\"packageRules\", 0, \"followTag\"]"))
}

test_s23_rejects_ignore_deps if {
	renovate := with_value(valid_config, "ignoreDeps", ["kindest/node"])
	denied_with(checked(renovate), changes_lookup("[\"ignoreDeps\"]"))
}

test_s23_rejects_enabled_managers if {
	renovate := with_value(valid_config, "enabledManagers", ["npm"])
	denied_with(checked(renovate), changes_lookup("[\"enabledManagers\"]"))
}

test_s23_rejects_ignore_paths_at_the_top if {
	renovate := with_value(valid_config, "ignorePaths", ["golden/**"])
	denied_with(checked(renovate), changes_lookup("[\"ignorePaths\"]"))
}

test_s23_rejects_ignore_paths_in_a_manager if {
	renovate := with_value(valid_config, "dockerfile", {"ignorePaths": ["golden/**"]})
	denied_with(checked(renovate), changes_lookup("[\"dockerfile\", \"ignorePaths\"]"))
}

test_s23_rejects_include_paths if {
	renovate := with_value(valid_config, "includePaths", ["src/**"])
	denied_with(checked(renovate), changes_lookup("[\"includePaths\"]"))
}

# Renovate turns ignoreNodeModules into ignorePaths
# (lib/config/migrations/custom/ignore-node-modules-migration.ts, line 8).
test_s23_rejects_the_legacy_ignore_node_modules if {
	renovate := with_value(valid_config, "ignoreNodeModules", true)
	denied_with(checked(renovate), changes_lookup("[\"ignoreNodeModules\"]"))
}

# The ignorePaths of the regex object, which package renovate_rules fixes to
# the letter, stays allowed.
test_s23_accepts_the_ignore_paths_of_the_regex_object if {
	accepted(checked(with_value(valid_config, "regex", {"ignorePaths": ["**/node_modules/**"]})))
}

# The objects of current managers stay allowed: both renovate.json files set
# pre-commit and regex.
test_s23_accepts_the_objects_of_current_managers if {
	renovate := object.union(valid_config, {
		"pre-commit": {"enabled": true},
		"regex": {"ignorePaths": ["**/node_modules/**"]},
		"dockerfile": {"description": "Images of the Dockerfiles."},
		"github-actions": {"description": "Actions of the workflows."},
	})
	accepted(checked(renovate))
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
		"docker.io/zricethezav/gitleaks",
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

# Updates turned off. Renovate applies an entry to every package that its
# criteria let through, whatever they are, and an entry without criteria to
# all of them: enabled is written as true or not at all.

test_s23_rejects_a_glob_entry_that_turns_every_update_off if {
	rule := {"matchPackageNames": ["*"], "enabled": false}
	denied_with(checked(config_with([rule])), "[\"packageRules\", 0, \"enabled\"] sets enabled to false")
}

test_s23_rejects_a_dep_name_entry_that_turns_updates_off if {
	rule := {"matchDepNames": ["postgres"], "enabled": false}
	denied_with(checked(config_with([rule])), "[\"packageRules\", 0, \"enabled\"] sets enabled to false")
}

test_s23_rejects_a_regex_entry_that_turns_off_a_registry_of_adr_016 if {
	rule := {"matchPackageNames": ["/^ghcr\\.io//"], "enabled": false}
	denied_with(checked(config_with([rule])), "[\"packageRules\", 0, \"enabled\"] sets enabled to false")
}

test_s23_rejects_a_regex_entry_that_turns_off_postgres if {
	rule := {"matchPackageNames": ["/postgres/"], "enabled": false}
	denied_with(checked(config_with([rule])), "[\"packageRules\", 0, \"enabled\"] sets enabled to false")
}

test_s23_rejects_a_negated_pattern_that_turns_updates_off if {
	rule := {"matchPackageNames": ["!react"], "enabled": false}
	denied_with(checked(config_with([rule])), "[\"packageRules\", 0, \"enabled\"] sets enabled to false")
}

test_s23_rejects_a_datasource_entry_that_turns_updates_off if {
	rule := {"matchDatasources": ["docker"], "enabled": false}
	denied_with(checked(config_with([rule])), "[\"packageRules\", 0, \"enabled\"] sets enabled to false")
}

test_s23_rejects_an_exact_name_entry_that_turns_updates_off if {
	rule := {"matchPackageNames": ["kindest/node"], "enabled": false}
	denied_with(checked(config_with([rule])), "[\"packageRules\", 0, \"enabled\"] sets enabled to false")
}

test_s23_rejects_updates_turned_off_for_an_update_type_inside_an_entry if {
	rule := {"matchPackageNames": ["react"], "major": {"enabled": false}}
	denied_with(checked(config_with([rule])), "[\"packageRules\", 0, \"major\", \"enabled\"] sets enabled to false")
}

test_s23_rejects_a_manager_turned_off if {
	renovate := with_value(valid_config, "dockerfile", {"enabled": false})
	denied_with(checked(renovate), "[\"dockerfile\", \"enabled\"] sets enabled to false")
}

test_s23_rejects_renovate_turned_off_at_the_top if {
	denied_with(checked(with_value(valid_config, "enabled", false)), "[\"enabled\"] sets enabled to false")
}

# Renovate moves the entries of pathRules into packageRules
# (lib/config/migrations/custom/path-rules-migration.ts, Renovate 44.247.1).
test_s23_rejects_updates_turned_off_by_a_legacy_path_rule if {
	renovate := with_value(valid_config, "pathRules", [{"paths": ["**"], "enabled": false}])
	denied_with(checked(renovate), "[\"pathRules\", 0, \"enabled\"] sets enabled to false")
}

test_s23_rejects_enabled_written_as_a_string if {
	rule := {"matchPackageNames": ["react"], "enabled": "no"}
	denied_with(checked(config_with([rule])), "[\"packageRules\", 0, \"enabled\"] sets enabled to no")
}

# Both renovate.json files turn the pre-commit manager on.
test_s23_accepts_a_manager_turned_on if {
	accepted(checked(with_value(valid_config, "pre-commit", {"enabled": true})))
}

# Keys that route a lookup elsewhere, change what the registry answers, or
# rewrite the name or the version of a package: a custom datasource, the
# credentials and registries of npm, a host rule, a version filter, a new
# versioning, a replacement.

test_s23_rejects_custom_datasources if {
	renovate := with_value(valid_config, "customDatasources", {"internal": {"defaultRegistryUrlTemplate": "https://registry.example.com"}})
	denied_with(checked(renovate), changes_lookup("[\"customDatasources\"]"))
}

test_s23_rejects_npmrc if {
	renovate := with_value(valid_config, "npmrc", "registry=https://registry.example.com")
	denied_with(checked(renovate), changes_lookup("[\"npmrc\"]"))
}

test_s23_rejects_npmrc_merge if {
	renovate := with_value(valid_config, "npmrcMerge", true)
	denied_with(checked(renovate), changes_lookup("[\"npmrcMerge\"]"))
}

test_s23_rejects_registry_aliases if {
	renovate := with_value(valid_config, "registryAliases", {"stable": "https://registry.example.com"})
	denied_with(checked(renovate), changes_lookup("[\"registryAliases\"]"))
}

test_s23_rejects_host_rules if {
	renovate := with_value(valid_config, "hostRules", [{"matchHost": "ghcr.io", "enabled": true}])
	denied_with(checked(renovate), changes_lookup("[\"hostRules\"]"))
}

test_s23_rejects_extract_version if {
	rule := {"matchPackageNames": ["postgres"], "extractVersion": "^nothing$"}
	denied_with(checked(config_with([rule])), changes_lookup("[\"packageRules\", 0, \"extractVersion\"]"))
}

test_s23_rejects_versioning if {
	rule := {"matchPackageNames": ["postgres"], "versioning": "regex:^(?<major>\\d+)$"}
	denied_with(checked(config_with([rule])), changes_lookup("[\"packageRules\", 0, \"versioning\"]"))
}

test_s23_rejects_update_pinned_dependencies if {
	renovate := with_value(valid_config, "updatePinnedDependencies", false)
	denied_with(checked(renovate), changes_lookup("[\"updatePinnedDependencies\"]"))
}

test_s23_rejects_replacement_name if {
	rule := {"matchPackageNames": ["postgres"], "replacementName": "example/postgres"}
	denied_with(checked(config_with([rule])), changes_lookup("[\"packageRules\", 0, \"replacementName\"]"))
}

test_s23_rejects_replacement_name_template if {
	rule := {"matchPackageNames": ["postgres"], "replacementNameTemplate": "example/postgres"}
	denied_with(checked(config_with([rule])), changes_lookup("[\"packageRules\", 0, \"replacementNameTemplate\"]"))
}

test_s23_rejects_replacement_version if {
	rule := {"matchPackageNames": ["postgres"], "replacementVersion": "1.0.0"}
	denied_with(checked(config_with([rule])), changes_lookup("[\"packageRules\", 0, \"replacementVersion\"]"))
}

test_s23_rejects_replacement_version_template if {
	rule := {"matchPackageNames": ["postgres"], "replacementVersionTemplate": "1.0.0"}
	denied_with(checked(config_with([rule])), changes_lookup("[\"packageRules\", 0, \"replacementVersionTemplate\"]"))
}

test_s23_rejects_constraints_filtering if {
	renovate := with_value(valid_config, "constraintsFiltering", "strict")
	denied_with(checked(renovate), changes_lookup("[\"constraintsFiltering\"]"))
}

# The Template keys of the tools manager are other keys than extractVersion
# and versioning, and stay allowed.
test_s23_accepts_the_template_keys_of_a_custom_manager if {
	manager := {"customType": "regex", "extractVersionTemplate": "^v(?<version>.*)$", "versioningTemplate": "semver"}
	accepted(checked(with_value(valid_config, "customManagers", [manager])))
}

# constraints names the tool versions that Renovate runs with, as in
# configuration-options.md: "constraints": {"node": "^18.0.0"}. The names of
# the tools there are not the legacy objects docker, node and the like.
test_s23_accepts_the_constraints_of_the_tools if {
	renovate := with_value(valid_config, "constraints", {"node": "^18.0.0", "docker": "^27.0.0"})
	accepted(checked(renovate))
}

test_s23_accepts_the_constraints_versioning_of_the_tools if {
	renovate := with_value(valid_config, "constraintsVersioning", {"node": "semver"})
	accepted(checked(renovate))
}

test_s23_rejects_a_constraint_that_is_not_a_string if {
	renovate := with_value(valid_config, "constraints", {"node": widened})
	denied_with(checked(renovate), legacy_container("constraints\", \"node"))
}

test_s23_still_rejects_the_legacy_node_object_with_enabled if {
	renovate := with_value(valid_config, "node", {"enabled": true})
	denied_with(checked(renovate), legacy_container("node"))
}

# Messages.

test_s23_names_the_delay_in_each_message if {
	msgs := deny with input as checked({})
	count(msgs) == 7
	every msg in msgs {
		startswith(msg, "S23 (FR-013")
	}
}
