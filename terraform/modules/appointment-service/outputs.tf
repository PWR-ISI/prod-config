output "alb_dns" {
  value = aws_lb.alb.dns_name
}

output "db_endpoint" {
  value = aws_db_instance.core.address
}

output "sns_topic_arn" {
  value = aws_sns_topic.appointment_events.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.appointment_inbox.url
}

output "sqs_queue_arn" {
  value = aws_sqs_queue.appointment_inbox.arn
}

output "ecr_repository_url" {
  value = aws_ecr_repository.core.repository_url
}

output "ecs_cluster" {
  value = aws_ecs_cluster.cluster.name
}

output "ecs_service" {
  value = aws_ecs_service.service.name
}
