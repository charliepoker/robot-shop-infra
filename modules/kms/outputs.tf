output "rds_key_arn" {
  description = "ARN of the RDS CMK — passed to modules/rds-mysql as kms_key_arn"
  value       = aws_kms_key.rds.arn
}

output "rds_key_id" {
  description = "Key ID of the RDS CMK"
  value       = aws_kms_key.rds.key_id
}

output "ebs_key_arn" {
  description = "ARN of the EBS CMK — passed to modules/eks for node volume encryption"
  value       = aws_kms_key.ebs.arn
}

output "ebs_key_id" {
  description = "Key ID of the EBS CMK"
  value       = aws_kms_key.ebs.key_id
}

output "s3_key_arn" {
  description = "ARN of the S3 CMK — used by the Velero backup bucket in Phase 2"
  value       = aws_kms_key.s3.arn
}

output "s3_key_id" {
  description = "Key ID of the S3 CMK"
  value       = aws_kms_key.s3.key_id
}
