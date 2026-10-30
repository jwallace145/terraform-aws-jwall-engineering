# terraform-aws-jwall-engineering

[![Terraform Registry](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fregistry.terraform.io%2Fv1%2Fmodules%2Fjwallace145%2Fjwall-engineering%2Faws&query=%24.version&prefix=v&label=registry&logo=terraform&color=7B42BC)](https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest)
[![GitHub release](https://img.shields.io/github/v/release/jwallace145/terraform-aws-jwall-engineering?label=release)](https://github.com/jwallace145/terraform-aws-jwall-engineering/releases/latest)
[![CI](https://github.com/jwallace145/terraform-aws-jwall-engineering/actions/workflows/ci.yml/badge.svg)](https://github.com/jwallace145/terraform-aws-jwall-engineering/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Registry:** <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest>

Versioned Terraform modules for the jwall-engineering static sites and the
account-level foundation they run on. Public,
MIT-licensed, and holds **no state**: this repo only publishes modules. The
`jwall-engineering-infra` repo and the individual project repos consume them.

## Root module: the site stack

The root module is what a project repository deploys: the production
distribution served from `<bucket>/prod`, an optional dev distribution served
from `<bucket>/dev`, and the `pr-<n>.preview.<domain>` distribution served from
`<bucket>/previews/pr-<n>`.

```hcl
module "site" {
  source  = "jwallace145/jwall-engineering/aws"
  version = "~> 0.2"

  bucket_name                 = module.context.bucket_name
  bucket_regional_domain_name = "${module.context.bucket_name}.s3.us-east-1.amazonaws.com"
  domain_name                 = "guitar.jwall.engineering"
  dev_domain_name             = "dev.guitar.jwall.engineering" # optional
  zone_id                     = "Z0123456789ABCDEFGHIJ"
}
```

The bucket and the CI roles come from the infra repo (`site-bucket`,
`ci-plan-role`, `ci-preview-role` and `ci-apply-role` submodules).

Site repositories no longer call this root module themselves. The
`jwall-engineering-sites` CLI in
[jwall-engineering-infra](https://github.com/jwallace145/jwall-engineering-infra)
renders it for each site from one `jwall-engineering-sites.yaml`, pins the
version in its `config.yaml`, and runs it from a versioned image through
reusable workflows. Bumping this library for every site is therefore one
`chore(deps)` PR there, followed by an image release. Calling the modules
directly still works for anything that is not a jwall.engineering site. Each submodule can also be used on its own.

## Submodules

| Module | Used by | Creates |
|---|---|---|
| [`context`](modules/context) ([registry](https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/context)) | everyone | Nothing. Derives `tags`, `name_prefix` and `bucket_name` from `project`, `environment` and `repository`. Feed `tags` into the provider's `default_tags`. |
| [`site-bucket`](modules/site-bucket) ([registry](https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/site-bucket)) | infra repo, one per project | The hardened `jwall-engineering-<project>` S3 bucket with lifecycle rules and a CloudFront-only bucket policy. |
| [`tfstate-bucket`](modules/tfstate-bucket) ([registry](https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/tfstate-bucket)) | infra repo, once per account | The versioned, encrypted, TLS-only S3 bucket that holds every stack's state. Locking uses the native `.tflock` object. |
| [`hosted-zone`](modules/hosted-zone) ([registry](https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/hosted-zone)) | infra repo, once per domain | A Route 53 hosted zone and its zone-level CAA and TXT records (domain verification). Project repos own the records inside it. |
| [`github-oidc-role`](modules/github-oidc-role) ([registry](https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/github-oidc-role)) | the CI role modules, any stack that needs one CI role | One IAM role trusted by GitHub Actions through OIDC, in both the classic and the immutable `sub` form, with inline and managed policies. |
| [`ci-plan-role`](modules/ci-plan-role) ([registry](https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/ci-plan-role)) | infra repo, one per project | The `<name_root>-<project>-ci-plan` role, trusted by `pull_request`, with the **read** policies it requests from `ci-policies`. |
| [`ci-preview-role`](modules/ci-preview-role) ([registry](https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/ci-preview-role)) | infra repo, one per site project | The `<name_root>-<project>-ci-preview` role, trusted by `pull_request`, with the **preview** policies it requests from `ci-policies`. |
| [`ci-apply-role`](modules/ci-apply-role) ([registry](https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/ci-apply-role)) | infra repo, one per project | The `<name_root>-<project>-ci-apply` role, trusted by a GitHub environment, with the **read** and **write** policies it requests from `ci-policies`. |
| [`ci-release-role`](modules/ci-release-role) ([registry](https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/ci-release-role)) | infra repo, one per bot project | The `<name_root>-<project>-ci-release` role, trusted only by the repository's release tags, with the **release** policies it requests from `ci-policies`. |
| [`ci-task-role`](modules/ci-task-role) ([registry](https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/ci-task-role)) | infra repo, one per project that runs remote tasks | The `<name_root>-<project>-ci-task` role, trusted only by the repository's pull requests and `main`, with the **task** policies it requests from `ci-policies`. |
| [`ci-policies`](modules/ci-policies) ([registry](https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/ci-policies)) | the CI role modules | The catalog of managed policies (`tfstate/*`, `static-site/*`, `foundation/*`, `ecr/*`, `container/*`, `task/*`, `dataset/*`) a CI role can request, built per project and role, and the per-role allow-lists. |
| [`ecr-repository`](modules/ecr-repository) ([registry](https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/ecr-repository)) | infra repo, once per image | A private ECR repository with immutable tags, scan on push, AES256 and a lifecycle policy that keeps the newest release images and expires untagged ones. |
| [`private-bucket`](modules/private-bucket) ([registry](https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/private-bucket)) | infra repo bot stacks, one per project | A versioned, encrypted, TLS-only, never-destroyed S3 bucket for durable project data such as game records. |
| [`dataset-bucket`](modules/dataset-bucket) ([registry](https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/dataset-bucket)) | infra repo bot stacks, one per dataset | A kept-forever, unversioned, Intelligent-Tiering, TLS-only, never-destroyed S3 bucket for append-only datasets such as training data, with add-only access for writer roles under one prefix. |
| [`vpc`](modules/vpc) ([registry](https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/vpc)) | infra repo bot stacks, one per project | A VPC with DNS on, public subnets in the given AZs, an internet gateway and one public route table. No NAT, no private subnets. |
| [`container-instance`](modules/container-instance) ([registry](https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/container-instance)) | infra repo bot stacks, one per project | One EC2 instance (a pinned AL2023 image, or the latest by public SSM parameter) that runs one image tag from ECR with a graceful on-box reconciler driven by SSM parameters and Run Command, an instance role, a no-ingress security group, a CloudWatch log group and versioned S3 game-record shipping. |
| [`task-runner`](modules/task-runner) ([registry](https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/task-runner)) | infra repo bot stacks, one per project that runs remote tasks | A launch template for ephemeral on-demand CI task instances (lifetime guard, shutdown terminates, IMDSv2, rustup setup), a write-only instance role, a no-ingress security group and a CloudWatch log group. Launches nothing: the CLI does. |
| [`static-site`](modules/static-site) ([registry](https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/static-site)) | project repos, one per environment | ACM cert, OAC, CloudFront distribution, index-rewrite function and Route 53 aliases for `<domain>` served from `<bucket>/<origin_path>`. |
| [`preview-site`](modules/preview-site) ([registry](https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/preview-site)) | project repos, one per project | Wildcard cert and distribution for `pr-<n>.preview.<domain>` served from `<bucket>/previews/pr-<n>/`. |

## Usage

Published on the [Terraform Registry](https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest)
as `jwallace145/jwall-engineering/aws`. The root module is the site stack; the
sixteen modules under `modules/` are published as
[submodules](https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules).
Pin a version:

```hcl
module "context" {
  source  = "jwallace145/jwall-engineering/aws//modules/context"
  version = "~> 0.1"

  project     = "guitar"
  environment = "prod"
  repository  = "jwallace145/guitar"
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = module.context.tags
  }
}
```

The git source also works and pins to the same release tags:

```hcl
source = "git::https://github.com/jwallace145/terraform-aws-jwall-engineering.git//modules/context?ref=v0.1.0"
```

Every module targets `us-east-1`, requires Terraform `>= 1.11` and the AWS
provider `~> 6.0`, never configures a provider, and tags its resources with
`Component = "<module-name>"`. Each module's README has the full input and
output reference generated by terraform-docs.

### Tagging

Every resource in every stack built from these modules carries the same tag
set, which is what makes per-project and per-component cost reports possible:

| Tag | Set by | Example |
|---|---|---|
| `Organization` | the caller's `default_tags`, from [`context`](modules/context) | `jwall-engineering` |
| `Project` | the caller's `default_tags`, from `context` | `rusty-chess` |
| `Environment` | the caller's `default_tags`, from `context` | `prod` |
| `Repository` | the caller's `default_tags`, from `context` | `jwallace145/rusty-chess-v2` |
| `ManagedBy` | the caller's `default_tags`, from `context` | `jwall-engineering-infra` |
| `Owner` | the caller's `default_tags`, from `context` | `jwallace145` |
| `Component` | the module | `container-instance` |
| `Name` | the module, where the resource has a name | `jwall-engineering-rusty-chess-bot` |

Modules take no tag maps: the six organisation tags come only from the
provider's `default_tags`, so a stack cannot forget one. Resources that do
not inherit `default_tags` on their own are tagged explicitly by the module
and pinned by a test; today that is the EC2 root volume in
[`container-instance`](modules/container-instance) and the task instances
and volumes in [`task-runner`](modules/task-runner). Several CI policies rely
on the tags too: EC2, CloudFront and ACM permissions are scoped by
`Project`.

Ephemeral CI task instances and their volumes carry one more tag,
`Purpose = ci-task`, set by the [`task-runner`](modules/task-runner)
launch template and by the CLI at launch. The `task/launch` CI policy
requires it on every launch and can terminate or run commands only on
instances that carry it, so long-lived instances such as a bot are out of
reach. It also separates task spend from the rest of a project's spend.

To report on cost by these tags, activate `Organization`, `Project`,
`Environment`, `Component`, `Purpose` and `Owner` as
[cost allocation tags](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/activating-tags.html)
in the Billing console once, after the first resources carrying them exist.

## Migrating CI roles from 0.5.x

0.6.0 replaces `site-ci-roles` and `infra-ci-roles` with `ci-plan-role`,
`ci-preview-role` and `ci-apply-role`. The roles keep their names, so their
ARNs and every workflow's `role-to-assume` stay the same. Each role moves to
`module.<name>.module.role.aws_iam_role.this`; its inline policies are
replaced by managed policies from `ci-policies`.

For a project previously created with `module "site_ci_roles"`:

```hcl
module "ci_plan" {
  source  = "jwallace145/jwall-engineering/aws//modules/ci-plan-role"
  version = "~> 0.6"

  project           = "guitar"
  repository        = "jwallace145/guitar"
  oidc_provider_arn = local.oidc_provider_arn
  policies          = ["tfstate/read", "static-site/read"]
  policy_inputs = {
    tfstate     = { bucket_arn = module.state_bucket.arn, prefix = "project=guitar/" }
    static_site = { bucket_arn = module.site_bucket.arn, zone_id = module.zone.zone_id }
  }
}

module "ci_preview" {
  source  = "jwallace145/jwall-engineering/aws//modules/ci-preview-role"
  version = "~> 0.6"

  project           = "guitar"
  repository        = "jwallace145/guitar"
  oidc_provider_arn = local.oidc_provider_arn
  policies          = ["static-site/previews"]
  policy_inputs = {
    static_site = { bucket_arn = module.site_bucket.arn }
  }
}

module "ci_apply" {
  source  = "jwallace145/jwall-engineering/aws//modules/ci-apply-role"
  version = "~> 0.6"

  project           = "guitar"
  repository        = "jwallace145/guitar"
  oidc_provider_arn = local.oidc_provider_arn
  policies          = ["tfstate/write", "static-site/read", "static-site/deploy"]
  policy_inputs = {
    tfstate = { bucket_arn = module.state_bucket.arn, prefix = "project=guitar/" }
    static_site = {
      bucket_arn   = module.site_bucket.arn
      zone_id      = module.zone.zone_id
      record_names = ["guitar.jwall.engineering", "dev.guitar.jwall.engineering", "*.preview.guitar.jwall.engineering"]
    }
  }
}

moved {
  from = module.site_ci_roles.module.role["plan"].aws_iam_role.this
  to   = module.ci_plan.module.role.aws_iam_role.this
}

moved {
  from = module.site_ci_roles.module.role["preview"].aws_iam_role.this
  to   = module.ci_preview.module.role.aws_iam_role.this
}

moved {
  from = module.site_ci_roles.module.role["apply"].aws_iam_role.this
  to   = module.ci_apply.module.role.aws_iam_role.this
}
```

For the foundation stack, previously `module "infra_ci_roles"`, request
`["tfstate/read", "foundation/read"]` for plan and
`["tfstate/write", "foundation/read", "foundation/manage"]` for apply, with
`tfstate = { bucket_arn, key = "<the stack's state key>" }` and
`foundation = { state_bucket_arn, hosted_zone_arn }` (plus
`managed_bucket_patterns` or `attachable_policy_arns` if you overrode them),
and move the roles:

```hcl
moved {
  from = module.infra_ci_roles.module.plan.aws_iam_role.this
  to   = module.infra_ci_plan.module.role.aws_iam_role.this
}

moved {
  from = module.infra_ci_roles.module.apply.aws_iam_role.this
  to   = module.infra_ci_apply.module.role.aws_iam_role.this
}
```

The plan then shows, per role:

- the role updated in place: its trust statement `Sid`, `description` and
  tags (`Component = ci`, `Name = <role name>`);
- its inline policies destroyed, and for the foundation roles the
  `ReadOnlyAccess` attachment destroyed;
- one managed policy created and attached per requested policy.

Permissions intentionally change in three ways. `ReadOnlyAccess` is gone,
replaced by `foundation/read`, so the foundation roles can no longer read
other projects' state. `foundation/manage` no longer reaches objects in
`<name_root>-*` buckets, which included the state bucket, and no longer
allows attaching `ReadOnlyAccess`. The site apply role can no longer delete
state objects, only `.tflock` files.

**Run this apply with administrator credentials, not through a CI apply
role.** The foundation apply role's own policies are replaced in the same
apply, and IAM changes take a few seconds to propagate, so it can lose a
permission it still needs partway through. Expect the same brief gap for
any workflow that assumes a role while the apply runs.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for local setup, the commit and PR
rules, CI, and how releases work. Coding agents: see [AGENTS.md](AGENTS.md).

## Root module reference

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
| dev | ./modules/static-site | n/a |
| preview | ./modules/preview-site | n/a |
| prod | ./modules/static-site | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| bucket\_name | Name of the project's site bucket (output `name` of `site-bucket`, or `bucket_name` of `context`). | `string` | n/a | yes |
| bucket\_regional\_domain\_name | Regional domain name of the site bucket (output `regional_domain_name` of `site-bucket`). | `string` | n/a | yes |
| domain\_name | Production FQDN, for example `guitar.jwall.engineering`. Served from `<bucket>/prod`; previews are served from `pr-<n>.preview.<domain_name>`. | `string` | n/a | yes |
| zone\_id | Route 53 hosted zone ID that contains `domain_name` (and `dev_domain_name`). | `string` | n/a | yes |
| dev\_domain\_name | Optional FQDN for the dev environment, served from `<bucket>/dev` (for example `dev.guitar.jwall.engineering`). Set to `null` to skip the dev distribution. | `string` | `null` | no |
| enable\_preview | Whether to create the `*.preview.<domain_name>` distribution for pull-request previews. | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| dev\_distribution\_id | CloudFront distribution ID for the dev site, or `null` when `dev_domain_name` is not set. |
| dev\_url | Dev URL (`https://<dev_domain_name>`), or `null` when `dev_domain_name` is not set. |
| distribution\_ids | Map of environment name (`prod`, `dev`, `preview`) to CloudFront distribution ID, for invalidation scripts. |
| preview\_distribution\_id | CloudFront distribution ID for `*.preview.<domain_name>`, or `null` when `enable_preview` is false. |
| preview\_url\_pattern | Preview URL pattern (`https://pr-<n>.preview.<domain_name>`), or `null` when `enable_preview` is false. |
| prod\_distribution\_arn | CloudFront distribution ARN for the production site. |
| prod\_distribution\_id | CloudFront distribution ID for the production site. |
| prod\_url | Production URL (`https://<domain_name>`). |
<!-- END_TF_DOCS -->

## License

[MIT](LICENSE)
