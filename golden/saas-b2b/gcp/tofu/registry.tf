# Artifact Registry, Docker format, immutable tags (ADR-008, scope): a pushed
# tag never points to another image. Who pushes, and from where, is left to
# Q8 (spec 001, plan).

resource "google_artifact_registry_repository" "images" {
  project       = var.project_id
  location      = var.region
  repository_id = var.name
  format        = "DOCKER"
  labels        = local.labels

  docker_config {
    immutable_tags = true
  }

  depends_on = [google_project_service.apis]
}
