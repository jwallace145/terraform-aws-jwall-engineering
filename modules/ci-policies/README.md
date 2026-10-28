# ci-policies

The catalog of managed policies that CI roles are built from. Callers normally
do not use this module directly: [`ci-plan-role`](../ci-plan-role),
[`ci-preview-role`](../ci-preview-role) and [`ci-apply-role`](../ci-apply-role)
call it with their `policies` and `policy_inputs` and attach what it creates.

Each policy a caller requests becomes one customer-managed policy built for
that project and role, named
`<name_root>-<project>-ci-<role>-<family>-<name>`. A policy's name is also its
folder: `static-site/deploy` lives in [`static-site/deploy/`](static-site/deploy).

## Catalog

| Policy | Class | Grants | `policy_inputs` |
|---|---|---|---|
| [`tfstate/read`](tfstate/read) | read | List the state prefix, read state, write and delete only `.tflock` | `tfstate = { bucket_arn, key \| prefix }` |
| [`tfstate/write`](tfstate/write) | write | Read and write state, take and release the lock. State objects are never deleted. | `tfstate = { bucket_arn, key \| prefix }` |
| [`static-site/read`](static-site/read) | read | Read the site bucket's configuration, the project's distributions, functions and certificates, and the hosted zone | `static_site = { bucket_arn, zone_id }` |
| [`static-site/deploy`](static-site/deploy) | write | Create and manage the project's distributions, functions and certificates, change its records, publish `prod/` and `dev/` | `static_site = { bucket_arn, zone_id, record_names }` |
| [`static-site/previews`](static-site/previews) | preview | List and write `previews/*` in the site bucket | `static_site = { bucket_arn }` |
| [`foundation/read`](foundation/read) | read | Read the state bucket and managed buckets (not their objects), `<name_root>-*` roles and policies, the GitHub OIDC provider and the hosted zone | `foundation = { state_bucket_arn, hosted_zone_arn, managed_bucket_patterns? }` |
| [`foundation/manage`](foundation/manage) | write | Configure the state bucket, manage buckets matching `managed_bucket_patterns` (not their objects), manage `<name_root>-*` roles, policies and ECR repositories, change records in the hosted zone | `foundation = { state_bucket_arn, hosted_zone_arn, managed_bucket_patterns?, attachable_policy_arns? }` |
| [`ecr/pull`](ecr/pull) | common | Log in to ECR and pull images from one repository | `ecr = { repository_arn }` |
| [`ecr/push`](ecr/push) | write | Log in to ECR and push images to one repository | `ecr = { repository_arn }` |
| [`container/read`](container/read) | read | Describe EC2, read the project's instance role and policies, image repository, parameters, log groups and their events, and records bucket configuration | none |
| [`container/manage`](container/manage) | write | Create and manage the project's VPC, instance, instance role, image repository, log groups and records bucket configuration; never their objects, never parameter values | `container = { attachable_policy_arns? }` (optional) |
| [`container/release`](container/release) | release | Push images to the project's repository, write `/<name_root>/<project>/bot/*` parameters, run `AWS-RunShellScript` on instances tagged with the project and follow it | none |

