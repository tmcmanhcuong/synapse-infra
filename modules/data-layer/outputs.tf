output "db_instance_endpoint" {
  description = "Connection endpoint for the RDS PostgreSQL instance"
  value       = aws_db_instance.synapse.endpoint
}

output "db_instance_arn" {
  description = "ARN of the RDS PostgreSQL instance"
  value       = aws_db_instance.synapse.arn
}

output "db_instance_id" {
  description = "Identifier of the RDS PostgreSQL instance"
  value       = aws_db_instance.synapse.id
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = aws_db_subnet_group.synapse.name
}

output "evidence_bucket_arn" {
  description = "ARN of the S3 evidence bucket"
  value       = aws_s3_bucket.evidence.arn
}

output "evidence_bucket_id" {
  description = "ID of the S3 evidence bucket"
  value       = aws_s3_bucket.evidence.id
}

output "evidence_bucket_name" {
  description = "Name of the S3 evidence bucket"
  value       = aws_s3_bucket.evidence.bucket
}

output "db_master_secret_arn" {
  description = "ARN of the Secrets Manager secret containing master credentials"
  value       = aws_db_instance.synapse.master_user_secret[0].secret_arn
}
