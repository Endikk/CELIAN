# S22: the vendored platform of the local layer keeps the settings of
# ADR-005 (spec 001, plan, matrix S22; ADR-005, condition 1):
# - every CRD of gateway.networking.k8s.io comes from the verified
#   standard-install.yaml of Gateway API, standard channel, one bundle
#   version; none comes from a chart of Envoy Gateway;
# - the render of gateway-crds-helm holds the CRDs of gateway.envoyproxy.io
#   and nothing else (crds.envoyGateway.enabled=true,
#   crds.gatewayAPI.enabled=false);
# - the render of gateway-helm holds no CRD (crds.enabled=false), and every
#   image it names is the controller image of local/tasks/local.yml, by
#   digest (global.images.envoyGateway.image), the configuration of the
#   controller included;
# - the ratelimit image, which the chart names by tag, never runs: the
#   configuration has no rateLimit, or the image is pinned by digest;
# - the render of gateway-helm holds the 21 objects of the frozen list, by
#   kind, namespace and name, and no more; no binding goes to the ClusterRole
#   cluster-admin, and no Role nor ClusterRole of the render grants the
#   verb *: a new release that adds an object or a right shows in the review;
# - the controller watches the namespaces of the project alone, its own and
#   the one of the application (provider.kubernetes.watch, type Namespaces;
#   ADR-005, complement of 2026-11-25): no ClusterRole of the render grants
#   a right on Secrets or pods, and every namespaced object of the render
#   lives in one of these two namespaces;
# - the namespace envoy-gateway-system enforces Pod Security, at baseline or
#   restricted;
# - the controller image and both charts come from one release, the one
#   local/tasks/local.yml names, and the render says the same chart.
#
# Input: the three vendored files, local/platform/namespace.yaml and the
# namespace of the application, k8s/base/namespace.yaml, given to
# `conftest test --combine`, one entry per YAML document with its `path` and
# parsed `contents` (research RS-18). Data: `envoy_gateway`, the three
# references of local/tasks/local.yml
# (controller, gateway-helm, gateway-crds-helm), written by
# local/tests/static/s22-envoy-charts.sh.
package envoy_render

label := "S22 (FR-008; ADR-005, condition 1)"

gateway_api_file := `(^|/)local/vendor/gateway-api/standard-install\.yaml$`

crds_render_file := `(^|/)local/vendor/envoy-gateway/gateway-crds-helm\.yaml$`

helm_render_file := `(^|/)local/vendor/envoy-gateway/gateway-helm\.yaml$`

namespace_file := `(^|/)local/platform/namespace\.yaml$`

app_namespace_file := `(^|/)k8s/base/namespace\.yaml$`

controller_namespace := "envoy-gateway-system"

gateway_api_groups := {"gateway.networking.k8s.io", "gateway.networking.x-k8s.io"}

default refs := {}

refs := data.envoy_gateway

# A reference of release v<x.y.z> of Envoy Gateway on Docker Hub, by tag and
# digest: group 1 is the tag.
reference_patterns := {
	"controller": `^docker\.io/envoyproxy/gateway:(v[0-9]+\.[0-9]+\.[0-9]+)@sha256:[a-f0-9]{64}$`,
	"helm_chart": `^docker\.io/envoyproxy/gateway-helm:(v[0-9]+\.[0-9]+\.[0-9]+)@sha256:[a-f0-9]{64}$`,
	"crds_chart": `^docker\.io/envoyproxy/gateway-crds-helm:(v[0-9]+\.[0-9]+\.[0-9]+)@sha256:[a-f0-9]{64}$`,
}

tag_of(name) := tag if {
	value := refs[name]
	is_string(value)
	parts := regex.find_all_string_submatch_n(reference_patterns[name], value, 1)
	count(parts) == 1
	tag := parts[0][1]
}

