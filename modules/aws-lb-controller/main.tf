# modules/aws-lb-controller/main.tf
#
# IAM policy + role + EKS Pod Identity association for the AWS Load
# Balancer Controller. Mirrors the same auth pattern already used by
# the karpenter module (Pod Identity, not IRSA/OIDC) — so this assumes
# the EKS Pod Identity Agent addon is already installed on the cluster
# (it should be, since karpenter depends on it too).
#
# This module ONLY creates the IAM side. The controller itself is
# deployed as an Argo CD Application (see argocd/apps/aws-lb-controller.yaml)
# — keeping "who can assume what AWS role" in Terraform and "what's
# running in the cluster" in GitOps is a decent line to have ready if
# an interviewer asks where you draw that boundary.

resource "aws_iam_policy" "aws_lb_controller" {
  name        = "AWSLoadBalancerController-${var.cluster_name}"
  description = "Permissions for the AWS Load Balancer Controller to manage ALBs/NLBs on behalf of Kubernetes Ingress/Service objects"
  policy      = file("${path.module}/iam-policy.json")

  tags = var.tags
}

resource "aws_iam_role" "aws_lb_controller" {
  name = "aws-lb-controller-${var.cluster_name}"

  # Pod Identity trust policy — NOT the OIDC federated-principal trust
  # policy you'd use for IRSA. The eks.amazonaws.com Pod Identity
  # service assumes this role on behalf of the pod, and the
  # aws_eks_pod_identity_association below is what maps a specific
  # namespace/service-account to it.
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

resource "aws_iam_role_policy_attachment" "aws_lb_controller" {
  role       = aws_iam_role.aws_lb_controller.name
  policy_arn = aws_iam_policy.aws_lb_controller.arn
}

resource "aws_eks_pod_identity_association" "aws_lb_controller" {
  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.aws_lb_controller.arn

  tags = var.tags
}
