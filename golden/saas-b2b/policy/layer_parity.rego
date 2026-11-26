# S07, local part (spec 001, matrix S07; contracts/layers.md, "Règle de
# parité"; FR-010; ADR-007, condition 5; ADR-010, condition 1): the common
# layer rendered alone is found again, unchanged, in the render of the local
# target, and the local layer adds nothing that does not come from one of its
# files.
# 1. Each object of the common render is in the local render, equal to the
#    field: the two fields that a target sets are left out of the comparison,
#    spec.gatewayClassName of the Gateway and spec.hostnames of the HTTPRoutes
#    (tasks.md, gap 141: the host of a target is its own, and Gateway API
#    refuses an IP in hostnames).
# 2. An object that the local render holds and the common render does not
#    comes from a file of the local layer (the third render, sources.yaml).
# 3. One Gateway per render (ADR-005, condition 5).
# 4. The references of the workloads of the common layer to ConfigMaps and
#    Secrets resolve: every ConfigMap they name is provided by the target,
#    every Secret they name is one of the contract (contracts/secrets.md), and
#    app-config holds exactly the keys of contracts/layers.md.
# 5. No render sets ASPNETCORE_ENVIRONMENT or DOTNET_ENVIRONMENT to
#    Development, which would show the stack trace (SECU review of step 3).
# 6. The HTTPRoutes of the common layer name no host, which is neutral; those
#    of the local render name localhost alone (tasks.md, gap 45).
#
# Input: three renders given to `conftest test --combine` by
# tests/static/s07-parity.sh, one entry per document with its path: the
# common layer alone, k8s/overlays/local (path ending in common.yaml);
# local/k8s/lite (lite.yaml); the objects that the files of the local layer
# define on their own (sources.yaml).
package layer_parity

label := "S07 (FR-010; ADR-007, condition 5; ADR-010, condition 1)"

common_file := `(^|/)common\.yaml$`

target_file := `(^|/)lite\.yaml$`

source_file := `(^|/)sources\.yaml$`

# What a target may set differently, by kind, as paths for json.remove.
target_fields := {
	"Gateway": ["spec/gatewayClassName"],
	"HTTPRoute": ["spec/hostnames"],
}

# The Secrets that the workloads of the common layer may name (contracts/secrets.md).
contract_secrets := {"db-auth", "cache-auth"}

# The keys of app-config (contracts/layers.md, "app-config").
app_config_keys := {
	"DATABASE_HOST", "DATABASE_PORT", "DATABASE_NAME", "DATABASE_SSL_MODE",
	"CACHE_HOST", "CACHE_PORT", "CACHE_TLS_MODE", "CACHE_TLS_CA_FILE",
}

# The host that the local layer gives to its routes, and shows the user.
local_host := "localhost"

documents(pattern) := [doc |
	some file in input
	regex.match(pattern, file.path)
	doc := file.contents
	is_object(doc)
]

object_key(doc) := sprintf("%s/%s", [doc.kind, doc.metadata.name])

keys(pattern) := {object_key(doc) | some doc in documents(pattern)}

normalized(doc) := json.remove(doc, target_fields[doc.kind]) if target_fields[doc.kind]

normalized(doc) := doc if not target_fields[doc.kind]

deny contains msg if {
	some pattern in [common_file, target_file, source_file]
	count(documents(pattern)) == 0
	msg := sprintf("%s: no document of a render matching %s among the checked files", [label, pattern])
}

# --- 1. The common layer is found again ----------------------------------------

deny contains msg if {
	some common in documents(common_file)
	count([doc | some doc in documents(target_file); object_key(doc) == object_key(common)]) != 1
	msg := sprintf("%s: %s of the common layer is not found exactly once in the local render", [label, object_key(common)])
}

deny contains msg if {
	some common in documents(common_file)
	some target in documents(target_file)
	object_key(target) == object_key(common)
	normalized(common) != normalized(target)
	msg := sprintf("%s: %s differs between the common layer and the local render, beyond %v", [label, object_key(common), object.get(target_fields, common.kind, [])])
}

# --- 2. What the local layer adds comes from its files --------------------------

deny contains msg if {
	some target in documents(target_file)
	not object_key(target) in keys(common_file)
	not object_key(target) in keys(source_file)
	msg := sprintf("%s: %s is in the local render, and in neither the common layer nor a file of the local layer", [label, object_key(target)])
}

# --- 3. One Gateway per render ----------------------------------------------------

