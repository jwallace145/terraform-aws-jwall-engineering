# tfstate-bucket

The S3 bucket that holds Terraform state for every stack in an account. The
infra repo calls this module once.

- Versioning is enabled, so every state write can be recovered.
- Objects are encrypted with SSE-S3 (`AES256`) and an S3 bucket key.
- All four Block Public Access flags are on, and object ownership is
  `BucketOwnerEnforced`, so ACLs are disabled.
- The bucket policy denies every request made without TLS
  (`DenyInsecureTransport`). Set `prefix_access` to harden it further; see
  below.
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

The `tfstate/*` CI policies in `ci-policies` scope CI roles to one key or
one prefix, so a stack's roles can only read and write its own state.

## Hardened bucket policy

IAM policies on the CI roles only bound those roles. Any other principal in
the account with broad S3 permissions (for example `s3:*` on `*`) can still
read, overwrite or delete every stack's state, and rewrite the bucket policy.
Setting `prefix_access` closes that from the bucket's side. It maps each key
prefix to the principals that may `read` and `write` under it:

```hcl
admin_principal_arns = [
  "arn:aws:iam::123456789012:user/admin",
  module.infra_ci_apply.role_arn, # applies this bucket
]

prefix_access = {
  "project=infra/env=prod/infra-prod.tfstate" = {
    read  = [module.infra_ci_plan.role_arn]
    write = [module.infra_ci_apply.role_arn]
  }
  "project=guitar/" = {
    read  = [module.guitar_ci_plan.role_arn]
    write = [module.guitar_ci_apply.role_arn]
  }
}
```

Each key matches `<key>*`, so a full state key also covers its `.tflock`.
Keys must not overlap. The policy then adds these statements, every one a
`Deny` for `Principal = "*"` matched on `aws:PrincipalArn`:

| Statement | Denies |
|---|---|
| `DenyUnlistedListing` | `s3:ListBucket*` to anyone not listed in `prefix_access` or `admin_principal_arns` |
| `DenyObjectsOutsidePrefixes` | Object access outside every declared prefix to anyone but the admins |
| `DenyOutsidePrefix<N>` | Object access under prefix `N` to anyone but its readers, writers and the admins |
| `DenyStateWritesByReaders` | Writes by read-only principals to anything but `.tflock` objects, so `terraform plan` can lock but not write state |
| `DenyUnmanagedConfiguration` | Bucket configuration changes, the bucket policy included, to anyone but the admins |

Every statement is a deny, so being listed or exempt grants nothing: a
principal still needs an IAM policy that allows the action.
`admin_principal_arns` is required with `prefix_access`, so someone can
always change the policy. List the role that applies this bucket there,
otherwise its next apply cannot update the policy. The account root user is
denied too, but can always delete a bucket policy as a last resort.

`DenyStateWritesByReaders` covers principals that read some prefix and write
none. A principal that writes one prefix and reads another is bounded only by
its IAM policy on the one it reads.

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
  version = "~> 0.7"

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
| admin\_principal\_arns | IAM principal ARNs exempt from every deny in the bucket policy except TLS, for example the admin user and the role that applies this bucket. Being exempt grants nothing; the principal's own IAM policies still decide what it can do. Required when `prefix_access` is set, so the policy can always be changed by someone. | `list(string)` | `[]` | no |
| component | Value of the `Component` tag on the bucket. | `string` | `"terraform-state"` | no |
| prefix\_access | Hardens the bucket policy when set: map of state key prefix to the principals that may `read` and `write` objects under it. Each key matches `<key>*`, so a full state key such as `project=infra/env=prod/infra-prod.tfstate` also covers its `.tflock`. Everyone else, including principals with `s3:*`, is denied object access; readers may only write `.tflock` objects. Leave empty for a TLS-only policy. | <pre>map(object({<br/>    read  = optional(list(string), [])<br/>    write = optional(list(string), [])<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the state bucket, for CI role policies (`policy_inputs.tfstate.bucket_arn` and `policy_inputs.foundation.state_bucket_arn` of the CI role modules). |
| name | Name of the state bucket, for the `bucket` argument of an `s3` backend. |
| policy | The bucket policy as a JSON string. |
<!-- END_TF_DOCS -->
