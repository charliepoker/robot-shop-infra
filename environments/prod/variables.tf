
# ── Core ─────────────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment label (used in tags and resource names)"
  type        = string
  default     = "prod"
}

variable "name_prefix" {
  description = "Short prefix applied to resource names for uniqueness and readability"
  type        = string
  default     = "robot-shop"
}

# ── DNS ──────────────────────────────────────────────────────────────────────

variable "domain_name" {
  description = "Public domain name for the portfolio project"
  type        = string
  default     = "devopsportfolio.com"
}

# ── Networking ────────────────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# ── EKS ───────────────────────────────────────────────────────────────────────
variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.35"
}

variable "node_instance_type" {
  description = "EC2 instance type for the baseline managed node group"
  type        = string
  default     = "t3.medium"
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 5
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "cluster_admin_principal_arns" {
  description = <<-EOT
    IAM principal ARNs granted EKS cluster-admin via an explicit access entry.
    - ci_apply: the terraform-apply.yml OIDC role (AWS_APPLY_ROLE_ARN secret).
      This role is a bootstrap resource created outside this repo's Terraform
      (it has to exist before Terraform can run, so there's no module output
      to reference it by) — it's the identity that actually applies this stack.
    - obinna: personal IAM user, for local kubectl/Helm/Argo CD access.
  EOT
  type        = map(string)
  default = {
    ci_apply = "arn:aws:iam::448049792905:role/robot-shop-infra-github-actions"
    obinna   = "arn:aws:iam::448049792905:user/obinna"
  }
}

# ────────── RDS ───────────────────────────────────────────────────────────────────

variable "db_name" {
  description = "Name of the MySQL database to create inside the instance"
  type        = string
  default     = "robotshop"
}

variable "db_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "admin"
  sensitive   = true
}

# ─────────── ECR ───────────────────────────────────────────────────────────────────
variable "ecr_repos" {
  description = "List of ECR repository names — one per Robot Shop microservice"
  type        = list(string)
  default = [
    "cart",
    "catalogue",
    "dispatch",
    "mongodb",
    "mysql",
    "payment",
    "rabbitmq",
    "ratings",
    "shipping",
    "user",
    "web",
  ]
}

# ────────── GitHub OIDC ───────────────────────────────────────────────────────────────
variable "github_org" {
  description = "GitHub organisation or username that owns the robot-shop repo"
  type        = string
  default     = "charliepoker"
}

variable "github_repo" {
  description = "GitHub repository name for the application code"
  type        = string
  default     = "robot-shop"
}
