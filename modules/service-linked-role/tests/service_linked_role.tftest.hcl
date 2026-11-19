mock_provider "aws" {
  override_during = plan

  mock_resource "aws_iam_service_linked_role" {
    defaults = {
      arn  = "arn:aws:iam::123456789012:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot"
      name = "AWSServiceRoleForEC2Spot"
    }
  }
}

variables {
  aws_service_name = "spot.amazonaws.com"
}

run "role_is_linked_to_the_service" {
  command = plan

  assert {
    condition     = aws_iam_service_linked_role.this.aws_service_name == "spot.amazonaws.com"
    error_message = "the role must be linked to var.aws_service_name"
  }

  assert {
    condition     = aws_iam_service_linked_role.this.description == null
    error_message = "without description, the role's description stays unset"
  }

  assert {
    condition     = aws_iam_service_linked_role.this.tags == tomap({ Component = "iam" })
    error_message = "the role is tagged Component = iam by default"
  }
}

run "description_and_component_pass_through" {
  command = plan

  variables {
    description = "Default EC2 Spot Service Linked Role"
    component   = "tasks"
  }

  assert {
    condition     = aws_iam_service_linked_role.this.description == "Default EC2 Spot Service Linked Role"
    error_message = "description must be var.description"
  }

  assert {
    condition     = aws_iam_service_linked_role.this.tags["Component"] == "tasks"
    error_message = "component must set the Component tag"
  }
}

run "outputs_come_from_the_role" {
  command = plan

  assert {
    condition     = output.name == "AWSServiceRoleForEC2Spot"
    error_message = "name must be the role's name"
  }

  assert {
    condition     = output.arn == "arn:aws:iam::123456789012:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot"
    error_message = "arn must be the role's ARN"
  }
}

run "rejects_a_non_service_principal" {
  command = plan

  variables {
    aws_service_name = "arn:aws:iam::123456789012:role/foo"
  }

  expect_failures = [var.aws_service_name]
}

run "rejects_an_empty_component" {
  command = plan

  variables {
    component = ""
  }

  expect_failures = [var.component]
}
