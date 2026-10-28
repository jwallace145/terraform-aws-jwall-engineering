# container/release

Everything a release of a bot project needs, and nothing else: log in to
ECR and push images to the project's repository, write the bot's own
parameters under `/<name_root>/<project>/bot/` (the desired version), run
`AWS-RunShellScript` on instances tagged `Project = <project>` (the
on-instance reconciler) and follow the command. Class: **release**.

It cannot manage any resource, cannot read or write the project's secret
(which lives outside `bot/`), and cannot touch S3 or IAM. It is requested
by [`ci-release-role`](../../../ci-release-role), which trusts the
consumer repository's release tags.

Part of the [`ci-policies`](../..) catalog. Request it from a CI role module
with `policies = ["container/release"]`; it is not meant to be called
directly.

## Known gaps

| Statement | Why it is `*` |
|---|---|
| `GetEcrAuthorizationToken` (`ecr:GetAuthorizationToken`) | No resource-level support. It only issues the Docker login token; what the token may push is decided by `PushImages`. |
| `FollowCommands` (`ssm:GetCommandInvocation`, `ssm:ListCommandInvocations`, `ssm:ListCommands`) | No resource-level support. Read-only status of commands. |
| `DescribeInstances` (`ec2:DescribeInstances`, `ssm:DescribeInstanceInformation`) | No resource-level support. How the CLI finds the instance by its `Project` and `Component` tags and checks its agent is online. |

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
| name | Name of the managed policy, for example `jwall-engineering-rusty-chess-ci-release-container-release`. | `string` | n/a | yes |
| project | Project name in kebab-case. Every resource ARN in the policy is built from `<name_root>-<project>`. | `string` | n/a | yes |
| name\_root | Prefix of resource names, in kebab-case. Roles, policies, repositories and buckets are scoped to `<name_root>-<project>-*`; parameters and log groups to `/<name_root>/<project>/*`. | `string` | `"jwall-engineering"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the managed policy. |
| name | Name of the managed policy. |
| policy | The policy document as a JSON string. |
<!-- END_TF_DOCS -->
