# ── SNS Topic for Alarms ──────────────────────────────────────────────────────
resource "aws_sns_topic" "alarms" {
  provider = aws.localstack
  name     = "${var.project_name}-alarms"

  tags = {
    Project = var.project_name
  }
}

# ── SQS Queue Depth Alarms ────────────────────────────────────────────────────
# Alert when queue has too many messages waiting
resource "aws_cloudwatch_metric_alarm" "sqs_queue_depth" {
  provider            = aws.localstack
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
# Alert when messages appear in Dead Letter Queue
resource "aws_cloudwatch_metric_alarm" "sqs_dlq_messages" {
  provider            = aws.localstack
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
# Alert when messages are too old (not being processed)
resource "aws_cloudwatch_metric_alarm" "sqs_message_age" {
  provider            = aws.localstack
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
# Alert when fewer tasks are running than desired (service degradation)
resource "aws_cloudwatch_metric_alarm" "ecs_running_tasks_auth" {
  provider            = aws.localstack
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

resource "aws_cloudwatch_metric_alarm" "ecs_running_tasks_appointment" {
  provider            = aws.localstack
  alarm_name          = "${var.project_name}-appointment-running-tasks"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RunningCount"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "appointment-service: Running task count below desired"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    ClusterName = module.appointment_service.ecs_cluster
    ServiceName = module.appointment_service.ecs_service
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_running_tasks_schedule" {
  provider            = aws.localstack
  alarm_name          = "${var.project_name}-schedule-running-tasks"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RunningCount"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "schedule-service: Running task count below desired"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    ClusterName = module.schedule_service.ecs_cluster
    ServiceName = module.schedule_service.ecs_service
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_running_tasks_payment" {
  provider            = aws.localstack
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
  provider            = aws.localstack
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
  provider            = aws.localstack
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
  provider            = aws.localstack
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
  provider            = aws.localstack
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
# Alert when task CPU is high
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  provider            = aws.localstack
  for_each            = toset(["auth", "appointment", "schedule", "payment", "notification", "facility", "medical", "audit"])
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
    ClusterName = local.ecs_clusters[each.key].cluster
    ServiceName = local.ecs_clusters[each.key].service
  }
}

# ── ECS Memory Utilization Alarms ─────────────────────────────────────────────
# Alert when task memory is high
resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  provider            = aws.localstack
  for_each            = toset(["auth", "appointment", "schedule", "payment", "notification", "facility", "medical", "audit"])
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
    ClusterName = local.ecs_clusters[each.key].cluster
    ServiceName = local.ecs_clusters[each.key].service
  }
}

# ── RDS CPU Utilization Alarms ────────────────────────────────────────────────
# Alert when database CPU is high
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  provider            = aws.localstack
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
# Alert when database storage is running low
resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  provider            = aws.localstack
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

# ── CloudWatch Dashboard ───────────────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "main" {
  provider       = aws.localstack
  dashboard_name = "${var.project_name}-main"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            for key, arn in module.sqs.queue_arns :
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", { label = key }]
          ]
          period = 300
          stat   = "Average"
          region = var.region
          title  = "SQS Queue Depths"
          yAxis  = { left = { min = 0 } }
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            for key, arn in module.sqs.dlq_arns :
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", { label = "${key} DLQ" }]
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
          metrics = [
            ["AWS/ECS", "RunningCount", { label = "Running Tasks" }],
            [".", "CPUUtilization", { label = "CPU Avg" }],
            [".", "MemoryUtilization", { label = "Memory Avg" }],
          ]
          period = 300
          stat   = "Average"
          region = var.region
          title  = "ECS Services Overview"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", { label = "RDS CPU" }],
            [".", "DatabaseConnections", { label = "Connections" }],
            [".", "FreeStorageSpace", { label = "Free Storage" }],
          ]
          period = 300
          stat   = "Average"
          region = var.region
          title  = "RDS Databases Overview"
        }
      },
    ]
  })
}

# ── Locals for ECS cluster/service mappings ────────────────────────────────────
locals {
  ecs_clusters = {
    auth        = { cluster = module.auth_service.ecs_cluster, service = module.auth_service.ecs_service }
    appointment = { cluster = module.appointment_service.ecs_cluster, service = module.appointment_service.ecs_service }
    schedule    = { cluster = module.schedule_service.ecs_cluster, service = module.schedule_service.ecs_service }
    payment     = { cluster = module.payment_service.ecs_cluster, service = module.payment_service.ecs_service }
    notification = { cluster = module.notification_service.ecs_cluster, service = module.notification_service.ecs_service }
    facility    = { cluster = module.facility_service.ecs_cluster, service = module.facility_service.ecs_service }
    medical     = { cluster = module.medical_service.ecs_cluster, service = module.medical_service.ecs_service }
    audit       = { cluster = module.audit_service.ecs_cluster, service = module.audit_service.ecs_service }
  }

  rds_instances = {
    auth        = { identifier = "terraform-${var.project_name}-auth-instance" }
    appointment = { identifier = "terraform-${var.project_name}-core-instance" }
    schedule    = { identifier = "terraform-${var.project_name}-schedule-instance" }
    payment     = { identifier = "terraform-${var.project_name}-payment-instance" }
    facility    = { identifier = "terraform-${var.project_name}-facility-instance" }
    medical     = { identifier = "terraform-${var.project_name}-medical-instance" }
    audit       = { identifier = "terraform-${var.project_name}-audit-instance" }
  }
}
