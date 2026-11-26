# What the user copies into the manifests of gcp/k8s/values/ after the first
# apply (research RS-16, "Hôte et CA des services managés"): the host and the
# CA of the database. Config Sync reads a manifest from Git, and neither exists
# before the apply. Neither is a secret, an address of the private network and
# a public certificate; no output carries a password or a token (S15).
#
# The user reads them with their own credentials, which the state needs to be
# decrypted (ADR-008, condition 2), and writes them into the manifests in a
# pull request that [SECU] and the owner of the project review.
#
# The cache joins with the second pull request of step 20 (tasks.md, gap 87
# of main), by the same road.

output "database_private_ip" {
  description = "Private IP address of the Cloud SQL instance: DATABASE_HOST of gcp/k8s/values/app-config.yaml."
  value       = google_sql_database_instance.main.private_ip_address
}

# The provider marks server_ca_cert sensitive (schema at v8.12.0), and a plan
# refuses an output that reads it without the flag. The certificate is public:
# `tofu output -raw database_server_ca_cert` prints it.
output "database_server_ca_cert" {
  description = "PEM of the CA of the Cloud SQL instance: database-ca.pem of gcp/k8s/values/app-ca.yaml."
  value       = google_sql_database_instance.main.server_ca_cert[0].cert
  sensitive   = true
}
