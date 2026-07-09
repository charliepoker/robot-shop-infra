variable "cluster_name" {
  description = <<-EOT
    EKS cluster name. The Karpenter submodule uses this to:
    - Name the SQS queue (must match the Helm value settings.interruptionQueue)
    - Tag resources for discovery
    - Create the access entry allowing Karpenter-launched nodes to join the cluster
  EOT
  type        = string
}

variable "cluster_endpoint" {
  description = <<-EOT
    EKS API server URL. Written into the Helm chart values at deploy time so
    Karpenter knows which cluster to talk to without relying on the default
    kubeconfig. This avoids a hard dependency on a local ~/.kube/config during
    CI/CD pipelines.
  EOT
  type        = string
}



variable "environment" {
  description = "Environment label used in tags"
  type        = string
}

# variable "oidc_provider_arn" {
#   description = <<-EOT
#     EKS OIDC provider ARN. Kept here for reference and future IRSA use.
#     The Karpenter submodule itself uses Pod Identity (not IRSA) so this is
#     not passed to the submodule — but it is exported as an output in case
#     other resources in this module need it later.
#   EOT
#   type        = string
# }

# variable "name_prefix" {
#   description = "Resource name prefix used for tagging and naming supplementary resources"
#   type        = string
# }

# variable "environment" {
#   description = "Environment label used in tags"
#   type        = string
# }

# variable "karpenter_namespace" {
#   description = <<-EOT
#     Kubernetes namespace where Karpenter will be installed via Helm.
#     Must match the namespace used in the Pod Identity association.
#     "kube-system" is the AWS-recommended namespace — it avoids creating
#     an additional namespace and keeps all platform components together.
#   EOT
#   type        = string
#   default     = "kube-system"
# }

# variable "karpenter_service_account" {
#   description = "Karpenter controller service account name — must match the Helm chart default"
#   type        = string
#   default     = "karpenter"
# }
