# Tests of S10, RootSync part (rootsync.rego), run by `conftest verify`.
package rootsync

namespace_role := {
	"apiVersion": "rbac.authorization.k8s.io/v1",
	"kind": "Role",
	"metadata": {"name": "saas-b2b-sync", "namespace": "saas-b2b"},
	"rules": [
		{
			"apiGroups": [""],
			"resources": ["configmaps", "serviceaccounts", "services"],
			"verbs": ["get", "list", "watch", "create", "update", "patch", "delete"],
		},
		{
			"apiGroups": ["apps"],
			"resources": ["deployments"],
			"verbs": ["get", "list", "watch", "create", "update", "patch", "delete"],
		},
		{
			"apiGroups": ["gateway.networking.k8s.io"],
			"resources": ["gateways", "httproutes"],
			"verbs": ["get", "list", "watch", "create", "update", "patch", "delete"],
		},
	],
}

cluster_role := {
	"apiVersion": "rbac.authorization.k8s.io/v1",
	"kind": "ClusterRole",
	"metadata": {"name": "saas-b2b-sync-cluster"},
	"rules": [
		{
			"apiGroups": ["", "admissionregistration.k8s.io"],
			"resources": ["namespaces", "validatingadmissionpolicies", "validatingadmissionpolicybindings"],
			"verbs": ["get", "list", "watch"],
		},
		{
			"apiGroups": [""],
			"resources": ["namespaces"],
			"resourceNames": ["saas-b2b"],
			"verbs": ["update", "patch"],
		},
		{
			"apiGroups": ["admissionregistration.k8s.io"],
			"resources": ["validatingadmissionpolicies", "validatingadmissionpolicybindings"],
			"resourceNames": ["require-requests"],
			"verbs": ["update", "patch", "delete"],
		},
	],
}

root_sync := {
	"apiVersion": "configsync.gke.io/v1beta1",
	"kind": "RootSync",
	"metadata": {"name": "root-sync", "namespace": "config-management-system"},
	"spec": {
		"sourceFormat": "unstructured",
		"git": {
			"repo": "ssh://git@github.com/example-owner/example-repo.git",
			"branch": "main",
			"dir": "gcp/k8s/prod",
			"auth": "ssh",
			"secretRef": {"name": "git-creds"},
		},
		"override": {"roleRefs": [
			{"kind": "Role", "name": "saas-b2b-sync", "namespace": "saas-b2b"},
			{"kind": "ClusterRole", "name": "saas-b2b-sync-cluster"},
		]},
		"monitoring": {"enabled": false},
	},
}

valid_objects := [namespace_role, cluster_role, root_sync]

files(objs) := [{"path": "bootstrap.yaml", "contents": obj} | some obj in objs]

accepted(objs) if {
	msgs := deny with input as files(objs)
	count(msgs) == 0
}

denied_with(objs, fragment) if {
	msgs := deny with input as files(objs)
	some msg in msgs
	contains(msg, fragment)
}

patched_root_sync(ops) := [namespace_role, cluster_role, json.patch(root_sync, ops)]

test_s10_accepts_the_valid_bootstrap if {
	accepted(valid_objects)
}

test_s10_rejects_a_missing_root_sync if {
	denied_with([namespace_role, cluster_role], "0 RootSync")
}

test_s10_rejects_two_root_syncs if {
	second := json.patch(root_sync, [{"op": "replace", "path": "/metadata/name", "value": "second-sync"}])
	denied_with([namespace_role, cluster_role, root_sync, second], "2 RootSync")
}

test_s10_rejects_hierarchy_format if {
	denied_with(patched_root_sync([{"op": "replace", "path": "/spec/sourceFormat", "value": "hierarchy"}]), "sourceFormat hierarchy")
}

test_s10_rejects_a_missing_source_format if {
	denied_with(patched_root_sync([{"op": "remove", "path": "/spec/sourceFormat"}]), "sourceFormat unset")
}

test_s10_rejects_metrics_left_on if {
	denied_with(patched_root_sync([{"op": "remove", "path": "/spec/monitoring"}]), "export of the metrics")
}

test_s10_rejects_metrics_turned_on if {
	denied_with(patched_root_sync([{"op": "replace", "path": "/spec/monitoring/enabled", "value": true}]), "export of the metrics")
}

test_s10_rejects_a_root_sync_without_role_refs if {
	denied_with(patched_root_sync([{"op": "remove", "path": "/spec/override"}]), "no spec.override.roleRefs")
}

