# Tests of S12 (postgres.rego), run by `conftest verify`.
package postgres

image := "docker.io/library/postgres:18.7-trixie@sha256:eb63372c1e05c755f55fa30cbd07aecc443676fc6c0fa90b9002d01537841e1a"

container := {
	"name": "postgres",
	"image": image,
	"env": [
		{"name": "POSTGRES_USER_FILE", "value": "/run/secrets/db-superuser/username"},
		{"name": "POSTGRES_PASSWORD_FILE", "value": "/run/secrets/db-superuser/password"},
		{"name": "POSTGRES_INITDB_ARGS", "value": "--auth-local=scram-sha-256 --auth-host=scram-sha-256"},
	],
	"securityContext": {"allowPrivilegeEscalation": false, "readOnlyRootFilesystem": true, "capabilities": {"drop": ["ALL"]}},
	"volumeMounts": [
		{"name": "data", "mountPath": "/var/lib/postgresql"},
		{"name": "run", "mountPath": "/run/postgresql"},
		{"name": "db-superuser", "mountPath": "/run/secrets/db-superuser", "readOnly": true},
		{"name": "db-auth", "mountPath": "/run/secrets/db-auth", "readOnly": true},
	],
}

statefulset := {
	"apiVersion": "apps/v1",
	"kind": "StatefulSet",
	"metadata": {"name": "postgres", "namespace": "saas-b2b"},
	"spec": {
		"template": {"spec": {
			"automountServiceAccountToken": false,
			"securityContext": {"runAsNonRoot": true, "runAsUser": 999, "runAsGroup": 999, "fsGroup": 999, "seccompProfile": {"type": "RuntimeDefault"}},
			"containers": [container],
			"volumes": [
				{"name": "run", "emptyDir": {}},
				{"name": "db-superuser", "secret": {"secretName": "db-superuser", "defaultMode": 288}},
				{"name": "db-auth", "secret": {"secretName": "db-auth", "defaultMode": 288}},
			],
		}},
		"volumeClaimTemplates": [{"metadata": {"name": "data"}}],
	},
}

service := {"apiVersion": "v1", "kind": "Service", "metadata": {"name": "postgres"}, "spec": {"ports": [{"name": "postgres", "port": 5432}]}}

init_script := {"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": "postgres-init-abc"}, "data": {"10-app-role.sh": "CREATE ROLE app WITH LOGIN NOSUPERUSER"}}

gateway := {"apiVersion": "gateway.networking.k8s.io/v1", "kind": "Gateway", "metadata": {"name": "saas-b2b"}}

lite(sts) := [
	{"path": "/tmp/x/lite.yaml", "contents": sts},
	{"path": "/tmp/x/lite.yaml", "contents": service},
	{"path": "/tmp/x/lite.yaml", "contents": init_script},
	{"path": "/tmp/x/lite.yaml", "contents": gateway},
	{"path": "/tmp/x/common.yaml", "contents": gateway},
]

with_container(c) := json.patch(statefulset, [{"op": "replace", "path": "/spec/template/spec/containers/0", "value": c}])

patched(ops) := json.patch(statefulset, ops)

accepted(files) if {
	count(deny) == 0 with input as files
}

denied_with(files, fragment) if {
	msgs := deny with input as files
	some msg in msgs
	contains(msg, fragment)
}

test_s12_accepts_the_valid_statefulset if {
	accepted(lite(statefulset))
}

test_s12_rejects_a_missing_render if {
	denied_with([{"path": "/tmp/x/lite.yaml", "contents": statefulset}], "common")
}

test_s12_rejects_a_missing_statefulset if {
	denied_with(lite(service), "0 StatefulSet postgres")
}

test_s12_rejects_root if {
	denied_with(lite(patched([{"op": "replace", "path": "/spec/template/spec/securityContext/runAsUser", "value": 0}])), "runAsUser of the StatefulSet postgres is 0")
}

test_s12_rejects_a_missing_seccomp_profile if {
	denied_with(lite(patched([{"op": "remove", "path": "/spec/template/spec/securityContext/seccompProfile"}])), "seccompProfile.type")
}

test_s12_rejects_a_mounted_token if {
	denied_with(lite(patched([{"op": "remove", "path": "/spec/template/spec/automountServiceAccountToken"}])), "automountServiceAccountToken")
}

test_s12_rejects_the_host_network if {
	denied_with(lite(patched([{"op": "add", "path": "/spec/template/spec/hostNetwork", "value": true}])), "hostNetwork")
}

test_s12_rejects_a_host_path if {
	denied_with(lite(patched([{"op": "add", "path": "/spec/template/spec/volumes/-", "value": {"name": "host", "hostPath": {"path": "/"}}}])), "hostPath")
}

test_s12_rejects_privilege_escalation if {
	denied_with(lite(with_container(json.patch(container, [{"op": "remove", "path": "/securityContext/allowPrivilegeEscalation"}]))), "allowPrivilegeEscalation")
}

test_s12_rejects_kept_capabilities if {
	denied_with(lite(with_container(json.patch(container, [{"op": "replace", "path": "/securityContext/capabilities/drop", "value": ["NET_RAW"]}]))), "does not drop ALL")
}

test_s12_rejects_an_added_capability if {
	denied_with(lite(with_container(json.patch(container, [{"op": "add", "path": "/securityContext/capabilities/add", "value": ["CHOWN"]}]))), "adds capabilities")
}

test_s12_rejects_a_writable_root_filesystem if {
	denied_with(lite(with_container(json.patch(container, [{"op": "remove", "path": "/securityContext/readOnlyRootFilesystem"}]))), "writable root filesystem")
}

