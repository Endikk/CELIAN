# Tests of S05, ports part (host_ports.rego), run by `conftest verify`.
package host_ports

mapping(container, host) := {"containerPort": container, "hostPort": host, "listenAddress": "127.0.0.1"}

cluster(mappings) := {"path": "local/kind/cluster.yaml", "contents": {
	"kind": "Cluster",
	"nodes": [{"role": "control-plane", "extraPortMappings": mappings}],
}}

proxy(ports) := {"path": "local/platform/envoy-proxy.yaml", "contents": {
	"apiVersion": "gateway.envoyproxy.io/v1alpha1",
	"kind": "EnvoyProxy",
	"spec": {"provider": {"type": "Kubernetes", "kubernetes": {"envoyService": {
		"type": "NodePort",
		"patch": {"type": "StrategicMerge", "value": {"spec": {"ports": ports}}},
	}}}},
}}

both := [mapping(30080, 18080), mapping(30443, 18443)]

valid := [cluster(both), proxy([{"port": 80, "nodePort": 30080}])]

accepted(files, ports) if {
	msgs := deny with input as files with data.task_host_ports as ports
	count(msgs) == 0
}

denied_with(files, ports, fragment) if {
	msgs := deny with input as files with data.task_host_ports as ports
	some msg in msgs
	contains(msg, fragment)
}

test_s05_ports_accepts_the_valid_layer if {
	accepted(valid, [18080, 18443])
}

test_s05_ports_accepts_both_node_ports if {
	accepted([cluster(both), proxy([{"port": 80, "nodePort": 30080}, {"port": 443, "nodePort": 30443}])], [18443, 18080])
}

test_s05_ports_rejects_tasks_without_ports if {
	denied_with(valid, [], "gives no host port")
}

test_s05_ports_rejects_another_port_in_the_tasks if {
	denied_with(valid, [8080, 18443], "local/tasks/local.yml gives [8080, 18443]")
}

test_s05_ports_rejects_a_port_missing_from_the_tasks if {
	denied_with(valid, [18080], "publishes the host ports [18080, 18443]")
}

test_s05_ports_rejects_a_mapping_without_host_port if {
	files := [cluster([{"containerPort": 30080, "listenAddress": "127.0.0.1"}]), proxy([{"port": 80, "nodePort": 30080}])]
	denied_with(files, [18080], "extraPortMappings[0].hostPort must be a port number")
}

test_s05_ports_rejects_a_missing_envoy_proxy if {
	denied_with([cluster(both)], [18080, 18443], "no EnvoyProxy")
}

test_s05_ports_rejects_an_envoy_proxy_without_node_port if {
	denied_with([cluster(both), proxy([{"port": 80}])], [18080, 18443], "fixes no nodePort")
}

test_s05_ports_rejects_a_node_port_that_no_mapping_reaches if {
	denied_with([cluster(both), proxy([{"port": 80, "nodePort": 30081}])], [18080, 18443], "nodePort 30081")
}
