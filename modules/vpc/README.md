# vpc

A VPC for workloads that need to reach the internet and must never be
reached from it: DNS support and hostnames on, one public subnet per
availability zone (consecutive `/24`s carved from the VPC CIDR, public IPs
on launch), an internet gateway and one public route table. The VPC's
default security group is left as AWS creates it and nothing is launched
into it; workloads bring their own security group.

By default there is no NAT gateway, no private subnet and no VPC endpoint. A
NAT gateway alone costs more than a small instance; an instance with a public
IPv4 address and a security group without ingress rules gets the same
egress for the price of the address. Private subnets and an S3 gateway
endpoint are optional (see [Private subnets](#private-subnets)).

Every resource carries `Name` and `Component` tags; the organisation tags
come from the caller's provider `default_tags`.

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/vpc>

## Private subnets

Set `private_subnet_cidrs` (one CIDR per entry of `availability_zones`, in
order) to add private subnets, named `<name>-private-<az>` and with no public
IP on launch. They share one private route table that has **no default
route**: the caller adds it, for example `aws_route` with
`route_table_id = module.network.private_route_table_id` and the network
interface of a `nat-instance`. The CIDRs must sit inside `cidr_block` and
overlap neither the public `/24`s (the first ones in `cidr_block`, one per
zone) nor each other; the upper half of the VPC is a safe place. The module
does not impose any subnet-size rule: that is for the consumer.

`s3_gateway_endpoint = { enabled = true }` adds a gateway endpoint for S3
associated with the **private** route table only, so same-region S3 traffic
from private subnets stays off the NAT. It requires private subnets. An
optional `policy` (JSON, build it with `jsonencode()`) is passed through
unchanged. When the policy has to name a role that does not exist yet, put it in
an `ArnEquals` `aws:PrincipalArn` condition rather than in `Principal`, which
AWS validates when the policy is attached.

Both inputs default to nothing: a caller that sets neither plans exactly the
resources it did before (no new subnets, route tables or endpoints), so
existing stacks such as rusty-chess are unaffected.

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
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Name of the VPC in kebab-case, for example `jwall-engineering-rusty-chess`. The subnets, gateway and route table are named after it. | `string` | n/a | yes |
| availability\_zones | Availability zones that get one public subnet each, in order. One is enough for a single instance; spot fleets want every zone that offers their type, since capacity is per zone. Append zones: subnets are numbered by position, so appending leaves existing subnets (and instances in them) alone. | `list(string)` | <pre>[<br/>  "us-east-1a",<br/>  "us-east-1b"<br/>]</pre> | no |
| cidr\_block | IPv4 CIDR of the VPC, between /16 and /24. Each public subnet is a /24 carved from it. | `string` | `"10.0.0.0/16"` | no |
| component | Value of the `Component` tag on every resource. | `string` | `"vpc"` | no |
| private\_subnet\_cidrs | IPv4 CIDRs of the private subnets, one per entry of `availability_zones` and in the same order, or empty for none. Each must sit inside `cidr_block` and not overlap a public /24 or another private subnet. The private route table has no default route: the caller adds one, for example from `nat-instance`. | `list(string)` | `[]` | no |
| s3\_gateway\_endpoint | Optional S3 gateway endpoint, associated with the private route table (so it needs `private_subnet_cidrs`). `policy` is an endpoint policy JSON document, passed through unchanged; omit it for the AWS default (full access). | <pre>object({<br/>    enabled = bool<br/>    policy  = optional(string)<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| cidr\_block | IPv4 CIDR of the VPC. |
| internet\_gateway\_id | ID of the internet gateway. |
| private\_route\_table\_id | ID of the private route table, for the caller's default route. Null without `private_subnet_cidrs`. |
| private\_subnet\_ids | IDs of the private subnets, in the order of `availability_zones`. Empty without `private_subnet_cidrs`. |
| public\_subnet\_ids | IDs of the public subnets, in the order of `availability_zones`. |
| route\_table\_id | ID of the public route table. |
| s3\_endpoint\_id | ID of the S3 gateway endpoint. Null unless `s3_gateway_endpoint.enabled`. |
| vpc\_id | ID of the VPC, for security groups. |
<!-- END_TF_DOCS -->
