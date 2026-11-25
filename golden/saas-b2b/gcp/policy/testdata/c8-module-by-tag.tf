# Failing case of S15: a third-party module pulled by tag (spec 001, story 3,
# scenario 2).
# package: tofu_adr008
# expect: ADR-008, condition 8): gcp/policy/testdata/c8-module-by-tag.tf: module.network comes from

module "network" {
  source = "git::https://github.com/GoogleCloudPlatform/cloud-foundation-fabric.git//modules/net-vpc?ref=v60.0.0"
}
