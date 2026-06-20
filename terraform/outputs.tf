# ── Monitoring ────────────────────────────────────────────────────────────────
output "alarm_sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarm notifications"
  value       = aws_sns_topic.alarms.arn
}

output "dashboard_name" {
  description = "CloudWatch dashboard name"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

# ── Cognito ────────────────────────────────────────────────────────────────────
output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = module.cognito.user_pool_id
}

output "cognito_app_client_id" {
  description = "Cognito App Client ID"
  value       = module.cognito.app_client_id
}

# ── SQS (centralised queues module) ───────────────────────────────────────────
output "sqs_queue_urls" {
  description = "SQS queue URLs keyed by service name"
  value       = module.sqs.queue_urls
}

# ── Auth service ──────────────────────────────────────────────────────────────
output "auth_service_alb_dns" {
  value = module.auth_service.alb_dns
}

# ── Appointment service ────────────────────────────────────────────────────────
output "appointment_service_alb_dns" {
  value = module.appointment_service.alb_dns
}

output "appointment_service_db_endpoint" {
  value = module.appointment_service.db_endpoint
}

output "appointment_ecr_repository_url" {
  value = module.appointment_service.ecr_repository_url
}

# ── Payment service ────────────────────────────────────────────────────────────
output "payment_service_alb_dns" {
  value = module.payment_service.alb_dns
}

output "payment_ecr_repository_url" {
  value = module.payment_service.ecr_repository_url
}

output "payment_ecs_cluster" {
  value = module.payment_service.ecs_cluster
}

output "payment_ecs_service" {
  value = module.payment_service.ecs_service
}

# ── Notification service ───────────────────────────────────────────────────────
output "notification_service_alb_dns" {
  value = module.notification_service.alb_dns
}

output "notification_sns_topic_arn" {
  value = module.notification_service.sns_topic_arn
}

output "notification_sqs_app_events_url" {
  value = module.notification_service.sqs_app_events_url
}

# ── Frontend ───────────────────────────────────────────────────────────────────
output "frontend_bucket" {
  description = "Frontend S3 bucket name"
  value       = module.frontend.bucket
}

output "frontend_website_endpoint" {
  description = "Frontend S3 website endpoint URL"
  value       = module.frontend.website_endpoint
}
