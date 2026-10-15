# infra-ci-roles

The plan and apply roles for a foundation stack repository, the repo that owns
the account-level singletons: the state bucket, the hosted zone, and every
project's bucket and CI roles. Both roles are instances of
[`github-oidc-role`](../github-oidc-role) (`module.plan` and `module.apply`).

| Role | Trusted `sub` | Permissions |
|---|---|---|
| `<name_root>-<project>-ci-plan` | `repo:<repository>:pull_request` | `ReadOnlyAccess`; inline `<role>-state`: list its own state prefix, read its own state and lock, write only its own `.tflock` |
| `<name_root>-<project>-ci-apply` | `repo:<repository>:environment:<apply_environment>` | `ReadOnlyAccess`; inline `<role>-manage`: everything the foundation stack manages, scoped as below |

With `owner_id` and `repository_id` set, both roles also trust GitHub's
immutable subject form `repo:<owner>@<owner_id>/<name>@<repository_id>:...`.

## Why the apply role is scoped the way it is

The apply role is the highest-privilege identity in the setup because it
creates IAM roles. It is constrained so that a compromised apply environment
cannot reach beyond the `<name_root>-*` namespace or attach powerful managed
policies. It is not a complete escalation barrier, see the limitation below.

- IAM actions are limited to roles and policies named `<name_root>-*`. It
  cannot touch any other principal. It has no permissions on the GitHub OIDC
  provider, which the foundation stack does not own; `ReadOnlyAccess` lets it
  read the provider.
- `iam:AttachRolePolicy` carries an `ArnLike` condition on `iam:PolicyARN`.
  By default it only accepts `ReadOnlyAccess` or a `<name_root>-*`
  customer-managed policy, so it cannot hand out `AdministratorAccess` to a
  role it creates. Override the list with `attachable_policy_arns`.
- S3 access is limited to the state bucket's configuration and to buckets
  matching `managed_bucket_patterns`, which defaults to `<name_root>-*`. An
  explicit `Deny` blocks `s3:DeleteBucket` and `s3:DeleteBucketPolicy` on the
  state bucket, and the role can reach no state object except its own.
- Route 53 access is limited to `hosted_zone_arn`. It cannot create or delete
  zones.
- It carries `ReadOnlyAccess` so that refresh and drift detection work across
  the account.

Both roles trust only `repository`, through the OIDC provider, with the
audience pinned to `sts.amazonaws.com`.

### Known limitation: the apply role can edit itself

The `ArnLike` allow-list bounds which **managed** policies can be attached. It
does not bound **inline** policies or trust policies. `ManageOrganisationRoles`
grants `iam:PutRolePolicy` and `iam:UpdateAssumeRolePolicy` on every
`<name_root>-*` role, and that includes the apply role itself and every role
from `site-ci-roles`. A compromised apply environment could therefore write a
broader inline policy onto one of them. The scoping above limits where the
apply role can act, but a compromise of the apply environment should be treated
as a compromise of the account. Protect the GitHub environment accordingly:
required reviewers, and deployment branches restricted to `main`.

This permission set matches the roles this module was lifted from, so it is
kept as it is to make adopting the module a no-change plan. Tightening it, for
example with an explicit `Deny` on these actions against the apply role or a
permissions boundary, is a separate change.

## Adopting existing roles

The resource addresses are stable, so roles that already exist can be moved
under this module. For roles named `ci_plan` and `ci_apply`:

```hcl
moved {
  from = aws_iam_role.ci_plan
  to   = module.infra_ci_roles.module.plan.aws_iam_role.this
}

moved {
  from = aws_iam_role_policy.ci_plan_state
  to   = module.infra_ci_roles.module.plan.aws_iam_role_policy.this["state"]
}

moved {
  from = aws_iam_role_policy_attachment.ci_plan_readonly
  to   = module.infra_ci_roles.module.plan.aws_iam_role_policy_attachment.this["arn:aws:iam::aws:policy/ReadOnlyAccess"]
}
```

