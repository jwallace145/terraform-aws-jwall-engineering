variable "external_location_name" {
  description = "Name of the onboarded dataset's external location, the `external_location_name` output of `databricks-dataset`."
  type        = string

  validation {
    condition     = length(trimspace(var.external_location_name)) > 0
    error_message = "external_location_name must not be empty; pass the external_location_name output of databricks-dataset."
  }
}

variable "consumers" {
  description = "Workspaces that may read the dataset, keyed by project: each workspace's `workspace_id` and `users_group_name` (outputs of `databricks-workspace`). The location is bound to each, and each users group gets `READ_FILES`. Every edge here is a handshake both the producer and the consumer declared. May be empty."
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
