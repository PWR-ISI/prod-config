terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

variable "project_name" { type = string }

# Microservice backends (LocalStack DNS reachable from inside the docker network).
# When deployed for real, swap with ALB DNS names or VPC link to private services.
variable "auth_service_url" {
  type    = string
  default = "http://auth-service:8000"
}

variable "core_service_url" {
  type    = string
  default = "http://core-service:8000"
}

variable "notification_service_url" {
  type    = string
  default = "http://notification-service:8000"
}

resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-gateway"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "auth" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = "${var.auth_service_url}/{proxy}"
  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_integration" "core" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = "${var.core_service_url}/{proxy}"
  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_integration" "notification" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = "${var.notification_service_url}/{proxy}"
  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_route" "auth" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY /auth/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.auth.id}"
}

resource "aws_apigatewayv2_route" "core" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY /appointments/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.core.id}"
}

resource "aws_apigatewayv2_route" "notification" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY /notifications/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.notification.id}"
}

resource "aws_apigatewayv2_stage" "local" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "local"
  auto_deploy = true
}

output "api_id" { value = aws_apigatewayv2_api.main.id }
output "api_endpoint" { value = aws_apigatewayv2_api.main.api_endpoint }
output "invoke_url" { value = "${aws_apigatewayv2_api.main.api_endpoint}/${aws_apigatewayv2_stage.local.name}" }
