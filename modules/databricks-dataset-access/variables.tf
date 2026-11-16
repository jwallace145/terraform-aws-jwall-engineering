variable "external_location_name" {
  description = "Name of the onboarded dataset's external location, the `external_location_name` output of `databricks-dataset`."
  type        = string

  validation {
    condition     = length(trimspace(var.external_location_name)) > 0
    error_message = "external_location_name must not be empty; pass the external_location_name output of databricks-dataset."
  }
}

variable "consumers" {
  description = "Workspaces that may read the dataset, keyed by project: each workspace's `workspace_id` and `users_group_name` (outputs of `databricks-workspace`). The location and credential are bound to each, and each users group gets `USE_SCHEMA` and `READ_VOLUME`. Every edge here is a handshake both the producer and the consumer declared. May be empty."
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

variable "storage_credential_name" {
  description = "Name of the dataset's storage credential, the `storage_credential_name` output of `databricks-dataset`. Each consumer workspace is bound to it so that Unity Catalog can use it there; a binding grants nothing."
  type        = string

  validation {
    condition     = length(trimspace(var.storage_credential_name)) > 0
    error_message = "storage_credential_name must not be empty; pass the storage_credential_name output of databricks-dataset."
  }
}

variable "owner_group_name" {
  description = "The group that owns the dataset's objects, the `admin_group_name` output of `databricks-metastore`. It alone holds READ FILES on the location, and it is in every grant set, so none is ever empty (an empty set would leave the securable unmanaged)."
  type        = string

  validation {
    condition     = length(trimspace(var.owner_group_name)) > 0
    error_message = "owner_group_name must not be empty; pass the admin_group_name output of databricks-metastore."
  }
}

variable "schema_full_name" {
  description = "`<catalog>.<schema>`, the dataset's schema (the `schema_full_name` output of `databricks-dataset`). With it, each consumer's users group gets USE SCHEMA. Set exactly when `volume_full_name` is; null for a dataset onboarded as a location only."
  type        = string
  default     = null

  validation {
    condition     = var.schema_full_name == null || can(regex("^[a-z0-9_]+\\.[a-z0-9_]+$", var.schema_full_name))
    error_message = "schema_full_name must be <catalog>.<schema> in lowercase letters, digits and underscores; change the schema_full_name variable."
  }
}

variable "volume_full_name" {
  description = "`<catalog>.<schema>.files`, the dataset's external volume (the `volume_full_name` output of `databricks-dataset`). With it, each consumer's users group gets READ VOLUME. Set exactly when `schema_full_name` is."
  type        = string
  default     = null

  validation {
    condition     = (var.volume_full_name == null) == (var.schema_full_name == null) && (var.volume_full_name == null || can(regex("^[a-z0-9_]+\\.[a-z0-9_]+\\.[a-z0-9_]+$", var.volume_full_name)))
    error_message = "volume_full_name must be <catalog>.<schema>.<volume>, set exactly when schema_full_name is; change the volume_full_name variable."
  }
}

