mock_provider "aws" {
  override_during = plan
}

variables {
  name           = "jwall-engineering-infra-ci-apply-ecr-push"
  repository_arn = "arn:aws:ecr:us-east-1:123456789012:repository/jwall-engineering-sites"
}

run "push_to_one_repository" {
  command = plan

  assert {
    condition = (
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Resource if s.Sid == "PushImages"][0] == "arn:aws:ecr:us-east-1:123456789012:repository/jwall-engineering-sites" &&
      contains([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Sid], "GetEcrAuthorizationToken")
    )
    error_message = "ecr/push must log in and push to the one repository"
  }

  assert {
    condition = alltrue([
      for a in [for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Action if s.Sid == "PushImages"][0] :
      !can(regex("Delete|Create|Put(Lifecycle|Registry|Repository|ImageTag|ImageScanning)|SetRepositoryPolicy", a))
    ])
    error_message = "ecr/push must not be able to manage the repository, only its images"
  }

  assert {
    condition = sort([
      for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Sid if s.Resource == "*"
    ]) == tolist(["GetEcrAuthorizationToken"])
    error_message = "only GetAuthorizationToken may use Resource = *"
  }
}

# `description` forces replacement of the policy, which would detach it from
# every role mid-apply. It is frozen; change the README instead.
run "description_is_frozen" {
  command = plan

  assert {
    condition     = aws_iam_policy.this.description == "CI policy ecr/push: log in to ECR and push images to one repository"
    error_message = "the policy description must never change: it forces replacement"
  }
}
