locals {
  name = "${var.project_name}-medical"
}

resource "aws_ecr_repository" "medical" {
  name = "${local.name}-repo"

  image_scanning_configuration { scan_on_push = false }
  force_delete = true
}

resource "aws_cloudwatch_log_group" "medical" {
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
        "sns:Publish",
        "cognito-idp:*",
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
    path                = "/api/v2/health/"
    matcher             = "200-399"
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
      name         = "medical"
      image = "${aws_ecr_repository.medical.repository_url}:latest"
      essential    = true
      portMappings = [{ containerPort = 8000, hostPort = 8000, protocol = "tcp" }]
      environment = [
        { name = "AWS_REGION", value = var.region },
        { name = "AWS_DEFAULT_REGION", value = var.region },
        { name = "DB_HOST", value = aws_db_instance.medical.address },
        { name = "DB_PORT", value = tostring(aws_db_instance.medical.port) },
        { name = "DB_NAME", value = "medicaldb" },
        { name = "DB_USER", value = var.db_username },
        { name = "DB_PASSWORD", value = nonsensitive(var.db_password) },
        { name = "COGNITO_USER_POOL_ID", value = var.cognito_user_pool_id },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.medical.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "medical"
        }
      }
    }
  ])

  lifecycle {
    ignore_changes = [container_definitions]
  }
}

resource "aws_ecs_service" "service" {
  name            = "${local.name}-svc"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.task.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnets
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "medical"
    container_port   = 8000
  }

  depends_on = [aws_lb_listener.http]

  lifecycle {
    ignore_changes = [availability_zone_rebalancing]
  }
}

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

resource "aws_db_subnet_group" "db_subnets" {
  name       = "${local.name}-dbsubnet"
  subnet_ids = var.db_subnets
}

resource "aws_db_instance" "medical" {
  allocated_storage      = 20
  engine                 = "postgres"
  engine_version = "15"
  instance_class         = "db.t3.micro"
  db_name                = "medicaldb"
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

resource "aws_sns_topic" "medical_events" {
  name = "${local.name}-events"
}

resource "aws_sqs_queue" "medical_inbox" {
  name                       = "${local.name}-inbox"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 1209600
}

data "aws_caller_identity" "current" {}

resource "aws_sqs_queue_policy" "medical_inbox_policy" {
  queue_url = aws_sqs_queue.medical_inbox.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.medical_inbox.arn
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}
