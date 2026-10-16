# ci-preview-role

The IAM role a repository's pull request workflows assume through GitHub OIDC
to publish previews. It trusts `repo:<repository>:pull_request` and is named
`<name_root>-<project>-ci-preview`. Built from
[`github-oidc-role`](../github-oidc-role) and [`ci-policies`](../ci-policies).

With `owner_id` and `repository_id` set (from `gh api users/<owner> --jq .id`
and `gh api repos/<owner>/<repo> --jq .id`), the role also trusts GitHub's
immutable subject form `repo:<owner>@<owner_id>/<name>@<repository_id>:...`.
The audience is pinned to `sts.amazonaws.com`.

## Permissions

The role has no permissions of its own. `policies` names managed policies from
the [`ci-policies`](../ci-policies) catalog; each one is created for this
project and role as `<name_root>-<project>-ci-preview-<family>-<name>` and
attached. `policy_inputs` carries the values they are built from, one optional
section per policy family; only the sections the requested policies need are
required. The catalog README lists every policy, what it grants and the inputs
it needs.

This role accepts only preview and common policies: `static-site/previews`,
`ecr/pull`. Anything else fails at plan time. Any pull request branch in the
repository can assume the role, so it must reach nothing but `previews/`.

`policy_inputs` is passed through as `any` and typed by `ci-policies`. A
section or attribute it does not know is dropped silently, so a misspelt
optional attribute (for example `managed_bucket_pattern`) falls back to its
default.

Upgrading from `site-ci-roles` or `infra-ci-roles`: see
[Migrating CI roles](../../README.md#migrating-ci-roles-from-05x) in the root
README.

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/ci-preview-role>

## Usage

```hcl
module "ci_preview" {
  source  = "jwallace145/jwall-engineering/aws//modules/ci-preview-role"
  version = "~> 0.6"

  project           = "guitar"
  repository        = "jwallace145/guitar"
  owner_id          = "35950238"  # gh api users/jwallace145 --jq .id
  repository_id     = "123456789" # gh api repos/jwallace145/guitar --jq .id
  oidc_provider_arn = data.aws_iam_openid_connect_provider.github.arn

  policies = ["static-site/previews"]

  policy_inputs = {
    static_site = { bucket_arn = module.site_bucket.arn }
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11 |
| aws | ~> 6.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| policies | ../ci-policies | n/a |
| role | ../github-oidc-role | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| oidc\_provider\_arn | ARN of the account's GitHub Actions OIDC provider (`token.actions.githubusercontent.com`). | `string` | n/a | yes |
| policies | Managed policies to create and attach, by catalog name. This role accepts only preview and common policies: `static-site/previews`, `ecr/pull`. | `set(string)` | n/a | yes |
| project | Project in kebab-case, for example `guitar` or `infra`. The role is named `<name_root>-<project>-ci-preview`, and static-site policies are scoped to resources tagged `Project = <project>`. | `string` | n/a | yes |
| repository | GitHub repository whose workflows may assume the role, as `owner/repo`. | `string` | n/a | yes |
| name\_root | Prefix of the role and policy names, in kebab-case. The role is named `<name_root>-<project>-ci-preview`. | `string` | `"jwall-engineering"` | no |
| owner\_id | Numeric GitHub ID of the repository owner (`gh api users/<owner> --jq .id`). When set together with `repository_id`, the role also trusts GitHub's immutable subject form `repo:<owner>@<owner_id>/<name>@<repository_id>:...`. | `string` | `null` | no |
| policy\_inputs | Values the requested policies are built from, one optional section per policy family: `tfstate = { bucket_arn, key or prefix }`, `static_site = { bucket_arn, zone_id?, record_names? }`, `foundation = { state_bucket_arn, hosted_zone_arn, managed_bucket_patterns?, attachable_policy_arns? }`. Only the sections the requested policies need are required. The `ci-policies` module checks the shape. | `any` | `{}` | no |
| repository\_id | Numeric GitHub ID of the repository (`gh api repos/<owner>/<repo> --jq .id`). When set together with `owner_id`, the role also trusts GitHub's immutable subject form. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| policy\_arns | Map of requested policy (for example `static-site/read`) to the ARN of the managed policy created for it and attached to the role. |
| role\_arn | ARN of the role, for `role-to-assume` in `aws-actions/configure-aws-credentials`. |
| role\_name | Name of the role. |
<!-- END_TF_DOCS -->
