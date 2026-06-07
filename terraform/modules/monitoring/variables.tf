variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications"
  type        = string
}

variable "schedule_service_target_group" {
  description = "Target group name for schedule service ALB"
  type        = string
}
