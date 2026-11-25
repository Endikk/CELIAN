# S05, ports part (spec 001, tasks.md, gap 10; research RS-20): the host
# ports of the gateway have one value each, kept in local/kind/cluster.yaml
# and in local/tasks/local.yml, and they lead to the proxy:
# - the hostPort values of the extraPortMappings are exactly the ports that
#   the tasks give to the preflight checks;
# - each nodePort that the EnvoyProxy of the local layer fixes on the
#   Service of the proxy is the containerPort of an extraPortMappings.
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
