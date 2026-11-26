# S31: the values of the gcp layer that the user writes after the first apply,
# and the producer of db-auth (spec 001, plan, matrix S31; contracts/layers.md,
# "app-config"; contracts/secrets.md; ADR-007, conditions 2 and 5; ADR-012;
# ADR-015, condition 7; research RS-16 and RS-12; tasks.md, gaps 75 and 108).
#
# The host of the database and the CA of Cloud SQL exist only after the apply,
# and Config Sync reads a manifest from Git. The values are written into three
# manifests of gcp/k8s/values/ by the person who applies, and reviewed in a
# pull request (research RS-16, "Hôte et CA des services managés"). Until the
# apply they are placeholders, which this policy accepts and which fail
# closed: a host under .invalid never resolves, and an empty CA bundle stops
# the API at start, with a message that names the file.
#
# - app-config: the closed list of the keys of contracts/layers.md, nothing
#   else, every value a string. DATABASE_SSL_MODE is VerifyCA or VerifyFull:
#   Disable, Allow and Prefer encrypt nothing or fall back, and Require
#   encrypts without checking the server (decision of the DSI, 2026-11-26,
#   gap 75; Npgsql, security page). CACHE_TLS_MODE is VerifyCA or VerifyFull
#   as well: Disable is refused on gcp (gap 108). A host is a placeholder
#   under .invalid, a private IPv4 address or a DNS name, never a loopback
#   address, a URL or a name with a port.
# - app-ca: one ConfigMap with the bundles of the two CAs, public by nature.
#   Each value is empty (placeholder) or one to four PEM certificates that
#   parse, each a CA. A private key inside is refused.
# - SecretProviderClass and SecretSync of db-auth: the producer of the
#   Secret on gcp (ADR-007): same name and same keys as on local, read from
#   the two secrets of Secret Manager that OpenTofu writes, at a version
#   written as a number. The project is a placeholder until the apply.
#   secretObject.type is Opaque: the page of Google names Opaque, tls and
#   docker-registry and does not say that kubernetes.io/basic-auth, the type
#   of db-auth on local, is accepted (read on 2026-11-26); the test of
#   ADR-007, condition 3, on GKE settles it.
#
# Input: the render of gcp/k8s/prod given to `conftest test --combine`, one
# entry per YAML document with its `path` and parsed `contents`
# (gcp/tests/static/s31-gcp-values.sh).
package gcp_values

label := "S31 (FR-010; ADR-007, condition 5; ADR-012; ADR-015, condition 7)"

config_keys := {
	"DATABASE_HOST", "DATABASE_PORT", "DATABASE_NAME", "DATABASE_SSL_MODE",
	"CACHE_HOST", "CACHE_PORT", "CACHE_TLS_MODE", "CACHE_TLS_CA_FILE",
}

ca_keys := {"database-ca.pem", "cache-ca.pem"}

# Where the common Deployment mounts app-ca (tasks.md, gap 143).
cache_ca_path := "/run/config/ca/cache-ca.pem"

tls_modes := {"verifyca", "verifyfull"}

objects contains [path, obj] if {
	some file in input
	path := file.path
	obj := file.contents
	is_object(obj)
}

describe(obj) := sprintf("%v %v", [object.get(obj, "kind", null), object.get(object.get(obj, "metadata", {}), "name", null)])

named(kind, name) := {[path, obj] |
	some [path, obj] in objects
	obj.kind == kind
	obj.metadata.name == name
}

app_namespaces contains name if {
	some [_, obj] in objects
	obj.kind == "Namespace"
	name := obj.metadata.name
}

# --- app-config ---------------------------------------------------------------

config_maps := named("ConfigMap", "app-config")

deny contains msg if {
	count(config_maps) != 1
	msg := sprintf("%s: %d ConfigMap app-config in the render, one expected (contracts/layers.md)", [label, count(config_maps)])
}

deny contains msg if {
	some [path, cm] in config_maps
	keys := {k | some k, _ in object.get(cm, "data", {})}
	missing := config_keys - keys
	count(missing) > 0
	msg := sprintf("%s: %s, app-config lacks the keys %v", [label, path, sort(missing)])
}

