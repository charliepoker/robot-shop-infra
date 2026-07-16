# modules/external-dns/main.tf
#
# IAM policy + role + EKS Pod Identity association for ExternalDNS.
# Same auth pattern as the aws-lb-controller and karpenter modules
# (Pod Identity, not IRSA). Only creates the AWS/IAM side; the
# ExternalDNS deployment itself is an Argo CD Application
# (argocd/apps/external-dns.yaml).
#
# The policy is deliberately SCOPED to the single hosted zone rather
# than "*". ChangeResourceRecordSets is the write permission that lets
# ExternalDNS create/delete DNS records — you do not want that granted
# cluster-wide across every zone in the account. The list/get actions
# have to stay on "*" because the Route53 List APIs don't support
# resource-level permissions (worth knowing for an interview: "I scoped
# the mutating action to the zone; the read actions can't be scoped
# because Route53 doesn't support it on those APIs").

resource "aws_iam_policy" "external_dns" {
  name        = "ExternalDNS-${var.cluster_name}"
  description = "Allows ExternalDNS to manage records in the ${var.domain_name} hosted zone"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ChangeRecordsInHostedZone"
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets"
        ]
        Resource = [
          "arn:aws:route53:::hostedzone/${var.hosted_zone_id}"
        ]
      },
      {
        Sid    = "ListZonesAndRecords"
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResources"
        ]
        Resource = ["*"]
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role" "external_dns" {
  name = "external-dns-${var.cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  role       = aws_iam_role.external_dns.name
  policy_arn = aws_iam_policy.external_dns.arn
}

resource "aws_eks_pod_identity_association" "external_dns" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.external_dns.arn

  tags = var.tags
}
