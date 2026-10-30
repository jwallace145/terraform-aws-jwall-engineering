# dataset-bucket

A durable, append-only S3 bucket for a project's datasets, such as NNUE
self-play training data: data that every later model is built and compared
from, so nothing ever expires.

- **Kept:** no expiration rule, and the bucket has `prevent_destroy`.
- **Write-once by convention:** writers add new keys (a new run gets a new
  partition) and never overwrite. Versioning is off: it would only store an
  accidental re-upload twice.
- **Intelligent-Tiering:** a lifecycle rule moves objects to S3
  Intelligent-Tiering after `transition_days` (0, the default, means at the
  next daily lifecycle run). Training reads data in bursts and then it goes
  cold; Intelligent-Tiering moves it to cheaper tiers on its own. S3 does not
  transition objects under 128 KB, such as manifests; they stay in Standard.
- **Hardened like [`private-bucket`](../private-bucket):** SSE-S3 with a
  bucket key, all four public access blocks, `BucketOwnerEnforced`, a bucket
  policy that denies requests without TLS, and incomplete multipart uploads
  aborted after 7 days.
- **Tags:** `Name`, `Component = dataset` and `Purpose = dataset`, plus the
  organisation tags from the provider's `default_tags`.

## Access

| Who | How | What |
|---|---|---|
| `writer_role_names` | an inline policy on each role, `<name>-write` | `s3:PutObject` and `s3:AbortMultipartUpload` under `prefix`; `s3:ListBucket` limited to `prefix` |
| `reader_role_arns` | the bucket policy | `s3:GetObject` under `prefix`; `s3:ListBucket` limited to `prefix` |
| the account's administrators | their own IAM policies | everything |

Writers never get `GetObject` or `DeleteObject`: a writer such as a CI task
instance may run pull request code, and the dataset is append-only. The CI
roles that plan and apply the bucket get its configuration only, never its
objects ([`dataset/read`](../ci-policies/dataset/read) and
[`dataset/manage`](../ci-policies/dataset/manage)).

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/dataset-bucket>

## Usage

```hcl
module "nnue" {
  source  = "jwallace145/jwall-engineering/aws//modules/dataset-bucket"
  version = "~> 0.14"

  name              = "jwall-engineering-rusty-chess-nnue"
  prefix            = "data/"
  writer_role_names = [module.tasks.instance_role_name]
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
| [aws_iam_role_policy.writer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_ownership_controls.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Name of the bucket, for example `jwall-engineering-rusty-chess-nnue`. Also the value of its `Name` tag. | `string` | n/a | yes |
| prefix | Key prefix the project's data lives under, ending in `/`, for example `data/`. Writers and readers are granted this prefix only. | `string` | n/a | yes |
| reader\_role\_arns | IAM role ARNs granted `s3:GetObject` under the prefix and `s3:ListBucket` limited to it, through the bucket policy. The account's administrators can read without being listed. | `list(string)` | `[]` | no |
| transition\_days | Days after which objects move to S3 Intelligent-Tiering. 0 moves them at once (at the next daily lifecycle run). Objects under 128 KB stay in S3 Standard. | `number` | `0` | no |
| writer\_role\_names | Roles in this account that may add objects under the prefix: an inline policy on each grants `s3:PutObject` (and `s3:AbortMultipartUpload` for its own failed uploads) under the prefix and `s3:ListBucket` limited to it. Never read, delete or overwrite protection: writers only add. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the bucket, for IAM policies. |
| name | Name of the bucket. |
| uri | Where the project's data lives: `s3://<name>/<prefix>`. |
<!-- END_TF_DOCS -->
