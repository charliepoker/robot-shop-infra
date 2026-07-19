# modules/velero-s3/outputs.tf

output "bucket_name" {
  description = <<-EOT
    Backup bucket name.
    Paste into the Velero Helm values:
      configuration.backupStorageLocation[0].bucket
  EOT
  value       = aws_s3_bucket.velero.id
}

output "bucket_arn" {
  description = "Backup bucket ARN"
  value       = aws_s3_bucket.velero.arn
}

output "iam_role_arn" {
  description = "IAM role ARN bound to the velero service account via Pod Identity"
  value       = aws_iam_role.velero.arn
}

output "iam_policy_arn" {
  value = aws_iam_policy.velero.arn
}
