# tfstate-bucket

The S3 bucket that holds Terraform state for every stack in an account. The
infra repo calls this module once.

- Versioning is enabled, so every state write can be recovered.
- Objects are encrypted with SSE-S3 (`AES256`) and an S3 bucket key.
- All four Block Public Access flags are on, and object ownership is
  `BucketOwnerEnforced`, so ACLs are disabled.
- The bucket policy has a single `DenyInsecureTransport` statement that denies
  every request made without TLS.
- The bucket is tagged `Name = <name>` and `Component = <component>`.

## `prevent_destroy` is hard-coded

The bucket carries `lifecycle { prevent_destroy = true }`. Terraform does not
allow lifecycle arguments to come from variables, so this cannot be turned
off by an input. Destroying the bucket would lose the state of every stack
that uses it. To remove the bucket on purpose, remove it from state first.

## State key convention

Each stack stores its state at:

```
project=<project>/env=<env>/<project>-<env>.tfstate
```

The `site-ci-roles` and `infra-ci-roles` modules scope their CI roles to these
prefixes, so a stack's roles can only read and write its own state.

## Locking

Locking uses the S3 native lockfile: Terraform writes `<key>.tflock` next to
the state object. There is no DynamoDB table, and none should be added.
Configure the backend with `use_lockfile = true`:

```hcl
terraform {
  backend "s3" {
    bucket       = "jwall-engineering-tfstate"
    key          = "project=infra/env=prod/infra-prod.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/tfstate-bucket>

## Usage

```hcl
module "state_bucket" {
  source  = "jwallace145/jwall-engineering/aws//modules/tfstate-bucket"
  version = "~> 0.4"

  name = "jwall-engineering-tfstate"
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
| [aws_s3_bucket_ownership_controls.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Name of the Terraform state bucket, for example `jwall-engineering-tfstate`. Also the value of its `Name` tag. | `string` | n/a | yes |
| component | Value of the `Component` tag on the bucket. | `string` | `"terraform-state"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the state bucket, for CI role policies (`state_bucket_arn` of `site-ci-roles` and `infra-ci-roles`). |
| name | Name of the state bucket, for the `bucket` argument of an `s3` backend. |
<!-- END_TF_DOCS -->
