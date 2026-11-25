# Failing case of S15: a federation that trusts a repository by its name.
# package: tofu_adr008
# expect: ADR-008, condition 1): gcp/policy/testdata/c1-federation-by-name.tf: google_iam_workload_identity_pool_provider.github: attribute_condition filters on a name

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = "ci"
  workload_identity_pool_provider_id = "github"
  attribute_condition                = "assertion.repository == 'org/repo' && assertion.ref == 'refs/heads/main'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com/"
  }
}
