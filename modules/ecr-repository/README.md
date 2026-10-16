# ecr-repository

A private ECR repository for one image, hardened the way every
jwall-engineering repository should be:

- `IMMUTABLE` tags: a release tag can never be moved to another image, so
  the tag a consumer pins is the image it gets.
- Scan on push and AES256 encryption.
- `force_delete = false`: a repository that still holds images cannot be
  destroyed by accident.
- A lifecycle policy that expires untagged images `expire_untagged_after_days`
  after they are pushed (layers left behind by a failed push) and keeps only
  the `keep_release_images` newest images tagged with one of
  `release_tag_prefixes` (`v` by default, for `v1.2.3`).
- Tagged `Name = <name>` and `Component = <component>`.

Pull and push rights are granted through the `ecr/pull` and `ecr/push`
policies in [`ci-policies`](../ci-policies), which take this module's `arn`.
Creating the repository itself is covered by `foundation/manage`.

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/ecr-repository>

## Usage

```hcl
module "sites_image" {
  source  = "jwallace145/jwall-engineering/aws//modules/ecr-repository"
  version = "~> 0.8"

  name                       = "jwall-engineering-sites"
  keep_release_images        = 20
  expire_untagged_after_days = 7
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
| [aws_ecr_lifecycle_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_lifecycle_policy) | resource |
| [aws_ecr_repository.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Repository name, for example `jwall-engineering-sites`. Also the value of its `Name` tag. | `string` | n/a | yes |
| component | Value of the `Component` tag on the repository. | `string` | `"ecr-repository"` | no |
| expire\_untagged\_after\_days | Untagged images (for example layers left behind by a failed push) expire this many days after being pushed. | `number` | `7` | no |
| keep\_release\_images | How many images tagged with one of `release_tag_prefixes` to keep. Older ones expire. | `number` | `20` | no |
| release\_tag\_prefixes | Tag prefixes that identify release images, which `keep_release_images` applies to. Defaults to `v`, for tags like `v1.2.3`. | `list(string)` | <pre>[<br/>  "v"<br/>]</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | Repository ARN, for `policy_inputs.ecr.repository_arn` of the CI role modules. |
| name | Repository name. |
| registry\_id | Registry (account) ID the repository belongs to. |
| url | Repository URL (`<account>.dkr.ecr.<region>.amazonaws.com/<name>`), for `docker push` and `docker pull`. |
<!-- END_TF_DOCS -->
