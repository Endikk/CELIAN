# Tests of S11 (cache_layer.rego), run by `conftest verify`.
package cache_layer

image := "docker.io/valkey/valkey:9.1.4-alpine@sha256:56729e68bdda139cbd3f6a2538683dc3523325fc5711ea1a379938f1b37893f0"

container_security := {
	"allowPrivilegeEscalation": false,
	"readOnlyRootFilesystem": true,
	"capabilities": {"drop": ["ALL"]},
}

pod_security := {
	"runAsNonRoot": true,
	"runAsUser": 999,
	"runAsGroup": 1000,
	"fsGroup": 1000,
	"seccompProfile": {"type": "RuntimeDefault"},
}

valid_script := concat("\n", [
	"#!/bin/sh",
	"set -eu",
	"{",
	`  echo 'save ""'`,
	"  echo 'appendonly no'",
	"  echo 'protected-mode yes'",
	"  echo 'maxmemory 64mb'",
	"  echo 'maxmemory-policy allkeys-lru'",
	"  echo 'enable-protected-configs no'",
	"  echo 'enable-debug-command no'",
	"  echo 'enable-module-command no'",
	`  printf 'user default on #%s ~* &* +@all -@admin -@scripting -acl -migrate -move -restore-asking -swapdb -xsetid\n' "$hash"`,
	`} >"$conf"`,
	"",
])

valid_deployment := {
	"apiVersion": "apps/v1",
	"kind": "Deployment",
	"metadata": {"name": "cache", "namespace": "saas-b2b"},
	"spec": {
		"replicas": 1,
		"selector": {"matchLabels": {"app.kubernetes.io/name": "cache"}},
		"template": {
			"metadata": {"labels": {"app.kubernetes.io/name": "cache"}},
			"spec": {
				"automountServiceAccountToken": false,
				"enableServiceLinks": false,
				"securityContext": pod_security,
				"initContainers": [{
					"name": "config",
					"image": image,
					"command": ["sh", "/opt/cache-init/write-config.sh"],
					"securityContext": container_security,
					"volumeMounts": [
						{"name": "cache-auth", "mountPath": "/run/secrets/cache-auth", "readOnly": true},
						{"name": "config", "mountPath": "/etc/cache"},
						{"name": "config-writer", "mountPath": "/opt/cache-init", "readOnly": true},
					],
				}],
				"containers": [{
					"name": "cache",
					"image": image,
					"args": ["valkey-server", "/etc/cache/cache.conf"],
					"ports": [{"name": "resp", "containerPort": 6379}],
					"resources": {"requests": {"memory": "64Mi", "cpu": "25m"}, "limits": {"memory": "128Mi"}},
					"securityContext": container_security,
					"volumeMounts": [
						{"name": "config", "mountPath": "/etc/cache", "readOnly": true},
						{"name": "data", "mountPath": "/data"},
					],
				}],
				"volumes": [
					{"name": "cache-auth", "secret": {"secretName": "cache-auth", "defaultMode": 288}},
					{"name": "config", "emptyDir": {"medium": "Memory", "sizeLimit": "1Mi"}},
					{"name": "data", "emptyDir": {"sizeLimit": "16Mi"}},
					{"name": "config-writer", "configMap": {"name": "cache-config-writer-abc123", "defaultMode": 292}},
				],
			},
		},
	},
}

service := {
	"apiVersion": "v1",
	"kind": "Service",
	"metadata": {"name": "cache", "namespace": "saas-b2b"},
	"spec": {
		"type": "ClusterIP",
		"selector": {"app.kubernetes.io/name": "cache"},
		"ports": [{"name": "resp", "port": 6379, "targetPort": "resp"}],
	},
}

network_policy := {
	"apiVersion": "networking.k8s.io/v1",
	"kind": "NetworkPolicy",
	"metadata": {"name": "cache", "namespace": "saas-b2b"},
	"spec": {
		"podSelector": {"matchLabels": {"app.kubernetes.io/name": "cache"}},
		"policyTypes": ["Ingress", "Egress"],
		"ingress": [{
			"from": [{"podSelector": {"matchExpressions": [{"key": "app.kubernetes.io/name", "operator": "In", "values": ["api", "cache-probe"]}]}}],
			"ports": [{"protocol": "TCP", "port": 6379}],
		}],
	},
}

config_map := {
	"apiVersion": "v1",
	"kind": "ConfigMap",
	"metadata": {"name": "cache-config-writer-abc123", "namespace": "saas-b2b"},
	"data": {"write-config.sh": valid_script},
}

