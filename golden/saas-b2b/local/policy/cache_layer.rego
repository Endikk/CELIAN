# S11: the cache of the local layer, as ADR-015 wants it (spec 001, plan,
# matrix S11; ADR-006, condition 2; ADR-015, conditions 3 to 6, 10 and 15;
# research RS-11):
# - condition 3: the pod runs as UID 999 and GID 1000, non-root, seccomp
#   RuntimeDefault, no service account token, every container without
#   privilege escalation, with a read-only root and every capability
#   dropped; /data is an emptyDir bounded by sizeLimit; nothing persists;
# - condition 4: the init container alone mounts cache-auth; the
#   configuration it writes holds the ACL line with the SHA-256 of the
#   password, the explicit refusals, and the three enable-* at no, never a
#   requirepass, a rename-command, a nopass or a cleartext password;
# - condition 5: no env and no envFrom on the cache container
#   (VALKEY_EXTRA_FLAGS becomes an argument of the server); no password
#   option in the command or the arguments of any container;
# - condition 6: a Service of type ClusterIP on 6379 alone, and a
#   NetworkPolicy that admits on 6379 the pods of the API and the probe
#   alone, and gives the cache pod no way out;
# - condition 10: 64Mi of memory and 25m of CPU requested, 128Mi of memory
#   as limit, no CPU limit, maxmemory 64mb;
# - condition 15: maxmemory-policy allkeys-lru.
# The probe Job of task up and of E13 (condition 17) is a client of the
# cache: same image, same pod security, the password from cache-auth by
# secretKeyRef alone.
#
# Input: the files given to `conftest test --combine`, one entry per YAML
# document (research RS-18): local/tests/static/s11-cache.sh renders
# local/data/cache with the Kustomize of kubectl, so that the ConfigMap of
# the script is checked as the cluster gets it, and adds
# local/data/cache/probe/job.yaml. The Kubernetes line of the image follows
# platform.yaml, which S21 checks.
package cache_layer

label := "S11 (ADR-006, condition 2; ADR-015, conditions 3 to 6, 10 and 15)"

label_c3 := "S11 (ADR-015, condition 3)"

label_c4 := "S11 (ADR-015, condition 4)"

label_c5 := "S11 (ADR-006, condition 2; ADR-015, condition 5)"

label_c6 := "S11 (ADR-015, condition 6)"

label_c10 := "S11 (ADR-015, conditions 10 and 15)"

app_label := "app.kubernetes.io/name"

secret_name := "cache-auth"

script_key := "write-config.sh"

run_user := 999

run_group := 1000

port := 6379

image_pattern := `^docker\.io/valkey/valkey:[0-9]+\.[0-9]+\.[0-9]+-alpine@sha256:[a-f0-9]{64}$`

# A password option of the server or of valkey-cli, as a word of a command
# or an argument, or inside a shell script given to sh -c.
password_option := `(^|\s)(-a|--pass|--user|--askpass|--requirepass)(\s|=|$)`

forbidden_words := `(?i)(requirepass|rename-command)`

# The settings that the init container writes, one echo per line.
expected_settings := [
	`save ""`,
	"appendonly no",
	"protected-mode yes",
	"maxmemory 64mb",
	"maxmemory-policy allkeys-lru",
	"enable-protected-configs no",
	"enable-debug-command no",
	"enable-module-command no",
]

# The ACL line: the SHA-256 of the password, then the refusals of
# research RS-11 (what Memorystore blocks and @admin misses), and
# @scripting, which the client never sends.
acl_line := "printf 'user default on #%s ~* &* +@all -@admin -@scripting -acl -migrate -move -restore-asking -swapdb -xsetid\\n'"

objects contains obj if {
	some file in input
	obj := file.contents
	is_object(obj)
}

named(kind, name) := {obj | some obj in objects; obj.kind == kind; obj.metadata.name == name}

deployments := named("Deployment", "cache")

services := named("Service", "cache")

policies := named("NetworkPolicy", "cache")

jobs := named("Job", "cache-probe")

config_maps := {obj |
	some obj in objects
	obj.kind == "ConfigMap"
	startswith(obj.metadata.name, "cache-config-writer")
}

allowed_kinds := {"Deployment", "Service", "NetworkPolicy", "ConfigMap", "Job"}

describe(obj) := sprintf("%v %v", [object.get(obj, "kind", null), object.get(object.get(obj, "metadata", {}), "name", null)])

