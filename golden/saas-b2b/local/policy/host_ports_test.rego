# Tests of S05, ports part (host_ports.rego), run by `conftest verify`.
package host_ports

mapping(container, host) := {"containerPort": container, "hostPort": host, "listenAddress": "127.0.0.1"}

cluster(mappings) := {"path": "local/kind/cluster.yaml", "contents": {
	"kind": "Cluster",
	"nodes": [{"role": "control-plane", "extraPortMappings": mappings}],
}}

proxy_image := "docker.io/envoyproxy/envoy:distroless-v1.40.2@sha256:09ca6f2140a61ad8df11779a4a30d52b48433d444466328494f9188c9c35eded"

deployment_of(image) := {"container": {"image": image}}

proxy(ports) := {"path": "local/platform/envoy-proxy.yaml", "contents": {
	"apiVersion": "gateway.envoyproxy.io/v1alpha1",
	"kind": "EnvoyProxy",
	"spec": {"provider": {"type": "Kubernetes", "kubernetes": {
		"envoyService": {
			"type": "NodePort",
			"patch": {"type": "StrategicMerge", "value": {"spec": {"ports": ports}}},
		},
		"envoyDeployment": deployment_of(proxy_image),
	}}},
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

# The EnvoyProxy stays what ADR-005 writes: a NodePort Service whose ports
# are patched, and nothing else (SECU review of the PR of step 7).
good_ports := [{"port": 80, "nodePort": 30080}]

good_service := {
	"type": "NodePort",
	"patch": {"type": "StrategicMerge", "value": {"spec": {"ports": good_ports}}},
}

proxy_of(spec) := {"path": "local/platform/envoy-proxy.yaml", "contents": {
	"apiVersion": "gateway.envoyproxy.io/v1alpha1",
	"kind": "EnvoyProxy",
	"spec": spec,
}}

with_service(service) := proxy_of({"provider": {"type": "Kubernetes", "kubernetes": {"envoyService": service, "envoyDeployment": deployment_of(proxy_image)}}})

with_deployment(deployment) := proxy_of({"provider": {"type": "Kubernetes", "kubernetes": {"envoyService": good_service, "envoyDeployment": deployment}}})

denied_proxy(proxy_file, fragment) if denied_with([cluster(both), proxy_file], [18080, 18443], fragment)

test_s05_ports_accepts_the_written_proxy if {
	accepted([cluster(both), with_service(good_service)], [18080, 18443])
}

test_s05_ports_rejects_a_proxy_without_service_type if {
	denied_proxy(with_service(object.remove(good_service, ["type"])), "envoyService.type must be NodePort")
}

test_s05_ports_rejects_a_load_balancer_service if {
	denied_proxy(with_service(object.union(good_service, {"type": "LoadBalancer"})), "envoyService.type must be NodePort")
}

test_s05_ports_rejects_a_patch_without_type if {
	service := object.union(good_service, {"patch": {"type": "JSONMerge"}})
	denied_proxy(with_service(service), "patch.type must be StrategicMerge")
}

test_s05_ports_rejects_external_ips_in_the_patch if {
	service := {"type": "NodePort", "patch": {"type": "StrategicMerge", "value": {"spec": {"ports": good_ports, "externalIPs": ["203.0.113.7"]}}}}
	denied_proxy(with_service(service), "patch.value.spec holds ports only")
}

test_s05_ports_rejects_metadata_in_the_patch if {
	service := {"type": "NodePort", "patch": {"type": "StrategicMerge", "value": {"metadata": {"annotations": {"a": "b"}}, "spec": {"ports": good_ports}}}}
	denied_proxy(with_service(service), "patch.value holds spec only")
}

test_s05_ports_rejects_a_target_port_in_the_patch if {
	service := {"type": "NodePort", "patch": {"type": "StrategicMerge", "value": {"spec": {"ports": [{"port": 80, "nodePort": 30080, "targetPort": 22}]}}}}
	denied_proxy(with_service(service), "carries port and nodePort only")
}

test_s05_ports_rejects_another_key_of_the_service if {
	denied_proxy(with_service(object.union(good_service, {"externalTrafficPolicy": "Local"})), "envoyService holds type and patch only")
}

test_s05_ports_rejects_a_deployment_patch if {
	deployment := object.union(deployment_of(proxy_image), {"patch": {"type": "StrategicMerge", "value": {"spec": {"template": {"spec": {"hostNetwork": true}}}}}})
	denied_proxy(with_deployment(deployment), "envoyDeployment holds container only")
}

test_s05_ports_rejects_another_key_of_the_kubernetes_provider if {
	kubernetes := {"envoyService": good_service, "envoyDeployment": deployment_of(proxy_image), "envoyHpa": {"minReplicas": 1}}
	denied_proxy(proxy_of({"provider": {"type": "Kubernetes", "kubernetes": kubernetes}}), "provider.kubernetes holds envoyService and envoyDeployment only")
}

# The image of the proxy, by digest (ADR-005, complement of 2026-11-26): the
# field envoyDeployment.container.image of the EnvoyProxy, under the registry
# of the controller, written the way the controller compiles its default.
test_s05_ports_accepts_the_proxy_image_by_digest if {
	accepted([cluster(both), with_deployment(deployment_of(proxy_image))], [18080, 18443])
}

test_s05_ports_rejects_a_proxy_without_image if {
	denied_proxy(with_deployment({}), "the EnvoyProxy fixes no image")
}

test_s05_ports_rejects_a_proxy_image_by_tag_alone if {
	denied_proxy(with_deployment(deployment_of("docker.io/envoyproxy/envoy:distroless-v1.40.2")), "by digest")
}

test_s05_ports_rejects_a_proxy_image_from_another_registry if {
	other := "ghcr.io/envoyproxy/envoy:distroless-v1.40.2@sha256:09ca6f2140a61ad8df11779a4a30d52b48433d444466328494f9188c9c35eded"
	denied_proxy(with_deployment(deployment_of(other)), "docker.io/envoyproxy/envoy")
}

test_s05_ports_rejects_a_proxy_image_from_another_repository if {
	other := "docker.io/library/busybox:1.37@sha256:09ca6f2140a61ad8df11779a4a30d52b48433d444466328494f9188c9c35eded"
	denied_proxy(with_deployment(deployment_of(other)), "docker.io/envoyproxy/envoy")
}

test_s05_ports_rejects_a_proxy_image_with_a_short_digest if {
	denied_proxy(with_deployment(deployment_of("docker.io/envoyproxy/envoy:distroless-v1.40.2@sha256:09ca6f21")), "by digest")
}

test_s05_ports_rejects_a_proxy_image_that_is_not_a_string if {
	denied_proxy(with_deployment(deployment_of(["docker.io/envoyproxy/envoy"])), "by digest")
}

test_s05_ports_rejects_an_image_repository_field if {
	deployment := {"container": {"imageRepository": "docker.io/envoyproxy/envoy", "image": proxy_image}}
	denied_proxy(with_deployment(deployment), "container holds image only")
}

test_s05_ports_rejects_a_container_override if {
	deployment := {"container": {"image": proxy_image, "securityContext": {"privileged": true}}}
	denied_proxy(with_deployment(deployment), "container holds image only")
}

test_s05_ports_rejects_a_replica_count_beside_the_container if {
	deployment := {"replicas": 3, "container": {"image": proxy_image}}
	denied_proxy(with_deployment(deployment), "envoyDeployment holds container only")
}

test_s05_ports_rejects_another_key_of_the_proxy_spec if {
	spec := {"provider": {"type": "Kubernetes", "kubernetes": {"envoyService": good_service}}, "bootstrap": {"type": "Replace", "value": "x"}}
	denied_proxy(proxy_of(spec), "spec of the EnvoyProxy holds provider only")
}
