
# -----------------------------------------------------------------------------
# 
#
# Creates three Customer-Managed Keys (CMKs):
#
#   rds  — encrypts the RDS MySQL instance and its automated snapshots
#   ebs  — encrypts EKS node root volumes and any Kubernetes PersistentVolumes
#   s3   — encrypts S3 buckets (Velero backups, and optionally the state bucket)
#
# Why CMKs instead of AWS-managed keys?
#   AWS-managed keys are free but you have no control over the key policy,
#   no ability to restrict which IAM principals can decrypt, and CloudTrail
#   doesn't show per-operation detail. CMKs give you all three — and
#   annual key rotation is a single argument at no extra cost.
#
# Outputs from this module are consumed by:
#   modules/rds-mysql   → rds_key_arn  (storage_encrypted + kms_key_id)
#   modules/eks         → ebs_key_arn  (node group block device encryption)
#   Phase 2 Velero S3   → s3_key_arn   (bucket server-side encryption)
# -----------------------------------------------------------------------------

resource "aws_kms_key" "rds" {
  description             = "CMK for RDS MySQL encryption — ${var.name_prefix}"
  deletion_window_in_days = var.deletion_window_in_days

  # AWS rotates the backing key material annually at no cost.
  # Your key ID and ARN never change — nothing needs to be re-encrypted.
  enable_key_rotation = true

  tags = {
    Name        = "${var.name_prefix}-rds"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "rds" {
  # Aliases make it easy to identify keys in the console and CLI
  name          = "alias/${var.name_prefix}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

# -----------------------------------------------------------------------------

resource "aws_kms_key" "ebs" {
  description             = "CMK for EBS volumes — EKS node root disks and PersistentVolumes"
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true

  tags = {
    Name        = "${var.name_prefix}-ebs"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/${var.name_prefix}-ebs"
  target_key_id = aws_kms_key.ebs.key_id
}

# -----------------------------------------------------------------------------

resource "aws_kms_key" "s3" {
  description             = "CMK for S3 buckets — Velero backups and Terraform state"
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true

  tags = {
    Name        = "${var.name_prefix}-s3"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.name_prefix}-s3"
  target_key_id = aws_kms_key.s3.key_id
}
