# S10, RootSync part: the binding objects of Config Sync, applied by the user
# once, never by Config Sync itself and never by an agent (spec 001, plan,
# matrix S10; tasks.md, gap 5; ADR-010, conditions 3 and 4 and reserve 2 of
# [FINOPS]; R-31, R-33).
#
# The RootSync:
# - sourceFormat is unstructured: without it the format is hierarchy, which
#   refuses a Kustomize render (ADR-010, "Répartition par couche");
# - override.roleRefs is there, and no entry names cluster-admin: without the
#   field Config Sync binds the reconciler to cluster-admin (type
#   RootSyncOverrideSpec, "If unset, a binding to cluster-admin will be
#   created", GoogleContainerTools/kpt-config-sync at v1.25.2, pkg/api/
#   configsync/v1beta1/resource_override.go, read on 2026-11-26);
# - monitoring.enabled is false: no otel-agent sidecar, no export of the
#   metrics (ADR-010, condition 7 and reserve 2 of [FINOPS]; type
#   MonitoringSpec, same tag);
# - the Git source carries no token and no cookie (ADR-010, condition 4: never
#   the token of scope repo, never the token of gh, never a personal token),
#   no password inside the URL, and no cleartext transport.
#
# The roles that roleRefs names, in the same render:
# - no wildcard, no verb escalate, bind or impersonate, no Secret, no RBAC
#   object, no token request, no exec: what a reconciler that obeys a
#   repository must not be able to do, or the repository could give itself
#   more;
# - a Role sits in the namespace of its RootSync entry; the ClusterRole bound
#   for the whole cluster (a ClusterRoleBinding, entry without namespace)
#   reaches namespaces and admission policies, which it reads and changes by
#   name, and the kinds of the Role, which it only reads (the status watcher
#   lists them at the cluster scope), and creates nothing: the create verb has no resource name in
#   Kubernetes RBAC, so it cannot be narrowed, and the user applies the
#   Namespace and the admission objects first, with the bootstrap;
# - the kinds of a Role are a closed list, as the kinds of the ClusterRole.
#
# Input: the render of gcp/k8s/bootstrap given to `conftest test --combine`,
# one entry per YAML document with its `path` and parsed `contents`
# (gcp/tests/static/s10-rootsync.sh).
package rootsync

label := "S10 (FR-012; ADR-010, conditions 3 and 4)"

objects contains [path, obj] if {
	some file in input
	path := file.path
	obj := file.contents
	is_object(obj)
}

describe(obj) := sprintf("%v %v", [object.get(obj, "kind", null), object.get(object.get(obj, "metadata", {}), "name", null)])

root_syncs contains [path, obj] if {
	some [path, obj] in objects
	obj.kind == "RootSync"
}

roles contains [path, obj] if {
	some [path, obj] in objects
	obj.apiVersion == "rbac.authorization.k8s.io/v1"
	obj.kind in {"Role", "ClusterRole"}
}

bindings_objects contains [path, obj] if {
	some [path, obj] in objects
	obj.kind in {"RoleBinding", "ClusterRoleBinding"}
}

# --- The RootSync ------------------------------------------------------------

deny contains msg if {
	count(root_syncs) != 1
	msg := sprintf("%s: %d RootSync in the render, one expected (one environment at the MVP, ADR-010 and Q6)", [label, count(root_syncs)])
}

deny contains msg if {
	some [path, rs] in root_syncs
	not rs.apiVersion == "configsync.gke.io/v1beta1"
	msg := sprintf("%s: %s, %s has apiVersion %v, configsync.gke.io/v1beta1 expected", [label, path, describe(rs), object.get(rs, "apiVersion", "unset")])
}

deny contains msg if {
	some [path, rs] in root_syncs
	not rs.metadata.namespace == "config-management-system"
	msg := sprintf("%s: %s, %s is not in the namespace config-management-system, where Config Sync reads its RootSync", [label, path, describe(rs)])
}

deny contains msg if {
	some [path, rs] in root_syncs
	not rs.spec.sourceFormat == "unstructured"
	msg := sprintf("%s: %s, %s has sourceFormat %v: unstructured is required, hierarchy refuses a Kustomize render", [label, path, describe(rs), object.get(rs.spec, "sourceFormat", "unset")])
}

deny contains msg if {
	some [path, rs] in root_syncs
	not rs.spec.monitoring.enabled == false
	msg := sprintf("%s: %s, %s leaves the export of the metrics on: write spec.monitoring.enabled: false (ADR-010, condition 7)", [label, path, describe(rs)])
}

deny contains msg if {
	some [path, rs] in root_syncs
	count(object.get(object.get(rs.spec, "override", {}), "roleRefs", [])) == 0
	msg := sprintf("%s: %s, %s has no spec.override.roleRefs: Config Sync would bind its reconciler to cluster-admin (ADR-010, condition 3)", [label, path, describe(rs)])
}