# One of each.
expected_counts := {
	"Deployment cache": deployments,
	"Service cache": services,
	"NetworkPolicy cache": policies,
	"Job cache-probe": jobs,
	"ConfigMap cache-config-writer": config_maps,
}

deny contains msg if {
	some what, found in expected_counts
	count(found) != 1
	msg := sprintf("%s: expected one %s among the checked files, found %v", [label, what, count(found)])
}

deny contains msg if {
	some obj in objects
	not obj.kind in allowed_kinds
	msg := sprintf("%s: %s has no place in the cache layer; it holds a Deployment, a Service, a NetworkPolicy, the ConfigMap of its script and the probe Job (a Secret is created by task up, never versioned)", [label, describe(obj)])
}

deny contains msg if {
	some obj in objects
	walk(obj, [path, value])
	is_string(value)
	regex.match(forbidden_words, value)
	msg := sprintf("%s: %s holds requirepass or rename-command at %v; the password lives in the ACL as a SHA-256, and commands are refused by the ACL", [label_c4, describe(obj), path])
}

# Pods: the Deployment and the probe Job.

workloads := deployments | jobs

pod_spec(obj) := obj.spec.template.spec

containers_of(obj) := array.concat(object.get(pod_spec(obj), "initContainers", []), object.get(pod_spec(obj), "containers", []))

deny contains msg if {
	some obj in workloads
	spec := pod_spec(obj)
	some key, want in {"automountServiceAccountToken": false, "enableServiceLinks": false}
	object.get(spec, key, null) != want
	msg := sprintf("%s: %s must set %s to %v", [label_c3, describe(obj), key, want])
}

deny contains msg if {
	some obj in workloads
	context := object.get(pod_spec(obj), "securityContext", {})
	some key, want in {"runAsNonRoot": true, "runAsUser": run_user, "runAsGroup": run_group}
	object.get(context, key, null) != want
	msg := sprintf("%s: %s must set securityContext.%s to %v: the image declares no USER (research RS-11)", [label_c3, describe(obj), key, want])
}

deny contains msg if {
	some obj in workloads
	object.get(object.get(object.get(pod_spec(obj), "securityContext", {}), "seccompProfile", {}), "type", null) != "RuntimeDefault"
	msg := sprintf("%s: %s must set securityContext.seccompProfile.type to RuntimeDefault", [label_c3, describe(obj)])
}

deny contains msg if {
	some obj in workloads
	some key in {"hostNetwork", "hostPID", "hostIPC"}
	object.get(pod_spec(obj), key, false) != false
	msg := sprintf("%s: %s must not set %s", [label_c3, describe(obj), key])
}

deny contains msg if {
	some obj in workloads
	some container in containers_of(obj)
	context := object.get(container, "securityContext", {})
	some key, want in {"allowPrivilegeEscalation": false, "readOnlyRootFilesystem": true}
	object.get(context, key, null) != want
	msg := sprintf("%s: container %v of %s must set securityContext.%s to %v", [label_c3, container.name, describe(obj), key, want])
}

deny contains msg if {
	some obj in workloads
	some container in containers_of(obj)
	capabilities := object.get(object.get(container, "securityContext", {}), "capabilities", {})
	object.get(capabilities, "drop", []) != ["ALL"]
	msg := sprintf("%s: container %v of %s must drop every capability, drop: [ALL]", [label_c3, container.name, describe(obj)])
}

deny contains msg if {
	some obj in workloads
	some container in containers_of(obj)
	context := object.get(container, "securityContext", {})
	some key in {"privileged", "runAsUser", "runAsGroup", "runAsNonRoot"}
	object.get(context, key, null) != null
	msg := sprintf("%s: container %v of %s sets securityContext.%s; the pod sets the user, and nothing else may change it", [label_c3, container.name, describe(obj), key])
}

deny contains msg if {
	some obj in workloads
	some container in containers_of(obj)
	object.get(object.get(object.get(container, "securityContext", {}), "capabilities", {}), "add", []) != []
	msg := sprintf("%s: container %v of %s adds a capability", [label_c3, container.name, describe(obj)])
}

deny contains msg if {
	some obj in workloads
	some container in containers_of(obj)
	not regex.match(image_pattern, object.get(container, "image", ""))
	msg := sprintf("%s: container %v of %s runs %v; ADR-015 wants docker.io/valkey/valkey, Alpine variant, by tag and digest (condition 1)", [label, container.name, describe(obj), object.get(container, "image", null)])
}

