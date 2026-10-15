# context

Derives the naming and tagging conventions for a jwall-engineering project.
This module **creates no resources**, so all of its outputs are known at plan
time and can be fed into the AWS provider's `default_tags`.

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/context>

## Usage

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

The `Project` tag that this module emits is what the `static-site/*` CI
policies in `ci-policies` use to scope CloudFront and ACM permissions, so every caller must pass
`module.context.tags` to `default_tags`.

## Conventions

| Output | Value |
|---|---|
| `tags` | `Organization`, `Project`, `Environment`, `Repository`, `ManagedBy = "terraform"`, `Owner`, merged over `extra_tags`. Required keys win any conflict. |
| `name_prefix` | `jwall-engineering-<project>-<environment>` |
| `bucket_name` | `jwall-engineering-<project>` |

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11 |
| aws | ~> 6.0 |

## Providers

No providers.

## Modules

No modules.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| environment | Deployment environment. One of `dev`, `staging`, `prod` or `preview`. | `string` | n/a | yes |
| project | Project name in kebab-case, for example `guitar`. Used in resource names and the `Project` tag. | `string` | n/a | yes |
| repository | GitHub repository that owns the project, as `owner/repo` (for example `jwallace145/guitar`). | `string` | n/a | yes |
| extra\_tags | Additional tags merged into `tags`. The required keys (Organization, Project, Environment, Repository, ManagedBy, Owner) always win on conflict. | `map(string)` | `{}` | no |
| organization | Organization the project belongs to. Becomes the `Organization` tag. | `string` | `"jwall-engineering"` | no |
| owner | GitHub user responsible for the project. Becomes the `Owner` tag. | `string` | `"jwallace145"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| bucket\_name | Site bucket name for the project: `jwall-engineering-<project>`. Shared by every environment of the project. |
| name\_prefix | Resource name prefix: `jwall-engineering-<project>-<environment>`. |
| tags | Tag map for the caller's provider `default_tags`: Organization, Project, Environment, Repository, ManagedBy=terraform and Owner, merged over `extra_tags` (required keys win). |
<!-- END_TF_DOCS -->