deny contains msg if {
	some [path, cm] in config_maps
	keys := {k | some k, _ in object.get(cm, "data", {})}
	extra := keys - config_keys
	count(extra) > 0
	msg := sprintf("%s: %s, app-config holds the keys %v, outside the closed list of contracts/layers.md", [label, path, sort(extra)])
}

deny contains msg if {
	some [path, cm] in config_maps
	some k, v in object.get(cm, "data", {})
	not is_string(v)
	msg := sprintf("%s: %s, app-config key %s is not a string", [label, path, k])
}

deny contains msg if {
	some [path, cm] in config_maps
	some k, _ in object.get(cm, "data", {})
	contains(lower(k), "password")
	msg := sprintf("%s: %s, app-config key %s names a password: app-config carries no secret", [label, path, k])
}

value_of(cm, key) := object.get(object.get(cm, "data", {}), key, "")

deny contains msg if {
	some [path, cm] in config_maps
	mode := value_of(cm, "DATABASE_SSL_MODE")
	not lower(mode) in tls_modes
	msg := sprintf("%s: %s, DATABASE_SSL_MODE is %q: VerifyCA or VerifyFull only on gcp (Disable, Allow and Prefer do not check the server, Require encrypts without checking it)", [label, path, mode])
}

deny contains msg if {
	some [path, cm] in config_maps
	mode := value_of(cm, "CACHE_TLS_MODE")
	not lower(mode) in tls_modes
	msg := sprintf("%s: %s, CACHE_TLS_MODE is %q: VerifyCA or VerifyFull only on gcp, TLS is on from the creation of the instance (ADR-015, condition 7)", [label, path, mode])
}

deny contains msg if {
	some [path, cm] in config_maps
	value_of(cm, "DATABASE_NAME") != "app"
	msg := sprintf("%s: %s, DATABASE_NAME is %q: the database that OpenTofu creates is app", [label, path, value_of(cm, "DATABASE_NAME")])
}

deny contains msg if {
	some [path, cm] in config_maps
	some key in ["DATABASE_PORT", "CACHE_PORT"]
	not port_ok(value_of(cm, key))
	msg := sprintf("%s: %s, %s is %q: a whole number from 1 to 65535", [label, path, key, value_of(cm, key)])
}

port_ok(value) if {
	regex.match(`^[1-9][0-9]{0,4}$`, value)
	to_number(value) <= 65535
}

deny contains msg if {
	some [path, cm] in config_maps
	some key in ["DATABASE_HOST", "CACHE_HOST"]
	not host_ok(value_of(cm, key))
	msg := sprintf("%s: %s, %s is %q: a placeholder under .invalid, a private IPv4 address or a DNS name, without scheme, port or path, never a loopback address", [label, path, key, value_of(cm, key)])
}

dns_name := `^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]{0,61}[a-z0-9]$`

ipv4 := `^[0-9]{1,3}(\.[0-9]{1,3}){3}$`

host_ok(host) if {
	regex.match(dns_name, host)
	not host == "localhost"
}

host_ok(host) if {
	regex.match(ipv4, host)
	some range in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
	net.cidr_contains(range, host)
}

deny contains msg if {
	some [path, cm] in config_maps
	value_of(cm, "CACHE_TLS_CA_FILE") != cache_ca_path
	msg := sprintf("%s: %s, CACHE_TLS_CA_FILE is %q: %s, where the API finds app-ca (research RS-16)", [label, path, value_of(cm, "CACHE_TLS_CA_FILE"), cache_ca_path])
}

deny contains msg if {
	some [path, cm] in config_maps
	not cm.metadata.namespace in app_namespaces
	msg := sprintf("%s: %s, app-config is not in the namespace of the application %v", [label, path, app_namespaces])
}

# --- app-ca -------------------------------------------------------------------

ca_maps := named("ConfigMap", "app-ca")

