# S12: Postgres of the local layer keeps the conditions of ADR-012 (spec
# 001, plan, matrix S12; FR-017; R-20; R-35):
# - condition 1: one StatefulSet postgres on the official image, Debian
#   variant, by tag and digest; UID and GID 999, runAsNonRoot, seccomp
#   RuntimeDefault, no service account token, no host namespace nor
#   hostPath; every container without privilege escalation, with every
#   capability dropped and none added, a read-only root filesystem
#   (research RS-12);
# - condition 2: the superuser comes from the files of the Secret
#   db-superuser (POSTGRES_USER_FILE, POSTGRES_PASSWORD_FILE), never from a
#   value nor from an environment variable fed by a Secret; initdb gets
#   --auth-local=scram-sha-256 and --auth-host=scram-sha-256; the word trust
#   appears in no environment value, command, argument, nor script of the
#   layer, and POSTGRES_HOST_AUTH_METHOD is never set;
# - condition 8: db-superuser is mounted by the StatefulSet postgres alone,
#   and the rendered common layer names it nowhere;
# - R-35: the volume of the data is the volume claim template data, mounted
#   at /var/lib/postgresql, the VOLUME of the image from PostgreSQL 18 on,
#   and PGDATA, when set, lies inside it; the Secrets are mounted read-only,
#   neither writable nor readable by others.
#
# Input: two renders given to `conftest test --combine` by
# local/tests/static/s12-postgres.sh, one entry per document with its path:
# local/k8s/lite (path ending in lite.yaml) and the common layer alone,
# k8s/overlays/local (path ending in common.yaml).
package postgres

label := "S12 (FR-017; ADR-012, conditions 1, 2 and 8; R-20, R-35)"

lite_file := `(^|/)lite\.yaml$`

common_file := `(^|/)common\.yaml$`

superuser_secret := "db-superuser"

data_mount := "/var/lib/postgresql"

documents(pattern) := [doc |
	some file in input
	regex.match(pattern, file.path)
	doc := file.contents
	is_object(doc)
]

deny contains msg if {
	some pattern in [lite_file, common_file]
	count(documents(pattern)) == 0
	msg := sprintf("%s: no document of a render matching %s among the checked files", [label, pattern])
}

statefulsets := [doc |
	some doc in documents(lite_file)
	doc.kind == "StatefulSet"
	doc.metadata.name == "postgres"
]

deny contains msg if {
	count(documents(lite_file)) > 0
	count(statefulsets) != 1
	msg := sprintf("%s: the render of local/k8s/lite holds %d StatefulSet postgres, one expected", [label, count(statefulsets)])
}

pod(sts) := object.get(object.get(object.get(sts, "spec", {}), "template", {}), "spec", {})

containers(sts) := array.concat(object.get(pod(sts), "initContainers", []), object.get(pod(sts), "containers", []))

# Pod level.
pod_settings := [
	{"path": ["automountServiceAccountToken"], "value": false},
	{"path": ["securityContext", "runAsNonRoot"], "value": true},
	{"path": ["securityContext", "runAsUser"], "value": 999},
	{"path": ["securityContext", "runAsGroup"], "value": 999},
	{"path": ["securityContext", "fsGroup"], "value": 999},
	{"path": ["securityContext", "seccompProfile", "type"], "value": "RuntimeDefault"},
]

deny contains msg if {
	some sts in statefulsets
	some setting in pod_settings
	found := object.get(pod(sts), setting.path, null)
	found != setting.value
	msg := sprintf("%s: spec.template.spec.%s of the StatefulSet postgres is %v, %v expected", [label, concat(".", setting.path), found, setting.value])
}

deny contains msg if {
	some sts in statefulsets
	some field in ["hostNetwork", "hostPID", "hostIPC"]
	object.get(pod(sts), field, false) == true
	msg := sprintf("%s: the StatefulSet postgres sets %s", [label, field])
}

deny contains msg if {
	some sts in statefulsets
	some volume in object.get(pod(sts), "volumes", [])
	object.get(volume, "hostPath", null) != null
	msg := sprintf("%s: the volume %v of the StatefulSet postgres is a hostPath", [label, volume.name])
}

# Container level.
deny contains msg if {
	some sts in statefulsets
	some container in containers(sts)
	object.get(container, ["securityContext", "allowPrivilegeEscalation"], null) != false
	msg := sprintf("%s: the container %v of the StatefulSet postgres does not set allowPrivilegeEscalation to false", [label, container.name])
}

deny contains msg if {
	some sts in statefulsets
	some container in containers(sts)
	not "ALL" in object.get(container, ["securityContext", "capabilities", "drop"], [])
	msg := sprintf("%s: the container %v of the StatefulSet postgres does not drop ALL capabilities", [label, container.name])
}

