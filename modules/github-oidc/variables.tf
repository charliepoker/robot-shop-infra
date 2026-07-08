variable "name_prefix" {
  description = "Resource name prefix"
  type        = string
}

variable "environment" {
  description = "Environment label used in tags"
  type        = string
}

variable "github_org" {
  description = "GitHub organisation or username that owns the robot-shop repo"
  type        = string
  default     = "charliepoker"
}

variable "github_repo" {
  description = "GitHub repository name for the application source code"
  type        = string
  default     = "robot-shop"
}

variable "github_branch" {
  description = <<-EOT
    Branch that is allowed to assume the CI role.
    robot-shop uses 'master' (forked from instana/robot-shop which uses master).
    robot-shop-infra uses 'main'.
    The trust policy is scoped to this branch only — PRs from forks
    or feature branches cannot assume the role and push to ECR.
  EOT
  type        = string
  default     = "master"
}

variable "ecr_repo_arns" {
  description = <<-EOT
    List of ECR repository ARNs the CI role is allowed to push and pull.
    Scoped to your specific repos — the role cannot touch any other
    ECR repo in the account even if someone modifies the workflow.
    Comes from module.ecr.repository_arns.
  EOT
  type        = list(string)
}