deny contains msg if {
	count(ca_maps) != 1
	msg := sprintf("%s: %d ConfigMap app-ca in the render, one expected: it carries the CA of the database and of the cache", [label, count(ca_maps)])
}

deny contains msg if {
	some [path, cm] in ca_maps
	keys := {k | some k, _ in object.get(cm, "data", {})}
	keys != ca_keys
	msg := sprintf("%s: %s, app-ca holds the keys %v, %v expected", [label, path, sort(keys), sort(ca_keys)])
}

deny contains msg if {
	some [path, cm] in ca_maps
	count(object.get(cm, "binaryData", {})) > 0
	msg := sprintf("%s: %s, app-ca holds binaryData: PEM certificates are text, in data", [label, path])
}

deny contains msg if {
	some [path, cm] in ca_maps
	not cm.metadata.namespace in app_namespaces
	msg := sprintf("%s: %s, app-ca is not in the namespace of the application %v", [label, path, app_namespaces])
}

deny contains msg if {
	some [path, cm] in ca_maps
	some key, pem in object.get(cm, "data", {})
	contains(pem, "PRIVATE KEY")
	msg := sprintf("%s: %s, app-ca %s holds a private key", [label, path, key])
}

deny contains msg if {
	some [path, cm] in ca_maps
	some key, pem in object.get(cm, "data", {})
	trim_space(pem) != ""
	not contains(pem, "PRIVATE KEY")
	not parsed(pem)
	msg := sprintf("%s: %s, app-ca %s is not a PEM bundle that parses as X.509 certificates", [label, path, key])
}

parsed(pem) := crypto.x509.parse_certificates(pem)

deny contains msg if {
	some [path, cm] in ca_maps
	some key, pem in object.get(cm, "data", {})
	trim_space(pem) != ""
	certs := parsed(pem)
	not count(certs) in {1, 2, 3, 4}
	msg := sprintf("%s: %s, app-ca %s holds %d certificates, one to four expected", [label, path, key, count(certs)])
}

deny contains msg if {
	some [path, cm] in ca_maps
	some key, pem in object.get(cm, "data", {})
	some cert in parsed(pem)
	not cert.IsCA == true
	msg := sprintf("%s: %s, app-ca %s holds a certificate that is not a CA (subject %v): a server certificate pinned as the root would break at its rotation", [label, path, key, cert.Subject.CommonName])
}

# --- db-auth ------------------------------------------------------------------

provider_classes := named("SecretProviderClass", "db-auth")

secret_syncs := named("SecretSync", "db-auth")

secret_pattern := `^projects/(PROJECT_ID|[a-z][a-z0-9-]{4,28}[a-z0-9])/secrets/[a-z][a-z0-9-]*-db-auth-(username|password)/versions/[0-9]+$`

deny contains msg if {
	count(provider_classes) != 1
	msg := sprintf("%s: %d SecretProviderClass db-auth in the render, one expected (ADR-007)", [label, count(provider_classes)])
}

deny contains msg if {
	count(secret_syncs) != 1
	msg := sprintf("%s: %d SecretSync db-auth in the render, one expected: it produces the Secret db-auth (contracts/secrets.md)", [label, count(secret_syncs)])
}

deny contains msg if {
	some [path, spc] in provider_classes
	not spc.apiVersion == "secrets-store.csi.x-k8s.io/v1"
	msg := sprintf("%s: %s, %s has apiVersion %v, secrets-store.csi.x-k8s.io/v1 expected", [label, path, describe(spc), object.get(spc, "apiVersion", "unset")])
}

deny contains msg if {
	some [path, spc] in provider_classes
	not spc.spec.provider == "gke"
	msg := sprintf("%s: %s, %s has provider %v, gke expected", [label, path, describe(spc), object.get(object.get(spc, "spec", {}), "provider", "unset")])
}

spc_entries(spc) := yaml.unmarshal(spc.spec.parameters.secrets)

deny contains msg if {
	some [path, spc] in provider_classes
	not spc_entries(spc)
	msg := sprintf("%s: %s, %s has no parseable spec.parameters.secrets", [label, path, describe(spc)])
}

