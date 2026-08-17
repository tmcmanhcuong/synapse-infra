################################################################################
# Observability Module - Variables
################################################################################

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"
}

variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "synapse"
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for SNS topic encryption"
  type        = string
}

variable "alert_email" {
  description = "Email address for alarm notifications"
  type        = string
}

variable "asg_name" {
  description = "Auto Scaling Group name for EC2 CPU alarm dimension"
  type        = string
}

variable "rds_instance_id" {
  description = "RDS instance identifier for database alarms"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name for dashboard metrics"
  type        = string
}

variable "ecs_service_name" {
  description = "ECS service name for dashboard metrics"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix (e.g. app/my-alb/1234567890)"
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix (e.g. targetgroup/my-tg/1234567890)"
  type        = string
}

variable "monthly_budget_limit" {
  description = "Monthly cost budget limit in USD"
  type        = string
  default     = "320"
}
