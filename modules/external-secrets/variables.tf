# modules/external-secrets/variables.tf

variable "cluster_name" {
  description = "EKS cluster name (used for Pod Identity association and IAM naming)"
  type        = string
}

variable "secret_arns" {
  description = "List of Secrets Manager secret ARNs ESO is allowed to read (e.g. [module.secrets_manager.secret_arn])"
  type        = list(string)
}

variable "kms_key_arn" {
  description = "ARN of the KMS CMK the secrets are encrypted with (module.kms.s3_key_arn). Required for kms:Decrypt."
  type        = string
}

variable "namespace" {
  description = "Namespace ESO runs in (must match the Argo CD Application destination namespace)"
  type        = string
  default     = "external-secrets"
}

variable "service_account" {
  description = "ESO controller ServiceAccount name (must match the Helm chart's serviceAccount.name)"
  type        = string
  default     = "external-secrets"
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {}
}
