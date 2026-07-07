module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name = var.cluster_name

  # Create the Pod Identity association between the controller IAM role
  # and the karpenter service account. This is what lets the Karpenter
  # pod get AWS credentials when it starts — no annotation required.
  create_pod_identity_association = true

  # Stable node IAM role name — must match spec.role in the EC2NodeClass
  # manifest you write in Phase 2. A name-prefix-generated name would
  # change on every recreation and break the manifest.
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "${var.cluster_name}-karpenter-node"

  # SSM access lets you connect to Karpenter-launched nodes for debugging
  # without needing SSH keys or a bastion host. Highly recommended for
  # chaos engineering scenarios in Phase 7.
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  # SQS queue + EventBridge rules for Spot interruption handling.
  # Queue name defaults to the cluster name — must match the Helm value
  # settings.interruptionQueue in Phase 2.
  enable_spot_termination = true

  tags = {
    Environment = var.environment
    Cluster     = var.cluster_name
  }
}
