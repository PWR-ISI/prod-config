# ── HTTP API V2 (works on both LocalStack and AWS) ──────────────────────────
resource "aws_apigatewayv2_api" "medical" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
  description   = "Medical microservices API"

  cors_configuration {
    allow_origins     = ["*"]
    allow_methods     = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"]
    allow_headers     = ["*"]
    expose_headers    = ["*"]
    max_age           = 300
  }

  tags = {
    Project = var.project_name
  }
}

# ── Auth Service Integration ─────────────────────────────────────────────────
# For LocalStack: uses host.docker.internal:64808 (port forward from host)
# For AWS: endpoint is ALB DNS name on port 80, routed via VPC Link
resource "aws_apigatewayv2_integration" "auth" {
  count              = var.auth_service_endpoint != "" ? 1 : 0
  api_id             = aws_apigatewayv2_api.medical.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"

  integration_uri = "http://${var.auth_service_endpoint}:${var.auth_service_endpoint == "host.docker.internal" ? "64808" : "80"}"

  request_parameters = {
    "overwrite:path" = "/api/v2/auth/$request.path.proxy"
  }

  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_route" "auth" {
  count     = var.auth_service_endpoint != "" ? 1 : 0
  api_id    = aws_apigatewayv2_api.medical.id
  route_key = "ANY /api/v2/auth/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.auth[0].id}"
}

# ── Services Integrations ────────────────────────────────────────────────────
locals {
  services = {
    appointments  = var.appointment_service_endpoint
    schedule      = var.schedule_service_endpoint
    payments      = var.payment_service_endpoint
    notifications = var.notification_service_endpoint
    facilities    = var.facility_staff_service_endpoint
    records       = var.medical_record_service_endpoint
    audit         = var.audit_service_endpoint
  }

  active_services = {
    for k, v in local.services : k => v if v != ""
  }
}

resource "aws_apigatewayv2_integration" "service" {
  for_each           = local.active_services
  api_id             = aws_apigatewayv2_api.medical.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"

  # For LocalStack: uses host.docker.internal with service port (e.g., 8001, 8002, etc)
  # For AWS: endpoint is ALB DNS name on port 80
  integration_uri = "http://${each.value}:80"

  request_parameters = {
    "overwrite:path" = "/api/v1$request.path"
  }
}

resource "aws_apigatewayv2_route" "service" {
  for_each   = local.active_services
  api_id     = aws_apigatewayv2_api.medical.id
  route_key  = "ANY /${each.key}/{proxy+}"
  target     = "integrations/${aws_apigatewayv2_integration.service[each.key].id}"
}

# ── Default Stage ────────────────────────────────────────────────────────────
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.medical.id
  name        = "$default"
  auto_deploy = true
}
