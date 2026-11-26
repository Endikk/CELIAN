# S30, the Deployments and Services of the API and the front (spec 001, T087;
# FR-009, FR-010; ADR-007, condition 5; ADR-012, condition 9; tasks.md, gaps
# 102 and 120 and following): the common layer rendered alone holds
# - one Deployment and one Service for each of api and front; the Service
#   selects the pods of its Deployment and serves port 80, to the port 8080
#   of the container, where the HTTPRoute backendRefs point;
# - for each pod: runAsNonRoot, seccomp RuntimeDefault, no service account
#   token; for each container: no privilege escalation, a read-only root
#   filesystem, every capability dropped and none added, requests of CPU and
#   memory, a memory limit, a readiness and a liveness probe on the paths of
#   contracts/http-api.md (/api/readyz and /api/healthz for the API, / for
#   the front);
# - every emptyDir bounded by sizeLimit;
# - Secrets read by mounted files only (contracts/secrets.md): no
#   secretKeyRef, no envFrom of a Secret; the API mounts db-auth and
#   cache-auth read-only under /run/secrets, the front mounts none;
# - the API reads app-config by envFrom, and its pod carries the label
#   app.kubernetes.io/name: api, the one that the NetworkPolicies of
#   Postgres and of the cache admit.
#
# Input: the render of the common layer, k8s/overlays/local, given to
# `conftest test --combine` by tests/static/s30-app-workloads.sh.
package app_workloads

label := "S30 (FR-009, FR-010; ADR-007, condition 5; ADR-012, condition 9)"

apps := {"api", "front"}

app_label := "app.kubernetes.io/name"

documents := [file.contents | some file in input; is_object(file.contents)]

named(kind, name) := [doc | some doc in documents; doc.kind == kind; doc.metadata.name == name]

deny contains msg if {
	some app in apps
	some kind in {"Deployment", "Service"}
	count(named(kind, app)) != 1
	msg := sprintf("%s: expected one %s %s in the render of the common layer, found %d", [label, kind, app, count(named(kind, app))])
}

deployment(app) := doc if {
	docs := named("Deployment", app)
	count(docs) == 1
	some doc in docs
}

service(app) := doc if {
	docs := named("Service", app)
	count(docs) == 1
	some doc in docs
}

pod_spec(app) := deployment(app).spec.template.spec

# The containers that serve (one each), and all of them, init containers
# included: the rules of security apply to every one.
main_containers(app) := [c | some c in object.get(pod_spec(app), "containers", [])]

containers(app) := array.concat(main_containers(app), [c | some c in object.get(pod_spec(app), "initContainers", [])])

deny contains msg if {
	some app in apps
	deployment(app)
	count(main_containers(app)) != 1
	msg := sprintf("%s: Deployment %s must run one container, found %d", [label, app, count(main_containers(app))])
}

deny contains msg if {
	some app in apps
	deployment(app)
	object.get(deployment(app).spec.template.metadata.labels, app_label, null) != app
	msg := sprintf("%s: the pod of Deployment %s must carry the label %s: %s", [label, app, app_label, app])
}

deny contains msg if {
	some app in apps
	deployment(app)
	service(app)
	object.get(service(app).spec.selector, app_label, null) != app
	msg := sprintf("%s: Service %s must select the pods labelled %s: %s", [label, app, app_label, app])
}

deny contains msg if {
	some app in apps
	service(app)
	ports := service(app).spec.ports
	not serves_80_to_8080(ports)
	msg := sprintf("%s: Service %s must serve port 80 to the port 8080 of the container, found %v", [label, app, ports])
}

serves_80_to_8080(ports) if {
	some p in ports
	p.port == 80
	p.targetPort == 8080
}

# --- The pod and the containers --------------------------------------------------------

deny contains msg if {
	some app in apps
	deployment(app)
	sc := object.get(pod_spec(app), "securityContext", {})
	object.get(sc, "runAsNonRoot", false) != true
	msg := sprintf("%s: the pod of %s must set runAsNonRoot to true", [label, app])
}

deny contains msg if {
	some app in apps
	deployment(app)
	sc := object.get(pod_spec(app), "securityContext", {})
	object.get(object.get(sc, "seccompProfile", {}), "type", null) != "RuntimeDefault"
	msg := sprintf("%s: the pod of %s must set the seccomp profile RuntimeDefault", [label, app])
}

