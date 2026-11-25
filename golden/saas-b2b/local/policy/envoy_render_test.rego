# Tests of S22 (envoy_render.rego), run by `conftest verify`.
package envoy_render

controller := "docker.io/envoyproxy/gateway:v1.10.0@sha256:c2243d43518bed91d3ed8c2db849a4b7a14ac9b96eb019f2ab104bb1ca8572b1"

helm_chart := "docker.io/envoyproxy/gateway-helm:v1.10.0@sha256:dcb82a14c04b426615a71d97222c7edf9f5ff58b800d241e71ac5784ae6dc7b7"

crds_chart := "docker.io/envoyproxy/gateway-crds-helm:v1.10.0@sha256:475c39aad3a05e3974a29fb80cfefe882b743e45e2ec0f751790ff0cb83bfa5d"

references := {"controller": controller, "helm_chart": helm_chart, "crds_chart": crds_chart}

gateway_api_path := "local/vendor/gateway-api/standard-install.yaml"

crds_path := "local/vendor/envoy-gateway/gateway-crds-helm.yaml"

helm_path := "local/vendor/envoy-gateway/gateway-helm.yaml"

namespace_path := "local/platform/namespace.yaml"

crd(name, group, annotations) := {
	"apiVersion": "apiextensions.k8s.io/v1",
	"kind": "CustomResourceDefinition",
	"metadata": {"name": name, "annotations": annotations},
	"spec": {"group": group},
}

standard := {"gateway.networking.k8s.io/bundle-version": "v1.7.0", "gateway.networking.k8s.io/channel": "standard"}

labels := {"helm.sh/chart": "gateway-helm-v1.10.0"}

controller_ns := "envoy-gateway-system"

app_ns := "saas-b2b"

app_namespace_path := "k8s/base/namespace.yaml"

# The kinds of the render that live in a namespace: the fixtures put them in
# the namespace of the controller, as helm template -n does.
namespaced_kinds := {"ConfigMap", "Deployment", "Job", "Role", "RoleBinding", "Secret", "Service", "ServiceAccount"}

meta_in(ns, name) := {"name": name, "namespace": ns, "labels": labels}

meta(kind, name) := meta_in(controller_ns, name) if {
	kind in namespaced_kinds
} else := {"name": name, "labels": labels}

# The watch of the controller (ADR-005, complement of 2026-11-25).
watch := {"type": "Namespaces", "namespaces": [controller_ns, app_ns]}

config_object := {
	"apiVersion": "gateway.envoyproxy.io/v1alpha1",
	"kind": "EnvoyGateway",
	"provider": {"type": "Kubernetes", "kubernetes": {
		"rateLimitDeployment": {"container": {"image": "docker.io/envoyproxy/ratelimit:5ae0682e"}},
		"shutdownManager": {"image": controller},
		"watch": watch,
	}},
}

config(extra) := yaml.marshal(object.union(config_object, extra))

configmap(text) := {
	"apiVersion": "v1",
	"kind": "ConfigMap",
	"metadata": meta("ConfigMap", "envoy-gateway-config"),
	"data": {"envoy-gateway.yaml": text},
}

deployment(image) := {
	"apiVersion": "apps/v1",
	"kind": "Deployment",
	"metadata": meta("Deployment", "envoy-gateway"),
	"spec": {"template": {"spec": {"containers": [{"name": "envoy-gateway", "image": image}]}}},
}

job(image) := {
	"apiVersion": "batch/v1",
	"kind": "Job",
	"metadata": meta("Job", "eg-gateway-helm-certgen"),
	"spec": {"template": {"spec": {"containers": [{"name": "envoy-gateway-certgen", "image": image}]}}},
}

# An object of the render of gateway-helm that the checks only name.
stub(kind, name) := {"apiVersion": "v1", "kind": kind, "metadata": meta(kind, name)}

role(kind, name, verbs) := {
	"apiVersion": "rbac.authorization.k8s.io/v1",
	"kind": kind,
	"metadata": meta(kind, name),
	"rules": [{"apiGroups": [""], "resources": ["configmaps"], "verbs": verbs}],
}

