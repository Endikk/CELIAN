# S23: the Renovate configuration of the generated project, renovate.json,
# keeps the update rules of the constitution and of the ADRs (spec 001, plan,
# matrix S23). The delay of the constitution (principle VI) lives in package
# renovate_delay; this package holds the rules that follow platform.yaml:
# - the postgres image stays on the postgres_major of platform.yaml
#   (ADR-012, condition 5);
# - the kind node image stays on the kubernetes_minor of platform.yaml, and
#   kind and its node image share one group (ADR-004, version rule, point 5);
# - the charts and the controller image of Envoy Gateway share one group
#   (ADR-005, updates, point 2);
# - Task and conftest, pinned in tests/tools/install.sh next to
#   platform.yaml, keep their custom manager, and the regex managers see
#   tests/, which config:recommended hides (research RS-17).
#
# Input: renovate.json and platform.yaml, given to `conftest test --combine`,
# a list of objects with a `path` and the parsed `contents` (research RS-18).
# Package renovate_delay checks the shape of renovate.json; this one reads it
# through renovate_delay.config.
# Renovate never reads this file in CELIAN (research RS-17): these policies
# and the validator run by X01 are its only checks. The Renovate of CELIAN
# reads the renovate.json of CELIAN, and applies it to the files of golden/:
# that file carries the same entries, and scripts/renovate/check-renovate.sh
# runs this package on it, against golden/saas-b2b/platform.yaml. Neither
# check can tell whether a manager of Renovate finds each image; the steps
# that write those files give Renovate a way to find them.
package renovate_rules

import data.renovate_delay

label := "S23 (FR-013)"

label_postgres := "S23 (FR-013; ADR-012, condition 5)"

label_kind := "S23 (FR-013; ADR-004, version rule, point 5)"

label_envoy := "S23 (FR-013; ADR-005, updates, point 2)"

label_versions := "S23 (FR-013; ADR-004, version rule, point 5; ADR-012, condition 5)"

label_tools := "S23 (FR-013; research RS-17)"

# Names under which Renovate may report each image or release: with or
# without the registry, as the file it reads writes them.
postgres_names := {"postgres", "library/postgres", "docker.io/library/postgres"}

node_names := {"kindest/node", "docker.io/kindest/node"}

kind_pair_names := node_names | {"kubernetes-sigs/kind"}

envoy_names := {
	"envoyproxy/gateway",
	"envoyproxy/gateway-helm",
	"envoyproxy/gateway-crds-helm",
	"docker.io/envoyproxy/gateway",
	"docker.io/envoyproxy/gateway-helm",
	"docker.io/envoyproxy/gateway-crds-helm",
}

watched_names := (postgres_names | kind_pair_names) | envoy_names

platform_files contains file if {
	some file in input
	regex.match(`(^|/)platform\.yaml$`, file.path)
}

config := renovate_delay.config

platform := file.contents if {
	count(platform_files) == 1
	some file in platform_files
	is_object(file.contents)
}

rules := renovate_delay.rules

# allowedVersions that platform.yaml implies, as Renovate reads a regular
# expression: between two slashes (research RS-18).
expected_postgres := sprintf("/^%s\\./", [platform.postgres_major]) if {
	is_string(platform.postgres_major)
}

expected_node := sprintf("/^v%s\\./", [replace(platform.kubernetes_minor, ".", "\\.")]) if {
	is_string(platform.kubernetes_minor)
}

# Shape of the input.

deny contains msg if {
	count(platform_files) != 1
	msg := sprintf("%s: expected one platform.yaml among the checked files, found %v", [label, count(platform_files)])
}

# Matching of package names. An entry of matchPackageNames catches a name
# when it is that name (Renovate compares exact names without case), or a
# regular expression between slashes that matches it (research RS-18).
# Other globs and negated patterns catch nothing here.

regex_body(pattern) := substring(pattern, 1, count(pattern) - 2) if {
	startswith(pattern, "/")
	endswith(pattern, "/")
	count(pattern) > 2
}

regex_body(pattern) := concat("", ["(?i)", substring(pattern, 1, count(pattern) - 3)]) if {
	startswith(pattern, "/")
	endswith(pattern, "/i")
	count(pattern) > 3
}