test_s12_rejects_an_init_container_as_root if {
	init := {"name": "chown", "image": image, "securityContext": {"allowPrivilegeEscalation": false, "readOnlyRootFilesystem": true, "capabilities": {"drop": ["ALL"]}, "runAsUser": 0}}
	denied_with(lite(patched([{"op": "add", "path": "/spec/template/spec/initContainers", "value": [init]}])), "runs as 0")
}

test_s12_rejects_the_image_by_tag if {
	denied_with(lite(with_container(object.union(container, {"image": "postgres:18.7-trixie"}))), "by tag and digest")
}

test_s12_rejects_the_alpine_variant if {
	alpine := "docker.io/library/postgres:18.7-alpine@sha256:eb63372c1e05c755f55fa30cbd07aecc443676fc6c0fa90b9002d01537841e1a"
	denied_with(lite(with_container(object.union(container, {"image": alpine}))), "Debian variant")
}

test_s12_rejects_a_password_in_a_value if {
	env := array.concat(container.env, [{"name": "POSTGRES_PASSWORD", "value": "x"}])
	denied_with(lite(with_container(object.union(container, {"env": env}))), "sets POSTGRES_PASSWORD")
}

test_s12_rejects_the_trust_method if {
	env := array.concat(container.env, [{"name": "POSTGRES_HOST_AUTH_METHOD", "value": "trust"}])
	denied_with(lite(with_container(object.union(container, {"env": env}))), "names the method trust")
}

test_s12_rejects_trust_in_the_initdb_arguments if {
	env := [
		container.env[0],
		container.env[1],
		{"name": "POSTGRES_INITDB_ARGS", "value": "--auth-local=trust --auth-host=scram-sha-256"},
	]
	denied_with(lite(with_container(object.union(container, {"env": env}))), "lacks --auth-local=scram-sha-256")
}

test_s12_rejects_trust_in_a_script if {
	files := array.concat(lite(statefulset), [{"path": "/tmp/x/lite.yaml", "contents": {"kind": "ConfigMap", "metadata": {"name": "hba"}, "data": {"20-hba.sh": "echo 'host all all all TRUST' >> pg_hba.conf"}}}])
	denied_with(files, "names the method trust")
}

test_s12_rejects_a_password_file_outside_the_superuser_secret if {
	env := [
		{"name": "POSTGRES_USER_FILE", "value": "/run/secrets/db-superuser/username"},
		{"name": "POSTGRES_PASSWORD_FILE", "value": "/run/secrets/db-auth/password"},
		container.env[2],
	]
	denied_with(lite(with_container(object.union(container, {"env": env}))), "POSTGRES_PASSWORD_FILE of the container postgres")
}

test_s12_rejects_a_missing_user_file if {
	env := [container.env[1], container.env[2]]
	denied_with(lite(with_container(object.union(container, {"env": env}))), "POSTGRES_USER_FILE of the container postgres is null")
}

test_s12_rejects_a_secret_in_an_environment_variable if {
	env := array.concat(container.env, [{"name": "APP_PASSWORD", "valueFrom": {"secretKeyRef": {"name": "db-auth", "key": "password"}}}])
	denied_with(lite(with_container(object.union(container, {"env": env}))), "reads a Secret into an environment variable")
}

test_s12_rejects_env_from if {
	denied_with(lite(with_container(object.union(container, {"envFrom": [{"secretRef": {"name": "db-auth"}}]}))), "envFrom")
}

test_s12_rejects_data_mounted_elsewhere if {
	mounts := array.concat([{"name": "data", "mountPath": "/var/lib/postgresql/data"}], array.slice(container.volumeMounts, 1, 4))
	denied_with(lite(with_container(object.union(container, {"volumeMounts": mounts}))), "R-35")
}

test_s12_rejects_pgdata_outside_the_volume if {
	env := array.concat(container.env, [{"name": "PGDATA", "value": "/data/pgdata"}])
	denied_with(lite(with_container(object.union(container, {"env": env}))), "PGDATA of the container postgres is /data/pgdata")
}

test_s12_rejects_a_secret_readable_by_others if {
	denied_with(lite(patched([{"op": "replace", "path": "/spec/template/spec/volumes/1/secret/defaultMode", "value": 420}])), "mode 420")
}

test_s12_rejects_a_writable_secret_mount if {
	mounts := array.concat(array.slice(container.volumeMounts, 0, 2), [{"name": "db-superuser", "mountPath": "/run/secrets/db-superuser"}, container.volumeMounts[3]])
	denied_with(lite(with_container(object.union(container, {"volumeMounts": mounts}))), "mounted writable")
}

test_s12_rejects_the_superuser_in_the_common_layer if {
	api := {"kind": "Deployment", "metadata": {"name": "api"}, "spec": {"template": {"spec": {"volumes": [{"name": "s", "secret": {"secretName": "db-superuser"}}]}}}}
	files := array.concat(lite(statefulset), [{"path": "/tmp/x/common.yaml", "contents": api}])
	denied_with(files, "Deployment api of the common layer names the Secret db-superuser")
}

test_s12_rejects_the_superuser_elsewhere_in_the_local_layer if {
	job := {"kind": "Job", "metadata": {"name": "migrate"}, "spec": {"template": {"spec": {"volumes": [{"name": "s", "secret": {"secretName": "db-superuser"}}]}}}}
	files := array.concat(lite(statefulset), [{"path": "/tmp/x/lite.yaml", "contents": job}])
	denied_with(files, "Job migrate names the Secret db-superuser")
}

test_s12_rejects_a_missing_service if {
	files := [f | some f in lite(statefulset); f.contents.kind != "Service"]
	denied_with(files, "no Service postgres on port 5432")
}