`tfstate` takes exactly one of `key` (one stack's state object, for example
`project=infra/env=prod/infra-prod.tfstate`) or `prefix` (every object under a
project's prefix, for example `project=guitar/`).

Write policies grant no reads. The apply role needs the matching read policy
too, for refresh: `static-site/read` with `static-site/deploy`, and
`foundation/read` with `foundation/manage`.

## Allow-lists

`role` decides which classes may be requested. The plan and preview roles
trust `pull_request`, so code that has not been reviewed can assume them; only
the apply role, which trusts a GitHub environment, may write. The release role
trusts a consumer repository's release tags: it may ship an image and roll it
out, and nothing that reads or changes the stack.

| Role | Accepts |
|---|---|
| `plan` | read, common |
| `preview` | preview, common |
| `apply` | read, write, common |
| `release` | release, common |

`common` policies are ones every role needs in order to run at all, such as
pulling the CI tool image from ECR. They grant nothing a pull request could
misuse, which is why the preview role may have them without accepting `read`.

A request outside the allow-list, an unknown policy name, or a policy without
its `policy_inputs` section fails at plan time with a message that names the
role, the policy and what is accepted.

## How permissions are scoped

- **Tags.** CloudFront distributions, CloudFront Functions and ACM certificates
  support `aws:ResourceTag`, and their create actions support
  `aws:RequestTag`. Those statements are conditioned on `Project = <project>`.
  This only works if the project's provider sets `default_tags` from the
  `context` module, which is what puts the `Project` tag on every resource.
- **Names.** CloudFront Function ARNs embed the function name, so
  `static-site/*` is further limited to `function/<name_root>-<project>-*`.
  The `static-site` and `preview-site` modules name their functions from
  `bucket_name`, which the `context` module sets to
  `jwall-engineering-<project>`.
- **Route 53.** `static-site/deploy` limits `ChangeResourceRecordSets` to the
  hosted zone and conditions it with
  `route53:ChangeResourceRecordSetsNormalizedRecordNames`
  (`ForAllValues:StringLike`) to `record_names`, plus `_*.<name>` for each of
  them so ACM DNS validation CNAMEs can be created. Wildcards are normalised
  to `\052` as Route 53 requires.
- **S3.** Object actions are limited to exact prefixes; `ListBucket` is
  conditioned on `s3:prefix`. The `foundation/*` policies name bucket ARNs
  only and never reach objects. The default pattern `<name_root>-*` matches
  the state bucket, so a grant on `<pattern>/*` would expose every project's
  state.
- **Names and paths (`container/*`).** Roles, instance profiles, policies,
  the image repository and the records bucket are limited to
  `<name_root>-<project>` and `<name_root>-<project>-*`; parameters and log
  groups to `/<name_root>/<project>/`. EC2 is scoped by the `Project` tag:
  `aws:RequestTag/Project` on create, `aws:ResourceTag/Project` on change.
  `container/release` reaches only `/<name_root>/<project>/bot/*`, so the
  project's secret, kept beside `bot/`, is never readable by CI.
- **No `ReadOnlyAccess`.** That AWS-managed policy grants `s3:GetObject` on
  every bucket, including every project's state. `foundation/read` replaces it
  with the reads the foundation stack needs. If it misses an action, add the
  action to `foundation/read`.

### Known gaps (documented rather than silently granting `*`)

| Permission | Policy | Why it is `*` |
|---|---|---|
| `cloudfront:List*`, `acm:ListCertificates` | `static-site/read` | List actions have no resource-level or tag support. They only disclose metadata. |
| `cloudfront:Get*OriginAccessControl*`, `cloudfront:Get*CachePolicy*`, `cloudfront:GetResponseHeadersPolicy*` | `static-site/read` | Origin access controls, cache policies and response headers policies cannot be tagged and have random IDs, so they cannot be scoped to a project. |
| `cloudfront:*OriginAccessControl`, `cloudfront:*CachePolicy` | `static-site/deploy` | Same reason. The apply role can create, update and delete any OAC or custom cache policy in the account; it cannot touch distributions that are not tagged with the project. |
| `cloudfront:CreateDistribution`, `cloudfront:CreateFunction`, `acm:RequestCertificate` | `static-site/deploy` | Create actions take no resource ARN; they are conditioned on `aws:RequestTag/Project` instead. |
| `iam:ListOpenIDConnectProviders` | `foundation/read` | No resource-level support. Looking the provider up by URL lists them first. |
| `ecr:GetAuthorizationToken` | `ecr/pull`, `ecr/push` | No resource-level support. It only issues the Docker login token; what the token may pull or push is decided by the repository-scoped statements. |
| `route53:GetChange` on `change/*` | `static-site/read`, `foundation/*` | Change IDs are random; this is read-only status polling. |

`foundation/read` and `foundation/manage` also grant `s3:ListBucket` on the
state bucket. That lists every project's state keys, but does not read them.

### Known limitation: `foundation/manage` can edit `<name_root>-*` roles

The `ArnLike` allow-list on `iam:AttachRolePolicy` bounds which **managed**
policies can be attached; by default only `<name_root>-*` customer-managed
policies. It does not bound **inline** policies, trust policies or the
contents of `<name_root>-*` policies, which `foundation/manage` can create and
edit. It can also set the state bucket's policy. A role with
`foundation/manage` can therefore grant itself, or any `<name_root>-*` role,
more access. Treat a compromise of the environment that role trusts as a
compromise of the account: protect it with required reviewers and deployment
branches restricted to `main`.

## Policy descriptions are frozen

`description` on `aws_iam_policy` forces replacement. Replacing a policy
detaches it from every role that holds it until the new one is attached, and
when the role doing the apply holds it, the apply can lose its own
permissions partway through. Every leaf therefore pins its description in a
test. Describe what a policy grants in its README, never in the description.

## Adding a policy

1. Create `<family>/<name>/` with `main.tf` (one `aws_iam_policy.this`),
   `variables.tf`, `outputs.tf` (`arn`, `name`, `policy`), `versions.tf`,
   `README.md` and `tests/`. Leaves are internal, so they have no
   `examples/basic`.
2. Add `"<family>/<name>" = "<class>"` to `local.catalog` in `main.tf`.
3. Add a `module` block for it in `main.tf` and an entry in `local.created`
   in `outputs.tf`.
4. If it needs new inputs, add an optional section or attribute to
   `policy_inputs` and a validation on `policies` that requires it.
5. Add the leaf to the CI matrix in `.github/workflows/ci.yml` with
   `example: false`.

The role modules need no change.

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/ci-policies>

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
| container\_manage | ./container/manage | n/a |
| container\_read | ./container/read | n/a |
| container\_release | ./container/release | n/a |
| ecr\_pull | ./ecr/pull | n/a |
| ecr\_push | ./ecr/push | n/a |
| foundation\_manage | ./foundation/manage | n/a |
| foundation\_read | ./foundation/read | n/a |
| static\_site\_deploy | ./static-site/deploy | n/a |
| static\_site\_previews | ./static-site/previews | n/a |
| static\_site\_read | ./static-site/read | n/a |
| tfstate\_read | ./tfstate/read | n/a |
| tfstate\_write | ./tfstate/write | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| oidc\_provider\_arn | ARN of the account's GitHub Actions OIDC provider, which `foundation/read` may read. | `string` | n/a | yes |
| policies | Policies to create, from the catalog: `tfstate/read`, `tfstate/write`, `static-site/read`, `static-site/deploy`, `static-site/previews`, `foundation/read`, `foundation/manage`, `ecr/pull`, `ecr/push`, `container/read`, `container/manage`, `container/release`. Each role accepts only some of them; see the README. | `set(string)` | n/a | yes |
| project | Project in kebab-case, for example `guitar` or `infra`. Used in policy names and as the `Project` tag value static-site policies are scoped to. | `string` | n/a | yes |
| role | The CI role the policies are for: `plan`, `preview`, `apply` or `release`. It decides which policies may be requested. | `string` | n/a | yes |
| name\_root | Prefix of every policy name, in kebab-case. Policies are named `<name_root>-<project>-ci-<role>-<family>-<name>`. | `string` | `"jwall-engineering"` | no |
| policy\_inputs | Values the requested policies are built from, one optional section per policy family. `tfstate` takes `bucket_arn` and exactly one of `key` or `prefix`. `static_site` takes `bucket_arn`, plus `zone_id` for `read` and `deploy` and `record_names` for `deploy`. `foundation` takes `state_bucket_arn`, `hosted_zone_arn` and optionally `managed_bucket_patterns` and `attachable_policy_arns`. `ecr` takes `repository_arn`. `container` optionally takes `attachable_policy_arns` for `container/manage`; the `container/*` policies are otherwise built from `project` alone. | <pre>object({<br/>    tfstate = optional(object({<br/>      bucket_arn = string<br/>      key        = optional(string)<br/>      prefix     = optional(string)<br/>    }))<br/>    static_site = optional(object({<br/>      bucket_arn   = string<br/>      zone_id      = optional(string)<br/>      record_names = optional(list(string))<br/>    }))<br/>    foundation = optional(object({<br/>      state_bucket_arn        = string<br/>      hosted_zone_arn         = string<br/>      managed_bucket_patterns = optional(list(string))<br/>      attachable_policy_arns  = optional(list(string))<br/>    }))<br/>    ecr = optional(object({<br/>      repository_arn = string<br/>    }))<br/>    container = optional(object({<br/>      attachable_policy_arns = optional(list(string))<br/>    }))<br/>  })</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arns | Map of requested policy (for example `static-site/read`) to the ARN of the managed policy created for it. |
| documents | Map of requested policy to its policy document as a JSON string. |
| names | Map of requested policy to the name of the managed policy created for it. |
<!-- END_TF_DOCS -->
