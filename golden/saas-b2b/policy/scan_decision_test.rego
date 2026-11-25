# Tests of U03 (scan_decision.rego), run by `conftest verify` from
# tests/unit/u03-scan-decision.sh, at a fixed date. The rules are read
# through data.scan_decision, so that these tests compile before the policy
# exists (red first). Reports follow the JSON of Trivy 0.76.2 (research
# RS-23); identifiers in CVE-2099 are examples, not real advisories.
package scan_decision

today := "2026-12-01"

policy := {"severity_threshold": "HIGH", "max_exception_days": 90}

app := "docker.io/example/app:1.0@sha256:1111111111111111111111111111111111111111111111111111111111111111"

vulnerability(id, severity) := {
	"VulnerabilityID": id,
	"PkgName": "libexample",
	"InstalledVersion": "1.0-1",
	"FixedVersion": "1.0-2",
	"Severity": severity,
}

report(name, vulnerabilities) := {
	"path": "reports/1.json",
	"contents": {
		"SchemaVersion": 2,
		"ArtifactName": name,
		"ArtifactType": "container_image",
		"Results": [{
			"Target": "docker.io/example/app:1.0 (debian 13.7)",
			"Class": "os-pkgs",
			"Type": "debian",
			"Vulnerabilities": vulnerabilities,
		}],
	},
}

valid_entry := {
	"vulnerability": "CVE-2099-0001",
	"image": "docker.io/example/app",
	"justification": "Reached only from inside the cluster; no fixed release yet.",
	"written": "2026-11-25",
	"expires": "2027-02-20",
}

exceptions(entries) := {"path": "local/security/scan-exceptions.yaml", "contents": {"exceptions": entries}}

high_finding := report(app, [vulnerability("CVE-2099-0001", "HIGH")])

denials(files) := msgs if {
	msgs := data.scan_decision.deny with input as files
		with data.scan_policy as policy
		with data.scan_today as today
}

warnings(files) := msgs if {
	msgs := data.scan_decision.warn with input as files
		with data.scan_policy as policy
		with data.scan_today as today
}

passes(files) if {
	count(denials(files)) == 0
}

denied_with(files, fragment) if {
	some msg in denials(files)
	contains(msg, fragment)
}

warned_with(files, fragment) if {
	some msg in warnings(files)
	contains(msg, fragment)
}

# Story 7, scenario 3: refused, naming the image and the vulnerability.
test_u03_refuses_a_finding_at_the_threshold_without_exception if {
	denied_with([high_finding, exceptions([])], "docker.io/example/app: CVE-2099-0001 (HIGH)")
}

test_u03_names_the_label_the_package_and_the_fix if {
	denied_with([high_finding, exceptions([])], "E27 (FR-021, FR-022")
	denied_with([high_finding, exceptions([])], "in libexample 1.0-1, fixed in 1.0-2")
}

test_u03_says_when_no_fix_exists if {
	finding := object.union(vulnerability("CVE-2099-0001", "HIGH"), {"FixedVersion": ""})
	denied_with([report(app, [finding]), exceptions([])], "no fixed version")
}

test_u03_refuses_a_critical_finding if {
	denied_with([report(app, [vulnerability("CVE-2099-0005", "CRITICAL")]), exceptions([])], "CVE-2099-0005 (CRITICAL)")
}

# Scenario 4: a complete exception within its dates lets it pass.
test_u03_passes_with_a_complete_exception_within_its_dates if {
	passes([high_finding, exceptions([valid_entry])])
}

test_u03_lists_the_finding_that_an_exception_covers if {
	warned_with([high_finding, exceptions([valid_entry])], "CVE-2099-0001 (HIGH) covered by an exception until 2027-02-20")
}

test_u03_passes_on_the_last_day_of_the_exception if {
	passes([high_finding, exceptions([object.union(valid_entry, {"expires": "2026-12-01"})])])
}

test_u03_reads_exceptions_from_several_files if {
	files := [
		high_finding,
		{"path": "security/scan-exceptions.yaml", "contents": {"exceptions": []}},
		exceptions([valid_entry]),
	]
	passes(files)
}

# Scenario 5: expired, incomplete or aimed at another image, refused again.
test_u03_refuses_with_an_expired_exception if {
	entry := object.union(valid_entry, {"written": "2026-09-01", "expires": "2026-11-30"})
	denied_with([high_finding, exceptions([entry])], "CVE-2099-0001 (HIGH)")
	warned_with([high_finding, exceptions([entry])], "expired on 2026-11-30; not taken into account")
}

test_u03_refuses_with_an_incomplete_exception if {
	entry := object.remove(valid_entry, ["justification"])
	denied_with([high_finding, exceptions([entry])], "CVE-2099-0001 (HIGH)")
	warned_with([high_finding, exceptions([entry])], "no justification; not taken into account")
}

test_u03_refuses_with_an_exception_for_another_image if {
	entry := object.union(valid_entry, {"image": "docker.io/example/other"})
	denied_with([high_finding, exceptions([entry])], "CVE-2099-0001 (HIGH)")
	warned_with([high_finding, exceptions([entry])], "matches no finding of the scanned images")
}

test_u03_refuses_with_an_exception_for_another_vulnerability if {
	entry := object.union(valid_entry, {"vulnerability": "CVE-2099-0009"})
	denied_with([high_finding, exceptions([entry])], "CVE-2099-0001 (HIGH)")
}

