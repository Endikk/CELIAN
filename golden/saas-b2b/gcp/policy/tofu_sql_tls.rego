# S15: the server certificate of Cloud SQL, written out, and the two values
# that the user copies into the manifests of the gcp layer after the apply
# (spec 001, FR-011; ADR-012; research RS-12 and RS-16; tasks.md, gaps 95
# and 142).
#
# - settings.ip_configuration.server_ca_mode is written
#   GOOGLE_MANAGED_INTERNAL_CA: one CA for each instance. The page of Google
#   makes it the default when nothing is written, and says that with it
#   "Verifying the CA verifies the server identity"; with the shared CA of a
#   region, the hostname has to be verified as well, which a private IP
#   instance cannot do (read on 2026-11-26, research RS-12). A default left
#   unwritten could change under the root, and the client mode VerifyCA of
#   the gcp layer rests on this value.
# - the outputs database_private_ip and database_server_ca_cert exist, and
#   read the instance: they are what the user pastes into app-config and
#   app-ca (research RS-16). Neither is a secret: an address and a public
#   certificate. No output carries a password, which S15 refuses elsewhere.
#
# Input: the .tf files given to `conftest test --combine` (research RS-18).
package tofu_sql_tls

label := "S15 (FR-011; ADR-012; research RS-12 and RS-16)"

tf_files contains file if {
	some file in input
	endswith(file.path, ".tf")
}

resources contains {"path": file.path, "type": type, "name": name, "body": body} if {
	some file in tf_files
	some type, named in object.get(file.contents, "resource", {})
	some name, bodies in named
	some body in bodies
}

blocks_of(type) := {block | some block in resources; block.type == type}

where(block) := sprintf("%s: %s.%s", [block.path, block.type, block.name])

first(body, key) := object.get(body, key, [{}])[0]

deny contains msg if {
	some instance in blocks_of("google_sql_database_instance")
	ip := first(first(instance.body, "settings"), "ip_configuration")
	mode := object.get(ip, "server_ca_mode", "")
	mode != "GOOGLE_MANAGED_INTERNAL_CA"
	msg := sprintf("%s: %s: settings.ip_configuration.server_ca_mode is '%v'; write GOOGLE_MANAGED_INTERNAL_CA, the CA of one instance, which VerifyCA checks", [label, where(instance), mode])
}

outputs contains {"name": name, "value": value} if {
	some file in tf_files
	some name, bodies in object.get(file.contents, "output", {})
	some body in bodies
	value := object.get(body, "value", "")
}

wanted_outputs := {
	"database_private_ip": "google_sql_database_instance.main.private_ip_address",
	"database_server_ca_cert": "google_sql_database_instance.main.server_ca_cert",
}

deny contains msg if {
	count(blocks_of("google_sql_database_instance")) > 0
	some name, expression in wanted_outputs
	not output_reads(name, expression)
	msg := sprintf("%s: no output %s that reads %s: the user copies it into the manifests of gcp/k8s/values/ after the apply", [label, name, expression])
}

# The provider marks server_ca_cert sensitive (schema of
# google_sql_database_instance at v8.12.0, Sensitive: true, read on
# 2026-11-26), and OpenTofu refuses, at plan time, an output that reads a
# sensitive value without the flag. No check here runs a plan, so the flag
# is asked for. The certificate is public: the flag only keeps it out of the
# listing of `tofu output`, and `tofu output -raw database_server_ca_cert`
# still prints it.
deny contains msg if {
	count(blocks_of("google_sql_database_instance")) > 0
	some file in tf_files
	some body in object.get(file.contents, "output", {})["database_server_ca_cert"]
	not body.sensitive == true
	msg := sprintf("%s: output database_server_ca_cert is not sensitive = true: the provider marks server_ca_cert sensitive, and a plan refuses the output without the flag", [label])
}

output_reads(name, expression) if {
	some out in outputs
	out.name == name
	contains(out.value, expression)
}
