# GitHub's OIDC provider — tells AWS to trust JWTs issued by GitHub Actions.
# Only one of these should exist per AWS account. If you already have one
# from another project, import it:
#   terraform import aws_iam_openid_connect_provider.github <arn>
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  # The audience that GitHub JWTs are issued for when calling AWS STS
  client_id_list = ["sts.amazonaws.com"]

  # SHA-1 thumbprint of GitHub's OIDC TLS certificate root CA.
  # AWS uses this to verify the JWKS endpoint when validating tokens.
  # This value is stable — GitHub rarely rotates its CA.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# IAM role that GitHub Actions assumes
resource "aws_iam_role" "github_actions" {
  name        = "${var.name_prefix}-github-actions"
  description = "Assumed by GitHub Actions via OIDC for ECR push/pull - no static credentials"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GitHubOIDCTrust"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${var.github_branch}"
          }
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
  }
}

# ECR permissions
resource "aws_iam_role_policy" "ecr" {
  name = "${var.name_prefix}-ecr-push-pull"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:ListImages",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Resource = var.ecr_repo_arns
      }
    ]
  })
}
