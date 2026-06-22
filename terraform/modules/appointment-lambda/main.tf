locals {
  name       = "${var.project_name}-appointment"
  lambda_zip = "${path.module}/../../../lambda/appointment/function.zip"
  functions  = ["create", "list", "get", "update", "cancel", "complete",
                "notes-get", "notes-update", "history", "upcoming"]
}

# ── RDS (moved here from appointment-service module) ──────────────────────────

resource "aws_db_subnet_group" "core" {
  name       = "${local.name}-dbsubnet"
  subnet_ids = var.db_subnets
}

resource "aws_db_instance" "core" {
  allocated_storage      = 20
  engine                 = "postgres"
  engine_version         = "13.7"
  instance_class         = "db.t3.micro"
  db_name                = "coredb"
  username               = var.db_username
  password               = var.db_password
  skip_final_snapshot    = true
  apply_immediately      = true
  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.core.name
  vpc_security_group_ids = [var.db_security_group_id]

  monitoring_interval          = 0
  performance_insights_enabled = false
  multi_az                     = false
  storage_type                 = "gp2"

  timeouts {
    create = "20m"
    update = "20m"
    delete = "20m"
  }
}

# ── IAM ──────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "lambda_exec" {
  name = "${local.name}-lambda-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Lambda in VPC requires ec2:CreateNetworkInterface to attach ENIs on invocation.
resource "aws_iam_role_policy_attachment" "vpc_access" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_sqs_logs" {
  role = aws_iam_role.lambda_exec.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/${local.name}-*"
      },
    ]
  })
}

# ── CloudWatch log groups ─────────────────────────────────────────────────────
# One log group per function; declaring here sets retention and lifecycle control.

resource "aws_cloudwatch_log_group" "lambda" {
  for_each          = toset(local.functions)
  name              = "/aws/lambda/${local.name}-${each.key}"
  retention_in_days = 7
}

# ── Lambda functions ──────────────────────────────────────────────────────────
# All functions share one zip and one handler. FUNCTION_NAME lets index.py
# route by function identity if needed in the future.

resource "aws_lambda_function" "appointment" {
  for_each = toset(local.functions)

  function_name    = "${local.name}-${each.key}"
  filename         = local.lambda_zip
  # source_code_hash forces re-deploy when the zip content changes.
  source_code_hash = filebase64sha256(local.lambda_zip)
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_exec.arn
  timeout          = 30
  memory_size      = 256

  # Lambda in VPC so it can reach the RDS instance on a private subnet.
  vpc_config {
    subnet_ids         = var.private_subnets
    security_group_ids = [var.ecs_security_group_id]
  }

  environment {
    variables = {
      DB_HOST              = aws_db_instance.core.address
      DB_PORT              = tostring(aws_db_instance.core.port)
      DB_NAME              = "coredb"
      DB_USER              = var.db_username
      DB_PASSWORD          = nonsensitive(var.db_password)
      NOTIFICATION_SQS_URL = var.notification_sqs_url
      FUNCTION_NAME        = each.key
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.vpc_access,
    aws_db_instance.core,
  ]
}

# ── API Gateway HTTP API (v2) → Lambda ───────────────────────────────────────
# HTTP API is cheaper and lower-latency than REST API; no per-method throttling
# needed at this stage.

resource "aws_apigatewayv2_api" "appointments" {
  name          = "${local.name}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.appointments.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "appointment" {
  for_each               = toset(local.functions)
  api_id                 = aws_apigatewayv2_api.appointments.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.appointment[each.key].invoke_arn
  payload_format_version = "2.0"
}

resource "aws_lambda_permission" "apigw" {
  for_each      = toset(local.functions)
  statement_id  = "AllowAPIGW-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.appointment[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.appointments.execution_arn}/*/*"
}

resource "aws_apigatewayv2_route" "list_create" {
  api_id    = aws_apigatewayv2_api.appointments.id
  route_key = "ANY /appointments"
  target    = "integrations/${aws_apigatewayv2_integration.appointment["list"].id}"
}

resource "aws_apigatewayv2_route" "get_update" {
  api_id    = aws_apigatewayv2_api.appointments.id
  route_key = "ANY /appointments/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.appointment["get"].id}"
}

resource "aws_apigatewayv2_route" "cancel" {
  api_id    = aws_apigatewayv2_api.appointments.id
  route_key = "POST /appointments/{id}/cancel"
  target    = "integrations/${aws_apigatewayv2_integration.appointment["cancel"].id}"
}

resource "aws_apigatewayv2_route" "complete" {
  api_id    = aws_apigatewayv2_api.appointments.id
  route_key = "POST /appointments/{id}/complete"
  target    = "integrations/${aws_apigatewayv2_integration.appointment["complete"].id}"
}

resource "aws_apigatewayv2_route" "notes" {
  api_id    = aws_apigatewayv2_api.appointments.id
  route_key = "ANY /appointments/{id}/notes"
  target    = "integrations/${aws_apigatewayv2_integration.appointment["notes-get"].id}"
}

resource "aws_apigatewayv2_route" "history" {
  api_id    = aws_apigatewayv2_api.appointments.id
  route_key = "GET /appointments/{id}/history"
  target    = "integrations/${aws_apigatewayv2_integration.appointment["history"].id}"
}

resource "aws_apigatewayv2_route" "upcoming" {
  api_id    = aws_apigatewayv2_api.appointments.id
  route_key = "GET /appointments/upcoming"
  target    = "integrations/${aws_apigatewayv2_integration.appointment["upcoming"].id}"
}