deny contains msg if {
	some sts in statefulsets
	some container in containers(sts)
	count(object.get(container, ["securityContext", "capabilities", "add"], [])) > 0
	msg := sprintf("%s: the container %v of the StatefulSet postgres adds capabilities", [label, container.name])
}

deny contains msg if {
	some sts in statefulsets
	some container in containers(sts)
	object.get(container, ["securityContext", "privileged"], false) == true
	msg := sprintf("%s: the container %v of the StatefulSet postgres is privileged", [label, container.name])
}

deny contains msg if {
	some sts in statefulsets
	some container in containers(sts)
	object.get(container, ["securityContext", "readOnlyRootFilesystem"], null) != true
	msg := sprintf("%s: the container %v of the StatefulSet postgres has a writable root filesystem (research RS-12)", [label, container.name])
}

deny contains msg if {
	some sts in statefulsets
	some container in containers(sts)
	user := object.get(container, ["securityContext", "runAsUser"], 999)
	user != 999
	msg := sprintf("%s: the container %v of the StatefulSet postgres runs as %v, 999 expected", [label, container.name, user])
}

deny contains msg if {
	some sts in statefulsets
	some container in containers(sts)
	object.get(container, ["securityContext", "runAsNonRoot"], true) != true
	msg := sprintf("%s: the container %v of the StatefulSet postgres lifts runAsNonRoot", [label, container.name])
}

# The image.
postgres_containers(sts) := [c | some c in object.get(pod(sts), "containers", []); c.name == "postgres"]

deny contains msg if {
	some sts in statefulsets
	count(postgres_containers(sts)) != 1
	msg := sprintf("%s: the StatefulSet postgres has %d container named postgres, one expected", [label, count(postgres_containers(sts))])
}

deny contains msg if {
	some sts in statefulsets
	some container in postgres_containers(sts)
	not regex.match(`^docker\.io/library/postgres:[0-9]+\.[0-9]+-trixie@sha256:[a-f0-9]{64}$`, object.get(container, "image", ""))
	msg := sprintf("%s: the container postgres runs %v; the official image, Debian variant, by tag and digest is expected (docker.io/library/postgres:<major>.<minor>-trixie@sha256:...)", [label, object.get(container, "image", null)])
}

# The environment of the container postgres.
env_of(container) := {e.name: e | some e in object.get(container, "env", [])}

secret_mount_paths(sts, secret) := {m.mountPath |
	some volume in object.get(pod(sts), "volumes", [])
	object.get(volume, ["secret", "secretName"], null) == secret
	some container in postgres_containers(sts)
	some m in object.get(container, "volumeMounts", [])
	m.name == volume.name
}

deny contains msg if {
	some sts in statefulsets
	some container in postgres_containers(sts)
	some name in ["POSTGRES_USER_FILE", "POSTGRES_PASSWORD_FILE"]
	value := object.get(env_of(container), [name, "value"], null)
	not under_superuser_mount(sts, value)
	msg := sprintf("%s: %s of the container postgres is %v; a file of the Secret %s, mounted in the pod, is expected", [label, name, value, superuser_secret])
}

under_superuser_mount(sts, value) if {
	is_string(value)
	some path in secret_mount_paths(sts, superuser_secret)
	startswith(value, concat("", [path, "/"]))
}

deny contains msg if {
	some sts in statefulsets
	some container in postgres_containers(sts)
	some name in ["POSTGRES_PASSWORD", "POSTGRES_USER", "POSTGRES_HOST_AUTH_METHOD"]
	env_of(container)[name]
	msg := sprintf("%s: the container postgres sets %s; the superuser comes from the files of %s, and the method from POSTGRES_INITDB_ARGS", [label, name, superuser_secret])
}

deny contains msg if {
	some sts in statefulsets
	some container in containers(sts)
	some e in object.get(container, "env", [])
	object.get(e, ["valueFrom", "secretKeyRef"], null) != null
	msg := sprintf("%s: %v of the container %v reads a Secret into an environment variable; the Secrets are read as files", [label, e.name, container.name])
}

deny contains msg if {
	some sts in statefulsets
	some container in containers(sts)
	count(object.get(container, "envFrom", [])) > 0
	msg := sprintf("%s: the container %v of the StatefulSet postgres takes its environment from envFrom", [label, container.name])
}

