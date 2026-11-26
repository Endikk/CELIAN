# Tests of U03 (scan_decision.rego), run by `conftest verify` from
# tests/unit/u03-scan-decision.sh, at a fixed date. The rules are read
# through data.scan_decision, so that these tests compile before the policy
# exists (red first). Reports follow the JSON of Trivy 0.76.2 (research
# RS-23); identifiers in CVE-2099 are examples, not real advisories.
package scan_decision

fixed_today := "2026-12-01"

# The platform that the run is for (data.scan_platform): the example reports
# are those of the arm64 variant.
fixed_platform := "linux/arm64"

fixed_policy := {
	"severity_threshold": "HIGH",
	"max_exception_days": 90,
	"image_classes": {
		"blocking": ["saas-b2b.invalid"],
		"reported": ["docker.io/example/local-tool"],
	},
}

example_app := "docker.io/example/app:1.0@sha256:1111111111111111111111111111111111111111111111111111111111111111"

example_vulnerability(id, severity) := {
	"VulnerabilityID": id,
	"PkgName": "libexample",
	"InstalledVersion": "1.0-1",
	"FixedVersion": "1.0-2",
	"Severity": severity,
}

example_metadata(architecture) := {
	"OS": {"Family": "debian", "Name": "13.7"},
	"ImageConfig": {"architecture": architecture, "os": "linux"},
}

example_report(name, vulnerabilities) := {
	"path": "reports/1.json",
	"contents": {
		"SchemaVersion": 2,
		"ArtifactName": name,
		"ArtifactType": "container_image",
		"Metadata": example_metadata("arm64"),
		"Results": [{
			"Target": "docker.io/example/app:1.0 (debian 13.7)",
			"Class": "os-pkgs",
			"Type": "debian",
			"Vulnerabilities": vulnerabilities,
		}],
	},
}

example_entry := {
	"vulnerability": "CVE-2099-0001",
	"image": "docker.io/example/app",
	"justification": "Reached only from inside the cluster; no fixed release yet.",
	"written": "2026-11-25",
	"expires": "2027-02-20",
}

example_exceptions(entries) := {"path": "local/security/scan-exceptions.yaml", "contents": {"exceptions": entries}}

example_high := example_report(example_app, [example_vulnerability("CVE-2099-0001", "HIGH")])

denials(files) := msgs if {
	msgs := data.scan_decision.deny with input as files
		with data.scan_policy as fixed_policy
		with data.scan_today as fixed_today
		with data.scan_platform as fixed_platform
}

warnings(files) := msgs if {
	msgs := data.scan_decision.warn with input as files
		with data.scan_policy as fixed_policy
		with data.scan_today as fixed_today
		with data.scan_platform as fixed_platform
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
	denied_with([example_high, example_exceptions([])], "docker.io/example/app: CVE-2099-0001 (HIGH)")
}

test_u03_names_the_label_the_package_and_the_fix if {
	denied_with([example_high, example_exceptions([])], "E27 (FR-021, FR-022")
	denied_with([example_high, example_exceptions([])], "in libexample 1.0-1, fixed in 1.0-2")
}

test_u03_says_when_no_fix_exists if {
	finding := object.union(example_vulnerability("CVE-2099-0001", "HIGH"), {"FixedVersion": ""})
	denied_with([example_report(example_app, [finding]), example_exceptions([])], "no fixed version")
}

test_u03_refuses_a_critical_finding if {
	denied_with([example_report(example_app, [example_vulnerability("CVE-2099-0005", "CRITICAL")]), example_exceptions([])], "CVE-2099-0005 (CRITICAL)")
}

# Scenario 4: a complete exception within its dates lets it pass.
test_u03_passes_with_a_complete_exception_within_its_dates if {
	passes([example_high, example_exceptions([example_entry])])
}

test_u03_lists_the_finding_that_an_exception_covers if {
	warned_with([example_high, example_exceptions([example_entry])], "CVE-2099-0001 (HIGH) covered by an exception until 2027-02-20")
}

test_u03_passes_on_the_last_day_of_the_exception if {
	passes([example_high, example_exceptions([object.union(example_entry, {"expires": "2026-12-01"})])])
}

test_u03_reads_exceptions_from_several_files if {
	files := [
		example_high,
		{"path": "security/scan-exceptions.yaml", "contents": {"exceptions": []}},
		example_exceptions([example_entry]),
	]
	passes(files)
}