images := {container.image | some obj in workloads; some container in containers_of(obj)}

deny contains msg if {
	count(images) > 1
	msg := sprintf("%s: the cache layer runs %v images, %v; the init container and the probe use the image of the server, so that nothing else is pulled", [label, count(images), images])
}

deny contains msg if {
	some obj in workloads
	some container in containers_of(obj)
	words := array.concat(object.get(container, "command", []), object.get(container, "args", []))
	some word in words
	regex.match(password_option, word)
	msg := sprintf("%s: container %v of %s passes a password option in its command or arguments: %v", [label_c5, container.name, describe(obj), word])
}

deny contains msg if {
	some obj in workloads
	some volume in object.get(pod_spec(obj), "volumes", [])
	some key in {"hostPath", "persistentVolumeClaim"}
	object.get(volume, key, null) != null
	msg := sprintf("%s: volume %v of %s is a %s; the cache keeps nothing", [label_c3, volume.name, describe(obj), key])
}

# The Deployment of the cache.

deployment := obj if {
	count(deployments) == 1
	some obj in deployments
}

server := container if {
	some container in object.get(pod_spec(deployment), "containers", [])
	container.name == "cache"
}

init_container := container if {
	some container in object.get(pod_spec(deployment), "initContainers", [])
	container.name == "config"
}

volumes := {volume.name: volume | some volume in object.get(pod_spec(deployment), "volumes", [])}

secret_volumes := {name | some name, volume in volumes; object.get(volume, "secret", null) != null}

deny contains msg if {
	is_object(deployment)
	object.get(deployment.spec, "replicas", null) != 1
	msg := sprintf("%s: the Deployment cache runs %v replicas; ADR-015 wants one", [label, object.get(deployment.spec, "replicas", null)])
}

deny contains msg if {
	is_object(deployment)
	object.get(object.get(deployment.spec.template.metadata, "labels", {}), app_label, null) != "cache"
	msg := sprintf("%s: the pod of the Deployment cache must carry the label %s: cache, which the Service and the NetworkPolicy select", [label_c6, app_label])
}

deny contains msg if {
	is_object(deployment)
	count(object.get(pod_spec(deployment), "containers", [])) != 1
	msg := sprintf("%s: the Deployment cache runs one container, cache", [label])
}

deny contains msg if {
	is_object(deployment)
	not server
	msg := sprintf("%s: the Deployment cache has no container named cache", [label])
}

deny contains msg if {
	is_object(deployment)
	not init_container
	msg := sprintf("%s: the Deployment cache has no init container named config, which writes cache.conf", [label_c4])
}

deny contains msg if {
	some key in {"env", "envFrom"}
	object.get(server, key, null) != null
	msg := sprintf("%s: the container cache sets %s; an environment variable such as VALKEY_EXTRA_FLAGS becomes an argument of the server (research RS-11)", [label_c5, key])
}

deny contains msg if {
	is_object(server)
	object.get(server, "args", null) != ["valkey-server", "/etc/cache/cache.conf"]
	msg := sprintf("%s: the container cache must start with args [valkey-server, /etc/cache/cache.conf], found %v", [label_c5, object.get(server, "args", null)])
}

deny contains msg if {
	is_object(server)
	object.get(server, "command", null) != null
	msg := sprintf("%s: the container cache keeps the entrypoint of its image; it must not set command", [label_c5])
}

deny contains msg if {
	is_object(server)
	some mount in object.get(server, "volumeMounts", [])
	mount.name in secret_volumes
	msg := sprintf("%s: the container cache mounts the Secret volume %v; only the init container reads the password", [label_c4, mount.name])
}

deny contains msg if {
	some container in object.get(pod_spec(deployment), "initContainers", [])
	some key in {"env", "envFrom"}
	object.get(container, key, null) != null
	msg := sprintf("%s: the init container %v sets %s; it reads the password from the file of cache-auth alone", [label_c5, container.name, key])
}

deny contains msg if {
	is_object(deployment)
	count(secret_volumes) != 1
	msg := sprintf("%s: the Deployment cache must have one Secret volume, of cache-auth; found %v", [label_c4, count(secret_volumes)])
}

deny contains msg if {
	some name in secret_volumes
	volumes[name].secret.secretName != secret_name
	msg := sprintf("%s: the Secret volume %v reads %v; the cache reads cache-auth (ADR-007, condition 5)", [label_c4, name, volumes[name].secret.secretName])
}