deny contains msg if {
	some sts in statefulsets
	some container in postgres_containers(sts)
	args := object.get(env_of(container), ["POSTGRES_INITDB_ARGS", "value"], "")
	some flag in ["--auth-local=scram-sha-256", "--auth-host=scram-sha-256"]
	not flag in split(args, " ")
	msg := sprintf("%s: POSTGRES_INITDB_ARGS of the container postgres lacks %s", [label, flag])
}

# The word trust, in what reaches the container: environment values,
# commands, arguments, and the data of the ConfigMaps of the layer.
trust_pattern := `(?i)(^|[^a-z])trust([^a-z]|$)`

deny contains msg if {
	some sts in statefulsets
	some container in containers(sts)
	texts := array.concat(array.concat(object.get(container, "command", []), object.get(container, "args", [])), [v | some e in object.get(container, "env", []); v := object.get(e, "value", "")])
	some text in texts
	regex.match(trust_pattern, text)
	msg := sprintf("%s: the container %v of the StatefulSet postgres names the method trust: %v", [label, container.name, text])
}

deny contains msg if {
	some doc in documents(lite_file)
	doc.kind == "ConfigMap"
	some key, text in object.get(doc, "data", {})
	regex.match(trust_pattern, text)
	msg := sprintf("%s: %s of the ConfigMap %v names the method trust", [label, key, doc.metadata.name])
}

# The volume of the data.
claim_names(sts) := {c.metadata.name | some c in object.get(object.get(sts, "spec", {}), "volumeClaimTemplates", [])}

deny contains msg if {
	some sts in statefulsets
	some container in postgres_containers(sts)
	mounts := {m.mountPath | some m in object.get(container, "volumeMounts", []); m.name in claim_names(sts)}
	mounts != {data_mount}
	msg := sprintf("%s: the volume claim templates of the StatefulSet postgres are mounted at %v; %s alone is expected (R-35)", [label, mounts, data_mount])
}

deny contains msg if {
	some sts in statefulsets
	some container in postgres_containers(sts)
	pgdata := object.get(env_of(container), ["PGDATA", "value"], null)
	pgdata != null
	not startswith(pgdata, concat("", [data_mount, "/"]))
	msg := sprintf("%s: PGDATA of the container postgres is %v, outside %s (R-35)", [label, pgdata, data_mount])
}

# The Secrets: mounted read-only, mode without write bit and without the
# bits of the others (octal 0222 is decimal 146).
deny contains msg if {
	some sts in statefulsets
	some volume in object.get(pod(sts), "volumes", [])
	secret := object.get(volume, "secret", null)
	secret != null
	mode := object.get(secret, "defaultMode", 420)
	not private_mode(mode)
	msg := sprintf("%s: the Secret %v is mounted with the mode %v (decimal); no write bit and nothing for the others are expected, 0440 for example", [label, object.get(secret, "secretName", null), mode])
}

private_mode(mode) if {
	bits.and(mode, 146) == 0
	bits.and(mode, 7) == 0
}

deny contains msg if {
	some sts in statefulsets
	some volume in object.get(pod(sts), "volumes", [])
	object.get(volume, "secret", null) != null
	some container in containers(sts)
	some m in object.get(container, "volumeMounts", [])
	m.name == volume.name
	object.get(m, "readOnly", false) != true
	msg := sprintf("%s: the Secret volume %v is mounted writable in the container %v", [label, volume.name, container.name])
}

# Condition 8: db-superuser is named by the StatefulSet postgres alone, and
# nowhere in the common layer.
names_superuser(doc) if {
	walk(doc, [_, value])
	value == superuser_secret
}

deny contains msg if {
	some doc in documents(common_file)
	names_superuser(doc)
	msg := sprintf("%s: %v %v of the common layer names the Secret %s, which the application never reads", [label, object.get(doc, "kind", null), object.get(object.get(doc, "metadata", {}), "name", null), superuser_secret])
}

deny contains msg if {
	some doc in documents(lite_file)
	names_superuser(doc)
	not postgres_statefulset(doc)
	msg := sprintf("%s: %v %v names the Secret %s; the StatefulSet postgres alone mounts it", [label, object.get(doc, "kind", null), object.get(object.get(doc, "metadata", {}), "name", null), superuser_secret])
}

postgres_statefulset(doc) if {
	doc.kind == "StatefulSet"
	doc.metadata.name == "postgres"
}

# The Service that the application and task up reach.
deny contains msg if {
	count(documents(lite_file)) > 0
	count([doc |
		some doc in documents(lite_file)
		doc.kind == "Service"
		doc.metadata.name == "postgres"
		some port in object.get(object.get(doc, "spec", {}), "ports", [])
		port.port == 5432
	]) != 1
	msg := sprintf("%s: the render of local/k8s/lite has no Service postgres on port 5432", [label])
}
