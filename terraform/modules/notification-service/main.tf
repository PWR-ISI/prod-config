terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

variable "project_name" { type = string }
variable "region" { type = string }

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
      Principal = "*"
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.notification_jobs.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.notifications.arn } }
    }]
  })
}

resource "aws_sns_topic_subscription" "notification_jobs" {
  topic_arn = aws_sns_topic.notifications.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.notification_jobs.arn
}

output "sns_topic_arn" { value = aws_sns_topic.notifications.arn }
output "sqs_app_events_url" { value = aws_sqs_queue.app_events.url }
output "sqs_notification_jobs_url" { value = aws_sqs_queue.notification_jobs.url }
output "dynamodb_table_name" { value = aws_dynamodb_table.notifications.name }