deny contains msg if {
	some app in apps
	deployment(app)
	object.get(pod_spec(app), "automountServiceAccountToken", true) != false
	msg := sprintf("%s: the pod of %s must set automountServiceAccountToken to false", [label, app])
}

deny contains msg if {
	some app in apps
	some c in containers(app)
	sc := object.get(c, "securityContext", {})
	object.get(sc, "allowPrivilegeEscalation", true) != false
	msg := sprintf("%s: container %s of %s must set allowPrivilegeEscalation to false", [label, c.name, app])
}

deny contains msg if {
	some app in apps
	some c in containers(app)
	sc := object.get(c, "securityContext", {})
	object.get(sc, "readOnlyRootFilesystem", false) != true
	msg := sprintf("%s: container %s of %s must set readOnlyRootFilesystem to true", [label, c.name, app])
}

deny contains msg if {
	some app in apps
	some c in containers(app)
	caps := object.get(object.get(c, "securityContext", {}), "capabilities", {})
	object.get(caps, "drop", []) != ["ALL"]
	msg := sprintf("%s: container %s of %s must drop ALL capabilities", [label, c.name, app])
}

deny contains msg if {
	some app in apps
	some c in containers(app)
	count(object.get(object.get(object.get(c, "securityContext", {}), "capabilities", {}), "add", [])) > 0
	msg := sprintf("%s: container %s of %s adds a capability", [label, c.name, app])
}

deny contains msg if {
	some app in apps
	some c in containers(app)
	some resource in ["cpu", "memory"]
	object.get(object.get(object.get(c, "resources", {}), "requests", {}), resource, null) == null
	msg := sprintf("%s: container %s of %s must request %s", [label, c.name, app, resource])
}

deny contains msg if {
	some app in apps
	some c in containers(app)
	object.get(object.get(object.get(c, "resources", {}), "limits", {}), "memory", null) == null
	msg := sprintf("%s: container %s of %s must limit memory", [label, c.name, app])
}

probe_paths := {
	"api": {"readinessProbe": "/api/readyz", "livenessProbe": "/api/healthz"},
	"front": {"readinessProbe": "/", "livenessProbe": "/"},
}

deny contains msg if {
	some app in apps
	some c in main_containers(app)
	some probe, path in probe_paths[app]
	object.get(object.get(object.get(c, probe, {}), "httpGet", {}), "path", null) != path
	msg := sprintf("%s: container %s of %s must set %s as an httpGet on %s", [label, c.name, app, probe, path])
}

# --- Volumes and Secrets -----------------------------------------------------------------

deny contains msg if {
	some app in apps
	deployment(app)
	some volume in object.get(pod_spec(app), "volumes", [])
	volume.emptyDir
	object.get(volume.emptyDir, "sizeLimit", null) == null
	msg := sprintf("%s: the emptyDir %s of %s must set sizeLimit", [label, volume.name, app])
}

deny contains msg if {
	some app in apps
	some c in containers(app)
	some variable in object.get(c, "env", [])
	variable.valueFrom.secretKeyRef
	msg := sprintf("%s: container %s of %s reads a Secret by secretKeyRef; Secrets are read by mounted files (contracts/secrets.md)", [label, c.name, app])
}

deny contains msg if {
	some app in apps
	some c in containers(app)
	some source in object.get(c, "envFrom", [])
	source.secretRef
	msg := sprintf("%s: container %s of %s reads a Secret by envFrom; Secrets are read by mounted files (contracts/secrets.md)", [label, c.name, app])
}

secret_mounts(app) := {sprintf("%s=%s", [volume.secret.secretName, mount.mountPath]) |
	some volume in object.get(pod_spec(app), "volumes", [])
	volume.secret
	some c in containers(app)
	some mount in object.get(c, "volumeMounts", [])
	mount.name == volume.name
}

deny contains msg if {
	deployment("api")
	secret_mounts("api") != {"db-auth=/run/secrets/db-auth", "cache-auth=/run/secrets/cache-auth"}
	msg := sprintf("%s: the API must mount db-auth and cache-auth under /run/secrets, found %v", [label, secret_mounts("api")])
}

