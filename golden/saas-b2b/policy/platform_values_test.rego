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

# The kind configuration of the local layer (T041).

node_image(tag) := sprintf("kindest/node:%s@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed", [tag])

with_kind(images) := [
	{"path": "platform.yaml", "contents": valid_values},
	{"path": "local/kind/cluster.yaml", "contents": {"nodes": [{"role": "control-plane", "image": image} | some image in images]}},
]

test_s21_accepts_a_node_image_on_the_platform_minor if {
	accepted(with_kind([node_image("v1.36.4")]))
}

test_s21_accepts_two_nodes_on_the_platform_minor if {
	accepted(with_kind([node_image("v1.36.4"), node_image("v1.36.5")]))
}

test_s21_rejects_a_node_image_on_another_minor if {
	denied_with(with_kind([node_image("v1.37.0")]), "nodes[0].image in local/kind/cluster.yaml runs Kubernetes 1.37, platform.yaml says kubernetes_minor 1.36")
}

test_s21_rejects_the_second_node_on_another_minor if {
	denied_with(with_kind([node_image("v1.36.4"), node_image("v1.35.8")]), "nodes[1].image")
}

test_s21_rejects_a_node_image_without_a_version_tag if {
	denied_with(with_kind(["kindest/node:latest"]), "has no vX.Y.Z tag to compare with kubernetes_minor")
}

test_s21_rejects_a_node_without_image if {
	files := [
		{"path": "platform.yaml", "contents": valid_values},
		{"path": "local/kind/cluster.yaml", "contents": {"nodes": [{"role": "control-plane"}]}},
	]
	denied_with(files, "has no vX.Y.Z tag to compare with kubernetes_minor, found null")
}

test_s21_does_not_take_a_minor_prefix_for_the_minor if {
	denied_with(with_kind([node_image("v1.361.0")]), "runs Kubernetes 1.361")
}
