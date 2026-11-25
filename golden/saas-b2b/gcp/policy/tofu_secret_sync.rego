# S15: condition 2 of ADR-007 on the HCL of the gcp layer (spec 001, FR-012).
# The sync of GKE is on; secretAccessor is granted secret by secret to a
# Workload Identity principal, never at the project level; the cluster runs
# 1.35.5-gke.1163012 or later, which recreates a deleted synced Secret; a
# rotation, if on, keeps to the free tier of Secret Manager (R-29).
#
# Input: the files given to `conftest test --combine`: the .tf files of the
# layer and platform.yaml, which holds the Kubernetes minor that the cluster
# reads (research RS-16).
package tofu_secret_sync

label := "S15 (FR-011, FR-012; ADR-007, condition 2)"

accessor := "roles/secretmanager.secretAccessor"

# Lowest cluster version of ADR-007, condition 2, as numbers: 1.35.5-gke.1163012.
minimum := [1, 35, 5, 1163012]

# ADR-007, condition 2: 15 minutes at least for 3 secrets.
min_rotation_seconds := 900

max_secrets_for_that_interval := 3

tf_files contains file if {
	some file in input
	endswith(file.path, ".tf")
}

platform := file.contents if {
	some file in input
	regex.match(`(^|/)platform\.yaml$`, file.path)
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

members(body) := {member |
	some member in array.concat([object.get(body, "member", "")], object.get(body, "members", []))
	is_string(member)
	member != ""
}

clusters := blocks_of("google_container_cluster")

# Access: never at the project level, always to a principal:// identity.

project_iam_types := {"google_project_iam_member", "google_project_iam_binding"}

deny contains msg if {
	some block in resources
	block.type in project_iam_types
	block.body.role == accessor
	msg := sprintf("%s: %s: %s granted at the project level; grant it secret by secret", [label, where(block), accessor])
}

secret_iam_types := {
	"google_secret_manager_secret_iam_member",
	"google_secret_manager_secret_iam_binding",
	"google_secret_manager_regional_secret_iam_member",
	"google_secret_manager_regional_secret_iam_binding",
}

deny contains msg if {
	some block in resources
	block.type in secret_iam_types
	block.body.role == accessor
	some member in members(block.body)
	not startswith(member, "principal://")
	msg := sprintf("%s: %s: %s goes to %s; only the Workload Identity principal (principal://) of the application reads its secrets", [label, where(block), accessor, member])
}

# The sync itself.

deny contains msg if {
	some cluster in clusters
	object.get(first(cluster.body, "secret_sync_config"), "enabled", false) != true
	msg := sprintf("%s: %s: the secret sync of GKE is not on (secret_sync_config.enabled = true)", [label, where(cluster)])
}

rotation(cluster) := first(first(cluster.body, "secret_sync_config"), "rotation_config")

# The interval in seconds, when it is written "<n>s" as the page of Google
# writes it (research RS-16).
seconds(interval) := n if {
	is_string(interval)
	regex.match(`^[0-9]+s$`, interval)
	n := to_number(trim_suffix(interval, "s"))
}

long_enough(interval) if seconds(interval) >= min_rotation_seconds

deny contains msg if {
	some cluster in clusters
	rotation(cluster).enabled == true
	interval := object.get(rotation(cluster), "rotation_interval", "")
	not long_enough(interval)
	msg := sprintf("%s: %s: rotation_interval '%v' is under %vs, or not written in seconds; the free tier of Secret Manager would not hold (R-29)", [label, where(cluster), interval, min_rotation_seconds])
}

secret_count := count(blocks_of("google_secret_manager_secret")) + count(blocks_of("google_secret_manager_regional_secret"))

deny contains msg if {
	some cluster in clusters
	rotation(cluster).enabled == true
	some block in blocks_of("google_secret_manager_secret")
	object.get(block.body, "for_each", null) != null
	msg := sprintf("%s: %s: rotation is on and %s counts its secrets with for_each, which this policy cannot count; recompute the interval by hand", [label, where(cluster), where(block)])
}

deny contains msg if {
	some cluster in clusters
	rotation(cluster).enabled == true
	secret_count > max_secrets_for_that_interval
	msg := sprintf("%s: %s: rotation is on with %v secret blocks; the 15 minutes hold for %v, recompute the interval", [label, where(cluster), secret_count, max_secrets_for_that_interval])
}

# Version of the cluster.

numbers(version) := [to_number(n) | some n in parts] if {
	groups := regex.find_all_string_submatch_n(`^([0-9]+)\.([0-9]+)(?:\.([0-9]+)(?:-gke\.([0-9]+))?)?$`, version, 1)[0]
	parts := [n | some i in [1, 2, 3, 4]; n := groups[i]; n != ""]
}

# A version reaches the minimum if every version it may resolve to does: a
# bare minor resolves to its highest patch, a bare patch to its highest
# gke.N (research RS-16), so they count as their lowest member, zeros added.
reaches_minimum(version) if {
	parts := numbers(version)
	padded := array.concat(parts, array.slice([0, 0, 0, 0], 0, 4 - count(parts)))
	padded >= minimum
}

# Version the cluster asks for: a literal, or the minor of platform.yaml.
asked_version(cluster) := version if {
	version := cluster.body.min_master_version
	is_string(version)
	not contains(version, "${")
}

asked_version(cluster) := platform.kubernetes_minor if {
	regex.match(`^\$\{local\.[A-Za-z0-9_]+\.kubernetes_minor\}$`, cluster.body.min_master_version)
}

deny contains msg if {
	some cluster in clusters
	object.get(cluster.body, "min_master_version", null) == null
	msg := sprintf("%s: %s: no min_master_version; the sync wants 1.35.5-gke.1163012 or later", [label, where(cluster)])
}

deny contains msg if {
	some cluster in clusters
	object.get(cluster.body, "min_master_version", null) != null
	not asked_version(cluster)
	msg := sprintf("%s: %s: min_master_version '%v' is neither a version nor the kubernetes_minor of platform.yaml; it cannot be checked", [label, where(cluster), cluster.body.min_master_version])
}

deny contains msg if {
	some cluster in clusters
	version := asked_version(cluster)
	not reaches_minimum(version)
	msg := sprintf("%s: %s: version '%v' may resolve under 1.35.5-gke.1163012, which recreates a deleted synced Secret", [label, where(cluster), version])
}