deny contains msg if {
	some name, _ in reference_patterns
	not tag_of(name)
	msg := sprintf("%s: the %s reference of local/tasks/local.yml must be a tag and a sha256 digest of Envoy Gateway, found %v", [label, name, object.get(refs, name, null)])
}

deny contains msg if {
	tags := {tag | some name, _ in reference_patterns; tag := tag_of(name)}
	count(tags) > 1
	msg := sprintf("%s: the controller image and both charts come from one release of Envoy Gateway; local/tasks/local.yml names %v", [label, tags])
}

documents(pattern) := [doc |
	some file in input
	regex.match(pattern, file.path)
	doc := file.contents
	is_object(doc)
]

deny contains msg if {
	some pattern in [gateway_api_file, crds_render_file, helm_render_file, namespace_file, app_namespace_file]
	count(documents(pattern)) == 0
	msg := sprintf("%s: no document of a file matching %s among the checked files", [label, pattern])
}

is_crd(doc) if doc.kind == "CustomResourceDefinition"

crd_group(doc) := object.get(object.get(doc, "spec", {}), "group", "")

# Every CRD of Gateway API comes from standard-install.yaml.
deny contains msg if {
	some file in input
	not regex.match(gateway_api_file, file.path)
	is_object(file.contents)
	is_crd(file.contents)
	crd_group(file.contents) in gateway_api_groups
	msg := sprintf("%s: %s holds the CRD %v of Gateway API; they come from the verified standard-install.yaml only", [label, file.path, file.contents.metadata.name])
}

annotations(doc) := object.get(object.get(doc, "metadata", {}), "annotations", {})

deny contains msg if {
	some doc in documents(gateway_api_file)
	is_crd(doc)
	crd_group(doc) != "gateway.networking.k8s.io"
	msg := sprintf("%s: standard-install.yaml holds the CRD %v of group %v, gateway.networking.k8s.io expected", [label, doc.metadata.name, crd_group(doc)])
}

deny contains msg if {
	some doc in documents(gateway_api_file)
	is_crd(doc)
	object.get(annotations(doc), "gateway.networking.k8s.io/channel", null) != "standard"
	msg := sprintf("%s: the CRD %v of standard-install.yaml is not of the standard channel", [label, doc.metadata.name])
}

deny contains msg if {
	versions := {v | some doc in documents(gateway_api_file); is_crd(doc); v := object.get(annotations(doc), "gateway.networking.k8s.io/bundle-version", null)}
	count(versions) != 1
	msg := sprintf("%s: the CRDs of standard-install.yaml carry the bundle versions %v, one expected", [label, versions])
}

deny contains msg if {
	some doc in documents(crds_render_file)
	not is_crd(doc)
	msg := sprintf("%s: the render of gateway-crds-helm holds a %v; CRDs only are expected", [label, object.get(doc, "kind", null)])
}

deny contains msg if {
	some doc in documents(crds_render_file)
	is_crd(doc)
	crd_group(doc) != "gateway.envoyproxy.io"
	msg := sprintf("%s: the render of gateway-crds-helm holds the CRD %v of group %v; crds.envoyGateway.enabled=true and crds.gatewayAPI.enabled=false leave gateway.envoyproxy.io alone", [label, doc.metadata.name, crd_group(doc)])
}

deny contains msg if {
	some doc in documents(helm_render_file)
	is_crd(doc)
	msg := sprintf("%s: the render of gateway-helm holds the CRD %v; it is rendered with crds.enabled=false", [label, doc.metadata.name])
}

# Every value of an `image` key, at any depth, in the documents of the render
# of gateway-helm.
helm_images contains [doc_name, image] if {
	some doc in documents(helm_render_file)
	walk(doc, [path, image])
	count(path) > 0
	path[count(path) - 1] == "image"
	is_string(image)
	doc_name := sprintf("%v %v", [object.get(doc, "kind", null), object.get(object.get(doc, "metadata", {}), "name", null)])
}

