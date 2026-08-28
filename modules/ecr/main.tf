resource "aws_ecr_repository" "this" {
  for_each = toset(var.repo_names)

  name                 = each.key
  image_tag_mutability = var.image_tag_mutability

  # Keep image tags immutable, but let cosign's sha256-*.sig/.att tags be
  # overwritten so re-signing an unchanged digest never hits TAG_INVALID.
  dynamic "image_tag_mutability_exclusion_filter" {
    for_each = endswith(var.image_tag_mutability, "WITH_EXCLUSION") ? var.mutable_tag_exclusions : []
    iterator = excl
    content {
      filter      = excl.value
      filter_type = "WILDCARD"
    }
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Environment = var.environment
    Service     = each.key
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.tagged_images_to_keep} tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.tagged_images_to_keep
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images after ${var.untagged_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expiry_days
        }
        action = { type = "expire" }
      },
    ]
  })
}
