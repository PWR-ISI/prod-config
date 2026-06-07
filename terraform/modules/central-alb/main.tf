locals {
  project_name = var.project_name
}

# Security Group for ALB
resource "aws_security_group" "alb" {
  name        = "${local.project_name}-alb-sg"
  description = "Security group for central ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.project_name}-alb-sg"
  }
}

# Central Application Load Balancer
resource "aws_lb" "main" {
  name               = "${local.project_name}-central-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnets

  enable_deletion_protection = false

  tags = {
    Name = "${local.project_name}-central-alb"
  }
}

# Target Group for schedule-service
resource "aws_lb_target_group" "schedule" {
  name        = "${local.project_name}-schedule-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health/"
    matcher             = "200"
  }

  tags = {
    Name = "${local.project_name}-schedule-tg"
  }
}

# Target Group for file-upload-service
resource "aws_lb_target_group" "file_upload" {
  name        = "${local.project_name}-file-upload-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health/"
    matcher             = "200"
  }

  tags = {
    Name = "${local.project_name}-file-upload-tg"
  }
}

# ALB Listener (port 80, default 404 — explicit rules below handle all traffic)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = "{\"detail\": \"Not found\"}"
      status_code  = "404"
    }
  }
}

# Path-based routing: /api/v1/appointments* and /api/v1/slots* → schedule-service
resource "aws_lb_listener_rule" "schedule" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.schedule.arn
  }

  condition {
    path_pattern {
      values = ["/api/v1/appointments*", "/api/v1/slots*", "/api/v1/doctor-schedules*", "/health/*"]
    }
  }
}

# Path-based routing: /api/v1/files* → file-upload-service
resource "aws_lb_listener_rule" "file_upload" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.file_upload.arn
  }

  condition {
    path_pattern {
      values = ["/api/v1/files*"]
    }
  }
}

output "alb_dns" {
  value = aws_lb.main.dns_name
}

output "schedule_target_group_arn" {
  value = aws_lb_target_group.schedule.arn
}

output "file_upload_target_group_arn" {
  value = aws_lb_target_group.file_upload.arn
}
