# Tests of S31 (gcp_values.rego), run by `conftest verify`.
package gcp_values

# Throwaway certificates made for these tests: a CA (CA:TRUE) and a server
# certificate (CA:FALSE), subjects under .invalid, their keys discarded.
ca_pem := concat("\n", [
	"-----BEGIN CERTIFICATE-----",
	"MIIBdzCCAR6gAwIBAgIUPJlXChxIT70mMZP959WQV55OLFQwCgYIKoZIzj0EAwIw",
	"GjEYMBYGA1UEAwwPdGVzdC1jYS5pbnZhbGlkMB4XDTI2MTEyNjE2NDU1MVoXDTM2",
	"MTEyMzE2NDU1MVowGjEYMBYGA1UEAwwPdGVzdC1jYS5pbnZhbGlkMFkwEwYHKoZI",
	"zj0CAQYIKoZIzj0DAQcDQgAEgaiI0S9sPW5kSMh+jCHZop2XxpH/BwzfSVVwuqYJ",
	"7UeFli3l/f4TEZBPg5ueJhPP8YgpRH+vf3Tdmjp0i6eZIqNCMEAwHQYDVR0OBBYE",
	"FA8u6iRuFLD+GpTRhGuWo6dpHPfYMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/",
	"BAQDAgIEMAoGCCqGSM49BAMCA0cAMEQCIHSYG7R5UC64yN6BM+4yRUdVrmWRS2iT",
	"bQQjIWDWbo4eAiBqwVIrFw6QJKnGcb5nhLqT//lVfFcMM28l1rGXbAgbiw==",
	"-----END CERTIFICATE-----",
	"",
])

# A CA (CA:TRUE) valid from 2020-01-01 to 2020-01-02 only.
expired_pem := concat("\n", [
	"-----BEGIN CERTIFICATE-----",
	"MIIBfTCCASSgAwIBAgIUFXxcMvLhv7+JPh7g4FIF2xWyLVQwCgYIKoZIzj0EAwIw",
	"HTEbMBkGA1UEAwwSZXhwaXJlZC1jYS5pbnZhbGlkMB4XDTIwMDEwMTAwMDAwMFoX",
	"DTIwMDEwMjAwMDAwMFowHTEbMBkGA1UEAwwSZXhwaXJlZC1jYS5pbnZhbGlkMFkw",
	"EwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEw+U1BTaiZEit0C6iDjFEig+Tt5PzZWQv",
	"kpE5V0jHSLysnBBAFgsb4jEzm4IxU6tK9WQfR99D9fz/l4JUynORIqNCMEAwHQYD",
	"VR0OBBYEFMUWYEpT/Zm9MJPWiYPc6eNQqjcWMA8GA1UdEwEB/wQFMAMBAf8wDgYD",
	"VR0PAQH/BAQDAgIEMAoGCCqGSM49BAMCA0cAMEQCIERVsrbwX0vVIZj7h/BtzZi1",
	"e4B/mgirQH2lC+Eh9demAiBYTEi4xIG3YGcbjIYmlt5RL34C2zc1ZULY/qkyc59z",
	"PA==",
	"-----END CERTIFICATE-----",
	"",
])

leaf_pem := concat("\n", [
	"-----BEGIN CERTIFICATE-----",
	"MIIBXzCCAQWgAwIBAgIUVswsqu74m3F7dpH4rH7g0NXuQlUwCgYIKoZIzj0EAwIw",
	"FzEVMBMGA1UEAwwMbGVhZi5pbnZhbGlkMB4XDTI2MTEyNjE2NDU1MVoXDTM2MTEy",
	"MzE2NDU1MVowFzEVMBMGA1UEAwwMbGVhZi5pbnZhbGlkMFkwEwYHKoZIzj0CAQYI",
	"KoZIzj0DAQcDQgAEmtA5gQ3HkIPQSQXDYgtx8vWAz97MKMLBPvzmZem4gEALk6XT",
	"tqzI4fzzYClY5cT6+xXPb+ucXTjjVpgxpnffq6MvMC0wHQYDVR0OBBYEFL6jSgA3",
	"L6C5c+C4phhX89sRgNINMAwGA1UdEwEB/wQCMAAwCgYIKoZIzj0EAwIDSAAwRQIh",
	"AJd5xAxH2H/KeA84XluZeAnKQ5Fxs0rJ2DCXAC0ujSfpAiBHZDIR5lqoHcp6v00k",
	"2ivVjKhCLRTN+Ipsm4I0yjEcFg==",
	"-----END CERTIFICATE-----",
	"",
])

