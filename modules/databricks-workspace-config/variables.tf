variable "compute_policies" {
  description = "Platform-owned cluster policies, keyed by policy name (lowercase kebab-case, for example `team-a-jobs`). `definition` is the policy rules (Databricks' policy definition language) as a JSON string, so policies may have differently shaped definitions: pass `jsonencode({...})`. The module adds a `fixed` rule for every entry of `fixed_tags` under `custom_tags.<key>`. Each definition must set `autotermination_minutes` and must not set `custom_tags.*` itself. The CLI passes only this project's policies."
  type = map(object({
    description = string
    definition  = string
  }))

  validation {
    condition     = alltrue([for name in keys(var.compute_policies) : can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", name))])
    error_message = "compute_policies keys (policy names) must be kebab-case: lowercase letters, digits and single hyphens, for example `team-a-jobs`; rename the offending keys in the compute_policies variable."
  }

  validation {
    condition     = alltrue([for p in values(var.compute_policies) : can(jsondecode(p.definition)) && can(keys(jsondecode(p.definition)))])
    error_message = "Every compute policy `definition` must be a JSON string that decodes to an object; pass `jsonencode({...})` for each definition in the compute_policies variable."
  }

  validation {
    condition     = alltrue([for p in values(var.compute_policies) : !can(jsondecode(p.definition)) || !can(keys(jsondecode(p.definition))) || !anytrue([for k in keys(jsondecode(p.definition)) : startswith(k, "custom_tags.")])])
    error_message = "A compute policy definition must not set `custom_tags.*` rules: the platform owns them and injects them from fixed_tags; remove those keys from the definitions in the compute_policies variable (add the tag to the fixed_tags variable instead)."
  }

  validation {
    condition     = alltrue([for p in values(var.compute_policies) : !can(jsondecode(p.definition)) || !can(keys(jsondecode(p.definition))) || contains(keys(jsondecode(p.definition)), "autotermination_minutes")])
    error_message = "Every compute policy definition must set `autotermination_minutes` (cost control), for example `jsonencode({ autotermination_minutes = { type = \"fixed\", value = 30 } })`; add it to each definition in the compute_policies variable."
  }
}

variable "fixed_tags" {
  description = "Tags pinned on every cluster created through a platform policy, as `custom_tags.<key>` rules of type `fixed` (for example `CostCenter`, `Project`). Must contain `Project`, `Environment`, `CostCenter`, `Workspace`, `Owner` and `ManagedBy` (the same governance tags as `databricks-workspace`'s `tags`), and no key Databricks reserves (`Vendor`, `Creator`, `ClusterName`, `ClusterId`, `Name`)."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["Project", "Environment", "CostCenter", "Workspace", "Owner", "ManagedBy"] : contains(keys(var.fixed_tags), k)])
    error_message = "fixed_tags must contain the keys Project, Environment, CostCenter, Workspace, Owner and ManagedBy; add the missing ones to the fixed_tags variable."
  }

  validation {
    condition     = length(setintersection(keys(var.fixed_tags), ["Vendor", "Creator", "ClusterName", "ClusterId", "Name"])) == 0
    error_message = "fixed_tags must not use a key Databricks reserves (Vendor, Creator, ClusterName, ClusterId, Name); remove it from the fixed_tags variable."
  }

  validation {
    condition     = alltrue([for k, v in var.fixed_tags : length(trimspace(k)) > 0 && length(trimspace(v)) > 0])
    error_message = "fixed_tags keys and values must not be empty; fix the fixed_tags variable."
  }
}

variable "users_group_name" {
  description = "Account group that may use the policies (`CAN_USE`) and has cluster creation switched off: the `users_group_name` output of `databricks-workspace` (`<project>-workspace-users`)."
  type        = string

  validation {
    condition     = length(trimspace(var.users_group_name)) > 0
    error_message = "users_group_name must not be empty; pass the users_group_name output of databricks-workspace."
  }
}

variable "restrict_builtin_users_group" {
  description = "Also switch off unrestricted cluster creation for the workspace's built-in `users` group. Databricks grants that entitlement to it by default and every user belongs to it, so leaving it on defeats the policies. Set to false only if the workspace's built-in group is managed elsewhere."
  type        = bool
  default     = true
}

variable "enable_system_schemas" {
  description = "Enable Unity Catalog system schemas (`system.<schema>` tables). Metastore-wide: set it in exactly one workspace, the governance workspace."
  type        = bool
  default     = false
}

variable "system_schemas" {
  description = "System schemas to enable when `enable_system_schemas` is true. See the Databricks system tables documentation for the names."
  type        = list(string)
  default     = ["access", "billing", "compute", "lakeflow", "query", "storage"]

  validation {
    condition     = alltrue([for s in var.system_schemas : can(regex("^[a-z][a-z0-9_]*$", s))])
    error_message = "system_schemas must be lowercase schema names such as `billing` or `access`; fix the system_schemas variable."
  }
}

variable "metastore_id" {
  description = "ID of the metastore the workspace is assigned to: the `metastore_id` of `databricks-metastore`. When system schemas are enabled, the plan fails if the workspace's current metastore is a different one."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.metastore_id))
    error_message = "metastore_id must be the metastore's UUID, for example 11111111-2222-3333-4444-555555555555; change the metastore_id variable."
  }
}

variable "max_token_lifetime_days" {
  description = "Maximum lifetime of personal access tokens, in days (workspace setting `maxTokenLifetimeDays`)."
  type        = number
  default     = 90

  validation {
    condition     = var.max_token_lifetime_days >= 1 && floor(var.max_token_lifetime_days) == var.max_token_lifetime_days
    error_message = "max_token_lifetime_days must be a positive whole number of days; change the max_token_lifetime_days variable."
  }
}
