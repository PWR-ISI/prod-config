variable "project_name"          { type = string }
variable "region"                { type = string }
variable "vpc_id"                { type = string }
variable "private_subnets"       { type = list(string) }
variable "db_subnets"            { type = list(string) }
variable "ecs_security_group_id" { type = string }
variable "db_security_group_id"  { type = string }
variable "db_username"           { type = string }
variable "db_password" {
  type      = string
  sensitive = true
}
variable "notification_sqs_url" {
  type    = string
  default = ""
}
