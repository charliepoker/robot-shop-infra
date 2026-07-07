data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# ── IAM Role for EBS CSI Driver (Pod Identity) ───────────────────────────────

data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
    ]
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.name_prefix}-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json

  tags = {
    Name        = "${var.name_prefix}-ebs-csi-driver"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ── EKS Cluster ───────────────────────────────────────────────────────────────

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  # ── Cluster Identity ──────────────────────────────────────────────────────
  name               = var.name_prefix
  kubernetes_version = var.cluster_version

  # ── Network ───────────────────────────────────────────────────────────────
  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Public endpoint allows kubectl from your laptop.
  # Private endpoint means nodes talk to the API server without going
  # through NAT — stays on the AWS backbone.
  endpoint_public_access  = true
  endpoint_private_access = true

  # ── Authentication ────────────────────────────────────────────────────────
  # Access entry gives the Terraform caller cluster-admin automatically.
  # No aws-auth ConfigMap editing required — that approach is deprecated.
  enable_cluster_creator_admin_permissions = true

  # OIDC provider for IRSA — kept enabled because some Phase 2 tools
  # (cert-manager, ExternalDNS older charts) still reference it.
  # Pod Identity and IRSA coexist without conflict.
  enable_irsa = true

  # ── Secrets Encryption ────────────────────────────────────────────────────
  # Encrypts Kubernetes Secrets in etcd using our KMS CMK.
  # Without this, Secrets are base64 in etcd — not encrypted at rest.
  encryption_config = {
    provider_key_arn = var.ebs_kms_key_arn
    resources        = ["secrets"]
  }

  # ── Control Plane Logs ────────────────────────────────────────────────────
  enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # ── Addons ────────────────────────────────────────────────────────────────
  # before_compute = true: install before nodes join to avoid race conditions
  #   vpc-cni must exist before nodes join — it provides pod IP addresses
  #   eks-pod-identity-agent must exist before any pod needs AWS credentials
  #
  # aws-ebs-csi-driver: now has a pod_identity_association block pointing
  #   at the IAM role we created above. Without this the controller pod
  #   has no credentials and the addon never reaches ACTIVE state.
  addons = {
    coredns = {
      most_recent = true
    }

    kube-proxy = {
      most_recent = true
    }

    vpc-cni = {
      most_recent    = true
      before_compute = true
    }

    eks-pod-identity-agent = {
      most_recent    = true
      before_compute = true
    }

    aws-ebs-csi-driver = {
      most_recent = true
      pod_identity_association = [{
        role_arn        = aws_iam_role.ebs_csi.arn
        service_account = "ebs-csi-controller-sa"
        namespace       = "kube-system"
      }]
    }
  }

  # ── Managed Node Group ────────────────────────────────────────────────────
  eks_managed_node_groups = {
    baseline = {
      name           = "${var.name_prefix}-baseline"
      instance_types = [var.node_instance_type]

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      # AL2023 is mandatory from EKS 1.33+ — AL2 AMIs no longer published
      ami_type = "AL2023_x86_64_STANDARD"

      # Encrypt root volumes with the EBS CMK
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 50
            volume_type           = "gp3"
            encrypted             = true
            kms_key_id            = var.ebs_kms_key_arn
            delete_on_termination = true
          }
        }
      }

      labels = {
        role        = "baseline"
        environment = var.environment
      }

      tags = {
        "karpenter.sh/discovery" = var.name_prefix
      }
    }
  }

  tags = {
    Environment              = var.environment
    "karpenter.sh/discovery" = var.name_prefix
  }
}