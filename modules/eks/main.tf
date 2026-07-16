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
  # No aws-auth ConfigMap editing required — access entries are the
  # modern replacement for that. Admin access is granted explicitly via
  # cluster_admin_principal_arns rather than enable_cluster_creator_admin_permissions,
  # since that flag ties admin to whichever identity happens to run
  # `terraform apply` and causes an access-entry replacement (not just a
  # diff) any time a different principal — a human vs. the CI role — runs it.
  enable_cluster_creator_admin_permissions = false

  access_entries = {
    for key, principal_arn in var.cluster_admin_principal_arns : key => {
      principal_arn = principal_arn
      policy_associations = {
        admin = {
          policy_arn = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # OIDC provider for IRSA — kept enabled because some Phase 2 tools
  # (cert-manager, ExternalDNS older charts) still reference it.
  # Pod Identity and IRSA coexist without conflict.
  enable_irsa = true

  # The KMS key this module creates for envelope-encrypting Secrets defaults
  # its key administrators to whichever identity runs `terraform apply` —
  # same underlying pattern as enable_cluster_creator_admin_permissions
  # above. Pin it explicitly so the key policy doesn't drift every time a
  # different principal (human vs. CI role) runs Terraform.
  kms_key_administrators = values(var.cluster_admin_principal_arns)

  # ── Secrets Encryption ────────────────────────────────────────────────────
  # Encrypts Kubernetes Secrets in etcd. Without this, Secrets are base64 in
  # etcd — not encrypted at rest.
  #
  # NOTE: provider_key_arn below is currently NOT the key actually in use.
  # create_kms_key defaults to true in the upstream module, so it creates
  # and uses its own CMK for this and ignores provider_key_arn. Switching
  # to var.ebs_kms_key_arn (create_kms_key = false) would change the live
  # cluster's encryption_config.provider.key_arn in place, but every Secret
  # already written stays wrapped under the old CMK — that key would need
  # every existing Secret rewritten under the new key before its deletion
  # window elapses. Deferred as a real migration, not a config toggle.
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
