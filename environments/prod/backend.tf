terraform {
  backend "s3" {
    bucket         = "synapse-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "synapse-terraform-lock"
    encrypt        = true
  }
}
