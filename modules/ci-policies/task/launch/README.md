# task/launch

Everything a consumer repository's job needs to run one task on a fresh,
dedicated instance, and nothing else. Class: **task**, requested by
[`ci-task-role`](../../../ci-task-role).

- **Launch** with `ec2:RunInstances`, only from a launch template tagged
  `Project = <project>` and `Component = task-runner`. The instance statement
  requires the `ec2:LaunchTemplate` key, so a launch without a template is
  denied. Other conditions:
  - only the `instance_types` allow-list;
  - only Amazon-owned images;
  - only the project's subnets and security groups;
  - only with the request tags `Project = <project>` and `Purpose = ci-task`;
  - no SSH key.
- **Spot or on demand.** A spot launch also authorizes a `spot-instances-request`
  (`RunAsSpot`); the instance it creates must meet every condition above. The
  CLI caps the spot price at a fraction of the on-demand price, so it reads
  prices and placement scores (`PriceTasks`).
- **Pass** only the task instance role, `<name_root>-<project>-task`, and only
  to EC2.
- **Run and stop.** `ssm:SendCommand` (`AWS-RunShellScript`) and
  `ec2:TerminateInstances` only on instances tagged `Project = <project>` and
  `Purpose = ci-task`. The production bot carries no `Purpose` tag and is out
  of reach.
- **Read the output.** The task log group `/<name_root>/<project>/tasks`, and
  the `tasks/` prefix of the results bucket `<name_root>-<project>-tasks`.

It cannot write results, change the launch template or any other resource,
or use any IAM action but `PassRole`.

Part of the [`ci-policies`](../..) catalog. Request it from a CI role module
with `policies = ["task/launch"]` and
`policy_inputs = { task = { instance_types = [...] } }`.

## Known gaps

| Statement | Why it is `*` |
|---|---|
| `DescribeTasks` (`ec2:DescribeInstances`, `ec2:DescribeInstanceTypes`, `ec2:DescribeSubnets`, `ec2:DescribeLaunchTemplates`, `ssm:DescribeInstanceInformation`) | No resource-level support. Finds the template, the subnets and the task instances, and checks the agent is online. |
| `FollowCommands` (`ssm:GetCommandInvocation`, `ssm:ListCommandInvocations`) | No resource-level support. Read-only status and exit code. |
| `PriceTasks` (`ec2:DescribeSpotPriceHistory`, `ec2:GetSpotPlacementScores`, `pricing:GetProducts`) | No resource-level support. Read-only: the on-demand price the spot cap is a fraction of, the current spot price and the zones' placement scores. |

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
| instance\_types | Instance types the role may launch, for example `["c8a.xlarge", "c8a.2xlarge"]`. | `list(string)` | n/a | yes |
| name | Name of the managed policy, for example `jwall-engineering-rusty-chess-ci-task-task-launch`. | `string` | n/a | yes |
| project | Project name in kebab-case. Every resource ARN in the policy is built from `<name_root>-<project>`. | `string` | n/a | yes |
| name\_root | Prefix of resource names, in kebab-case. Roles, policies, repositories and buckets are scoped to `<name_root>-<project>-*`; parameters and log groups to `/<name_root>/<project>/*`. | `string` | `"jwall-engineering"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the managed policy. |
| name | Name of the managed policy. |
| policy | The policy document as a JSON string. |
<!-- END_TF_DOCS -->
