# S21: the Kubernetes minor, the Postgres major and the line of the cache
# engine have one value each, kept in platform.yaml, and every file that
# repeats them agrees with it (spec 001, data-model, "Valeurs partagées";
# ADR-004, version rule; ADR-012, condition 5; ADR-015, condition 16).
#
# Input: the files given to `conftest test --combine`, a list of objects with
# a `path` and the parsed `contents` (research RS-18). Step 1 checks the shape
# of platform.yaml; step 6 (T041) compares the node images of the kind
# configuration with it; T065 and T105 add the Postgres image and the
# OpenTofu layer; step 19 adds the images of the cache layer.
#
# OpenTofu layer (T105): its .tf files read the Kubernetes minor from
# platform.yaml through a local. The Postgres major is a literal that equals
# the one of platform.yaml: Trivy does not resolve a computed value, and then
# skips its Cloud SQL checks (AVD-GCP-0014, 0016, 0020, 0022, 0025).
package platform_values

# Shared keys and the form of their value. All are strings: YAML would read
# an unquoted 1.30 as the number 1.3.
shared_keys := {
	"kubernetes_minor": `^[0-9]+\.[0-9]+$`,
	"postgres_major": `^[0-9]+$`,
	"cache_engine_line": `^[0-9]+\.[0-9]+$`,
}

label := "S21 (FR-010, FR-017; ADR-004, version rule; ADR-012, condition 5; ADR-015, condition 16)"

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

# OpenTofu layer. The expression that reads platform.yaml, as conftest parses
# it, and the form each attribute must take, %s standing for the local.
platform_expression := `${yamldecode(file("${path.module}/../../platform.yaml"))}`

# Read from the local.
computed_values := {"min_master_version": "${local.%s.kubernetes_minor}"}

# A literal, %s standing for the postgres_major of platform.yaml.
literal_values := {"database_version": "POSTGRES_%s"}

layer_values := object.union(computed_values, literal_values)

tf_files contains file if {
	some file in input
	endswith(file.path, ".tf")
}

platform_locals contains name if {
	some file in tf_files
	some block in object.get(file.contents, "locals", [])
	some name, expression in block
	expression == platform_expression
}

layer_settings contains {"path": file.path, "where": sprintf("%s.%s", [type, name]), "attribute": attribute, "value": value} if {
	some file in tf_files
	some type, named in object.get(file.contents, "resource", {})
	some name, bodies in named
	some body in bodies
	some attribute, _ in layer_values
	value := body[attribute]
}

deny contains msg if {
	count(tf_files) > 0
	count(platform_locals) == 0
	msg := sprintf("%s: the OpenTofu layer does not read platform.yaml; declare a local set to %s", [label, platform_expression])
}

deny contains msg if {
	some setting in layer_settings
	some attribute, form in computed_values
	setting.attribute == attribute
	allowed := {sprintf(form, [name]) | some name in platform_locals}
	not setting.value in allowed
	msg := sprintf("%s: %s: %s.%s is '%v'; it must read platform.yaml, as %s", [label, setting.path, setting.where, setting.attribute, setting.value, sprintf(form, ["<local>"])])
}

# The majors that platform.yaml states. The rules above refuse a missing, a
# duplicated or a malformed file, so this one speaks only when the value is
# unambiguous.
platform_postgres_majors contains major if {
	some file in platform_files
	major := file.contents.postgres_major
	is_string(major)
	regex.match(shared_keys.postgres_major, major)
}

deny contains msg if {
	count(platform_postgres_majors) == 1
	some major in platform_postgres_majors
	some setting in layer_settings
	some attribute, form in literal_values
	setting.attribute == attribute
	expected := sprintf(form, [major])
	setting.value != expected
	msg := sprintf("%s: %s: %s.%s is '%v'; it must be the literal '%s', the postgres_major of platform.yaml (Trivy does not resolve a computed value and then skips its Cloud SQL checks)", [label, setting.path, setting.where, setting.attribute, setting.value, expected])
}

