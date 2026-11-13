variable "name" {
  description = "Name of the NAT in kebab-case, for example `jwall-engineering-databricks-poc-nat`. The instance, network interface, security group and Elastic IP are named after it."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name)) && length(var.name) <= 64
    error_message = "name must be kebab-case: lowercase letters, digits and single hyphens, at most 64 characters."
  }
}

variable "subnet_id" {
  description = "ID of the public subnet (one with a route to an internet gateway) that holds the NAT's network interface. The NAT serves one availability zone's worth of failure: this subnet's."
  type        = string
}

variable "private_route_table_ids" {
  description = "IDs of the private route tables that get a default route (0.0.0.0/0) through the NAT's network interface, for example the `private_route_table_id` output of `vpc`. Must not already have a default route."
  type        = list(string)

  validation {
    condition     = length(var.private_route_table_ids) >= 1
    error_message = "private_route_table_ids must list at least one route table ID, for example the `private_route_table_id` output of the vpc module."
  }
}

variable "source_cidrs" {
  description = "IPv4 CIDRs allowed to send traffic through the NAT, normally the private subnets' CIDRs. They are the only ingress of the security group and the only sources masqueraded."
  type        = list(string)

  validation {
    condition     = length(var.source_cidrs) >= 1 && alltrue([for c in var.source_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "source_cidrs must list at least one IPv4 CIDR, none of them 0.0.0.0/0, for example [\"10.0.2.0/24\"]."
  }
}

variable "ami_id" {
  description = "ID of an Amazon Linux 2023 arm64 AMI. The caller resolves it from a pinned name, so the NAT is not replaced when a new image is published."
  type        = string

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be an AMI ID such as `ami-0123456789abcdef0`."
  }
}

variable "instance_type" {
  description = "Arm64 instance type of the NAT: `t4g`, `c7g`, `c8g` or `m7g` family. The default is enough for light egress; raise it for sustained throughput."
  type        = string
  default     = "t4g.nano"

  validation {
    condition     = can(regex("^(t4g|c7g|c8g|m7g)\\.", var.instance_type))
    error_message = "instance_type must be an arm64 type from the t4g, c7g, c8g or m7g families (the AMI is arm64), for example `t4g.nano`; change instance_type."
  }
}

variable "component" {
  description = "Value of the `Component` tag on every resource."
  type        = string
  default     = "nat-instance"
}
