# vpc

A VPC for workloads that need to reach the internet and must never be
reached from it: DNS support and hostnames on, one public subnet per
availability zone (consecutive `/24`s carved from the VPC CIDR, public IPs
on launch), an internet gateway and one public route table. The VPC's
default security group is left as AWS creates it and nothing is launched
into it; workloads bring their own security group.

There is no NAT gateway, no private subnet and no VPC endpoint. A NAT
gateway alone costs more than a small instance; an instance with a public
IPv4 address and a security group without ingress rules gets the same
egress for the price of the address. Private subnets or endpoints would be
additive if a later workload needs them.

Every resource carries `Name` and `Component` tags; the organisation tags
come from the caller's provider `default_tags`.

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/vpc>

## Usage

```hcl
module "network" {
  source  = "jwallace145/jwall-engineering/aws//modules/vpc"
  version = "~> 0.10"

  name               = "jwall-engineering-rusty-chess"
  availability_zones = ["us-east-1a", "us-east-1b"]
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11 |
| aws | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | ~> 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_route.internet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Name of the VPC in kebab-case, for example `jwall-engineering-rusty-chess`. The subnets, gateway and route table are named after it. | `string` | n/a | yes |
| availability\_zones | Availability zones that get one public subnet each, in order. One is enough for a single instance; spot fleets want every zone that offers their type, since capacity is per zone. Append zones: subnets are numbered by position, so appending leaves existing subnets (and instances in them) alone. | `list(string)` | <pre>[<br/>  "us-east-1a",<br/>  "us-east-1b"<br/>]</pre> | no |
| cidr\_block | IPv4 CIDR of the VPC, between /16 and /24. Each public subnet is a /24 carved from it. | `string` | `"10.0.0.0/16"` | no |
| component | Value of the `Component` tag on every resource. | `string` | `"vpc"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| cidr\_block | IPv4 CIDR of the VPC. |
| internet\_gateway\_id | ID of the internet gateway. |
| public\_subnet\_ids | IDs of the public subnets, in the order of `availability_zones`. |
| route\_table\_id | ID of the public route table. |
| vpc\_id | ID of the VPC, for security groups. |
<!-- END_TF_DOCS -->