binding(kind, name, role_kind, role_name) := {
	"apiVersion": "rbac.authorization.k8s.io/v1",
	"kind": kind,
	"metadata": meta(kind, name),
	"roleRef": {"apiGroup": "rbac.authorization.k8s.io", "kind": role_kind, "name": role_name},
	"subjects": [{"kind": "ServiceAccount", "name": "envoy-gateway", "namespace": "envoy-gateway-system"}],
}

# The namespaced rights of the controller, which the watch puts in a Role of
# each watched namespace (_rbac.tpl of the chart, eg.rbac.namespaced).
namespaced_rules := [
	{"apiGroups": [""], "resources": ["configmaps", "secrets", "services"], "verbs": ["get", "list", "watch"]},
	{"apiGroups": [""], "resources": ["pods", "pods/binding"], "verbs": ["get", "list", "patch", "update", "watch"]},
]

role_in(ns, name, rules) := {
	"apiVersion": "rbac.authorization.k8s.io/v1",
	"kind": "Role",
	"metadata": meta_in(ns, name),
	"rules": rules,
}

binding_in(ns, name, role_name) := {
	"apiVersion": "rbac.authorization.k8s.io/v1",
	"kind": "RoleBinding",
	"metadata": meta_in(ns, name),
	"roleRef": {"apiGroup": "rbac.authorization.k8s.io", "kind": "Role", "name": role_name},
	"subjects": [{"kind": "ServiceAccount", "name": "envoy-gateway", "namespace": "envoy-gateway-system"}],
}

cluster_role(name, rules) := {
	"apiVersion": "rbac.authorization.k8s.io/v1",
	"kind": "ClusterRole",
	"metadata": meta("ClusterRole", name),
	"rules": rules,
}

# The 14 objects of the render that step 7 froze, besides the ConfigMap, the
# Deployment and the Job.
other_objects := [
	role("ClusterRole", "eg-gateway-helm-certgen:envoy-gateway-system", ["get", "update"]),
	role("ClusterRole", "eg-gateway-helm-envoy-gateway-role", ["get", "list", "watch"]),
	binding("ClusterRoleBinding", "eg-gateway-helm-certgen:envoy-gateway-system", "ClusterRole", "eg-gateway-helm-certgen:envoy-gateway-system"),
	binding("ClusterRoleBinding", "eg-gateway-helm-envoy-gateway-rolebinding", "ClusterRole", "eg-gateway-helm-envoy-gateway-role"),
	stub("MutatingWebhookConfiguration", "envoy-gateway-topology-injector.envoy-gateway-system"),
	role("Role", "eg-gateway-helm-certgen", ["get", "update"]),
	role("Role", "eg-gateway-helm-infra-manager", ["create", "get"]),
	role("Role", "eg-gateway-helm-leader-election-role", ["get", "update"]),
	binding("RoleBinding", "eg-gateway-helm-certgen", "Role", "eg-gateway-helm-certgen"),
	binding("RoleBinding", "eg-gateway-helm-infra-manager", "Role", "eg-gateway-helm-infra-manager"),
	binding("RoleBinding", "eg-gateway-helm-leader-election-rolebinding", "Role", "eg-gateway-helm-leader-election-role"),
	stub("Service", "envoy-gateway"),
	stub("ServiceAccount", "eg-gateway-helm-certgen"),
	stub("ServiceAccount", "envoy-gateway"),
]

# The 4 objects that the watch adds: a Role and its RoleBinding in each
# watched namespace.
watch_objects := [
	role_in(controller_ns, "eg-gateway-helm-envoy-gateway-role", namespaced_rules),
	role_in(app_ns, "eg-gateway-helm-envoy-gateway-role", namespaced_rules),
	binding_in(controller_ns, "eg-gateway-helm-envoy-gateway-rolebinding", "eg-gateway-helm-envoy-gateway-role"),
	binding_in(app_ns, "eg-gateway-helm-envoy-gateway-rolebinding", "eg-gateway-helm-envoy-gateway-role"),
]

namespace(labels_of) := {
	"apiVersion": "v1",
	"kind": "Namespace",
	"metadata": {"name": "envoy-gateway-system", "labels": labels_of},
}

app_namespace(name) := {
	"apiVersion": "v1",
	"kind": "Namespace",
	"metadata": {"name": name, "labels": {"pod-security.kubernetes.io/enforce": "restricted"}},
}

