# Tests of S30 (app_workloads.rego), run by `conftest verify`.
package app_workloads

container_security := {
	"allowPrivilegeEscalation": false,
	"readOnlyRootFilesystem": true,
	"capabilities": {"drop": ["ALL"]},
}

resources := {"requests": {"cpu": "10m", "memory": "16Mi"}, "limits": {"memory": "64Mi"}}

probe(path) := {"httpGet": {"path": path, "port": 8080}}

make_deployment(name, user, container_extra, pod_extra) := {
	"apiVersion": "apps/v1",
	"kind": "Deployment",
	"metadata": {"name": name},
	"spec": {
		"selector": {"matchLabels": {"app.kubernetes.io/name": name}},
		"template": {
			"metadata": {"labels": {"app.kubernetes.io/name": name}},
			"spec": object.union({
				"automountServiceAccountToken": false,
				"securityContext": {"runAsNonRoot": true, "runAsUser": user, "seccompProfile": {"type": "RuntimeDefault"}},
				"containers": [object.union({
					"name": name,
					"image": sprintf("saas-b2b.invalid/%s:unbuilt", [name]),
					"imagePullPolicy": "IfNotPresent",
					"securityContext": container_security,
					"resources": resources,
				}, container_extra)],
			}, pod_extra),
		},
	},
}

make_service(name) := {
	"apiVersion": "v1",
	"kind": "Service",
	"metadata": {"name": name},
	"spec": {"selector": {"app.kubernetes.io/name": name}, "ports": [{"port": 80, "targetPort": 8080}]},
}

make_route(name) := {
	"apiVersion": "gateway.networking.k8s.io/v1",
	"kind": "HTTPRoute",
	"metadata": {"name": name},
	"spec": {"rules": [{"backendRefs": [{"name": name, "port": 80}]}]},
}

api := make_deployment(
	"api", 1654,
	{
		"readinessProbe": probe("/api/readyz"),
		"livenessProbe": probe("/api/healthz"),
		"envFrom": [{"configMapRef": {"name": "app-config"}}],
		"volumeMounts": [
			{"name": "db-auth", "mountPath": "/run/secrets/db-auth"},
			{"name": "cache-auth", "mountPath": "/run/secrets/cache-auth"},
			{"name": "tmp", "mountPath": "/tmp"},
		],
	},
	{"volumes": [
		{"name": "db-auth", "secret": {"secretName": "db-auth", "defaultMode": 288}},
		{"name": "cache-auth", "secret": {"secretName": "cache-auth", "defaultMode": 288}},
		{"name": "tmp", "emptyDir": {"sizeLimit": "64Mi"}},
	]},
)

front := make_deployment(
	"front", 101,
	{
		"readinessProbe": probe("/"),
		"livenessProbe": probe("/"),
		"volumeMounts": [{"name": "tmp", "mountPath": "/tmp"}],
	},
	{"volumes": [{"name": "tmp", "emptyDir": {"sizeLimit": "16Mi"}}]},
)

valid := [api, front, make_service("api"), make_service("front"), make_route("api"), make_route("front")]

rendered(docs) := [{"path": "render/common.yaml", "contents": doc} | some doc in docs]

accepted(docs) if {
	msgs := deny with input as rendered(docs)
	count(msgs) == 0
}

denied_with(docs, fragment) if {
	msgs := deny with input as rendered(docs)
	some msg in msgs
	contains(msg, fragment)
}

# replace_container(doc, patch): doc with the first container merged with patch.
# The keys of patch replace those of the container, whole (object.union would merge them).
replaced(base, patch) := object.union(object.remove(base, [k | some k, _ in patch]), patch)

with_container(doc, patch) := object.union(doc, {"spec": {"template": {"spec": {"containers": [replaced(doc.spec.template.spec.containers[0], patch)]}}}})

with_pod(doc, patch) := object.union(doc, {"spec": {"template": {"spec": replaced_pod(doc.spec.template.spec, patch)}}})

replaced_pod(base, patch) := replaced(base, patch)

others(name) := [d | some d in valid; not is_obj(d, "Deployment", name)]

test_s30_accepts_the_two_workloads if {
	accepted(valid)
}

test_s30_rejects_a_missing_deployment if {
	denied_with(others("front"), "expected one Deployment front")
}

