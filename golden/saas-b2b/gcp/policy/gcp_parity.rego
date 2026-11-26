# S07, gcp part: the render of the gcp layer holds the common layer as it is,
# and what it adds comes from the gcp layer (spec 001, plan, matrix S07;
# contracts/layers.md, "Règle de parité"; ADR-005, condition 5; ADR-007,
# condition 5; tasks.md, gap 163).
#
# Three renders come in, told apart by the name of the file:
# - common.yaml: the overlay of the environment alone (k8s/overlays/prod);
# - gcp.yaml: the same overlay with the component of the gcp target
#   (gcp/k8s/prod);
# - layer.yaml: the objects of the files of the gcp layer, as written
#   (gcp/k8s/component/ and gcp/k8s/values/).
#
# 1. Each object of common.yaml is in gcp.yaml, identical, but for
#    spec.gatewayClassName of the Gateway, which names the class of GKE.
# 2. Each object of gcp.yaml that common.yaml lacks is, identical, in
#    layer.yaml: it comes from a file of the gcp layer.
# 3. One Gateway in each render (ADR-005, condition 5).
# 5. The Namespace of bootstrap.yaml (gcp/k8s/bootstrap, applied once by the
#    user before the RootSync can read anything) is the one of the common
#    layer, byte for byte in its fields: a Role needs its namespace to exist,
#    and Config Sync then takes the namespace of k8s/base over.
# 4. Every Secret and ConfigMap that a pod template of the common layer reads
#    is produced by the gcp layer, with the keys it reads: a Secret by a
#    SecretSync (contracts/secrets.md), a ConfigMap by an object of the
#    layer. Two Secrets have a producer to come, listed in pending_secrets
#    with the reason: they raise a warning, not a failure, and the day their
#    producer is written the entry goes. db-superuser has none on gcp and the
#    application never reads it (ADR-012).
#
# Rule 4 reads the Deployments when step 9 brings them: until then the common
# layer has no pod template and the rule has nothing to read.
package gcp_parity

label := "S07 (FR-010; ADR-005, condition 5; ADR-007, condition 5)"

gcp_class := "gke-l7-global-external-managed"

# Secrets read by the application whose producer on gcp is not written yet.
pending_secrets := {
	"cache-auth": "its producer is the second PR of step 20: the token of Memorystore, by Secret Manager and the sync of GKE (ADR-015, condition 18)",
	"gateway-tls": "its producer comes with the HTTPS listener of the Gateway (research RS-16, \"gateway-tls sur gcp\")",
}

never_produced := {"db-superuser": "Cloud SQL gives no superuser and the application never reads it (ADR-012)"}

controllers := {"Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Job"}

objects_of(name) := {[obj.kind, object.get(obj.metadata, "namespace", ""), obj.metadata.name, group_of(obj), obj] |
	some file in input
	endswith(file.path, name)
	obj := file.contents
	is_object(obj)
}

group_of(obj) := "" if not contains(object.get(obj, "apiVersion", ""), "/")

group_of(obj) := split(obj.apiVersion, "/")[0] if contains(object.get(obj, "apiVersion", ""), "/")

common := objects_of("common.yaml")

gcp := objects_of("gcp.yaml")

layer := objects_of("layer.yaml")

key(entry) := [entry[0], entry[1], entry[2], entry[3]]

keys_of(entries) := {key(e) | some e in entries}

describe(k) := sprintf("%v %v/%v (group %q)", [k[0], k[1], k[2], k[3]])

without_class(obj) := json.remove(obj, ["spec/gatewayClassName"]) if obj.kind == "Gateway"

without_class(obj) := obj if obj.kind != "Gateway"

deny contains msg if {
	count(common) == 0
	msg := sprintf("%s: common.yaml holds no object: the overlay of the environment is not rendered", [label])
}

deny contains msg if {
	count(gcp) == 0
	msg := sprintf("%s: gcp.yaml holds no object: gcp/k8s/prod is not rendered", [label])
}

# 1. The common layer in the gcp render.
deny contains msg if {
	some c in common
	not key(c) in keys_of(gcp)
	msg := sprintf("%s: %s is in the common layer and not in the render of gcp", [label, describe(key(c))])
}

