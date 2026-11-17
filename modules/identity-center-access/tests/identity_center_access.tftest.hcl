mock_provider "aws" {
  override_during = plan

  mock_resource "aws_identitystore_user" {
    defaults = {
      user_id = "90676d2e5d-11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_ssoadmin_permission_set" {
    defaults = {
      arn = "arn:aws:sso:::permissionSet/ssoins-0123456789abcdef/ps-0123456789abcdef"
    }
  }

  mock_data "aws_iam_roles" {
    defaults = {
      arns  = ["arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_0123456789abcdef"]
      names = ["AWSReservedSSO_AdministratorAccess_0123456789abcdef"]
    }
  }
}

variables {
  instance_arn      = "arn:aws:sso:::instance/ssoins-0123456789abcdef"
  identity_store_id = "d-0123456789"
  account_id        = "123456789012"

  user = {
    user_name   = "jwallace145"
    given_name  = "Jane"
    family_name = "Doe"
    email       = "owner@example.com"
  }
}

run "defaults_grant_administrator_access_for_one_hour" {
  command = plan

  assert {
    condition     = aws_ssoadmin_permission_set.this.name == "AdministratorAccess"
    error_message = "the permission set must default to AdministratorAccess"
  }

  assert {
    condition     = aws_ssoadmin_permission_set.this.session_duration == "PT1H"
    error_message = "sessions must default to one hour"
  }

  assert {
    condition     = keys(aws_ssoadmin_managed_policy_attachment.this) == ["arn:aws:iam::aws:policy/AdministratorAccess"]
    error_message = "the AdministratorAccess managed policy, and only it, must be attached by default"
  }

  assert {
    condition     = aws_ssoadmin_permission_set.this.tags == tomap({ Component = "identity-center-access" })
    error_message = "the permission set must carry the Component tag"
  }
}

run "one_user_assigned_in_one_account" {
  command = plan

  assert {
    condition     = aws_ssoadmin_account_assignment.this.principal_type == "USER"
    error_message = "the permission set must be assigned to the user directly, not to a group"
  }

  assert {
    condition     = aws_ssoadmin_account_assignment.this.target_type == "AWS_ACCOUNT" && aws_ssoadmin_account_assignment.this.target_id == "123456789012"
    error_message = "the assignment must target var.account_id"
  }

  assert {
    condition     = aws_ssoadmin_account_assignment.this.principal_id == aws_identitystore_user.this.user_id
    error_message = "the assignment must be for the module's user"
  }

  assert {
    condition     = aws_identitystore_user.this.user_name == "jwallace145" && aws_identitystore_user.this.display_name == "Jane Doe"
    error_message = "the user name comes from var.user and the display name defaults to given and family name"
  }

  assert {
    condition     = aws_identitystore_user.this.emails[0].value == "owner@example.com" && aws_identitystore_user.this.emails[0].primary == true
    error_message = "the email must be the user's primary email"
  }
}

run "no_other_account_by_default" {
  command = plan

  assert {
    condition     = length(aws_ssoadmin_account_assignment.additional) == 0
    error_message = "without additional_account_ids there must be exactly the one assignment"
  }

  assert {
    condition     = output.account_ids == ["123456789012"]
    error_message = "account_ids must list only account_id by default"
  }
}

run "the_same_permission_set_in_other_accounts" {
  command = plan

  variables {
    additional_account_ids = ["210987654321", "333333333333"]
  }

  assert {
    condition     = toset(keys(aws_ssoadmin_account_assignment.additional)) == toset(["210987654321", "333333333333"])
    error_message = "there must be one more assignment per additional account, keyed by its ID"
  }

  assert {
    condition = alltrue([
      for id, a in aws_ssoadmin_account_assignment.additional :
      a.target_type == "AWS_ACCOUNT" && a.target_id == id && a.principal_type == "USER" &&
      a.principal_id == aws_identitystore_user.this.user_id &&
      a.permission_set_arn == aws_ssoadmin_permission_set.this.arn
    ])
    error_message = "each additional assignment must give the module's user the module's permission set in that account"
  }

  assert {
    condition     = aws_ssoadmin_account_assignment.this.target_id == "123456789012"
    error_message = "the first account's assignment must not move"
  }

  assert {
    condition     = output.account_ids == ["123456789012", "210987654321", "333333333333"]
    error_message = "account_ids must list account_id, then the additional accounts in order"
  }
}

run "rejects_an_additional_account_that_repeats_the_first" {
  command = plan

  variables {
    additional_account_ids = ["123456789012"]
  }

  expect_failures = [var.additional_account_ids]
}

run "rejects_a_malformed_additional_account" {
  command = plan

  variables {
    additional_account_ids = ["prod"]
  }

  expect_failures = [var.additional_account_ids]
}

run "role_lookup_matches_the_permission_set" {
  command = plan

  assert {
    condition     = data.aws_iam_roles.provisioned.path_prefix == "/aws-reserved/sso.amazonaws.com/"
    error_message = "the role lookup must search Identity Center's reserved path"
  }

  assert {
    condition     = data.aws_iam_roles.provisioned.name_regex == "^AWSReservedSSO_AdministratorAccess_[0-9a-f]+$"
    error_message = "the role lookup must match only this permission set's role"
  }
}

run "custom_permission_set" {
  command = plan

  variables {
    permission_set_name = "ReadOnly"
    session_duration    = "PT12H"
    managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    user = {
      user_name    = "jwallace145"
      given_name   = "Jane"
      family_name  = "Doe"
      email        = "owner@example.com"
      display_name = "Owner"
    }
  }

  assert {
    condition     = aws_ssoadmin_permission_set.this.session_duration == "PT12H"
    error_message = "session_duration must be passed through"
  }

  assert {
    condition     = keys(aws_ssoadmin_managed_policy_attachment.this) == ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    error_message = "managed_policy_arns must replace the default"
  }

  assert {
    condition     = aws_identitystore_user.this.display_name == "Owner"
    error_message = "an explicit display_name must win"
  }
}

run "rejects_sub_hour_sessions" {
  command = plan

  variables {
    session_duration = "PT30M"
  }

  expect_failures = [var.session_duration]
}

run "rejects_sessions_over_twelve_hours" {
  command = plan

  variables {
    session_duration = "PT13H"
  }

  expect_failures = [var.session_duration]
}

run "rejects_fractional_hours" {
  command = plan

  variables {
    session_duration = "PT1H30M"
  }

  expect_failures = [var.session_duration]
}

run "rejects_a_malformed_instance_arn" {
  command = plan

  variables {
    instance_arn = "arn:aws:sso:::instance/ins-0123"
  }

  expect_failures = [var.instance_arn]
}

run "rejects_a_malformed_identity_store_id" {
  command = plan

  variables {
    identity_store_id = "0123456789"
  }

  expect_failures = [var.identity_store_id]
}

run "rejects_a_malformed_account_id" {
  command = plan

  variables {
    account_id = "12345"
  }

  expect_failures = [var.account_id]
}

run "rejects_wildcard_policies" {
  command = plan

  variables {
    managed_policy_arns = ["arn:aws:iam::aws:policy/*"]
  }

  expect_failures = [var.managed_policy_arns]
}

run "rejects_a_permission_set_name_that_would_need_escaping" {
  command = plan

  variables {
    permission_set_name = "Admin.Access"
  }

  expect_failures = [var.permission_set_name]
}