test_s10_rejects_empty_role_refs if {
	denied_with(patched_root_sync([{"op": "replace", "path": "/spec/override/roleRefs", "value": []}]), "no spec.override.roleRefs")
}

test_s10_rejects_a_binding_to_cluster_admin if {
	ops := [{"op": "add", "path": "/spec/override/roleRefs/-", "value": {"kind": "ClusterRole", "name": "cluster-admin"}}]
	denied_with(patched_root_sync(ops), "binds the reconciler to cluster-admin")
}

test_s10_rejects_a_binding_to_edit if {
	ops := [{"op": "add", "path": "/spec/override/roleRefs/-", "value": {"kind": "ClusterRole", "name": "edit", "namespace": "saas-b2b"}}]
	denied_with(patched_root_sync(ops), "binds the reconciler to edit")
}

test_s10_rejects_a_role_ref_to_nothing if {
	ops := [{"op": "replace", "path": "/spec/override/roleRefs/0/name", "value": "absent"}]
	denied_with(patched_root_sync(ops), "which is not in the render")
}

test_s10_rejects_a_role_bound_in_another_namespace if {
	ops := [{"op": "replace", "path": "/spec/override/roleRefs/0/namespace", "value": "other"}]
	denied_with(patched_root_sync(ops), "but the Role is in saas-b2b")
}

test_s10_rejects_a_role_without_namespace if {
	ops := [{"op": "remove", "path": "/spec/override/roleRefs/0/namespace"}]
	denied_with(patched_root_sync(ops), "with namespace unset")
}

test_s10_rejects_auth_token if {
	denied_with(patched_root_sync([{"op": "replace", "path": "/spec/git/auth", "value": "token"}]), "spec.git.auth token")
}

test_s10_rejects_auth_cookiefile if {
	denied_with(patched_root_sync([{"op": "replace", "path": "/spec/git/auth", "value": "cookiefile"}]), "spec.git.auth cookiefile")
}

test_s10_rejects_ssh_without_secret if {
	denied_with(patched_root_sync([{"op": "remove", "path": "/spec/git/secretRef"}]), "without spec.git.secretRef.name")
}

test_s10_rejects_a_clear_transport if {
	ops := [{"op": "replace", "path": "/spec/git/repo", "value": "http://github.com/example-owner/example-repo.git"}]
	denied_with(patched_root_sync(ops), "never a clear transport")
}

test_s10_rejects_a_credential_in_the_url if {
	ops := [{"op": "replace", "path": "/spec/git/repo", "value": "https://user:secret@github.com/example-owner/example-repo.git"}]
	denied_with(patched_root_sync(ops), "credential inside spec.git.repo")
}

test_s10_rejects_a_missing_dir if {
	denied_with(patched_root_sync([{"op": "remove", "path": "/spec/git/dir"}]), "no spec.git.dir")
}

test_s10_rejects_another_source_type if {
	denied_with(patched_root_sync([{"op": "add", "path": "/spec/sourceType", "value": "oci"}]), "sourceType oci")
}

test_s10_rejects_a_root_sync_in_another_namespace if {
	ops := [{"op": "replace", "path": "/metadata/namespace", "value": "saas-b2b"}]
	denied_with(patched_root_sync(ops), "not in the namespace config-management-system")
}

test_s10_rejects_a_wildcard_verb if {
	bad := json.patch(namespace_role, [{"op": "replace", "path": "/rules/0/verbs", "value": ["*"]}])
	denied_with([bad, cluster_role, root_sync], "a wildcard in verbs")
}

test_s10_rejects_a_wildcard_resource if {
	bad := json.patch(namespace_role, [{"op": "replace", "path": "/rules/1/resources", "value": ["*"]}])
	denied_with([bad, cluster_role, root_sync], "a wildcard in resources")
}

test_s10_rejects_a_wildcard_group if {
	bad := json.patch(namespace_role, [{"op": "replace", "path": "/rules/1/apiGroups", "value": ["*"]}])
	denied_with([bad, cluster_role, root_sync], "a wildcard in apiGroups")
}

test_s10_rejects_secrets_in_a_role if {
	bad := json.patch(namespace_role, [{"op": "add", "path": "/rules/0/resources/-", "value": "secrets"}])
	denied_with([bad, cluster_role, root_sync], "reaches secrets")
}

test_s10_rejects_rbac_writes_in_a_role if {
	bad := json.patch(namespace_role, [{"op": "add", "path": "/rules/-", "value": {"apiGroups": ["rbac.authorization.k8s.io"], "resources": ["rolebindings"], "verbs": ["create"]}}])
	denied_with([bad, cluster_role, root_sync], "reaches rolebindings")
}

