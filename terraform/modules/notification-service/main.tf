data "aws_caller_identity" "current" {}

locals {
  name = "${var.project_name}-notification"
}

variable "project_name" { type = string }
variable "region" { type = string }
variable "vpc_id" { type = string }
variable "public_subnets" { type = list(string) }
variable "private_subnets" { type = list(string) }
variable "ecs_security_group_id" { type = string }

# ── ECR Repository ───────────────────────────────────────────────────────────
resource "terraform_data" "ecr_pre_delete" {
  triggers_replace = { repo_name = "${local.name}-repo" }

  provisioner "local-exec" {
    interpreter = ["powershell", "-NoProfile", "-Command"]
    environment = {
      AWS_ACCESS_KEY_ID     = "test"
      AWS_SECRET_ACCESS_KEY = "test"
      AWS_DEFAULT_REGION    = var.region
    }
    command = "try { aws ecr delete-repository --repository-name ${local.name}-repo --force  --region ${var.region} 2>$null } catch {}; exit 0"
  }
}

resource "aws_ecr_repository" "notification" {
  name = "${local.name}-repo"
  image_scanning_configuration { scan_on_push = false }
  force_delete = true
  depends_on = [terraform_data.ecr_pre_delete]
  lifecycle { ignore_changes = [image_scanning_configuration, image_tag_mutability] }
}

# ── Logs & Cluster ────────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "notification" {
  name              = "/ecs/${local.name}"
  retention_in_days = 7
}

resource "aws_ecs_cluster" "cluster" {
  name = "${local.name}-cluster"
}

# ── IAM Roles ─────────────────────────────────────────────────────────────────
resource "aws_iam_role" "task_exec_role" {
  name               = "${local.name}-task-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "exec_attach" {
  role       = aws_iam_role.task_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task_role" {
  name               = "${local.name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

resource "aws_iam_role_policy" "task_role_policy" {
  role = aws_iam_role.task_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:*", "sns:*", "dynamodb:*", "logs:*"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["cognito-idp:AdminGetUser", "cognito-idp:ListUsers"]
        Resource = var.cognito_user_pool_arn
      },
      {
        Effect   = "Allow"
        Action   = ["scheduler:CreateSchedule", "scheduler:DeleteSchedule", "scheduler:GetSchedule"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = var.scheduler_exec_role_arn
      },
    ]
  })
}

# ── ALB Security Group ────────────────────────────────────────────────────────
resource "aws_security_group" "alb_sg" {
  name   = "${local.name}-alb-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ── ALB & Target Group ────────────────────────────────────────────────────────
resource "aws_lb" "alb" {
  name               = "${local.name}-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = var.public_subnets
  security_groups    = [aws_security_group.alb_sg.id]
}

resource "aws_lb_target_group" "tg" {
  name        = "${local.name}-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/api/v2/health/"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# ── ECS Task Definition & Service ─────────────────────────────────────────────
resource "aws_ecs_task_definition" "task" {
  family                   = "${local.name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.task_exec_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([{
    name      = "notification"
    image     = "${aws_ecr_repository.notification.repository_url}:latest"
    essential = true
    portMappings = [{ containerPort = 8000, hostPort = 8000, protocol = "tcp" }]
    environment = [
      { name = "AWS_REGION",             value = var.region },
      { name = "AWS_DEFAULT_REGION",     value = var.region },
      { name = "DEBUG",                  value = "False" },
      { name = "ALLOWED_HOSTS",          value = "*" },
      { name = "SNS_TOPIC_ARN",          value = aws_sns_topic.notifications.arn },
      { name = "SQS_QUEUE_URL",          value = aws_sqs_queue.notification_jobs.url },
      { name = "EVENTS_SQS_QUEUE_URL",   value = aws_sqs_queue.notification_jobs.url },
      { name = "NOTIFICATION_SQS_ARN",   value = aws_sqs_queue.notification_jobs.arn },
      { name = "DYNAMODB_TABLE",         value = aws_dynamodb_table.notifications.name },
      { name = "COGNITO_USER_POOL_ID",   value = var.cognito_user_pool_id },
      { name = "SENDER_EMAIL",           value = var.sender_email },
      { name = "SCHEDULER_ROLE_ARN",     value = var.scheduler_exec_role_arn },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.notification.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "notification"
      }
    }
  }])

  lifecycle { ignore_changes = [container_definitions] }
}

resource "aws_ecs_service" "service" {
  name            = "${local.name}-svc"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.task.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.private_subnets
    security_groups = [var.ecs_security_group_id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "notification"
    container_port   = 8000
  }

  depends_on = [aws_lb_listener.http]

  lifecycle { ignore_changes = [availability_zone_rebalancing] }
}

