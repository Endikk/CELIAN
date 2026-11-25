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
# - the controller image and both charts come from one release, the one
#   local/tasks/local.yml names, and the render says the same chart.
#
# Input: the three vendored files given to `conftest test --combine`, one
# entry per YAML document with its `path` and parsed `contents` (research
# RS-18). Data: `envoy_gateway`, the three references of local/tasks/local.yml
# (controller, gateway-helm, gateway-crds-helm), written by
# local/tests/static/s22-envoy-charts.sh.
package envoy_render

label := "S22 (FR-008; ADR-005, condition 1)"

gateway_api_file := `(^|/)local/vendor/gateway-api/standard-install\.yaml$`

crds_render_file := `(^|/)local/vendor/envoy-gateway/gateway-crds-helm\.yaml$`

helm_render_file := `(^|/)local/vendor/envoy-gateway/gateway-helm\.yaml$`

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
	some pattern in [gateway_api_file, crds_render_file, helm_render_file]
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
