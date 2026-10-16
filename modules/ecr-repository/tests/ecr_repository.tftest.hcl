mock_provider "aws" {
  override_during = plan

  mock_resource "aws_ecr_repository" {
    defaults = {
      arn            = "arn:aws:ecr:us-east-1:123456789012:repository/jwall-engineering-sites"
      repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/jwall-engineering-sites"
      registry_id    = "123456789012"
    }
  }
}

variables {
  name = "jwall-engineering-sites"
}

run "repository_hardening" {
  command = plan

  assert {
    condition     = aws_ecr_repository.this.name == "jwall-engineering-sites"
    error_message = "repository name must be var.name"
  }

  assert {
    condition     = aws_ecr_repository.this.image_tag_mutability == "IMMUTABLE"
    error_message = "tags must be immutable so a release tag can never be moved"
  }

  assert {
    condition     = aws_ecr_repository.this.force_delete == false
    error_message = "the repository must not be force-deletable"
  }

  assert {
    condition     = aws_ecr_repository.this.image_scanning_configuration[0].scan_on_push == true
    error_message = "images must be scanned on push"
  }

  assert {
    condition     = aws_ecr_repository.this.encryption_configuration[0].encryption_type == "AES256"
    error_message = "images must be encrypted with AES256"
  }

  assert {
    condition     = aws_ecr_repository.this.tags == tomap({ Name = "jwall-engineering-sites", Component = "ecr-repository" })
    error_message = "the repository must carry Name and Component tags only"
  }
}

run "lifecycle_policy_defaults" {
  command = plan

  assert {
    condition     = aws_ecr_lifecycle_policy.this.repository == "jwall-engineering-sites"
    error_message = "the lifecycle policy must attach to the repository"
  }

  assert {
    condition = (
      jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[0].selection.tagStatus == "untagged" &&
      jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[0].selection.countType == "sinceImagePushed" &&
      jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[0].selection.countNumber == 7
    )
    error_message = "rule 1 must expire untagged images 7 days after push by default"
  }

  assert {
    condition = (
      jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[1].selection.tagStatus == "tagged" &&
      jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[1].selection.tagPrefixList == ["v"] &&
      jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[1].selection.countType == "imageCountMoreThan" &&
      jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[1].selection.countNumber == 20
    )
    error_message = "rule 2 must keep the 20 newest v* images by default"
  }
}

run "lifecycle_policy_custom" {
  command = plan

  variables {
    keep_release_images        = 5
    expire_untagged_after_days = 1
    release_tag_prefixes       = ["release-"]
  }

  assert {
    condition = (
      jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[0].selection.countNumber == 1 &&
      jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[1].selection.countNumber == 5 &&
      jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[1].selection.tagPrefixList == ["release-"]
    )
    error_message = "lifecycle values must come from the variables"
  }
}

run "outputs" {
  command = plan

  assert {
    condition = (
      output.arn == "arn:aws:ecr:us-east-1:123456789012:repository/jwall-engineering-sites" &&
      output.url == "123456789012.dkr.ecr.us-east-1.amazonaws.com/jwall-engineering-sites" &&
      output.name == "jwall-engineering-sites" &&
      output.registry_id == "123456789012"
    )
    error_message = "outputs must describe the repository"
  }
}

run "rejects_uppercase_name" {
  command = plan

  variables {
    name = "Jwall-Sites"
  }

  expect_failures = [var.name]
}

run "rejects_zero_keep" {
  command = plan

  variables {
    keep_release_images = 0
  }

  expect_failures = [var.keep_release_images]
}
