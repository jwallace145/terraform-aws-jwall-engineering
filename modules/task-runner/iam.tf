resource "aws_iam_role" "this" {
  name        = local.name
  description = "Task instances of ${var.project}: run commands, write task logs and results"

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

resource "aws_iam_role_policy" "this" {
  name = "${local.name}-instance"
  role = aws_iam_role.this.id

  # A task runs pull request code, so the instance can only write: no read
  # of earlier results, no images, no parameters, no secrets.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteTaskLogs"
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
      {
        Sid      = "WriteTaskResults"
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::${local.results_bucket}/${local.results_prefix}*"
      },
    ]
  })
}

# Run Command and Session Manager.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = local.name
  role = aws_iam_role.this.name

  tags = local.tags
}
