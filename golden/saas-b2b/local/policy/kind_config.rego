# S05: the kind configuration of the local cluster, local/kind/cluster.yaml,
# keeps the API server and every published port on the loopback, and pins
# every node image by digest (spec 001, plan, matrix S05; ADR-004,
# conditions 1 and 3). The Kubernetes minor of the node image is compared
# with platform.yaml by package platform_values (S21).
#
# Input: the files given to `conftest test --combine`, a list of objects
# with a `path` and the parsed `contents` (research RS-18). Field names are
# those of kind.x-k8s.io/v1alpha4 at kind v0.33.0 (research RS-13).
package kind_config

label := "S05 (FR-003, FR-008; ADR-004, conditions 1 and 3)"

loopback := "127.0.0.1"

# A node image: a repository, a tag, then a sha256 digest of 64 hex digits.
pinned_image := `^[a-z0-9][a-z0-9._/-]*:[A-Za-z0-9._-]+@sha256:[a-f0-9]{64}$`

kind_files contains file if {
	some file in input
	regex.match(`(^|/)local/kind/cluster\.yaml$`, file.path)
}

deny contains msg if {
	count(kind_files) != 1
	msg := sprintf("%s: expected one local/kind/cluster.yaml among the checked files, found %v", [label, count(kind_files)])
}

config := file.contents if {
	count(kind_files) == 1
	some file in kind_files
}

deny contains msg if {
	is_object(config)
	object.get(config, "kind", "") != "Cluster"
	msg := sprintf("%s: kind must be Cluster, found %v", [label, object.get(config, "kind", null)])
}

deny contains msg if {
	is_object(config)
	object.get(config, "apiVersion", "") != "kind.x-k8s.io/v1alpha4"
	msg := sprintf("%s: apiVersion must be kind.x-k8s.io/v1alpha4, the version read for kind 0.33.0, found %v", [label, object.get(config, "apiVersion", null)])
}

# kind defaults apiServerAddress to 127.0.0.1; the file writes it anyway, so
# that a change of default cannot move the API off the loopback.
deny contains msg if {
	is_object(config)
	address := object.get(object.get(config, "networking", {}), "apiServerAddress", null)
	address != loopback
	msg := sprintf("%s: networking.apiServerAddress must be %s, found %v", [label, loopback, address])
}

nodes := object.get(config, "nodes", [])

deny contains msg if {
	is_object(config)
	count(nodes) == 0
	msg := sprintf("%s: no node: each node names its image by digest, or kind picks its own default image", [label])
}

deny contains msg if {
	some i, node in nodes
	image := object.get(node, "image", null)
	not pinned(image)
	msg := sprintf("%s: nodes[%v].image must be a tag and a sha256 digest, found %v", [label, i, image])
}

pinned(image) if {
	is_string(image)
	regex.match(pinned_image, image)
}

# kind publishes an extraPortMappings entry on 0.0.0.0 when listenAddress is
# missing (ADR-004, condition 1): every entry writes 127.0.0.1.
deny contains msg if {
	some i, node in nodes
	some j, mapping in object.get(node, "extraPortMappings", [])
	address := object.get(mapping, "listenAddress", null)
	address != loopback
	msg := sprintf("%s: nodes[%v].extraPortMappings[%v].listenAddress must be %s, found %v", [label, i, j, loopback, address])
}
