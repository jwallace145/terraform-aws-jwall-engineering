variable "name_root" {
  description = "Prefix of AWS resource names, in kebab-case; must equal `databricks-workspace`'s. With `<p>` = `<name_root>-<project>`, the bucket is `<p>-databricks-catalog` and the Unity Catalog role `<p>-databricks-uc`, the names the workspace's S3 endpoint policy admits."
  type        = string
  default     = "jwall-engineering"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name_root))
    error_message = "name_root must be kebab-case: lowercase letters, digits and single hyphens, for example `jwall-engineering`; change the name_root variable."
  }
}

variable "project" {
  description = "Project in kebab-case, for example `databricks-poc`; must equal `databricks-workspace`'s. The catalog is the project in snake_case (`databricks_poc`)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.project))
    error_message = "project must be kebab-case: lowercase letters, digits and single hyphens, for example `databricks-poc`; change the project variable."
  }

  # S3 bucket names are at most 63 characters, IAM role names 64.
  validation {
    condition     = length("${var.name_root}-${var.project}-databricks-catalog") <= 63
    error_message = "project is too long: `<name_root>-<project>-databricks-catalog` must be at most 63 characters (S3 bucket names), which with the default name_root means at most 24; shorten the project variable."
  }
}

variable "workspace_id" {
  description = "Numeric ID of the workspace the catalog, external location and storage credential are bound to: the `workspace_id` output of `databricks-workspace`, the workspace this stack's `databricks` provider points at."
  type        = number

  validation {
    condition     = var.workspace_id > 0 && floor(var.workspace_id) == var.workspace_id
    error_message = "workspace_id must be the workspace's positive numeric ID, for example 1234567890123456 (the workspace_id output of databricks-workspace); change the workspace_id variable."
  }
}

variable "admin_group_name" {
  description = "Account group that owns the catalog and gets `ALL_PRIVILEGES` on it and on the external location: the `admin_group_name` output of `databricks-workspace` (`<project>-workspace-admins`)."
  type        = string

  validation {
    condition     = length(trimspace(var.admin_group_name)) > 0
    error_message = "admin_group_name must not be empty; pass the admin_group_name output of databricks-workspace."
  }
}

variable "users_group_name" {
  description = "Account group that may use the catalog, create schemas and tables in it, and read and modify data, but not manage it: the `users_group_name` output of `databricks-workspace` (`<project>-workspace-users`)."
  type        = string

  validation {
    condition     = length(trimspace(var.users_group_name)) > 0
    error_message = "users_group_name must not be empty; pass the users_group_name output of databricks-workspace."
  }
}

variable "apply_role_arn" {
  description = "ARN of the CI apply role. The bucket policy lets it list and delete objects (so `destroy` can empty the bucket) and denies it reading or writing them."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.apply_role_arn))
    error_message = "apply_role_arn must be an IAM role ARN such as arn:aws:iam::111122223333:role/ci-apply; change the apply_role_arn variable."
  }
}

variable "management_role_arns" {
  description = "ARNs of the other roles that manage the account (CI plan, admin). They keep their IAM rights to the bucket's configuration, but the bucket policy denies them every object read, write and delete; none may be the Unity Catalog role."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.management_role_arns : can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", a))])
    error_message = "every entry of management_role_arns must be an IAM role ARN such as arn:aws:iam::111122223333:role/ci-plan; change the management_role_arns variable."
  }
}

variable "tags" {
  description = "Properties of the catalog (`databricks_catalog.properties`), for example the governance tags. Must contain `Project` and `Owner`."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["Project", "Owner"] : contains(keys(var.tags), k)])
    error_message = "tags must contain the keys Project and Owner; add the missing ones to the tags variable."
  }
}

variable "component" {
  description = "Value of the `Component` tag on every AWS resource."
  type        = string
  default     = "databricks-catalog"
}
