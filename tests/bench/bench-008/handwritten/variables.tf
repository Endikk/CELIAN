# Same inputs for the three options of BENCH-008. No default on purpose:
# `tofu validate` needs no value, and no version or size is written from
# memory (principle VIII). The blueprint will fill them from the catalogue.

variable "project_id" {
  description = "Existing GCP project that receives the stack."
  type        = string
}

variable "region" {
  description = "GCP region of every regional resource."
  type        = string
}

variable "name" {
  description = "Short name of the generated project, used as a prefix."
  type        = string
}

variable "database_version" {
  description = "Cloud SQL engine version, for example a POSTGRES_* value."
  type        = string
}

variable "database_tier" {
  description = "Cloud SQL machine tier."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository allowed to impersonate the CI account, as owner/name."
  type        = string
}

variable "github_ref" {
  description = "Git ref allowed to impersonate the CI account, for example refs/heads/main."
  type        = string
}
