# Tests of S13 (mirror_config.rego), run by `conftest verify`.
package mirror_config

registries := [{"namespace": "docker.io", "upstream": "https://index.docker.io"}]

zot_config := {
	"distSpecVersion": "1.1.1",
	"storage": {"rootDirectory": "/var/lib/registry", "dedupe": false, "gc": false},
	"http": {"address": "0.0.0.0", "port": "5000", "compat": ["docker2s2"]},
	"log": {"level": "info"},
	"extensions": {"sync": {"enable": true, "registries": [{"urls": ["https://index.docker.io"], "onDemand": true, "tlsVerify": true}]}},
}

mirror_hosts := {"host": {"http://saas-b2b-mirror:5000": {"capabilities": ["pull"]}}}

kind_cluster := {
	"kind": "Cluster",
	"containerdConfigPatches": ["[plugins.\"io.containerd.grpc.v1.cri\".registry]\n  config_path = \"/etc/containerd/certs.d\""],
	"nodes": [{"role": "control-plane", "extraMounts": [{"hostPath": "local/mirror/certs.d", "containerPath": "/etc/containerd/certs.d", "readOnly": true}]}],
}

files(zot, hosts_by_namespace, kind) := array.concat(
	[
		{"path": "local/mirror/zot/config.json", "contents": zot},
		{"path": "local/kind/cluster.yaml", "contents": kind},
	],
	[{"path": sprintf("local/mirror/certs.d/%s/hosts.toml", [namespace]), "contents": contents} | some namespace, contents in hosts_by_namespace],
)

valid_files := files(zot_config, {"docker.io": mirror_hosts}, kind_cluster)

checks(input_files) := msgs if {
	msgs := deny with input as input_files
		with data.registries as registries
		with data.mirror_name as "saas-b2b-mirror"
}

accepted(input_files) if count(checks(input_files)) == 0

denied_with(input_files, fragment) if {
	some msg in checks(input_files)
	contains(msg, fragment)
}

with_sync(entry) := object.union(zot_config, {"extensions": {"sync": {"enable": true, "registries": [entry]}}})

sync_entry := {"urls": ["https://index.docker.io"], "onDemand": true, "tlsVerify": true}

test_s13_accepts_the_valid_files if {
	accepted(valid_files)
}

test_s13_accepts_the_files_under_the_golden_repo_of_celian if {
	prefixed := [object.union(file, {"path": concat("", ["golden/saas-b2b/", file.path])}) | some file in valid_files]
	accepted(prefixed)
}

test_s13_rejects_a_missing_zot_config if {
	denied_with(array.slice(valid_files, 1, count(valid_files)), "expected one local/mirror/zot/config.json")
}

test_s13_rejects_another_extension if {
	zot := object.union(zot_config, {"extensions": {"sync": zot_config.extensions.sync, "search": {"enable": true}}})
	denied_with(files(zot, {"docker.io": mirror_hosts}, kind_cluster), "must enable the extension sync and no other")
}

test_s13_rejects_a_disabled_sync if {
	zot := object.union(zot_config, {"extensions": {"sync": {"enable": false, "registries": [sync_entry]}}})
	denied_with(files(zot, {"docker.io": mirror_hosts}, kind_cluster), "extensions.sync.enable must be true")
}

test_s13_rejects_a_credentials_file if {
	zot := object.union(zot_config, {"extensions": {"sync": {"enable": true, "credentialsFile": "/etc/zot/auth.json", "registries": [sync_entry]}}})
	denied_with(files(zot, {"docker.io": mirror_hosts}, kind_cluster), "no credential goes in the mirror")
}

test_s13_rejects_http_authentication if {
	zot := object.union(zot_config, {"http": {"address": "0.0.0.0", "port": "5000", "auth": {"htpasswd": {"path": "/etc/zot/htpasswd"}}}})
	denied_with(files(zot, {"docker.io": mirror_hosts}, kind_cluster), "http holds auth")
}

test_s13_rejects_a_sync_entry_that_polls if {
	denied_with(files(with_sync(object.union(sync_entry, {"onDemand": false})), {"docker.io": mirror_hosts}, kind_cluster), "onDemand must be true")
}

test_s13_rejects_a_sync_entry_without_tls_verification if {
	denied_with(files(with_sync(object.union(sync_entry, {"tlsVerify": false})), {"docker.io": mirror_hosts}, kind_cluster), "tlsVerify must be true")
}

test_s13_rejects_a_sync_entry_with_content_filters if {
	denied_with(files(with_sync(object.union(sync_entry, {"content": [{"prefix": "/library/**"}]})), {"docker.io": mirror_hosts}, kind_cluster), "holds content")
}

test_s13_rejects_an_upstream_absent_from_the_list if {
	denied_with(files(with_sync(object.union(sync_entry, {"urls": ["https://ghcr.io"]})), {"docker.io": mirror_hosts}, kind_cluster), "local/mirror/registries lists")
}

test_s13_rejects_storage_inside_the_container_root if {
	zot := object.union(zot_config, {"storage": {"rootDirectory": "/tmp/zot", "dedupe": false, "gc": false}})
	denied_with(files(zot, {"docker.io": mirror_hosts}, kind_cluster), "storage.rootDirectory must be /var/lib/registry")
}

