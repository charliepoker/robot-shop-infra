# -----------------------------------------------------------------------------
# Dependency order (top = no deps, bottom = depends on everything above):
#
#   KMS       → no dependencies
#   Route53   → no dependencies
#   VPC       → no dependencies
#   ACM       → Route53 (needs zone_id)
#   EKS       → VPC (needs subnet IDs), KMS (EBS key)
#   Karpenter → EKS (needs cluster_name + OIDC provider ARN)
#   RDS       → VPC (intra subnets), KMS (RDS key)
#   ECR       → no dependencies
#   Secrets   → RDS (endpoint + generated password)
#   OIDC      → ECR (repo ARNs for IAM policy scope)
# -----------------------------------------------------------------------------


module "kms" {
  source = "../../modules/kms"

  name_prefix = var.name_prefix
  environment = var.environment
}

# ────—──—──—─ Route53 ─────────────────────────────────────────────────────────
# Public hosted zone for devopsportfolio.com
# Outputs consumed by: modules/acm (DNS validation), Phase 2 ExternalDNS

module "route53" {
  source = "../../modules/route53"

  domain_name = var.domain_name
  environment = var.environment
}

# ──────────────VPC ────────────────────────────────────────────────────────────
module "vpc" {
  source = "../../modules/vpc"

  name_prefix  = var.name_prefix
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr
  cluster_name = var.name_prefix
}

# ──────────── EKS ─────────────────────────────────────────────────────────────
module "eks" {
  source = "../../modules/eks"

  name_prefix        = var.name_prefix
  environment        = var.environment
  cluster_version    = var.cluster_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  ebs_kms_key_arn    = module.kms.ebs_key_arn
  node_instance_type = var.node_instance_type
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size
  node_desired_size  = var.node_desired_size
}

# ────────────── Karpenter ──────────────────────────────────────────────────────

module "karpenter" {
  source = "../../modules/karpenter"

  name_prefix       = var.name_prefix
  environment       = var.environment
  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  oidc_provider_arn = module.eks.oidc_provider_arn
}

# ── Task 7 — RDS MySQL ───────────────────────────────────────────────────────
# Added in Task 7

# module "rds" {
#   source = "../../modules/rds-mysql"
#
#   name_prefix        = var.name_prefix
#   environment        = var.environment
#   vpc_id             = module.vpc.vpc_id
#   db_subnet_ids      = module.vpc.intra_subnet_ids
#   kms_key_arn        = module.kms.rds_key_arn
#   db_name            = var.db_name
#   db_username        = var.db_username
# }

# ── Task 8 — ECR ─────────────────────────────────────────────────────────────
# Added in Task 8

# module "ecr" {
#   source = "../../modules/ecr"
#
#   repo_names  = var.ecr_repos
#   environment = var.environment
# }

# ── Task 8 — ACM ─────────────────────────────────────────────────────────────
# Added in Task 8

# module "acm" {
#   source = "../../modules/acm"
#
#   domain_name = var.domain_name
#   zone_id     = module.route53.zone_id
#   environment = var.environment
# }

# ── Task 9 — Secrets Manager ─────────────────────────────────────────────────
# Added in Task 9

# module "secrets_manager" {
#   source = "../../modules/secrets-manager"
#
#   name_prefix = var.name_prefix
#   environment = var.environment
#   db_host     = module.rds.db_endpoint
#   db_port     = module.rds.db_port
#   db_name     = var.db_name
#   db_username = var.db_username
#   db_password = module.rds.db_password
# }

# ── Task 9 — GitHub OIDC ─────────────────────────────────────────────────────
# Added in Task 9

# module "github_oidc" {
#   source = "../../modules/github-oidc"
#
#   name_prefix   = var.name_prefix
#   environment   = var.environment
#   github_org    = var.github_org
#   github_repo   = var.github_repo
#   ecr_repo_arns = module.ecr.repository_arns
# }
