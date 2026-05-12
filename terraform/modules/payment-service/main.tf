locals {
  name = "${var.project_name}-payment"
}

resource "aws_ecr_repository" "payment" {
  name = "${local.name}-repo"

  image_scanning_configuration { scan_on_push = false }
  force_delete = true
}

resource "aws_cloudwatch_log_group" "payment" {
  name              = "/ecs/${local.name}"
  retention_in_days = 7
}

resource "aws_ecs_cluster" "cluster" {
  name = "${local.name}-cluster"
}

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
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes",
        "logs:CreateLogStream", "logs:PutLogEvents"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_lb" "alb" {
  name               = "${local.name}-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = var.public_subnets
  security_groups    = [var.ecs_security_group_id]
}

resource "aws_lb_target_group" "tg" {
  name        = "${local.name}-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/api/payments/health"
    matcher             = "200"
    interval            = 30
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

resource "aws_db_subnet_group" "db_subnets" {
  name       = "${local.name}-dbsubnet"
  subnet_ids = var.db_subnets
}

resource "aws_db_instance" "payment" {
  allocated_storage      = 20
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.micro"
  db_name                = "payment_db"
  username               = var.db_username
  password               = var.db_password
  skip_final_snapshot    = true
  db_subnet_group_name   = aws_db_subnet_group.db_subnets.name
  vpc_security_group_ids = [var.db_security_group_id]
}

resource "aws_ecs_task_definition" "task" {
  family                   = "${local.name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.task_exec_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name         = "payment"
      image        = "${aws_ecr_repository.payment.repository_url}:latest"
      essential    = true
      portMappings = [{ containerPort = 8000, hostPort = 8000, protocol = "tcp" }]
      # LocalStack ECS ignores entryPoint — put sh -c in command so Docker CMD is ["sh","-c","..."]
      command = ["sh", "-c", "python manage.py migrate --noinput && gunicorn payment.wsgi:application --bind 0.0.0.0:8000 --workers 2 --timeout 120"]
      environment = [
        { name = "AWS_ENDPOINT_URL",                  value = "http://localstack:4566" },
        { name = "AWS_REGION",                        value = var.region },
        { name = "AWS_DEFAULT_REGION",                value = var.region },
        { name = "AWS_ACCESS_KEY_ID",                 value = "test" },
        { name = "AWS_SECRET_ACCESS_KEY",             value = "test" },
        { name = "DJANGO_DB_HOST",                    value = var.db_host != "" ? var.db_host : aws_db_instance.payment.address },
        { name = "DJANGO_DB_PORT",                    value = "5432" },
        { name = "DJANGO_DB_NAME",                    value = "payment_db" },
        { name = "DJANGO_DB_USER",                    value = var.db_username },
        { name = "DJANGO_DB_PASSWORD",                value = var.db_password },
        { name = "ALLOWED_HOSTS",                     value = "*" },
        { name = "AWS_SQS_PAYMENT_SUCCESS_QUEUE_URL", value = "http://localstack:4566/000000000000/payment-success" },
        { name = "AWS_SQS_PAYMENT_FAILED_QUEUE_URL",  value = "http://localstack:4566/000000000000/payment-failed" },
        { name = "PAYU_MERCHANT_ID",                  value = var.payu_merchant_id },
        { name = "PAYU_API_KEY",                      value = var.payu_api_key },
        { name = "PAYU_OAUTH_CLIENT_ID",              value = var.payu_oauth_client_id },
        { name = "PAYU_OAUTH_CLIENT_SECRET",          value = var.payu_oauth_client_secret },
        { name = "PAYU_SANDBOX_MODE",                 value = "true" },
        { name = "BASE_URL",                          value = "http://${aws_lb.alb.dns_name}" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.payment.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "payment"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "service" {
  name            = "${local.name}-svc"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnets
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "payment"
    container_port   = 8000
  }

  depends_on = [aws_lb_listener.http]
}