# Scenario 5: expired, incomplete or aimed at another image, refused again.
test_u03_refuses_with_an_expired_exception if {
	entry := object.union(example_entry, {"written": "2026-09-01", "expires": "2026-11-30"})
	denied_with([example_high, example_exceptions([entry])], "CVE-2099-0001 (HIGH)")
	warned_with([example_high, example_exceptions([entry])], "expired on 2026-11-30; not taken into account")
}

test_u03_refuses_with_an_incomplete_exception if {
	entry := object.remove(example_entry, ["justification"])
	denied_with([example_high, example_exceptions([entry])], "CVE-2099-0001 (HIGH)")
	warned_with([example_high, example_exceptions([entry])], "no justification; not taken into account")
}

test_u03_refuses_with_an_exception_for_another_image if {
	entry := object.union(example_entry, {"image": "docker.io/example/other"})
	denied_with([example_high, example_exceptions([entry])], "CVE-2099-0001 (HIGH)")
	warned_with([example_high, example_exceptions([entry])], "matches no finding of the scanned images")
}

test_u03_refuses_with_an_exception_for_another_vulnerability if {
	entry := object.union(example_entry, {"vulnerability": "CVE-2099-0009"})
	denied_with([example_high, example_exceptions([entry])], "CVE-2099-0001 (HIGH)")
}

test_u03_refuses_with_an_exception_written_in_the_future if {
	entry := object.union(example_entry, {"written": "2026-12-02", "expires": "2027-01-10"})
	denied_with([example_high, example_exceptions([entry])], "CVE-2099-0001 (HIGH)")
}

test_u03_refuses_with_an_exception_longer_than_the_maximum if {
	entry := object.union(example_entry, {"expires": "2027-02-24"})
	denied_with([example_high, example_exceptions([entry])], "CVE-2099-0001 (HIGH)")
}

test_u03_refuses_with_an_exception_that_names_the_image_with_its_tag if {
	entry := object.union(example_entry, {"image": "docker.io/example/app:1.0"})
	denied_with([example_high, example_exceptions([entry])], "CVE-2099-0001 (HIGH)")
}

# Below the threshold: passes.
test_u03_passes_a_finding_below_the_threshold if {
	passes([example_report(example_app, [example_vulnerability("CVE-2099-0002", "MEDIUM")]), example_exceptions([])])
}

test_u03_follows_a_lower_threshold if {
	files := [example_report(example_app, [example_vulnerability("CVE-2099-0002", "MEDIUM")]), example_exceptions([])]
	msgs := data.scan_decision.deny with input as files
		with data.scan_policy as {"severity_threshold": "MEDIUM", "max_exception_days": 90}
		with data.scan_today as fixed_today
	some msg in msgs
	contains(msg, "CVE-2099-0002 (MEDIUM)")
}

# UNKNOWN: listed, never blocking (research RS-23, to be confirmed by SECU).
test_u03_lists_an_unknown_finding_without_blocking if {
	files := [example_report(example_app, [example_vulnerability("CVE-2099-0003", "UNKNOWN")]), example_exceptions([])]
	passes(files)
	warned_with(files, "CVE-2099-0003 (UNKNOWN) in libexample 1.0-1: listed, does not block")
}

test_u03_reads_a_missing_severity_as_unknown if {
	files := [example_report(example_app, [object.remove(example_vulnerability("CVE-2099-0004", "HIGH"), ["Severity"])]), example_exceptions([])]
	passes(files)
	warned_with(files, "CVE-2099-0004 (UNKNOWN)")
}

test_u03_refuses_a_severity_it_cannot_rank if {
	denied_with([example_report(example_app, [example_vulnerability("CVE-2099-0006", "SEVERE")]), example_exceptions([])], "CVE-2099-0006 (SEVERE)")
}

test_u03_counts_the_findings_of_each_image if {
	findings := [
		example_vulnerability("CVE-2099-0001", "HIGH"),
		example_vulnerability("CVE-2099-0002", "MEDIUM"),
		example_vulnerability("CVE-2099-0003", "UNKNOWN"),
	]
	warned_with([example_report(example_app, findings), example_exceptions([])], "docker.io/example/app: 0 CRITICAL, 1 HIGH, 1 MEDIUM, 0 LOW, 1 UNKNOWN; 1 at or above HIGH without a valid exception")
}

test_u03_passes_an_image_without_findings if {
	passes([example_report(example_app, []), example_exceptions([])])
}

