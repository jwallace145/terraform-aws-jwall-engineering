data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  prefix     = "${var.name_root}-${var.project}"

  # Write-only: the matching read (scheduler:GetSchedule) is in container/read.
  # Its own policy because container/manage is close to the 6,144-character
  # limit of a managed policy.
  policy = {
    Version = "2012-10-17"
    Statement = [
      {
        # The instance's start, drain and stop schedules (container-instance
        # `schedule`), named <prefix>-...; schedules carry no tags.
        Sid    = "ManageProjectSchedules"
        Effect = "Allow"
        Action = [
          "scheduler:CreateSchedule",
          "scheduler:UpdateSchedule",
          "scheduler:DeleteSchedule",
        ]
        Resource = "arn:aws:scheduler:${local.region}:${local.account_id}:schedule/default/${local.prefix}-*"
      },
      {
        # The role those schedules run as, and only to EventBridge Scheduler.
        Sid       = "PassSchedulerRole"
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = "arn:aws:iam::${local.account_id}:role/${local.prefix}-*-scheduler"
        Condition = { StringEquals = { "iam:PassedToService" = "scheduler.amazonaws.com" } }
      },
    ]
  }
}

resource "aws_iam_policy" "this" {
  name        = var.name
  description = "CI policy container/schedule: manage the start, drain and stop schedules of the project's instance and pass their role to EventBridge Scheduler"
  policy      = jsonencode(local.policy)

  tags = {
    Component = "ci"
  }
}
