output "appointment_service_alb_dns" {
  value = module.appointment_service.alb_dns
}

output "appointment_service_db_endpoint" {
  value = module.appointment_service.db_endpoint
}

output "appointment_ecr_repository_url" {
  value = module.appointment_service.ecr_repository_url
}

output "cognito_user_pool_id" {
  value = module.cognito.user_pool_id
}

output "cognito_client_id" {
  value = module.cognito.client_id
}

output "sns_topic_arn" {
  value = module.notification_service.sns_topic_arn
}

output "sqs_app_events_url" {
  value = module.notification_service.sqs_app_events_url
}

output "api_gateway_invoke_url" {
  value = module.api_gateway.invoke_url
}

output "api_gateway_id" {
  value = module.api_gateway.api_id
}
