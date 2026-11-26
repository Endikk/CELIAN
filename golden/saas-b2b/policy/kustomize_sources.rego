# S02, Kustomize part (spec 001, matrix S02; ADR-004, condition 4): no
# kustomization.yaml of the golden repo takes anything from outside the
# repository. An entry of resources or components, the path of an entry of
# patches and each file of a configMapGenerator is a local relative path, or
# it is refused: Kustomize would fetch anything else at build time, past the
# sums of local/vendor/ (SECU reviews of step 7). The top-level keys are a
# closed list, further down.
#
# The marks of a remote entry are "://", "git@" and "?ref=" (a URL, an SSH
# address, a pinned base). Kustomize also takes the forms without a mark:
# the go-getter form "github.com/org/repo//dir" and "gitlab.com/org/repo",
# and a query string that does not start with ref ("?timeout=120"). A local
# relative path needs none of: a "/" at the start, a "//", a "?", a ":", a
# first segment that is a host name (a dot in it, and not a dot at the start).
# A local directory whose first segment has a dot, "v1.0/base", is written
# "./v1.0/base". Doc of the entries:
# https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/resource/
# (read on 2026-11-25).
#
# Input: the kustomization.yaml files under k8s/ and local/, given to
# `conftest test --combine` (research RS-18), one entry per file with its
# `path` and parsed `contents`; local/tests/static/s02-vendor-sums.sh.
package kustomize_sources

label := "S02 (FR-008; ADR-004, condition 4)"

remote_marks := ["://", "git@", "?ref=", "//", "?", ":"]

# A first segment with a dot, and not a dot at the start, followed by a
# slash: github.com/, gitlab.com/, git.example.org/.
host_first := `^[^./][^/]*\.[^/]*/`

remote(entry) if {
	is_string(entry)
	some mark in remote_marks
	contains(entry, mark)
}

remote(entry) if {
	is_string(entry)
	startswith(entry, "/")
}

remote(entry) if {
	is_string(entry)
	regex.match(host_first, entry)
}

# The closed list of the top-level keys (decision of the DSI, 2026-11-26): a
# key that is not here is refused, since Kustomize loads a file or a source
# through many of them (a chart pulled from a URL with helmCharts, a plugin
# with generators and transformers, files with patchesStrategicMerge,
# replacements, openapi, secretGenerator...). A key joins the list with the
# step that needs it, and with its reason here. Reference of the fields:
# https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/
# (read on 2026-11-26).
#
# - apiVersion, kind: the identity of the file; kind is Kustomization or
#   Component (the local target layer is a Component, local/k8s/component/).
# - metadata: the name and the annotations of the object; loads nothing.
# - namespace: the namespace of the objects (k8s/base/, local/data/).
# - resources, components: the composition of the layers (contracts/layers.md,
#   "Composition Kustomize"); their paths are checked below.
# - patches: the environment overlays change the common layer through
#   patches; an entry takes path, patch and target, and its path is checked.
# - labels: the labels of the objects, listed by the DSI for the layers to
#   come; no step of the plan uses it yet.
# - configMapGenerator: the scripts of Postgres and of the cache are given to
#   the pods through a generated ConfigMap (local/data/, local/data/cache/).
#   An entry takes name, files and literals; each file is checked like a
#   resource. envs and env are not admitted: they are not used, and read a
#   file. secretGenerator stays out: no Secret is versioned (S03).
# images and commonLabels are not here: neither the plan nor the contracts
# ask for them.
allowed_keys := [
	"apiVersion", "kind", "metadata", "namespace", "resources", "components",
	"patches", "labels", "configMapGenerator",
]

allowed_kinds := ["Kustomization", "Component"]

patch_keys := ["path", "patch", "target"]

generator_keys := ["name", "files", "literals"]

list_keys := ["resources", "components"]

# The path of an entry of files: "key=path" or "path". The whole entry is
# checked too, since a query string of a URL can hold an "=".
file_path(entry) := substring(entry, indexof(entry, "=") + 1, -1) if contains(entry, "=")

