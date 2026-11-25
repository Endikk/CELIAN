# S23: the Renovate configuration of the generated project, renovate.json,
# keeps the update rules of the constitution and of the ADRs (spec 001, plan,
# matrix S23). The delay of the constitution (principle VI) lives in package
# renovate_delay; this package holds the rules that follow platform.yaml:
# - the postgres image stays on the postgres_major of platform.yaml
#   (ADR-012, condition 5);
# - the kind node image stays on the kubernetes_minor of platform.yaml, and
#   kind and its node image share one group (ADR-004, version rule, point 5);
# - the cache image stays on the patches of the cache_engine_line of
#   platform.yaml, in the Alpine variant (ADR-015, conditions 2, 9 and 16);
# - the charts and the controller image of Envoy Gateway share one group
#   (ADR-005, updates, point 2);
# - no other entry, manager or top setting decides the branch of an update,
#   so that nothing splits those two pairs;
# - Task and conftest, pinned in tests/tools/install.sh next to
#   platform.yaml, and kind, pinned in local/scripts/lib/preflight-checks.sh,
#   keep their custom manager; the node image of local/kind/cluster.yaml,
#   the zot image of local/tasks/, the images of local/data/ and the proxy
#   image of local/platform/ keep theirs; customManagers holds only those two
#   and the one of the
#   _IMAGE variables of the workflows, and the regex managers see tests/,
#   which config:recommended hides (research RS-17).
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

label_versions := "S23 (FR-013; ADR-004, version rule, point 5; ADR-012, condition 5; ADR-015, condition 2)"

label_cache := "S23 (FR-013; ADR-015, conditions 2, 9 and 16)"

label_tools := "S23 (FR-013; research RS-17)"

label_pairs := "S23 (FR-013; ADR-004, version rule, point 5; ADR-005, updates, point 2)"

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

cache_names := {"valkey/valkey", "docker.io/valkey/valkey"}

watched_names := ((postgres_names | kind_pair_names) | envoy_names) | cache_names

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

# The cache image: the patches of the line, Alpine variant alone (ADR-015,
# conditions 2 and 9): "/^9\\.1\\.[0-9]+-alpine$/" for cache_engine_line "9.1".
expected_cache := sprintf("/^%s\\.[0-9]+-alpine$/", [replace(platform.cache_engine_line, ".", "\\.")]) if {
	is_string(platform.cache_engine_line)
}

# Shape of the input.

deny contains msg if {
	count(platform_files) != 1
	msg := sprintf("%s: expected one platform.yaml among the checked files, found %v", [label, count(platform_files)])
}

# Matching of package names. An entry of matchPackageNames catches a name
# when it is that name (Renovate compares exact names without case), or a
# regular expression between slashes that matches it (research RS-18).
# Other globs and negated patterns catch nothing here: the entries that S23
# relies on may not hold them (own_pattern).

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

# A pattern that catches() reads in full: a regular expression between
# slashes, or one of `names`. Renovate reads any other string as a glob,
# through minimatch without case, or as an exclusion when it starts with !
# (lib/util/string-match.ts, lines 11 to 27 and 48 to 57, Renovate 44.247.1);
# it reads "/" and "//" as an empty regular expression, which catches every
# name (lines 73 to 92).
own_pattern(pattern, _) if {
	is_string(pattern)
	is_string(regex_body(pattern))
}

own_pattern(pattern, names) if {
	is_string(pattern)
	lower(pattern) in names
}

# rule holds only keys of `allowed`, and in matchPackageNames only patterns
# that catches() reads in full.
plain(rule, allowed, names) if {
	is_object(rule)
	every key, _ in rule {
		key in allowed
	}
	is_array(rule.matchPackageNames)
	every pattern in rule.matchPackageNames {
		own_pattern(pattern, names)
	}
}

guard_rule(rule, names, expected) if {
	plain(rule, guard_keys, names)
	for_docker(rule)
	every name in names {
		catches(rule, name)
	}
	rule.allowedVersions == expected
}

postgres_entry(rule) if guard_rule(rule, postgres_names, expected_postgres)

node_entry(rule) if guard_rule(rule, node_names, expected_node)

