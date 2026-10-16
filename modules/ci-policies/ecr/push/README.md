# ecr/push

Log in to ECR and push images to one repository: layer uploads and
`ecr:PutImage`, nothing that manages the repository itself. For the role that
publishes the CI tool image. Class: **write**.

Part of the [`ci-policies`](../..) catalog. Request it from a CI role module
with `policies = ["ecr/push"]`; it is not meant to be called directly.

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
