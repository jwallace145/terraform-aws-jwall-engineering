variable "name" {
  description = "Name of the VPC in kebab-case, for example `jwall-engineering-rusty-chess`. The subnets, gateway and route table are named after it."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name)) && length(var.name) <= 64
    error_message = "name must be kebab-case: lowercase letters, digits and single hyphens, at most 64 characters."
  }
}

variable "cidr_block" {
  description = "IPv4 CIDR of the VPC, between /16 and /24. Each public subnet is a /24 carved from it."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition = (
      can(cidrhost(var.cidr_block, 0)) &&
      can(regex("^[0-9.]+/(1[6-9]|2[0-4])$", var.cidr_block))
    )
    error_message = "cidr_block must be an IPv4 CIDR with a prefix length between 16 and 24, for example `10.0.0.0/16`."
  }
}

variable "availability_zones" {
  description = "Availability zones that get one public subnet each, in order. One is enough for a single instance; spot fleets want every zone that offers their type, since capacity is per zone. Append zones: subnets are numbered by position, so appending leaves existing subnets (and instances in them) alone."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition = (
      length(var.availability_zones) >= 1 && length(var.availability_zones) <= 6 &&
      alltrue([for az in var.availability_zones : can(regex("^us-east-1[a-f]$", az))]) &&
      length(distinct(var.availability_zones)) == length(var.availability_zones)
    )
    error_message = "availability_zones must list 1 to 6 distinct us-east-1 zones, for example [\"us-east-1a\", \"us-east-1b\"]."
  }
}

variable "component" {
  description = "Value of the `Component` tag on every resource."
  type        = string
  default     = "vpc"

  validation {
    condition     = length(var.component) > 0
    error_message = "component must not be empty."
  }
}

variable "private_subnet_cidrs" {
  description = "IPv4 CIDRs of the private subnets, one per entry of `availability_zones` and in the same order, or empty for none. Each must sit inside `cidr_block` and not overlap a public /24 or another private subnet. The private route table has no default route: the caller adds one, for example from `nat-instance`."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.private_subnet_cidrs) == 0 || length(var.private_subnet_cidrs) == length(var.availability_zones)
    error_message = "private_subnet_cidrs must be empty or have exactly one CIDR per entry of availability_zones (in the same order). Change private_subnet_cidrs or availability_zones so the counts match."
  }

  validation {
    condition     = alltrue([for c in var.private_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "private_subnet_cidrs must all be valid IPv4 CIDRs, for example `10.0.128.0/20`. Change private_subnet_cidrs."
  }

  # Terraform has no cidrcontains(): ranges are compared as integers, start
  # address and size. try() keeps a malformed entry reported by the validation
  # above instead of erroring here.
  validation {
    condition = try(alltrue([
      for c in var.private_subnet_cidrs :
      sum([for k, o in split(".", cidrhost(c, 0)) : tonumber(o) * pow(256, 3 - k)]) >= sum([for k, o in split(".", cidrhost(var.cidr_block, 0)) : tonumber(o) * pow(256, 3 - k)]) &&
      sum([for k, o in split(".", cidrhost(c, 0)) : tonumber(o) * pow(256, 3 - k)]) + pow(2, 32 - tonumber(split("/", c)[1])) <=
      sum([for k, o in split(".", cidrhost(var.cidr_block, 0)) : tonumber(o) * pow(256, 3 - k)]) + pow(2, 32 - tonumber(split("/", var.cidr_block)[1]))
    ]), false)
    error_message = "every private_subnet_cidrs entry must sit inside cidr_block. Change private_subnet_cidrs or cidr_block."
  }

  # The public subnets are cidrsubnet(cidr_block, 24 - prefix, i): /24s at
  # cidr_block's start address plus i * 256.
  validation {
    condition = try(alltrue([
      for c in var.private_subnet_cidrs : alltrue([
        for i in range(length(var.availability_zones)) :
        !(
          sum([for k, o in split(".", cidrhost(c, 0)) : tonumber(o) * pow(256, 3 - k)]) < sum([for k, o in split(".", cidrhost(var.cidr_block, 0)) : tonumber(o) * pow(256, 3 - k)]) + (i + 1) * 256 &&
          sum([for k, o in split(".", cidrhost(var.cidr_block, 0)) : tonumber(o) * pow(256, 3 - k)]) + i * 256 < sum([for k, o in split(".", cidrhost(c, 0)) : tonumber(o) * pow(256, 3 - k)]) + pow(2, 32 - tonumber(split("/", c)[1]))
        )
      ])
    ]), false)
    error_message = "private_subnet_cidrs must not overlap the public subnets, which are consecutive /24s from the start of cidr_block (one per availability zone). Change private_subnet_cidrs to a range outside them, for example the upper half of cidr_block."
  }

  validation {
    condition = try(alltrue([
      for i, a in var.private_subnet_cidrs : alltrue([
        for j, b in var.private_subnet_cidrs :
        i == j || !(
          sum([for k, o in split(".", cidrhost(a, 0)) : tonumber(o) * pow(256, 3 - k)]) < sum([for k, o in split(".", cidrhost(b, 0)) : tonumber(o) * pow(256, 3 - k)]) + pow(2, 32 - tonumber(split("/", b)[1])) &&
          sum([for k, o in split(".", cidrhost(b, 0)) : tonumber(o) * pow(256, 3 - k)]) < sum([for k, o in split(".", cidrhost(a, 0)) : tonumber(o) * pow(256, 3 - k)]) + pow(2, 32 - tonumber(split("/", a)[1]))
        )
      ])
    ]), false)
    error_message = "private_subnet_cidrs must not overlap each other. Change private_subnet_cidrs."
  }
}

variable "s3_gateway_endpoint" {
  description = "Optional S3 gateway endpoint, associated with the private route table (so it needs `private_subnet_cidrs`). `policy` is an endpoint policy JSON document, passed through unchanged; omit it for the AWS default (full access)."
  type = object({
    enabled = bool
    policy  = optional(string)
  })
  default = { enabled = false }

  validation {
    condition     = !var.s3_gateway_endpoint.enabled || length(var.private_subnet_cidrs) > 0
    error_message = "s3_gateway_endpoint.enabled requires private subnets: set private_subnet_cidrs, or set s3_gateway_endpoint.enabled to false."
  }

  validation {
    condition     = var.s3_gateway_endpoint.policy == null || can(jsondecode(var.s3_gateway_endpoint.policy))
    error_message = "s3_gateway_endpoint.policy must be a JSON policy document (use jsonencode()). Change s3_gateway_endpoint.policy."
  }
}
