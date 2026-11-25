# S02, Kustomize part (spec 001, matrix S02; ADR-004, condition 4): no
# kustomization.yaml of the golden repo takes anything from outside the
# repository. An entry of resources, components or bases, and the path of
# an entry of patches, is a local relative path, or it is refused: Kustomize
# would fetch anything else at build time, past the sums of local/vendor/
# (SECU reviews of step 7).
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
