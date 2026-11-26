# Tests of S07, gcp part (gcp_parity.rego), run by `conftest verify`.
package gcp_parity

namespace := {
	"apiVersion": "v1",
	"kind": "Namespace",
	"metadata": {"name": "saas-b2b", "labels": {"pod-security.kubernetes.io/enforce": "restricted"}},
}

gateway := {
	"apiVersion": "gateway.networking.k8s.io/v1",
	"kind": "Gateway",
	"metadata": {"name": "saas-b2b", "namespace": "saas-b2b"},
	"spec": {
		"gatewayClassName": "saas-b2b",
		"listeners": [{"name": "http", "protocol": "HTTP", "port": 80}],
	},
}

route := {
	"apiVersion": "gateway.networking.k8s.io/v1",
	"kind": "HTTPRoute",
	"metadata": {"name": "api", "namespace": "saas-b2b"},
	"spec": {"parentRefs": [{"name": "saas-b2b"}]},
}

deployment := {
	"apiVersion": "apps/v1",
	"kind": "Deployment",
	"metadata": {"name": "api", "namespace": "saas-b2b"},
	"spec": {"template": {"spec": {
		"containers": [{
			"name": "api",
			"image": "x",
			"envFrom": [{"configMapRef": {"name": "app-config"}}],
			"env": [{"name": "TOKEN", "valueFrom": {"secretKeyRef": {"name": "db-auth", "key": "username"}}}],
		}],
		"volumes": [
			{"name": "db-auth", "secret": {"secretName": "db-auth"}},
			{"name": "ca", "configMap": {"name": "app-ca", "optional": true}},
		],
	}}},
}

app_config := {
	"apiVersion": "v1",
	"kind": "ConfigMap",
	"metadata": {"name": "app-config", "namespace": "saas-b2b"},
	"data": {"DATABASE_HOST": "database.invalid"},
}

service_account := {
	"apiVersion": "v1",
	"kind": "ServiceAccount",
	"metadata": {"name": "secret-sync", "namespace": "saas-b2b"},
}

secret_sync := {
	"apiVersion": "secret-sync.gke.io/v1",
	"kind": "SecretSync",
	"metadata": {"name": "db-auth", "namespace": "saas-b2b"},
	"spec": {
		"serviceAccountName": "secret-sync",
		"secretProviderClassName": "db-auth",
		"secretObject": {"type": "Opaque", "data": [
			{"sourcePath": "username", "targetKey": "username"},
			{"sourcePath": "password", "targetKey": "password"},
		]},
	},
}

common_objects := [namespace, gateway, route, deployment]

gcp_gateway := json.patch(gateway, [{"op": "replace", "path": "/spec/gatewayClassName", "value": "gke-l7-global-external-managed"}])

layer_objects := [app_config, service_account, secret_sync]

gcp_objects := array.concat([namespace, gcp_gateway, route, deployment], layer_objects)

entries(name, objs) := [{"path": concat("/", ["render", name]), "contents": obj} | some obj in objs]

render(common_objs, gcp_objs, layer_objs) := array.concat(
	entries("common.yaml", common_objs),
	array.concat(entries("gcp.yaml", gcp_objs), entries("layer.yaml", layer_objs)),
)

valid := render(common_objects, gcp_objects, layer_objects)

accepted(input_files) if {
	msgs := deny with input as input_files
	count(msgs) == 0
}

denied_with(input_files, fragment) if {
	msgs := deny with input as input_files
	some msg in msgs
	contains(msg, fragment)
}

# gcp objects with one of them replaced by a patched copy.
gcp_with(obj, ops) := array.concat([json.patch(obj, ops)], [o | some o in gcp_objects; o != obj])

test_s07_accepts_the_valid_renders if {
	accepted(valid)
}

test_s07_accepts_a_common_layer_without_a_pod if {
	accepted(render([namespace, gateway, route], [namespace, gcp_gateway, route], []))
}

# --- 1. The common layer in the gcp render -----------------------------------

test_s07_rejects_a_missing_common_render if {
	denied_with(render([], gcp_objects, layer_objects), "common.yaml holds no object")
}

test_s07_rejects_a_missing_gcp_render if {
	denied_with(render(common_objects, [], layer_objects), "gcp.yaml holds no object")
}

test_s07_rejects_a_common_object_missing_from_gcp if {
	objs := [o | some o in gcp_objects; o != route]
	denied_with(render(common_objects, objs, layer_objects), "HTTPRoute saas-b2b/api")
}

test_s07_rejects_a_changed_route if {
	objs := gcp_with(route, [{"op": "add", "path": "/spec/hostnames", "value": ["example.org"]}])
	denied_with(render(common_objects, objs, layer_objects), "differs between the common layer and the render of gcp")
}

test_s07_rejects_a_changed_deployment if {
	objs := gcp_with(deployment, [{"op": "add", "path": "/spec/replicas", "value": 3}])
	denied_with(render(common_objects, objs, layer_objects), "Deployment saas-b2b/api")
}

