# S23, delay part: a renovate.json keeps the update delay of the
# constitution (spec 001, plan, matrix S23):
# - every update waits 7 days (constitution, principle VI);
# - a security fix does not wait (principle VI, constitution 1.2.0);
# - an update from a registry that Renovate cannot date waits on the
#   Dependency Dashboard until a person ticks it (ADR-016);
# - nothing turns updates off, security fixes included (principle VI,
#   ADR-016);
# - entries are written in packageRules at the top only, where the checks
#   of both packages read them.
#
# The rules that hold for any Renovate configuration of CELIAN live here,
# apart from the rules that follow platform.yaml, in package renovate_rules.
# tests/static/s23-renovate.sh runs both packages on renovate.json of the
# generated project. In CELIAN, scripts/renovate/check-renovate.sh runs both
# packages on the renovate.json of CELIAN (ADR-016, condition 2).
#
# Input: one renovate.json, given to `conftest test --combine`, a list of
# objects with a `path` and the parsed `contents` (research RS-18).
package renovate_delay

label := "S23 (FR-013)"

label_delay := "S23 (FR-013; constitution, principle VI)"

label_undated := "S23 (FR-013; constitution, principle VI; ADR-016)"

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
# else, with two exceptions: vulnerabilityAlerts, and the entry of ADR-016
# below. Renovate also reads them in packageRules, in the config of a manager
# and in the object of an update type, such as digest (research RS-18).
delay_keys := {"minimumReleaseAge", "minimumReleaseAgeBehaviour", "internalChecksFilter"}

allowed_delay_path(path) if path == ["vulnerabilityAlerts", "minimumReleaseAge"]

allowed_delay_path(path) if undated_rule_path(path, "minimumReleaseAgeBehaviour")

deny contains msg if {
	is_object(config)
	walk(config, [path, _])
	count(path) > 1
	path[count(path) - 1] in delay_keys
	not allowed_delay_path(path)
	msg := sprintf("%s: %v sets the delay again; it is set once, at the top of renovate.json, apart from the entry of ADR-016", [label_delay, path])
}

# Legacy keys. Renovate migrates a configuration before it reads it, at every
# depth, each packageRules entry included (lib/config/migration.ts, lines 92
# to 119, Renovate 44.247.1). Three legacy keys turn into a key that S23
# checks, and would pass under their old name:
# - stabilityDays becomes minimumReleaseAge, 0 becoming null
#   (lib/config/migrations/custom/stability-days-migration.ts, lines 12 to 23);
# - masterIssueApproval becomes dependencyDashboardApproval
#   (lib/config/migrations/migrations-service.ts, line 110);
# - unpublishSafe set to true adds preset security:minimumReleaseAgeNpm to
#   extends (lib/config/migrations/custom/unpublish-safe-migration.ts, lines
#   19 to 37).
# A fourth turns into the Dependency Dashboard, where the updates of ADR-016
# wait for approval:
# - masterIssue becomes dependencyDashboard (migrations-service.ts, line
#   109), then an object whose enabled field takes the old boolean
#   (lib/config/migrations/custom/dependency-dashboard-migration.ts, lines 36
#   to 64). Renovate keeps the dashboard and reads its boxes as long as an
#   entry asks for approval (lib/workers/repository/dependency-dashboard.ts,
#   lines 194 to 196 and 380 to 383), so the key cannot drop the approval
#   today. S23 refuses it all the same: the dashboard is set under its
#   current name only.
# No other renamed property of migrations-service.ts (lines 93 to 119), and
# no other custom migration, writes a key of the delay, the approval,
# internalChecksFilter or extends.
legacy_keys := {"stabilityDays", "masterIssueApproval", "masterIssue", "unpublishSafe"}

deny contains msg if {
	is_object(config)
	walk(config, [path, _])
	count(path) > 0
	path[count(path) - 1] in legacy_keys
	msg := sprintf("%s: %v is a legacy key that Renovate turns into the delay, the approval, the dashboard or a preset", [label_delay, path])
}

# Legacy containers of entries. Renovate moves their content into
# packageRules before it reads the configuration, at every depth, where the
# checks of the entries (allowedVersions, the branch keys, the entry of
# ADR-016) do not look for it:
# - pathRules and packages are appended to packageRules
#   (lib/config/migrations/custom/path-rules-migration.ts, lines 9 to 17;
#   packages-migration.ts, lines 9 to 17);
# - an object of packageFiles with more than its packageFile becomes an entry
#   (package-files-migration.ts, lines 8 to 41);
# - dependencies, devDependencies, optionalDependencies, peerDependencies,
#   engines and depTypes become entries on matchDepTypes
#   (dep-types-migration.ts, lines 12 to 40);
# - an object under docker, dotnet, golang, java, js, node, php, python,
#   ruby or rust becomes an entry on matchCategories, placed first
#   (lib/config/migration.ts, lines 140 to 166).
# No current option and no manager bears one of these names
# (lib/config/options/index.ts; lib/modules/manager/api.ts), so S23 refuses
# the name whatever its value. Entries are written in packageRules only.
legacy_container_keys := {
	"pathRules",
	"packages",
	"packageFiles",
	"dependencies",
	"devDependencies",
	"optionalDependencies",
	"peerDependencies",
	"engines",
	"depTypes",
	"docker",
	"dotnet",
	"golang",
	"java",
	"js",
	"node",
	"php",
	"python",
	"ruby",
	"rust",
}

