# ecr/pull

Log in to ECR (`ecr:GetAuthorizationToken`, which has no resource-level
support) and pull images from one repository. Every CI role requests it to run
the CI tool image. Class: **common**, so every role accepts it.

Part of the [`ci-policies`](../..) catalog. Request it from a CI role module
with `policies = ["ecr/pull"]`; it is not meant to be called directly.

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
| name | Name of the managed policy, for example `jwall-engineering-guitar-ci-plan-ecr-pull`. | `string` | n/a | yes |
| repository\_arn | ARN of the ECR repository (output `arn` of `ecr-repository`). | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the managed policy. |
| name | Name of the managed policy. |
| policy | The policy document as a JSON string. |
<!-- END_TF_DOCS -->
