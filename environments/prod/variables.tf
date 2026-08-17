variable "allowed_web_cidrs" {
  description = "CIDR blocks allowed to access web tier (HTTP/HTTPS)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "app_port" {
  description = "Application port for app tier security group rules"
  type        = number
  default     = 8080
}

variable "app_subnet_cidrs" {
  description = "CIDR blocks for app (private) subnets"
  type        = list(string)
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
}

variable "data_subnet_cidrs" {
  description = "CIDR blocks for data (private) subnets"
  type        = list(string)
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "alert_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
}