deny contains msg if {
	is_object(init_container)
	count({mount | some mount in object.get(init_container, "volumeMounts", []); mount.name in secret_volumes; mount.readOnly == true}) != 1
	msg := sprintf("%s: the init container config must mount the Secret volume of cache-auth, read-only", [label_c4])
}

data_mounts := [mount | some mount in object.get(server, "volumeMounts", []); mount.mountPath == "/data"]

deny contains msg if {
	is_object(server)
	count(data_mounts) != 1
	msg := sprintf("%s: the container cache must mount one volume at /data, its working directory", [label_c3])
}

deny contains msg if {
	some mount in data_mounts
	size := object.get(object.get(volumes, mount.name, {}), ["emptyDir", "sizeLimit"], null)
	size == null
	msg := sprintf("%s: /data must be an emptyDir bounded by sizeLimit, found volume %v", [label_c3, mount.name])
}

deny contains msg if {
	some name, volume in volumes
	object.get(volume, "emptyDir", null) != null
	object.get(volume.emptyDir, "sizeLimit", null) == null
	msg := sprintf("%s: the emptyDir %v has no sizeLimit", [label_c3, name])
}

# Condition 10: requests and limits of the cache container.
expected_resources := {
	["requests", "memory"]: "64Mi",
	["requests", "cpu"]: "25m",
	["limits", "memory"]: "128Mi",
}

deny contains msg if {
	is_object(server)
	some path, want in expected_resources
	object.get(object.get(server, "resources", {}), path, null) != want
	msg := sprintf("%s: the container cache must set resources.%s to %v, found %v", [label_c10, concat(".", path), want, object.get(object.get(server, "resources", {}), path, null)])
}

deny contains msg if {
	is_object(server)
	object.get(object.get(server, "resources", {}), ["limits", "cpu"], null) != null
	msg := sprintf("%s: the container cache sets a CPU limit; ADR-015 wants none", [label_c10])
}

deny contains msg if {
	is_object(server)
	ports := {p.containerPort | some p in object.get(server, "ports", [])}
	ports != {port}
	msg := sprintf("%s: the container cache must declare port %v alone, found %v", [label_c6, port, ports])
}

# The script of the init container, as the ConfigMap gives it.
script := cm.data[script_key] if {
	count(config_maps) == 1
	some cm in config_maps
}

deny contains msg if {
	count(config_maps) == 1
	not script
	msg := sprintf("%s: the ConfigMap cache-config-writer has no key %s", [label_c4, script_key])
}

deny contains msg if {
	is_string(script)
	some setting in expected_settings
	not regex.match(sprintf(`(?m)^\s*echo '%s'$`, [replace(setting, `"`, `\"`)]), script)
	msg := sprintf("%s: the script of the init container does not write the line %v, as echo '%v'", [label_c10, setting, setting])
}

deny contains msg if {
	is_string(script)
	not contains(script, acl_line)
	msg := sprintf("%s: the script of the init container does not write the ACL line of research RS-11: %s", [label_c4, acl_line])
}

deny contains msg if {
	is_string(script)
	some word in {"nopass", "aclfile", "resetpass"}
	contains(script, word)
	msg := sprintf("%s: the script of the init container names %v; the default user gets the SHA-256 of the password and nothing else", [label_c4, word])
}

deny contains msg if {
	is_string(script)
	regex.match(`user default[^\n]*>`, script)
	msg := sprintf("%s: the ACL line of the script holds a > rule, a cleartext password", [label_c4])
}

deny contains msg if {
	is_object(init_container)
	object.get(init_container, "command", null) != ["sh", "/opt/cache-init/write-config.sh"]
	msg := sprintf("%s: the init container config must run [sh, /opt/cache-init/write-config.sh], the script of the ConfigMap, found %v", [label_c4, object.get(init_container, "command", null)])
}

# Condition 6: the Service and the NetworkPolicy.

deny contains msg if {
	some service in services
	object.get(service.spec, "type", "ClusterIP") != "ClusterIP"
	msg := sprintf("%s: the Service cache is of type %v; only ClusterIP, never NodePort nor LoadBalancer", [label_c6, service.spec.type])
}

deny contains msg if {
	some service in services
	some key in {"externalIPs", "loadBalancerIP", "externalName"}
	object.get(service.spec, key, null) != null
	msg := sprintf("%s: the Service cache sets %s", [label_c6, key])
}