test_u03_passes_a_report_without_results_when_it_names_the_os if {
	clean := {"path": "reports/1.json", "contents": {
		"SchemaVersion": 2,
		"ArtifactName": example_app,
		"ArtifactType": "container_image",
		"Metadata": example_metadata("arm64"),
	}}
	passes([clean, example_exceptions([])])
}

# The image of an exception is the repository of the scanned reference.
test_u03_matches_a_registry_with_a_port if {
	name := "registry.example.com:5000/team/app:2.0@sha256:2222222222222222222222222222222222222222222222222222222222222222"
	entry := object.union(example_entry, {"image": "registry.example.com:5000/team/app"})
	passes([example_report(name, [example_vulnerability("CVE-2099-0001", "HIGH")]), example_exceptions([entry])])
}

test_u03_matches_a_reference_without_tag if {
	name := "docker.io/example/app@sha256:1111111111111111111111111111111111111111111111111111111111111111"
	passes([example_report(name, [example_vulnerability("CVE-2099-0001", "HIGH")]), example_exceptions([example_entry])])
}

# Refusals that keep the scan from passing in silence.
test_u03_refuses_an_input_without_report if {
	denied_with([example_exceptions([])], "no Trivy report")
}

test_u03_refuses_another_schema_version if {
	old := {"path": "reports/1.json", "contents": {"SchemaVersion": 1, "ArtifactName": example_app, "ArtifactType": "container_image"}}
	denied_with([old, example_exceptions([])], "SchemaVersion 1, 2 expected")
}

test_u03_refuses_a_report_that_is_not_an_image if {
	other := {"path": "reports/1.json", "contents": {"SchemaVersion": 2, "ArtifactName": ".", "ArtifactType": "filesystem"}}
	denied_with([other, example_exceptions([])], "ArtifactType filesystem, container_image expected")
}

test_u03_refuses_a_missing_threshold if {
	msgs := data.scan_decision.deny with input as [example_high, example_exceptions([])]
		with data.scan_policy as {"max_exception_days": 90}
		with data.scan_today as fixed_today
	some msg in msgs
	contains(msg, "no valid severity_threshold")
}

test_u03_refuses_unknown_as_threshold if {
	msgs := data.scan_decision.deny with input as [example_high, example_exceptions([])]
		with data.scan_policy as {"severity_threshold": "UNKNOWN", "max_exception_days": 90}
		with data.scan_today as fixed_today
	some msg in msgs
	contains(msg, "no valid severity_threshold")
}

test_u03_refuses_a_missing_date_of_the_day if {
	msgs := data.scan_decision.deny with input as [example_high, example_exceptions([example_entry])]
		with data.scan_policy as fixed_policy
		with data.scan_today as null
	some msg in msgs
	contains(msg, "no date of the day (data.scan_today)")
}

# Decision of the DSI of 2026-11-25 (FR-021, FR-022): the scan blocks what
# goes to production, and reports the third-party images that run on the
# local cluster only. An image that no class holds blocks (closed on failure).
local_tool := "docker.io/example/local-tool:3.1@sha256:3333333333333333333333333333333333333333333333333333333333333333"

built_api := "saas-b2b.invalid/api:local"

test_u03_reported_image_with_a_high_finding_passes if {
	files := [example_report(local_tool, [example_vulnerability("CVE-2099-0001", "HIGH")]), example_exceptions([])]
	passes(files)
}

test_u03_reported_image_with_a_critical_finding_passes if {
	files := [example_report(local_tool, [example_vulnerability("CVE-2099-0005", "CRITICAL")]), example_exceptions([])]
	passes(files)
}

test_u03_built_image_with_a_high_finding_is_refused if {
	files := [example_report(built_api, [example_vulnerability("CVE-2099-0001", "HIGH")]), example_exceptions([])]
	denied_with(files, "saas-b2b.invalid/api: CVE-2099-0001 (HIGH)")
	denied_with(files, "class blocking")
}

test_u03_unclassified_image_is_refused_by_default if {
	files := [example_report(example_app, [example_vulnerability("CVE-2099-0001", "HIGH")]), example_exceptions([])]
	denied_with(files, "unclassified image, blocking by default")
}

