# Tests of S22 (envoy_render.rego), run by `conftest verify`.
package envoy_render

controller := "docker.io/envoyproxy/gateway:v1.10.0@sha256:c2243d43518bed91d3ed8c2db849a4b7a14ac9b96eb019f2ab104bb1ca8572b1"

helm_chart := "docker.io/envoyproxy/gateway-helm:v1.10.0@sha256:dcb82a14c04b426615a71d97222c7edf9f5ff58b800d241e71ac5784ae6dc7b7"

crds_chart := "docker.io/envoyproxy/gateway-crds-helm:v1.10.0@sha256:475c39aad3a05e3974a29fb80cfefe882b743e45e2ec0f751790ff0cb83bfa5d"

references := {"controller": controller, "helm_chart": helm_chart, "crds_chart": crds_chart}

gateway_api_path := "local/vendor/gateway-api/standard-install.yaml"

crds_path := "local/vendor/envoy-gateway/gateway-crds-helm.yaml"

helm_path := "local/vendor/envoy-gateway/gateway-helm.yaml"

crd(name, group, annotations) := {
	"apiVersion": "apiextensions.k8s.io/v1",
	"kind": "CustomResourceDefinition",
	"metadata": {"name": name, "annotations": annotations},
	"spec": {"group": group},
}

standard := {"gateway.networking.k8s.io/bundle-version": "v1.7.0", "gateway.networking.k8s.io/channel": "standard"}

labels := {"helm.sh/chart": "gateway-helm-v1.10.0"}

config(extra) := yaml.marshal(object.union({
	"apiVersion": "gateway.envoyproxy.io/v1alpha1",
	"kind": "EnvoyGateway",
	"provider": {"type": "Kubernetes", "kubernetes": {
		"rateLimitDeployment": {"container": {"image": "docker.io/envoyproxy/ratelimit:5ae0682e"}},
		"shutdownManager": {"image": controller},
	}},
}, extra))

configmap(text) := {
	"apiVersion": "v1",
	"kind": "ConfigMap",
	"metadata": {"name": "envoy-gateway-config", "labels": labels},
	"data": {"envoy-gateway.yaml": text},
}

deployment(image) := {
	"apiVersion": "apps/v1",
	"kind": "Deployment",
	"metadata": {"name": "envoy-gateway", "labels": labels},
	"spec": {"template": {"spec": {"containers": [{"name": "envoy-gateway", "image": image}]}}},
}

job(image) := {
	"apiVersion": "batch/v1",
	"kind": "Job",
	"metadata": {"name": "eg-gateway-helm-certgen", "labels": labels},
	"spec": {"template": {"spec": {"containers": [{"name": "envoy-gateway-certgen", "image": image}]}}},
}

valid_files := [
	{"path": gateway_api_path, "contents": crd("gateways.gateway.networking.k8s.io", "gateway.networking.k8s.io", standard)},
	{"path": gateway_api_path, "contents": crd("httproutes.gateway.networking.k8s.io", "gateway.networking.k8s.io", standard)},
	{"path": crds_path, "contents": crd("envoyproxies.gateway.envoyproxy.io", "gateway.envoyproxy.io", {})},
	{"path": helm_path, "contents": configmap(config({}))},
	{"path": helm_path, "contents": deployment(controller)},
	{"path": helm_path, "contents": job(controller)},
]

accepted(files, refs_data) if {
	msgs := deny with input as files with data.envoy_gateway as refs_data
	count(msgs) == 0
}

denied_with(files, refs_data, fragment) if {
	msgs := deny with input as files with data.envoy_gateway as refs_data
	some msg in msgs
	contains(msg, fragment)
}

replace(files, i, entry) := array.concat(array.slice(files, 0, i), array.concat([entry], array.slice(files, i + 1, count(files))))

test_s22_accepts_the_valid_render if {
	accepted(valid_files, references)
}

test_s22_accepts_the_files_under_the_golden_repo_of_celian if {
	files := [{"path": concat("", ["golden/saas-b2b/", f.path]), "contents": f.contents} | some f in valid_files]
	accepted(files, references)
}

test_s22_rejects_a_missing_file if {
	denied_with(array.slice(valid_files, 0, 3), references, "gateway-helm")
}

test_s22_rejects_a_gateway_api_crd_from_a_chart if {
	files := array.concat(valid_files, [{"path": crds_path, "contents": crd("gateways.gateway.networking.k8s.io", "gateway.networking.k8s.io", {})}])
	denied_with(files, references, "from the verified standard-install.yaml only")
}

test_s22_rejects_an_experimental_crd_from_a_chart if {
	files := array.concat(valid_files, [{"path": crds_path, "contents": crd("xbackendtrafficpolicies.gateway.networking.x-k8s.io", "gateway.networking.x-k8s.io", {})}])
	denied_with(files, references, "from the verified standard-install.yaml only")
}