The apply role follows the same pattern with `module.apply` and the policy
key `manage`.

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/infra-ci-roles>

## Usage

```hcl
module "infra_ci_roles" {
  source  = "jwallace145/jwall-engineering/aws//modules/infra-ci-roles"
  version = "~> 0.4"

  repository        = "jwallace145/jwall-engineering-infra"
  owner_id          = "35950238"   # gh api users/jwallace145 --jq .id
  repository_id     = "1420037633" # gh api repos/jwallace145/jwall-engineering-infra --jq .id
  oidc_provider_arn = data.aws_iam_openid_connect_provider.github.arn
  state_bucket_arn  = module.state_bucket.arn
  state_key         = "project=infra/env=prod/infra-prod.tfstate"
  hosted_zone_arn   = module.zone.arn
}
```

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

| Name | Source | Version |
| ---- | ------ | ------- |
| apply | ../github-oidc-role | n/a |
| plan | ../github-oidc-role | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| hosted\_zone\_arn | ARN of the hosted zone the apply role may change records in (output `arn` of `hosted-zone`). | `string` | n/a | yes |
| oidc\_provider\_arn | ARN of the account's GitHub Actions OIDC provider (`token.actions.githubusercontent.com`). This module does not manage the provider and grants no permissions on it. | `string` | n/a | yes |
| repository | GitHub repository of the foundation stack, as `owner/repo`. Both roles trust only this repository. | `string` | n/a | yes |
| state\_bucket\_arn | ARN of the Terraform state bucket (output `arn` of `tfstate-bucket`). | `string` | n/a | yes |
| state\_key | This stack's own state key, for example `project=infra/env=prod/infra-prod.tfstate`. Must match the backend configuration. The roles may only touch this object and its `.tflock`. | `string` | n/a | yes |
| apply\_environment | GitHub environment whose jobs may assume the apply role. The apply role trusts `environment:<apply_environment>`; the plan role trusts `pull_request`. | `string` | `"prod"` | no |
| attachable\_policy\_arns | Managed policy ARN patterns the apply role may attach with `iam:AttachRolePolicy` (an `ArnLike` allow-list). Defaults to `ReadOnlyAccess` and the account's `<name_root>-*` customer-managed policies. | `list(string)` | `null` | no |
| managed\_bucket\_patterns | Bucket name patterns the apply role gets `s3:*` on, for the buckets and their objects. Defaults to `["<name_root>-*"]`, which covers every `site-bucket`. | `list(string)` | `null` | no |
| name\_root | Prefix of every role, policy and bucket the apply role may manage, in kebab-case. Roles are named `<name_root>-<project>-ci-{plan,apply}`. | `string` | `"jwall-engineering"` | no |
| owner\_id | Numeric GitHub ID of the repository owner (`gh api users/<owner> --jq .id`). When set together with `repository_id`, the roles also trust GitHub's immutable subject form `repo:<owner>@<owner_id>/<name>@<repository_id>:...`. | `string` | `null` | no |
| project | Project of the foundation stack in kebab-case, for example `infra`. Roles are named `<name_root>-<project>-ci-{plan,apply}`. | `string` | `"infra"` | no |
| repository\_id | Numeric GitHub ID of the repository (`gh api repos/<owner>/<repo> --jq .id`). When set together with `owner_id`, the roles also trust GitHub's immutable subject form. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| apply\_role\_arn | ARN of `<name_root>-<project>-ci-apply`, assumed by jobs in the `apply_environment` GitHub environment to run `terraform apply`. |
| apply\_role\_name | Name of the apply role. |
| plan\_role\_arn | ARN of `<name_root>-<project>-ci-plan`, assumed by `pull_request` workflows to run `terraform plan`. |
| plan\_role\_name | Name of the plan role. |
<!-- END_TF_DOCS -->
