terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Primary provider — eu-central-1 for all main resources
provider "aws" {
  region = var.aws_region
}

# Second provider — us-east-1 required specifically for ACM + CloudFront
# CloudFront only reads certificates from us-east-1, this is an AWS hard requirement
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}