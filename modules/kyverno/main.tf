# modules/kyverno/main.tf
# IAM role + EKS Pod Identity association giving the Kyverno admission
# controller READ-ONLY ECR access, so its verifyImages policy can fetch the
# cosign .sig/.att artifacts (and resolve tag->digest for mutateDigest) from
# the private registry. Same Pod Identity pattern as external-dns / karpenter.

resource "aws_iam_role" "kyverno" {
  name = "kyverno-${var.cluster_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
  tags = var.tags
}

# Read-only ECR. Managed policy keeps it simple; scope to your repo ARNs later
# if you want to match the least-privilege ethos of the other modules.
resource "aws_iam_role_policy_attachment" "kyverno_ecr_read" {
  role       = aws_iam_role.kyverno.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_pod_identity_association" "kyverno" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.kyverno.arn
  tags            = var.tags
}
