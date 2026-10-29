# ci-task-role

The IAM role a consumer repository's workflows assume through GitHub OIDC
to run one task on a dedicated, ephemeral EC2 instance: launch it from the
project's task launch template, run the task through SSM Run Command, read
its output and results, and terminate it. It trusts the repository's pull
requests and its `main` branch by default and is named
`<name_root>-<project>-ci-task`. Built from
[`github-oidc-role`](../github-oidc-role) and
[`ci-policies`](../ci-policies).

## Who can assume it

The trust lists exact subjects, never globs: `repo:<repository>:pull_request`
and `repo:<repository>:ref:refs/heads/main` by default. `subjects` may
replace them, but each must be `pull_request` or `ref:refs/heads/<branch>`;
tags, environments and wildcards fail at plan time.

- **Forks cannot reach it.** GitHub issues no OIDC token to pull request
  runs from forks, so `pull_request` admits same-repository pull requests
  only.
- **Anyone who can push a branch can open a pull request** and so launch
  task instances. The role bounds what they can launch, not whether.

With `owner_id` and `repository_id` set (from `gh api users/<owner> --jq .id`
and `gh api repos/<owner>/<repo> --jq .id`), the role also trusts GitHub's
immutable subject form `repo:<owner>@<owner_id>/<name>@<repository_id>:...`.
The audience is pinned to `sts.amazonaws.com`.

## Permissions

The role has no permissions of its own. `policies` names managed policies
from the [`ci-policies`](../ci-policies) catalog; this role accepts only
task and common policies: `task/launch`, `ecr/pull`. Anything else fails at
plan time. `task/launch` can launch only from the project's launch template,
only the listed instance types, only Amazon-owned images, only into the
project's subnets and security groups, and only with `Purpose = ci-task`.
It can terminate and send commands only to instances tagged with the
project and `Purpose = ci-task`, so long-lived instances such as the bot
are out of reach. It can read no secret and change no infrastructure.

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/ci-task-role>

## Usage

```hcl
module "rusty_chess_task" {
  source  = "jwallace145/jwall-engineering/aws//modules/ci-task-role"
  version = "~> 0.12"

  project           = "rusty-chess"
  repository        = "jwallace145/rusty-chess-v2"
  owner_id          = "35950238"  # gh api users/jwallace145 --jq .id
  repository_id     = "123456789" # gh api repos/jwallace145/rusty-chess-v2 --jq .id
  oidc_provider_arn = data.aws_iam_openid_connect_provider.github.arn

  policies = ["task/launch"]
  policy_inputs = {
    task = { instance_types = ["c8a.xlarge", "c8a.2xlarge"] }
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
| policies | Managed policies to create and attach, by catalog name. This role accepts only task and common policies: `task/launch`, `ecr/pull`. | `set(string)` | n/a | yes |
| project | Project in kebab-case, for example `rusty-chess`. The role is named `<name_root>-<project>-ci-task`, and `task/launch` is scoped to the project's launch templates, network, task role and instances tagged `Project = <project>` and `Purpose = ci-task`. | `string` | n/a | yes |
| repository | GitHub repository whose workflows may assume the role, as `owner/repo`. | `string` | n/a | yes |
| name\_root | Prefix of the role and policy names, in kebab-case. The role is named `<name_root>-<project>-ci-task`. | `string` | `"jwall-engineering"` | no |
| owner\_id | Numeric GitHub ID of the repository owner (`gh api users/<owner> --jq .id`). When set together with `repository_id`, the role also trusts GitHub's immutable subject form `repo:<owner>@<owner_id>/<name>@<repository_id>:...`. | `string` | `null` | no |
| policy\_inputs | Values the requested policies are built from, one optional section per policy family. `task/launch` needs `task = { instance_types }`; `ecr/pull` needs `ecr = { repository_arn }`. The `ci-policies` module checks the shape. | `any` | `{}` | no |
| repository\_id | Numeric GitHub ID of the repository (`gh api repos/<owner>/<repo> --jq .id`). When set together with `owner_id`, the role also trusts GitHub's immutable subject form. | `string` | `null` | no |
| subjects | GitHub OIDC subjects, after `repo:<repository>:`, whose workflows may assume the role. The default trusts the repository's pull requests and its `main` branch. GitHub issues no OIDC token to pull request runs from forks, so `pull_request` admits same-repository pull requests only. Each subject is exact: `pull_request` or `ref:refs/heads/<branch>`, with no wildcards. | `list(string)` | <pre>[<br/>  "pull_request",<br/>  "ref:refs/heads/main"<br/>]</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| policy\_arns | Map of requested policy (for example `task/launch`) to the ARN of the managed policy created for it and attached to the role. |
| role\_arn | ARN of the role, for `role-to-assume` in `aws-actions/configure-aws-credentials`. |
| role\_name | Name of the role. |
<!-- END_TF_DOCS -->
