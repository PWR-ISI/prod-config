variable "project_name" {
  type    = string
  default = "prod-config"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_id" {
  type    = string
  default = "vpc-localstack"
}

variable "public_subnets" {
  type    = list(string)
  default = ["subnet-public-1", "subnet-public-2"]
}

variable "private_subnets" {
  type    = list(string)
  default = ["subnet-private-1", "subnet-private-2"]
}

variable "db_subnets" {
  type    = list(string)
  default = ["subnet-db-1", "subnet-db-2"]
}

variable "ecs_security_group_id" {
  type    = string
  default = "sg-ecs-localstack"
}

variable "db_security_group_id" {
  type    = string
  default = "sg-db-localstack"
}

variable "db_username" {
  type    = string
  default = "appuser"
}

variable "db_password" {
  type      = string
  sensitive = true
  default   = "appuser123"
}
