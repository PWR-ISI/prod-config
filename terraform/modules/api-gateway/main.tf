resource "aws_apigatewayv2_api" "medical" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }

  tags = {
    Project = var.project_name
  }
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.medical.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito-jwt"

  jwt_configuration {
    audience = [var.cognito_app_client_id]
    issuer   = "https://cognito-idp.${var.region}.amazonaws.com/${var.cognito_user_pool_id}"
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.medical.id
  name        = "$default"
  auto_deploy = true
}

# ── Per-service integrations + routes ─────────────────────────────────────────
# Only services with a non-empty endpoint get a route; safe to deploy
# incrementally as service ALBs are added.

locals {
  all_services = {
    auth          = var.auth_service_endpoint
    appointments  = var.appointment_service_endpoint
    schedule      = var.schedule_service_endpoint
    payments      = var.payment_service_endpoint
    notifications = var.notification_service_endpoint
    facilities    = var.facility_staff_service_endpoint
    records       = var.medical_record_service_endpoint
    audit         = var.audit_service_endpoint
  }
  services = { for k, v in local.all_services : k => v if v != "" }
}

resource "aws_apigatewayv2_integration" "service" {
  for_each = local.services

  api_id                 = aws_apigatewayv2_api.medical.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = "http://${each.value}/api/v1/{proxy}"
  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_route" "service" {
  for_each = local.services

  api_id    = aws_apigatewayv2_api.medical.id
  route_key = "ANY /${each.key}/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.service[each.key].id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# Health check — unauthenticated
resource "aws_apigatewayv2_integration" "health" {
  count = var.auth_service_endpoint != "" ? 1 : 0

  api_id                 = aws_apigatewayv2_api.medical.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "GET"
  integration_uri        = "http://${var.auth_service_endpoint}/health/"
  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_route" "health" {
  count = var.auth_service_endpoint != "" ? 1 : 0

  api_id             = aws_apigatewayv2_api.medical.id
  route_key          = "GET /health"
  target             = "integrations/${aws_apigatewayv2_integration.health[0].id}"
  authorization_type = "NONE"
}