job := {
	"apiVersion": "batch/v1",
	"kind": "Job",
	"metadata": {"name": "cache-probe", "namespace": "saas-b2b"},
	"spec": {
		"backoffLimit": 0,
		"template": {
			"metadata": {"labels": {"app.kubernetes.io/name": "cache-probe"}},
			"spec": {
				"restartPolicy": "Never",
				"automountServiceAccountToken": false,
				"enableServiceLinks": false,
				"securityContext": pod_security,
				"containers": [{
					"name": "probe",
					"image": image,
					"command": ["sh", "-c", "valkey-cli -h cache -p 6379 ping"],
					"env": [{"name": "VALKEYCLI_AUTH", "valueFrom": {"secretKeyRef": {"name": "cache-auth", "key": "password"}}}],
					"securityContext": container_security,
				}],
			},
		},
	},
}

files(objs) := [{"path": "rendered.yaml", "contents": obj} | some obj in objs]

valid_objects := [valid_deployment, service, network_policy, config_map, job]

accepted(objs) if {
	msgs := deny with input as files(objs)
	count(msgs) == 0
}

denied_with(objs, fragment) if {
	msgs := deny with input as files(objs)
	some msg in msgs
	contains(msg, fragment)
}

# One object changed by a JSON patch, the others as they are.
with_patch(obj, ops) := array.concat([json.patch(obj, ops)], [o | some o in valid_objects; o != obj])

server_path := "/spec/template/spec/containers/0"

init_path := "/spec/template/spec/initContainers/0"

test_s11_accepts_the_valid_layer if {
	accepted(valid_objects)
}

test_s11_rejects_a_missing_network_policy if {
	denied_with([valid_deployment, service, config_map, job], "expected one NetworkPolicy cache")
}

test_s11_rejects_a_missing_probe_job if {
	denied_with([valid_deployment, service, network_policy, config_map], "expected one Job cache-probe")
}

test_s11_rejects_a_secret_in_the_layer if {
	secret := {"apiVersion": "v1", "kind": "Secret", "metadata": {"name": "cache-auth"}, "stringData": {"password": "x"}}
	denied_with(array.concat(valid_objects, [secret]), "Secret cache-auth has no place in the cache layer")
}

test_s11_rejects_env_on_the_cache_container if {
	ops := [{"op": "add", "path": sprintf("%s/env", [server_path]), "value": [{"name": "VALKEY_EXTRA_FLAGS", "value": "--loglevel debug"}]}]
	denied_with(with_patch(valid_deployment, ops), "the container cache sets env")
}

test_s11_rejects_env_from_on_the_cache_container if {
	ops := [{"op": "add", "path": sprintf("%s/envFrom", [server_path]), "value": [{"secretRef": {"name": "cache-auth"}}]}]
	denied_with(with_patch(valid_deployment, ops), "the container cache sets envFrom")
}

test_s11_rejects_a_password_option_in_the_arguments if {
	ops := [{"op": "replace", "path": sprintf("%s/args", [server_path]), "value": ["valkey-server", "--requirepass", "x"]}]
	denied_with(with_patch(valid_deployment, ops), "passes a password option")
}

test_s11_rejects_a_password_option_inside_a_shell_script if {
	ops := [{"op": "replace", "path": "/spec/template/spec/containers/0/command", "value": ["sh", "-c", "valkey-cli -h cache -a secret ping"]}]
	denied_with(with_patch(job, ops), "passes a password option")
}

test_s11_rejects_requirepass_anywhere if {
	script := concat("\n", [valid_script, "echo 'requirepass x'"])
	ops := [{"op": "replace", "path": "/data/write-config.sh", "value": script}]
	denied_with(with_patch(config_map, ops), "holds requirepass or rename-command")
}

test_s11_rejects_rename_command if {
	script := concat("\n", [valid_script, "echo 'rename-command CONFIG \"\"'"])
	ops := [{"op": "replace", "path": "/data/write-config.sh", "value": script}]
	denied_with(with_patch(config_map, ops), "holds requirepass or rename-command")
}

test_s11_rejects_a_secret_mounted_in_the_server if {
	mount := {"name": "cache-auth", "mountPath": "/run/secrets/cache-auth", "readOnly": true}
	ops := [{"op": "add", "path": sprintf("%s/volumeMounts/-", [server_path]), "value": mount}]
	denied_with(with_patch(valid_deployment, ops), "the container cache mounts the Secret volume cache-auth")
}

test_s11_rejects_an_init_container_without_the_secret if {
	ops := [{"op": "remove", "path": sprintf("%s/volumeMounts/0", [init_path])}]
	denied_with(with_patch(valid_deployment, ops), "must mount the Secret volume of cache-auth")
}