cache_entry(rule) if guard_rule(rule, cache_names, expected_cache)

guard_entry(rule) if postgres_entry(rule)

guard_entry(rule) if node_entry(rule)

guard_entry(rule) if cache_entry(rule)

group_rule(rule, names) if {
	plain(rule, group_keys, names)
	grouped(rule)
	every name in names {
		catches(rule, name)
	}
}

# catches() reads neither globs nor matchDepNames, so a later entry could
# take an image back through them, such as {"matchPackageNames": ["*"],
# "allowedVersions": "/.*/"}. Only the three entries of S23 set allowedVersions;
# Renovate reads it in packageRules only (lib/config/options/index.ts).
deny contains msg if {
	some i, rule in rules
	is_object(rule)
	"allowedVersions" in object.keys(rule)
	not guard_entry(rule)
	msg := sprintf("%s: packageRules[%v] sets allowedVersions; only the postgres, node and cache entries set it, with no other key than %s, and only regexes or their own names as patterns", [label_versions, i, concat(", ", guard_keys)])
}

# An entry that turns updates off is refused in package renovate_delay,
# whatever it catches.

# Keys that decide the branch of an update, hence its PR. Renovate puts the
# updates of one branch name in one PR
# (lib/workers/repository/updates/branchify.ts, lines 47 to 49), and builds
# that name from these keys (lib/workers/repository/updates/branch-name.ts,
# lines 59 to 159), groupSlug following the last groupName
# (lib/util/package-rules/index.ts, lines 69 to 74). The last four are legacy
# names that Renovate turns into one of them
# (lib/config/migrations/migrations-service.ts, lines 103 to 105;
# lib/config/migrations/custom/separate-major-release-migration.ts).
branch_keys := {
	"groupName",
	"groupSlug",
	"group",
	"branchName",
	"branchTopic",
	"branchPrefix",
	"additionalBranchPrefix",
	"hashedBranchLength",
	"branchNameStrict",
	"separateMajorMinor",
	"separateMultipleMajor",
	"separateMultipleMinor",
	"separateMinorPatch",
	"managerBranchPrefix",
	"multipleMajorPrs",
	"separatePatchReleases",
	"separateMajorReleases",
}

# A group of S23 keeps each pair whole: it catches all of a pair or none of
# it, kind with no matchDatasources, Envoy Gateway as docker images.
kind_whole(rule) if {
	every name in kind_pair_names {
		catches(rule, name)
	}
	not rule.matchDatasources
}

envoy_whole(rule) if {
	every name in envoy_names {
		catches(rule, name)
	}
	for_docker(rule)
}

splits(rule) if {
	catches_any(rule, kind_pair_names)
	not kind_whole(rule)
}

splits(rule) if {
	catches_any(rule, envoy_names)
	not envoy_whole(rule)
}

group_entry(rule) if {
	group_rule(rule, kind_pair_names)
	not splits(rule)
}

group_entry(rule) if {
	group_rule(rule, envoy_names)
	not splits(rule)
}

group_name_path(path) if {
	count(path) == 3
	path[0] == "packageRules"
	path[2] == "groupName"
	group_entry(rules[path[1]])
}

# Only the groupName of the two groups decides a branch. Any other entry can
# catch part of a pair, through a glob, a regex, matchDepNames or a criterion
# that catches() does not read; a manager or the top can name a branch after
# each package, through a template. S23 refuses the key itself, wherever it is
# written, legacy containers of packageRules included.
deny contains msg if {
	is_object(config)
	walk(config, [path, _])
	count(path) > 0
	path[count(path) - 1] in branch_keys
	not group_name_path(path)
	msg := sprintf("%s: %v sets a key that decides the branch, hence the PR, of an update; only the kind group and the Envoy group set one, groupName, and each catches all or none of both pairs, so that nothing splits kind from its node image or the charts of Envoy Gateway from its controller", [label_pairs, path])
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
	msg := sprintf("%s: no packageRules entry keeps the postgres image on allowedVersions %s, the postgres_major of platform.yaml, with matchPackageNames catching %s, no other key than %s, and only regexes or these names as patterns", [label_postgres, expected_postgres, concat(", ", postgres_names), concat(", ", guard_keys)])
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
	msg := sprintf("%s: no packageRules entry keeps the kind node image on allowedVersions %s, the kubernetes_minor of platform.yaml, with matchPackageNames catching %s, no other key than %s, and only regexes or these names as patterns", [label_kind, expected_node, concat(", ", node_names), concat(", ", guard_keys)])
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
	msg := sprintf("%s: no packageRules entry without matchDatasources puts %s in one groupName, with no other key than %s, and only regexes or these names as patterns, so that kind and its node image move in one PR", [label_kind, concat(", ", kind_pair_names), concat(", ", group_keys)])
}

