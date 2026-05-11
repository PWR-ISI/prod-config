variable "project_name" {
  type = string
}

variable "region" {
  type = string
}

variable "cognito_user_pool_id" {
  type = string
}

variable "cognito_app_client_id" {
  type = string
}

# Service ALB endpoints (host:port or DNS name) — set to ALB DNS in production
variable "auth_service_endpoint" {
  type = string
}

variable "appointment_service_endpoint" {
  type = string
}

variable "schedule_service_endpoint" {
  type = string
}

variable "payment_service_endpoint" {
  type = string
}

variable "notification_service_endpoint" {
  type = string
}

variable "facility_staff_service_endpoint" {
  type = string
}

variable "medical_record_service_endpoint" {
  type = string
}

variable "audit_service_endpoint" {
  type = string
}