base_files := [
	{"path": gateway_api_path, "contents": crd("gateways.gateway.networking.k8s.io", "gateway.networking.k8s.io", standard)},
	{"path": gateway_api_path, "contents": crd("httproutes.gateway.networking.k8s.io", "gateway.networking.k8s.io", standard)},
	{"path": crds_path, "contents": crd("envoyproxies.gateway.envoyproxy.io", "gateway.envoyproxy.io", {})},
	{"path": helm_path, "contents": configmap(config({}))},
	{"path": helm_path, "contents": deployment(controller)},
	{"path": helm_path, "contents": job(controller)},
]

# Indexes: 0 to 5 base_files, 6 to 19 other_objects, 20 the namespace of the
# controller, 21 to 24 watch_objects, 25 the namespace of the application.
valid_files := array.concat(
	array.concat(
		array.concat(base_files, [{"path": helm_path, "contents": obj} | some obj in other_objects]),
		[{"path": namespace_path, "contents": namespace({"pod-security.kubernetes.io/enforce": "restricted"})}],
	),
	array.concat(
		[{"path": helm_path, "contents": obj} | some obj in watch_objects],
		[{"path": app_namespace_path, "contents": app_namespace(app_ns)}],
	),
)

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

# The 21 objects of the render of gateway-helm are frozen by kind, namespace
# and name.
test_s22_rejects_an_object_added_to_the_render if {
	files := array.concat(valid_files, [{"path": helm_path, "contents": stub("Secret", "envoy-gateway-token")}])
	denied_with(files, references, "Secret envoy-gateway-system/envoy-gateway-token")
}

test_s22_rejects_an_object_missing_from_the_render if {
	files := [f | some i, f in valid_files; i != 8]
	denied_with(files, references, "ClusterRoleBinding eg-gateway-helm-certgen:envoy-gateway-system")
}

test_s22_rejects_an_object_renamed_in_the_render if {
	files := replace(valid_files, 19, {"path": helm_path, "contents": stub("ServiceAccount", "envoy-gateway-admin")})
	denied_with(files, references, "ServiceAccount envoy-gateway-system/envoy-gateway-admin")
}

test_s22_rejects_a_service_in_the_render_of_another_kind if {
	files := replace(valid_files, 17, {"path": helm_path, "contents": stub("Service", "envoy-gateway-admin")})
	denied_with(files, references, "frozen list")
}

test_s22_rejects_a_binding_to_cluster_admin if {
	files := array.concat(valid_files, [{"path": helm_path, "contents": binding("ClusterRoleBinding", "eg-gateway-helm-envoy-gateway-rolebinding", "ClusterRole", "cluster-admin")}])
	denied_with(files, references, "cluster-admin")
}

test_s22_rejects_a_role_binding_to_cluster_admin if {
	files := replace(valid_files, 14, {"path": helm_path, "contents": binding("RoleBinding", "eg-gateway-helm-certgen", "ClusterRole", "cluster-admin")})
	denied_with(files, references, "cluster-admin")
}

test_s22_rejects_the_wildcard_verb_in_a_cluster_role if {
	files := replace(valid_files, 7, {"path": helm_path, "contents": role("ClusterRole", "eg-gateway-helm-envoy-gateway-role", ["get", "*"])})
	denied_with(files, references, "verb *")
}

test_s22_rejects_the_wildcard_verb_in_a_role if {
	files := replace(valid_files, 12, {"path": helm_path, "contents": role("Role", "eg-gateway-helm-infra-manager", ["*"])})
	denied_with(files, references, "verb *")
}

# Pod Security on the namespace of Envoy Gateway (SECU review of the PR of
# step 7).
test_s22_rejects_a_missing_namespace_file if {
	files := [f | some f in valid_files; f.path != namespace_path]
	denied_with(files, references, "local/platform/namespace")
}

test_s22_rejects_a_namespace_without_pod_security if {
	files := replace(valid_files, 20, {"path": namespace_path, "contents": namespace({})})
	denied_with(files, references, "pod-security.kubernetes.io/enforce")
}

test_s22_rejects_a_privileged_namespace if {
	files := replace(valid_files, 20, {"path": namespace_path, "contents": namespace({"pod-security.kubernetes.io/enforce": "privileged"})})
	denied_with(files, references, "pod-security.kubernetes.io/enforce")
}

