output "api_endpoint" {
  value = aws_apigatewayv2_api.appointments.api_endpoint
}

output "function_arns" {
  value = { for k, fn in aws_lambda_function.appointment : k => fn.arn }
}

output "function_names" {
  value = { for k, fn in aws_lambda_function.appointment : k => fn.function_name }
}

output "log_group_names" {
  value = { for k, lg in aws_cloudwatch_log_group.lambda : k => lg.name }
}

output "db_host" {
  value = aws_db_instance.core.address
}

output "db_endpoint" {
  value = aws_db_instance.core.endpoint
}
