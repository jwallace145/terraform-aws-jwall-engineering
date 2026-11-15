mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  mock_data "aws_ssm_parameter" {
    defaults = {
      value = "ami-0123456789abcdef0"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/jwall-engineering-rusty-chess-bot"
    }
  }

  mock_resource "aws_instance" {
    defaults = {
      id  = "i-0123456789abcdef0"
      arn = "arn:aws:ec2:us-east-1:123456789012:instance/i-0123456789abcdef0"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/jwall-engineering/rusty-chess/bot"
    }
  }
}

variables {
  name                   = "jwall-engineering-rusty-chess-bot"
  project                = "rusty-chess"
  image_repository_url   = "123456789012.dkr.ecr.us-east-1.amazonaws.com/jwall-engineering-rusty-chess"
  image_repository_arn   = "arn:aws:ecr:us-east-1:123456789012:repository/jwall-engineering-rusty-chess"
  vpc_id                 = "vpc-0123"
  subnet_id              = "subnet-0123"
  secret_parameters      = { LICHESS_TOKEN = "/jwall-engineering/rusty-chess/lichess-token" }
  container_environment  = { ENGINE_HASH_MB = "128" }
  bot_name               = "rusty-chess-bot"
  records_bucket_name    = "jwall-engineering-rusty-chess-records"
  records_container_path = "/opt/lichess-bot/game_records"
  health_log_pattern     = "awaiting challenges"
}

# --- no schedule -------------------------------------------------------------

run "no_schedule_runs_all_the_time" {
  command = plan

  assert {
    condition     = length(aws_scheduler_schedule.start) == 0 && length(aws_scheduler_schedule.drain) == 0 && length(aws_scheduler_schedule.stop) == 0
    error_message = "without a schedule there are no schedules"
  }
  assert {
    condition     = length(aws_iam_role.scheduler) == 0 && output.schedule == null
    error_message = "without a schedule there is no scheduler role and no schedule output"
  }
  assert {
    condition     = aws_instance.this.instance_initiated_shutdown_behavior == "stop"
    error_message = "a power-off from inside stops the instance, never terminates it"
  }
}

# --- a schedule ----------------------------------------------------------------

run "daily_08_to_20" {
  command = plan

  variables {
    schedule = { days = "daily", start = "08:00", stop = "20:00" }
  }

  assert {
    condition     = aws_scheduler_schedule.start[0].schedule_expression == "cron(0 8 * * ? *)"
    error_message = "start at 08:00 every day"
  }
  assert {
    condition     = aws_scheduler_schedule.drain[0].schedule_expression == "cron(0 20 * * ? *)"
    error_message = "drain at 20:00 every day"
  }
  assert {
    condition     = aws_scheduler_schedule.stop[0].schedule_expression == "cron(0 21 * * ? *)"
    error_message = "hard stop drain_minutes (60) after the drain"
  }
  assert {
    condition = alltrue([
      for s in [aws_scheduler_schedule.start[0], aws_scheduler_schedule.drain[0], aws_scheduler_schedule.stop[0]] :
      s.schedule_expression_timezone == "UTC" && s.flexible_time_window[0].mode == "OFF" && s.group_name == "default"
    ])
    error_message = "every schedule is UTC, exact and in the default group"
  }
  assert {
    condition = [aws_scheduler_schedule.start[0].name, aws_scheduler_schedule.drain[0].name, aws_scheduler_schedule.stop[0].name] == [
      "jwall-engineering-rusty-chess-bot-start", "jwall-engineering-rusty-chess-bot-drain", "jwall-engineering-rusty-chess-bot-stop",
    ]
    error_message = "schedules are named <name>-start, -drain and -stop"
  }
  assert {
    condition     = aws_scheduler_schedule.start[0].target[0].arn == "arn:aws:scheduler:::aws-sdk:ec2:startInstances" && jsondecode(aws_scheduler_schedule.start[0].target[0].input) == { InstanceIds = ["i-0123456789abcdef0"] }
    error_message = "start calls ec2:StartInstances on this instance"
  }
  assert {
    condition     = aws_scheduler_schedule.stop[0].target[0].arn == "arn:aws:scheduler:::aws-sdk:ec2:stopInstances" && jsondecode(aws_scheduler_schedule.stop[0].target[0].input) == { InstanceIds = ["i-0123456789abcdef0"] }
    error_message = "stop calls ec2:StopInstances on this instance"
  }
  assert {
    condition = aws_scheduler_schedule.drain[0].target[0].arn == "arn:aws:scheduler:::aws-sdk:ssm:sendCommand" && jsondecode(aws_scheduler_schedule.drain[0].target[0].input) == {
      InstanceIds  = ["i-0123456789abcdef0"]
      DocumentName = "AWS-RunShellScript"
      Comment      = "scheduled drain"
      Parameters   = { commands = ["/usr/local/bin/container-reconcile-async --drain"], executionTimeout = ["120"] }
    }
    error_message = "drain runs container-reconcile --drain through the async wrapper"
  }
  assert {
    condition     = output.schedule.start.name == "jwall-engineering-rusty-chess-bot-start" && output.schedule.stop.expression == "cron(0 21 * * ? *)"
    error_message = "the schedule output names each schedule and its expression"
  }
}

