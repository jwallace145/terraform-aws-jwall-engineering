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

Every resource is tagged `Component = "site-bucket"`. All other tags come from
the caller's provider `default_tags` (see the `context` module).

## Prefix layout

| Prefix | Served by | Written by |
|---|---|---|
| `prod/` | `static-site` with `origin_path = "/prod"` | `ci-apply` role |
| `dev/` | `static-site` with `origin_path = "/dev"` | `ci-apply` role |
| `previews/pr-<n>/` | `preview-site` (`pr-<n>.preview.<domain>`) | `ci-preview` role; objects expire after 14 days |

## Usage

```hcl
module "site_bucket" {
  source = "git::https://github.com/jwallace145/terraform-library.git//modules/site-bucket?ref=v0.1.0"

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

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | Bucket ARN. |
| name | Bucket name (`jwall-engineering-<project>`). |
| regional\_domain\_name | Regional bucket domain name, to be used as a CloudFront origin (`<bucket>.s3.us-east-1.amazonaws.com`). |
<!-- END_TF_DOCS -->
