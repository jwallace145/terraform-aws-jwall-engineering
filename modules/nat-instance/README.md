# nat-instance

Gives private route tables a default route to the internet through one small
instance. It is a low-cost stand-in for a NAT gateway: a `t4g.nano` with IP
forwarding and `iptables` masquerading, behind a dedicated network interface
(ENI) that the routes point at.

The module knows nothing about what sits behind it. Typical use is
`private_route_table_ids = [module.vpc.private_route_table_id]` and
`source_cidrs = <the private subnets' CIDRs>`.

## How it works

- `aws_network_interface` with `source_dest_check = false`, in the public
  `subnet_id`, is the instance's primary interface.
- One Elastic IP is associated with that ENI. It is required: an interface
  created separately from the instance never gets an auto-assigned public
  IPv4, so without it the NAT would have no egress. `public_ip` is its address.
- `user_data` is a `#cloud-config` that writes [`files/nat-setup.sh`](files/nat-setup.sh)
  to `/usr/local/sbin/nat-setup.sh` and runs it with `source_cidrs` as arguments.
  The script enables forwarding, installs `iptables-services`, masquerades each
  CIDR out of the default-route interface and persists the rules.
- One `aws_route` (`0.0.0.0/0`) per private route table, targeting the **ENI**,
  not the instance.
- Security group: all protocols in from `source_cidrs` only, all out.
- IMDSv2 required; encrypted 8 GB gp3 root volume. The AMI is an input, so the
  caller pins an AL2023 arm64 image and a new release does not replace the NAT.

## Cost

About $3 per month in us-east-1 (`t4g.nano` plus its 8 GB volume plus one
public IPv4 via an Elastic IP, required because the primary ENI is created
separately; it costs the same $0.005 per hour as any public IPv4), against
about $33 per month plus per-GB data processing charges for a NAT gateway.
Data transfer out to the internet is billed as usual.

## Availability

One availability zone, no high availability. If the instance's host fails,
EC2 simplified automatic recovery restarts the instance, and the ENI keeps
its address and routes. If the instance is replaced (for example a change to
`ami_id`, `instance_type` or the CIDRs, which replaces it through
`user_data_replace_on_change`), the routes keep pointing at the same ENI, so
routing resumes when the new instance has booted, with a gap of a couple of
minutes. A failure of the whole zone takes egress down until it returns.

## Known gaps

- **Single point of failure**, as above. Use a NAT gateway where egress must
  survive an instance or zone failure.
- **Throughput is the instance's.** A `t4g.nano` has burstable, limited network
  bandwidth; raise `instance_type` for sustained load.
- **Source CIDRs are fixed at boot.** Changing them replaces the instance.
- **No IPv6.**
- **No monitoring or alarms** are created.
- **The security group allows all protocols** from the source CIDRs, because a
  NAT must carry anything. It is not a filter.
- **`Resource = "*"`:** the module creates no IAM policy and no instance role,
  so it adds none.

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
| [aws_eip.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_network_interface.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_interface) | resource |
| [aws_route.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_subnet.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| ami\_id | ID of an Amazon Linux 2023 arm64 AMI. The caller resolves it from a pinned name, so the NAT is not replaced when a new image is published. | `string` | n/a | yes |
| name | Name of the NAT in kebab-case, for example `jwall-engineering-databricks-poc-nat`. The instance, network interface, security group and Elastic IP are named after it. | `string` | n/a | yes |
| private\_route\_table\_ids | IDs of the private route tables that get a default route (0.0.0.0/0) through the NAT's network interface, for example the `private_route_table_id` output of `vpc`. Must not already have a default route. | `list(string)` | n/a | yes |
| source\_cidrs | IPv4 CIDRs allowed to send traffic through the NAT, normally the private subnets' CIDRs. They are the only ingress of the security group and the only sources masqueraded. | `list(string)` | n/a | yes |
| subnet\_id | ID of the public subnet (one with a route to an internet gateway) that holds the NAT's network interface. The NAT serves one availability zone's worth of failure: this subnet's. | `string` | n/a | yes |
| component | Value of the `Component` tag on every resource. | `string` | `"nat-instance"` | no |
| instance\_type | Arm64 instance type of the NAT: `t4g`, `c7g`, `c8g` or `m7g` family. The default is enough for light egress; raise it for sustained throughput. | `string` | `"t4g.nano"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| instance\_id | ID of the NAT instance. |
| network\_interface\_id | ID of the NAT's network interface, the target of the default routes. It survives replacement of the instance. |
| public\_ip | Elastic IP address that private traffic leaves from, for allow-lists at the destination. |
| security\_group\_id | ID of the NAT's security group. |
<!-- END_TF_DOCS -->
