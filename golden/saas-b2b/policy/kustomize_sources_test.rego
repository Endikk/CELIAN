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

test_s02_kustomize_accepts_relative_local_forms if {
	accepted([kustomization({
		"resources": ["namespace.yaml", "sub-dir/some-deployment.yaml", "../../common", "./k8s.v2/base", ".hidden/base"],
		"components": ["../../../local/k8s/lite"],
		"bases": ["../base"],
		"patches": [{"path": "patches/gateway.yaml"}],
	})])
}

test_s02_kustomize_rejects_a_github_path_without_a_mark if {
	denied_with([kustomization({"resources": ["github.com/org/repo//dir"]})], "github.com/org/repo//dir")
}

test_s02_kustomize_rejects_a_gitlab_host_without_a_mark if {
	denied_with([kustomization({"resources": ["gitlab.com/org/repo/dir"]})], "gitlab.com/org/repo/dir")
}

test_s02_kustomize_rejects_any_dotted_host_first if {
	denied_with([kustomization({"components": ["example.org/team/component"]})], "components")
	denied_with([kustomization({"bases": ["git.example.org/team/base"]})], "bases")
	denied_with([kustomization({"patches": [{"path": "example.org/team/patch.yaml"}]})], "patches[0].path")
}

test_s02_kustomize_rejects_an_absolute_path if {
	denied_with([kustomization({"resources": ["/etc/kubernetes/base"]})], "/etc/kubernetes/base")
	denied_with([kustomization({"patches": [{"path": "/tmp/patch.yaml"}]})], "patches[0].path")
}

test_s02_kustomize_rejects_a_double_slash_in_a_relative_path if {
	denied_with([kustomization({"resources": ["../../base//sub"]})], "../../base//sub")
}

test_s02_kustomize_rejects_a_query_string_without_ref if {
	denied_with([kustomization({"resources": ["../base?timeout=120"]})], "../base?timeout=120")
}

test_s02_kustomize_rejects_a_host_colon_path if {
	denied_with([kustomization({"resources": ["github.com:org/repo"]})], "github.com:org/repo")
}
