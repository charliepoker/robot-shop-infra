# modules/aws-lb-controller/outputs.tf

output "iam_role_arn" {
  description = "IAM role ARN bound to kube-system/aws-load-balancer-controller via Pod Identity"
  value       = aws_iam_role.aws_lb_controller.arn
}

output "iam_policy_arn" {
  value = aws_iam_policy.aws_lb_controller.arn
}
