# U03 and E27: the decision of the image scan (spec 001, FR-021, FR-022;
# research RS-23). Trivy writes one JSON report per image, every severity
# kept; this policy applies the threshold of security/scan-policy.yaml and
# the exceptions that hold (scan_exceptions.rego), and refuses each image and
# vulnerability at or above the threshold without one, naming both (story 7,
# scenario 3).
#
# Input: the files given to `conftest test --combine`, a list of objects with
# a `path` and the parsed `contents`: the reports of Trivy 0.76.2 (schema 2,
# research RS-23) and the exception files. Data: data.scan_policy
# (severity_threshold, max_exception_days) and data.scan_today (YYYY-MM-DD).
#
# Rules:
# - levels in the order of Trivy: UNKNOWN, LOW, MEDIUM, HIGH, CRITICAL. A
#   finding at or above the threshold blocks; UNKNOWN never blocks and is
#   listed (research RS-23, to be confirmed by [SECU]); a missing severity
#   reads UNKNOWN, as in Trivy; a severity outside the list blocks, since
#   nothing ranks it;
# - the image of a finding is the repository of the scanned reference,
#   without tag or digest, as the exceptions name it;
# - warnings list the findings that an exception covers, the exceptions
#   that do not hold or match nothing, and the count per image and level,
#   which [SECU] reads to review the threshold.
package scan_decision

import data.scan_exceptions

label := "E27 (FR-021, FR-022; research RS-23)"

levels := ["UNKNOWN", "LOW", "MEDIUM", "HIGH", "CRITICAL"]

threshold := data.scan_policy.severity_threshold

threshold_rank := rank if {
	some rank, level in levels
	level == threshold
	level != "UNKNOWN"
}

reports contains file if {
	some file in input
	is_object(file.contents)
	"ArtifactName" in object.keys(file.contents)
}

# The repository of a reference: no digest, and no tag after the last "/".
repository(name) := concat("/", array.concat(array.slice(parts, 0, count(parts) - 1), [split(last, ":")[0]])) if {
	parts := split(split(name, "@")[0], "/")
	last := parts[count(parts) - 1]
}

severity(vulnerability) := value if {
	value := object.get(vulnerability, "Severity", "")
	is_string(value)
	value != ""
}

severity(vulnerability) := "UNKNOWN" if {
	value := object.get(vulnerability, "Severity", "")
	not non_empty_string(value)
}

non_empty_string(value) if {
	is_string(value)
	value != ""
}

findings contains finding if {
	some file in reports
	image := repository(file.contents.ArtifactName)
	some result in object.get(file.contents, "Results", [])
	some vulnerability in object.get(result, "Vulnerabilities", [])
	finding := {
		"image": image,
		"id": object.get(vulnerability, "VulnerabilityID", "?"),
		"severity": severity(vulnerability),
		"package": object.get(vulnerability, "PkgName", "?"),
		"installed": object.get(vulnerability, "InstalledVersion", "?"),
		"fixed": object.get(vulnerability, "FixedVersion", ""),
		"target": object.get(result, "Target", "?"),
	}
}

blocks(sev) if {
	some rank, level in levels
	level == sev
	level != "UNKNOWN"
	rank >= threshold_rank
}

blocks(sev) if {
	not sev in levels
}

covering(finding) := entry if {
	some entry in scan_exceptions.valid_entries
	entry.image == finding.image
	entry.vulnerability == finding.id
}

fix_text(fixed) := "no fixed version" if fixed == ""

fix_text(fixed) := sprintf("fixed in %s", [fixed]) if fixed != ""

describe(finding) := sprintf("%s: %s (%s) in %s %s, %s; target %s", [
	finding.image, finding.id, finding.severity, finding.package,
	finding.installed, fix_text(finding.fixed), finding.target,
])

refused contains finding if {
	some finding in findings
	blocks(finding.severity)
	not covering(finding)
}

deny contains msg if {
	some finding in refused
	msg := sprintf("%s: %s: no valid exception", [label, describe(finding)])
}

deny contains msg if {
	count(reports) == 0
	msg := sprintf("%s: no Trivy report among the checked files", [label])
}

deny contains msg if {
	some file in reports
	file.contents.SchemaVersion != 2
	msg := sprintf("%s: %s: SchemaVersion %v, 2 expected (research RS-23)", [label, file.path, file.contents.SchemaVersion])
}

deny contains msg if {
	some file in reports
	object.get(file.contents, "ArtifactType", "") != "container_image"
	msg := sprintf("%s: %s: ArtifactType %v, container_image expected", [label, file.path, object.get(file.contents, "ArtifactType", "")])
}

deny contains msg if {
	not threshold_rank
	msg := sprintf("%s: no valid severity_threshold in data.scan_policy (LOW, MEDIUM, HIGH or CRITICAL)", [label])
}

deny contains msg if {
	not scan_exceptions.today_ns
	msg := sprintf("%s: no date of the day (data.scan_today), as YYYY-MM-DD", [label])
}

warn contains msg if {
	some finding in findings
	finding.severity == "UNKNOWN"
	msg := sprintf("%s: %s (UNKNOWN) in %s %s: listed, does not block (research RS-23)", [
		finding.image, finding.id, finding.package, finding.installed,
	])
}

warn contains msg if {
	some finding in findings
	blocks(finding.severity)
	entry := covering(finding)
	msg := sprintf("%s: %s (%s) covered by an exception until %s (%s)", [
		finding.image, finding.id, finding.severity, entry.expires, entry.path,
	])
}

warn contains msg if {
	some [path, index, reason] in scan_exceptions.problems
	msg := sprintf("%s: %s; not taken into account", [scan_exceptions.entry_name(path, index), reason])
}

warn contains msg if {
	some entry in scan_exceptions.valid_entries
	not matched(entry)
	msg := sprintf("%s: exception for %s on %s matches no finding of the scanned images", [entry.path, entry.vulnerability, entry.image])
}

matched(entry) if {
	some finding in findings
	finding.image == entry.image
	finding.id == entry.vulnerability
}

warn contains msg if {
	some file in reports
	image := repository(file.contents.ArtifactName)
	counts := [n |
		some level in ["CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN"]
		n := count({finding | some finding in findings; finding.image == image; finding.severity == level})
	]
	blocked := count({finding | some finding in refused; finding.image == image})
	msg := sprintf("%s: %d CRITICAL, %d HIGH, %d MEDIUM, %d LOW, %d UNKNOWN; %d at or above %s without a valid exception", [
		image, counts[0], counts[1], counts[2], counts[3], counts[4], blocked, threshold,
	])
}
