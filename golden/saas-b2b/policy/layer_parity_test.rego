# Tests of S07 (layer_parity.rego), run by `conftest verify`.
package layer_parity

gateway(class) := {
	"apiVersion": "gateway.networking.k8s.io/v1",
	"kind": "Gateway",
	"metadata": {"name": "saas-b2b", "namespace": "saas-b2b"},
	"spec": {"gatewayClassName": class, "listeners": [{"name": "http", "port": 80, "protocol": "HTTP"}]},
}

route(name, hostnames) := {
	"apiVersion": "gateway.networking.k8s.io/v1",
	"kind": "HTTPRoute",
	"metadata": {"name": name, "namespace": "saas-b2b"},
	"spec": {"parentRefs": [{"name": "saas-b2b"}], "hostnames": hostnames},
}

route_without_hosts(name) := {
	"apiVersion": "gateway.networking.k8s.io/v1",
	"kind": "HTTPRoute",
	"metadata": {"name": name, "namespace": "saas-b2b"},
	"spec": {"parentRefs": [{"name": "saas-b2b"}]},
}

api_deployment := {
	"apiVersion": "apps/v1",
	"kind": "Deployment",
	"metadata": {"name": "api", "namespace": "saas-b2b"},
	"spec": {"template": {"spec": {
		"containers": [{
			"name": "api",
			"image": "saas-b2b.invalid/api:unbuilt",
			"envFrom": [{"configMapRef": {"name": "app-config"}}],
			"volumeMounts": [{"name": "db-auth", "mountPath": "/run/secrets/db-auth"}],
		}],
		"volumes": [
			{"name": "db-auth", "secret": {"secretName": "db-auth"}},
			{"name": "cache-auth", "secret": {"secretName": "cache-auth"}},
		],
	}}},
}

app_config := {
	"apiVersion": "v1",
	"kind": "ConfigMap",
	"metadata": {"name": "app-config", "namespace": "saas-b2b"},
	"data": {
		"DATABASE_HOST": "postgres", "DATABASE_PORT": "5432", "DATABASE_NAME": "app", "DATABASE_SSL_MODE": "Disable",
		"CACHE_HOST": "cache", "CACHE_PORT": "6379", "CACHE_TLS_MODE": "Disable", "CACHE_TLS_CA_FILE": "",
	},
}

postgres := {
	"apiVersion": "apps/v1",
	"kind": "StatefulSet",
	"metadata": {"name": "postgres", "namespace": "saas-b2b"},
	"spec": {"template": {"spec": {"containers": [{"name": "postgres", "image": "postgres"}]}}},
}

valid_common := [gateway("saas-b2b"), route_without_hosts("api"), route_without_hosts("front"), api_deployment]

valid_target := [gateway("envoy"), route("api", ["localhost"]), route("front", ["localhost"]), api_deployment, app_config, postgres]

valid_sources := [app_config, postgres]

renders(common, target, sources) := array.concat(
	array.concat(
		[{"path": "render/common.yaml", "contents": doc} | some doc in common],
		[{"path": "render/lite.yaml", "contents": doc} | some doc in target],
	),
	[{"path": "render/sources.yaml", "contents": doc} | some doc in sources],
)

accepted(files) if {
	msgs := deny with input as files
	count(msgs) == 0
}

denied_with(files, fragment) if {
	msgs := deny with input as files
	some msg in msgs
	contains(msg, fragment)
}

with_spec(doc, spec) := object.union(doc, {"spec": spec})

test_s07_accepts_a_target_that_changes_the_class_and_the_hosts if {
	accepted(renders(valid_common, valid_target, valid_sources))
}

test_s07_rejects_an_input_without_a_render if {
	denied_with([], "no document of a render matching")
}

test_s07_rejects_a_common_object_missing_from_the_target if {
	target := [doc | some doc in valid_target; doc.kind != "Deployment"]
	denied_with(renders(valid_common, target, valid_sources), "Deployment/api of the common layer is not found exactly once")
}

test_s07_rejects_a_common_object_changed_by_the_target if {
	changed := object.union(api_deployment, {"metadata": {"labels": {"tool": "x"}}})
	target := [changed, gateway("envoy"), route("api", ["localhost"]), route("front", ["localhost"]), app_config, postgres]
	denied_with(renders(valid_common, target, valid_sources), "Deployment/api differs between the common layer and the local render")
}

