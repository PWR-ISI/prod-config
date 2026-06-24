# ── SNS Topic for Alarms ──────────────────────────────────────────────────────
resource "aws_sns_topic" "alarms" {
  name = "${var.project_name}-alarms"

  tags = {
    Project = var.project_name
  }
}

# ── SQS Queue Depth Alarms ────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "sqs_queue_depth" {
  for_each            = module.sqs.queue_arns
  alarm_name          = "${var.project_name}-${each.key}-queue-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Average"
  threshold           = "100"
  alarm_description   = "${each.key}: Queue has >100 pending messages"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    QueueName = "${var.project_name}-${each.key}-queue"
  }
}

# ── SQS DLQ Message Alarms ────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "sqs_dlq_messages" {
  for_each            = module.sqs.dlq_arns
  alarm_name          = "${var.project_name}-${each.key}-dlq-messages"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "${each.key}: Messages in Dead Letter Queue (processing failed)"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    QueueName = "${var.project_name}-${each.key}-dlq"
  }
}

# ── SQS Message Age Alarms ────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "sqs_message_age" {
  for_each            = module.sqs.queue_arns
  alarm_name          = "${var.project_name}-${each.key}-message-age"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "3600"
  alarm_description   = "${each.key}: Messages older than 1 hour (processing delay)"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    QueueName = "${var.project_name}-${each.key}-queue"
  }
}

# ── ECS Running Task Count Alarms ─────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "ecs_running_tasks_auth" {
  alarm_name          = "${var.project_name}-auth-running-tasks"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RunningCount"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "auth-service: Running task count below desired"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    ClusterName = module.auth_service.ecs_cluster
    ServiceName = module.auth_service.ecs_service
  }
}


resource "aws_cloudwatch_metric_alarm" "ecs_running_tasks_payment" {
  alarm_name          = "${var.project_name}-payment-running-tasks"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RunningCount"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "payment-service: Running task count below desired"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    ClusterName = module.payment_service.ecs_cluster
    ServiceName = module.payment_service.ecs_service
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_running_tasks_notification" {
  alarm_name          = "${var.project_name}-notification-running-tasks"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RunningCount"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "notification-service: Running task count below desired"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    ClusterName = module.notification_service.ecs_cluster
    ServiceName = module.notification_service.ecs_service
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_running_tasks_facility" {
  alarm_name          = "${var.project_name}-facility-running-tasks"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RunningCount"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "facility-service: Running task count below desired"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    ClusterName = module.facility_service.ecs_cluster
    ServiceName = module.facility_service.ecs_service
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_running_tasks_medical" {
  alarm_name          = "${var.project_name}-medical-running-tasks"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RunningCount"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "medical-service: Running task count below desired"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    ClusterName = module.medical_service.ecs_cluster
    ServiceName = module.medical_service.ecs_service
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_running_tasks_audit" {
  alarm_name          = "${var.project_name}-audit-running-tasks"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RunningCount"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "audit-service: Running task count below desired"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    ClusterName = module.audit_service.ecs_cluster
    ServiceName = module.audit_service.ecs_service
  }
}

# ── ECS CPU Utilization Alarms ────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  for_each            = local.ecs_clusters
  alarm_name          = "${var.project_name}-${each.key}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "${each.key}-service: CPU > 80%"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    ClusterName = each.value.cluster
    ServiceName = each.value.service
  }
}

# ── ECS Memory Utilization Alarms ─────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  for_each            = local.ecs_clusters
  alarm_name          = "${var.project_name}-${each.key}-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "85"
  alarm_description   = "${each.key}-service: Memory > 85%"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    ClusterName = each.value.cluster
    ServiceName = each.value.service
  }
}

# ── RDS CPU Utilization Alarms ────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  for_each            = local.rds_instances
  alarm_name          = "${var.project_name}-${each.key}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "${each.key} RDS: CPU > 70%"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBInstanceIdentifier = each.value.identifier
  }
}

# ── RDS Storage Space Alarms ──────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  for_each            = local.rds_instances
  alarm_name          = "${var.project_name}-${each.key}-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = 2147483648
  alarm_description   = "${each.key} RDS: Free storage < 2GB"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBInstanceIdentifier = each.value.identifier
  }
}

# ── Notification-service health alarm ─────────────────────────────────────────
# SQS messages failing after maxReceiveCount retries land in the DLQ, which
# signals notification-service processing errors without needing a custom metric.
resource "aws_cloudwatch_metric_alarm" "notification_sqs_dlq" {
  alarm_name          = "${var.project_name}-notification-processing-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "notification-service: messages in DLQ indicate processing failures"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    QueueName = "${var.project_name}-app-events-dlq"
  }
}

