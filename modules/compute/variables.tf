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

variable "alb_target_group_api_arn" {
  description = "ALB target group ARN for API service. Empty string = no load balancer attached."
  type        = string
  default     = ""
}

variable "ecs_api_desired_count" {
  description = "Desired number of API tasks."
  type        = number
  default     = 1
}

variable "secret_api_token_arn" {
  description = "ARN of Secrets Manager secret containing SYNAPSE_API_TOKEN"
  type        = string
}

variable "secret_db_dsn_arn" {
  description = "ARN of Secrets Manager secret containing SYNAPSE_DB_DSN (PostgreSQL connection string)"
  type        = string
}

variable "secret_db_migration_dsn_arn" {
  description = "ARN of Secrets Manager secret containing SYNAPSE_DB_MIGRATION_DSN (admin PostgreSQL connection string for migrations)"
  type        = string
}

variable "secret_llm_api_key_arn" {
  description = "ARN of Secrets Manager secret containing the OpenRouter/LLM API key for AI triage"
  type        = string
  default     = ""
}
