# Tests of S27 (scan_exceptions.rego), run by `conftest verify`. The rules
# are read through data.scan_exceptions, so that these tests compile before
# the policy exists (red first, plan "Étapes livrables").
package scan_exceptions

today := "2026-12-01"

policy := {"severity_threshold": "HIGH", "max_exception_days": 90}

valid_entry := {
	"vulnerability": "CVE-2099-0001",
	"image": "docker.io/example/app",
	"justification": "Reached only from inside the cluster; no fixed release yet.",
	"written": "2026-11-25",
	"expires": "2027-02-20",
}

file_with(entries) := [{"path": "local/security/scan-exceptions.yaml", "contents": {"exceptions": entries}}]

denials(files) := msgs if {
	msgs := data.scan_exceptions.deny with input as files
		with data.scan_policy as policy
		with data.scan_today as today
}

accepted(files) if {
	count(denials(files)) == 0
}

denied_with(files, fragment) if {
	some msg in denials(files)
	contains(msg, fragment)
}

test_s27_accepts_a_complete_entry_within_its_dates if {
	accepted(file_with([valid_entry]))
}

test_s27_accepts_an_empty_list if {
	accepted(file_with([]))
}

test_s27_accepts_an_entry_on_its_last_day if {
	accepted(file_with([object.union(valid_entry, {"expires": "2026-12-01"})]))
}

test_s27_accepts_two_files if {
	files := [
		{"path": "security/scan-exceptions.yaml", "contents": {"exceptions": []}},
		{"path": "local/security/scan-exceptions.yaml", "contents": {"exceptions": [valid_entry]}},
	]
	accepted(files)
}

test_s27_names_the_label_the_file_and_the_entry if {
	denied_with(file_with([object.remove(valid_entry, ["justification"])]), "S27 (FR-022")
	denied_with(file_with([object.remove(valid_entry, ["justification"])]), "local/security/scan-exceptions.yaml: entry 1 (CVE-2099-0001 on docker.io/example/app)")
}

test_s27_rejects_an_entry_without_vulnerability if {
	denied_with(file_with([object.remove(valid_entry, ["vulnerability"])]), "no vulnerability")
}

test_s27_rejects_an_entry_without_image if {
	denied_with(file_with([object.remove(valid_entry, ["image"])]), "no image")
}

test_s27_rejects_an_entry_without_justification if {
	denied_with(file_with([object.remove(valid_entry, ["justification"])]), "no justification")
}

test_s27_rejects_a_blank_justification if {
	denied_with(file_with([object.union(valid_entry, {"justification": "   "})]), "no justification")
}

test_s27_rejects_an_entry_without_written_date if {
	denied_with(file_with([object.remove(valid_entry, ["written"])]), "no written")
}

test_s27_rejects_an_entry_without_expiry if {
	denied_with(file_with([object.remove(valid_entry, ["expires"])]), "no expires")
}

test_s27_rejects_a_field_that_is_not_a_string if {
	denied_with(file_with([object.union(valid_entry, {"vulnerability": 2099})]), "no vulnerability")
}

test_s27_rejects_an_image_with_a_digest if {
	entry := object.union(valid_entry, {"image": "docker.io/example/app@sha256:0000000000000000000000000000000000000000000000000000000000000000"})
	denied_with(file_with([entry]), "not a repository written in full")
}

test_s27_rejects_an_image_with_a_tag if {
	denied_with(file_with([object.union(valid_entry, {"image": "docker.io/example/app:1.0"})]), "not a repository written in full")
}

test_s27_rejects_an_image_without_registry if {
	denied_with(file_with([object.union(valid_entry, {"image": "example/app"})]), "not a repository written in full")
}

test_s27_accepts_a_registry_with_a_port if {
	accepted(file_with([object.union(valid_entry, {"image": "registry.example.com:5000/team/app"})]))
}

test_s27_rejects_a_vulnerability_with_a_blank_inside if {
	denied_with(file_with([object.union(valid_entry, {"vulnerability": "CVE 2099 0001"})]), "vulnerability is not an identifier")
}

test_s27_rejects_a_written_date_in_another_format if {
	denied_with(file_with([object.union(valid_entry, {"written": "25/11/2026"})]), "written is not a date YYYY-MM-DD")
}

test_s27_rejects_an_impossible_date if {
	denied_with(file_with([object.union(valid_entry, {"expires": "2027-02-30"})]), "expires is not a date YYYY-MM-DD")
}

test_s27_rejects_a_written_date_after_today if {
	entry := object.union(valid_entry, {"written": "2026-12-02", "expires": "2027-01-10"})
	denied_with(file_with([entry]), "written after today (2026-12-01)")
}

test_s27_rejects_an_expiry_on_the_written_date if {
	denied_with(file_with([object.union(valid_entry, {"expires": "2026-11-25"})]), "expires on or before written")
}

test_s27_rejects_an_expiry_before_the_written_date if {
	denied_with(file_with([object.union(valid_entry, {"expires": "2026-11-20"})]), "expires on or before written")
}

test_s27_rejects_an_expiry_beyond_the_maximum if {
	denied_with(file_with([object.union(valid_entry, {"expires": "2027-02-24"})]), "expires more than 90 days after written")
}

test_s27_accepts_an_expiry_on_the_maximum if {
	accepted(file_with([object.union(valid_entry, {"expires": "2027-02-23"})]))
}

test_s27_rejects_an_expired_entry if {
	entry := object.union(valid_entry, {"written": "2026-09-01", "expires": "2026-11-30"})
	denied_with(file_with([entry]), "expired on 2026-11-30")
}

test_s27_rejects_a_list_that_is_not_a_list if {
	files := [{"path": "security/scan-exceptions.yaml", "contents": {"exceptions": "none"}}]
	denied_with(files, "security/scan-exceptions.yaml: exceptions must be a list")
}

test_s27_rejects_an_entry_that_is_not_a_mapping if {
	denied_with(file_with(["CVE-2099-0001"]), "entry 1 is not a mapping")
}

test_s27_rejects_a_file_without_exceptions_key if {
	files := [{"path": "security/scan-exceptions.yaml", "contents": {"entries": []}}]
	denied_with(files, "security/scan-exceptions.yaml: no exceptions key")
}

test_s27_rejects_an_empty_input if {
	denied_with([], "no exception file")
}

test_s27_rejects_a_missing_date_of_the_day if {
	msgs := data.scan_exceptions.deny with input as file_with([valid_entry])
		with data.scan_policy as policy
		with data.scan_today as null
	some msg in msgs
	contains(msg, "no date of the day (data.scan_today)")
}

test_s27_rejects_a_missing_maximum if {
	msgs := data.scan_exceptions.deny with input as file_with([valid_entry])
		with data.scan_policy as {"severity_threshold": "HIGH"}
		with data.scan_today as today
	some msg in msgs
	contains(msg, "no max_exception_days")
}

test_s27_rejects_a_maximum_that_is_not_a_positive_integer if {
	msgs := data.scan_exceptions.deny with input as file_with([valid_entry])
		with data.scan_policy as {"severity_threshold": "HIGH", "max_exception_days": 0}
		with data.scan_today as today
	some msg in msgs
	contains(msg, "no max_exception_days")
}