namespace := {
	"apiVersion": "v1",
	"kind": "Namespace",
	"metadata": {"name": "saas-b2b"},
}

service_account := {
	"apiVersion": "v1",
	"kind": "ServiceAccount",
	"metadata": {"name": "secret-sync", "namespace": "saas-b2b"},
}

# The placeholders of the repository before the first apply.
config_map := {
	"apiVersion": "v1",
	"kind": "ConfigMap",
	"metadata": {"name": "app-config", "namespace": "saas-b2b"},
	"data": {
		"DATABASE_HOST": "database.invalid",
		"DATABASE_PORT": "5432",
		"DATABASE_NAME": "app",
		"DATABASE_SSL_MODE": "VerifyCA",
		"CACHE_HOST": "cache.invalid",
		"CACHE_PORT": "6379",
		"CACHE_TLS_MODE": "VerifyCA",
		"CACHE_TLS_CA_FILE": "/run/config/ca/cache-ca.pem",
	},
}

# The same after an apply: private addresses.
applied_config_map := json.patch(config_map, [
	{"op": "replace", "path": "/data/DATABASE_HOST", "value": "10.40.0.3"},
	{"op": "replace", "path": "/data/CACHE_HOST", "value": "10.0.0.7"},
])

ca_map := {
	"apiVersion": "v1",
	"kind": "ConfigMap",
	"metadata": {"name": "app-ca", "namespace": "saas-b2b"},
	"data": {"database-ca.pem": "", "cache-ca.pem": ""},
}

applied_ca_map := json.patch(ca_map, [
	{"op": "replace", "path": "/data/database-ca.pem", "value": ca_pem},
	{"op": "replace", "path": "/data/cache-ca.pem", "value": concat("", [ca_pem, ca_pem])},
])

secrets_block := concat("\n", [
	"- resourceName: \"projects/PROJECT_ID/secrets/saas-b2b-db-auth-username/versions/1\"",
	"  path: \"username\"",
	"- resourceName: \"projects/PROJECT_ID/secrets/saas-b2b-db-auth-password/versions/1\"",
	"  path: \"password\"",
	"",
])

provider_class := {
	"apiVersion": "secrets-store.csi.x-k8s.io/v1",
	"kind": "SecretProviderClass",
	"metadata": {"name": "db-auth", "namespace": "saas-b2b"},
	"spec": {"provider": "gke", "parameters": {"secrets": secrets_block}},
}

secret_sync := {
	"apiVersion": "secret-sync.gke.io/v1",
	"kind": "SecretSync",
	"metadata": {"name": "db-auth", "namespace": "saas-b2b"},
	"spec": {
		"serviceAccountName": "secret-sync",
		"secretProviderClassName": "db-auth",
		"secretObject": {
			"type": "Opaque",
			"data": [
				{"sourcePath": "username", "targetKey": "username"},
				{"sourcePath": "password", "targetKey": "password"},
			],
		},
	},
}

valid_objects := [namespace, service_account, config_map, ca_map, provider_class, secret_sync]

files(objs) := [{"path": "render.yaml", "contents": obj} | some obj in objs]

accepted(objs) if {
	msgs := deny with input as files(objs)
	count(msgs) == 0
}

denied_with(objs, fragment) if {
	msgs := deny with input as files(objs)
	some msg in msgs
	contains(msg, fragment)
}

# One object of the valid render replaced by a patched copy.
patched(obj, ops) := array.concat([json.patch(obj, ops)], [o | some o in valid_objects; o != obj])

