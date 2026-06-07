locals {
  name = "${var.project_name}-file-upload"
}

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

resource "aws_ecr_repository" "file-upload" {
  name         = "${local.name}-repo"
  force_delete = true

  depends_on = [terraform_data.ecr_pre_delete]

  lifecycle {
    ignore_changes = [image_scanning_configuration, image_tag_mutability]
  }
}

resource "aws_ecs_cluster" "cluster" {
  name = "${local.name}-cluster"
}

# IAM role for task execution
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

# Task role grants the running container access to SNS publish + SQS read.
resource "aws_iam_role" "task_role" {
  name               = "${local.name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

resource "aws_iam_role_policy" "task_role_sns_sqs" {
  role = aws_iam_role.task_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.file-upload_events.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
        ]
        Resource = aws_sqs_queue.file-upload_inbox.arn
      },
    ]
  })
}

resource "aws_iam_role_policy" "task_role_s3" {
  role = aws_iam_role.task_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
      Resource = "${var.files_bucket_arn}/*"
    }, {
      Effect   = "Allow"
      Action   = ["s3:ListBucket"]
      Resource = var.files_bucket_arn
    }]
  })
}

# CloudWatch Logs permissions for task execution role
resource "aws_iam_role_policy" "task_exec_cloudwatch" {
  role = aws_iam_role.task_exec_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:${var.region}:*:log-group:/ecs/file-upload-service:*"
      },
    ]
  })
}

# ALB
resource "aws_lb" "alb" {
  name               = "${local.name}-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = var.public_subnets
}

resource "aws_lb_target_group" "tg" {
  name        = "${local.name}-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health/"
    matcher             = "200-299"
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

# Task definition
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
      name      = "file-upload"
      image     = "${aws_ecr_repository.file-upload.repository_url}:latest"
      essential = true
      portMappings = [{ containerPort = 8000, hostPort = 8000 }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/file-upload-service"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      environment = [
        { name = "AWS_REGION", value = var.region },
        { name = "DJANGO_DB_HOST", value = aws_db_instance.file-upload.address },
        { name = "DJANGO_DB_PORT", value = tostring(aws_db_instance.file-upload.port) },
        { name = "DJANGO_DB_NAME", value = "file-uploaddb" },
        { name = "DJANGO_DB_USER", value = var.db_username },
        { name = "DJANGO_DB_PASSWORD", value = nonsensitive(var.db_password) },
        { name = "FILE_UPLOAD_SNS_TOPIC_ARN", value = aws_sns_topic.file-upload_events.arn },
        { name = "EVENTS_SQS_QUEUE_URL", value = aws_sqs_queue.file-upload_inbox.url },
        { name = "AWS_S3_BUCKET", value = var.files_bucket_name },
        { name = "ALLOWED_HOSTS", value = "*" },
        { name = "CLOUDWATCH_LOG_GROUP", value = "/ecs/file-upload-service" },
        { name = "CLOUDWATCH_REGION", value = var.region },
        { name = "LOG_LEVEL", value = "INFO" },
        { name = "LOG_FORMAT", value = "json" },
      ]
    }
  ])

  lifecycle {
    ignore_changes = [container_definitions]
  }
}

# ECS service
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
    container_name   = "file-upload"
    container_port   = 8000
  }

  lifecycle {
    ignore_changes = [availability_zone_rebalancing]
  }
}

# Autoscaling
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 4
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "scale_up" {
  name               = "${local.name}-scale-up"
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

# RDS Postgres
resource "aws_db_subnet_group" "db_subnets" {
  name       = "${local.name}-dbsubnet"
  subnet_ids = var.db_subnets
}

resource "aws_db_instance" "file-upload" {
  allocated_storage      = 20
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.micro"
  db_name                = "fileuploaddb"
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

# Domain event topic and inbox queue
resource "aws_sns_topic" "file-upload_events" {
  name = "${local.name}-events"
}

resource "aws_sqs_queue" "file-upload_inbox" {
  name                       = "${local.name}-inbox"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 1209600
}

data "aws_caller_identity" "current" {}

# Cross-service subscriptions live in the root module to keep modules
# acyclic; this policy allows any same-account SNS topic to deliver here.
resource "aws_sqs_queue_policy" "file-upload_inbox_policy" {
  queue_url = aws_sqs_queue.file-upload_inbox.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.file-upload_inbox.arn
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}