test_s22_rejects_an_experimental_channel if {
	experimental := {"gateway.networking.k8s.io/bundle-version": "v1.7.0", "gateway.networking.k8s.io/channel": "experimental"}
	files := replace(valid_files, 1, {"path": gateway_api_path, "contents": crd("httproutes.gateway.networking.k8s.io", "gateway.networking.k8s.io", experimental)})
	denied_with(files, references, "not of the standard channel")
}

test_s22_rejects_two_bundle_versions if {
	older := {"gateway.networking.k8s.io/bundle-version": "v1.6.1", "gateway.networking.k8s.io/channel": "standard"}
	files := replace(valid_files, 1, {"path": gateway_api_path, "contents": crd("httproutes.gateway.networking.k8s.io", "gateway.networking.k8s.io", older)})
	denied_with(files, references, "one expected")
}

test_s22_rejects_another_object_in_the_crds_render if {
	files := array.concat(valid_files, [{"path": crds_path, "contents": deployment(controller)}])
	denied_with(files, references, "CRDs only are expected")
}

test_s22_rejects_a_crd_in_the_controller_render if {
	files := array.concat(valid_files, [{"path": helm_path, "contents": crd("envoyproxies.gateway.envoyproxy.io", "gateway.envoyproxy.io", {})}])
	denied_with(files, references, "crds.enabled=false")
}

test_s22_rejects_the_controller_by_tag if {
	files := replace(valid_files, 4, {"path": helm_path, "contents": deployment("docker.io/envoyproxy/gateway:v1.10.0")})
	denied_with(files, references, "global.images.envoyGateway.image")
}

test_s22_rejects_another_image_in_the_job if {
	files := replace(valid_files, 5, {"path": helm_path, "contents": job("docker.io/library/busybox:1.37.0@sha256:a7dbc319b1438115a207e11930dc4bb3e643dcb3ec0bdd694bb36cd8fad289ec")})
	denied_with(files, references, "Job eg-gateway-helm-certgen")
}

test_s22_rejects_another_shutdown_manager_image if {
	text := config({"provider": {"type": "Kubernetes", "kubernetes": {"shutdownManager": {"image": "docker.io/envoyproxy/gateway:v1.9.4"}}}})
	files := replace(valid_files, 3, {"path": helm_path, "contents": configmap(text)})
	denied_with(files, references, "provider.kubernetes.shutdownManager.image")
}

test_s22_rejects_rate_limiting_with_the_image_by_tag if {
	files := replace(valid_files, 3, {"path": helm_path, "contents": configmap(config({"rateLimit": {"backend": {"type": "Redis"}}}))})
	denied_with(files, references, "rate limiting is on")
}

test_s22_accepts_rate_limiting_with_the_image_by_digest if {
	pinned_ratelimit := "docker.io/envoyproxy/ratelimit:5ae0682e@sha256:b95206e32b1a5f824fb06062fbb85bbdfb7f5de54135e92afe8462f22c979681"
	text := config({
		"rateLimit": {"backend": {"type": "Redis"}},
		"provider": {"type": "Kubernetes", "kubernetes": {
			"rateLimitDeployment": {"container": {"image": pinned_ratelimit}},
			"shutdownManager": {"image": controller},
		}},
	})
	accepted(replace(valid_files, 3, {"path": helm_path, "contents": configmap(text)}), references)
}

test_s22_rejects_a_render_without_configuration if {
	files := array.concat(array.slice(valid_files, 0, 3), array.slice(valid_files, 4, 6))
	denied_with(files, references, "no ConfigMap with the configuration")
}

test_s22_rejects_a_render_of_another_chart if {
	refs_data := object.union(references, {"helm_chart": "docker.io/envoyproxy/gateway-helm:v1.10.1@sha256:dcb82a14c04b426615a71d97222c7edf9f5ff58b800d241e71ac5784ae6dc7b7"})
	denied_with(valid_files, refs_data, "redo the render")
}

test_s22_rejects_two_releases if {
	refs_data := object.union(references, {"crds_chart": "docker.io/envoyproxy/gateway-crds-helm:v1.10.1@sha256:475c39aad3a05e3974a29fb80cfefe882b743e45e2ec0f751790ff0cb83bfa5d"})
	denied_with(valid_files, refs_data, "one release of Envoy Gateway")
}

test_s22_rejects_a_reference_by_tag if {
	refs_data := object.union(references, {"controller": "docker.io/envoyproxy/gateway:v1.10.0"})
	denied_with(valid_files, refs_data, "the controller reference of local/tasks/local.yml")
}

test_s22_rejects_missing_references if {
	denied_with(valid_files, {}, "the helm_chart reference of local/tasks/local.yml")
}
