terraform {
  backend "s3" {
    key          = "prod/terraform.tfstate"
    use_lockfile = true
  }
}
