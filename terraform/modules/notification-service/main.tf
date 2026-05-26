terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

variable "project_name" { type = string }
variable "region" { type = string }

# ── Google Calendar integration (Priority 2) ──────────────────────────────────
# These are forwarded as env vars to the notification-service container. Today
# the container runs via docker-compose; when an ECS task is added to this
# module it will pick them up the same way.
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
  description = "Fernet key (base64-urlsafe, 32 bytes). Generate with `python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())'`. Inject from AWS Secrets Manager in production."
}

# Sibling-service URLs that notification-service calls to enrich thin events.
variable "appointment_service_url" {
  type    = string
  default = "http://appointment-service:8000"
}

variable "auth_service_url" {
  type    = string
  default = "http://auth-identity-service:8000"
}

# The queue notification-service drains for payment.success events. The
# bootstrap script creates `payment-success` directly (not via SNS), so the
# consumer reads it as a raw SQS queue. If/when we move to SNS fan-out, this
# becomes the notification_jobs URL output below.
variable "payment_success_queue_url" {
  type    = string
  default = "http://localstack:4566/000000000000/payment-success"
}

resource "aws_dynamodb_table" "notifications" {
  name         = "${var.project_name}-notifications"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "notificationId"

  attribute {
    name = "notificationId"
    type = "S"
  }

  tags = { Service = "notification" }
}

resource "aws_sns_topic" "notifications" {
  name = "${var.project_name}-notifications"
}

resource "aws_sqs_queue" "app_events" {
  name = "${var.project_name}-app-events"
}

resource "aws_sqs_queue" "notification_jobs" {
  name = "${var.project_name}-notification-jobs"
}

resource "aws_sqs_queue_policy" "notification_jobs" {
  queue_url = aws_sqs_queue.notification_jobs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.notification_jobs.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.notifications.arn } }
    }]
  })
}

resource "aws_sns_topic_subscription" "notification_jobs" {
  topic_arn = aws_sns_topic.notifications.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.notification_jobs.arn
}

output "sns_topic_arn" { value = aws_sns_topic.notifications.arn }
output "sqs_app_events_url" { value = aws_sqs_queue.app_events.url }
output "sqs_notification_jobs_url" { value = aws_sqs_queue.notification_jobs.url }
output "dynamodb_table_name" { value = aws_dynamodb_table.notifications.name }

# Env-var bundle the notification-service container/task should receive.
# Surfaced as a single map so docker-compose (or a future ECS task definition)
# can splat it into the container environment in one shot.
output "container_env_vars" {
  description = "Env vars to inject into notification-service container."
  value = {
    EVENTS_SQS_QUEUE_URL        = var.payment_success_queue_url
    APPOINTMENT_SERVICE_URL     = var.appointment_service_url
    AUTH_SERVICE_URL            = var.auth_service_url
    GOOGLE_OAUTH_CLIENT_ID      = var.google_oauth_client_id
    GOOGLE_OAUTH_CLIENT_SECRET  = var.google_oauth_client_secret
    GOOGLE_OAUTH_REDIRECT_URI   = var.google_oauth_redirect_uri
    GOOGLE_TOKEN_ENCRYPTION_KEY = var.google_token_encryption_key
    AWS_ENDPOINT_URL            = "http://localstack:4566"
    AWS_REGION                  = var.region
    AWS_DEFAULT_REGION          = var.region
  }
  sensitive = true
}