# The cache: the patches of the line of platform.yaml, Alpine variant alone.
# A minor or a major moves by hand with cache_engine_line, when Memorystore
# serves another line by default (ADR-015, condition 16); the Debian
# variant would add 26.0 MB to the first task up (condition 9).

cache_rule_found if {
	some rule in rules
	cache_entry(rule)
}

deny contains msg if {
	is_object(config)
	is_object(platform)
	not cache_rule_found
	msg := sprintf("%s: no packageRules entry keeps the cache image on allowedVersions %s, the patches of the cache_engine_line of platform.yaml in the Alpine variant, with matchPackageNames catching %s, no other key than %s, and only regexes or these names as patterns", [label_cache, expected_cache, concat(", ", cache_names), concat(", ", guard_keys)])
}

deny contains msg if {
	some i, rule in rules
	is_object(rule)
	catches_any(rule, cache_names)
	value := rule.allowedVersions
	value != expected_cache
	msg := sprintf("%s: packageRules[%v] sets allowedVersions %v for the cache image; only %s is allowed", [label_cache, i, value, expected_cache])
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
	msg := sprintf("%s: no packageRules entry puts the charts and the controller image of Envoy Gateway (%s) in one groupName, with no other key than %s, and only regexes or these names as patterns", [label_envoy, concat(", ", envoy_names), concat(", ", group_keys)])
}

# Task and conftest, then kind. tests/tools/install.sh and
# local/scripts/lib/preflight-checks.sh pin their versions, each under a
# "# renovate:" comment that tests/tools/check-renovate-comments.sh checks;
# kind moves with its node image, in the group above. Their custom manager
# is written once, to the letter apart from its description; its paths
# follow the one of platform.yaml, so that the renovate.json of CELIAN names
# the files under golden/saas-b2b/.
tools_prefix := trim_suffix(file.path, "platform.yaml") if {
	count(platform_files) == 1
	some file in platform_files
}

escaped_prefix := replace(tools_prefix, ".", "\\.")

tools_manager := {
	"customType": "regex",
	"managerFilePatterns": [
		sprintf("/^%stests/tools/install\\.sh$/", [escaped_prefix]),
		sprintf("/^%slocal/scripts/lib/preflight-checks\\.sh$/", [escaped_prefix]),
	],
	"matchStrings": [`# renovate: datasource=(?<datasource>github-releases) depName=(?<depName>\S+)\s+[A-Z0-9_]+_VERSION="(?<currentValue>[^"\s]+)"`],
	"extractVersionTemplate": "^v(?<version>.*)$",
	"versioningTemplate": "semver",
}

tools_manager_found if {
	some manager in object.get(config, "customManagers", [])
	is_object(manager)
	object.remove(manager, {"description"}) == tools_manager
}

# The manager of the _IMAGE variables of the workflows, written once as well,
# to the letter apart from its description. It reads the workflows of the
# project, and in CELIAN those of the golden repo too, so its patterns follow
# tools_prefix.
workflows_pattern(prefix) := sprintf("/^%s\\.github/workflows/.+\\.ya?ml$/", [replace(prefix, ".", "\\.")])

images_patterns := [workflows_pattern("")] if tools_prefix == ""

images_patterns := [workflows_pattern(""), workflows_pattern(tools_prefix)] if tools_prefix != ""

images_manager := {
	"customType": "regex",
	"managerFilePatterns": images_patterns,
	"matchStrings": [`# renovate: datasource=(?<datasource>docker) depName=(?<depName>\S+)\s+[A-Z0-9_]+_IMAGE\s*:\s*\S+?:(?<currentValue>[^\s@]+)@(?<currentDigest>sha256:[a-f0-9]+)`],
}