deny contains msg if {
	some pattern in [common_file, target_file]
	gateways := [doc | some doc in documents(pattern); doc.kind == "Gateway"]
	count(gateways) != 1
	msg := sprintf("%s: a render matching %s holds %d Gateway, one expected (ADR-005, condition 5)", [label, pattern, count(gateways)])
}

# --- 4. The references ------------------------------------------------------------

pod_spec(doc) := doc.spec.template.spec if doc.kind in {"Deployment", "StatefulSet", "Job", "DaemonSet"}

containers_of(spec) := array.concat(object.get(spec, "containers", []), object.get(spec, "initContainers", []))

config_map_refs(doc) := {name |
	spec := pod_spec(doc)
	some container in containers_of(spec)
	some source in object.get(container, "envFrom", [])
	name := source.configMapRef.name
} | {name |
	spec := pod_spec(doc)
	some container in containers_of(spec)
	some variable in object.get(container, "env", [])
	name := variable.valueFrom.configMapKeyRef.name
} | {name |
	spec := pod_spec(doc)
	some volume in object.get(spec, "volumes", [])
	name := volume.configMap.name
}

secret_refs(doc) := {name |
	spec := pod_spec(doc)
	some container in containers_of(spec)
	some source in object.get(container, "envFrom", [])
	name := source.secretRef.name
} | {name |
	spec := pod_spec(doc)
	some container in containers_of(spec)
	some variable in object.get(container, "env", [])
	name := variable.valueFrom.secretKeyRef.name
} | {name |
	spec := pod_spec(doc)
	some volume in object.get(spec, "volumes", [])
	name := volume.secret.secretName
}

target_config_maps := {doc.metadata.name | some doc in documents(target_file); doc.kind == "ConfigMap"}

deny contains msg if {
	some common in documents(common_file)
	some name in config_map_refs(common)
	not name in target_config_maps
	msg := sprintf("%s: %s names the ConfigMap %s, which the local render does not provide", [label, object_key(common), name])
}

deny contains msg if {
	some common in documents(common_file)
	some name in secret_refs(common)
	not name in contract_secrets
	msg := sprintf("%s: %s names the Secret %s, which is not one of contracts/secrets.md (%v)", [label, object_key(common), name, contract_secrets])
}

deny contains msg if {
	some target in documents(target_file)
	target.kind == "ConfigMap"
	target.metadata.name == "app-config"
	found := {key | some key, _ in object.get(target, "data", {})}
	found != app_config_keys
	msg := sprintf("%s: app-config holds the keys %v, contracts/layers.md fixes %v", [label, found, app_config_keys])
}

deny contains msg if {
	count([doc | some doc in documents(target_file); doc.kind == "ConfigMap"; doc.metadata.name == "app-config"]) != 1
	msg := sprintf("%s: the local render holds no single ConfigMap app-config, which the workloads of the common layer read", [label])
}

# --- 5. No Development environment -------------------------------------------------

environment_names := {"ASPNETCORE_ENVIRONMENT", "DOTNET_ENVIRONMENT"}

deny contains msg if {
	some pattern in [common_file, target_file]
	some doc in documents(pattern)
	walk(doc, [path, value])
	is_object(value)
	value.name in environment_names
	lower(object.get(value, "value", "")) == "development"
	msg := sprintf("%s: %s sets %s to Development (%v), which shows the stack trace", [label, object_key(doc), value.name, path])
}

deny contains msg if {
	some pattern in [common_file, target_file]
	some doc in documents(pattern)
	doc.kind == "ConfigMap"
	some name in environment_names
	lower(object.get(object.get(doc, "data", {}), name, "")) == "development"
	msg := sprintf("%s: the ConfigMap %s sets %s to Development, which shows the stack trace", [label, doc.metadata.name, name])
}

# --- 6. The hosts of the routes -------------------------------------------------------

deny contains msg if {
	some route in documents(common_file)
	route.kind == "HTTPRoute"
	object.get(route.spec, "hostnames", null) != null
	msg := sprintf("%s: %s of the common layer names hostnames; the host of a target is set by its layer", [label, object_key(route)])
}

deny contains msg if {
	some route in documents(target_file)
	route.kind == "HTTPRoute"
	object.get(route.spec, "hostnames", null) != [local_host]
	msg := sprintf("%s: %s of the local render must name the hostname %s alone, found %v (tasks.md, gap 45)", [label, object_key(route), local_host, object.get(route.spec, "hostnames", null)])
}
