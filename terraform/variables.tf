variable "project_name" {
  type    = string
  default = "prod-config"
}

variable "region" {
  type    = string
  default = "us-east-1"
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
  default = ""
}

variable "google_token_encryption_key" {
  type      = string
  sensitive = true
  default   = ""
}
