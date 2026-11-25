# APIs of the services that this root creates, enabled on an existing project
# (ADR-008, scope). Kept at destroy: other resources of the project may use
# them. Service names: research RS-16.

locals {
  services = [
    "artifactregistry.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "gkeconnect.googleapis.com",
    "gkehub.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "secretmanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
    "sts.googleapis.com",
    # pending (2026-11-25): the API of the configmanagement fleet feature.
    # No page read names it; the first apply agreed by Lucas tells whether
    # the fleet feature enables it alone (research RS-16).
  ]
}

resource "google_project_service" "apis" {
  for_each           = toset(local.services)
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
