# dataset-bucket

A durable, append-only S3 bucket for a project's datasets, such as NNUE
self-play training data: data that every later model is built and compared
from. By default nothing expires, the bucket is not versioned and the bucket
has `prevent_destroy`. Versioning, expiry of named sub-prefixes and write-once
sub-prefixes are opt-ins.

- **Kept by default:** there is no expiration rule unless `expire_prefixes`
  names a sub-prefix, for projects that keep scratch data next to the
  dataset. On a versioned bucket expiry only adds a delete marker; set
  `expire_noncurrent_days` to remove the data and stop paying for it.
- **Not versioned by default:** writers add new keys (a new run gets a new
  partition), so versioning would only store an accidental re-upload twice.
  `versioning = true` turns it on; setting it back to false suspends it and
  keeps existing versions.
- **Write-once on request:** a `role_grants` entry can list `write_once`
  sub-prefixes, enforced by S3 conditional writes (`If-None-Match: *`), so an
  existing object is never overwritten through that grant. `CopyObject` into
  such a prefix is refused. The module rejects configurations that would
  defeat this: `writer_role_names` must be empty, and no `write` grant or
  `expire_prefixes` key may overlap a `write_once` sub-prefix.
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
| `role_grants` | an inline policy on each role, `<name>-access` | `s3:GetObject` under each `read` sub-prefix of `prefix`; `s3:PutObject` and `s3:AbortMultipartUpload` under each `write` sub-prefix; `s3:PutObject` only with `If-None-Match: *` (and `s3:AbortMultipartUpload`) under each `write_once` sub-prefix; `s3:ListBucket` limited to those sub-prefixes |
| the account's administrators | their own IAM policies | everything |

A grant is for a role that reads one part of the dataset and adds to
another, such as a GPU trainer that reads `selfplay/` positions and writes
`nets/`. It never deletes, and the rest of the bucket is out of its reach.

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
| [aws_iam_role_policy.grant](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.writer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
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
| name | Name of the bucket, for example `jwall-engineering-rusty-chess-nnue`. Also the value of its `Name` tag. | `string` | n/a | yes |
| prefix | Key prefix the project's data lives under, ending in `/`, for example `data/`. Writers and readers are granted this prefix only. | `string` | n/a | yes |
| expire\_noncurrent\_days | Days after which noncurrent object versions are permanently deleted, across the whole bucket. Requires `versioning = true`. `null` keeps them forever. | `number` | `null` | no |
| expire\_prefixes | Sub-prefixes of `prefix` whose objects expire after the given number of days, for example `{ "tmp/" = 30 }` under `data/` expires `data/tmp/` after 30 days. Keys end in `/`, must not overlap each other or any `role_grants` `write_once` sub-prefix (either string starting with the other), and must give distinct rule ids (`a/b/` and `a-b/` both give `expire-a-b-`). Nothing outside the named sub-prefixes expires. On a versioned bucket, expiry only adds a delete marker: without `expire_noncurrent_days` the data is kept, and still billed. | `map(number)` | `{}` | no |
| reader\_role\_arns | IAM role ARNs granted `s3:GetObject` under the prefix and `s3:ListBucket` limited to it, through the bucket policy. The account's administrators can read without being listed. | `list(string)` | `[]` | no |
| role\_grants | Roles in this account granted narrower access than a writer or reader. `read`, `write` and `write_once` are lists of sub-prefixes of `prefix`, each ending in `/` (for example `selfplay/`). An inline policy on each role grants `s3:GetObject` under each `read` sub-prefix, `s3:PutObject` (and `s3:AbortMultipartUpload`) under each `write` sub-prefix, and `s3:ListBucket` limited to all three lists. `write_once` sub-prefixes are add-only: `s3:PutObject` is allowed there only with `If-None-Match: *` (for example `aws s3 cp --no-overwrite`), so S3 refuses to overwrite an existing object, and `CopyObject` into such a prefix is refused because it carries no such condition. A grant never deletes. Keys are role names. The guarantee holds only for what this module controls: if any grant has `write_once`, `writer_role_names` must be empty, no grant's `write` may overlap any grant's `write_once`, and no `expire_prefixes` key may overlap one (overlap means either string starts with the other). Policies this module does not manage, such as an administrator's or another inline policy on the same role, can still overwrite. | <pre>map(object({<br/>    read  = optional(list(string), [])<br/>    write = optional(list(string), [])<br/>    # Add-only: objects can be created but never overwritten (S3 conditional writes).<br/>    write_once = optional(list(string), [])<br/>  }))</pre> | `{}` | no |
| transition\_days | Days after which objects move to S3 Intelligent-Tiering. 0 moves them at once (at the next daily lifecycle run). Objects under 128 KB stay in S3 Standard. | `number` | `0` | no |
| versioning | Keep previous versions of overwritten or deleted objects. Off by default: datasets are write-once, so versioning would only store an accidental re-upload twice. Setting it back to false suspends versioning rather than removing existing versions. | `bool` | `false` | no |
| writer\_role\_names | Roles in this account that may add objects under the prefix: an inline policy on each grants `s3:PutObject` (and `s3:AbortMultipartUpload` for its own failed uploads) under the prefix and `s3:ListBucket` limited to it. Never read, delete or overwrite protection: writers only add. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the bucket, for IAM policies. |
| name | Name of the bucket. |
| uri | Where the project's data lives: `s3://<name>/<prefix>`. |
<!-- END_TF_DOCS -->
