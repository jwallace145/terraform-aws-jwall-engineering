# compute/read

Read what the stack of a project with no bot needs for `terraform plan` and
refresh: describe EC2 (VPC, subnets, security groups, launch templates), look
up the public Amazon Linux AMI parameters, read the project's instance role
and policies, and read its log groups under `/<name_root>/<project>/` and
their events. Class: **read**.

It is the network, instance role and log group part of
[`container/read`](../../container/read): it reads no image repository, no
project parameters and no bucket. Pair it with [`compute/manage`](../manage) on
the apply role.

Part of the [`ci-policies`](../..) catalog. Request it from a CI role module
with `policies = ["compute/read"]`; it is not meant to be called directly.

## Known gaps

| Statement | Why it is `*` |
|---|---|
| `DescribeEc2` (`ec2:Describe*`) | EC2 describe actions have no resource-level support. They disclose metadata about every VPC and instance in the account. |
| `DescribeLogGroups` (`logs:DescribeLogGroups`) | No resource-level support. Lists log group names only. |

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
| [aws_iam_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Name of the managed policy, for example `jwall-engineering-rusty-chess-ci-plan-compute-read`. | `string` | n/a | yes |
| project | Project name in kebab-case. Every resource ARN in the policy is built from `<name_root>-<project>`. | `string` | n/a | yes |
| name\_root | Prefix of resource names, in kebab-case. Roles, policies, repositories and buckets are scoped to `<name_root>-<project>-*`; parameters and log groups to `/<name_root>/<project>/*`. | `string` | `"jwall-engineering"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the managed policy. |
| name | Name of the managed policy. |
| policy | The policy document as a JSON string. |
<!-- END_TF_DOCS -->
