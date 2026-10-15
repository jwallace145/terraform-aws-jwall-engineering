# github-oidc-role

One IAM role that GitHub Actions assumes through OIDC. It is the building
block that `site-ci-roles` and `infra-ci-roles` compose, so the trust-policy
logic, including the immutable subject form, exists in exactly one place.

## Trust policy

The role has a single trust statement that allows
`sts:AssumeRoleWithWebIdentity` from `oidc_provider_arn`. The statement has
two `StringEquals` conditions:

- `token.actions.githubusercontent.com:aud` is `sts.amazonaws.com`.
- `token.actions.githubusercontent.com:sub` is one of the subjects built from
  every prefix and every suffix in `subjects`.

GitHub issues `sub` in one of two shapes depending on the repository's OIDC
settings. The classic form is `repo:<owner>/<name>:...` and the immutable form
is `repo:<owner>@<owner_id>/<name>@<repository_id>:...`. The classic prefix is
always trusted. Pass `owner_id` and `repository_id` to trust the immutable
prefix as well.

| `subjects` | IDs set | Trusted `sub` values |
|---|---|---|
| `["pull_request"]` | no | `repo:owner/repo:pull_request` |
| `["pull_request"]` | yes | `repo:owner/repo:pull_request`, `repo:owner@1/repo@2:pull_request` |
| `["environment:prod"]` | yes | `repo:owner/repo:environment:prod`, `repo:owner@1/repo@2:environment:prod` |

The statement's `Sid` defaults to `GitHubOidc`. Set `trust_statement_sid` to
the Sid an existing role already uses to adopt it without a trust-policy diff.

## Permissions

- `inline_policies` maps a suffix to a policy document object. Each entry
  becomes `aws_iam_role_policy.this["<key>"]`, named `<name>-<key>`, with the
  document passed through `jsonencode()` so the policy is known at plan time.
- `managed_policy_arns` lists managed policies. Each becomes
  `aws_iam_role_policy_attachment.this["<arn>"]`.

These resource addresses are part of the module's contract. Callers adopting
existing roles write `moved` blocks against them.

## Tags

The module sets `Component = <component>`. All other tags come from the
caller's provider `default_tags`. Set `name_tag` to also add a `Name` tag,
which lets a caller adopt an existing role that already carries one without a
tag change.

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/github-oidc-role>

## Usage

```hcl
module "plan_role" {
  source  = "jwallace145/jwall-engineering/aws//modules/github-oidc-role"
  version = "~> 0.4"

  name              = "jwall-engineering-infra-ci-plan"
  description       = "terraform plan for jwallace145/jwall-engineering-infra pull requests (read-only)"
  repository        = "jwallace145/jwall-engineering-infra"
  owner_id          = "35950238"   # gh api users/jwallace145 --jq .id
  repository_id     = "1420037633" # gh api repos/jwallace145/jwall-engineering-infra --jq .id
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  subjects          = ["pull_request"]
  component         = "ci"

  managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]

  inline_policies = {
    state = {
      Version   = "2012-10-17"
      Statement = [{ Sid = "ReadOwnState", Effect = "Allow", Action = "s3:GetObject", Resource = "arn:aws:s3:::bucket/key" }]
    }
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

| Name | Version |
| ---- | ------- |
| aws | ~> 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| component | Value of the `Component` tag on the role. | `string` | n/a | yes |
| description | IAM role description, for example `terraform plan for owner/repo pull requests (read-only)`. | `string` | n/a | yes |
| name | IAM role name. Inline policies are named `<name>-<key>`. | `string` | n/a | yes |
| oidc\_provider\_arn | ARN of the account's GitHub Actions OIDC provider (`token.actions.githubusercontent.com`). | `string` | n/a | yes |
| repository | GitHub repository whose workflows may assume the role, as `owner/repo`. | `string` | n/a | yes |
| subjects | Subject suffixes the role trusts, appended to `repo:<repository>:` (and to the immutable prefix when the IDs are set). For example `["pull_request"]` or `["environment:prod"]`. | `list(string)` | n/a | yes |
| inline\_policies | Inline policies to attach, keyed by suffix. Each value is an IAM policy document object (`{ Version = "2012-10-17", Statement = [...] }`) that becomes `aws_iam_role_policy.this[<key>]` named `<name>-<key>` with `policy = jsonencode(value)`. | `any` | `{}` | no |
| managed\_policy\_arns | ARNs of managed policies to attach. Each becomes `aws_iam_role_policy_attachment.this[<arn>]`. | `list(string)` | `[]` | no |
| max\_session\_duration | Maximum session duration in seconds for the role. | `number` | `3600` | no |
| name\_tag | Value of the `Name` tag. Left `null`, the module sets no `Name` tag and `Component` is the only tag it adds. | `string` | `null` | no |
| owner\_id | Numeric GitHub ID of the repository owner (`gh api users/<owner> --jq .id`). When set together with `repository_id`, the role also trusts GitHub's immutable subject form `repo:<owner>@<owner_id>/<name>@<repository_id>:...`. | `string` | `null` | no |
| repository\_id | Numeric GitHub ID of the repository (`gh api repos/<owner>/<repo> --jq .id`). When set together with `owner_id`, the role also trusts GitHub's immutable subject form. | `string` | `null` | no |
| trust\_statement\_sid | Sid of the single trust-policy statement. Only the trust policy JSON changes with it; set it to the Sid an existing role already uses to adopt the role without a diff. | `string` | `"GitHubOidc"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the role, for `role-to-assume` in `aws-actions/configure-aws-credentials`. |
| id | ID of the role (the same as its name). |
| name | Name of the role. |
<!-- END_TF_DOCS -->
