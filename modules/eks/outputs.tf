output "cluster_name" {
  description = "EKS cluster name — used in aws eks update-kubeconfig and by the Karpenter module"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server URL — passed to the Karpenter module and Helm providers"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster"
  value       = module.eks.cluster_version
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded CA certificate — needed for kubeconfig and Helm provider config"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group attached to the EKS control plane — add rules here to allow node access"
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Security group attached to worker nodes — used in RDS SG ingress rules "
  value       = module.eks.node_security_group_id
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN — consumed by Karpenter module and any IRSA roles"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider" {
  description = "OIDC provider URL without https:// — used in IAM trust policy conditions"
  value       = module.eks.oidc_provider
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN for the EKS control plane"
  value       = module.eks.cluster_iam_role_arn
}