test_s13_rejects_retention if {
	zot := object.union(zot_config, {"storage": {"rootDirectory": "/var/lib/registry", "gc": false, "retention": {"dryRun": true}}})
	denied_with(files(zot, {"docker.io": mirror_hosts}, kind_cluster), "storage holds retention")
}

test_s13_rejects_the_garbage_collector if {
	zot := object.union(zot_config, {"storage": {"rootDirectory": "/var/lib/registry", "gc": true}})
	denied_with(files(zot, {"docker.io": mirror_hosts}, kind_cluster), "storage.gc must be false")
}

test_s13_rejects_a_missing_hosts_file if {
	denied_with(files(zot_config, {}, kind_cluster), "local/mirror/certs.d holds hosts.toml for set()")
}

test_s13_rejects_a_hosts_file_for_an_unlisted_registry if {
	denied_with(files(zot_config, {"docker.io": mirror_hosts, "ghcr.io": mirror_hosts}, kind_cluster), "local/mirror/certs.d holds hosts.toml for")
}

test_s13_rejects_the_resolve_capability if {
	two := {"host": {"http://saas-b2b-mirror:5000": {"capabilities": ["pull", "resolve"]}}}
	denied_with(files(zot_config, {"docker.io": two}, kind_cluster), "pull alone is expected")
}

test_s13_rejects_the_push_capability if {
	push := {"host": {"http://saas-b2b-mirror:5000": {"capabilities": ["pull", "push"]}}}
	denied_with(files(zot_config, {"docker.io": push}, kind_cluster), "pull alone is expected")
}

test_s13_rejects_a_host_without_capabilities if {
	none := {"host": {"http://saas-b2b-mirror:5000": {}}}
	denied_with(files(zot_config, {"docker.io": none}, kind_cluster), "gives http://saas-b2b-mirror:5000 the capabilities null")
}

test_s13_rejects_another_mirror if {
	other := {"host": {"http://registry.example:5000": {"capabilities": ["pull"]}}}
	denied_with(files(zot_config, {"docker.io": other}, kind_cluster), "the mirror http://saas-b2b-mirror:5000 alone is expected")
}

test_s13_rejects_a_second_host if {
	two := {"host": {"http://saas-b2b-mirror:5000": {"capabilities": ["pull"]}, "https://registry.example": {"capabilities": ["pull"]}}}
	denied_with(files(zot_config, {"docker.io": two}, kind_cluster), "the mirror http://saas-b2b-mirror:5000 alone is expected")
}

test_s13_rejects_a_header_on_the_host if {
	header := {"host": {"http://saas-b2b-mirror:5000": {"capabilities": ["pull"], "header": {"Authorization": "Basic x"}}}}
	denied_with(files(zot_config, {"docker.io": header}, kind_cluster), "the setting header")
}

test_s13_rejects_skip_verify_at_the_top if {
	top := object.union(mirror_hosts, {"skip_verify": true})
	denied_with(files(zot_config, {"docker.io": top}, kind_cluster), "holds skip_verify")
}

test_s13_rejects_a_plain_http_fallback if {
	server := object.union(mirror_hosts, {"server": "http://registry-1.docker.io"})
	denied_with(files(zot_config, {"docker.io": server}, kind_cluster), "not to an https upstream")
}

test_s13_accepts_an_https_fallback if {
	server := object.union(mirror_hosts, {"server": "https://registry-1.docker.io"})
	accepted(files(zot_config, {"docker.io": server}, kind_cluster))
}

test_s13_rejects_a_kind_config_without_config_path if {
	kind := object.remove(kind_cluster, {"containerdConfigPatches"})
	denied_with(files(zot_config, {"docker.io": mirror_hosts}, kind), "no containerdConfigPatches entry sets")
}

test_s13_rejects_a_writable_certs_mount if {
	kind := object.union(kind_cluster, {"nodes": [{"role": "control-plane", "extraMounts": [{"hostPath": "local/mirror/certs.d", "containerPath": "/etc/containerd/certs.d"}]}]})
	denied_with(files(zot_config, {"docker.io": mirror_hosts}, kind), "nodes[0] must mount local/mirror/certs.d at /etc/containerd/certs.d, readOnly: true")
}

test_s13_rejects_a_node_without_the_certs_mount if {
	kind := object.union(kind_cluster, {"nodes": [{"role": "control-plane"}]})
	denied_with(files(zot_config, {"docker.io": mirror_hosts}, kind), "nodes[0] must mount")
}

test_s13_rejects_an_empty_list if {
	msgs := deny with input as valid_files with data.registries as [] with data.mirror_name as "saas-b2b-mirror"
	some msg in msgs
	contains(msg, "lists no registry")
}

test_s13_names_its_requirements_in_each_message if {
	two := {"host": {"http://saas-b2b-mirror:5000": {"capabilities": ["pull", "resolve"]}}}
	msgs := checks(files(zot_config, {"docker.io": two}, kind_cluster))
	count(msgs) == 1
	every msg in msgs {
		startswith(msg, "S13 (FR-008, FR-016;")
	}
}
