# container/schedule

What the apply role needs for a bot instance's running hours (the
`container-instance` module's `schedule`): create, update and delete the
EventBridge Scheduler schedules named `<name_root>-<project>-*` in the default
group, and pass the project's `<name_root>-<project>-*-scheduler` role to
`scheduler.amazonaws.com`. Class: **write**.

The scheduler role itself is created with `container/manage`, which already
manages every `<name_root>-<project>-*` role. Reading the schedules
(`scheduler:GetSchedule`) is in `container/read`. This is its own policy
because `container/manage` is close to the 6,144-character limit of a managed
policy.

Part of the [`ci-policies`](../..) catalog. Request it from a CI role module
with `policies = ["container/schedule"]`; it is not meant to be called
directly.

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
| name | Name of the managed policy, for example `jwall-engineering-rusty-chess-ci-apply-container-schedule`. | `string` | n/a | yes |
| project | Project name in kebab-case. Every resource ARN in the policy is built from `<name_root>-<project>`. | `string` | n/a | yes |
| name\_root | Prefix of resource names, in kebab-case. Roles, policies, repositories and buckets are scoped to `<name_root>-<project>-*`; parameters and log groups to `/<name_root>/<project>/*`. | `string` | `"jwall-engineering"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the managed policy. |
| name | Name of the managed policy. |
| policy | The policy document as a JSON string. |
<!-- END_TF_DOCS -->