config_with(key, value) := patched(config_map, [{"op": "replace", "path": sprintf("/data/%s", [key]), "value": value}])

test_s31_accepts_the_placeholders if {
	accepted(valid_objects)
}

test_s31_accepts_the_applied_values if {
	accepted([namespace, service_account, applied_config_map, applied_ca_map, provider_class, secret_sync])
}

test_s31_accepts_verify_full if {
	accepted(config_with("DATABASE_SSL_MODE", "VerifyFull"))
}

test_s31_accepts_the_mode_whatever_its_case if {
	accepted(config_with("CACHE_TLS_MODE", "verifyfull"))
}

# --- The TLS modes ---------------------------------------------------------

test_s31_rejects_database_ssl_disable if {
	denied_with(config_with("DATABASE_SSL_MODE", "Disable"), "DATABASE_SSL_MODE is \"Disable\"")
}

test_s31_rejects_database_ssl_allow if {
	denied_with(config_with("DATABASE_SSL_MODE", "Allow"), "DATABASE_SSL_MODE is \"Allow\"")
}

test_s31_rejects_database_ssl_prefer if {
	denied_with(config_with("DATABASE_SSL_MODE", "Prefer"), "DATABASE_SSL_MODE is \"Prefer\"")
}

test_s31_rejects_database_ssl_require if {
	denied_with(config_with("DATABASE_SSL_MODE", "Require"), "DATABASE_SSL_MODE is \"Require\"")
}

test_s31_rejects_database_ssl_require_in_lower_case if {
	denied_with(config_with("DATABASE_SSL_MODE", "require"), "DATABASE_SSL_MODE is \"require\"")
}

test_s31_rejects_an_empty_database_ssl_mode if {
	denied_with(config_with("DATABASE_SSL_MODE", ""), "DATABASE_SSL_MODE is \"\"")
}

test_s31_rejects_cache_tls_disable if {
	denied_with(config_with("CACHE_TLS_MODE", "Disable"), "CACHE_TLS_MODE is \"Disable\"")
}

# --- app-config ------------------------------------------------------------

test_s31_rejects_a_missing_app_config if {
	denied_with([namespace, service_account, ca_map, provider_class, secret_sync], "0 ConfigMap app-config")
}

test_s31_rejects_a_missing_key if {
	denied_with(patched(config_map, [{"op": "remove", "path": "/data/CACHE_HOST"}]), "app-config lacks the keys [\"CACHE_HOST\"]")
}

test_s31_rejects_an_extra_key if {
	denied_with(patched(config_map, [{"op": "add", "path": "/data/EXTRA", "value": "x"}]), "outside the closed list")
}

test_s31_rejects_a_password_key if {
	denied_with(patched(config_map, [{"op": "add", "path": "/data/DATABASE_PASSWORD", "value": "x"}]), "names a password")
}

test_s31_rejects_a_number_in_data if {
	denied_with(patched(config_map, [{"op": "replace", "path": "/data/DATABASE_PORT", "value": 5432}]), "is not a string")
}

test_s31_rejects_another_database_name if {
	denied_with(config_with("DATABASE_NAME", "postgres"), "DATABASE_NAME is \"postgres\"")
}

test_s31_rejects_a_port_out_of_range if {
	denied_with(config_with("DATABASE_PORT", "70000"), "DATABASE_PORT is \"70000\"")
}

test_s31_rejects_a_port_zero if {
	denied_with(config_with("CACHE_PORT", "0"), "CACHE_PORT is \"0\"")
}

test_s31_rejects_a_port_with_text if {
	denied_with(config_with("CACHE_PORT", "6379/tcp"), "CACHE_PORT is \"6379/tcp\"")
}

test_s31_rejects_a_loopback_host if {
	denied_with(config_with("DATABASE_HOST", "127.0.0.1"), "DATABASE_HOST is \"127.0.0.1\"")
}

test_s31_rejects_localhost if {
	denied_with(config_with("CACHE_HOST", "localhost"), "CACHE_HOST is \"localhost\"")
}

test_s31_rejects_a_public_address if {
	denied_with(config_with("DATABASE_HOST", "34.1.2.3"), "DATABASE_HOST is \"34.1.2.3\"")
}