test_s30_rejects_a_missing_service if {
	denied_with([d | some d in valid; not is_obj(d, "Service", "api")], "expected one Service api")
}

test_s30_rejects_a_pod_that_may_run_as_root if {
	changed := with_pod(api, {"securityContext": {"runAsNonRoot": false, "seccompProfile": {"type": "RuntimeDefault"}}})
	denied_with(array.concat(others("api"), [changed]), "the pod of api must set runAsNonRoot to true")
}

test_s30_rejects_a_writable_root_filesystem if {
	changed := with_container(front, {"securityContext": object.union(container_security, {"readOnlyRootFilesystem": false})})
	denied_with(array.concat(others("front"), [changed]), "container front of front must set readOnlyRootFilesystem to true")
}

test_s30_rejects_a_capability_left_in_place if {
	changed := with_container(front, {"securityContext": {"allowPrivilegeEscalation": false, "readOnlyRootFilesystem": true}})
	denied_with(array.concat(others("front"), [changed]), "must drop ALL capabilities")
}

test_s30_rejects_a_container_without_requests if {
	changed := with_container(front, {"resources": {"limits": {"memory": "64Mi"}}})
	denied_with(array.concat(others("front"), [changed]), "must request cpu")
}

test_s30_rejects_a_container_without_a_memory_limit if {
	changed := with_container(front, {"resources": {"requests": {"cpu": "10m", "memory": "16Mi"}}})
	denied_with(array.concat(others("front"), [changed]), "must limit memory")
}

test_s30_rejects_a_readiness_probe_on_the_wrong_path if {
	changed := with_container(api, {"readinessProbe": probe("/api/healthz")})
	denied_with(array.concat(others("api"), [changed]), "must set readinessProbe as an httpGet on /api/readyz")
}

test_s30_rejects_an_unbounded_empty_dir if {
	changed := with_pod(front, {"volumes": [{"name": "tmp", "emptyDir": {}}]})
	denied_with(array.concat(others("front"), [changed]), "the emptyDir tmp of front must set sizeLimit")
}

test_s30_rejects_a_secret_read_by_key_reference if {
	changed := with_container(api, {"env": [{"name": "X", "valueFrom": {"secretKeyRef": {"name": "db-auth", "key": "password"}}}]})
	denied_with(array.concat(others("api"), [changed]), "by secretKeyRef")
}

test_s30_rejects_a_secret_read_by_env_from if {
	changed := with_container(api, {"envFrom": [{"configMapRef": {"name": "app-config"}}, {"secretRef": {"name": "db-auth"}}]})
	denied_with(array.concat(others("api"), [changed]), "by envFrom")
}

test_s30_rejects_an_api_without_the_cache_secret if {
	changed := with_pod(api, {"volumes": [{"name": "db-auth", "secret": {"secretName": "db-auth", "defaultMode": 288}}, {"name": "tmp", "emptyDir": {"sizeLimit": "64Mi"}}]})
	denied_with(array.concat(others("api"), [changed]), "the API must mount db-auth and cache-auth")
}

test_s30_rejects_a_secret_volume_without_a_mode if {
	changed := with_pod(api, {"volumes": [
		{"name": "db-auth", "secret": {"secretName": "db-auth"}},
		{"name": "cache-auth", "secret": {"secretName": "cache-auth", "defaultMode": 288}},
		{"name": "tmp", "emptyDir": {"sizeLimit": "64Mi"}},
	]})
	denied_with(array.concat(others("api"), [changed]), "must set defaultMode")
}

test_s30_rejects_a_front_that_mounts_a_secret if {
	changed := with_pod(front, {"volumes": [{"name": "tmp", "emptyDir": {"sizeLimit": "16Mi"}}, {"name": "s", "secret": {"secretName": "db-auth", "defaultMode": 288}}]})
	changed_mounted := with_container(changed, {"volumeMounts": [{"name": "s", "mountPath": "/run/secrets/db-auth"}]})
	denied_with(array.concat(others("front"), [changed_mounted]), "the front mounts no Secret")
}

test_s30_rejects_an_api_without_its_label if {
	changed := object.union(api, {"spec": {"template": {"metadata": {"labels": {"app.kubernetes.io/name": "other"}}}}})
	denied_with(array.concat(others("api"), [changed]), "must carry the label app.kubernetes.io/name: api")
}

