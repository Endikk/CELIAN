# Failing case of S15: Config Sync left to its automatic upgrades.
# package: tofu_config_sync
# expect: google_gke_hub_feature_membership.configmanagement: configmanagement.management is 'MANAGEMENT_AUTOMATIC'

resource "google_gke_hub_feature_membership" "configmanagement" {
  location   = "global"
  feature    = "configmanagement"
  membership = "main"

  configmanagement {
    version    = "1.25.2"
    management = "MANAGEMENT_AUTOMATIC"

    config_sync {
      enabled = true
    }
  }
}