# The manager of the images of the local layer, written once as well: the
# node image of local/kind/cluster.yaml, under the key image, the zot image
# of the Taskfile of the layer, under MIRROR_IMAGE, the images of the
# manifests of local/data/ and the proxy image of local/platform/, under the
# key image (ADR-004, version rule, point 5; ADR-005, complement of
# 2026-11-26; ADR-011, condition 8; ADR-012, condition 5; ADR-015, condition
# 2; ADR-016). All are pinned by tag and digest, so the expression is the one
# of the _IMAGE variables, with the key image as well.
local_manager := {
	"customType": "regex",
	"managerFilePatterns": [
		sprintf("/^%slocal/kind/cluster\\.yaml$/", [escaped_prefix]),
		sprintf("/^%slocal/tasks/.+\\.ya?ml$/", [escaped_prefix]),
		sprintf("/^%slocal/data/.+\\.ya?ml$/", [escaped_prefix]),
		sprintf("/^%slocal/platform/.+\\.ya?ml$/", [escaped_prefix]),
	],
	"matchStrings": [`# renovate: datasource=(?<datasource>docker) depName=(?<depName>\S+)\s+(?:image|[A-Z0-9_]+_IMAGE)\s*:\s*\S+?:(?<currentValue>[^\s@]+)@(?<currentDigest>sha256:[a-f0-9]+)`],
}

local_manager_found if {
	some manager in object.get(config, "customManagers", [])
	is_object(manager)
	object.remove(manager, {"description"}) == local_manager
}

known_manager(manager) if {
	is_object(manager)
	object.remove(manager, {"description"}) == local_manager
}

known_manager(manager) if {
	is_object(manager)
	object.remove(manager, {"description"}) == images_manager
}

known_manager(manager) if {
	is_object(manager)
	object.remove(manager, {"description"}) == tools_manager
}

# A template of an entry of customManagers wins over what its expression
# captures, and picks the datasource, the package name and the registry
# (lib/modules/manager/custom/regex/utils.ts, lines 55 to 74, Renovate
# 44.247.1), hence who dates a release. Only the three known managers stay.
deny contains msg if {
	is_object(config)
	is_string(tools_prefix)
	managers := object.get(config, "customManagers", [])
	not is_array(managers)
	msg := sprintf("%s: customManagers must be a list", [label_tools])
}

deny contains msg if {
	is_object(config)
	is_string(tools_prefix)
	managers := object.get(config, "customManagers", [])
	is_array(managers)
	some i, manager in managers
	not known_manager(manager)
	msg := sprintf("%s: customManagers[%v] is not one of the three known managers, to the letter apart from the description: the _IMAGE variables of the workflows, %stests/tools/install.sh with %slocal/scripts/lib/preflight-checks.sh, and the images of %slocal/kind/cluster.yaml, %slocal/tasks/, %slocal/data/ and %slocal/platform/; a template of another entry picks the datasource, the package and the registry, hence who dates the release", [label_tools, i, tools_prefix, tools_prefix, tools_prefix, tools_prefix, tools_prefix, tools_prefix])
}

deny contains msg if {
	is_object(config)
	is_string(tools_prefix)
	not tools_manager_found
	msg := sprintf("%s: no customManagers entry is the manager of %stests/tools/install.sh and %slocal/scripts/lib/preflight-checks.sh, to the letter apart from its description (regex, github-releases, extractVersion ^v, semver); without it, Renovate never updates Task, conftest and kind", [label_tools, tools_prefix, tools_prefix])
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

deny contains msg if {
	is_object(config)
	is_string(tools_prefix)
	not local_manager_found
	msg := sprintf("%s: no customManagers entry is the manager of the images of %slocal/kind/cluster.yaml, %slocal/tasks/, %slocal/data/ and %slocal/platform/, to the letter apart from its description (regex, docker, key image or <NAME>_IMAGE, tag and digest); without it, Renovate never updates the node image of kind, the zot image and the images of the data layer", [label_kind, tools_prefix, tools_prefix, tools_prefix, tools_prefix])
}
