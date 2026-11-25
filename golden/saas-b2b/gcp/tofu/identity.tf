# Identity of the CI by Workload Identity Federation, without any service
# account key (ADR-008, condition 1; R-19). GitHub writes the numeric ids of
# the repository and of its owner in its tokens; Google recommends them over
# the names, which a third party can take over after a rename.
# Attributes: research RS-16.

resource "google_iam_workload_identity_pool" "ci" {
  project                   = var.project_id
  workload_identity_pool_id = "${var.name}-ci"

  depends_on = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.ci.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"

  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.repository_id"       = "assertion.repository_id"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    "attribute.ref"                 = "assertion.ref"
    "attribute.event_name"          = "assertion.event_name"
  }

  # event_name is a claim of the GitHub token, "the event that triggered the
  # workflow run" (GitHub OIDC page, read on 2026-11-25): only a push gets the
  # token, not pull_request_target, workflow_run, schedule nor
  # workflow_dispatch. Each interpolated variable has a validation block
  # (variables.tf), so that a quote cannot rewrite this CEL expression.
  attribute_condition = "assertion.repository_id == '${var.github_repository_id}' && assertion.repository_owner_id == '${var.github_repository_owner_id}' && assertion.ref == '${var.github_ref}' && assertion.event_name == 'push'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com/"
  }
}

resource "google_service_account" "ci" {
  project      = var.project_id
  account_id   = "${var.name}-ci"
  display_name = "CI of ${var.name}, federated, without key"

  depends_on = [google_project_service.apis]
}

# Only the repository, by its numeric id, may impersonate the CI account.
resource "google_service_account_iam_member" "ci_federation" {
  service_account_id = google_service_account.ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.ci.name}/attribute.repository_id/${var.github_repository_id}"
}

# pending (2026-11-25): the roles of the CI account. ADR-008, question 3,
# replaces roles/viewer by read roles per service, still to define, and Q8
# (spec 001) decides whether the CI pushes to Artifact Registry. No role
# until then: the CI of the project runs no plan (principle X).
