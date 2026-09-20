terraform {
  backend "s3" {
    bucket       = "ai-healthcare-tfstate-bucket0404"
    key          = "ai-healthcare-platform/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}