deny contains msg if {
	is_object(config)
	walk(config, [path, _])
	count(path) > 0
	path[count(path) - 1] in legacy_container_keys
	msg := sprintf("%s: %v is a legacy key that Renovate moves into packageRules, out of reach of the checks of the entries; entries are written in packageRules only", [label, path])
}

# Renovate merges each entry of a nested packageRules into its parent, and
# puts the result in place of the parent (lib/config/migration.ts, lines 167
# to 191).
deny contains msg if {
	is_object(config)
	walk(config, [path, _])
	count(path) > 1
	path[count(path) - 1] == "packageRules"
	msg := sprintf("%s: %v nests packageRules; Renovate flattens it out of reach of the checks of the entries, which are written in packageRules at the top only", [label, path])
}

# Experimental options of the delay (lib/config/options/index.ts, lines 2506
# to 2529, Renovate 44.247.1). With the sync, Renovate passes the delay to the
# package managers, and upstream warns that the behaviour may change.
experimental_delay_keys := {"minimumReleaseAgePackageManager", "minimumReleaseAgePackageManagerSync"}

deny contains msg if {
	is_object(config)
	walk(config, [path, _])
	count(path) > 0
	path[count(path) - 1] in experimental_delay_keys
	msg := sprintf("%s: %v is an experimental option that hands the delay to the package managers", [label_delay, path])
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

# Registries without a release date (ADR-016). Renovate dates the images of
# Docker Hub only, so under timestamp-required an update from ghcr.io,
# quay.io or mcr.microsoft.com waits forever, security fixes included. One
# packageRules entry, this one to the letter, description aside, lets such a
# release through the delay check (timestamp-optional) and holds it on the
# Dependency Dashboard until a person ticks it (dependencyDashboardApproval).
# Any other shape could drop the approval or widen the registries, so none
# is accepted: another registry goes through an ADR, then through this rule
# (ADR-016, condition 4).
undated_registries_rule := {
	"matchDatasources": ["docker"],
	"matchPackageNames": [`/^(ghcr\.io|quay\.io|mcr\.microsoft\.com)/.+$/`],
	"minimumReleaseAgeBehaviour": "timestamp-optional",
	"dependencyDashboardApproval": true,
}

is_undated_rule(rule) if {
	is_object(rule)
	object.remove(rule, {"description"}) == undated_registries_rule
}

# path is key `key` of a packageRules entry that is the entry of ADR-016.
undated_rule_path(path, key) if {
	count(path) == 3
	path[0] == "packageRules"
	path[2] == key
	is_undated_rule(rules[path[1]])
}

undated_rule_found if {
	some rule in rules
	is_undated_rule(rule)
}

deny contains msg if {
	is_object(config)
	not undated_rule_found
	msg := sprintf("%s: no packageRules entry is the entry of ADR-016 for ghcr.io, quay.io and mcr.microsoft.com, description aside; without it, their updates wait forever, security fixes included", [label_undated])
}

# The approval is set by the entry of ADR-016 and nowhere else. Renovate
# reads it at the top, in packageRules, and in the config of a manager, of an
# update type, of vulnerabilityAlerts and of group (sharedScopes,
# lib/config/options/scopes.ts, Renovate 44.247.1): an entry that turns it
# off after the entry of ADR-016 would let these images in without any delay.
deny contains msg if {
	is_object(config)
	walk(config, [path, _])
	count(path) > 0
	path[count(path) - 1] == "dependencyDashboardApproval"
	not undated_rule_path(path, "dependencyDashboardApproval")
	msg := sprintf("%s: %v sets dependencyDashboardApproval; only the entry of ADR-016 sets it", [label_undated, path])
}

# Updates turned off. Renovate applies a packageRules entry to every package
# that its criteria let through, and an entry without criteria to all of them
# (lib/util/package-rules/index.ts, lines 28 to 46, Renovate 44.247.1). A
# criterion can be a glob read by minimatch, a regex, a negated pattern
# (lib/util/string-match.ts, lines 11 to 57), matchDepNames or
# matchDatasources: S23 cannot tell which updates such an entry turns off,
# nor what a manager or the top turns off. A security fix does not bring the
# update back: the entry that Renovate adds for an advisory forces the
# settings of vulnerabilityAlerts, where enabled is not set
# (lib/workers/repository/init/vulnerability.ts, lines 160 to 166;
# lib/util/package-rules/index.ts, lines 79 to 103). So enabled is true
# wherever it is written, legacy containers included.
deny contains msg if {
	is_object(config)
	walk(config, [path, value])
	count(path) > 0
	path[count(path) - 1] == "enabled"
	value != true
	msg := sprintf("%s: %v sets enabled to %v; enabled is written as true or not at all, because S23 cannot tell which updates, security fixes included, an entry, a manager or the top would turn off", [label_undated, path, value])
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
