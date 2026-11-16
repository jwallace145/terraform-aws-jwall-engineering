variable "name" {
  description = "Name of the bucket, the Unity Catalog IAM role, the storage credential and the external location, in kebab-case, for example `jwall-engineering-dataset-catalogs`."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name)) && length(var.name) >= 3 && length(var.name) <= 63
    error_message = "name must be 3 to 63 characters of kebab-case, for example `jwall-engineering-dataset-catalogs`; change the name variable."
  }
}

variable "host_workspace_id" {
  description = "Numeric ID of the shared-objects host, the `workspace_id` output of `databricks-host-workspace`: the workspace this module's `databricks` provider points at, and the only one the credential and location are bound to."
  type        = number

  validation {
    condition     = var.host_workspace_id > 0 && floor(var.host_workspace_id) == var.host_workspace_id
    error_message = "host_workspace_id must be the host's positive numeric workspace ID; change the host_workspace_id variable."
  }
}

variable "owner_group_name" {
  description = "Account group that owns the credential and location and holds `ALL_PRIVILEGES` on the location: the `admin_group_name` output of `databricks-metastore`."
  type        = string

  validation {
    condition     = length(trimspace(var.owner_group_name)) > 0
    error_message = "owner_group_name must not be empty; pass the admin_group_name output of databricks-metastore."
  }
}

variable "apply_role_arn" {
  description = "ARN of the CI apply role. The bucket policy lets it list and delete objects (so a destroy can empty the bucket) and denies it reading or writing them."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.apply_role_arn))
    error_message = "apply_role_arn must be an IAM role ARN such as arn:aws:iam::111122223333:role/ci-apply; change the apply_role_arn variable."
  }
}

variable "tags" {
  description = "Tags for the bucket and the role, on top of the provider's default tags."
  type        = map(string)
  default     = {}
}

variable "component" {
  description = "The `Component` tag of the bucket and the role."
  type        = string
  default     = "dataset-catalogs"
}
