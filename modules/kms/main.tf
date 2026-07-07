
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# ── EBS Key Policy ────────────────────────────────────────────────────────────
# Must grant the Auto Scaling service-linked role both key USE and CreateGrant
# permissions before any node group with encrypted volumes can be created.

data "aws_iam_policy_document" "ebs" {
  # Statement 1: Allow the account root to administer the key
  # (required — without this, no IAM principal can manage the key at all)
  statement {
    sid    = "EnableRootAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Statement 2: Allow EC2 Auto Scaling to USE the key for EBS encryption
  # AWSServiceRoleForAutoScaling is the role ASGs use when launching instances
  statement {
    sid    = "AllowAutoScalingServiceLinkedRole"
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = [
        "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
      ]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }

  # Statement 3: Allow Auto Scaling to CreateGrant (CRITICAL)
  # EC2 creates grants so the hypervisor can decrypt volume data keys at
  # runtime without a live IAM call on every disk I/O. Without this statement
  # the node launches but immediately fails because the hypervisor cannot
  # access the key to decrypt the root volume's data key.
  # kms:GrantIsForAWSResource ensures grants can only be created for use
  # by AWS services — it cannot be used to grant access to arbitrary principals.
  statement {
    sid    = "AllowAutoScalingCreateGrant"
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = [
        "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
      ]
    }
    actions = [
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant",
    ]
    resources = ["*"]
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}

# ── RDS Key Policy ────────────────────────────────────────────────────────────
# RDS manages its own grants to access CMKs. The default key policy (root
# account access) is sufficient — RDS calls CreateGrant itself as part of
# the instance creation process and is covered by the root statement.

data "aws_iam_policy_document" "rds" {
  statement {
    sid    = "EnableRootAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }
}

# ── S3 Key Policy ─────────────────────────────────────────────────────────────
# S3 access is via IAM roles (Velero, Terraform) which are covered by the
# default root-account policy. No service-linked role involved.

data "aws_iam_policy_document" "s3" {
  statement {
    sid    = "EnableRootAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }
}

# ── KMS Keys ──────────────────────────────────────────────────────────────────

resource "aws_kms_key" "ebs" {
  description             = "CMK for EKS node EBS volumes — ${var.name_prefix}"
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.ebs.json

  tags = {
    Name        = "${var.name_prefix}-ebs"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/${var.name_prefix}-ebs"
  target_key_id = aws_kms_key.ebs.key_id
}

resource "aws_kms_key" "rds" {
  description             = "CMK for RDS MySQL — ${var.name_prefix}"
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.rds.json

  tags = {
    Name        = "${var.name_prefix}-rds"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.name_prefix}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

resource "aws_kms_key" "s3" {
  description             = "CMK for S3 buckets — Velero and Terraform state"
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.s3.json

  tags = {
    Name        = "${var.name_prefix}-s3"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.name_prefix}-s3"
  target_key_id = aws_kms_key.s3.key_id
}
