# S23: the Renovate configuration of the generated project, renovate.json,
# keeps the update rules of the constitution and of the ADRs (spec 001, plan,
# matrix S23). The delay of the constitution (principle VI) lives in package
# renovate_delay; this package holds the rules that follow platform.yaml:
# - the postgres image stays on the postgres_major of platform.yaml
#   (ADR-012, condition 5);
# - the kind node image stays on the kubernetes_minor of platform.yaml, and
#   kind and its node image share one group (ADR-004, version rule, point 5);
# - the charts and the controller image of Envoy Gateway share one group
#   (ADR-005, updates, point 2).
#
# Input: renovate.json and platform.yaml, given to `conftest test --combine`,
# a list of objects with a `path` and the parsed `contents` (research RS-18).
# Package renovate_delay checks the shape of renovate.json; this one reads it
# through renovate_delay.config.
# Renovate never reads this file in CELIAN (research RS-17): these policies
# and the validator run by X01 are its only checks. Neither can tell whether
# a manager of Renovate finds each image; the steps that write those files
# give Renovate a way to find them.
package renovate_rules

import data.renovate_delay

label := "S23 (FR-013)"

label_postgres := "S23 (FR-013; ADR-012, condition 5)"

label_kind := "S23 (FR-013; ADR-004, version rule, point 5)"

label_envoy := "S23 (FR-013; ADR-005, updates, point 2)"

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
	is_object(rule)
	for_docker(rule)
	every name in postgres_names {
		catches(rule, name)
	}
	rule.allowedVersions == expected_postgres
}

deny contains msg if {
	is_object(config)
	is_object(platform)
	not postgres_rule_found
	msg := sprintf("%s: no packageRules entry keeps the postgres image on allowedVersions %s, the postgres_major of platform.yaml, with matchPackageNames catching %s", [label_postgres, expected_postgres, concat(", ", postgres_names)])
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
	is_object(rule)
	for_docker(rule)
	every name in node_names {
		catches(rule, name)
	}
	rule.allowedVersions == expected_node
}

deny contains msg if {
	is_object(config)
	is_object(platform)
	not node_rule_found
	msg := sprintf("%s: no packageRules entry keeps the kind node image on allowedVersions %s, the kubernetes_minor of platform.yaml, with matchPackageNames catching %s", [label_kind, expected_node, concat(", ", node_names)])
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
	is_object(rule)
	grouped(rule)
	not rule.matchDatasources
	every name in kind_pair_names {
		catches(rule, name)
	}
}

deny contains msg if {
	is_object(config)
	not kind_group_found
	msg := sprintf("%s: no packageRules entry without matchDatasources puts %s in one groupName, so that kind and its node image move in one PR", [label_kind, concat(", ", kind_pair_names)])
}

# Envoy Gateway: the charts and the controller image in one group.

envoy_group_found if {
	some rule in rules
	is_object(rule)
	grouped(rule)
	for_docker(rule)
	every name in envoy_names {
		catches(rule, name)
	}
}

deny contains msg if {
	is_object(config)
	not envoy_group_found
	msg := sprintf("%s: no packageRules entry puts the charts and the controller image of Envoy Gateway (%s) in one groupName", [label_envoy, concat(", ", envoy_names)])
}
