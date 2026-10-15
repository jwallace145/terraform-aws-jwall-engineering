# tfstate/write

Read and write access to Terraform state, for `terraform apply`. Reads and
writes the state object (or every object under `prefix`) and takes and
releases its `.tflock`. Only lock objects are ever deleted. Class: **write**.

Part of the [`ci-policies`](../..) catalog. Request it from a CI role module
with `policies = ["tfstate/write"]`; it is not meant to be called directly.

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
| bucket\_arn | ARN of the Terraform state bucket (output `arn` of `tfstate-bucket`). | `string` | n/a | yes |
| name | Name of the managed policy, for example `jwall-engineering-guitar-ci-plan-tfstate-read`. | `string` | n/a | yes |
| key | One stack's state key, for example `project=infra/env=prod/infra-prod.tfstate`. The policy covers this object and its `.tflock`. Set exactly one of `key` and `prefix`. | `string` | `null` | no |
| prefix | A key prefix every state object of a project lives under, for example `project=guitar/`. The policy covers every object under it. Set exactly one of `key` and `prefix`. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the managed policy. |
| name | Name of the managed policy. |
| policy | The policy document as a JSON string. |
<!-- END_TF_DOCS -->
