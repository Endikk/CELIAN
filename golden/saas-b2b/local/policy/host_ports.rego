# S05, ports part (spec 001, tasks.md, gap 10; research RS-20): the host
# ports of the gateway have one value each, kept in local/kind/cluster.yaml
# and in local/tasks/local.yml, and they lead to the proxy:
# - the hostPort values of the extraPortMappings are exactly the ports that
#   the tasks give to the preflight checks;
# - each nodePort that the EnvoyProxy of the local layer fixes on the
#   Service of the proxy is the containerPort of an extraPortMappings;
# - the EnvoyProxy keeps to what ADR-005 writes: envoyService.type NodePort,
#   a StrategicMerge patch reduced to spec.ports[] with port and nodePort,
#   and no other key under spec, provider.kubernetes or envoyService;
# - the EnvoyProxy pins the proxy image by digest under
#   docker.io/envoyproxy/envoy, in envoyDeployment.container.image, and sets
#   nothing else of the Deployment (ADR-005, complement of 2026-11-26).
#
# Input: local/kind/cluster.yaml and local/platform/envoy-proxy.yaml, given
# to `conftest test --combine` (research RS-18). Data: task_host_ports, the
# ports of local/tasks/local.yml, written by
# local/tests/static/s05-kind-config.sh.
package host_ports

label := "S05 (FR-002, FR-003; ADR-004, condition 1; research RS-20)"

default task_ports := []

task_ports := data.task_host_ports

mappings contains [i, j, mapping] if {
	some file in input
	regex.match(`(^|/)local/kind/cluster\.yaml$`, file.path)
	some i, node in object.get(file.contents, "nodes", [])
	some j, mapping in object.get(node, "extraPortMappings", [])
}

host_ports := {port | some [_, _, mapping] in mappings; port := mapping.hostPort}

container_ports := {port | some [_, _, mapping] in mappings; port := mapping.containerPort}

proxies contains proxy if {
	some file in input
	proxy := file.contents
	is_object(proxy)
	proxy.kind == "EnvoyProxy"
}

service_ports(proxy) := object.get(proxy, ["spec", "provider", "kubernetes", "envoyService", "patch", "value", "spec", "ports"], [])

node_ports := {port | some proxy in proxies; some entry in service_ports(proxy); port := entry.nodePort}

deny contains msg if {
	count(task_ports) == 0
	msg := sprintf("%s: local/tasks/local.yml gives no host port of the gateway to the preflight checks", [label])
}

deny contains msg if {
	some [i, j, mapping] in mappings
	some field in ["containerPort", "hostPort"]
	not is_number(object.get(mapping, field, null))
	msg := sprintf("%s: nodes[%v].extraPortMappings[%v].%s must be a port number, found %v", [label, i, j, field, object.get(mapping, field, null)])
}

deny contains msg if {
	count(task_ports) > 0
	wanted := {port | some port in task_ports}
	wanted != host_ports
	msg := sprintf("%s: local/kind/cluster.yaml publishes the host ports %v, local/tasks/local.yml gives %v to the preflight checks", [label, sort([p | some p in host_ports]), sort([p | some p in wanted])])
}

deny contains msg if {
	count(proxies) == 0
	msg := sprintf("%s: no EnvoyProxy among the checked files: the proxy would get random node ports, which no extraPortMappings reaches", [label])
}

deny contains msg if {
	count(proxies) > 0
	count(node_ports) == 0
	msg := sprintf("%s: the EnvoyProxy fixes no nodePort on the Service of the proxy", [label])
}

deny contains msg if {
	some port in node_ports
	not port in container_ports
	msg := sprintf("%s: the EnvoyProxy fixes the nodePort %v, which no extraPortMappings of local/kind/cluster.yaml publishes (containerPort)", [label, port])
}

# The EnvoyProxy is what ADR-005 writes and nothing more (SECU review of the
# PR of step 7): a NodePort Service patched by strategic merge on spec.ports,
# each port with a port and a nodePort, and no other key where a key would
# reach another object (externalIPs, a Deployment patch, a bootstrap).
keys_beyond(value, allowed) := {key | some key, _ in value; not key in allowed} if is_object(value)

keys_beyond(value, _) := set() if not is_object(value)

proxy_spec(proxy) := object.get(proxy, "spec", {})

kubernetes_of(proxy) := object.get(object.get(proxy_spec(proxy), "provider", {}), "kubernetes", {})

service_of(proxy) := object.get(kubernetes_of(proxy), "envoyService", {})

patch_of(proxy) := object.get(service_of(proxy), "patch", {})

value_of(proxy) := object.get(patch_of(proxy), "value", {})

deny contains msg if {
	some proxy in proxies
	object.get(service_of(proxy), "type", null) != "NodePort"
	msg := sprintf("%s: provider.kubernetes.envoyService.type must be NodePort, found %v", [label, object.get(service_of(proxy), "type", null)])
}