deny contains msg if {
	some service in services
	ports := [{"port": p.port, "nodePort": object.get(p, "nodePort", null)} | some p in object.get(service.spec, "ports", [])]
	ports != [{"port": port, "nodePort": null}]
	msg := sprintf("%s: the Service cache must expose port %v alone, without nodePort, found %v", [label_c6, port, ports])
}

deny contains msg if {
	some service in services
	object.get(service.spec, "selector", {}) != {app_label: "cache"}
	msg := sprintf("%s: the Service cache must select %s: cache alone", [label_c6, app_label])
}

admitted_from := [{"podSelector": {"matchExpressions": [{"key": app_label, "operator": "In", "values": ["api", "cache-probe"]}]}}]

admitted_ports := [{"protocol": "TCP", "port": port}]

deny contains msg if {
	some policy in policies
	object.get(policy.spec, "podSelector", {}) != {"matchLabels": {app_label: "cache"}}
	msg := sprintf("%s: the NetworkPolicy cache must select the pods of %s: cache", [label_c6, app_label])
}

deny contains msg if {
	some policy in policies
	{type | some type in object.get(policy.spec, "policyTypes", [])} != {"Ingress", "Egress"}
	msg := sprintf("%s: the NetworkPolicy cache must isolate the cache pod for Ingress and Egress, found %v", [label_c6, object.get(policy.spec, "policyTypes", null)])
}

deny contains msg if {
	some policy in policies
	object.get(policy.spec, "egress", []) != []
	msg := sprintf("%s: the NetworkPolicy cache admits an egress; the cache pod opens no connection", [label_c6])
}

deny contains msg if {
	some policy in policies
	object.get(policy.spec, "ingress", []) != [{"from": admitted_from, "ports": admitted_ports}]
	msg := sprintf("%s: the NetworkPolicy cache must admit on TCP %v the pods of %s api or cache-probe alone, found %v", [label_c6, port, app_label, object.get(policy.spec, "ingress", null)])
}

# The probe Job.

deny contains msg if {
	some job in jobs
	object.get(object.get(job.spec.template.metadata, "labels", {}), app_label, null) != "cache-probe"
	msg := sprintf("%s: the pod of the Job cache-probe must carry the label %s: cache-probe, which the NetworkPolicy admits", [label_c6, app_label])
}

probe_env := [{"name": "VALKEYCLI_AUTH", "valueFrom": {"secretKeyRef": {"name": secret_name, "key": "password"}}}]

deny contains msg if {
	some job in jobs
	some container in containers_of(job)
	object.get(container, "env", []) != probe_env
	msg := sprintf("%s: container %v of the Job cache-probe must read the password by secretKeyRef from cache-auth, key password, in VALKEYCLI_AUTH, and set nothing else", [label_c5, container.name])
}

deny contains msg if {
	some job in jobs
	some container in containers_of(job)
	object.get(container, "envFrom", null) != null
	msg := sprintf("%s: container %v of the Job cache-probe sets envFrom", [label_c5, container.name])
}

# A Job left by an interrupted task up goes by itself, and with it its
# reference to cache-auth (tasks.md, gap 130): a TTL after the end, from one
# minute to ten.
probe_ttl_min := 60

probe_ttl_max := 600

deny contains msg if {
	some job in jobs
	ttl := object.get(job.spec, "ttlSecondsAfterFinished", null)
	not is_number(ttl)
	msg := sprintf("%s: the Job cache-probe must set ttlSecondsAfterFinished, from %d to %d seconds, so that a Job left by an interrupted task up goes by itself", [label_c5, probe_ttl_min, probe_ttl_max])
}

deny contains msg if {
	some job in jobs
	ttl := object.get(job.spec, "ttlSecondsAfterFinished", null)
	is_number(ttl)
	not probe_ttl_min <= ttl
	msg := sprintf("%s: the Job cache-probe must set ttlSecondsAfterFinished, from %d to %d seconds, found %v", [label_c5, probe_ttl_min, probe_ttl_max, ttl])
}

deny contains msg if {
	some job in jobs
	ttl := object.get(job.spec, "ttlSecondsAfterFinished", null)
	is_number(ttl)
	ttl > probe_ttl_max
	msg := sprintf("%s: the Job cache-probe must set ttlSecondsAfterFinished, from %d to %d seconds, found %v", [label_c5, probe_ttl_min, probe_ttl_max, ttl])
}