test_s11_rejects_another_secret if {
	ops := [{"op": "replace", "path": "/spec/template/spec/volumes/0/secret/secretName", "value": "db-auth"}]
	denied_with(with_patch(valid_deployment, ops), "reads db-auth")
}

test_s11_rejects_a_missing_uid if {
	ops := [{"op": "remove", "path": "/spec/template/spec/securityContext/runAsUser"}]
	denied_with(with_patch(valid_deployment, ops), "securityContext.runAsUser to 999")
}

test_s11_rejects_another_gid if {
	ops := [{"op": "replace", "path": "/spec/template/spec/securityContext/runAsGroup", "value": 0}]
	denied_with(with_patch(valid_deployment, ops), "securityContext.runAsGroup to 1000")
}

test_s11_rejects_a_mounted_token if {
	ops := [{"op": "replace", "path": "/spec/template/spec/automountServiceAccountToken", "value": true}]
	denied_with(with_patch(valid_deployment, ops), "automountServiceAccountToken to false")
}

test_s11_rejects_service_links if {
	ops := [{"op": "remove", "path": "/spec/template/spec/enableServiceLinks"}]
	denied_with(with_patch(job, ops), "enableServiceLinks to false")
}

test_s11_rejects_a_writable_root if {
	ops := [{"op": "replace", "path": sprintf("%s/securityContext/readOnlyRootFilesystem", [init_path]), "value": false}]
	denied_with(with_patch(valid_deployment, ops), "container config of Deployment cache must set securityContext.readOnlyRootFilesystem to true")
}

test_s11_rejects_kept_capabilities if {
	ops := [{"op": "replace", "path": sprintf("%s/securityContext/capabilities", [server_path]), "value": {"drop": ["NET_RAW"]}}]
	denied_with(with_patch(valid_deployment, ops), "must drop every capability")
}

test_s11_rejects_a_container_that_sets_its_user if {
	ops := [{"op": "add", "path": sprintf("%s/securityContext/runAsUser", [server_path]), "value": 0}]
	denied_with(with_patch(valid_deployment, ops), "sets securityContext.runAsUser")
}

test_s11_rejects_an_image_by_tag_alone if {
	ops := [{"op": "replace", "path": sprintf("%s/image", [server_path]), "value": "docker.io/valkey/valkey:9.1.4-alpine"}]
	denied_with(with_patch(valid_deployment, ops), "by tag and digest")
}

test_s11_rejects_the_debian_variant if {
	ops := [{"op": "replace", "path": sprintf("%s/image", [init_path]), "value": "docker.io/valkey/valkey:9.1.4-trixie@sha256:3ab0eca823ebbf0fe352476ebac330ac9e5f14b592b9a954eab296d341e81b0e"}]
	denied_with(with_patch(valid_deployment, ops), "Alpine variant")
}

