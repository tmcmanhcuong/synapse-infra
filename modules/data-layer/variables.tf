variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the data layer resources reside"
  type        = string
}

variable "data_subnet_ids" {
  description = "List of subnet IDs for the RDS subnet group (data tier)"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for the RDS instance (data tier SG from foundation)"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS CMK used for RDS storage and S3 bucket encryption"
  type        = string
}

variable "db_instance_class" {
  description = "RDS instance class. Default is burstable db.t3.medium -- production should consider db.r6g family"
  type        = string
  default     = "db.t3.medium"
}

variable "db_allocated_storage" {
  description = "Initial allocated storage in GiB for the RDS instance"
  type        = number
  default     = 20
}

variable "db_max_storage" {
  description = "Maximum storage threshold in GiB for RDS autoscaling"
  type        = number
  default     = 100
}
