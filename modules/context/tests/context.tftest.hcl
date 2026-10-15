mock_provider "aws" {}

variables {
  project     = "guitar"
  environment = "prod"
  repository  = "jwallace145/guitar"
}

run "derives_names" {
  command = plan

  assert {
    condition     = output.name_prefix == "jwall-engineering-guitar-prod"
    error_message = "name_prefix should be jwall-engineering-<project>-<environment>, got ${output.name_prefix}"
  }

  assert {
    condition     = output.bucket_name == "jwall-engineering-guitar"
    error_message = "bucket_name should be jwall-engineering-<project>, got ${output.bucket_name}"
  }
}

run "emits_required_tags" {
  command = plan

  assert {
    condition = output.tags == {
      Organization = "jwall-engineering"
      Project      = "guitar"
      Environment  = "prod"
      Repository   = "jwallace145/guitar"
      ManagedBy    = "terraform"
      Owner        = "jwallace145"
    }
    error_message = "tags should contain exactly the six required keys with default owner/organization"
  }
}

run "required_tags_win_over_extra_tags" {
  command = plan

  variables {
    extra_tags = {
      Project    = "not-guitar"
      ManagedBy  = "hand"
      CostCenter = "personal"
    }
  }

  assert {
    condition     = output.tags["Project"] == "guitar" && output.tags["ManagedBy"] == "terraform"
    error_message = "required tags must override conflicting extra_tags"
  }

  assert {
    condition     = output.tags["CostCenter"] == "personal"
    error_message = "non-conflicting extra_tags must be preserved"
  }
}

run "honours_owner_and_organization_overrides" {
  command = plan

  variables {
    owner        = "someone-else"
    organization = "other-org"
    environment  = "preview"
  }

  assert {
    condition     = output.tags["Owner"] == "someone-else" && output.tags["Organization"] == "other-org"
    error_message = "owner and organization inputs should flow into tags"
  }

  assert {
    condition     = output.name_prefix == "jwall-engineering-guitar-preview"
    error_message = "name_prefix must keep the jwall-engineering root regardless of the organization tag"
  }
}

run "rejects_non_kebab_project" {
  command = plan

  variables {
    project = "Guitar_Site"
  }

  expect_failures = [var.project]
}

run "rejects_unknown_environment" {
  command = plan

  variables {
    environment = "qa"
  }

  expect_failures = [var.environment]
}

run "rejects_malformed_repository" {
  command = plan

  variables {
    repository = "guitar"
  }

  expect_failures = [var.repository]
}
