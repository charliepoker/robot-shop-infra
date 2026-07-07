
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

# ── ECR ───────────────────────────────────────────────────────────────────────
# Uncommented in Task 8 (ecr module)

# variable "ecr_repos" {
#   description = "List of ECR repository names — one per Robot Shop microservice"
#   type        = list(string)
#   default = [
#     "cart",
#     "catalogue",
#     "dispatch",
#     "mongodb",
#     "mysql",
#     "payment",
#     "rabbitmq",
#     "ratings",
#     "shipping",
#     "user",
#     "web",
#   ]
# }

# ── GitHub OIDC ───────────────────────────────────────────────────────────────
# Uncommented in Task 9 (github-oidc module)

# variable "github_org" {
#   description = "GitHub organisation or username that owns the robot-shop repo"
#   type        = string
#   default     = "charliepoker"
# }

# variable "github_repo" {
#   description = "GitHub repository name for the application code"
#   type        = string
#   default     = "robot-shop"
# }