test_s07_rejects_a_changed_listener if {
	objs := gcp_with(gcp_gateway, [{"op": "replace", "path": "/spec/listeners/0/port", "value": 8080}])
	denied_with(render(common_objects, objs, layer_objects), "differs between the common layer and the render of gcp")
}

test_s07_rejects_a_changed_namespace_label if {
	objs := gcp_with(namespace, [{"op": "replace", "path": "/metadata/labels/pod-security.kubernetes.io~1enforce", "value": "baseline"}])
	denied_with(render(common_objects, objs, layer_objects), "Namespace")
}

test_s07_rejects_another_gateway_class if {
	objs := gcp_with(gcp_gateway, [{"op": "replace", "path": "/spec/gatewayClassName", "value": "gke-l7-rilb"}])
	denied_with(render(common_objects, objs, layer_objects), "asks the class gke-l7-rilb")
}

test_s07_rejects_the_class_left_unchanged if {
	denied_with(render(common_objects, [namespace, gateway, route, deployment, app_config, service_account, secret_sync], layer_objects), "asks the class saas-b2b")
}

# --- 2. What gcp adds ------------------------------------------------------------

test_s07_rejects_an_object_from_nowhere if {
	stray := {"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": "stray", "namespace": "saas-b2b"}}
	denied_with(render(common_objects, array.concat(gcp_objects, [stray]), layer_objects), "ConfigMap saas-b2b/stray")
}

test_s07_rejects_a_layer_object_changed_on_its_way if {
	changed := json.patch(app_config, [{"op": "add", "path": "/metadata/labels", "value": {"x": "y"}}])
	objs := array.concat([changed], [o | some o in gcp_objects; o != app_config])
	denied_with(render(common_objects, objs, layer_objects), "is changed on its way")
}

# --- 3. One Gateway -----------------------------------------------------------

test_s07_rejects_a_second_gateway_in_gcp if {
	second := json.patch(gcp_gateway, [{"op": "replace", "path": "/metadata/name", "value": "second"}])
	denied_with(render(common_objects, array.concat(gcp_objects, [second]), array.concat(layer_objects, [second])), "2 Gateway in the render of gcp")
}

test_s07_rejects_two_gateways_in_the_common_layer if {
	second := json.patch(gateway, [{"op": "replace", "path": "/metadata/name", "value": "second"}])
	denied_with(render(array.concat(common_objects, [second]), gcp_objects, layer_objects), "2 Gateway in the common layer")
}

test_s07_rejects_no_gateway if {
	denied_with(render([namespace, route], [namespace, route], []), "0 Gateway")
}

# --- 5. The namespace of the bootstrap --------------------------------------------

with_bootstrap(obj) := array.concat(valid, entries("bootstrap.yaml", [obj]))

test_s07_accepts_the_namespace_of_the_bootstrap if {
	accepted(with_bootstrap(namespace))
}

test_s07_rejects_a_bootstrap_namespace_that_differs if {
	other := json.patch(namespace, [{"op": "replace", "path": "/metadata/labels/pod-security.kubernetes.io~1enforce", "value": "privileged"}])
	denied_with(with_bootstrap(other), "differs from the one of the common layer")
}

test_s07_rejects_a_bootstrap_namespace_the_common_layer_lacks if {
	other := {"apiVersion": "v1", "kind": "Namespace", "metadata": {"name": "other"}}
	denied_with(with_bootstrap(other), "which the common layer does not hold")
}

# --- 6. The admission objects, applied first -----------------------------------
# Config Sync updates them by name and never creates them (the ClusterRole of
# the RootSync has no create verb), so the bootstrap holds them too.

admission_policy := {
	"apiVersion": "admissionregistration.k8s.io/v1",
	"kind": "ValidatingAdmissionPolicy",
	"metadata": {"name": "saas-b2b-require-requests"},
	"spec": {"failurePolicy": "Fail"},
}

admission_binding := {
	"apiVersion": "admissionregistration.k8s.io/v1",
	"kind": "ValidatingAdmissionPolicyBinding",
	"metadata": {"name": "saas-b2b-require-requests"},
	"spec": {"policyName": "saas-b2b-require-requests", "validationActions": ["Deny"]},
}

with_admission := render(
	common_objects,
	array.concat(gcp_objects, [admission_policy, admission_binding]),
	array.concat(layer_objects, [admission_policy, admission_binding]),
)

test_s07_accepts_admission_objects_that_the_bootstrap_holds if {
	accepted(array.concat(with_admission, entries("bootstrap.yaml", [admission_policy, admission_binding])))
}

test_s07_rejects_an_admission_policy_the_bootstrap_lacks if {
	denied_with(array.concat(with_admission, entries("bootstrap.yaml", [admission_binding])), "ValidatingAdmissionPolicy")
}

test_s07_rejects_an_admission_binding_the_bootstrap_lacks if {
	denied_with(array.concat(with_admission, entries("bootstrap.yaml", [admission_policy])), "ValidatingAdmissionPolicyBinding")
}

test_s07_rejects_admission_objects_without_any_bootstrap if {
	denied_with(with_admission, "is not in the bootstrap")
}

