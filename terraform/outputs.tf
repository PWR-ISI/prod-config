# ── API Gateway (HTTP API V2) ──────────────────────────────────────────────────
output "api_gateway_id" {
  description = "API Gateway HTTP API ID"
  value       = module.api_gateway.api_gateway_id
}

output "api_gateway_endpoint" {
  description = "API Gateway endpoint URL (HTTP for LocalStack)"
  value       = module.api_gateway.api_gateway_endpoint
}

output "api_gateway_endpoint_https" {
  description = "API Gateway endpoint URL (HTTPS for frontend)"
  value       = replace(module.api_gateway.api_gateway_endpoint, "http://", "https://")
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
output "notification_sns_topic_arn" {
  value = module.notification_service.sns_topic_arn
}

output "notification_sqs_app_events_url" {
  value = module.notification_service.sqs_app_events_url
}
