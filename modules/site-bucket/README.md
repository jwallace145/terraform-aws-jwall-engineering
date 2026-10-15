# site-bucket

Creates the single S3 bucket that holds every environment of a static site:
`jwall-engineering-<project>`. One bucket per project; the infra repo calls
this module once per project.

## What it creates

- Bucket `jwall-engineering-<project>` with Block Public Access fully on,
  `BucketOwnerEnforced` object ownership, SSE-S3 encryption and versioning.
- Lifecycle rules:
  - noncurrent object versions expire after 30 days
  - objects under `previews/` expire after 14 days
  - incomplete multipart uploads are aborted after 7 days
- Bucket policy:
  - deny any request that is not over TLS (`aws:SecureTransport = false`)
  - allow `cloudfront.amazonaws.com` to `s3:GetObject` on `bucket/*`, only
    when `AWS:SourceAccount` is the current account (origin access control)
  - with `prefix_writers` set, write and configuration denies; see below

Every resource is tagged `Component = "site-bucket"`. All other tags come from
the caller's provider `default_tags` (see the `context` module).

## Prefix layout

| Prefix | Served by | Written by |
|---|---|---|
| `prod/` | `static-site` with `origin_path = "/prod"` | `ci-apply` role |
| `dev/` | `static-site` with `origin_path = "/dev"` | `ci-apply` role |
| `previews/pr-<n>/` | `preview-site` (`pr-<n>.preview.<domain>`) | `ci-preview` role; objects expire after 14 days |

## Hardened bucket policy

IAM policies on the CI roles only bound those roles. Any other principal in
the account with broad S3 permissions (for example `s3:*` on `*`) can still
overwrite or delete the site, and rewrite the bucket policy. Setting
`prefix_writers` closes that from the bucket's side. It maps each prefix to
the principals that may write it:

```hcl
admin_principal_arns = [
  "arn:aws:iam::123456789012:user/admin",
  module.infra_ci_apply.role_arn, # applies this bucket
]

prefix_writers = {
  "prod/"     = [module.guitar_ci_apply.role_arn]
  "dev/"      = [module.guitar_ci_apply.role_arn]
  "previews/" = [module.guitar_ci_preview.role_arn]
}
```

Prefixes end in `/` and must not overlap. The policy then adds these
statements, every one a `Deny` for `Principal = "*"` matched on
`aws:PrincipalArn`:

| Statement | Denies |
|---|---|
| `DenyWritesOutsidePrefixes` | Writes outside every declared prefix to anyone but the admins |
| `DenyWritesToPrefix<N>` | Writes under prefix `N` to anyone but its writers and the admins |
| `DenyUnmanagedConfiguration` | Bucket configuration changes, the bucket policy included, to anyone but the admins |

Reads are deliberately not restricted: the content is public through
CloudFront, and plan roles read the bucket's configuration. Lifecycle expiry
is performed by S3 itself, so the `previews/` rule keeps working. Every
statement is a deny, so being listed or exempt grants nothing.
`admin_principal_arns` is required with `prefix_writers`; list the role that
applies this bucket there, otherwise its next apply cannot update the policy.

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/site-bucket>

## Usage

```hcl
module "site_bucket" {
  source  = "jwallace145/jwall-engineering/aws//modules/site-bucket"
  version = "~> 0.1"

  project = "guitar"
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
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_ownership_controls.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| project | Project name in kebab-case. The bucket is named `jwall-engineering-<project>`. | `string` | n/a | yes |
| admin\_principal\_arns | IAM principal ARNs exempt from every deny in the bucket policy except TLS, for example the admin user and the role that applies this bucket. Being exempt grants nothing; the principal's own IAM policies still decide what it can do. Required when `prefix_writers` is set, so the policy can always be changed by someone. | `list(string)` | `[]` | no |
| prefix\_writers | Hardens the bucket policy when set: map of key prefix (ending in `/`) to the principals that may write objects under it, for example `{ "prod/" = [<apply role>], "dev/" = [<apply role>], "previews/" = [<preview role>] }`. Everyone else, including principals with `s3:*`, is denied writes, and only `admin_principal_arns` may write outside these prefixes or change the bucket's configuration. Reads are not restricted: the content is public through CloudFront. Leave empty for the TLS and CloudFront statements only. | `map(list(string))` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | Bucket ARN. |
| name | Bucket name (`jwall-engineering-<project>`). |
| policy | The bucket policy as a JSON string. |
| regional\_domain\_name | Regional bucket domain name, to be used as a CloudFront origin (`<bucket>.s3.us-east-1.amazonaws.com`). |
<!-- END_TF_DOCS -->
