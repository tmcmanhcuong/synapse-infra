variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "synapse"
}

variable "environment" {
  description = "Deployment environment (e.g. prod, staging, dev)"
  type        = string

  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "Environment must be one of: prod, staging, dev."
  }
}

variable "evidence_bucket_arn" {
  description = "ARN of the S3 bucket used for evidence and scan artifacts"
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
