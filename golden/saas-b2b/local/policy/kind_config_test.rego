# Tests of S05 (kind_config.rego), run by `conftest verify`.
package kind_config

node_image := "kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed"

valid := {
	"kind": "Cluster",
	"apiVersion": "kind.x-k8s.io/v1alpha4",
	"networking": {"apiServerAddress": "127.0.0.1"},
	"nodes": [{"role": "control-plane", "image": node_image}],
}

checked(contents) := [{"path": "local/kind/cluster.yaml", "contents": contents}]

accepted(files) if {
	msgs := deny with input as files
	count(msgs) == 0
}

denied_with(files, fragment) if {
	msgs := deny with input as files
	some msg in msgs
	contains(msg, fragment)
}

with_node(node) := object.union(valid, {"nodes": [node]})

test_s05_accepts_the_valid_config if {
	accepted(checked(valid))
}

test_s05_accepts_a_port_mapping_on_the_loopback if {
	node := {"role": "control-plane", "image": node_image, "extraPortMappings": [{"containerPort": 30080, "hostPort": 8080, "listenAddress": "127.0.0.1"}]}
	accepted(checked(with_node(node)))
}

test_s05_accepts_the_file_under_the_golden_repo_of_celian if {
	accepted([{"path": "golden/saas-b2b/local/kind/cluster.yaml", "contents": valid}])
}

test_s05_rejects_an_input_without_the_kind_config if {
	denied_with([{"path": "local/kind/other.yaml", "contents": valid}], "expected one local/kind/cluster.yaml")
}

test_s05_rejects_another_kind if {
	denied_with(checked(object.union(valid, {"kind": "Config"})), "kind must be Cluster")
}

test_s05_rejects_another_api_version if {
	denied_with(checked(object.union(valid, {"apiVersion": "kind.x-k8s.io/v1alpha3"})), "apiVersion must be kind.x-k8s.io/v1alpha4")
}

test_s05_rejects_a_missing_api_server_address if {
	denied_with(checked(object.remove(valid, {"networking"})), "networking.apiServerAddress must be 127.0.0.1, found null")
}

test_s05_rejects_an_api_server_on_every_interface if {
	denied_with(checked(object.union(valid, {"networking": {"apiServerAddress": "0.0.0.0"}})), "found 0.0.0.0")
}

test_s05_rejects_a_config_without_nodes if {
	denied_with(checked(object.remove(valid, {"nodes"})), "no node")
}

test_s05_rejects_a_node_without_image if {
	denied_with(checked(with_node({"role": "control-plane"})), "nodes[0].image must be a tag and a sha256 digest, found null")
}

test_s05_rejects_a_node_image_by_tag if {
	denied_with(checked(with_node({"role": "control-plane", "image": "kindest/node:v1.36.4"})), "nodes[0].image must be a tag and a sha256 digest")
}

test_s05_rejects_a_node_image_with_a_short_digest if {
	denied_with(checked(with_node({"role": "control-plane", "image": "kindest/node:v1.36.4@sha256:099e0493"})), "nodes[0].image must be a tag and a sha256 digest")
}

test_s05_rejects_a_port_mapping_without_listen_address if {
	node := {"role": "control-plane", "image": node_image, "extraPortMappings": [{"containerPort": 30080, "hostPort": 8080}]}
	denied_with(checked(with_node(node)), "nodes[0].extraPortMappings[0].listenAddress must be 127.0.0.1, found null")
}

test_s05_rejects_a_port_mapping_on_every_interface if {
	node := {"role": "control-plane", "image": node_image, "extraPortMappings": [{"containerPort": 30443, "hostPort": 8443, "listenAddress": "::"}]}
	denied_with(checked(with_node(node)), "found ::")
}

test_s05_names_its_requirements_in_each_message if {
	msgs := deny with input as checked(object.remove(valid, {"networking"}))
	count(msgs) == 1
	every msg in msgs {
		startswith(msg, "S05 (FR-003, FR-008;")
	}
}
