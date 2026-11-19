# BENCH-008, option terraform-google-modules: the same minimal GCP layer with
# the registry modules of the Cloud Foundation Toolkit. Artifact Registry and
# Secret Manager have no module in that organisation: the closest ones are
# published under GoogleCloudPlatform. Never planned nor applied (principle X).

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

module "apis" {
  source                      = "terraform-google-modules/project-factory/google//modules/project_services"
  version                     = "18.4.0"
  project_id                  = var.project_id
  activate_apis               = local.services
  disable_services_on_destroy = false
}

module "vpc" {
  source       = "terraform-google-modules/network/google"
  version      = "18.3.1"
  project_id   = var.project_id
  network_name = var.name
  subnets = [{
    subnet_name           = local.subnet
    subnet_ip             = "10.0.0.0/20"
    subnet_region         = var.region
    subnet_private_access = "true"
  }]
  secondary_ranges = {
    (local.subnet) = [
      { range_name = "pods", ip_cidr_range = "10.16.0.0/14" },
      { range_name = "services", ip_cidr_range = "10.20.0.0/20" },
    ]
  }
}

module "psa" {
  source      = "terraform-google-modules/sql-db/google//modules/private_service_access"
  version     = "28.3.1"
  project_id  = var.project_id
  vpc_network = module.vpc.network_name
}

module "gke" {
  source               = "terraform-google-modules/kubernetes-engine/google//modules/beta-autopilot-private-cluster"
  version              = "47.0.0"
  project_id           = var.project_id
  name                 = var.name
  region               = var.region
  network              = module.vpc.network_name
  subnetwork           = local.subnet
  ip_range_pods        = "pods"
  ip_range_services    = "services"
  ip_endpoints_enabled = false
}

module "db" {
  source                      = "terraform-google-modules/sql-db/google//modules/postgresql"
  version                     = "28.3.1"
  project_id                  = var.project_id
  name                        = var.name
  region                      = var.region
  database_version            = var.database_version
  tier                        = var.database_tier
  edition                     = "ENTERPRISE"
  db_name                     = "app"
  enable_default_user         = false
  deletion_protection_enabled = true
  ip_configuration = {
    ipv4_enabled    = false
    private_network = module.vpc.network_self_link
    ssl_mode        = "ENCRYPTED_ONLY"
  }
  backup_configuration = {
    enabled = true
  }
  depends_on = [module.psa]
}

module "cache" {
  source                  = "terraform-google-modules/memorystore/google"
  version                 = "16.4.1"
  project_id              = var.project_id
  name                    = "${var.name}-cache"
  region                  = var.region
  tier                    = "BASIC"
  memory_size_gb          = 1
  authorized_network      = module.vpc.network_id
  connect_mode            = "PRIVATE_SERVICE_ACCESS"
  auth_enabled            = true
  transit_encryption_mode = "SERVER_AUTHENTICATION"
  enable_apis             = false
  depends_on              = [module.psa]
}

module "registry" {
  source        = "GoogleCloudPlatform/artifact-registry/google"
  version       = "0.9.0"
  project_id    = var.project_id
  location      = var.region
  repository_id = var.name
  format        = "DOCKER"
  docker_config = { immutable_tags = true }
}

# create_version = false: the value never goes through OpenTofu.
module "secrets" {
  source     = "GoogleCloudPlatform/secret-manager/google"
  version    = "0.10.0"
  project_id = var.project_id
  secrets = [{
    name           = "${var.name}-db-password"
    create_version = false
  }]
}

module "ci_sa" {
  source          = "terraform-google-modules/service-accounts/google"
  version         = "5.1.0"
  project_id      = var.project_id
  names           = ["${var.name}-ci"]
  display_name    = "CI, plan only"
  project_roles   = ["${var.project_id}=>roles/viewer"]
  grant_xpn_roles = false
}

module "ci_wif" {
  source      = "terraform-google-modules/github-actions-runners/google//modules/gh-oidc"
  version     = "6.0.0"
  project_id  = var.project_id
  pool_id     = "${var.name}-ci"
  provider_id = "github"
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }
  attribute_condition = "assertion.repository == '${var.github_repository}' && assertion.ref == '${var.github_ref}'"
  sa_mapping = {
    ci = {
      sa_name   = module.ci_sa.service_account.name
      attribute = "attribute.repository/${var.github_repository}"
    }
  }
}
