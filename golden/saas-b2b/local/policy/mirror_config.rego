# S13: the configuration of the zot mirror and of the registry hosts of the
# node (spec 001, plan, matrix S13; ADR-011, conditions 1, 5, 7, 10 and 13).
# - each hosts.toml gives the mirror the capability pull, and nothing else;
# - the zot configuration holds the extension sync and nothing else, with no
#   credential anywhere, and the anonymous policy that grants read on every
#   repository and nothing else, so that no pod writes to the mirror
#   (ADR-011, complement of 2026-11-26);
# - the hosts.toml files and the sync entries both derive from the one list
#   of registries, local/mirror/registries;
# - the kind configuration points containerd at the versioned hosts.toml,
#   mounted read-only.
#
# Input: the files given to `conftest test --combine` (research RS-18):
# local/mirror/zot/config.json, every local/mirror/certs.d/<registry>/
# hosts.toml and local/kind/cluster.yaml. Data, written by the control
# script from local/mirror/registries and local/scripts/lib/local-env.sh:
#   data.registries     [{"namespace": "docker.io", "upstream": "https://..."}]
#   data.mirror_name    the name of the mirror container on the network kind
# Field names: zot 2.1.23, containerd 2.3.4 docs/hosts.md, kind v0.33.0
# (research RS-13).
package mirror_config

label := "S13 (FR-008, FR-016; ADR-011, conditions 1, 5, 7, 10 and 13)"

# Where the mirror keeps its images: the target of the named volume that
# local/scripts/mirror.sh mounts.
storage_root := "/home/nonroot"

# Where the node reads its registry hosts, and the folder mounted there.
certs_dir := "/etc/containerd/certs.d"

certs_source := "local/mirror/certs.d"

config_path_line := sprintf(`config_path = "%s"`, [certs_dir])

zot_files contains file if {
	some file in input
	regex.match(`(^|/)local/mirror/zot/config\.json$`, file.path)
}

kind_files contains file if {
	some file in input
	regex.match(`(^|/)local/kind/cluster\.yaml$`, file.path)
}

# Registry namespace of a hosts.toml, from its folder name.
hosts_files[namespace] := file if {
	some file in input
	parts := regex.find_all_string_submatch_n(`(^|/)local/mirror/certs\.d/([^/]+)/hosts\.toml$`, file.path, 1)
	count(parts) == 1
	namespace := parts[0][2]
}

deny contains msg if {
	count(zot_files) != 1
	msg := sprintf("%s: expected one local/mirror/zot/config.json among the checked files, found %v", [label, count(zot_files)])
}

deny contains msg if {
	count(kind_files) != 1
	msg := sprintf("%s: expected one local/kind/cluster.yaml among the checked files, found %v", [label, count(kind_files)])
}

listed := {entry.namespace | some entry in data.registries}

upstreams := {entry.upstream | some entry in data.registries}

deny contains msg if {
	count(listed) == 0
	msg := sprintf("%s: local/mirror/registries lists no registry", [label])
}

zot := file.contents if {
	count(zot_files) == 1
	some file in zot_files
}

# The zot configuration: known top keys, the extension sync alone.

zot_top_keys := {"distSpecVersion", "storage", "http", "log", "extensions"}

deny contains msg if {
	some key, _ in zot
	not key in zot_top_keys
	msg := sprintf("%s: the zot configuration holds %s; only %v are expected", [label, key, zot_top_keys])
}

deny contains msg if {
	is_object(zot)
	extensions := object.get(zot, "extensions", {})
	{key | some key, _ in extensions} != {"sync"}
	msg := sprintf("%s: the zot configuration must enable the extension sync and no other, found %v", [label, {key | some key, _ in extensions}])
}

sync := object.get(object.get(zot, "extensions", {}), "sync", {})

deny contains msg if {
	is_object(zot)
	object.get(sync, "enable", false) != true
	msg := sprintf("%s: extensions.sync.enable must be true", [label])
}

deny contains msg if {
	some key, _ in sync
	not key in {"enable", "registries"}
	msg := sprintf("%s: extensions.sync holds %s; only enable and registries are expected", [label, key])
}

sync_registries := object.get(sync, "registries", [])

deny contains msg if {
	some i, entry in sync_registries
	some key, _ in entry
	not key in {"urls", "onDemand", "tlsVerify"}
	msg := sprintf("%s: extensions.sync.registries[%v] holds %s; only urls, onDemand and tlsVerify are expected", [label, i, key])
}

deny contains msg if {
	some i, entry in sync_registries
	object.get(entry, "onDemand", false) != true
	msg := sprintf("%s: extensions.sync.registries[%v].onDemand must be true: the mirror fetches what the node asks for, nothing else", [label, i])
}

deny contains msg if {
	some i, entry in sync_registries
	object.get(entry, "tlsVerify", false) != true
	msg := sprintf("%s: extensions.sync.registries[%v].tlsVerify must be true", [label, i])
}

deny contains msg if {
	some i, entry in sync_registries
	count(object.get(entry, "urls", [])) != 1
	msg := sprintf("%s: extensions.sync.registries[%v].urls must hold one upstream", [label, i])
}

synced := {url | some entry in sync_registries; some url in object.get(entry, "urls", [])}

deny contains msg if {
	is_object(zot)
	synced != upstreams
	msg := sprintf("%s: the sync entries of the zot configuration fetch from %v, local/mirror/registries lists %v", [label, synced, upstreams])
}

