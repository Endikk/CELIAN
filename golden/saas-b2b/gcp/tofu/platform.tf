# Values shared with the local layer, read from the single file that holds
# them (spec 001, data-model, "Valeurs partagées"). Test S21 keeps this layer
# on them: the Kubernetes minor of the cluster (ADR-004, version rule) and the
# Postgres major of Cloud SQL (ADR-012, condition 5).

locals {
  platform = yamldecode(file("${path.module}/../../platform.yaml"))

  # Labels of the resources that take them, with the three of R-05 (owner,
  # env, ttl). S15 refuses a root where one is missing.
  labels = merge(
    {
      app        = var.name
      managed-by = "opentofu"
    },
    {
      owner = var.owner
      env   = var.env
      ttl   = var.ttl
    },
  )
}
