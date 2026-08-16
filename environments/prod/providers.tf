provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = title(var.environment)
      Service     = var.project
      ManagedBy   = "terraform"
    }
  }
}
