output "kms_key_arn" {
  description = "ARN of the Synapse platform KMS key"
  value       = aws_kms_key.platform.arn
}

output "kms_key_id" {
  description = "ID of the Synapse platform KMS key"
  value       = aws_kms_key.platform.key_id
}

output "ecs_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_execution.arn
}

output "api_task_role_arn" {
  description = "ARN of the API task role"
  value       = aws_iam_role.api_task.arn
}

output "worker_task_role_arn" {
  description = "ARN of the worker task role"
  value       = aws_iam_role.worker_task.arn
}

output "mcp_task_role_arn" {
  description = "ARN of the MCP task role"
  value       = aws_iam_role.mcp_task.arn
}

output "secret_arns" {
  description = "Map of secret key to ARN for all managed secrets"
  value       = { for k, v in aws_secretsmanager_secret.this : k => v.arn }
}