deny contains msg if {
	is_object(zot)
	object.get(object.get(zot, "storage", {}), "rootDirectory", null) != storage_root
	msg := sprintf("%s: storage.rootDirectory must be %s, where local/scripts/mirror.sh mounts the volume of the mirror, outside the project tree", [label, storage_root])
}

deny contains msg if {
	some key, _ in object.get(zot, "storage", {})
	not key in {"rootDirectory", "dedupe", "gc"}
	msg := sprintf("%s: storage holds %s; retention or another storage stays off until [SECU] reviews it (ADR-011, condition 5)", [label, key])
}

deny contains msg if {
	is_object(zot)
	object.get(object.get(zot, "storage", {}), "gc", null) != false
	msg := sprintf("%s: storage.gc must be false: task mirror:purge empties the volume (ADR-011, condition 5)", [label])
}

deny contains msg if {
	some key, _ in object.get(zot, "http", {})
	not key in {"address", "port", "compat", "accessControl"}
	msg := sprintf("%s: http holds %s; the mirror has no authentication or TLS to configure, and accessControl alone, for the anonymous policy (ADR-011, condition 13)", [label, key])
}

# zot 2.1.23 reads accessControl under http (pkg/api/config/config.go,
# HTTPConfig, field accessControl). Without authentication, its presence
# alone turns on the "anonymous policy only" access control (pkg/api/routes.go,
# lines 127 to 144): an anonymous client gets the actions of
# anonymousPolicy on the repositories that match, and nothing else. The
# pattern ** matches every repository, and read is the one action the node
# needs. create, update and delete stay out, as does any other key: a
# defaultPolicy, an adminPolicy or a second pattern would be a right to write
# that the mirror has no one to check (R-34).
read_only_access := {"repositories": {"**": {"anonymousPolicy": ["read"]}}}

deny contains msg if {
	is_object(zot)
	object.get(object.get(zot, "http", {}), "accessControl", null) != read_only_access
	msg := sprintf("%s: http.accessControl must be %v, the anonymous policy that grants read on every repository and nothing else, so that no pod of the cluster writes to the mirror (ADR-011, complement of 2026-11-26; tasks.md, gaps 29 and 98)", [label, read_only_access])
}

credential_keys := {"credentialsfile", "password", "username", "htpasswd", "token", "secret", "auth", "accesscontrol", "bearer", "ldap", "openid"}

# The key http.accessControl is the policy above, which no credential fits;
# every key under it, and every other key of the file, is read as before.
deny contains msg if {
	walk(zot, [path, _])
	count(path) > 0
	path != ["http", "accessControl"]
	key := path[count(path) - 1]
	is_string(key)
	lower(key) in credential_keys
	msg := sprintf("%s: the zot configuration holds %v; no credential goes in the mirror (ADR-011, condition 13)", [label, path])
}

# The hosts.toml files: one per listed registry, the mirror with pull alone.

mirror_url := sprintf("http://%s:%s", [data.mirror_name, object.get(object.get(zot, "http", {}), "port", "")])

found_namespaces := {namespace | some namespace, _ in hosts_files}

deny contains msg if {
	found_namespaces != listed
	msg := sprintf("%s: local/mirror/certs.d holds hosts.toml for %v, local/mirror/registries lists %v", [label, found_namespaces, listed])
}

deny contains msg if {
	some namespace, file in hosts_files
	some key, _ in file.contents
	not key in {"server", "host"}
	msg := sprintf("%s: %s holds %s; only server and host are expected, and no header, certificate or skip_verify", [label, file.path, key])
}

deny contains msg if {
	some namespace, file in hosts_files
	server := object.get(file.contents, "server", "https://")
	not startswith(server, "https://")
	msg := sprintf("%s: %s sends the fallback to %v, not to an https upstream", [label, file.path, server])
}

deny contains msg if {
	some namespace, file in hosts_files
	hosts := {host | some host, _ in object.get(file.contents, "host", {})}
	hosts != {mirror_url}
	msg := sprintf("%s: %s declares the hosts %v; the mirror %s alone is expected", [label, file.path, hosts, mirror_url])
}

deny contains msg if {
	some namespace, file in hosts_files
	some host, settings in object.get(file.contents, "host", {})
	some key, _ in settings
	key != "capabilities"
	msg := sprintf("%s: %s gives the host %s the setting %s; only capabilities is expected", [label, file.path, host, key])
}

deny contains msg if {
	some namespace, file in hosts_files
	some host, settings in object.get(file.contents, "host", {})
	object.get(settings, "capabilities", null) != ["pull"]
	msg := sprintf("%s: %s gives %s the capabilities %v; pull alone is expected, a public mirror is never trusted to resolve (ADR-011, condition 1)", [label, file.path, host, object.get(settings, "capabilities", null)])
}

# The kind configuration: containerd reads the versioned hosts, read-only.

kind_config := file.contents if {
	count(kind_files) == 1
	some file in kind_files
}

deny contains msg if {
	is_object(kind_config)
	not some_patch_sets_config_path
	msg := sprintf("%s: no containerdConfigPatches entry sets %s", [label, config_path_line])
}

some_patch_sets_config_path if {
	some patch in object.get(kind_config, "containerdConfigPatches", [])
	contains(patch, config_path_line)
}

deny contains msg if {
	some i, node in object.get(kind_config, "nodes", [])
	not mounts_certs(node)
	msg := sprintf("%s: nodes[%v] must mount %s at %s, readOnly: true", [label, i, certs_source, certs_dir])
}

mounts_certs(node) if {
	some mount in object.get(node, "extraMounts", [])
	mount.hostPath == certs_source
	mount.containerPath == certs_dir
	mount.readOnly == true
}