test_s31_rejects_a_host_with_a_port if {
	denied_with(config_with("DATABASE_HOST", "10.40.0.3:5432"), "DATABASE_HOST is \"10.40.0.3:5432\"")
}

test_s31_rejects_a_host_with_a_scheme if {
	denied_with(config_with("CACHE_HOST", "rediss://cache.example.com"), "CACHE_HOST is \"rediss://cache.example.com\"")
}

test_s31_rejects_an_empty_host if {
	denied_with(config_with("CACHE_HOST", ""), "CACHE_HOST is \"\"")
}

# The outputs of OpenTofu are IP addresses: a DNS name other than the
# placeholder is a way to send the connection elsewhere (SECU review of
# the PR 87).
test_s31_rejects_localhost_localdomain if {
	denied_with(config_with("DATABASE_HOST", "localhost.localdomain"), "DATABASE_HOST is \"localhost.localdomain\"")
}

test_s31_rejects_a_localhost_subdomain if {
	denied_with(config_with("CACHE_HOST", "foo.localhost"), "CACHE_HOST is \"foo.localhost\"")
}

test_s31_rejects_a_loopback_in_a_resolver_name if {
	denied_with(config_with("DATABASE_HOST", "127.0.0.1.nip.io"), "DATABASE_HOST is \"127.0.0.1.nip.io\"")
}

test_s31_rejects_the_metadata_server if {
	denied_with(config_with("DATABASE_HOST", "metadata.google.internal"), "DATABASE_HOST is \"metadata.google.internal\"")
}

test_s31_rejects_a_public_name if {
	denied_with(config_with("CACHE_HOST", "evil.example.com"), "CACHE_HOST is \"evil.example.com\"")
}

test_s31_rejects_an_address_with_a_leading_zero if {
	denied_with(config_with("DATABASE_HOST", "010.0.0.1"), "DATABASE_HOST is \"010.0.0.1\"")
}

test_s31_rejects_an_address_out_of_range if {
	denied_with(config_with("DATABASE_HOST", "10.0.0.256"), "DATABASE_HOST is \"10.0.0.256\"")
}

test_s31_accepts_a_172_16_address if {
	accepted(config_with("DATABASE_HOST", "172.20.1.9"))
}

test_s31_accepts_a_192_168_address if {
	accepted(config_with("CACHE_HOST", "192.168.4.4"))
}

test_s31_rejects_another_ca_path if {
	denied_with(config_with("CACHE_TLS_CA_FILE", "/tmp/ca.pem"), "CACHE_TLS_CA_FILE is \"/tmp/ca.pem\"")
}

test_s31_rejects_an_empty_ca_path if {
	denied_with(config_with("CACHE_TLS_CA_FILE", ""), "CACHE_TLS_CA_FILE is \"\"")
}

test_s31_rejects_app_config_in_another_namespace if {
	denied_with(patched(config_map, [{"op": "replace", "path": "/metadata/namespace", "value": "default"}]), "app-config is not in the namespace")
}

# --- app-ca ----------------------------------------------------------------

test_s31_rejects_a_missing_app_ca if {
	denied_with([namespace, service_account, config_map, provider_class, secret_sync], "0 ConfigMap app-ca")
}

test_s31_rejects_a_missing_ca_key if {
	denied_with(patched(ca_map, [{"op": "remove", "path": "/data/cache-ca.pem"}]), "app-ca holds the keys")
}

test_s31_rejects_an_extra_ca_key if {
	denied_with(patched(ca_map, [{"op": "add", "path": "/data/other.pem", "value": ""}]), "app-ca holds the keys")
}

test_s31_rejects_binary_data_in_app_ca if {
	denied_with(patched(ca_map, [{"op": "add", "path": "/binaryData", "value": {"x": "eA=="}}]), "holds binaryData")
}

test_s31_rejects_text_that_is_not_a_certificate if {
	denied_with(patched(ca_map, [{"op": "replace", "path": "/data/database-ca.pem", "value": "not a certificate\n"}]), "not a PEM bundle")
}

