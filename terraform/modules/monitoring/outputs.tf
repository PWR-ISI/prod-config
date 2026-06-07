output "schedule_service_log_group_name" {
  value       = aws_cloudwatch_log_group.schedule_service.name
  description = "CloudWatch log group name for schedule service"
}

output "file_upload_service_log_group_name" {
  value       = aws_cloudwatch_log_group.file_upload_service.name
  description = "CloudWatch log group name for file upload service"
}

output "api_gateway_log_group_name" {
  value       = aws_cloudwatch_log_group.api_gateway.name
  description = "CloudWatch log group name for API Gateway"
}

output "dashboard_url" {
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
  description = "URL to CloudWatch dashboard"
}
