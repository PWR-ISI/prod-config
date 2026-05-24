output "api_gateway_id" {
  description = "API Gateway ID"
  value       = aws_apigatewayv2_api.medical.id
}

output "api_gateway_endpoint" {
  description = "API Gateway endpoint URL"
  value       = aws_apigatewayv2_api.medical.api_endpoint
}

output "stage_name" {
  description = "API Gateway Stage Name"
  value       = aws_apigatewayv2_stage.default.name
}
