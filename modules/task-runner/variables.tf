variable "name_root" {
  description = "Prefix of every name, in kebab-case. The template, role, profile and security group are `<name_root>-<project>-task`."
  type        = string
  default     = "jwall-engineering"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name_root))
    error_message = "name_root must be kebab-case: lowercase letters, digits and single hyphens."
  }
}

variable "project" {
  description = "Project in kebab-case, for example `rusty-chess`. Names derive from it: `<name_root>-<project>-task`, the log group `/<name_root>/<project>/tasks` and the results bucket `<name_root>-<project>-tasks`, which the caller creates."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.project))
    error_message = "project must be kebab-case: lowercase letters, digits and single hyphens (e.g. `rusty-chess`)."
  }

  validation {
    condition     = length("${var.name_root}-${var.project}-tasks") <= 63
    error_message = "name_root and project are too long: `<name_root>-<project>-tasks` must fit S3's 63-character bucket name limit."
  }
}

variable "vpc_id" {
  description = "VPC of the task security group. Instances launch into the project's public subnets of this VPC, which the CLI picks per launch."
  type        = string
}

variable "architecture" {
  description = "CPU architecture of the image: `x86_64` or `arm64`. The instance types launched must match it."
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be x86_64 or arm64."
  }
}

variable "ami_id" {
  description = "Image of the task instances, an Amazon-owned Amazon Linux 2023 image (the launch role may launch no other). `null` follows the latest one through `/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-<architecture>`; pin it for reproducible task environments."
  type        = string
  default     = null

  validation {
    condition     = var.ami_id == null || can(regex("^ami-[0-9a-f]{8,17}$", var.ami_id))
    error_message = "ami_id must be an AMI ID like ami-0123456789abcdef0, or null."
  }
}

variable "default_instance_type" {
  description = "Instance type of the template. The CLI passes the type per launch; which types may be launched is the launch role's allow-list (`ci-task-role`), not this module's."
  type        = string
  default     = "c8a.xlarge"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.default_instance_type))
    error_message = "default_instance_type must be an EC2 instance type like c8a.xlarge."
  }
}

variable "root_volume_gb" {
  description = "Size of the encrypted gp3 root volume in GB, deleted with the instance. It holds the toolchain, the checkout and the build."
  type        = number
  default     = 40

  validation {
    condition     = var.root_volume_gb >= 20 && var.root_volume_gb <= 200 && floor(var.root_volume_gb) == var.root_volume_gb
    error_message = "root_volume_gb must be a whole number from 20 to 200."
  }
}

variable "max_lifetime_hours" {
  description = "Hours after boot at which an instance shuts itself down, and so terminates, whatever it is doing. It bounds the cost of an instance the CLI failed to terminate."
  type        = number
  default     = 6

  validation {
    condition     = var.max_lifetime_hours >= 1 && var.max_lifetime_hours <= 24 && floor(var.max_lifetime_hours) == var.max_lifetime_hours
    error_message = "max_lifetime_hours must be a whole number from 1 to 24."
  }
}

variable "log_retention_days" {
  description = "Days CloudWatch keeps task output."
  type        = number
  default     = 14

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.log_retention_days)
    error_message = "log_retention_days must be one of 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180 or 365."
  }
}

variable "rust_toolchain" {
  description = "Rust toolchain the setup installs with rustup: `stable`, a channel like `nightly-2026-10-01`, or a version like `1.91.0`. Pin a version for reproducible builds."
  type        = string
  default     = "stable"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*$", var.rust_toolchain))
    error_message = "rust_toolchain must be a rustup toolchain name: lowercase letters, digits, `.` and `-`."
  }
}