test_s07_rejects_a_listener_changed_by_the_target if {
	changed := object.union(gateway("envoy"), {"spec": {"gatewayClassName": "envoy", "listeners": []}})
	target := [changed, route("api", ["localhost"]), route("front", ["localhost"]), api_deployment, app_config, postgres]
	denied_with(renders(valid_common, target, valid_sources), "Gateway/saas-b2b differs between the common layer and the local render")
}

test_s07_rejects_an_object_that_no_file_of_the_layer_defines if {
	extra := {"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": "stray"}}
	denied_with(
		renders(valid_common, array.concat(valid_target, [extra]), valid_sources),
		"ConfigMap/stray is in the local render, and in neither the common layer nor a file of the local layer",
	)
}

test_s07_rejects_two_gateways_in_the_local_render if {
	second := object.union(gateway("envoy"), {"metadata": {"name": "other", "namespace": "saas-b2b"}})
	denied_with(renders(valid_common, array.concat(valid_target, [second]), array.concat(valid_sources, [second])), "holds 2 Gateway, one expected")
}

test_s07_rejects_a_config_map_that_the_target_does_not_provide if {
	target := [doc | some doc in valid_target; doc.kind != "ConfigMap"]
	denied_with(renders(valid_common, target, valid_sources), "names the ConfigMap app-config, which the local render does not provide")
}

# An optional volume names a ConfigMap that a target may not provide: app-ca,
# which only the gcp layer writes (tasks.md, gap 179).
test_s07_accepts_an_optional_config_map_volume_that_the_target_lacks if {
	optional := json.patch(api_deployment, [{"op": "add", "path": "/spec/template/spec/volumes/-", "value": {"name": "ca", "configMap": {"name": "app-ca", "optional": true}}}])
	common := [gateway("saas-b2b"), route_without_hosts("api"), route_without_hosts("front"), optional]
	target := [gateway("envoy"), route("api", ["localhost"]), route("front", ["localhost"]), optional, app_config, postgres]
	accepted(renders(common, target, valid_sources))
}

test_s07_rejects_a_required_config_map_volume_that_the_target_lacks if {
	required := json.patch(api_deployment, [{"op": "add", "path": "/spec/template/spec/volumes/-", "value": {"name": "ca", "configMap": {"name": "app-ca"}}}])
	common := [gateway("saas-b2b"), route_without_hosts("api"), route_without_hosts("front"), required]
	target := [gateway("envoy"), route("api", ["localhost"]), route("front", ["localhost"]), required, app_config, postgres]
	denied_with(renders(common, target, valid_sources), "names the ConfigMap app-ca, which the local render does not provide")
}

test_s07_rejects_a_secret_outside_the_contract if {
	changed := object.union(api_deployment, {"spec": {"template": {"spec": {"volumes": [{"name": "x", "secret": {"secretName": "db-superuser"}}]}}}})
	common := [gateway("saas-b2b"), route_without_hosts("api"), route_without_hosts("front"), changed]
	target := [gateway("envoy"), route("api", ["localhost"]), route("front", ["localhost"]), changed, app_config, postgres]
	denied_with(renders(common, target, valid_sources), "names the Secret db-superuser")
}

test_s07_rejects_a_secret_named_by_a_key_reference if {
	container := {"name": "api", "image": "saas-b2b.invalid/api:unbuilt", "env": [{"name": "X", "valueFrom": {"secretKeyRef": {"name": "db-superuser", "key": "password"}}}]}
	changed := object.union(api_deployment, {"spec": {"template": {"spec": {"containers": [container]}}}})
	common := [gateway("saas-b2b"), route_without_hosts("api"), route_without_hosts("front"), changed]
	target := [gateway("envoy"), route("api", ["localhost"]), route("front", ["localhost"]), changed, app_config, postgres]
	denied_with(renders(common, target, valid_sources), "names the Secret db-superuser")
}

