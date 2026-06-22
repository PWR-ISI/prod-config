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

# ── Service ALB endpoints ──────────────────────────────────────────────────────
# Leave empty until the service module is deployed; api-gateway skips empty entries.
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

# ── PayU credentials (payment-service only) ────────────────────────────────────
variable "payu_merchant_id" {
  type      = string
  sensitive = true
  default   = ""
}

variable "payu_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "payu_oauth_client_id" {
  type      = string
  sensitive = true
  default   = ""
}

variable "payu_oauth_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

# LocalStack routing mode
# true = use direct target IPs (10.196.242.59:8000) - LocalStack workaround for API GW → ALB
# false = use ALB DNS names (AWS production pattern with VPC Link)
variable "use_direct_service_routing" {
  type    = bool
  default = true
}

# ── SMTP (notification-service outbound email) ────────────────────────────────
variable "smtp_host" {
  type    = string
  default = ""
}
variable "smtp_port" {
  type    = number
  default = 465
}
variable "smtp_user" {
  type      = string
  sensitive = true
  default   = ""
}
variable "smtp_password" {
  type      = string
  sensitive = true
  default   = ""
}
variable "email_from" {
  type    = string
  default = ""
}

# ── Google Calendar (notification-service) ────────────────────────────────────
# Set via TF_VAR_google_oauth_client_id etc. in the shell, sourced from .env or
# AWS Secrets Manager in prod. Default empty means the integration is dormant —
# the OAuth endpoints return 503 and the consumer skips Google inserts.
variable "google_oauth_client_id" {
  type      = string
  sensitive = true
  default   = ""
}

variable "google_oauth_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

variable "google_oauth_redirect_uri" {
  type    = string
  default = "http://localhost:8003/api/v2/google/callback/"
}

variable "google_token_encryption_key" {
  type      = string
  sensitive = true
  default   = ""
}
