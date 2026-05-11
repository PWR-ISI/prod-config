output "api_gateway_endpoint" {
  description = "Base URL of the AWS API Gateway (HTTP API v2)"
  value       = module.api_gateway.api_endpoint
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = module.cognito.user_pool_id
}

output "cognito_app_client_id" {
  description = "Cognito App Client ID"
  value       = module.cognito.app_client_id
}

output "sqs_queue_urls" {
  description = "SQS queue URLs keyed by service name"
  value       = module.sqs.queue_urls
}

output "appointment_service_alb_dns" {
  value = module.appointment_service.alb_dns
}

output "appointment_service_db_endpoint" {
  value = module.appointment_service.db_endpoint
}