# ── Autoscaling ────────────────────────────────────────────────────────────────
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 4
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "scale_cpu" {
  name               = "${local.name}-scale-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 50.0
  }
}

variable "cognito_user_pool_arn" {
  type    = string
  default = ""
  description = "ARN of Cognito User Pool for email lookup in notification handlers"
}

variable "scheduler_exec_role_arn" {
  type    = string
  default = ""
  description = "ARN of EventBridge Scheduler execution role"
}

variable "notification_email" {
  type    = string
  default = ""
  description = "Email address to subscribe to notification SNS topic"
}

variable "cognito_user_pool_id" {
  type    = string
  default = ""
}

variable "sender_email" {
  type    = string
  default = ""
}

variable "files_bucket_name" {
  type    = string
  default = ""
}

# ── Google Calendar integration (Priority 2) ──────────────────────────────────
# These are forwarded as env vars to the notification-service container. Today
# the container runs via docker-compose; when an ECS task is added to this
# module it will pick them up the same way.
variable "google_oauth_client_id" {
  type      = string
  sensitive = true
  default   = ""
}

variable "google_oauth_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

variable "google_oauth_redirect_uri" {
  type    = string
  default = ""
  description = "Callback URI for Google OAuth - set to API Gateway URL in prod"
}

variable "google_token_encryption_key" {
  type      = string
  sensitive = true
  default   = ""
  description = "Fernet key (base64-urlsafe, 32 bytes). Generate with `python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())'`. Inject from AWS Secrets Manager in production."
}

# Sibling-service URLs that notification-service calls to enrich thin events.
variable "appointment_service_url" {
  type    = string
  default = "http://appointment-service:8000"
}

variable "auth_service_url" {
  type    = string
  default = "http://auth-identity-service:8000"
}

# The queue notification-service drains for payment.success events. The
# bootstrap script creates `payment-success` directly (not via SNS), so the
# consumer reads it as a raw SQS queue. If/when we move to SNS fan-out, this
# becomes the notification_jobs URL output below.
variable "payment_success_queue_url" {
  type    = string
  default = ""
  description = "SQS queue URL for payment success events - set in main.tf"
}

resource "aws_dynamodb_table" "notifications" {
  name         = "${var.project_name}-notifications"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "notificationId"

  attribute {
    name = "notificationId"
    type = "S"
  }

  tags = { Service = "notification" }
}

resource "aws_sns_topic" "notifications" {
  name = "${var.project_name}-notifications"
}

resource "aws_sqs_queue" "app_events" {
  name = "${var.project_name}-app-events"
}

resource "aws_sqs_queue" "notification_jobs" {
  name = "${var.project_name}-notification-jobs"
}

resource "aws_sqs_queue_policy" "notification_jobs" {
  queue_url = aws_sqs_queue.notification_jobs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.notification_jobs.arn
      Condition = { ArnLike = { "aws:SourceArn" = "arn:aws:sns:*:*:${var.project_name}-*" } }
    }]
  })
}

resource "aws_sns_topic_subscription" "notification_jobs" {
  topic_arn = aws_sns_topic.notifications.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.notification_jobs.arn
}

# Email subscription — set notification_email var to activate
resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

output "sns_topic_arn" { value = aws_sns_topic.notifications.arn }
output "sqs_app_events_url" { value = aws_sqs_queue.app_events.url }
output "sqs_notification_jobs_url" { value = aws_sqs_queue.notification_jobs.url }
output "sqs_notification_jobs_arn" { value = aws_sqs_queue.notification_jobs.arn }
output "dynamodb_table_name" { value = aws_dynamodb_table.notifications.name }

# Env-var bundle the notification-service container/task should receive.
# Surfaced as a single map so docker-compose (or a future ECS task definition)
# can splat it into the container environment in one shot.
output "alb_dns" { value = aws_lb.alb.dns_name }
output "ecs_cluster" { value = aws_ecs_cluster.cluster.name }
output "ecs_service" { value = aws_ecs_service.service.name }

output "container_env_vars" {
  description = "Env vars to inject into notification-service container."
  value = {
    EVENTS_SQS_QUEUE_URL        = var.payment_success_queue_url
    APPOINTMENT_SERVICE_URL     = var.appointment_service_url
    AUTH_SERVICE_URL            = var.auth_service_url
    GOOGLE_OAUTH_CLIENT_ID      = var.google_oauth_client_id
    GOOGLE_OAUTH_CLIENT_SECRET  = var.google_oauth_client_secret
    GOOGLE_OAUTH_REDIRECT_URI   = var.google_oauth_redirect_uri
    GOOGLE_TOKEN_ENCRYPTION_KEY = var.google_token_encryption_key
    AWS_REGION                  = var.region
    AWS_DEFAULT_REGION          = var.region
  }
  sensitive = true
}
