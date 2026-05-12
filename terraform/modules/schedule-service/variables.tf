variable "project_name" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

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

variable "db_username" {
  type    = string
  default = "scheduleuser"
}

variable "db_password" {
  type      = string
  sensitive = true
  default   = "scheduleuser123"
}

