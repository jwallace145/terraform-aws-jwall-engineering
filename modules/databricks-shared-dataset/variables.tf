variable "name_root" {
  description = "Prefix of resource names, in kebab-case. The role and storage credential are `<name_root>-<name>-databricks-share`, the external location `<name_root>-<name>`."
  type        = string
  default     = "jwall-engineering"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name_root))
    error_message = "name_root must be kebab-case, for example `jwall-engineering`; change the name_root variable."
  }
}

variable "name" {
  description = "The dataset's name in kebab-case, unique in the account, for example `rusty-chess-nnue` (the producing project and its dataset)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name))
    error_message = "name must be kebab-case, for example `rusty-chess-nnue`; change the name variable."
  }

  validation {
    condition     = length("${var.name_root}-${var.name}-databricks-share") <= 64
    error_message = "name is too long: `<name_root>-<name>-databricks-share` must be at most 64 characters (IAM role names), which with the default name_root means at most 29; shorten the name variable."
  }
}

variable "bucket" {
  description = "The dataset's S3 bucket, in this account and region, for example `jwall-engineering-rusty-chess-nnue`."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket))
    error_message = "bucket must be an S3 bucket name such as `jwall-engineering-rusty-chess-nnue`; change the bucket variable."
  }
}

variable "prefix" {
  description = "The prefix shared, one or more path segments ending in `/` with no leading `/`, for example `data/`. The dataset's readers grant must cover it."
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
  description = "Account group that owns the storage credential and external location, the `admin_group_name` output of `databricks-metastore`: no project owns a shared dataset's Databricks objects."
  type        = string

  validation {
    condition     = length(trimspace(var.owner_group_name)) > 0
    error_message = "owner_group_name must not be empty; pass the admin_group_name output of databricks-metastore."
  }
}

variable "consumers" {
  description = "Workspaces that may read the dataset, keyed by project: each workspace's `workspace_id` and `users_group_name` (outputs of `databricks-workspace`). The location is bound to each and its users group gets `READ_FILES`. Each consumer must also pass `endpoint_dataset` to its `databricks-workspace` (`read_only_datasets`). May be empty."
  type = map(object({
    workspace_id     = number
    users_group_name = string
  }))
  default = {}

  validation {
    condition     = alltrue([for k, c in var.consumers : can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", k)) && c.workspace_id > 0 && length(trimspace(c.users_group_name)) > 0])
    error_message = "every consumer must be keyed by its kebab-case project and have a positive workspace_id and a users_group_name; change the consumers variable."
  }

  validation {
    condition     = !contains(keys(var.consumers), "host")
    error_message = "`host` is reserved for the host workspace's own binding; key consumers by project."
  }
}

variable "component" {
  description = "Value of the `Component` tag on every AWS resource."
  type        = string
  default     = "databricks-shared-dataset"
}
