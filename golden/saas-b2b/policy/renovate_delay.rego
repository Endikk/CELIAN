# S23, delay part: a renovate.json keeps the update delay of the
# constitution (spec 001, plan, matrix S23):
# - every update waits 7 days (constitution, principle VI);
# - a security fix does not wait (principle VI, constitution 1.2.0).
#
# The rules that hold for any Renovate configuration of CELIAN live here,
# apart from the rules that follow platform.yaml, in package renovate_rules.
# tests/static/s23-renovate.sh runs both packages on renovate.json of the
# generated project.
#
# Input: one renovate.json, given to `conftest test --combine`, a list of
# objects with a `path` and the parsed `contents` (research RS-18).
package renovate_delay

label := "S23 (FR-013)"

label_delay := "S23 (FR-013; constitution, principle VI)"

renovate_files contains file if {
	some file in input
	regex.match(`(^|/)renovate\.json$`, file.path)
}

config := file.contents if {
	count(renovate_files) == 1
	some file in renovate_files
	is_object(file.contents)
}

rules := object.get(config, "packageRules", [])

alerts := object.get(config, "vulnerabilityAlerts", {})

# Shape of the input.

deny contains msg if {
	count(renovate_files) != 1
	msg := sprintf("%s: expected one renovate.json among the checked files, found %v", [label, count(renovate_files)])
}

deny contains msg if {
	some file in renovate_files
	not is_object(file.contents)
	msg := sprintf("%s: %s must hold a JSON object", [label, file.path])
}

deny contains msg if {
	is_object(config)
	not is_array(rules)
	msg := sprintf("%s: packageRules must be a list", [label])
}

# Delay of 7 days, written once, at the top.

deny contains msg if {
	is_object(config)
	value := object.get(config, "minimumReleaseAge", null)
	value != "7 days"
	msg := sprintf("%s: minimumReleaseAge must be \"7 days\", found %v", [label_delay, value])
}

# The keys that govern the delay are written out at the top and set nowhere
# else, vulnerabilityAlerts aside. Renovate also reads them in packageRules,
# in the config of a manager and in the object of an update type, such as
# digest (research RS-18).
delay_keys := {"minimumReleaseAge", "minimumReleaseAgeBehaviour", "internalChecksFilter"}

allowed_delay_path(path) if path == ["vulnerabilityAlerts", "minimumReleaseAge"]

deny contains msg if {
	is_object(config)
	walk(config, [path, _])
	count(path) > 1
	path[count(path) - 1] in delay_keys
	not allowed_delay_path(path)
	msg := sprintf("%s: %v sets the delay again; it is set once, at the top of renovate.json", [label_delay, path])
}

deny contains msg if {
	is_object(config)
	object.get(config, "minimumReleaseAgeBehaviour", null) != "timestamp-required"
	msg := sprintf("%s: minimumReleaseAgeBehaviour must be written out as \"timestamp-required\", or a release without a date skips the delay", [label_delay])
}

deny contains msg if {
	is_object(config)
	object.get(config, "internalChecksFilter", null) != "strict"
	msg := sprintf("%s: internalChecksFilter must be written out as \"strict\"; none and flexible open a PR for a release still in the delay", [label_delay])
}

deny contains msg if {
	is_object(config)
	object.get(config, "extends", []) != ["config:recommended", "helpers:pinGitHubActionDigests", "customManagers:githubActionsVersions"]
	msg := sprintf("%s: extends must hold exactly the three presets of CELIAN; another preset can change the delay", [label_delay])
}

# Renovate reads extends anywhere in a configuration (research RS-18). A
# preset extended below the top brings settings that S23 does not read.
deny contains msg if {
	is_object(config)
	walk(config, [path, _])
	count(path) > 1
	path[count(path) - 1] == "extends"
	msg := sprintf("%s: %v extends a preset; presets are listed once, in the extends at the top", [label_delay, path])
}

# Security exception: written out, so that a change of default upstream
# cannot remove it.

null_delay(obj) if {
	is_object(obj)
	obj.minimumReleaseAge == null
}

deny contains msg if {
	is_object(config)
	not null_delay(alerts)
	msg := sprintf("%s: vulnerabilityAlerts.minimumReleaseAge must be written out as null, so that a security fix skips the delay", [label_delay])
}

deny contains msg if {
	is_object(alerts)
	object.get(alerts, "enabled", true) == false
	msg := sprintf("%s: vulnerabilityAlerts must stay enabled", [label_delay])
}

deny contains msg if {
	is_object(config)
	object.get(config, "osvVulnerabilityAlerts", false) != true
	msg := sprintf("%s: osvVulnerabilityAlerts must be true; it raises the security fixes of npm and NuGet packages", [label_delay])
}
