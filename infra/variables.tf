variable "aws_region" {
  description = "Region where the AWS project is deployed."
  type        = string
  default     = "ap-south-1"
}
variable "notification_email" {
  description = "Optional SNS alert destination. Leave empty to skip email subscription."
  type        = string
  default     = ""
}
variable "github_oidc_subject" {
  description = "Exact GitHub OIDC sub claim (includes owner/repository IDs for repos created after 2026-07-15). Empty disables GitHub role."
  type        = string
  default     = ""
}
