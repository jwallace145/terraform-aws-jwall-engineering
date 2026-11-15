# The instance's running hours (var.schedule), with EventBridge Scheduler and
# no Lambda:
#
#   <name>-start  at start   ec2:StartInstances
#   <name>-drain  at stop    Run Command: container-reconcile --drain, which lets
#                            the container finish (the bot ends its game), ships
#                            its records and powers off; shutdown means stop
#   <name>-stop   at stop + drain_minutes   ec2:StopInstances, in case the
#                            drain is still waiting or never ran
#
# All three run in UTC on the same days. Stopping a stopped instance, or
# sending the drain to one, does nothing harmful. Nothing here keeps a started
# instance running: a start by hand outside the window lasts until the next
# drain.

locals {
  scheduled = var.schedule != null

  minutes = local.scheduled ? {
    start = tonumber(substr(var.schedule.start, 0, 2)) * 60 + tonumber(substr(var.schedule.start, 3, 2))
    drain = tonumber(substr(var.schedule.stop, 0, 2)) * 60 + tonumber(substr(var.schedule.stop, 3, 2))
    stop  = tonumber(substr(var.schedule.stop, 0, 2)) * 60 + tonumber(substr(var.schedule.stop, 3, 2)) + var.drain_minutes
  } : {}

  # cron(minutes hours day-of-month month day-of-week year); one day field is `?`.
  cron_days = local.scheduled ? {
    daily    = "* * ? *"
    weekdays = "? * MON-FRI *"
    weekends = "? * SAT,SUN *"
  }[var.schedule.days] : ""

  schedule_expressions = {
    for k, m in local.minutes : k => "cron(${m % 60} ${floor(m / 60)} ${local.cron_days})"
  }

  instance_arn = "arn:aws:ec2:${local.region}:${local.account_id}:instance/${aws_instance.this.id}"
  run_shell    = "arn:aws:ssm:${local.region}::document/AWS-RunShellScript"

  scheduler_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StartAndStopTheInstance"
        Effect   = "Allow"
        Action   = ["ec2:StartInstances", "ec2:StopInstances"]
        Resource = local.instance_arn
      },
      {
        Sid      = "DrainTheInstance"
        Effect   = "Allow"
        Action   = "ssm:SendCommand"
        Resource = [local.instance_arn, local.run_shell]
      },
    ]
  }
}

resource "aws_iam_role" "scheduler" {
  count = local.scheduled ? 1 : 0

  name        = "${var.name}-scheduler"
  description = "Starts, drains and stops ${var.name} on its schedule"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "scheduler.amazonaws.com" }
        Action    = "sts:AssumeRole"
        Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
      },
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "scheduler" {
  count = local.scheduled ? 1 : 0

  name   = "start-drain-stop"
  role   = aws_iam_role.scheduler[0].id
  policy = jsonencode(local.scheduler_policy)
}

resource "aws_scheduler_schedule" "start" {
  count = local.scheduled ? 1 : 0

  name                         = "${var.name}-start"
  description                  = "Start ${var.name} (${var.schedule.days}, ${var.schedule.start} UTC)"
  schedule_expression          = local.schedule_expressions.start
  group_name                   = "default"
  schedule_expression_timezone = "UTC"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:startInstances"
    role_arn = aws_iam_role.scheduler[0].arn
    input    = jsonencode({ InstanceIds = [aws_instance.this.id] })

    retry_policy {
      maximum_event_age_in_seconds = 900
      maximum_retry_attempts       = 3
    }
  }

  depends_on = [aws_iam_role_policy.scheduler]
}

resource "aws_scheduler_schedule" "drain" {
  count = local.scheduled ? 1 : 0

  name                         = "${var.name}-drain"
  description                  = "Drain and power off ${var.name} (${var.schedule.days}, ${var.schedule.stop} UTC)"
  schedule_expression          = local.schedule_expressions.drain
  group_name                   = "default"
  schedule_expression_timezone = "UTC"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ssm:sendCommand"
    role_arn = aws_iam_role.scheduler[0].arn
    input = jsonencode({
      InstanceIds  = [aws_instance.this.id]
      DocumentName = "AWS-RunShellScript"
      Comment      = "scheduled drain"
      Parameters = {
        # Returns at once: the drain runs as its own unit, like a deploy.
        commands         = ["/usr/local/bin/container-reconcile-async --drain"]
        executionTimeout = ["120"]
      }
    })

    retry_policy {
      maximum_event_age_in_seconds = 900
      maximum_retry_attempts       = 3
    }
  }

  depends_on = [aws_iam_role_policy.scheduler]
}

resource "aws_scheduler_schedule" "stop" {
  count = local.scheduled ? 1 : 0

  name                         = "${var.name}-stop"
  description                  = "Stop ${var.name} if the drain has not (${var.schedule.days}, ${var.drain_minutes} min after ${var.schedule.stop} UTC)"
  schedule_expression          = local.schedule_expressions.stop
  group_name                   = "default"
  schedule_expression_timezone = "UTC"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.scheduler[0].arn
    input    = jsonencode({ InstanceIds = [aws_instance.this.id] })

    retry_policy {
      maximum_event_age_in_seconds = 900
      maximum_retry_attempts       = 3
    }
  }

  depends_on = [aws_iam_role_policy.scheduler]
}