test_s22_accepts_the_baseline_namespace if {
	files := replace(valid_files, 20, {"path": namespace_path, "contents": namespace({"pod-security.kubernetes.io/enforce": "baseline"})})
	accepted(files, references)
}

# The watch of the controller: the namespaces of the project alone (ADR-005,
# complement of 2026-11-25; tasks.md, gap 43).
test_s22_rejects_a_configuration_without_watch if {
	text := yaml.marshal(json.remove(config_object, ["provider/kubernetes/watch"]))
	files := replace(valid_files, 3, {"path": helm_path, "contents": configmap(text)})
	denied_with(files, references, "has no provider.kubernetes.watch")
}

test_s22_rejects_a_watch_by_namespace_selector if {
	text := config({"provider": {"kubernetes": {"watch": {"type": "NamespaceSelector", "namespaceSelector": {"matchLabels": {"a": "b"}}}}}})
	files := replace(valid_files, 3, {"path": helm_path, "contents": configmap(text)})
	denied_with(files, references, "Namespaces expected")
}

test_s22_rejects_a_watch_of_another_namespace if {
	text := config({"provider": {"kubernetes": {"watch": {"type": "Namespaces", "namespaces": [controller_ns, app_ns, "default"]}}}})
	files := replace(valid_files, 3, {"path": helm_path, "contents": configmap(text)})
	denied_with(files, references, "and no other")
}

test_s22_rejects_a_watch_without_the_application if {
	text := config({"provider": {"kubernetes": {"watch": {"type": "Namespaces", "namespaces": [controller_ns]}}}})
	files := replace(valid_files, 3, {"path": helm_path, "contents": configmap(text)})
	denied_with(files, references, "and no other")
}

test_s22_rejects_a_watch_of_another_application_namespace if {
	files := replace(valid_files, 25, {"path": app_namespace_path, "contents": app_namespace("shop")})
	denied_with(files, references, "and no other")
}

test_s22_rejects_a_missing_application_namespace_file if {
	files := array.slice(valid_files, 0, 25)
	denied_with(files, references, "k8s/base/namespace")
}

test_s22_rejects_a_cluster_role_that_reads_secrets if {
	rules := [{"apiGroups": [""], "resources": ["nodes", "secrets"], "verbs": ["get", "list", "watch"]}]
	files := replace(valid_files, 7, {"path": helm_path, "contents": cluster_role("eg-gateway-helm-envoy-gateway-role", rules)})
	denied_with(files, references, "on secrets across the cluster")
}

test_s22_rejects_a_cluster_role_that_patches_pods if {
	rules := [{"apiGroups": [""], "resources": ["pods"], "verbs": ["patch", "update"]}]
	files := replace(valid_files, 7, {"path": helm_path, "contents": cluster_role("eg-gateway-helm-envoy-gateway-role", rules)})
	denied_with(files, references, "on pods across the cluster")
}

test_s22_rejects_a_cluster_role_on_every_resource if {
	rules := [{"apiGroups": ["*"], "resources": ["*"], "verbs": ["get"]}]
	files := replace(valid_files, 7, {"path": helm_path, "contents": cluster_role("eg-gateway-helm-envoy-gateway-role", rules)})
	denied_with(files, references, "across the cluster")
}

test_s22_rejects_a_role_outside_the_project_namespaces if {
	files := replace(valid_files, 22, {"path": helm_path, "contents": role_in("kube-system", "eg-gateway-helm-envoy-gateway-role", namespaced_rules)})
	denied_with(files, references, "outside the namespaces of the project")
}

test_s22_rejects_a_role_moved_to_another_namespace if {
	files := replace(valid_files, 24, {"path": helm_path, "contents": binding_in("default", "eg-gateway-helm-envoy-gateway-rolebinding", "eg-gateway-helm-envoy-gateway-role")})
	denied_with(files, references, "lacks RoleBinding saas-b2b/eg-gateway-helm-envoy-gateway-rolebinding")
}

test_s22_rejects_a_render_without_the_watch_roles if {
	files := array.concat(array.slice(valid_files, 0, 21), array.slice(valid_files, 25, 26))
	denied_with(files, references, "lacks Role saas-b2b/eg-gateway-helm-envoy-gateway-role")
}
