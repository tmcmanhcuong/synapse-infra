# -----------------------------------------------------------------------------
# Foundation Module — Outputs
# -----------------------------------------------------------------------------

output "app_subnet_ids" {
  description = "List of app (private) subnet IDs"
  value       = aws_subnet.app[*].id
}

output "data_subnet_ids" {
  description = "List of data (private) subnet IDs"
  value       = aws_subnet.data[*].id
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = aws_nat_gateway.main[*].id
}

output "private_route_table_ids" {
  description = "List of private route table IDs (one per AZ)"
  value       = aws_route_table.private[*].id
}

output "public_route_table_id" {
  description = "Public route table ID"
  value       = aws_route_table.public.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "security_group_app_id" {
  description = "App tier security group ID"
  value       = aws_security_group.app.id
}

output "security_group_data_id" {
  description = "Data tier security group ID"
  value       = aws_security_group.data.id
}

output "security_group_web_id" {
  description = "Web tier security group ID"
  value       = aws_security_group.web.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}
