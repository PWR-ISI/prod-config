locals {
  name       = "${var.project_name}-schedule"
  lambda_zip = "${path.module}/../../../lambda/schedule/function.zip"
  functions  = ["slots", "appointments", "doctor-schedules"]
}

# ── RDS Postgres ──────────────────────────────────────────────────────────────
resource "aws_db_subnet_group" "db_subnets" {
  name       = "${local.name}-dbsubnet"
  subnet_ids = var.db_subnets
}

resource "aws_db_instance" "schedule" {
  allocated_storage      = 20
  engine                 = "postgres"
  engine_version         = "13.7"
  instance_class         = "db.t3.micro"
  db_name                = "scheduledb"
  username               = var.db_username
  password               = var.db_password
  skip_final_snapshot    = true
  apply_immediately      = true
  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.db_subnets.name
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

# ── SNS Topic ─────────────────────────────────────────────────────────────────
resource "aws_sns_topic" "schedule_events" {
  name = "${local.name}-events"
}

# ── SQS Inbox ─────────────────────────────────────────────────────────────────
resource "aws_sqs_queue" "schedule_inbox_dlq" {
  name                      = "${local.name}-inbox-dlq"
  message_retention_seconds = 1209600
  tags = { Project = var.project_name, Purpose = "dead-letter" }
}

resource "aws_sqs_queue" "schedule_inbox" {
  name                       = "${local.name}-inbox"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 1209600
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.schedule_inbox_dlq.arn
    maxReceiveCount     = 3
  })
}

data "aws_caller_identity" "current" {}

resource "aws_sqs_queue_policy" "schedule_inbox_policy" {
  queue_url = aws_sqs_queue.schedule_inbox.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.schedule_inbox.arn
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
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

resource "aws_iam_role_policy_attachment" "vpc_access" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_exec.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.schedule_events.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/${local.name}-*"
      },
    ]
  })
}

# ── CloudWatch Log Groups ─────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "lambda" {
  for_each          = toset(local.functions)
  name              = "/aws/lambda/${local.name}-${each.key}"
  retention_in_days = 7
}

# ── Lambda Functions ──────────────────────────────────────────────────────────
resource "aws_lambda_function" "schedule" {
  for_each = toset(local.functions)

  function_name    = "${local.name}-${each.key}"
  filename         = local.lambda_zip
  source_code_hash = filebase64sha256(local.lambda_zip)
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_exec.arn
  timeout          = 30
  memory_size      = 256

  vpc_config {
    subnet_ids         = var.private_subnets
    security_group_ids = [var.ecs_security_group_id]
  }

  environment {
    variables = {
      DB_HOST                    = aws_db_instance.schedule.address
      DB_PORT                    = tostring(aws_db_instance.schedule.port)
      DB_NAME                    = "scheduledb"
      DB_USER                    = var.db_username
      DB_PASSWORD                = nonsensitive(var.db_password)
      SCHEDULE_SNS_TOPIC_ARN     = aws_sns_topic.schedule_events.arn
      AWS_ENDPOINT_URL           = "http://localstack:4566"
      SLOT_RESERVATION_TTL_MINUTES = "15"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.vpc_access,
    aws_db_instance.schedule,
  ]
}

# ── API Gateway HTTP v2 ───────────────────────────────────────────────────────
resource "aws_apigatewayv2_api" "schedule" {
  name          = "${local.name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["*"]
    max_age       = 3000
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.schedule.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "schedule" {
  for_each               = toset(local.functions)
  api_id                 = aws_apigatewayv2_api.schedule.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.schedule[each.key].invoke_arn
  payload_format_version = "2.0"
}

resource "aws_lambda_permission" "apigw" {
  for_each      = toset(local.functions)
  statement_id  = "AllowAPIGW-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.schedule[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.schedule.execution_arn}/*/*"
}

# ── Routes ────────────────────────────────────────────────────────────────────
resource "aws_apigatewayv2_route" "slots" {
  api_id    = aws_apigatewayv2_api.schedule.id
  route_key = "ANY /api/v1/slots"
  target    = "integrations/${aws_apigatewayv2_integration.schedule["slots"].id}"
}

resource "aws_apigatewayv2_route" "slots_detail" {
  api_id    = aws_apigatewayv2_api.schedule.id
  route_key = "ANY /api/v1/slots/{slot_id}"
  target    = "integrations/${aws_apigatewayv2_integration.schedule["slots"].id}"
}

resource "aws_apigatewayv2_route" "slots_action" {
  api_id    = aws_apigatewayv2_api.schedule.id
  route_key = "ANY /api/v1/slots/{slot_id}/{action}"
  target    = "integrations/${aws_apigatewayv2_integration.schedule["slots"].id}"
}

resource "aws_apigatewayv2_route" "appointments" {
  api_id    = aws_apigatewayv2_api.schedule.id
  route_key = "ANY /api/v1/appointments"
  target    = "integrations/${aws_apigatewayv2_integration.schedule["appointments"].id}"
}

resource "aws_apigatewayv2_route" "appointments_detail" {
  api_id    = aws_apigatewayv2_api.schedule.id
  route_key = "ANY /api/v1/appointments/{apt_id}"
  target    = "integrations/${aws_apigatewayv2_integration.schedule["appointments"].id}"
}

resource "aws_apigatewayv2_route" "appointments_action" {
  api_id    = aws_apigatewayv2_api.schedule.id
  route_key = "ANY /api/v1/appointments/{apt_id}/{action}"
  target    = "integrations/${aws_apigatewayv2_integration.schedule["appointments"].id}"
}

resource "aws_apigatewayv2_route" "doctor_schedules" {
  api_id    = aws_apigatewayv2_api.schedule.id
  route_key = "ANY /api/v1/doctor-schedules"
  target    = "integrations/${aws_apigatewayv2_integration.schedule["doctor-schedules"].id}"
}

resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.schedule.id
  route_key = "GET /api/v2/health"
  target    = "integrations/${aws_apigatewayv2_integration.schedule["slots"].id}"
}