catches(rule, name) if {
	some pattern in object.get(rule, "matchPackageNames", [])
	is_string(pattern)
	lower(pattern) == lower(name)
}

catches(rule, name) if {
	some pattern in object.get(rule, "matchPackageNames", [])
	is_string(pattern)
	regex.match(regex_body(pattern), name)
}

catches_any(rule, names) if {
	some name in names
	catches(rule, name)
}

for_docker(rule) if not rule.matchDatasources

for_docker(rule) if "docker" in rule.matchDatasources

grouped(rule) if {
	is_string(rule.groupName)
	rule.groupName != ""
}

# Entries that S23 relies on hold nothing else than these keys. Renovate
# applies an entry only when every criterion in it matches
# (lib/util/package-rules/index.ts, lines 28 to 46, Renovate 44.247.1): one
# more criterion, such as matchFileNames, matchUpdateTypes or
# matchCurrentVersion, could make the entry match nothing while catches()
# still finds the names in it.
guard_keys := {"description", "matchDatasources", "matchPackageNames", "allowedVersions"}

group_keys := {"description", "matchDatasources", "matchPackageNames", "groupName"}

# rule holds only keys of `allowed`, and a list of plain patterns in
# matchPackageNames. A pattern that starts with ! excludes the names it
# matches (lib/util/string-match.ts, lines 48 to 57), and catches() does not
# read it.
plain(rule, allowed) if {
	is_object(rule)
	every key, _ in rule {
		key in allowed
	}
	is_array(rule.matchPackageNames)
	every pattern in rule.matchPackageNames {
		is_string(pattern)
		not startswith(pattern, "!")
	}
}

guard_rule(rule, names, expected) if {
	plain(rule, guard_keys)
	for_docker(rule)
	every name in names {
		catches(rule, name)
	}
	rule.allowedVersions == expected
}

postgres_entry(rule) if guard_rule(rule, postgres_names, expected_postgres)

node_entry(rule) if guard_rule(rule, node_names, expected_node)

guard_entry(rule) if postgres_entry(rule)

guard_entry(rule) if node_entry(rule)

group_rule(rule, names) if {
	plain(rule, group_keys)
	grouped(rule)
	every name in names {
		catches(rule, name)
	}
}

# catches() reads neither globs nor matchDepNames, so a later entry could
# take an image back through them, such as {"matchPackageNames": ["*"],
# "allowedVersions": "/.*/"}. Only the two entries of S23 set allowedVersions;
# Renovate reads it in packageRules only (lib/config/options/index.ts).
deny contains msg if {
	some i, rule in rules
	is_object(rule)
	"allowedVersions" in object.keys(rule)
	not guard_entry(rule)
	msg := sprintf("%s: packageRules[%v] sets allowedVersions; only the postgres and node entries set it, with no other key than %s, and no pattern that starts with !", [label_versions, i, concat(", ", guard_keys)])
}

deny contains msg if {
	some i, rule in rules
	is_object(rule)
	rule.enabled == false
	catches_any(rule, watched_names)
	msg := sprintf("%s: packageRules[%v] turns off the updates of an image or release that S23 watches", [label, i])
}

# Postgres: no other major than the one of platform.yaml.

postgres_rule_found if {
	some rule in rules
	postgres_entry(rule)
}

deny contains msg if {
	is_object(config)
	is_object(platform)
	not postgres_rule_found
	msg := sprintf("%s: no packageRules entry keeps the postgres image on allowedVersions %s, the postgres_major of platform.yaml, with matchPackageNames catching %s, no other key than %s, and no pattern that starts with !", [label_postgres, expected_postgres, concat(", ", postgres_names), concat(", ", guard_keys)])
}

deny contains msg if {
	some i, rule in rules
	is_object(rule)
	catches_any(rule, postgres_names)
	value := rule.allowedVersions
	value != expected_postgres
	msg := sprintf("%s: packageRules[%v] sets allowedVersions %v for the postgres image; only %s is allowed", [label_postgres, i, value, expected_postgres])
}

# kind: the node image on the minor of platform.yaml, and in one group with
# kind itself.

node_rule_found if {
	some rule in rules
	node_entry(rule)
}

