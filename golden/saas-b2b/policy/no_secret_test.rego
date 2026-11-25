# Tests of S03 (no_secret.rego), run by `conftest verify`.
package no_secret

secret := {"apiVersion": "v1", "kind": "Secret", "metadata": {"name": "db-auth"}, "type": "kubernetes.io/basic-auth"}

statefulset := {
	"apiVersion": "apps/v1",
	"kind": "StatefulSet",
	"metadata": {"name": "postgres"},
	"spec": {"template": {"spec": {"volumes": [{"name": "db-auth", "secret": {"secretName": "db-auth"}}]}}},
}

kustomization := {"apiVersion": "kustomize.config.k8s.io/v1beta1", "kind": "Kustomization", "resources": ["statefulset.yaml"]}

valid_files := [
	{"path": "local/data/statefulset.yaml", "contents": statefulset},
	{"path": "local/data/kustomization.yaml", "contents": kustomization},
	{"path": "renovate.json", "contents": {"extends": ["config:recommended"]}},
]

accepted(files) if {
	count(deny) == 0 with input as files
}

denied_with(files, fragment) if {
	msgs := deny with input as files
	some msg in msgs
	contains(msg, fragment)
}

test_s03_accepts_references_to_secrets if {
	accepted(valid_files)
}

test_s03_rejects_a_secret if {
	denied_with(array.concat(valid_files, [{"path": "k8s/base/secret.yaml", "contents": secret}]), "k8s/base/secret.yaml holds a Secret, db-auth")
}

test_s03_rejects_a_secret_in_a_list if {
	list := {"apiVersion": "v1", "kind": "List", "items": [statefulset, secret]}
	denied_with(array.concat(valid_files, [{"path": "local/data/all.yaml", "contents": list}]), "holds a Secret")
}

test_s03_rejects_a_secret_under_the_golden_repo_of_celian if {
	denied_with([{"path": "golden/saas-b2b/gcp/k8s/secret.json", "contents": secret}], "golden/saas-b2b/gcp/k8s/secret.json")
}

test_s03_rejects_a_secret_generator if {
	generator := object.union(kustomization, {"secretGenerator": [{"name": "db-auth", "literals": ["password=x"]}]})
	denied_with([{"path": "local/k8s/lite/kustomization.yaml", "contents": generator}], "secretGenerator")
}

test_s03_rejects_an_empty_secret_generator if {
	generator := object.union(kustomization, {"secretGenerator": []})
	denied_with([{"path": "k8s/overlays/local/kustomization.yaml", "contents": generator}], "secretGenerator")
}

test_s03_accepts_a_document_that_is_not_an_object if {
	accepted([{"path": "tests/static/list.yaml", "contents": ["a", "b"]}])
}