test_s10_rejects_escalate if {
	bad := json.patch(namespace_role, [{"op": "add", "path": "/rules/0/verbs/-", "value": "escalate"}])
	denied_with([bad, cluster_role, root_sync], "grants the verb escalate")
}

test_s10_rejects_impersonate if {
	bad := json.patch(namespace_role, [{"op": "add", "path": "/rules/0/verbs/-", "value": "impersonate"}])
	denied_with([bad, cluster_role, root_sync], "grants the verb impersonate")
}

test_s10_rejects_deletecollection if {
	bad := json.patch(namespace_role, [{"op": "add", "path": "/rules/0/verbs/-", "value": "deletecollection"}])
	denied_with([bad, cluster_role, root_sync], "grants deletecollection")
}

test_s10_rejects_a_cluster_role_on_pods if {
	bad := json.patch(cluster_role, [{"op": "add", "path": "/rules/0/resources/-", "value": "pods"}])
	denied_with([namespace_role, bad, root_sync], "reaches pods")
}

test_s10_rejects_a_cluster_write_without_names if {
	bad := json.patch(cluster_role, [{"op": "remove", "path": "/rules/1/resourceNames"}])
	denied_with([namespace_role, bad, root_sync], "without resourceNames")
}

test_s10_rejects_creating_namespaces_for_the_cluster if {
	bad := json.patch(cluster_role, [{"op": "add", "path": "/rules/-", "value": {"apiGroups": [""], "resources": ["namespaces"], "verbs": ["create"]}}])
	denied_with([namespace_role, bad, root_sync], "grants create for the whole cluster")
}

test_s10_rejects_creating_admission_policies_for_the_cluster if {
	bad := json.patch(cluster_role, [{"op": "add", "path": "/rules/-", "value": {"apiGroups": ["admissionregistration.k8s.io"], "resources": ["validatingadmissionpolicies", "validatingadmissionpolicybindings"], "verbs": ["create"]}}])
	denied_with([namespace_role, bad, root_sync], "grants create for the whole cluster")
}

# The kinds of the Role are a closed list too (SECU review of the PR 87).
test_s10_rejects_pods_in_a_role if {
	bad := json.patch(namespace_role, [{"op": "add", "path": "/rules/-", "value": {"apiGroups": [""], "resources": ["pods"], "verbs": ["get"]}}])
	denied_with([bad, cluster_role, root_sync], "outside the closed list of kinds")
}

test_s10_rejects_jobs_in_a_role if {
	bad := json.patch(namespace_role, [{"op": "add", "path": "/rules/-", "value": {"apiGroups": ["batch"], "resources": ["jobs"], "verbs": ["create"]}}])
	denied_with([bad, cluster_role, root_sync], "outside the closed list of kinds")
}

test_s10_rejects_network_policies_in_a_role_until_the_layer_has_one if {
	bad := json.patch(namespace_role, [{"op": "add", "path": "/rules/-", "value": {"apiGroups": ["networking.k8s.io"], "resources": ["networkpolicies"], "verbs": ["create"]}}])
	denied_with([bad, cluster_role, root_sync], "outside the closed list of kinds")
}

test_s10_rejects_a_known_kind_in_a_foreign_group if {
	bad := json.patch(namespace_role, [{"op": "replace", "path": "/rules/1/apiGroups", "value": ["extensions"]}])
	denied_with([bad, cluster_role, root_sync], "outside the closed list of kinds")
}

test_s10_rejects_a_subresource_in_a_role if {
	bad := json.patch(namespace_role, [{"op": "add", "path": "/rules/0/resources/-", "value": "services/proxy"}])
	denied_with([bad, cluster_role, root_sync], "outside the closed list of kinds")
}

test_s10_accepts_a_cluster_role_bound_in_a_namespace if {
	ops := [{"op": "replace", "path": "/spec/override/roleRefs/1", "value": {"kind": "ClusterRole", "name": "saas-b2b-sync-cluster", "namespace": "saas-b2b"}}]
	accepted(patched_root_sync(ops))
}

test_s10_rejects_a_binding_object_to_cluster_admin if {
	binding := {
		"apiVersion": "rbac.authorization.k8s.io/v1",
		"kind": "ClusterRoleBinding",
		"metadata": {"name": "oops"},
		"roleRef": {"apiGroup": "rbac.authorization.k8s.io", "kind": "ClusterRole", "name": "cluster-admin"},
		"subjects": [],
	}
	denied_with([namespace_role, cluster_role, root_sync, binding], "ClusterRoleBinding oops binds cluster-admin")
}