test_u03_refuses_with_an_exception_written_in_the_future if {
	entry := object.union(valid_entry, {"written": "2026-12-02", "expires": "2027-01-10"})
	denied_with([high_finding, exceptions([entry])], "CVE-2099-0001 (HIGH)")
}

test_u03_refuses_with_an_exception_longer_than_the_maximum if {
	entry := object.union(valid_entry, {"expires": "2027-02-24"})
	denied_with([high_finding, exceptions([entry])], "CVE-2099-0001 (HIGH)")
}

test_u03_refuses_with_an_exception_that_names_the_image_with_its_tag if {
	entry := object.union(valid_entry, {"image": "docker.io/example/app:1.0"})
	denied_with([high_finding, exceptions([entry])], "CVE-2099-0001 (HIGH)")
}

# Below the threshold: passes.
test_u03_passes_a_finding_below_the_threshold if {
	passes([report(app, [vulnerability("CVE-2099-0002", "MEDIUM")]), exceptions([])])
}

test_u03_follows_a_lower_threshold if {
	files := [report(app, [vulnerability("CVE-2099-0002", "MEDIUM")]), exceptions([])]
	msgs := data.scan_decision.deny with input as files
		with data.scan_policy as {"severity_threshold": "MEDIUM", "max_exception_days": 90}
		with data.scan_today as today
	some msg in msgs
	contains(msg, "CVE-2099-0002 (MEDIUM)")
}

# UNKNOWN: listed, never blocking (research RS-23, to be confirmed by SECU).
test_u03_lists_an_unknown_finding_without_blocking if {
	files := [report(app, [vulnerability("CVE-2099-0003", "UNKNOWN")]), exceptions([])]
	passes(files)
	warned_with(files, "CVE-2099-0003 (UNKNOWN) in libexample 1.0-1: listed, does not block")
}

test_u03_reads_a_missing_severity_as_unknown if {
	files := [report(app, [object.remove(vulnerability("CVE-2099-0004", "HIGH"), ["Severity"])]), exceptions([])]
	passes(files)
	warned_with(files, "CVE-2099-0004 (UNKNOWN)")
}

test_u03_refuses_a_severity_it_cannot_rank if {
	denied_with([report(app, [vulnerability("CVE-2099-0006", "SEVERE")]), exceptions([])], "CVE-2099-0006 (SEVERE)")
}

test_u03_counts_the_findings_of_each_image if {
	findings := [
		vulnerability("CVE-2099-0001", "HIGH"),
		vulnerability("CVE-2099-0002", "MEDIUM"),
		vulnerability("CVE-2099-0003", "UNKNOWN"),
	]
	warned_with([report(app, findings), exceptions([])], "docker.io/example/app: 0 CRITICAL, 1 HIGH, 1 MEDIUM, 0 LOW, 1 UNKNOWN; 1 at or above HIGH without a valid exception")
}

test_u03_passes_an_image_without_findings if {
	passes([report(app, []), exceptions([])])
}

test_u03_passes_a_report_without_results if {
	clean := {"path": "reports/1.json", "contents": {"SchemaVersion": 2, "ArtifactName": app, "ArtifactType": "container_image"}}
	passes([clean, exceptions([])])
}

# The image of an exception is the repository of the scanned reference.
test_u03_matches_a_registry_with_a_port if {
	name := "registry.example.com:5000/team/app:2.0@sha256:2222222222222222222222222222222222222222222222222222222222222222"
	entry := object.union(valid_entry, {"image": "registry.example.com:5000/team/app"})
	passes([report(name, [vulnerability("CVE-2099-0001", "HIGH")]), exceptions([entry])])
}

test_u03_matches_a_reference_without_tag if {
	name := "docker.io/example/app@sha256:1111111111111111111111111111111111111111111111111111111111111111"
	passes([report(name, [vulnerability("CVE-2099-0001", "HIGH")]), exceptions([valid_entry])])
}

# Refusals that keep the scan from passing in silence.
test_u03_refuses_an_input_without_report if {
	denied_with([exceptions([])], "no Trivy report")
}

test_u03_refuses_another_schema_version if {
	old := {"path": "reports/1.json", "contents": {"SchemaVersion": 1, "ArtifactName": app, "ArtifactType": "container_image"}}
	denied_with([old, exceptions([])], "SchemaVersion 1, 2 expected")
}

test_u03_refuses_a_report_that_is_not_an_image if {
	other := {"path": "reports/1.json", "contents": {"SchemaVersion": 2, "ArtifactName": ".", "ArtifactType": "filesystem"}}
	denied_with([other, exceptions([])], "ArtifactType filesystem, container_image expected")
}

test_u03_refuses_a_missing_threshold if {
	msgs := data.scan_decision.deny with input as [high_finding, exceptions([])]
		with data.scan_policy as {"max_exception_days": 90}
		with data.scan_today as today
	some msg in msgs
	contains(msg, "no valid severity_threshold")
}

test_u03_refuses_unknown_as_threshold if {
	msgs := data.scan_decision.deny with input as [high_finding, exceptions([])]
		with data.scan_policy as {"severity_threshold": "UNKNOWN", "max_exception_days": 90}
		with data.scan_today as today
	some msg in msgs
	contains(msg, "no valid severity_threshold")
}

test_u03_refuses_a_missing_date_of_the_day if {
	msgs := data.scan_decision.deny with input as [high_finding, exceptions([valid_entry])]
		with data.scan_policy as policy
		with data.scan_today as null
	some msg in msgs
	contains(msg, "no date of the day (data.scan_today)")
}
