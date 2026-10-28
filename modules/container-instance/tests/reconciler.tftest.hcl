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

run "reconciler_contract" {
  command = plan

  assert {
    condition     = startswith(output.reconciler_script, "#!/usr/bin/env bash\nset -euo pipefail\n")
    error_message = "bash with strict mode"
  }

  assert {
    condition     = length(regexall("docker kill", output.reconciler_script)) == length(regexall("docker kill --signal=", output.reconciler_script)) && !strcontains(output.reconciler_script, "docker stop")
    error_message = "the only way the reconciler stops a container is one stop signal; never docker stop, never a bare docker kill"
  }

  assert {
    condition     = strcontains(output.reconciler_script, "docker update --restart=no app")
    error_message = "the restart policy is cleared before the stop signal"
  }

  assert {
    condition     = strcontains(output.reconciler_script, "\n  flock 9\n") && !strcontains(output.reconciler_script, "flock -n")
    error_message = "one reconcile at a time, and a second one waits instead of dropping a newer deploy"
  }

  assert {
    condition     = alltrue([for s in ["status_soft \"waiting:", "status ok", "status_soft \"rolling-back:", "status \"failed:"] : strcontains(output.reconciler_script, s)])
    error_message = "every documented status value is written"
  }

  assert {
    condition     = strcontains(output.reconciler_script, "docker ps --filter \"name=^app$\"")
    error_message = "convergence inspects the running container, not just the parameters"
  }

  assert {
    condition     = length(regexall("records_sync", output.reconciler_script)) >= 3
    error_message = "the records are synced before the stop signal and after the container exits"
  }

  assert {
    condition     = strcontains(output.reconciler_script, "--log-driver awslogs") && strcontains(output.reconciler_script, "--env-file")
    error_message = "logs go to CloudWatch; secrets reach the container through an env file"
  }

  assert {
    condition     = strcontains(output.reconciler_script, "trap 'on_error $LINENO' ERR")
    error_message = "an unexpected failure still ends in a terminal failed: status"
  }

  assert {
    condition     = !strcontains(lower(output.reconciler_script), "lichess")
    error_message = "the reconciler is generic"
  }

  assert {
    condition     = strcontains(output.reconciler_script, "$RECORDS_ROOT/$tag")
    error_message = "each version writes records into its own directory"
  }
}

run "records_sync_contract" {
  command = plan

  assert {
    condition = (
      startswith(output.records_sync_script, "#!/usr/bin/env python3") &&
      strcontains(output.records_sync_script, "SCHEMA = 1") &&
      !strcontains(output.records_sync_script, "--delete")
    )
    error_message = "the records sync is versioned and never deletes"
  }
}