deny contains msg if {
	some c in common
	some g in gcp
	key(c) == key(g)
	without_class(c[4]) != without_class(g[4])
	msg := sprintf("%s: %s differs between the common layer and the render of gcp, in more than spec.gatewayClassName", [label, describe(key(c))])
}

deny contains msg if {
	some g in gcp
	g[0] == "Gateway"
	not g[4].spec.gatewayClassName == gcp_class
	msg := sprintf("%s: the Gateway of gcp asks the class %v, %v expected (research RS-16)", [label, object.get(object.get(g[4], "spec", {}), "gatewayClassName", "unset"), gcp_class])
}

# 2. What gcp adds comes from the layer.
deny contains msg if {
	some g in gcp
	not key(g) in keys_of(common)
	not key(g) in keys_of(layer)
	msg := sprintf("%s: %s is in the render of gcp, in no file of the common layer nor of the gcp layer", [label, describe(key(g))])
}

deny contains msg if {
	some g in gcp
	not key(g) in keys_of(common)
	some l in layer
	key(g) == key(l)
	g[4] != l[4]
	msg := sprintf("%s: %s is changed on its way from its file of the gcp layer to the render: a patch of the layer must reach common objects only through spec.gatewayClassName", [label, describe(key(g))])
}

# 3. One Gateway.
gateways(entries) := {e | some e in entries; e[0] == "Gateway"}

deny contains msg if {
	count(gateways(common)) != 1
	msg := sprintf("%s: %d Gateway in the common layer, one expected (ADR-005, condition 5)", [label, count(gateways(common))])
}

deny contains msg if {
	count(gateways(gcp)) != 1
	msg := sprintf("%s: %d Gateway in the render of gcp, one expected (ADR-005, condition 5): each Gateway is a billed load balancer", [label, count(gateways(gcp))])
}

# 5. The namespace of the bootstrap.
bootstrap := objects_of("bootstrap.yaml")

deny contains msg if {
	some b in bootstrap
	b[0] == "Namespace"
	some c in common
	key(c) == key(b)
	c[4] != b[4]
	msg := sprintf("%s: the Namespace %v of the bootstrap differs from the one of the common layer: copy k8s/base/namespace.yaml", [label, b[2]])
}

deny contains msg if {
	some b in bootstrap
	b[0] == "Namespace"
	not key(b) in keys_of(common)
	msg := sprintf("%s: the bootstrap creates the Namespace %v, which the common layer does not hold", [label, b[2]])
}

# 6. The admission policy and its binding, which the render of gcp holds and
# Config Sync syncs, are in the bootstrap too, identical. The ClusterRole of the
# RootSync has no create verb (S10): Config Sync updates these two objects by
# name and cannot create them, so the user applies them first with the
# bootstrap (SECU review of the PR 87; tasks.md, gap 168).
admission_kinds := {"ValidatingAdmissionPolicy", "ValidatingAdmissionPolicyBinding"}

deny contains msg if {
	some g in gcp
	g[0] in admission_kinds
	not key(g) in keys_of(bootstrap)
	msg := sprintf("%s: %s is synced by Config Sync and is not in the bootstrap: the RootSync cannot create it, the user applies it first", [label, describe(key(g))])
}

deny contains msg if {
	some g in gcp
	g[0] in admission_kinds
	some b in bootstrap
	key(g) == key(b)
	g[4] != b[4]
	msg := sprintf("%s: %s of the bootstrap differs from the one that Config Sync syncs", [label, describe(key(g))])
}

# 4. The producers.
specs contains spec if {
	some c in common
	c[0] in controllers
	spec := c[4].spec.template.spec
}

# A reference read by a pod: {"kind", "name", "key"} ("" for the whole
# object), optional ones left out.
refs contains {"kind": "Secret", "name": ref.name, "key": ref.key} if {
	some spec in specs
	walk(spec, [_, node])
	ref := node.secretKeyRef
	not ref.optional == true
}