deny contains msg if {
	is_string(refs.controller)
	some [doc_name, image] in helm_images
	image != refs.controller
	msg := sprintf("%s: %v in the render of gateway-helm runs %v; the controller image of local/tasks/local.yml, %v, is expected (global.images.envoyGateway.image)", [label, doc_name, image, refs.controller])
}

deny contains msg if {
	count(documents(helm_render_file)) > 0
	count(helm_images) == 0
	msg := sprintf("%s: the render of gateway-helm names no image", [label])
}

# The configuration of the controller, a YAML document inside a ConfigMap.
controller_config := config if {
	some doc in documents(helm_render_file)
	doc.kind == "ConfigMap"
	text := doc.data["envoy-gateway.yaml"]
	config := yaml.unmarshal(text)
}

deny contains msg if {
	count(documents(helm_render_file)) > 0
	not controller_config
	msg := sprintf("%s: the render of gateway-helm has no ConfigMap with the configuration envoy-gateway.yaml", [label])
}

config_images contains [path, image] if {
	walk(controller_config, [path, image])
	count(path) > 0
	path[count(path) - 1] == "image"
	is_string(image)
}

ratelimit_path := ["provider", "kubernetes", "rateLimitDeployment", "container", "image"]

pinned(image) if regex.match(`@sha256:[a-f0-9]{64}$`, image)

deny contains msg if {
	some [path, image] in config_images
	path != ratelimit_path
	is_string(refs.controller)
	image != refs.controller
	msg := sprintf("%s: the configuration of the controller names %v at %v; the controller image of local/tasks/local.yml is expected", [label, image, concat(".", path)])
}

# ADR-005, condition 1: the ratelimit image is pinned once rate limiting is on.
deny contains msg if {
	object.get(controller_config, "rateLimit", null) != null
	some [path, image] in config_images
	path == ratelimit_path
	not pinned(image)
	msg := sprintf("%s: rate limiting is on (rateLimit) and the ratelimit image %v has no digest", [label, image])
}

deny contains msg if {
	tag := tag_of("helm_chart")
	expected := sprintf("gateway-helm-%s", [tag])
	some doc in documents(helm_render_file)
	chart := object.get(object.get(object.get(doc, "metadata", {}), "labels", {}), "helm.sh/chart", null)
	chart != null
	chart != expected
	msg := sprintf("%s: %v %v of the render of gateway-helm comes from the chart %v; local/tasks/local.yml names %v: redo the render", [label, doc.kind, doc.metadata.name, chart, expected])
}

deny contains msg if {
	tag_of("helm_chart")
	charts := {chart | some doc in documents(helm_render_file); chart := doc.metadata.labels["helm.sh/chart"]}
	count(charts) == 0
	msg := sprintf("%s: no object of the render of gateway-helm carries the label helm.sh/chart", [label])
}

# The objects of the render of gateway-helm of release v1.10.0, rendered
# with the watch of the controller (ADR-005, complement of 2026-11-25), by
# kind, namespace and name: 21 documents. A new release that adds, drops,
# renames or moves one fails here until the list is read again (SECU review
# of step 7). The watch adds a Role and a RoleBinding in each namespace it
# names, and leaves the ClusterRole with the cluster-scoped rights alone.
frozen_objects := {
	"ClusterRole/eg-gateway-helm-certgen:envoy-gateway-system",
	"ClusterRole/eg-gateway-helm-envoy-gateway-role",
	"ClusterRoleBinding/eg-gateway-helm-certgen:envoy-gateway-system",
	"ClusterRoleBinding/eg-gateway-helm-envoy-gateway-rolebinding",
	"ConfigMap/envoy-gateway-system/envoy-gateway-config",
	"Deployment/envoy-gateway-system/envoy-gateway",
	"Job/envoy-gateway-system/eg-gateway-helm-certgen",
	"MutatingWebhookConfiguration/envoy-gateway-topology-injector.envoy-gateway-system",
	"Role/envoy-gateway-system/eg-gateway-helm-certgen",
	"Role/envoy-gateway-system/eg-gateway-helm-envoy-gateway-role",
	"Role/envoy-gateway-system/eg-gateway-helm-infra-manager",
	"Role/envoy-gateway-system/eg-gateway-helm-leader-election-role",
	"Role/saas-b2b/eg-gateway-helm-envoy-gateway-role",
	"RoleBinding/envoy-gateway-system/eg-gateway-helm-certgen",
	"RoleBinding/envoy-gateway-system/eg-gateway-helm-envoy-gateway-rolebinding",
	"RoleBinding/envoy-gateway-system/eg-gateway-helm-infra-manager",
	"RoleBinding/envoy-gateway-system/eg-gateway-helm-leader-election-rolebinding",
	"RoleBinding/saas-b2b/eg-gateway-helm-envoy-gateway-rolebinding",
	"Service/envoy-gateway-system/envoy-gateway",
	"ServiceAccount/envoy-gateway-system/eg-gateway-helm-certgen",
	"ServiceAccount/envoy-gateway-system/envoy-gateway",
}

