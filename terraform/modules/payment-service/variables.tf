variable "project_name" { type = string }
variable "region" { type = string }
variable "vpc_id" { type = string }

variable "public_subnets" {
  type    = list(string)
  default = []
}

variable "private_subnets" {
  type    = list(string)
  default = []
}

variable "db_subnets" {
  type    = list(string)
  default = []
}

variable "ecs_security_group_id" {
  type    = string
  default = ""
}

variable "db_security_group_id" {
  type    = string
  default = ""
}

variable "db_host" {
  type        = string
  description = "DB host for ECS task. Override to a real container hostname for local dev (LocalStack RDS has no real connectivity)."
  default     = ""  # empty = use aws_db_instance endpoint
}

variable "db_username" {
  type    = string
  default = "payment_user"
}

variable "db_password" {
  type      = string
  sensitive = true
  default   = "payment_pass"
}

variable "payu_merchant_id" {
  type      = string
  sensitive = true
}

variable "payu_api_key" {
  type      = string
  sensitive = true
}

variable "payu_oauth_client_id" {
  type      = string
  sensitive = true
}

variable "payu_oauth_client_secret" {
  type      = string
  sensitive = true
}
