# Tests of S02, Kustomize part (kustomize_sources.rego), run by `conftest verify`.
package kustomize_sources

kustomization(contents) := {"path": "k8s/overlays/local/kustomization.yaml", "contents": object.union({
	"apiVersion": "kustomize.config.k8s.io/v1beta1",
	"kind": "Kustomization",
}, contents)}

accepted(files) if {
	msgs := deny with input as files
	count(msgs) == 0
}

denied_with(files, fragment) if {
	msgs := deny with input as files
	some msg in msgs
	contains(msg, fragment)
}

test_s02_kustomize_accepts_local_paths if {
	accepted([kustomization({
		"resources": ["../../base", "namespace.yaml"],
		"components": ["../../../local/k8s/lite"],
		"patches": [{"path": "patch.yaml", "target": {"kind": "Gateway"}}, {"patch": "- op: add\n  path: /x\n  value: https://example.invalid\n"}],
	})])
}

test_s02_kustomize_rejects_no_file if {
	denied_with([], "no kustomization.yaml")
}

test_s02_kustomize_rejects_a_remote_resource if {
	denied_with([kustomization({"resources": ["https://example.invalid/base.yaml"]})], "resources")
}

test_s02_kustomize_rejects_a_ssh_resource if {
	denied_with([kustomization({"resources": ["git@github.com:org/repo.git//dir"]})], "git@")
}

test_s02_kustomize_rejects_a_ref_resource if {
	denied_with([kustomization({"resources": ["github.com/org/repo//dir?ref=v1.0.0"]})], "?ref=")
}

test_s02_kustomize_rejects_a_remote_component if {
	denied_with([kustomization({"components": ["https://example.invalid/component"]})], "components")
}

test_s02_kustomize_rejects_a_remote_base if {
	denied_with([kustomization({"bases": ["git::https://example.invalid/base"]})], "bases")
}

test_s02_kustomize_rejects_a_remote_patch_path if {
	denied_with([kustomization({"patches": [{"path": "https://example.invalid/patch.yaml"}]})], "patches[0].path")
}

test_s02_kustomize_names_the_file if {
	denied_with([kustomization({"resources": ["oci://example.invalid/x"]})], "k8s/overlays/local/kustomization.yaml")
}