object_namespace(doc) := object.get(object.get(doc, "metadata", {}), "namespace", "")

object_name(doc) := object.get(object.get(doc, "metadata", {}), "name", null)

# Kind/namespace/name for a namespaced object, Kind/name for the others.
object_id(doc) := sprintf("%v/%v/%v", [object.get(doc, "kind", null), object_namespace(doc), object_name(doc)]) if {
	object_namespace(doc) != ""
} else := sprintf("%v/%v", [object.get(doc, "kind", null), object_name(doc)])

# "Kind namespace/name" or "Kind name", for the messages.
describe(doc) := sprintf("%v %v/%v", [object.get(doc, "kind", null), object_namespace(doc), object_name(doc)]) if {
	object_namespace(doc) != ""
} else := sprintf("%v %v", [object.get(doc, "kind", null), object_name(doc)])

describe_id(id) := sprintf("%s %s/%s", [parts[0], parts[1], parts[2]]) if {
	parts := split(id, "/")
	count(parts) == 3
} else := concat(" ", split(id, "/"))

deny contains msg if {
	some doc in documents(helm_render_file)
	not object_id(doc) in frozen_objects
	msg := sprintf("%s: the render of gateway-helm holds %s, which the frozen list of %d objects of envoy_render.rego does not name; read the new object, then change the list", [label, describe(doc), count(frozen_objects)])
}

deny contains msg if {
	count(documents(helm_render_file)) > 0
	some id in frozen_objects
	not id in {object_id(doc) | some doc in documents(helm_render_file)}
	msg := sprintf("%s: the render of gateway-helm lacks %s, which the frozen list of %d objects names", [label, describe_id(id), count(frozen_objects)])
}

deny contains msg if {
	count(documents(helm_render_file)) > count(frozen_objects)
	msg := sprintf("%s: the render of gateway-helm holds %d documents, the frozen list names %d objects", [label, count(documents(helm_render_file)), count(frozen_objects)])
}

# The namespaces of the project: the one of the controller, and the one of
# the application, declared by k8s/base/namespace.yaml.
app_namespaces contains name if {
	some doc in documents(app_namespace_file)
	doc.kind == "Namespace"
	name := object_name(doc)
	is_string(name)
}

project_namespaces := {controller_namespace} | app_namespaces

deny contains msg if {
	count(documents(app_namespace_file)) > 0
	count(app_namespaces) != 1
	msg := sprintf("%s: k8s/base/namespace.yaml declares the namespaces %v of the application, one expected", [label, app_namespaces])
}

# The watch of the controller (ADR-005, complement of 2026-11-25): without
# it, the controller reconciles every namespace, and the chart gives it the
# right to read the Secrets and to patch the pods of the whole cluster.
watch_path := ["provider", "kubernetes", "watch"]

controller_watch := object.get(controller_config, watch_path, null)