deny contains msg if {
	deployment("front")
	count(secret_mounts("front")) > 0
	msg := sprintf("%s: the front mounts no Secret, found %v", [label, secret_mounts("front")])
}

deny contains msg if {
	some volume in object.get(pod_spec("api"), "volumes", [])
	volume.secret
	object.get(volume.secret, "defaultMode", null) == null
	msg := sprintf("%s: the Secret volume %s of the API must set defaultMode (0440), so that no other user reads it", [label, volume.name])
}

deny contains msg if {
	deployment("api")
	some c in main_containers("api")
	not {"configMapRef": {"name": "app-config"}} in object.get(c, "envFrom", [])
	msg := sprintf("%s: container %s of the API must read app-config by envFrom", [label, c.name])
}

# --- The CA bundles of the managed services (tasks.md, gap 166) ---------------------------

ca_mounts(app) := {mount.mountPath |
	some volume in object.get(pod_spec(app), "volumes", [])
	volume.configMap.name == "app-ca"
	volume.configMap.optional == true
	some c in containers(app)
	some mount in object.get(c, "volumeMounts", [])
	mount.name == volume.name
	mount.readOnly == true
}

deny contains msg if {
	deployment("api")
	ca_mounts("api") != {"/run/config/ca"}
	msg := sprintf("%s: the API must mount the ConfigMap app-ca, optional, read-only, on /run/config/ca (found %v)", [label, ca_mounts("api")])
}

deny contains msg if {
	deployment("api")
	some c in main_containers("api")
	not {"name": "PGSSLROOTCERT", "value": "/run/config/ca/database-ca.pem"} in object.get(c, "env", [])
	msg := sprintf("%s: container %s of the API must set PGSSLROOTCERT to /run/config/ca/database-ca.pem, the root of the database that Npgsql reads", [label, c.name])
}

serves(ref) if {
	some s in documents
	s.kind == "Service"
	s.metadata.name == ref.name
	some p in s.spec.ports
	p.port == ref.port
}

# --- The routes reach the Services ------------------------------------------------------------

deny contains msg if {
	some doc in documents
	doc.kind == "HTTPRoute"
	some rule in doc.spec.rules
	some ref in rule.backendRefs
	not serves(ref)
	msg := sprintf("%s: HTTPRoute %s sends to %s port %v, which no Service of the render serves", [label, doc.metadata.name, ref.name, ref.port])
}

# --- The host, the volumes that reach out, the pull policy (tasks.md, gap 155) ---------

deny contains msg if {
	some app in apps
	deployment(app)
	some field in ["hostNetwork", "hostPID", "hostIPC"]
	object.get(pod_spec(app), field, false) != false
	msg := sprintf("%s: the pod of %s must not set %s", [label, app, field])
}

deny contains msg if {
	some app in apps
	deployment(app)
	some volume in object.get(pod_spec(app), "volumes", [])
	volume.hostPath
	msg := sprintf("%s: the volume %s of %s is a hostPath, which reaches the file system of the node", [label, volume.name, app])
}

# A projected volume can carry a Secret like a secret volume does, beside the
# mounts that the rule above counts.
deny contains msg if {
	some app in apps
	deployment(app)
	some volume in object.get(pod_spec(app), "volumes", [])
	some source in object.get(object.get(volume, "projected", {}), "sources", [])
	source.secret
	msg := sprintf("%s: the projected volume %s of %s takes a Secret as a source; Secrets are mounted as secret volumes, which this control counts", [label, volume.name, app])
}

deny contains msg if {
	some app in apps
	some c in containers(app)
	object.get(object.get(c, "securityContext", {}), "privileged", false) != false
	msg := sprintf("%s: container %s of %s must not be privileged", [label, c.name, app])
}

# The built images never come from a registry: .invalid resolves to none, and
# the pull policy says so (research RS-07).
deny contains msg if {
	some app in apps
	some c in containers(app)
	startswith(c.image, "saas-b2b.invalid/")
	not object.get(c, "imagePullPolicy", null) in {"IfNotPresent", "Never"}
	msg := sprintf("%s: container %s of %s runs the built image %s: imagePullPolicy must be IfNotPresent or Never, found %v", [label, c.name, app, c.image, object.get(c, "imagePullPolicy", null)])
}