test_s07_rejects_an_app_config_with_a_missing_key if {
	short := {
		"apiVersion": "v1",
		"kind": "ConfigMap",
		"metadata": {"name": "app-config", "namespace": "saas-b2b"},
		"data": {"DATABASE_HOST": "postgres"},
	}
	target := [gateway("envoy"), route("api", ["localhost"]), route("front", ["localhost"]), api_deployment, short, postgres]
	denied_with(renders(valid_common, target, [short, postgres]), "app-config holds the keys")
}

test_s07_rejects_an_app_config_with_an_extra_key if {
	extra := object.union(app_config, {"data": object.union(app_config.data, {"PASSWORD": "x"})})
	target := [gateway("envoy"), route("api", ["localhost"]), route("front", ["localhost"]), api_deployment, extra, postgres]
	denied_with(renders(valid_common, target, [extra, postgres]), "app-config holds the keys")
}

test_s07_rejects_a_development_environment_in_a_workload if {
	container := {"name": "api", "image": "saas-b2b.invalid/api:unbuilt", "env": [{"name": "ASPNETCORE_ENVIRONMENT", "value": "Development"}]}
	changed := object.union(api_deployment, {"spec": {"template": {"spec": {"containers": [container]}}}})
	common := [gateway("saas-b2b"), route_without_hosts("api"), route_without_hosts("front"), changed]
	target := [gateway("envoy"), route("api", ["localhost"]), route("front", ["localhost"]), changed, app_config, postgres]
	denied_with(renders(common, target, valid_sources), "sets ASPNETCORE_ENVIRONMENT to Development")
}

test_s07_rejects_dotnet_environment_in_any_case if {
	container := {"name": "api", "image": "saas-b2b.invalid/api:unbuilt", "env": [{"name": "DOTNET_ENVIRONMENT", "value": "development"}]}
	changed := object.union(api_deployment, {"spec": {"template": {"spec": {"containers": [container]}}}})
	common := [gateway("saas-b2b"), route_without_hosts("api"), route_without_hosts("front"), changed]
	target := [gateway("envoy"), route("api", ["localhost"]), route("front", ["localhost"]), changed, app_config, postgres]
	denied_with(renders(common, target, valid_sources), "sets DOTNET_ENVIRONMENT to Development")
}

test_s07_rejects_a_development_environment_in_app_config if {
	dev := object.union(app_config, {"data": object.union(app_config.data, {"ASPNETCORE_ENVIRONMENT": "Development"})})
	target := [gateway("envoy"), route("api", ["localhost"]), route("front", ["localhost"]), api_deployment, dev, postgres]
	denied_with(renders(valid_common, target, [dev, postgres]), "the ConfigMap app-config sets ASPNETCORE_ENVIRONMENT to Development")
}

test_s07_accepts_a_production_environment if {
	container := {"name": "api", "image": "saas-b2b.invalid/api:unbuilt", "env": [{"name": "ASPNETCORE_ENVIRONMENT", "value": "Production"}]}
	changed := object.union(api_deployment, {"spec": {"template": {"spec": {"containers": [container]}}}})
	common := [gateway("saas-b2b"), route_without_hosts("api"), route_without_hosts("front"), changed]
	target := [gateway("envoy"), route("api", ["localhost"]), route("front", ["localhost"]), changed, app_config, postgres]
	accepted(renders(common, target, valid_sources))
}

test_s07_rejects_hostnames_in_the_common_layer if {
	common := [gateway("saas-b2b"), route("api", ["localhost"]), route_without_hosts("front"), api_deployment]
	denied_with(renders(common, valid_target, valid_sources), "names hostnames; the host of a target is set by its layer")
}

test_s07_rejects_a_local_route_without_hostnames if {
	target := [gateway("envoy"), route_without_hosts("api"), route("front", ["localhost"]), api_deployment, app_config, postgres]
	denied_with(renders(valid_common, target, valid_sources), "HTTPRoute/api of the local render must name the hostname localhost alone")
}

test_s07_rejects_an_ip_or_a_wildcard_as_the_local_host if {
	target := [gateway("envoy"), route("api", ["127.0.0.1"]), route("front", ["*"]), api_deployment, app_config, postgres]
	msgs := deny with input as renders(valid_common, target, valid_sources)
	count([msg | some msg in msgs; contains(msg, "must name the hostname localhost alone")]) == 2
}
