# ── Central ALB ────────────────────────────────────────────────────────────────
output "central_alb_dns" {
  description = "Central ALB DNS name for direct service access"
  value       = module.central_alb.alb_dns
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
# output "auth_service_alb_dns" {
#   value = module.auth_service.alb_dns
# }

# ── Appointment service ────────────────────────────────────────────────────────
# disabled for MVP
# output "appointment_service_alb_dns" {
#   value = module.appointment_service.alb_dns
# }
#
# output "appointment_service_db_endpoint" {
#   value = module.appointment_service.db_endpoint
# }
#
# output "appointment_ecr_repository_url" {
#   value = module.appointment_service.ecr_repository_url
# }

# ── Payment service ────────────────────────────────────────────────────────────
# disabled for MVP
# output "payment_service_alb_dns" {
#   value = module.payment_service.alb_dns
# }
#
# output "payment_ecr_repository_url" {
#   value = module.payment_service.ecr_repository_url
# }
#
# output "payment_ecs_cluster" {
#   value = module.payment_service.ecs_cluster
# }
#
# output "payment_ecs_service" {
#   value = module.payment_service.ecs_service
# }

# ── Notification service ───────────────────────────────────────────────────────
# disabled for MVP
# output "notification_service_alb_dns" {
#   value = module.notification_service.alb_dns
# }
#
# output "notification_sns_topic_arn" {
#   value = module.notification_service.sns_topic_arn
# }
#
# output "notification_sqs_app_events_url" {
#   value = module.notification_service.sqs_app_events_url
# }

# ── Frontend ───────────────────────────────────────────────────────────────────
output "frontend_bucket" {
  description = "Frontend S3 bucket name"
  value       = module.frontend.bucket
}

output "frontend_website_endpoint" {
  description = "Frontend S3 website endpoint URL"
  value       = module.frontend.website_endpoint
}

# ── DynamoDB ──────────────────────────────────────────────────────────────────
output "dynamodb_file_metadata_table" {
  description = "DynamoDB table for file metadata"
  value       = module.dynamodb.file_metadata_table_name
}

output "dynamodb_notification_history_table" {
  description = "DynamoDB table for notification history"
  value       = module.dynamodb.notification_history_table_name
}

# ── SNS ────────────────────────────────────────────────────────────────────────
output "sns_appointment_topic_arn" {
  description = "SNS topic ARN for appointment notifications"
  value       = module.sns_notifications.appointment_topic_arn
}

output "sns_file_upload_topic_arn" {
  description = "SNS topic ARN for file upload notifications"
  value       = module.sns_notifications.file_upload_topic_arn
}

# ── File Upload Service ────────────────────────────────────────────────────────
output "file_upload_service_alb_dns" {
  description = "File upload service ALB DNS"
  value       = module.file_upload_service.alb_dns
}

output "file_upload_service_db_endpoint" {
  description = "File upload service RDS database endpoint"
  value       = module.file_upload_service.db_endpoint
}

# ── Monitoring & CloudWatch ───────────────────────────────────────────────────
output "cloudwatch_schedule_service_log_group" {
  description = "CloudWatch log group for schedule service"
  value       = module.monitoring.schedule_service_log_group_name
}

output "cloudwatch_file_upload_service_log_group" {
  description = "CloudWatch log group for file upload service"
  value       = module.monitoring.file_upload_service_log_group_name
}

output "cloudwatch_api_gateway_log_group" {
  description = "CloudWatch log group for API Gateway"
  value       = module.monitoring.api_gateway_log_group_name
}

output "cloudwatch_dashboard_url" {
  description = "URL to CloudWatch monitoring dashboard"
  value       = module.monitoring.dashboard_url
}