test_u03_refuses_every_image_when_the_policy_has_no_classes if {
	files := [example_report(local_tool, [example_vulnerability("CVE-2099-0001", "HIGH")]), example_exceptions([])]
	msgs := data.scan_decision.deny with input as files
		with data.scan_policy as {"severity_threshold": "HIGH", "max_exception_days": 90}
		with data.scan_today as fixed_today
	some msg in msgs
	contains(msg, "unclassified image, blocking by default")
}

test_u03_a_reported_entry_does_not_cover_a_longer_repository if {
	name := "docker.io/example/local-tool-extra:1.0@sha256:4444444444444444444444444444444444444444444444444444444444444444"
	files := [example_report(name, [example_vulnerability("CVE-2099-0001", "HIGH")]), example_exceptions([])]
	denied_with(files, "docker.io/example/local-tool-extra: CVE-2099-0001 (HIGH)")
}

test_u03_a_blocking_entry_covers_what_sits_under_it if {
	name := "saas-b2b.invalid/web:local"
	files := [example_report(name, [example_vulnerability("CVE-2099-0001", "HIGH")]), example_exceptions([])]
	denied_with(files, "class blocking")
}

test_u03_blocking_wins_when_an_image_is_in_both_classes if {
	policy := {
		"severity_threshold": "HIGH",
		"max_exception_days": 90,
		"image_classes": {
			"blocking": ["docker.io/example/local-tool"],
			"reported": ["docker.io/example/local-tool"],
		},
	}
	files := [example_report(local_tool, [example_vulnerability("CVE-2099-0001", "HIGH")]), example_exceptions([])]
	msgs := data.scan_decision.deny with input as files
		with data.scan_policy as policy
		with data.scan_today as fixed_today
	some msg in msgs
	contains(msg, "class blocking")
}

test_u03_a_valid_exception_still_lets_a_blocking_image_pass if {
	entry := object.union(example_entry, {"image": "saas-b2b.invalid/api"})
	files := [example_report(built_api, [example_vulnerability("CVE-2099-0001", "HIGH")]), example_exceptions([entry])]
	passes(files)
}

# The summary of a reported image: distinct identifiers at or above the
# threshold, by level, and how many carry a fixed version in every row.
test_u03_summarises_a_reported_image if {
	findings := [
		example_vulnerability("CVE-2099-0001", "HIGH"),
		object.union(example_vulnerability("CVE-2099-0002", "HIGH"), {"FixedVersion": ""}),
		example_vulnerability("CVE-2099-0005", "CRITICAL"),
		example_vulnerability("CVE-2099-0006", "MEDIUM"),
	]
	files := [example_report(local_tool, findings), example_exceptions([])]
	warned_with(files, "reported: docker.io/example/local-tool: 1 CRITICAL, 2 HIGH, 3 distinct at or above HIGH, 2 with a fixed version; does not block (class reported)")
}

test_u03_counts_an_identifier_once_across_targets if {
	report := {"path": "reports/1.json", "contents": {
		"SchemaVersion": 2,
		"ArtifactName": local_tool,
		"ArtifactType": "container_image",
		"Results": [
			{"Target": "a", "Vulnerabilities": [example_vulnerability("CVE-2099-0001", "HIGH")]},
			{"Target": "b", "Vulnerabilities": [example_vulnerability("CVE-2099-0001", "HIGH")]},
		],
	}}
	warned_with([report, example_exceptions([])], "0 CRITICAL, 1 HIGH, 1 distinct at or above HIGH, 1 with a fixed version")
}

test_u03_one_identifier_without_a_fix_in_one_target_is_not_fixed if {
	report := {"path": "reports/1.json", "contents": {
		"SchemaVersion": 2,
		"ArtifactName": local_tool,
		"ArtifactType": "container_image",
		"Results": [
			{"Target": "a", "Vulnerabilities": [example_vulnerability("CVE-2099-0001", "HIGH")]},
			{"Target": "c", "Vulnerabilities": [object.union(example_vulnerability("CVE-2099-0001", "HIGH"), {"FixedVersion": ""})]},
		],
	}}
	warned_with([report, example_exceptions([])], "0 CRITICAL, 1 HIGH, 1 distinct at or above HIGH, 0 with a fixed version")
}

test_u03_summarises_a_reported_image_without_findings if {
	warned_with([example_report(local_tool, []), example_exceptions([])], "reported: docker.io/example/local-tool: 0 CRITICAL, 0 HIGH, 0 distinct at or above HIGH, 0 with a fixed version")
}

