variable "name_prefix" {
  description = "Prefix for resource names (e.g. robot-shop)"
  type        = string
}

variable "environment" {
  description = "Environment label used in names and tags"
  type        = string
}

variable "protected_hostnames" {
  description = "Public hostnames fronted by ALB Cognito authentication. Each becomes an allowed OAuth callback: https://<host>/oauth2/idpresponse"
  type        = list(string)

  validation {
    condition     = length(var.protected_hostnames) > 0
    error_message = "At least one protected hostname is required, otherwise the ALB cannot complete the login redirect."
  }
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {}
}
