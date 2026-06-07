terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# AWS Provider - credentials from ~/.aws/credentials or AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY env vars
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "production"
      ManagedBy   = "Terraform"
    }
  }
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}
data "aws_ecr_authorization_token" "token" {}
