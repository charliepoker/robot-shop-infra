

# ──—──—──—──—──—──—──—──—──— KMS ───────────────────────────────────────
output "kms_rds_key_arn" {
  description = "KMS CMK ARN for RDS — console: KMS > Customer managed keys"
  value       = module.kms.rds_key_arn
}

output "kms_ebs_key_arn" {
  description = "KMS CMK ARN for EBS volumes"
  value       = module.kms.ebs_key_arn
}

output "kms_s3_key_arn" {
  description = "KMS CMK ARN for S3 buckets"
  value       = module.kms.s3_key_arn
}

# ────—──—──—──—──—──—──—──— Route53 ────────────────────────────────────

output "route53_zone_id" {
  description = "Hosted zone ID — used by ACM and ExternalDNS"
  value       = module.route53.zone_id
}

output "route53_name_servers" {
  description = "Route53 nameservers for the hosted zone"
  value       = module.route53.name_servers
}

#────────────── VPC ───────────────────────────────────────────────────────────

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

# ────────────EKS ─────────────────────────────────────────────────────────────
output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

# ────────────── Karpenter ──────────────────────────────────────────────────────

output "karpenter_role_arn" {
  value = module.karpenter.role_arn
}

output "karpenter_queue_name" {
  value = module.karpenter.queue_name
}

# ── Task 7 — RDS ─────────────────────────────────────────────────────────────

# output "db_endpoint" {
#   value = module.rds.db_endpoint
# }

# output "db_port" {
#   value = module.rds.db_port
# }

# ── Task 8 — ECR + ACM ───────────────────────────────────────────────────────

# output "ecr_repository_urls" {
#   value = module.ecr.repository_urls
# }

# output "acm_certificate_arn" {
#   value = module.acm.certificate_arn
# }

# ── Task 9 — Secrets + OIDC ──────────────────────────────────────────────────

# output "rds_secret_arn" {
#   value = module.secrets_manager.secret_arn
# }

# output "github_actions_role_arn" {
#   value = module.github_oidc.role_arn
# }
