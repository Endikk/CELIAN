# S02, Kustomize part (spec 001, matrix S02; ADR-004, condition 4): no
# kustomization.yaml of the golden repo takes anything from outside the
# repository. An entry of resources, components or bases, and the path of
# an entry of patches, holds none of "://", "git@" and "?ref=": they are the
# marks of a URL, an SSH address and a pinned remote base, which Kustomize
# would fetch at build time, past the sums of local/vendor/ (SECU review of
# step 7).
#
# Input: the kustomization.yaml files under k8s/ and local/, given to
# `conftest test --combine` (research RS-18), one entry per file with its
# `path` and parsed `contents`; local/tests/static/s02-vendor-sums.sh.
package kustomize_sources

label := "S02 (FR-008; ADR-004, condition 4)"

remote_marks := ["://", "git@", "?ref="]

remote(entry) if {
	is_string(entry)
	some mark in remote_marks
	contains(entry, mark)
}

list_keys := ["resources", "components", "bases"]

deny contains msg if {
	count(input) == 0
	msg := sprintf("%s: no kustomization.yaml among the checked files", [label])
}

deny contains msg if {
	some file in input
	is_object(file.contents)
	some key in list_keys
	some i, entry in object.get(file.contents, key, [])
	remote(entry)
	msg := sprintf("%s: %s, %s[%d] is \"%v\": a Kustomization takes nothing from a URL, an SSH address or a ?ref= base", [label, file.path, key, i, entry])
}

deny contains msg if {
	some file in input
	is_object(file.contents)
	some i, patch in object.get(file.contents, "patches", [])
	is_object(patch)
	remote(object.get(patch, "path", null))
	msg := sprintf("%s: %s, patches[%d].path is \"%v\": a Kustomization takes nothing from a URL, an SSH address or a ?ref= base", [label, file.path, i, patch.path])
}
