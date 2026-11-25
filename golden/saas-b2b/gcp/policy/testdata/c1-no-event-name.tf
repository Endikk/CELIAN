# Failing case of S15: a federation that lets any event of the repository get the token.
# package: tofu_adr008
# expect: ADR-008, condition 1): gcp/policy/testdata/c1-no-event-name.tf: google_iam_workload_identity_pool_provider.github: attribute_condition does not check assertion.event_name

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = "ci"
  workload_identity_pool_provider_id = "github"
  attribute_condition                = "assertion.repository_id == '1' && assertion.repository_owner_id == '2' && assertion.ref == 'refs/heads/main'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com/"
  }
}
