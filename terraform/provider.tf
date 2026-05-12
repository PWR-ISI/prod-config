terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "access_key" {
  type    = string
  default = "test"
}

variable "secret_key" {
  type    = string
  default = "test"
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
}

provider "aws" {
  alias      = "localstack"
  region     = var.region
  access_key = var.access_key
  secret_key = var.secret_key

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    apigateway           = var.localstack_endpoint
    apigatewayv2         = var.localstack_endpoint
    cloudwatch           = var.localstack_endpoint
    cognitoidp           = var.localstack_endpoint
    dynamodb             = var.localstack_endpoint
    ec2                  = var.localstack_endpoint
    ecr                  = var.localstack_endpoint
    ecs                  = var.localstack_endpoint
    elasticloadbalancing = var.localstack_endpoint
    elbv2                = var.localstack_endpoint
    events               = var.localstack_endpoint
    iam                  = var.localstack_endpoint
    lambda               = var.localstack_endpoint
    logs                 = var.localstack_endpoint
    rds                  = var.localstack_endpoint
    s3                   = var.localstack_endpoint
    sns                  = var.localstack_endpoint
    sqs                  = var.localstack_endpoint
    sts                  = var.localstack_endpoint
  }
}