test_u03_keeps_the_summary_to_reported_images if {
	files := [example_report(example_app, [example_vulnerability("CVE-2099-0001", "HIGH")]), example_exceptions([])]
	not warned_with(files, "reported: ")
}

test_u03_a_reported_image_has_no_blocked_count if {
	files := [example_report(local_tool, [example_vulnerability("CVE-2099-0001", "HIGH")]), example_exceptions([])]
	not warned_with(files, "without a valid exception")
}

# Second PR of step 18, gap 65: a report that says nothing of the image does
# not pass for an image that blocks. Trivy writes neither Results nor
# Metadata.OS for an image it could not read, and the policy would count
# nothing and pass.
empty_report(name) := {"path": "reports/1.json", "contents": {
	"SchemaVersion": 2,
	"ArtifactName": name,
	"ArtifactType": "container_image",
	"Metadata": {"ImageConfig": {"architecture": "arm64", "os": "linux"}},
}}

test_u03_refuses_an_empty_report_of_a_built_image if {
	files := [empty_report(built_api), example_exceptions([])]
	denied_with(files, "saas-b2b.invalid/api")
	denied_with(files, "the report holds no Results and no Metadata.OS")
}

test_u03_refuses_an_empty_report_of_an_unclassified_image if {
	denied_with([empty_report(example_app), example_exceptions([])], "the report holds no Results and no Metadata.OS")
}

test_u03_refuses_a_report_with_an_empty_list_of_results_and_no_os if {
	report := {"path": "reports/1.json", "contents": object.union(empty_report(built_api).contents, {"Results": []})}
	denied_with([report, example_exceptions([])], "the report holds no Results and no Metadata.OS")
}

test_u03_passes_a_report_with_results_and_no_os if {
	report := {"path": "reports/1.json", "contents": object.union(empty_report(built_api).contents, {"Results": [{"Target": "app/Api.deps.json", "Class": "lang-pkgs"}]})}
	passes([report, example_exceptions([])])
}

test_u03_does_not_judge_the_content_of_the_report_of_a_reported_image if {
	files := [empty_report(local_tool), example_exceptions([])]
	passes(files)
}

# The platform of the run (data.scan_platform): the report of an image that
# blocks must be of that variant, so that the arm64 scan cannot pass on an
# amd64 report, nor the reverse.
test_u03_refuses_a_built_image_scanned_for_another_platform if {
	report := {"path": "reports/1.json", "contents": object.union(example_report(built_api, []).contents, {"Metadata": example_metadata("amd64")})}
	files := [report, example_exceptions([])]
	denied_with(files, "saas-b2b.invalid/api: scanned for linux/amd64, linux/arm64 expected")
}

test_u03_refuses_a_report_that_names_no_platform if {
	contents := object.remove(example_report(built_api, []).contents, ["Metadata"])
	report := {"path": "reports/1.json", "contents": object.union(contents, {"Metadata": {"OS": {"Family": "debian", "Name": "13.7"}}})}
	denied_with([report, example_exceptions([])], "saas-b2b.invalid/api: scanned for no platform, linux/arm64 expected")
}

test_u03_accepts_the_amd64_report_in_a_run_for_amd64 if {
	report := {"path": "reports/1.json", "contents": object.union(example_report(built_api, []).contents, {"Metadata": example_metadata("amd64")})}
	msgs := data.scan_decision.deny with input as [report, example_exceptions([])]
		with data.scan_policy as fixed_policy
		with data.scan_today as fixed_today
		with data.scan_platform as "linux/amd64"
	count(msgs) == 0
}

test_u03_does_not_check_the_platform_of_a_reported_image if {
	report := {"path": "reports/1.json", "contents": object.union(example_report(local_tool, []).contents, {"Metadata": example_metadata("amd64")})}
	passes([report, example_exceptions([])])
}

test_u03_refuses_a_run_without_a_platform if {
	msgs := data.scan_decision.deny with input as [example_report(built_api, []), example_exceptions([])]
		with data.scan_policy as fixed_policy
		with data.scan_today as fixed_today
	some msg in msgs
	contains(msg, "no platform of the run (data.scan_platform)")
}

test_u03_refuses_a_platform_that_is_not_os_slash_architecture if {
	msgs := data.scan_decision.deny with input as [example_report(built_api, []), example_exceptions([])]
		with data.scan_policy as fixed_policy
		with data.scan_today as fixed_today
		with data.scan_platform as "arm64"
	some msg in msgs
	contains(msg, "no platform of the run (data.scan_platform)")
}
