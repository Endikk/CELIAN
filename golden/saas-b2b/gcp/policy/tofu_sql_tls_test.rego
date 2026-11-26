# Tests of S15 for the server certificate of Cloud SQL (tofu_sql_tls.rego),
# run by `conftest verify`. Each case changes one thing in a valid root.
package tofu_sql_tls

valid := {
	"resource": {"google_sql_database_instance": {"main": [{"settings": [{"ip_configuration": [{
		"ipv4_enabled": false,
		"server_ca_mode": "GOOGLE_MANAGED_INTERNAL_CA",
	}]}]}]}},
	"output": {
		"database_private_ip": [{"value": "${google_sql_database_instance.main.private_ip_address}"}],
		"database_server_ca_cert": [{"value": "${google_sql_database_instance.main.server_ca_cert[0].cert}"}],
	},
}

files(contents) := [{"path": "gcp/tofu/main.tf", "contents": contents}]

patched(ops) := files(json.patch(valid, ops))

accepted(input_files) if {
	msgs := deny with input as input_files
	count(msgs) == 0
}

denied_with(input_files, fragment) if {
	msgs := deny with input as input_files
	some msg in msgs
	contains(msg, fragment)
}

ip_path := "/resource/google_sql_database_instance/main/0/settings/0/ip_configuration/0"

test_s15_accepts_a_valid_root if {
	accepted(files(valid))
}

test_s15_accepts_a_root_without_a_database if {
	accepted(files({"resource": {}}))
}

test_s15_rejects_an_unwritten_server_ca_mode if {
	denied_with(patched([{"op": "remove", "path": concat("/", [ip_path, "server_ca_mode"])}]), "server_ca_mode is ''")
}

test_s15_rejects_the_shared_ca if {
	ops := [{"op": "replace", "path": concat("/", [ip_path, "server_ca_mode"]), "value": "GOOGLE_MANAGED_CAS_CA"}]
	denied_with(patched(ops), "server_ca_mode is 'GOOGLE_MANAGED_CAS_CA'")
}

test_s15_rejects_the_customer_managed_ca if {
	ops := [{"op": "replace", "path": concat("/", [ip_path, "server_ca_mode"]), "value": "CUSTOMER_MANAGED_CAS_CA"}]
	denied_with(patched(ops), "server_ca_mode is 'CUSTOMER_MANAGED_CAS_CA'")
}

test_s15_rejects_a_missing_address_output if {
	denied_with(patched([{"op": "remove", "path": "/output/database_private_ip"}]), "no output database_private_ip")
}

test_s15_rejects_a_missing_ca_output if {
	denied_with(patched([{"op": "remove", "path": "/output/database_server_ca_cert"}]), "no output database_server_ca_cert")
}

test_s15_rejects_an_output_that_reads_something_else if {
	ops := [{"op": "replace", "path": "/output/database_private_ip/0/value", "value": "10.0.0.1"}]
	denied_with(patched(ops), "no output database_private_ip that reads")
}
