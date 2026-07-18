# How ESO uses this: with Pod Identity, the ESO controller pod receives
# ambient AWS credentials. The ClusterSecretStore is configured WITHOUT
# an explicit serviceAccountRef, so ESO's AWS provider falls back to the
# controller pod's credentials (the Pod Identity ones). No IRSA, no keys.
#
# CRITICAL detail: the RDS secret is encrypted with a customer-managed
# KMS key (the S3 CMK). Secrets Manager decrypts transparently on read,
# but ONLY if the caller can use the key — so this policy needs
# kms:Decrypt on that CMK IN ADDITION to secretsmanager:GetSecretValue.
# Omitting the KMS permission is the classic "AccessDenied that isn't
# about Secrets Manager" bug.

resource "aws_iam_policy" "external_secrets" {
  name        = "ExternalSecrets-${var.cluster_name}"
  description = "Allows External Secrets Operator to read the Robot Shop secrets and decrypt them with the CMK"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        # Scoped to exactly the secret ARNs passed in — ESO can't read
        # any other secret in the account.
        Resource = var.secret_arns
      },
      {
        Sid    = "DecryptWithCMK"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = [var.kms_key_arn]
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role" "external_secrets" {
  name = "external-secrets-${var.cluster_name}"

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

resource "aws_iam_role_policy_attachment" "external_secrets" {
  role       = aws_iam_role.external_secrets.name
  policy_arn = aws_iam_policy.external_secrets.arn
}

resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.external_secrets.arn

  tags = var.tags
}