watched_namespaces := {name | is_object(controller_watch); some name in object.get(controller_watch, "namespaces", [])}

deny contains msg if {
	controller_config
	not is_object(controller_watch)
	msg := sprintf("%s: the configuration of the controller has no provider.kubernetes.watch; it would watch every namespace, and the chart would let it read the Secrets and patch the pods of the whole cluster (ADR-005, complement of 2026-11-25)", [label])
}

deny contains msg if {
	is_object(controller_watch)
	object.get(controller_watch, "type", null) != "Namespaces"
	msg := sprintf("%s: provider.kubernetes.watch.type of the configuration of the controller is %v; Namespaces expected, with the namespaces of the project (ADR-005, complement of 2026-11-25)", [label, object.get(controller_watch, "type", null)])
}

deny contains msg if {
	is_object(controller_watch)
	count(app_namespaces) == 1
	watched_namespaces != project_namespaces
	msg := sprintf("%s: the controller watches the namespaces %v; the namespaces of the project, %v, are expected, and no other (ADR-005, complement of 2026-11-25)", [label, watched_namespaces, project_namespaces])
}

# What the watch leaves cluster-wide: no right on the Secrets nor on the
# pods, and no wildcard resource, in any ClusterRole of the render.
cluster_sensitive_resources := {"secrets", "pods", "pods/binding", "*"}

deny contains msg if {
	some doc in documents(helm_render_file)
	doc.kind == "ClusterRole"
	some rule in object.get(doc, "rules", [])
	some resource in object.get(rule, "resources", [])
	resource in cluster_sensitive_resources
	msg := sprintf("%s: %s in the render of gateway-helm grants %v on %s across the cluster; the watch of the controller keeps these rights in the namespaces of the project (ADR-005, complement of 2026-11-25)", [label, describe(doc), object.get(rule, "verbs", []), resource])
}

deny contains msg if {
	count(app_namespaces) == 1
	some doc in documents(helm_render_file)
	namespace := object_namespace(doc)
	namespace != ""
	not namespace in project_namespaces
	msg := sprintf("%s: %s of the render of gateway-helm lives outside the namespaces of the project, %v", [label, describe(doc), project_namespaces])
}

# No binding to cluster-admin, no verb * in a Role or a ClusterRole of the
# render: the rights of the controller are the ones the chart writes, none
# is the wildcard.
deny contains msg if {
	some doc in documents(helm_render_file)
	doc.kind in {"ClusterRoleBinding", "RoleBinding"}
	object.get(object.get(doc, "roleRef", {}), "name", null) == "cluster-admin"
	msg := sprintf("%s: %s in the render of gateway-helm binds to cluster-admin", [label, describe(doc)])
}

deny contains msg if {
	some doc in documents(helm_render_file)
	doc.kind in {"ClusterRole", "Role"}
	some rule in object.get(doc, "rules", [])
	"*" in object.get(rule, "verbs", [])
	msg := sprintf("%s: %s in the render of gateway-helm grants the verb *", [label, describe(doc)])
}

# Pod Security on the namespace of Envoy Gateway.
pod_security_label := "pod-security.kubernetes.io/enforce"

pod_security_levels := {"baseline", "restricted"}

namespace_docs := [doc |
	some doc in documents(namespace_file)
	doc.kind == "Namespace"
	object.get(object.get(doc, "metadata", {}), "name", null) == "envoy-gateway-system"
]

deny contains msg if {
	count(documents(namespace_file)) > 0
	count(namespace_docs) == 0
	msg := sprintf("%s: local/platform/namespace.yaml declares no Namespace envoy-gateway-system", [label])
}

deny contains msg if {
	some doc in namespace_docs
	level := object.get(object.get(object.get(doc, "metadata", {}), "labels", {}), pod_security_label, null)
	not level in pod_security_levels
	msg := sprintf("%s: the namespace envoy-gateway-system needs %s at baseline or restricted, found %v", [label, pod_security_label, level])
}