deny contains msg if {
	some [path, spc] in provider_classes
	entries := spc_entries(spc)
	paths := {e.path | some e in entries}
	paths != {"username", "password"}
	msg := sprintf("%s: %s, %s reads the paths %v, {\"password\", \"username\"} expected: the two keys of db-auth", [label, path, describe(spc), paths])
}

deny contains msg if {
	some [path, spc] in provider_classes
	some entry in spc_entries(spc)
	not regex.match(secret_pattern, entry.resourceName)
	msg := sprintf("%s: %s, %s has the resourceName %q: projects/<project>/secrets/<name>-db-auth-<username|password>/versions/<number>", [label, path, describe(spc), entry.resourceName])
}

deny contains msg if {
	some [path, spc] in provider_classes
	some entry in spc_entries(spc)
	regex.match(secret_pattern, entry.resourceName)
	not regex.match(sprintf("-db-auth-%s/versions/[0-9]+$", [entry.path]), entry.resourceName)
	msg := sprintf("%s: %s, %s reads %q into the path %v: each path takes the secret of its own key", [label, path, describe(spc), entry.resourceName, entry.path])
}

deny contains msg if {
	some [path, spc] in provider_classes
	not spc.metadata.namespace in app_namespaces
	msg := sprintf("%s: %s, %s is not in the namespace of the application %v", [label, path, describe(spc), app_namespaces])
}

deny contains msg if {
	some [path, sync] in secret_syncs
	not sync.apiVersion == "secret-sync.gke.io/v1"
	msg := sprintf("%s: %s, %s has apiVersion %v, secret-sync.gke.io/v1 expected", [label, path, describe(sync), object.get(sync, "apiVersion", "unset")])
}

deny contains msg if {
	some [path, sync] in secret_syncs
	not sync.metadata.namespace in app_namespaces
	msg := sprintf("%s: %s, %s is not in the namespace of the application %v: it must sit with its SecretProviderClass", [label, path, describe(sync), app_namespaces])
}

deny contains msg if {
	some [path, sync] in secret_syncs
	some [_, spc] in provider_classes
	sync.metadata.namespace != spc.metadata.namespace
	msg := sprintf("%s: %s, %s is not in the namespace of its SecretProviderClass (page of Google: \"It must be the same namespace as the SecretProviderClass\")", [label, path, describe(sync)])
}

deny contains msg if {
	some [path, sync] in secret_syncs
	not sync.spec.secretProviderClassName == "db-auth"
	msg := sprintf("%s: %s, %s reads the class %v, db-auth expected", [label, path, describe(sync), object.get(object.get(sync, "spec", {}), "secretProviderClassName", "unset")])
}

service_accounts contains name if {
	some [_, obj] in objects
	obj.kind == "ServiceAccount"
	name := obj.metadata.name
}

deny contains msg if {
	some [path, sync] in secret_syncs
	not sync.spec.serviceAccountName in service_accounts
	msg := sprintf("%s: %s, %s uses the service account %v, which is not in the render (ADR-007, condition 2: the secrets are read by one account)", [label, path, describe(sync), object.get(object.get(sync, "spec", {}), "serviceAccountName", "unset")])
}

deny contains msg if {
	some [path, sync] in secret_syncs
	not sync.spec.secretObject.type == "Opaque"
	msg := sprintf("%s: %s, %s has secretObject.type %v, Opaque expected until the test of ADR-007 (condition 3) shows another type accepted", [label, path, describe(sync), object.get(object.get(object.get(sync, "spec", {}), "secretObject", {}), "type", "unset")])
}

deny contains msg if {
	some [path, sync] in secret_syncs
	pairs := {[d.sourcePath, d.targetKey] | some d in sync.spec.secretObject.data}
	pairs != {["username", "username"], ["password", "password"]}
	msg := sprintf("%s: %s, %s maps %v: the Secret takes the keys username and password, read from the paths of the same name (contracts/secrets.md)", [label, path, describe(sync), pairs])
}
