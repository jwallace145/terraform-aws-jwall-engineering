variable "account_id" {
  description = "Databricks account ID (a UUID)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.account_id))
    error_message = "account_id must be the Databricks account ID, a UUID such as 11111111-2222-3333-4444-555555555555; change the account_id variable."
  }
}

variable "workspace_name" {
  description = "Name of the host workspace, at most 30 characters. One per account."
  type        = string
  default     = "jwall-engineering-shared"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.workspace_name)) && length(var.workspace_name) <= 30
    error_message = "workspace_name must be kebab-case and at most 30 characters, for example `jwall-engineering-shared`; change the workspace_name variable."
  }
}

variable "region" {
  description = "Region of the workspace. Only `us-east-1` is supported, the metastore's region."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.region == "us-east-1"
    error_message = "region must be \"us-east-1\", the only region this library supports; change the region variable."
  }
}

variable "metastore_id" {
  description = "ID of the region's Unity Catalog metastore, the `metastore_id` output of `databricks-metastore`: the objects created through this workspace live in it."
  type        = string

  validation {
    condition     = length(var.metastore_id) > 0
    error_message = "metastore_id must not be empty; pass the metastore_id output of databricks-metastore."
  }
}

variable "admin_group_name" {
  description = "Account group given ADMIN on the workspace, the `admin_group_name` output of `databricks-metastore`. It holds the automation service principal, which manages the shared objects through the workspace, and the metastore admins. Nobody else is assigned."
  type        = string

  validation {
    condition     = length(trimspace(var.admin_group_name)) > 0
    error_message = "admin_group_name must not be empty; pass the admin_group_name output of databricks-metastore."
  }
}

variable "tags" {
  description = "Tags on the workspace (`custom_tags`): must contain `Project`, `Environment`, `CostCenter`, `Workspace`, `Owner` and `ManagedBy`, and no key Databricks reserves (`Vendor`, `Creator`, `ClusterName`, `ClusterId`, `Name`)."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["Project", "Environment", "CostCenter", "Workspace", "Owner", "ManagedBy"] : contains(keys(var.tags), k)])
    error_message = "tags must contain the keys Project, Environment, CostCenter, Workspace, Owner and ManagedBy; add the missing ones to the tags variable."
  }

  validation {
    condition     = length(setintersection(keys(var.tags), ["Vendor", "Creator", "ClusterName", "ClusterId", "Name"])) == 0
    error_message = "tags must not use a key Databricks reserves (Vendor, Creator, ClusterName, ClusterId, Name); remove it from the tags variable."
  }
}
