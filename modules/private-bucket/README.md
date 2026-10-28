# private-bucket

A private S3 bucket for durable project data that must outlive the stack
that produces it, such as the game records a bot writes. Versioned,
SSE-S3 encrypted with a bucket key, Block Public Access on,
`BucketOwnerEnforced`, and a TLS-only bucket policy. Noncurrent object
versions expire after `noncurrent_version_expiration_days` (30 by default)
and incomplete multipart uploads are aborted after 7 days.

`prevent_destroy` is hard-coded: a `terraform destroy` of the stack keeps
the bucket and its objects, by design. Who may read and write the objects is
decided by the callers' IAM policies; the bucket policy grants nothing.

The bucket carries `Name` and `Component` tags; the organisation tags come
from the caller's provider `default_tags`.

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/private-bucket>

## Usage

```hcl
module "records" {
  source  = "jwallace145/jwall-engineering/aws//modules/private-bucket"
  version = "~> 0.10"

  name = "jwall-engineering-rusty-chess-records"
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

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Name of the bucket, for example `jwall-engineering-rusty-chess-records`. Also the value of its `Name` tag. | `string` | n/a | yes |
| component | Value of the `Component` tag on the bucket. | `string` | `"private-bucket"` | no |
| noncurrent\_version\_expiration\_days | Overwritten and deleted object versions are kept this many days before they expire. | `number` | `30` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the bucket, for IAM policies. |
| name | Name of the bucket, for `aws s3 sync` targets and IAM policies. |
<!-- END_TF_DOCS -->
