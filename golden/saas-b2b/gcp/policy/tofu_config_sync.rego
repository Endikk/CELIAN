# S15: Config Sync on the cluster of the gcp layer, in a pinned version
# (spec 001, FR-012; ADR-010; R-32). The cluster joins a fleet, the
# configmanagement feature turns Config Sync on, and its version is written
# out with the automatic upgrades off: it moves by a PR that passes the
# matrix, with the free form of the E16 test (ADR-010, condition 5).
#
# Input: the .tf files given to `conftest test --combine` (research RS-18).
package tofu_config_sync

label := "S15 (FR-011, FR-012; ADR-010, Config Sync pinned; R-32)"

tf_files contains file if {
	some file in input
	endswith(file.path, ".tf")
}

resources contains {"path": file.path, "type": type, "name": name, "body": body} if {
	some file in tf_files
	some type, named in object.get(file.contents, "resource", {})
	some name, bodies in named
	some body in bodies
}

blocks_of(type) := {block | some block in resources; block.type == type}

where(block) := sprintf("%s: %s.%s", [block.path, block.type, block.name])

first(body, key) := object.get(body, key, [{}])[0]

clusters := blocks_of("google_container_cluster")

memberships := {block |
	some block in blocks_of("google_gke_hub_feature_membership")
	count(object.get(block.body, "configmanagement", [])) > 0
}

deny contains msg if {
	some cluster in clusters
	object.get(first(cluster.body, "fleet"), "project", "") == ""
	msg := sprintf("%s: %s: the cluster joins no fleet (fleet.project); Config Sync needs one", [label, where(cluster)])
}

deny contains msg if {
	count(clusters) > 0
	not config_sync_on
	msg := sprintf("%s: no google_gke_hub_feature_membership turns Config Sync on (configmanagement.config_sync.enabled = true)", [label])
}

config_sync_on if {
	some membership in memberships
	first(first(membership.body, "configmanagement"), "config_sync").enabled == true
}

deny contains msg if {
	some membership in memberships
	version := object.get(first(membership.body, "configmanagement"), "version", "")
	not regex.match(`^[0-9]+\.[0-9]+\.[0-9]+$`, version)
	msg := sprintf("%s: %s: configmanagement.version '%v' is not a pinned version (X.Y.Z)", [label, where(membership), version])
}

deny contains msg if {
	some membership in memberships
	management := object.get(first(membership.body, "configmanagement"), "management", "")
	management != "MANAGEMENT_MANUAL"
	msg := sprintf("%s: %s: configmanagement.management is '%v'; MANAGEMENT_MANUAL keeps the version where it is written", [label, where(membership), management])
}
