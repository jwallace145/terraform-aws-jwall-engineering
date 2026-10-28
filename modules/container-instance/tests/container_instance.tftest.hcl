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

run "ami_from_public_parameter" {
  command = plan

  assert {
    condition     = data.aws_ssm_parameter.ami.name == "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
    error_message = "x86_64 uses the latest Amazon Linux 2023 x86_64 AMI"
  }
}

run "ami_for_arm64" {
  command = plan

  variables {
    architecture  = "arm64"
    instance_type = "t4g.micro"
  }

  assert {
    condition     = data.aws_ssm_parameter.ami.name == "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
    error_message = "arm64 uses the latest Amazon Linux 2023 arm64 AMI"
  }
}

run "instance_shape" {
  command = plan

  assert {
    condition = (
      aws_instance.this.ami == "ami-0123456789abcdef0" &&
      aws_instance.this.instance_type == "t3.micro" &&
      aws_instance.this.subnet_id == "subnet-0123" &&
      aws_instance.this.associate_public_ip_address == true &&
      aws_instance.this.user_data_replace_on_change == true &&
      aws_instance.this.monitoring == false
    )
    error_message = "one t3.micro with a public IP in the given subnet"
  }

  assert {
    condition     = aws_instance.this.metadata_options[0].http_tokens == "required" && aws_instance.this.metadata_options[0].http_endpoint == "enabled"
    error_message = "IMDSv2 only"
  }

  assert {
    condition     = aws_instance.this.credit_specification[0].cpu_credits == "standard"
    error_message = "burst credits are standard, so a busy engine can never run up unlimited-mode charges"
  }

  assert {
    condition = (
      aws_instance.this.root_block_device[0].volume_type == "gp3" &&
      aws_instance.this.root_block_device[0].volume_size == 16 &&
      aws_instance.this.root_block_device[0].encrypted == true &&
      aws_instance.this.root_block_device[0].delete_on_termination == true
    )
    error_message = "16 GB encrypted gp3 root volume"
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].tags == tomap({ Name = "jwall-engineering-rusty-chess-bot", Component = "container-instance" })
    error_message = "the root volume does not inherit default_tags; it must be tagged explicitly for cost allocation"
  }

  assert {
    condition     = aws_instance.this.tags == tomap({ Name = "jwall-engineering-rusty-chess-bot", Component = "container-instance" })
    error_message = "the instance carries Name and Component tags"
  }
}

run "no_ingress" {
  command = plan

  assert {
    condition = (
      aws_vpc_security_group_egress_rule.all_ipv4.cidr_ipv4 == "0.0.0.0/0" &&
      aws_vpc_security_group_egress_rule.all_ipv4.ip_protocol == "-1"
    )
    error_message = "egress to the internet only"
  }

  assert {
    condition = (
      aws_security_group.this.name == "jwall-engineering-rusty-chess-bot" &&
      aws_security_group.this.vpc_id == "vpc-0123" &&
      aws_security_group.this.tags == tomap({ Name = "jwall-engineering-rusty-chess-bot", Component = "container-instance" })
    )
    error_message = "the security group is named after the instance"
  }
}

