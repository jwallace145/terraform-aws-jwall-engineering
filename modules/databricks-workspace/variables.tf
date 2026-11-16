variable "account_id" {
  description = "Databricks account ID (a UUID). Also the external ID the cross-account role requires from Databricks."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.account_id))
    error_message = "account_id must be the Databricks account ID, a UUID such as 11111111-2222-3333-4444-555555555555; change the account_id variable."
  }
}

variable "name_root" {
  description = "Prefix of AWS resource names, in kebab-case. With `<p>` = `<name_root>-<project>`, the root bucket is `<p>-databricks-root`, the cross-account role `<p>-databricks-cross-account` and the security group `<p>-databricks-workspace`."
  type        = string
  default     = "jwall-engineering"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name_root))
    error_message = "name_root must be kebab-case: lowercase letters, digits and single hyphens, for example `jwall-engineering`; change the name_root variable."
  }
}

variable "project" {
  description = "Project in kebab-case, for example `databricks-poc`. Names the workspace (`<project>-<environment>`), its groups (`<project>-workspace-admins`, `<project>-workspace-users`) and, through `<p>`, its AWS resources. At most 21 characters with the default name_root, so `<p>-databricks-cross-account` fits IAM's 64 and `<p>-databricks-catalog` S3's 63."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.project))
    error_message = "project must be kebab-case: lowercase letters, digits and single hyphens, for example `databricks-poc`; change the project variable."
  }

  # The longest names derived from project: the IAM role (64-character
  # limit) and the catalog bucket that databricks-catalog creates (63).
  validation {
    condition = (
      length(var.project) <= 24 &&
      length("${var.name_root}-${var.project}-databricks-cross-account") <= 64 &&
      length("${var.name_root}-${var.project}-databricks-catalog") <= 63
    )
    error_message = "project is too long: it must be at most 24 characters and short enough that `<name_root>-<project>-databricks-cross-account` is at most 64 (IAM role names), which with the default name_root means at most 21 characters; shorten the project variable."
  }
}

variable "environment" {
  description = "Environment in kebab-case, for example `dev`. The workspace is named `<project>-<environment>`, at most 30 characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.environment))
    error_message = "environment must be kebab-case: lowercase letters, digits and single hyphens, for example `dev`; change the environment variable."
  }

  validation {
    condition     = length("${var.project}-${var.environment}") <= 30
    error_message = "the workspace name `<project>-<environment>` must be at most 30 characters; shorten the environment (or project) variable."
  }
}

variable "vpc_id" {
  description = "ID of the VPC the workspace's clusters run in, for example the `vpc_id` output of `vpc`. It needs a NAT (for example `nat-instance`) for the private subnets' internet egress."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a VPC ID such as `vpc-0123456789abcdef0`; change the vpc_id variable."
  }
}

variable "subnet_ids" {
  description = "IDs of the private subnets of vpc_id for the workspace's clusters, for example the `private_subnet_ids` output of `vpc`: at least two, each in a different availability zone, each with a netmask between /17 and /26 (checked against the subnet when it is read)."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2 && length(distinct(var.subnet_ids)) == length(var.subnet_ids)
    error_message = "subnet_ids must list at least two distinct subnet IDs (Databricks needs two subnets in different availability zones), for example the private_subnet_ids output of vpc; change the subnet_ids variable."
  }
}

variable "metastore_id" {
  description = "ID of the region's Unity Catalog metastore that the workspace is assigned to, the `metastore_id` output of `databricks-metastore` (the stack looks it up)."
  type        = string

  validation {
    condition     = length(var.metastore_id) > 0
    error_message = "metastore_id must not be empty; pass the metastore_id output of databricks-metastore."
  }
}

variable "deployment_name" {
  description = "Deployment name, the first label of the workspace URL (`<deployment_name>.cloud.databricks.com`). `null` (the default) lets Databricks pick one. Only possible if the account allows custom deployment names."
  type        = string
  default     = null

  validation {
    condition     = var.deployment_name == null || can(regex("^[a-z0-9-]{3,30}$", var.deployment_name))
    error_message = "deployment_name must be null or 3 to 30 lowercase letters, digits and hyphens, for example `databricks-poc-dev`; change the deployment_name variable."
  }
}

