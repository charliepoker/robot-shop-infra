# .tflint.hcl
#
# TFLint configuration file.
# Enables the AWS ruleset which knows about valid EC2 instance types,
# RDS engine versions, EKS Kubernetes versions, and other provider-specific
# constraints that terraform validate cannot check (it only checks syntax,
# not whether the values are valid in AWS).
#
# call_module_type = "all": lints inside module calls, not just root modules.
# This is important for our structure where most resources are in modules.

config {
  call_module_type = "all"
}

plugin "aws" {
  enabled = true
  version = "0.40.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
