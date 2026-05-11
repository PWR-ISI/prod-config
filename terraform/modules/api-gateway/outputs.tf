output "api_id" {
  value = aws_apigatewayv2_api.medical.id
}

output "api_endpoint" {
  description = "Base invoke URL for the API Gateway"
  value       = aws_apigatewayv2_api.medical.api_endpoint
}