test_s11_rejects_two_images if {
	other := "docker.io/valkey/valkey:9.1.3-alpine@sha256:0000000000000000000000000000000000000000000000000000000000000000"
	ops := [{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": other}]
	denied_with(with_patch(job, ops), "the cache layer runs 2 images")
}

test_s11_rejects_a_persistent_volume if {
	ops := [{"op": "replace", "path": "/spec/template/spec/volumes/2", "value": {"name": "data", "persistentVolumeClaim": {"claimName": "cache"}}}]
	denied_with(with_patch(valid_deployment, ops), "is a persistentVolumeClaim")
}

test_s11_rejects_an_unbounded_data_volume if {
	ops := [{"op": "replace", "path": "/spec/template/spec/volumes/2/emptyDir", "value": {}}]
	denied_with(with_patch(valid_deployment, ops), "/data must be an emptyDir bounded by sizeLimit")
}

test_s11_rejects_other_requests if {
	ops := [{"op": "replace", "path": sprintf("%s/resources/requests/memory", [server_path]), "value": "128Mi"}]
	denied_with(with_patch(valid_deployment, ops), "resources.requests.memory to 64Mi")
}

test_s11_rejects_a_missing_memory_limit if {
	ops := [{"op": "remove", "path": sprintf("%s/resources/limits/memory", [server_path])}]
	denied_with(with_patch(valid_deployment, ops), "resources.limits.memory to 128Mi")
}

test_s11_rejects_a_cpu_limit if {
	ops := [{"op": "add", "path": sprintf("%s/resources/limits/cpu", [server_path]), "value": "100m"}]
	denied_with(with_patch(valid_deployment, ops), "sets a CPU limit")
}

test_s11_rejects_two_replicas if {
	ops := [{"op": "replace", "path": "/spec/replicas", "value": 2}]
	denied_with(with_patch(valid_deployment, ops), "runs 2 replicas")
}

test_s11_rejects_another_server_command if {
	ops := [{"op": "add", "path": sprintf("%s/command", [server_path]), "value": ["valkey-server"]}]
	denied_with(with_patch(valid_deployment, ops), "must not set command")
}

test_s11_rejects_a_missing_maxmemory if {
	ops := [{"op": "replace", "path": "/data/write-config.sh", "value": replace(valid_script, "  echo 'maxmemory 64mb'\n", "")}]
	denied_with(with_patch(config_map, ops), "does not write the line maxmemory 64mb")
}

test_s11_rejects_another_eviction_policy if {
	ops := [{"op": "replace", "path": "/data/write-config.sh", "value": replace(valid_script, "allkeys-lru", "volatile-lru")}]
	denied_with(with_patch(config_map, ops), "does not write the line maxmemory-policy allkeys-lru")
}

test_s11_rejects_persistence if {
	ops := [{"op": "replace", "path": "/data/write-config.sh", "value": replace(valid_script, "appendonly no", "appendonly yes")}]
	denied_with(with_patch(config_map, ops), "does not write the line appendonly no")
}

test_s11_rejects_the_debug_command if {
	ops := [{"op": "replace", "path": "/data/write-config.sh", "value": replace(valid_script, "enable-debug-command no", "enable-debug-command local")}]
	denied_with(with_patch(config_map, ops), "does not write the line enable-debug-command no")
}

test_s11_rejects_an_acl_line_without_the_refusals if {
	ops := [{"op": "replace", "path": "/data/write-config.sh", "value": replace(valid_script, " -swapdb", "")}]
	denied_with(with_patch(config_map, ops), "does not write the ACL line")
}

test_s11_rejects_a_cleartext_password_rule if {
	script := replace(valid_script, "on #%s", "on >%s")
	ops := [{"op": "replace", "path": "/data/write-config.sh", "value": script}]
	denied_with(with_patch(config_map, ops), "holds a > rule")
}

test_s11_rejects_nopass if {
	ops := [{"op": "replace", "path": "/data/write-config.sh", "value": concat("\n", [valid_script, "echo 'user default nopass'"])}]
	denied_with(with_patch(config_map, ops), "names nopass")
}

test_s11_rejects_a_node_port_service if {
	ops := [{"op": "replace", "path": "/spec/type", "value": "NodePort"}]
	denied_with(with_patch(service, ops), "is of type NodePort")
}

test_s11_rejects_a_fixed_node_port if {
	ops := [{"op": "add", "path": "/spec/ports/0/nodePort", "value": 30379}]
	denied_with(with_patch(service, ops), "without nodePort")
}

test_s11_rejects_an_open_ingress if {
	ops := [{"op": "replace", "path": "/spec/ingress/0/from", "value": [{"podSelector": {}}]}]
	denied_with(with_patch(network_policy, ops), "api or cache-probe alone")
}

test_s11_rejects_an_ingress_from_another_namespace if {
	peer := {"namespaceSelector": {}, "podSelector": {"matchExpressions": [{"key": "app.kubernetes.io/name", "operator": "In", "values": ["api", "cache-probe"]}]}}
	ops := [{"op": "replace", "path": "/spec/ingress/0/from", "value": [peer]}]
	denied_with(with_patch(network_policy, ops), "api or cache-probe alone")
}

test_s11_rejects_an_egress if {
	ops := [{"op": "add", "path": "/spec/egress", "value": [{"to": [{"ipBlock": {"cidr": "0.0.0.0/0"}}]}]}]
	denied_with(with_patch(network_policy, ops), "admits an egress")
}

test_s11_rejects_a_policy_without_egress_isolation if {
	ops := [{"op": "replace", "path": "/spec/policyTypes", "value": ["Ingress"]}]
	denied_with(with_patch(network_policy, ops), "isolate the cache pod for Ingress and Egress")
}

test_s11_rejects_a_probe_without_its_label if {
	ops := [{"op": "replace", "path": "/spec/template/metadata/labels", "value": {"app.kubernetes.io/name": "other"}}]
	denied_with(with_patch(job, ops), "must carry the label app.kubernetes.io/name: cache-probe")
}

test_s11_rejects_a_probe_password_by_value if {
	ops := [{"op": "replace", "path": "/spec/template/spec/containers/0/env", "value": [{"name": "VALKEYCLI_AUTH", "value": "x"}]}]
	denied_with(with_patch(job, ops), "must read the password by secretKeyRef")
}