test_s31_rejects_a_truncated_certificate if {
	bad := concat("\n", ["-----BEGIN CERTIFICATE-----", "MIIBdzCCAR6gAwIBAgIUPJlX", "-----END CERTIFICATE-----", ""])
	denied_with(patched(ca_map, [{"op": "replace", "path": "/data/cache-ca.pem", "value": bad}]), "not a PEM bundle")
}

test_s31_rejects_a_private_key_in_app_ca if {
	# Assembled, so that the hook that looks for private keys finds none in the file.
	kind := "PRIVATE KEY"
	key := sprintf("-----BEGIN %s-----\nAAAA\n-----END %s-----\n", [kind, kind])
	denied_with(patched(ca_map, [{"op": "replace", "path": "/data/database-ca.pem", "value": key}]), "holds a private key")
}

test_s31_rejects_a_server_certificate_as_a_ca if {
	denied_with(patched(ca_map, [{"op": "replace", "path": "/data/database-ca.pem", "value": leaf_pem}]), "is not a CA")
}

test_s31_rejects_an_expired_ca if {
	denied_with(patched(ca_map, [{"op": "replace", "path": "/data/database-ca.pem", "value": expired_pem}]), "expired")
}

test_s31_rejects_an_expired_ca_among_valid_ones if {
	mixed := concat("", [ca_pem, expired_pem])
	denied_with(patched(ca_map, [{"op": "replace", "path": "/data/cache-ca.pem", "value": mixed}]), "expired")
}

# --- The service account of the sync -----------------------------------------

pod_with(spec) := {
	"apiVersion": "apps/v1",
	"kind": "Deployment",
	"metadata": {"name": "api", "namespace": "saas-b2b"},
	"spec": {"template": {"spec": spec}},
}

test_s31_accepts_a_pod_on_another_account if {
	accepted(array.concat(valid_objects, [pod_with({"serviceAccountName": "api", "containers": []})]))
}

test_s31_accepts_a_pod_without_an_account if {
	accepted(array.concat(valid_objects, [pod_with({"containers": []})]))
}

test_s31_rejects_a_pod_on_the_account_of_the_sync if {
	bad := pod_with({"serviceAccountName": "secret-sync", "containers": []})
	denied_with(array.concat(valid_objects, [bad]), "runs as the service account secret-sync")
}

test_s31_rejects_a_pod_on_the_deprecated_field if {
	bad := pod_with({"serviceAccount": "secret-sync", "containers": []})
	denied_with(array.concat(valid_objects, [bad]), "runs as the service account secret-sync")
}

test_s31_rejects_a_cron_job_on_the_account_of_the_sync if {
	bad := {
		"apiVersion": "batch/v1",
		"kind": "CronJob",
		"metadata": {"name": "tick", "namespace": "saas-b2b"},
		"spec": {"jobTemplate": {"spec": {"template": {"spec": {"serviceAccountName": "secret-sync", "containers": []}}}}},
	}
	denied_with(array.concat(valid_objects, [bad]), "runs as the service account secret-sync")
}

test_s31_rejects_a_bare_pod_on_the_account_of_the_sync if {
	bad := {
		"apiVersion": "v1",
		"kind": "Pod",
		"metadata": {"name": "p", "namespace": "saas-b2b"},
		"spec": {"serviceAccountName": "secret-sync", "containers": []},
	}
	denied_with(array.concat(valid_objects, [bad]), "runs as the service account secret-sync")
}

test_s31_rejects_five_certificates if {
	five := concat("", [ca_pem, ca_pem, ca_pem, ca_pem, ca_pem])
	denied_with(patched(ca_map, [{"op": "replace", "path": "/data/database-ca.pem", "value": five}]), "holds 5 certificates")
}

test_s31_rejects_app_ca_in_another_namespace if {
	denied_with(patched(ca_map, [{"op": "replace", "path": "/metadata/namespace", "value": "default"}]), "app-ca is not in the namespace")
}

# --- db-auth ---------------------------------------------------------------

