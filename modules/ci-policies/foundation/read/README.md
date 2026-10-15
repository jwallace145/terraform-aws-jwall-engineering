# foundation/read

Read access for the foundation stack, replacing `ReadOnlyAccess`: the state
bucket's and managed buckets' configuration (never their objects),
`<name_root>-*` roles and policies, the GitHub OIDC provider and the hosted
zone. Class: **read**.

Part of the [`ci-policies`](../..) catalog. Request it from a CI role module
with `policies = ["foundation/read"]`; it is not meant to be called directly.

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
| hosted\_zone\_arn | ARN of the hosted zone the foundation stack manages (output `arn` of `hosted-zone`). | `string` | n/a | yes |
| name | Name of the managed policy, for example `jwall-engineering-infra-ci-apply-foundation-manage`. | `string` | n/a | yes |
| oidc\_provider\_arn | ARN of the account's GitHub Actions OIDC provider. The policy may read it, so a data source can look it up. | `string` | n/a | yes |
| state\_bucket\_arn | ARN of the Terraform state bucket (output `arn` of `tfstate-bucket`). | `string` | n/a | yes |
| managed\_bucket\_patterns | Bucket name patterns the foundation stack manages. Defaults to `["<name_root>-*"]`, which covers every `site-bucket`. The policies reach the buckets themselves, never their objects. | `list(string)` | `null` | no |
| name\_root | Prefix of every role, policy and bucket the foundation stack manages, in kebab-case. | `string` | `"jwall-engineering"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the managed policy. |
| name | Name of the managed policy. |
| policy | The policy document as a JSON string. |
<!-- END_TF_DOCS -->