deny contains msg if {
	count(tf_files) > 0
	some attribute, _ in layer_values
	not attribute_set(attribute)
	msg := sprintf("%s: no resource of the OpenTofu layer sets %s", [label, attribute])
}

attribute_set(attribute) if {
	some setting in layer_settings
	setting.attribute == attribute
}

# The Postgres image of the local layer (T065): the major of its tag,
# <major>.<minor>-trixie, is the postgres_major of platform.yaml (ADR-012,
# condition 5). Renovate keeps it there (S23); a hand-made change shows here.
postgres_files contains file if {
	some file in input
	regex.match(`(^|/)local/data/statefulset\.yaml$`, file.path)
}

postgres_images contains [file.path, image] if {
	some file in postgres_files
	walk(file.contents, [path, image])
	count(path) > 0
	path[count(path) - 1] == "image"
	is_string(image)
	regex.match(`(^|/)postgres:`, image)
}

# The major of a Postgres image reference: "18" for
# docker.io/library/postgres:18.7-trixie@sha256:...
postgres_image_major(image) := major if {
	parts := regex.find_all_string_submatch_n(`(^|/)postgres:([0-9]+)\.[0-9]+[^@]*@sha256:[a-f0-9]{64}$`, image, 1)
	count(parts) == 1
	major := parts[0][2]
}

deny contains msg if {
	some file in postgres_files
	count({image | some [path, image] in postgres_images; path == file.path}) == 0
	msg := sprintf("%s: %s names no Postgres image to compare with postgres_major", [label, file.path])
}

deny contains msg if {
	some [path, image] in postgres_images
	not postgres_image_major(image)
	msg := sprintf("%s: the Postgres image %v of %s has no <major>.<minor> tag and digest to compare with postgres_major", [label, image, path])
}

deny contains msg if {
	count(platform_postgres_majors) == 1
	some major in platform_postgres_majors
	some [path, image] in postgres_images
	found := postgres_image_major(image)
	found != major
	msg := sprintf("%s: the Postgres image of %s runs the major %s, platform.yaml says postgres_major %s", [label, path, found, major])
}

# The cache of the local layer (ADR-015, condition 16): the tag of each
# image of local/data/cache/, the Deployment and the probe Job, is
# X.Y.Z-alpine, and X.Y is the cache_engine_line of platform.yaml, the line
# that Memorystore for Valkey serves by default. The gcp layer reads the same
# value for its engine_version at step 20. A patch of the line is free, and
# Renovate follows it (S23).
cache_files contains file if {
	some file in input
	regex.match(`(^|/)local/data/cache/.+\.ya?ml$`, file.path)
	is_object(file.contents)
	is_object(object.get(file.contents, ["spec", "template", "spec"], null))
}

platform_cache_line := value if {
	count(platform_files) == 1
	some file in platform_files
	value := file.contents.cache_engine_line
	is_string(value)
}

# The line of a cache image reference: "9.1" for
# docker.io/valkey/valkey:9.1.4-alpine@sha256:...
cache_line(image) := line if {
	is_string(image)
	parts := regex.find_all_string_submatch_n(`^[^@]+:([0-9]+\.[0-9]+)\.[0-9]+-alpine(@sha256:[a-f0-9]{64})?$`, image, 1)
	count(parts) == 1
	line := parts[0][1]
}

cache_images contains [file.path, container.name, object.get(container, "image", null)] if {
	some file in cache_files
	spec := file.contents.spec.template.spec
	some container in array.concat(object.get(spec, "initContainers", []), object.get(spec, "containers", []))
}

deny contains msg if {
	some [path, name, image] in cache_images
	not cache_line(image)
	msg := sprintf("%s: container %v in %s has no X.Y.Z-alpine tag to compare with cache_engine_line, found %v", [label, name, path, image])
}

deny contains msg if {
	some [path, name, image] in cache_images
	line := cache_line(image)
	is_string(platform_cache_line)
	line != platform_cache_line
	msg := sprintf("%s: container %v in %s runs the line %s, platform.yaml says cache_engine_line %s", [label, name, path, line, platform_cache_line])
}
