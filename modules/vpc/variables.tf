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