deny contains msg if {
	is_object(config)
	is_object(platform)
	not node_rule_found
	msg := sprintf("%s: no packageRules entry keeps the kind node image on allowedVersions %s, the kubernetes_minor of platform.yaml, with matchPackageNames catching %s, no other key than %s, and no pattern that starts with !", [label_kind, expected_node, concat(", ", node_names), concat(", ", guard_keys)])
}

deny contains msg if {
	some i, rule in rules
	is_object(rule)
	catches_any(rule, node_names)
	value := rule.allowedVersions
	value != expected_node
	msg := sprintf("%s: packageRules[%v] sets allowedVersions %v for the kind node image; only %s is allowed", [label_kind, i, value, expected_node])
}

kind_group_found if {
	some rule in rules
	group_rule(rule, kind_pair_names)
	not rule.matchDatasources
}

deny contains msg if {
	is_object(config)
	not kind_group_found
	msg := sprintf("%s: no packageRules entry without matchDatasources puts %s in one groupName, with no other key than %s, and no pattern that starts with !, so that kind and its node image move in one PR", [label_kind, concat(", ", kind_pair_names), concat(", ", group_keys)])
}

# Envoy Gateway: the charts and the controller image in one group.

envoy_group_found if {
	some rule in rules
	group_rule(rule, envoy_names)
	for_docker(rule)
}

deny contains msg if {
	is_object(config)
	not envoy_group_found
	msg := sprintf("%s: no packageRules entry puts the charts and the controller image of Envoy Gateway (%s) in one groupName, with no other key than %s, and no pattern that starts with !", [label_envoy, concat(", ", envoy_names), concat(", ", group_keys)])
}

# Task and conftest. tests/tools/install.sh pins their versions, each under
# a "# renovate:" comment that tests/tools/check-renovate-comments.sh checks.
# Its custom manager is written once, to the letter apart from its
# description; its path follows the one of platform.yaml, so that the
# renovate.json of CELIAN names golden/saas-b2b/tests/tools/install.sh.
tools_prefix := trim_suffix(file.path, "platform.yaml") if {
	count(platform_files) == 1
	some file in platform_files
}

tools_manager := {
	"customType": "regex",
	"managerFilePatterns": [sprintf("/^%stests/tools/install\\.sh$/", [replace(tools_prefix, ".", "\\.")])],
	"matchStrings": [`# renovate: datasource=(?<datasource>github-releases) depName=(?<depName>\S+)\s+[A-Z0-9_]+_VERSION="(?<currentValue>[^"\s]+)"`],
	"extractVersionTemplate": "^v(?<version>.*)$",
	"versioningTemplate": "semver",
}

tools_manager_found if {
	some manager in object.get(config, "customManagers", [])
	is_object(manager)
	object.remove(manager, {"description"}) == tools_manager
}

deny contains msg if {
	is_object(config)
	is_string(tools_prefix)
	not tools_manager_found
	msg := sprintf("%s: no customManagers entry is the manager of %stests/tools/install.sh, to the letter apart from its description (regex, github-releases, extractVersion ^v, semver); without it, Renovate never updates Task and conftest", [label_tools, tools_prefix])
}

# config:recommended extends :ignoreModulesAndTests, whose ignorePaths hide
# tests/ from every manager (lib/config/presets/internal/default.preset.ts,
# lines 306 to 315, Renovate 44.247.1). The regex object at the top gives the
# regex managers the same list without **/tests/**, and nothing else.
regex_ignore_paths := [
	"**/node_modules/**",
	"**/bower_components/**",
	"**/vendor/**",
	"**/examples/**",
	"**/__tests__/**",
	"**/test/**",
	"**/__fixtures__/**",
]

regex_object_found if {
	value := object.get(config, "regex", null)
	is_object(value)
	object.remove(value, {"description"}) == {"ignorePaths": regex_ignore_paths}
}

deny contains msg if {
	is_object(config)
	not regex_object_found
	msg := sprintf("%s: regex must hold ignorePaths and nothing else, description aside: %v, the list of preset :ignoreModulesAndTests without **/tests/**, so that Renovate sees tests/tools/install.sh", [label_tools, regex_ignore_paths])
}
