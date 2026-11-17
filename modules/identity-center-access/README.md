# identity-center-access

One IAM Identity Center user with one permission set in one AWS account, and
optionally in the organization's other accounts: a person's short-lived console and CLI access, with no IAM user and no access
key. It creates:

- the user in the instance's identity store (no groups: with one person, a
  group is a layer that adds nothing);
- a permission set, `AdministratorAccess` with one-hour sessions by default,
  with its managed policies attached;
- the assignment of the permission set to the user in `account_id`;
- the same assignment in each of `additional_account_ids` (none by default),
  for an organization with more than one account;
- a lookup of the IAM role Identity Center provisions for the assignment,
  exported as `role_arn`.

The person signs in at the instance's AWS access portal and, from the CLI,
with `aws sso login`. The CLI and SDKs renew the permission set's credentials
(`session_duration`, one hour by default) until the Identity Center sign-in
itself expires.

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/identity-center-access>

## Before you use it

The module needs an **organization instance** of IAM Identity Center, which
can only be enabled in the console, from an organization's management account
(a standalone account's console offers to create the organization). Do not
run `aws sso-admin create-instance`: it creates an *account* instance, which
cannot grant access to AWS accounts and cannot be converted later. Pass the
instance from `data.aws_ssoadmin_instances`.

A few instance settings have no API and stay in the console: the MFA rules,
the sign-in session length, and **Send email OTP** for users created from the
API. The user this module creates has no password; with that setting on, the
first sign-in emails a one-time password, and otherwise you generate one in
the console.

## The provisioned role

Identity Center provisions the permission set as an IAM role named
`AWSReservedSSO_<permission set>_<suffix>` under the path
`/aws-reserved/sso.amazonaws.com/`. AWS generates the suffix, and IAM refuses
edits to the role, so nothing outside Identity Center can change it.

`role_arn` is that role's full ARN, path included, which is what
`aws:PrincipalArn` holds in a bucket policy. IAM can take a moment to list a
new role, so it may be null right after the first apply: run
`terraform apply -refresh-only` to fill it in.

## Lifecycle

The user and the permission set have `prevent_destroy`. Recreating the
permission set provisions a new role with a new suffix, which breaks every
policy that names the old ARN; recreating the user drops its registered MFA
devices. To remove either on purpose, `terraform state rm` it first.

`permission_set_name` is limited to `A-Z a-z 0-9 _ -` so it can be matched in
the role lookup without escaping.

## Usage

```hcl
data "aws_caller_identity" "current" {}
data "aws_ssoadmin_instances" "this" {}

module "owner_admin" {
  source  = "jwallace145/jwall-engineering/aws//modules/identity-center-access"
  version = "x.y.z"

  instance_arn      = one(data.aws_ssoadmin_instances.this.arns)
  identity_store_id = one(data.aws_ssoadmin_instances.this.identity_store_ids)
  account_id        = data.aws_caller_identity.current.account_id

  user = {
    user_name   = "jwallace145"
    given_name  = "Jane"
    family_name = "Doe"
    email       = "owner@example.com"
  }
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
| [aws_identitystore_user.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/identitystore_user) | resource |
| [aws_ssoadmin_account_assignment.additional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_account_assignment) | resource |
| [aws_ssoadmin_account_assignment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_account_assignment) | resource |
| [aws_ssoadmin_managed_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_managed_policy_attachment) | resource |
| [aws_ssoadmin_permission_set.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_permission_set) | resource |
| [aws_iam_roles.provisioned](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_roles) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| account\_id | The AWS account the user gets the permission set in, as a 12-digit string. | `string` | n/a | yes |
| identity\_store\_id | ID of the instance's identity store, from `data.aws_ssoadmin_instances` (for example `d-0123456789`). | `string` | n/a | yes |
| instance\_arn | ARN of the IAM Identity Center organization instance, from `data.aws_ssoadmin_instances` (for example `arn:aws:sso:::instance/ssoins-0123456789abcdef`). The instance must already be enabled in the console; this module cannot create one. | `string` | n/a | yes |
| user | The one Identity Center user who gets the permission set. `display_name` defaults to `<given_name> <family_name>`. The user is created without a password: set one at first sign-in through Identity Center's email one-time password, or generate one in the console. | <pre>object({<br/>    user_name    = string<br/>    given_name   = string<br/>    family_name  = string<br/>    email        = string<br/>    display_name = optional(string)<br/>  })</pre> | n/a | yes |
| additional\_account\_ids | Other AWS accounts of the organization the user gets the same permission set in, as 12-digit strings. Identity Center provisions the permission set's role in each; `role_arn` is still the role in the account the provider runs in, so read another account's role ARN there (`aws iam list-roles --path-prefix /aws-reserved/sso.amazonaws.com/`). | `list(string)` | `[]` | no |
| managed\_policy\_arns | Managed policies attached to the permission set. Defaults to `AdministratorAccess`. | `list(string)` | <pre>[<br/>  "arn:aws:iam::aws:policy/AdministratorAccess"<br/>]</pre> | no |
| permission\_set\_description | Description of the permission set. | `string` | `"Administrator access for the account owner"` | no |
| permission\_set\_name | Name of the permission set. Identity Center provisions its IAM role as `AWSReservedSSO_<name>_<suffix>`, and the CLI profile's `sso_role_name` is this name. | `string` | `"AdministratorAccess"` | no |
| session\_duration | How long each set of credentials (and each console session) from the permission set lasts, as an ISO-8601 duration in whole hours from `PT1H` to `PT12H`. The AWS CLI and SDKs renew credentials until the Identity Center sign-in itself expires. | `string` | `"PT1H"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| account\_ids | Every account the user has the permission set in: `account_id` first, then `additional_account_ids` in order. |
| permission\_set\_arn | ARN of the permission set. |
| permission\_set\_name | Name of the permission set: the `sso_role_name` of an AWS CLI profile. |
| role\_arn | Full ARN, path included, of the IAM role Identity Center provisioned for the permission set (`arn:aws:iam::<account>:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_<name>_<suffix>`): the value `aws:PrincipalArn` takes in bucket policies. Null until IAM lists the role; run `terraform apply -refresh-only` if it is null after the first apply. |
| session\_duration | Session duration of the permission set, as an ISO-8601 duration. |
| user\_id | Identity store ID of the user. |
| user\_name | User name the person signs in to the access portal with. |
<!-- END_TF_DOCS -->
