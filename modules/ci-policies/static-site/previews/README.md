# static-site/previews

Publish and remove pull request previews: `ListBucket` limited to
`previews/*`, and `PutObject`/`DeleteObject` on `<bucket>/previews/*`.
Class: **preview**.

Part of the [`ci-policies`](../..) catalog. Request it from a CI role module
with `policies = ["static-site/previews"]`; it is not meant to be called directly.

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
| bucket\_arn | ARN of the project's site bucket (output `arn` of the `site-bucket` module). | `string` | n/a | yes |
| name | Name of the managed policy, for example `jwall-engineering-guitar-ci-apply-static-site-deploy`. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the managed policy. |
| name | Name of the managed policy. |
| policy | The policy document as a JSON string. |
<!-- END_TF_DOCS -->