refs contains {"kind": "Secret", "name": node.secretRef.name, "key": ""} if {
	some spec in specs
	walk(spec, [_, node])
	not node.secretRef.optional == true
}

refs contains {"kind": "Secret", "name": node.secret.secretName, "key": ""} if {
	some spec in specs
	walk(spec, [_, node])
	not node.secret.optional == true
	not node.secret.items
}

refs contains {"kind": "Secret", "name": node.secret.secretName, "key": item.key} if {
	some spec in specs
	walk(spec, [_, node])
	not node.secret.optional == true
	some item in node.secret.items
}

refs contains {"kind": "ConfigMap", "name": ref.name, "key": ref.key} if {
	some spec in specs
	walk(spec, [_, node])
	ref := node.configMapKeyRef
	not ref.optional == true
}

refs contains {"kind": "ConfigMap", "name": node.configMapRef.name, "key": ""} if {
	some spec in specs
	walk(spec, [_, node])
	not node.configMapRef.optional == true
}

refs contains {"kind": "ConfigMap", "name": node.configMap.name, "key": ""} if {
	some spec in specs
	walk(spec, [_, node])
	not node.configMap.optional == true
	not node.configMap.items
}

refs contains {"kind": "ConfigMap", "name": node.configMap.name, "key": item.key} if {
	some spec in specs
	walk(spec, [_, node])
	not node.configMap.optional == true
	some item in node.configMap.items
}

# The certificate of a listener of the Gateway is read as a Secret too.
refs contains {"kind": "Secret", "name": ref.name, "key": ""} if {
	some c in common
	c[0] == "Gateway"
	some listener in c[4].spec.listeners
	some ref in listener.tls.certificateRefs
	object.get(ref, "kind", "Secret") == "Secret"
}

# Keys that a SecretSync of the gcp render writes into its Secret.
secret_keys(name) := {d.targetKey |
	some g in gcp
	g[0] == "SecretSync"
	g[2] == name
	some d in g[4].spec.secretObject.data
}

secret_produced(name) if {
	some g in gcp
	g[0] == "SecretSync"
	g[2] == name
}

config_keys(name) := {k |
	some g in gcp
	g[0] == "ConfigMap"
	g[2] == name
	some k, _ in object.get(g[4], "data", {})
}

config_produced(name) if {
	some g in gcp
	g[0] == "ConfigMap"
	g[2] == name
}

deny contains msg if {
	some ref in refs
	ref.kind == "Secret"
	reason := never_produced[ref.name]
	msg := sprintf("%s: a pod of the common layer reads the Secret %v: %s", [label, ref.name, reason])
}

deny contains msg if {
	some ref in refs
	ref.kind == "Secret"
	not never_produced[ref.name]
	not pending_secrets[ref.name]
	not secret_produced(ref.name)
	msg := sprintf("%s: a pod of the common layer reads the Secret %v, and the gcp layer has no SecretSync that produces it (contracts/secrets.md)", [label, ref.name])
}

deny contains msg if {
	some ref in refs
	ref.kind == "Secret"
	ref.key != ""
	secret_produced(ref.name)
	not ref.key in secret_keys(ref.name)
	msg := sprintf("%s: a pod of the common layer reads the key %v of the Secret %v, which the SecretSync of gcp does not write (it writes %v)", [label, ref.key, ref.name, sort(secret_keys(ref.name))])
}

deny contains msg if {
	some ref in refs
	ref.kind == "ConfigMap"
	not config_produced(ref.name)
	msg := sprintf("%s: a pod of the common layer reads the ConfigMap %v, which the gcp layer does not provide", [label, ref.name])
}

deny contains msg if {
	some ref in refs
	ref.kind == "ConfigMap"
	ref.key != ""
	config_produced(ref.name)
	not ref.key in config_keys(ref.name)
	msg := sprintf("%s: a pod of the common layer reads the key %v of the ConfigMap %v, which the gcp layer does not write", [label, ref.key, ref.name])
}

warn contains msg if {
	some ref in refs
	ref.kind == "Secret"
	reason := pending_secrets[ref.name]
	msg := sprintf("%s: the Secret %v has no producer on gcp yet: %s", [label, ref.name, reason])
}
