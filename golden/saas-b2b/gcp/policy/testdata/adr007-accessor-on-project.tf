# Failing case of S15: Secret Manager readable by the whole project.
# package: tofu_secret_sync
# expect: ADR-007, condition 2): gcp/policy/testdata/adr007-accessor-on-project.tf: google_project_iam_member.app_reads_secrets: roles/secretmanager.secretAccessor granted at the project level

resource "google_project_iam_member" "app_reads_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "principal://iam.googleapis.com/projects/1/locations/global/workloadIdentityPools/p.svc.id.goog/subject/ns/app/sa/api"
}