run "instance_role" {
  command = plan

  assert {
    condition = (
      aws_iam_role.this.name == "jwall-engineering-rusty-chess-bot" &&
      jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal.Service == "ec2.amazonaws.com" &&
      aws_iam_instance_profile.this.name == "jwall-engineering-rusty-chess-bot" &&
      aws_iam_role_policy_attachment.ssm.policy_arn == "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    )
    error_message = "an EC2 role and instance profile named after the instance, with Session Manager core"
  }

  assert {
    condition = (
      [for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s if s.Sid == "PullImages"][0].Resource == "arn:aws:ecr:us-east-1:123456789012:repository/jwall-engineering-rusty-chess" &&
      jsonencode(sort([for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s if s.Sid == "PullImages"][0].Action)) == jsonencode(sort(["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]))
    )
    error_message = "pull from the one repository"
  }

  assert {
    condition     = [for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s if s.Sid == "ReadSecrets"][0].Action == "ssm:GetParameter" && jsonencode([for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s if s.Sid == "ReadSecrets"][0].Resource) == jsonencode(["arn:aws:ssm:us-east-1:123456789012:parameter/jwall-engineering/rusty-chess/lichess-token"])
    error_message = "read exactly the declared secret parameters"
  }

  assert {
    condition = (
      jsonencode(sort([for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s if s.Sid == "ReadWriteBotParameters"][0].Action)) == jsonencode(sort(["ssm:GetParameter", "ssm:PutParameter"])) &&
      [for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s if s.Sid == "ReadWriteBotParameters"][0].Resource == "arn:aws:ssm:us-east-1:123456789012:parameter/jwall-engineering/rusty-chess/bot/*"
    )
    error_message = "read and write the bot's own parameters"
  }

  assert {
    condition = (
      jsonencode(sort([for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s if s.Sid == "WriteRecords"][0].Action)) == jsonencode(sort(["s3:PutObject", "s3:ListBucket"])) &&
      jsonencode([for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s if s.Sid == "WriteRecords"][0].Resource) == jsonencode(["arn:aws:s3:::jwall-engineering-rusty-chess-records", "arn:aws:s3:::jwall-engineering-rusty-chess-records/records/*"])
    )
    error_message = "write records under the prefix only"
  }

  assert {
    condition = (
      jsonencode(sort([for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s if s.Sid == "WriteLogs"][0].Action)) == jsonencode(sort(["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"])) &&
      jsonencode([for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s if s.Sid == "WriteLogs"][0].Resource) == jsonencode(["arn:aws:logs:us-east-1:123456789012:log-group:/jwall-engineering/rusty-chess/bot", "arn:aws:logs:us-east-1:123456789012:log-group:/jwall-engineering/rusty-chess/bot:*"])
    )
    error_message = "write to the one log group"
  }

  assert {
    condition     = sort([for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s.Sid if s.Resource == "*"]) == tolist(["GetEcrAuthorizationToken"])
    error_message = "only the Docker login token may use Resource = *"
  }

  assert {
    condition     = !anytrue([for a in flatten([for s in jsondecode(aws_iam_role_policy.this.policy).Statement : tolist(flatten([s.Action]))]) : contains(["s3:GetObject", "s3:DeleteObject", "ssm:DeleteParameter"], a)])
    error_message = "the instance never reads back or deletes records, and never deletes parameters"
  }
}

run "log_group" {
  command = plan

  assert {
    condition = (
      aws_cloudwatch_log_group.this.name == "/jwall-engineering/rusty-chess/bot" &&
      aws_cloudwatch_log_group.this.retention_in_days == 30 &&
      aws_cloudwatch_log_group.this.tags == tomap({ Name = "/jwall-engineering/rusty-chess/bot", Component = "container-instance" })
    )
    error_message = "one log group per bot with 30-day retention"
  }
}

run "user_data_carries_the_config" {
  command = plan

  assert {
    condition     = startswith(aws_instance.this.user_data, "#cloud-config")
    error_message = "user data is cloud-config"
  }

  assert {
    condition     = can(yamldecode(aws_instance.this.user_data))
    error_message = "user data must be valid YAML, or cloud-init skips all of it"
  }

  assert {
    condition = (
      length(yamldecode(aws_instance.this.user_data).write_files) == 8 &&
      startswith([for f in yamldecode(aws_instance.this.user_data).write_files : f.content if f.path == "/etc/container-instance/config.env"][0], "AWS_REGION='us-east-1'\nBOT_NAME=")
    )
    error_message = "cloud-init must see all eight files, and config.env must start with its first setting"
  }

  assert {
    condition = alltrue([for line in [
      "PARAMETER_PREFIX='/jwall-engineering/rusty-chess/bot'",
      "IMAGE_REPOSITORY='123456789012.dkr.ecr.us-east-1.amazonaws.com/jwall-engineering-rusty-chess'",
      "SECRET_PARAMETERS='LICHESS_TOKEN=/jwall-engineering/rusty-chess/lichess-token'",
      "CONTAINER_ENV='ENGINE_HASH_MB=128'",
      "RECORDS_BUCKET='jwall-engineering-rusty-chess-records'",
      "RECORDS_PREFIX='records/'",
      "RECORDS_CONTAINER_PATH='/opt/lichess-bot/game_records'",
      "HEALTH_LOG_PATTERN='awaiting challenges'",
      "HEALTH_SECONDS='90'",
      "STOP_SIGNAL='SIGINT'",
      "STOP_POLL_SECONDS='15'",
      "LOG_GROUP='/jwall-engineering/rusty-chess/bot'",
      "BOT_NAME='rusty-chess-bot'",
      "AWS_REGION='us-east-1'",
    ] : strcontains(aws_instance.this.user_data, line)])
    error_message = "config.env must carry every setting, shell-quoted"
  }

  assert {
    condition = alltrue([for unit in [
      "container-reconcile.service",
      "container-records-sync.timer",
      "container-records-final.service",
      "OnUnitActiveSec=10min",
      "TimeoutStartSec=infinity",
      "encoding: gz+b64",
    ] : strcontains(aws_instance.this.user_data, unit)])
    error_message = "user data installs the units and the compressed scripts"
  }

  assert {
    condition     = length(aws_instance.this.user_data) < 16384
    error_message = "EC2 user data is limited to 16 KB"
  }
}

run "outputs" {
  command = plan

  assert {
    condition = (
      output.parameter_prefix == "/jwall-engineering/rusty-chess/bot" &&
      output.parameter_names.desired_version == "/jwall-engineering/rusty-chess/bot/desired-version" &&
      output.parameter_names.running_version == "/jwall-engineering/rusty-chess/bot/running-version" &&
      output.parameter_names.status == "/jwall-engineering/rusty-chess/bot/status" &&
      output.parameter_names.last_sync == "/jwall-engineering/rusty-chess/bot/last-sync" &&
      output.records_uri == "s3://jwall-engineering-rusty-chess-records/records/" &&
      output.log_group_name == "/jwall-engineering/rusty-chess/bot" &&
      output.instance_id == "i-0123456789abcdef0" &&
      output.role_name == "jwall-engineering-rusty-chess-bot"
    )
    error_message = "outputs describe the instance, its parameters, logs and records"
  }
}

run "no_records" {
  command = plan

  variables {
    records_bucket_name    = null
    records_container_path = null
  }

  assert {
    condition     = length([for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s if s.Sid == "WriteRecords"]) == 0
    error_message = "no records bucket, no S3 permissions"
  }

  assert {
    condition     = output.records_uri == null && strcontains(aws_instance.this.user_data, "RECORDS_BUCKET=''")
    error_message = "the sync is disabled without a bucket"
  }
}

run "no_secrets" {
  command = plan

  variables {
    secret_parameters = {}
  }

  assert {
    condition     = length([for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s if s.Sid == "ReadSecrets"]) == 0
    error_message = "no secrets, no ReadSecrets statement"
  }
}

run "rejects_secret_outside_project_path" {
  command = plan

  variables {
    secret_parameters = { X = "/other/path" }
  }

  expect_failures = [var.secret_parameters]
}

run "rejects_secret_under_bot_prefix" {
  command = plan

  variables {
    secret_parameters = { X = "/jwall-engineering/rusty-chess/bot/token" }
  }

  expect_failures = [var.secret_parameters]
}

run "rejects_records_without_path" {
  command = plan

  variables {
    records_container_path = null
  }

  expect_failures = [var.records_container_path]
}

run "rejects_bad_retention" {
  command = plan

  variables {
    log_retention_days = 31
  }

  expect_failures = [var.log_retention_days]
}