file_path(entry) := entry if not contains(entry, "=")

remote_file(entry) if remote(file_path(entry))

remote_file(entry) if {
	is_string(entry)
	some mark in remote_marks
	contains(entry, mark)
}

deny contains msg if {
	count(input) == 0
	msg := sprintf("%s: no kustomization.yaml among the checked files", [label])
}

deny contains msg if {
	some file in input
	is_object(file.contents)
	some key, _ in file.contents
	not key in allowed_keys
	msg := sprintf("%s: %s, key \"%s\" is not admitted in a Kustomization of the golden repo; admitted: %s", [label, file.path, key, concat(", ", allowed_keys)])
}

deny contains msg if {
	some file in input
	is_object(file.contents)
	kind := object.get(file.contents, "kind", null)
	not kind in allowed_kinds
	msg := sprintf("%s: %s, kind is \"%v\": a file of the golden repo is a Kustomization or a Component", [label, file.path, kind])
}

deny contains msg if {
	some file in input
	is_object(file.contents)
	some key in list_keys
	some i, entry in object.get(file.contents, key, [])
	remote(entry)
	msg := sprintf("%s: %s, %s[%d] is \"%v\": a Kustomization takes local relative paths only, nothing from a URL, a host name, an absolute path or a query string", [label, file.path, key, i, entry])
}

deny contains msg if {
	some file in input
	is_object(file.contents)
	some i, patch in object.get(file.contents, "patches", [])
	is_object(patch)
	remote(object.get(patch, "path", null))
	msg := sprintf("%s: %s, patches[%d].path is \"%v\": a Kustomization takes local relative paths only, nothing from a URL, a host name, an absolute path or a query string", [label, file.path, i, patch.path])
}

deny contains msg if {
	some file in input
	is_object(file.contents)
	some i, patch in object.get(file.contents, "patches", [])
	not is_object(patch)
	msg := sprintf("%s: %s, patches[%d] is not an object: an entry takes %s only", [label, file.path, i, concat(", ", patch_keys)])
}

deny contains msg if {
	some file in input
	is_object(file.contents)
	some i, patch in object.get(file.contents, "patches", [])
	is_object(patch)
	some key, _ in patch
	not key in patch_keys
	msg := sprintf("%s: %s, patches[%d] has the key \"%s\": an entry takes %s only", [label, file.path, i, key, concat(", ", patch_keys)])
}

deny contains msg if {
	some file in input
	is_object(file.contents)
	some i, generator in object.get(file.contents, "configMapGenerator", [])
	not is_object(generator)
	msg := sprintf("%s: %s, configMapGenerator[%d] is not an object: an entry takes %s only", [label, file.path, i, concat(", ", generator_keys)])
}

deny contains msg if {
	some file in input
	is_object(file.contents)
	some i, generator in object.get(file.contents, "configMapGenerator", [])
	is_object(generator)
	some key, _ in generator
	not key in generator_keys
	msg := sprintf("%s: %s, configMapGenerator[%d] has the key \"%s\": an entry takes %s only", [label, file.path, i, key, concat(", ", generator_keys)])
}

deny contains msg if {
	some file in input
	is_object(file.contents)
	some i, generator in object.get(file.contents, "configMapGenerator", [])
	is_object(generator)
	some j, entry in object.get(generator, "files", [])
	not is_string(entry)
	msg := sprintf("%s: %s, configMapGenerator[%d].files[%d] is not a string: a file is a local relative path", [label, file.path, i, j])
}

deny contains msg if {
	some file in input
	is_object(file.contents)
	some i, generator in object.get(file.contents, "configMapGenerator", [])
	is_object(generator)
	some j, entry in object.get(generator, "files", [])
	is_string(entry)
	remote_file(entry)
	msg := sprintf("%s: %s, configMapGenerator[%d].files[%d] is \"%v\": a Kustomization takes local relative paths only, nothing from a URL, a host name, an absolute path or a query string", [label, file.path, i, j, entry])
}
