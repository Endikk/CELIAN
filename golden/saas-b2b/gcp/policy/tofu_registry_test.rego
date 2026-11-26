# Tests of S15 for the registry of the providers (tofu_registry.rego), run by
# `conftest verify`. Each case changes one thing in a valid root.
package tofu_registry

valid := {
	"terraform": [{"required_providers": [{
		"google": {"source": "registry.opentofu.org/hashicorp/google", "version": "8.12.0"},
		"random": {"source": "registry.opentofu.org/hashicorp/random", "version": "3.9.1"},
	}]}],
	"provider": {"google": [{"project": "${var.project_id}"}]},
}

files(contents) := [{"path": "gcp/tofu/versions.tf", "contents": contents}]

patched(ops) := files(json.patch(valid, ops))

set(path, value) := [{"op": "replace", "path": path, "value": value}]

drop(path) := [{"op": "remove", "path": path}]

accepted(input_files) if {
	msgs := deny with input as input_files
	count(msgs) == 0
}

denied_with(input_files, fragment) if {
	msgs := deny with input as input_files
	some msg in msgs
	contains(msg, fragment)
}

google_path := "/terraform/0/required_providers/0/google"

test_s15_registry_accepts_a_valid_root if {
	accepted(files(valid))
}

test_s15_registry_ignores_an_input_without_opentofu_file if {
	accepted([{"path": "platform.yaml", "contents": {"kubernetes_minor": "1.36"}}])
}

test_s15_registry_rejects_a_source_without_host if {
	denied_with(
		patched(set(concat("/", [google_path, "source"]), "hashicorp/google")),
		"required_providers.google has source 'hashicorp/google'",
	)
}

test_s15_registry_rejects_the_terraform_host if {
	denied_with(
		patched(set(concat("/", [google_path, "source"]), "registry.terraform.io/hashicorp/google")),
		"required_providers.google has source 'registry.terraform.io/hashicorp/google'",
	)
}

test_s15_registry_rejects_a_host_with_a_suffix if {
	denied_with(
		patched(set(concat("/", [google_path, "source"]), "registry.opentofu.org.example.com/hashicorp/google")),
		"has source 'registry.opentofu.org.example.com/hashicorp/google'",
	)
}

test_s15_registry_rejects_a_source_without_namespace if {
	denied_with(
		patched(set(concat("/", [google_path, "source"]), "registry.opentofu.org/google")),
		"has source 'registry.opentofu.org/google'",
	)
}

test_s15_registry_rejects_a_version_string if {
	denied_with(
		patched(set(google_path, ">= 8.0.0")),
		"required_providers.google has no source",
	)
}

test_s15_registry_rejects_an_object_without_source if {
	denied_with(
		patched(drop(concat("/", [google_path, "source"]))),
		"required_providers.google has no source",
	)
}

test_s15_registry_rejects_a_provider_block_without_declaration if {
	denied_with(
		patched(drop("/terraform/0/required_providers/0/google")),
		"provider google is configured but not declared in required_providers",
	)
}

test_s15_registry_names_the_file if {
	denied_with(
		patched(set(concat("/", [google_path, "source"]), "hashicorp/google")),
		"gcp/tofu/versions.tf",
	)
}
