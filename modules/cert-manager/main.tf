# modules/cert-manager/main.tf
#
# IAM policy + role + EKS Pod Identity association for cert-manager's
# Route53 DNS-01 solver. Same Pod Identity pattern as aws-lb-controller
# and external-dns. Only the AWS/IAM side lives here; cert-manager
# itself (controller, webhook, cainjector, CRDs) is deployed as an
# Argo CD Application, and the ClusterIssuers are separate manifests.
#
# How cert-manager uses this role: with EKS Pod Identity, the
# cert-manager controller pod receives "ambient" AWS credentials
# (AWS_REGION + a token are injected by the Pod Identity agent).
# ClusterIssuers use ambient credentials BY DEFAULT — so the Route53
# solver block in the ClusterIssuer needs no role/accessKey, and
# cert-manager needs no --issuer-ambient-credentials flag (that flag
# only matters for namespace-scoped Issuers).
#
# Policy scoping (this is the official cert-manager Route53 policy,
# tightened to the single zone where possible):
#   - GetChange on change/* : cert-manager polls the change status
#     after writing the TXT record; change IDs aren't zone-scopable.
#   - ChangeResourceRecordSets / ListResourceRecordSets on the ONE
#     hosted zone : the actual TXT-record create/delete for the ACME
#     challenge, scoped so cert-manager can't touch other zones.
#   - ListHostedZonesByName on * : zone lookup; the List APIs don't
#     support resource-level permissions.

resource "aws_iam_policy" "cert_manager" {
  name        = "CertManager-${var.cluster_name}"
  description = "Allows cert-manager to solve ACME DNS-01 challenges in the ${var.domain_name} hosted zone"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "GetChangeStatus"
        Effect   = "Allow"
        Action   = ["route53:GetChange"]
        Resource = ["arn:aws:route53:::change/*"]
      },
      {
        Sid    = "ChangeRecordsInHostedZone"
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets"
        ]
        Resource = ["arn:aws:route53:::hostedzone/${var.hosted_zone_id}"]
      },
      {
        Sid      = "ListZonesByName"
        Effect   = "Allow"
        Action   = ["route53:ListHostedZonesByName"]
        Resource = ["*"]
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role" "cert_manager" {
  name = "cert-manager-${var.cluster_name}"

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

resource "aws_iam_role_policy_attachment" "cert_manager" {
  role       = aws_iam_role.cert_manager.name
  policy_arn = aws_iam_policy.cert_manager.arn
}

resource "aws_eks_pod_identity_association" "cert_manager" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.cert_manager.arn

  tags = var.tags
}
