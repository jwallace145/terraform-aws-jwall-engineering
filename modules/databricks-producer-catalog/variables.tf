variable "producer" {
  description = "The producing project, in kebab-case, for example `braveheart-selfplay`. The catalog is named after it, `-` replaced by `_` (`braveheart_selfplay`)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.producer))
    error_message = "producer must be a kebab-case project name such as `braveheart-selfplay`; change the producer variable."
  }
}

variable "storage_url" {
  description = "The `url` output of `databricks-catalog-storage`, `s3://<bucket>/managed`: the catalog's managed location is `<storage_url>/<catalog>`."
  type        = string

  validation {
    condition     = can(regex("^s3://[a-z0-9][a-z0-9.-]{1,61}[a-z0-9](/[A-Za-z0-9!_.'()-]+)*$", var.storage_url))
    error_message = "storage_url must be an s3:// URL with no trailing slash, the url output of databricks-catalog-storage; change the storage_url variable."
  }
}

variable "host_workspace_id" {
  description = "Numeric ID of the shared-objects host (`databricks-host-workspace`'s `workspace_id`): the workspace this module's `databricks` provider points at, and the only one bound read-write."
  type        = number

  validation {
    condition     = var.host_workspace_id > 0 && floor(var.host_workspace_id) == var.host_workspace_id
    error_message = "host_workspace_id must be the host's positive numeric workspace ID; change the host_workspace_id variable."
  }
}

variable "owner_group_name" {
  description = "Account group that owns the catalog: the `admin_group_name` output of `databricks-metastore`. Never a producer or consumer group: a catalog's owner can grant anyone access."
  type        = string

  validation {
    condition     = length(trimspace(var.owner_group_name)) > 0
    error_message = "owner_group_name must not be empty; pass the admin_group_name output of databricks-metastore."
  }
}

variable "properties" {
  description = "Extra catalog properties; `producer` is always set to `producer`."
  type        = map(string)
  default     = {}
}
