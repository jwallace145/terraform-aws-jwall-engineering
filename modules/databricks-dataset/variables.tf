variable "name" {
  description = "The dataset's platform name, in kebab-case: the IAM role, the storage credential and the external location all take it, for example `jwall-engineering-ds-braveheart-selfplay-positions` (`<organization>-ds-<owner>-<dataset>`)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name))
    error_message = "name must be kebab-case, for example `jwall-engineering-ds-braveheart-selfplay-positions`; change the name variable."
  }

  validation {
    condition     = length(var.name) <= 64
    error_message = "name must be at most 64 characters, IAM's limit for role names; shorten the name variable."
  }
}

variable "bucket" {
  description = "The dataset's S3 bucket, in this account and region, for example `jwall-engineering-braveheart-selfplay-positions`."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket))
    error_message = "bucket must be an S3 bucket name such as `jwall-engineering-braveheart-selfplay-positions`; change the bucket variable."
  }
}

variable "prefix" {
  description = "The prefix onboarded, one or more path segments ending in `/` with no leading `/`, for example `data/`. The dataset's bucket-policy readers grant must cover it."
  type        = string

  validation {
    condition     = can(regex("^([A-Za-z0-9!_.'()-]+/)+$", var.prefix))
    error_message = "prefix must be one or more path segments ending in `/` with no leading `/` and no `*`, for example `data/`; change the prefix variable."
  }
}

variable "host_workspace_id" {
  description = "Numeric ID of the shared-objects host, the `workspace_id` output of `databricks-host-workspace`: the workspace this module's `databricks` provider points at."
  type        = number

  validation {
    condition     = var.host_workspace_id > 0 && floor(var.host_workspace_id) == var.host_workspace_id
    error_message = "host_workspace_id must be the host's positive numeric workspace ID; change the host_workspace_id variable."
  }
}

variable "owner_group_name" {
  description = "Account group that owns the storage credential and external location, the `admin_group_name` output of `databricks-metastore`: no project owns an onboarded dataset's Databricks objects."
  type        = string

  validation {
    condition     = length(trimspace(var.owner_group_name)) > 0
    error_message = "owner_group_name must not be empty; pass the admin_group_name output of databricks-metastore."
  }
}

variable "component" {
  description = "Value of the `Component` tag on every AWS resource."
  type        = string
  default     = "databricks-dataset"
}
