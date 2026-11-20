# BENCH-008, option Cloud Foundation Fabric v60.0.0: the same minimal GCP
# layer with Fabric modules, sourced from GitHub with a tag as the Fabric
# modules README recommends. Fabric has no Memorystore module: the cache is
# a plain provider resource. Never planned nor applied (principle X).

# A module source must be a literal: the tag is repeated in each block.
locals {
  subnet = "${var.name}-${var.region}"
  services = [
    "artifactregistry.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "redis.googleapis.com",
    "secretmanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
    "sts.googleapis.com",
  ]
}

# Existing project: APIs and the CI workload identity pool (R-19).
module "project" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/project?ref=v60.0.0&depth=1"
  name          = var.project_id
  project_reuse = {}
  services      = local.services
  workload_identity_pools = {
    ci = {
      providers = {
        github = {
          attribute_condition = "assertion.repository == '${var.github_repository}' && assertion.ref == '${var.github_ref}'"
          identity_provider = {
            oidc = {
              template = "github"
            }
          }
        }
      }
    }
  }
}

module "vpc" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-vpc?ref=v60.0.0&depth=1"
  project_id = var.project_id
  name       = var.name
  subnets = [{
    name          = local.subnet
    region        = var.region
    ip_cidr_range = "10.0.0.0/20"
    secondary_ip_ranges = {
      pods     = { ip_cidr_range = "10.16.0.0/14" }
      services = { ip_cidr_range = "10.20.0.0/20" }
    }
  }]
  psa_configs = [{
    ranges = { psa = "10.60.0.0/16" }
  }]
}

module "gke" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gke-cluster-autopilot?ref=v60.0.0&depth=1"
  project_id = var.project_id
  name       = var.name
  location   = var.region
  vpc_config = {
    network    = module.vpc.self_link
    subnetwork = module.vpc.subnet_self_links["${var.region}/${local.subnet}"]
    secondary_range_names = {
      pods     = "pods"
      services = "services"
    }
  }
}

module "db" {
  source           = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/cloudsql-instance?ref=v60.0.0&depth=1"
  project_id       = var.project_id
  name             = var.name
  region           = var.region
  database_version = var.database_version
  tier             = var.database_tier
  databases        = ["app"]
  network_config = {
    connectivity = {
      psa_config = {
        private_network = module.vpc.self_link
      }
    }
  }
  ssl = {
    mode = "ENCRYPTED_ONLY"
  }
  backup_configuration = {
    enabled = true
  }
  depends_on = [module.vpc]
}

# No Fabric module for Memorystore at v60.0.0: plain resource.
resource "google_redis_instance" "cache" {
  project                 = var.project_id
  name                    = "${var.name}-cache"
  region                  = var.region
  tier                    = "BASIC"
  memory_size_gb          = 1
  authorized_network      = module.vpc.self_link
  connect_mode            = "PRIVATE_SERVICE_ACCESS"
  auth_enabled            = true
  transit_encryption_mode = "SERVER_AUTHENTICATION"
  depends_on              = [module.vpc]
}

module "registry" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/artifact-registry?ref=v60.0.0&depth=1"
  project_id = var.project_id
  location   = var.region
  name       = var.name
  format     = { docker = { standard = { immutable_tags = true } } }
}

module "secrets" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/secret-manager?ref=v60.0.0&depth=1"
  project_id = var.project_id
  secrets = {
    "${var.name}-db-password" = {}
  }
}

module "ci_sa" {
  source       = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/iam-service-account?ref=v60.0.0&depth=1"
  project_id   = var.project_id
  name         = "${var.name}-ci"
  display_name = "CI, plan only"
  iam = {
    "roles/iam.workloadIdentityUser" = [
      "principalSet://iam.googleapis.com/${module.project.workload_identity_pool_ids["ci"]}/attribute.repository/${var.github_repository}",
    ]
  }
  iam_project_roles = {
    (var.project_id) = ["roles/viewer"]
  }
}
