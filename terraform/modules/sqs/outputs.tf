output "queue_urls" {
  description = "Map of service name -> SQS queue URL"
  value       = { for k, q in aws_sqs_queue.service : k => q.url }
}

output "queue_arns" {
  description = "Map of service name -> SQS queue ARN"
  value       = { for k, q in aws_sqs_queue.service : k => q.arn }
}

output "dlq_arns" {
  description = "Map of service name -> dead-letter queue ARN"
  value       = { for k, q in aws_sqs_queue.service_dlq : k => q.arn }
}