test_s30_rejects_a_route_to_a_port_no_service_serves if {
	changed := {
		"apiVersion": "gateway.networking.k8s.io/v1",
		"kind": "HTTPRoute",
		"metadata": {"name": "api"},
		"spec": {"rules": [{"backendRefs": [{"name": "api", "port": 8080}]}]},
	}
	denied_with(array.concat([d | some d in valid; not is_obj(d, "HTTPRoute", "api")], [changed]), "which no Service of the render serves")
}

test_s30_rejects_a_service_that_does_not_reach_the_container_port if {
	changed := object.union(make_service("front"), {"spec": {"ports": [{"port": 80, "targetPort": 80}]}})
	denied_with(array.concat([d | some d in valid; not is_obj(d, "Service", "front")], [changed]), "must serve port 80 to the port 8080")
}

is_obj(doc, kind, name) if {
	doc.kind == kind
	doc.metadata.name == name
}

# --- The host, the volumes that reach out, the pull policy ---

bare_init := {"name": "init", "image": "saas-b2b.invalid/api:unbuilt", "imagePullPolicy": "IfNotPresent", "resources": resources, "securityContext": container_security}

test_s30_reads_the_init_containers_too if {
	changed := with_pod(front, {"initContainers": [replaced(bare_init, {"securityContext": {"allowPrivilegeEscalation": false, "capabilities": {"drop": ["ALL"]}}})]})
	denied_with(array.concat(others("front"), [changed]), "container init of front must set readOnlyRootFilesystem to true")
}

test_s30_accepts_a_well_made_init_container if {
	accepted(array.concat(others("front"), [with_pod(front, {"initContainers": [bare_init]})]))
}

test_s30_rejects_a_privileged_init_container if {
	changed := with_pod(front, {"initContainers": [object.union(bare_init, {"securityContext": object.union(container_security, {"privileged": true})})]})
	denied_with(array.concat(others("front"), [changed]), "container init of front must not be privileged")
}

test_s30_rejects_a_privileged_container if {
	changed := with_container(front, {"securityContext": object.union(container_security, {"privileged": true})})
	denied_with(array.concat(others("front"), [changed]), "container front of front must not be privileged")
}

test_s30_rejects_host_networking if {
	changed := with_pod(front, {"hostNetwork": true})
	denied_with(array.concat(others("front"), [changed]), "must not set hostNetwork")
}

test_s30_rejects_a_host_path_volume if {
	changed := with_pod(front, {"volumes": [{"name": "tmp", "emptyDir": {"sizeLimit": "16Mi"}}, {"name": "node", "hostPath": {"path": "/"}}]})
	denied_with(array.concat(others("front"), [changed]), "is a hostPath")
}

test_s30_rejects_a_projected_secret if {
	changed := with_pod(front, {"volumes": [{"name": "tmp", "emptyDir": {"sizeLimit": "16Mi"}}, {"name": "p", "projected": {"sources": [{"secret": {"name": "db-auth"}}]}}]})
	denied_with(array.concat(others("front"), [changed]), "takes a Secret as a source")
}

test_s30_accepts_a_projected_config_map if {
	changed := with_pod(front, {"volumes": [{"name": "tmp", "emptyDir": {"sizeLimit": "16Mi"}}, {"name": "p", "projected": {"sources": [{"configMap": {"name": "app-config"}}]}}]})
	accepted(array.concat(others("front"), [changed]))
}

test_s30_rejects_a_built_image_that_is_always_pulled if {
	changed := with_container(front, {"imagePullPolicy": "Always"})
	denied_with(array.concat(others("front"), [changed]), "imagePullPolicy must be IfNotPresent or Never, found Always")
}

test_s30_accepts_the_never_pull_policy if {
	accepted(array.concat(others("front"), [with_container(front, {"imagePullPolicy": "Never"})]))
}

test_s30_rejects_a_built_image_without_a_pull_policy if {
	changed := object.union(front, {"spec": {"template": {"spec": {"containers": [object.remove(front.spec.template.spec.containers[0], ["imagePullPolicy"])]}}}})
	denied_with(array.concat(others("front"), [changed]), "imagePullPolicy must be IfNotPresent or Never, found null")
}
