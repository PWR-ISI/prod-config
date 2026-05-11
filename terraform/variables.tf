variable "project_name" {
  type    = string
  default = "prod-config"
}

variable "vpc_id" {
  type    = string
  default = ""
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
  default = "appuser"
}

variable "db_password" {
  type      = string
  sensitive = true
  default   = "appuser123"
}

# Service ALB endpoints — set these via tfvars in production (e.g. from ECS/ALB outputs)
variable "auth_service_endpoint" {
  type    = string
  default = ""
}

variable "appointment_service_endpoint" {
  type    = string
  default = ""
}

variable "schedule_service_endpoint" {
  type    = string
  default = ""
}

variable "payment_service_endpoint" {
  type    = string
  default = ""
}

variable "notification_service_endpoint" {
  type    = string
  default = ""
}

variable "facility_staff_service_endpoint" {
  type    = string
  default = ""
}

variable "medical_record_service_endpoint" {
  type    = string
  default = ""
}

variable "audit_service_endpoint" {
  type    = string
  default = ""
}