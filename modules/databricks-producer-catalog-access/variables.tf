variable "catalog_name" {
  description = "The producer's catalog, the `catalog_name` output of `databricks-producer-catalog`, for example `braveheart_selfplay`."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9_]+$", var.catalog_name))
    error_message = "catalog_name must be lowercase letters, digits and underscores, the catalog_name output of databricks-producer-catalog; change the catalog_name variable."
  }
}

variable "owner_group_name" {
  description = "The group that owns the catalog, the `admin_group_name` output of `databricks-metastore`. It is always in the catalog's grant set, so the set is never empty (an empty set would leave the catalog's grants unmanaged)."
  type        = string

  validation {
    condition     = length(trimspace(var.owner_group_name)) > 0
    error_message = "owner_group_name must not be empty; pass the admin_group_name output of databricks-metastore."
  }
}

variable "consumers" {
  description = "Workspaces with at least one agreed edge into this producer's datasets, keyed by project: each workspace's `workspace_id` and `users_group_name` (outputs of `databricks-workspace`). The catalog is bound read-only to each, and each users group gets `USE_CATALOG`. May be empty."
  type = map(object({
    workspace_id     = number
    users_group_name = string
  }))
  default = {}

  validation {
    condition     = alltrue([for k, c in var.consumers : can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", k)) && c.workspace_id > 0 && length(trimspace(c.users_group_name)) > 0])
    error_message = "every consumer must be keyed by its kebab-case project and have a positive workspace_id and a users_group_name; change the consumers variable."
  }
}
