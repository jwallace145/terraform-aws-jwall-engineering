# static-site/read

Read access to one project's static site: the site bucket's configuration,
the CloudFront distributions, functions and ACM certificates tagged
`Project = <project>`, and the hosted zone. Every action is a `Get*`, `List*`
or `Describe*`. Class: **read**.

Part of the [`ci-policies`](../..) catalog. Request it from a CI role module
with `policies = ["static-site/read"]`; it is not meant to be called directly.

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

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| bucket\_arn | ARN of the project's site bucket (output `arn` of the `site-bucket` module). | `string` | n/a | yes |
| name | Name of the managed policy, for example `jwall-engineering-guitar-ci-apply-static-site-deploy`. | `string` | n/a | yes |
| project | Project name in kebab-case. Tag-scoped statements require `Project = <project>`. | `string` | n/a | yes |
| zone\_id | Route 53 hosted zone ID the project's records live in. | `string` | n/a | yes |
| name\_root | Prefix of resource names, in kebab-case. CloudFront Functions are scoped to `<name_root>-<project>-*`. | `string` | `"jwall-engineering"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the managed policy. |
| name | Name of the managed policy. |
| policy | The policy document as a JSON string. |
<!-- END_TF_DOCS -->
