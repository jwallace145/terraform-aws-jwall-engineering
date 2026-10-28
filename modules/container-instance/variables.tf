variable "name" {
  description = "Name of the instance, its role, instance profile and security group, in kebab-case, for example `jwall-engineering-rusty-chess-bot`. Start it with `<name_root>-<project>-` so the `container/*` CI policies can manage it."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name)) && length(var.name) <= 48
    error_message = "name must be kebab-case: lowercase letters, digits and single hyphens, at most 48 characters."
  }
}

variable "project" {
  description = "Project in kebab-case, for example `rusty-chess`. Parameters live under `/<name_root>/<project>/bot/` and logs in `/<name_root>/<project>/bot`."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.project))
    error_message = "project must be kebab-case: lowercase letters, digits and single hyphens."
  }
}

variable "name_root" {
  description = "Prefix of parameter and log group paths, in kebab-case."
  type        = string
  default     = "jwall-engineering"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name_root))
    error_message = "name_root must be kebab-case: lowercase letters, digits and single hyphens."
  }
}

variable "image_repository_url" {
  description = "URL of the ECR repository the image tags come from (output `url` of `ecr-repository`)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com/[a-z0-9._/-]+$", var.image_repository_url))
    error_message = "image_repository_url must be an ECR repository URL like `123456789012.dkr.ecr.us-east-1.amazonaws.com/name`."
  }
}

variable "image_repository_arn" {
  description = "ARN of the same ECR repository (output `arn` of `ecr-repository`), which the instance may pull from."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:ecr:[a-z0-9-]+:[0-9]{12}:repository/[a-z0-9._/-]+$", var.image_repository_arn))
    error_message = "image_repository_arn must be an ECR repository ARN like `arn:aws:ecr:us-east-1:123456789012:repository/name`."
  }
}

variable "instance_type" {
  description = "EC2 instance type. Must match `architecture` (t3 for x86_64, t4g for arm64)."
  type        = string
  default     = "t3.micro"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must look like `t3.micro`."
  }
}

variable "architecture" {
  description = "CPU architecture of the AMI: `x86_64` or `arm64`. The image must be built for the same one."
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be x86_64 or arm64."
  }
}

variable "vpc_id" {
  description = "VPC of the security group (output `vpc_id` of `vpc`)."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a VPC ID like `vpc-0123abcd`."
  }
}

variable "subnet_id" {
  description = "Public subnet of the instance (an element of `public_subnet_ids` of `vpc`). The instance gets a public IPv4 address for egress."
  type        = string

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a subnet ID like `subnet-0123abcd`."
  }
}

variable "secret_parameters" {
  description = "Environment variables the container gets from SecureString parameters: variable name to parameter name, for example `{ LICHESS_TOKEN = \"/jwall-engineering/rusty-chess/lichess-token\" }`. The parameters are created out of band, never by Terraform; the instance may read exactly these."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.secret_parameters) : can(regex("^[A-Z][A-Z0-9_]*$", k))])
    error_message = "every secret_parameters key must be an environment variable name like `LICHESS_TOKEN`."
  }

  validation {
    condition = alltrue([
      for v in values(var.secret_parameters) :
      startswith(v, "/${var.name_root}/${var.project}/") && !startswith(v, "/${var.name_root}/${var.project}/bot/") && can(regex("^(/[A-Za-z0-9_.-]+)+$", v))
    ])
    error_message = "every secret parameter must live under /<name_root>/<project>/ and outside /<name_root>/<project>/bot/ (which the release role can write)."
  }
}

variable "container_environment" {
  description = "Plain environment variables for the container. Values must not contain spaces."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.container_environment : can(regex("^[A-Z][A-Z0-9_]*$", k)) && can(regex("^[^\\s'\"]*$", v))
    ])
    error_message = "container_environment keys must be environment variable names and values must not contain whitespace or quotes."
  }
}

variable "bot_name" {
  description = "Name of the account the container plays as (for example the Lichess bot user), recorded in every game record's sidecar."
  type        = string
  default     = ""
}

variable "records_bucket_name" {
  description = "Bucket that finished game records are shipped to (output `name` of `private-bucket`). `null` disables the records sync."
  type        = string
  default     = null
}

variable "records_prefix" {
  description = "Key prefix in the records bucket. Below it the layout is fixed: `pgn/schema=1/engine=<tag>/date=<YYYY-MM-DD>/<game_id>.pgn` and the matching `meta/.../<game_id>.json` sidecar."
  type        = string
  default     = "records/"

  validation {
    condition     = can(regex("^([a-z0-9][a-z0-9-]*/)+$", var.records_prefix))
    error_message = "records_prefix must be one or more lowercase path segments ending in `/`, for example `records/`."
  }
}

variable "records_container_path" {
  description = "Absolute path inside the container where it writes one `.pgn` file per game. Required when `records_bucket_name` is set; the host directory mounted there is per image tag."
  type        = string
  default     = null

  validation {
    condition     = var.records_bucket_name == null || (var.records_container_path != null && can(regex("^/[A-Za-z0-9_./-]+$", coalesce(var.records_container_path, "-"))))
    error_message = "records_container_path must be an absolute path when records_bucket_name is set."
  }
}

variable "log_retention_days" {
  description = "Retention of the container's CloudWatch log group, in days."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of CloudWatch's allowed values: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653."
  }
}

variable "health_log_pattern" {
  description = "Text the new container must log within `health_seconds` to count as healthy, for example `awaiting challenges`. Empty: it only has to stay up."
  type        = string
  default     = ""
}

variable "health_seconds" {
  description = "How long a new container has to prove it is healthy before it is rolled back."
  type        = number
  default     = 90

  validation {
    condition     = var.health_seconds >= 10 && var.health_seconds <= 600 && floor(var.health_seconds) == var.health_seconds
    error_message = "health_seconds must be an integer from 10 to 600."
  }
}

variable "stop_signal" {
  description = "Signal sent once to the running container to ask it to finish and exit. It is never followed by a kill."
  type        = string
  default     = "SIGINT"

  validation {
    condition     = can(regex("^SIG[A-Z0-9]+$", var.stop_signal)) && var.stop_signal != "SIGKILL"
    error_message = "stop_signal must be a signal name like SIGINT or SIGTERM, and never SIGKILL."
  }
}

variable "stop_poll_seconds" {
  description = "How often the reconciler checks whether the stopping container has exited."
  type        = number
  default     = 15

  validation {
    condition     = var.stop_poll_seconds >= 1 && var.stop_poll_seconds <= 60 && floor(var.stop_poll_seconds) == var.stop_poll_seconds
    error_message = "stop_poll_seconds must be an integer from 1 to 60."
  }
}

variable "root_volume_gb" {
  description = "Size of the gp3 root volume in GB. It holds Docker images and the game records until they are shipped."
  type        = number
  default     = 16

  validation {
    condition     = var.root_volume_gb >= 8 && var.root_volume_gb <= 64 && floor(var.root_volume_gb) == var.root_volume_gb
    error_message = "root_volume_gb must be an integer from 8 to 64."
  }
}

variable "component" {
  description = "Value of the `Component` tag on every resource. The release CLI finds the instance by `Project` and this tag."
  type        = string
  default     = "container-instance"

  validation {
    condition     = length(var.component) > 0
    error_message = "component must not be empty."
  }
}
