# -----------------------------------------------------------------------------
# Foundation Module — Input Variables
# -----------------------------------------------------------------------------

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
  description = "CIDR blocks for app (private) subnets, one per AZ"
  type        = list(string)
}

variable "availability_zones" {
  description = "List of availability zones to deploy subnets into"
  type        = list(string)
}

variable "data_subnet_cidrs" {
  description = "CIDR blocks for data (private) subnets, one per AZ"
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

variable "flow_log_retention_days" {
  description = "CloudWatch Logs retention in days for VPC Flow Logs (minimum 365 for production compliance)"
  type        = number
  default     = 365

  validation {
    condition     = var.flow_log_retention_days >= 365
    error_message = "Flow log retention must be at least 365 days for production compliance."
  }
}

variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per AZ"
  type        = list(string)
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}
