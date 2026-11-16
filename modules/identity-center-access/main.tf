# One Identity Center user with one permission set in one account: a person's
# short-lived console and CLI access, with no IAM user and no access key.
#
# The user and the permission set refuse to be destroyed. Recreating the
# permission set makes Identity Center provision a new role with a new
# generated suffix, which breaks every policy that names the old role's ARN;
# recreating the user drops its registered MFA devices. Either is a deliberate
# act: remove the lifecycle block in a fork, or `terraform state rm` first.

locals {
  display_name = coalesce(var.user.display_name, "${var.user.given_name} ${var.user.family_name}")

  # The role Identity Center provisions in the account for this permission set.
  # permission_set_name is limited to [A-Za-z0-9_-], so it needs no escaping.
  role_path_prefix = "/aws-reserved/sso.amazonaws.com/"
  role_name_regex  = "^AWSReservedSSO_${var.permission_set_name}_[0-9a-f]+$"
}

resource "aws_identitystore_user" "this" {
  identity_store_id = var.identity_store_id

  user_name    = var.user.user_name
  display_name = local.display_name

  name {
    given_name  = var.user.given_name
    family_name = var.user.family_name
  }

  emails {
    value   = var.user.email
    primary = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssoadmin_permission_set" "this" {
  instance_arn     = var.instance_arn
  name             = var.permission_set_name
  description      = var.permission_set_description
  session_duration = var.session_duration

  tags = {
    Component = "identity-center-access"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = toset(var.managed_policy_arns)

  instance_arn       = var.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this.arn
  managed_policy_arn = each.value
}

resource "aws_ssoadmin_account_assignment" "this" {
  instance_arn       = var.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this.arn

  principal_type = "USER"
  principal_id   = aws_identitystore_user.this.user_id

  target_type = "AWS_ACCOUNT"
  target_id   = var.account_id

  # Provision the role with its policies already attached.
  depends_on = [aws_ssoadmin_managed_policy_attachment.this]
}

# The IAM role the assignment provisioned. IAM can take a moment to list a new
# role, so this may come back empty right after the first apply; a
# `terraform apply -refresh-only` then fills in role_arn.
data "aws_iam_roles" "provisioned" {
  path_prefix = local.role_path_prefix
  name_regex  = local.role_name_regex

  depends_on = [aws_ssoadmin_account_assignment.this]
}