role_refs(rs) := object.get(object.get(rs.spec, "override", {}), "roleRefs", [])

deny contains msg if {
	some [path, rs] in root_syncs
	some ref in role_refs(rs)
	ref.name in {"cluster-admin", "admin", "edit"}
	msg := sprintf("%s: %s, %s binds the reconciler to %v, a role of the cluster that is not limited to the namespace of the environment", [label, path, describe(rs), ref.name])
}

deny contains msg if {
	some [path, rs] in root_syncs
	some ref in role_refs(rs)
	not ref.kind in {"Role", "ClusterRole"}
	msg := sprintf("%s: %s, %s has a roleRef of kind %v, Role or ClusterRole expected", [label, path, describe(rs), object.get(ref, "kind", "unset")])
}

deny contains msg if {
	some [path, rs] in root_syncs
	some ref in role_refs(rs)
	not role_in_render(ref)
	msg := sprintf("%s: %s, %s names the %v %v, which is not in the render: the bootstrap holds the roles of the reconciler", [label, path, describe(rs), object.get(ref, "kind", "?"), object.get(ref, "name", "?")])
}

role_in_render(ref) if {
	some [_, role] in roles
	role.kind == ref.kind
	role.metadata.name == ref.name
}

# A Role is bound where it lives: the entry names the namespace of the Role.
deny contains msg if {
	some [path, rs] in root_syncs
	some ref in role_refs(rs)
	ref.kind == "Role"
	some [_, role] in roles
	role.kind == "Role"
	role.metadata.name == ref.name
	not ref.namespace == role.metadata.namespace
	msg := sprintf("%s: %s, %s binds the Role %v with namespace %v, but the Role is in %v", [label, path, describe(rs), ref.name, object.get(ref, "namespace", "unset"), object.get(role.metadata, "namespace", "unset")])
}

# --- The Git source ----------------------------------------------------------

deny contains msg if {
	some [path, rs] in root_syncs
	object.get(rs.spec, "sourceType", "git") != "git"
	msg := sprintf("%s: %s, %s has sourceType %v: the golden repo reads Git", [label, path, describe(rs), rs.spec.sourceType])
}

deny contains msg if {
	some [path, rs] in root_syncs
	not rs.spec.git.auth
	msg := sprintf("%s: %s, %s has no spec.git.auth", [label, path, describe(rs)])
}

forbidden_auth := {
	"token": "a token, which the documentation of Google asks with the scope repo, the write access to every repository of the user (ADR-010, condition 4)",
	"cookiefile": "a cookie file, a credential of the same kind as a token",
}

deny contains msg if {
	some [path, rs] in root_syncs
	reason := forbidden_auth[rs.spec.git.auth]
	msg := sprintf("%s: %s, %s has spec.git.auth %v: %s", [label, path, describe(rs), rs.spec.git.auth, reason])
}

deny contains msg if {
	some [path, rs] in root_syncs
	rs.spec.git.auth == "ssh"
	not rs.spec.git.secretRef.name
	msg := sprintf("%s: %s, %s reads Git by ssh without spec.git.secretRef.name: the deploy key lives in a Secret that the user creates, never in the repository", [label, path, describe(rs)])
}

deny contains msg if {
	some [path, rs] in root_syncs
	not startswith(object.get(rs.spec.git, "repo", ""), "ssh://git@")
	not startswith(object.get(rs.spec.git, "repo", ""), "https://")
	msg := sprintf("%s: %s, %s has the repo %v: ssh://git@ or https:// expected, never a clear transport", [label, path, describe(rs), object.get(rs.spec.git, "repo", "unset")])
}

deny contains msg if {
	some [path, rs] in root_syncs
	regex.match(`://[^/@]+:[^/@]+@`, object.get(rs.spec.git, "repo", ""))
	msg := sprintf("%s: %s, %s has a credential inside spec.git.repo", [label, path, describe(rs)])
}

deny contains msg if {
	some [path, rs] in root_syncs
	object.get(rs.spec.git, "dir", "") == ""
	msg := sprintf("%s: %s, %s has no spec.git.dir: it names the composition that Config Sync renders", [label, path, describe(rs)])
}

# --- The roles ---------------------------------------------------------------

forbidden_resources := {"secrets", "roles", "rolebindings", "clusterroles", "clusterrolebindings", "serviceaccounts/token", "pods/exec", "pods/attach", "pods/portforward", "tokenreviews", "subjectaccessreviews"}

forbidden_verbs := {"*", "escalate", "bind", "impersonate"}

deny contains msg if {
	some [path, role] in roles
	some rule in role.rules
	some field in ["apiGroups", "resources", "verbs"]
	"*" in rule[field]
	msg := sprintf("%s: %s, %s has a wildcard in %s", [label, path, describe(role), field])
}

