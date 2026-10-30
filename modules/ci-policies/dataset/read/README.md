# dataset/read

Read the configuration of a project's dataset buckets, for `terraform plan`
and refresh. It never reads the data. The writers' inline policies are on
roles already readable through [`container/read`](../../container/read).
Class: **read**.

Part of the [`ci-policies`](../..) catalog. Request it from a CI role module
with `policies = ["dataset/read"]` and
`policy_inputs = { dataset = { bucket_names = [...] } }`; it is not meant
to be called directly.

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

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| bucket\_names | The project's dataset buckets, each named `<name_root>-<project>-<dataset>`. | `list(string)` | n/a | yes |
| name | Name of the managed policy, for example `jwall-engineering-rusty-chess-ci-plan-dataset-read`. | `string` | n/a | yes |
| project | Project name in kebab-case. | `string` | n/a | yes |
| name\_root | Prefix of resource names, in kebab-case. Dataset buckets must be named `<name_root>-<project>-*`. | `string` | `"jwall-engineering"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the managed policy. |
| name | Name of the managed policy. |
| policy | The policy document as a JSON string. |
<!-- END_TF_DOCS -->
