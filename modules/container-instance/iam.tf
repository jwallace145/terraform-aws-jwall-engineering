resource "aws_iam_role" "this" {
  name        = var.name
  description = "Instance role of ${var.name}: pull its image, read its secrets, report its state, write its logs and records"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      },
    ]
  })

  tags = local.tags
}

locals {
  secret_arns = [for k in sort(keys(var.secret_parameters)) : "arn:aws:ssm:${local.region}:${local.account_id}:parameter${var.secret_parameters[k]}"]

  instance_policy = {
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          # Docker login. The action has no resource-level support.
          Sid      = "GetEcrAuthorizationToken"
          Effect   = "Allow"
          Action   = "ecr:GetAuthorizationToken"
          Resource = "*"
        },
        {
          Sid    = "PullImages"
          Effect = "Allow"
          Action = [
            "ecr:BatchGetImage",
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchCheckLayerAvailability",
          ]
          Resource = var.image_repository_arn
        },
        {
          Sid    = "ReadWriteBotParameters"
          Effect = "Allow"
          Action = [
            "ssm:GetParameter",
            "ssm:PutParameter",
          ]
          Resource = "arn:aws:ssm:${local.region}:${local.account_id}:parameter${local.parameter_prefix}/*"
        },
        {
          Sid    = "WriteLogs"
          Effect = "Allow"
          Action = [
            "logs:CreateLogStream",
            "logs:PutLogEvents",
            "logs:DescribeLogStreams",
          ]
          Resource = [
            aws_cloudwatch_log_group.this.arn,
            "${aws_cloudwatch_log_group.this.arn}:*",
          ]
        },
      ],
      length(local.secret_arns) == 0 ? [] : [
        {
          # SecureString parameters encrypted with the default aws/ssm key,
          # which the key policy lets any principal in the account use
          # through SSM.
          Sid      = "ReadSecrets"
          Effect   = "Allow"
          Action   = "ssm:GetParameter"
          Resource = local.secret_arns
        },
      ],
      var.records_bucket_name == null ? [] : [
        {
          # Add only: never read back, never delete.
          Sid    = "WriteRecords"
          Effect = "Allow"
          Action = [
            "s3:PutObject",
            "s3:ListBucket",
          ]
          Resource = [
            "arn:aws:s3:::${var.records_bucket_name}",
            "arn:aws:s3:::${var.records_bucket_name}/${var.records_prefix}*",
          ]
        },
      ],
    )
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "${var.name}-instance"
  role   = aws_iam_role.this.id
  policy = jsonencode(local.instance_policy)
}

# Session Manager (shell access without SSH) and Run Command.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = var.name
  role = aws_iam_role.this.name

  tags = local.tags
}