test_s07_rejects_an_admission_policy_that_differs_in_the_bootstrap if {
	other := json.patch(admission_policy, [{"op": "replace", "path": "/spec/failurePolicy", "value": "Ignore"}])
	denied_with(array.concat(with_admission, entries("bootstrap.yaml", [other, admission_binding])), "differs from the one that Config Sync syncs")
}

# --- 4. The producers ---------------------------------------------------------

test_s07_rejects_a_secret_without_a_producer if {
	bad := json.patch(deployment, [{"op": "add", "path": "/spec/template/spec/volumes/-", "value": {"name": "x", "secret": {"secretName": "other-secret"}}}])
	objs := array.concat([bad], [o | some o in gcp_objects; o != deployment])
	denied_with(render([namespace, gateway, route, bad], objs, layer_objects), "the Secret other-secret")
}

test_s07_rejects_a_key_that_gcp_does_not_write if {
	bad := json.patch(deployment, [{"op": "replace", "path": "/spec/template/spec/containers/0/env/0/valueFrom/secretKeyRef/key", "value": "token"}])
	objs := array.concat([bad], [o | some o in gcp_objects; o != deployment])
	denied_with(render([namespace, gateway, route, bad], objs, layer_objects), "the key token of the Secret db-auth")
}

test_s07_rejects_a_secret_volume_item_that_gcp_does_not_write if {
	vol := {"name": "x", "secret": {"secretName": "db-auth", "items": [{"key": "token", "path": "token"}]}}
	bad := json.patch(deployment, [{"op": "add", "path": "/spec/template/spec/volumes/-", "value": vol}])
	objs := array.concat([bad], [o | some o in gcp_objects; o != deployment])
	denied_with(render([namespace, gateway, route, bad], objs, layer_objects), "the key token of the Secret db-auth")
}

test_s07_rejects_the_superuser_secret if {
	bad := json.patch(deployment, [{"op": "add", "path": "/spec/template/spec/volumes/-", "value": {"name": "x", "secret": {"secretName": "db-superuser"}}}])
	objs := array.concat([bad], [o | some o in gcp_objects; o != deployment])
	denied_with(render([namespace, gateway, route, bad], objs, layer_objects), "the Secret db-superuser")
}

test_s07_rejects_a_config_map_that_gcp_does_not_provide if {
	bad := json.patch(deployment, [{"op": "add", "path": "/spec/template/spec/volumes/-", "value": {"name": "x", "configMap": {"name": "other-config"}}}])
	objs := array.concat([bad], [o | some o in gcp_objects; o != deployment])
	denied_with(render([namespace, gateway, route, bad], objs, layer_objects), "the ConfigMap other-config")
}

test_s07_rejects_a_config_key_that_gcp_does_not_write if {
	bad := json.patch(deployment, [{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "H", "valueFrom": {"configMapKeyRef": {"name": "app-config", "key": "UNKNOWN"}}}}])
	objs := array.concat([bad], [o | some o in gcp_objects; o != deployment])
	denied_with(render([namespace, gateway, route, bad], objs, layer_objects), "the key UNKNOWN of the ConfigMap app-config")
}

test_s07_accepts_an_optional_reference_without_a_producer if {
	opt := {"name": "x", "secret": {"secretName": "never-written", "optional": true}}
	ok := json.patch(deployment, [{"op": "add", "path": "/spec/template/spec/volumes/-", "value": opt}])
	objs := array.concat([ok], [o | some o in gcp_objects; o != deployment])
	accepted(render([namespace, gateway, route, ok], objs, layer_objects))
}

test_s07_warns_and_accepts_a_pending_secret if {
	pending := {"name": "x", "secret": {"secretName": "cache-auth"}}
	ok := json.patch(deployment, [{"op": "add", "path": "/spec/template/spec/volumes/-", "value": pending}])
	objs := array.concat([ok], [o | some o in gcp_objects; o != deployment])
	files := render([namespace, gateway, route, ok], objs, layer_objects)
	accepted(files)
	some msg in warn with input as files
	contains(msg, "the Secret cache-auth has no producer on gcp yet")
}

test_s07_reads_the_certificate_of_a_listener if {
	tls_gateway := json.patch(gateway, [{"op": "add", "path": "/spec/listeners/-", "value": {
		"name": "https", "protocol": "HTTPS", "port": 443,
		"tls": {"mode": "Terminate", "certificateRefs": [{"name": "gateway-tls"}]},
	}}])
	tls_gcp := json.patch(gcp_gateway, [{"op": "add", "path": "/spec/listeners/-", "value": {
		"name": "https", "protocol": "HTTPS", "port": 443,
		"tls": {"mode": "Terminate", "certificateRefs": [{"name": "gateway-tls"}]},
	}}])
	objs := array.concat([tls_gcp], [o | some o in gcp_objects; o != gcp_gateway])
	files := render([namespace, tls_gateway, route, deployment], objs, layer_objects)
	accepted(files)
	some msg in warn with input as files
	contains(msg, "the Secret gateway-tls has no producer on gcp yet")
}