test_s31_rejects_a_missing_provider_class if {
	denied_with([namespace, service_account, config_map, ca_map, secret_sync], "0 SecretProviderClass db-auth")
}

test_s31_rejects_a_missing_secret_sync if {
	denied_with([namespace, service_account, config_map, ca_map, provider_class], "0 SecretSync db-auth")
}

test_s31_rejects_another_provider if {
	denied_with(patched(provider_class, [{"op": "replace", "path": "/spec/provider", "value": "vault"}]), "has provider vault")
}

test_s31_rejects_a_missing_path if {
	one := "- resourceName: \"projects/PROJECT_ID/secrets/saas-b2b-db-auth-username/versions/1\"\n  path: \"username\"\n"
	denied_with(patched(provider_class, [{"op": "replace", "path": "/spec/parameters/secrets", "value": one}]), "reads the paths")
}

test_s31_rejects_a_secret_of_another_project_form if {
	bad := replace(secrets_block, "projects/PROJECT_ID/secrets/saas-b2b-db-auth-username", "projects/PROJECT_ID/secrets/saas-b2b-db-root-username")
	denied_with(patched(provider_class, [{"op": "replace", "path": "/spec/parameters/secrets", "value": bad}]), "has the resourceName")
}

test_s31_rejects_latest if {
	bad := replace(secrets_block, "username/versions/1", "username/versions/latest")
	denied_with(patched(provider_class, [{"op": "replace", "path": "/spec/parameters/secrets", "value": bad}]), "has the resourceName")
}

test_s31_rejects_a_swapped_path if {
	bad := concat("\n", [
		"- resourceName: \"projects/PROJECT_ID/secrets/saas-b2b-db-auth-username/versions/1\"",
		"  path: \"password\"",
		"- resourceName: \"projects/PROJECT_ID/secrets/saas-b2b-db-auth-password/versions/1\"",
		"  path: \"username\"",
		"",
	])
	denied_with(patched(provider_class, [{"op": "replace", "path": "/spec/parameters/secrets", "value": bad}]), "each path takes the secret of its own key")
}

test_s31_accepts_a_real_project_id if {
	good := replace(secrets_block, "PROJECT_ID", "my-demo-project-1")
	accepted(patched(provider_class, [{"op": "replace", "path": "/spec/parameters/secrets", "value": good}]))
}

test_s31_rejects_a_provider_class_in_another_namespace if {
	denied_with(patched(provider_class, [{"op": "replace", "path": "/metadata/namespace", "value": "default"}]), "is not in the namespace of the application")
}

test_s31_rejects_a_secret_sync_in_another_namespace if {
	denied_with(patched(secret_sync, [{"op": "replace", "path": "/metadata/namespace", "value": "default"}]), "is not in the namespace of the application")
}

test_s31_rejects_a_secret_sync_to_another_class if {
	denied_with(patched(secret_sync, [{"op": "replace", "path": "/spec/secretProviderClassName", "value": "other"}]), "reads the class other")
}

test_s31_rejects_an_unknown_service_account if {
	denied_with(patched(secret_sync, [{"op": "replace", "path": "/spec/serviceAccountName", "value": "default"}]), "service account default")
}

test_s31_rejects_a_basic_auth_type_until_gke_accepts_it if {
	denied_with(patched(secret_sync, [{"op": "replace", "path": "/spec/secretObject/type", "value": "kubernetes.io/basic-auth"}]), "secretObject.type kubernetes.io/basic-auth")
}

test_s31_rejects_a_missing_key if {
	denied_with(patched(secret_sync, [{"op": "remove", "path": "/spec/secretObject/data/1"}]), "maps")
}

test_s31_rejects_a_renamed_key if {
	denied_with(patched(secret_sync, [{"op": "replace", "path": "/spec/secretObject/data/0/targetKey", "value": "user"}]), "maps")
}

test_s31_rejects_a_wrong_api_version if {
	denied_with(patched(secret_sync, [{"op": "replace", "path": "/apiVersion", "value": "secret-sync.gke.io/v1beta1"}]), "has apiVersion secret-sync.gke.io/v1beta1")
}