# ── CloudWatch Dashboard ───────────────────────────────────────────────────────
locals {
  service_inbox_queues = {
    "schedule-inbox"      = "${var.project_name}-schedule-inbox"
    "appointment-inbox"   = "${var.project_name}-core-inbox"
    "notification-events" = "${var.project_name}-app-events"
    "notification-jobs"   = "${var.project_name}-notification-jobs"
  }
  service_inbox_dlqs = {
    "schedule-inbox"      = "${var.project_name}-schedule-inbox-dlq"
    "appointment-inbox"   = "${var.project_name}-core-inbox-dlq"
    "notification-events" = "${var.project_name}-app-events-dlq"
    "notification-jobs"   = "${var.project_name}-notification-jobs-dlq"
  }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-main"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            for key, qname in local.service_inbox_queues :
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", qname, { label = key }]
          ]
          period = 300
          stat   = "Average"
          region = var.region
          title  = "SQS Event Queues (service inboxes)"
          yAxis  = { left = { min = 0 } }
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            for key, qname in local.service_inbox_dlqs :
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", qname, { label = key }]
          ]
          period = 300
          stat   = "Sum"
          region = var.region
          title  = "SQS Dead Letter Queues"
          yAxis  = { left = { min = 0 } }
        }
      },
      {
        type = "metric"
        properties = {
          metrics = concat(
            [for key, v in local.ecs_clusters :
              ["AWS/ECS", "RunningCount", "ClusterName", v.cluster, "ServiceName", v.service, { label = key }]
            ]
          )
          period = 60
          stat   = "Average"
          region = var.region
          title  = "ECS Running Task Count (per service)"
          yAxis  = { left = { min = 0 } }
        }
      },
      {
        type = "metric"
        properties = {
          metrics = concat(
            [for key, v in local.ecs_clusters :
              ["AWS/ECS", "CPUUtilization", "ClusterName", v.cluster, "ServiceName", v.service, { label = key }]
            ]
          )
          period = 300
          stat   = "Average"
          region = var.region
          title  = "ECS CPU Utilization % (per service)"
          yAxis  = { left = { min = 0, max = 100 } }
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            for key, v in local.rds_instances :
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", v.identifier, { label = key }]
          ]
          period = 300
          stat   = "Average"
          region = var.region
          title  = "RDS CPU Utilization %"
          yAxis  = { left = { min = 0, max = 100 } }
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            for key, v in local.rds_instances :
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", v.identifier, { label = key }]
          ]
          period = 300
          stat   = "Average"
          region = var.region
          title  = "RDS Database Connections"
          yAxis  = { left = { min = 0 } }
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            for name in values(module.schedule_lambda.function_names) :
            ["AWS/Lambda", "Errors", "FunctionName", name, { stat = "Sum", label = name }]
          ]
          period = 60
          region = var.region
          title  = "Lambda Errors (schedule functions)"
          yAxis  = { left = { min = 0 } }
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            for name in values(module.schedule_lambda.function_names) :
            ["AWS/Lambda", "Duration", "FunctionName", name, { stat = "p95", label = name }]
          ]
          period = 300
          region = var.region
          title  = "Lambda Duration p95 ms (schedule functions)"
          yAxis  = { left = { min = 0 } }
        }
      },
    ]
  })
}

# ── Locals for ECS cluster/service and RDS mappings ──────────────────────────
locals {
  ecs_clusters = {
    auth         = { cluster = module.auth_service.ecs_cluster,         service = module.auth_service.ecs_service }
    # schedule moved to Lambda — removed from ECS map
    payment      = { cluster = module.payment_service.ecs_cluster,      service = module.payment_service.ecs_service }
    notification = { cluster = module.notification_service.ecs_cluster, service = module.notification_service.ecs_service }
    facility     = { cluster = module.facility_service.ecs_cluster,     service = module.facility_service.ecs_service }
    medical      = { cluster = module.medical_service.ecs_cluster,      service = module.medical_service.ecs_service }
    audit        = { cluster = module.audit_service.ecs_cluster,        service = module.audit_service.ecs_service }
  }

  rds_instances = {
    auth     = { identifier = "terraform-${var.project_name}-auth-instance" }
    schedule = { identifier = "terraform-${var.project_name}-schedule-instance" }
    payment     = { identifier = "terraform-${var.project_name}-payment-instance" }
    facility    = { identifier = "terraform-${var.project_name}-facility-instance" }
    medical     = { identifier = "terraform-${var.project_name}-medical-instance" }
    audit       = { identifier = "terraform-${var.project_name}-audit-instance" }
  }
}

# ── Notification-service health alarm ─────────────────────────────────────────

# ── Lambda Error Rate Alarms (schedule) ───────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "lambda_errors_schedule" {
  for_each            = module.schedule_lambda.function_names
  alarm_name          = "${var.project_name}-lambda-schedule-${each.key}-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Lambda ${each.key}: at least one execution error"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    FunctionName = each.value
  }
}

# ── Lambda Duration Alarms (schedule) ─────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "lambda_duration_schedule" {
  for_each            = module.schedule_lambda.function_names
  alarm_name          = "${var.project_name}-lambda-schedule-${each.key}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  extended_statistic  = "p95"
  threshold           = 20000
  alarm_description   = "Lambda ${each.key}: p95 duration > 20 s"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    FunctionName = each.value
  }
}

# ── Lambda Throttle Alarms (schedule) ─────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "lambda_throttles_schedule" {
  for_each            = module.schedule_lambda.function_names
  alarm_name          = "${var.project_name}-lambda-schedule-${each.key}-throttles"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Lambda ${each.key}: throttled (concurrency limit hit)"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    FunctionName = each.value
  }
}
