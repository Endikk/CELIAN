# S21: the Kubernetes minor and the Postgres major have one value each, kept
# in platform.yaml, and every file that repeats them agrees with it (spec 001,
# data-model, "Valeurs partagées"; ADR-004, version rule; ADR-012, condition 5).
#
# Input: the files given to `conftest test --combine`, a list of objects with
# a `path` and the parsed `contents` (research RS-18). Step 1 checks the shape
# of platform.yaml; step 6 (T041) compares the node images of the kind
# configuration with it; T065 and T105 add the Postgres image and the
# OpenTofu layer.
package platform_values

# Shared keys and the form of their value. Both are strings: YAML would read
# an unquoted 1.30 as the number 1.3.
shared_keys := {
	"kubernetes_minor": `^[0-9]+\.[0-9]+$`,
	"postgres_major": `^[0-9]+$`,
}

label := "S21 (FR-010, FR-017; ADR-004, version rule; ADR-012, condition 5)"

platform_files contains file if {
	some file in input
	regex.match(`(^|/)platform\.yaml$`, file.path)
}

deny contains msg if {
	count(platform_files) == 0
	msg := sprintf("%s: platform.yaml is missing from the checked files", [label])
}

deny contains msg if {
	count(platform_files) > 1
	msg := sprintf("%s: %v files named platform.yaml; the shared values live in one", [label, count(platform_files)])
}

deny contains msg if {
	some file in platform_files
	not is_object(file.contents)
	msg := sprintf("%s: %s must be a mapping of keys to values", [label, file.path])
}

deny contains msg if {
	some file in platform_files
	is_object(file.contents)
	some key, _ in shared_keys
	object.get(file.contents, key, null) == null
	msg := sprintf("%s: %s has no %s key", [label, file.path, key])
}

deny contains msg if {
	some file in platform_files
	some key, _ in shared_keys
	value := file.contents[key]
	value != null
	not is_string(value)
	msg := sprintf("%s: %s in %s must be a quoted string, found %v", [label, key, file.path, value])
}

deny contains msg if {
	some file in platform_files
	some key, pattern in shared_keys
	value := file.contents[key]
	is_string(value)
	not regex.match(pattern, value)
	msg := sprintf("%s: %s in %s is '%v', which does not match %s", [label, key, file.path, value, pattern])
}

# The kind configuration of the local layer (T041): the tag of each node
# image is vX.Y.Z, and X.Y is kubernetes_minor (ADR-004, version rule,
# point 2). kind 0.33.0 creates v1.37.0 by default: a node image of another
# minor would change the cluster without a word.
kind_files contains file if {
	some file in input
	regex.match(`(^|/)local/kind/cluster\.yaml$`, file.path)
}

platform_minor := value if {
	count(platform_files) == 1
	some file in platform_files
	value := file.contents.kubernetes_minor
	is_string(value)
}

# The minor of a node image reference: "1.36" for kindest/node:v1.36.4@...
node_minor(image) := minor if {
	is_string(image)
	parts := regex.find_all_string_submatch_n(`^[^@]+:v([0-9]+\.[0-9]+)\.[0-9]+(@sha256:[a-f0-9]{64})?$`, image, 1)
	count(parts) == 1
	minor := parts[0][1]
}

deny contains msg if {
	some file in kind_files
	some i, node in object.get(file.contents, "nodes", [])
	image := object.get(node, "image", null)
	not node_minor(image)
	msg := sprintf("%s: nodes[%v].image in %s has no vX.Y.Z tag to compare with kubernetes_minor, found %v", [label, i, file.path, image])
}

deny contains msg if {
	some file in kind_files
	some i, node in object.get(file.contents, "nodes", [])
	minor := node_minor(node.image)
	is_string(platform_minor)
	minor != platform_minor
	msg := sprintf("%s: nodes[%v].image in %s runs Kubernetes %s, platform.yaml says kubernetes_minor %s", [label, i, file.path, minor, platform_minor])
}
