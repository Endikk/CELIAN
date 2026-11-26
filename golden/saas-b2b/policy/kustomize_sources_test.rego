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

# The list of the top-level keys is closed: a key outside it is refused, with
# its file, its name and the admitted list in the message.

refused_keys := {
	"patchesStrategicMerge": ["patch.yaml"],
	"patchesJson6902": [{"path": "patch.yaml", "target": {"kind": "Gateway"}}],
	"transformers": ["transformer.yaml"],
	"generators": ["generator.yaml"],
	"validators": ["validator.yaml"],
	"crds": ["crd.json"],
	"replacements": [{"path": "replacement.yaml"}],
	"configurations": ["configuration.yaml"],
	"openapi": {"path": "schema.json"},
	"helmCharts": [{"name": "chart", "repo": "https://example.invalid/charts"}],
	"helmGlobals": {"chartHome": "charts"},
	"helmChartInflationGenerator": [{"chartName": "chart"}],
	"secretGenerator": [{"name": "s", "files": ["secret.txt"]}],
	"buildMetadata": ["originAnnotations"],
	"bases": ["../base"],
	"images": [{"name": "app", "newTag": "1"}],
	"commonLabels": {"app": "x"},
	"commonAnnotations": {"owner": "x"},
	"namePrefix": "p-",
	"nameSuffix": "-s",
	"vars": [{"name": "V"}],
	"replicas": [{"name": "app", "count": 2}],
	"generatorOptions": {"disableNameSuffixHash": true},
	"sortOptions": {"order": "legacy"},
	"inventory": {"type": "ConfigMap"},
	"anUnknownKey": "x",
}

test_s02_kustomize_refuses_each_key_outside_the_list if {
	every key, value in refused_keys {
		denied_with([kustomization({key: value})], sprintf("key \"%s\"", [key]))
	}
}

test_s02_kustomize_names_the_file_the_key_and_the_list if {
	files := [kustomization({"helmCharts": [{"name": "chart"}]})]
	denied_with(files, "k8s/overlays/local/kustomization.yaml")
	denied_with(files, "key \"helmCharts\"")
	denied_with(files, "admitted: apiVersion, kind, metadata, namespace, resources, components, patches, labels, configMapGenerator")
}

test_s02_kustomize_accepts_the_keys_of_the_list if {
	accepted([kustomization({
		"metadata": {"name": "local"},
		"namespace": "saas-b2b",
		"labels": [{"pairs": {"app.kubernetes.io/part-of": "saas-b2b"}}],
		"resources": ["../../base"],
		"components": ["../component"],
		"patches": [{"patch": "- op: add\n  path: /x\n  value: y\n", "target": {"kind": "Gateway"}}],
		"configMapGenerator": [{"name": "init", "files": ["init/10-app-role.sh", "script=init/20-x.sh"], "literals": ["MODE=local"]}],
	})])
}

test_s02_kustomize_accepts_a_component if {
	accepted([{"path": "local/k8s/component/kustomization.yaml", "contents": {
		"apiVersion": "kustomize.config.k8s.io/v1alpha1",
		"kind": "Component",
		"resources": ["../../data"],
	}}])
}

test_s02_kustomize_refuses_a_kind_outside_the_two if {
	denied_with([{"path": "k8s/x/kustomization.yaml", "contents": {"apiVersion": "v1", "kind": "ConfigMap"}}], "kind")
	denied_with([{"path": "k8s/x/kustomization.yaml", "contents": {"apiVersion": "kustomize.config.k8s.io/v1beta1"}}], "kind")
}

test_s02_kustomize_refuses_a_patch_key_other_than_path_patch_target if {
	denied_with([kustomization({"patches": [{"path": "patch.yaml", "options": {"allowNameChange": true}}]})], "patches[0]")
	denied_with([kustomization({"patches": [{"patch": "x", "options": {}}]})], "\"options\"")
}

test_s02_kustomize_refuses_a_patch_that_is_not_an_object if {
	denied_with([kustomization({"patches": ["patch.yaml"]})], "patches[0]")
}

test_s02_kustomize_refuses_a_generator_key_that_loads_a_file_by_env if {
	denied_with([kustomization({"configMapGenerator": [{"name": "c", "envs": ["config.env"]}]})], "configMapGenerator[0]")
	denied_with([kustomization({"configMapGenerator": [{"name": "c", "env": "config.env"}]})], "\"env\"")
}

test_s02_kustomize_refuses_a_remote_file_of_a_generator if {
	denied_with([kustomization({"configMapGenerator": [{"name": "c", "files": ["https://example.invalid/x.json"]}]})], "configMapGenerator[0].files[0]")
	denied_with([kustomization({"configMapGenerator": [{"name": "c", "files": ["key=github.com/org/repo//x.json"]}]})], "configMapGenerator[0].files[0]")
	denied_with([kustomization({"configMapGenerator": [{"name": "c", "files": ["/etc/passwd"]}]})], "/etc/passwd")
}

test_s02_kustomize_refuses_a_generator_that_is_not_an_object if {
	denied_with([kustomization({"configMapGenerator": ["c"]})], "configMapGenerator[0]")
}
