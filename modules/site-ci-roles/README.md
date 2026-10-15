# site-ci-roles

Creates the three IAM roles a project repository's GitHub Actions workflows
assume through OIDC. The infra repo calls this module once per project. **No
role has any IAM permissions.**

Every trust policy requires `token.actions.githubusercontent.com:aud` to be
`sts.amazonaws.com` and pins the `sub` claim. GitHub issues `sub` in one of
two shapes depending on the repository's OIDC settings: the classic
`repo:<owner>/<name>:...` and the immutable
`repo:<owner>@<owner_id>/<name>@<repository_id>:...`. Pass `owner_id` and
`repository_id` (from `gh api users/<owner> --jq .id` and
`gh api repos/<owner>/<repo> --jq .id`) and the roles trust both forms;
without them only the classic form is trusted.

Each role is an instance of [`github-oidc-role`](../github-oidc-role), so the
trust-policy logic lives in one place. Roles created by `site-ci-roles` 0.3.x
and earlier sit at `aws_iam_role.this["<key>"]` and
`aws_iam_role_policy.this["<key>"]`. This module no longer carries `moved`
blocks for them, so a caller upgrading from 0.3.x must add its own, mapping
them to `module.<name>.module.role["<key>"].aws_iam_role.this` and
`module.<name>.module.role["<key>"].aws_iam_role_policy.this["policy"]`.

| Role | `sub` | Permissions |
|---|---|---|
| `jwall-engineering-<project>-ci-plan` | `repo:<repository>:pull_request` | Read-only on the project's bucket config, distributions, functions, certificates and hosted zone; read state under `project=<project>/*`; `PutObject`/`DeleteObject` **only** on `project=<project>/*.tflock` |
| `jwall-engineering-<project>-ci-preview` | `repo:<repository>:pull_request` | `PutObject`/`DeleteObject` on `<bucket>/previews/*`; `ListBucket` with `s3:prefix` limited to `previews/*` |
| `jwall-engineering-<project>-ci-apply` | `repo:<repository>:environment:prod` | Everything `plan` can read; read/write state under `project=<project>/*`; write `<bucket>/prod/*` and `<bucket>/dev/*`; manage the project's distributions, functions, OAC, cache policies and certificates; `cloudfront:CreateInvalidation`; `route53:ChangeResourceRecordSets` on the zone for the project's record names only |

## How permissions are scoped

- **Tags.** CloudFront distributions, CloudFront Functions and ACM certificates
  support `aws:ResourceTag`, and their create actions support
  `aws:RequestTag`. Those statements are conditioned on `Project = <project>`.
  This only works if the project's provider sets `default_tags` from the
  `context` module, which is what puts the `Project` tag on every resource.
- **Names.** CloudFront Function ARNs embed the function name, so the role is
  further limited to `function/jwall-engineering-<project>-*`. The
  `static-site` and `preview-site` modules name their functions from
  `bucket_name`, which the `context` module sets to
  `jwall-engineering-<project>`.
- **Route 53.** `ChangeResourceRecordSets` is limited to the hosted zone and
  conditioned with `route53:ChangeResourceRecordSetsNormalizedRecordNames`
  (`ForAllValues:StringLike`) to `record_names`, plus `_*.<name>` for each of
  them so ACM DNS validation CNAMEs can be created. Wildcards are normalised
  to `\052` as Route 53 requires.
- **S3.** Object actions are limited to the exact prefixes; `ListBucket` is
  conditioned on `s3:prefix`.

### Known gaps (documented rather than silently granting `*`)

| Permission | Why it is `*` |
|---|---|
| `cloudfront:List*`, `acm:ListCertificates` | List actions have no resource-level or tag support. They only disclose metadata. |
| `cloudfront:*OriginAccessControl*`, `cloudfront:*CachePolicy*`, `cloudfront:GetResponseHeadersPolicy*` | Origin access controls, cache policies and response headers policies cannot be tagged and have random IDs, so they cannot be scoped to a project. The apply role can therefore create, update and delete any OAC or custom cache policy in the account; it cannot touch distributions that are not tagged with the project. |
| `cloudfront:CreateDistribution`, `cloudfront:CreateFunction`, `acm:RequestCertificate` | Create actions take no resource ARN; they are conditioned on `aws:RequestTag/Project` instead, so only resources tagged with the project can be created. |
| `route53:GetChange` on `change/*` | Change IDs are random; this is read-only status polling. |

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/site-ci-roles>

## Usage

```hcl
module "site_ci_roles" {
  source  = "jwallace145/jwall-engineering/aws//modules/site-ci-roles"
  version = "~> 0.1"

  project           = "guitar"
  repository        = "jwallace145/guitar"
  owner_id          = "35950238"   # gh api users/jwallace145 --jq .id
  repository_id     = "123456789"  # gh api repos/jwallace145/guitar --jq .id
  bucket_arn        = module.site_bucket.arn
  state_bucket_arn  = "arn:aws:s3:::jwall-engineering-terraform-state"
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  zone_id           = "Z0123456789ABCDEFGHIJ"
  record_names = [
    "guitar.jwall.engineering",
    "dev.guitar.jwall.engineering",
    "*.preview.guitar.jwall.engineering",
  ]
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
| role | ../github-oidc-role | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| bucket\_arn | ARN of the project's site bucket (output `arn` of the `site-bucket` module). | `string` | n/a | yes |
| oidc\_provider\_arn | ARN of the account's GitHub Actions OIDC provider (`token.actions.githubusercontent.com`). | `string` | n/a | yes |
| project | Project name in kebab-case. Roles are named `jwall-engineering-<project>-ci-{plan,preview,apply}` and permissions are scoped to resources tagged `Project = <project>`. | `string` | n/a | yes |
| record\_names | FQDNs the project may manage in the hosted zone, including the wildcard preview name (for example `["guitar.example.com", "dev.guitar.example.com", "*.preview.guitar.example.com"]`). ACM validation CNAMEs for these names are allowed automatically. | `list(string)` | n/a | yes |
| repository | GitHub repository whose workflows may assume the roles, as `owner/repo`. | `string` | n/a | yes |
| state\_bucket\_arn | ARN of the shared Terraform state bucket. The project's state lives under the key prefix `project=<project>/`. | `string` | n/a | yes |
| zone\_id | Route 53 hosted zone ID in which the project may change records. | `string` | n/a | yes |
| owner\_id | Numeric GitHub ID of the repository owner (`gh api users/<owner> --jq .id`). When set together with `repository_id`, the roles also trust GitHub's immutable subject form `repo:<owner>@<owner_id>/<name>@<repository_id>:...`. | `string` | `null` | no |
| repository\_id | Numeric GitHub ID of the repository (`gh api repos/<owner>/<repo> --jq .id`). When set together with `owner_id`, the roles also trust GitHub's immutable subject form. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| apply\_role\_arn | ARN of `jwall-engineering-<project>-ci-apply`, assumed by the `prod` environment to run `terraform apply` and publish `prod/` and `dev/`. |
| plan\_role\_arn | ARN of `jwall-engineering-<project>-ci-plan`, assumed by `pull_request` workflows to run `terraform plan`. |
| preview\_role\_arn | ARN of `jwall-engineering-<project>-ci-preview`, assumed by `pull_request` workflows to publish `previews/pr-<n>/`. |
<!-- END_TF_DOCS -->