deny contains msg if {
	some proxy in proxies
	object.get(patch_of(proxy), "type", null) != "StrategicMerge"
	msg := sprintf("%s: provider.kubernetes.envoyService.patch.type must be StrategicMerge, found %v", [label, object.get(patch_of(proxy), "type", null)])
}

deny contains msg if {
	some proxy in proxies
	extra := keys_beyond(proxy_spec(proxy), {"provider"})
	count(extra) > 0
	msg := sprintf("%s: the spec of the EnvoyProxy holds provider only, found also %v", [label, sort([k | some k in extra])])
}

deny contains msg if {
	some proxy in proxies
	extra := keys_beyond(kubernetes_of(proxy), {"envoyService", "envoyDeployment"})
	count(extra) > 0
	msg := sprintf("%s: provider.kubernetes holds envoyService and envoyDeployment only, found also %v", [label, sort([k | some k in extra])])
}

# The image of the proxy (ADR-005, complement of 2026-11-26). The controller
# compiles a default image into its binary (DefaultEnvoyProxyImage, by tag and
# digest in v1.10.0); the EnvoyProxy writes it down, so that the repository
# names the image that runs, the inventory of the scan reads it (S25) and
# Renovate follows it. The field is
# provider.kubernetes.envoyDeployment.container.image (api/v1alpha1 of
# Envoy Gateway v1.10.0, shared_types.go, KubernetesDeploymentSpec.Container
# and KubernetesContainerSpec.Image), and nothing else of the Deployment is
# set: no patch, no replicas, no securityContext, no imageRepository.
envoy_deployment_of(proxy) := object.get(kubernetes_of(proxy), "envoyDeployment", {})

container_of(proxy) := object.get(envoy_deployment_of(proxy), "container", {})

proxy_image_of(proxy) := object.get(container_of(proxy), "image", null)

proxy_image_pattern := `^docker\.io/envoyproxy/envoy:[A-Za-z0-9._-]+@sha256:[a-f0-9]{64}$`

deny contains msg if {
	some proxy in proxies
	extra := keys_beyond(envoy_deployment_of(proxy), {"container"})
	count(extra) > 0
	msg := sprintf("%s: provider.kubernetes.envoyDeployment holds container only, found also %v", [label, sort([k | some k in extra])])
}

deny contains msg if {
	some proxy in proxies
	extra := keys_beyond(container_of(proxy), {"image"})
	count(extra) > 0
	msg := sprintf("%s: provider.kubernetes.envoyDeployment.container holds image only, found also %v", [label, sort([k | some k in extra])])
}

deny contains msg if {
	some proxy in proxies
	proxy_image_of(proxy) == null
	msg := sprintf("%s: the EnvoyProxy fixes no image: provider.kubernetes.envoyDeployment.container.image pins the proxy by digest (ADR-005, complement of 2026-11-26)", [label])
}

proxy_image_valid(proxy) if {
	image := proxy_image_of(proxy)
	is_string(image)
	regex.match(proxy_image_pattern, image)
}

deny contains msg if {
	some proxy in proxies
	proxy_image_of(proxy) != null
	not proxy_image_valid(proxy)
	msg := sprintf("%s: the proxy image %v must be written by digest under docker.io/envoyproxy/envoy, docker.io/envoyproxy/envoy:<tag>@sha256:<64 hex digits>", [label, proxy_image_of(proxy)])
}

deny contains msg if {
	some proxy in proxies
	extra := keys_beyond(service_of(proxy), {"type", "patch"})
	count(extra) > 0
	msg := sprintf("%s: provider.kubernetes.envoyService holds type and patch only, found also %v", [label, sort([k | some k in extra])])
}

deny contains msg if {
	some proxy in proxies
	extra := keys_beyond(patch_of(proxy), {"type", "value"})
	count(extra) > 0
	msg := sprintf("%s: provider.kubernetes.envoyService.patch holds type and value only, found also %v", [label, sort([k | some k in extra])])
}

deny contains msg if {
	some proxy in proxies
	extra := keys_beyond(value_of(proxy), {"spec"})
	count(extra) > 0
	msg := sprintf("%s: the envoyService.patch.value holds spec only, found also %v", [label, sort([k | some k in extra])])
}

deny contains msg if {
	some proxy in proxies
	extra := keys_beyond(object.get(value_of(proxy), "spec", {}), {"ports"})
	count(extra) > 0
	msg := sprintf("%s: the envoyService.patch.value.spec holds ports only, found also %v", [label, sort([k | some k in extra])])
}

deny contains msg if {
	some proxy in proxies
	some entry in service_ports(proxy)
	extra := keys_beyond(entry, {"port", "nodePort"})
	count(extra) > 0
	msg := sprintf("%s: each port of the envoyService patch carries port and nodePort only, found also %v", [label, sort([k | some k in extra])])
}
