resource "aws_ecr_repository" "this" {
  name = var.name

  # Release tags are exact versions; a tag can never be moved to another image.
  image_tag_mutability = "IMMUTABLE"

  # A repository that still holds images cannot be destroyed by accident.
  force_delete = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name      = var.name
    Component = var.component
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images ${var.expire_untagged_after_days} days after they are pushed"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.expire_untagged_after_days
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep the ${var.keep_release_images} newest release images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = var.release_tag_prefixes
          countType     = "imageCountMoreThan"
          countNumber   = var.keep_release_images
        }
        action = {
          type = "expire"
        }
      },
    ]
  })
}