variable "tags" {
  description = "Tags Databricks puts on the workspace's cluster resources (`custom_tags`), as AWS does not apply the caller's default_tags to them. Must contain `Project`, `Environment`, `CostCenter`, `Workspace`, `Owner` and `ManagedBy`, and no key Databricks reserves (`Vendor`, `Creator`, `ClusterName`, `ClusterId`, `Name`)."
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

variable "admin_user_names" {
  description = "Databricks user names (email addresses) of the workspace admins, for example `[\"owner@example.com\"]`. Each user must already exist in the account; they join `<project>-workspace-admins`."
  type        = list(string)

  validation {
    condition     = alltrue([for u in var.admin_user_names : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", u))])
    error_message = "every entry of admin_user_names must be an email address such as owner@example.com; change the admin_user_names variable."
  }
}

variable "user_names" {
  description = "Databricks user names (email addresses) of the workspace's non-admin users. Each user must already exist in the account; they join `<project>-workspace-users`."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for u in var.user_names : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", u))])
    error_message = "every entry of user_names must be an email address such as analyst@example.com; change the user_names variable."
  }
}

variable "service_principal_application_id" {
  description = "Application (client) ID of the account-level service principal that automation authenticates as. It joins the admin group, so the workspace stack can manage the workspace."
  type        = string

  validation {
    condition     = length(var.service_principal_application_id) > 0
    error_message = "service_principal_application_id must not be empty; pass the application ID of the automation service principal."
  }
}

variable "read_only_datasets" {
  description = "Shared datasets the workspace may read through Unity Catalog, keyed by the dataset's kebab-case name, for example `{ braveheart-selfplay-positions = { bucket = \"jwall-engineering-braveheart-selfplay-positions\", prefix = \"data/\", role_arn = \"arn:aws:iam::111122223333:role/jwall-engineering-ds-braveheart-selfplay-positions\" } }`: the `endpoint_dataset` output of `databricks-dataset`. Each adds one statement to the S3 endpoint policy allowing `s3:GetObject` under the prefix and `s3:ListBucket`/`s3:GetBucketLocation` on the bucket, only for that dataset's role. The endpoint grants nothing: the dataset's bucket policy must name the role as a reader."
  type = map(object({
    bucket   = string
    prefix   = string
    role_arn = string
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.read_only_datasets) : can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", k)) && length(k) <= 40])
    error_message = "every key of read_only_datasets must be kebab-case and at most 40 characters, for example `rusty-chess-nnue`; change the read_only_datasets variable."
  }

  validation {
    condition     = alltrue([for d in values(var.read_only_datasets) : can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", d.bucket))])
    error_message = "every bucket in read_only_datasets must be an S3 bucket name such as `jwall-engineering-rusty-chess-nnue`; change the read_only_datasets variable."
  }

  # A non-empty prefix, as a dataset's readers are granted: path segments
  # ending in `/`, no leading `/`, no wildcard.
  validation {
    condition     = alltrue([for d in values(var.read_only_datasets) : can(regex("^([A-Za-z0-9!_.'()-]+/)+$", d.prefix))])
    error_message = "every prefix in read_only_datasets must be one or more path segments ending in `/` with no leading `/` and no `*`, for example `data/`; change the read_only_datasets variable."
  }

  validation {
    condition     = alltrue([for d in values(var.read_only_datasets) : can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", d.role_arn))])
    error_message = "every role_arn in read_only_datasets must be an IAM role ARN, the dataset role from databricks-dataset's endpoint_dataset output; change the read_only_datasets variable."
  }

  # The workspace's own buckets are already covered, and its own Unity
  # Catalog role reads only its catalog: a dataset must bring its own role.
  validation {
    condition = alltrue([
      for d in values(var.read_only_datasets) :
      !contains(["${var.name_root}-${var.project}-databricks-root", "${var.name_root}-${var.project}-databricks-catalog"], d.bucket) &&
      !endswith(d.role_arn, ":role/${var.name_root}-${var.project}-databricks-uc")
    ])
    error_message = "read_only_datasets must not name the workspace's own root or catalog bucket, or its own Unity Catalog role; pass onboarded datasets from databricks-dataset only."
  }
}

variable "component" {
  description = "Value of the `Component` tag on every AWS resource."
  type        = string
  default     = "databricks-workspace"
}
