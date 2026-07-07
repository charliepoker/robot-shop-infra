# ── Controller role ──────────────────────────────────────────────────────────

output "role_arn" {
  description = <<-EOT
    Karpenter controller IAM role ARN.
    Set this as the Helm value:
      serviceAccount.annotations."eks\.amazonaws\.com/role-arn"
    Only needed if you fall back to IRSA. With Pod Identity this is
    automatically associated — the annotation is not required.
    Useful to record for audit purposes.
  EOT
  value = module.karpenter.iam_role_arn
}

output "role_name" {
  description = "Karpenter controller IAM role name"
  value       = module.karpenter.iam_role_name
}

# ── Node role ─────────────────────────────────────────────────────────────────

output "node_iam_role_name" {
  description = <<-EOT
    Node IAM role name.
    Referenced in the EC2NodeClass manifest in Phase 2:
      spec:
        role: <this value>
  EOT
  value = module.karpenter.node_iam_role_name
}

output "node_iam_role_arn" {
  description = "Node IAM role ARN"
  value       = module.karpenter.node_iam_role_arn
}

output "instance_profile_name" {
  description = <<-EOT
    EC2 instance profile name.
    Wraps the node IAM role so EC2 instances can assume it.
    Also referenced in the EC2NodeClass if you pin the instance profile
    explicitly instead of using the role name.
  EOT
  value = module.karpenter.instance_profile_name
}

# ── Interruption handling ─────────────────────────────────────────────────────

output "queue_name" {
  description = <<-EOT
    SQS queue name for Spot interruption events.
    MUST match the Helm value settings.interruptionQueue in Phase 2.
    Defaults to the cluster name — verify this matches before installing.
  EOT
  value = module.karpenter.queue_name
}

output "queue_arn" {
  description = "SQS queue ARN"
  value       = module.karpenter.queue_arn
}

output "queue_url" {
  description = "SQS queue URL"
  value       = module.karpenter.queue_url
}

# ── Convenience outputs for Phase 2 Helm values ───────────────────────────────

output "helm_values_summary" {
  description = <<-EOT
    Key values needed for the Karpenter Helm chart in Phase 2.
    Record these after apply — you will paste them into the ArgoCD
    helm-values file for Karpenter.
  EOT
  value = {
    cluster_name       = var.cluster_name
    cluster_endpoint   = var.cluster_endpoint
    queue_name         = module.karpenter.queue_name
    node_role_name     = module.karpenter.node_iam_role_name
    controller_role_arn = module.karpenter.iam_role_arn
  }
}
