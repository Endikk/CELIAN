# S06: the common layer, rendered by Kustomize, names no tool and no
# provider (spec 001, plan, matrix S06; contracts/layers.md, "Appartenance";
# ADR-005, condition 2; ADR-010, condition 1):
# - only objects of upstream Kubernetes and Gateway API: the core group,
#   apps, batch, policy, autoscaling, and the groups under k8s.io that are
#   not SIG projects under x-k8s.io; no gateway.envoyproxy.io,
#   configsync.gke.io, *.toolkit.fluxcd.io nor argoproj.io;
# - no label nor annotation of an engine or a provider: a key with a
#   prefix keeps it under kubernetes.io or k8s.io;
# - no "${" anywhere, the substitution of a GitOps engine;
# - no value that names a tool of a target layer or a provider.
#
# Input: the rendered files given to `conftest test --combine`, one entry per
# YAML document with its `path` and parsed `contents` (research RS-18):
# tests/static/s06-common-neutral.sh renders k8s/base and each overlay of
# k8s/overlays/ with `kubectl kustomize`.
package common_neutral

label := "S06 (FR-010; ADR-005, condition 2; ADR-010, condition 1)"

named_groups := {
	"gateway.envoyproxy.io": "Envoy Gateway",
	"configsync.gke.io": "Config Sync",
	"argoproj.io": "Argo CD",
}

upstream_groups := {"", "apps", "batch", "policy", "autoscaling"}

# Words that name a tool of a target layer, a GitOps engine or a provider,
# matched in any value, case aside.
tool_words := `(?i)(envoy|zot|flux|argocd|argoproj|configsync|config-sync|kindest|gke|google|googleapis)`

objects contains [file.path, obj] if {
	some file in input
	obj := file.contents
	is_object(obj)
}

group_of(obj) := "" if {
	not contains(object.get(obj, "apiVersion", ""), "/")
}

group_of(obj) := group if {
	parts := split(object.get(obj, "apiVersion", ""), "/")
	count(parts) == 2
	group := parts[0]
}

upstream(group) if group in upstream_groups

upstream(group) if {
	endswith(group, ".k8s.io")
	not endswith(group, ".x-k8s.io")
}

describe(obj) := sprintf("%v %v", [object.get(obj, "kind", null), object.get(object.get(obj, "metadata", {}), "name", null)])

deny contains msg if {
	count(objects) == 0
	msg := sprintf("%s: no rendered object of the common layer among the checked files", [label])
}

deny contains msg if {
	some [path, obj] in objects
	group := group_of(obj)
	tool := named_groups[group]
	msg := sprintf("%s: %s holds %s of the group %s, of %s, which belongs in a target layer", [label, path, describe(obj), group, tool])
}

deny contains msg if {
	some [path, obj] in objects
	group := group_of(obj)
	endswith(group, ".toolkit.fluxcd.io")
	msg := sprintf("%s: %s holds %s of the group %s, of Flux, which belongs in the local layer", [label, path, describe(obj), group])
}

deny contains msg if {
	some [path, obj] in objects
	group := group_of(obj)
	not upstream(group)
	not named_groups[group]
	not endswith(group, ".toolkit.fluxcd.io")
	msg := sprintf("%s: %s holds %s of the group %s, outside upstream Kubernetes and Gateway API", [label, path, describe(obj), group])
}

upstream_key(key) if not contains(key, "/")

upstream_key(key) if split(key, "/")[0] in {"kubernetes.io", "k8s.io"}

upstream_key(key) if {
	prefix := split(key, "/")[0]
	not endswith(prefix, ".x-k8s.io")
	some domain in [".kubernetes.io", ".k8s.io"]
	endswith(prefix, domain)
}

deny contains msg if {
	some [path, obj] in objects
	some field in ["labels", "annotations"]
	some key, _ in object.get(object.get(obj, "metadata", {}), field, {})
	not upstream_key(key)
	msg := sprintf("%s: %s gives %s the %s %s, of an engine or a provider", [label, path, describe(obj), trim_suffix(field, "s"), key])
}

deny contains msg if {
	some [path, obj] in objects
	walk(obj, [at, value])
	is_string(value)
	contains(value, "${")
	msg := sprintf("%s: %s holds \"${\" in %s at %v, a substitution of a GitOps engine", [label, path, describe(obj), at])
}

deny contains msg if {
	some [path, obj] in objects
	walk(obj, [at, value])
	is_string(value)
	regex.match(tool_words, value)
	msg := sprintf("%s: %s names a tool or a provider in %s at %v: %v", [label, path, describe(obj), at, value])
}
