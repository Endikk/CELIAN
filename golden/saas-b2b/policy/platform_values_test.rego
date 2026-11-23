# Tests of S21 (platform_values.rego), run by `conftest verify`.
package platform_values

valid_values := {"kubernetes_minor": "1.36", "postgres_major": "18"}

combined(path, contents) := [{"path": path, "contents": contents}]

accepted(files) if {
	msgs := deny with input as files
	count(msgs) == 0
}

denied_with(files, fragment) if {
	msgs := deny with input as files
	some msg in msgs
	contains(msg, fragment)
}

test_s21_accepts_both_values_as_strings if {
	accepted(combined("platform.yaml", valid_values))
}

test_s21_accepts_platform_yaml_under_a_folder if {
	accepted(combined("golden/saas-b2b/platform.yaml", valid_values))
}

test_s21_rejects_an_input_without_platform_yaml if {
	denied_with(combined("other.yaml", valid_values), "platform.yaml is missing")
}

test_s21_rejects_an_empty_input if {
	denied_with([], "platform.yaml is missing")
}

test_s21_does_not_take_a_similar_name_for_platform_yaml if {
	denied_with(combined("my-platform.yaml", valid_values), "platform.yaml is missing")
}

test_s21_rejects_two_platform_files if {
	files := [
		{"path": "platform.yaml", "contents": valid_values},
		{"path": "local/platform.yaml", "contents": valid_values},
	]
	denied_with(files, "2 files named platform.yaml")
}

test_s21_rejects_a_file_that_is_not_a_mapping if {
	denied_with(combined("platform.yaml", ["1.36", "18"]), "must be a mapping")
}

test_s21_rejects_a_missing_kubernetes_minor if {
	denied_with(combined("platform.yaml", {"postgres_major": "18"}), "has no kubernetes_minor key")
}

test_s21_rejects_a_missing_postgres_major if {
	denied_with(combined("platform.yaml", {"kubernetes_minor": "1.36"}), "has no postgres_major key")
}

test_s21_rejects_an_empty_value if {
	denied_with(combined("platform.yaml", {"kubernetes_minor": null, "postgres_major": "18"}), "has no kubernetes_minor key")
}

test_s21_rejects_a_minor_read_as_a_number if {
	denied_with(combined("platform.yaml", {"kubernetes_minor": 1.36, "postgres_major": "18"}), "kubernetes_minor in platform.yaml must be a quoted string")
}

test_s21_rejects_a_major_read_as_a_number if {
	denied_with(combined("platform.yaml", {"kubernetes_minor": "1.36", "postgres_major": 18}), "postgres_major in platform.yaml must be a quoted string")
}

test_s21_rejects_a_minor_with_a_patch_number if {
	denied_with(combined("platform.yaml", {"kubernetes_minor": "1.36.4", "postgres_major": "18"}), "kubernetes_minor in platform.yaml is '1.36.4'")
}

test_s21_rejects_a_minor_with_a_prefix if {
	denied_with(combined("platform.yaml", {"kubernetes_minor": "v1.36", "postgres_major": "18"}), "kubernetes_minor in platform.yaml is 'v1.36'")
}

test_s21_rejects_a_major_with_a_minor if {
	denied_with(combined("platform.yaml", {"kubernetes_minor": "1.36", "postgres_major": "18.7"}), "postgres_major in platform.yaml is '18.7'")
}

test_s21_names_its_requirements_in_each_message if {
	files := combined("platform.yaml", {"kubernetes_minor": 1.36})
	msgs := deny with input as files
	count(msgs) == 2
	every msg in msgs {
		startswith(msg, "S21 (FR-010, FR-017;")
	}
}
