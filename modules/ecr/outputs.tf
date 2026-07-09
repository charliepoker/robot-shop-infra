output "repository_urls" {
  description = <<-EOT
    Map of service name to ECR repository URL.
    Used in GitHub Actions CI to construct the push destination:
      docker push <url>:<sha>
    Example: { "cart" = "448049792905.dkr.ecr.us-east-1.amazonaws.com/cart" }
  EOT
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "repository_arns" {
  description = <<-EOT
    List of all ECR repository ARNs.
    Passed to modules/github-oidc to scope the CI IAM policy to only
    these specific repos — not all ECR repos in the account.
  EOT
  value       = [for v in aws_ecr_repository.this : v.arn]
}

output "registry_id" {
  description = "AWS account ID that owns the registries (same for all repos in an account)"
  value       = values(aws_ecr_repository.this)[0].registry_id
}

output "registry_url" {
  description = <<-EOT
    Base ECR registry URL (without repo name).
    Used in GitHub Actions for docker login:
      aws ecr get-login-password | docker login --username AWS --password-stdin <registry_url>
  EOT
  value       = "${values(aws_ecr_repository.this)[0].registry_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com"
}

data "aws_region" "current" {}
