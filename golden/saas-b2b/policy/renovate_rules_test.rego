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

# ADR-015, conditions 2 and 16: the cache image on the patches of the
# cache_engine_line of platform.yaml, Alpine variant alone. config_for adds
# it at the end of packageRules, so that the indexes of the entries above
# do not move.
cache_rule := {
	"matchDatasources": ["docker"],
	"matchPackageNames": ["/^(docker\\.io/)?valkey/valkey$/"],
	"allowedVersions": "/^9\\.1\\.[0-9]+-alpine$/",
}

# kubectl of the CI, pinned in tests/tools/install.sh: the minor of
# platform.yaml, with an optional v for the workflow of CELIAN. config_for adds
# it after the cache entry.
kubectl_rule := {
	"matchDatasources": ["github-releases"],
	"matchPackageNames": ["kubernetes/kubernetes"],
	"allowedVersions": "/^v?1\\.36\\./",
}

celian_presets := ["config:recommended", "helpers:pinGitHubActionDigests", "customManagers:githubActionsVersions"]

# The regex managers see tests/: the list of :ignoreModulesAndTests without
# **/tests/**.
regex_object := {
	"description": "The installer of the test tools lives under tests/.",
	"ignorePaths": [
		"**/node_modules/**",
		"**/bower_components/**",
		"**/vendor/**",
		"**/examples/**",
		"**/__tests__/**",
		"**/test/**",
		"**/__fixtures__/**",
	],
}

# The manager of the _IMAGE variables, to the letter, as both renovate.json
# files write it: the workflows of the project, and in CELIAN those of the
# golden repo too.
images_expression := `# renovate: datasource=(?<datasource>docker) depName=(?<depName>\S+)\s+[A-Z0-9_]+_IMAGE\s*:\s*\S+?:(?<currentValue>[^\s@]+)@(?<currentDigest>sha256:[a-f0-9]+)`

image_manager := {
	"customType": "regex",
	"description": "Container images in workflow env vars ending in _IMAGE",
	"managerFilePatterns": ["/^\\.github/workflows/.+\\.ya?ml$/"],
	"matchStrings": [images_expression],
}

celian_image_manager := with_value(image_manager, "managerFilePatterns", ["/^\\.github/workflows/.+\\.ya?ml$/", "/^golden/saas-b2b/\\.github/workflows/.+\\.ya?ml$/"])

# The manager of tests/tools/install.sh, next to platform.yaml.
golden_tools_manager := {
	"customType": "regex",
	"description": "Task and conftest, in tests/tools/install.sh; kind, in local/scripts/lib/preflight-checks.sh.",
	"managerFilePatterns": ["/^tests/tools/install\\.sh$/", "/^local/scripts/lib/preflight-checks\\.sh$/"],
	"matchStrings": [`# renovate: datasource=(?<datasource>github-releases) depName=(?<depName>\S+)\s+[A-Z0-9_]+_VERSION="(?<currentValue>[^"\s]+)"`],
	"extractVersionTemplate": "^v(?<version>.*)$",
	"versioningTemplate": "semver",
}

# The same manager in CELIAN, where platform.yaml is
# golden/saas-b2b/platform.yaml.
celian_tools_manager := with_value(golden_tools_manager, "managerFilePatterns", ["/^golden/saas-b2b/tests/tools/install\\.sh$/", "/^golden/saas-b2b/local/scripts/lib/preflight-checks\\.sh$/"])

# The manager of the images of the local layer: the node image of the kind
# configuration and the zot image of the Taskfile of the layer (ADR-004,
# version rule, point 5; ADR-011, condition 8; ADR-016).
local_expression := `# renovate: datasource=(?<datasource>docker) depName=(?<depName>\S+)\s+(?:image|[A-Z0-9_]+_IMAGE)\s*:\s*\S+?:(?<currentValue>[^\s@]+)@(?<currentDigest>sha256:[a-f0-9]+)`

