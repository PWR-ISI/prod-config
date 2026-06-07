# CloudWatch monitoring, logging, and alarms for all services.

# CloudWatch Log Groups for ECS Services

resource "aws_cloudwatch_log_group" "schedule_service" {
  name              = "/ecs/schedule-service"
  retention_in_days = 14

  tags = {
    Service = "schedule-service"
    Project = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "file_upload_service" {
  name              = "/ecs/file-upload-service"
  retention_in_days = 14

  tags = {
    Service = "file-upload-service"
    Project = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.project_name}-api"
  retention_in_days = 7

  tags = {
    Service = "api-gateway"
    Project = var.project_name
  }
}

# CloudWatch Alarms for Schedule Service

resource "aws_cloudwatch_metric_alarm" "schedule_service_cpu_high" {
  alarm_name          = "${var.project_name}-schedule-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Alert when schedule service CPU exceeds 80%"
  alarm_actions       = [var.sns_topic_arn]

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = "schedule-service"
  }
}

resource "aws_cloudwatch_metric_alarm" "schedule_service_memory_high" {
  alarm_name          = "${var.project_name}-schedule-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "85"
  alarm_description   = "Alert when schedule service memory exceeds 85%"
  alarm_actions       = [var.sns_topic_arn]

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = "schedule-service"
  }
}

resource "aws_cloudwatch_metric_alarm" "schedule_service_errors" {
  alarm_name          = "${var.project_name}-schedule-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "4XXError"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "Alert on 4xx errors in schedule service"
  alarm_actions       = [var.sns_topic_arn]

  dimensions = {
    TargetGroup = var.schedule_service_target_group
  }
}

# CloudWatch Alarms for File Upload Service

resource "aws_cloudwatch_metric_alarm" "file_upload_service_cpu_high" {
  alarm_name          = "${var.project_name}-file-upload-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Alert when file upload service CPU exceeds 80%"
  alarm_actions       = [var.sns_topic_arn]

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = "file-upload-service"
  }
}

# CloudWatch Log Insights Queries (for reference)

resource "aws_cloudwatch_query_definition" "api_errors" {
  name = "${var.project_name}-api-errors"

  log_group_names = [
    aws_cloudwatch_log_group.schedule_service.name,
    aws_cloudwatch_log_group.file_upload_service.name,
  ]

  query_string = <<-EOQ
    fields @timestamp, @message, @logStream, level
    | filter level like /ERROR|EXCEPTION/
    | stats count() by @logStream
  EOQ
}

resource "aws_cloudwatch_query_definition" "slow_requests" {
  name = "${var.project_name}-slow-requests"

  log_group_names = [
    aws_cloudwatch_log_group.schedule_service.name,
    aws_cloudwatch_log_group.file_upload_service.name,
  ]

  query_string = <<-EOQ
    fields @timestamp, @message, duration_ms
    | filter duration_ms > 1000
    | stats avg(duration_ms) as avg_duration, pct(duration_ms, 99) as p99_duration by @logStream
  EOQ
}

# CloudWatch Dashboard

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-monitoring"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", { stat = "Average" }],
            [".", "MemoryUtilization", { stat = "Average" }],
          ]
          period = 300
          stat   = "Average"
          region = var.region
          title  = "ECS Services Health"
        }
      },
      {
        type = "log"
        properties = {
          query   = "SOURCE '/ecs/schedule-service' | stats count() by level"
          region  = var.region
          title   = "Schedule Service Logs"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", { stat = "Sum" }],
            [".", "HTTPCode_Target_5XX_Count", { stat = "Sum" }],
          ]
          period = 60
          stat   = "Sum"
          region = var.region
          title  = "API Gateway Errors"
        }
      },
    ]
  })
}
