variable "name_prefix" {
  description = "Prefix applied to all KMS key aliases (e.g. robot-shop-prod)"
  type        = string
}

variable "environment" {
  description = "Environment label used in tags"
  type        = string
}

variable "deletion_window_in_days" {
  description = "Days AWS holds a deleted key before permanently destroying it. Minimum is 7."
  type        = number
  default     = 7
}
