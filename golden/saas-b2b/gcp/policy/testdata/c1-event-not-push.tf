# Failing case of S15: a federation that accepts a manual run of the workflow.
# package: tofu_adr008
# expect: ADR-008, condition 1): gcp/policy/testdata/c1-event-not-push.tf: google_iam_workload_identity_pool_provider.github: assertion.event_name must be 'push'

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = "ci"
  workload_identity_pool_provider_id = "github"
  attribute_condition                = "assertion.repository_id == '1' && assertion.repository_owner_id == '2' && assertion.ref == 'refs/heads/main' && assertion.event_name == 'workflow_dispatch'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com/"
  }
}
