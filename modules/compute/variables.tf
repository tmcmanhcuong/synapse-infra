variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "app_subnet_ids" {
  description = "List of app subnet IDs for ECS instances"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for ECS instances"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for ECS cluster"
  type        = string
  default     = "t3.large"
}

variable "ecs_execution_role_arn" {
  description = "IAM role ARN for ECS task execution"
  type        = string
}

variable "api_task_role_arn" {
  description = "IAM role ARN for synapse-api task"
  type        = string
}

variable "worker_task_role_arn" {
  description = "IAM role ARN for synapse-worker task"
  type        = string
}

variable "mcp_task_role_arn" {
  description = "IAM role ARN for synapse-mcp task"
  type        = string
}