run "scheduler_role_starts_drains_and_stops_only_this_instance" {
  command = plan

  variables {
    schedule = { days = "daily", start = "08:00", stop = "20:00" }
  }

  assert {
    condition     = aws_iam_role.scheduler[0].name == "jwall-engineering-rusty-chess-bot-scheduler"
    error_message = "the role is <name>-scheduler"
  }
  assert {
    condition = jsondecode(aws_iam_role.scheduler[0].assume_role_policy).Statement == [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = "123456789012" } }
    }]
    error_message = "only EventBridge Scheduler in this account may assume it"
  }
  assert {
    condition = jsondecode(aws_iam_role_policy.scheduler[0].policy).Statement == [
      {
        Sid      = "StartAndStopTheInstance"
        Effect   = "Allow"
        Action   = ["ec2:StartInstances", "ec2:StopInstances"]
        Resource = "arn:aws:ec2:us-east-1:123456789012:instance/i-0123456789abcdef0"
      },
      {
        Sid      = "DrainTheInstance"
        Effect   = "Allow"
        Action   = "ssm:SendCommand"
        Resource = ["arn:aws:ec2:us-east-1:123456789012:instance/i-0123456789abcdef0", "arn:aws:ssm:us-east-1::document/AWS-RunShellScript"]
      },
    ]
    error_message = "the role may start and stop this one instance and send it AWS-RunShellScript, nothing else"
  }
}

run "weekdays_on_the_quarter_hour" {
  command = plan

  variables {
    schedule      = { days = "weekdays", start = "07:45", stop = "19:30" }
    drain_minutes = 45
  }

  assert {
    condition = [aws_scheduler_schedule.start[0].schedule_expression, aws_scheduler_schedule.drain[0].schedule_expression, aws_scheduler_schedule.stop[0].schedule_expression] == [
      "cron(45 7 ? * MON-FRI *)", "cron(30 19 ? * MON-FRI *)", "cron(15 20 ? * MON-FRI *)",
    ]
    error_message = "weekdays run Monday to Friday, and the hard stop carries into the next hour"
  }
}

run "weekends" {
  command = plan

  variables {
    schedule = { days = "weekends", start = "10:00", stop = "22:00" }
  }

  assert {
    condition     = aws_scheduler_schedule.start[0].schedule_expression == "cron(0 10 ? * SAT,SUN *)" && aws_scheduler_schedule.stop[0].schedule_expression == "cron(0 23 ? * SAT,SUN *)"
    error_message = "weekends run Saturday and Sunday"
  }
}

run "the_limits_are_allowed" {
  command = plan

  variables {
    schedule      = { days = "daily", start = "02:45", stop = "22:45" }
    drain_minutes = 15
  }

  assert {
    condition     = aws_scheduler_schedule.stop[0].schedule_expression == "cron(0 23 * * ? *)"
    error_message = "a 20-hour window whose hard stop lands before midnight is allowed"
  }
}

# --- schedules that make no sense ----------------------------------------------

run "rejects_unknown_days" {
  command = plan

  variables {
    schedule = { days = "mondays", start = "08:00", stop = "20:00" }
  }

  expect_failures = [var.schedule]
}

run "rejects_not_a_quarter_hour" {
  command = plan

  variables {
    schedule = { days = "daily", start = "08:10", stop = "20:00" }
  }

  expect_failures = [var.schedule]
}

run "rejects_not_a_time" {
  command = plan

  variables {
    schedule = { days = "daily", start = "8am", stop = "20:00" }
  }

  expect_failures = [var.schedule]
}

run "rejects_hour_out_of_range" {
  command = plan

  variables {
    schedule = { days = "daily", start = "08:00", stop = "24:00" }
  }

  expect_failures = [var.schedule]
}

run "rejects_across_midnight" {
  command = plan

  variables {
    schedule = { days = "daily", start = "20:00", stop = "08:00" }
  }

  expect_failures = [var.schedule]
}

run "rejects_same_start_and_stop" {
  command = plan

  variables {
    schedule = { days = "daily", start = "08:00", stop = "08:00" }
  }

  expect_failures = [var.schedule]
}

run "rejects_shorter_than_4_hours" {
  command = plan

  variables {
    schedule = { days = "daily", start = "08:00", stop = "11:45" }
  }

  expect_failures = [var.schedule]
}

run "rejects_longer_than_20_hours" {
  command = plan

  variables {
    schedule = { days = "daily", start = "02:00", stop = "22:15" }
  }

  expect_failures = [var.schedule]
}

run "rejects_hard_stop_after_midnight" {
  command = plan

  variables {
    schedule = { days = "daily", start = "10:00", stop = "23:15" }
  }

  expect_failures = [var.schedule]
}

run "rejects_drain_pushes_the_hard_stop_past_midnight" {
  command = plan

  variables {
    schedule      = { days = "daily", start = "10:00", stop = "22:00" }
    drain_minutes = 120
  }

  expect_failures = [var.schedule]
}

run "rejects_a_drain_outside_15_to_120_minutes" {
  command = plan

  variables {
    schedule      = { days = "daily", start = "08:00", stop = "20:00" }
    drain_minutes = 5
  }

  expect_failures = [var.drain_minutes]
}
