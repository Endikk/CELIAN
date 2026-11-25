# Inputs of the gcp layer. No default for what depends on the project, the
# budget or the repository of the user: `tofu validate` needs no value, and no
# size is chosen here before [FINOPS] validates a budget (R-05). The values
# shared with the local layer come from platform.yaml (platform.tf).

variable "project_id" {
  description = "Existing GCP project that receives the stack. This root creates no project."
  type        = string
}

variable "region" {
  description = "GCP region of every regional resource: cluster, database, registry, secrets."
  type        = string
}

variable "name" {
  description = "Short name of the project, prefix of every resource name."
  type        = string

  # The longest derived name, "<name>-nodes", must fit the 30 characters of a
  # service account id, which starts with a letter.
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,18}[a-z0-9]$", var.name))
    error_message = "name: 4 to 20 characters, lower-case letters, digits and hyphens, starting with a letter."
  }
}

variable "state_encryption_key" {
  description = "Cloud KMS key that encrypts the state and the plans (ADR-008, condition 2), as projects/<project>/locations/<location>/keyRings/<ring>/cryptoKeys/<key>. It exists before the first init."
  type        = string

  validation {
    condition     = can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.state_encryption_key))
    error_message = "state_encryption_key: projects/<project>/locations/<location>/keyRings/<ring>/cryptoKeys/<key>."
  }
}

variable "database_tier" {
  description = "Machine tier of the Cloud SQL instance, chosen with [FINOPS] (R-05): db-f1-micro, db-g1-small or db-custom-<vcpu>-<memory in MB> with 1 or 2 vCPU. A larger tier goes through a reviewed PR."
  type        = string

  # Demo profile (R-05, R-17): 2 vCPU at most, in the ENTERPRISE edition of
  # database.tf, which accepts shared-core and custom tiers. No backslash in
  # the pattern: S15 reads it and tries tiers against it.
  validation {
    condition     = can(regex("^(db-f1-micro|db-g1-small|db-custom-[12]-[0-9]+)$", var.database_tier))
    error_message = "database_tier: db-f1-micro, db-g1-small or db-custom-<vcpu>-<memory in MB> with 1 or 2 vCPU (demo profile, R-17)."
  }
}

variable "database_disk_autoresize_limit_gb" {
  description = "Upper limit, in GB, of the automatic growth of the Cloud SQL disk (R-17). Without a limit the disk grows, and bills, with no bound."
  type        = number

  # Provider: 0 means no limit, which R-17 refuses. Cloud SQL: at least 10 GB
  # (docs.cloud.google.com/sql/docs/postgres/instance-settings, read on 2026-11-25).
  validation {
    condition     = var.database_disk_autoresize_limit_gb == floor(var.database_disk_autoresize_limit_gb) && var.database_disk_autoresize_limit_gb >= 10
    error_message = "database_disk_autoresize_limit_gb: a whole number of GB, 10 at least. 0 would mean no limit."
  }
}

variable "database_retained_backups" {
  description = "Number of automated Cloud SQL backups kept, oldest deleted first. Each one is billed as storage (R-05)."
  type        = number

  # Cloud SQL: "any value in the range of 1 to 365" (same page, read on 2026-11-25).
  validation {
    condition     = var.database_retained_backups == floor(var.database_retained_backups) && var.database_retained_backups >= 1 && var.database_retained_backups <= 365
    error_message = "database_retained_backups: a whole number from 1 to 365."
  }
}

# Labels of R-05: they tell whose a resource is, which environment it serves
# and when it may be removed, so that a forgotten demo shows up in the bill.
# GCP label values: lower-case letters, digits, hyphens and underscores, 63
# characters at most. A date such as 2026-12-31 fits. No backslash in the
# patterns: S15 reads them and tries values against them.

variable "owner" {
  description = "Who owns the resources, as a label value (R-05)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9_-]{1,63}$", var.owner))
    error_message = "owner: 1 to 63 characters, lower-case letters, digits, hyphens and underscores."
  }
}

variable "env" {
  description = "Environment that the stack serves, as a label value, for example demo (R-05)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9_-]{1,63}$", var.env))
    error_message = "env: 1 to 63 characters, lower-case letters, digits, hyphens and underscores."
  }
}

variable "ttl" {
  description = "Date after which the stack should be torn down, as a label value such as 2026-12-31 (R-05)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9_-]{1,63}$", var.ttl))
    error_message = "ttl: 1 to 63 characters, lower-case letters, digits, hyphens and underscores, for example 2026-12-31."
  }
}

# ADR-008, condition 1: the CI is identified by the numeric ids that GitHub
# writes in its tokens, never by a name that a third party could take over
# after a rename. Each value is interpolated in a CEL condition: the
# validation blocks keep a quote from rewriting that expression.

variable "github_repository_id" {
  description = "Numeric id of the GitHub repository whose CI may impersonate the CI account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "github_repository_id: digits only, the id that GitHub gives the repository."
  }
}

variable "github_repository_owner_id" {
  description = "Numeric id of the GitHub account or organization that owns the repository."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_owner_id))
    error_message = "github_repository_owner_id: digits only, the id that GitHub gives the owner."
  }
}

variable "github_ref" {
  description = "Git ref allowed to impersonate the CI account, for example refs/heads/main."
  type        = string

  validation {
    condition     = can(regex("^refs/(heads|tags)/[A-Za-z0-9._/-]+$", var.github_ref))
    error_message = "github_ref: refs/heads/<branch> or refs/tags/<tag>, without quotes or spaces."
  }
}

# ADR-007, condition 2: each secret is readable by the Kubernetes service
# account of the application only. Its namespace and name come with the
# manifests of steps 9 and 14 (spec 001).

variable "app_namespace" {
  description = "Kubernetes namespace of the application on the cluster."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", var.app_namespace))
    error_message = "app_namespace: 63 characters at most, lower-case letters, digits and hyphens, starting with a letter."
  }
}

variable "app_service_account" {
  description = "Kubernetes service account of the application, the only reader of its secrets."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", var.app_service_account))
    error_message = "app_service_account: 253 characters at most, lower-case letters, digits, hyphens and dots, starting and ending with a letter or a digit."
  }
}
