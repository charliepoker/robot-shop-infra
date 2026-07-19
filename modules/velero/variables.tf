# modules/velero-s3/variables.tf

variable "name_prefix" {
  description = "Prefix for the bucket name (e.g. robot-shop)"
  type        = string
}

variable "environment" {
  description = "Environment label used in tags"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name (used for Pod Identity association and IAM naming)"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the S3 CMK used to encrypt backups (module.kms.s3_key_arn)"
  type        = string
}

variable "backup_retention_days" {
  description = <<-EOT
    Days to keep backup objects before lifecycle expiry.
    30 is a reasonable portfolio default — long enough to demo restore
    scenarios, short enough that storage cost stays near $2/mo.
    Production would tune this to the actual RPO/compliance requirement.
  EOT
  type        = number
  default     = 30
}

variable "namespace" {
  description = "Namespace Velero runs in (must match the Argo CD Application destination namespace)"
  type        = string
  default     = "velero"
}

variable "service_account" {
  description = "Velero ServiceAccount name (must match the Helm chart's serviceAccount name)"
  type        = string
  default     = "velero"
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {}
}
