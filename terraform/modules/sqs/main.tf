locals {
  services = [
    "auth-identity-service",
    "appointment-service",
    "schedule-service",
    "payment-service",
    "notification-service",
    "facility-staff-service",
    "medical-record-service",
    "audit-service",
  ]
}

resource "aws_sqs_queue" "service_dlq" {
  for_each = toset(local.services)

  name                      = "${var.project_name}-${each.key}-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = {
    Project = var.project_name
    Service = each.key
  }
}

resource "aws_sqs_queue" "service" {
  for_each = toset(local.services)

  name                       = "${var.project_name}-${each.key}-queue"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400 # 1 day

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.service_dlq[each.key].arn
    maxReceiveCount     = 3
  })

  tags = {
    Project = var.project_name
    Service = each.key
  }
}

# Payment-specific queues for success/failed events
resource "aws_sqs_queue" "payment_success" {
  name                       = "${var.project_name}-payment-success"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 86400 # 1 day

  tags = {
    Project = var.project_name
    Service = "payment-service"
  }
}

resource "aws_sqs_queue" "payment_failed" {
  name                       = "${var.project_name}-payment-failed"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 86400 # 1 day

  tags = {
    Project = var.project_name
    Service = "payment-service"
  }
}
