# Backup bucket + IAM + Pod Identity association for Velero.
# This is the ONLY new Terraform module in Phase 2 — everything else in
# the phase is GitOps. Velero itself is an Argo CD Application.
#
# Layering note for interviews: Terraform owns the bucket and the IAM
# (AWS-account-level, must survive a cluster rebuild); Argo CD owns the
# Velero deployment. If the cluster is destroyed, the BACKUPS must still
# exist — which is exactly why the bucket is Terraform-managed and not
# something the cluster creates for itself.

data "aws_caller_identity" "current" {}

# ── Backup bucket ─────────────────────────────────────────────────────────────
# Bucket names are globally unique, so the account ID is appended.

resource "aws_s3_bucket" "velero" {
  bucket = "${var.name_prefix}-velero-backups-${data.aws_caller_identity.current.account_id}"

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-velero-backups"
    Environment = var.environment
    Purpose     = "velero-backups"
  })
}

# Block all public access — backups contain Secrets. Non-negotiable.
resource "aws_s3_bucket_public_access_block" "velero" {
  bucket = aws_s3_bucket.velero.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Encrypt at rest with the S3 CMK created in Phase 1 (its description
# literally says "Velero and Terraform state"). bucket_key_enabled
# reduces KMS API call costs on high object counts.
resource "aws_s3_bucket_server_side_encryption_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

# Versioning protects against a corrupted/overwritten backup object.
resource "aws_s3_bucket_versioning" "velero" {
  bucket = aws_s3_bucket.velero.id

  versioning_configuration {
    status = "Enabled"
  }
}

# COST CONTROL: backups accumulate forever otherwise. Expire current
# objects after N days and clean up noncurrent versions + aborted
# multipart uploads. This is the difference between "~$2/mo for backups"
# and a slowly growing bill nobody notices.
resource "aws_s3_bucket_lifecycle_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id

  # Explicit dependency: versioning must be on before noncurrent-version
  # rules are meaningful.
  depends_on = [aws_s3_bucket_versioning.velero]

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    filter {}

    expiration {
      days = var.backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ── IAM ───────────────────────────────────────────────────────────────────────

resource "aws_iam_policy" "velero" {
  name        = "Velero-${var.cluster_name}"
  description = "Allows Velero to write backups to S3 and manage EBS volume snapshots"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Object-level operations inside the backup bucket only.
        Sid    = "BackupObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ]
        Resource = ["${aws_s3_bucket.velero.arn}/*"]
      },
      {
        # Bucket-level: Velero lists to discover existing backups.
        Sid      = "BackupBucketAccess"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [aws_s3_bucket.velero.arn]
      },
      {
        # SSE-KMS writes need GenerateDataKey, not just Encrypt. Same
        # class of gotcha as ESO needing kms:Decrypt — omit this and
        # backups fail with an opaque AccessDenied that looks like S3.
        Sid    = "EncryptDecryptBackups"
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = [var.kms_key_arn]
      },
      {
        # EBS volume snapshots for PersistentVolume data. Snapshot APIs
        # don't support meaningful resource-level scoping, hence "*".
        Sid    = "VolumeSnapshots"
        Effect = "Allow"
        Action = [
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:CreateSnapshot",
          "ec2:DeleteSnapshot"
        ]
        Resource = ["*"]
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role" "velero" {
  name = "velero-${var.cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "pods.eks.amazonaws.com" }
        Action    = ["sts:AssumeRole", "sts:TagSession"]
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "velero" {
  role       = aws_iam_role.velero.name
  policy_arn = aws_iam_policy.velero.arn
}

resource "aws_eks_pod_identity_association" "velero" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.velero.arn

  tags = var.tags
}
