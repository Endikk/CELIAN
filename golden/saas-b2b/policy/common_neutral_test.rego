# Tests of S06 (common_neutral.rego), run by `conftest verify`.
package common_neutral

namespace := {
	"apiVersion": "v1",
	"kind": "Namespace",
	"metadata": {"name": "saas-b2b", "labels": {"pod-security.kubernetes.io/enforce": "restricted"}},
}

gateway := {
	"apiVersion": "gateway.networking.k8s.io/v1",
	"kind": "Gateway",
	"metadata": {"name": "saas-b2b", "namespace": "saas-b2b"},
	"spec": {"gatewayClassName": "saas-b2b", "listeners": [{"name": "http", "port": 80, "protocol": "HTTP"}]},
}

deployment := {
	"apiVersion": "apps/v1",
	"kind": "Deployment",
	"metadata": {"name": "api", "labels": {"app.kubernetes.io/name": "api"}, "annotations": {"kubectl.kubernetes.io/default-container": "api"}},
}

rendered(objects) := [{"path": "rendered/local.yaml", "contents": obj} | some obj in objects]

accepted(files) if {
	msgs := deny with input as files
	count(msgs) == 0
}

denied_with(files, fragment) if {
	msgs := deny with input as files
	some msg in msgs
	contains(msg, fragment)
}

with_metadata(obj, extra) := object.union(obj, {"metadata": object.union(obj.metadata, extra)})

test_s06_accepts_a_neutral_layer if {
	accepted(rendered([namespace, gateway, deployment]))
}

test_s06_rejects_an_empty_render if {
	denied_with([], "no rendered object")
}

test_s06_rejects_an_envoy_proxy if {
	proxy := {"apiVersion": "gateway.envoyproxy.io/v1alpha1", "kind": "EnvoyProxy", "metadata": {"name": "p"}}
	denied_with(rendered([gateway, proxy]), "of Envoy Gateway")
}

test_s06_rejects_a_root_sync if {
	sync := {"apiVersion": "configsync.gke.io/v1beta1", "kind": "RootSync", "metadata": {"name": "root-sync"}}
	denied_with(rendered([sync]), "of Config Sync")
}

test_s06_rejects_a_flux_kustomization if {
	flux := {"apiVersion": "kustomize.toolkit.fluxcd.io/v1", "kind": "Kustomization", "metadata": {"name": "app"}}
	denied_with(rendered([flux]), "of Flux")
}

test_s06_rejects_an_argo_application if {
	argo := {"apiVersion": "argoproj.io/v1alpha1", "kind": "Application", "metadata": {"name": "app"}}
	denied_with(rendered([argo]), "of Argo CD")
}

test_s06_rejects_a_provider_object if {
	policy := {"apiVersion": "networking.gke.io/v1", "kind": "HealthCheckPolicy", "metadata": {"name": "h"}}
	denied_with(rendered([policy]), "outside upstream Kubernetes and Gateway API")
}

test_s06_rejects_a_sig_project_object if {
	spc := {"apiVersion": "secrets-store.csi.x-k8s.io/v1", "kind": "SecretProviderClass", "metadata": {"name": "db"}}
	denied_with(rendered([spc]), "outside upstream Kubernetes and Gateway API")
}

test_s06_rejects_an_engine_annotation if {
	denied_with(rendered([with_metadata(deployment, {"annotations": {"kustomize.toolkit.fluxcd.io/reconcile": "disabled"}})]), "annotation kustomize.toolkit.fluxcd.io/reconcile")
}

test_s06_rejects_a_provider_annotation if {
	denied_with(rendered([with_metadata(gateway, {"annotations": {"networking.gke.io/certmap": "c"}})]), "annotation networking.gke.io/certmap")
}

test_s06_rejects_a_sig_project_label if {
	denied_with(rendered([with_metadata(gateway, {"labels": {"cluster.x-k8s.io/cluster-name": "c"}})]), "label cluster.x-k8s.io/cluster-name")
}

test_s06_rejects_a_substitution if {
	configmap := {"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": "app-config"}, "data": {"host": "${DB_HOST}"}}
	denied_with(rendered([configmap]), "a substitution of a GitOps engine")
}

test_s06_rejects_a_class_of_a_target if {
	gke := object.union(gateway, {"spec": object.union(gateway.spec, {"gatewayClassName": "gke-l7-global-external-managed"})})
	denied_with(rendered([gke]), "names a tool or a provider")
}

test_s06_rejects_an_envoy_class if {
	envoy := object.union(gateway, {"spec": object.union(gateway.spec, {"gatewayClassName": "envoy-gateway"})})
	denied_with(rendered([envoy]), "names a tool or a provider")
}

test_s06_rejects_a_mirror_host if {
	configmap := {"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": "app-config"}, "data": {"registry": "saas-b2b-mirror.zot:5000"}}
	denied_with(rendered([configmap]), "names a tool or a provider")
}

# ADR-015, condition 17: the common layer names neither the cache engine of
# the local layer nor the managed cache of the gcp layer.
test_s06_rejects_the_cache_engine if {
	configmap := {"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": "app-config"}, "data": {"CACHE_HOST": "valkey.saas-b2b.svc"}}
	denied_with(rendered([configmap]), "names a tool or a provider")
}

test_s06_rejects_the_managed_cache if {
	configmap := {"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": "app-config"}, "data": {"note": "Memorystore endpoint"}}
	denied_with(rendered([configmap]), "names a tool or a provider")
}
