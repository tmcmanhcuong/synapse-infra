# -----------------------------------------------------------------------------
# Environment Outputs
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "VPC ID"
  value       = module.foundation.vpc_id
}

output "vpc_cidr_block" {
  description = "VPC CIDR block"
  value       = module.foundation.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.foundation.public_subnet_ids
}

output "app_subnet_ids" {
  description = "App (private) subnet IDs"
  value       = module.foundation.app_subnet_ids
}

output "data_subnet_ids" {
  description = "Data (private) subnet IDs"
  value       = module.foundation.data_subnet_ids
}

output "security_group_web_id" {
  description = "Web tier security group ID"
  value       = module.foundation.security_group_web_id
}

output "security_group_app_id" {
  description = "App tier security group ID"
  value       = module.foundation.security_group_app_id
}

output "security_group_data_id" {
  description = "Data tier security group ID"
  value       = module.foundation.security_group_data_id
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs"
  value       = module.foundation.nat_gateway_ids
}
