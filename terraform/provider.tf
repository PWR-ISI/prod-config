variable "use_localstack" {
  type    = bool
  default = false
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "access_key" {
  type    = string
  default = "test"
}

variable "secret_key" {
  type    = string
  default = "test"
}

provider "aws" {
  region     = var.region
  access_key = var.access_key
  secret_key = var.secret_key

  skip_credentials_validation = var.use_localstack
  skip_requesting_account_id  = var.use_localstack
}

provider "aws" {
  alias      = "localstack"
  region     = var.region
  access_key = var.access_key
  secret_key = var.secret_key

  skip_credentials_validation = true
  skip_requesting_account_id  = true

  endpoints {
    s3          = "http://localhost:4566"
    sqs         = "http://localhost:4566"
    sns         = "http://localhost:4566"
    dynamodb    = "http://localhost:4566"
    apigateway  = "http://localhost:4566"
    apigatewayv2 = "http://localhost:4566"
    ecr         = "http://localhost:4566"
    cognitoidp  = "http://localhost:4566"
    iam         = "http://localhost:4566"
    sts         = "http://localhost:4566"
  }
}