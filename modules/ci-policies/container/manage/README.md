# container/manage

Create and manage everything in a bot project's stack: its VPC, subnets,
internet gateway, route table and security groups; its EC2 instance; its
instance role, instance profile and inline policy; its image repository;
its log groups under `/<name_root>/<project>/`; the tags of its parameters;
and the configuration of its records bucket. Class: **write**.

Write policies grant no reads; pair it with [`container/read`](../read) on
the apply role.

Part of the [`ci-policies`](../..) catalog. Request it from a CI role module
with `policies = ["container/manage"]`; it is not meant to be called
directly.

## How it is scoped

- **EC2 by tag.** Create calls require `aws:RequestTag/Project = <project>`
  and every change or delete requires `aws:ResourceTag/Project = <project>`.
  This only works because the caller's provider sets `default_tags` from
  the `context` module. Creating a subnet, security group or route table
  also authorizes against the parent VPC, which must carry the same tag.
- **IAM by name.** Roles, instance profiles and policies are limited to
  `<name_root>-<project>-*`. `iam:AttachRolePolicy` only accepts the
  project's own policies, `AmazonSSMManagedInstanceCore` and
  `attachable_policy_arns`. `iam:PassRole` only passes project roles to EC2.
- **Everything else by name or path.** The repository is
  `<name_root>-<project>`, the bucket `<name_root>-<project>-records`, log
  groups and parameters live under `/<name_root>/<project>/`.
- **Never data.** No S3 object action, no `ssm:PutParameter`: the records
  are written by the instance and the secret by the owner.

## Known gaps

| Statement | Why it is `*` |
|---|---|
| `CreateTagsOnCreate` (`ec2:CreateTags`) | Tags applied by a create call. Bounded with `ec2:CreateAction` to the create calls this policy allows, each of which already requires the `Project` tag. |
| `ManageProjectTags` (`ec2:CreateTags`, `ec2:DeleteTags`) | Tag changes on existing resources. Bounded by `aws:ResourceTag/Project`. |

`RunInstancesDependencies` names the image, network interface, subnet and
security group resource types without a tag condition, because
`RunInstances` authorizes against them and a public AMI cannot carry the
project's tag.

## Known limitation

Like [`foundation/manage`](../../foundation/manage), this policy can edit
the inline policies of `<name_root>-<project>-*` roles, including the
project's own CI roles if they share the prefix. A role holding it can
therefore grant the project's roles more access within the project's
namespace. Protect the environment the apply role trusts.

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
| [aws_iam_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Name of the managed policy, for example `jwall-engineering-rusty-chess-ci-apply-container-manage`. | `string` | n/a | yes |
| project | Project name in kebab-case. Every resource ARN in the policy is built from `<name_root>-<project>`. | `string` | n/a | yes |
| attachable\_policy\_arns | Extra managed policy ARNs the apply role may attach to `<name_root>-<project>-*` roles, on top of the project's own policies and `AmazonSSMManagedInstanceCore`. | `list(string)` | `[]` | no |
| name\_root | Prefix of resource names, in kebab-case. Roles, policies, repositories and buckets are scoped to `<name_root>-<project>-*`; parameters and log groups to `/<name_root>/<project>/*`. | `string` | `"jwall-engineering"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the managed policy. |
| name | Name of the managed policy. |
| policy | The policy document as a JSON string. |
<!-- END_TF_DOCS -->
