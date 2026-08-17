################################################################################
# Edge Module - Variables
################################################################################

variable "vpc_id" {
  description = "VPC ID where ALB and target group will be created"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the internet-facing ALB"
  type        = list(string)
}

variable "ecs_security_group_id" {
  description = "Security group ID of the ECS/app tier (ALB egress target)"
  type        = string
}

variable "account_id" {
  description = "AWS account ID used for globally unique S3 bucket naming"
  type        = string
}

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

variable "alb_access_logs_bucket" {
  description = "S3 bucket name for ALB access logs. Leave empty to disable access logging."
  type        = string
  default     = ""
}