golden_local_manager := {
	"customType": "regex",
	"description": "Images of the local layer.",
	"managerFilePatterns": ["/^local/kind/cluster\\.yaml$/", "/^local/tasks/.+\\.ya?ml$/", "/^local/data/.+\\.ya?ml$/", "/^local/platform/.+\\.ya?ml$/"],
	"matchStrings": [local_expression],
}

celian_local_manager := with_value(golden_local_manager, "managerFilePatterns", ["/^golden/saas-b2b/local/kind/cluster\\.yaml$/", "/^golden/saas-b2b/local/tasks/.+\\.ya?ml$/", "/^golden/saas-b2b/local/data/.+\\.ya?ml$/", "/^golden/saas-b2b/local/platform/.+\\.ya?ml$/"])

config_for(package_rules, managers) := {
	"extends": celian_presets,
	"minimumReleaseAge": "7 days",
	"minimumReleaseAgeBehaviour": "timestamp-required",
	"internalChecksFilter": "strict",
	"vulnerabilityAlerts": {"minimumReleaseAge": null},
	"osvVulnerabilityAlerts": true,
	"regex": regex_object,
	"customManagers": managers,
	"packageRules": array.concat(package_rules, [cache_rule, kubectl_rule]),
}

config_with(package_rules) := config_for(package_rules, [image_manager, golden_tools_manager, golden_local_manager])

valid_config := config_with(valid_rules)

valid_platform := {"kubernetes_minor": "1.36", "postgres_major": "18", "cache_engine_line": "9.1"}

with_value(obj, key, value) := object.union(object.remove(obj, {key}), {key: value})

without(obj, key) := object.remove(obj, {key})

checked(renovate, values) := [
	{"path": "renovate.json", "contents": renovate},
	{"path": "platform.yaml", "contents": values},
]

# The files as check-renovate.sh gives them in CELIAN.
in_celian(renovate) := [
	{"path": "renovate.json", "contents": renovate},
	{"path": "golden/saas-b2b/platform.yaml", "contents": valid_platform},
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
		{"path": "golden/saas-b2b/renovate.json", "contents": config_for(valid_rules, [celian_image_manager, celian_tools_manager, celian_local_manager])},
		{"path": "golden/saas-b2b/platform.yaml", "contents": valid_platform},
	])
}

test_s23_accepts_the_layout_of_celian if {
	accepted(in_celian(config_for(valid_rules, [celian_image_manager, celian_tools_manager, celian_local_manager])))
}

test_s23_accepts_a_description_on_each_entry if {
	rules := [rule |
		some entry in valid_rules
		rule := with_value(entry, "description", "Why this entry exists.")
	]
	accepted(checked(config_with(rules), valid_platform))
}

# Both renovate.json files, the one of CELIAN and the one of the golden repo,
# write these entries, then the entry of ADR-016. The two packages accept
# that layout. The entries of this package set allowedVersions or groupName,
# the entry of ADR-016 the delay behaviour and the approval: no key is set
# twice, so their order does not change what Renovate does. No image is
# caught by both sides either.

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

# kind and its node image.

test_s23_rejects_another_kubernetes_minor if {
	rule := with_value(node_rule, "allowedVersions", "/^v1\\.37\\./")
	renovate := config_with([postgres_rule, rule, kind_group, envoy_group])
	denied_with(checked(renovate, valid_platform), "no packageRules entry keeps the kind node image on allowedVersions /^v1\\.36\\./")
}

