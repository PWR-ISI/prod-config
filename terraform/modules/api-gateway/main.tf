# ── HTTP API V2 (works on both LocalStack and AWS) ──────────────────────────
resource "aws_apigatewayv2_api" "medical" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
  description   = "Medical microservices API"

  cors_configuration {
    allow_origins     = ["*"]
    allow_methods     = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD"]
    allow_headers     = ["content-type", "authorization", "x-amz-date", "x-api-key", "x-amz-security-token"]
    expose_headers    = ["content-type", "x-amzn-requestid"]
    max_age           = 300
    allow_credentials = false
  }

  tags = {
    Project = var.project_name
  }
}

# ── Auth Service Integration ─────────────────────────────────────────────────
# HTTP_PROXY to schedule service (auth disabled - use Cognito Hosted UI)
resource "aws_apigatewayv2_integration" "auth" {
  api_id             = aws_apigatewayv2_api.medical.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = "http://${var.schedule_service_endpoint}:80"
  payload_format_version = "1.0"

  request_parameters = {
    "overwrite:path" = "/api/v1/auth/$request.path.proxy"
  }
}

resource "aws_apigatewayv2_route" "auth" {
  api_id    = aws_apigatewayv2_api.medical.id
  route_key = "ANY /api/v2/auth/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.auth.id}"
}

# ── Services Integrations ────────────────────────────────────────────────────
locals {
  services = {
    # MVP: schedule (appointments) and file-upload
    schedule     = var.schedule_service_endpoint
    file-upload  = var.file_upload_service_endpoint
    # disabled services:
    # appointments  = var.appointment_service_endpoint
    # payments      = var.payment_service_endpoint
    # notifications = var.notification_service_endpoint
    # facilities    = var.facility_staff_service_endpoint
    # records       = var.medical_record_service_endpoint
    # audit         = var.audit_service_endpoint
  }

}

resource "aws_apigatewayv2_integration" "service" {
  for_each           = local.services
  api_id             = aws_apigatewayv2_api.medical.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"

  # Use ALB endpoints on port 80 (ALB forwards to port 8000 on ECS tasks)
  integration_uri = each.value != "" ? "http://${each.value}:80" : "http://localhost:8000"

  request_parameters = {
    "overwrite:path" = "/api/v1/$request.path.proxy"
  }
}

resource "aws_apigatewayv2_route" "service" {
  for_each   = local.services
  api_id     = aws_apigatewayv2_api.medical.id
  route_key  = "ANY /api/v2/${each.key}/{proxy+}"
  target     = "integrations/${aws_apigatewayv2_integration.service[each.key].id}"
}

# ── Default Stage ────────────────────────────────────────────────────────────
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.medical.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    detailed_metrics_enabled        = true
    data_trace_enabled              = false
    logging_level                   = "OFF"
    throttling_burst_limit          = 10000
    throttling_rate_limit           = 20000
  }
}

# Usunąć - CORS w api-gateway dla HTTP API V2 obsługuje OPTIONS automatycznie