deny contains msg if {
	some [path, role] in roles
	some rule in role.rules
	some verb in rule.verbs
	verb in forbidden_verbs
	msg := sprintf("%s: %s, %s grants the verb %s", [label, path, describe(role), verb])
}

deny contains msg if {
	some [path, role] in roles
	some rule in role.rules
	some resource in rule.resources
	resource in forbidden_resources
	msg := sprintf("%s: %s, %s reaches %s: a reconciler that obeys a repository must not read Secrets nor write RBAC", [label, path, describe(role), resource])
}

deny contains msg if {
	some [path, role] in roles
	some rule in role.rules
	some verb in rule.verbs
	verb == "deletecollection"
	msg := sprintf("%s: %s, %s grants deletecollection", [label, path, describe(role)])
}

# The ClusterRole bound for the whole cluster, found through the entries of
# the RootSync that name no namespace.
cluster_bound(name) if {
	some [_, rs] in root_syncs
	some ref in role_refs(rs)
	ref.kind == "ClusterRole"
	ref.name == name
	not ref.namespace
}

cluster_scope_resources := {"namespaces", "validatingadmissionpolicies", "validatingadmissionpolicybindings"}

read_verbs := {"get", "list", "watch"}

# A rule that only reads.
read_only(rule) if {
	every verb in rule.verbs {
		verb in read_verbs
	}
}

# The status watcher of Config Sync lists every kind of the render at the cluster
# scope, since the render holds cluster-scoped objects (cli-utils, DefaultStatusWatcher,
# read on 2026-11-26; E16): the ClusterRole may read the kinds of the Role, and only read.
cluster_read_ok(rule, resource) if {
	read_only(rule)
	every group in rule.apiGroups {
		[group, resource] in role_kinds
	}
}

deny contains msg if {
	some [path, role] in roles
	role.kind == "ClusterRole"
	cluster_bound(role.metadata.name)
	some rule in role.rules
	some resource in rule.resources
	not resource in cluster_scope_resources
	not cluster_read_ok(rule, resource)
	msg := sprintf("%s: %s, %s is bound for the whole cluster and reaches %s: only namespaces and admission policies by name, and a read of the kinds of the Role", [label, path, describe(role), resource])
}

deny contains msg if {
	some [path, role] in roles
	role.kind == "ClusterRole"
	cluster_bound(role.metadata.name)
	some rule in role.rules
	some verb in rule.verbs
	verb in {"update", "patch", "delete"}
	count(object.get(rule, "resourceNames", [])) == 0
	msg := sprintf("%s: %s, %s grants %s on %v without resourceNames: a write for the whole cluster is limited to the objects of the environment", [label, path, describe(role), verb, rule.resources])
}

# No create for the whole cluster, whatever the kind: the admission objects and
# the Namespace are applied first by the user with the bootstrap, and Config
# Sync updates them by name (SECU review of the PR 87; tasks.md, gap 181).
deny contains msg if {
	some [path, role] in roles
	role.kind == "ClusterRole"
	cluster_bound(role.metadata.name)
	some rule in role.rules
	"create" in rule.verbs
	msg := sprintf("%s: %s, %s is bound for the whole cluster and grants create for the whole cluster on %v: the user applies those objects first, Config Sync only updates them by name", [label, path, describe(role), rule.resources])
}

# The kinds of a Role are a closed list: the kinds that the render of gcp/k8s/prod
# holds in the namespace, each with its group, nothing else (SECU review of the
# PR 87). A kind that the layer adds joins the list, with its reason, here.
role_kinds := {
	["", "configmaps"],
	["", "serviceaccounts"],
	["", "services"],
	["apps", "deployments"],
	["gateway.networking.k8s.io", "gateways"],
	["gateway.networking.k8s.io", "httproutes"],
	["secrets-store.csi.x-k8s.io", "secretproviderclasses"],
	["secret-sync.gke.io", "secretsyncs"],
}

# Read only, never written: the status of a Deployment is read from its ReplicaSets
# and theirs from their Pods (cli-utils, kstatus statusreaders, read on 2026-11-26).
observed_kinds := {
	["apps", "replicasets"],
	["", "pods"],
}

observed_read(rule, group, resource) if {
	[group, resource] in observed_kinds
	read_only(rule)
}

deny contains msg if {
	some [path, role] in roles
	role.kind == "Role"
	some rule in role.rules
	some group in rule.apiGroups
	some resource in rule.resources
	not [group, resource] in role_kinds
	not observed_read(rule, group, resource)
	msg := sprintf("%s: %s, %s reaches %v of the group %q, outside the closed list of kinds of the Role", [label, path, describe(role), resource, group])
}

# A binding object in the render must not hand cluster-admin to anything.
deny contains msg if {
	some [path, binding] in bindings_objects
	binding.roleRef.name in {"cluster-admin", "admin", "edit"}
	msg := sprintf("%s: %s, %s binds %v", [label, path, describe(binding), binding.roleRef.name])
}