test_s23_follows_the_kubernetes_minor_of_platform_yaml if {
	rule := with_value(node_rule, "allowedVersions", "/^v1\\.37\\./")
	kubectl := with_value(kubectl_rule, "allowedVersions", "/^v?1\\.37\\./")
	base := without_kubectl_rule(config_with([postgres_rule, rule, kind_group, envoy_group]))
	renovate := object.union(base, {"packageRules": array.concat(base.packageRules, [kubectl])})
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

# Entries that look right but match nothing, or that a later entry undoes.
# Renovate applies an entry only when all its criteria match.

test_s23_rejects_a_postgres_entry_narrowed_to_some_files if {
	rule := with_value(postgres_rule, "matchFileNames", ["nothing/**"])
	renovate := config_with([rule, node_rule, kind_group, envoy_group])
	denied_with(checked(renovate, valid_platform), "no packageRules entry keeps the postgres image")
}

test_s23_rejects_a_postgres_entry_narrowed_to_a_current_version if {
	rule := with_value(postgres_rule, "matchCurrentVersion", "/^17\\./")
	renovate := config_with([rule, node_rule, kind_group, envoy_group])
	denied_with(checked(renovate, valid_platform), "packageRules[0] sets allowedVersions; only the postgres, node, cache and kubectl entries set it")
}

test_s23_rejects_a_node_entry_narrowed_to_some_update_types if {
	rule := with_value(node_rule, "matchUpdateTypes", ["patch"])
	renovate := config_with([postgres_rule, rule, kind_group, envoy_group])
	denied_with(checked(renovate, valid_platform), "no packageRules entry keeps the kind node image")
}

test_s23_rejects_a_postgres_entry_with_a_negated_pattern if {
	rule := with_value(postgres_rule, "matchPackageNames", ["/^(docker\\.io/)?(library/)?postgres$/", "!postgres"])
	renovate := config_with([rule, node_rule, kind_group, envoy_group])
	denied_with(checked(renovate, valid_platform), "no packageRules entry keeps the postgres image")
}

test_s23_rejects_a_later_glob_entry_that_sets_allowed_versions if {
	rule := {"matchPackageNames": ["*"], "allowedVersions": "/.*/"}
	renovate := config_with(array.concat(valid_rules, [rule]))
	denied_with(checked(renovate, valid_platform), "packageRules[4] sets allowedVersions; only the postgres, node, cache and kubectl entries set it")
}

test_s23_rejects_a_later_dep_name_entry_that_sets_allowed_versions if {
	rule := {"matchDepNames": ["postgres"], "allowedVersions": "/^19\\./"}
	renovate := config_with(array.concat(valid_rules, [rule]))
	denied_with(checked(renovate, valid_platform), "packageRules[4] sets allowedVersions; only the postgres, node, cache and kubectl entries set it")
}

test_s23_rejects_a_kind_group_narrowed_to_some_files if {
	group := with_value(kind_group, "matchFileNames", ["nothing/**"])
	renovate := config_with([postgres_rule, node_rule, group, envoy_group])
	denied_with(checked(renovate, valid_platform), "so that kind and its node image move in one PR")
}

test_s23_rejects_an_envoy_group_with_a_negated_pattern if {
	group := with_value(envoy_group, "matchPackageNames", ["/^(docker\\.io/)?envoyproxy/gateway(-helm|-crds-helm)?$/", "!envoyproxy/gateway"])
	renovate := config_with([postgres_rule, node_rule, kind_group, group])
	denied_with(checked(renovate, valid_platform), "no packageRules entry puts the charts and the controller image of Envoy Gateway")
}

# A pattern of an entry that S23 relies on is a regex or one of its own
# names. Renovate reads any other string as a glob (lib/util/string-match.ts,
# Renovate 44.247.1), which catches() does not read.

test_s23_rejects_a_glob_added_to_the_postgres_entry if {
	rule := with_value(postgres_rule, "matchPackageNames", array.concat(postgres_rule.matchPackageNames, ["*"]))
	renovate := config_with([rule, node_rule, kind_group, envoy_group])
	denied_with(checked(renovate, valid_platform), "no packageRules entry keeps the postgres image")
}

test_s23_rejects_a_pattern_that_renovate_reads_as_an_empty_regex if {
	rule := with_value(node_rule, "matchPackageNames", array.concat(node_rule.matchPackageNames, ["//"]))
	renovate := config_with([postgres_rule, rule, kind_group, envoy_group])
	denied_with(checked(renovate, valid_platform), "no packageRules entry keeps the kind node image")
}

test_s23_rejects_a_glob_added_to_the_kind_group if {
	group := with_value(kind_group, "matchPackageNames", array.concat(kind_group.matchPackageNames, ["envoyproxy/*"]))
	renovate := config_with([postgres_rule, node_rule, group, envoy_group])
	denied_with(checked(renovate, valid_platform), "so that kind and its node image move in one PR")
}

# Entries that split a pair. An update lands in the branch, hence the PR,
# that its group and branch keys name; a later entry that sets one of them
# for part of a pair splits it.

later_entry_fragment(key) := sprintf("[\"packageRules\", 4, \"%s\"] sets a key that decides the branch", [key])

test_s23_rejects_a_glob_entry_that_moves_the_node_image_to_another_group if {
	rule := {"matchPackageNames": ["kindest/*"], "groupName": "kind images"}
	renovate := config_with(array.concat(valid_rules, [rule]))
	denied_with(checked(renovate, valid_platform), later_entry_fragment("groupName"))
}

test_s23_rejects_a_glob_entry_that_moves_the_envoy_controller_to_another_group if {
	rule := {"matchPackageNames": ["**/gateway"], "groupName": "controllers"}
	renovate := config_with(array.concat(valid_rules, [rule]))
	denied_with(checked(renovate, valid_platform), later_entry_fragment("groupName"))
}

test_s23_rejects_a_dep_name_entry_that_moves_the_node_image_to_another_group if {
	rule := {"matchDepNames": ["kindest/node"], "groupName": "kind node"}
	renovate := config_with(array.concat(valid_rules, [rule]))
	denied_with(checked(renovate, valid_platform), later_entry_fragment("groupName"))
}

test_s23_rejects_another_group_slug_for_the_node_image if {
	rule := {"matchPackageNames": ["kindest/node"], "groupSlug": "kind-node"}
	renovate := config_with(array.concat(valid_rules, [rule]))
	denied_with(checked(renovate, valid_platform), later_entry_fragment("groupSlug"))
}

test_s23_rejects_another_branch_prefix_for_the_envoy_charts if {
	rule := {"matchPackageNames": ["/-helm$/"], "additionalBranchPrefix": "charts-"}
	renovate := config_with(array.concat(valid_rules, [rule]))
	denied_with(checked(renovate, valid_platform), later_entry_fragment("additionalBranchPrefix"))
}

# Renovate renames separatePatchReleases to separateMinorPatch
# (lib/config/migrations/migrations-service.ts, line 105).
test_s23_rejects_a_legacy_key_that_becomes_a_branch_key if {
	rule := {"matchPackageNames": ["kindest/node"], "separatePatchReleases": true}
	renovate := config_with(array.concat(valid_rules, [rule]))
	denied_with(checked(renovate, valid_platform), later_entry_fragment("separatePatchReleases"))
}

test_s23_rejects_a_group_branch_topic_set_at_the_top if {
	renovate := with_value(valid_config, "group", {"branchTopic": "{{{depNameSanitized}}}"})
	denied_with(checked(renovate, valid_platform), "[\"group\"] sets a key that decides the branch")
}

test_s23_rejects_an_envoy_group_that_takes_the_node_image_from_kind if {
	group := with_value(envoy_group, "matchPackageNames", array.concat(envoy_group.matchPackageNames, ["/^(docker\\.io/)?kindest/node$/"]))
	renovate := config_with([postgres_rule, node_rule, kind_group, group])
	denied_with(checked(renovate, valid_platform), "[\"packageRules\", 3, \"groupName\"] sets a key that decides the branch")
}

test_s23_rejects_a_kind_group_that_takes_part_of_envoy_gateway if {
	group := with_value(kind_group, "matchPackageNames", array.concat(kind_group.matchPackageNames, ["/^envoyproxy/gateway$/"]))
	renovate := config_with([postgres_rule, node_rule, envoy_group, group])
	denied_with(checked(renovate, valid_platform), "[\"packageRules\", 3, \"groupName\"] sets a key that decides the branch")
}

test_s23_accepts_a_kind_group_that_takes_all_of_envoy_gateway if {
	group := with_value(kind_group, "matchPackageNames", array.concat(kind_group.matchPackageNames, envoy_group.matchPackageNames))
	accepted(checked(config_with([postgres_rule, node_rule, envoy_group, group]), valid_platform))
}

# The layout of both renovate.json files: a description on each entry, the
# entry of ADR-016 last, the pre-commit manager turned on. conftest test runs
# both packages on the files themselves (tests/static/s23-renovate.sh,
# scripts/renovate/check-renovate.sh).

file_rules := array.concat(
	[rule |
		some entry in valid_rules
		rule := with_value(entry, "description", "Why this entry exists.")
	],
	[renovate_delay.undated_registries_rule],
)

file_config(managers) := object.union(config_for(file_rules, managers), {"pre-commit": {"enabled": true}})

test_s23_accepts_the_layout_of_the_golden_repo_in_both_packages if {
	files := checked(file_config([image_manager, golden_tools_manager, golden_local_manager]), valid_platform)
	accepted(files)
	count(renovate_delay.deny) == 0 with input as files
}

test_s23_accepts_the_layout_of_celian_in_both_packages if {
	files := in_celian(file_config([celian_image_manager, celian_tools_manager, celian_local_manager]))
	accepted(files)
	count(renovate_delay.deny) == 0 with input as files
}

# The manager of tests/tools/install.sh, and the regex object that lets the
# regex managers see tests/.

test_s23_rejects_a_config_without_the_tools_manager if {
	renovate := config_for(valid_rules, [image_manager])
	denied_with(checked(renovate, valid_platform), "no customManagers entry is the manager of tests/tools/install.sh")
}

test_s23_rejects_the_tools_manager_of_the_golden_repo_in_celian if {
	denied_with(in_celian(valid_config), "no customManagers entry is the manager of golden/saas-b2b/tests/tools/install.sh")
}

test_s23_rejects_the_tools_manager_of_celian_in_the_golden_repo if {
	renovate := config_for(valid_rules, [image_manager, celian_tools_manager])
	denied_with(checked(renovate, valid_platform), "no customManagers entry is the manager of tests/tools/install.sh")
}

test_s23_rejects_a_tools_manager_without_the_v_prefix if {
	manager := without(golden_tools_manager, "extractVersionTemplate")
	renovate := config_for(valid_rules, [image_manager, manager])
	denied_with(checked(renovate, valid_platform), "no customManagers entry is the manager of tests/tools/install.sh")
}

test_s23_rejects_a_tools_manager_for_another_datasource if {
	manager := with_value(golden_tools_manager, "matchStrings", [`# renovate: datasource=(?<datasource>\S+) depName=(?<depName>\S+)\s+[A-Z0-9_]+_VERSION="(?<currentValue>[^"\s]+)"`])
	renovate := config_for(valid_rules, [image_manager, manager])
	denied_with(checked(renovate, valid_platform), "no customManagers entry is the manager of tests/tools/install.sh")
}

test_s23_rejects_a_config_without_the_regex_object if {
	denied_with(checked(without(valid_config, "regex"), valid_platform), "regex must hold ignorePaths and nothing else")
}

test_s23_rejects_regex_ignore_paths_that_still_hide_tests if {
	paths := array.concat(regex_object.ignorePaths, ["**/tests/**"])
	renovate := with_value(valid_config, "regex", with_value(regex_object, "ignorePaths", paths))
	denied_with(checked(renovate, valid_platform), "regex must hold ignorePaths and nothing else")
}

test_s23_rejects_another_key_in_the_regex_object if {
	renovate := with_value(valid_config, "regex", with_value(regex_object, "pinDigests", true))
	denied_with(checked(renovate, valid_platform), "regex must hold ignorePaths and nothing else")
}

test_s23_rejects_a_regex_object_that_is_not_an_object if {
	renovate := with_value(valid_config, "regex", "tests")
	denied_with(checked(renovate, valid_platform), "regex must hold ignorePaths and nothing else")
}

test_s23_accepts_a_regex_object_without_a_description if {
	renovate := with_value(valid_config, "regex", without(regex_object, "description"))
	accepted(checked(renovate, valid_platform))
}

# The custom managers. A template of an entry wins over what its expression
# captures, and picks the datasource, the package and the registry, hence who
# dates a release: customManagers holds the three known managers, to the letter
# apart from the description, and nothing else.

test_s23_rejects_one_more_custom_manager if {
	extra := {
		"customType": "regex",
		"managerFilePatterns": ["/^Dockerfile$/"],
		"matchStrings": ["FROM (?<depName>\\S+):(?<currentValue>\\S+)"],
	}
	renovate := config_for(valid_rules, [image_manager, extra, golden_tools_manager])
	denied_with(checked(renovate, valid_platform), "customManagers[1] is not one of the three known managers")
}

test_s23_rejects_one_more_custom_manager_in_celian if {
	extra := {"customType": "regex", "managerFilePatterns": ["/^Dockerfile$/"], "matchStrings": ["FROM (?<depName>\\S+)"]}
	renovate := config_for(valid_rules, [celian_image_manager, celian_tools_manager, extra, celian_local_manager])
	denied_with(in_celian(renovate), "customManagers[2] is not one of the three known managers")
}

test_s23_rejects_an_image_manager_with_a_datasource_template if {
	manager := with_value(image_manager, "datasourceTemplate", "github-tags")
	renovate := config_for(valid_rules, [manager, golden_tools_manager])
	denied_with(checked(renovate, valid_platform), "customManagers[0] is not one of the three known managers")
}

test_s23_rejects_an_image_manager_with_a_registry_url_template if {
	manager := with_value(image_manager, "registryUrlTemplate", "https://registry.example.com")
	renovate := config_for(valid_rules, [manager, golden_tools_manager])
	denied_with(checked(renovate, valid_platform), "customManagers[0] is not one of the three known managers")
}

test_s23_rejects_an_image_manager_with_another_expression if {
	manager := with_value(image_manager, "matchStrings", ["(?<depName>\\S+)_IMAGE: (?<currentValue>\\S+)"])
	renovate := config_for(valid_rules, [manager, golden_tools_manager])
	denied_with(checked(renovate, valid_platform), "customManagers[0] is not one of the three known managers")
}

test_s23_rejects_an_image_manager_with_another_file_pattern if {
	manager := with_value(image_manager, "managerFilePatterns", ["/.*/"])
	renovate := config_for(valid_rules, [manager, golden_tools_manager])
	denied_with(checked(renovate, valid_platform), "customManagers[0] is not one of the three known managers")
}

test_s23_rejects_the_image_manager_of_celian_in_the_golden_repo if {
	renovate := config_for(valid_rules, [celian_image_manager, golden_tools_manager])
	denied_with(checked(renovate, valid_platform), "customManagers[0] is not one of the three known managers")
}

test_s23_rejects_the_image_manager_of_the_golden_repo_in_celian if {
	renovate := config_for(valid_rules, [image_manager, celian_tools_manager])
	denied_with(in_celian(renovate), "customManagers[0] is not one of the three known managers")
}

test_s23_rejects_a_tools_manager_with_a_datasource_template if {
	manager := with_value(golden_tools_manager, "datasourceTemplate", "github-tags")
	renovate := config_for(valid_rules, [image_manager, manager])
	denied_with(checked(renovate, valid_platform), "customManagers[1] is not one of the three known managers")
}

test_s23_names_the_three_known_managers_in_the_message if {
	manager := with_value(image_manager, "datasourceTemplate", "github-tags")
	renovate := config_for(valid_rules, [manager, golden_tools_manager])
	denied_with(checked(renovate, valid_platform), "the _IMAGE variables of the workflows, tests/tools/install.sh with local/scripts/lib/preflight-checks.sh, and the images of local/kind/cluster.yaml, local/tasks/, local/data/ and local/platform/")
}

test_s23_rejects_custom_managers_that_is_not_a_list if {
	renovate := with_value(valid_config, "customManagers", image_manager)
	denied_with(checked(renovate, valid_platform), "customManagers must be a list")
}

# Messages.

test_s23_names_its_requirements_in_each_message if {
	msgs := deny with input as checked({}, valid_platform)
	count(msgs) == 9
	every msg in msgs {
		startswith(msg, "S23 (FR-013")
	}
}

# The manager of the images of the local layer (step 6), and kind in the
# manager of the versions.

test_s23_rejects_a_config_without_the_local_manager if {
	renovate := config_for(valid_rules, [image_manager, golden_tools_manager])
	denied_with(checked(renovate, valid_platform), "no customManagers entry is the manager of the images of local/kind/cluster.yaml, local/tasks/, local/data/ and local/platform/")
}

test_s23_rejects_the_local_manager_of_celian_in_the_golden_repo if {
	renovate := config_for(valid_rules, [image_manager, golden_tools_manager, celian_local_manager])
	denied_with(checked(renovate, valid_platform), "customManagers[2] is not one of the three known managers")
}

test_s23_rejects_the_local_manager_of_the_golden_repo_in_celian if {
	renovate := config_for(valid_rules, [celian_image_manager, celian_tools_manager, golden_local_manager])
	denied_with(in_celian(renovate), "no customManagers entry is the manager of the images of golden/saas-b2b/local/kind/cluster.yaml")
}

test_s23_rejects_a_local_manager_with_a_versioning_template if {
	manager := with_value(golden_local_manager, "versioningTemplate", "loose")
	renovate := config_for(valid_rules, [image_manager, golden_tools_manager, manager])
	denied_with(checked(renovate, valid_platform), "customManagers[2] is not one of the three known managers")
}

test_s23_rejects_a_local_manager_that_reads_every_file if {
	manager := with_value(golden_local_manager, "managerFilePatterns", ["/^local/.+$/"])
	renovate := config_for(valid_rules, [image_manager, golden_tools_manager, manager])
	denied_with(checked(renovate, valid_platform), "customManagers[2] is not one of the three known managers")
}

test_s23_rejects_a_tools_manager_without_the_preflight_checks if {
	manager := with_value(golden_tools_manager, "managerFilePatterns", ["/^tests/tools/install\\.sh$/"])
	renovate := config_for(valid_rules, [image_manager, manager, golden_local_manager])
	denied_with(checked(renovate, valid_platform), "no customManagers entry is the manager of tests/tools/install.sh")
}

# The cache image: the patches of the cache_engine_line of platform.yaml, in
# the Alpine variant alone (ADR-015, conditions 2, 9 and 16).

without_cache_rule(renovate) := object.union(renovate, {"packageRules": [rule | some rule in renovate.packageRules; rule != cache_rule]})

test_s23_rejects_a_config_without_the_cache_rule if {
	denied_with(checked(without_cache_rule(valid_config), valid_platform), "no packageRules entry keeps the cache image on allowedVersions /^9\\.1\\.[0-9]+-alpine$/")
}

test_s23_rejects_a_cache_rule_on_the_minor_alone if {
	rule := with_value(cache_rule, "allowedVersions", "/^9\\.1\\./")
	renovate := config_with([postgres_rule, node_rule, kind_group, envoy_group, rule])
	denied_with(checked(renovate, valid_platform), "sets allowedVersions /^9\\.1\\./ for the cache image")
}

test_s23_rejects_a_cache_rule_on_another_line if {
	rule := with_value(cache_rule, "allowedVersions", "/^9\\.2\\.[0-9]+-alpine$/")
	renovate := without_cache_rule(config_with([postgres_rule, node_rule, kind_group, envoy_group, rule]))
	denied_with(checked(renovate, valid_platform), "no packageRules entry keeps the cache image")
}

test_s23_accepts_a_cache_rule_that_follows_platform_yaml if {
	rule := with_value(cache_rule, "allowedVersions", "/^9\\.2\\.[0-9]+-alpine$/")
	renovate := without_cache_rule(config_with([postgres_rule, node_rule, kind_group, envoy_group, rule]))
	accepted(checked(renovate, with_value(valid_platform, "cache_engine_line", "9.2")))
}

test_s23_rejects_a_cache_rule_for_another_datasource if {
	rule := with_value(cache_rule, "matchDatasources", ["helm"])
	renovate := without_cache_rule(config_with([postgres_rule, node_rule, kind_group, envoy_group, rule]))
	denied_with(checked(renovate, valid_platform), "no packageRules entry keeps the cache image")
}

test_s23_rejects_a_cache_rule_that_misses_the_registry_name if {
	rule := with_value(cache_rule, "matchPackageNames", ["valkey/valkey"])
	renovate := without_cache_rule(config_with([postgres_rule, node_rule, kind_group, envoy_group, rule]))
	denied_with(checked(renovate, valid_platform), "no packageRules entry keeps the cache image")
}

test_s23_rejects_a_local_manager_without_the_data_folder if {
	manager := with_value(golden_local_manager, "managerFilePatterns", ["/^local/kind/cluster\\.yaml$/", "/^local/tasks/.+\\.ya?ml$/"])
	renovate := config_for(valid_rules, [image_manager, golden_tools_manager, manager])
	denied_with(checked(renovate, valid_platform), "no customManagers entry is the manager of the images of")
}

# kubectl of the CI: the minor of platform.yaml (ADR-004, version rule, point 5).

without_kubectl_rule(renovate) := object.union(renovate, {"packageRules": [rule | some rule in renovate.packageRules; rule != kubectl_rule]})

test_s23_rejects_a_config_without_the_kubectl_rule if {
	denied_with(checked(without_kubectl_rule(valid_config), valid_platform), "no packageRules entry keeps kubectl on allowedVersions /^v?1\\.36\\./")
}

test_s23_rejects_a_kubectl_rule_on_another_minor if {
	rule := with_value(kubectl_rule, "allowedVersions", "/^v?1\\.37\\./")
	renovate := without_kubectl_rule(object.union(valid_config, {"packageRules": array.concat(valid_config.packageRules, [rule])}))
	denied_with(checked(renovate, valid_platform), "sets allowedVersions /^v?1\\.37\\./ for kubectl")
}

test_s23_rejects_a_kubectl_rule_on_the_major_alone if {
	rule := with_value(kubectl_rule, "allowedVersions", "/^v?1\\./")
	renovate := without_kubectl_rule(object.union(valid_config, {"packageRules": array.concat(valid_config.packageRules, [rule])}))
	denied_with(checked(renovate, valid_platform), "sets allowedVersions /^v?1\\./ for kubectl")
}

test_s23_rejects_a_kubectl_rule_for_another_datasource if {
	rule := with_value(kubectl_rule, "matchDatasources", ["docker"])
	renovate := without_kubectl_rule(object.union(valid_config, {"packageRules": array.concat(valid_config.packageRules, [rule])}))
	denied_with(checked(renovate, valid_platform), "no packageRules entry keeps kubectl")
}

test_s23_rejects_a_kubectl_rule_with_another_criterion if {
	rule := with_value(kubectl_rule, "matchUpdateTypes", ["patch"])
	renovate := without_kubectl_rule(object.union(valid_config, {"packageRules": array.concat(valid_config.packageRules, [rule])}))
	denied_with(checked(renovate, valid_platform), "no packageRules entry keeps kubectl")
}

test_s23_rejects_a_kubectl_rule_that_misses_the_name if {
	rule := with_value(kubectl_rule, "matchPackageNames", ["kubernetes/kubectl"])
	renovate := without_kubectl_rule(object.union(valid_config, {"packageRules": array.concat(valid_config.packageRules, [rule])}))
	denied_with(checked(renovate, valid_platform), "no packageRules entry keeps kubectl")
}
